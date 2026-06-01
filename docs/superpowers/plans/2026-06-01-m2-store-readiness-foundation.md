# M2 Store-Readiness (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the CI-testable foundation that turns a folder of mobile-grade game assets into the inputs an Android build needs — app icons (all densities + Play 512 + adaptive layers), boot splash, store screenshots, a texture atlas, an asset size-budget report, and an Android export preset — derived from the manifest, recorded in a new `store_pass` block, and gated by a new validator packaging method, **without** pulling in the Android SDK.

**Architecture:** Mirror the `comfy.mjs` pattern exactly — a pure, deterministic, vitest-tested JS seam (`tools/package.mjs`) paired with external Godot-engine scripts that do the pixel work (`tools/godot/*.gd`). Everything that can be unit-tested in CI (icon table, size-budget math, export-preset generation + parsing, atlas bin-packing, PNG-dimension reading) is pure and engine-free; the Godot scripts handle only what needs real pixels (resize, atlas composite, screenshot). Schema additions are additive/non-breaking (`store_pass` block + new terminal `packaged` status). A new `packager` skill derives the packaging set from `concept.theme` and records `store_pass`; the `validator` gains **Method 5 — packaging gate**, which asserts (headlessly, no SDK) that both polish passes are present + A/B-confirmed, every icon exists at its exact pixel size, the atlas covers every member, the budget passes, and the export preset parses, then advances `scored → packaged`.

**Tech Stack:** Node ESM, vitest, ajv (JSON Schema draft 2020-12), Godot 4.6.3 (GDScript, `Image` API + `SceneTree` screenshot harness). Tests run with `npx vitest run`.

---

## Background the engineer needs (read before starting)

- **The `comfy.mjs` precedent (`tools/comfy.mjs` + `tools/comfy.test.mjs`).** A pure function (`injectRecipe`) is unit-tested directly; the network flow (`gen`) is tested through a **mocked fetch**, never a live server; the real server is a separately-gated dependency. `package.mjs` follows this: the four/five pure functions are unit-tested; the Godot subprocess orchestration is thin and verified only by the proof exercise (Task 8), not by vitest — exactly as the real ComfyUI server is not exercised in CI.
- **Loud-failure contract.** Every `package.mjs` function throws with context (prefix `"package: "`) and writes **no partial output** on error. Copy the tone of `comfy.mjs`'s error strings.
- **Manifest tooling (`tools/manifest.mjs`).** `STATUSES` is an exported array; `TRANSITIONS` is the legal-transition map; `setStatus` enforces it. `merge` deep-merges a nested block and replaces arrays wholesale. `newManifest()` seeds `_reserved: { compliance, store, maintenance }`. **Do not touch `newManifest`/`merge`/`deepMerge`** — only `STATUSES` + `TRANSITIONS` change (for `packaged`).
- **Schema (`schema/manifest.schema.json`).** Root is `additionalProperties: false`, so a new top-level `store_pass` property **must** be declared or it is rejected. `asset_pass` and `audio_pass` are the two existing sibling pass-blocks to mirror. `_reserved.store` stays reserved/`null` — we add `store_pass` at top level, we do **not** promote `_reserved.store`.
- **Validator methods today (`.claude/skills/validator/SKILL.md`):** Method 1 (programmatic run-clean), Method 1.5 (selftest), Method 2 (human playtest → `playable`), Method 3 (re-skin → `styled`), **Method 4 (audio → `scored`)**. The packaging gate is therefore **Method 5** — the spec §6's "Method 4" label is stale; use **Method 5**.
- **Godot on this machine (`godot-binary-path` memory).** The `godot` shim is **PowerShell-only** and does **not** persist across sessions. **Run every Godot command via the PowerShell tool**, restoring the shim first:
  ```powershell
  $exe = "C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
  $binDir = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
  Set-Content "$binDir\godot.cmd" "@`"$exe`" %*"
  $env:Path += ";$binDir"
  godot --version   # -> 4.6.3.stable.official.7d41c59c4
  ```
  The `Image` API (`load_from_file`, `resize`, `blit_rect`, `save_png`) works under `--headless` (CPU-side). **Screenshots do NOT** — the `--headless` dummy renderer cannot capture pixels, so the screenshot harness runs **without** `--headless` on the real Vulkan renderer (RTX 5080). Pixel output (icon fidelity, atlas-on-screen, screenshot framing) and the APK are explicitly **not** CI-automatable (spec §10) — they are the owner aesthetic A/B + the §8 Android-toolchain feasibility gate.

Baseline before starting: `npx vitest run` → **72 passed**. Keep it green; it grows as each task adds tests.

---

## File Structure

**Created:**
- `tools/package.mjs` — the pure, tested seam + thin CLI/orchestration (mirrors `comfy.mjs`). One responsibility: derive + record the packaging set; spawn Godot for pixel ops.
- `tools/package.test.mjs` — vitest for every pure function (mirrors `comfy.test.mjs`). The CI regression guard.
- `tools/godot/project.godot` — minimal Godot tool-project so `--script` has a project context for the headless `Image` scripts.
- `tools/godot/icon_resize.gd` — headless: load a master PNG, resize to each requested size, save.
- `tools/godot/atlas_render.gd` — headless: composite member sprites into one atlas sheet from an `atlasLayout` JSON.
- `tools/godot/screenshot.gd` — real renderer: load a game's `Main.tscn`, wait N frames, save the viewport image. Copied into the game dir by `package.mjs`, then removed.
- `.claude/skills/packager/SKILL.md` — the new title-level packaging skill.

**Modified:**
- `schema/manifest.schema.json` — add top-level `store_pass`; add `"packaged"` to the `status` enum.
- `tools/manifest.mjs` — add `packaged` to `STATUSES` and `TRANSITIONS` (terminal; reachable from `scored`).
- `tools/manifest.test.mjs` — status-enum + transition tests; `store_pass` schema tests.
- `tools/skills.test.mjs` — add `"packager"` to `REQUIRED_SKILLS`.
- `.claude/skills/validator/SKILL.md` — add **Method 5 — packaging gate** (incl. the cross-modal cohesion A/B the theming precursor deferred to M2).
- `manifests/creature-0001.json` — the proof exercise records a `store_pass` block (status stays `validated`).

---

## Task 1: Schema + manifest status — `store_pass` block and the terminal `packaged` status

**Files:**
- Modify: `schema/manifest.schema.json` (the `status` enum at `schema/manifest.schema.json:13`; add `store_pass` as a new top-level property after the `audio_pass` block ends at `schema/manifest.schema.json:189`)
- Modify: `tools/manifest.mjs` (`STATUSES` at `tools/manifest.mjs:48`; `TRANSITIONS` at `tools/manifest.mjs:51-59`)
- Test: `tools/manifest.test.mjs` (status tests in `describe("setStatus", ...)` near `tools/manifest.test.mjs:220`; schema tests in `describe("validate", ...)` after the theme tests near `tools/manifest.test.mjs:196`)

- [ ] **Step 1: Write the failing tests — status enum + transitions**

In `tools/manifest.test.mjs`, the `describe("setStatus", ...)` block has a test asserting the exact `STATUSES` array (`tools/manifest.test.mjs:220-222`). Replace that test:

```javascript
  test("exposes the seven statuses through scored", () => {
    expect(STATUSES).toEqual(["concept", "generated", "validated", "playable", "styled", "scored", "failed"]);
  });
```

with:

```javascript
  test("exposes the eight statuses through packaged", () => {
    expect(STATUSES).toEqual(["concept", "generated", "validated", "playable", "styled", "scored", "packaged", "failed"]);
  });
```

Then, immediately after the existing `test("scored can fail", ...)` test (near `tools/manifest.test.mjs:281-284`), add:

```javascript
  test("scored can advance to packaged (canonical packaging path)", () => {
    const m = { ...base(), status: "scored" };
    expect(setStatus(m, "packaged").status).toBe("packaged");
  });
  test("packaged is terminal — cannot leave it", () => {
    const m = { ...base(), status: "packaged" };
    expect(() => setStatus(m, "scored")).toThrow();
    expect(() => setStatus(m, "failed")).toThrow();
  });
  test("rejects reaching packaged from a non-scored status", () => {
    const styled = { ...base(), status: "styled" };
    expect(() => setStatus(styled, "packaged")).toThrow(/illegal transition/);
  });
```

- [ ] **Step 2: Write the failing tests — `store_pass` schema**

In `tools/manifest.test.mjs`, inside `describe("validate", () => { ... })`, immediately after the `test("rejects an unknown key inside theme", ...)` test (near `tools/manifest.test.mjs:192-196`), add:

```javascript
  test("accepts a manifest carrying a full store_pass block", () => {
    const m = validManifest();
    m.store_pass = {
      icons: [{ name: "ic_launcher_xxxhdpi", px: 192, kind: "launcher", source: "store/icons/ic_launcher_xxxhdpi.png" }],
      splash: { source: "store/splash.png", show_image: true },
      screenshots: [{ name: "screen-1", px: "1080x1920", source: "store/screenshots/screen-1.png" }],
      atlas: { sheet: "store/atlas.png", map: "store/atlas.json", sprite_count: 2 },
      size_budget: { total_bytes: 1024, budget_bytes: 52428800, pass: true, per_file: [{ path: "store/atlas.png", bytes: 1024 }] },
      export_preset: { path: "export_presets.cfg", platform: "android", package: "com.gameforge.creature-0001" },
      icon_master: "art/spirit.png",
      notes: "foundation proof"
    };
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("accepts the packaged status value", () => {
    const m = validManifest();
    m.status = "packaged";
    expect(validate(m).valid).toBe(true);
  });

  test("store_pass is optional (no regression for pre-M2 manifests)", () => {
    expect(validate(validManifest()).valid).toBe(true);
  });

  test("rejects an unknown key inside store_pass", () => {
    const m = validManifest();
    m.store_pass = { icon_master: "art/x.png", bogus: true };
    expect(validate(m).valid).toBe(false);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — the status-enum test fails (STATUSES has 7), the `scored → packaged` / terminal tests fail (`packaged` unknown), the `store_pass` tests fail (root is `additionalProperties:false` with no `store_pass`), and the `packaged` status value is rejected by the enum.

- [ ] **Step 4: Add `packaged` to the schema status enum and the `store_pass` block**

In `schema/manifest.schema.json`, change the status enum (line 13):

```json
    "status": { "enum": ["concept", "generated", "validated", "playable", "styled", "scored", "failed"] },
```

to:

```json
    "status": { "enum": ["concept", "generated", "validated", "playable", "styled", "scored", "packaged", "failed"] },
```

Then add a top-level `store_pass` property. The `audio_pass` block ends at `schema/manifest.schema.json:189` (its closing `},` just before `"_reserved"`). Insert the following object **between** the `audio_pass` block's closing `}` and the `"_reserved"` property (i.e. as a new sibling property):

```json
    "store_pass": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "icons": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "name": { "type": "string" },
              "px": { "type": "number" },
              "kind": { "type": "string" },
              "source": { "type": "string" }
            }
          }
        },
        "splash": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "source": { "type": "string" },
            "show_image": { "type": "boolean" }
          }
        },
        "screenshots": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "name": { "type": "string" },
              "px": { "type": "string" },
              "source": { "type": "string" }
            }
          }
        },
        "atlas": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "sheet": { "type": "string" },
            "map": { "type": "string" },
            "sprite_count": { "type": "number" }
          }
        },
        "size_budget": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "total_bytes": { "type": "number" },
            "budget_bytes": { "type": "number" },
            "pass": { "type": "boolean" },
            "per_file": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                  "path": { "type": "string" },
                  "bytes": { "type": "number" }
                }
              }
            }
          }
        },
        "export_preset": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "path": { "type": "string" },
            "platform": { "type": "string" },
            "package": { "type": "string" }
          }
        },
        "icon_master": { "type": "string" },
        "notes": { "type": "string" }
      }
    },
```

Note: `store_pass` is NOT added to the root `required` list (only `asset_pass`/`audio_pass`-style optional blocks). `px` is a **number** for icons (square, e.g. `192`) and a **string** for screenshots (e.g. `"1080x1920"`) — matching spec §4 verbatim.

- [ ] **Step 5: Add `packaged` to `STATUSES` and `TRANSITIONS`**

In `tools/manifest.mjs`, change `STATUSES` (line 48):

```javascript
export const STATUSES = ["concept", "generated", "validated", "playable", "styled", "scored", "failed"];
```

to:

```javascript
export const STATUSES = ["concept", "generated", "validated", "playable", "styled", "scored", "packaged", "failed"];
```

Then change the `TRANSITIONS` map (lines 51-59). It currently reads:

```javascript
const TRANSITIONS = {
  concept: ["generated", "failed"],
  generated: ["validated", "failed"],
  validated: ["playable", "failed"],
  playable: ["styled", "scored", "failed"],
  styled: ["scored", "failed"],
  scored: ["styled", "failed"],
  failed: []
};
```

Replace with (add `packaged` to `scored`'s targets; add `packaged: []` as a terminal status):

```javascript
const TRANSITIONS = {
  concept: ["generated", "failed"],
  generated: ["validated", "failed"],
  validated: ["playable", "failed"],
  playable: ["styled", "scored", "failed"],
  styled: ["scored", "failed"],
  scored: ["styled", "packaged", "failed"],
  packaged: [],
  failed: []
};
```

Rationale (spec §2): the canonical incoming status for packaging is `scored` (audio A/B done; visual A/B already done at the earlier `styled` step). `packaged` is terminal. A `styled`-only game (no audio) must reach `scored` before `packaged` — so `styled → packaged` stays illegal. The "both passes present + A/B-confirmed" requirement is enforced by the **validator gate keying off the pass blocks** (Task 7), not by the status string alone.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — all new status + `store_pass` tests green.

- [ ] **Step 7: Run the whole suite**

Run: `npx vitest run`
Expected: green, count up by the 7 tests added here (1 status-enum test was edited in place, 3 transition tests + 4 schema tests added → 72 + 7 = **79 passed**).

- [ ] **Step 8: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat(schema): add store_pass block + terminal packaged status (M2 foundation)"
```

---

## Task 2: `package.mjs` — `iconSizeTable`, `sizeBudget`, `pngSize` (pure, tested)

**Files:**
- Create: `tools/package.mjs`
- Create: `tools/package.test.mjs`

- [ ] **Step 1: Write the failing tests**

Create `tools/package.test.mjs`:

```javascript
import { test, expect, describe } from "vitest";
import { iconSizeTable, sizeBudget, pngSize } from "./package.mjs";

describe("iconSizeTable", () => {
  test("returns all 8 required Android icon outputs", () => {
    const t = iconSizeTable();
    expect(t).toHaveLength(8);
    for (const e of t) {
      expect(typeof e.name).toBe("string");
      expect(typeof e.px).toBe("number");
      expect(typeof e.kind).toBe("string");
    }
  });

  test("launcher densities mdpi→xxxhdpi at exact px", () => {
    const launchers = iconSizeTable().filter((e) => e.kind === "launcher");
    expect(launchers.map((e) => e.px)).toEqual([48, 72, 96, 144, 192]);
  });

  test("includes the Play hi-res 512 and adaptive fg/bg at 432", () => {
    const t = iconSizeTable();
    expect(t.find((e) => e.kind === "play").px).toBe(512);
    const adaptive = t.filter((e) => e.kind === "adaptive_fg" || e.kind === "adaptive_bg");
    expect(adaptive).toHaveLength(2);
    expect(adaptive.every((e) => e.px === 432)).toBe(true);
  });

  test("names are unique and it returns a fresh array each call", () => {
    const a = iconSizeTable();
    const b = iconSizeTable();
    const names = a.map((e) => e.name);
    expect(new Set(names).size).toBe(names.length);
    expect(a).not.toBe(b); // not a shared mutable singleton
  });
});

describe("sizeBudget", () => {
  test("sums bytes and reports a per-file breakdown", () => {
    const r = sizeBudget([{ path: "a.png", bytes: 100 }, { path: "b.png", bytes: 250 }], 1000);
    expect(r.total).toBe(350);
    expect(r.budget_bytes).toBe(1000);
    expect(r.pass).toBe(true);
    expect(r.per_file).toEqual([{ path: "a.png", bytes: 100 }, { path: "b.png", bytes: 250 }]);
  });

  test("passes at the exact boundary (total === budget)", () => {
    expect(sizeBudget([{ path: "a", bytes: 500 }], 500).pass).toBe(true);
  });

  test("fails when total exceeds budget", () => {
    expect(sizeBudget([{ path: "a", bytes: 501 }], 500).pass).toBe(false);
  });

  test("empty file list totals 0 and passes", () => {
    expect(sizeBudget([], 10)).toEqual({ total: 0, budget_bytes: 10, pass: true, per_file: [] });
  });

  test("throws on a non-array files arg", () => {
    expect(() => sizeBudget("nope", 10)).toThrow(/array/);
  });

  test("throws on a malformed entry", () => {
    expect(() => sizeBudget([{ path: "a" }], 10)).toThrow(/path.*bytes|bytes/);
  });
});

describe("pngSize", () => {
  // Build a minimal valid PNG header: 8-byte signature + IHDR length+type+w+h.
  function pngHeader(w, h) {
    const buf = Buffer.alloc(24);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buf, 0); // signature
    buf.writeUInt32BE(13, 8);            // IHDR chunk length
    buf.write("IHDR", 12, "latin1");     // chunk type
    buf.writeUInt32BE(w, 16);            // width
    buf.writeUInt32BE(h, 20);            // height
    return buf;
  }

  test("reads width and height from the IHDR chunk", () => {
    expect(pngSize(pngHeader(192, 192))).toEqual({ w: 192, h: 192 });
    expect(pngSize(pngHeader(1080, 1920))).toEqual({ w: 1080, h: 1920 });
  });

  test("throws on a non-PNG buffer", () => {
    expect(() => pngSize(Buffer.from("not a png at all....."))).toThrow(/signature|PNG/);
  });

  test("throws on a too-short buffer", () => {
    expect(() => pngSize(Buffer.alloc(10))).toThrow(/24|PNG/);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs`
Expected: FAIL — `Cannot find module './package.mjs'` / functions undefined.

- [ ] **Step 3: Create `tools/package.mjs` with the three pure functions**

Create `tools/package.mjs`:

```javascript
import { readFileSync, writeFileSync, mkdirSync, statSync, existsSync, readdirSync, copyFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, basename } from "node:path";

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
  return { total, budget_bytes: budgetBytes, pass: total <= budgetBytes, per_file };
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs`
Expected: PASS (the `iconSizeTable`, `sizeBudget`, `pngSize` describe blocks all green).

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: green; +13 tests from this file → **79 + 13 = 92 passed**.

- [ ] **Step 6: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): iconSizeTable + sizeBudget + pngSize (pure seam)"
```

---

## Task 3: `package.mjs` — `exportPresetCfg` + `parsePresetCfg` (pure, round-tripping)

**Files:**
- Modify: `tools/package.mjs` (append the two functions)
- Modify: `tools/package.test.mjs` (add a describe block)

- [ ] **Step 1: Write the failing tests**

In `tools/package.test.mjs`, add a new import line at the top alongside the existing import:

```javascript
import { exportPresetCfg, parsePresetCfg } from "./package.mjs";
```

Then append this describe block at the end of the file:

```javascript
describe("exportPresetCfg + parsePresetCfg", () => {
  test("generates an Android preset that round-trips through the parser", () => {
    const cfg = exportPresetCfg({ id: "creature-0001", name: "Glade Spirit" });
    const parsed = parsePresetCfg(cfg);
    expect(parsed["preset.0"].platform).toBe("Android");
    expect(parsed["preset.0"].name).toBe("Glade Spirit");
    expect(parsed["preset.0"].runnable).toBe(true);
    expect(parsed["preset.0"].export_path).toBe("build/creature-0001-debug.apk");
    expect(parsed["preset.0.options"]["package/unique_name"]).toBe("com.gameforge.creature-0001");
    expect(parsed["preset.0.options"]["package/name"]).toBe("Glade Spirit");
  });

  test("honors an explicit packageName and exportPath", () => {
    const cfg = exportPresetCfg({ id: "x-0001", name: "X", packageName: "com.acme.x", exportPath: "out/x.apk" });
    const parsed = parsePresetCfg(cfg);
    expect(parsed["preset.0.options"]["package/unique_name"]).toBe("com.acme.x");
    expect(parsed["preset.0"].export_path).toBe("out/x.apk");
  });

  test("exportPresetCfg throws without id or name", () => {
    expect(() => exportPresetCfg({ id: "x" })).toThrow(/name|id/);
    expect(() => exportPresetCfg({ name: "X" })).toThrow(/id|name/);
  });

  test("parsePresetCfg strips quotes, coerces booleans and ints", () => {
    const parsed = parsePresetCfg('[preset.0]\n\nname="Hi"\nrunnable=true\nfoo=false\nn=42\n');
    expect(parsed["preset.0"]).toEqual({ name: "Hi", runnable: true, foo: false, n: 42 });
  });

  test("parsePresetCfg throws on a key before any section", () => {
    expect(() => parsePresetCfg('name="orphan"\n')).toThrow(/section/);
  });

  test("parsePresetCfg throws on an unparseable line", () => {
    expect(() => parsePresetCfg("[preset.0]\nthis line has no equals\n")).toThrow(/unparseable/);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs`
Expected: FAIL — `exportPresetCfg`/`parsePresetCfg` are not exported yet.

- [ ] **Step 3: Append the two functions to `tools/package.mjs`**

Add to `tools/package.mjs` (after `pngSize`):

```javascript
// Generate a minimal-but-valid Godot Android export_presets.cfg string. Pure.
export function exportPresetCfg({ id, name, packageName, exportPath } = {}) {
  if (!id || !name) {
    throw new Error("package: exportPresetCfg requires both { id, name }");
  }
  const unique = packageName || `com.gameforge.${id}`;
  const out = exportPath || `build/${id}-debug.apk`;
  return [
    "[preset.0]",
    "",
    `name="${name}"`,
    `platform="Android"`,
    "runnable=true",
    `export_filter="all_resources"`,
    `include_filter=""`,
    `exclude_filter=""`,
    `export_path="${out}"`,
    "",
    "[preset.0.options]",
    "",
    `package/unique_name="${unique}"`,
    `package/name="${name}"`,
    ""
  ].join("\n");
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: green; +6 tests → **92 + 6 = 98 passed**.

- [ ] **Step 6: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): exportPresetCfg + parsePresetCfg (round-trip Android preset)"
```

---

## Task 4: `package.mjs` — `atlasLayout` (deterministic shelf packer)

**Files:**
- Modify: `tools/package.mjs` (append the function)
- Modify: `tools/package.test.mjs` (add a describe block)

- [ ] **Step 1: Write the failing tests**

In `tools/package.test.mjs`, add to the top import group:

```javascript
import { atlasLayout } from "./package.mjs";
```

Append this describe block at the end of the file:

```javascript
describe("atlasLayout", () => {
  // No two placements may overlap (axis-aligned rectangle intersection test).
  function anyOverlap(placements) {
    for (let i = 0; i < placements.length; i++) {
      for (let j = i + 1; j < placements.length; j++) {
        const a = placements[i], b = placements[j];
        const sep = a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y;
        if (!sep) return true;
      }
    }
    return false;
  }

  test("packs a single rect at the origin in a power-of-two sheet", () => {
    const out = atlasLayout([{ name: "hero", w: 100, h: 80 }]);
    expect(out.placements).toEqual([{ name: "hero", x: 0, y: 0, w: 100, h: 80 }]);
    expect(out.sheet.w).toBe(128);
    expect(out.sheet.h).toBe(128);
  });

  test("places every rect with no overlap and inside the sheet", () => {
    const rects = [
      { name: "a", w: 200, h: 200 }, { name: "b", w: 150, h: 100 },
      { name: "c", w: 300, h: 120 }, { name: "d", w: 64, h: 64 }
    ];
    const out = atlasLayout(rects, { maxWidth: 512 });
    expect(out.placements).toHaveLength(rects.length);
    expect(out.placements.map((p) => p.name).sort()).toEqual(["a", "b", "c", "d"]);
    expect(anyOverlap(out.placements)).toBe(false);
    for (const p of out.placements) {
      expect(p.x + p.w).toBeLessThanOrEqual(out.sheet.w);
      expect(p.y + p.h).toBeLessThanOrEqual(out.sheet.h);
    }
  });

  test("is deterministic — identical input yields identical output", () => {
    const rects = [{ name: "a", w: 90, h: 40 }, { name: "b", w: 90, h: 40 }, { name: "c", w: 30, h: 70 }];
    expect(atlasLayout(rects, { maxWidth: 128 })).toEqual(atlasLayout(rects, { maxWidth: 128 }));
  });

  test("empty input yields an empty sheet", () => {
    expect(atlasLayout([])).toEqual({ sheet: { w: 0, h: 0 }, placements: [] });
  });

  test("throws when a rect is wider than maxWidth", () => {
    expect(() => atlasLayout([{ name: "wide", w: 2000, h: 10 }], { maxWidth: 1024 })).toThrow(/maxWidth|wide/);
  });

  test("throws on a malformed rect", () => {
    expect(() => atlasLayout([{ name: "a", w: 10 }])).toThrow(/w.*h|h/);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs`
Expected: FAIL — `atlasLayout` is not exported yet.

- [ ] **Step 3: Append `atlasLayout` to `tools/package.mjs`**

Add to `tools/package.mjs` (after `parsePresetCfg`):

```javascript
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs`
Expected: PASS. (Verify the single-rect sheet math: `usedW = 100 → pow2 = 128`, `totalH = 80 → pow2 = 128`.)

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: green; +6 tests → **98 + 6 = 104 passed**.

- [ ] **Step 6: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): atlasLayout deterministic shelf packer"
```

---

## Task 5: Godot pixel scripts + `package.mjs` CLI orchestration

This task adds the engine side (the `comfy.mjs` analog of "ComfyUI does the heavy lifting") and the thin CLI that orchestrates it. The pixel scripts are verified by a Godot parse-check (`--check-only`) and exercised for real in Task 8; they are **not** vitest-tested (no engine in CI), exactly as `comfy.mjs`'s live-server path is not.

**Files:**
- Create: `tools/godot/project.godot`
- Create: `tools/godot/icon_resize.gd`
- Create: `tools/godot/atlas_render.gd`
- Create: `tools/godot/screenshot.gd`
- Modify: `tools/package.mjs` (add orchestration helpers + a CLI)

- [ ] **Step 1: Create the minimal Godot tool-project**

Create `tools/godot/project.godot`:

```
config_version=5

[application]

config/name="GameForge packaging tools"
config/features=PackedStringArray("4.6")
```

This exists only so `godot --path tools/godot/ --script res://<x>.gd` has a project context for the headless `Image` scripts. The scripts read/write **absolute** filesystem paths passed as user args, so they do not depend on any game's `res://`.

- [ ] **Step 2: Create `tools/godot/icon_resize.gd` (headless)**

Create `tools/godot/icon_resize.gd`:

```gdscript
extends SceneTree

# Resize a master PNG into N square icon outputs.
# Run: godot --headless --path tools/godot/ --script res://icon_resize.gd -- <master.png> <outdir> <name:px,name:px,...>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("icon_resize: usage: -- <master.png> <outdir> <name:px,name:px,...>")
		quit(1)
		return
	var master_path := args[0]
	var outdir := args[1]
	var specs := args[2].split(",", false)

	var img := Image.load_from_file(master_path)
	if img == null:
		push_error("icon_resize: failed to load master %s" % master_path)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(outdir)

	for spec in specs:
		var parts := spec.split(":")
		if parts.size() != 2:
			push_error("icon_resize: bad spec '%s' (expected name:px)" % spec)
			quit(1)
			return
		var icon_name := parts[0]
		var px := int(parts[1])
		var copy := img.duplicate() as Image
		copy.resize(px, px, Image.INTERPOLATE_LANCZOS)
		var dest := outdir.path_join(icon_name + ".png")
		var serr := copy.save_png(dest)
		if serr != OK:
			push_error("icon_resize: failed to save %s (err %d)" % [dest, serr])
			quit(1)
			return
		print("icon_resize: wrote %s (%dx%d)" % [dest, px, px])

	print("ICON_RESIZE OK")
	quit(0)
```

- [ ] **Step 3: Create `tools/godot/atlas_render.gd` (headless)**

Create `tools/godot/atlas_render.gd`:

```gdscript
extends SceneTree

# Composite member sprites into one atlas sheet from an atlasLayout JSON.
# Run: godot --headless --path tools/godot/ --script res://atlas_render.gd -- <layout.json> <sprite_dir> <out_sheet.png>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("atlas_render: usage: -- <layout.json> <sprite_dir> <out_sheet.png>")
		quit(1)
		return
	var layout_path := args[0]
	var sprite_dir := args[1]
	var out_path := args[2]

	var txt := FileAccess.get_file_as_string(layout_path)
	if txt == "":
		push_error("atlas_render: could not read layout %s" % layout_path)
		quit(1)
		return
	var data = JSON.parse_string(txt)
	if data == null or not data.has("sheet") or not data.has("placements"):
		push_error("atlas_render: layout JSON missing sheet/placements")
		quit(1)
		return

	var sheet_w := int(data["sheet"]["w"])
	var sheet_h := int(data["sheet"]["h"])
	var target := Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
	target.fill(Color(0, 0, 0, 0))

	for p in data["placements"]:
		var src := Image.load_from_file(sprite_dir.path_join(str(p["name"]) + ".png"))
		if src == null:
			push_error("atlas_render: failed to load sprite %s" % str(p["name"]))
			quit(1)
			return
		if src.get_format() != Image.FORMAT_RGBA8:
			src.convert(Image.FORMAT_RGBA8)
		target.blit_rect(src, Rect2i(0, 0, src.get_width(), src.get_height()), Vector2i(int(p["x"]), int(p["y"])))

	var serr := target.save_png(out_path)
	if serr != OK:
		push_error("atlas_render: failed to save %s (err %d)" % [out_path, serr])
		quit(1)
		return
	print("ATLAS_RENDER OK")
	quit(0)
```

- [ ] **Step 4: Create `tools/godot/screenshot.gd` (real renderer — NOT headless)**

Create `tools/godot/screenshot.gd`:

```gdscript
extends SceneTree

# Capture a gameplay frame at a target size. Must run on the REAL renderer
# (NOT --headless — the dummy renderer cannot capture pixels).
# package.mjs copies this into games/<id>/ as res://_screenshot.gd and runs:
#   godot --path games/<id>/ --script res://_screenshot.gd -- <out.png> <frames>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("screenshot: usage: -- <out.png> [frames]")
		quit(1)
		return
	var out_path := args[0]
	var frames := int(args[1]) if args.size() > 1 else 220

	var packed := load("res://Main.tscn")
	if packed == null:
		push_error("screenshot: could not load res://Main.tscn")
		quit(1)
		return
	get_root().add_child(packed.instantiate())
	_capture(out_path, frames)

func _capture(out_path: String, frames: int) -> void:
	for _i in range(frames):
		await process_frame
	var img := get_root().get_texture().get_image()
	var serr := img.save_png(out_path)
	if serr != OK:
		push_error("screenshot: failed to save %s (err %d)" % [out_path, serr])
		quit(1)
		return
	print("SCREENSHOT OK")
	quit(0)
```

- [ ] **Step 5: Add CLI + orchestration to `tools/package.mjs`**

Append to `tools/package.mjs` (after `atlasLayout`). This is the thin engine-spawning layer — kept minimal and verified by Task 8, not vitest:

```javascript
// Resolve the pinned Godot binary. PowerShell carries a `godot` shim; fall back
// to the winget install path the README/memory pin (godot-binary-path).
function godotBin() {
  return process.env.GODOT_BIN
    || "C:\\Users\\quint\\AppData\\Local\\Microsoft\\WinGet\\Packages\\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\\Godot_v4.6.3-stable_win64_console.exe";
}

function runGodot(args, label) {
  try {
    return execFileSync(godotBin(), args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    const out = `${e.stdout ?? ""}${e.stderr ?? ""}`;
    throw new Error(`package: Godot ${label} failed: ${out || e.message}`);
  }
}

// Resize the icon master into every iconSizeTable() entry under games/<id>/store/icons/.
export function generateIcons(id, { gamesDir = GAMES_DIR } = {}) {
  const m = JSON.parse(readFileSync(join(REPO_ROOT, "manifests", `${id}.json`), "utf8"));
  const master = m?.store_pass?.icon_master;
  if (!master) throw new Error(`package: generateIcons needs store_pass.icon_master in manifests/${id}.json`);
  const masterAbs = join(gamesDir, id, master);
  if (!existsSync(masterAbs)) throw new Error(`package: icon master not found at ${masterAbs}`);
  const outdir = join(gamesDir, id, "store", "icons");
  const specs = iconSizeTable().map((e) => `${e.name}:${e.px}`).join(",");
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://icon_resize.gd", "--", masterAbs, outdir, specs], "icon_resize");
  if (!out.includes("ICON_RESIZE OK")) throw new Error(`package: icon_resize did not report OK:\n${out}`);
  return { outdir, icons: iconSizeTable().map((e) => ({ ...e, source: `store/icons/${e.name}.png` })) };
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
export function verify(id, { gamesDir = GAMES_DIR } = {}) {
  const m = JSON.parse(readFileSync(join(REPO_ROOT, "manifests", `${id}.json`), "utf8"));
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

  // 2. atlas sheet exists and its map covers every member sprite
  if (sp.atlas) {
    const sheetAbs = join(gamesDir, id, sp.atlas.sheet);
    const mapAbs = join(gamesDir, id, sp.atlas.map);
    if (!existsSync(sheetAbs)) issues.push(`atlas sheet absent: ${sp.atlas.sheet}`);
    if (!existsSync(mapAbs)) issues.push(`atlas map absent: ${sp.atlas.map}`);
    else {
      const layout = JSON.parse(readFileSync(mapAbs, "utf8"));
      if ((layout.placements || []).length !== sp.atlas.sprite_count) {
        issues.push(`atlas map covers ${layout.placements?.length} sprites, store_pass says ${sp.atlas.sprite_count}`);
      }
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

  // 5. both polish passes present (A/B confirmation is the human gate — reported, not asserted here)
  const bothPasses = Boolean(m.asset_pass) && Boolean(m.audio_pass);
  return { id, issues, file_checks_pass: issues.length === 0, both_passes_present: bothPasses, status: m.status };
}

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
  if (!id) { console.error("usage: node tools/package.mjs <icons|atlas|screenshot|budget|preset|verify|--check> <id> ..."); process.exit(2); }
  switch (cmd) {
    case "icons": console.log(JSON.stringify(generateIcons(id), null, 2)); return;
    case "atlas": console.log(JSON.stringify(generateAtlas(id), null, 2)); return;
    case "screenshot": console.log(JSON.stringify(captureScreenshot(id, rest[1] || "screen-1", { frames: Number(rest[2] || 220) }), null, 2)); return;
    case "budget": console.log(JSON.stringify(budgetReport(id), null, 2)); return;
    case "preset": {
      const m = JSON.parse(readFileSync(join(REPO_ROOT, "manifests", `${id}.json`), "utf8"));
      console.log(exportPresetCfg({ id, name: m.name }));
      return;
    }
    case "verify": { const r = verify(id); console.log(JSON.stringify(r, null, 2)); if (r.issues.length) process.exit(1); return; }
    default:
      console.error("usage: node tools/package.mjs <icons|atlas|screenshot|budget|preset|verify|--check> <id> ...");
      process.exit(2);
  }
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  cli(process.argv.slice(2)).catch((e) => { console.error(e.message); process.exit(1); });
}
```

- [ ] **Step 6: Verify the suite still passes (no new vitest, but confirm no syntax break)**

Run: `npx vitest run`
Expected: **104 passed** (unchanged — this task adds no unit tests; it must not break the module's parse/imports).

- [ ] **Step 7: Parse-check the Godot scripts on the real engine (PowerShell tool only)**

Restore the `godot` shim (see "Background" snippet), then run each script with `--check-only` (parses for errors and quits):

```powershell
godot --headless --path tools/godot/ --script res://icon_resize.gd --check-only
godot --headless --path tools/godot/ --script res://atlas_render.gd --check-only
godot --headless --path tools/godot/ --script res://screenshot.gd --check-only
```

Expected: each exits 0 with no parse errors. If `--check-only` is unavailable on this point release, fall back to running `icon_resize.gd` with no user args and confirm it prints the usage `push_error` and exits 1 (proves the script loads/runs). This is a local engine check — it is not part of `npx vitest run`.

- [ ] **Step 8: Commit**

```bash
git add tools/package.mjs tools/godot/
git commit -m "feat(package): Godot pixel scripts + CLI orchestration (icons, atlas, screenshot, verify)"
```

---

## Task 6: The `packager` skill

**Files:**
- Create: `.claude/skills/packager/SKILL.md`
- Modify: `tools/skills.test.mjs` (add `"packager"` to `REQUIRED_SKILLS` at `tools/skills.test.mjs:7`)

- [ ] **Step 1: Write the failing test — register `packager` as a required skill**

In `tools/skills.test.mjs`, change line 7:

```javascript
const REQUIRED_SKILLS = ["concept", "builder", "validator", "asset"];
```

to:

```javascript
const REQUIRED_SKILLS = ["concept", "builder", "validator", "asset", "packager"];
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/skills.test.mjs`
Expected: FAIL — the `skill: packager` "SKILL.md exists" and "has frontmatter" cases fail (file does not exist yet).

- [ ] **Step 3: Create `.claude/skills/packager/SKILL.md`**

Create `.claude/skills/packager/SKILL.md` (the frontmatter `name:` must equal `packager`; the test checks `name === skill` and `description.length > 10`):

```markdown
---
name: packager
description: Use when turning a fully-polished Godot title (both a confirmed visual asset_pass AND audio_pass) into the inputs an Android store build needs — launcher icons at every density, the Play 512 + adaptive layers, a boot splash, gameplay screenshots, a texture atlas, an asset size-budget report, and an Android export preset. Derives the packaging set from concept.theme, records store_pass, and hands off to validator's packaging gate for "packaged".
---

# packager

Turn a folder of mobile-grade assets into the **inputs a shippable Android build needs**, with the same legible-attribution discipline as every prior milestone: a re-runnable tool (`tools/package.mjs` + the `tools/godot/` pixel scripts) that derives the packaging set from the manifest, records it in `store_pass`, and is gated by `validator` Method 5. This runs as a title-level bolt-on **after** a game has both its visual and audio identity:

```
… → asset → [styled] → audio → [scored] → packager → validator(Method 5) → [packaged]
                                                                                 └→ (later) APK feasibility gate → store submission (owner)
```

## Inputs (both polish passes required)

- `manifests/<id>.json` carrying **both** an `asset_pass` (visual identity, owner A/B-confirmed → the game reached `styled`) **and** an `audio_pass` (audio identity, owner A/B-confirmed → the game reached `scored`). A primitive-art or silent game is **not** store-ready — both identities are mandatory (spec §2). The canonical incoming status is `scored`.
- The game on disk at `games/<id>/`, with its committed raster art under `games/<id>/art/`.
- The pinned Godot from `README.md` (`tools/package.mjs` spawns it for the pixel ops). ComfyUI is **not** needed here — packaging reuses art that already exists.

## Outputs

- `games/<id>/store/icons/*.png` — every `iconSizeTable()` entry (launcher mdpi→xxxhdpi, Play 512, adaptive fg/bg 432).
- `games/<id>/store/atlas.png` + `games/<id>/store/atlas.json` — the texture atlas + coordinate map.
- `games/<id>/store/screenshots/*.png` — gameplay frames at Play dimensions.
- `games/<id>/store/splash.png` (and the Godot `boot_splash` config).
- `games/<id>/export_presets.cfg` — a valid Android export preset.
- A populated `store_pass` block (icons, splash, screenshots, atlas, size_budget, export_preset, icon_master, notes).
- Hand-off to `validator` — **do not** set `packaged` yourself.

## Step 0 — Derive the packaging set FIRST (the real deliverable)

Like `asset`/`audio` Step 0, write the packaging decisions down **before** generating anything, anchored to `concept.theme` (premise/tone/mood_keywords/setting — the same modality-neutral world the visuals and audio express). The icon, splash, and screenshots are the title's **store face**; they must read as *that theme's world*, not a fourth independent interpretation. Decide and record verbatim in `store_pass`:

- **Icon master** — the styled hero/character sprite that best represents the theme (e.g. the painterly forest-spirit for a cozy-woodland title), or a deliberately-composed master. Record it as `store_pass.icon_master` (a path under `games/<id>/`). For this **foundation** the master is *derived from an existing sprite*; the **final** icon/splash art is an **owner aesthetic A/B**, recorded as deferred in `notes` (the inverse of `asset`'s "flag what SVG does badly").
- **Splash** — the boot image and whether to show it.
- **Screenshots** — which gameplay moments read best in a store listing (e.g. a mid-combo frame, a near-miss).
- **Atlas membership** — which sprite PNGs pack into the atlas.
- **Size budget** — the per-title byte budget (default 50 MiB; override via `GAMEFORGE_SIZE_BUDGET` or the tool opt).

## Flow

Run the tool (it pairs the pure JS seam with the Godot pixel scripts, exactly like `comfy.mjs`):

```
node tools/package.mjs icons <id>        # resize the icon master into every density (headless Image)
node tools/package.mjs atlas <id>        # pack art/*.png → store/atlas.png + atlas.json (headless Image)
node tools/package.mjs screenshot <id> <name> [frames]   # capture a play frame on the REAL renderer (not headless)
node tools/package.mjs budget <id>       # sum store assets vs the budget
node tools/package.mjs preset <id>       # print the Android export_presets.cfg (redirect into games/<id>/export_presets.cfg)
```

Then record `store_pass` (arrays replace wholesale — pass the full set):

```
node tools/manifest.mjs merge <id> "{\"store_pass\": { \"icon_master\": \"art/<hero>.png\", \"icons\": [ … ], \"splash\": { … }, \"screenshots\": [ … ], \"atlas\": { … }, \"size_budget\": { … }, \"export_preset\": { \"path\": \"export_presets.cfg\", \"platform\": \"android\", \"package\": \"com.gameforge.<id>\" }, \"notes\": \"…\" }}"
node tools/manifest.mjs validate <id>
```

## Hard requirements & honesty

- **Headless vs real renderer.** Icon resize + atlas composite use Godot's `Image` API and run **headless**. Screenshots **must not** be headless — the dummy renderer captures no pixels; `package.mjs` runs the harness on the real Vulkan renderer (see the `asset` raster note + `godot-binary-path`).
- **Mobile density.** Every launcher density comes from **downscaling** the high-res master, never upscaling — that is the app-store readiness the raster masters were sized for.
- **IP safety.** The icon/splash/screenshots inherit the art's IP posture; do not introduce franchise/character/studio likenesses. The owner aesthetic A/B is the final IP review (same as `asset`).
- **Do not** edit `concept`, `builder`, `asset`, or `audio`. Consume `concept.theme` + the two pass blocks as-is.
- **Do not** set `packaged` — hand to `validator`.

## Deferred (named gates — track, do not fake)

- **Actual APK build** (`godot --headless --export-debug "Android" …`) → the **Android-toolchain feasibility gate** (spec §8): needs the Android SDK + JDK (`ANDROID_HOME` unset here). Same shape as the ComfyUI (M1.5) and Stable-Audio (M1.6) gates — stood up once, a single decisive pass/fail.
- **Icon/splash aesthetic A/B + real store submission** (account, signing keys, listing copy, legal) → owner-gated, like every art/audio A/B.

## Hand off to the validator

Hand off to `validator`, which runs **Method 5 — packaging gate** (both pass blocks present + A/B-confirmed; every icon at its exact px; atlas map covers every member; budget passes; export preset parses; headless run still clean; cross-modal cohesion A/B) and advances `scored → packaged` on success, or records legible `issues` (attributed to `packager`/`package.mjs`) and stops.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run tools/skills.test.mjs`
Expected: PASS — `skill: packager` "SKILL.md exists" + "has frontmatter with matching name" green.

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: green; +2 tests (the two `describe.each` cases for `packager`) → **104 + 2 = 106 passed**.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/packager/SKILL.md tools/skills.test.mjs
git commit -m "feat(packager): new title-level packaging skill (derives store set from concept.theme)"
```

---

## Task 7: `validator` — Method 5 packaging gate

**Files:**
- Modify: `.claude/skills/validator/SKILL.md` (insert Method 5 after Method 4, which ends at `.claude/skills/validator/SKILL.md:99`, before the `## Notes` section at `.claude/skills/validator/SKILL.md:101`)

This is a prose edit; verification is vitest-green + a correct read.

- [ ] **Step 1: Insert Method 5 between Method 4 and the Notes section**

In `.claude/skills/validator/SKILL.md`, Method 4 ends with:

```markdown
Record results in `manifest.validation.issues` as needed. Audio validation does not block the visual pass and vice-versa.

## Notes
```

Insert a new Method 5 section **between** that paragraph and `## Notes` (keep both as-is; add the new section in the gap):

```markdown
Record results in `manifest.validation.issues` as needed. Audio validation does not block the visual pass and vice-versa.

## Method 5 — Packaging gate (`scored → packaged`, after the `packager` skill)

When `packager` has produced a `store_pass`, assert the title is genuinely store-ready — **headlessly and without the Android SDK** — then advance to the terminal `packaged` status. The CI-checkable assertions run through `tools/package.mjs verify` (pure file + dimension + parse checks; no GPU, no SDK):

```
node tools/package.mjs verify <id>
```

1. **Both polish passes present + A/B-confirmed.** A game is store-ready only with **both** a confirmed visual `asset_pass` **and** a confirmed `audio_pass` (spec §2). The gate keys off the **presence of both pass blocks** — the source of truth the `asset`/`audio` skills designate — **not** the lossy `status` string (which holds only `styled` *or* `scored` at once). The A/B *confirmation* itself is the human gate that advanced the title through `styled` (visual) and `scored` (audio): the canonical incoming status is `scored`, having passed through `styled`. If either block is absent, or the owner has not A/B-confirmed both visual and audio, **do not** advance — record "packager ran before both identities were owner-confirmed."
2. **Every icon at exact px.** Each `iconSizeTable()` entry exists at its **exact** pixel dimensions (read straight from each PNG's IHDR by `package.mjs`, no engine). A missing or wrong-sized icon is a `packager`/`package.mjs` finding.
3. **Atlas covers every member.** The atlas sheet exists and its map (`store/atlas.json`) has one placement per member sprite (`sprite_count` matches).
4. **Size budget passes.** `store_pass.size_budget.pass` is true (total committed store bytes ≤ budget). On failure, attribute it to oversized masters or too many assets — a specific `packager` choice.
5. **Export preset parses.** `games/<id>/export_presets.cfg` exists and parses as a valid Godot Android preset (`parsePresetCfg` → `preset.0.platform == "Android"`).
6. **Regression guard.** The game still imports + runs headless clean — `godot --headless --path games/<id>/ --quit-after 120`, exit 0 with no `SCRIPT ERROR`/`ERROR:`/"Failed to load" (packaging must not have broken the game).
7. **Cross-modal cohesion A/B (human).** The owner confirms the visuals, audio, **and the store icon/splash/screenshots** read as **one themed world** — the same premise/tone/setting from `concept.theme` — not four independent interpretations. (This is the M2 cohesion check the theming precursor explicitly deferred to here.) On failure, attribute it to a **`concept.theme` gap** (anchor too vague) or to the **skill that ignored the theme** (e.g. "packager: chose a hard-neon icon for a cozy-storybook theme — ignored `concept.theme.tone`") — a specific, fixable prose cause.

On all gates passing:
```
node tools/manifest.mjs set-status <id> packaged
node tools/manifest.mjs validate <id>
```
On failure, record the specific issue in `validation.issues`, attribute it to a skill (`packager` / `package.mjs`), and do **not** advance — the game stays `scored`. The **icon/splash aesthetic A/B** (item 7's aesthetic verdict) and the **real APK build** are explicitly the owner gate and the **§8 Android-toolchain feasibility gate** — not asserted here. The end-to-end `… → packaged` proof needs a `scored` game (owner-gated) plus the APK gate; the foundation exercises the CI-checkable assertions against the current substrate without claiming `packaged` (spec §9).

## Notes
```

- [ ] **Step 2: Verify the prose**

Re-read the edited file. Confirm: Method 5 appears **after** Method 4 (audio) and **before** `## Notes`; it references `node tools/package.mjs verify`, the both-passes-present gate, exact-px icons, atlas coverage, budget, preset parse, regression run, and the cross-modal cohesion A/B; and it advances `scored → packaged`. Confirm there is exactly one `## Notes` heading (you did not duplicate it).

- [ ] **Step 3: Run the whole suite**

Run: `npx vitest run`
Expected: **106 passed** (skill prose does not affect tests; confirm no accidental file damage).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "feat(validator): Method 5 packaging gate (exact-px icons, atlas, budget, preset, cohesion A/B)"
```

---

## Task 8: Proof exercise — run the seam against `creature-0001` (no status advance)

Exercise the foundation against the current substrate to confirm it runs and the CI-checkable gate assertions pass, **without** claiming `packaged` (spec §9). `creature-0001` is `validated` (its art + audio A/Bs are owner-gated, not yet confirmed) and carries both `asset_pass` and `audio_pass` blocks with a committed raster `art/spirit.png` (the icon master) + `art/hazard.png`. Recording a `store_pass` here is provenance only — exactly as it already carries `asset_pass`/`audio_pass` while held at `validated`; status does **not** change (and `validated → packaged` is illegal anyway).

**Files:**
- Modify: `manifests/creature-0001.json` (record `store_pass` via the merge CLI)
- Create: `games/creature-0001/store/**` + `games/creature-0001/export_presets.cfg` (committed outputs)

> **Run all Godot commands via the PowerShell tool with the shim restored** (see Background). The Bash tool will not see `godot`.

- [ ] **Step 1: Generate icons (headless) from the styled hero master**

First record the icon master so `generateIcons` can find it, then generate:

```bash
node tools/manifest.mjs merge creature-0001 "{\"store_pass\": {\"icon_master\": \"art/spirit.png\"}}"
```

Then (PowerShell, shim restored):

```powershell
node tools/package.mjs icons creature-0001
```

Expected: writes `games/creature-0001/store/icons/ic_launcher_mdpi.png` … `ic_adaptive_background.png` (8 files); stdout is the JSON `{ outdir, icons:[…] }`. If Godot reports it cannot load the master, that is an infra/path finding (attributable to `package.mjs`/the master path), not a fake-around.

- [ ] **Step 2: Build the atlas (headless)**

```powershell
node tools/package.mjs atlas creature-0001
```

Expected: writes `games/creature-0001/store/atlas.png` + `atlas.json`; stdout shows `sprite_count` (2 — spirit + hazard) and the layout. `ATLAS_RENDER OK` in the Godot output.

- [ ] **Step 3: Generate the export preset**

```powershell
node tools/package.mjs preset creature-0001 > games/creature-0001/export_presets.cfg
```

Expected: `games/creature-0001/export_presets.cfg` contains `[preset.0]`, `platform="Android"`, `name="Glade Spirit"`, `package/unique_name="com.gameforge.creature-0001"`.

- [ ] **Step 4: Capture a screenshot (REAL renderer — local GPU step)**

Screenshots need the real Vulkan renderer (not headless) and are explicitly **not** CI-automatable (spec §10). On this machine (RTX 5080) run:

```powershell
node tools/package.mjs screenshot creature-0001 screen-1 220
```

Expected: `SCREENSHOT OK` and `games/creature-0001/store/screenshots/screen-1.png`. If no renderer is available in the execution environment, record that this step is the owner/feasibility-gated visual capture and proceed — do **not** fabricate a frame.

- [ ] **Step 5: Compute the size budget and record the full `store_pass`**

```powershell
node tools/package.mjs budget creature-0001
```

Take the budget JSON, the icon list (from Step 1), the atlas info (Step 2), the screenshot (Step 4), and merge the complete `store_pass`. Run (PowerShell single-quote the JSON; fill the arrays from the tool output):

```powershell
node tools/manifest.mjs merge creature-0001 '{"store_pass":{"icon_master":"art/spirit.png","icons":[{"name":"ic_launcher_mdpi","px":48,"kind":"launcher","source":"store/icons/ic_launcher_mdpi.png"},{"name":"ic_launcher_hdpi","px":72,"kind":"launcher","source":"store/icons/ic_launcher_hdpi.png"},{"name":"ic_launcher_xhdpi","px":96,"kind":"launcher","source":"store/icons/ic_launcher_xhdpi.png"},{"name":"ic_launcher_xxhdpi","px":144,"kind":"launcher","source":"store/icons/ic_launcher_xxhdpi.png"},{"name":"ic_launcher_xxxhdpi","px":192,"kind":"launcher","source":"store/icons/ic_launcher_xxxhdpi.png"},{"name":"ic_play_store","px":512,"kind":"play","source":"store/icons/ic_play_store.png"},{"name":"ic_adaptive_foreground","px":432,"kind":"adaptive_fg","source":"store/icons/ic_adaptive_foreground.png"},{"name":"ic_adaptive_background","px":432,"kind":"adaptive_bg","source":"store/icons/ic_adaptive_background.png"}],"screenshots":[{"name":"screen-1","px":"720x1280","source":"store/screenshots/screen-1.png"}],"atlas":{"sheet":"store/atlas.png","map":"store/atlas.json","sprite_count":2},"export_preset":{"path":"export_presets.cfg","platform":"android","package":"com.gameforge.creature-0001"},"notes":"M2 foundation PROOF EXERCISE — tooling run against the validated substrate to confirm the seam executes + CI-checkable gate assertions pass. NOT packaged: creature-0001 is validated; both asset_pass + audio_pass are present but their owner A/B confirmations (and the cross-modal cohesion A/B) are still pending, and validated->packaged is illegal. icon_master derived from the styled spirit sprite; final icon/splash art is the deferred owner aesthetic A/B. APK build = the deferred Android-toolchain feasibility gate (ANDROID_HOME unset). Screenshot px reflects the project viewport (720x1280)."}}'
```

Then merge the `size_budget` object from the `budget` output (paste its `{total, budget_bytes, pass, per_file}` as `size_budget`):

```powershell
node tools/manifest.mjs merge creature-0001 '{"store_pass":{"size_budget":<PASTE_BUDGET_JSON_HERE>}}'
```

(The screenshot `px` string should match the actual project viewport — `games/creature-0001/project.godot` sets `window/size/viewport_width`/`_height`; the builder default is `720x1280`. Confirm and use the real value.)

- [ ] **Step 6: Run the CI-checkable gate assertions**

```bash
node tools/package.mjs verify creature-0001
```

Expected output: `file_checks_pass: true`, `both_passes_present: true`, `status: "validated"`, `issues: []`. This confirms every icon is at its exact px, the atlas map covers both sprites, the budget passes, and the export preset parses — **the foundation's CI-checkable assertions pass**. `verify` does **not** advance status; `both_passes_present:true` with `status:validated` correctly shows the owner A/B gates are still the blocker to `packaged`.

- [ ] **Step 7: Validate the manifest and confirm status unchanged**

```bash
node tools/manifest.mjs validate creature-0001
```

Expected: `creature-0001 OK`. Confirm `status` is still `validated` (merge does not change status; we intentionally did **not** call `set-status packaged`).

- [ ] **Step 8: Run the whole suite once more**

Run: `npx vitest run`
Expected: **106 passed**.

- [ ] **Step 9: Commit the proof outputs**

```bash
git add manifests/creature-0001.json games/creature-0001/store/ games/creature-0001/export_presets.cfg
git commit -m "feat(m2): foundation proof — store_pass + committed store assets for creature-0001 (held at validated)"
```

(The PNGs are binary — `.gitattributes` already marks `*.png binary`. `export_presets.cfg` is text/diffable.)

---

## Final: push to main

After all eight tasks commit and `npx vitest run` reports **106 passed**:

```bash
git push origin main
```

(Owner has standing authorization to push to `main` — the per-push-ask rule is retired, per the `m2-theming-direction` memory.)

---

## Self-Review (run after writing, before execution)

**Spec coverage** — every spec section maps to a task:
- Spec §1 (in-scope foundation: icons, splash, screenshots, atlas, size budget, export preset) → Tasks 2–5 (tooling) + Task 8 (exercised) ✓. *Splash:* the schema `store_pass.splash` block (Task 1) + the `packager` skill's splash decision (Task 6) cover the config/asset; no dedicated splash *generator* is built this cycle (a splash is a static image/Godot `boot_splash` setting, not a pixel-algorithm) — noted, not silent.
- Spec §2 (pipeline placement; `packaged` terminal; both passes required; gate keys off pass blocks not status) → Task 1 (transitions) + Task 6 (skill inputs) + Task 7 (Method 5 item 1) ✓
- Spec §3 (pure JS seam + Godot pixel scripts; loud-failure; env knobs `GAMEFORGE_GAMES_DIR`/`GAMEFORGE_SIZE_BUDGET`) → Tasks 2–5 ✓
- Spec §4 (additive `store_pass` block; `packaged` enum; `_reserved.store` left reserved; no change to root `required`) → Task 1 ✓ (top-level `store_pass`; `newManifest`/`merge` untouched)
- Spec §5 (the `packager` skill: both passes, Step 0 derive-set-first, icon-master honesty, hand off) → Task 6 ✓
- Spec §6 (validator packaging method: both passes present+A/B, exact-px icons, atlas coverage, budget, preset parses, regression run) → Task 7, **renamed Method 5** (Method 4 is audio) ✓
- Spec §7 (determinism; committed outputs; `*.png binary` already in `.gitattributes`) → Tasks 4/5 (deterministic `atlasLayout`/`iconSizeTable`) + Task 8 (committed) ✓
- Spec §8 (APK feasibility gate deferred — not built) → tracked in Task 6 + Task 7 prose; not built ✓
- Spec §9 (end-to-end proof deferred; foundation exercised against current substrate w/o claiming `packaged`) → Task 8 ✓ (status held at `validated`)
- Spec §10 (vitest for the pure funcs + schema; pixel output + APK gated, not CI) → Tasks 1–4 tests; Godot scripts parse-checked not unit-tested (Task 5 Step 7); screenshots local-GPU only (Task 8 Step 4) ✓
- Spec §11 (cycle deliverables) → all present ✓
- Spec §12 (roadmap fit) → narrative, no task needed ✓

**Placeholder scan** — no TBD/TODO/"add appropriate X"; every code, GDScript, prose, and command step shows exact content. The one `<PASTE_BUDGET_JSON_HERE>` in Task 8 Step 5 is a deliberate runtime value (the measured byte total of the just-generated files), not an authoring gap — the command and shape around it are exact. ✓

**Type/name consistency:**
- Pure function names are stable across tasks and consumers: `iconSizeTable`, `sizeBudget`, `pngSize` (Task 2); `exportPresetCfg`, `parsePresetCfg` (Task 3); `atlasLayout` (Task 4); all re-used by `verify`/orchestration (Task 5) and the validator prose (Task 7). ✓
- `store_pass` field names match across the schema (Task 1), the `packager` merge payload (Task 6), the proof merge (Task 8), and `verify` (Task 5): `icons[]{name,px,kind,source}`, `splash{source,show_image}`, `screenshots[]{name,px,source}`, `atlas{sheet,map,sprite_count}`, `size_budget{total_bytes,budget_bytes,pass,per_file[]{path,bytes}}`, `export_preset{path,platform,package}`, `icon_master`, `notes`. ✓
- Icon `px` is a **number**, screenshot `px` is a **string** — consistent in schema (Task 1), `iconSizeTable` (Task 2), and both merge payloads. ✓
- Godot OK-sentinels match between the `.gd` scripts and `package.mjs`'s `.includes()` checks: `ICON_RESIZE OK`, `ATLAS_RENDER OK`, `SCREENSHOT OK`. ✓
- Test-count arithmetic is threaded through every "run the suite" step: 72 → 79 → 92 → 98 → 104 → 104 → 106 → 106. ✓
- Validator method number: the new section is **Method 5** (Method 4 = audio), correcting spec §6's stale "Method 4." ✓
```