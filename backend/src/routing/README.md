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
       → 64×64 px blocks (BLOCK_PX; ~46 m at Edmonton's latitude)
       → classifier scores each block 0..1 (JEV, or the colour fallback)
       → touching green blocks merged into regions → outline ring + entry point nearest the origin
       → foot route origin → entry (OSRM-compatible router) → nearest 3 regions tried, walk closest to 120 s kept
       → simplified to the contract caps → validated
```

A green block means "drawn as green space on the map". It does not prove grass or public access.

## Setup

1. `backend/.env` (git-ignored): `JEV_API_KEY`, `JEV_API_URL=https://api.typesafe.ai/v1/systemone`, `JEV_MODEL=jev-latest`.
2. **JEV is TypeSafe's System One API** (docs: https://api.typesafe.ai/docs, models: `GET /v1/models`). `providers/jev.ts`
   sends each block as an image asset with one yes/no (`noul`) question, "is this map crop mostly green space?", and
   uses the returned probability as the block's score. Facts found by probing (not in the docs):
   - images must be at least **280×280 px**, so blocks are upscaled (nearest neighbour);
   - about **8 real map crops per request** are accepted (~47 KB); 16 gives `400 Invalid image request`, so batches of 8,
     and any 400 batch is split in half and retried;
   - requests with images need the header `TypeSafe-Danger-Zone-Images: true`;
   - typical scores: OSM park green ≈ 0.8, plain map ≈ 0.1–0.2. Threshold `GREEN_MIN_SCORE=0.5`.
   - cost: about 330–600 input tokens per block. 64 px blocks over a 120 s walk area = 144 blocks ≈ 18 requests, ~3–4 s.
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

Dev HTTP server (same contract as Part 3's future service, for testing only; no HTTPS, no rate limiting):

```
node backend/scripts/dev-server.ts        # http://localhost:8787, mode from ROUTING_MODE in backend/.env
curl localhost:8787/health
curl -X POST localhost:8787/walk-plan -H "Content-Type: application/json" -d "{\"originLatE6\":53546000,\"originLonE6\":-113493800,\"maxWalkS\":120}"
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
- [x] Live pipeline with blocks → classifier → regions → route
- [x] JEV (TypeSafe System One) wired to its real API and run on real OSM tiles of downtown Edmonton: 144 blocks in ~3.7 s,
      the nearest green region found was the ICE District Fan Park (~57 m away). The colour fallback finds the same park.
- [ ] A foot router at `ROUTER_URL`; routing not yet run against a real router
- [ ] Fixture geography is synthetic; replace with a checked park near the demo venue
- [ ] OSM tile policy allows light use only; use another tile host beyond the demo
