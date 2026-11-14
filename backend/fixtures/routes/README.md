# Route fixtures (Part 2)

| File | Consumer | Contents |
| --- | --- | --- |
| `demo-park.json` | Part 3 (via `findGrassRoute` in fixture mode), Part 1 (source for the bundled Monkey C copy) | A full `WalkPlan`, `source: "fixture"`: 8 route points, a 6-vertex garden ring, about 145 m / 104 s |
| `demo-park.gps.json` | Part 1 map/GPS integration | Replay samples every 2 s along the route, then jitter inside the 25 m arrival radius |

**Route:** Platform Calgary (51.044277, -114.055682) to Calgary Central Library Garden (51.045460, -114.055422).
The walking route follows the OSRM/FOSSGIS pedestrian path along 4th St SE northbound. The green-space polygon
approximates the library's garden area on its northeast side. Coordinates sourced from OpenStreetMap Nominatim
and the FOSSGIS OSRM foot router.

GPS replay quality values mirror `Position` quality names: `GOOD`, `USABLE`, `LAST_KNOWN`, `NOT_AVAILABLE`.
Samples with a `case` field are deliberate bad fixes (missing position, stale last-known) that must not
trigger arrival. `latE6`/`lonE6` are `null` for the missing-position case.

The Connect IQ simulator replays `.FIT` files, not JSON, so Part 1 feeds this replay in from code
(or converts it) rather than loading it in the simulator directly.
