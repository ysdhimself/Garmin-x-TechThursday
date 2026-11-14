import { toLocalM } from "./geo.ts";
import type { PointE6 } from "./types.ts";

function triArea(a: PointE6, b: PointE6, c: PointE6): number {
  const [bx, by] = toLocalM(b, a);
  const [cx, cy] = toLocalM(c, a);
  return Math.abs(bx * cy - by * cx) / 2;
}

/**
 * Visvalingam-Whyatt reduction: repeatedly drop the vertex whose removal changes the shape
 * least, so the entry point and real turns survive and near-collinear points go first.
 * - open polyline: first and last points always kept.
 * - closed ring (implicitly closed): stops at `minKeep` (default 3) vertices.
 * - `protect`: indices that must survive (e.g. the entry point on a green-space ring).
 * Keeps original order and never invents points.
 */
export function simplifyToCap(
  points: PointE6[],
  cap: number,
  opts: { closed?: boolean; protect?: number[]; minKeep?: number } = {},
): PointE6[] {
  const closed = opts.closed ?? false;
  const minKeep = opts.minKeep ?? (closed ? 3 : 2);
  const protect = new Set(opts.protect ?? []);
  if (!closed) {
    protect.add(0);
    protect.add(points.length - 1);
  }
  const target = Math.max(cap, minKeep);
  const alive = points.map((_, i) => i);

  while (alive.length > target) {
    let best = -1;
    let bestArea = Infinity;
    for (let k = 0; k < alive.length; k++) {
      const idx = alive[k]!;
      if (protect.has(idx)) continue;
      const prev = alive[(k - 1 + alive.length) % alive.length]!;
      const next = alive[(k + 1) % alive.length]!;
      const area = triArea(points[prev]!, points[idx]!, points[next]!);
      if (area < bestArea) {
        bestArea = area;
        best = k;
      }
    }
    if (best === -1) break;
    alive.splice(best, 1);
  }
  return alive.map((i) => points[i]!);
}

/** Index of the vertex closest to `p`. */
export function nearestIndex(ring: PointE6[], p: PointE6): number {
  let best = 0;
  let bestD = Infinity;
  ring.forEach((v, i) => {
    const [x, y] = toLocalM(v, p);
    const d = x * x + y * y;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  });
  return best;
}
