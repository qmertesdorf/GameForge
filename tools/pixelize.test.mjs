import { test, expect, describe } from "vitest";
import { pixelize } from "./pixelize.mjs";

// A pure-colour palette so nearest-colour is unambiguous in the assertions.
const PAL = ["#ff0000", "#00ff00", "#0000ff", "#000000", "#ffffff"];
const PAL_KEYS = new Set([0xff0000, 0x00ff00, 0x0000ff, 0x000000, 0xffffff]);

function solidRGBA(w, h, [r, g, b, a]) {
  const d = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) { d[i * 4] = r; d[i * 4 + 1] = g; d[i * 4 + 2] = b; d[i * 4 + 3] = a; }
  return { width: w, height: h, channels: 4, data: d };
}

describe("pixelize", () => {
  test("downscales the long side to `native`, preserving aspect", () => {
    const out = pixelize(solidRGBA(16, 8, [255, 0, 0, 255]), { native: 4, palette: PAL });
    expect(out.width).toBe(4);
    expect(out.height).toBe(2);
  });

  test("quantizes every opaque pixel to an exact palette colour", () => {
    const out = pixelize(solidRGBA(8, 8, [250, 10, 10, 255]), { native: 4, palette: PAL });
    for (let i = 0; i < out.width * out.height; i++) {
      const o = i * 4;
      const key = (out.data[o] << 16) | (out.data[o + 1] << 8) | out.data[o + 2];
      expect(PAL_KEYS.has(key)).toBe(true);
    }
    // near-red input → exact #ff0000
    expect(out.data[0]).toBe(255); expect(out.data[1]).toBe(0); expect(out.data[2]).toBe(0);
  });

  test("hardens alpha: below threshold → fully transparent, above → opaque", () => {
    const out = pixelize(solidRGBA(8, 8, [255, 255, 255, 60]), { native: 4, palette: PAL, alphaThreshold: 128 });
    for (let i = 0; i < out.width * out.height; i++) expect(out.data[i * 4 + 3]).toBe(0);
    const out2 = pixelize(solidRGBA(8, 8, [255, 255, 255, 200]), { native: 4, palette: PAL, alphaThreshold: 128 });
    for (let i = 0; i < out2.width * out2.height; i++) expect(out2.data[i * 4 + 3]).toBe(255);
  });

  test("never emits a partial-alpha pixel", () => {
    // a 50/50 alpha mix would average to ~127 — must still snap to 0 or 255
    const d = new Uint8Array(4 * 4 * 4);
    for (let i = 0; i < 16; i++) { d[i * 4] = 255; d[i * 4 + 3] = i % 2 ? 255 : 0; }
    const out = pixelize({ width: 4, height: 4, channels: 4, data: d }, { native: 2, palette: PAL });
    for (let i = 0; i < out.width * out.height; i++) {
      const a = out.data[i * 4 + 3];
      expect(a === 0 || a === 255).toBe(true);
    }
  });

  test("handles 3-channel (opaque background) input", () => {
    const d = new Uint8Array(8 * 8 * 3).fill(0);
    for (let i = 0; i < 64; i++) { d[i * 3 + 2] = 255; } // pure blue
    const out = pixelize({ width: 8, height: 8, channels: 3, data: d }, { native: 4, palette: PAL });
    expect(out.channels).toBe(3);
    expect(out.data[0]).toBe(0); expect(out.data[1]).toBe(0); expect(out.data[2]).toBe(255);
  });
});
