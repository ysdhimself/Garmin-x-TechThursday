---
name: running-garmin-simulator-windows
description: Builds and runs this project's Garmin Connect IQ apps (the touch-grass main app and the demo/motion gesture demo) in the local Connect IQ simulator on Windows, and runs the motion contract tests. Use for Windows local setup, simulator launch, test runs, FIT playback, and Windows-specific SDK troubleshooting. For Linux use running-garmin-simulator instead. Not for implementing Touch Grass features.
compatibility: Windows 10/11 with Garmin's native Connect IQ SDK (installed via SDK Manager), a JDK on PATH, and PowerShell. Verified on Windows 11 with SDK 9.1.0, JDK 17, fenix7 and fenix7s profiles.
---

# Running the Garmin simulator on Windows

## Platform scope

This is the **native Windows** workflow. Check the host OS first; on Linux use the `running-garmin-simulator` skill. No Docker, Nix, `~/.local/bin` launchers, or X11 are involved. Run commands in PowerShell from the repository root (`Garmin-x-TechThursday`), not from `touch-grass/`.

## Check the existing setup

```powershell
$ciq = "$env:APPDATA\Garmin\ConnectIQ"
$sdk = (Get-Content "$ciq\current-sdk.cfg").Trim()   # active SDK folder
Test-Path "$sdk\bin\monkeyc.bat"
Get-ChildItem "$ciq\Devices" -Name | Select-String fenix7
(Get-Command java).Source; java -version
Select-String -Path "$env:APPDATA\Code\User\settings.json" -Pattern monkeyC.developerKeyPath
Get-Process simulator -ErrorAction SilentlyContinue
```

- The SDK lives under `%APPDATA%\Garmin\ConnectIQ\Sdks\`. Resolve the active one through `current-sdk.cfg`; never hardcode a versioned folder (several may be installed).
- Tools are `.bat` / `.exe` in `$sdk\bin`: `monkeyc.bat`, `monkeydo.bat`, `simulator.exe`. They are usually not on PATH; call them by full path.
- Device profiles live in `%APPDATA%\Garmin\ConnectIQ\Devices\<id>\` (`compiler.json`, `simulator.json`).
- The signing key path is whatever VS Code's `monkeyC.developerKeyPath` points to (or `GARMIN_DEVELOPER_KEY`). Reuse it; never print it, copy it into the repo, or commit it.

Read `touch-grass/manifest.xml` and `demo/motion/manifest.xml` and use a device they list. Main app: `fenix7pro`, `fenix7s`. Motion demo: `fenix7`, `fenix7s`.

Ensure build output is git-excluded before writing it: `/.amp/in/` must be in the file from `git rev-parse --git-path info/exclude`. Append only if missing.

## Motion demo (preferred path)

`demo\motion\run-windows.ps1` handles SDK, device check, key lookup, build, simulator start, and launch:

```powershell
powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1              # demo app, fenix7
powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1 -Test        # contract tests
powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1 -Device fenix7s -Key C:\path\to\developer_key
```

Success criteria:
- Build prints `BUILD SUCCESSFUL`, exit 0.
- Tests print `PASSED (passed=1, failed=0, errors=0)` and exit 0 (on Windows the exit code is reliable, unlike the Linux runner).
- Demo: the `monkeydo` process stays attached while the app runs; output `Motion listener registered at 25 Hz` appears each time a LIVE SENSOR attempt starts. Run it in the background and leave it running for the user. It exits (code 0) when the app is closed or replaced — e.g. running tests replaces the demo, so relaunch the demo afterwards.

## Main app (manual commands)

```powershell
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$key = "<path from monkeyC.developerKeyPath>"
$DEVICE = "fenix7s"
New-Item -ItemType Directory -Force .amp\in\build | Out-Null
& "$sdk\bin\monkeyc.bat" -f touch-grass\monkey.jungle -d $DEVICE -o .amp\in\build\touch-grass.prg -y $key
if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) { Start-Process "$sdk\bin\simulator.exe"; Start-Sleep 6 }
& "$sdk\bin\monkeydo.bat" .amp\in\build\touch-grass.prg $DEVICE
```

Require `BUILD SUCCESSFUL` and `$LASTEXITCODE -eq 0` before launching. The main jungle has `base.excludeAnnotations = motion` until Part 1 integration adds the `Sensor` permission; don't remove it just to launch.

## Windows gotchas

- **`monkeydo` test flag is `/t`, not `-t`.** `-t` prints the usage text and exits 1. (`monkeyc` still takes `-t`.)
- **Execution policy:** run scripts with `powershell -ExecutionPolicy Bypass -File ...` rather than changing the machine policy.
- **PowerShell `&&` is unavailable in Windows PowerShell 5.1**; use `; if ($?) { ... }`.
- **Simulator must be running before `monkeydo`.** Start `simulator.exe` and wait a few seconds; reuse an existing `simulator` process rather than starting a second one.
- **Device not found:** open SDK Manager (`%APPDATA%\Garmin\ConnectIQ\` / Start menu "Connect IQ SDK Manager"), have the user sign in and download the device under **Devices**. Never ask for Garmin credentials in chat.
- **`java` not recognized:** install a JDK (17+) and make sure `java` is on PATH; reopen the terminal.
- **No developer key:** only if none exists, generate one via VS Code "Monkey C: Generate a Developer Key" and point `monkeyC.developerKeyPath` at it. Never replace an existing key to fix a build error.

## Driving the motion demo

On the watch: **UP/DOWN** select a mode, **START** begins/cancels, **BACK** cancels or exits.

| Mode | Expected |
| --- | --- |
| DEMO: PETTING | Pass after 5 s |
| DEMO: STILL / BRIEF / GAP | Try again |
| LIVE SENSOR | Depends on sensor data (see below) |

LIVE SENSOR with FIT playback (no container on Windows, so load files directly from the repo):

1. Simulator → **Simulation → Activity Data**.
2. **FIT/GPX Playable File** → **Load File** → `demo\motion\fixtures\petting.fit`.
3. Press the **bottom-left ▶ Play** button (not the Data Field Timer's Start).
4. On the watch choose **LIVE SENSOR**, press **START** → expected pass. `still.fit` → expected retry.

`Samples: 0` / **NO SENSOR DATA** means playback isn't running, not that the gesture failed. End-to-end FIT playback pass/fail has not yet been verified on Windows; report what is actually observed.

## Verify and report

Take a screenshot of the simulator window if a screenshot tool is available and inspect it against the expected screen; otherwise say the screen was not visually verified and ask the user to confirm. Report the build result, test summary, observed screen, and any blocker. Leave the simulator running.
