import { crc32, deflateSync, inflateSync } from "node:zlib";

/** 8-bit RGBA raster. */
export interface Image {
  width: number;
  height: number;
  data: Uint8Array; // width * height * 4
}

export const newImage = (width: number, height: number, rgba: [number, number, number, number] = [0, 0, 0, 255]): Image => {
  const data = new Uint8Array(width * height * 4);
  for (let i = 0; i < data.length; i += 4) data.set(rgba, i);
  return { width, height, data };
};

const SIG = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const CHANNELS: Record<number, number> = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

/**
 * Minimal PNG decoder (no dependencies): non-interlaced, gray/RGB/palette/gray+alpha/RGBA,
 * bit depth 8 (and 1/2/4 for gray and palette). Covers standard OSM raster tiles.
 */
export function decodePng(buf: Uint8Array): Image {
  const b = Buffer.from(buf);
  if (!b.subarray(0, 8).equals(SIG)) throw new Error("not a PNG");
  let off = 8;
  let width = 0, height = 0, depth = 0, ctype = 0, interlace = 0;
  let palette: Buffer | null = null;
  let trns: Buffer | null = null;
  const idat: Buffer[] = [];
  while (off < b.length) {
    const len = b.readUInt32BE(off);
    const type = b.toString("latin1", off + 4, off + 8);
    const body = b.subarray(off + 8, off + 8 + len);
    if (type === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      depth = body[8]!;
      ctype = body[9]!;
      interlace = body[12]!;
    } else if (type === "PLTE") palette = body;
    else if (type === "tRNS") trns = body;
    else if (type === "IDAT") idat.push(body);
    else if (type === "IEND") break;
    off += 12 + len;
  }
  const ch = CHANNELS[ctype];
  if (!ch || interlace) throw new Error(`unsupported PNG (color type ${ctype}, interlace ${interlace})`);
  if (depth !== 8 && !((ctype === 0 || ctype === 3) && [1, 2, 4].includes(depth)))
    throw new Error(`unsupported PNG bit depth ${depth}`);

  const raw = inflateSync(Buffer.concat(idat));
  const bitsPP = ch * depth;
  const stride = Math.ceil((width * bitsPP) / 8);
  const bpp = Math.max(1, bitsPP >> 3);
  const lines = new Uint8Array(stride * height);
  let prev = new Uint8Array(stride);
  for (let y = 0; y < height; y++) {
    const ft = raw[y * (stride + 1)]!;
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = lines.subarray(y * stride, (y + 1) * stride);
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? cur[i - bpp]! : 0;
      const up = prev[i]!;
      const c = i >= bpp ? prev[i - bpp]! : 0;
      let v = src[i]!;
      if (ft === 1) v += a;
      else if (ft === 2) v += up;
      else if (ft === 3) v += (a + up) >> 1;
      else if (ft === 4) {
        const p = a + up - c, pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c;
      }
      cur[i] = v & 255;
    }
    prev = cur;
  }

  const out = new Uint8Array(width * height * 4);
  const sample = (row: Uint8Array, x: number): number => {
    if (depth === 8) return row[x]!;
    const bit = x * depth;
    return (row[bit >> 3]! >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
  };
  for (let y = 0; y < height; y++) {
    const row = lines.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      if (ctype === 3) {
        const idx = sample(row, x);
        out[o] = palette![idx * 3]!;
        out[o + 1] = palette![idx * 3 + 1]!;
        out[o + 2] = palette![idx * 3 + 2]!;
        out[o + 3] = trns && idx < trns.length ? trns[idx]! : 255;
      } else if (ctype === 0) {
        const g = Math.round((sample(row, x) * 255) / ((1 << depth) - 1));
        out.set([g, g, g, 255], o);
      } else if (ctype === 4) out.set([row[x * 2]!, row[x * 2]!, row[x * 2]!, row[x * 2 + 1]!], o);
      else if (ctype === 2) out.set([row[x * 3]!, row[x * 3 + 1]!, row[x * 3 + 2]!, 255], o);
      else out.set(row.subarray(x * 4, x * 4 + 4), o);
    }
  }
  return { width, height, data: out };
}

function chunk(type: string, body: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length);
  const tb = Buffer.concat([Buffer.from(type, "latin1"), body]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(tb) >>> 0);
  return Buffer.concat([len, tb, crc]);
}

/** Minimal RGBA PNG encoder (filter 0), used to send blocks to JEV and write debug images. */
export function encodePng(img: Image): Buffer {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(img.width, 0);
  ihdr.writeUInt32BE(img.height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const stride = img.width * 4;
  const raw = Buffer.alloc((stride + 1) * img.height);
  for (let y = 0; y < img.height; y++) raw.set(img.data.subarray(y * stride, (y + 1) * stride), y * (stride + 1) + 1);
  return Buffer.concat([SIG, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

export function crop(img: Image, x0: number, y0: number, w: number, h: number): Image {
  const out = newImage(w, h, [0, 0, 0, 0]);
  for (let y = 0; y < h; y++) {
    const sy = y0 + y;
    if (sy < 0 || sy >= img.height) continue;
    for (let x = 0; x < w; x++) {
      const sx = x0 + x;
      if (sx < 0 || sx >= img.width) continue;
      out.data.set(img.data.subarray((sy * img.width + sx) * 4, (sy * img.width + sx) * 4 + 4), (y * w + x) * 4);
    }
  }
  return out;
}
