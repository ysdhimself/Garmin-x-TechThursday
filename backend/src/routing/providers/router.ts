import { RoutingError } from "../errors.ts";
import { toE6 } from "../geo.ts";
import type { PointE6 } from "../types.ts";
import type { FetchFn } from "./tiles.ts";

export const WALK_SPEED_MPS = 1.4;

export interface FootRoute {
  points: PointE6[];
  distanceM: number;
  durationS: number;
}

/**
 * OSRM-compatible foot route. Returns null when the router reports no route.
 * Duration = distance / 1.4 m/s. Use a router with a real foot profile (self-hosted OSRM foot,
 * Valhalla, ORS); the public OSRM demo may route by car.
 */
export async function footRoute(from: PointE6, to: PointE6, o: { url: string; userAgent: string; fetchFn?: FetchFn }): Promise<FootRoute | null> {
  const coord = (p: PointE6) => `${p[1] / 1e6},${p[0] / 1e6}`;
  const url = `${o.url.replace(/\/$/, "")}/route/v1/foot/${coord(from)};${coord(to)}?overview=full&geometries=geojson`;
  let res: Response;
  let body: any;
  try {
    res = await (o.fetchFn ?? fetch)(url, { headers: { "User-Agent": o.userAgent }, signal: AbortSignal.timeout(8_000) });
    body = await res.json();
  } catch {
    throw new RoutingError("PROVIDER_UNAVAILABLE", "Pedestrian routing unavailable.");
  }
  if (body?.code === "NoRoute") return null;
  if (!res.ok || body?.code !== "Ok" || !body.routes?.[0]) throw new RoutingError("PROVIDER_UNAVAILABLE", "Pedestrian routing unavailable.");
  const r = body.routes[0];
  const points: PointE6[] = (r.geometry?.coordinates ?? []).map((c: [number, number]) => [toE6(c[1]), toE6(c[0])] as PointE6);
  if (points.length < 2) return null;
  const distanceM = Math.round(r.distance);
  return { points, distanceM, durationS: Math.round(distanceM / WALK_SPEED_MPS) };
}
