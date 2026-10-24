---
name: nested-x11-authentication
description: >-
  Work on Xsunaba's X11 credential handling: parent Xauthority filtering,
  fresh MIT-MAGIC-COOKIE-1 generation, display allocation, authority-file
  ownership, and nested-socket permissions. Use for Xephyr argv, Xauthority
  parsing/writing, cookie length, display selection, or socket races.
---

# Nested X11 authentication

## When to use

Use this skill when a task touches:

- `read_xauth_file`, `parse_xauth_bytes`, `extract_parent_auth`,
  `xauth_records_for`, `write_xauth_file`, `gen_cookie`.
- `build_xephyr_argv`, `find_free_display`, `socket_path`,
  `_wait_for_socket`, `_restrict_socket`, `_cleanup_stale_display`.
- Xephyr flags, `-auth`, `-nolisten tcp`, `-noreset`, `-ac`, `xhost`.
- authority-file paths/modes, socket 0660, or the doas rule's `setenv`.

## Model to preserve

- Parent credentials: read the invoking user's Xauthority, keep only
  `MIT-MAGIC-COOKIE-1` records whose display number matches the parent
  display, require 16-byte cookie data, and write them to a mode-0600
  file readable only by `_xsunaba_xephyr`.
- Nested credentials: generate 16 random bytes from `/dev/urandom`, encode
  as 32 lowercase hex characters, then write two authority records
  (`FamilyLocal` with hostname and `FamilyWild`) containing the raw
  16-byte cookie. Server and client get separate files.
- Xephyr argv is fixed:
  `-auth <server-auth> -screen WxH -br -nolisten tcp -noreset
  -resizeable -no-host-grab :N`.
  No `-ac`, no `xhost`, no remote TCP listen.
- Display allocation scans from the requested start to 999, skips an
  existing `/tmp/.X11-unix/X<n>`, and is serialized by
  `/var/run/xsunaba/display.lock`.
- The nested socket must end up mode 0660, owned by the Xephyr UID and the
  application's socket group. Tighten it without a path-based
  `chown`/`chmod` race: move it to a root-owned staging directory inside
  `.X11-unix`, change it there, move it back, and re-verify.
- Authority files are created while their parent directory is still
  root-owned, chowned, then the directory is handed to the sandbox UID.

## Procedure

1. Read `AGENTS.md`, then the xauth and socket helpers in
   `libexec/xsunaba-helper`. Confirm the wire format against
   `xauth_record_bytes` and `parse_xauth_bytes`.
2. Trace one nested session:
   - parse parent display and parent Xauth path;
   - read/parse the parent file;
   - filter records by display and `MIT-MAGIC-COOKIE-1`;
   - generate the cookie;
   - write parent/server/client authority files;
   - chown files, then chown directories;
   - fork Xephyr;
   - wait for the socket, stage it, chown/chmod, move back, verify;
   - fork the application with `DISPLAY=:N` and its own `XAUTHORITY`.
3. Check every failure path: missing/oversized/unparseable parent file,
   no matching cookie, short cookie, Xephyr exit before socket, wrong
   socket type/owner, chown/chmod failure, staging rename failure.
4. Check that no cookie appears in argv, environment, logs, or a
   predictable path. `t/80-log.t` enforces the source-level rule.
5. If you change Xephyr flags, update `t/11-xephyr-argv.t`,
   `t/90-static.t`, `README.md`, and `man/Xsunaba.1` together.

## Validation

```sh
prove -I t/lib -v t/11-xephyr-argv.t t/20-xauth.t t/30-cookie.t t/40-display.t
prove -I t/lib -v t/50-unveil.t t/60-env.t t/80-log.t t/90-static.t
```

These tests exercise pure builders and parsers, temp files, and fake
sockets. They do **not** start Xephyr or talk to a real X server, and they
do not prove the runtime socket race is closed. A real OpenBSD run is a
separate, explicit check.

## Common problems

- Confusing the hex cookie with the raw cookie. The file stores raw bytes;
  the internal representation is 32 hex characters.
- Filtering parent records by name but not by display number, or copying
  the whole authority database.
- Using `-ac` or `xhost`; both undermine cookie authentication and are
  forbidden by static tests.
- Path-based `chown`/`chmod` on a socket in a directory writable by the
  Xephyr UID. Use the staging approach.
- Forgetting `-noreset`: a reset can recreate the socket with looser
  permissions.
- Assuming hostname matching is optional. The `FamilyLocal` address must
  match `gethostname(3)` as Xlib computes it; only NUL/overlong values are
  rejected.
- Freeing a stale display while its Xephyr may still be alive. Only
  release it after the recorded PID is gone.

## References

- `libexec/xsunaba-helper`: xauth helpers, `build_xephyr_argv`,
  `find_free_display`, `_wait_for_socket`, `_restrict_socket`,
  `_cleanup_stale_display`.
- `README.md`: Restricting the filesystem with unveil, Runtime files,
  Architecture.
- `man/Xsunaba.1`: DESCRIPTION, ENVIRONMENT, FILES.
- `t/11-xephyr-argv.t`, `t/20-xauth.t`, `t/30-cookie.t`, `t/40-display.t`,
  `t/50-unveil.t`, `t/80-log.t`, `t/90-static.t`.
