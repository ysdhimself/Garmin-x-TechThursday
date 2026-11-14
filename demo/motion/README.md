# Five-second grass-touch gesture

This is Part 4 of `PROJECT_PLAN.md`: an accelerometer-only, on-watch motion
challenge plus a standalone test app. It does **not** identify grass or prove
physical contact. Repeated walking, waving, or other similar movements may pass.
No gyro, network, GPS, or machine-learning model is needed for this slice.

## Run

Use the repository's `running-garmin-simulator` skill for Linux SDK setup.
Reuse the installed SDK, simulator, and private developer key. These commands
run from the repository root; choose `fenix7` once its device profile is installed.
Only `fenix7s` is installed on the current development machine.

```sh
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"
DEVICE=fenix7s
mkdir -p .amp/in/build
monkeyc -f demo/motion/monkey.jungle -d "$DEVICE" \
  -o .amp/in/build/motion-demo.prg \
  -y "$HOME/.Garmin/ConnectIQ/developer_key.der"
# Start connectiq if the simulator is not already running, then:
monkeydo .amp/in/build/motion-demo.prg "$DEVICE"
```

Keep `/.amp/in/` in the repository-local exclude file. Never commit the signing
key. Windows/macOS users should use Garmin's native SDK tools and their own key
path rather than these Linux-specific paths.

**UP/DOWN** selects a mode. **START** begins or cancels; **BACK** cancels a
running attempt, otherwise exits. Each attempt allows five seconds of input
plus one second for callback delivery. Mode changes, view hiding, inactivity,
and exit cancel sampling and timers. Cancelled attempts do not emit a result.

| Mode | Input | Expected result |
| --- | --- | --- |
| LIVE SENSOR | One-second accelerometer batches, up to 25 Hz | Depends on actual sensor input |
| DEMO: PETTING | 1.25 Hz, 300 millig sine wave for five seconds | Pass |
| DEMO: STILL | Gravity only | Retry |
| DEMO: BRIEF | One second of movement, then stillness | Retry |
| DEMO: GAP | Petting with the third batch omitted | Retry |

The demo feeds generated x/y/z samples into the **same detector** as the live
callback. It never sets success directly. Synthetic modes never register a
sensor listener. Simulator random sensor data is not a real wrist recording.

### Deterministic FIT files

`demo/motion/fixtures/petting.fit` contains two minutes of synthetic petting:
25 Hz, a 1.25 Hz sine wave of ±300 millig on X, zero on Y, and 1000 millig
gravity on Z. `still.fit` contains gravity only as a negative control. Each
contains 3000 accelerometer samples, using the signed compressed calibrated
fields used by Garmin's bundled PitchCounter FIT sample. These are synthetic
test inputs, not wrist recordings or evidence of grass contact.

1. Open **Simulation → Activity Data**.
2. Choose **FIT/GPX Playable File**, then **Load File** and select `petting.fit`.
3. Press the bottom-left **▶ Play** button (not the data-field timer's Start).
4. Return to the watch, choose **LIVE SENSOR**, then press watch **START**.
   Expected: samples arrive and five seconds of motion pass.
5. Load `still.fit`, start playback, then start a fresh watch attempt.
   Expected: samples arrive but the challenge retries.

The Linux compatibility container only mounts `~/.Garmin`, not the repository
or the rest of your home directory. Copy the fixtures there before browsing:

```sh
mkdir -p "$HOME/.Garmin/motion-fixtures"
cp demo/motion/fixtures/*.fit "$HOME/.Garmin/motion-fixtures/"
```

In the picker, **Ctrl+L** allows an absolute path such as
`/home/matthew_hre/.Garmin/motion-fixtures/petting.fit`; hidden directories may
not appear in the normal file listing. Local convenience copies also exist at
`~/petting.fit` and `~/still.fit`, but those are outside the container mount.
Restart playback from the beginning or reload the file when its two minutes
end. Restart the watch attempt after changing sources.

Regenerate the checked-in files from the repository root with
`uv run demo/motion/fixtures/generate.py`. The dependency is pinned in the
script; no project-wide Python installation is needed. Regeneration uses a
fixed timestamp and produces identical bytes. Both files passed independent
Garmin FIT SDK checksum and decoded-sample checks. End-to-end simulator
playback of these files has **not yet been verified**.

### LIVE SENSOR in the simulator

The simulator's data playback and the watch's challenge are separate controls:

1. Open **Simulation → Activity Data**.
2. Select **Data Simulation** in the **Data Source** dropdown.
3. Press the black **▶ Play** button at the **bottom left** of that window.
   The **Start** button under **Data Field Timer Controls** is not playback.
   If the bottom-left button already shows **Ⅱ**, playback is running.
4. Leave playback running, return to the watch, select **LIVE SENSOR**, and
   press the watch's **START** button for a fresh attempt.

The live screen now shows a **Samples** counter during and after an attempt.
Zero samples produces **NO SENSOR DATA / Check sensor source**, not a claim
that your hand movement failed. A nonzero count with **TRY AGAIN** means input
arrived but did not meet the gesture check. Random simulator data is not
expected to pass; use **DEMO: PETTING** to exercise repeatable success.

On this setup, a live attempt received **150 samples** while Data Simulation
was playing, and another received **0 samples** with no input. Both diagnostic
results were inspected in the simulator. The initial setup instructions
omitted the separate Play step. No detector thresholds were relaxed to make
random input pass.

## Detector and integration

`touch-grass/source/motion/GrassMotionDetector.mc` accepts
`addBatch(x, y, z, sampleRate, elapsedMs)`. Arrays contain millig values; elapsed
time is monotonic milliseconds since Start. Batches must be fresh and roughly
one second long (0.8–1.2 seconds), with at most 250 ms of delivery jitter.
Compressed/duplicate delivery and gaps invalidate the attempt. `getProgress()`
returns accepted movement seconds; `passed(elapsedMs)` cannot pass before five
real seconds. A new detector is required for every attempt.

For each batch it selects the axis with the largest excursion, then requires
180–1800 millig of swing and 1–5 direction reversals with 90 millig hysteresis.
Constant gravity, small noise, a one-way tilt, and the tested hard/rapid shakes
do not qualify. Thresholds are named constants for tuning with real watch data.
This is a demo heuristic, not a validated gesture classifier. It retains only
small counters, never a raw-sample history.

`GrassMotionChallenge` owns sensor registration, monotonic timing, and cleanup:

```monkeyc
var challenge = new GrassMotionChallenge();
challenge.start(method(:onMotionProgress), method(:onMotionResult));
// onMotionProgress(seconds): 0.0–5.0 accepted motion seconds
// onMotionResult(passed): one Boolean result, including failure on missing input
// On cancel, view hide, app inactivity, or app stop:
challenge.cancel();
```

Part 1 integration requires the `Sensor` permission in the **main** manifest
and removal of `base.excludeAnnotations = motion` from its `monkey.jungle`.
That temporary exclusion keeps the unchanged starter build working until it
owns sensor permission and calls this module from its arrival/Start screen.
No main views or main manifest were changed. Keep the scenario generator and
test/demo UI out of the production build.

## Deterministic tests

```sh
monkeyc -f demo/motion/monkey.jungle -d fenix7s -t \
  -o .amp/in/build/motion-tests.prg \
  -y "$HOME/.Garmin/ConnectIQ/developer_key.der"
monkeydo .amp/in/build/motion-tests.prg fenix7s -t
```

The single contract test covers successful movement on all three axes,
no early success, stillness, brief motion, missing/no input, accelerated
delivery, noise, one-way movement, and violent/rapid shaking. With SDK 9.3.0
on this Linux setup, the runner reports `PASSED (passed=1, failed=0, errors=0)`
but exits with status 1 even on that successful run; inspect the test summary
rather than interpreting that exit status as a clean automated check.

## Verification and limits

Verified locally with Connect IQ SDK 9.3.0 and the fēnix 7S API 5.2.0 profile:

- Main starter and standalone demo compile successfully.
- Monkey C contract test reports one pass, zero failures/errors (runner exit
  limitation above).
- Visible petting progress and success, stillness/brief/gap retries, and live
  cancellation were exercised. A subsequent petting attempt succeeds again.
- The live sensor listener registered at 25 Hz; this does not prove gesture
  accuracy or real-device sampling reliability.

The original fēnix 7 profile/build, physical-watch calibration, lifecycle events
generated by a real watch, raw-sensor FIT playback, and the main walking-flow
integration remain unverified. Test the watch while stopped, waving the
watch-wearing hand gently back and forth like petting a dog, before tuning
thresholds or presenting this as hardware-tested.
