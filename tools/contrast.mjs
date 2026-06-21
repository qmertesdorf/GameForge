// Objective colour metrics for the visual-audit legibility + colour-accessibility
// lenses — the testable seam that replaces eyeball judgment with numbers and
// deterministic images. Pure functions (WCAG contrast, CVD simulation, bimodal
// crop measurement) live here; the thin Godot pixel ops (crop_pixels.gd,
// cvd_sim.gd) only decode/encode pixels, exactly like the package.mjs icon split.
//
// CLI:
//   node tools/contrast.mjs ratio "#rrggbb" "#rrggbb" [--large]   # quick pair check
//   node tools/contrast.mjs measure <crop.png> [--large]          # measured text-vs-backing contrast of a crop
//   node tools/contrast.mjs cvd <frame.png> <outdir>              # grayscale + deuteranopia + protanopia renders

import { execFileSync } from "node:child_process";
import { copyFileSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GODOT_DIR = join(__dirname, "godot");

// --- WCAG contrast -------------------------------------------------------
// sRGB 0..255 channel → linear (WCAG 2.x definition).
function srgbToLinear(c) {
  const x = c / 255;
  return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
}
// WCAG relative luminance (Rec.709 weights), 0..1.
export function relativeLuminance([r, g, b]) {
  return 0.2126 * srgbToLinear(r) + 0.7152 * srgbToLinear(g) + 0.0722 * srgbToLinear(b);
}
// WCAG contrast ratio between two sRGB colours, 1..21.
export function wcagContrast(a, b) {
  const la = relativeLuminance(a), lb = relativeLuminance(b);
  const hi = Math.max(la, lb), lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
// Pass/fail vs WCAG AA: 4.5:1 body, 3:1 large/bold.
export function contrastVerdict(ratio, { large = false } = {}) {
  const threshold = large ? 3 : 4.5;
  return { ok: ratio >= threshold, threshold, ratio };
}

// --- Colour-vision-deficiency simulation ---------------------------------
// Machado et al. 2009 severity-1.0 matrices, applied in sRGB and clamped — a
// faithful-enough render for the auditor to SEE the red-green collapse, not
// imagine it. Grayscale uses the Rec.709 luminance so value-only collisions show.
const CVD_MATRIX = {
  deuteranopia: [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
  protanopia: [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
};
const clamp8 = (v) => Math.max(0, Math.min(255, Math.round(v)));
export function cvdTransform([r, g, b], type) {
  if (type === "grayscale") {
    const y = clamp8(0.2126 * r + 0.7152 * g + 0.0722 * b);
    return [y, y, y];
  }
  const m = CVD_MATRIX[type];
  if (!m) throw new Error(`contrast: unknown CVD type '${type}'`);
  return [
    clamp8(m[0][0] * r + m[0][1] * g + m[0][2] * b),
    clamp8(m[1][0] * r + m[1][1] * g + m[1][2] * b),
    clamp8(m[2][0] * r + m[2][1] * g + m[2][2] * b),
  ];
}
export const CVD_TYPES = ["grayscale", "deuteranopia", "protanopia"];

// --- Bimodal crop measurement --------------------------------------------
// A tight crop of text-on-backing is two luminance clusters: strokes and plate.
// Otsu-threshold the crop's luminance, take the mean colour of each side, and
// return the WCAG contrast between them — the measured "does this text separate"
// number. Input: array of packed 0xRRGGBB ints. A crop with no real split (a
// uniform region — no visible strokes) returns contrast 1.
const unpack = (p) => [(p >> 16) & 255, (p >> 8) & 255, p & 255];
const lum255 = ([r, g, b]) => Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b);
export function measureCrop(rgb) {
  const n = rgb.length;
  const px = rgb.map(unpack);
  const lum = px.map(lum255);
  const hist = new Array(256).fill(0);
  for (const l of lum) hist[l]++;
  const total = n;
  let sumTotal = 0;
  for (let i = 0; i < 256; i++) sumTotal += i * hist[i];
  let wB = 0, sumB = 0, maxVar = 0, threshold = -1;
  for (let t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB === 0) continue;
    const wF = total - wB;
    if (wF === 0) break;
    sumB += t * hist[t];
    const mB = sumB / wB;
    const mF = (sumTotal - sumB) / wF;
    const between = wB * wF * (mB - mF) * (mB - mF);
    if (between > maxVar) { maxVar = between; threshold = t; }
  }
  const mean = (sel) => {
    let r = 0, g = 0, b = 0, k = 0;
    for (let i = 0; i < n; i++) if (sel(lum[i])) { r += px[i][0]; g += px[i][1]; b += px[i][2]; k++; }
    return k === 0 ? null : [Math.round(r / k), Math.round(g / k), Math.round(b / k)];
  };
  if (maxVar === 0 || threshold < 0) {
    const m = mean(() => true);
    return { contrast: 1, threshold, dark: m, light: m, counts: { dark: n, light: 0 } };
  }
  const darkSel = (l) => l <= threshold;
  const dark = mean(darkSel);
  const light = mean((l) => !darkSel(l));
  const counts = { dark: lum.filter(darkSel).length, light: lum.filter((l) => !darkSel(l)).length };
  return { contrast: wcagContrast(dark, light), threshold, dark, light, counts };
}

// --- Min-text-size (pure) ------------------------------------------------
// Score the text-node list emitted by text_metrics.gd: any VISIBLE text node whose
// RESOLVED font size is below the mobile-readability floor is a finding. Nodes whose
// size couldn't resolve (font_size 0 — e.g. an empty theme) are reported separately,
// not failed. Default floor 18px suits the 720×1280 portrait design; pass minPx for
// other design resolutions. Custom _draw() text isn't in `nodes` at all (see
// text_metrics.gd) — this gate covers Control text and says so.
export function scoreTextMetrics(nodes, { minPx = 18, includeHidden = false } = {}) {
  const findings = [];
  const unresolved = [];
  let checked = 0;
  for (const n of nodes) {
    if (!includeHidden && !n.visible) continue;
    if (!n.font_size || n.font_size <= 0) { unresolved.push({ path: n.path, class: n.class }); continue; }
    checked++;
    if (n.font_size < minPx)
      findings.push({ path: n.path, class: n.class, text: n.text, font_size: n.font_size, rect: n.rect, minPx });
  }
  return { ok: findings.length === 0, minPx, checked, findings, unresolved };
}

// --- thin Godot pixel ops ------------------------------------------------
function godotBin() {
  return process.env.GODOT_BIN || "godot";
}
function runGodot(args, label) {
  try {
    return execFileSync(godotBin(), args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    throw new Error(`contrast: Godot ${label} failed: ${e.message}\n${e.stdout || ""}${e.stderr || ""}`);
  }
}

// Decode a crop PNG → packed-int pixel list (via crop_pixels.gd), measure it.
export function measureCropFile(cropPath, { large = false } = {}) {
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://crop_pixels.gd", "--", resolve(cropPath)], "crop_pixels");
  const m = out.match(/CROP_PIXELS (\{.*\})/);
  if (!m) throw new Error(`contrast: crop_pixels emitted no grid:\n${out}`);
  const { rgb } = JSON.parse(m[1]);
  const r = measureCrop(rgb);
  return { ...r, contrast: Math.round(r.contrast * 100) / 100, verdict: contrastVerdict(r.contrast, { large }) };
}

// Probe the game's Control text via text_metrics.gd (copied into the game dir,
// screenshot.gd-style, then cleaned up) and score min-text-size. Returns
// { viewport, ok, minPx, checked, findings, unresolved }. The findings' rects also
// give the legibility/colour lenses deterministically-located text regions.
export function textMetricsFile(gameDir, { minPx = 18 } = {}) {
  const dir = resolve(gameDir);
  const tmp = join(dir, "_text_metrics.gd");
  copyFileSync(join(GODOT_DIR, "text_metrics.gd"), tmp);
  try {
    const out = runGodot(["--headless", "--path", dir, "--script", "res://_text_metrics.gd"], "text_metrics");
    const m = out.match(/TEXT_METRICS (\{.*\})/);
    if (!m) throw new Error(`contrast: text_metrics emitted no data:\n${out}`);
    const { viewport, nodes } = JSON.parse(m[1]);
    return { viewport, ...scoreTextMetrics(nodes, { minPx }) };
  } finally {
    rmSync(tmp, { force: true });
    rmSync(`${tmp}.uid`, { force: true });
  }
}

// Write grayscale + deuteranopia + protanopia renders of a frame (via cvd_sim.gd).
export function cvdRenderFile(framePath, outdir) {
  const absOut = resolve(outdir);
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://cvd_sim.gd", "--", resolve(framePath), absOut], "cvd_sim");
  if (!out.includes("CVD_SIM OK")) throw new Error(`contrast: cvd_sim did not report OK:\n${out}`);
  return CVD_TYPES.map((t) => ({ type: t, path: join(absOut, `cvd_${t}.png`) }));
}

const parseHex = (s) => {
  const m = String(s).trim().match(/^#?([0-9a-fA-F]{6})$/);
  if (!m) throw new Error(`contrast: not a #rrggbb colour: ${s}`);
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};

function main(argv) {
  const args = argv.slice(2);
  const large = args.includes("--large");
  const pos = args.filter((a) => !a.startsWith("--"));
  const cmd = pos[0];
  if (cmd === "ratio") {
    const ratio = wcagContrast(parseHex(pos[1]), parseHex(pos[2]));
    console.log(JSON.stringify({ ratio: Math.round(ratio * 100) / 100, ...contrastVerdict(ratio, { large }) }, null, 2));
  } else if (cmd === "measure") {
    console.log(JSON.stringify(measureCropFile(pos[1], { large }), null, 2));
  } else if (cmd === "cvd") {
    console.log(JSON.stringify(cvdRenderFile(pos[1], pos[2]), null, 2));
  } else if (cmd === "text-metrics") {
    const mi = args.indexOf("--min");
    const minPx = mi >= 0 ? Number(args[mi + 1]) : 18;
    const res = textMetricsFile(pos[1], { minPx });
    console.log(JSON.stringify(res, null, 2));
    process.exit(res.ok ? 0 : 2);
  } else {
    console.error("usage: contrast.mjs ratio <#hex> <#hex> [--large] | measure <crop.png> [--large] | cvd <frame.png> <outdir> | text-metrics <game-dir> [--min N]");
    process.exit(2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main(process.argv);
