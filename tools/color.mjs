// Shared, pure colour math. CIELAB ΔE76 between two sRGB colours given as
// [r,g,b] 0..255. ΔE (not plain luminance) is deliberate: a complementary pairing
// like coral-on-teal reads as high contrast yet has near-equal luminance — only a
// chromatic metric scores it. Used by the icon-legibility gate (package.mjs) and
// the asset palette/seam QC (asset-qc.mjs). No I/O — pure functions only.

export function srgbToLinear(c) {
  const x = c / 255;
  return x <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
}

export function rgbToLab([r, g, b]) {
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

// Parse "#rrggbb" / "#rgb" / "rrggbb" into [r,g,b] 0..255. Throws on a malformed
// string so a bad palette entry fails loudly (attributable), never silently 0,0,0.
export function hexToRgb(hex) {
  let h = String(hex).trim().replace(/^#/, "");
  if (h.length === 3) h = h.split("").map((c) => c + c).join("");
  if (!/^[0-9a-fA-F]{6}$/.test(h)) throw new Error(`color: not a hex colour: ${JSON.stringify(hex)}`);
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}
