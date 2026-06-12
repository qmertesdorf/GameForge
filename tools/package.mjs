import { readFileSync, writeFileSync, mkdirSync, statSync, existsSync, readdirSync, copyFileSync, rmSync, openSync, readSync, closeSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, basename } from "node:path";
import { readManifest } from "./manifest.mjs"; // single manifest-dir resolver (honors GAMEFORGE_MANIFEST_DIR)

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");

export const GAMES_DIR = process.env.GAMEFORGE_GAMES_DIR || join(REPO_ROOT, "games");
export const GODOT_DIR = join(__dirname, "godot"); // the tool-project for headless Image scripts
// 50 MiB default whole-title asset budget; override per-title via opts or env.
export const DEFAULT_SIZE_BUDGET = Number(process.env.GAMEFORGE_SIZE_BUDGET || 52428800);

// The canonical list of required Android icon outputs. Pure + deterministic;
// a fresh array each call so callers can't mutate a shared singleton.
export function iconSizeTable() {
  return [
    { name: "ic_launcher_mdpi", px: 48, kind: "launcher" },
    { name: "ic_launcher_hdpi", px: 72, kind: "launcher" },
    { name: "ic_launcher_xhdpi", px: 96, kind: "launcher" },
    { name: "ic_launcher_xxhdpi", px: 144, kind: "launcher" },
    { name: "ic_launcher_xxxhdpi", px: 192, kind: "launcher" },
    { name: "ic_play_store", px: 512, kind: "play" },
    { name: "ic_adaptive_foreground", px: 432, kind: "adaptive_fg" },
    { name: "ic_adaptive_background", px: 432, kind: "adaptive_bg" }
  ];
}

// Sum shippable asset bytes and compare to a budget. Pure.
export function sizeBudget(files, budgetBytes) {
  if (!Array.isArray(files)) {
    throw new Error("package: sizeBudget(files) requires an array of { path, bytes }");
  }
  if (typeof budgetBytes !== "number" || budgetBytes < 0) {
    throw new Error("package: sizeBudget budgetBytes must be a non-negative number");
  }
  const per_file = files.map((f) => {
    if (typeof f?.path !== "string" || typeof f?.bytes !== "number") {
      throw new Error(`package: sizeBudget entry must be { path:string, bytes:number }, got ${JSON.stringify(f)}`);
    }
    return { path: f.path, bytes: f.bytes };
  });
  const total = per_file.reduce((s, f) => s + f.bytes, 0);
  return { total_bytes: total, budget_bytes: budgetBytes, pass: total <= budgetBytes, per_file };
}

// Read a PNG's pixel dimensions straight from the IHDR chunk — no decode, no
// Godot. Lets the validator assert exact icon sizes headlessly. Pure.
export function pngSize(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 24) {
    throw new Error("package: pngSize requires a PNG buffer of at least 24 bytes");
  }
  const sig = buf.subarray(0, 8).toString("latin1");
  if (sig !== "\x89PNG\r\n\x1a\n") {
    throw new Error("package: pngSize: not a PNG (bad signature)");
  }
  if (buf.subarray(12, 16).toString("latin1") !== "IHDR") {
    throw new Error("package: pngSize: first chunk is not IHDR (corrupt PNG)");
  }
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

// Godot .cfg values are double-quoted, and parsePresetCfg strips quotes without
// unescaping — so an embedded quote/backslash/newline in an interpolated value
// would emit a line that Godot's own parser mis-reads or that fails to round-trip.
// Inputs here are short Claude-authored titles, so reject loudly (the honest guard)
// rather than silently corrupt the preset. Pure.
function assertCfgSafe(value, field) {
  if (typeof value === "string" && /["\\\r\n]/.test(value)) {
    throw new Error(`package: ${field} contains a character unsafe for a Godot .cfg value (double-quote, backslash, or newline): ${JSON.stringify(value)}`);
  }
  return value;
}

// Derive an Android-legal package name from a game id. Android package segments
// must be valid Java identifiers ([A-Za-z_][A-Za-z0-9_]*); our ids are hyphenated
// (creature-0001), so map any run of non-alphanumerics to "_" and ensure the
// segment starts with a letter. Pure.
export function packageNameFor(id) {
  const seg = String(id).replace(/[^A-Za-z0-9]+/g, "_");
  const safe = /^[A-Za-z]/.test(seg) ? seg : `g_${seg}`;
  return `com.gameforge.${safe}`;
}

// Generate a minimal-but-valid Godot Android export preset block. Pure.
// format: "apk" (prebuilt template, gradle off) | "aab" (requires gradle build on).
// buildType: "debug" | "release". presetIndex picks the [preset.N] section so a
// single cfg can carry both a debug-APK and a release-AAB preset.
export function exportPresetCfg({ id, name, packageName, exportPath, format = "apk", buildType = "debug", presetIndex = 0 } = {}) {
  if (!id || !name) {
    throw new Error("package: exportPresetCfg requires both { id, name }");
  }
  if (format !== "apk" && format !== "aab") {
    throw new Error(`package: exportPresetCfg format must be "apk" or "aab", got ${JSON.stringify(format)}`);
  }
  if (buildType !== "debug" && buildType !== "release") {
    throw new Error(`package: exportPresetCfg buildType must be "debug" or "release", got ${JSON.stringify(buildType)}`);
  }
  assertCfgSafe(name, "exportPresetCfg name");
  const unique = assertCfgSafe(packageName || packageNameFor(id), "exportPresetCfg packageName");
  const out = assertCfgSafe(exportPath || `build/${id}-${buildType}.${format}`, "exportPresetCfg exportPath");
  const useGradle = format === "aab"; // AAB output requires Godot's gradle build enabled
  const p = `preset.${presetIndex}`;
  return [
    `[${p}]`,
    "",
    `name="${name}"`,
    `platform="Android"`,
    "runnable=true",
    `export_filter="all_resources"`,
    `include_filter=""`,
    `exclude_filter=""`,
    `export_path="${out}"`,
    "",
    `[${p}.options]`,
    "",
    `gradle_build/use_gradle_build=${useGradle ? "true" : "false"}`,
    // export_format: 0=APK, 1=AAB. Required for AAB output — Godot keys the
    // output container off this, NOT the export_path extension. Without it a
    // .aab path is rejected with "Android APK requires the *.apk extension".
    `gradle_build/export_format=${format === "aab" ? 1 : 0}`,
    `package/unique_name="${unique}"`,
    `package/name="${name}"`,
    ""
  ].join("\n");
}

// Emit a full export_presets.cfg carrying BOTH a debug-APK preset (preset.0,
// named after the game) and a release-AAB preset (preset.1, "<name> Release").
// One file, two presets, so a single project root builds either artifact. Pure.
export function exportPresetsFile({ id, name, packageName } = {}) {
  if (!id || !name) {
    throw new Error("package: exportPresetsFile requires both { id, name }");
  }
  const debug = exportPresetCfg({ id, name, packageName, format: "apk", buildType: "debug", presetIndex: 0 });
  const release = exportPresetCfg({ id, name: `${name} Release`, packageName, format: "aab", buildType: "release", presetIndex: 1 });
  return `${debug}\n${release}`;
}

// Is the Android toolchain available? Env-driven (NOT the hardcoded SDK path) so
// it is deterministic in tests and on CI. The android-setup helper exports
// ANDROID_HOME for the session, flipping this on. Mirrors the no-GPU/no-ComfyUI
// guard posture — buildArtifact() and verifyBuildArtifact() skip when this is false.
export function androidToolchainPresent() {
  return Boolean(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT);
}

// Pure plan for a headless Godot Android export. No SDK touched — fully unit-testable.
// debug → APK via preset "<name>"; release → AAB via preset "<name> Release"
// (the two presets exportPresetsFile() writes). Returns the spawn args + out path
// so buildArtifact() only has to prepend godotBin() and run it.
export function buildArtifactPlan({ id, name, packageName, format = "apk", buildType = "debug", gamesDir = GAMES_DIR } = {}) {
  if (!id || !name) {
    throw new Error("package: buildArtifactPlan requires both { id, name }");
  }
  if (format !== "apk" && format !== "aab") {
    throw new Error(`package: buildArtifactPlan format must be "apk" or "aab", got ${JSON.stringify(format)}`);
  }
  if (buildType !== "debug" && buildType !== "release") {
    throw new Error(`package: buildArtifactPlan buildType must be "debug" or "release", got ${JSON.stringify(buildType)}`);
  }
  const preset = buildType === "debug" ? name : `${name} Release`;
  const flag = buildType === "debug" ? "--export-debug" : "--export-release";
  const projectDir = join(gamesDir, id);
  const outPath = join(projectDir, "build", `${id}-${buildType}.${format}`);
  return {
    args: ["--headless", "--path", projectDir, flag, preset, outPath],
    outPath,
    package: packageName || packageNameFor(id),
    preset,
    format,
    build_type: buildType
  };
}

// Parse a Godot .cfg/export_presets.cfg into { section: { key: value } }.
// Strips surrounding quotes; coerces true/false and bare integers. Throws
// loudly on a malformed line so the validator can assert "the preset parses".
export function parsePresetCfg(text) {
  if (typeof text !== "string") {
    throw new Error("package: parsePresetCfg requires a string");
  }
  const sections = {};
  let current = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith(";")) continue; // Godot .cfg comment lines
    const sec = line.match(/^\[(.+)\]$/);
    if (sec) { current = sec[1]; sections[current] = {}; continue; }
    const kv = line.match(/^([^=]+)=(.*)$/);
    if (!kv) throw new Error(`package: parsePresetCfg: unparseable line: ${raw}`);
    if (current === null) throw new Error(`package: parsePresetCfg: key before any [section]: ${raw}`);
    let val = kv[2].trim();
    if (val.startsWith('"') && val.endsWith('"')) val = val.slice(1, -1);
    else if (val === "true") val = true;
    else if (val === "false") val = false;
    else if (/^-?\d+$/.test(val)) val = Number(val);
    sections[current][kv[1].trim()] = val;
  }
  return sections;
}

// Deterministic shelf bin-packing: tallest-first, left-to-right rows wrapping
// at maxWidth, sheet rounded up to power-of-two on both axes. Pure (no pixels).
export function atlasLayout(rects, { maxWidth = 1024, padding = 0 } = {}) {
  if (!Array.isArray(rects)) {
    throw new Error("package: atlasLayout(rects) requires an array of { name, w, h }");
  }
  const items = rects.map((r) => {
    if (typeof r?.name !== "string" || typeof r?.w !== "number" || typeof r?.h !== "number") {
      throw new Error(`package: atlasLayout entry must be { name:string, w:number, h:number }, got ${JSON.stringify(r)}`);
    }
    return { name: r.name, w: r.w, h: r.h };
  });
  if (items.length === 0) return { sheet: { w: 0, h: 0 }, placements: [] };

  // Deterministic order: tallest, then widest, then name — no Math.random / input order dependence.
  const sorted = [...items].sort((a, b) => b.h - a.h || b.w - a.w || (a.name < b.name ? -1 : 1));
  for (const r of sorted) {
    if (r.w + padding > maxWidth) {
      throw new Error(`package: atlasLayout sprite '${r.name}' width ${r.w + padding} exceeds maxWidth ${maxWidth}`);
    }
  }

  const placements = [];
  let shelfX = 0, shelfY = 0, shelfH = 0, usedW = 0;
  for (const r of sorted) {
    const w = r.w + padding, h = r.h + padding;
    if (shelfX + w > maxWidth) { shelfY += shelfH; shelfX = 0; shelfH = 0; } // wrap to a new shelf
    placements.push({ name: r.name, x: shelfX, y: shelfY, w: r.w, h: r.h });
    shelfX += w;
    usedW = Math.max(usedW, shelfX);
    shelfH = Math.max(shelfH, h);
  }
  const totalH = shelfY + shelfH;
  const pow2 = (n) => { let p = 1; while (p < n) p <<= 1; return p; };
  return { sheet: { w: pow2(usedW), h: pow2(totalH) }, placements };
}

// Canonical boot-splash dimensions for the given orientation. Portrait is the
// default; the manifest schema makes build.orientation optional (absent = portrait).
// Fresh object each call (no shared mutable singleton). Pure.
export function splashSize(orientation = "portrait") {
  return orientation === "landscape" ? { w: 1920, h: 1080 } : { w: 1080, h: 1920 };
}

// Generate the Godot project.godot [application] boot_splash block. Text, pure,
// and round-trips through parsePresetCfg — same "reviewable + diffable + parses"
// discipline as exportPresetCfg (the real boot-splash wiring rides project.godot).
export function bootSplashCfg({ image, showImage = true } = {}) {
  if (!image) throw new Error("package: bootSplashCfg requires an image path");
  assertCfgSafe(image, "bootSplashCfg image");
  return [
    "[application]",
    "",
    `application/boot_splash/show_image=${showImage ? "true" : "false"}`,
    `application/boot_splash/image="${image}"`,
    "application/boot_splash/fullsize=true",
    ""
  ].join("\n");
}

// Extract the leading "#rrggbb" from a palette entry like "#2fa6a0 sea-teal (primary)".
// Pure; returns lowercased "#rrggbb" or null.
export function parseHexLead(s) {
  if (typeof s !== "string") return null;
  const m = s.trim().match(/^#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?/);
  return m ? `#${m[1].toLowerCase()}` : null;
}

// --- Icon background colour math (pure; encodes ASO icon rule 3 — contrast &
// chrome survival) -------------------------------------------------------------

// "#rrggbb" -> {r,g,b} 0..255. Assumes a validated 6-hex string.
function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}
const clamp01 = (x) => Math.min(1, Math.max(0, x));

// {r,g,b} 0..255 -> {h:0..360, s:0..1, l:0..1}.
function rgbToHsl({ r, g, b }) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  let h = 0, s = 0;
  if (d > 1e-6) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
  }
  return { h, s, l };
}

// {h,s,l} -> "#rrggbb".
function hslToHex({ h, s, l }) {
  h = ((h % 360) + 360) % 360;
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  let r = 0, g = 0, b = 0;
  if (h < 60) [r, g, b] = [c, x, 0];
  else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x];
  else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  const to = (v) => Math.round((v + m) * 255).toString(16).padStart(2, "0");
  return `#${to(r)}${to(g)}${to(b)}`;
}

// WCAG relative luminance 0..1 — how an icon background reads against store chrome.
export function srgbLuminance(hex) {
  const { r, g, b } = hexToRgb(hex);
  const lin = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}
// Smallest circular distance between two hues, 0..180.
export function hueDelta(a, b) {
  const d = Math.abs((((a % 360) + 360) % 360) - (((b % 360) + 360) % 360));
  return Math.min(d, 360 - d);
}
// Hue (0..360) of a "#rrggbb".
export function iconHue(hex) { return rgbToHsl(hexToRgb(hex)).h; }

// Condition a palette-derived icon background so it reads as a deep, saturated
// plate that survives BOTH light and dark store chrome and carries radial depth
// (centre/top brighter than edge/bottom). Pure. ASO rule 3's computable half —
// the "opaque colour plate, survives light & dark" guarantee. Applied ONLY to the
// auto (palette-derived) path; explicit/recorded backgrounds are respected verbatim.
const BG_L_FLOOR = 0.16;   // not so dark it dies on black chrome / swallows the subject
const BG_L_CEIL = 0.56;    // not so light it vanishes on white store chrome
const BG_S_FLOOR = 0.30;   // keep the plate saturated, not muddy
const BG_DEPTH = 0.14;     // centre-vs-edge luminance gap so the radial glow reads
export function conditionIconBg({ top, bottom }) {
  const a = rgbToHsl(hexToRgb(top));
  const b = rgbToHsl(hexToRgb(bottom));
  if (a.s > 0.08) a.s = Math.max(a.s, BG_S_FLOOR);  // saturate hues; never colourize a true grey
  if (b.s > 0.08) b.s = Math.max(b.s, BG_S_FLOOR);
  const mid = clamp01((a.l + b.l) / 2);
  const midC = Math.min(BG_L_CEIL - BG_DEPTH / 2, Math.max(BG_L_FLOOR + BG_DEPTH / 2, mid));
  a.l = midC + BG_DEPTH / 2;   // top = radial centre = brighter glow
  b.l = midC - BG_DEPTH / 2;   // bottom = rim = deeper vignette
  return { top: hslToHex(a), bottom: hslToHex(b) };
}

// If the palette-derived background hue sits too close to the subject's hue (a
// low-contrast clash), rotate the background to the subject's complement so the
// subject pops. Pure; no-op when the subject is ~neutral or already contrasts.
const BG_CLASH_DEG = 45;
export function complementaryBg(subjectHex, { top, bottom }) {
  const subj = rgbToHsl(hexToRgb(subjectHex));
  if (subj.s < 0.20) return { top, bottom };                      // no clear subject hue to oppose
  if (hueDelta(subj.h, iconHue(top)) >= BG_CLASH_DEG) return { top, bottom };  // already contrasts
  const comp = (subj.h + 180) % 360;
  const rot = (hex) => { const c = rgbToHsl(hexToRgb(hex)); c.h = comp; return hslToHex(c); };
  return { top: rot(top), bottom: rot(bottom) };
}

// Decide the two-stop icon background, in priority order:
// --bg arg ("#top,#bottom" or "#solid") > store_pass.icon_bg > asset_pass palette
// (auto: complement vs the subject hue, then condition for chrome survival + depth)
// > neutral default. `subjectHex` (the focal's dominant opaque hue, probed by
// generateIcons or recorded as store_pass.icon_subject_hex) drives the complement.
// Explicit/recorded/default backgrounds are deliberate → returned verbatim. Pure.
export function resolveIconBg({ bgArg, manifest = {}, subjectHex } = {}) {
  const fromSpec = (spec) => {
    if (typeof spec !== "string" || !spec.trim()) return null;
    const parts = spec.split(",").map((p) => parseHexLead(p)).filter(Boolean);
    if (parts.length === 0) return null;
    return { top: parts[0], bottom: parts[1] || parts[0] };
  };
  const fromArg = fromSpec(bgArg);
  if (fromArg) return fromArg;                              // explicit override: verbatim
  const fromManifest = fromSpec(manifest?.store_pass?.icon_bg);
  if (fromManifest) return fromManifest;                    // recorded choice: verbatim
  const subj = subjectHex || parseHexLead(manifest?.store_pass?.icon_subject_hex);
  const palette = manifest?.asset_pass?.visual_system?.palette;
  if (Array.isArray(palette)) {
    const hexes = palette.map(parseHexLead).filter(Boolean);
    if (hexes.length >= 1) {
      let bg = { top: hexes[0], bottom: hexes[1] || hexes[0] };
      if (subj) bg = complementaryBg(subj, bg);             // fix a subject↔bg hue clash
      return conditionIconBg(bg);                           // guarantee chrome survival + radial depth
    }
  }
  return { top: "#202830", bottom: "#202830" };             // neutral default: already chrome-safe
}

// Icon background style: "radial" (default — a bright glow behind the subject +
// a soft drop shadow under it, the premium app-store look) or "linear" (the flat
// 2-stop vertical gradient). Pure; defaults to radial, throws on anything else.
export function parseIconBgStyle(arg) {
  const v = arg || "radial";
  if (v !== "linear" && v !== "radial") throw new Error(`package: --bg-style must be "linear" or "radial", got ${JSON.stringify(arg)}`);
  return v;
}

// Map an iconSizeTable kind to how icon_compose.gd renders it.
// focal = transparent subject inside the adaptive safe zone; background = gradient
// fill; composite = focal alpha-blended over the gradient, opaque. Pure.
export function iconCompositionRole(kind) {
  switch (kind) {
    case "adaptive_fg": return "focal";
    case "adaptive_bg": return "background";
    case "launcher":
    case "play": return "composite";
    default: throw new Error(`package: iconCompositionRole: unknown kind "${kind}"`);
  }
}

// Resolve the pinned Godot binary. Set GODOT_BIN to the absolute path of your
// Godot 4.6.3 console executable; otherwise we look for `godot` on PATH.
function godotBin() {
  return process.env.GODOT_BIN || "godot";
}

function runGodot(args, label) {
  try {
    return execFileSync(godotBin(), args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    const out = `${e.stdout ?? ""}${e.stderr ?? ""}`;
    throw new Error(`package: Godot ${label} failed: ${out || e.message}`);
  }
}

// Probe the focal's dominant opaque hue (drives the auto complementary background).
// Tolerant: returns null on any failure so a hue probe never blocks icon generation.
function probeFocalHue(focalAbs) {
  try {
    const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://focal_hue.gd", "--", focalAbs], "focal_hue");
    const m = out.match(/FOCAL_HUE\s+(#[0-9a-fA-F]{6})/);
    return m ? m[1].toLowerCase() : null;
  } catch {
    return null;
  }
}

// Compose the Android icon set from a transparent focal (store_pass.icon_master)
// over a themed background: distinct adaptive fg/bg + composited legacy/Play. The
// palette-derived background is auto-complemented against the focal's hue + chrome-
// conditioned (resolveIconBg); explicit --bg / store_pass.icon_bg bypass that.
export function generateIcons(id, { gamesDir = GAMES_DIR, bg, bgStyle } = {}) {
  const m = readManifest(id);
  const focal = m?.store_pass?.icon_master;
  if (!focal) throw new Error(`package: generateIcons needs store_pass.icon_master (a transparent focal PNG) in manifests/${id}.json`);
  const focalAbs = join(gamesDir, id, focal);
  if (!existsSync(focalAbs)) throw new Error(`package: icon focal not found at ${focalAbs}`);
  const subjectHex = probeFocalHue(focalAbs);
  const { top, bottom } = resolveIconBg({ bgArg: bg, manifest: m, subjectHex });
  const style = parseIconBgStyle(bgStyle);
  for (const e of iconSizeTable()) iconCompositionRole(e.kind); // validate kinds up front: a clearer JS error than a Godot stderr dump if the table gains an unmapped kind
  const outdir = join(gamesDir, id, "store", "icons");
  const specs = iconSizeTable().map((e) => `${e.name}:${e.px}:${e.kind}`).join(",");
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://icon_compose.gd", "--", focalAbs, outdir, specs, top, bottom, style], "icon_compose");
  if (!out.includes("ICON_COMPOSE OK")) throw new Error(`package: icon_compose did not report OK:\n${out}`);
  const legibility = checkIconLegibility(id, { gamesDir });   // ASO 48px legibility gate (advisory)
  return { outdir, bg: { top, bottom }, bg_style: style, subject_hex: subjectHex, legibility, icons: iconSizeTable().map((e) => ({ ...e, source: `store/icons/${e.name}.png` })) };
}

// --- Icon legibility scoring (pure) --------------------------------------
// CIELAB ΔE76 between two sRGB colours given as [r,g,b] 0..255. ΔE (not plain
// luminance) is deliberate: a complementary pairing like coral-on-teal reads as
// high contrast yet has near-equal luminance — only a chromatic metric scores it.
function srgbToLinear(c) {
  const x = c / 255;
  return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
}
function rgbToLab([r, g, b]) {
  const rl = srgbToLinear(r), gl = srgbToLinear(g), bl = srgbToLinear(b);
  const x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047;
  const y = (0.2126 * rl + 0.7152 * gl + 0.0722 * bl) / 1.0;
  const z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883;
  const f = (t) => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);
  const fx = f(x), fy = f(y), fz = f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}
export function labDeltaE(a, b) {
  const [l1, a1, b1] = rgbToLab(a);
  const [l2, a2, b2] = rgbToLab(b);
  return Math.hypot(l1 - l2, a1 - a2, b1 - b2);
}

// Score figure/ground legibility from an aligned thumbnail grid:
//   n     – grid edge length (the gate uses 48)
//   rgb   – n*n packed 0xRRGGBB of the COMPOSITE icon (subject already over plate)
//   alpha – n*n subject mask 0..255 (the focal's silhouette, placed where the
//           subject sits in the composite)
// Walks the SILHOUETTE (inside pixels adjacent to plate pixels) and measures the
// CIELAB ΔE between the subject side and the plate just outside it. Reports the
// 10th-percentile ΔE — the WORST-reading arc of the outline, not the average: a
// subject can contrast the plate on three sides yet melt into it on the fourth, and
// that fourth side is what kills it at thumbnail size. Sampling the silhouette (not
// the centre) is the whole point: a dark-cored subject on a bright same-hue plate
// scores high centre-vs-corner yet blends along its rim — the bug this replaces.
export function scoreIconLegibility({ n, rgb, alpha, deltaEMin = 22 }) {
  const IN = 128;
  const inside = (x, y) => alpha[y * n + x] >= IN;
  const unpack = (p) => [(p >> 16) & 255, (p >> 8) & 255, p & 255];
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  const samples = [];
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (!inside(x, y)) continue;
      const subj = unpack(rgb[y * n + x]);
      for (const [dx, dy] of dirs) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
        if (inside(nx, ny)) continue; // neighbour is plate → (x,y) is on the silhouette
        // step one more pixel outward (if still plate + in-bounds) to clear the AA fringe
        let bx = nx, by = ny;
        const fx = nx + dx, fy = ny + dy;
        if (fx >= 0 && fy >= 0 && fx < n && fy < n && !inside(fx, fy)) { bx = fx; by = fy; }
        samples.push(labDeltaE(subj, unpack(rgb[by * n + bx])));
      }
    }
  }
  if (samples.length === 0) return { ok: true, delta_e: null, delta_e_min: deltaEMin, edge_samples: 0 };
  samples.sort((p, q) => p - q);
  const de = samples[Math.min(Math.floor(samples.length * 0.1), samples.length - 1)];
  return { ok: de >= deltaEMin, delta_e: Math.round(de * 10) / 10, delta_e_min: deltaEMin, edge_samples: samples.length };
}

// Check the subject still pops off its plate at ~48px (ASO rules 6 & 9 —
// legibility at thumbnail size). The Godot side (icon_legibility.gd) emits an
// aligned thumbnail grid (composite RGB + the focal's silhouette mask); the SCORING
// — silhouette-edge vs adjacent plate, worst-arc ΔE — lives in pure JS
// (scoreIconLegibility), the testable seam. Advisory: returns { ok, warning,
// metrics }; ok=false is a WARN the packager surfaces in notes, not a hard failure.
// Tolerant of a missing/odd Godot result (ok=true, metrics=null).
export function checkIconLegibility(id, { gamesDir = GAMES_DIR, iconName = "ic_play_store" } = {}) {
  const iconAbs = join(gamesDir, id, "store", "icons", `${iconName}.png`);
  if (!existsSync(iconAbs)) throw new Error(`package: checkIconLegibility needs ${iconAbs} (run \`icons\` first)`);
  const m = readManifest(id);
  const focal = m?.store_pass?.icon_master;
  if (!focal) throw new Error(`package: checkIconLegibility needs store_pass.icon_master (the focal silhouette) in manifests/${id}.json`);
  const focalAbs = join(gamesDir, id, focal);
  if (!existsSync(focalAbs)) throw new Error(`package: icon focal not found at ${focalAbs}`);
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://icon_legibility.gd", "--", iconAbs, focalAbs], "icon_legibility");
  const gj = out.match(/ICON_LEGIBILITY_GRID (\{.*\})/);
  if (!gj) return { icon: iconName, ok: true, warning: null, metrics: null };
  const grid = JSON.parse(gj[1]);
  const score = scoreIconLegibility({ n: grid.n, rgb: grid.rgb, alpha: grid.alpha });
  const warning = score.ok ? null
    : `subject barely separates from the plate at ${grid.n}px (worst-arc ΔE ${score.delta_e} < ${score.delta_e_min}) — enlarge the subject or push its colour off the background`;
  return { icon: iconName, ok: score.ok, warning, metrics: { px: grid.n, delta_e: score.delta_e, delta_e_min: score.delta_e_min, edge_samples: score.edge_samples } };
}

// Build the atlas layout from the game's raster sprites, write the map JSON, render the sheet.
export function generateAtlas(id, { gamesDir = GAMES_DIR } = {}) {
  const artDir = join(gamesDir, id, "art");
  const sprites = existsSync(artDir) ? readdirSync(artDir).filter((f) => f.endsWith(".png")) : [];
  if (sprites.length === 0) throw new Error(`package: no .png sprites under ${artDir} to atlas`);
  const rects = sprites.map((f) => {
    const { w, h } = pngSize(readFileSync(join(artDir, f)));
    return { name: basename(f, ".png"), w, h };
  });
  const layout = atlasLayout(rects);
  const storeDir = join(gamesDir, id, "store");
  mkdirSync(storeDir, { recursive: true });
  const mapPath = join(storeDir, "atlas.json");
  writeFileSync(mapPath, JSON.stringify(layout, null, 2) + "\n");
  const sheetPath = join(storeDir, "atlas.png");
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://atlas_render.gd", "--", mapPath, artDir, sheetPath], "atlas_render");
  if (!out.includes("ATLAS_RENDER OK")) throw new Error(`package: atlas_render did not report OK:\n${out}`);
  return { sheet: "store/atlas.png", map: "store/atlas.json", sprite_count: rects.length, layout };
}

// Capture one gameplay screenshot on the real renderer (copies the harness in, runs, cleans up).
export function captureScreenshot(id, name, { gamesDir = GAMES_DIR, frames = 220 } = {}) {
  const gameDir = join(gamesDir, id);
  const harnessSrc = join(GODOT_DIR, "screenshot.gd");
  const harnessDst = join(gameDir, "_screenshot.gd");
  const storeDir = join(gameDir, "store", "screenshots");
  mkdirSync(storeDir, { recursive: true });
  const outPath = join(storeDir, `${name}.png`);
  copyFileSync(harnessSrc, harnessDst);
  try {
    const out = runGodot(["--path", gameDir, "--script", "res://_screenshot.gd", "--", outPath, String(frames)], "screenshot");
    if (!out.includes("SCREENSHOT OK")) throw new Error(`package: screenshot did not report OK:\n${out}`);
  } finally {
    rmSync(harnessDst, { force: true });
  }
  return { name, source: `store/screenshots/${name}.png`, path: outPath };
}

// Run a game-provided capture harness (committed at games/<id>/_shots.gd) on the
// REAL renderer; collect the {name, px, source} of every frame it prints. The
// harness drives the game's own state, so moment selection lives with the game.
export function captureScreenshotScript(id, { gamesDir = GAMES_DIR, script = "res://_shots.gd" } = {}) {
  const gameDir = join(gamesDir, id);
  const storeDir = join(gameDir, "store", "screenshots");
  mkdirSync(storeDir, { recursive: true });
  const out = runGodot(["--path", gameDir, "--script", script, "--", storeDir], "shots"); // NOT --headless
  if (!out.includes("SHOTS OK")) throw new Error(`package: capture script did not report SHOTS OK:\n${out}`);
  const shots = [];
  for (const line of out.split(/\r?\n/)) {
    const m = line.match(/wrote (.+\.png) \((\d+)x(\d+)\)/);
    if (m) {
      const name = basename(m[1], ".png");
      shots.push({ name, px: `${m[2]}x${m[3]}`, source: `store/screenshots/${name}.png` });
    }
  }
  return { script, shots };
}

// Render the boot splash from the icon master onto a solid background under games/<id>/store/.
// bg is "#RRGGBBAA" (the packager skill picks it from concept.theme); defaults to opaque black.
export function generateSplash(id, { gamesDir = GAMES_DIR, bg = "#000000ff", showImage = true } = {}) {
  const m = readManifest(id);
  const master = m?.store_pass?.icon_master;
  if (!master) throw new Error(`package: generateSplash needs store_pass.icon_master in manifests/${id}.json`);
  const masterAbs = join(gamesDir, id, master);
  if (!existsSync(masterAbs)) throw new Error(`package: icon master not found at ${masterAbs}`);
  const { w, h } = splashSize();
  const storeDir = join(gamesDir, id, "store");
  mkdirSync(storeDir, { recursive: true });
  const outPath = join(storeDir, "splash.png");
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://splash_render.gd", "--", masterAbs, outPath, `${w}x${h}`, bg], "splash_render");
  if (!out.includes("SPLASH_RENDER OK")) throw new Error(`package: splash_render did not report OK:\n${out}`);
  // store_pass.splash carries only {source, show_image}; boot_splash_cfg is for the skill to apply to project.godot.
  return { source: "store/splash.png", show_image: showImage, boot_splash_cfg: bootSplashCfg({ image: "res://store/splash.png", showImage }) };
}

// Source the release-signing env vars Godot reads (GODOT_ANDROID_KEYSTORE_RELEASE_*)
// from a git-ignored local config so no secret is ever committed. Returns the env
// overlay for the spawned process (empty for debug builds). Throws if a release
// build is requested without the config.
function releaseSigningEnv(buildType) {
  if (buildType !== "release") return {};
  const cfgPath = join(REPO_ROOT, "tools", "android-signing.local.json");
  if (!existsSync(cfgPath)) {
    throw new Error(`package: a release build needs signing config at ${cfgPath} (git-ignored). Create it with { "keystore_path", "keystore_user", "keystore_password" }.`);
  }
  const c = JSON.parse(readFileSync(cfgPath, "utf8"));
  for (const k of ["keystore_path", "keystore_user", "keystore_password"]) {
    if (!c[k]) throw new Error(`package: android-signing.local.json is missing "${k}"`);
  }
  return {
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH: c.keystore_path,
    GODOT_ANDROID_KEYSTORE_RELEASE_USER: c.keystore_user,
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD: c.keystore_password
  };
}

// Build the Android artifact by spawning headless Godot. Toolchain-guarded: returns
// { skipped, reason } when ANDROID_HOME/ANDROID_SDK_ROOT is unset (CI / no-SDK),
// so this is never reached in vitest. On success returns the build_artifact record.
export function buildArtifact(id, { gamesDir = GAMES_DIR, format = "apk", buildType = "debug", present = androidToolchainPresent() } = {}) {
  if (!present) {
    return { skipped: true, reason: "Android toolchain absent (ANDROID_HOME/ANDROID_SDK_ROOT unset) — skipping real export, same posture as no-GPU/no-ComfyUI." };
  }
  const m = readManifest(id);
  if (!m?.name) throw new Error(`package: buildArtifact needs a name in manifests/${id}.json`);
  const plan = buildArtifactPlan({ id, name: m.name, format, buildType, gamesDir });
  mkdirSync(join(gamesDir, id, "build"), { recursive: true });
  const env = { ...process.env, ...releaseSigningEnv(buildType) };
  try {
    execFileSync(godotBin(), plan.args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env });
  } catch (e) {
    const out = `${e.stdout ?? ""}${e.stderr ?? ""}`;
    throw new Error(`package: Godot ${buildType} ${format} export failed: ${out || e.message}`);
  }
  if (!existsSync(plan.outPath)) {
    throw new Error(`package: Godot reported success but no artifact at ${plan.outPath}`);
  }
  const bytes = statSync(plan.outPath).size;
  return {
    format: plan.format,
    build_type: plan.build_type,
    path: plan.outPath.slice(join(gamesDir, id).length + 1).replace(/\\/g, "/"),
    bytes,
    package: plan.package
  };
}

// Assert a recorded build_artifact's real file exists and is a well-formed ZIP
// (APK and AAB are both ZIP containers — first 4 bytes are PK\x03\x04). Guarded:
// skips when the toolchain is absent (binaries are git-ignored, not on CI).
export function verifyBuildArtifact(id, { gamesDir = GAMES_DIR, build_artifact, present = androidToolchainPresent() } = {}) {
  if (!present) return { skipped: true, reason: "toolchain absent — build artifact not checked" };
  const ba = build_artifact || readManifest(id)?.store_pass?.build_artifact;
  const issues = [];
  if (!ba) return { ok: false, issues: ["no build_artifact recorded in store_pass"] };
  const abs = join(gamesDir, id, ba.path);
  if (!existsSync(abs)) {
    issues.push(`build artifact absent: ${ba.path} (not found at ${abs})`);
    return { ok: false, issues, signature_ok: false };
  }
  const bytes = statSync(abs).size;
  if (bytes < 1024) issues.push(`build artifact suspiciously small: ${bytes} bytes`);
  const head = Buffer.alloc(4);
  const fd = openSync(abs, "r");
  try { readSync(fd, head, 0, 4, 0); } finally { closeSync(fd); }
  const signature_ok = head.equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]));
  if (!signature_ok) issues.push(`build artifact is not a ZIP (bad signature, not an APK/AAB): ${ba.path}`);
  return { ok: issues.length === 0, issues, signature_ok, bytes };
}

// Sum the committed store assets and compare to the budget. File-based; pure math via sizeBudget.
export function budgetReport(id, { gamesDir = GAMES_DIR, budgetBytes = DEFAULT_SIZE_BUDGET } = {}) {
  const storeDir = join(gamesDir, id, "store");
  const files = [];
  const walk = (dir) => {
    if (!existsSync(dir)) return;
    for (const ent of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else files.push({ path: p.slice(join(gamesDir, id).length + 1).replace(/\\/g, "/"), bytes: statSync(p).size });
    }
  };
  walk(storeDir);
  return sizeBudget(files, budgetBytes);
}

// Validator Method 5's headless, no-SDK assertions. Throws on the first hard failure.
export function verify(id, { gamesDir = GAMES_DIR, manifest } = {}) {
  const m = manifest || readManifest(id);
  const sp = m.store_pass;
  if (!sp) throw new Error(`package: verify: manifests/${id}.json has no store_pass`);
  const issues = [];

  // 1. every iconSizeTable entry exists at its exact px
  for (const want of iconSizeTable()) {
    const rec = (sp.icons || []).find((i) => i.name === want.name);
    if (!rec) { issues.push(`missing icon ${want.name}`); continue; }
    const abs = join(gamesDir, id, rec.source);
    if (!existsSync(abs)) { issues.push(`icon file absent: ${rec.source}`); continue; }
    const { w, h } = pngSize(readFileSync(abs));
    if (w !== want.px || h !== want.px) issues.push(`icon ${want.name} is ${w}x${h}, expected ${want.px}x${want.px}`);
  }

  // 1b. adaptive foreground and background must differ (the old single-master
  // path wrote identical files — not a valid adaptive icon).
  const fgRec = (sp.icons || []).find((i) => i.name === "ic_adaptive_foreground");
  const bgRec = (sp.icons || []).find((i) => i.name === "ic_adaptive_background");
  if (fgRec && bgRec) {
    const fgAbs = join(gamesDir, id, fgRec.source);
    const bgAbs = join(gamesDir, id, bgRec.source);
    if (existsSync(fgAbs) && existsSync(bgAbs)) {
      if (readFileSync(fgAbs).equals(readFileSync(bgAbs))) {
        issues.push("adaptive foreground and background are identical — not a valid adaptive icon (packager/icon_compose)");
      }
    }
  }

  // 2. atlas sheet exists and its map covers every member sprite
  if (sp.atlas) {
    const sheetAbs = join(gamesDir, id, sp.atlas.sheet);
    const mapAbs = join(gamesDir, id, sp.atlas.map);
    if (!existsSync(sheetAbs)) issues.push(`atlas sheet absent: ${sp.atlas.sheet}`);
    if (!existsSync(mapAbs)) issues.push(`atlas map absent: ${sp.atlas.map}`);
    else {
      const layout = JSON.parse(readFileSync(mapAbs, "utf8"));
      if ((layout.placements || []).length !== sp.atlas.sprite_count) {
        issues.push(`atlas map covers ${(layout.placements || []).length} sprites, store_pass says ${sp.atlas.sprite_count}`);
      }
    }
  }

  // 2b. splash, if recorded, exists at the canonical boot-splash dimensions
  if (sp.splash) {
    const splashAbs = join(gamesDir, id, sp.splash.source);
    if (!existsSync(splashAbs)) issues.push(`splash absent: ${sp.splash.source}`);
    else {
      const { w, h } = pngSize(readFileSync(splashAbs));
      const want = splashSize();
      if (w !== want.w || h !== want.h) issues.push(`splash is ${w}x${h}, expected ${want.w}x${want.h}`);
    }
  }

  // 3. size budget passes
  if (sp.size_budget && sp.size_budget.pass !== true) issues.push(`size budget fails: ${sp.size_budget.total_bytes} > ${sp.size_budget.budget_bytes}`);

  // 4. export preset parses as a valid Godot Android preset
  if (sp.export_preset) {
    const cfgAbs = join(gamesDir, id, sp.export_preset.path);
    if (!existsSync(cfgAbs)) issues.push(`export preset absent: ${sp.export_preset.path}`);
    else {
      const parsed = parsePresetCfg(readFileSync(cfgAbs, "utf8"));
      if (parsed["preset.0"]?.platform !== "Android") issues.push(`export preset platform is not Android`);
    }
  }

  // 5. both polish passes present (A/B confirmation is the human gate -- reported, not asserted here)
  const bothPasses = Boolean(m.asset_pass) && Boolean(m.audio_pass);

  // 6. build artifact record (shape only — the real file is git-ignored and
  // checked by verifyBuildArtifact() when the toolchain is present).
  if (sp.build_artifact) {
    const ba = sp.build_artifact;
    if (ba.format !== "apk" && ba.format !== "aab") issues.push(`build_artifact.format is "${ba.format}", expected apk|aab`);
    if (ba.build_type !== "debug" && ba.build_type !== "release") issues.push(`build_artifact.build_type is "${ba.build_type}", expected debug|release`);
    if (typeof ba.path !== "string" || !ba.path) issues.push(`build_artifact.path is missing`);
  }

  return { id, issues, file_checks_pass: issues.length === 0, both_passes_present: bothPasses, status: m.status };
}

// Parse the post-id args of `package.mjs screenshot`. --script <path> runs a
// game-provided capture harness (script owns its moments); otherwise boot mode
// captures one frame at [name] [frames]. Pure.
export function parseScreenshotArgs(args) {
  const i = args.indexOf("--script");
  if (i >= 0) {
    const script = args[i + 1];
    if (!script || script.startsWith("--")) throw new Error("package: screenshot --script needs a res:// path");
    return { mode: "script", script };
  }
  return { mode: "boot", name: args[0] || "screen-1", frames: Number(args[1] || 220) };
}

const USAGE = "usage: node tools/package.mjs <icons|legibility|atlas|screenshot|splash|budget|preset|build|verify|verify-build|--check> <id> ...";

async function cli(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === "--check") {
    const [id] = rest;
    if (!id) { console.error("usage: node tools/package.mjs --check <id>"); process.exit(2); }
    const r = verify(id);
    console.log(`package verify ${id}: file_checks=${r.file_checks_pass ? "PASS" : "FAIL"} both_passes_present=${r.both_passes_present} status=${r.status}`);
    if (r.issues.length) { console.error(r.issues.map((i) => `  - ${i}`).join("\n")); process.exit(1); }
    return;
  }
  const id = rest[0];
  if (!id) { console.error(USAGE); process.exit(2); }
  switch (cmd) {
    case "icons": {
      const bi = rest.indexOf("--bg");
      const bg = bi >= 0 ? rest[bi + 1] : undefined;
      const si = rest.indexOf("--bg-style");
      const bgStyle = si >= 0 ? rest[si + 1] : undefined;
      console.log(JSON.stringify(generateIcons(id, { bg, bgStyle }), null, 2));
      return;
    }
    case "legibility": console.log(JSON.stringify(checkIconLegibility(id), null, 2)); return;
    case "atlas": console.log(JSON.stringify(generateAtlas(id), null, 2)); return;
    case "screenshot": {
      const a = parseScreenshotArgs(rest.slice(1));
      const r = a.mode === "script"
        ? captureScreenshotScript(id, { script: a.script })
        : captureScreenshot(id, a.name, { frames: a.frames });
      console.log(JSON.stringify(r, null, 2));
      return;
    }
    case "splash": console.log(JSON.stringify(generateSplash(id, { bg: rest[1] || "#000000ff" }), null, 2)); return;
    case "budget": console.log(JSON.stringify(budgetReport(id), null, 2)); return;
    case "preset": {
      const m = readManifest(id);
      console.log(exportPresetCfg({ id, name: m.name }));
      return;
    }
    case "build": {
      const format = rest.includes("--aab") ? "aab" : "apk";
      const buildType = rest.includes("--release") ? "release" : "debug";
      const r = buildArtifact(id, { format, buildType });
      console.log(JSON.stringify(r, null, 2));
      if (r.skipped) process.exit(3); // distinct code: "toolchain absent", not a failure
      return;
    }
    case "verify-build": {
      const r = verifyBuildArtifact(id);
      console.log(JSON.stringify(r, null, 2));
      if (r.skipped) return;
      if (!r.ok) process.exit(1);
      return;
    }
    case "verify": { const r = verify(id); console.log(JSON.stringify(r, null, 2)); if (r.issues.length) process.exit(1); return; }
    default:
      console.error(USAGE);
      process.exit(2);
  }
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  cli(process.argv.slice(2)).catch((e) => { console.error(e.message); process.exit(1); });
}
