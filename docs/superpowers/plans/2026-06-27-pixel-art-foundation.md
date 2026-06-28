# Pixel-Art Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `art_direction: pixel` produce real, native-resolution, DB32-palette-locked, hard-edged pixel art whose cohesion is guaranteed by a deterministic GPU-free gate.

**Architecture:** A deterministic post-process — generate at 1024px with the `pixel-art-xl` LoRA (already wired), then `tools/pixelize.mjs` downscales → quantizes to the DB32 house palette → hardens alpha, producing the canonical committed PNG. A new `asset-qc` `pixel-purity` check fails any PNG that is off-palette, soft-edged, or not at native res. The asset skill wires gen → pixelize → gate; proven by re-skinning crosser-0001.

**Tech Stack:** Node ESM (pure, no runtime deps), `node:zlib`, vitest. Reuses `tools/png.mjs` (decode) and `tools/color.mjs` (ΔE/hex). Tests: `npm test` (all) or `npx vitest run tools/<file>.test.mjs` (one).

**Spec:** `docs/superpowers/specs/2026-06-27-pixel-art-foundation-design.md`

---

## File Structure

- **Create** `tools/palette.mjs` — DB32 house palette (32 hex constants), exported. One responsibility: the canonical palette.
- **Modify** `tools/png.mjs` — add an `encodePng()` export (the repo has a decoder only; the test file has a private encoder we promote). Responsibility: PNG byte (de)serialization.
- **Create** `tools/pixelize.mjs` — pure `pixelize(img, opts)` + `pixelizeFile()` + CLI. Responsibility: the downscale→quantize→harden transform.
- **Modify** `tools/asset-qc.mjs` — add `scorePixelPurity()` + wire `opts.pixel` into `qcImage()`. Responsibility: the deterministic exactness gate.
- **Create** `tools/pixelize.test.mjs`; **Modify** `tools/png.test.mjs` (or `asset-qc.test.mjs` if no png test exists) and `tools/asset-qc.test.mjs`.
- **Modify** `.claude/skills/asset/SKILL.md` — document the `pixel` art-direction path. Responsibility: skill guidance.
- **Proving ground** (manual, GPU+Godot+owner): re-skin `games/crosser-0001/` via the pixel path.

Each engineering task (1–5) is independently testable and committed. Tasks 6–7 are documentation/manual.

---

## Task 1: Add `encodePng()` to `tools/png.mjs`

`png.mjs` currently only decodes. `pixelize.mjs` must WRITE a PNG. Promote a minimal filter-0 encoder (the test fixture in `asset-qc.test.mjs` proves the technique).

**Files:**
- Modify: `tools/png.mjs`
- Test: `tools/png.test.mjs` (create if absent)

- [ ] **Step 1: Write the failing test**

Create `tools/png.test.mjs`:

```js
import { test, expect, describe } from "vitest";
import { decodePng, encodePng } from "./png.mjs";

describe("encodePng", () => {
  for (const ch of [3, 4]) {
    test(`round-trips ${ch}-channel data through decodePng`, () => {
      const w = 5, h = 4;
      const data = new Uint8Array(w * h * ch);
      for (let i = 0; i < data.length; i++) data[i] = (i * 7) & 255;
      const png = encodePng(w, h, ch, data);
      const out = decodePng(png);
      expect(out.width).toBe(w);
      expect(out.height).toBe(h);
      expect(out.channels).toBe(ch);
      expect(Array.from(out.data)).toEqual(Array.from(data));
    });
  }
  test("rejects an unsupported channel count", () => {
    expect(() => encodePng(1, 1, 2, new Uint8Array(2))).toThrow(/3 or 4 channels/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/png.test.mjs`
Expected: FAIL — `encodePng is not a function` (not exported yet).

- [ ] **Step 3: Implement `encodePng`**

In `tools/png.mjs`, change the import line and append the encoder. Replace line 1:

```js
import { inflateSync, deflateSync } from "node:zlib";
```

Append at end of file (reuses the existing `SIG` constant):

```js
// --- Encoder -------------------------------------------------------------
// Minimal filter-None PNG encoder: enough to write the pixelize output (small
// native-res sprites/backgrounds). 8-bit, non-interlaced, RGB (type 2) or RGBA
// (type 6) — the mirror of decodePng's supported set. Pure: pixels in, Buffer out.
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
function pngChunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

// Encode raw row-major pixels → PNG Buffer. channels: 3 (RGB) or 4 (RGBA).
export function encodePng(width, height, channels, data) {
  if (channels !== 3 && channels !== 4) throw new Error(`png: encode supports 3 or 4 channels, got ${channels}`);
  const stride = width * channels;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: None
    Buffer.from(data.subarray(y * stride, y * stride + stride)).copy(raw, y * (stride + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; ihdr[9] = channels === 4 ? 6 : 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([SIG, pngChunk("IHDR", ihdr), pngChunk("IDAT", deflateSync(raw)), pngChunk("IEND", Buffer.alloc(0))]);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/png.test.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/png.mjs tools/png.test.mjs
git commit -m "feat(png): add filter-None encodePng for pixelize output"
```

---

## Task 2: Create the DB32 house palette `tools/palette.mjs`

**Files:**
- Create: `tools/palette.mjs`
- Test: `tools/palette.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `tools/palette.test.mjs`:

```js
import { test, expect, describe } from "vitest";
import { DB32 } from "./palette.mjs";
import { hexToRgb } from "./color.mjs";

describe("DB32 palette", () => {
  test("has 32 entries", () => {
    expect(DB32.length).toBe(32);
  });
  test("every entry is a valid hex colour", () => {
    for (const hex of DB32) expect(() => hexToRgb(hex)).not.toThrow();
  });
  test("has no duplicate colours", () => {
    expect(new Set(DB32.map((h) => h.toLowerCase())).size).toBe(32);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/palette.test.mjs`
Expected: FAIL — cannot resolve `./palette.mjs`.

- [ ] **Step 3: Implement the palette**

Create `tools/palette.mjs`:

```js
// The GameForge house pixel-art palette: DawnBringer 32 (DB32) — 32 colours with
// deliberately constructed hue ramps, the de-facto general-purpose pixel palette.
// One swappable house palette for EVERY pixel game (chosen for maximum cohesion
// over per-game palettes). pixelize.mjs quantizes every sprite to this; asset-qc's
// pixel-purity gate fails anything off it. Change this one array to re-skin the
// whole house style.
export const DB32 = [
  "#000000", "#222034", "#45283c", "#663931", "#8f563b", "#df7126", "#d9a066", "#eec39a",
  "#fbf236", "#99e550", "#6abe30", "#37946e", "#4b692f", "#524b24", "#323c39", "#3f3f74",
  "#306082", "#5b6ee1", "#639bff", "#5fcde4", "#cbdbfc", "#ffffff", "#9badb7", "#847e87",
  "#696a6a", "#595652", "#76428a", "#ac3232", "#d95763", "#d77bba", "#8f974a", "#8a6f30"
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/palette.test.mjs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/palette.mjs tools/palette.test.mjs
git commit -m "feat(palette): DB32 house pixel-art palette"
```

---

## Task 3: The converter `tools/pixelize.mjs` — pure `pixelize()`

**Files:**
- Create: `tools/pixelize.mjs`
- Test: `tools/pixelize.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `tools/pixelize.test.mjs`:

```js
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/pixelize.test.mjs`
Expected: FAIL — cannot resolve `./pixelize.mjs`.

- [ ] **Step 3: Implement `pixelize()`**

Create `tools/pixelize.mjs`:

```js
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/pixelize.test.mjs`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/pixelize.mjs tools/pixelize.test.mjs
git commit -m "feat(pixelize): deterministic downscale + DB32 quantize + alpha-harden"
```

---

## Task 4: pixelize file wrapper + CLI

**Files:**
- Modify: `tools/pixelize.mjs`
- Test: `tools/pixelize.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/pixelize.test.mjs` (add imports `writeFileSync, rmSync` from `node:fs`, `join` from `node:path`, `tmpdir` from `node:os`, `encodePng` from `./png.mjs`, and `pixelizeFile, pixelizeCli` from `./pixelize.mjs`):

```js
import { writeFileSync, rmSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { encodePng, decodePng } from "./png.mjs";
import { pixelizeFile, pixelizeCli } from "./pixelize.mjs";

describe("pixelizeFile", () => {
  test("reads a PNG, writes a clean native-res PNG", () => {
    const dir = tmpdir();
    const inP = join(dir, `pxin-${process.pid}.png`);
    const outP = join(dir, `pxout-${process.pid}.png`);
    const d = new Uint8Array(16 * 16 * 4);
    for (let i = 0; i < 256; i++) { d[i * 4] = 250; d[i * 4 + 1] = 8; d[i * 4 + 2] = 8; d[i * 4 + 3] = 255; }
    writeFileSync(inP, encodePng(16, 16, 4, d));
    try {
      const res = pixelizeFile(inP, outP, { native: 4, palette: ["#ff0000", "#000000"] });
      expect(res).toEqual({ width: 4, height: 4, channels: 4 });
      const back = decodePng(readFileSync(outP));
      expect(back.width).toBe(4);
      expect(back.data[0]).toBe(255); expect(back.data[1]).toBe(0); expect(back.data[2]).toBe(0);
    } finally { rmSync(inP, { force: true }); rmSync(outP, { force: true }); }
  });
});

describe("pixelizeCli", () => {
  test("returns 1 on missing args", () => {
    const errs = [];
    expect(pixelizeCli([], { log() {}, err: (m) => errs.push(m) })).toBe(1);
    expect(errs[0]).toMatch(/usage/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/pixelize.test.mjs`
Expected: FAIL — `pixelizeFile`/`pixelizeCli` not exported.

- [ ] **Step 3: Implement the wrapper + CLI**

Append to `tools/pixelize.mjs`:

```js
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/pixelize.test.mjs`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add tools/pixelize.mjs tools/pixelize.test.mjs
git commit -m "feat(pixelize): file wrapper + CLI"
```

---

## Task 5: `pixel-purity` gate in `tools/asset-qc.mjs`

**Files:**
- Modify: `tools/asset-qc.mjs`
- Test: `tools/asset-qc.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/asset-qc.test.mjs` (it already has `encodePng`, `writeFileSync`, `join`, `tmpdir`; add `scorePixelPurity` to the `asset-qc.mjs` import):

```js
import { scorePixelPurity } from "./asset-qc.mjs";

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
});
```

Ensure the top-of-file import includes `rmSync` (already present) and `qcImage` (already present).

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/asset-qc.test.mjs`
Expected: FAIL — `scorePixelPurity` not exported.

- [ ] **Step 3: Implement the scorer + wire it in**

In `tools/asset-qc.mjs`, add the scorer after `scoreSeamTiling` (before the `qcImage` orchestrator):

```js
// --- Pixel-purity (pure) -------------------------------------------------
// The EXACTNESS gate on a post-pixelize canonical PNG (vs. scorePaletteLock,
// which tolerates ΔE drift on raw generations). A clean pixel asset has: every
// opaque pixel EXACTLY a palette colour, hard alpha (0 or 255 only — no AA
// fringe), and a long side at/under native res. Any violation fails — re-run
// pixelize. Pure: counts computed from pixels.
//   img     – { width, height, channels, data } from decodePng
//   palette – array of [r,g,b] (0..255)
// Returns { ok, offPalette, softAlpha, longSide, native }.
export function scorePixelPurity(img, palette, { native = 64 } = {}) {
  if (!palette || palette.length === 0) throw new Error("asset-qc: scorePixelPurity needs a non-empty palette");
  const set = new Set(palette.map((c) => (c[0] << 16) | (c[1] << 8) | c[2]));
  const { width, height, channels, data } = img;
  let offPalette = 0, softAlpha = 0;
  for (let i = 0; i < width * height; i++) {
    const o = i * channels;
    const a = channels === 4 ? data[o + 3] : 255;
    if (a !== 0 && a !== 255) softAlpha++;
    if (a === 0) continue; // fully transparent — colour irrelevant
    const key = (data[o] << 16) | (data[o + 1] << 8) | data[o + 2];
    if (!set.has(key)) offPalette++;
  }
  const longSide = Math.max(width, height);
  return { ok: offPalette === 0 && softAlpha === 0 && longSide <= native, offPalette, softAlpha, longSide, native };
}
```

In `qcImage`, after the `opts.tiling` block (before `const ran = ...`), add:

```js
  if (opts.pixel) {
    const palette = (opts.pixel.palette || []).map((c) => (Array.isArray(c) ? c : hexToRgb(c)));
    const r = scorePixelPurity(img, palette, opts.pixel);
    checks.pixel = r;
    if (!r.ok) warnings.push(`pixel impurity: ${r.offPalette} off-palette px, ${r.softAlpha} soft-alpha px, long side ${r.longSide} (native ${r.native}) — re-run pixelize`);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/asset-qc.test.mjs`
Expected: PASS (existing + new tests).

- [ ] **Step 5: Run the FULL suite (no regressions)**

Run: `npm test`
Expected: PASS (all files green).

- [ ] **Step 6: Commit**

```bash
git add tools/asset-qc.mjs tools/asset-qc.test.mjs
git commit -m "feat(asset-qc): pixel-purity gate (exact palette + hard alpha + native res)"
```

---

## Task 6: Document the `pixel` path in the asset skill

No automated test — this is skill guidance. Keep it concrete.

**Files:**
- Modify: `.claude/skills/asset/SKILL.md`

- [ ] **Step 1: Add a "Pixel-art path" subsection**

Under the raster-method section (near the existing pixel-art notes around the `process/size_limit` / NEAREST guidance), add:

```markdown
#### Pixel-art path (`art_direction: pixel`)

When `art_direction` is `pixel`, the look is GUARANTEED by a deterministic
post-process, not by hoping the LoRA holds a palette:

1. **Generate** at the normal 1024px master via `sdxl-layerdiffuse-lora` with
   `lora: "pixel-art-xl"` (sprites) or the opaque `sdxl` template + pixel prompt
   terms (backgrounds, no LoRA node). Style fragment: `"pixel art, …"`.
2. **Pixelize** every master through `tools/pixelize.mjs`:
   `node tools/pixelize.mjs <master.png> <out.png> '{"native":64,"palette":<DB32>}'`
   (sprites ~64px long side; backgrounds larger, e.g. 256, same palette). This
   downscales → quantizes to the **DB32 house palette** (`tools/palette.mjs`) →
   hardens alpha. The pixelized PNG is the committed canonical asset.
3. **Gate** each committed PNG with the asset-qc pixel-purity check:
   `node tools/asset-qc.mjs <out.png> '{"pixel":{"palette":<DB32>,"native":64}}'`
   Exit 2 = off-palette / soft-alpha / wrong-res → re-run pixelize (or regenerate
   if the subject is illegible at native res). Do NOT commit a PNG that fails.
4. **Record** in `asset_pass.visual_system.style`:
   `{ loras: ["pixel-art-xl"], style_prompt: "pixel art, …", native: 64, palette: "DB32" }`.
5. **Crispness:** set `rendering/textures/canvas_textures/default_texture_filter = 0`
   (Nearest) in the game's `project.godot` so pixels stay crisp project-wide, and
   draw textures at integer-scaled destination sizes.

The DB32 palette and pixel-purity are the cohesion guarantee — visual-audit does
NOT re-litigate softness/palette (those are gated deterministically upstream); it
judges composition, legibility, and sizing on the composited screen as usual.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/asset/SKILL.md
git commit -m "docs(asset): document the pixel art-direction path (gen -> pixelize -> qc)"
```

---

## Task 7 (manual, GPU + Godot + owner): Prove on crosser-0001

This task needs a running ComfyUI server, Godot, and the owner's eye. It is NOT CI-gated. Drive it interactively.

**Files:**
- Modify: `games/crosser-0001/art/*.png` (regenerated as pixel), `games/crosser-0001/project.godot`, the relevant `.png.import` files, and `games/crosser-0001/manifest.json` (`asset_pass.visual_system.style`).

- [ ] **Step 1:** Confirm ComfyUI is reachable: `node tools/comfy.mjs --check` (expect reachable + checkpoints).
- [ ] **Step 2:** Invoke the **asset** skill on `crosser-0001` with `art_direction: pixel`, following the Task-6 path: regenerate hero, hazard, background through gen → `pixelize` → `asset-qc` pixel-purity (each must exit 0 before commit).
- [ ] **Step 3:** Set `rendering/textures/canvas_textures/default_texture_filter = 0` in `games/crosser-0001/project.godot`; set NEAREST + mipmaps off in each regenerated `.png.import`.
- [ ] **Step 4:** Run the game's existing gates green: validator (`selftest.gd`, `uitest.gd`) headless.
- [ ] **Step 5:** Hand off to **visual-audit** on the running game; fix any composition/legibility/sizing findings (NOT softness/palette — those are gated).
- [ ] **Step 6:** Launch the window for the owner's eyeball (`Godot_v4.6.3-stable_win64.exe --path games/crosser-0001/`). **Success = owner confirms "reads as designed pixel art."**
- [ ] **Step 7:** Commit the re-skin:

```bash
git add games/crosser-0001/
git commit -m "asset(crosser-0001): pixel-art re-skin — proving ground for the pixel foundation"
```

---

## Self-Review Notes

- **Spec coverage:** palette module (T2) ✓; pixelize converter (T3/T4) ✓; pixel-purity gate (T5) ✓; asset-skill wiring + project NEAREST default (T6) ✓; proving ground crosser-0001 (T7) ✓; encoder dependency surfaced and added (T1) ✓. Out-of-scope (animation, per-game palettes, ComfyUI graph) untouched ✓.
- **Naming consistency:** `pixelize`/`pixelizeFile`/`pixelizeCli`, `scorePixelPurity`, `encodePng`, `DB32` used identically across all tasks and tests.
- **Note for the implementer:** Tasks 1–5 are pure-Node TDD and fully CI-verifiable; Task 6 is docs; Task 7 needs GPU+Godot+owner and gates on the human eye — do not mark it complete from automation.
```

