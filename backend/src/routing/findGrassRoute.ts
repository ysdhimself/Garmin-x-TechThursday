import { RoutingError, failure } from "./errors.ts";
import { isValidE6 } from "./geo.ts";
import { fixtureProvider } from "./providers/fixture.ts";
import { nearestIndex, simplifyToCap } from "./simplify.ts";
import { LIMITS, type Candidate, type PointE6, type RoutingProvider, type RoutingResult, type WalkPlan } from "./types.ts";
import { validatePlan } from "./validate.ts";

const NO_ROUTE_MSG = "No accessible green space within this walk budget.";

function build(c: Candidate, routeCap: number, ringCap: number): WalkPlan {
  return {
    version: 1,
    source: c.source,
    origin: c.route.points[0]!,
    destination: c.destination,
    route: { points: simplifyToCap(c.route.points, routeCap), distanceM: c.route.distanceM, durationS: c.route.durationS },
    greenSpaces: c.greenSpaces.slice(0, LIMITS.greenSpaces.max).map((g) => ({
      name: g.name,
      ring: simplifyToCap(g.ring, ringCap, { closed: true, protect: [nearestIndex(g.ring, c.destination.point)] }),
    })),
    attribution: c.attribution,
  };
}

/**
 * Origin -> bounded plan for the watch, or an explicit failure. Expected failures are
 * returned, never thrown. Part 3 serves a plan unchanged and maps error.code to a status.
 */
export async function findGrassRoute(
  originLatE6: number,
  originLonE6: number,
  maxWalkS: number = LIMITS.defaultMaxWalkS,
  provider: RoutingProvider = fixtureProvider(),
): Promise<RoutingResult> {
  const origin: PointE6 = [originLatE6, originLonE6];
  if (!isValidE6(origin) || !Number.isInteger(maxWalkS) || maxWalkS <= 0)
    return failure("INVALID_REQUEST", "originLatE6, originLonE6 and maxWalkS must be valid integers.");

  let candidate: Candidate | null;
  try {
    candidate = await provider.find(origin, maxWalkS);
  } catch (e) {
    if (e instanceof RoutingError) return failure(e.code, e.message);
    return failure("PROVIDER_UNAVAILABLE", "Routing provider unavailable.");
  }

  // Never silently exceed the requested budget; the user can choose a longer search.
  if (!candidate || candidate.route.durationS > maxWalkS) return failure("NO_ROUTE", NO_ROUTE_MSG);

  let routeCap: number = LIMITS.routePoints.max;
  let ringCap: number = LIMITS.ringVertices.max;
  let plan = build(candidate, routeCap, ringCap);
  while (validatePlan(plan).length > 0) {
    if (routeCap <= 8 && ringCap <= 6) return failure("NO_ROUTE", "Result is too detailed for the watch payload budget.");
    routeCap = Math.max(8, Math.floor(routeCap * 0.75));
    ringCap = Math.max(6, ringCap - 2);
    plan = build(candidate, routeCap, ringCap);
  }
  return plan;
}
