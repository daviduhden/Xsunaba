# Xsunaba

## Overview

`Xsunaba` runs X11 GUI applications on OpenBSD inside a nested
[Xephyr(1)](https://man.openbsd.org/Xephyr) display, under dedicated
Unix accounts, with optional filesystem restriction via
[unveil(2)](https://man.openbsd.org/unveil). The name comes from the
Japanese word 砂場 (_sunaba_, meaning sandbox).

The security boundary is **Unix account separation plus X11
authentication plus socket permissions**. Xephyr and the application
run under two dedicated local users that are distinct from your login
user. Neither account can read your credentials, and your login user
cannot read the nested display's credentials. `unveil(2)` and
`pledge(2)` are applied on top as defense in depth, not as the
boundary itself.

```
login user (you)
    |
    | parent X display :0
    v
_xsunaba_xephyr  (runs Xephyr only)
    |
    | nested X display :NN
    v
_xsunaba_app  (runs the application only)
```

### Principals

| Principal | UID | Can access |
|---|---|---|
| Login user | yours | Parent display, everything you own |
| `_xsunaba_xephyr` | dedicated | Parent display (as Xephyr's outer window), nested display server side |
| `_xsunaba_app` | dedicated | Nested display only |

### Why this matters

X11 access control with MIT-MAGIC-COOKIE-1 depends entirely on
keeping the cookie secret. In older Xsunaba versions, Xephyr and the
application ran as your login UID: any other process of yours could
read the temporary X authority file and join the nested display, and
the application could read your real `~/.Xauthority`. Merely using a
different DISPLAY number is not isolation.

The redesign removes that dependency on voluntary cooperation:

1. A process running as your login user **cannot** authenticate to the
   nested display: the cookie files are mode 0600 and owned by the two
   dedicated accounts, and the nested socket is mode 0660 owned by the
   Xephyr account, group `_xsunaba`, which your login user is not a
   member of.

2. An application launched by Xsunaba **cannot** obtain credentials
   for the parent display, with or without `XSUNABA_UNVEIL`: it runs
   as `_xsunaba_app`, its environment is rebuilt from scratch
   (`DISPLAY` points to the nested display, `XAUTHORITY` to its own
   authority file), and the parent's credentials are mode 0600 files
   owned by you or by the Xephyr account.

3. The application never runs with your UID, and Xephyr never runs
   with the application's UID.

4. Xephyr is itself a client of the parent X server. A malicious
   client already authorized on the parent display may still observe,
   resize, inject input into, or otherwise interfere with the Xephyr
   outer window. Xsunaba prevents **direct** access to the nested
   server by other processes and prevents the nested application from
   reaching the parent display; it cannot make two X11 clients on the
   same parent X server mutually isolated. Stronger host-to-sandbox
   isolation requires a separate X server/session/VT, a virtual
   machine, or another display architecture.

### What this is not

- This is **not** a full virtual machine or container. It does not
  provide kernel-level isolation like [vmm(4)](https://man.openbsd.org/vmm).
- Xephyr is not a hardened security boundary; it is an unprivileged X
  client of the parent display (see above).
- Separate Xsunaba invocations are **not** mutually isolated: they
  share the `_xsunaba_app` account, so an application in one session
  can read another session's application-side files (including its
  client authority file) and its shared home directory. Per-session
  isolation would require per-session UIDs.
- There is no window manager inside the Xephyr display. The
  application runs full-screen at the configured resolution. Wrap the
  command in a shell script if your app needs session setup.

## Prerequisites

- **OpenBSD** with Perl (both in base).
- **Xephyr** from the `xserv` installation set (e.g. `xserv79.tgz` on
  OpenBSD 7.9); it is not installed with `pkg_add`.
- **doas(1)** (in base) with the rule described below.
- No `xauth` or `openssl` dependency: authority databases are parsed,
  built and written directly by the helper, and cookies come from
  `/dev/urandom`.

## Installation

```
$ doas make install        # installs Xsunaba, the helper and the man page
$ doas make install-users  # creates the dedicated accounts
```

Then review and append the following rule to `/etc/doas.conf`
(`make show-doas-rule` prints it). Replace `<USER>` with your login
name, or `:wheel` with a suitable group:

```
permit nopass <USER> as root cmd /usr/local/libexec/xsunaba-helper args --parent-display
```

The rule grants execution of **only** the root-owned helper, only
with invocations that start with `--parent-display`. It grants nothing
else as root. It deliberately does **not** grant arbitrary execution
as the sandbox accounts: every operation must go through the helper's
validated interface.

`make install-users` creates:

| Account | Group | Home | Shell | Purpose |
|---|---|---|---|---|
| `_xsunaba_xephyr` | `_xsunaba_xephyr` | `/nonexistent` | nologin | Runs Xephyr |
| `_xsunaba_app` | `_xsunaba` | `/home/_xsunaba_app` | ksh | Runs applications |
| `_xsunaba` (group) | - | - | - | Socket group for the application UID |

Review the commands in the Makefile before running them; they are
idempotent.

### Uninstalling

```
$ doas make uninstall
```

The dedicated accounts are not removed (their home directory may
contain application data); remove them manually if desired.

## Usage

Prefix any X application command with `Xsunaba`:

```
$ Xsunaba firefox --private-window &
$ Xsunaba chrome --incognito &
$ Xsunaba xterm &
$ Xsunaba gimp &
```

The application runs as `_xsunaba_app` inside a Xephyr window owned
by `_xsunaba_xephyr`. No filesystem restrictions are applied unless
you set `XSUNABA_UNVEIL`; the Unix-account, X11-authentication and
socket-permission layers always apply.

### Restricting the filesystem with unveil

Set `XSUNABA_UNVEIL` to a comma-separated list of `path:permission`
pairs. Only these paths will be visible to the application:

```
$ XSUNABA_UNVEIL="/usr/local/bin/firefox:rx,/usr/local/lib/firefox:rx,/tmp:rwc,/etc:r,/dev:r" \
  Xsunaba firefox --private-window
```

The application can now execute `/usr/local/bin/firefox` and its
runtime (`rx`), read and create files in `/tmp` (`rwc`) and read
`/etc` and `/dev` (`r`). Everything else is invisible.

Additionally, Xsunaba always unveils for the application, after your
entries and before locking:

- `/tmp/.X11-unix/X<NN>` with `w` &mdash; the exact nested socket
  only (`w` permits `connect(2)` to AF_UNIX sockets). The
  `/tmp/.X11-unix` directory itself is **not** exposed.
- the application's own client authority file with `r`;
- its per-session `XDG_RUNTIME_DIR` with `rwxc`.

Note that the application's home is now `/home/_xsunaba_app`; unveil
paths must reference it (e.g.
`/home/_xsunaba_app/.mozilla:rwc`), not your own home.

`unveil` is an **additional** restriction. The account and credential
separation holds when `XSUNABA_UNVEIL` is unset.

### Sharing files with the sandbox

The application cannot read your files (different UID, private home
directory). To share specific data, copy it into
`/home/_xsunaba_app` (as root), or use a directory readable by the
`_xsunaba_app` account. Anything readable by `_xsunaba_app` is
readable by every Xsunaba application session.

### Audio

`sndio` authentication is per-user; the sandbox account does not have
your `~/.sndio/cookie`. To allow audio, copy or expose the cookie to
the sandbox account yourself (this weakens audio isolation):

```
# doas -u _xsunaba_app mkdir -m 700 /home/_xsunaba_app/.sndio
# doas cp ~/.sndio/cookie /home/_xsunaba_app/.sndio/cookie
# doas chown _xsunaba_app:_xsunaba /home/_xsunaba_app/.sndio/cookie
```

and unveil `~/.sndio/cookie:r` plus `/tmp/sndio:rwc` for the
application.

### Changing the Xephyr display

By default Xephyr starts at display `:32` and scans upward to find a
free socket. Set a different starting display:

```
$ XSUNABA_DISPLAY=":50" Xsunaba firefox
```

### Changing the window size

```
$ WIDTH=1280 HEIGHT=1024 Xsunaba firefox
```

For `firefox` and `chrome`, `Xsunaba` automatically appends geometry
flags so the browser fills the Xephyr window.

### Verbose output

```
$ VERBOSE=1 Xsunaba firefox
[INFO] using display :32
[INFO] session directory /var/run/xsunaba/<random>
[INFO] Xephyr started (PID 12345)
[INFO] launched 'firefox' (PID 12346)
[INFO] stopped Xephyr (PID 12345)
[INFO] cleanup complete
```

Authentication material never appears in any output.

## Environment variable reference

| Variable | Default | Description |
|---|---|---|
| `XSUNABA_UNVEIL` | _(unset, full filesystem visible to the sandbox account)_ | Comma-separated `path:perm` entries passed to unveil(2) for the application. When unset, no unveil is applied; the account and credential separation still holds. |
| `XSUNABA_DISPLAY` | `:32` | Starting display number; Xephyr scans upward for a free socket. |
| `WIDTH` | `1024` | Xephyr display width in pixels. |
| `HEIGHT` | `768` | Xephyr display height in pixels. |
| `VERBOSE` | _(unset)_ | Emit diagnostic messages. |

The application's environment is rebuilt from scratch and contains
only `PATH`, `HOME`, `USER`, `LOGNAME`, `SHELL`, `DISPLAY`,
`XAUTHORITY`, `XDG_RUNTIME_DIR`, and (if present in the invoking
environment) `TERM`, `TZ`, `LANG` and `LC_*`. Variables such as
`DBUS_SESSION_BUS_ADDRESS`, `SSH_AUTH_SOCK`, `SSH_AGENT_PID`,
`GPG_AGENT_INFO`, `WAYLAND_DISPLAY`, `XDG_SESSION_*`, `KRB5CCNAME`,
`sndio` variables and `XSUNABA_*` are never forwarded. The invoking
environment is not copied wholesale into the sandbox account.

### Unveil permission codes

| Code | Allowed operations |
|---|---|
| `r` | Read files, list directories. |
| `rx` | Read and execute. Use for binaries and shared libraries. |
| `rw` | Read and write existing files. |
| `rwx` | Read, write, and execute existing files. |
| `rwc` | Read, write, and create new files. |
| `rwxc` | Read, write, execute, and create. Full access to that subtree. |

## Choosing unveil paths for common applications

Every application needs different paths; remember that profile
directories now live under `/home/_xsunaba_app`. Starting points:

### Firefox

```
XSUNABA_UNVEIL="/usr/local/bin/firefox:rx,/usr/local/lib/firefox:rx,/tmp:rwc,/etc:r,/dev:r,/home/_xsunaba_app/.mozilla:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
```

### Chromium / Chrome

```
XSUNABA_UNVEIL="/usr/local/bin/chrome:rx,/usr/local/chrome:rx,/tmp:rwc,/etc:r,/dev:r,/home/_xsunaba_app/.config/chromium:rwc,/home/_xsunaba_app/.cache/chromium:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
```

### xterm

```
XSUNABA_UNVEIL="/usr/X11R6/bin/xterm:rx,/tmp:rwc,/etc:r,/dev:r"
```

## Runtime files

| Path | Owner | Mode | Purpose |
|---|---|---|---|
| `/var/run/xsunaba/` | root:wheel | 0711 | Session runtime directory (created by the helper). |
| `/var/run/xsunaba/<random>/` | root:wheel | 0711 | One session. Traversable but not listable by users. |
| `.../xephyr/` | `_xsunaba_xephyr` | 0700 | Xephyr private directory. |
| `.../xephyr/parent-auth` | `_xsunaba_xephyr` | 0600 | Only the parent-display MIT-MAGIC-COOKIE-1 records Xephyr needs. |
| `.../xephyr/server-auth` | `_xsunaba_xephyr` | 0600 | Fresh per-session nested cookie, passed to Xephyr via `-auth`. |
| `.../app/` | `_xsunaba_app` | 0700 | Application private directory. |
| `.../app/client-auth` | `_xsunaba_app` | 0600 | Same nested cookie, for the application (`XAUTHORITY`). |
| `.../app/run/` | `_xsunaba_app` | 0700 | Per-session `XDG_RUNTIME_DIR`. |
| `/tmp/.X11-unix/X<NN>` | `_xsunaba_xephyr:_xsunaba` | 0660 | Nested socket, tightened after Xephyr creates it. |

Your login user owns none of the authority files and cannot read
them. The nested cookie is never placed in command-line arguments,
logs, the environment of unrelated processes, or predictable
locations. Nothing security-sensitive is kept in `/tmp`.

## Architecture

`Xsunaba` is a thin frontend. It validates its arguments and executes
`/usr/local/libexec/xsunaba-helper` through doas. The root-owned
helper controls the entire session:

1. It validates every argument (parent display must be local, the
   parent Xauthority must be owned by the invoking user, the
   application path must be absolute, geometry values bounded, unveil
   entries well-formed) and fails closed on any error.
2. It acquires `/var/run/xsunaba/display.lock` and allocates a free
   nested display atomically; callers can never join an existing
   session, supply a session directory, socket pathname, UID or
   authority file.
3. It creates a random session directory and copies only the
   parent-display `MIT-MAGIC-COOKIE-1` records from your Xauthority
   into `xephyr/parent-auth`.
4. It generates a fresh 128-bit cookie from `/dev/urandom` and writes
   it into `server-auth` and `client-auth` (two authority files, one
   trust domain per file, both mode 0600).
5. It forks Xephyr as `_xsunaba_xephyr` with a sanitized environment,
   `-auth` set to `server-auth`, `-nolisten tcp` and `-noreset`.
6. Once the nested socket exists, it verifies Xephyr created it, then
   chowns it to `_xsunaba_xephyr:_xsunaba` and chmods it to 0660,
   so only the two sandbox accounts can connect. `-noreset` prevents
   the server from recreating the socket with loose permissions on a
   reset. (The X server otherwise creates sockets with umask(0) and
   mode 0777.)
7. It forks the application as `_xsunaba_app` with a rebuilt
   environment, optionally applies your unveil entries plus the exact
   nested socket (`w`), the client authority (`r`) and the runtime
   directory (`rwxc`), locks unveil, and execs the application.
8. It waits for the application, stops Xephyr, removes the socket and
   the session tree, and returns the application's exit status.

The helper then pledges itself (`stdio rpath cpath fattr proc`) for
the teardown phase; the frontend pledges `stdio exec`. The helper
drops privileges with verified `setgid`/`setuid` sequences and checks
that privileges cannot be regained. Children never inherit privileged
state, supplementary groups are reset, and every security-sensitive
syscall is checked.

### Why unveil alone was not enough

Even with unveil, the old design exposed all of `/tmp/.X11-unix` and
kept the nested cookie in a file readable by the login user, and the
application still ran with the login UID. `unveil` restricts the
process's own filesystem view; it does not create a credential
boundary against other same-UID processes. That is what the separate
accounts, the split authority files and the socket permissions now
provide.

## Module usage (Perl API)

`Xsunaba` can be loaded as a Perl module. The low-level
`pledge`/`unveil` helpers restrict the **current** process only, and
`launch()` is the frontend used by the command-line tool (it requires
the helper and the doas rule to be installed).

```perl
#!/usr/bin/perl
require '/usr/local/bin/Xsunaba';

Xsunaba::launch(
    app     => '/usr/local/bin/firefox',
    args    => ['--private-window'],
    display => ':40',
    width   => 1280,
    height  => 900,
    unveil  => ['/usr/local/bin/firefox:rx', '/tmp:rwc'],
);
```

The `sandbox()` convenience wrapper applies unveil in the current
process and execs a program; it does not switch UIDs or start Xephyr.

## Tips and troubleshooting

- **Xephyr can't start**: check that the `xserv` set is installed,
  that your parent `DISPLAY` is a local display (`:0`), that the
  parent socket allows other users to connect (the default mode 0777
  does), and that the doas rule is present.
- **"no MIT-MAGIC-COOKIE-1 entry"**: your `~/.Xauthority` has no
  cookie for the parent display; run `xauth list` to inspect it.
- **App cannot read its files**: profile paths moved to
  `/home/_xsunaba_app`; unveil entries must reference the new
  location.
- **Multiple sandboxes at once**: supported; display allocation is
  serialized by the helper. Sessions share the sandbox accounts and
  are not mutually isolated.

## Security considerations

- The boundary is: separate Unix accounts, per-domain authority
  files, a fresh cookie per invocation, a 0660 group-restricted
  socket, and sanitized environments. `unveil`/`pledge` are
  defense in depth.
- Xephyr remains a client of the parent X server: an attacker already
  authorized on the parent display can interfere with its window.
- `_xsunaba_app` processes from different sessions share a UID and
  can access each other's files; do not claim per-session isolation.
- A compromised `_xsunaba_app` cannot read your `~/.Xauthority`
  (mode 0600, private home) or the Xephyr authority files (mode 0600,
  other UID), and cannot connect to the nested socket of other
  sessions without their cookies.
- Keep your system updated and prefer applications with their own
  pledge(2) policies.

## History

`Xsunaba` is based on [a script by Milosz
Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/)
and was ported to OpenBSD and `doas` by Morgan Aldridge. David Uhden
Collado rewrote it in Perl (2025) and added unveil integration (2026).
The 2026 redesign replaces the same-UID model (where the cookie files
were readable by the login user) with dedicated `_xsunaba_xephyr` /
`_xsunaba_app` accounts, a narrow root helper invoked through doas,
split authority files, socket permission tightening and a rebuilt
environment.

## License

Released under the [MIT License](LICENSE) by permission.
