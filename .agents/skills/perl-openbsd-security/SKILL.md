---
name: perl-openbsd-security
description: >-
  Apply OpenBSD-specific Perl security practices in Xsunaba: taint mode,
  doas environment, pledge/unveil limits, privilege drops, safe exec, and
  race-resistant file operations. Use for helper code, syscalls, or any
  privileged Perl change.
---

# Perl on OpenBSD: security practices

## When to use

Use this skill when a task touches:

- `libexec/xsunaba-helper` or `bin/Xsunaba.pl` and any privileged path.
- `setuid`/`setgid`/`$)`/`$(`, supplementary groups, saved credentials.
- `pledge`, `unveil`, `OpenBSD::Pledge`, `OpenBSD::Unveil`, doas.
- `sysopen`, `open`, `chown`, `chmod`, `rename`, `unlink`, `flock`,
  `remove_tree`, `waitpid`, `kill`, `exec`.
- Taint-mode failures, `-T`, `DOAS_USER`, environment whitelists.

## Rules that matter here

- The helper is `#!/usr/bin/perl -T`. Data from `@ARGV`, `%ENV`,
  `readdir`, and file reads must be captured with an anchored regex before
  it is used as a path or exec argument. Existing examples:
  `_untaint`, `stale_session_tokens`, account/display/pid captures.
- Use list-form exec or indirect-object exec:
  `exec @argv` / `exec { $app } $app, @args`. Never use `system`,
  backticks, `qx`, or a shell.
- Drop privileges in the child, in this order: reset effective gid and
  supplementary groups with `$)`, set real gid with `$(`, `setgid`, then
  `setuid`; verify real/effective/saved IDs and the exact supplementary
  group set; prove `setuid(0)` fails.
- `flock` locks are shared across `fork`. Children must close inherited
  lock descriptors.
- Check every security-sensitive syscall and fail closed. `write_xauth_file`
  uses `O_CREAT | O_EXCL` and mode 0600.
- Avoid path-based privilege operations on paths a less-privileged UID can
  replace. Create authority files while the parent is root-owned; stage the
  socket in a root-owned directory for chown/chmod; never follow a symlink
  with root privileges.
- `OpenBSD::Pledge` has no `execpromises` binding. Do not claim a promise
  restricts an executed program. The frontend stays unpledged to execute
  doas; the persistent supervisor pledges only after forking.
- `unveil` is cleared on `execve`; it restricts pre-exec setup, not the
  running app. Do not add it to the runtime isolation claim.
- Trust `DOAS_USER` only because the documented doas rule does not put it in
  `setenv`. Never add it there.
- Keep `local %ENV` scoping and the `TERM TZ LANG LC_ALL LC_CTYPE
  LC_MESSAGES` whitelist. Rebuild `PATH`, `HOME`, `USER`, `LOGNAME`,
  `SHELL`, `DISPLAY`, `XAUTHORITY`, and `XDG_RUNTIME_DIR` explicitly.

## Procedure

1. Read `AGENTS.md`, the function you will change, and the nearest tests.
2. Identify the trust boundary: login user, doas root, helper root, Xephyr
   UID, app UID. State which process executes each new operation.
3. For each input, decide whether it is tainted and capture it before use.
4. For each filesystem path, decide whether a less-privileged UID can
   replace any component. If yes, use a root-owned directory, `O_EXCL`,
   `lstat` plus post-checks, or the socket staging pattern.
5. For each child, close inherited descriptors and verify the privilege
   transition before exec.
6. For each cleanup path, decide what happens on partial failure and
   whether a later invocation can retry.
7. Update docs and tests. Run only non-privileged checks unless explicitly
   authorized.

## Validation

```sh
perl -T -c libexec/xsunaba-helper
perl -c bin/Xsunaba.pl
prove -I t/lib -v t/10-args.t t/12-amnesiac.t t/20-xauth.t t/70-frontend.t
prove -I t/lib -v t/90-static.t
```

`perl -T -c` is a compile/taint check, not execution. `t/90-static.t` is a
source-text check; it cannot prove a syscall is race-free.

## Common problems

- Assuming `-T` only affects `@ARGV`; `readdir`/file data also needs
  capture.
- Using `open` where `sysopen` with `O_EXCL`/`O_NOFOLLOW` semantics are
  required.
- Writing a root-owned file into a directory owned by the target UID and
  then chowning the path. Create it while the directory is root-owned.
- Chowning/chmodding a socket path that the Xephyr UID can replace. Stage
  it in a root-owned directory.
- Forgetting `$) = "$gid $gid"` or verifying only `getuid`.
- Pledging before forking, or adding an `exec` promise that cannot work.
- Treating `remove_tree` as infallible; check whether the path is gone.
- Signaling a reaped PID; use `_child_alive` and clear the PID.

## References

- `AGENTS.md`
- `libexec/xsunaba-helper`: `_untaint`, `drop_privs`, `_run_cmd`,
  `_write_auth_file`, `_restrict_socket`, `_child_alive`, `_remove_tree`.
- `bin/Xsunaba.pl`: `pledge`, `unveil`, `launch`.
- `t/00-compile.t`, `t/10-args.t`, `t/12-amnesiac.t`, `t/90-static.t`.
- `perlsec(1)`, `pledge(2)`, `unveil(2)`, `doas(1)`, `doas.conf(5)`.

## Maintenance & Continuous Learning

When this skill is used for a repository change, review it after completing the implementation. Update it when taint handling, privilege transitions, pledge/unveil behavior, tools, paths, tests, or security assumptions change, and add reusable findings that improve future work. Correct guidance shown to be wrong, keep examples and validation commands current, and remove stale or contradictory details. Do not add one-run task notes. Also inspect the root and any nearer `AGENTS.md` plus related skills, and perform the repository's required synchronization check before reporting completion.
