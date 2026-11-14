import { test } from "node:test";
import assert from "node:assert/strict";
import { findGrassRoute, fixtureProviderFromEnv, isFailure, RoutingError, validatePlan, type Candidate, type RoutingProvider } from "./index.ts";
import { haversineM, routeLengthM } from "./geo.ts";
import { simplifyToCap } from "./simplify.ts";

const ORIGIN = [51044277, -114055682] as const;
const EDMONTON_ORIGIN = [53546000, -113493800] as const;

test("fixture origin returns a valid bounded plan", async () => {
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120);
  assert.ok(!isFailure(r));
  assert.equal(r.source, "fixture");
  assert.deepEqual(validatePlan(r), []);
  assert.ok(r.route.durationS <= 120);
});

test("route ends at the entry point, which is a vertex of the green-space ring", async () => {
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120);
  assert.ok(!isFailure(r));
  assert.deepEqual(r.route.points.at(-1), r.destination.point);
  assert.ok(r.greenSpaces[0]!.ring.some((v) => haversineM(v, r.destination.point) < 1));
});

test("declared distance matches route geometry", async () => {
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120);
  assert.ok(!isFailure(r));
  assert.ok(Math.abs(routeLengthM(r.route.points) - r.route.distanceM) < 2);
});

test("over budget or far from green space -> NO_ROUTE", async () => {
  for (const [lat, lon, s] of [[ORIGIN[0], ORIGIN[1], 30], [48000000, 2000000, 120]] as const) {
    const r = await findGrassRoute(lat, lon, s);
    assert.ok(isFailure(r));
    assert.equal(r.error.code, "NO_ROUTE");
  }
});

test("provider failure -> PROVIDER_UNAVAILABLE without leaking details", async () => {
  const down: RoutingProvider = { find: async () => { throw new RoutingError("PROVIDER_UNAVAILABLE", "upstream down"); } };
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, down);
  assert.ok(isFailure(r) && r.error.code === "PROVIDER_UNAVAILABLE");
  const weird: RoutingProvider = { find: async () => { throw new Error("boom secret-key"); } };
  const r2 = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, weird);
  assert.ok(isFailure(r2) && r2.error.code === "PROVIDER_UNAVAILABLE" && !r2.error.message.includes("secret"));
});

test("invalid requests are rejected", async () => {
  for (const a of [[91_000_000, 0, 120], [0, 181_000_000, 120], [1.5, 2, 120], [0, 0, 0], [0, 0, 1.5]] as const) {
    const r = await findGrassRoute(a[0], a[1], a[2]);
    assert.ok(isFailure(r) && r.error.code === "INVALID_REQUEST");
  }
});

test("oversized geometry is simplified to contract caps and byte budget", async () => {
  const route = Array.from({ length: 300 }, (_, i): [number, number] => [53546000 + i * 10, -113493800 + (i % 7) * 3 + i]);
  const ring = Array.from({ length: 100 }, (_, i): [number, number] => {
    const a = (i / 100) * 2 * Math.PI;
    return [53547000 + Math.round(Math.sin(a) * 800), -113492000 + Math.round(Math.cos(a) * 1200)];
  });
  const big: RoutingProvider = {
    async find(): Promise<Candidate> {
      return {
        source: "live",
        destination: { name: "Big Park", point: route.at(-1)!, arrivalRadiusM: 25 },
        route: { points: route, distanceM: 300, durationS: 100 },
        greenSpaces: [{ name: "Big Park", ring }],
        attribution: "test",
      };
    },
  };
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120, big);
  assert.ok(!isFailure(r));
  assert.ok(r.route.points.length <= 64 && r.greenSpaces[0]!.ring.length <= 16);
  assert.deepEqual(r.route.points[0], route[0]);
  assert.deepEqual(r.route.points.at(-1), route.at(-1));
  assert.deepEqual(validatePlan(r), []);
});

test("simplifyToCap keeps endpoints and protected ring vertices", () => {
  assert.deepEqual(simplifyToCap([[0, 0], [0, 100], [0, 200], [0, 300], [500, 300]], 3), [[0, 0], [0, 300], [500, 300]]);
  const ring: [number, number][] = [[0, 0], [0, 1000], [10, 2000], [0, 3000], [3000, 3000], [3000, 0]];
  const out = simplifyToCap(ring, 4, { closed: true, protect: [2] });
  assert.equal(out.length, 4);
  assert.ok(out.some((p) => p[0] === 10 && p[1] === 2000));
  assert.equal(simplifyToCap(ring, 1, { closed: true }).length, 3);
});

test("FIXTURE_FILE serves the simulator walk's route (demo/walk) as a valid fixture plan", async () => {
  const p = fixtureProviderFromEnv({ FIXTURE_FILE: "demo/walk/fixtures/route-edmonton.json" });
  const r = await findGrassRoute(EDMONTON_ORIGIN[0], EDMONTON_ORIGIN[1], 120, p);
  assert.ok(!isFailure(r));
  assert.equal(r.source, "fixture");
  assert.deepEqual(validatePlan(r), []);
  assert.ok(r.attribution.includes("OpenStreetMap"));
  const missing = await findGrassRoute(EDMONTON_ORIGIN[0], EDMONTON_ORIGIN[1], 120, fixtureProviderFromEnv({ FIXTURE_FILE: "nope.json" }));
  assert.ok(isFailure(missing) && missing.error.code === "PROVIDER_UNAVAILABLE");
});

test("validatePlan flags contract violations", async () => {
  const r = await findGrassRoute(ORIGIN[0], ORIGIN[1], 120);
  assert.ok(!isFailure(r));
  const bad = structuredClone(r);
  bad.destination.name = "x".repeat(41);
  bad.route.points = [r.route.points[0]!];
  bad.attribution = "café";
  assert.equal(validatePlan(bad).length, 3);
});
