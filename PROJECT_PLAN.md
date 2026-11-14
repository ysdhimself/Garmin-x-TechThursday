# Touch Grass: Department of Outdoor Affairs

Build a fēnix 7 app that says **go walk**, shows a **green-space map and short pedestrian route**, and asks the user to **wave their watch-wearing hand for five seconds to "touch grass."**

**MVP:** invitation, map, walk, arrival, hand-motion challenge, completion stamp. Photo verification and a phone website are stretch goals, not prerequisites.

**Architecture rule: the watch is a Monkey C client, never an HTTP server.** A separate computer/cloud service handles green-space discovery and routing. The watch renders a small map payload and runs the walk/challenge locally. No Node.js, web server, image model, browser, database, or inbound socket belongs on the watch.

## Claim one of four parallel parts

| Part | Workstream | Owner | Status | Primary files |
| --- | --- | --- | --- | --- |
| 1 | Watch app, map UI, and walking flow | Unassigned | Not started | `touch-grass/`, except Part 4's paths |
| 2 | Green-space data and pedestrian routing | Unassigned | Not started | `backend/src/routing/`, `fixtures/routes/` |
| 3 | Off-watch HTTPS service and compact payloads | Unassigned | Not started | Rest of `backend/` |
| 4 | Hand-motion challenge and simulator scenarios | Unassigned | Not started | `touch-grass/source/motion/`, `touch-grass/tests/motion/`, `fixtures/motion/`, `demo/` |

Part 1 owns the watch manifest, build configuration, views, app lifecycle, GPS, and web client. Part 4 owns the motion module; Part 1 calls it through the interface below. Part 3 owns backend startup and dependencies; Part 2 owns the routing module and coordinates dependency additions with Part 3. Coordinate changes to this plan and the root README. Keep the repository file as the source of truth for assignments.

## The experience

1. Open the app. An inactivity signal or explicit demo action triggers: **"Your outdoor privileges are about to expire."** The user accepts a grass break and consents to sharing their location for routing.
2. Get a GPS fix and fetch a short walking plan. Show nearby green-space shapes, the chosen destination, the pedestrian route, and the user's position.
3. Walk toward the destination: **"Proceed to the designated touching area."** Show remaining route distance and an approximate walking time.
4. With a recent, usable GPS fix inside the arrival radius, offer: **"Grass proximity established. Wave your hand to touch grass."** The user stops walking and presses Start.
5. Detect sustained gentle movement of the watch-wearing hand across five seconds. Stillness or insufficient movement allows a retry.
6. Award **"GRASS TOUCHED. Your humanity has been renewed."** Show a local receipt with time/distance and an optional bearing/distance back to the start. A bearing is not turn-by-turn return navigation.

The joke is a ceremonial motion check. GPS does not prove literal grass contact, and an accelerometer cannot identify grass. Never describe this as verified physical contact.

## fēnix 7 constraints and feasibility audit

These findings were checked against Garmin's published device reference and API documentation on 2026-11-14. They establish documented API support, not a tested implementation. The repository contains a starter watch app in `touch-grass/`, but no implemented Touch Grass flow or backend. The incoming scaffold targets `fenix7s` with minimum API 5.2.0 and no permissions; Part 1 must align it with the original `fenix7` target and permissions below. No Garmin SDK is installed in this planning environment.

| Area | Verified platform fact | Decision for this project |
| --- | --- | --- |
| Exact target | Original `fenix7`: round 260 × 260, 64 colors, touch and five buttons [1] | Build a Device App, not a watch face or data field; support physical buttons first |
| App memory | Watch App limit: **786,432 bytes (768 KiB)**; background limit: 65,536 bytes [1] | Small vector map and bounded arrays; measure peak runtime memory, not just `.prg` size |
| Networking | `Communications.makeWebRequest()` is an asynchronous client API; Garmin provides high-level communications rather than raw phone-link sockets [2, 3] | Only outbound HTTPS requests to an off-watch service; no server, WebSocket, or push dependency |
| Connection | Web requests support a mobile Bluetooth connection or Wi-Fi [2] | Plan for a paired phone running Garmin Connect on real hardware; do not assume Wi-Fi hardware means an always-on connection. Validate simulator networking separately |
| API versions | fēnix 7 is currently listed at API 5.2; newer SDK APIs may require 6.x [2, 4] | Use a conservative API 4.0 baseline and compile for `fenix7`; avoid 6.x-only `:body` and string Content-Type options |
| GPS | `Position.enableLocationEvents()` supports continuous fixes; `Info.accuracy` is a **quality enum**, not metres [5] | Require `QUALITY_USABLE` or `QUALITY_GOOD`, non-null position, and recent updates. Do not invent an `accuracyM` field |
| Maps | fēnix 7 is in `WatchUi.MapView`'s supported-device list; it can display markers and a polyline [6] | Native maps are possible, but the MVP uses its own small vector map so it does not depend on installed basemap coverage in the simulator |
| Motion | fēnix 7 is in `Sensor.registerSensorDataListener()`'s supported-device list [7] | Use accelerometer batches locally; no need for gyro, heart rate, Pulse Ox, or extra sensors |
| Five-second challenge | Sensor batch `:period` is in seconds and has a **four-second maximum** [7] | Request one-second batches, initially at 25 Hz if supported; aggregate five seconds. Never request `:period => 5` or `5000` |
| Background reminders | Temporal background events have a minimum five-minute spacing; waking an app requests user confirmation [8] | Manual launch/foreground invitation is MVP. A genuine all-day inactivity reminder is stretch scope, not an always-running sensor loop |
| Simulator input | Garmin documents random sensor simulation and FIT playback; logged accelerometer data can be replayed [9] | Test the exact SDK and file. A normal GPS activity FIT/GPX is not evidence that raw accelerometer samples are present |

### Keep the device workload small

- Manifest target: `fenix7`; app type `watch-app`. Required MVP permissions: `Positioning`, `Sensor`, and `Communications`. Do not request `Background` unless implementing the stretch reminder.
- Use the `makeWebRequest()` parameters dictionary, `REQUEST_CONTENT_TYPE_JSON`, and `HTTP_RESPONSE_CONTENT_TYPE_JSON`. The backend must return `application/json`, including errors. Do not copy newer `:body` examples into this target.
- Fetch the walking plan once. Keep invitation, arrival, challenge, and completion state on-watch. **No mission service, pairing codes, status polling, or completion round trip is needed for the MVP.**
- Keep one request in flight. On network loss, offer retry or an explicitly selected bundled demo plan; never silently substitute a different route. A loaded plan remains usable offline.
- Refresh a simple north-up map on position updates, not at animation frame rate. Draw green-space polygons, route, current position, and destination with `Graphics.Dc`. Label it a simplified map; it is not a downloaded street basemap.
- Show remaining distance along the route, not just straight-line distance. An off-route user gets a clear warning, not an invented path. Keep location math in appropriate precision; use integer microdegrees on the wire.
- Turn GPS off after arrival unless needed for the return view. Enable high-frequency accelerometer sampling only during the challenge and unregister afterward. Cancel/restart the challenge if the app becomes inactive; do not count missing samples as successful motion.

## Part 1: Watch app, map UI, and walking flow

**Goal:** Own the complete fēnix 7 experience except the motion algorithm.

- [ ] Adapt the existing `touch-grass/` Monkey C Device App to target `fenix7`, with the API baseline and permissions above. Document SDK/device-profile installation, build, and simulator launch commands; do not commit private signing keys.
- [ ] Build an invitation using `ActivityMonitor.getInfo().moveBarLevel` when available, or foreground step deltas over elapsed time. Handle missing data and midnight resets. Include a labeled demo trigger and manual Start; inactivity is not sitting detection.
- [ ] Use continuous `Position` events while navigating. Gate route requests and arrival on position quality, non-null coordinates, and recent receipt of a usable fix. An initial ten-second freshness threshold is a project choice, not a device accuracy guarantee.
- [ ] Implement one outbound JSON request for the compact walking plan below. Handle timeouts, malformed/oversized payloads, and retry without changing to the arrival state.
- [ ] Render the green-space polygons and walking route from the shared fixture. Show the current marker, destination, remaining route distance, and estimated walk time within the round display.
- [ ] Use an initial 25-metre arrival radius and several consecutive acceptable fixes to reduce jitter-triggered arrivals. Keep the radius configurable in the plan; it is a product tolerance, not claimed GPS precision.
- [ ] On arrival, show a Start action, integrate Part 4's challenge progress/retry/result, and display a local completion stamp and receipt. Do not depend on a server acknowledgment to celebrate completion.
- [ ] Provide cancel/reset and clean up location listeners, motion sampling, and timers on exit.

**Can start independently:** Use a bundled Monkey C representation of the route fixture and a stub motion result. Part 1 owns that watch-side fixture; Part 2 supplies the source JSON geometry.

**Done when:** A fēnix 7 simulator run shows invitation, actual green-space shapes and route, moving position, arrival, motion retry, and completion. Record peak app memory with the maximum permitted map payload. No camera, browser, or backend mission-state dependency remains.

## Part 2: Green-space data and pedestrian routing

**Goal:** Turn an origin into nearby green space and a plausible short pedestrian route, entirely off-watch.

- [ ] Supply one geographically consistent fixture: known origin, accessible park entrance, green-space outline, pedestrian route, and GPS replay coordinates. Check that the path does not cross barriers or restricted land.
- [ ] Implement `findGrassRoute(originLatE6, originLonE6, maxWalkS)` in `backend/src/routing/`, returning the plan below or an explicit no-route result.
- [ ] After fixture integration works, connect a green-space source and pedestrian-routing provider on the backend. Prefer accessible entrances, not park centroids; a map tag alone does not prove public access or grass coverage.
- [ ] Prefer a walk of about 120 seconds. If none is available, return `NO_ROUTE` and let the user choose a longer search rather than silently exceeding the requested budget.
- [ ] Simplify route/polygon geometry to the contract limits while preserving the entrance, meaningful turns, and recognizable green-space outline. Do not straighten the route across unsafe terrain to satisfy a byte limit.
- [ ] Return explicit failures for no green space, no pedestrian route, or provider unavailability. Keep provider credentials and full source geometries off the watch; preserve required map attribution.

**Can start independently:** Test the routing function and JSON fixtures without running the HTTP service or watch.

**Done when:** A known origin returns the bounded plan with a drawable green-space polygon and valid pedestrian route. No-route and provider-failure cases are exercised. Fixture mode is required; live discovery follows if time permits.

## Part 3: Off-watch HTTPS service and compact payloads

**Goal:** Expose Part 2's routing result through one small, Garmin-compatible endpoint. This runs on a laptop/server/cloud host, never in Monkey C.

- [ ] Set up `backend/` with an HTTP service; suggested stack: Node.js/TypeScript. Terminate HTTPS on the host or a trusted reverse proxy. Document configuration and run commands.
- [ ] Implement `POST /walk-plan` and `GET /health`. Use the fixture routing function until Part 2's live version is ready; make demo fixture mode explicit in both the response and watch UI.
- [ ] Validate flat integer request fields and coordinate ranges. Return `application/json` for success and errors. Bound execution time, rate-limit public requests, and avoid returning HTML login/error pages to the watch.
- [ ] Enforce the geometry and UTF-8 response-size budgets below before sending the result. Keep provider errors concise; do not send full GeoJSON, map tiles, images, or source-provider responses.
- [ ] Do not store missions, stream GPS, or collect challenge telemetry. Process the origin only for planning; avoid logging precise user coordinates and keep provider secrets server-side.
- [ ] Establish a URL reachable from the simulator. For team integration use trusted HTTPS without an interactive sign-in wall. Validate any dev proxy/tunnel with Monkey C, not only `curl`.
- [ ] Exercise the actual `makeWebRequest()` call with Part 1 early. Verify JSON decoding, connection failure/retry, and the final maximum-size payload.

**Can start independently:** Serve the route fixture and exercise the endpoint with an HTTP client. This validates the server contract, but does not substitute for a later simulator request.

**Done when:** The actual fēnix 7 simulator receives and decodes a plan from the external service, and service failures leave the watch usable. A loaded walk completes with the service disconnected.

## Part 4: Hand-motion challenge and simulator scenarios

**Goal:** Provide a small on-watch movement detector and a repeatable no-hardware demonstration.

- [ ] Implement the motion module in Monkey C without editing Part 1's views or manifest. Agree on the small interface below before integration.
- [ ] Use `Sensor.registerSensorDataListener()` with `:period => 1` and `:accelerometer => { :enabled => true, :sampleRate => 25 }`, bounded by the runtime-supported sample rate. Follow the API reference rather than older tutorial snippets with conflicting option names/units.
- [ ] Process x/y/z samples in millig units. Detect change over time rather than treating gravity or a fixed wrist orientation as motion. Reduce batches to a small amount of state; do not retain an unbounded raw sample history.
- [ ] Require gentle repeated motion across at least five real seconds after Start. A single shake, stillness, missing samples, or data from before Start must not pass. Make it a playful wave check, not a grass classifier or medical measurement.
- [ ] Supply deterministic scenarios for five seconds of motion, stillness, a brief shake followed by stillness, and interrupted/missing input. Tune thresholds as demo heuristics; real-world gesture accuracy is unvalidated without a watch.
- [ ] Check sensor simulation/FIT playback in the exact installed SDK. A prerecorded sensor FIT must actually contain accelerometer messages. If unavailable, feed clearly labeled synthetic batches into the same detector in a demo build; do not set success directly with a button.
- [ ] Coordinate with Part 1 to package replay inputs and a resettable demo in `demo/`. Unregister sampling on completion/cancel/exit and reset after inactivity/suspension.

**Can start independently:** Run the detector against synthetic batches in Monkey C tests or a temporary sensor harness. Part 1 owns adding the shared build paths and final views.

**Done when:** The detector passes sustained movement and rejects stillness, a short shake, and interrupted input. The simulator exercises the same detector used by the hardware callback, with replay/synthetic sources visibly identified.

## Shared interfaces: lock before parallel implementation

These are proposed contracts, not existing code. Keep all four parts compatible with them; agree on changes together.

### Walking-plan endpoint

`POST /walk-plan` accepts a flat JSON object: `{ "originLatE6": 53546000, "originLonE6": -113493800, "maxWalkS": 120 }`. These coordinates are a format example, not a verified route. E6 means decimal degrees multiplied by 1,000,000 and rounded to an integer. Latitude comes first in every coordinate pair.

| Response field | Meaning and cap |
| --- | --- |
| `version` | `1` |
| `source` | `live` or `fixture`; show fixture mode on the watch |
| `origin` | `[latE6, lonE6]` |
| `destination` | `{ name, point: [latE6, lonE6], arrivalRadiusM }`; name at most 40 ASCII characters for MVP |
| `route` | `{ points: [[latE6, lonE6], ...], distanceM, durationS }`; 2–64 points, origin to entrance |
| `greenSpaces` | One or two `{ name, ring: [[latE6, lonE6], ...] }` objects; each name at most 40 ASCII characters, each ring has 3–16 vertices and is implicitly closed |
| `attribution` | Concise source attribution, at most 160 ASCII characters; provide an About view for it |

Use a maximum **8,192-byte UTF-8 JSON response**, including errors, as a conservative project budget, not a claimed Garmin transport limit. Include at least the destination green-space outline. Flat integer coordinates avoid unnecessarily large arrays of point dictionaries and loss of location precision through Monkey C's single-precision `Float`; convert with `Double`/appropriate location methods on-watch.

Part 2 returns this object to Part 3. Part 3 serves it unchanged after validation. Failures use `{ "error": { "code": "NO_ROUTE", "message": "No accessible green space within this walk budget." } }` with appropriate non-2xx status codes. Define `INVALID_REQUEST` and `PROVIDER_UNAVAILABLE` similarly. The watch does not upload arrival or completion events.

### Local motion interface

Part 4 provides `start(onProgress, onResult)`, `cancel()`, and a detector input accepting x/y/z batches, their sample rate, and monotonic elapsed time. `onProgress` reports accepted movement time from zero to five seconds. After the five-second attempt, `onResult(passed)` fires once with a Boolean so the UI can show success or retry; missing data must fail, not leave the attempt waiting forever. Cancellation suppresses further callbacks. The module owns its sensor listener and timing. Part 1 owns the retry/cancel UI and local mission state.

The demo adapter feeds synthetic/replayed batches into that same detector input. Sensor mode and demo mode must not run concurrently. Start with accelerometer-only input; do not add an ML model or extra sensor dependency.

## Integration gates and what "works" means

- [ ] **Platform smoke test first:** Compile for `fenix7`, draw a basic map, receive `Position` updates, and register the accelerometer callback. Record SDK/device-profile versions. No physical sensor accuracy claims follow from this test.
- [ ] **Network smoke test:** From Monkey C in that simulator, fetch the external HTTPS fixture endpoint and decode its JSON. Verify a non-2xx JSON response and disconnected-network behavior. An HTTP-client-only check is insufficient.
- [ ] **Independent slices:** Every owner supplies fixtures/mocks and run instructions within their assigned paths. Parts 1 and 4 can proceed without the backend; Parts 2 and 3 can proceed without a Garmin runtime.
- [ ] **Map/GPS integration:** Use the fixture's matching GPS replay to move the marker along the displayed pedestrian route. Test good/usable versus poor/last-known/missing positions and the arrival boundary. No arrival from a bad or stale fix.
- [ ] **Gesture integration:** After arrival and explicit Start, run a failing input followed by a successful five-second wave through the real detector. No success from a timer alone.
- [ ] **Memory/offline check:** Exercise a maximum-size plan, inspect peak app memory against the 786,432-byte limit, then disconnect the service and finish the already-loaded walk/challenge.
- [ ] **Rehearsal:** Reset and run twice from invitation to stamp. Label compressed inactivity time, GPS replay, prepared maps/routes, and synthetic motion. Part 1 drives the watch; Part 4 owns replay instructions; Part 3 coordinates the external endpoint.

The complete flow is not verified until these checks run. Simulator results establish simulator behavior, not real-device Bluetooth reliability, GPS precision, or gesture classification quality.

## Stretch goals, in order

1. **Live discovery beyond the demo park**, using backend green-space lookup and pedestrian routing with provider limits and access checks.
2. **Background inactivity invitation**, using a small `Background` service and supported activity-monitor data. Observe five-minute temporal-event spacing and use `requestApplicationWake()` for user-confirmed launch; do not assume the app can interrupt silently or continuously sample in the background.
3. **Native basemap**, using supported `WatchUi.MapView`, markers, and polyline after confirming map coverage and rendering in the simulator. Do not assume map display also performs green-space search or route calculation.
4. **Photo verification and companion website:** phone camera capture, backend image verification, short-lived pairing, and shared mission status. All hosting and inference stay off-watch. This would add a new optional photo stage; do not prebuild its endpoints, polling, or authentication into the MVP. Explain third-party image processing, allow retry, and do not retain photos after verification.

## Out of scope

An HTTP server on the watch, unrestricted background execution, turn-by-turn routing calculated in Monkey C, guaranteed grass-contact detection, anti-cheating guarantees, medical claims, accounts/leaderboards, production-scale storage, and app-store release.

## Sources and evidence limits

1. [Garmin fēnix 7 device reference: target ID, display, inputs, and app memory](https://developer.garmin.com/connect-iq/articles/device-reference/fenix7.html)
2. [Communications API: web requests, content-type constants, connection requirements, and API-version notes](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
3. [Garmin phone communication model: high-level messages rather than raw sockets](https://developer.garmin.com/connect-iq/articles/core-topics/Communicating_with_Mobile_Apps.html)
4. [Device compatibility/API levels](https://developer.garmin.com/connect-iq/compatible-devices/)
5. [Position API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Position.html) and [Position.Info quality enum and nullable fields](https://developer.garmin.com/connect-iq/api-docs/Toybox/Position/Info.html)
6. [MapView API and supported devices](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/MapView.html)
7. [Sensor API: supported devices, batch periods, sample rates, and callback lifecycle](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html)
8. [Background API: temporal-event limits and user-confirmed app wake](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html)
9. [Garmin sensor guide: simulation and logged accelerometer playback](https://developer.garmin.com/connect-iq/articles/core-topics/Sensors.html)

The API HTML's supported-device lists explicitly include the original fēnix 7 for `MapView` and `registerSensorDataListener`. The published sensor guide contains legacy sample snippets; use the current API reference for option names and seconds-based periods. No SDK/runtime execution was performed during this planning audit; the integration gates above remain open.
