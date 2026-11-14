# Route fixtures (Part 2)

| File | Consumer | Contents |
| --- | --- | --- |
| `demo-park.json` | Part 3 (via `findGrassRoute` in fixture mode), Part 1 (source for the bundled Monkey C copy) | A full `WalkPlan`, `source: "fixture"`: 5 route points, a 6-vertex park ring, about 160 m / 114 s |
| `demo-park.gps.json` | Part 1 map/GPS integration | Replay samples every 2 s along the route, then jitter inside the 25 m arrival radius |

**The geography is synthetic placeholder data.** It sits at the plan's example origin (`53546000, -113493800`)
but has not been checked against a real map, so it must not be described as a real park or route.
Replace it with a real park near the demo venue (checked for fences, roads and private land) before the demo.

GPS replay quality values mirror `Position` quality names: `GOOD`, `USABLE`, `LAST_KNOWN`, `NOT_AVAILABLE`.
Samples with a `case` field are deliberate bad fixes (missing position, stale last-known) that must not
trigger arrival. `latE6`/`lonE6` are `null` for the missing-position case.

The Connect IQ simulator replays `.FIT` files, not JSON, so Part 1 feeds this replay in from code
(or converts it) rather than loading it in the simulator directly.
