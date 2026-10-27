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

## Commands that actually exist

```sh
make test                         # prove -I t/lib -v t/
prove -I t/lib t/                 # all tests, non-verbose
prove -I t/lib -v t/20-xauth.t    # single test
perl -T -c libexec/xsunaba-helper # syntax check (taint mode)
perl -c bin/Xsunaba.pl            # syntax check
perl tools/check-agent-maintenance.pl --worktree # local knowledge sync check
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
- [sandbox-regression-and-docs](.agents/skills/sandbox-regression-and-docs/SKILL.md) — tests, static checks, README/man synchronization.

## Continuous Agent & Skills Maintenance

Agent instructions and skills are living repository artifacts.

Every repository modification MUST include an agent/skills synchronization step.

Before completing any task, inspect the applicable AGENTS.md and SKILL.md files, update the affected instructions, and validate their consistency with the implementation.

A code change without the corresponding agent knowledge maintenance is considered incomplete.

Never claim completion when the synchronization step has been skipped or has failed.

This requirement applies to every change: code, tests, configuration, dependencies, workflows, architecture, and documentation, including changes to these instructions themselves. At the end of the task, perform one complete review; repeat only when that review finds an error that is then corrected.

### Required procedure

1. Before editing, inspect `git status --short`, this file, all nested `AGENTS.md` files, `.github/agents/*.agent.md`, and skills under `.agents/skills/**/SKILL.md`, `.github/skills/**/SKILL.md`, and `.claude/skills/**/SKILL.md`. Also inspect tool-specific instruction files present in the repository (including `.github/copilot-instructions.md`, `.cursor/rules/**`, and `CLAUDE.md`). Preserve pre-existing work.
2. Map the changed paths and behavior to existing agent responsibilities and skill `When to use` scopes. Read each applicable instruction and its linked procedures/references. If no skill covers recurring specialist work, extend the closest skill or create one with valid Agent Skills frontmatter (`name` and `description`) and a clear scope; do not create duplicate coverage.
3. After implementation, re-read the affected instructions. Update them when behavior, interfaces, security assumptions, commands, paths, tests, or reusable findings changed. Remove stale or contradictory guidance. Agent instructions must point to current skills; skill references and validation commands must resolve. Do not make cosmetic, empty, timestamp-only, or task-diary edits.
4. Every change set must contain a substantive, relevant change to at least one `AGENTS.md`, specialized `*.agent.md`, or `SKILL.md`. If no new reusable knowledge arises, make a relevant clarification or correction to instructions; do not fabricate knowledge. The automated check rejects empty/whitespace-only maintenance and checks structure and local Markdown links, while a human review must judge semantic relevance.
5. Validate instruction structure and references with `perl tools/check-agent-maintenance.pl --worktree` for local changes (or `perl tools/check-agent-maintenance.pl --base <base-sha> --head <head-sha>` for a PR range). Run the relevant project checks as well. GitHub Actions runs the range check on pull requests. The validator needs Perl and Git only; it does not prove semantic correctness.
6. Include the synchronization outcome in the final report. The task is incomplete if relevant instructions were not inspected, a needed update was omitted, references/checks fail, or semantic relevance has not been reviewed. Correct failures and rerun validation; if genuinely impossible, state the blocker and report FAIL rather than claiming completion.

### Post-Change Definition of Done

- [ ] Repository changes implemented.
- [ ] Relevant agent instructions reviewed.
- [ ] Relevant skills reviewed.
- [ ] Affected AGENTS.md / SKILL.md files updated.
- [ ] Obsolete knowledge removed.
- [ ] New reusable knowledge incorporated.
- [ ] Agent and skill references validated.
- [ ] Automated maintenance checks passed.
- [ ] Final synchronization status reported.

Every final response must include **Agent & Skills Synchronization** and report agents reviewed, skills reviewed, instruction files updated, knowledge incorporated or corrected, validations actually executed, and status `PASS` or `FAIL`. Never claim a check passed unless it was run. There are currently no specialized agent definition files; maintain this inventory when adding or removing them.

## License

MIT. Copyright (c) 2013 Milosz Galazka, (c) 2020 Morgan Aldridge,
(c) 2025-2026 David Uhden Collado. See `LICENSE`.
