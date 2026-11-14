import type { PointE6 } from "./types.ts";

const EARTH_R_M = 6371008.8;
const rad = (deg: number) => (deg * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;

export const toE6 = (d: number) => Math.round(d * 1e6);

export function haversineM(a: PointE6, b: PointE6): number {
  const dLat = rad((b[0] - a[0]) / 1e6);
  const dLon = rad((b[1] - a[1]) / 1e6);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a[0] / 1e6)) * Math.cos(rad(b[0] / 1e6)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_R_M * Math.asin(Math.sqrt(h));
}

export function routeLengthM(points: PointE6[]): number {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += haversineM(points[i - 1]!, points[i]!);
  return total;
}

/** Local flat-earth metres relative to a reference point. Fine at park scale. */
export function toLocalM(p: PointE6, ref: PointE6): [number, number] {
  const x = rad((p[1] - ref[1]) / 1e6) * EARTH_R_M * Math.cos(rad(ref[0] / 1e6));
  const y = rad((p[0] - ref[0]) / 1e6) * EARTH_R_M;
  return [x, y];
}

export const isValidE6 = (p: unknown): p is PointE6 =>
  Array.isArray(p) &&
  p.length === 2 &&
  Number.isInteger(p[0]) &&
  Number.isInteger(p[1]) &&
  Math.abs(p[0]) <= 90_000_000 &&
  Math.abs(p[1]) <= 180_000_000;

/** Decimal degrees. */
export interface BBox { south: number; west: number; north: number; east: number }

export function bboxAround(p: PointE6, radiusM: number): BBox {
  const dLat = deg(radiusM / EARTH_R_M);
  const dLon = dLat / Math.cos(rad(p[0] / 1e6));
  return { south: p[0] / 1e6 - dLat, north: p[0] / 1e6 + dLat, west: p[1] / 1e6 - dLon, east: p[1] / 1e6 + dLon };
}

// ---- Web-Mercator ("slippy map") tile math. Global pixel coords at zoom z, 256 px tiles. ----

export const TILE_PX = 256;

export function latLonToPixel(latDeg: number, lonDeg: number, z: number): [number, number] {
  const size = TILE_PX * 2 ** z;
  const x = ((lonDeg + 180) / 360) * size;
  const s = Math.sin(rad(latDeg));
  const y = (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * size;
  return [x, y];
}

export function pixelToLatLon(x: number, y: number, z: number): [number, number] {
  const size = TILE_PX * 2 ** z;
  const lon = (x / size) * 360 - 180;
  const lat = deg(Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / size))));
  return [lat, lon];
}

export const pixelToE6 = (x: number, y: number, z: number): PointE6 => {
  const [lat, lon] = pixelToLatLon(x, y, z);
  return [toE6(lat), toE6(lon)];
};

/** Metres per pixel at a latitude and zoom. */
export const metresPerPixel = (latDeg: number, z: number) =>
  (2 * Math.PI * EARTH_R_M * Math.cos(rad(latDeg))) / (TILE_PX * 2 ** z);
