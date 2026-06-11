# Packager v2 — app-store-grade store face — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `packager` skill produce a genuinely app-store-grade icon (bespoke GPU focal → correct Android adaptive layers) and codify screenshot-moment capture, then prove it by re-packaging shopkeep-0001.

**Architecture:** Keep `tools/package.mjs` as the pure-JS seam + `tools/godot/*.gd` headless pixel scripts. Add pure, vitest-tested helpers (bg-gradient resolution, composition role, screenshot-arg parsing, an adaptive fg≠bg regression guard in `verify`). Replace the square-stretch `icon_resize.gd` with an alpha-compositing `icon_compose.gd` (transparent focal over a code gradient → distinct adaptive fg/bg + composited legacy/Play). Add a `screenshot --script` runner + a capture-harness template. Pixel correctness is proven by a real-Godot smoke + the shopkeep dogfood, mirroring the existing codebase discipline (Godot-spawning functions aren't unit-tested; only pure seams are).

**Tech Stack:** Node ESM (`tools/*.mjs`), vitest, Godot 4.6.3 headless `Image` API (GDScript `SceneTree` scripts), ComfyUI + Cartoon Arcadia XL + LayerDiffuse (dogfood focal gen only).

**Conventions for every task:**
- Run tests with: `npx vitest run tools/package.test.mjs` (whole-file) or append `-t "<name>"` to target one.
- `GODOT_BIN` is not on PATH across sessions — set it before any real-Godot step:
  `export GODOT_BIN="C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"`
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

## File Structure

- `tools/package.mjs` — **modify**: add `parseHexLead`, `resolveIconBg`, `iconCompositionRole`, `parseScreenshotArgs`, `captureScreenshotScript`; rework `generateIcons` (focal+bg); extend `verify` (adaptive fg≠bg); rewire `icons`/`screenshot` CLI.
- `tools/godot/icon_compose.gd` — **create**: composite focal over gradient into the 3 layer roles.
- `tools/godot/icon_resize.gd` — **delete**: superseded.
- `tools/godot/splash_render.gd` — **modify**: `blit_rect` → `blend_rect` (alpha-composite the now-transparent focal).
- `tools/godot/shots.template.gd` — **create**: the screenshot capture-harness template.
- `tools/package.test.mjs` — **modify**: tests for the new pure seams + the `verify` guard.
- `schema/manifest.schema.json` — **modify**: add optional `store_pass.icon_bg` (string).
- `.claude/skills/packager/SKILL.md` — **modify**: icon = bespoke focal + adaptive composition + `--bg`; screenshot harness pattern + `--script`; splash-from-focal; `icon_master` redefinition; GPU-posture line.
- `games/shopkeep-0001/**` — **dogfood**: regenerate focal + store face; `_shots.gd` committed.

---

## Task 1: Pure seam — bg gradient resolution

**Files:**
- Modify: `tools/package.mjs`
- Test: `tools/package.test.mjs`

- [ ] **Step 1: Write the failing tests**

Add to `tools/package.test.mjs`:

```js
import { parseHexLead, resolveIconBg } from "./package.mjs";

describe("parseHexLead", () => {
  test("extracts the leading #hex from a palette entry", () => {
    expect(parseHexLead("#2fa6a0 sea-teal (primary)")).toBe("#2fa6a0");
  });
  test("trims whitespace and lowercases", () => {
    expect(parseHexLead("  #FF7B54  coral")).toBe("#ff7b54");
  });
  test("returns null when no leading hex", () => {
    expect(parseHexLead("sea-teal")).toBe(null);
    expect(parseHexLead("")).toBe(null);
  });
});

describe("resolveIconBg", () => {
  test("--bg with two stops wins", () => {
    expect(resolveIconBg({ bgArg: "#111111,#222222", manifest: {} }))
      .toEqual({ top: "#111111", bottom: "#222222" });
  });
  test("--bg with one stop sets both", () => {
    expect(resolveIconBg({ bgArg: "#abcdef", manifest: {} }))
      .toEqual({ top: "#abcdef", bottom: "#abcdef" });
  });
  test("falls back to store_pass.icon_bg", () => {
    const manifest = { store_pass: { icon_bg: "#0a0b0c,#1a1b1c" } };
    expect(resolveIconBg({ manifest })).toEqual({ top: "#0a0b0c", bottom: "#1a1b1c" });
  });
  test("derives from the asset_pass palette's first two hexes", () => {
    const manifest = { asset_pass: { visual_system: { palette: [
      "#2fa6a0 sea-teal (primary)", "#ff7b54 coral (accent)", "#8a5a3b wood"
    ] } } };
    expect(resolveIconBg({ manifest })).toEqual({ top: "#2fa6a0", bottom: "#ff7b54" });
  });
  test("single-hex palette uses it for both stops", () => {
    const manifest = { asset_pass: { visual_system: { palette: ["#2fa6a0 only"] } } };
    expect(resolveIconBg({ manifest })).toEqual({ top: "#2fa6a0", bottom: "#2fa6a0" });
  });
  test("absent everything → neutral default", () => {
    expect(resolveIconBg({ manifest: {} })).toEqual({ top: "#202830", bottom: "#202830" });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs -t "parseHexLead"` and `-t "resolveIconBg"`
Expected: FAIL — `parseHexLead`/`resolveIconBg` are not exported.

- [ ] **Step 3: Implement the helpers**

Add to `tools/package.mjs` (near `iconSizeTable`, after `pngSize`):

```js
// Extract the leading "#rrggbb" from a palette entry like "#2fa6a0 sea-teal (primary)".
// Pure; returns lowercased "#rrggbb" or null.
export function parseHexLead(s) {
  if (typeof s !== "string") return null;
  const m = s.trim().match(/^#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?/);
  return m ? `#${m[1].toLowerCase()}` : null;
}

// Decide the two-stop vertical gradient for the icon background, in priority order:
// --bg arg ("#top,#bottom" or "#solid") > store_pass.icon_bg > asset_pass palette's
// first two hexes > neutral default. Pure (manifest is a plain object).
export function resolveIconBg({ bgArg, manifest = {} } = {}) {
  const fromSpec = (spec) => {
    if (typeof spec !== "string" || !spec.trim()) return null;
    const parts = spec.split(",").map((p) => parseHexLead(p)).filter(Boolean);
    if (parts.length === 0) return null;
    return { top: parts[0], bottom: parts[1] || parts[0] };
  };
  const fromArg = fromSpec(bgArg);
  if (fromArg) return fromArg;
  const fromManifest = fromSpec(manifest?.store_pass?.icon_bg);
  if (fromManifest) return fromManifest;
  const palette = manifest?.asset_pass?.visual_system?.palette;
  if (Array.isArray(palette)) {
    const hexes = palette.map(parseHexLead).filter(Boolean);
    if (hexes.length >= 2) return { top: hexes[0], bottom: hexes[1] };
    if (hexes.length === 1) return { top: hexes[0], bottom: hexes[0] };
  }
  return { top: "#202830", bottom: "#202830" };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs -t "parseHexLead"` then `-t "resolveIconBg"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): resolveIconBg + parseHexLead pure seams for icon gradient

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: Pure seam — icon composition role

**Files:**
- Modify: `tools/package.mjs`
- Test: `tools/package.test.mjs`

- [ ] **Step 1: Write the failing tests**

```js
import { iconCompositionRole, iconSizeTable } from "./package.mjs";

describe("iconCompositionRole", () => {
  test("adaptive_fg → focal (transparent subject in safe zone)", () => {
    expect(iconCompositionRole("adaptive_fg")).toBe("focal");
  });
  test("adaptive_bg → background (gradient fill)", () => {
    expect(iconCompositionRole("adaptive_bg")).toBe("background");
  });
  test("launcher + play → composite (focal over bg, opaque)", () => {
    expect(iconCompositionRole("launcher")).toBe("composite");
    expect(iconCompositionRole("play")).toBe("composite");
  });
  test("every iconSizeTable kind maps to a role", () => {
    for (const e of iconSizeTable()) {
      expect(["focal", "background", "composite"]).toContain(iconCompositionRole(e.kind));
    }
  });
  test("unknown kind throws (fail loud)", () => {
    expect(() => iconCompositionRole("nope")).toThrow();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs -t "iconCompositionRole"`
Expected: FAIL — not exported.

- [ ] **Step 3: Implement**

Add to `tools/package.mjs`:

```js
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs -t "iconCompositionRole"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): iconCompositionRole — fg/bg/composite role per icon kind

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: Pure seam — screenshot arg parsing

**Files:**
- Modify: `tools/package.mjs`
- Test: `tools/package.test.mjs`

- [ ] **Step 1: Write the failing tests**

```js
import { parseScreenshotArgs } from "./package.mjs";

describe("parseScreenshotArgs", () => {
  test("boot mode with defaults", () => {
    expect(parseScreenshotArgs([])).toEqual({ mode: "boot", name: "screen-1", frames: 220 });
  });
  test("boot mode with name + frames", () => {
    expect(parseScreenshotArgs(["gather", "300"]))
      .toEqual({ mode: "boot", name: "gather", frames: 300 });
  });
  test("--script switches to script mode", () => {
    expect(parseScreenshotArgs(["--script", "res://_shots.gd"]))
      .toEqual({ mode: "script", script: "res://_shots.gd" });
  });
  test("--script ignores trailing name/frames (the script owns them)", () => {
    expect(parseScreenshotArgs(["--script", "res://_shots.gd", "x", "9"]))
      .toEqual({ mode: "script", script: "res://_shots.gd" });
  });
  test("--script without a path throws", () => {
    expect(() => parseScreenshotArgs(["--script"])).toThrow();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs -t "parseScreenshotArgs"`
Expected: FAIL — not exported.

- [ ] **Step 3: Implement**

Add to `tools/package.mjs`:

```js
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs -t "parseScreenshotArgs"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): parseScreenshotArgs — boot vs --script capture modes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: verify() regression guard — adaptive fg ≠ bg

**Files:**
- Modify: `tools/package.mjs` (the `verify` function, after the icon px loop ~line 456)
- Test: `tools/package.test.mjs`

This directly guards the bug v2 fixes: the old single-master path wrote byte-identical `ic_adaptive_foreground` and `ic_adaptive_background`.

- [ ] **Step 1: Write the failing test**

Add inside `describe("verify (packaging gate)", ...)` in `tools/package.test.mjs` (mirror the existing tmp-fixture style — look at the existing block ~line 247-384 for how it stages a manifest + store files). Add:

```js
test("flags byte-identical adaptive foreground and background", () => {
  const dir = mkdtempSync(join(tmpdir(), "gf-adp-"));
  const id = "adp-0001";
  const store = join(dir, id, "store", "icons");
  mkdirSync(store, { recursive: true });
  // a real 1x1 PNG (any valid PNG) — same bytes written to both adaptive icons
  const onePx = Buffer.from(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4" +
    "890000000d49444154789c6360000002000100ffff03000006000557bfabd400" +
    "00000049454e44ae426082", "hex");
  // size them so the px check passes: write 432x432 by faking? Simpler — write the
  // same buffer to both; the px check will also fire, but we assert the dup issue too.
  writeFileSync(join(store, "ic_adaptive_foreground.png"), onePx);
  writeFileSync(join(store, "ic_adaptive_background.png"), onePx);
  const manifest = { status: "scored", asset_pass: {}, audio_pass: {}, store_pass: { icons: [
    { name: "ic_adaptive_foreground", source: "store/icons/ic_adaptive_foreground.png" },
    { name: "ic_adaptive_background", source: "store/icons/ic_adaptive_background.png" },
  ] } };
  const r = verify(id, { gamesDir: dir, manifest });
  expect(r.issues.some((s) => /adaptive foreground and background are identical/i.test(s))).toBe(true);
  rmSync(dir, { recursive: true, force: true });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/package.test.mjs -t "byte-identical adaptive"`
Expected: FAIL — no such issue is produced.

- [ ] **Step 3: Implement the guard**

In `tools/package.mjs`, inside `verify()`, immediately AFTER the `for (const want of iconSizeTable())` loop (after line ~456, before the atlas block), add:

```js
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/package.test.mjs -t "byte-identical adaptive"`
Expected: PASS. Then run the whole file: `npx vitest run tools/package.test.mjs` — all green.

- [ ] **Step 5: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): verify guards adaptive fg != bg (catches the duplicate-master bug)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: icon_compose.gd + generateIcons rework

**Files:**
- Create: `tools/godot/icon_compose.gd`
- Delete: `tools/godot/icon_resize.gd`
- Modify: `tools/package.mjs` (`generateIcons` + the `icons` CLI case)

No vitest (Godot-spawning, like the existing `generateIcons`); validated by a real-Godot smoke here + the dogfood (Task 10).

- [ ] **Step 1: Create `tools/godot/icon_compose.gd`**

```gdscript
extends SceneTree

# Compose Android icon layers from a transparent focal PNG + a 2-stop vertical
# gradient background. Run (headless):
#   godot --headless --path tools/godot/ --script res://icon_compose.gd -- \
#       <focal.png> <outdir> <name:px:kind,...> <#topRRGGBB> <#botRRGGBB>
# kind ∈ { adaptive_fg | adaptive_bg | launcher | play }.
const FG_SAFE := 0.66      # adaptive foreground: subject within Android's safe zone
const COMPOSITE_SAFE := 0.80  # legacy/Play: focal can fill more (not masked)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("icon_compose: usage -- <focal.png> <outdir> <name:px:kind,...> <#top> <#bot>")
		quit(1); return
	var focal_path := args[0]
	var outdir := args[1]
	var specs := args[2].split(",", false)
	var top := Color.html(args[3])
	var bot := Color.html(args[4])

	var focal := Image.load_from_file(focal_path)
	if focal == null:
		push_error("icon_compose: failed to load focal %s" % focal_path)
		quit(1); return
	if focal.get_format() != Image.FORMAT_RGBA8:
		focal.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(outdir)

	for spec in specs:
		var parts := spec.split(":")
		if parts.size() != 3:
			push_error("icon_compose: bad spec '%s' (name:px:kind)" % spec)
			quit(1); return
		var icon_name := parts[0]
		var px := int(parts[1])
		var kind := parts[2]
		var canvas: Image
		if kind == "adaptive_bg":
			canvas = _gradient(px, top, bot)
		elif kind == "adaptive_fg":
			canvas = Image.create(px, px, false, Image.FORMAT_RGBA8) # transparent
			_blend_focal(canvas, focal, px, FG_SAFE)
		elif kind == "launcher" or kind == "play":
			canvas = _gradient(px, top, bot)
			_blend_focal(canvas, focal, px, COMPOSITE_SAFE)
		else:
			push_error("icon_compose: unknown kind '%s'" % kind)
			quit(1); return
		var dest := outdir.path_join(icon_name + ".png")
		var serr := canvas.save_png(dest)
		if serr != OK:
			push_error("icon_compose: save failed %s (err %d)" % [dest, serr])
			quit(1); return
		print("icon_compose: wrote %s (%dx%d, %s)" % [dest, px, px, kind])

	print("ICON_COMPOSE OK")
	quit(0)

func _gradient(px: int, top: Color, bot: Color) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in range(px):
		var t := float(y) / float(max(1, px - 1))
		var col := top.lerp(bot, t)
		for x in range(px):
			img.set_pixel(x, y, col)
	return img

# Contain-fit the focal into `ratio` of the canvas, centered, alpha-composited.
func _blend_focal(canvas: Image, focal: Image, px: int, ratio: float) -> void:
	var box := int(px * ratio)
	var fw := focal.get_width()
	var fh := focal.get_height()
	var scale := float(box) / float(max(fw, fh))
	var tw: int = max(1, int(round(fw * scale)))
	var th: int = max(1, int(round(fh * scale)))
	var scaled := focal.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	var ox := int((px - tw) / 2.0)
	var oy := int((px - th) / 2.0)
	canvas.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
```

- [ ] **Step 2: Rework `generateIcons` in `tools/package.mjs`**

Replace the existing `generateIcons` (currently ~lines 281-292) with:

```js
// Compose the Android icon set from a transparent focal (store_pass.icon_master)
// over a themed 2-stop gradient: distinct adaptive fg/bg + composited legacy/Play.
export function generateIcons(id, { gamesDir = GAMES_DIR, bg } = {}) {
  const m = readManifest(id);
  const focal = m?.store_pass?.icon_master;
  if (!focal) throw new Error(`package: generateIcons needs store_pass.icon_master (a transparent focal PNG) in manifests/${id}.json`);
  const focalAbs = join(gamesDir, id, focal);
  if (!existsSync(focalAbs)) throw new Error(`package: icon focal not found at ${focalAbs}`);
  const { top, bottom } = resolveIconBg({ bgArg: bg, manifest: m });
  const outdir = join(gamesDir, id, "store", "icons");
  const specs = iconSizeTable().map((e) => `${e.name}:${e.px}:${e.kind}`).join(",");
  const out = runGodot(["--headless", "--path", GODOT_DIR, "--script", "res://icon_compose.gd", "--", focalAbs, outdir, specs, top, bottom], "icon_compose");
  if (!out.includes("ICON_COMPOSE OK")) throw new Error(`package: icon_compose did not report OK:\n${out}`);
  return { outdir, bg: { top, bottom }, icons: iconSizeTable().map((e) => ({ ...e, source: `store/icons/${e.name}.png` })) };
}
```

- [ ] **Step 3: Rewire the `icons` CLI case**

In `cli()` (~line 526), replace:

```js
    case "icons": console.log(JSON.stringify(generateIcons(id), null, 2)); return;
```

with:

```js
    case "icons": {
      const bi = rest.indexOf("--bg");
      const bg = bi >= 0 ? rest[bi + 1] : undefined;
      console.log(JSON.stringify(generateIcons(id, { bg }), null, 2));
      return;
    }
```

- [ ] **Step 4: Delete the superseded script**

```bash
git rm tools/godot/icon_resize.gd
```
Confirm nothing else references it: `grep -rn "icon_resize" tools/` → only matches in deleted file / none.

- [ ] **Step 5: Real-Godot smoke (not vitest)**

Make a throwaway transparent focal + a throwaway game dir and run the tool. Run:

```bash
export GODOT_BIN="C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
# square 256² transparent focal with an opaque centered disc, via PIL
python - <<'PY'
from PIL import Image, ImageDraw
img = Image.new("RGBA", (256,256), (0,0,0,0))
d = ImageDraw.Draw(img); d.ellipse((48,48,208,208), fill=(255,123,84,255))
import os; os.makedirs("games/_smoke/store", exist_ok=True)
img.save("games/_smoke/store/focal.png")
PY
node -e "const fs=require('fs');fs.writeFileSync('manifests/_smoke.json',JSON.stringify({id:'_smoke',name:'Smoke',status:'scored',store_pass:{icon_master:'store/focal.png'},asset_pass:{visual_system:{palette:['#2fa6a0 a','#ff7b54 b']}}},null,2))"
node tools/package.mjs icons _smoke
```
Expected: JSON with 8 icons; `ICON_COMPOSE OK` in the spawn. Verify the layers:
```bash
node -e "const {pngSize}=require('./tools/package.mjs');const fs=require('fs');for(const n of ['ic_adaptive_foreground','ic_adaptive_background','ic_play_store']){const b=fs.readFileSync('games/_smoke/store/icons/'+n+'.png');console.log(n,pngSize(b))}"
node -e "const fs=require('fs');const a=fs.readFileSync('games/_smoke/store/icons/ic_adaptive_foreground.png');const b=fs.readFileSync('games/_smoke/store/icons/ic_adaptive_background.png');console.log('fg!==bg:',!a.equals(b))"
```
Expected: fg/bg/play at 432/432/512; `fg!==bg: true`. Open `ic_play_store.png` with the Read tool to eyeball: disc centered on a teal→coral gradient, opaque corners. `ic_adaptive_foreground.png`: disc on transparent.

Clean up: `rm -rf games/_smoke manifests/_smoke.json`.

- [ ] **Step 6: Commit**

```bash
git add tools/package.mjs tools/godot/icon_compose.gd
git rm tools/godot/icon_resize.gd
git commit -m "feat(package): icon_compose — transparent focal -> correct adaptive layers

Replaces the square-stretch icon_resize. adaptive_fg = focal in the 66%
safe zone (transparent), adaptive_bg = palette gradient, legacy/Play =
focal alpha-composited over the gradient. Fixes fg==bg duplication.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: screenshot --script runner + harness template

**Files:**
- Create: `tools/godot/shots.template.gd`
- Modify: `tools/package.mjs` (`captureScreenshotScript` + the `screenshot` CLI case)

- [ ] **Step 1: Create `tools/godot/shots.template.gd`**

```gdscript
extends SceneTree

# TEMPLATE — copy to games/<id>/_shots.gd and fill the moments. Captures store-
# listing frames on the REAL renderer (NOT --headless). package.mjs passes the
# screenshots outdir as the first user arg.
#   godot --path games/<id>/ --script res://_shots.gd -- <outdir>
const PHASE := preload("res://ShopState.gd")  # EDIT: the game's state script, if any

func _initialize() -> void:
	var outdir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "store/screenshots"
	# Persistence games: clear the save so we boot a fresh run, not an inherited day.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))

	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(180)

	# 1) the boot moment
	await _shot("%s/one.png" % outdir)

	# 2..N) drive the view's state to each showcase moment, like selftest, then rebuild.
	#   var s = main.S
	#   s.phase = PHASE.Phase.SELL
	#   s.shelves = [...] ; s.patrons = [...]
	#   main._rebuild_ui()
	#   await _wait(90)
	#   await _shot("%s/two.png" % outdir)

	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	print("SHOTS OK")
	quit(0)

func _wait(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _shot(path: String) -> void:
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("shots: save failed %s (err %d)" % [path, err]); quit(1); return
	print("wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
```

- [ ] **Step 2: Add `captureScreenshotScript` to `tools/package.mjs`**

Add after `captureScreenshot` (~line 330):

```js
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
```

- [ ] **Step 3: Rewire the `screenshot` CLI case**

Replace (~line 528):

```js
    case "screenshot": console.log(JSON.stringify(captureScreenshot(id, rest[1] || "screen-1", { frames: Number(rest[2] || 220) }), null, 2)); return;
```

with:

```js
    case "screenshot": {
      const a = parseScreenshotArgs(rest.slice(1));
      const r = a.mode === "script"
        ? captureScreenshotScript(id, { script: a.script })
        : captureScreenshot(id, a.name, { frames: a.frames });
      console.log(JSON.stringify(r, null, 2));
      return;
    }
```

- [ ] **Step 4: Verify the whole test file still passes**

Run: `npx vitest run tools/package.test.mjs`
Expected: PASS (no new vitest here — the runner is Godot-spawning, validated in the dogfood).

- [ ] **Step 5: Commit**

```bash
git add tools/package.mjs tools/godot/shots.template.gd
git commit -m "feat(package): screenshot --script runner + shots harness template

Codifies the drive-the-view-state capture pattern as a game-committed
_shots.gd the packager runs on the real renderer.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 7: splash composites the transparent focal

**Files:**
- Modify: `tools/godot/splash_render.gd`

The focal is now transparent, so `blit_rect` (overwrite) would punch a transparent hole. Switch to `blend_rect` (alpha-composite).

- [ ] **Step 1: Fix the compositing op**

In `tools/godot/splash_render.gd`, change line ~44 from:

```gdscript
	canvas.blit_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
```

to:

```gdscript
	canvas.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
```

- [ ] **Step 2: Real-Godot smoke**

Reuse the Task 5 smoke focal pattern:

```bash
export GODOT_BIN="C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
python - <<'PY'
from PIL import Image, ImageDraw
img = Image.new("RGBA",(256,256),(0,0,0,0)); d=ImageDraw.Draw(img)
d.ellipse((48,48,208,208), fill=(255,123,84,255))
import os; os.makedirs("games/_smoke/store", exist_ok=True); img.save("games/_smoke/store/focal.png")
PY
node -e "const fs=require('fs');fs.writeFileSync('manifests/_smoke.json',JSON.stringify({id:'_smoke',name:'Smoke',status:'scored',store_pass:{icon_master:'store/focal.png'}},null,2))"
node tools/package.mjs splash _smoke "#2fa6a0ff"
node -e "const {pngSize}=require('./tools/package.mjs');console.log(pngSize(require('fs').readFileSync('games/_smoke/store/splash.png')))"
```
Expected: `SPLASH_RENDER OK`; splash is 1080×1920. Read `games/_smoke/store/splash.png` — the coral disc sits on a solid teal field with **no transparent hole** around it. Clean up: `rm -rf games/_smoke manifests/_smoke.json`.

- [ ] **Step 3: Commit**

```bash
git add tools/godot/splash_render.gd
git commit -m "fix(package): splash blend_rect (alpha-composite) for the transparent focal

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 8: schema — optional store_pass.icon_bg

**Files:**
- Modify: `schema/manifest.schema.json`

- [ ] **Step 1: Add the property**

In `schema/manifest.schema.json`, under `store_pass.properties` (alongside `icon_master`, `notes`), add:

```json
"icon_bg": { "type": "string" }
```

- [ ] **Step 2: Verify schema still loads + an existing manifest validates**

Run:
```bash
node tools/manifest.mjs validate shopkeep-0001
node -e "require('./tools/manifest.mjs'); const s=require('./schema/manifest.schema.json'); console.log('icon_bg in schema:', !!s.properties.store_pass.properties.icon_bg)"
```
Expected: `shopkeep-0001 OK`; `icon_bg in schema: true`.

- [ ] **Step 3: Run any schema tests + the package tests**

Run: `npx vitest run` (the whole suite) — confirm still green (e.g. 197+/197+).
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add schema/manifest.schema.json
git commit -m "feat(schema): optional store_pass.icon_bg (icon gradient override)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 9: Rewrite packager SKILL.md for v2

**Files:**
- Modify: `.claude/skills/packager/SKILL.md`

- [ ] **Step 1: Update the icon model + Step-0 guidance**

Edit the **Inputs** bullet that says "ComfyUI is **not** needed here": change to note ComfyUI **is** needed for the icon focal (the only GPU step), everything else reuses existing art. Edit **Step 0 → Icon master** bullet to redefine it: the icon master is now a **bespoke transparent focal** generated via `comfy.mjs` + the asset checkpoint with **LayerDiffuse**, using the **icon prompt scaffold** (add it verbatim):

> *single bold focal subject · centered · generous empty margins · simple iconic shape · high contrast · flat clean cartoon · NO text · NO words · NO scene/background · NO multiple objects* — plus the title's own hero subject from `concept.theme`, square (1024²).

State that `icon_compose` builds the adaptive layers from it (transparent fg in the 66% safe zone, palette **code-gradient** bg, composited legacy/Play), and the bg comes from `concept.theme` palette or `--bg "#top,#bottom"` / `store_pass.icon_bg`.

- [ ] **Step 2: Update the Flow command block**

In the **Flow** fenced block, change the `icons` and `screenshot` lines and add a focal-gen line:

```
node tools/comfy.mjs gen <id> icon_focal '<recipe-json>'   # bespoke transparent icon focal (LayerDiffuse, square 1024², icon scaffold)
node tools/package.mjs icons <id> [--bg "#top,#bottom"]    # focal -> adaptive fg/bg + composited legacy/Play (headless Image)
node tools/package.mjs screenshot <id> --script res://_shots.gd   # run the game's capture harness on the REAL renderer
```
Keep `atlas`/`splash`/`budget`/`preset`/`build` lines. Note `screenshot <id> <name> [frames]` still works as the boot-only fallback.

- [ ] **Step 3: Add the screenshot harness pattern + splash note**

Add a subsection under **Hard requirements** documenting the capture-harness pattern (copy `tools/godot/shots.template.gd` → `games/<id>/_shots.gd`, drive the view's state like `selftest` Stage 6 to each moment, `_rebuild_ui()`, capture; clear `user://save.json` at start/end; commit `_shots.gd`). Update the **Boot splash** bullet: the splash now composites the **transparent focal** (no opaque-bg trap); keep "match the master's bg colour" only as the opaque-master fallback.

- [ ] **Step 4: Update the store_pass example**

Change the `icon_master` in the merge example from `"art/<hero>.png"` to `"store/icon_focal.png"`, and add `"icon_bg": "#top,#bottom"` to the example.

- [ ] **Step 5: Self-check for stale references**

`grep -n "icon_resize\|square-stretch\|reuses art that already exists\|not.*needed here" .claude/skills/packager/SKILL.md` — confirm no stale claim survives that contradicts v2.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/packager/SKILL.md
git commit -m "docs(packager): v2 — bespoke icon focal + adaptive layers + shots harness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 10: Dogfood — re-package shopkeep-0001 to the new bar

**Files:**
- Create: `games/shopkeep-0001/_shots.gd` (committed; filled from the template)
- Modify: `games/shopkeep-0001/store/**`, `manifests/shopkeep-0001.json`

GPU/owner task. shopkeep is already `packaged`; this is a legitimate re-package, not a regression.

- [ ] **Step 1: Boot ComfyUI**

Confirm reachable: `node tools/comfy.mjs --check`. If down, launch via the README boot (asset checkpoint `cartoonArcadiaXL_v2` + LayerDiffuse present). If it wedges on first gen, kill the PID + relaunch (known infra gotcha).

- [ ] **Step 2: Generate the icon focal**

Run (recipe mirrors `asset_pass.recipes` shape, LayerDiffuse on, square):

```bash
node tools/comfy.mjs gen shopkeep-0001 icon_focal '{"name":"icon_focal","checkpoint":"cartoonArcadiaXL_v2","prompt":"a single scallop seashell, flat bold cartoon, clean thick outlines, vibrant coral and cream cel shading, one bold centered subject, simple iconic shape, generous empty margins, high contrast, sticker style","negative":"text, words, letters, logo, watermark, multiple objects, scene, background, landscape, pattern, photorealistic, 3d render, trademarked character, brand","seed":4242,"sampler":"euler","steps":28,"cfg":7,"width":1024,"height":1024,"layerdiffuse":true}'
```
Inspect the result PNG (Read tool). Re-roll seed / tweak the subject phrase until it's a single clean centered shell on transparency. Move/record the accepted focal as `store/icon_focal.png` (or generate straight to art/ and reference it). Set `store_pass.icon_master` to its path.

- [ ] **Step 3: Compose icons + splash**

```bash
export GODOT_BIN="C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe"
node tools/manifest.mjs merge shopkeep-0001 "{\"store_pass\":{\"icon_master\":\"store/icon_focal.png\",\"icon_bg\":\"#2fa6a0,#1c7d78\"}}"
node tools/package.mjs icons shopkeep-0001
node tools/package.mjs splash shopkeep-0001 "#2fa6a0ff"
```
Read `ic_play_store.png`, `ic_adaptive_foreground.png`, `splash.png` — confirm app-store-grade (shell on gradient, depth, transparent fg, clean splash).

- [ ] **Step 4: Re-capture screenshots via the harness**

Copy `tools/godot/shots.template.gd` → `games/shopkeep-0001/_shots.gd`; fill the GATHER (boot) / CRAFT / SELL moments (reuse the Stage-6 drive used previously: set `S.phase`, `S.resources`, `S.demand`, `S.shelves`, `S.patrons`, `_rebuild_ui()`). Then:

```bash
node tools/package.mjs screenshot shopkeep-0001 --script res://_shots.gd
```
Expected: `SHOTS OK`; 3 frames at 720×1280. Read each to confirm.

- [ ] **Step 5: Re-record store_pass + atlas/budget/preset/build as needed**

Re-run `atlas`, `budget`, `preset` (preset/atlas unchanged but budget must re-sum). Re-build the APK if you want a fresh artifact (`ANDROID_HOME=…/Android/Sdk node tools/package.mjs build shopkeep-0001`). Merge the full `store_pass` (icons, splash, screenshots `{name,px,source}`, atlas, size_budget, export_preset, icon_master, icon_bg, build_artifact, notes) and `node tools/manifest.mjs validate shopkeep-0001`.

- [ ] **Step 6: Validator Method 5 + owner A/B**

```bash
node tools/package.mjs verify shopkeep-0001        # file_checks_pass true, adaptive fg!=bg
ANDROID_HOME="C:/Users/quint/AppData/Local/Android/Sdk" node tools/package.mjs verify-build shopkeep-0001
"$GODOT_BIN" --headless --path games/shopkeep-0001/ --quit-after 120   # regression: clean
```
Open the icon/splash/screenshots for the owner cross-modal cohesion + icon aesthetic A/B. Status is already `packaged`; on approval it stays `packaged` with the upgraded face (re-run `set-status` only if it had regressed).

- [ ] **Step 7: Clean up + commit**

Delete any throwaway probes. Commit the regenerated face:

```bash
git add games/shopkeep-0001/_shots.gd games/shopkeep-0001/store games/shopkeep-0001/art manifests/shopkeep-0001.json
git commit -m "feat(shopkeep-0001): re-package — bespoke icon focal + adaptive layers (packager v2 dogfood)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Final suite + push**

Run: `npx vitest run` → all green. Then `git push origin main` (owner-gated — confirm first). Update memory.

---

## Self-Review

**Spec coverage:**
- §3.1 bespoke focal + adaptive layers → Tasks 5 (compose), 9 (skill scaffold + GPU posture), 10 (dogfood gen). ✓
- §3.1 source-agnostic / no-squish → Task 5 (`_blend_focal` contain-fits any focal; square gen in Task 10). ✓
- §3.1 fg≠bg correctness → Task 4 (verify guard) + Task 5 (distinct roles). ✓
- §3.1 `--bg` / palette default → Tasks 1 (`resolveIconBg`) + 5 (CLI `--bg`). ✓
- §3.2 screenshot harness + runner → Tasks 3 (arg parse), 6 (runner + template), 9 (skill pattern), 10 (fill + run). ✓
- §3.3 splash from transparent focal → Task 7 (`blend_rect`) + 9 (skill note). ✓
- §3.4 schema `icon_bg` → Task 8. ✓
- §4 tests (pure seams + verify guard) → Tasks 1–4, 8. Godot pixel work via smoke (5,7) + dogfood (10), matching codebase discipline. ✓
- §5 dogfood → Task 10. ✓
- §6 blast radius → only the files listed; no concept/builder/asset/audio/validator skill edits. ✓

**Placeholder scan:** every code/step carries real code or a runnable command. No TBD/TODO. ✓

**Type consistency:** `resolveIconBg` returns `{top,bottom}` — consumed by `generateIcons` and passed to `icon_compose.gd` as `<#top> <#bot>` (✓). `iconCompositionRole` roles `focal|background|composite` mirror `icon_compose.gd`'s `adaptive_fg|adaptive_bg|launcher/play` branches (✓). `parseScreenshotArgs` `{mode,script|name,frames}` consumed by the CLI case (✓). `captureScreenshotScript` returns `{script, shots:[{name,px,source}]}` — matches the schema-shaped screenshots record (✓). `store_pass.icon_master` redefined as the focal everywhere (Tasks 5, 9, 10) (✓).
