# Simulated walk: Activity Data for the fēnix 7

Synthetic **Activity Data** for the Connect IQ simulator, so the whole Touch Grass flow can be run without a real
walk: sit still → get up → walk to the green space → stand on the grass (→ wave). These are generated test inputs,
not wrist recordings, and they do not show that anyone touched grass.

All tracks follow `fixtures/route-edmonton.json`: a real walk plan from the backend's live mode (JEV + FOSSGIS
foot routing) from the plan's example origin in downtown Edmonton to the **ICE District Fan Park**, 69 m / about 49 s.

## Files

| File | Length | What happens | Expected on the watch |
| --- | --- | --- | --- |
| `touch-grass-full.fit` | 145 s | Sit 60 s → walk the route → stand 30 s at the entry; "petting" motion in standing seconds 10–19 | Invitation, walk, arrival, wave passes, stamp |
| `arrive-no-wave.fit` | 145 s | Same walk, but no hand motion while standing | Arrival; the wave check asks to retry |
| `walk-stops-short.fit` | 96 s | Sit 20 s → walk, then stop about 40 m (straight line) before the entry and stay | Never arrives (25 m radius) |
| `walk-off-route.fit` | 192 s | Sit 20 s → walk; at the route's midpoint, walk out to a spot ~60 m from the route and back, then arrive | Off-route warning, then arrival |
| `route-edmonton.json` | | The walk plan the tracks follow (`WalkPlan` contract) | Map shapes match the simulated GPS |

Every second has one FIT `Record` and one `AccelerometerData` message (25 samples, signed millig, the same fields as
`demo/motion`). Record fields: position, speed, distance, heart rate, cadence, cumulative strides (`total_cycles`;
steps = 2 × strides), cumulative calories, altitude, absolute air pressure and temperature.

| Phase | Speed | Heart rate | Cadence / steps | Calories | Temperature | Accelerometer |
| --- | --- | --- | --- | --- | --- | --- |
| Sit | 0 | ~68 bpm | 0 | ~1.3 kcal/min | 22 °C (indoors) | Gravity only (Z = 1000 millig) |
| Walk | 1.4 m/s | rises to ~95 bpm | 53 strides/min (~106 steps/min); 96 steps on the full walk | ~4 kcal/min | cools toward 6 °C | Gravity only (no arm swing, so walking can't pass the wave check) |
| Stand | 0, with sub-metre GPS wobble | settles to ~85 bpm | 0 | ~1.6 kcal/min | 10 °C by the end | Gravity, plus 10 s of `demo/motion`'s petting signal (1.25 Hz, ±300 millig on X) in `touch-grass-full` only |

Altitude undulates ±1.5 m around 668 m (downtown Edmonton), and air pressure follows it through the standard
barometric formula (~935 hPa). FIT activity records have no compass field, so heading is not in the files; Walk
Monitor uses the compass if the simulator provides one, otherwise the direction of travel from GPS.

## See the live data: Walk Monitor

The simulator does not display activity data by itself; an app has to read and draw it. `demo/walk/` includes a
small test app, **Walk Monitor**, that shows what the watch receives while a file plays. **UP/DOWN** switches
between two pages:

```
Page 1: WALK                                  Page 2: SENSORS
WALK  #57 PAS     ← updates + data channels    SENSORS
GPS GOOD          ← NO FIX/POOR/USABLE/GOOD     95               ← heart rate (bpm)
53.546231  -113.493941                          HR bpm   +27 vs sitting
TO GREEN SPACE                                  STEPS 64   CAD 53
 ▲  23 m          ← arrow points to the park   KCAL 3   HEAD 312°
1.4 m/s   walked 46 m                           ALT 669 m   935.4 hPa
WALKING           ← STOPPED/OFF ROUTE/ARRIVED   TEMP 14 C
```

- **ARRIVED** needs 3 consecutive usable/good fixes inside the 25 m radius (the project's arrival rule), and stays on
  once reached. **OFF ROUTE** shows when the position is more than 30 m from the route.
- The **arrow** points to the park relative to the way you face: compass heading if available, otherwise the
  direction of travel from GPS.
- **HR change** = highest heart rate since the walk started minus the average while still before it.
- **Steps** come from the watch's step counter when it changes; otherwise they are estimated from GPS distance
  (0.7 m per step) and shown with `~`. **KCAL** counts from when the app started.
- Any reading the simulator or watch doesn't provide shows `--`.
- The letters after the update count show which channel delivered data: **E** position events, **P** polled
  position, **A** activity info, **S** sensor info. They are there to find out how the simulator feeds FIT playback.

Press **START/SELECT** to reset the counters before playing the next file.

```powershell
# Build + launch Walk Monitor in the simulator (fenix7 by default; same key lookup as demo\motion)
powershell -ExecutionPolicy Bypass -File demo\walk\run-windows.ps1
```

Expected per file:

| File | What you should see |
| --- | --- |
| `touch-grass-full.fit` | STOPPED for 60 s at ~57 m, WALKING with the distance falling, then ARRIVED |
| `arrive-no-wave.fit` | Same as full (the motion difference shows in the motion demo, not here) |
| `walk-stops-short.fit` | Walks, then STOPPED at ~40 m; never ARRIVED |
| `walk-off-route.fit` | OFF ROUTE up to ~60 m mid-walk, then back on route and ARRIVED |

Walk Monitor is a test tool. It is not the Touch Grass app, and it reads the route from `fixtures/route-edmonton.json`
as a `jsonData` resource, the same way Part 1 can bundle a plan.

## Play it in the simulator (Windows)

1. Start the simulator with an app on `fenix7`: Walk Monitor (above), `demo\motion\run-windows.ps1`, or Part 1's app.
2. **Simulation → Activity Data**.
3. Choose **FIT/GPX Playable File**, then **Load File**, and pick a `.fit` from `demo\walk\fixtures\`.
4. Press the bottom-left **▶ Play** button (not the data-field timer's Start). Position, speed and heart rate now
   follow the file in real time. Reload the file to start again from the beginning.
5. FIT playback does not drive `ActivityMonitor`. To fake "you've been sitting too long" for the invitation, set
   **Settings → Activity Monitor → Move Bar Level** (0–5) by hand.

To try the wave check during the standing phase, run the motion demo's **LIVE SENSOR** mode
(see `demo/motion/README.md`) and press START during standing seconds 10–19 of `touch-grass-full.fit`.

## Serve the matching walk plan

So that the route on the watch is the same one the FIT file walks, point the backend's fixture mode at the plan in
`backend/.env`:

```
ROUTING_MODE=fixture
FIXTURE_FILE=demo/walk/fixtures/route-edmonton.json
```

Then `node backend/scripts/dev-server.ts`, and `POST /walk-plan` with
`{"originLatE6":53546000,"originLonE6":-113493800,"maxWalkS":120}` returns this plan (labelled `source: "fixture"`).

Or bundle it in the watch app as a JSON resource (Part 1):

```xml
<jsonData id="mockPlan" filename="route-edmonton.json"/>
```

```monkeyc
var plan = WatchUi.loadResource(Rez.JsonData.mockPlan) as Dictionary;
```

## Regenerate

From the repository root:

```sh
uv run demo/walk/fixtures/generate.py
```

The `fit-tool==0.9.17` dependency is pinned in the script, as in `demo/motion`. Without `uv`:
`python -m venv .venv && .venv\Scripts\pip install fit-tool==0.9.17 && .venv\Scripts\python demo\walk\fixtures\generate.py`
(keep the venv outside the repo, or delete it afterwards).

Generation uses a fixed start time (2026-11-17 15:00 UTC) and no randomness, so it produces identical bytes. To walk
a different route, replace `route-edmonton.json` with another `WalkPlan` and regenerate.

## Verification and limits

Checked by decoding every file back with fit-tool:
- timestamps step exactly 1 s, and speed never exceeds 1.5 m/s;
- every track starts at the plan origin;
- the full, no-wave and off-route tracks end within 1 m of the entry;
- stops-short gets no closer than 39.4 m;
- the off-route detour reaches 60.5 m from the route, and the other tracks stay on it;
- 25 accelerometer samples per second, with petting only after arrival in `touch-grass-full`;
- heart rate stays in 66–97 bpm;
- `touch-grass-full`: 96 steps, 5 kcal cumulative, altitude 668.0–669.6 m, pressure 935.4–935.5 hPa,
  temperature 22 °C → 10 °C, cadence 0 when still and 53 strides/min walking;
- regenerating gives identical bytes;
- `route-edmonton.json` passes the backend's `validatePlan`.

Walk Monitor compiles for `fenix7` with SDK 9.1.0 (`BUILD SUCCESSFUL`).

**Not yet verified:** playback of these files in the Connect IQ simulator, and what Walk Monitor shows during it. The GPS is perfect apart from a small
standing wobble, so poor or missing fixes are not covered here; use `backend/fixtures/routes/demo-park.gps.json` from code for
those. The heart rate, cadence and motion values are plausible stand-ins, not measurements.
