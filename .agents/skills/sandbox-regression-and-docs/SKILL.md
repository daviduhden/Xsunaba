---
name: sandbox-regression-and-docs
description: >-
  Run and extend Xsunaba's portable regression suite, static checks, and
  paired README/man documentation. Use when adding tests, changing Makefile
  targets, updating security claims, or preparing a change for review
  without privileged runtime testing.
---

# Sandbox regression and documentation

## When to use

Use this skill when a task touches:

- `t/*.t`, `t/lib/TestHelper.pm`.
- `Makefile` targets `test`, `tools`, `help`, `show-doas-rule`.
- `README.md` or `man/Xsunaba.1`.
- `t/90-static.t` needles or security claims that must stay evidence-based.

## Test layers

| Layer | What it proves | What it does not prove |
|---|---|---|
| Static reading/grep | Source shape, forbidden constructs, doc needles | Runtime behavior |
| `perl -c` / `perl -T -c` | Syntax and taint-mode compilation | Execution, privileges |
| Pure-function tests | Argv builders, parsers, env builders, validators | Syscalls, X11, accounts |
| Temp-dir integration | Reaper on synthetic sessions, real temp sockets | Real `/var/run`, real users |
| Optional X11 test | Pointer/popup behavior on a real display | Privilege boundary |

No test calls the helper's `run()`, `drop_privs()`, Xephyr, doas, or real
account creation. Do not describe the suite as an end-to-end sandbox test.

## Procedure

1. Read `AGENTS.md`, the changed code, and the nearest test. Check
   `git status --short` first and preserve unrelated work.
2. Choose the smallest test layer that can catch the regression. Prefer a
   pure function or a temp-dir test over a privileged runtime test.
3. If you need a script, load it by path:
   `require "$FindBin::Bin/../libexec/xsunaba-helper";`
   and use `local $Xsunaba::Helper::RUN_DIR` for state.
4. Use `TestHelper`:
   - `run_capture(@cmd)` uses `IPC::Open3`, no shell, returns
     `($stdout, $stderr, $?)`.
   - `dies_ok { ... } qr/.../, 'name'`.
   - `lives_ok { ... }`; note its optional regex is only checked when the
     block dies.
5. Update `README.md` and `man/Xsunaba.1` together for behavior or claim
   changes. Keep the `t/90-static.t` needles: `_xsunaba_app`,
   `_xsunaba_xephyr`, `permit nopass`, `--amnesiac`, `-resizeable` (or
   `Fl resizeable`), `-no-host-grab` (or `Fl no-host-grab`), and
   "Crossing the Unix-user isolation boundary".
6. Run only portable checks unless the task explicitly authorizes real X11
   or OpenBSD runtime work.

## Validation

```sh
make test
prove -I t/lib t/
perl -T -c libexec/xsunaba-helper
perl -c bin/Xsunaba.pl
make -s show-doas-rule
make -s help
git diff --check
git status --short
```

There is no hosted CI. Run the validation commands above locally and
report which ones ran. They do not run `make tools`, the optional X11
test, `make install`, `make install-users`, doas, Xephyr, or real account
operations.

Optional, only with explicit approval:

```sh
make tools
XSUNABA_TEST_DISPLAY=:32 prove -I t/lib t/95-x11-optional.t
```

`t/95-x11-optional.t` injects pointer input into the named display and
writes `tools/popup-grab-test.log`. Treat it as a real interactive test,
not part of the default suite.

## Common problems

- Running `make install-users` or `make uninstall` as a "test". They
  modify the system and are outside test scope.
- Assuming `t/90-static.t` proves semantics. It greps source text.
- Editing only `README.md` or only `man/Xsunaba.1`; the static test checks
  both.
- Documenting "only these paths are visible" or "nothing persists" without
  the `execve`/teardown qualifications.
- Using a shell in tests; `t/90-static.t` forbids `system`, backticks, and
  `qx` in shipped code, and tests follow the same no-shell convention.
- Forgetting that `t/12-amnesiac.t` uses the synthetic account name
  `_xsunaba_ffffffffffffffff`; do not run it as root on a system where that
  account could exist.
- Reporting a passing suite as proof that the socket race, privilege drop,
  or reaper is safe at runtime.

## References

- `AGENTS.md`
- `t/00-compile.t`, `t/10-args.t`, `t/11-xephyr-argv.t`,
  `t/12-amnesiac.t`, `t/13-umask.t`, `t/15-makefile.t`, `t/20-xauth.t`,
  `t/30-cookie.t`, `t/40-display.t`, `t/50-unveil.t`, `t/60-env.t`,
  `t/70-frontend.t`, `t/80-log.t`, `t/90-static.t`, `t/95-x11-optional.t`
- `t/lib/TestHelper.pm`
- `Makefile`
- `README.md`, `man/Xsunaba.1`
