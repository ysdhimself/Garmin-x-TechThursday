// Real-data check for Part 2 live mode.
//   node backend/scripts/live-check.ts <lat> <lon> [maxWalkS=120] [outDir=<os tmp>]
// Reads backend/.env. Writes <outDir>/live-check.png (map with blocks shaded by score, regions
// outlined) and <outDir>/live-check.geojson (route, green space, entry) for geojson.io.
// Output stays local; coordinates are not sent anywhere except the configured tile/JEV/router services.
import { existsSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { findGrassRoute, isFailure, validatePlan, byteSize, liveProvider, colorClassifier, jevClassifier } from "../src/routing/index.ts";
import { toE6, latLonToPixel } from "../src/routing/geo.ts";
import { encodePng } from "../src/routing/providers/png.ts";

const envFile = fileURLToPath(new URL("../.env", import.meta.url));
if (existsSync(envFile)) process.loadEnvFile(envFile);
const env = process.env;

const [lat, lon] = [Number(process.argv[2]), Number(process.argv[3])];
const maxWalkS = Number(process.argv[4] ?? 120);
const outDir = process.argv[5] ?? tmpdir();
if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
  console.error("usage: node backend/scripts/live-check.ts <lat> <lon> [maxWalkS] [outDir]");
  process.exit(2);
}

const classifier =
  (env.CLASSIFIER ?? "jev") === "color" || !env.JEV_API_KEY
    ? colorClassifier()
    : jevClassifier({ url: env.JEV_API_URL!, apiKey: env.JEV_API_KEY });
console.log(`classifier: ${classifier.name}${classifier.name === "color" && env.CLASSIFIER !== "color" ? " (no JEV key set, using colour fallback)" : ""}`);

const provider = liveProvider({
  classifier,
  tileUrl: env.TILE_URL ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
  tileZoom: Number(env.TILE_ZOOM ?? 17),
  routerUrl: env.ROUTER_URL ?? "http://localhost:5000",
  userAgent: env.USER_AGENT ?? "touch-grass-demo/0.1",
  minScore: env.GREEN_MIN_SCORE ? Number(env.GREEN_MIN_SCORE) : undefined,
  onDebug: ({ mosaic, rows, cols, size, scores, regions }) => {
    const img = { ...mosaic.image, data: new Uint8Array(mosaic.image.data) };
    const min = Number(env.GREEN_MIN_SCORE ?? 0.5);
    for (let r = 0; r < rows; r++)
      for (let c = 0; c < cols; c++) {
        const s = scores[r * cols + c]!;
        for (let y = r * size; y < (r + 1) * size; y++)
          for (let x = c * size; x < (c + 1) * size; x++) {
            const o = (y * img.width + x) * 4;
            const edge = x % size === 0 || y % size === 0;
            if (edge) img.data.set([120, 120, 120, 255], o);
            else if (s >= min) img.data.set([(img.data[o]! + 40) >> 1, (img.data[o + 1]! + 200) >> 1, (img.data[o + 2]! + 40) >> 1, 255], o); // tint green blocks
          }
      }
    // Mark origin in red.
    const [ox, oy] = latLonToPixel(lat, lon, mosaic.zoom);
    for (let dy = -4; dy <= 4; dy++)
      for (let dx = -4; dx <= 4; dx++) {
        const x = Math.round(ox - mosaic.originPx[0]) + dx, y = Math.round(oy - mosaic.originPx[1]) + dy;
        if (x >= 0 && y >= 0 && x < img.width && y < img.height) img.data.set([220, 30, 30, 255], (y * img.width + x) * 4);
      }
    writeFileSync(join(outDir, "live-check.png"), encodePng(img));
    console.log(`grid ${rows}x${cols} blocks of ${size}px, green blocks: ${scores.filter((s) => s >= min).length}, regions: ${regions.length}`);
    regions.slice(0, 5).forEach((g, i) => console.log(`  region ${i}: ${g.blocks} blocks, entry ${Math.round(g.entryDistM)} m away${g.containsOrigin ? " (origin inside)" : ""}`));
  },
});

const r = await findGrassRoute(toE6(lat), toE6(lon), maxWalkS, provider);
console.log(`debug image: ${join(outDir, "live-check.png")}`);
if (isFailure(r)) {
  console.log("result:", r.error);
  process.exit(1);
}
const ll = (p: [number, number]) => [p[1] / 1e6, p[0] / 1e6];
const geo = {
  type: "FeatureCollection",
  features: [
    { type: "Feature", properties: { kind: "route", distanceM: r.route.distanceM, durationS: r.route.durationS }, geometry: { type: "LineString", coordinates: r.route.points.map(ll) } },
    ...r.greenSpaces.map((g) => ({ type: "Feature", properties: { kind: "green", name: g.name }, geometry: { type: "Polygon", coordinates: [[...g.ring, g.ring[0]!].map(ll)] } })),
    { type: "Feature", properties: { kind: "entry" }, geometry: { type: "Point", coordinates: ll(r.destination.point) } },
  ],
};
writeFileSync(join(outDir, "live-check.geojson"), JSON.stringify(geo));
console.log(`plan: ${r.route.distanceM} m, ${r.route.durationS} s, ${r.route.points.length} pts, ring ${r.greenSpaces[0]!.ring.length} v, ${byteSize(r)} bytes`);
console.log("validatePlan:", validatePlan(r).length ? validatePlan(r) : "OK");
console.log(`geojson: ${join(outDir, "live-check.geojson")}`);
