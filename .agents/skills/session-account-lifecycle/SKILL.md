---
name: session-account-lifecycle
description: >-
  Work on Xsunaba's persistent and amnesiac session lifecycle: account and
  group creation, homes, teardown, process proof, stale-session reaping,
  and display release. Use for useradd/userdel/groupdel/pkill changes,
  /var/xsunaba layout, or cleanup bugs.
---

# Session account lifecycle

## When to use

Use this skill when a task touches:

- `_amnesiac_create`, `_amnesiac_teardown`, `reap_stale_sessions`,
  `home_safe_to_delete`, `_delete_ephemeral_group`.
- `build_useradd_argv`, `build_userdel_argv`, `build_groupdel_argv`,
  `build_pkill_argv`.
- `make_session_dir`, `_ensure_run_dir`, `_ensure_ephemeral_bases`.
- persistent vs amnesiac behavior, `/var/run/xsunaba` or
  `/var/xsunaba/home` layout, account/group cleanup.

## Model to preserve

- Persistent mode: fixed `_xsunaba_app`, group `_xsunaba`, shared
  `/home/_xsunaba_app`; sessions are not mutually isolated.
- Amnesiac mode: fresh `_xsunaba_<16 hex>` account, private primary group,
  locked password (`useradd -p '*'`), `/sbin/nologin`, home
  `/var/xsunaba/home/<account>` mode 0700.
- Account creation is recorded in the session's `account` file before
  `useradd`, so a crash after `useradd` is still recoverable. On a failed
  attempt the file is unlinked before the next token.
- Teardown order: kill every process under the ephemeral UID; prove none
  remain with `pkill -0`; remove the verified home; `userdel`; delete the
  private group; remove the session directory last.
- If a process may remain, or home/account/group deletion fails, keep the
  session directory and leave the account and/or group for the next
  amnesiac invocation. Never delete an account while its UID may still be
  in use.
- The reaper only considers 32-hex session directories with
  `active.lock`; it takes a non-blocking exclusive flock and skips live
  sessions. It verifies the account file, account pattern, home path, and
  home ownership. It releases a recorded display only when the recorded
  Xephyr PID is gone.
- Persistent sessions are not reaped by the amnesiac reaper. Do not
  change that without a safe way to identify persistent processes.

## Procedure

1. Read `AGENTS.md` and the lifecycle helpers in
   `libexec/xsunaba-helper`.
2. Trace creation: `_ensure_ephemeral_bases` (root-owned 0711,
   not group/world writable), random token, account file pre-write,
   `useradd`, passwd re-resolution, checks (uid/gid nonzero, UID distinct
   from Xephyr, exact home), home `mkdir 0700` and `chown`.
3. Trace teardown: process kill proof, home safety, `userdel`, group
   deletion, session removal, lock close. Confirm the session directory is
   removed only after account/group success.
4. Trace the reaper: readdir token filter, `active.lock` flock, account
   file capture, passwd lookup, `pkill`, home handling, `userdel`,
   group cleanup, display/pid metadata, session removal/retry.
5. Check that every path used in `userdel`/`groupdel`/`pkill` is derived
   from a validated account name, never from caller input.
6. Update `README.md` and `man/Xsunaba.1` for any lifecycle or guarantee
   change. Do not promise "nothing persists" or a never-reused UID.

## Validation

```sh
prove -I t/lib -v t/12-amnesiac.t t/13-umask.t t/40-display.t
prove -I t/lib -v t/15-makefile.t t/70-frontend.t t/90-static.t
```

`t/12-amnesiac.t` exercises command builders, `home_safe_to_delete` with
injected `lstat`, parameter bounds, and the real reaper against a
synthetic session under a temporary `RUN_DIR`. It does not create a real
account. Never "validate" by creating or deleting users, and never run
`make install-users`.

## Common problems

- Removing the session directory before `userdel`/`groupdel`; the reaper
  then loses its only record and cannot retry.
- Releasing `active.lock` before teardown finishes; a concurrent reaper
  can race the same account.
- Deleting the home while a process may still run, or deleting the
  account after `pkill -0` says processes may remain.
- Treating `pkill` exit 0 as "gone". Only exit 1 means no match; 0 or an
  execution error means "may still run".
- Group name and gid mismatch, or a group with members. Do not delete it.
- Relying on the platform default password state; pass `-p '*'`
  explicitly.
- Promising a fresh numeric UID. Only the account name is fresh.
- Assuming files outside the ephemeral home are cleaned up; they are not.

## References

- `libexec/xsunaba-helper`: lifecycle helpers named above.
- `Makefile`: `install-users`, `show-doas-rule`, `uninstall`.
- `README.md`: Amnesiac mode, Runtime files, Security considerations,
  OpenBSD validation checklist.
- `man/Xsunaba.1`: AMNESIAC MODE, FILES, CAVEATS.
- `t/12-amnesiac.t`, `t/13-umask.t`, `t/40-display.t`, `t/90-static.t`.
