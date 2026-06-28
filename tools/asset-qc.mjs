import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { decodePng } from "./png.mjs";
import { labDeltaE, hexToRgb } from "./color.mjs";

// Deterministic asset quality-control gate (the no-GPU half of the research's
// asset-QC priority): palette-lock + seamless-tiling, computed on the generated
// PNG's pixels. Pure scorers (testable seam) + a thin file/CLI orchestrator. The
// aesthetic-score auto-reject (a ComfyUI VLM node) is deliberately NOT here — it
// needs the GPU server validated against pinned ComfyUI v0.3.16 first.

// --- Palette-lock (pure) -------------------------------------------------
// "Did the generation stay on the game's locked palette?" Naively scoring EVERY
// pixel's distance to the palette false-flags good art (AA + gradients produce
// many in-between shades). Instead we score the image's DOMINANT colours: coarse-
// quantize, take the buckets that cover most of the (opaque) image, and measure
// each dominant colour's ΔE to the NEAREST palette entry — weighted by how much of
// the image it occupies. Gross drift (wrong hues entirely) moves the dominant mass
// far from the palette; sparse AA noise can't.
//   img      – { width, height, channels, data } from decodePng
//   palette  – array of [r,g,b] (0..255) — the locked visual_system.palette
// Returns { ok, weighted_drift, worst, dominant, coverage, deltaEMax }.
export function scorePaletteLock(img, palette, {
  deltaEMax = 30,      // a dominant colour within this ΔE of the palette counts as on-palette
  coverage = 0.85,     // consider dominant buckets until they cover this fraction of the image
  maxDominant = 32,    // ...but never more than this many buckets
  alphaMin = 16,       // ignore (near-)transparent pixels
  quantBits = 4        // 4 bits/channel → 4096 buckets
} = {}) {
  if (!palette || palette.length === 0) throw new Error("asset-qc: scorePaletteLock needs a non-empty palette");
  const { width, height, channels, data } = img;
  const shift = 8 - quantBits;
  const buckets = new Map(); // key -> { n, r, g, b } (accumulated true rgb sums)
  let total = 0;
  for (let i = 0; i < width * height; i++) {
    const o = i * channels;
    if (channels === 4 && data[o + 3] < alphaMin) continue;
    const r = data[o], g = data[o + 1], b = data[o + 2];
    const key = ((r >> shift) << (2 * quantBits)) | ((g >> shift) << quantBits) | (b >> shift);
    let e = buckets.get(key);
    if (!e) { e = { n: 0, r: 0, g: 0, b: 0 }; buckets.set(key, e); }
    e.n++; e.r += r; e.g += g; e.b += b;
    total++;
  }
  if (total === 0) return { ok: true, weighted_drift: 0, worst: 0, dominant: 0, coverage: 0, deltaEMax };

  const sorted = [...buckets.values()].sort((a, b) => b.n - a.n);
  let cum = 0, wsum = 0, wdrift = 0, worst = 0, dominant = 0;
  for (const e of sorted) {
    if (dominant >= maxDominant || (cum / total) >= coverage) break;
    const rep = [Math.round(e.r / e.n), Math.round(e.g / e.n), Math.round(e.b / e.n)];
    let d = Infinity;
    for (const p of palette) d = Math.min(d, labDeltaE(rep, p));
    const w = e.n;
    wsum += w; wdrift += w * d; worst = Math.max(worst, d);
    cum += e.n; dominant++;
  }
  const weighted_drift = wsum ? wdrift / wsum : 0;
  return {
    ok: weighted_drift <= deltaEMax,
    weighted_drift: Math.round(weighted_drift * 10) / 10,
    worst: Math.round(worst * 10) / 10,
    dominant,
    coverage: Math.round((cum / total) * 100) / 100,
    deltaEMax
  };
}

// --- Seamless-tiling (pure) ----------------------------------------------
// "Will this tile/background tile without a visible seam?" When tiled, the right
// edge sits against the left edge and the bottom against the top — so we measure
// the ΔE between those wrap-around edge pairs. The 90th-percentile (not the mean)
// is the gate: one bright mismatched streak is what the eye catches, even if the
// average edge matches. Only meaningful for assets MEANT to tile.
//   img – { width, height, channels, data } from decodePng
// Returns { ok, seam_h_p90, seam_v_p90, seam_h_mean, seam_v_mean, deltaEMax }.
export function scoreSeamTiling(img, { deltaEMax = 12 } = {}) {
  const { width, height, channels, data } = img;
  const px = (x, y) => { const o = (y * width + x) * channels; return [data[o], data[o + 1], data[o + 2]]; };
  const stats = (arr) => {
    if (arr.length === 0) return { mean: 0, p90: 0 };
    const mean = arr.reduce((s, v) => s + v, 0) / arr.length;
    const s = [...arr].sort((a, b) => a - b);
    const p90 = s[Math.min(Math.floor(s.length * 0.9), s.length - 1)];
    return { mean, p90 };
  };
  const h = [], v = [];
  for (let y = 0; y < height; y++) h.push(labDeltaE(px(0, y), px(width - 1, y)));
  for (let x = 0; x < width; x++) v.push(labDeltaE(px(x, 0), px(x, height - 1)));
  const hs = stats(h), vs = stats(v);
  const r1 = (n) => Math.round(n * 10) / 10;
  return {
    ok: Math.max(hs.p90, vs.p90) <= deltaEMax,
    seam_h_p90: r1(hs.p90), seam_v_p90: r1(vs.p90),
    seam_h_mean: r1(hs.mean), seam_v_mean: r1(vs.mean),
    deltaEMax
  };
}

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

// --- File orchestrator ---------------------------------------------------
// Run the applicable checks on a PNG file. `opts.palette` (hex or [r,g,b] entries)
// enables palette-lock; `opts.tiling` enables the seam check. Returns
// { ok, checks: {palette?, tiling?}, warnings: [] }.
export function qcImage(pngPath, opts = {}) {
  const img = decodePng(readFileSync(pngPath));
  const checks = {};
  const warnings = [];
  if (opts.palette && opts.palette.length) {
    const palette = opts.palette.map((c) => (Array.isArray(c) ? c : hexToRgb(c)));
    const r = scorePaletteLock(img, palette, opts);
    checks.palette = r;
    if (!r.ok) warnings.push(`palette drift: dominant colours sit ΔE ${r.weighted_drift} from the locked palette (worst ${r.worst} > ${r.deltaEMax}) — regenerate or re-confirm the palette`);
  }
  if (opts.tiling) {
    const r = scoreSeamTiling(img, opts);
    checks.tiling = r;
    if (!r.ok) warnings.push(`visible tile seam: edge ΔE p90 ${Math.max(r.seam_h_p90, r.seam_v_p90)} > ${r.deltaEMax} (h ${r.seam_h_p90} / v ${r.seam_v_p90}) — enable tiling generation or fix the edges`);
  }
  if (opts.pixel && opts.pixel.palette && opts.pixel.palette.length) {
    const palette = (opts.pixel.palette || []).map((c) => (Array.isArray(c) ? c : hexToRgb(c)));
    const r = scorePixelPurity(img, palette, opts.pixel);
    checks.pixel = r;
    if (!r.ok) warnings.push(`pixel impurity: ${r.offPalette} off-palette px, ${r.softAlpha} soft-alpha px, long side ${r.longSide} (native ${r.native}) — re-run pixelize`);
  }
  const ran = Object.values(checks);
  return { ok: ran.every((c) => c.ok), checks, warnings, dimensions: { w: img.width, h: img.height, channels: img.channels } };
}

// CLI: node tools/asset-qc.mjs <png> '<json-opts>'  (also reachable as `comfy.mjs qc`).
// Exit 0 = all checks pass; 2 = a check FAILED (off-palette / seam); 1 = usage/IO error.
export function qcCli(argv, { log = console.log, err = console.error } = {}) {
  const [pngPath, optsJson] = argv;
  if (!pngPath) { err("usage: asset-qc <png-path> '<json {palette?, tiling?, ...thresholds}>'"); return 1; }
  let opts = {};
  if (optsJson) { try { opts = JSON.parse(optsJson); } catch (e) { err(`asset-qc: bad JSON opts: ${e.message}`); return 1; } }
  let res;
  try { res = qcImage(pngPath, opts); } catch (e) { err(`asset-qc: ${e.message}`); return 1; }
  log(`ASSET_QC ${JSON.stringify(res)}`);
  for (const w of res.warnings) err(`WARN ${w}`);
  log(res.ok ? "ASSET_QC OK" : "ASSET_QC FAIL");
  return res.ok ? 0 : 2;
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exit(qcCli(process.argv.slice(2)));
}
