import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { RoutingError } from "../errors.ts";
import { haversineM } from "../geo.ts";
import type { Candidate, PointE6, RoutingProvider, WalkPlan } from "../types.ts";

const REPO_ROOT = fileURLToPath(new URL("../../../../", import.meta.url));
const DEFAULT_FILE = "backend/fixtures/routes/demo-park.json";

/** Fixture mode serves the prepared plan to any origin this close to the fixture origin. */
const MATCH_RADIUS_M = 250;

/**
 * Serves a prepared walk plan. `file` is absolute or relative to the repo root.
 * Always `source: "fixture"` so the watch can label demo mode.
 */
export function fixtureProvider(file = DEFAULT_FILE): RoutingProvider {
  const path = isAbsolute(file) ? file : resolve(REPO_ROOT, file);
  return {
    async find(origin: PointE6): Promise<Candidate | null> {
      let plan: WalkPlan;
      try {
        plan = JSON.parse(await readFile(path, "utf8"));
      } catch {
        throw new RoutingError("PROVIDER_UNAVAILABLE", "Fixture data could not be loaded.");
      }
      if (haversineM(origin, plan.origin) > MATCH_RADIUS_M) return null;
      const { destination, route, greenSpaces, attribution } = plan;
      return { source: "fixture", destination, route, greenSpaces, attribution };
    },
  };
}

/** FIXTURE_FILE picks the plan, e.g. demo/walk/fixtures/route-edmonton.json to match the simulated walk. */
export const fixtureProviderFromEnv = (env: Record<string, string | undefined> = process.env) =>
  fixtureProvider(env.FIXTURE_FILE || DEFAULT_FILE);
