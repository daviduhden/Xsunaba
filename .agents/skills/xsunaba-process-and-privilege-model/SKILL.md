---
name: xsunaba-process-and-privilege-model
description: >-
  Analyze or change Xsunaba's frontend/helper process tree, doas boundary,
  UID/GID transitions, supervisor pledge, PID lifetime, and lock handling.
  Use for bin/Xsunaba.pl, libexec/xsunaba-helper, privilege drops, process
  cleanup, or any claim about what confines the application.
---

# Xsunaba process and privilege model

## When to use

Use this skill when a task touches:

- `bin/Xsunaba.pl`: `launch`, `build_helper_argv`, `resolve_app`, doas exec.
- `libexec/xsunaba-helper`: `run`, `drop_privs`, fork points, `$fatal`,
  `_stop_child`, `_stop_xephyr`, `_wait_for_socket`, `_child_alive`.
- doas configuration, `DOAS_USER`, setuid/setgid, supplementary groups.
- pledge scope or claims that the application is "pledged"/"contained".
- cleanup ordering, PID reuse, `flock` lifetime, or signals.

## Model to preserve

```
frontend (login UID, unpledged)
  -> doas (root)
    -> helper (root supervisor)
       -> Xephyr child: drop to _xsunaba_xephyr, exec Xephyr
       -> app child:    drop to app UID/GID, optional unveil, exec app
```

- The helper is the trusted computing base. It starts as root, validates
  arguments, creates session state, forks both children, and keeps root
  for cleanup.
- `drop_privs` runs in each child immediately before `exec`. It resets
  effective gid plus supplementary groups with `$)`, sets real gid with
  `$(`, calls `setgid` then `setuid`, verifies all four IDs and the single
  supplementary group, then proves `setuid(0)` fails.
- The persistent supervisor pledges after both forks:
  `stdio rpath cpath fattr proc getpw`. Amnesiac mode stays unpledged
  because teardown execs account-management helpers.
- The frontend stays unpledged because it must execute doas.
  `OpenBSD::Pledge` has no `execpromises` binding, so never add `exec` to
  the frontend promises and never accept a non-empty `XSUNABA_PLEDGE`.
- `unveil` rules are applied in the app child before `exec`, then cleared
  by `execve`. They do not restrict the running application.

## Procedure

1. Read `AGENTS.md` and the current `bin/Xsunaba.pl` plus the helper
   functions named above. Do not rely on line numbers from old reports.
2. Draw the process tree and annotate, for each process: real/effective
   UID/GID, supplementary groups, environment, cwd, open lock fds, and
   whether it is pledged.
3. Verify the doas boundary:
   - helper requires `getuid() == 0 && geteuid() == 0`;
   - `DOAS_USER` is required and resolved with `getpwnam`;
   - the parent Xauthority is owned by that user;
   - the documented rule grants only the helper, as root, with no `args`
     prefix trick and no `DOAS_USER` in `setenv`.
4. Verify account checks: nonzero UIDs/GIDs, distinct app/Xephyr UIDs,
   login user not sharing a sandbox UID and not in `_xsunaba`, persistent
   home directory owned by `_xsunaba_app`.
5. Verify lock handling: the parent holds `display.lock` until the socket
   is restricted; every forked child closes inherited lock fds; amnesiac
   `active.lock` is held by the helper and closed only after teardown.
6. Verify PID handling: `_child_alive` (or an equivalent) must run before
   signaling; PIDs must be cleared or made undef after `waitpid` reaps
   them. Never send `TERM`/`KILL` to a PID that may have been recycled.
7. Verify cleanup: `$fatal` kills only live children, unlinks the socket
   only when owned by the Xephyr UID, and removes session state; normal
   exit stops the app/Xephyr and propagates the application status.
8. If you change behavior, update `README.md` and `man/Xsunaba.1` and add
   or adjust a non-privileged test in `t/`.

## Validation

Static and portable checks only, unless the task explicitly authorizes a
real OpenBSD run:

```sh
perl -T -c libexec/xsunaba-helper
perl -c bin/Xsunaba.pl
prove -I t/lib -v t/10-args.t t/11-xephyr-argv.t t/40-display.t t/70-frontend.t
prove -I t/lib -v t/90-static.t
```

`t/90-static.t` is a text check, not a proof of runtime behavior. It
expects the verified transition patterns, `close $lock`, and
`close $am->{lock_fh}` in the source.

## Common problems

- Pledging the helper before the children exist, or adding `exec` to the
  frontend promises. Both break the documented model.
- Killing a PID after it was reaped; a later signal can hit an unrelated
  process. Use `_child_alive` and clear the PID.
- Forgetting that `flock` locks survive `fork`; children must close the
  lock descriptors.
- Assuming `unveil` protects the running app. It is cleared on `execve`.
- Treating the frontend as trusted by the helper. The helper re-validates
  every value.
- Claiming per-session isolation in persistent mode; `_xsunaba_app` is
  shared across sessions.

## References

- `AGENTS.md`
- `bin/Xsunaba.pl`: `launch`, `build_helper_argv`, `resolve_app`.
- `libexec/xsunaba-helper`: `drop_privs`, `run`, `_fatal` closure,
  `_stop_child`, `_stop_xephyr`, `_wait_for_socket`, `_child_alive`.
- `man/Xsunaba.1` (DESCRIPTION, PRIVILEGED HELPER, CAVEATS)
- `README.md` (Architecture, Security considerations)
- `t/70-frontend.t`, `t/90-static.t`
