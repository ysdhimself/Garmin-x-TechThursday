import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { findGrassRoute, isFailure, validatePlan, liveProvider, jevClassifier, colorClassifier, liveProviderFromEnv, RoutingError } from "./index.ts";
import { TILE_PX, haversineM, latLonToPixel, metresPerPixel, pixelToE6, pixelToLatLon } from "./geo.ts";
import { decodePng, encodePng, newImage, type Image } from "./providers/png.ts";
import { cutBlocks } from "./providers/blocks.ts";
import { findGreenRegions } from "./providers/regions.ts";
import { _clearTileCache } from "./providers/tiles.ts";

beforeEach(() => _clearTileCache());

const Z = 17;
const BG: [number, number, number, number] = [242, 239, 233, 255]; // OSM land background
const PARK: [number, number, number, number] = [200, 250, 204, 255]; // OSM leisure=park

function paint(img: Image, x0: number, y0: number, x1: number, y1: number, c: number[]) {
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) img.data.set(c, (y * img.width + x) * 4);
}

// A tile with a park filling x 128..224, y 64..192.
const parkTile = () => {
  const t = newImage(TILE_PX, TILE_PX, BG);
  paint(t, 128, 64, 224, 192, PARK);
  return t;
};

// Pick a real tile near Edmonton and put the origin 88 px west of the park, mid-height.
const [cx, cy] = latLonToPixel(53.546, -113.4938, Z);
const TX = Math.floor(cx / TILE_PX), TY = Math.floor(cy / TILE_PX);
const ORIGIN = pixelToE6(TX * TILE_PX + 40, TY * TILE_PX + 128, Z);

function fakeFetch(opts: { parkPng?: Buffer; noRoute?: boolean; jev?: (body: any) => Response } = {}): typeof fetch {
  const park = opts.parkPng ?? encodePng(parkTile());
  const plain = encodePng(newImage(TILE_PX, TILE_PX, BG));
  return (async (url: any, init?: any) => {
    const u = String(url);
    if (u.startsWith("http://jev")) return opts.jev!(JSON.parse(init.body));
    if (u.includes("/route/v1/foot/")) {
      if (opts.noRoute) return new Response(JSON.stringify({ code: "NoRoute" }), { status: 400 });
      const m = u.match(/foot\/([-\d.]+),([-\d.]+);([-\d.]+),([-\d.]+)/)!;
      const a = [Number(m[2]), Number(m[1])], b = [Number(m[4]), Number(m[3])];
      const d = haversineM([Math.round(a[0]! * 1e6), Math.round(a[1]! * 1e6)], [Math.round(b[0]! * 1e6), Math.round(b[1]! * 1e6)]);
      return new Response(JSON.stringify({ code: "Ok", routes: [{ distance: d, geometry: { coordinates: [[a[1], a[0]], [b[1], b[0]]] } }] }));
    }
    const t = u.match(/\/17\/(\d+)\/(\d+)\.png/);
    if (t) return new Response(Number(t[1]) === TX && Number(t[2]) === TY ? park : plain);
    return new Response("not found", { status: 404 });
  }) as typeof fetch;
}

const mk = (f: typeof fetch, extra = {}) =>
  liveProvider({ classifier: colorClassifier(), tileUrl: "http://tiles/{z}/{x}/{y}.png", tileZoom: Z, routerUrl: "http://router", userAgent: "t", fetchFn: f, ...extra });

test("tile math round-trips and gives sane metres per pixel", () => {
  const [x, y] = latLonToPixel(53.546, -113.4938, Z);
  const [lat, lon] = pixelToLatLon(x, y, Z);
  assert.ok(Math.abs(lat - 53.546) < 1e-9 && Math.abs(lon + 113.4938) < 1e-9);
  const mpp = metresPerPixel(53.546, Z);
  assert.ok(mpp > 0.6 && mpp < 0.8, `m/px ${mpp}`);
});

test("PNG encode/decode round-trips", () => {
  const img = parkTile();
  const back = decodePng(encodePng(img));
  assert.equal(back.width, 256);
  assert.deepEqual(Buffer.from(back.data), Buffer.from(img.data));
});

test("blocks + colour classifier + regions find the park and an entry on its near edge", async () => {
  const mosaic = { image: parkTile(), zoom: Z, originPx: [TX * TILE_PX, TY * TILE_PX] as [number, number] };
  const grid = cutBlocks(mosaic, 32);
  assert.equal(grid.rows * grid.cols, 64);
  const scores = await colorClassifier().classify(grid.blocks);
  assert.equal(scores.filter((s) => s >= 0.5).length, 3 * 4); // 96x128 px park = 3x4 blocks
  const regions = findGreenRegions(grid, scores, mosaic, ORIGIN);
  assert.equal(regions.length, 1);
  const reg = regions[0]!;
  assert.equal(reg.ring.length, 5); // rectangle corners + inserted entry point
  assert.deepEqual(reg.entry, pixelToE6(TX * TILE_PX + 128, TY * TILE_PX + 128, Z)); // straight east of origin
  assert.ok(Math.abs(reg.entryDistM - 88 * metresPerPixel(53.546, Z)) < 1);
});

test("live: finds the green region, routes to it, returns a valid plan", async () => {
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, mk(fakeFetch()));
  assert.ok(!isFailure(r), JSON.stringify(r));
  assert.equal(r.source, "live");
  assert.deepEqual(validatePlan(r), []);
  assert.deepEqual(r.route.points[0], ORIGIN);
  assert.deepEqual(r.route.points.at(-1), r.destination.point);
  assert.ok(r.greenSpaces[0]!.ring.some((v) => v[0] === r.destination.point[0] && v[1] === r.destination.point[1]));
  assert.match(r.attribution, /OpenStreetMap/);
});

test("live: origin already inside green space -> zero-length walk", async () => {
  const inside = pixelToE6(TX * TILE_PX + 170, TY * TILE_PX + 120, Z);
  const r = await findGrassRoute(inside[0], inside[1], 120, mk(fakeFetch()));
  assert.ok(!isFailure(r));
  assert.equal(r.route.distanceM, 0);
});

test("live: router NoRoute and over-budget -> NO_ROUTE", async () => {
  const a = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, mk(fakeFetch({ noRoute: true })));
  assert.ok(isFailure(a) && a.error.code === "NO_ROUTE");
  const b = await findGrassRoute(ORIGIN[0], ORIGIN[1], 20, mk(fakeFetch()));
  assert.ok(isFailure(b) && b.error.code === "NO_ROUTE");
});

test("live: tile server down -> PROVIDER_UNAVAILABLE", async () => {
  const down = (async () => new Response("err", { status: 503 })) as typeof fetch;
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, mk(down));
  assert.ok(isFailure(r) && r.error.code === "PROVIDER_UNAVAILABLE");
});

/** Fake TypeSafe System One: answers each noul question by scoring the image its instructions name. */
function systemOne(score: (img: Image) => number, seen?: any[]) {
  return (body: any) => {
    seen?.push(body);
    const answers: Record<string, object> = {};
    for (const [name, q] of Object.entries<any>(body.questions)) {
      const id = Object.keys(body.assets).find((a) => q.instructions.includes(a))!;
      answers[name] = { type: "noul", noul: score(decodePng(Buffer.from(body.assets[id].data_base64, "base64"))) };
    }
    return new Response(JSON.stringify({ model: "jev-test", answers, usage: { input_tokens: 1, output_tokens: 1 } }));
  };
}

test("JEV client: System One request shape (assets + noul questions, 280px images) and answer parsing", async () => {
  const seen: any[] = [];
  const f = fakeFetch({ jev: systemOne((img) => (img.data[1]! > 245 ? 0.8 : 0.2), seen) });
  const grid = cutBlocks({ image: parkTile(), zoom: Z, originPx: [0, 0] }, 32);
  const s = await jevClassifier({ url: "http://jev/v1/systemone", apiKey: "k", fetchFn: f }).classify(grid.blocks);
  assert.equal(s.length, 64);
  assert.equal(seen.length, 8); // 64 blocks / batches of 8
  const b = seen[0];
  assert.equal(b.model, "jev-latest");
  assert.equal(Object.keys(b.assets).length, 8);
  const a = Object.values<any>(b.assets)[0];
  assert.equal(a.type, "image");
  assert.equal(a.format, "png");
  const img = decodePng(Buffer.from(a.data_base64, "base64"));
  assert.ok(img.width >= 280 && img.height >= 280);
  assert.equal((Object.values<any>(b.questions)[0]).type, "noul");
  // Park block (row 2, col 5 -> inside x128..224, y64..192) vs background block (0,0)
  assert.equal(s[2 * 8 + 5], 0.8);
  assert.equal(s[0], 0.2);
});

test("JEV client: a 400 for a too-large batch is split and retried", async () => {
  const sizes: number[] = [];
  const ok = systemOne(() => 0.5);
  const f = fakeFetch({ jev: (body) => { const n = Object.keys(body.assets).length; sizes.push(n); return n > 2 ? new Response('{"detail":{}}', { status: 400 }) : ok(body); } });
  const grid = cutBlocks({ image: parkTile(), zoom: Z, originPx: [0, 0] }, 64);
  const s = await jevClassifier({ url: "http://jev/v1/systemone", apiKey: "k", fetchFn: f, batchSize: 8 }).classify(grid.blocks.slice(0, 8));
  assert.equal(s.length, 8);
  assert.deepEqual(sizes, [8, 4, 2, 2, 4, 2, 2]);
});

test("JEV client: outage or malformed reply -> PROVIDER_UNAVAILABLE, key never leaked", async () => {
  const grid = cutBlocks({ image: parkTile(), zoom: Z, originPx: [0, 0] }, 128);
  for (const jev of [() => new Response("x", { status: 500 }), () => new Response(JSON.stringify({ answers: { b0: { type: "noul", noul: 2 } } }))]) {
    await assert.rejects(
      jevClassifier({ url: "http://jev/c", apiKey: "SECRET", fetchFn: fakeFetch({ jev }) }).classify(grid.blocks),
      (e: any) => e instanceof RoutingError && e.code === "PROVIDER_UNAVAILABLE" && !e.message.includes("SECRET"),
    );
  }
});

test("live end-to-end through the JEV path", async () => {
  // Fake JEV that scores like the colour classifier, to prove the wiring.
  const { greenFraction } = await import("./providers/jev.ts");
  const f = fakeFetch({ jev: systemOne(greenFraction) });
  const p = liveProviderFromEnv({ CLASSIFIER: "jev", JEV_API_KEY: "k", JEV_API_URL: "http://jev/c", ROUTER_URL: "http://router", TILE_URL: "http://tiles/{z}/{x}/{y}.png", TILE_ZOOM: "17" }, f);
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, p);
  assert.ok(!isFailure(r), JSON.stringify(r));
  assert.match(r.attribution, /JEV/);
});

test("liveProviderFromEnv refuses to run JEV without key/url", () => {
  assert.throws(() => liveProviderFromEnv({ CLASSIFIER: "jev", ROUTER_URL: "x" }), /JEV is not configured/);
});
