# Xsunaba

## OVERVIEW

`Xsunaba` runs X (X11) applications inside a minimal sandbox to constrain filesystem access and X events (notably keyboard input). "Sunaba" is the romanization of the Japanese word 砂場, meaning sandbox.

The sandbox is composed of:

1. A separate, less-privileged local user under which the X application executes, restricting access to your files when permissions are properly set
2. A separate X session rendered via `Xephyr` inside your existing display, preventing the sandboxed application from observing X events in the parent session

**IMPORTANT:** _This is a mitigation, not an absolute isolation boundary; leakage outside the sandbox user and display remains possible._

On OpenBSD, some X applications in ports additionally employ [pledge(2)](https://man.openbsd.org/pledge) and [unveil(2)](https://man.openbsd.org/unveil) to trim filesystem and network access.

Limitations of the `Xephyr` approach:

* No hardware acceleration for OpenGL; rendering falls back to [LLVMpipe](https://docs.mesa3d.org/drivers/llvmpipe.html). Expect acceptable 2D in some cases and very poor 3D performance.
* No display manager is spawned; the sandbox does not run the sandbox user's `~/.xsession` or `~/.xinitrc`, nor start a window manager. If an application needs environment setup, wrap it in a script that prepares the environment and invoke that via `Xsunaba`.

## PREREQUISITES

* OpenBSD
* [X(7)](https://man.openbsd.org/X) and [Xorg(1)](https://man.openbsd.org/Xorg) (preferably with the [xenodm(1)](https://man.openbsd.org/xenodm) display manager)
* [doas(1)](https://man.openbsd.org/doas)
* [Xephyr(1)](https://man.openbsd.org/Xephyr)
* [xauth(1)](https://man.openbsd.org/xauth)
* [openssl(1)](https://man.openbsd.org/openssl)

### Optional

* [xclip(1)](https://github.com/astrand/xclip)
* [sndio(7)](https://man.openbsd.org/sndio)

## INSTALLATION

Install `Xsunaba`, the manual page, create the `xsunaba` user, and add a doas rule allowing your user to run sandboxed applications without a password:

```
$ doas make install USER="$USER"
```

If `/etc/doas.conf` does not exist, it is created. When running `make install` as `root`, explicitly pass your username (replace `<username>`):

```
# make install USER=<username>
```

## USAGE

Prefix your X application command with `Xsunaba`, for example:

```
Xsunaba chrome --incognito &

Xsunaba firefox --private-window &
```

**NOTE:** `Xsunaba` applies geometry adjustments so `chrome` and `firefox` fit the `Xephyr` display.

### ADVANCED USAGE

You can override defaults with these environment variables:

* `VERBOSE`: Set to `true` to show verbose output. Default: `false`.
* `XSUNABA_DISPLAY`: Set a custom display number (incl. leading colon) to start `Xephyr` displays at. Default: `:32`.
* `XSUNABA_USER`: Set a username to run X application as. Default: `xsunaba`.
* `WIDTH`: Set a custom `Xephyr` display width in pixels. Default: `1024`.
* `HEIGHT`: Set a custom `Xephyr` display height in pixels. Default: `768`.

#### Alternate and/or Multiple Sandbox Users

If you would like your sandbox user to have a different username than `xsunaba` or would like to create multiple sandbox users, you can create them 
as follows (replacing `<sandbox_user>` with your preferred sandbox username):

```
doas make install-user XSUNABA_USER=<sandbox_user>
doas make install-doas XSUNABA_USER=<sandbox_user> USER=$USER
```

You can then execute `Xsunaba` with your custom sandbox user, for example (replacing `<sandbox_user>`):

```
XSUNABA_USER=<sandbox_user> Xsunaba firefox --private-window &
```

#### Shared Selection and/or Clipboard

To mirror the sandbox user's X selection or clipboard to your user with `xclip`, after launching an application in the sandbox run:

##### Selection

```
doas -u "$XSUNABA_USER" xclip -display "$XSUNABA_DISPLAY" -out | xclip -in
```

##### Clipboard

```
doas -u "$XSUNABA_USER" xclip -display "$XSUNABA_DISPLAY" -selection clipboard -out | xclip -selection clipboard -in
```

#### Shared Files

To share files, create a directory owned by `xsunaba` and grant group access to your primary user's group (typically matching your username). Move only the specific files required in and out; any application run via `Xsunaba` will see the shared directory.

*IMPORTANT:* This will weaken the security of your sandbox!

#### Audio

By default, sandboxed applications have no audio playback/recording for privacy. Following the ['Authentication' section in sndio(7)](https://man.openbsd.org/sndio#Authentication), you can copy `~/.sndio/cookie` to the `xsunaba` user to permit access to [sndiod(8)](https://man.openbsd.org/sndiod):

```
doas -u xsunaba mkdir -p ~xsunaba/.sndio
doas install -o xsunaba -g xsunaba -m 600 ~${USER}/.sndio/cookie ~xsunaba/.sndio/
```

The Makefile provides an `install-sndio-cookie` target to automate this:

```
doas make install-sndio-cookie USER=$USER
```

*IMPORTANT:* If kernel recording is enabled via [sysctl(8)](https://man.openbsd.org/sysctl) or [sysctl.conf(5)](https://man.openbsd.org/sysctl.conf) (`kern.audio.record=1`), sandboxed applications can access the microphone.

If audio fails inside the sandbox, verify:

1. You have played any audio as your primary user to create the sndio(7) cookie
2. You copied (not symlinked) `~/.sndio/cookie` to the sandbox user
3. Ownership is correct (e.g., `xsunaba:xsunaba`) and mode is `600`
4. The cookie contents match between your user and the sandbox user

## HISTORY

`Xsunaba` is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) (see [Internet Archive's Wayback Machine archive](https://web.archive.org/web/20210115000000*/https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/)) and ported to [OpenBSD](http://www.openbsd.org/) and `doas` by Morgan Aldridge. Milosz granted permission for this implementation to be released under the MIT license.

## LICENSE

Released under the [MIT License](LICENSE) by permission.