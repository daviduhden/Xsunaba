# AGENTS.md

## What this repository is

Xsunaba runs X11 applications on OpenBSD inside a nested Xephyr display
under dedicated Unix accounts. The security boundary is Unix account
separation, X11 MIT-MAGIC-COOKIE-1 authentication, and nested-socket
permissions. `unveil(2)` is a pre-exec restriction only; it is cleared by
`execve` and is **not** runtime containment. `pledge(2)` protects the
persistent-mode supervisor after its children exist, not the application.

## Architecture

```
bin/Xsunaba.pl                 frontend, runs as the login user
  -> /usr/bin/doas            documented narrow rule
  -> /usr/local/libexec/xsunaba-helper   root supervisor
       -> Xephyr              as _xsunaba_xephyr
       -> application         as _xsunaba_app (persistent)
                              or _xsunaba_<16 hex> (amnesiac)
```

- Persistent mode reuses `_xsunaba_app`, group `_xsunaba`, and
  `/home/_xsunaba_app`. Sessions are **not** mutually isolated.
- Amnesiac mode creates a per-session account, private group, and home
  under `/var/xsunaba/home`, then removes them on successful teardown.
  The numeric UID may be reused by the OS after deletion.
- Xephyr always runs as the shared `_xsunaba_xephyr` account.
- The helper creates a fresh 128-bit cookie, writes separate mode-0600
  authority files for Xephyr and the application, and tightens the nested
  socket to 0660. It stages the socket in a root-owned directory while
  chown/chmod run, to avoid a symlink race.
- Persistent sessions keep the supervisor pledge
  `stdio rpath cpath fattr proc getpw`. Amnesiac mode stays unpledged
  because teardown execs `useradd`/`userdel`/`groupdel`/`pkill`.
- The frontend deliberately stays unpledged: it must `exec` doas, and
  `OpenBSD::Pledge` has no `execpromises` binding. Never add `exec` to its
  promises or accept `XSUNABA_PLEDGE`.

## Key files

| Path | Role |
|---|---|
| `bin/Xsunaba.pl` | CLI parsing, validation, helper argv, doas exec |
| `libexec/xsunaba-helper` | Root session orchestration and cleanup |
| `man/Xsunaba.1` | mdoc manual; keep in sync with `README.md` |
| `README.md` | User-facing behavior, limits, caveats |
| `t/*.t` | Portable regression tests; no root/Xephyr/doas required |
| `t/lib/TestHelper.pm` | `run_capture`, `dies_ok`, `lives_ok` |
| `tools/popup-grab-test.c` | Optional X11 input regression tool |
| `Makefile` | Install/accounts/doas-rule/test/tools targets |
| `.github/workflows/ci.yml` | Linux + OpenBSD 8.0 checks |

## Commands that actually exist

```sh
make test                         # prove -I t/lib -v t/
prove -I t/lib t/                 # CI form
prove -I t/lib -v t/20-xauth.t    # single test
perl -T -c libexec/xsunaba-helper # CI syntax check (taint mode)
perl -c bin/Xsunaba.pl            # CI syntax check
make -s show-doas-rule            # print, never edit, /etc/doas.conf
make tools                        # build tools/popup-grab-test
make help                         # list targets
make build                        # no-op: pure Perl
```

`t/95-x11-optional.t` is opt-in and needs a built tool, a display, and
`xdotool`:

```sh
make tools
XSUNABA_TEST_DISPLAY=:32 prove -I t/lib t/95-x11-optional.t
```

It injects pointer input and writes `tools/popup-grab-test.log`; do not
run it unless the task explicitly requires real X11 input testing.

## Conventions

- Perl: `use strict; use warnings;`; helper keeps `-T` (taint mode).
  Use 4-space indentation, ASCII output, and no ANSI/emoji.
- Logging: `[INFO]` via `logi` to stdout when verbose, `[WARN]`/`[ERROR]`
  to stderr. `die_tool` is for fatal CLI/startup paths; validators `die`
  so callers and tests can catch the message.
- Never use a shell. Use list-form `exec`, `_run_cmd`, `IPC::Open3`, or
  indirect-object `exec { $app } $app, @args`. `system`, backticks, and
  `qx` are forbidden by `t/90-static.t`.
- Verify security-sensitive syscalls (`sysopen`, `chown`, `chmod`,
  `flock`, `setgid`, `setuid`, `close`) and fail closed.
- Forked children must close inherited lock descriptors; `flock` locks
  survive `fork`.
- Never signal a PID after it has been reaped. Clear PIDs or use
  `_child_alive` before `kill`/`waitpid`.
- Tests load scripts by path, not as modules:
  `require "$FindBin::Bin/../libexec/xsunaba-helper"`. Use
  `local $Xsunaba::Helper::RUN_DIR` and temp dirs; never touch
  `/var/run/xsunaba`.
- Documentation changes must update both `README.md` and
  `man/Xsunaba.1`. `t/90-static.t` checks both for account names,
  the doas rule, `--amnesiac`, `-resizeable`, `-no-host-grab`, and the
  exact phrase "Crossing the Unix-user isolation boundary".
- There is no `.perlcriticrc`, release tag, changelog, or packaging
  manifest. Keep severity-5-style cleanliness; annotate justified
  exceptions with `## no critic (Policy::Name)` and a reason.

## Security and testing policy

- Do **not** run `make install`, `make install-users`, `make uninstall`,
  `doas`, the helper, Xephyr, or any command that creates, deletes, or
  modifies real users/groups. Do not edit `/etc/doas.conf`.
- Do not run destructive tests. Prefer static reading, pure functions,
  temporary directories, and mocks already present in `t/`.
- Do not add `DOAS_USER` to the doas `setenv` list; that would let the
  caller spoof the parent-Xauthority ownership check.
- Do not claim `unveil` isolates the running application. Do not claim
  persistent sessions are mutually isolated, and do not promise that an
  amnesiac UID is never reused.
- Treat a compromised Xephyr as inside the threat model: it runs as its
  own UID and must not be able to make root follow a symlink or signal an
  unrelated process.
- Before changing behavior, distinguish static analysis, build, unit
  tests, and real OpenBSD runtime checks. The suite does not exercise
  `run()`, `drop_privs()`, Xephyr, pledge/unveil, or real account
  creation.

## Pre-existing changes

Run `git status --short` before editing. Preserve unrelated modified or
untracked files; do not revert, checkout, stash, commit, or push unless
the task explicitly asks. Keep edits scoped and review `git diff` plus
`git diff --check`.

## Skills

Load only the skill that matches the task:

- [xsunaba-process-and-privilege-model](.agents/skills/xsunaba-process-and-privilege-model/SKILL.md) — process tree, UID/GID drops, supervisor pledge, PID/lock lifetime.
- [nested-x11-authentication](.agents/skills/nested-x11-authentication/SKILL.md) — Xauthority records, cookies, display allocation, socket permissions.
- [session-account-lifecycle](.agents/skills/session-account-lifecycle/SKILL.md) — persistent/amnesiac accounts, homes, teardown, stale-session reaping.
- [perl-openbsd-security](.agents/skills/perl-openbsd-security/SKILL.md) — taint mode, pledge/unveil/doas, privileged Perl changes.
- [sandbox-regression-and-docs](.agents/skills/sandbox-regression-and-docs/SKILL.md) — tests, static checks, CI, README/man synchronization.

## License

MIT. Copyright (c) 2013 Milosz Galazka, (c) 2020 Morgan Aldridge,
(c) 2025-2026 David Uhden Collado. See `LICENSE`.
