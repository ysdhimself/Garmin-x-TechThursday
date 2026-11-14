import { latLonToPixel, pixelToE6, toLocalM } from "../geo.ts";
import type { PointE6 } from "../types.ts";
import type { BlockGrid } from "./blocks.ts";
import type { Mosaic } from "./tiles.ts";

export interface GreenRegion {
  blocks: number; // size in blocks
  ring: PointE6[]; // outer boundary, implicitly closed, includes `entry` as a vertex
  entry: PointE6; // boundary point nearest the origin (origin itself when already inside)
  entryDistM: number;
  containsOrigin: boolean;
}

type Corner = [number, number]; // grid-corner coords (col, row)

/** Outer boundary of a set of grid cells, as a corner loop (clockwise on screen). */
function traceOuter(cells: Set<number>, cols: number): Corner[] {
  const has = (r: number, c: number) => c >= 0 && c < cols && r >= 0 && cells.has(r * cols + c);
  const edges = new Map<string, Corner[]>();
  const add = (a: Corner, b: Corner) => {
    const k = a.join(",");
    (edges.get(k) ?? edges.set(k, []).get(k)!).push(b);
  };
  for (const id of cells) {
    const r = Math.floor(id / cols), c = id % cols;
    if (!has(r - 1, c)) add([c, r], [c + 1, r]);
    if (!has(r, c + 1)) add([c + 1, r], [c + 1, r + 1]);
    if (!has(r + 1, c)) add([c + 1, r + 1], [c, r + 1]);
    if (!has(r, c - 1)) add([c, r + 1], [c, r]);
  }
  const loops: Corner[][] = [];
  for (const [startKey, ends] of edges) {
    while (ends.length) {
      const loop: Corner[] = [startKey.split(",").map(Number) as Corner];
      let next = ends.pop()!;
      while (next.join(",") !== startKey) {
        loop.push(next);
        const out = edges.get(next.join(","));
        if (!out?.length) break;
        next = out.pop()!;
      }
      loops.push(loop);
    }
  }
  const area = (l: Corner[]) => Math.abs(l.reduce((s, p, i) => s + p[0] * l[(i + 1) % l.length]![1] - l[(i + 1) % l.length]![0] * p[1], 0)) / 2;
  const outer = loops.sort((a, b) => area(b) - area(a))[0] ?? [];
  // Drop collinear corners.
  return outer.filter((p, i) => {
    const a = outer[(i - 1 + outer.length) % outer.length]!, b = outer[(i + 1) % outer.length]!;
    return (p[0] - a[0]) * (b[1] - p[1]) - (p[1] - a[1]) * (b[0] - p[0]) !== 0;
  });
}

/** Nearest point on the closed ring to `p`; returns the point and the segment it lies on. */
function nearestOnRing(ring: PointE6[], p: PointE6): { point: PointE6; seg: number; distM: number } {
  let best = { point: ring[0]!, seg: 0, distM: Infinity };
  for (let i = 0; i < ring.length; i++) {
    const a = ring[i]!, b = ring[(i + 1) % ring.length]!;
    const [ax, ay] = toLocalM(a, p), [bx, by] = toLocalM(b, p);
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    const t = len2 ? Math.max(0, Math.min(1, -(ax * dx + ay * dy) / len2)) : 0;
    const qx = ax + t * dx, qy = ay + t * dy;
    const d = Math.hypot(qx, qy);
    if (d < best.distM)
      best = { point: [Math.round(a[0] + t * (b[0] - a[0])), Math.round(a[1] + t * (b[1] - a[1]))], seg: i, distM: d };
  }
  return best;
}

/**
 * Green blocks -> connected regions (4-neighbour) -> outline ring + entry point, nearest first.
 * A "region" is where the map is drawn green; it is not proof of grass or public access.
 */
export function findGreenRegions(
  grid: BlockGrid,
  scores: number[],
  mosaic: Mosaic,
  origin: PointE6,
  opts: { minScore?: number; minBlocks?: number } = {},
): GreenRegion[] {
  const minScore = opts.minScore ?? 0.5;
  const minBlocks = opts.minBlocks ?? 2;
  const { rows, cols, size } = grid;
  const green = scores.map((s) => s >= minScore);
  const seen = new Uint8Array(rows * cols);

  const [opx, opy] = latLonToPixel(origin[0] / 1e6, origin[1] / 1e6, mosaic.zoom);
  const oCol = Math.floor((opx - mosaic.originPx[0]) / size), oRow = Math.floor((opy - mosaic.originPx[1]) / size);
  const originCell = oRow >= 0 && oRow < rows && oCol >= 0 && oCol < cols ? oRow * cols + oCol : -1;
  const toE6 = ([c, r]: Corner) => pixelToE6(mosaic.originPx[0] + c * size, mosaic.originPx[1] + r * size, mosaic.zoom);

  const regions: GreenRegion[] = [];
  for (let start = 0; start < rows * cols; start++) {
    if (!green[start] || seen[start]) continue;
    const cells = new Set<number>();
    const stack = [start];
    seen[start] = 1;
    while (stack.length) {
      const id = stack.pop()!;
      cells.add(id);
      const r = Math.floor(id / cols), c = id % cols;
      for (const [nr, nc] of [[r - 1, c], [r + 1, c], [r, c - 1], [r, c + 1]] as const) {
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        const n = nr * cols + nc;
        if (green[n] && !seen[n]) {
          seen[n] = 1;
          stack.push(n);
        }
      }
    }
    if (cells.size < minBlocks) continue;
    const ring = traceOuter(cells, cols).map(toE6);
    if (ring.length < 3) continue;
    const containsOrigin = cells.has(originCell);
    if (containsOrigin) {
      regions.push({ blocks: cells.size, ring, entry: origin, entryDistM: 0, containsOrigin });
      continue;
    }
    const near = nearestOnRing(ring, origin);
    const atVertex = ring.findIndex((v) => v[0] === near.point[0] && v[1] === near.point[1]);
    if (atVertex === -1) ring.splice(near.seg + 1, 0, near.point);
    regions.push({ blocks: cells.size, ring, entry: near.point, entryDistM: near.distM, containsOrigin });
  }
  return regions.sort((a, b) => a.entryDistM - b.entryDistM);
}
