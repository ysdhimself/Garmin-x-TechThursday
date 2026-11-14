import { crop, type Image } from "./png.ts";
import type { Mosaic } from "./tiles.ts";

export interface Block {
  row: number;
  col: number;
  image: Image; // size x size crop
}

export interface BlockGrid {
  rows: number;
  cols: number;
  size: number; // block edge in pixels
  blocks: Block[]; // row-major
}

/** Cut the stitched map into size x size pixel blocks (the units JEV classifies). */
export function cutBlocks(m: Mosaic, size = 32): BlockGrid {
  const rows = Math.floor(m.image.height / size);
  const cols = Math.floor(m.image.width / size);
  const blocks: Block[] = [];
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++) blocks.push({ row: r, col: c, image: crop(m.image, c * size, r * size, size, size) });
  return { rows, cols, size, blocks };
}
