---
name: running-garmin-simulator
description: Builds and runs this project's Garmin watch app in the local Connect IQ simulator on Linux. Use for Linux local setup, simulator launch or debugging, and Garmin SDK troubleshooting. Windows users need Garmin's separate Windows setup process. Not for implementing the planned Touch Grass features.
compatibility: Linux desktop only; verified on Debian 13 with Docker, an X11-compatible graphical session, and a machine-local Garmin SDK installation. Not a Windows or macOS setup guide.
---

# Running the Garmin simulator on Linux

## Platform scope

This skill documents a **Linux-only workflow**, verified on Debian 13. Check the host operating system before running its commands. The Bash commands, filesystem paths, Nix installation, Docker compatibility image, and X11 screenshot steps below are not Windows instructions. The project itself is not Linux-only.

**Windows users follow a different process:** use Garmin's native Windows SDK Manager and the Windows instructions in Garmin's [getting-started guide](https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/) and [command-line setup guide](https://developer.garmin.com/connect-iq/reference-guides/monkey-c-command-line-setup/), or the Garmin Monkey C extension for Visual Studio Code. On Windows, direct the session to those instructions instead of executing this skill's Linux workflow. The Linux compatibility container and local launchers described here are not prerequisites for Windows. Windows and macOS setup have not been verified by this skill.

Run this workflow on the user's Linux desktop, from the repository root. The installed SDK, device profiles, signing key, Docker image, and graphical session belong to that machine; a fresh cloud checkout does not contain them. This is a Monkey C watch app, not a web app. No Node server is needed to run the starter.

## Check the existing setup

Read `touch-grass/manifest.xml` and `touch-grass/monkey.jungle` before building. Use a device listed in the current manifest. The verified starter target is `fenix7s` (fēnix 7S); `PROJECT_PLAN.md` proposes `fenix7`, but that plan is not the build configuration. Do not change the target just to launch the simulator.

```bash
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"
command -v java monkeyc monkeydo connectiq garmin-sdk-manager
java -version
monkeyc --version
cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg"
printf 'DISPLAY=%s\n' "$DISPLAY"
docker image inspect garmin-connectiq-local --format '{{.Id}}'
```

The working local installation uses Java 21 and Connect IQ SDK 9.3.0. Resolve the active SDK through `current-sdk.cfg` rather than hardcoding its versioned directory.

- `~/.local/bin/monkeyc` and `monkeydo` invoke the active SDK with host Java.
- `~/.local/bin/connectiq` runs the simulator in the `garmin-connectiq-local` Ubuntu 22.04 Docker image. It shares `~/.Garmin`, the X11 socket, and host networking so host `monkeydo` can reach the simulator on TCP port 1234.
- `~/.local/bin/garmin-sdk-manager` opens Garmin's SDK Manager through the same image.
- `~/.local/share/garmin/Dockerfile` contains the compatibility image recipe. The SDK Manager files are in `~/.local/share/garmin/sdk-manager/`.
- `~/.Garmin/ConnectIQ/developer_key.der` is the existing private signing key. Reuse it without displaying its contents or copying it into the repository.

These launchers are machine-local, not files supplied by this repository. Inspect them when diagnosing setup differences. Reuse the installed environment instead of reinstalling it on each run.

## Build and launch

Ensure `/.amp/in/` is in the repository-local Git exclude file before writing outputs there. Find that file with `git rev-parse --git-path info/exclude` and preserve its existing rules.

Set `DEVICE` to the chosen manifest target. For the current app:

```bash
DEVICE=fenix7s
SDK="$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")"
test -f "$HOME/.Garmin/ConnectIQ/Devices/$DEVICE/compiler.json"
test -f "$HOME/.Garmin/ConnectIQ/Devices/$DEVICE/simulator.json"
test -f "$HOME/.Garmin/ConnectIQ/developer_key.der"
mkdir -p .amp/in/build .amp/in/artifacts
monkeyc -f touch-grass/monkey.jungle -d "$DEVICE" \
  -o .amp/in/build/touch-grass.prg \
  -y "$HOME/.Garmin/ConnectIQ/developer_key.der"
```

Require `BUILD SUCCESSFUL` and exit code 0 before loading the program. Preserve compiler errors if the current source no longer builds.

Check `ss -ltnp | grep ':1234'` and, when available, `xwininfo -root -tree` for an existing `CIQ Simulator` window. Reuse a running simulator. If none is running, launch `connectiq` with the shell tool's background-process support and leave it running. Check its output and listener before continuing; a missing graphical session is not a reason to claim a visible launch succeeded.

Then run:

```bash
monkeydo .amp/in/build/touch-grass.prg "$DEVICE"
```

Each shell invocation has its own variables; set `DEVICE` again if needed. `monkeydo` can remain attached while the app runs. A background process that remains running is not itself a failure or proof of success. Read its output and inspect the simulator.

## Verify the visible app

On this desktop, `xwininfo -root -tree` lists the simulator's current window ID and device title. Capture that specific window, not the whole desktop:

```bash
import -window WINDOW_ID .amp/in/artifacts/simulator-running.png
```

Replace `WINDOW_ID` with the ID from the current window list. Inspect the capture with `view_media`, stating the screen expected from the current app source. Use an available desktop screenshot tool if ImageMagick `import` is unavailable. A screenshot saved without inspection is not verification.

The app opens on a placeholder flow screen showing `1/6` and `Passive`; START advances through the six flow states and wraps back to `Passive`. On `You proved it`, START first runs a 2.5-second fake touch challenge (the accelerometer is not used yet); press START again once it shows `All done!`. The planned map, route, and gesture flow is not implemented yet. If the code changes, verify its actual expected screen instead.

Report the build result, observed screen, and any remaining blocker. Include the inspected screenshot in the handoff and leave the simulator running for the user.

## Recover missing prerequisites

- **Invalid device ID or missing profile:** Open `garmin-sdk-manager`. Ask the user to sign in in Garmin's window and download the selected device under **Devices**. Installing the SDK alone does not install device profiles. Check the profile files again before rebuilding; do not ask for credentials in chat.
- **Missing active SDK:** Use SDK Manager to install an SDK and select **Use as SDK**, then reread `current-sdk.cfg`.
- **Missing Java:** On this machine, Java was installed with `nix profile add nixpkgs#jdk21_headless`. Check the existing Nix profile before adding it again.
- **Missing signing key:** Only if the key does not already exist, generate an RSA 4096-bit private key in DER/PKCS#8 format outside the repository with restrictive permissions. Never replace an existing key to fix a build error.
- **Missing launchers or Docker image:** The prior setup is not present in this environment. Consult Garmin's [SDK download](https://developer.garmin.com/connect-iq/sdk/) and [command-line setup](https://developer.garmin.com/connect-iq/reference-guides/monkey-c-command-line-setup/) instructions. If the local Dockerfile remains, rebuild with `docker build -t garmin-connectiq-local "$HOME/.local/share/garmin"`.
- **Missing Linux shared libraries:** Debian 13 lacks the older `libwebkit2gtk-4.0.so.37`, `libjavascriptcoregtk-4.0.so.18`, and `libjpeg.so.8` required by Garmin's Linux desktop binaries. Use the Ubuntu compatibility image rather than launching the raw host simulator or replacing Debian system libraries. Its verified package list is `ca-certificates libcurl4 libwebkit2gtk-4.0-37 libjpeg8 libsecret-1-0 libsm6 libxext6 libusb-1.0-0 libasound2 fonts-dejavu-core`. `libcurl4` is also required by SDK Manager.
- **Simulator starts but `monkeydo` cannot connect:** Check port 1234 and the installed `connectiq` launcher's networking. The verified launcher uses `--network host`. Inspect the error before restarting anything; do not stop unrelated containers or the user's simulator session blindly.
