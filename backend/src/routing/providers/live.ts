import { RoutingError } from "../errors.ts";
import { bboxAround } from "../geo.ts";
import { LIMITS, type Candidate, type PointE6, type RoutingProvider } from "../types.ts";
import { cutBlocks } from "./blocks.ts";
import { colorClassifier, jevClassifier, type BlockClassifier } from "./jev.ts";
import { findGreenRegions, type GreenRegion } from "./regions.ts";
import { footRoute, WALK_SPEED_MPS } from "./router.ts";
import { fetchMosaic, type FetchFn, type Mosaic } from "./tiles.ts";

export interface LiveOptions {
  classifier: BlockClassifier;
  tileUrl: string;
  tileZoom: number;
  routerUrl: string;
  userAgent: string;
  blockPx?: number;
  minScore?: number;
  minBlocks?: number;
  maxCandidates?: number;
  arrivalRadiusM?: number;
  fetchFn?: FetchFn;
  /** Debug hook (live-check script): sees the mosaic, scores and regions. */
  onDebug?: (d: { mosaic: Mosaic; rows: number; cols: number; size: number; scores: number[]; regions: GreenRegion[] }) => void;
}

/**
 * Live provider: map tiles around the origin -> blocks -> classifier (JEV) -> green regions ->
 * foot route to the nearest few -> the walk within budget closest to ~120 s.
 * Origin coordinates are never logged.
 */
export function liveProvider(o: LiveOptions): RoutingProvider {
  return {
    async find(origin: PointE6, maxWalkS: number): Promise<Candidate | null> {
      const radiusM = maxWalkS * WALK_SPEED_MPS;
      const mosaic = await fetchMosaic(bboxAround(origin, radiusM), {
        url: o.tileUrl, zoom: o.tileZoom, userAgent: o.userAgent, fetchFn: o.fetchFn,
      });
      const grid = cutBlocks(mosaic, o.blockPx ?? 64);
      const scores = await o.classifier.classify(grid.blocks);
      const regions = findGreenRegions(grid, scores, mosaic, origin, { minScore: o.minScore, minBlocks: o.minBlocks });
      o.onDebug?.({ mosaic, rows: grid.rows, cols: grid.cols, size: grid.size, scores, regions });

      const target = Math.min(LIMITS.defaultMaxWalkS, maxWalkS);
      let best: { cand: Candidate; gap: number } | null = null;
      for (const reg of regions.filter((r) => r.entryDistM <= radiusM).slice(0, o.maxCandidates ?? 3)) {
        let points: PointE6[], distanceM: number, durationS: number;
        if (reg.containsOrigin) {
          points = [origin, origin]; // already standing in green space
          distanceM = 0;
          durationS = 0;
        } else {
          const r = await footRoute(origin, reg.entry, { url: o.routerUrl, userAgent: o.userAgent, fetchFn: o.fetchFn });
          if (!r || r.durationS > maxWalkS) continue;
          // The router snaps to the path network; pin the ends to the real origin and entry.
          points = [origin, ...r.points, reg.entry];
          ({ distanceM, durationS } = r);
        }
        const gap = Math.abs(durationS - target);
        if (best && gap >= best.gap) continue;
        best = {
          gap,
          cand: {
            source: "live",
            destination: { name: "Green Space", point: reg.entry, arrivalRadiusM: o.arrivalRadiusM ?? 25 },
            route: { points, distanceM, durationS },
            greenSpaces: [{ name: "Green Space", ring: reg.ring }],
            attribution: `Map tiles (c) OpenStreetMap contributors. Green areas classified by ${o.classifier.name === "jev" ? "JEV" : "map colour"}.`,
          },
        };
      }
      return best?.cand ?? null;
    },
  };
}

/** Build from environment variables (see backend/.env.example). */
export function liveProviderFromEnv(env: Record<string, string | undefined> = process.env, fetchFn?: FetchFn): RoutingProvider {
  let classifier: BlockClassifier;
  if ((env.CLASSIFIER ?? "jev") === "color") classifier = colorClassifier();
  else {
    if (!env.JEV_API_KEY || !env.JEV_API_URL) throw new RoutingError("PROVIDER_UNAVAILABLE", "JEV is not configured (JEV_API_KEY / JEV_API_URL).");
    classifier = jevClassifier({ url: env.JEV_API_URL, apiKey: env.JEV_API_KEY, model: env.JEV_MODEL || undefined, fetchFn });
  }
  if (!env.ROUTER_URL) throw new RoutingError("PROVIDER_UNAVAILABLE", "ROUTER_URL is not configured.");
  return liveProvider({
    classifier,
    tileUrl: env.TILE_URL ?? "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    tileZoom: Number(env.TILE_ZOOM ?? 17),
    routerUrl: env.ROUTER_URL,
    userAgent: env.USER_AGENT ?? "touch-grass-demo/0.1",
    minScore: env.GREEN_MIN_SCORE ? Number(env.GREEN_MIN_SCORE) : undefined,
    blockPx: env.BLOCK_PX ? Number(env.BLOCK_PX) : undefined,
    fetchFn,
  });
}
