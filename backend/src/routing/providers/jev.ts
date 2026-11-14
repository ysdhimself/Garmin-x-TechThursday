import { randomUUID } from "node:crypto";
import { RoutingError } from "../errors.ts";
import type { Block } from "./blocks.ts";
import { encodePng, upscaleTo, type Image } from "./png.ts";
import type { FetchFn } from "./tiles.ts";

/** Scores each block 0..1 for "green space". Same order as the input. */
export interface BlockClassifier {
  name: string;
  classify(blocks: Block[]): Promise<number[]>;
}

/** JEV rejects images smaller than this on either side ("Invalid image dimensions"), found by probing. */
export const JEV_MIN_SIDE_PX = 280;

const QUESTION = "Is the map crop {img} mostly green space, such as a park, grass, garden, sports field or woods?";

/**
 * JEV (TypeSafe System One, https://api.typesafe.ai/docs). One request per batch of blocks:
 *   POST {JEV_API_URL}   (…/v1/systemone)
 *   Authorization: Bearer {JEV_API_KEY}, TypeSafe-Danger-Zone-Images: true
 *   { model, state, assets: { <placeholder>: { type: "image", format: "png", data_base64 } },
 *     questions: { b<i>: { type: "noul", instructions: "... <placeholder> ..." } } }
 *   -> { answers: { b<i>: { type: "noul", noul: <P(yes) 0..1> } }, model, usage }
 * Blocks are upscaled (nearest neighbour) to JEV's 280 px minimum. Any failure -> PROVIDER_UNAVAILABLE
 * with no upstream detail and never the key.
 */
export function jevClassifier(o: { url: string; apiKey: string; model?: string; batchSize?: number; fetchFn?: FetchFn }): BlockClassifier {
  const f = o.fetchFn ?? fetch;
  const unavailable = () => new RoutingError("PROVIDER_UNAVAILABLE", "Green-space classifier unavailable.");

  async function scoreBatch(batch: Block[]): Promise<number[]> {
    const tag = randomUUID().slice(0, 8);
    const assets: Record<string, object> = {};
    const questions: Record<string, object> = {};
    batch.forEach((b, j) => {
      const id = `img-${tag}-${j}`;
      assets[id] = { type: "image", format: "png", data_base64: encodePng(upscaleTo(b.image, JEV_MIN_SIDE_PX)).toString("base64") };
      questions[`b${j}`] = { type: "noul", instructions: QUESTION.replace("{img}", id) };
    });
    let res: Response;
    try {
      res = await f(o.url, {
        method: "POST",
        headers: { Authorization: `Bearer ${o.apiKey}`, "Content-Type": "application/json", "TypeSafe-Danger-Zone-Images": "true" },
        body: JSON.stringify({ model: o.model ?? "jev-latest", state: "Square crops of an OpenStreetMap street map.", assets, questions }),
        signal: AbortSignal.timeout(60_000),
      });
    } catch {
      throw unavailable();
    }
    // JEV rejects requests whose images are too large in total ("Invalid image request"): split and retry.
    if (res.status === 400 && batch.length > 1) {
      const half = Math.ceil(batch.length / 2);
      return [...(await scoreBatch(batch.slice(0, half))), ...(await scoreBatch(batch.slice(half)))];
    }
    if (!res.ok) throw unavailable();
    let answers: any;
    try {
      answers = (await res.json())?.answers;
    } catch {
      throw unavailable();
    }
    return batch.map((_, j) => {
      const p = answers?.[`b${j}`]?.noul;
      if (typeof p !== "number" || p < 0 || p > 1) throw unavailable();
      return p;
    });
  }

  return {
    name: "jev",
    async classify(blocks) {
      const out: number[] = [];
      const size = o.batchSize ?? 8; // 8 real 320 px map crops (~47 KB) is accepted; 16 is not
      for (let i = 0; i < blocks.length; i += size) out.push(...(await scoreBatch(blocks.slice(i, i + size))));
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
