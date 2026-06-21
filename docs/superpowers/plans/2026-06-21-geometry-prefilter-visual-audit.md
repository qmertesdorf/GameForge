# Geometry Pre-filter for visual-audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic scene-tree geometry pre-filter to `visual-audit` that flags off-viewport clipping, opaque occlusion, and missing-texture nodes (with bounding boxes) ahead of the VLM lens fan-out.

**Architecture:** Mirror the P0b `text_metrics` split — a thin Godot probe (`tools/godot/scene_geometry.gd`) reads `CanvasItem` geometry from the live scene tree (CPU-side, headless-OK) and a pure-JS scorer (`tools/scene-geom.mjs`) turns the raw node list into hard/advisory findings + bboxes. A CLI exits 2 on hard findings (the `contrast.mjs text-metrics` contract). Skill prose wires it in as a pre-fan-out step that also feeds the composition/collision lens located bboxes.

**Tech Stack:** Node ESM (pure functions, no deps), vitest, GDScript (`SceneTree` probe), Godot 4.6.3 headless.

---

## File Structure

- `tools/scene-geom.mjs` — **create.** Pure scorer (`scoreGeometry` + geometry helpers) + thin Godot runner (`sceneGeometryFile`) + CLI. Sibling to `tools/contrast.mjs`.
- `tools/scene-geom.test.mjs` — **create.** vitest unit tests on the pure scorer + a guarded Godot integration test. Sibling to `tools/contrast.test.mjs`.
- `tools/godot/scene_geometry.gd` — **create.** Thin scene-tree introspection probe. Sibling to `tools/godot/text_metrics.gd`.
- `.claude/skills/visual-audit/SKILL.md` — **modify.** Add step 2c + lenses-table/numbering touch-ups.
- `.claude/skills/visual-audit/references/composition-collision.md` — **modify.** Consume the 2c bboxes.

Notes for the implementer:
- This repo's tools are dependency-free ESM. Run a single test file with `npx vitest run tools/scene-geom.test.mjs`; the full suite with `npx vitest run`.
- Godot integration tests are **guarded** — they `test.skipIf(!hasGodot)` so CI (no Godot) stays green; locally set `GODOT_BIN` (see `godot-binary-location` — Godot 4.6.3 console exe, not on PATH).
- `rect` is `[x, y, w, h]`; `viewport` is `[w, h]`; all ints (px). Colours/alpha are floats 0..1.

---

## Task 1: Pure scorer — off-viewport clipping

**Files:**
- Create: `tools/scene-geom.mjs`
- Test: `tools/scene-geom.test.mjs`

- [ ] **Step 1: Write the failing test**

Create `tools/scene-geom.test.mjs`:

```js
import { test, expect, describe } from "vitest";
import { scoreGeometry } from "./scene-geom.mjs";

const VP = [720, 1280];
// minimal node factory — visible text/interactive node with given rect
const node = (over = {}) => ({
  path: "/root/Main/N", class: "Label", rect: [0, 0, 100, 30],
  paint: 0, z_index: 0, mod_a: 1, fill_a: null, has_texture: false,
  texture_null: false, interactive: false, is_text: true, visible: true,
  ...over,
});

describe("scoreGeometry — off-viewport", () => {
  test("a fully on-screen text node is clean", () => {
    const r = scoreGeometry([node({ rect: [10, 10, 100, 30] })], VP);
    expect(r.ok).toBe(true);
    expect(r.hard).toEqual([]);
    expect(r.checked).toBe(1);
  });

  test("a button clipped past the right edge is a hard finding", () => {
    const r = scoreGeometry([node({ class: "Button", interactive: true, is_text: false, rect: [680, 100, 100, 40] })], VP);
    expect(r.ok).toBe(false);
    expect(r.hard).toHaveLength(1);
    expect(r.hard[0]).toMatchObject({ kind: "offscreen", clippedPx: 60, fully: false });
  });

  test("a node entirely off-screen is flagged fully", () => {
    const r = scoreGeometry([node({ rect: [800, 100, 100, 40] })], VP);
    expect(r.hard[0]).toMatchObject({ kind: "offscreen", fully: true });
  });

  test("clipTol tolerates a 2px bleed but not a 3px one", () => {
    expect(scoreGeometry([node({ rect: [-2, 10, 100, 30] })], VP).ok).toBe(true);
    expect(scoreGeometry([node({ rect: [-3, 10, 100, 30] })], VP).ok).toBe(false);
  });

  test("a clipped NON-victim (decorative) node is not a hard off-viewport finding", () => {
    const r = scoreGeometry([node({ is_text: false, interactive: false, rect: [680, 100, 100, 40] })], VP);
    expect(r.hard).toEqual([]);
  });

  test("invisible nodes are skipped", () => {
    const r = scoreGeometry([node({ rect: [800, 100, 100, 40], visible: false })], VP);
    expect(r.checked).toBe(0);
    expect(r.hard).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: FAIL — `Failed to resolve import "./scene-geom.mjs"` (module not created yet).

- [ ] **Step 3: Write minimal implementation**

Create `tools/scene-geom.mjs`:

```js
// Deterministic scene-tree GEOMETRY pre-filter for the visual-audit gate — the
// testable seam that turns three geometric defect classes into facts ahead of the
// VLM lens fan-out: off-viewport clipping, opaque occlusion, and missing-texture
// nodes. Pure scoring lives here; the thin Godot op (scene_geometry.gd) only reads
// the live tree's geometry — the same pure-JS-seam + thin-Godot split as contrast.mjs.
//
// CLI:
//   node tools/scene-geom.mjs check <game-dir> [--clip-tol N] [--opaque-alpha A]
//
// BOUNDARY: sees only introspectable CanvasItem geometry (Control rects, textured
// Node2D). Art drawn via custom _draw()/draw_texture() is invisible here and stays
// the composition/collision VLM lens's job — a low `checked` count means the game
// draws in code, not that the screen is clean.

// --- geometry helpers (pure) ---------------------------------------------
// rect = [x, y, w, h]; viewport = [w, h].
function offViewport(rect, [vw, vh], tol) {
  const [x, y, w, h] = rect;
  const out = Math.max(-x, -y, x + w - vw, y + h - vh); // worst overshoot on any side
  const clippedPx = Math.max(0, Math.round(out));
  const fully = x >= vw || y >= vh || x + w <= 0 || y + h <= 0;
  return { clippedPx, fully, clipped: clippedPx > tol };
}

export function scoreGeometry(nodes, viewport, { clipTol = 2, opaqueAlpha = 0.9 } = {}) {
  const vis = nodes.filter((n) => n.visible);
  const hard = [];
  const advisory = [];
  let checked = 0;
  for (const n of vis) {
    const victim = !!(n.is_text || n.interactive);
    if (victim) {
      checked++;
      const ov = offViewport(n.rect, viewport, clipTol);
      if (ov.clipped)
        hard.push({ kind: "offscreen", path: n.path, class: n.class, rect: n.rect, clippedPx: ov.clippedPx, fully: ov.fully });
    }
  }
  const ok = hard.length === 0;
  const bboxes = [...hard, ...advisory].map((f) => ({ kind: f.kind, path: f.path ?? f.victim?.path, rect: f.rect ?? f.victim?.rect }));
  return { ok, viewport, checked, hard, advisory, bboxes };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: PASS (6 tests in the off-viewport describe).

- [ ] **Step 5: Commit**

```bash
git add tools/scene-geom.mjs tools/scene-geom.test.mjs
git commit -m "feat(scene-geom): pure off-viewport clipping scorer"
```

---

## Task 2: Pure scorer — opaque occlusion (hard) + partial overlap (advisory)

**Files:**
- Modify: `tools/scene-geom.mjs`
- Test: `tools/scene-geom.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/scene-geom.test.mjs`:

```js
describe("scoreGeometry — occlusion", () => {
  const panel = (over = {}) => node({
    path: "/root/Main/Panel", class: "Panel", is_text: false, interactive: false,
    fill_a: 0.95, rect: [0, 0, 720, 1280], paint: 5, ...over,
  });

  test("a text node fully under an opaque higher-paint panel is hard-occluded", () => {
    const label = node({ path: "/root/Main/Label", rect: [100, 100, 200, 40], paint: 1 });
    const r = scoreGeometry([label, panel()], VP);
    expect(r.ok).toBe(false);
    expect(r.hard[0]).toMatchObject({ kind: "occluded" });
    expect(r.hard[0].victim.path).toBe("/root/Main/Label");
    expect(r.hard[0].occluder.path).toBe("/root/Main/Panel");
  });

  test("a node under a 0.5-alpha scrim is NOT occluded (scrim is not opaque)", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const r = scoreGeometry([label, panel({ fill_a: 0.5 })], VP);
    expect(r.hard).toEqual([]);
  });

  test("opaqueAlpha boundary: 0.92 panel occludes at default, not at a 0.95 threshold", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const nodes = [label, panel({ fill_a: 0.92 })];
    expect(scoreGeometry(nodes, VP).ok).toBe(false);                     // default 0.9
    expect(scoreGeometry(nodes, VP, { opaqueAlpha: 0.95 }).ok).toBe(true);
  });

  test("a LOWER-paint opaque panel does NOT occlude the text above it", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 9 });
    const r = scoreGeometry([label, panel({ paint: 1 })], VP);
    expect(r.hard).toEqual([]);
  });

  test("mod_a knocks a textured occluder below the opaque bar", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const sprite = node({ path: "/root/Main/Cover", class: "Sprite2D", is_text: false, has_texture: true, mod_a: 0.4, rect: [0, 0, 720, 1280], paint: 5 });
    expect(scoreGeometry([label, sprite], VP).hard).toEqual([]);
  });

  test("partial overlap (not full containment) is advisory, not hard", () => {
    const label = node({ rect: [100, 100, 400, 40], paint: 1 });
    const half = panel({ rect: [300, 0, 720, 1280], paint: 5 }); // covers right half only
    const r = scoreGeometry([label, half], VP);
    expect(r.hard).toEqual([]);
    expect(r.advisory.some((a) => a.kind === "overlap")).toBe(true);
  });

  test("z_index outranks paint order", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 9, z_index: 0 });
    const r = scoreGeometry([label, panel({ paint: 1, z_index: 1 })], VP);
    expect(r.hard[0]).toMatchObject({ kind: "occluded" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: FAIL — occlusion findings not produced (no `occluded`/`overlap` logic yet).

- [ ] **Step 3: Write minimal implementation**

In `tools/scene-geom.mjs`, add helpers after `offViewport`:

```js
// effective opacity of a node as an occluder, vs the opaqueAlpha bar.
function isOpaque(n, opaqueAlpha) {
  const base = n.fill_a != null ? n.fill_a : (n.has_texture ? 1 : 0);
  return base * (n.mod_a ?? 1) >= opaqueAlpha;
}
// paint-above: higher z_index wins; ties broken by walk order (paint).
function isAbove(a, b) {
  const za = a.z_index ?? 0, zb = b.z_index ?? 0;
  if (za !== zb) return za > zb;
  return (a.paint ?? 0) > (b.paint ?? 0);
}
// rect a fully contains rect b (within tol on every side).
function contains(a, b, tol) {
  return b[0] >= a[0] - tol && b[1] >= a[1] - tol &&
         b[0] + b[2] <= a[0] + a[2] + tol && b[1] + b[3] <= a[1] + a[3] + tol;
}
// area of intersection of two rects (0 if disjoint).
function overlapArea(a, b) {
  const x = Math.max(a[0], b[0]), y = Math.max(a[1], b[1]);
  const r = Math.min(a[0] + a[2], b[0] + b[2]), btm = Math.min(a[1] + a[3], b[1] + b[3]);
  const w = r - x, h = btm - y;
  return w > 0 && h > 0 ? w * h : 0;
}
```

Then, inside `scoreGeometry`, replace the body of the loop region + the closing with occlusion handling. The full updated function:

```js
export function scoreGeometry(nodes, viewport, { clipTol = 2, opaqueAlpha = 0.9 } = {}) {
  const vis = nodes.filter((n) => n.visible);
  const occluders = vis.filter((n) => isOpaque(n, opaqueAlpha));
  const hard = [];
  const advisory = [];
  let checked = 0;
  for (const n of vis) {
    const victim = !!(n.is_text || n.interactive);
    if (victim) {
      checked++;
      const ov = offViewport(n.rect, viewport, clipTol);
      if (ov.clipped)
        hard.push({ kind: "offscreen", path: n.path, class: n.class, rect: n.rect, clippedPx: ov.clippedPx, fully: ov.fully });
    }
    // occlusion: is some opaque higher node sitting over this one?
    let fullyOccluded = false;
    for (const c of occluders) {
      if (c === n || !isAbove(c, n)) continue;
      if (contains(c.rect, n.rect, clipTol)) {
        if (victim) {
          hard.push({ kind: "occluded", victim: { path: n.path, class: n.class, rect: n.rect }, occluder: { path: c.path, class: c.class } });
          fullyOccluded = true;
        }
        break;
      }
    }
    if (!fullyOccluded) {
      const over = occluders.find((c) => c !== n && isAbove(c, n) && overlapArea(c.rect, n.rect) > 0);
      if (over)
        advisory.push({ kind: "overlap", path: n.path, class: n.class, rect: n.rect, over: over.path });
    }
  }
  const ok = hard.length === 0;
  const bboxes = [...hard, ...advisory].map((f) => ({ kind: f.kind, path: f.path ?? f.victim?.path, rect: f.rect ?? f.victim?.rect }));
  return { ok, viewport, checked, hard, advisory, bboxes };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: PASS (off-viewport + occlusion describes). The earlier off-viewport tests must still pass — note the clean-screen test's single node is its own only node, so no spurious overlap.

- [ ] **Step 5: Commit**

```bash
git add tools/scene-geom.mjs tools/scene-geom.test.mjs
git commit -m "feat(scene-geom): opaque occlusion (hard) + partial overlap (advisory)"
```

---

## Task 3: Pure scorer — missing-texture (advisory)

**Files:**
- Modify: `tools/scene-geom.mjs`
- Test: `tools/scene-geom.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/scene-geom.test.mjs`:

```js
describe("scoreGeometry — missing-texture", () => {
  test("a visible texture-requiring node with no texture is advisory", () => {
    const r = scoreGeometry([node({ path: "/root/Main/Icon", class: "TextureRect", is_text: false, texture_null: true, rect: [10, 10, 44, 44] })], VP);
    expect(r.hard).toEqual([]);
    expect(r.advisory).toHaveLength(1);
    expect(r.advisory[0]).toMatchObject({ kind: "missing-texture", path: "/root/Main/Icon" });
  });

  test("missing-texture findings appear in bboxes for lens hand-off", () => {
    const r = scoreGeometry([node({ class: "Sprite2D", is_text: false, texture_null: true, rect: [10, 10, 44, 44] })], VP);
    expect(r.bboxes.some((b) => b.kind === "missing-texture" && b.rect[2] === 44)).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: FAIL — no `missing-texture` advisory produced yet.

- [ ] **Step 3: Write minimal implementation**

In `scoreGeometry`, inside the `for (const n of vis)` loop, add after the occlusion/overlap block (still inside the loop):

```js
    if (n.texture_null)
      advisory.push({ kind: "missing-texture", path: n.path, class: n.class, rect: n.rect });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: PASS (all three describes green).

- [ ] **Step 5: Commit**

```bash
git add tools/scene-geom.mjs tools/scene-geom.test.mjs
git commit -m "feat(scene-geom): missing-texture advisory finding"
```

---

## Task 4: Godot probe + runner + CLI

**Files:**
- Create: `tools/godot/scene_geometry.gd`
- Modify: `tools/scene-geom.mjs` (add `sceneGeometryFile` + `main`)
- Test: `tools/scene-geom.test.mjs` (guarded Godot integration test)

- [ ] **Step 1: Write the probe**

Create `tools/godot/scene_geometry.gd`:

```gdscript
extends SceneTree

# Deterministic GEOMETRY probe for the visual-audit geometry pre-filter. Instantiates
# Main.tscn, lets the layout settle, then walks the tree for CanvasItem nodes and emits
# each visible node's on-screen rect + paint order + raw opacity signals + texture state.
# The JS side (scene-geom.mjs scoreGeometry) decides off-viewport / occlusion /
# missing-texture. Purely a READER — no scoring here (threshold stays a JS knob).
#
# Headless is fine — we read layout metrics (CPU-side), not pixels.
#   godot --headless --path games/<id>/ --script res://scene_geometry.gd
#
# LIMITATION: only introspectable CanvasItem geometry (Control rects, textured Node2D).
# Art drawn via a custom _draw()/draw_texture() is NOT visible here.

const TEX_CLASSES := ["Sprite2D", "TextureRect", "TextureButton", "NinePatchRect", "AnimatedSprite2D"]
const TEXT_CLASSES := ["Label", "RichTextLabel", "Button", "LineEdit", "TextEdit", "CheckBox", "CheckButton", "OptionButton"]
const INTERACTIVE_CLASSES := ["Button", "TextureButton", "LineEdit", "TextEdit", "CheckBox", "CheckButton", "OptionButton", "HSlider", "VSlider"]

var _paint := 0

func _initialize() -> void:
	var packed := load("res://Main.tscn")
	if packed == null:
		push_error("scene_geometry: could not load res://Main.tscn")
		quit(1)
		return
	get_root().add_child(packed.instantiate())
	await _emit()

func _emit() -> void:
	for _i in range(10):       # let anchors/containers resolve sizes
		await process_frame
	var nodes: Array = []
	_walk(get_root(), nodes)
	var vp: Vector2 = get_root().get_visible_rect().size
	print("SCENE_GEOMETRY ", JSON.stringify({"viewport": [int(vp.x), int(vp.y)], "nodes": nodes}))
	quit(0)

func _walk(node: Node, out: Array) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		var rect := _rect_of(ci)
		if rect != null:
			var cls := ci.get_class()
			var has_tex := _has_texture(ci)
			out.append({
				"path": String(ci.get_path()),
				"class": cls,
				"rect": rect,
				"paint": _paint,
				"z_index": ci.z_index if ci is Node2D else 0,
				"mod_a": ci.modulate.a * ci.self_modulate.a,
				"fill_a": _fill_alpha(ci),
				"has_texture": has_tex,
				"texture_null": (cls in TEX_CLASSES) and not has_tex,
				"interactive": cls in INTERACTIVE_CLASSES,
				"is_text": _is_text(ci),
				"visible": ci.is_visible_in_tree(),
			})
		_paint += 1
	for child in node.get_children():
		_walk(child, out)

# On-screen rect [x,y,w,h] as ints, or null if the node has no measurable extent.
func _rect_of(ci: CanvasItem):
	if ci is Control:
		var r: Rect2 = (ci as Control).get_global_rect()
		return [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
	if ci is Sprite2D and (ci as Sprite2D).texture != null:
		var s := ci as Sprite2D
		var sz: Vector2 = s.texture.get_size() * s.global_scale
		var pos: Vector2 = s.global_position
		if s.centered:
			pos -= sz * 0.5
		pos += s.offset
		return [int(pos.x), int(pos.y), int(sz.x), int(sz.y)]
	return null

func _has_texture(ci: CanvasItem) -> bool:
	if ci.has_method("get_texture"):
		return ci.get("texture") != null
	return false

# bg_color.a of a StyleBoxFlat panel/normal stylebox, or null when none.
func _fill_alpha(ci: CanvasItem):
	if not (ci is Control):
		return null
	var c := ci as Control
	for sb_name in ["panel", "normal"]:
		if c.has_theme_stylebox(sb_name):
			var sb := c.get_theme_stylebox(sb_name)
			if sb is StyleBoxFlat:
				return (sb as StyleBoxFlat).bg_color.a
	return null

func _is_text(ci: CanvasItem) -> bool:
	if not (ci.get_class() in TEXT_CLASSES):
		return false
	var t = ci.get("text")
	return t != null and String(t).strip_edges() != ""
```

- [ ] **Step 2: Add the runner + CLI to `tools/scene-geom.mjs`**

At the top of `tools/scene-geom.mjs`, add imports (below the header comment, above the helpers):

```js
import { execFileSync } from "node:child_process";
import { copyFileSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GODOT_DIR = join(__dirname, "godot");
```

At the bottom of `tools/scene-geom.mjs`, add the runner, CLI, and entrypoint:

```js
// --- thin Godot runner ---------------------------------------------------
function godotBin() {
  return process.env.GODOT_BIN || "godot";
}
function runGodot(args, label) {
  try {
    return execFileSync(godotBin(), args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    throw new Error(`scene-geom: Godot ${label} failed: ${e.message}\n${e.stdout || ""}${e.stderr || ""}`);
  }
}

// Probe the game's scene-tree geometry (scene_geometry.gd copied into the game dir,
// screenshot.gd-style, then cleaned up) and score it. Returns the scoreGeometry result.
export function sceneGeometryFile(gameDir, { clipTol = 2, opaqueAlpha = 0.9 } = {}) {
  const dir = resolve(gameDir);
  const tmp = join(dir, "_scene_geometry.gd");
  copyFileSync(join(GODOT_DIR, "scene_geometry.gd"), tmp);
  try {
    const out = runGodot(["--headless", "--path", dir, "--script", "res://_scene_geometry.gd"], "scene_geometry");
    const m = out.match(/SCENE_GEOMETRY (\{.*\})/);
    if (!m) throw new Error(`scene-geom: scene_geometry emitted no data:\n${out}`);
    const { viewport, nodes } = JSON.parse(m[1]);
    return scoreGeometry(nodes, viewport, { clipTol, opaqueAlpha });
  } finally {
    rmSync(tmp, { force: true });
    rmSync(`${tmp}.uid`, { force: true });
  }
}

function main(argv) {
  const args = argv.slice(2);
  const pos = args.filter((a) => !a.startsWith("--"));
  const flag = (name, def) => { const i = args.indexOf(name); return i >= 0 ? Number(args[i + 1]) : def; };
  if (pos[0] === "check" && pos[1]) {
    const res = sceneGeometryFile(pos[1], { clipTol: flag("--clip-tol", 2), opaqueAlpha: flag("--opaque-alpha", 0.9) });
    console.log(JSON.stringify(res, null, 2));
    process.exit(res.ok ? 0 : 2);
  } else {
    console.error("usage: scene-geom.mjs check <game-dir> [--clip-tol N] [--opaque-alpha A]");
    process.exit(2);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main(process.argv);
```

- [ ] **Step 3: Write the guarded integration test**

Append to `tools/scene-geom.test.mjs`. First extend the import line at the top of the file:

```js
import { scoreGeometry, sceneGeometryFile } from "./scene-geom.mjs";
import { execFileSync } from "node:child_process";

function godotAvailable() {
  try {
    execFileSync(process.env.GODOT_BIN || "godot", ["--version"], { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch { return false; }
}
const hasGodot = godotAvailable();
```

Then add the describe:

```js
describe("sceneGeometryFile (Godot integration, guarded)", () => {
  test.skipIf(!hasGodot)("diver-0001 chrome is geometrically clean", () => {
    const r = sceneGeometryFile("games/diver-0001");
    expect(r.checked).toBeGreaterThan(0);   // it has Control chrome to see
    expect(r.hard).toEqual([]);             // clip/occlusion bugs were already fixed
  });
});
```

- [ ] **Step 4: Run the tests**

Run: `npx vitest run tools/scene-geom.test.mjs`
Expected: PASS. The integration test runs locally (with `GODOT_BIN` set) and is SKIPPED on CI. If it FAILS on `hard`, that is a real dogfood finding — capture it (do not weaken the gate); see Task 6.

- [ ] **Step 5: Commit**

```bash
git add tools/scene-geom.mjs tools/scene-geom.test.mjs tools/godot/scene_geometry.gd
git commit -m "feat(scene-geom): Godot geometry probe + runner + CLI"
```

---

## Task 5: Wire the pre-filter into the visual-audit skill prose

**Files:**
- Modify: `.claude/skills/visual-audit/SKILL.md`
- Modify: `.claude/skills/visual-audit/references/composition-collision.md`

- [ ] **Step 1: Add step 2c to `SKILL.md`**

In `.claude/skills/visual-audit/SKILL.md`, immediately AFTER the `**2b. Deterministic text metrics ...**` paragraph (it ends with "...not that it has no text."), insert this new paragraph:

```markdown
**2c. Deterministic geometry pre-filter (off-viewport / occlusion / missing-texture).** Run `node tools/scene-geom.mjs check games/<id> [--clip-tol N] [--opaque-alpha A]`. It instantiates the scene and reads each visible `CanvasItem`'s on-screen rect, paint order, opacity, and texture state from the live tree, then deterministically flags two **hard** classes — **off-viewport clipping** of an interactive/text node, and **full occlusion** of an interactive/text node by an opaque higher-paint node (rendered, but the player can't see/tap it) — plus **partial overlap** and **missing-texture** nodes as advisory. It **exits 2** on any hard finding. Two uses, exactly like 2b: (1) hard findings go straight into the report as blockers — a clipped or fully-covered button is a deterministic FAIL, not a VLM judgment call; (2) the emitted **bboxes are deterministically-located candidate regions** — feed them to the composition/collision lens (step 4) instead of eyeballing. **Coverage boundary (state it in the report):** this sees only introspectable `CanvasItem` geometry (`Control` rects, textured `Node2D`). Art drawn via a custom `_draw()`/`draw_texture()` is invisible here and still needs the composition/collision VLM lens — a low `checked` count means the game draws its visuals in code, not that the screen is clean. (Paint order is `z_index` then tree order; `CanvasLayer`/`top_level` edge cases are not modelled.)
```

- [ ] **Step 2: Point the composition/collision lens at the bboxes**

In `.claude/skills/visual-audit/SKILL.md`, find the fan-out bullet:

```markdown
- `references/composition-collision.md`
```

Replace it with:

```markdown
- `references/composition-collision.md` *(consumes the step-2c geometry bboxes as pre-located collision/clipping candidates)*
```

- [ ] **Step 3: Add a consumption note to the composition-collision reference**

In `.claude/skills/visual-audit/references/composition-collision.md`, add this note near the top (after the first heading/intro paragraph — read the file first to place it naturally):

```markdown
**Start from the deterministic candidates.** The step-2c geometry pre-filter (`tools/scene-geom.mjs`) has already located, with exact bounding boxes, any off-viewport-clipped or opaquely-occluded interactive/text node and any partial-overlap region. Treat those bboxes as confirmed starting points — verify and describe each, then go looking for the collisions it CANNOT see: anything drawn via custom `_draw()`/`draw_texture()` (most game-world art here), which is invisible to the geometry probe. A clean pre-filter is not a clean screen.
```

- [ ] **Step 4: Update the lenses table note (optional consistency touch)**

In the `## The lenses` table row for "Composition & collision", leave the row as-is (the consumption is documented in step 2c + the fan-out bullet). No change needed — verify the table still reads correctly.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/visual-audit/SKILL.md .claude/skills/visual-audit/references/composition-collision.md
git commit -m "docs(visual-audit): wire in the step-2c geometry pre-filter"
```

---

## Task 6: Dogfood diver-0001 + full-suite verification

**Files:**
- No source changes expected (verification + evidence task). Possibly: capture a forced-fail demo.

- [ ] **Step 1: Run the gate on the real dogfood title**

Run (locally, `GODOT_BIN` set): `node tools/scene-geom.mjs check games/diver-0001`
Expected: exit 0; JSON shows `checked > 0` (diver's Control chrome — the shop panel/buttons/labels) and `hard: []`. This is the honest "the prior visual-audit fixes hold" outcome.

If `hard` is non-empty: that is a REAL defect the prior pass missed. Do NOT relax `--opaque-alpha`/`--clip-tol` to make it pass. Instead read the cited node, confirm the clip/occlusion in a rendered frame, and fix the chrome (or record it for the owner). Re-run until clean for the right reason.

- [ ] **Step 2: Demonstrate the gate bites (forced-fail evidence)**

Run: `node tools/scene-geom.mjs check games/diver-0001 --opaque-alpha 0.0`
Expected: this drops the opacity bar to zero, so any text/interactive node sitting under any higher node now reports `occluded` → exit 2. This proves the gate fires end-to-end on a real scene (mirrors how P0b demonstrated `text-metrics --min 40`). Capture the output line count in the dogfood notes. (The synthetic unit tests in Tasks 1–3 are the primary gate-bites proof; this is the live-scene confirmation.)

- [ ] **Step 3: Run the full test suite**

Run: `npx vitest run`
Expected: all prior suites still green PLUS the new `tools/scene-geom.test.mjs` (the guarded integration test runs locally, skips on CI). Record the passed count.

- [ ] **Step 4: Confirm no game-logic regression on diver**

The pre-filter touches no game code, but confirm diver's own gates are unaffected (sanity): run its `selftest.gd`/`uitest.gd`/`playtest.gd` per the project's usual headless invocation (see `validator`/`playtest-audit` skills for the exact commands and the `GODOT_BIN` path in `godot-binary-location`).
Expected: `SELFTEST OK` / `UITEST OK` / `PLAYTEST METRICS {...}` unchanged.

- [ ] **Step 5: Commit any evidence + finalize**

```bash
git add -A
git commit -m "test(scene-geom): dogfood diver-0001 geometry pre-filter (clean) + forced-fail demo"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- Off-viewport clipping (hard) → Task 1. ✓
- Opaque occlusion (hard) + partial overlap (advisory) → Task 2. ✓
- Missing-texture (advisory) → Task 3. ✓
- `opaqueAlpha` (JS-side, calibrated 0.9) → computed in Task 2 `isOpaque`, knob tested. ✓
- `paint`/`z_index` ordering (documented approximation) → Task 2 `isAbove` + tests + skill note. ✓
- Thin Godot probe + runner (`textMetricsFile` pattern) + CLI exit 2 → Task 4. ✓
- bboxes for lens hand-off → built in Task 1, asserted in Task 3, consumed in Task 5. ✓
- Skill step 2c + composition-collision consumption + boundary prose → Task 5. ✓
- diver dogfood (expect clean) + calibration finding + gate-bites demo → Task 6. ✓
- Records nothing to manifest → no manifest task exists (correct). ✓

**Placeholder scan:** none — every code step shows complete code; every run step shows the command + expected output.

**Type consistency:** `scoreGeometry(nodes, viewport, {clipTol, opaqueAlpha})` and its return shape `{ok, viewport, checked, hard, advisory, bboxes}` are identical across Tasks 1–4. Helpers `offViewport`/`isOpaque`/`isAbove`/`contains`/`overlapArea` are defined once (Tasks 1–2) and reused. `sceneGeometryFile(gameDir, {clipTol, opaqueAlpha})` matches the CLI flag plumbing. Node field names (`mod_a`, `fill_a`, `has_texture`, `texture_null`, `interactive`, `is_text`, `paint`, `z_index`, `rect`, `visible`) are identical between the probe (Task 4) and the test factory/scorer (Tasks 1–3).
