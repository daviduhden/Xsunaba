# Xsunaba

## Overview

Xsunaba is a utility that runs X11 (or simply X) applications within a basic sandbox (derived from the Japanese word “sunaba”) to limit access to your files and X11 events (notably keyboard input). The sandbox is composed of two main parts:

1. A separate local user account under which the X11 application runs, helping to restrict access to your personal files (assuming the proper permissions are in place).
2. A separate X session, created and rendered in a window within your active X display using `Xephyr`. This prevents the sandboxed X application from monitoring X11 events in your parent X session and display.

**IMPORTANT:** This setup does not guarantee that access is entirely blocked outside of the sandbox user and display, but it does provide a marginal increase in security.

Xsunaba is based on [a script by Milosz Galazka](https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/) (see the [Internet Archive Wayback Machine](https://web.archive.org/web/20210115000000*/https://blog.sleeplessbeastie.eu/2013/07/19/how-to-create-browser-sandbox/)) and has been ported to [OpenBSD](http://www.openbsd.org/).

For OpenBSD users, certain X11 applications in the ports tree also utilize [pledge(2)](https://man.openbsd.org/pledge) and [unveil(2)](https://man.openbsd.org/unveil) to further restrict filesystem access.

## Prerequisites

- [OpenBSD](https://www.openbsd.org/faq/faq4.html#Download)
- X11 (ideally running [xenodm(1)](https://man.openbsd.org/xenodm))
- [doas(1)](https://man.openbsd.org/doas)
- [Xephyr(1)](https://man.openbsd.org/Xephyr)
- [xauth(1)](https://man.openbsd.org/xauth)
- [openssl(1)](https://man.openbsd.org/openssl)

### Optional

- [sndio(7)](https://man.openbsd.org/sndio)

## Usage

1. To install Xsunaba, create the `xsunaba` user and update your `/etc/doas.conf` to allow your user to run applications within the sandbox without entering a password:

    ```sh
    doas make install USER="$USER"
    ```

2. If you do not already have an `/etc/doas.conf`, one will be created for you. If you are running `make install` as `root`, you must explicitly specify your username (replace `<username>` with your actual username):

    ```sh
    doas make install USER=<username>
    ```

3. To run an X11 application in the sandbox, prefix your command with `Xsunaba`. For example:

    ```sh
    Xsunaba chrome --incognito &
    Xsunaba firefox --private-window &
    ```

> **Note:** Xsunaba automatically applies window geometry adjustments to ensure the `Xephyr` display fits properly for applications like `chrome` and `firefox`.

### Advanced Usage

You can customize Xsunaba's behavior by setting the following environment variables:

- **VERBOSE:** Set to `true` for verbose output. *(Default: `false`)*
- **XSUNABA_DISPLAY:** Specify a custom display number (including the leading colon) to use when starting Xephyr. *(Default: `:32`)*
- **XSUNABA_USER:** Define the username under which X11 applications will run. *(Default: `xsunaba`)*
- **WIDTH:** Set a custom width (in pixels) for the Xephyr display. *(Default: `1024`)*
- **HEIGHT:** Set a custom height (in pixels) for the Xephyr display. *(Default: `768`)*
- **XSUNABA_XEPHYR_PID:** Optionally set the PID of the Xephyr process. *(Default: None)*

#### Alternate and/or Multiple Sandbox Users

If you wish to use a different username for the sandbox or create multiple sandbox users, follow these steps (replace `<sandbox_user>` with your desired username):

1. Create the sandbox user:

    ```sh
    doas make install-user XSUNABA_USER=<sandbox_user>
    ```

2. Configure passwordless access for the sandbox user:

    ```sh
    doas make install-doas XSUNABA_USER=<sandbox_user> USER=$USER
    ```

3. Run Xsunaba with the custom sandbox user:

    ```sh
    XSUNABA_USER=<sandbox_user> Xsunaba firefox --private-window &
    ```

#### Shared Files

If you need to share files between your main user and the `xsunaba` user, it is recommended to create a directory owned by the `xsunaba` user and grant group access to your primary user (typically the same as your username). However, it is advisable to move only specific files into and out of this shared directory when necessary rather than using it for permanent storage, as any X11 application run through Xsunaba will have access to it.

> **IMPORTANT:** Enabling shared file access can weaken the security provided by the sandbox.

#### Audio

By default, X11 applications running in the Xsunaba sandbox do not have access to play or record audio, in order to preserve privacy. If you wish to enable audio, copy your `~/.sndio/cookie` file to the `xsunaba` user following the instructions in the [Authentication section of sndio(7)](https://man.openbsd.org/sndio#Authentication). This allows sandboxed applications to access [sndiod(8)](https://man.openbsd.org/sndiod):

```sh
doas -u xsunaba mkdir -p ~xsunaba/.sndio
doas cp $HOME/.sndio/cookie ~xsunaba/.sndio/
doas chown xsunaba:xsunaba ~xsunaba/.sndio/cookie
doas chmod 600 ~xsunaba/.sndio/cookie
```

## License

Xsunaba is released under the [MIT License](LICENSE) by permission.