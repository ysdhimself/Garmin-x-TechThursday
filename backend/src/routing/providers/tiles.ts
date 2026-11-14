import { RoutingError } from "../errors.ts";
import { TILE_PX, latLonToPixel, type BBox } from "../geo.ts";
import { decodePng, newImage, type Image } from "./png.ts";

export type FetchFn = typeof fetch;

/** Stitched tiles plus where they sit in global pixel space at `zoom`. */
export interface Mosaic {
  image: Image;
  zoom: number;
  originPx: [number, number]; // global pixel of the image's top-left corner
}

export interface TileOptions {
  url: string; // template with {z} {x} {y}
  zoom: number;
  userAgent: string;
  fetchFn?: FetchFn;
  maxTiles?: number;
  now?: () => number;
}

const TTL_MS = 10 * 60_000;
const cache = new Map<string, { at: number; img: Image }>();
export const _clearTileCache = () => cache.clear();

async function fetchTile(z: number, x: number, y: number, o: TileOptions): Promise<Image> {
  const key = `${z}/${x}/${y}`;
  const now = (o.now ?? Date.now)();
  const hit = cache.get(key);
  if (hit && now - hit.at < TTL_MS) return hit.img;
  const url = o.url.replace("{z}", String(z)).replace("{x}", String(x)).replace("{y}", String(y));
  let img: Image;
  try {
    const res = await (o.fetchFn ?? fetch)(url, { headers: { "User-Agent": o.userAgent }, signal: AbortSignal.timeout(8_000) });
    if (!res.ok) throw new Error(String(res.status));
    img = decodePng(new Uint8Array(await res.arrayBuffer()));
  } catch {
    throw new RoutingError("PROVIDER_UNAVAILABLE", "Map tiles unavailable.");
  }
  cache.set(key, { at: now, img });
  return img;
}

/**
 * Fetch and stitch the rendered map tiles that cover `bbox`. Tile-keyed cache so repeated
 * nearby requests don't refetch. OSM's tile policy allows light use only: keep maxTiles small.
 */
export async function fetchMosaic(bbox: BBox, o: TileOptions): Promise<Mosaic> {
  const z = o.zoom;
  const [x0, y0] = latLonToPixel(bbox.north, bbox.west, z);
  const [x1, y1] = latLonToPixel(bbox.south, bbox.east, z);
  const tx0 = Math.floor(x0 / TILE_PX), ty0 = Math.floor(y0 / TILE_PX);
  const tx1 = Math.floor(x1 / TILE_PX), ty1 = Math.floor(y1 / TILE_PX);
  const nx = tx1 - tx0 + 1, ny = ty1 - ty0 + 1;
  if (nx * ny > (o.maxTiles ?? 25)) throw new RoutingError("INVALID_REQUEST", "Search area too large; lower maxWalkS or TILE_ZOOM.");

  const image = newImage(nx * TILE_PX, ny * TILE_PX, [0, 0, 0, 0]);
  const jobs: Promise<void>[] = [];
  for (let ty = ty0; ty <= ty1; ty++)
    for (let tx = tx0; tx <= tx1; tx++)
      jobs.push(
        fetchTile(z, tx, ty, o).then((t) => {
          const ox = (tx - tx0) * TILE_PX, oy = (ty - ty0) * TILE_PX;
          for (let y = 0; y < Math.min(t.height, TILE_PX); y++)
            image.data.set(t.data.subarray(y * t.width * 4, (y * t.width + Math.min(t.width, TILE_PX)) * 4), ((oy + y) * image.width + ox) * 4);
        }),
      );
  await Promise.all(jobs);
  return { image, zoom: z, originPx: [tx0 * TILE_PX, ty0 * TILE_PX] };
}
