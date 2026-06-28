import { test, expect, describe } from "vitest";
import { deflateSync } from "node:zlib";
import { writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { decodePng } from "./png.mjs";
import { scorePaletteLock, scoreSeamTiling, qcImage, scorePixelPurity } from "./asset-qc.mjs";
import { hexToRgb, labDeltaE } from "./color.mjs";

// --- Hermetic PNG encoder (test fixture only) ----------------------------
// Encodes raw RGB/RGBA with a chosen scanline filter so the decoder's unfilter
// paths (None/Sub/Up/Average/Paeth) are all exercised on round-trip.
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; }
  return t;
})();
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (~c) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function paeth(a, b, c) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
function encodePng(width, height, channels, data, filter = 0) {
  const stride = width * channels;
  const rows = [];
  let prev = new Uint8Array(stride);
  for (let y = 0; y < height; y++) {
    const cur = data.subarray(y * stride, y * stride + stride);
    const line = Buffer.alloc(stride + 1);
    line[0] = filter;
    for (let i = 0; i < stride; i++) {
      const x = cur[i];
      const a = i >= channels ? cur[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      let v;
      switch (filter) {
        case 0: v = x; break;
        case 1: v = x - a; break;
        case 2: v = x - b; break;
        case 3: v = x - ((a + b) >> 1); break;
        case 4: v = x - paeth(a, b, c); break;
      }
      line[i + 1] = v & 255;
    }
    rows.push(line);
    prev = cur;
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", deflateSync(Buffer.concat(rows))), chunk("IEND", Buffer.alloc(0))]);
}

// A small RGBA gradient so adjacent pixels differ (exercises Sub/Up/Paeth).
function gradient(w, h, channels) {
  const d = new Uint8Array(w * h * channels);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = (y * w + x) * channels;
    d[o] = (x * 13) & 255; d[o + 1] = (y * 17) & 255; d[o + 2] = (x * y) & 255;
    if (channels === 4) d[o + 3] = 255;
  }
  return d;
}

describe("decodePng", () => {
  for (const ch of [3, 4]) {
    for (const filter of [0, 1, 2, 3, 4]) {
      test(`round-trips ${ch}-channel data through filter ${filter}`, () => {
        const w = 9, h = 7, data = gradient(w, h, ch);
        const png = encodePng(w, h, ch, data, filter);
        const out = decodePng(png);
        expect(out.width).toBe(w);
        expect(out.height).toBe(h);
        expect(out.channels).toBe(ch);
        expect(Array.from(out.data)).toEqual(Array.from(data));
      });
    }
  }
  test("rejects a non-PNG buffer", () => {
    expect(() => decodePng(Buffer.from("not a png"))).toThrow(/not a PNG/);
  });
});

// Build a decoded-image object directly (no PNG) for scorer tests.
function img(w, h, channels, fill) {
  const d = new Uint8Array(w * h * channels);
  for (let i = 0; i < w * h; i++) fill(d, i * channels, i % w, Math.floor(i / w));
  return { width: w, height: h, channels, data: d };
}

describe("scorePaletteLock", () => {
  const palette = [[20, 30, 200], [240, 240, 240], [10, 120, 90]]; // blues/white/teal

  test("an all-on-palette image has ~zero drift and passes", () => {
    const im = img(16, 16, 3, (d, o, x) => { const c = palette[x % palette.length]; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; });
    const r = scorePaletteLock(im, palette);
    expect(r.weighted_drift).toBeLessThan(2);
    expect(r.ok).toBe(true);
  });

  test("a wildly off-palette image (saturated red) fails", () => {
    const im = img(16, 16, 3, (d, o) => { d[o] = 230; d[o + 1] = 10; d[o + 2] = 10; });
    const r = scorePaletteLock(im, palette);
    expect(r.ok).toBe(false);
    expect(r.weighted_drift).toBeGreaterThan(30);
  });

  test("sparse off-palette pixels do not flip a mostly-on-palette image", () => {
    const im = img(20, 20, 3, (d, o, x, y) => {
      if (x === 0 && y === 0) { d[o] = 230; d[o + 1] = 10; d[o + 2] = 10; return; } // one stray red pixel
      const c = palette[(x + y) % palette.length]; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2];
    });
    const r = scorePaletteLock(im, palette);
    expect(r.ok).toBe(true);
  });

  test("fully-transparent pixels are ignored (no crash, treated empty)", () => {
    const im = img(8, 8, 4, (d, o) => { d[o] = 230; d[o + 1] = 10; d[o + 2] = 10; d[o + 3] = 0; });
    const r = scorePaletteLock(im, palette);
    expect(r.dominant).toBe(0);
    expect(r.ok).toBe(true);
  });
});

describe("scoreSeamTiling", () => {
  test("a constant-colour image tiles seamlessly", () => {
    const im = img(12, 12, 3, (d, o) => { d[o] = 80; d[o + 1] = 120; d[o + 2] = 160; });
    const r = scoreSeamTiling(im);
    expect(r.seam_h_p90).toBeLessThan(1);
    expect(r.seam_v_p90).toBeLessThan(1);
    expect(r.ok).toBe(true);
  });

  test("a left-to-right gradient has a visible horizontal seam", () => {
    const im = img(16, 16, 3, (d, o, x) => { const v = Math.round((x / 15) * 255); d[o] = v; d[o + 1] = v; d[o + 2] = v; });
    const r = scoreSeamTiling(im);
    expect(r.ok).toBe(false);
    expect(r.seam_h_p90).toBeGreaterThan(12);
    expect(r.seam_v_p90).toBeLessThan(1); // rows match top-to-bottom
  });
});

describe("hexToRgb", () => {
  test("parses #rrggbb and #rgb", () => {
    expect(hexToRgb("#1020c8")).toEqual([16, 32, 200]);
    expect(hexToRgb("#fff")).toEqual([255, 255, 255]);
    expect(hexToRgb("1020c8")).toEqual([16, 32, 200]);
  });
  test("throws on malformed input", () => {
    expect(() => hexToRgb("nope")).toThrow();
  });
});

describe("qcImage (file orchestrator)", () => {
  test("runs palette + tiling checks on a real PNG file", () => {
    const w = 16, h = 16;
    const data = new Uint8Array(w * h * 3).fill(0);
    for (let i = 0; i < w * h; i++) { const o = i * 3; data[o] = 80; data[o + 1] = 120; data[o + 2] = 160; }
    const p = join(tmpdir(), `gf-qc-${process.pid}.png`);
    writeFileSync(p, encodePng(w, h, 3, data, 0));
    try {
      const res = qcImage(p, { palette: ["#5078a0"], tiling: true });
      expect(res.dimensions).toEqual({ w, h, channels: 3 });
      expect(res.checks.palette.ok).toBe(true);
      expect(res.checks.tiling.ok).toBe(true);
      expect(res.ok).toBe(true);
    } finally {
      rmSync(p, { force: true });
    }
  });
});

describe("scorePixelPurity", () => {
  const PAL = [[255, 0, 0], [0, 0, 0], [255, 255, 255]];
  function img(w, h, fill) { // fill(i)->[r,g,b,a]
    const d = new Uint8Array(w * h * 4);
    for (let i = 0; i < w * h; i++) { const [r, g, b, a] = fill(i); d[i*4]=r; d[i*4+1]=g; d[i*4+2]=b; d[i*4+3]=a; }
    return { width: w, height: h, channels: 4, data: d };
  }
  test("passes a clean on-palette, hard-alpha, native-res image", () => {
    const r = scorePixelPurity(img(4, 4, () => [255, 0, 0, 255]), PAL, { native: 4 });
    expect(r.ok).toBe(true);
    expect(r.offPalette).toBe(0); expect(r.softAlpha).toBe(0);
  });
  test("fails on an off-palette pixel", () => {
    const r = scorePixelPurity(img(4, 4, (i) => (i === 0 ? [10, 200, 30, 255] : [255, 0, 0, 255])), PAL, { native: 4 });
    expect(r.ok).toBe(false); expect(r.offPalette).toBe(1);
  });
  test("fails on a soft-alpha pixel", () => {
    const r = scorePixelPurity(img(4, 4, (i) => (i === 0 ? [255, 0, 0, 128] : [255, 0, 0, 255])), PAL, { native: 4 });
    expect(r.ok).toBe(false); expect(r.softAlpha).toBe(1);
  });
  test("fails when long side exceeds native", () => {
    const r = scorePixelPurity(img(8, 4, () => [255, 0, 0, 255]), PAL, { native: 4 });
    expect(r.ok).toBe(false); expect(r.longSide).toBe(8);
  });
  test("ignores colour of fully transparent pixels", () => {
    const r = scorePixelPurity(img(4, 4, (i) => (i === 0 ? [9, 9, 9, 0] : [255, 0, 0, 255])), PAL, { native: 4 });
    expect(r.ok).toBe(true); expect(r.offPalette).toBe(0);
  });
  test("treats 3-channel input as fully opaque and palette-checks it", () => {
    const d = new Uint8Array(4 * 4 * 3);
    for (let i = 0; i < 16; i++) { d[i*3]=255; } // pure red, 3-channel
    const r = scorePixelPurity({ width: 4, height: 4, channels: 3, data: d }, PAL, { native: 4 });
    expect(r.ok).toBe(true); expect(r.softAlpha).toBe(0); expect(r.offPalette).toBe(0);
  });
});

describe("qcImage pixel gate", () => {
  test("runs pixel-purity when opts.pixel is set", () => {
    const dir = tmpdir();
    const p = join(dir, `qcpx-${process.pid}.png`);
    const d = new Uint8Array(4 * 4 * 4);
    for (let i = 0; i < 16; i++) { d[i*4]=255; d[i*4+3]=255; } // pure red, hard alpha
    writeFileSync(p, encodePng(4, 4, 4, d));
    try {
      const res = qcImage(p, { pixel: { palette: ["#ff0000", "#000000"], native: 4 } });
      expect(res.ok).toBe(true);
      expect(res.checks.pixel.offPalette).toBe(0);
    } finally { rmSync(p, { force: true }); }
  });
  test("fails qcImage when the PNG is pixel-impure", () => {
    const dir = tmpdir();
    const p = join(dir, `qcpxbad-${process.pid}.png`);
    const d = new Uint8Array(4 * 4 * 4);
    for (let i = 0; i < 16; i++) { d[i*4]=255; d[i*4+3]=255; } // start all pure red
    d[0]=10; d[1]=200; d[2]=30; // one off-palette pixel
    writeFileSync(p, encodePng(4, 4, 4, d));
    try {
      const res = qcImage(p, { pixel: { palette: ["#ff0000", "#000000"], native: 4 } });
      expect(res.ok).toBe(false);
      expect(res.checks.pixel.offPalette).toBe(1);
      expect(res.warnings.length).toBeGreaterThan(0);
    } finally { rmSync(p, { force: true }); }
  });
});
