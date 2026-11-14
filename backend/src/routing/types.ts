// Shared contract from PROJECT_PLAN.md ("Walking-plan endpoint"). Change only with Parts 1, 3 and 4.

/** [latE6, lonE6]: decimal degrees x 1,000,000, rounded. Latitude first. */
export type PointE6 = [number, number];

export interface Destination {
  name: string; // <= 40 ASCII chars
  point: PointE6;
  arrivalRadiusM: number;
}

export interface Route {
  points: PointE6[]; // 2-64 points, origin to entry point
  distanceM: number;
  durationS: number;
}

export interface GreenSpace {
  name: string; // <= 40 ASCII chars
  ring: PointE6[]; // 3-16 vertices, implicitly closed
}

export interface WalkPlan {
  version: 1;
  source: "live" | "fixture";
  origin: PointE6;
  destination: Destination;
  route: Route;
  greenSpaces: GreenSpace[]; // 1-2
  attribution: string; // <= 160 ASCII chars
}

export type ErrorCode = "NO_ROUTE" | "INVALID_REQUEST" | "PROVIDER_UNAVAILABLE";

export interface RoutingFailure {
  error: { code: ErrorCode; message: string };
}

export type RoutingResult = WalkPlan | RoutingFailure;

export const LIMITS = {
  maxResponseBytes: 8192,
  routePoints: { min: 2, max: 64 },
  ringVertices: { min: 3, max: 16 },
  greenSpaces: { min: 1, max: 2 },
  nameChars: 40,
  attributionChars: 160,
  defaultMaxWalkS: 120,
} as const;

/** What a provider hands back before simplification/validation. Never sent to the watch as-is. */
export interface Candidate {
  source: WalkPlan["source"];
  destination: Destination;
  route: Route;
  greenSpaces: GreenSpace[];
  attribution: string;
}

/**
 * Green-space discovery + pedestrian routing behind one seam.
 * Return null when nothing suitable exists (-> NO_ROUTE).
 * Throw RoutingError("PROVIDER_UNAVAILABLE", ...) when an upstream is down.
 * Never put credentials or raw upstream responses in a Candidate.
 */
export interface RoutingProvider {
  find(origin: PointE6, maxWalkS: number): Promise<Candidate | null>;
}
