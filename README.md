# Xsunaba

## Overview

`Xsunaba` is an OpenBSD tool that runs X11 GUI applications inside a sandbox with two layers of protection: display isolation via [Xephyr(1)](https://man.openbsd.org/Xephyr) and process restriction via [pledge(2)](https://man.openbsd.org/pledge) and [unveil(2)](https://man.openbsd.org/unveil).

The name comes from the Japanese word 砂場 (_sunaba_, meaning sandbox).

### How the sandbox works

1. **Display isolation** &mdash; `Xsunaba` starts a [Xephyr(1)](https://man.openbsd.org/Xephyr) nested X server that appears as a window inside your existing X session. The application renders into this nested display and cannot see keystrokes or X events intended for other windows in your real session. This prevents a compromised or nosy application from keylogging, screen-grabbing, or injecting input into your other applications.

2. **Process restriction** &mdash; Before the application starts, `Xsunaba` calls [pledge(2)](https://man.openbsd.org/pledge) and [unveil(2)](https://man.openbsd.org/unveil) inside the application process. `pledge` restricts which system calls the process may use (network, filesystem, forking, etc.). `unveil` restricts which parts of the filesystem the process can see. Both are configured through environment variables, so you can tighten or loosen restrictions per application.

When `XSUNABA_UNVEIL` is set, the application can only access paths you explicitly allow. When `XSUNABA_PLEDGE` is set (or left at its safe default), the application can only make system calls you permit. Both restrictions are enforced by the kernel and cannot be escaped by the application.

### What this is not

- This is **not** a full virtual machine or container. It does not provide kernel-level isolation like [vmm(4)](https://man.openbsd.org/vmm).
- A determined attacker who compromises the application may still be able to escape the sandbox, especially if you grant broad promises or unveil paths.
- There is no window manager inside the Xephyr display. The application runs full-screen at the configured resolution. If your app needs session setup, wrap it in a shell script.

The goal is to raise the cost of attacks while keeping things lightweight and easy to configure. This is a mitigation, not a guarantee.

## Prerequisites

- **OpenBSD** &mdash; `pledge` and `unveil` are OpenBSD-only kernel interfaces. The script is harmless on other systems (it logs warnings and skips restrictions), but you will only get the full sandbox on OpenBSD.
- **Perl** &mdash; included in the OpenBSD base system.
- **Xephyr** &mdash; install via `pkg_add xephyr` or by enabling the X11 file set during installation.
- **xauth** &mdash; included with Xenocara (the OpenBSD X11 distribution).
- **openssl** &mdash; included in the base system, used to generate X11 magic cookies for authenticating connections to the Xephyr display.

## Installation

Clone the repository and run:

```
$ doas make install
```

This installs the `Xsunaba` script to `/usr/local/bin/Xsunaba` (mode 755) and the manual page to `/usr/local/man/man1/Xsunaba.1` (mode 444).

There are no build steps &mdash; the tool is pure Perl. The Makefile simply copies files into place.

### Uninstalling

```
$ doas make uninstall
```

Removes the script and the man page from `/usr/local`.

## Usage

### Basic usage

Prefix any X application command with `Xsunaba`:

```
$ Xsunaba firefox --private-window &
$ Xsunaba chrome --incognito &
$ Xsunaba xterm &
$ Xsunaba gimp &
```

This starts the application inside a Xephyr window with the default pledge promises applied (`stdio rpath wpath cpath fattr proc exec inet dns unix tty`). No filesystem restrictions are applied unless you set `XSUNABA_UNVEIL`.

### Restricting the filesystem with unveil

Set `XSUNABA_UNVEIL` to a comma-separated list of `path:permission` pairs. Only these paths will be visible to the application:

```
$ XSUNABA_UNVEIL="/usr/X11R6/bin/firefox:rx,/tmp:rwc,/etc:r,/dev:r" \
  Xsunaba firefox --private-window
```

The application can now:
- Execute `/usr/X11R6/bin/firefox` (`rx`)
- Read and create files in `/tmp` (`rwc`)
- Read files in `/etc` and `/dev` (`r`)

Everything else on the filesystem is invisible. The `/tmp/.X11-unix` socket directory and `/dev` are always unveiled for X11 communication, so you do not need to include them unless you want to change permissions.

### Tightening system-call access with pledge

Set `XSUNABA_PLEDGE` to override the default promises:

```
$ XSUNABA_PLEDGE="stdio rpath inet dns" \
  Xsunaba xterm
```

This restricts `xterm` to basic I/O (`stdio`), reading files (`rpath`), and network access (`inet dns`). The process cannot write files, create directories, fork, or execute other programs.

To disable pledge entirely (not recommended), set `XSUNABA_PLEDGE` to an empty string:

```
$ XSUNABA_PLEDGE="" Xsunaba my-app
```

### Changing the Xephyr display

By default Xephyr starts on display `:32` and scans upward (`:33`, `:34`, ..., `:99`) if that socket is already taken. You can set a different starting display:

```
$ XSUNABA_DISPLAY=":50" Xsunaba firefox
```

### Changing the window size

```
$ WIDTH=1280 HEIGHT=1024 Xsunaba firefox
```

Xephyr will open a window of 1280&times;1024 pixels. For `firefox` and `chrome`, `Xsunaba` automatically appends geometry flags so the browser fills the Xephyr window.

### Verbose output

Set `VERBOSE` to any true value to see what `Xsunaba` is doing:

```
$ VERBOSE=1 Xsunaba firefox
[INFO] using display :32
[INFO] Xephyr started (PID 12345)
[INFO] launched 'firefox' (PID 12346)
[INFO] stopping Xephyr (PID 12345)
[INFO] cleanup complete
```

## Environment variable reference

| Variable | Default | Description |
|---|---|---|
| `XSUNABA_PLEDGE` | `stdio rpath wpath cpath fattr proc exec inet dns unix tty` | Space-separated pledge promises applied to the application. Set to an empty string to disable. See [pledge(2)](https://man.openbsd.org/pledge) for the full list of promises. |
| `XSUNABA_UNVEIL` | _(unset, full filesystem visible)_ | Comma-separated list of `path:perm` entries. Each entry restricts or grants filesystem access for the application. When unset, the application inherits the launcher's filesystem view (no restrictions). |
| `XSUNABA_DISPLAY` | `:32` | Starting display number. Xephyr scans from here up to `:99` looking for a free socket in `/tmp/.X11-unix/`. |
| `WIDTH` | `1024` | Xephyr display width in pixels. |
| `HEIGHT` | `768` | Xephyr display height in pixels. |
| `VERBOSE` | _(unset)_ | Set to any true value (`1`, `true`, `yes`) to emit diagnostic messages during setup and cleanup. |

### Unveil permission codes

| Code | Allowed operations |
|---|---|
| `r` | Read files, list directories. |
| `rx` | Read and execute. Use this for binaries and shared libraries. |
| `rw` | Read and write existing files. |
| `rwx` | Read, write, and execute existing files. |
| `rwc` | Read, write, and create new files. |
| `rwxc` | Read, write, execute, and create. Full access to that subtree. |

## Choosing unveil paths for common applications

Every application needs different paths. Here are starting points for common programs.

### Firefox

```
XSUNABA_UNVEIL="/usr/X11R6/bin/firefox:rx,/tmp:rwc,/etc:r,/dev:r,$HOME/.mozilla:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
```

### Chromium / Chrome

```
XSUNABA_UNVEIL="/usr/X11R6/bin/chrome:rx,/tmp:rwc,/etc:r,/dev:r,$HOME/.config/chromium:rwc,$HOME/.cache/chromium:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
```

### xterm

```
XSUNABA_UNVEIL="/usr/X11R6/bin/xterm:rx,/tmp:rwc,/etc:r,/dev:r"
```

### Generic pattern

At minimum, most GUI applications need:

- Their own binary: `path:rx`
- Their config and cache directories: `path:rwc`
- `/tmp`: `rwc`
- `/etc`: `r`
- `/dev`: `r`
- Library directories if they load shared objects at runtime: `rx`

Start with the minimum, run with `VERBOSE=1`, and add paths if the application fails to start.

## Module usage (Perl API)

`Xsunaba` can be loaded as a Perl module with `require`. This lets you embed pledge/unveil logic into your own scripts, launchers, or wrapper programs.

### Quick start

```perl
#!/usr/bin/perl
require '/usr/local/bin/Xsunaba';

# Option 1: one-call convenience wrapper (no Xephyr, just pledge + unveil + exec)
Xsunaba::sandbox(
    app    => 'xterm',
    unveil => ['/usr/X11R6/bin/xterm:rx', '/tmp:rwc', '/etc:r'],
    pledge => 'stdio rpath wpath cpath inet dns unix tty',
);
```

```perl
# Option 2: full Xephyr sandbox programmatically
Xsunaba::launch(
    app     => 'firefox',
    args    => ['--private-window'],
    display => ':40',
    width   => 1280,
    height  => 900,
    unveil  => ['/usr/X11R6/bin/firefox:rx', '/tmp:rwc', '/etc:r'],
    pledge  => 'stdio rpath wpath cpath proc exec inet dns unix tty',
);
```

### Low-level API

If you want fine-grained control, use the individual functions:

```perl
#!/usr/bin/perl
require '/usr/local/bin/Xsunaba';

# Announce paths the process is allowed to access
Xsunaba::unveil('/usr/X11R6/bin/firefox',  'rx');
Xsunaba::unveil("$ENV{HOME}/.mozilla",     'rwc');
Xsunaba::unveil('/tmp',                     'rwc');
Xsunaba::unveil('/etc',                     'r');
Xsunaba::unveil('/dev',                     'r');
Xsunaba::unveil('/usr/local/lib',           'rx');
Xsunaba::unveil('/usr/lib',                 'rx');

# Lock the unveil list (no more unveil calls after this)
Xsunaba::unveil_lock();

# Restrict system calls
Xsunaba::pledge('stdio rpath wpath cpath proc exec inet dns unix tty');

# Launch the application
exec 'firefox', '--private-window' or die "exec: $!";
```

### Function reference

| Function | Arguments | Description |
|---|---|---|
| `pledge($promises)` | `$promises` &mdash; space-separated promise names | Calls [pledge(2)](https://man.openbsd.org/pledge). If `$promises` is omitted or `undef`, the default `$PLEGE_PROMISES` is used. No-op on non-OpenBSD systems. |
| `unveil($path, $perm)` | `$path` &mdash; filesystem path<br>`$perm` &mdash; permission string (default `r`) | Calls [unveil(2)](https://man.openbsd.org/unveil). Must be called before `unveil_lock()`. No-op on non-OpenBSD systems. |
| `unveil_lock()` | _(none)_ | Locks the unveil configuration. After this call, no more paths can be unveiled. The filesystem is now restricted to the announced paths. |
| `sandbox(%opts)` | `app` &mdash; executable to run<br>`args` &mdash; array ref of arguments<br>`pledge` &mdash; promise string<br>`unveil` &mdash; array ref of `"path:perm"` strings<br>`lock` &mdash; boolean (default true when unveil entries exist) | Applies unveil and pledge, then `exec`s the application directly. No Xephyr. Suitable for command-line tools or headless processes. |
| `launch(%opts)` | `app` &mdash; executable<br>`args` &mdash; arguments array ref<br>`display` &mdash; X display number<br>`width` &mdash; Xephyr width<br>`height` &mdash; Xephyr height<br>`pledge` &mdash; promise string<br>`unveil` &mdash; array ref of `"path:perm"` strings | Full sandbox: starts Xephyr, forks the application with pledge/unveil applied, waits for the app to exit, then stops Xephyr and cleans up. |

### Package variables

| Variable | Default | Description |
|---|---|---|
| `$Xsunaba::PLEGE_PROMISES` | `stdio rpath wpath cpath fattr proc exec inet dns unix tty` | Default pledge string used by `pledge()`, `sandbox()`, and `launch()` when no explicit promise string is provided. Set this before calling the functions to change the default. |

## Tips and troubleshooting

### The application crashes immediately

Run with `VERBOSE=1` to see what is happening. Common causes:

- **Missing unveil paths**: The application cannot find its config files, shared libraries, or runtime data. Add the needed paths to `XSUNABA_UNVEIL`.
- **Pledge too restrictive**: The application needs a system call that is not in your promise list. Start with the default `XSUNABA_PLEDGE` and remove promises one at a time to find the minimum.
- **Xephyr can't start**: Check that Xephyr is installed (`pkg_info | grep xephyr`) and that `/tmp/.X11-unix` exists and is writable.

### The application has no network access

Make sure `XSUNABA_PLEDGE` includes `inet` (for sockets) and `dns` (for hostname resolution). If your application uses Unix domain sockets (common for D-Bus, PulseAudio, etc.), also include `unix`.

### The application can't play audio

`sndio` uses Unix domain sockets and filesystem cookies. You need:

1. `unix` in your pledge promises
2. `~/.sndio/cookie` unveiled with `r` permission
3. `/tmp/sndio` unveiled with `rwc` permission (or wherever `AUDIOSOCK` points)

```
XSUNABA_UNVEIL="$HOME/.sndio/cookie:r,/tmp/sndio:rwc,..."
```

### Running multiple sandboxes at once

Xephyr uses separate display numbers, so you can run multiple sandboxed applications simultaneously. Each gets its own display number (starting from `XSUNABA_DISPLAY`):

```
$ Xsunaba firefox &
$ Xsunaba chrome &
$ XSUNABA_DISPLAY=":50" Xsunaba gimp &
```

### The window is too small

Use `WIDTH` and `HEIGHT` to set the Xephyr window size. For `chrome` and `firefox`, geometry flags are automatically appended so the browser fills the Xephyr window. For other applications, you may need to pass geometry arguments yourself.

### No hardware acceleration

Xephyr uses software rendering (LLVMpipe). 2D performance is acceptable for most desktop applications. 3D performance will be poor. This is a limitation of the nested X server approach.

## Security considerations

- `pledge` and `unveil` are enforced by the OpenBSD kernel. Once applied to a process, they cannot be lifted.
- The Xephyr display isolation prevents X11-level snooping but does **not** protect against kernel exploits or hardware-level attacks.
- Combine `Xsunaba` with other OpenBSD mitigations: keep your system updated, use full-disk encryption, and run applications under separate user accounts when additional isolation is needed.
- The `/tmp/.X11-unix` socket directory is always unveiled with `rwc` for the application. This is required for X11 communication. A compromised application could potentially interact with other X11 sockets in that directory if they are not properly protected (e.g., incorrect `xauth` cookie handling).

## History

`Xsunaba` is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) and was ported to OpenBSD and `doas` by Morgan Aldridge. David Uhden Collado rewrote it in Perl (2025) and later refactored it into a pledge/unveil variable wrapper with Xephyr display isolation (2026). Milosz granted permission for this implementation to be released under the MIT license.

## License

Released under the [MIT License](LICENSE) by permission.
