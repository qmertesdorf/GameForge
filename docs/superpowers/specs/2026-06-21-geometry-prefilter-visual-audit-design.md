# P1-b — Deterministic geometry pre-filter for `visual-audit`

**Date:** 2026-06-21
**Status:** design approved, pre-implementation
**Roadmap:** P1 queue item #5 (`research-backed-roadmap`) — "Add a deterministic CV defect
pre-filter (overlap/occlusion/clipping/missing-asset) ahead of VLM lenses." Follows P1-a
(balance tuning) and the three P0s (generate-and-verify, asset QC, visual-audit CoT + text metrics).

## Problem

`visual-audit` grades the composited, running screen by fanning out fresh VLM auditor subagents,
one per lens. Three defect classes are **geometric facts**, not judgment calls, yet today they are
left entirely to the VLM lenses (which sometimes rationalise them away):

- **Off-viewport clipping** — a visible interactive/text element whose rect exits the viewport
  (the real `diver-0001` "Fins cost clipped off-screen" bug).
- **Opaque overlap / occlusion** — a visible element fully covered by an opaque higher-paint
  element, so it renders but the player can't see it (the `diver-0001` "world bleeding under the
  overlay" / "diver-over-buttons" bug class).
- **Missing / placeholder texture** — a texture-requiring node with no texture assigned.

The research roadmap's unifying principle: **push correctness to deterministic verifiers; keep
heuristics/VLMs in the proposing layer.** A deterministic pre-filter for these three classes makes
the verdict a fact for the cases it can see, and feeds the VLM lenses located bounding boxes for
the rest — exactly as P0b's `text_metrics` does for legibility.

## Approach (chosen): scene-tree geometry introspection

Mirror the P0b `text_metrics.gd` + `contrast.mjs` split: a thin Godot probe reads geometry from the
live scene tree (CPU-side, headless-OK), and a pure-JS scorer turns it into findings.

### Why scene-tree over pixel-CV or hybrid

This catalogue renders ~95% of its **game art via custom `_draw()`** (18 of 19 games;
only `runner-0002` uses `Sprite2D`/`TextureRect` nodes). That is the same blind spot
`text_metrics` documents, only wider. Given that:

| Defect class | Scene-tree | Pixel-CV |
| --- | --- | --- |
| Opaque overlap / occlusion | exact (rect∩ + opacity + paint order) | ~infeasible (can't see behind the top layer) |
| Off-viewport clipping | exact, zero false positives (knows node identity + true extents) | heuristic (can't tell a full-bleed background from a clipped button) |
| Missing / placeholder texture | node-level (`texture==null`) | magenta scan only (and a `draw_texture(null)` usually draws *nothing*, so no marker) |

- **Occlusion is the highest-value class and is reliably detectable ONLY from geometry.**
- Scene-tree gives **zero-false-positive** off-viewport detection (node identity + true extents).
- The blind spot (custom-`_draw()` art) is **already covered** — holistically — by the VLM
  composition/collision lens; the pre-filter *feeds* that lens located bboxes rather than
  duplicating it with a noisier pixel tool.
- A pixel heuristic living inside the "deterministic pre-filter" would pollute the very
  verifier/heuristic boundary that makes the pre-filter trustworthy.

Deferred (YAGNI): a targeted magenta/placeholder pixel scan can bolt on later **if** that bug class
ever actually recurs. It has not — the real `diver` bugs were all chrome geometry + contrast.

## Components

### 1. `tools/godot/scene_geometry.gd` (thin introspection — sibling to `text_metrics.gd`)

`extends SceneTree`. Loads `res://Main.tscn`, settles 10 `process_frame`s (let anchors/containers
resolve), walks the tree for `CanvasItem` nodes. Headless is fine — geometry is CPU-side.

Per **visible** node (`is_visible_in_tree()`), emit:

| Field | Meaning |
| --- | --- |
| `path` | node path (for attribution) |
| `class` | `get_class()` |
| `rect` | global on-screen `[x, y, w, h]`. `Control` → `get_global_rect()`. Textured `Node2D`/`Sprite2D` → derived from `texture.get_size() * global_scale`, offset for `centered`/`offset`. |
| `paint` | walk-order rank (monotonic depth-first counter) — the real front/back order for siblings |
| `z_index` | effective z (combined with `paint` for ordering JS-side) |
| `mod_a` | `modulate.a * self_modulate.a` (float 0..1) — the node's OWN alpha (ancestor `modulate` is NOT walked; a node under a faded parent still reads opaque) |
| `fill_a` | for a `Control` with a `StyleBoxFlat` → `bg_color.a`; else `null` (no introspectable opaque fill) |
| `has_texture` | node has a non-null texture (opacity base for textured Node2D) |
| `texture_null` | true for texture-requiring classes (`Sprite2D`/`TextureRect`/`TextureButton`/`NinePatchRect`) with no texture. `AnimatedSprite2D` is intentionally NOT included — it uses `sprite_frames` (not `texture`) and, as a `Node2D` that is neither `Control` nor `Sprite2D`, `_rect_of()` returns null so it is never emitted anyway. |
| `interactive` | `Button`/`TextureButton`/`LineEdit`/`TextEdit`/… |
| `is_text` | has a non-empty `text` property |

The probe is **purely a reader** — it emits raw opacity signals (`mod_a`, `fill_a`, `has_texture`)
and the JS scorer decides opacity against `opaqueAlpha`, so the threshold stays a unit-testable
knob (the `contrast.mjs` thin-GD / pure-JS split). Prints one line:
`SCENE_GEOMETRY {"viewport":[w,h],"nodes":[...]}`. `quit(0)`.

**Ordering note (documented approximation):** effective paint order is computed JS-side as
`(z_index, paint)`. This ignores `CanvasLayer`/`top_level` nuance — acceptable for the in-tree
chrome these games use; called out in the skill boundary.

### 2. `tools/scene-geom.mjs` (pure scorer + CLI — sibling to `contrast.mjs`)

Pure functions (unit-tested, no GPU/disk/network):

```
scoreGeometry(nodes, viewport, { clipTol = 2, opaqueAlpha = 0.9 }) → {
  ok,            // no hard findings
  viewport,
  checked,       // count of visible nodes considered
  hard:     [ {kind, ...} ],   // off-viewport (text/interactive) | occluded (text/interactive, full)
  advisory: [ {kind, ...} ],   // partial overlap (any node) | missing-texture
  bboxes:   [ {kind, path, rect} ]  // every finding's rect, for VLM-lens hand-off
}
```

Opacity is decided JS-side: `opaque(n) = (fill_a ?? (has_texture ? 1 : 0)) * mod_a ≥ opaqueAlpha`.
Default `opaqueAlpha = 0.9` — calibrated: diver's panels are α=0.92/0.95, visually occluding but
not 1.0, so a 1.0 threshold would miss real occluders; a 0.5 scrim correctly stays non-opaque.

Scoring rules (pure geometry):

- **off-viewport** — a visible **text/interactive** node whose rect exits the viewport by more than
  `clipTol` px on any side → `hard` `{kind:'offscreen', path, class, rect, clippedPx, fully}`
  (`fully` = rect entirely outside the viewport).
- **occlusion** — a visible **text/interactive** victim V fully contained (beyond `clipTol`) by a
  node C where `C.opaque && order(C) > order(V)` (order = sort by `z_index` then `paint`) →
  `hard` `{kind:'occluded', victim, occluder}`. A node (any class) whose visible area is
  *partially* covered (intersection > 0 but not full) by such a C → `advisory`
  `{kind:'overlap', node, over}`.
- **missing-texture** — a visible texture-requiring node with `texture_null` → `advisory`
  `{kind:'missing-texture', path, class, rect}`.

Thin Godot runner (the `textMetricsFile` pattern): `sceneGeometryFile(gameDir, {clipTol, opaqueAlpha})`
copies the probe into the game dir as `_scene_geometry.gd`, runs
`godot --headless --path <dir> --script res://_scene_geometry.gd`, parses the `SCENE_GEOMETRY` line,
calls `scoreGeometry(nodes, viewport, {clipTol, opaqueAlpha})`, and cleans up
`_scene_geometry.gd(.uid)` in a `finally`.

CLI:
```
node tools/scene-geom.mjs check <game-dir> [--clip-tol N] [--opaque-alpha A]
```
Prints the `scoreGeometry` result as JSON. Exit **2** if `!ok` (hard findings), **0** if clean,
**1** on io/parse error. (Same exit-code contract as `contrast.mjs text-metrics`.)

### 3. `tools/scene-geom.test.mjs` (vitest, ~12–15 cases on `scoreGeometry`)

Synthetic node lists — the deterministic **proof the gate bites** (CI, no GPU):
clean screen; button clipped at the right edge (hard); button fully off-screen (hard, `fully`);
label fully under an opaque panel (hard occluded); label under a 0.5-α scrim → **not** occluded;
two panels partially overlapping → advisory; missing-texture node → advisory; invisible nodes
excluded; non-text/non-interactive victim fully covered → advisory not hard; paint/z tie ordering
correctness; `clipTol` boundary (2px in vs out); `opaqueAlpha` boundary (0.9 vs 0.92 vs 0.5).

### 4. `visual-audit/SKILL.md` prose

New **step 2c. Deterministic geometry pre-filter** (after 2b text-metrics, before the step-4
fan-out):

> Run `node tools/scene-geom.mjs check games/<id>`. It instantiates the scene and reads each
> visible `CanvasItem`'s on-screen rect, paint order, opacity, and texture state from the live
> tree, then deterministically flags: **off-viewport** clipping of interactive/text nodes and
> **full occlusion** of an interactive/text node by an opaque higher-paint node (both **hard**,
> exit 2), plus **partial overlap** and **missing-texture** nodes (advisory). Two uses, exactly
> like 2b: (1) hard findings go straight into the report as blockers — a clipped/covered button is
> a deterministic FAIL, not a VLM judgment call; (2) the emitted **bboxes are deterministically
> located candidate regions** — feed them to the composition/collision lens instead of eyeballing.
> **Coverage boundary (state it in the report):** sees only introspectable `CanvasItem` geometry
> (`Control` rects, textured `Node2D`). Art drawn via custom `_draw()`/`draw_texture()` is
> invisible here and stays the composition/collision VLM lens's job — a low `checked` count means
> the game draws in code, not that the screen is clean.

Plus: a one-line edit to `references/composition-collision.md` telling that lens to consume the 2c
bboxes as pre-located candidates; update the lenses table + step numbering in `SKILL.md`.

### 5. Dogfood (evidence)

Run `node tools/scene-geom.mjs check games/diver-0001`. Expected outcome: **CLEAN** — diver's
chrome-clip/occlusion bugs were already fixed in the prior asset/visual-audit pass, so the gate
agreeing is an honest "the fixes hold" result (cf. P1-a's honest no-op). Record the **calibration
finding**: diver's panel styleboxes are α=0.92/0.95 ⇒ the `opaqueAlpha` default of 0.9 is correct
(1.0 would miss them). Gate-bites evidence is the synthetic-broken unit tests. Optionally note a
forced-fail demo (e.g. `--opaque-alpha 0.9` already bites the synthetic case; a temp off-screen
button on diver), mirroring how P0b demonstrated `text-metrics --min 40`.

## Boundaries / honesty

- Deterministic geometry only; **no pixel heuristics** (preserves the verifier/heuristic line).
- Blind to custom-`_draw()` art **by design** — the VLM composition/collision lens owns that, now
  fed by the pre-filter's bboxes.
- Paint-order is `(z_index, paint)`; ignores `CanvasLayer`/`top_level` edge cases (documented).
- `opaque` for a textured Node2D treats any α≥threshold texture as opaque (texture alpha channel
  not pixel-measured) — kept conservative by scoping **hard** occlusion to text/interactive
  victims only; broader/uncertain coverage stays **advisory**.
- Records nothing to the manifest — `visual-audit` is a transient gate (code fixes + report).

## Out of scope

- Pixel-CV / magenta scan (deferred until the bug class recurs).
- Any change to the VLM lens fan-out mechanics beyond consuming the new bboxes.
- `runner-0002`'s `Sprite2D` path is supported but not the dogfood (diver is the running title).

## Test / verification plan

- `npx vitest run tools/scene-geom.test.mjs` green (+ full suite stays green).
- `node tools/scene-geom.mjs check games/diver-0001` → exit 0, JSON shows `checked` chrome nodes,
  `hard: []`.
- `SELFTEST`/`UITEST`/`PLAYTEST` on diver unaffected (no game-logic change).
