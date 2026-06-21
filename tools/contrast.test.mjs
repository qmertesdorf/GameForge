import { test, expect, describe } from "vitest";
import { relativeLuminance, wcagContrast, cvdTransform, measureCrop, contrastVerdict, measureCropFile, scoreTextMetrics } from "./contrast.mjs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
function godotAvailable() {
  try {
    execFileSync(process.env.GODOT_BIN || "godot", ["--version"], { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch { return false; }
}
const hasGodot = godotAvailable();

describe("scoreTextMetrics", () => {
  const nodes = [
    { path: "/root/Main/Score", class: "Label", text: "0", font_size: 40, rect: [0, 0, 60, 48], visible: true },
    { path: "/root/Main/Hint", class: "Label", text: "tap to start", font_size: 12, rect: [0, 60, 200, 16], visible: true },
    { path: "/root/Main/Hidden", class: "Label", text: "debug", font_size: 8, rect: [0, 80, 50, 10], visible: false },
    { path: "/root/Main/Themeless", class: "Button", text: "OK", font_size: 0, rect: [0, 100, 40, 20], visible: true },
  ];

  test("flags a visible sub-floor font, passes the large one", () => {
    const r = scoreTextMetrics(nodes, { minPx: 18 });
    expect(r.ok).toBe(false);
    expect(r.findings.map((f) => f.path)).toEqual(["/root/Main/Hint"]);
    expect(r.checked).toBe(2); // Score + Hint (Hidden skipped, Themeless unresolved)
  });

  test("hidden nodes are skipped unless includeHidden", () => {
    const r = scoreTextMetrics(nodes, { minPx: 18, includeHidden: true });
    expect(r.findings.map((f) => f.path).sort()).toEqual(["/root/Main/Hidden", "/root/Main/Hint"]);
  });

  test("unresolved (font_size 0) nodes are reported, not failed", () => {
    const r = scoreTextMetrics(nodes, { minPx: 18 });
    expect(r.unresolved.map((u) => u.path)).toEqual(["/root/Main/Themeless"]);
  });

  test("a generous floor passes everything visible+resolved", () => {
    expect(scoreTextMetrics(nodes, { minPx: 10 }).ok).toBe(true);
  });
});

describe("relativeLuminance", () => {
  test("white → 1, black → 0", () => {
    expect(relativeLuminance([255, 255, 255])).toBeCloseTo(1, 4);
    expect(relativeLuminance([0, 0, 0])).toBeCloseTo(0, 4);
  });
  test("green is the heaviest channel (Rec.709 weighting)", () => {
    expect(relativeLuminance([0, 255, 0])).toBeGreaterThan(relativeLuminance([255, 0, 0]));
    expect(relativeLuminance([255, 0, 0])).toBeGreaterThan(relativeLuminance([0, 0, 255]));
  });
});

describe("wcagContrast", () => {
  test("black vs white is the 21:1 maximum", () => {
    expect(wcagContrast([0, 0, 0], [255, 255, 255])).toBeCloseTo(21, 1);
  });
  test("a colour against itself is 1:1", () => {
    expect(wcagContrast([88, 88, 88], [88, 88, 88])).toBeCloseTo(1, 4);
  });
  test("symmetric (order does not matter)", () => {
    const a = [20, 20, 20], b = [200, 200, 200];
    expect(wcagContrast(a, b)).toBeCloseTo(wcagContrast(b, a), 6);
  });
  test("dark-on-dark numerals fail a body threshold", () => {
    expect(wcagContrast([60, 60, 60], [40, 40, 40])).toBeLessThan(4.5);
  });
});

describe("cvdTransform", () => {
  test("grayscale returns an equal-channel grey", () => {
    const [r, g, b] = cvdTransform([255, 80, 20], "grayscale");
    expect(r).toBe(g);
    expect(g).toBe(b);
  });
  test("deuteranopia of pure red is a deterministic, clamped value", () => {
    // Machado 2009 (severity 1.0), applied in sRGB and clamped to 0..255 ints.
    expect(cvdTransform([255, 0, 0], "deuteranopia")).toEqual([94, 71, 0]);
  });
  test("the red-green axis nearly vanishes under deuteranopia (hue confusion, not luminance)", () => {
    // CVD is a HUE collapse, not a contrast change — measured on the red-green
    // opponent channel (r-g), which is what a deuteranope cannot resolve.
    const opp = ([r, g]) => r - g;
    const red0 = [255, 0, 0], green0 = [0, 255, 0];
    const sepBefore = Math.abs(opp(red0) - opp(green0));
    const sepAfter = Math.abs(opp(cvdTransform(red0, "deuteranopia")) - opp(cvdTransform(green0, "deuteranopia")));
    expect(sepAfter).toBeLessThan(sepBefore * 0.2);
  });
  test("channels stay within 0..255", () => {
    for (const t of ["grayscale", "deuteranopia", "protanopia"]) {
      for (const px of [[255, 255, 255], [0, 0, 0], [255, 0, 255]]) {
        const out = cvdTransform(px, t);
        expect(Math.min(...out)).toBeGreaterThanOrEqual(0);
        expect(Math.max(...out)).toBeLessThanOrEqual(255);
      }
    }
  });
});

describe("measureCrop", () => {
  // pack [r,g,b] → 0xRRGGBB
  const p = ([r, g, b]) => (r << 16) | (g << 8) | b;
  const fill = (n, c) => Array.from({ length: n }, () => p(c));

  test("a two-tone text crop (dark strokes on a light panel) measures high contrast", () => {
    // 80% light backing, 20% dark strokes
    const crop = [...fill(80, [240, 240, 240]), ...fill(20, [20, 20, 20])];
    const r = measureCrop(crop);
    expect(r.contrast).toBeGreaterThan(10);
    expect(r.dark).toEqual([20, 20, 20]);
    expect(r.light).toEqual([240, 240, 240]);
  });

  test("dark-on-dark text measures a failing contrast", () => {
    const crop = [...fill(70, [45, 45, 45]), ...fill(30, [70, 70, 70])];
    const r = measureCrop(crop);
    expect(r.contrast).toBeLessThan(4.5);
  });

  test("a uniform crop has no distinct strokes → contrast 1", () => {
    const r = measureCrop(fill(50, [128, 128, 128]));
    expect(r.contrast).toBeCloseTo(1, 2);
  });
});

describe("contrastVerdict", () => {
  test("body text needs ≥ 4.5:1", () => {
    expect(contrastVerdict(4.5).ok).toBe(true);
    expect(contrastVerdict(4.49).ok).toBe(false);
    expect(contrastVerdict(4.5).threshold).toBe(4.5);
  });
  test("large/bold text needs only ≥ 3:1", () => {
    expect(contrastVerdict(3.0, { large: true }).ok).toBe(true);
    expect(contrastVerdict(2.99, { large: true }).ok).toBe(false);
    expect(contrastVerdict(3.0, { large: true }).threshold).toBe(3);
  });
});

// Godot decode → JS measure, end to end. Guarded: skips when Godot isn't on the
// machine (CI), runs locally with GODOT_BIN set — the same posture as the
// Android buildArtifact tests. Gives the crop_pixels.gd pixel op a regression net.
describe("measureCropFile (Godot integration, guarded)", () => {
  const fx = (n) => join(__dirname, "godot", "fixtures", n);
  test.skipIf(!hasGodot)("flags a dark-on-dark text crop", () => {
    const r = measureCropFile(fx("text_low_contrast.png"));
    expect(r.contrast).toBeLessThan(4.5);
    expect(r.verdict.ok).toBe(false);
  });
  test.skipIf(!hasGodot)("passes a high-contrast text crop", () => {
    const r = measureCropFile(fx("text_high_contrast.png"));
    expect(r.contrast).toBeGreaterThan(4.5);
    expect(r.verdict.ok).toBe(true);
  });
});
