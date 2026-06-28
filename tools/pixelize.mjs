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
  const scale = native / Math.max(W, H);
  const tw = Math.max(1, Math.round(W * scale));
  const th = Math.max(1, Math.round(H * scale));
  const out = new Uint8Array(tw * th * channels);
  for (let ty = 0; ty < th; ty++) {
    for (let tx = 0; tx < tw; tx++) {
      // source box this target pixel averages over
      const x0 = Math.floor((tx * W) / tw), x1 = Math.max(x0 + 1, Math.floor(((tx + 1) * W) / tw));
      const y0 = Math.floor((ty * H) / th), y1 = Math.max(y0 + 1, Math.floor(((ty + 1) * H) / th));
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
