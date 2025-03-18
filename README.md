# Xsunaba

## Overview

Xsunaba is a utility to run X11 (or just X) applications in a basic sandbox ('sunaba' from Japanese) to limit access to your files and X11 events (especially keyboard input). The 'sandbox' consists of:

1. A separate local user account under which the X11 application will be run, restricting access to your user files (assuming appropriate permissions are in place).
2. A separate X session created and rendered into a window within your running X display using `Xephyr`, preventing the sandboxed X application from snooping on X11 events in the parent X session & display.

_IMPORTANT:_ This _does not_ guarantee access is prevented outside the sandbox user & display, but it should be at least marginally safer.

This is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) (see [Internet Archive's Wayback Machine archive](https://web.archive.org/web/20210115000000*/https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/)) and ported to [OpenBSD](http://www.openbsd.org/).

For those using Xsunaba under OpenBSD, some X11 applications in the ports tree utilize the [pledge(2)](https://man.openbsd.org/pledge) & [unveil(2)](https://man.openbsd.org/unveil) functions to further restrict access to the filesystem.

## Prerequisites

* [OpenBSD](https://www.openbsd.org/faq/faq4.html#Download)
* X11 (preferably running [xenodm(1)](https://man.openbsd.org/xenodm))
* [doas(1)](https://man.openbsd.org/doas)
* [Xephyr(1)](https://man.openbsd.org/Xephyr)
* [xauth(1)](https://man.openbsd.org/xauth)
* [openssl(1)](https://man.openbsd.org/openssl)

### Optional

* [sndio(7)](https://man.openbsd.org/sndio)

## Usage

1. To install `Xsunaba`, create the `xsunaba` user, and update your `/etc/doas.conf` to allow your user to run applications in the sandbox without a password:

    ```sh
    doas make install USER="$USER"
    ```

2. If you don't yet have an `/etc/doas.conf`, one will be created for you, but you will need to explicitly specify your username when running `make install` as `root` (replacing `<username>` with your username):

    ```sh
    doas make install USER=<username>
    ```

3. Prefix your X11 application command with `Xsunaba`, for example:

    ```sh
    Xsunaba chrome --incognito &
    Xsunaba firefox --private-window &
    ```

_Note:_ `Xsunaba` will automatically apply window geometry hacks to fit the `Xephyr` display for the following X11 applications: `chrome` and `firefox`.

### Advanced Usage

The following environment variables may be set to change `Xsunaba`'s behavior:

* `VERBOSE`: Set to `true` to show verbose output. Default: `false`.
* `XSUNABA_DISPLAY`: Set a custom display number (including leading colon) to start `Xephyr` displays at. Default: `:32`.
* `XSUNABA_USER`: Set a username to run X11 applications as. Default: `xsunaba`.
* `WIDTH`: Set a custom `Xephyr` display width in pixels. Default: `1024`.
* `HEIGHT`: Set a custom `Xephyr` display height in pixels. Default: `768`.
* `XSUNABA_XEPHYR_PID`: Set the PID of the Xephyr process. Default: None.

#### Alternate and/or Multiple Sandbox Users

To use a different username for your sandbox user or to create multiple sandbox users, follow these steps (replacing `<sandbox_user>` with your desired username):

1. Create the sandbox user:

    ```sh
    doas make install-user XSUNABA_USER=<sandbox_user>
    ```

2. Configure passwordless access for the sandbox user:

    ```sh
    doas make install-doas XSUNABA_USER=<sandbox_user> USER=$USER
    ```

3. Run `Xsunaba` with the custom sandbox user:

    ```sh
    XSUNABA_USER=<sandbox_user> Xsunaba firefox --private-window &
    ```

#### Shared Files

If you want to share some files between your user and the `xsunaba` user, it is suggested that you create a directory owned by the `xsunaba` user and grant group access to it to your user's group (generally the same as your user's name). It is best to only move specific files into and out of this shared directory as needed, not permanently store data in it, as any X11 application run using `Xsunaba` will have access to it.

*IMPORTANT:* This will weaken the security of your sandbox!

#### Audio

By default, X11 applications running in the Xsunaba sandbox will not have access to play or record audio for privacy reasons. To enable audio access, you can copy your `~/.sndio/cookie` file to the `xsunaba` user as described in the ['Authentication' section of sndio(7)](https://man.openbsd.org/sndio#Authentication). This will allow the sandboxed applications to access [sndiod(8)](https://man.openbsd.org/sndiod):

```sh
doas -u xsunaba mkdir -p ~xsunaba/.sndio
doas cp $HOME/.sndio/cookie ~xsunaba/.sndio/
doas chown xsunaba:xsunaba ~xsunaba/.sndio/cookie
doas chmod 600 ~xsunaba/.sndio/cookie
```

## License

Released under the [MIT License](LICENSE) by permission.
