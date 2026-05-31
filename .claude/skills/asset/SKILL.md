---
name: asset
description: Use when re-skinning a playable Godot game with coherent Claude-authored art. Branches on concept.art_direction into two methods — svg (geometric/UI, authored inline) or raster (representational/illustrated, generated as RGBA PNGs via local ComfyUI+SDXL+LayerDiffuse through tools/comfy.mjs). Derives a visual system, rewires primitive _draw() to textures, records asset_pass, and hands off to validator for "styled".
---

# asset

Replace a `playable` game's deliberate **primitive** visuals with real, coherent **SVG art**, so the title goes from "intentional toy" to "looks designed" — with the re-skin legibly recorded in the manifest. The real deliverable is a sharp re-skin **system**, not the prettier game: every gap must be attributable to specific prose here. This runs as a clean bolt-on **after `playable`**:

```
concept → builder → validator → [playable] → asset → validator(re-run) → [styled]
```

## Choosing the method (branch on `concept.art_direction`)

This skill has **two methods**, picked from `art_direction`. Both share *all* the rewiring craft below (texture-on-disk → `Sprite2D`/`TextureRect`/`draw_texture*`, footprint placement, primitive removal, the run-007 immediate-mode lessons) — only how the texture is *produced* differs.

- **geometric / neon / flat / hyper-casual / UI** → **`svg`** method (authored inline as text; the rest of this skill below). Resolution-independent, covers every density bucket from one file.
- **representational / character / creature / illustrated / textured** → **`raster`** method (generated RGBA PNGs via local ComfyUI + SDXL + LayerDiffuse; see **The `raster` method** section). This is the art SVG does *badly* — a painted hero, a creature, a textured surface.

This is the same "SVG aesthetic boundary" the SVG method documents — `raster` is now where the skill **goes** when it hits a representational concept, instead of only flagging it. A single run may be **mixed-method** (some entities `raster`, some `svg`, some left `primitive`); see the raster section's "Mixed-method honesty".

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
- **Form language** — corner radius, geometric vs. organic, level of detail. Pick one and hold it. Then give **each** actor *one* signature silhouette detail (a directional notch on the player, an inner facet on a pickup) — staying within the form language. Without it the re-skin reads as "the same primitive, just rounder" and the upgrade is muted (run-007 finding #3): a re-skinned square that is still just a square is a weak A/B.
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

**d) Re-skinning an immediate-mode `_draw()` game (the builder's DEFAULT — read this first).** The builder ships a *single* `Node2D` whose `Main.gd` draws every entity in one root `_draw()`, with **zero child nodes** and screen-shake applied via `draw_set_transform`. Two swap strategies, and the choice is itself a finding to record in `asset_pass.notes` (run-007 findings #1–#2):

- **Lighter, preferred for immediate-mode games — `draw_texture*` in place.** Replace each actor's `draw_rect`/`draw_circle` with `draw_texture_rect()` / `draw_texture()` *inside the existing `_draw()`*, loading the SVG texture once in `_ready()`. This reuses the SVG art while preserving z-order, the shake transform, and squash/stretch **for free** — no node tree surgery. Reach for this first when the game is one `_draw()`.
- **Retained `Sprite2D`/`TextureRect` nodes — for node-based scenes, or when you want per-actor nodes.** If you go this route on an immediate-mode game, expect three non-obvious steps the naive "just add a Sprite2D" misses:
  1. A parent's own `_draw()` renders *below* its children. So keep the **background layer** in the root `_draw()`, but move anything that must sit **above** the actors (HUD, particles, crash-flash) into a **higher-`z_index` child node** that delegates back (e.g. an `Overlay` Node2D whose `_draw()` calls a `draw_overlay(self)` method on Main). Otherwise the HUD vanishes under the sprites.
  2. **Hoist screen-shake into shared per-frame state** (compute the shake offset once in `_process`, store it, add it to every sprite's `position` *and* use it for the background `draw_set_transform`) so sprites and background shake together. A sprite's node transform does not inherit the `_draw()` transform.
  3. **Pool one node per spawned actor** (grow an `Array` of `Sprite2D`, show/hide per live instance). For a tinted family (e.g. obstacles in two danger colours from one white SVG), set `modulate` per instance.

**Failure attribution (the POC value):** a bad re-skin is always attributable — you authored a poor SVG, mis-positioned/mis-scaled a sprite, or failed to remove the underlying primitive. Each is a specific, fixable prose gap.

## The `raster` method (representational art via local SD)

Use this when the method branch sent you to `raster`. It produces **RGBA sprites** (native transparency at generation time) that hand-authored SVG cannot do well. The deliverable is still a sharp **system**: every "this sprite looks bad" must trace to a fixable cause — a weak prompt scaffold, a wrong style profile/param, a mis-placed sprite, a left-in primitive, or an *infra* failure in `comfy.mjs` — never an unattributable blob.

### Prerequisite (assumed running, like Godot)
ComfyUI runs headless as a local server (default `http://127.0.0.1:8188`) with an SDXL checkpoint and the **ComfyUI-layerdiffuse** node installed. It is **not** managed by this skill — the owner starts it. Before generating, confirm it is reachable and see what checkpoints exist:
```
node tools/comfy.mjs --check
```
Expected: `comfy OK at http://127.0.0.1:8188 — N checkpoint(s): ...`. If it prints `UNREACHABLE`, **stop** and ask the owner to start ComfyUI (or `! <launch command>`). A failure here is *infra*, attributable to the stack, not to your art judgment — never work around it by faking a PNG.

**Stack-version sensitivity (hard-won — see `docs/superpowers/m1.5-feasibility-notes.md`).** ComfyUI-layerdiffuse is **version-fragile**: on a bleeding-edge ComfyUI it (a) silently drops its model patch (`patch type not recognized` in the server log → output is haze) and (b) errors on the final alpha-join. The feasibility gate pinned **ComfyUI to a node-compatible release** + a small local node patch to get clean transparency. If sprites come back as haze or with a desaturated/gray interior (correct alpha but flat color), that is a **stack-version** issue, not your recipe — check the server log for patch warnings and confirm the pin/patch from the feasibility notes are in place before touching the recipe.

### Step 0 (raster) — visual system first, with style as a first-class choice
Do the normal Step 0 (palette, form, shading, scale). For raster, additionally:

**(a) Select the per-game style profile — explicitly.** Art style is a **first-class, per-game parameter**; it is what lets *one* skill make *different-looking* games. From `art_direction`, choose:
- a **checkpoint** (e.g. a painterly SDXL finetune vs. a flat-cartoon vs. a pixel-art checkpoint),
- optional **LoRA(s)**,
- the **style fragment** of the prompt (e.g. `"painterly, illustrated, soft brushwork"`).

Justify "this `art_direction` → this profile" exactly as you justify the SVG visual system. Record it verbatim in `asset_pass.visual_system.style` (`{ checkpoint, loras[], style_prompt }`). Two different games **should** look deliberately different because they picked different profiles — that difference is the goal, not a failure.

**(b) Fix the shared prompt scaffold.** Write one base prompt string (style fragment + shared scene/lighting/background terms) and one fixed sampler/steps/cfg. **Every** sprite in this game is generated as `scaffold + this actor's subject` from that one scaffold, so the set reads as a single designed family. Record it in `asset_pass.visual_system.prompt_scaffold`.

**"Each sprite is fine but they don't cohere"** is the same *primary failure* the SVG method guards against — here prevented by the profile + shared scaffold + fixed params, **not** by independent per-actor prompts. Incoherence within one game is a finding about the **scaffold/profile**, never about an individual PNG.

### Per-entity flow
For each entity you decide to make raster:
1. **Recipe** — compose the JSON recipe: `prompt` = `scaffold + this actor's subject`; plus `negative`, `seed`, `sampler`, `steps`, `cfg`, `checkpoint`, optional `lora`, `layerdiffuse: true`, and `master_resolution` (see Resolution below). Keep `sampler`/`steps`/`cfg` identical across the game's sprites. A template that includes a `%lora%` node requires the recipe to set `lora`; for a profile with no LoRA, use a template that omits the `%lora%` token (an absent `lora` against a `%lora%` template fails loudly by design — that is attributable, not a bug).
   - **Proven defaults (feasibility gate):** use an **SDXL finetune** as `checkpoint` (e.g. Juggernaut XL, DreamShaper XL) — **not base `sd_xl_base_1.0`**, which renders flat/washed-out through LayerDiffuse. `sampler: "euler"`, `cfg: 7–8`, `steps: 20–25`. The LayerDiffuse templates bake the FG-RGBA-canonical settings (`SDXL, Conv Injection` + scheduler `normal`) — those are the *working* settings; `Attention Injection`/`karras` produced mud in testing. `master_resolution`: 1024 for a hero/large actor, 512 for a minor prop (always downscale-from-master).
2. **Generate** — `node tools/comfy.mjs gen <id> <name> '<recipe-json>'` → writes `games/<id>/art/<name>.png` (RGBA). On a graph/unreachable error it fails loudly — fix the *infra/recipe*, do not fake the file.
3. **Import** — run the headless import pass so Godot makes the `.png.import` sidecar + cached texture **before** re-validation:
   ```
   godot --headless --path games/<id>/ --import
   ```
4. **Configure mobile import settings** (see Resolution & mobile density) — edit the generated `games/<id>/art/<name>.png.import` so it is mobile-grade, then re-run `--import`.
5. **Rewire** — identical to the SVG swap below: prefer `draw_texture*`-in-place for the builder's default single-`_draw()` games, else pooled `Sprite2D`/`TextureRect`; place at the primitive's original footprint; **remove/guard** the matching primitive (no double-draw); **game logic untouched**.

### Mixed-method honesty (inverted boundary)
The SVG method flags when representational art needs raster. Raster **inverts** it: if an actor is genuinely better as crisp vector or a primitive — a UI/HP bar, a geometric pickup, a HUD frame — you are **allowed to leave it `svg` or `primitive`**, and you must **say so**. A run can be mixed-method. Record per-entity which is `raster` vs `svg` vs `primitive` (`reskinned`/`left_primitive` + `assets[].origin`) so a partial raster pass is a legible choice, not a silent gap.

### Resolution & mobile density (recovering what SVG gave for free)
SVG covered every Android density bucket (mdpi → xxxhdpi) from one file. Raster forfeits that, so replace it deliberately or the output is **not** app-store-ready:
- **Generate high-res masters.** Size each sprite's `master_resolution` for the **largest** density bucket it occupies on screen — a generous power-of-two master (e.g. **512²** for a minor prop, **1024²** for a hero actor). Always **downscale from the master**, never upscale, so it stays crisp on xxxhdpi.
- **Set mobile import settings explicitly.** In each `games/<id>/art/<name>.png.import`, set `mipmaps/generate=true` (clean minification), a linear `filter`, and a 2D-mobile-appropriate compression (lossless for small sprite counts; VRAM-compressed if the title grows). Do **not** accept Godot's editor defaults silently. Record the choice in the recipe's `import_settings` (`{ mipmaps, filter, compression }`).
- **Footprint mapping unchanged.** The sprite scales to the primitive's on-screen footprint at runtime; the master being larger than the footprint is *correct* (high-DPI headroom), not waste to "fix" by shrinking the master.

Texture **atlasing** and whole-title APK **size budgeting** are **M2** packaging concerns — out of scope here. Generating proper masters now is what makes that later step possible.

### Content & IP safety
SDXL can emit outputs resembling trademarked/copyrighted characters — an app-store rejection and legal risk. So:
- Put IP guards in **every** recipe's `negative` prompt: `"logo, watermark, text, trademarked character, brand, celebrity likeness"`.
- Keep prompts to **generic descriptors** — never name a franchise, studio, or character.
- The **human A/B** is the safety review: the owner confirms nothing looks like protected IP **before** `styled`. (Model/output licensing is settled in the research note — SDXL Community License, outputs owned for commercial use under the revenue threshold; re-verify the threshold at ship time.)

### Determinism (state this plainly)
The committed **PNG is canonical** — a fresh clone runs identically. `recipes[]` is **provenance, not a bit-exact regeneration guarantee**: GPU matmul + RNG are non-deterministic, so the same recipe regenerates a *close* image, never the same pixels. "I have the seed" ≠ "I can reproduce the art."

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

**For the `raster` method**, the `asset_pass` you merge in step 2 additionally carries the style profile, the shared scaffold, and one recipe per generated PNG (arrays replace wholesale — pass the full `recipes[]`):
```
node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"raster\",\"visual_system\":{\"palette\":[...],\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\",\"prompt_scaffold\":\"...\",\"style\":{\"checkpoint\":\"...\",\"loras\":[...],\"style_prompt\":\"...\"}},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\",\"recipes\":[{\"name\":\"hero\",\"checkpoint\":\"...\",\"prompt\":\"...\",\"negative\":\"...\",\"seed\":123,\"sampler\":\"...\",\"steps\":30,\"cfg\":6.5,\"master_resolution\":1024,\"layerdiffuse\":true,\"lora\":\"...\",\"import_settings\":{\"mipmaps\":true,\"filter\":\"linear\",\"compression\":\"lossless\"}}]}}"
```
Flip each raster entity's `assets[]` entry to `origin:"raster"` (e.g. `{"type":"sprite","name":"hero","source":"art/hero.png","origin":"raster"}`); leave `svg`/`primitive` entities as they are.

## Hand off to the validator

Do **not** set `styled` yourself. Hand off to `validator`, which re-runs the same gates on the rewired game (headless import + run clean; `selftest.gd` still `SELFTEST OK` if present; human A/B playtest) and advances `playable → styled` on success, or records legible `issues` (attributed almost always to `asset`) and stops on failure.

## Notes
- The import pass (`--import`) must run before the validator's headless run, or `load("res://art/...svg")` returns null at runtime.
- If a re-skin makes the game look *worse* or incoherent, that is a finding about the **visual system** (Step 0), not the individual files — fix the system and re-derive, don't patch one SVG.
