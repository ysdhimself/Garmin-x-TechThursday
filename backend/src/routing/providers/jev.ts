import { RoutingError } from "../errors.ts";
import type { Block } from "./blocks.ts";
import { encodePng, type Image } from "./png.ts";
import type { FetchFn } from "./tiles.ts";

/** Scores each block 0..1 for "green space". Same order as the input. */
export interface BlockClassifier {
  name: string;
  classify(blocks: Block[]): Promise<number[]>;
}

/**
 * JEV image classifier.
 *
 * PLACEHOLDER CONTRACT (the real JEV API format is not confirmed yet; adjust here only):
 *   POST {JEV_API_URL}
 *   Authorization: Bearer {JEV_API_KEY}
 *   { "images": ["<base64 PNG>", ...] }
 *   -> { "scores": [0.93, ...] }  or  { "results": [{ "score": 0.93 } | { "label": "grass", "confidence": 0.93 }, ...] }
 * Any failure -> PROVIDER_UNAVAILABLE (no upstream detail, never the key).
 */
export function jevClassifier(o: { url: string; apiKey: string; batchSize?: number; fetchFn?: FetchFn; greenLabels?: string[] }): BlockClassifier {
  const f = o.fetchFn ?? fetch;
  const green = new Set((o.greenLabels ?? ["grass", "park", "green", "vegetation", "forest", "meadow"]).map((s) => s.toLowerCase()));
  const parse = (body: any, n: number): number[] => {
    let s: unknown[] | undefined = body?.scores;
    if (!s && Array.isArray(body?.results))
      s = body.results.map((r: any) =>
        typeof r?.score === "number" ? r.score : green.has(String(r?.label ?? "").toLowerCase()) ? (r?.confidence ?? 1) : 1 - (r?.confidence ?? 1),
      );
    if (!Array.isArray(s) || s.length !== n || !s.every((v) => typeof v === "number" && v >= 0 && v <= 1))
      throw new Error("bad JEV response");
    return s as number[];
  };
  return {
    name: "jev",
    async classify(blocks) {
      const out: number[] = [];
      const size = o.batchSize ?? 32;
      for (let i = 0; i < blocks.length; i += size) {
        const batch = blocks.slice(i, i + size);
        try {
          const res = await f(o.url, {
            method: "POST",
            headers: { Authorization: `Bearer ${o.apiKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({ images: batch.map((b) => encodePng(b.image).toString("base64")) }),
            signal: AbortSignal.timeout(15_000),
          });
          if (!res.ok) throw new Error(String(res.status));
          out.push(...parse(await res.json(), batch.length));
        } catch {
          throw new RoutingError("PROVIDER_UNAVAILABLE", "Green-space classifier unavailable.");
        }
      }
      return out;
    },
  };
}

/** OSM Carto fills for parks, grass, gardens, pitches, woods. */
const OSM_GREENS: [number, number, number][] = [
  [200, 250, 204], // leisure=park
  [205, 235, 176], // landuse=grass / meadow / village_green
  [173, 209, 158], // wood / forest
  [170, 224, 203], // pitch
  [222, 246, 192], // garden / recreation_ground
  [223, 252, 226], // playground-ish light green
];

export function greenFraction(img: Image, tol = 14): number {
  let green = 0, total = 0;
  for (let i = 0; i < img.data.length; i += 4) {
    if (img.data[i + 3]! < 128) continue;
    total++;
    const r = img.data[i]!, g = img.data[i + 1]!, b = img.data[i + 2]!;
    if (OSM_GREENS.some(([R, G, B]) => Math.abs(r - R) <= tol && Math.abs(g - G) <= tol && Math.abs(b - B) <= tol)) green++;
  }
  return total ? green / total : 0;
}

/** Offline fallback and test double: share of pixels painted in OSM's green-space colours. */
export function colorClassifier(): BlockClassifier {
  return { name: "color", classify: async (blocks) => blocks.map((b) => greenFraction(b.image)) };
}
