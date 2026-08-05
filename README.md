# Xsunaba

## Overview

`Xsunaba` is an OpenBSD tool that runs X11 GUI applications with two optional isolation layers: a nested display via [Xephyr(1)](https://man.openbsd.org/Xephyr) and a restricted filesystem view via [unveil(2)](https://man.openbsd.org/unveil). It also exposes a low-level [pledge(2)](https://man.openbsd.org/pledge) helper for restricting Perl code itself.

The name comes from the Japanese word 砂場 (_sunaba_, meaning sandbox).

### How the sandbox works

1. **Display isolation** &mdash; `Xsunaba` starts a [Xephyr(1)](https://man.openbsd.org/Xephyr) nested X server that appears as a window inside your existing X session. The application renders into this nested display and cannot see keystrokes or X events intended for other windows in your real session. This prevents a compromised or nosy application from keylogging, screen-grabbing, or injecting input into your other applications.

2. **Filesystem restriction** &mdash; When `XSUNABA_UNVEIL` is configured, `Xsunaba` calls [unveil(2)](https://man.openbsd.org/unveil) and locks the resulting view before executing the application. The restricted view remains in the process across `exec`.

When `XSUNABA_UNVEIL` is set, the application can only access paths you explicitly allow, plus its private X authority file and the X11 socket directory. This is a kernel-enforced mitigation, not a complete security boundary.

`OpenBSD::Pledge(3p)` accepts only the promises for the current Perl process; it does not expose the `execpromises` argument of `pledge(2)`. Since a program executed without `execpromises` starts without pledge restrictions, Xsunaba deliberately does not claim to pledge an arbitrary target application. A non-empty legacy `XSUNABA_PLEDGE` value is rejected instead of silently providing no protection. Applications such as OpenBSD's browsers may install their own pledge policy after startup.

### What this is not

- This is **not** a full virtual machine or container. It does not provide kernel-level isolation like [vmm(4)](https://man.openbsd.org/vmm).
- Xephyr is another same-user process and part of the attack surface; display separation does not make it a hardened security boundary.
- A determined attacker who compromises the application may still be able to escape the sandbox, especially if you grant broad unveil paths.
- There is no window manager inside the Xephyr display. The application runs full-screen at the configured resolution. If your app needs session setup, wrap it in a shell script.

The goal is to raise the cost of attacks while keeping things lightweight and easy to configure. This is a mitigation, not a guarantee.

## Prerequisites

- **OpenBSD** &mdash; this is the supported platform. The pledge/unveil wrappers become no-ops elsewhere, but the Xenocara paths and overall launcher layout are OpenBSD-specific.
- **Perl** &mdash; included in the OpenBSD base system.
- **Xephyr** &mdash; provided by OpenBSD's versioned `xserv` installation set (for example, `xserv79.tgz` on OpenBSD 7.9). It is not installed with `pkg_add`.
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

This starts the application inside a Xephyr window. No filesystem restrictions are applied unless you set `XSUNABA_UNVEIL`.

### Restricting the filesystem with unveil

Set `XSUNABA_UNVEIL` to a comma-separated list of `path:permission` pairs. Only these paths will be visible to the application:

```
$ XSUNABA_UNVEIL="/usr/local/bin/firefox:rx,/usr/local/lib/firefox:rx,/tmp:rwc,/etc:r,/dev:r" \
  Xsunaba firefox --private-window
```

The application can now:
- Execute `/usr/local/bin/firefox` and its runtime (`rx`)
- Read and create files in `/tmp` (`rwc`)
- Read files in `/etc` and `/dev` (`r`)

Everything else on the filesystem is invisible. Xsunaba additionally unveils its private authority file with `r` and `/tmp/.X11-unix` with `rw`, after the user entries and before locking unveil. It does not automatically expose all of `/dev`; add only the devices the application needs.

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

Set `VERBOSE` to a non-empty value to see what `Xsunaba` is doing:

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
| `XSUNABA_UNVEIL` | _(unset, full filesystem visible)_ | Comma-separated list of `path:perm` entries. Each entry restricts or grants filesystem access for the application. When unset, the application inherits the launcher's filesystem view (no restrictions). |
| `XSUNABA_DISPLAY` | `:32` | Starting display number. Xephyr scans from here up to `:99` looking for a free socket in `/tmp/.X11-unix/`. |
| `WIDTH` | `1024` | Xephyr display width in pixels. |
| `HEIGHT` | `768` | Xephyr display height in pixels. |
| `VERBOSE` | _(unset)_ | Set to a non-empty value to emit diagnostic messages during setup and cleanup. |

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
XSUNABA_UNVEIL="/usr/local/bin/firefox:rx,/usr/local/lib/firefox:rx,/tmp:rwc,/etc:r,/dev:r,$HOME/.mozilla:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
```

### Chromium / Chrome

```
XSUNABA_UNVEIL="/usr/local/bin/chrome:rx,/usr/local/chrome:rx,/tmp:rwc,/etc:r,/dev:r,$HOME/.config/chromium:rwc,$HOME/.cache/chromium:rwc,/usr/local/lib:rx,/usr/lib:rx,/usr/X11R6/lib:rx,/usr/local/share:r,/usr/share:r"
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

`Xsunaba` can be loaded as a Perl module with `require`. This lets Perl programs restrict themselves with pledge/unveil or invoke the Xephyr/unveil launcher.

### Quick start

```perl
#!/usr/bin/perl
require '/usr/local/bin/Xsunaba';

# Option 1: one-call convenience wrapper (no Xephyr, unveil + exec)
Xsunaba::sandbox(
    app    => 'xterm',
    unveil => ['/usr/X11R6/bin/xterm:rx', '/tmp:rwc', '/etc:r'],
);
```

```perl
# Option 2: full Xephyr sandbox programmatically
Xsunaba::launch(
    app     => '/usr/local/bin/firefox',
    args    => ['--private-window'],
    display => ':40',
    width   => 1280,
    height  => 900,
    unveil  => ['/usr/local/bin/firefox:rx', '/usr/local/lib/firefox:rx', '/tmp:rwc', '/etc:r'],
);
```

### Low-level API

If you want fine-grained control, use the individual functions:

```perl
#!/usr/bin/perl
require '/usr/local/bin/Xsunaba';

# Restrict this Perl process to reading one file.
Xsunaba::unveil('/usr/share/dict/words', 'r');

# Lock the unveil list (no more unveil calls after this)
Xsunaba::unveil_lock();

# Restrict system calls
Xsunaba::pledge('stdio rpath');

open my $fh, '<', '/usr/share/dict/words' or die "open: $!";
print while <$fh>;
```

### Function reference

| Function | Arguments | Description |
|---|---|---|
| `pledge($promises)` | `$promises` &mdash; space-separated promise names | Splits the string into the list required by [OpenBSD::Pledge(3p)](https://man.openbsd.org/OpenBSD::Pledge), then calls `pledge(2)`. If omitted, the default `$PLEDGE_PROMISES` is used. No-op on non-OpenBSD systems. |
| `unveil($path, $perm)` | `$path` &mdash; filesystem path<br>`$perm` &mdash; permission string (default `r`) | Calls [unveil(2)](https://man.openbsd.org/unveil). Must be called before `unveil_lock()`. No-op on non-OpenBSD systems. |
| `unveil_lock()` | _(none)_ | Locks the unveil configuration. After this call, no more paths can be unveiled. The filesystem is now restricted to the announced paths. |
| `sandbox(%opts)` | `app` &mdash; executable to run<br>`args` &mdash; array ref of arguments<br>`unveil` &mdash; array ref of `"path:perm"` strings<br>`lock` &mdash; boolean (default true when unveil entries exist) | Applies unveil, then `exec`s the application directly. No Xephyr. Suitable for command-line tools or headless processes. |
| `launch(%opts)` | `app` &mdash; executable<br>`args` &mdash; arguments array ref<br>`display` &mdash; X display number<br>`width` &mdash; Xephyr width<br>`height` &mdash; Xephyr height<br>`unveil` &mdash; array ref of `"path:perm"` strings | Starts Xephyr, forks the application with optional unveil restrictions, waits for the app to exit, then stops Xephyr and cleans up. |

### Package variables

| Variable | Default | Description |
|---|---|---|
| `$Xsunaba::PLEDGE_PROMISES` | `stdio rpath wpath cpath fattr proc exec inet dns unix tty` | Default promise string used only by the low-level `pledge()` helper when its argument is omitted. |

## Tips and troubleshooting

### The application crashes immediately

Run with `VERBOSE=1` to see what is happening. Common causes:

- **Missing unveil paths**: The application cannot find its config files, shared libraries, or runtime data. Add the needed paths to `XSUNABA_UNVEIL`.
- **Xephyr can't start**: Check that `/usr/X11R6/bin/Xephyr` from the `xserv` set is installed, that the host `DISPLAY` is valid, and that `/tmp/.X11-unix` is usable.
- **Invalid geometry**: `WIDTH` and `HEIGHT` must be positive decimal integers.

### The application can't play audio

`sndio` uses Unix domain sockets and filesystem cookies. If unveil is enabled, you need:

1. `~/.sndio/cookie` unveiled with `r` permission
2. `/tmp/sndio` unveiled with `rwc` permission (or wherever `AUDIOSOCK` points)

```
XSUNABA_UNVEIL="$HOME/.sndio/cookie:r,/tmp/sndio:rwc,..."
```

### Running multiple sandboxes at once

Xephyr uses separate display numbers, so you can run multiple sandboxed applications simultaneously. Selection is serialized with a per-user advisory lock in `/tmp`, preventing two concurrent launchers from claiming the same free socket. Each gets its own display number (starting from `XSUNABA_DISPLAY`):

```
$ Xsunaba firefox &
$ Xsunaba chrome &
$ XSUNABA_DISPLAY=":50" Xsunaba gimp &
```

### The window is too small

Use `WIDTH` and `HEIGHT` to set the Xephyr window size. For `chrome` and `firefox`, geometry flags are automatically appended so the browser fills the Xephyr window. For other applications, you may need to pass geometry arguments yourself.

### Graphics performance

Acceleration depends on the Xephyr/Xorg build and host configuration. Do not assume that a particular renderer such as LLVMpipe is always selected; inspect the Xephyr log when diagnosing performance.

## Security considerations

- `unveil` is enforced by the OpenBSD kernel and cannot be widened after it is locked.
- The exported `pledge()` helper restricts the current Perl process only. It is suitable for embedded Perl workflows, but not for imposing promises on an arbitrary program executed afterward.
- The Xephyr display isolation prevents X11-level snooping but does **not** protect against kernel exploits or hardware-level attacks.
- Combine `Xsunaba` with other OpenBSD mitigations: keep your system updated, use full-disk encryption, and run applications under separate user accounts when additional isolation is needed.
- When filesystem restriction is enabled, `/tmp/.X11-unix` is additionally unveiled with `rw` for X11 communication. Other sockets remain protected by their X authority cookies, but exposing the directory is still part of the attack surface.
- Each run uses a mode-0600 temporary X authority file and passes it through `XAUTHORITY`; it is removed during normal cleanup.

## History

`Xsunaba` is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) and was ported to OpenBSD and `doas` by Morgan Aldridge. David Uhden Collado rewrote it in Perl (2025) and later added unveil integration and Xephyr display isolation (2026). Milosz granted permission for this implementation to be released under the MIT license.

## License

Released under the [MIT License](LICENSE) by permission.
