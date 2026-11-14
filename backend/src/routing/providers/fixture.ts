import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { RoutingError } from "../errors.ts";
import { haversineM } from "../geo.ts";
import type { Candidate, PointE6, RoutingProvider, WalkPlan } from "../types.ts";

const FIXTURE_DIR = fileURLToPath(new URL("../../../fixtures/routes/", import.meta.url));

/** Fixture mode serves the prepared plan to any origin this close to the fixture origin. */
const MATCH_RADIUS_M = 250;

/** Always `source: "fixture"` so the watch can label demo mode. */
export function fixtureProvider(file = "demo-park.json"): RoutingProvider {
  return {
    async find(origin: PointE6): Promise<Candidate | null> {
      let plan: WalkPlan;
      try {
        plan = JSON.parse(await readFile(FIXTURE_DIR + file, "utf8"));
      } catch {
        throw new RoutingError("PROVIDER_UNAVAILABLE", "Fixture data could not be loaded.");
      }
      if (haversineM(origin, plan.origin) > MATCH_RADIUS_M) return null;
      const { destination, route, greenSpaces, attribution } = plan;
      return { source: "fixture", destination, route, greenSpaces, attribution };
    },
  };
}
