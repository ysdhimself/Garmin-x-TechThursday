# Part 2: Green-space discovery and pedestrian routing

Off-watch only. Turns the user's location into the nearest green space and a short walking route, as the
`WalkPlan` contract in `PROJECT_PLAN.md` ("Walking-plan endpoint").

```ts
import { findGrassRoute, isFailure, liveProviderFromEnv } from "./index.ts";

const r = await findGrassRoute(53546000, -113493800, 120);                          // fixture mode
const r2 = await findGrassRoute(latE6, lonE6, 120, liveProviderFromEnv(process.env)); // live mode
if (isFailure(r)) r.error; // { code: "NO_ROUTE" | "INVALID_REQUEST" | "PROVIDER_UNAVAILABLE", message }
else r;                    // WalkPlan, validated, <= 8,192 bytes
```

Expected failures are returned, not thrown. For Part 3: serve a plan unchanged, map `error.code` to a status
(suggested INVALID_REQUEST 400, NO_ROUTE 404, PROVIDER_UNAVAILABLE 503), always as `application/json`, and pick
the provider from `ROUTING_MODE` in `backend/.env`.

## How live mode finds green space

```
origin → OSM map tiles around it (radius = maxWalkS × 1.4 m/s, zoom 17)
       → 32×32 px blocks (~23 m at Edmonton's latitude)
       → classifier scores each block 0..1 (JEV, or the colour fallback)
       → touching green blocks merged into regions → outline ring + entry point nearest the origin
       → foot route origin → entry (OSRM-compatible router) → nearest 3 regions tried, walk closest to 120 s kept
       → simplified to the contract caps → validated
```

A green block means "drawn as green space on the map". It does not prove grass or public access.

## Setup

1. `backend/.env` (git-ignored) is already created from `backend/.env.example`. Paste your key after `JEV_API_KEY=` and set `JEV_API_URL`.
2. **JEV request/response format is a placeholder** in `providers/jev.ts`: it POSTs `{ images: [base64 PNG, ...] }` with
   `Authorization: Bearer <key>` and accepts `{ scores: [...] }` or `{ results: [{ score } | { label, confidence }] }`.
   Change `jevClassifier` once the real API format is known.
3. Set `ROUTER_URL` to a foot-profile OSRM-compatible router (self-host OSRM with the foot profile, or Valhalla/ORS
   behind an OSRM-style adapter). The public OSRM demo may route by car.
4. No dependencies: Node 24 runs the TypeScript directly, and PNG decoding uses Node's built-in `zlib`.
   If Part 3 adds a `tsconfig.json`, it needs `allowImportingTsExtensions` and `erasableSyntaxOnly`.

## Run

```
node --test backend/src/routing/core.test.ts backend/src/routing/discovery.test.ts   # offline, no network
node backend/scripts/live-check.ts 53.546 -113.4938                                  # real tiles + JEV + router
CLASSIFIER=color node backend/scripts/live-check.ts 53.546 -113.4938 120 <outDir>    # without a JEV key
```

`live-check` writes `live-check.png` (map, block grid, green blocks tinted, origin in red) and `live-check.geojson`
(paste into geojson.io) to the output folder (default: the OS temp folder).

## Layout

| File | Role |
| --- | --- |
| `types.ts` | Contract types and `LIMITS`. Change only with Parts 1, 3, 4 |
| `findGrassRoute.ts` | Pipeline: input check → provider → budget check → simplify → validate/shrink |
| `providers/fixture.ts` | Serves `fixtures/routes/demo-park.json` (`source: "fixture"`) |
| `providers/live.ts` | Live pipeline + `liveProviderFromEnv()` |
| `providers/tiles.ts` | Fetch + stitch map tiles (10-min tile cache, max 25 tiles) |
| `providers/blocks.ts` | Cut the stitched map into blocks |
| `providers/jev.ts` | `jevClassifier` (JEV API) and `colorClassifier` (OSM green colours, offline fallback) |
| `providers/regions.ts` | Green blocks → regions → outline ring + entry point |
| `providers/router.ts` | OSRM-compatible foot routing |
| `providers/png.ts` | Minimal PNG decode/encode/crop (zlib only) |
| `geo.ts`, `simplify.ts`, `validate.ts` | Distances, tile math; Visvalingam-Whyatt; contract checks (reusable by Part 3) |

## Status

- [x] Fixture mode, contract validation, error mapping
- [x] Live pipeline with blocks → classifier → regions → route; checked on real OSM tiles of downtown Edmonton with the
      colour classifier (it found the ICE District Fan Park as the nearest green region)
- [ ] Real JEV API format (placeholder now) and a run with your key
- [ ] A foot router at `ROUTER_URL`; routing not yet run against a real router
- [ ] Fixture geography is synthetic; replace with a checked park near the demo venue
- [ ] OSM tile policy allows light use only; use another tile host beyond the demo
