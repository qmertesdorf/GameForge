---
name: asset
description: Use when re-skinning a playable Godot game with coherent Claude-authored SVG art. Derives a visual system from concept.art_direction, authors SVGs, rewires primitive _draw() to Sprite2D/TextureRect, records asset_pass, and sets status to "styled".
---

# asset

Replace a `playable` game's deliberate **primitive** visuals with real, coherent **SVG art**, so the title goes from "intentional toy" to "looks designed" — with the re-skin legibly recorded in the manifest. The real deliverable is a sharp re-skin **system**, not the prettier game: every gap must be attributable to specific prose here. This runs as a clean bolt-on **after `playable`**:

```
concept → builder → validator → [playable] → asset → validator(re-run) → [styled]
```

## Inputs
- `manifests/<id>.json` with a populated `concept` block and `status = "playable"`.
- The generated project on disk at `games/<id>/` (a single `Node2D` whose `Main.gd` draws every entity procedurally in `_draw()`).
- The pinned Godot version from `README.md`.

## Outputs
- `games/<id>/art/*.svg` — one Claude-authored vector file per re-skinned entity.
- A rewired `Main.gd` / `Main.tscn` displaying those SVGs via `Sprite2D` (world) / `TextureRect` (HUD).
- A populated `asset_pass` block and flipped `assets[]` entries (`origin:"svg"`).
- `status = "styled"` (after the validator re-run passes).

## Hard requirements
- The re-skinned project MUST still import and run **headless with no script errors** (the `validator` re-enforces this).
- Game **logic is untouched** — movement, collision, spawning, scoring, input, and game-over/restart behave exactly as before. Only the *visual representation* changes.
- No double-draw: for every re-skinned entity the old `_draw()` primitive is removed or guarded. Leaving the primitive *and* adding the sprite is the most common failure — prevent it.
- No new MCP tool and no new dependency: author SVG inline as text, exactly as `builder` authors GDScript. Godot's native importer rasterizes it.
- Do **not** edit `concept` or `builder`. Consume `concept.art_direction` as-is.

## Step 0 — Derive the visual system FIRST (the real deliverable)

A real asset creator does not produce a pile of independently-acceptable shapes — it produces **one coherent visual system** and applies it everywhere, so the game reads as a single designed thing. "Each SVG is fine but they don't cohere" is the **primary failure** this step exists to prevent (the art analog of the M0 hybrid finding, "two systems that coexist instead of fuse"). When it happens, it is attributable to *this system*, not the individual files.

Before authoring **any** SVG, write the system down explicitly from `concept.art_direction`:

- **Palette** — a fixed 3–5 colour set with named roles (primary, accent, danger, background, …). Every fill/stroke comes from this set.
- **Line/stroke** — one stroke weight and one join/cap style, used throughout.
- **Form language** — corner radius, geometric vs. organic, level of detail. Pick one and hold it.
- **Shading model** — flat / single-direction gradient / glow halo — pick **one** and apply it to every asset.
- **Scale & padding** — how each SVG maps to its primitive's footprint, plus consistent internal padding so assets sit together (e.g. all art drawn into a square `viewBox` with the same % padding).

This system is recorded verbatim in `asset_pass.visual_system` (below) so it is reviewable, reusable, and the thing a run report critiques when the result looks incoherent.

## The SVG aesthetic boundary (be honest about scope)

SVG is the *right* tool for the art this pipeline produces today — abstract, geometric, neon/flat, hyper-casual, all UI. Resolution independence is an app-store strength: one vector covers every Android density bucket. SVG is the *wrong* tool for **representational, character, illustrated, or textured** art (a painted hero, a photoreal background) — that is an **M1.5 (raster / local-SD)** concern.

If a concept's `art_direction` leans representational enough that hand-authored vector would be weak, **say so in `asset_pass.notes`** ("art_direction calls for an illustrated character; SVG would be mediocre here — M1.5 would serve it better") rather than silently shipping poor vector art. Re-skin what SVG does well; flag what it doesn't.

## Authoring the SVGs

One file per builder-registered visual entity, under `games/<id>/art/` (e.g. `player.svg`, `obstacle.svg`, `pickup.svg`). Every file conforms to the Step 0 system: same palette, same stroke, same form language, same shading model, same `viewBox`/padding convention.

- Use a square `viewBox` (e.g. `0 0 100 100`) so scaling to a footprint is predictable.
- Execute the shading model — if it is "flat fill + outer glow halo", actually draw the halo (an oversized, low-alpha shape behind, or an SVG `<filter>` blur), don't just assert it. Asserting neon is not executing neon.
- Keep files small and diffable — paths, `<rect>`, `<circle>`, gradients, filters. No embedded rasters.

## The SVG-swap mechanism (the technically hard part)

The builder draws procedurally — there are **no sprite slots to swap into**, and `Main.tscn` is a bare `Node2D` with all rendering in `Main.gd`'s `_draw()`. So you must both generate SVGs *and* rewire the game.

**a) Get the SVGs into Godot.** Godot 4.x imports `.svg` as a texture via a `.svg.import` sidecar (carrying a `scale` param). Run a headless import pass so the sidecars and cached textures exist **before** re-validating:
```
godot --headless --path games/<id>/ --import
```
Commit the generated `*.svg.import` sidecars alongside the art (expected Godot output, like `.gd.uid`).

**b) Replace each primitive (the documented swap pattern).** Per re-skinned entity:
- Load the texture and display it with a node positioned/scaled to the primitive's original footprint:
  - **World actors** (player, obstacles, pickups) → `Sprite2D` with `texture = load("res://art/<name>.svg")`, placed at the same world transform the `_draw()` used. For pooled/spawned collections (e.g. obstacles), create one `Sprite2D` per live instance and move it each frame to the position the primitive was drawn at, instead of a `draw_*` call.
  - **HUD/UI** → `TextureRect` under the HUD layer.
- **Remove or guard** the matching `_draw()` code for that entity — delete its `draw_rect`/`draw_circle`/glow calls; keep the node's transform and all game logic. Verify you did not leave the primitive drawing underneath the sprite (double-draw).
- Movement, collision, spawning, scoring — **unchanged**.

**c) What stays primitive.** Effects (glow halos, particles, screen-shake, squash/stretch, flash) stay code — they are *motion/juice*, not art. Backgrounds may stay procedural (parallax grid/stars) **or** get a tiling SVG — your judgment from `art_direction`. **Record which entities you re-skinned vs. left primitive** so a partial re-skin is a legible choice, not a silent gap.

**Failure attribution (the POC value):** a bad re-skin is always attributable — you authored a poor SVG, mis-positioned/mis-scaled a sprite, or failed to remove the underlying primitive. Each is a specific, fixable prose gap.

## Recording the pass

1. Flip the re-skinned `assets[]` entries (arrays replace wholesale — pass the **full** array, re-skinned entries as `origin:"svg"`, untouched ones as-is):
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ {\"type\":\"sprite\",\"name\":\"player\",\"source\":\"art/player.svg\",\"origin\":\"svg\"}, ... ]}"
   ```
2. Write the `asset_pass` block (record the Step 0 system verbatim):
   ```
   node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"svg\",\"visual_system\":{\"palette\":[...],\"stroke\":\"...\",\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\"},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\"}}"
   ```
3. Validate the manifest (still `playable` at this point):
   ```
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`.

## Hand off to the validator

Do **not** set `styled` yourself. Hand off to `validator`, which re-runs the same gates on the rewired game (headless import + run clean; `selftest.gd` still `SELFTEST OK` if present; human A/B playtest) and advances `playable → styled` on success, or records legible `issues` (attributed almost always to `asset`) and stops on failure.

## Notes
- The import pass (`--import`) must run before the validator's headless run, or `load("res://art/...svg")` returns null at runtime.
- If a re-skin makes the game look *worse* or incoherent, that is a finding about the **visual system** (Step 0), not the individual files — fix the system and re-derive, don't patch one SVG.
