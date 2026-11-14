# Touch Grass backend

The off-watch service for the Touch Grass fēnix 7 app. It takes the user's location and returns a small
walking plan: the nearest green space, an entry point, and a short pedestrian route to it.

The watch makes **one request** per walk. Everything after that (walking, arrival, the hand-wave check) runs on
the watch. The backend stores nothing, keeps no record of the walk and never sees the result.

For the module-level detail (file table, JEV API notes, status checklist), see
[`src/routing/README.md`](src/routing/README.md). The shared contract lives in [`../PROJECT_PLAN.md`](../PROJECT_PLAN.md).

## Quick start

Requires Node 22.6+ (developed on Node 24). There are no npm dependencies; Node runs the TypeScript directly.

```powershell
# 1. Config: copy the template and fill in your JEV key (backend/.env is git-ignored)
Copy-Item backend/.env.example backend/.env

# 2. Start the dev server (http://localhost:8787)
node backend/scripts/dev-server.ts

# 3. In a second terminal
Invoke-RestMethod http://localhost:8787/health
$body = '{"originLatE6":53546000,"originLonE6":-113493800,"maxWalkS":120}'
Invoke-RestMethod -Method Post http://localhost:8787/walk-plan -ContentType 'application/json' -Body $body | ConvertTo-Json -Depth 6
```

On macOS/Linux, use `cp` and `curl -X POST ... -d '<json>'` instead. In Windows PowerShell 5.1, `curl` is an alias for
`Invoke-WebRequest`, so use `Invoke-RestMethod` or `curl.exe`.

Other checks:

```powershell
node --test backend/src/routing/core.test.ts backend/src/routing/discovery.test.ts   # offline tests, no network
node backend/scripts/live-check.ts 53.546 -113.4938 120 $env:TEMP                   # real tiles + JEV + router, debug image
```

`live-check` writes `live-check.png` (map, block grid, green blocks tinted, origin in red) and `live-check.geojson`
(paste into geojson.io) to the folder you give it.

## Architecture

```
 fēnix 7 watch                       Backend                                           Outside services
 ─────────────                       ───────                                           ────────────────
 "Stand up!" prompt
 user accepts, gets GPS fix
        │  POST /walk-plan
        │  {originLatE6, originLonE6, maxWalkS}
        ▼
                              HTTP layer  (scripts/dev-server.ts now; Part 3's service later)
                                     │
                                     ▼
                              findGrassRoute()   (src/routing/findGrassRoute.ts)
                                     │
                         ┌───────────┴────────────┐
                    fixture mode              live mode
                 (demo-park.json)      tiles → blocks → JEV → regions → route ──► OSM tiles, JEV, foot router
                         └───────────┬────────────┘
                                     ▼
                         simplify + validate (≤ 8,192 bytes)
        ◄────────────────────────────┘
        │  WalkPlan JSON, or {error}
        ▼
 draws map + route, user walks,
 arrival + hand-wave check on-watch
```

### 1. HTTP layer: `scripts/dev-server.ts`

- On startup it reads `backend/.env` and picks the provider from `ROUTING_MODE` (`fixture` or `live`).
- `GET /health` returns `{ ok, mode }`.
- `POST /walk-plan` parses the JSON body and calls `findGrassRoute(lat, lon, maxWalkS, provider)`.
- It maps the result to a status: success 200, `INVALID_REQUEST` 400, `NO_ROUTE` 404, `PROVIDER_UNAVAILABLE` 503.
  Every reply, errors included, is `application/json`.
- It never logs coordinates; it logs only method, path, status and time.

This is a **test server** (no HTTPS, no rate limiting). Part 3 owns the production service and will wrap the same
`findGrassRoute()` function.

### 2. Orchestrator: `src/routing/findGrassRoute.ts`

The same steps run in both modes:

1. **Check input.** Coordinates must be integers in range, and `maxWalkS` a positive integer.
2. **Ask the provider** for a candidate: destination, route and green-space outline.
3. **Budget check.** A walk longer than `maxWalkS` returns `NO_ROUTE` instead of quietly sending something too long.
4. **Simplify** (`simplify.ts`, Visvalingam–Whyatt) to ≤ 64 route points and ≤ 16 outline vertices, always keeping
   the start, the end and the entry point. It never invents points.
5. **Validate** (`validate.ts`) every contract limit and the 8,192-byte cap, shrinking further if needed.
6. **Return** the `WalkPlan`, or `{ "error": { "code", "message" } }`.

Every provider implements one interface, `find(origin, maxWalkS) → candidate | null`, so the orchestrator never
knows which mode it is in. `null` means "nothing suitable" (`NO_ROUTE`). A thrown `RoutingError` means an upstream
problem (`PROVIDER_UNAVAILABLE`).

### 3a. Fixture provider: `providers/fixture.ts`

- Reads `fixtures/routes/demo-park.json`. If the origin is within 250 m of the fixture point it returns that plan;
  otherwise `null`.
- Instant, needs no network or keys, always labelled `source: "fixture"` so the watch can show demo mode.
- For the demo and for Parts 1 and 3 to develop against. The current fixture geography is a **synthetic placeholder**
  and must be replaced with a checked park near the demo venue.

### 3b. Live provider: `providers/live.ts` (the JEV pipeline)

| Step | File | What happens |
|---|---|---|
| 1. Search area | `geo.ts` | Radius = `maxWalkS × 1.4 m/s` (about 170 m for a 2-minute walk), giving a bounding box around the user |
| 2. Map tiles | `tiles.ts`, `png.ts` | Downloads the OSM map tiles covering the box at zoom 17, decodes them (built-in PNG decoder on Node's `zlib`) and stitches them into one image, about 768×768 px. Tiles are cached for 10 minutes; at most 25 tiles per request |
| 3. Blocks | `blocks.ts` | Cuts the image into a grid of `BLOCK_PX` squares (default 64 px, about 46 m): 144 blocks |
| 4. JEV | `jev.ts` | Sends the blocks to TypeSafe's JEV API, 8 per request, each enlarged to 280 px (JEV's minimum). Each block asks "is this map crop mostly green space?" and gets back a probability. Takes about 3–4 s |
| 5. Regions | `regions.ts` | Blocks scoring ≥ `GREEN_MIN_SCORE` (0.5) are green. Touching green blocks merge into regions; single blocks are dropped. Each region gets an outline and an **entry point**, the point on its edge nearest the user |
| 6. Route | `router.ts` | For the nearest 3 regions, asks an OSRM-compatible foot router (FOSSGIS by default) for a walking path from the user to the entry point. Duration = distance ÷ 1.4 m/s |
| 7. Pick | `live.ts` | Keeps routes within budget and picks the one closest to 120 s. If the user is already inside a green region, the walk is zero |

Control then returns to the orchestrator, which simplifies and validates the result.

A green block means "drawn as green space on the map". It does **not** prove that grass is there or that the area
is public. Describe it that way in the demo.

## What comes back

```json
{
  "version": 1,
  "source": "live",
  "origin": [53546000, -113493800],
  "destination": { "name": "Green Space", "point": [53546428, -113494263], "arrivalRadiusM": 25 },
  "route": { "points": [[53546000, -113493800], "..."], "distanceM": 69, "durationS": 49 },
  "greenSpaces": [{ "name": "Green Space", "ring": [[53547652, -113495636], "..."] }],
  "attribution": "Map tiles (c) OpenStreetMap contributors. Green areas classified by JEV."
}
```

- Coordinates are **integers**: decimal degrees × 1,000,000, latitude first. Monkey C's `Float` is 32-bit and would
  lose GPS precision.
- Limits (from `PROJECT_PLAN.md`): 2–64 route points, 1–2 green spaces of 3–16 vertices each, ASCII names ≤ 40
  characters, attribution ≤ 160 characters, whole response ≤ 8,192 bytes.
- The watch draws the outline and route on its own small map and guides the user to `destination.point`.

## When something fails

| Situation | Code | HTTP |
|---|---|---|
| Bad input (not JSON, non-integer or out-of-range coordinates) | `INVALID_REQUEST` | 400 |
| No green space nearby, the router finds no path, or the walk is too long | `NO_ROUTE` | 404 |
| Tile server, JEV or router down; JEV or router not configured | `PROVIDER_UNAVAILABLE` | 503 |

```json
{ "error": { "code": "NO_ROUTE", "message": "No accessible green space within this walk budget." } }
```

Error messages never contain upstream details or the API key. The watch can always retry, or the user can choose a
longer walk.

## Configuration: `backend/.env`

Git-ignored; never commit it. `backend/.env.example` is the committed template.

| Setting | Controls | Default |
|---|---|---|
| `ROUTING_MODE` | `fixture` or `live` | `fixture` |
| `JEV_API_KEY` | Your TypeSafe key | (empty) |
| `JEV_API_URL` | JEV endpoint | `https://api.typesafe.ai/v1/systemone` |
| `JEV_MODEL` | JEV model (`GET /v1/models` lists them) | `jev-latest` |
| `CLASSIFIER` | `jev`, or `color` (OSM park-colour fallback, no key needed) | `jev` |
| `GREEN_MIN_SCORE` | Score at which a block counts as green | `0.5` |
| `BLOCK_PX` | Block size in pixels: larger means fewer JEV calls and coarser outlines | `64` |
| `TILE_URL`, `TILE_ZOOM` | Map tile source and zoom | OSM, `17` |
| `ROUTER_URL` | OSRM-compatible foot router | FOSSGIS `routed-foot` |
| `USER_AGENT` | Sent to tile and routing servers | `touch-grass-demo/0.1` |
| `PORT` | Dev server port | `8787` |

**Cost and fair use:** each JEV block costs about 330–600 input tokens, so one live request is roughly 50–90k tokens
at 64 px blocks. The OSM tile server and the FOSSGIS router allow light use only; that is fine for a demo, but use
other hosts for anything more.

## Ownership

| Part | Owns |
|---|---|
| Part 2 (routing) | `backend/src/routing/`, `fixtures/routes/`, and the test tools in `backend/scripts/` |
| Part 3 (service) | The production HTTP service around `findGrassRoute()`: HTTPS, rate limiting, hosting, `backend/package.json` |
| Part 1 (watch app) | The "stand up" prompt, GPS, the request to `/walk-plan`, drawing the map, arrival |
| Part 4 (motion) | The hand-wave check after arrival; no backend involvement |

## Not done yet

- **Real fixture park:** the demo fixture is synthetic; replace it with a checked park near the demo venue.
- **Production service:** Part 3's HTTPS endpoint, reachable from the Connect IQ simulator and the watch.
- **Simulator test:** a Monkey C `makeWebRequest()` call to this endpoint has not been tried yet.
- **Small parks:** only what the map draws in green counts, and regions smaller than 2 blocks (about 46 m × 92 m)
  are dropped, so very small green patches are not offered.
