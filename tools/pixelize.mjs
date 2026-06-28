import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { decodePng, encodePng } from "./png.mjs";
import { labDeltaE, hexToRgb } from "./color.mjs";
import { DB32 } from "./palette.mjs";

// Deterministic pixel-art post-process: box-downscale the long side to `native`,
// quantize every opaque pixel to the nearest palette colour (ΔE76), and harden
// alpha to 0/255. Turns a soft 1024px LoRA generation into a clean, palette-locked
// native-res sprite. Pure: { width, height, channels, data } in and out, no I/O.
export function pixelize(img, { native = 64, palette = DB32, alphaThreshold = 128 } = {}) {
  const pal = palette.map((c) => (Array.isArray(c) ? c : hexToRgb(c)));
  if (pal.length === 0) throw new Error("pixelize: empty palette");
  const { width: W, height: H, channels, data } = img;
  // Downscale-only: never upscale a source already at/below native (cap scale at 1).
  const scale = Math.min(1, native / Math.max(W, H));
  const tw = Math.max(1, Math.round(W * scale));
  const th = Math.max(1, Math.round(H * scale));
  const out = new Uint8Array(tw * th * channels);
  for (let ty = 0; ty < th; ty++) {
    for (let tx = 0; tx < tw; tx++) {
      // source box this target pixel averages over
      const x0 = Math.floor((tx * W) / tw), x1 = Math.max(x0 + 1, Math.floor(((tx + 1) * W) / tw));
      const y0 = Math.floor((ty * H) / th), y1 = Math.max(y0 + 1, Math.floor(((ty + 1) * H) / th));
      // Straight-alpha box average (RGB is NOT premultiplied by alpha): a coloured
      // transparent halo contributes full RGB weight. Acceptable here — the palette
      // quantize below absorbs the small drift. Revisit with alpha-weighted averaging
      // only if proving-ground sprites show edge-colour contamination.
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let sy = y0; sy < y1; sy++) {
        for (let sx = x0; sx < x1; sx++) {
          const o = (sy * W + sx) * channels;
          r += data[o]; g += data[o + 1]; b += data[o + 2];
          a += channels === 4 ? data[o + 3] : 255;
          n++;
        }
      }
      r = Math.round(r / n); g = Math.round(g / n); b = Math.round(b / n); a = Math.round(a / n);
      const oo = (ty * tw + tx) * channels;
      if (channels === 4 && a < alphaThreshold) { out[oo] = out[oo + 1] = out[oo + 2] = out[oo + 3] = 0; continue; }
      let best = pal[0], bestD = Infinity;
      for (const p of pal) { const d = labDeltaE([r, g, b], p); if (d < bestD) { bestD = d; best = p; } }
      out[oo] = best[0]; out[oo + 1] = best[1]; out[oo + 2] = best[2];
      if (channels === 4) out[oo + 3] = 255;
    }
  }
  return { width: tw, height: th, channels, data: out };
}

// Read a PNG, pixelize it, write the canonical PNG. Returns the output dimensions.
export function pixelizeFile(inPath, outPath, opts = {}) {
  const img = decodePng(readFileSync(inPath));
  const out = pixelize(img, opts);
  writeFileSync(outPath, encodePng(out.width, out.height, out.channels, out.data));
  return { width: out.width, height: out.height, channels: out.channels };
}

// CLI: node tools/pixelize.mjs <in.png> <out.png> '<json {native?, palette?, alphaThreshold?}>'
export function pixelizeCli(argv, { log = console.log, err = console.error } = {}) {
  const [inPath, outPath, optsJson] = argv;
  if (!inPath || !outPath) { err("usage: pixelize <in.png> <out.png> '<json opts>'"); return 1; }
  let opts = {};
  if (optsJson) { try { opts = JSON.parse(optsJson); } catch (e) { err(`pixelize: bad JSON opts: ${e.message}`); return 1; } }
  let res;
  try { res = pixelizeFile(inPath, outPath, opts); } catch (e) { err(`pixelize: ${e.message}`); return 1; }
  log(`PIXELIZE ${JSON.stringify(res)}`);
  return 0;
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exit(pixelizeCli(process.argv.slice(2)));
}
