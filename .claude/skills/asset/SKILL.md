---
name: asset
description: Use when re-skinning a playable Godot game with coherent, Claude-authored art. Branches on concept.art_direction — raster (representational/illustrated, the default for character/creature/scene art: RGBA PNGs via local ComfyUI+SDXL+LayerDiffuse through tools/comfy.mjs) or svg (geometric/UI/flat, authored inline as text). Derives a visual system, rewires primitive _draw() to textures, audits the composited running game, records asset_pass, and hands off to validator for "styled".
---

# asset

Replace a `playable` game's deliberate **primitive** visuals with real, coherent, **Claude-authored art**, so the title goes from "intentional toy" to "looks designed" — recorded legibly in the manifest. The deliverable is a sharp re-skin **system**, not one prettier game: every gap must trace to specific prose here. Runs as a clean bolt-on after `playable`:

```
concept → builder → validator → [playable] → asset → validator(re-run) → [styled]
```

## Choosing the method (branch on `concept.art_direction`)

First **read `concept.theme`** — the title's modality-neutral world (premise/tone/mood/setting). `art_direction` is the *visual expression* of that theme: the system you derive must read as *that world*, the same one the audio and store icon express — not a free-standing aesthetic. (Reading the theme is not editing it; the "consume `concept` as-is" rule holds.)

Two methods, both sharing all the rewiring craft below — only how the texture is *produced* differs:

- **representational / character / creature / illustrated / textured → `raster`** (the default for art): RGBA PNGs generated via local ComfyUI + SDXL + LayerDiffuse. This is what SVG does badly — a painted hero, a creature, a textured scene.
- **geometric / neon / flat / hyper-casual / pure UI → `svg`**: authored inline as text, rasterized by Godot's importer. Resolution-independent — one file covers every Android density bucket.

**Raster is the default; do not retreat to SVG to dodge a quality problem.** The remedy for "terrible" raster is to *lift raster quality* (better backgrounds, sizing, the levers below), not to fall back to vectors. Choose `svg` only for a genuine reason — a UI/HUD/geometric element where vector resolution-independence is a real win — and state that justification in `asset_pass.notes`. A run may be **mixed-method** (some entities `raster`, some `svg`, some left `primitive`); see "Mixed-method honesty".

## Inputs
- `manifests/<id>.json` with a populated `concept` block and `status = "playable"`.
- The generated project at `games/<id>/` (typically a single `Node2D` whose `Main.gd` draws every entity procedurally in `_draw()`).
- The pinned Godot version from `README.md`.

## Outputs
- `games/<id>/art/*` — one Claude-authored texture per re-skinned entity (`.png` raster / `.svg` vector).
- A rewired `Main.gd` / `Main.tscn` displaying them via `draw_texture*` / `Sprite2D` / `TextureRect`.
- A populated `asset_pass` block and flipped `assets[]` entries (`origin:"raster"|"svg"`).
- `status = "styled"` (after the validator re-run passes).

## Hard requirements
- The re-skinned project MUST still import and run **headless with no script errors** (validator re-enforces).
- Game **logic is untouched** — movement, collision, spawning, scoring, input, game-over/restart behave exactly as before. Only the *visual representation* changes. If a `selftest.gd` exists it must still print `SELFTEST OK`.
- **No double-draw:** for every re-skinned entity the old `_draw()` primitive is removed or guarded. Leaving the primitive *and* adding the texture is the most common failure — prevent it.
- No new MCP tool or dependency beyond the existing `tools/comfy.mjs` raster stack.
- Do **not** edit `concept` or `builder`. Consume `concept.art_direction` as-is.

## Step 0 — Derive the visual system FIRST (the real deliverable)

A real asset creator produces **one coherent visual system** applied everywhere, not a pile of independently-acceptable shapes. "Each asset is fine but they don't cohere" is the **primary failure** this step prevents; when it happens it's attributable to *this system*, not the individual files. Before authoring/generating anything, write it down from `concept.art_direction`:

- **World/character bible (derive FIRST)** — from `theme.setting` + `premise`, pin **one fictional world and one character family** before any subject is chosen. Every actor — hero, hazard, pickup — is an inhabitant of that one world (same materials, era/genre, "what kind of thing is this"). The hero and hazard must read as belonging together — *not a cyan robot vs. a red ogre*. This is the *subject-level* sibling of palette/form/shading below (which pin only *how* things render, never *what world they're from*). Recorded in `asset_pass.visual_system.world_bible`. Applies to **both** methods.
- **Palette** — a fixed 3–5 colour set with named roles (primary, accent, danger, background). Every fill/stroke comes from it.
- **Line/stroke** — one weight, one join/cap, throughout.
- **Form language** — corner radius, geometric vs. organic, detail level. Pick one and hold it. Then give **each** actor *one* signature silhouette detail (a directional notch, an inner facet) — within the form language and the character family. Without it the re-skin reads as "the same primitive, just rounder."
- **Shading model** — flat / single-direction gradient / glow halo — pick one, apply everywhere. Asserting it isn't executing it: if it's "flat + glow halo," actually draw the halo.
- **Scale & padding** — how each asset maps to its primitive's footprint, with consistent internal padding (e.g. all art in a square canvas at the same % padding).

Recorded verbatim in `asset_pass.visual_system` so it's reviewable and the thing a run report critiques when the result looks incoherent.

## The swap mechanism (the technically hard part — shared by both methods)

The builder draws procedurally: `Main.tscn` is a bare `Node2D` with all rendering in `Main.gd`'s `_draw()` — **no sprite slots to swap into**. So you both produce textures *and* rewire.

**a) Get textures into Godot.** Run a headless import pass so the `.import` sidecars + cached textures exist **before** re-validating:
```
godot --headless --path games/<id>/ --import
```
Commit the generated `*.import` sidecars alongside the art (expected Godot output, like `.gd.uid`).

**b) Two swap strategies** (the choice is itself a finding to record in `asset_pass.notes`):
- **`draw_texture*` in place — lighter, preferred for the builder's default single-`_draw()` games.** Replace each actor's `draw_rect`/`draw_circle` with `draw_texture_rect()`/`draw_texture()` *inside the existing `_draw()`*, loading the texture once in `_ready()`. Preserves z-order, the shake transform, and squash/stretch for free — no node surgery.
- **Retained `Sprite2D`/`TextureRect` nodes — for node-based scenes or per-actor nodes** (world actors → `Sprite2D` at the primitive's transform; HUD/UI → `TextureRect` under the HUD layer). On an immediate-mode game this needs three non-obvious steps the naive "just add a Sprite2D" misses:
  1. A parent's `_draw()` renders *below* its children. Keep the **background** in the root `_draw()`, but move anything that must sit *above* actors (HUD, particles, crash-flash) into a higher-`z_index` child that delegates back (e.g. an `Overlay` Node2D whose `_draw()` calls `draw_overlay(self)` on Main). Else the HUD vanishes under the sprites.
  2. **Hoist screen-shake into shared per-frame state** (compute the offset once in `_process`, add it to every sprite's `position` *and* the background `draw_set_transform`) — a node transform doesn't inherit the `_draw()` transform.
  3. **Pool one node per spawned actor** (grow an `Array`, show/hide per live instance; `modulate` per instance for a tinted family from one texture).

**c) Remove or guard** the matching `_draw()` for each re-skinned entity — delete its `draw_rect`/`draw_circle`/glow calls; keep the node's transform and all logic. Verify no double-draw. Also delete **stale glow-halos sized for the old primitive** — behind a larger sprite they read as an odd disc artifact.

**d) What stays code.** Effects (glow, particles, screen-shake, squash/stretch, flash) stay code — they're *juice*, not art. Record which entities you re-skinned vs. left primitive (`reskinned`/`left_primitive`) so a partial pass is a legible choice, not a silent gap. **A primitive background is a cohesion gap, not a free pass** — the raster method generates a themed background (see Backgrounds); if you leave it primitive you must justify it in `notes`.

**Failure attribution (the POC value):** a bad re-skin is always attributable — a weak texture, a mis-positioned/mis-scaled sprite, or a left-in primitive. Each is a specific, fixable prose gap.

---

# The `raster` method (representational art via local SD)

Produces **RGBA sprites** (native transparency at generation time) SVG can't do well. The deliverable is still a sharp **system**: every "this looks bad" must trace to a fixable cause — a weak scaffold, wrong style profile/param, a mis-placed sprite, a left-in primitive, or an *infra* failure in `comfy.mjs` — never an unattributable blob.

## Prerequisite (assumed running, like Godot)
ComfyUI runs headless as a local server (default `http://127.0.0.1:8188`) with an SDXL checkpoint + the **ComfyUI-layerdiffuse** node. The owner starts it; this skill doesn't manage it. Confirm reachability + see checkpoints:
```
node tools/comfy.mjs --check
```
If it prints `UNREACHABLE`, **stop** and ask the owner to start it. A failure here is *infra*, attributable to the stack — never work around it by faking a PNG.

**Stack-version sensitivity.** ComfyUI-layerdiffuse is version-fragile: on a bleeding-edge ComfyUI it silently drops its model patch (`patch type not recognized` → haze) and errors on the alpha-join. If sprites come back as haze or a desaturated/gray interior (correct alpha, flat colour), that's a **stack-version** issue, not your recipe — check the server log for patch warnings and confirm the pin/patch from `docs/superpowers/m1.5-feasibility-notes.md` are in place before touching the recipe.

## Step 0 (raster) — style as a first-class choice
Do the normal Step 0, plus:

**(a) Select the per-game style profile explicitly.** Style is a *first-class, per-game parameter* — it's what lets one skill make different-looking games. From `art_direction`, choose a **checkpoint** (painterly vs. flat-cartoon vs. pixel-art finetune), optional **LoRA(s)**, and the **style fragment** (e.g. `"painterly, illustrated, soft brushwork"`). Justify "this art_direction → this profile" as you justify the visual system. Record in `asset_pass.visual_system.style` (`{checkpoint, loras[], style_prompt}`). Two games *should* look deliberately different — that's the goal, not a failure.

**(b) Fix the shared prompt scaffold.** One base prompt (style fragment + shared scene/lighting terms) and one fixed sampler/steps/cfg. **Every** sprite is `scaffold + this actor's subject`, so the set reads as one family. Record in `asset_pass.visual_system.prompt_scaffold`. Always include `"single centered subject, full body, clean transparent background"` in the scaffold, and put scene/multiplicity terms — `"scene, multiple characters, frame, border, ring, wreath, ground, floor, shadow"` — in the shared `negative`. Without this, an over-described minor prop comes back as a wreath/row-of-blobs; the negatives don't fire if the positive prompt itself invites a scene.

Incoherence has two kinds: **style** divergence (caught by profile/scaffold/params) and **subject-world** divergence (caught by the world bible). A cyan-robot hero next to a red-ogre hazard is the latter — a finding about the world bible, never about one PNG.

## Audit every generation against intent — subject, tone, cross-asset cohesion
A diffusion model does **not** reliably draw what you asked. **Read every PNG and judge it against intent before accepting** — regenerate, don't ship "close enough" — on three axes:

- **Subject fidelity** — is this the *thing* you asked for? (e.g. "a small impish fire-demon" rendered a tall winged demoness.) When it drifts, **tighten the subject phrase** (make the intended thing the explicit sole subject, add concrete shape/scale words like "small, squat, hunched, oversized head") and add **anti-drift negatives** for what it became. **A named asset must depict the thing it names, recognizably at a glance — that's gameplay legibility, not just style.** A card called "Chain Lightning" must read as chained forked lightning, not a generic "arcane sigil" (a proven failure: abstracting a spell into an ornamental medallion left *no lightning in it at all* — the player can't tell what it does). Name the literal effect as the sole subject; negative out the generic-icon attractors (`medallion, emblem, sigil, rune circle, badge, gemstone, ornamental icon, symmetrical`) when they hijack it. Audit by asking *"could a player name this from the art?"*
- **Tone fidelity** — does it match the title's *mood*? Subject-right isn't enough: a corrected "small imp" can come back cute/chibi when the world wants sinister. Pull tone with mood words in the positive, the wrong tone in the negative (`cute, adorable, chibi, mascot` to banish; `menacing, sinister, grotesque, fanged` to invite). Tone lives in `concept.theme` — judge against it, not in the abstract.
- **Cross-asset cohesion — judge each asset *against the others*, not in isolation.** A shared style fragment is necessary but not sufficient: the same words land in different rendering registers depending on subject. **Diffusion pulls representational subjects (creatures, characters) toward photo-realism harder than abstract subjects (effects, sigils)** — so one fragment can render an effect-card as painterly but a creature as semi-photoreal, and side by side they don't cohere even though palette + words matched. Pick the asset whose style the owner approved as the **reference** and conform the others to *that specific register*, regenerating the reference too so you compare the locked style to itself. **De-realism ≠ flatten:** if the defect is photoreal *anatomy*, remove *only* the photoreal attractor (`photorealistic, hyperrealistic, realistic human skin, detailed musculature, 3d render, octane render`) and **keep the reference's painterly qualities** (`hand-painted illustration, painterly rendering, soft volumetric lighting, glowing aura`) — over-swinging to `cel-shaded, flat color, thick outlines` makes a flat mascot that's incoherent in the *opposite* direction. Match the reference's level of rendered detail and glow, not a generic flatness. "Same medium" is **not** cohesion: apply the one-hand test on the specific sub-axes — finish/render level, line weight, detail density, mood — *"would one illustrator have drawn both?"* — and watch for **whack-a-mole** where each regen fixes one axis and slips another. The fix isn't to keep swapping which asset is "too much": lock ONE finish register up front (name its finish/line/detail), conform every asset to it at once, and judge a true side-by-side.

The audit extends to the **composited render**, not just the raw PNG — when code draws chrome over the art, eyeball the assembled widget for layout collisions/clipping too (see "Audit the composited, running game"). "The art is good" ≠ "the screen is good."

Lever order per regen: subject/tone phrase → negatives → `master_resolution`/`width,height` → `cfg ±1`. Keep the *style* fragment + params fixed (cohesion); only subject/tone/negatives move.

## When the base model FIGHTS the style, swap the checkpoint — don't out-prompt it
The highest-leverage style lever is the **checkpoint**, not the prompt. A photoreal base (e.g. Juggernaut XL) will keep dragging representational subjects toward realism no matter how many `2D, flat, cel-shaded` terms + anti-`3d/photo` negatives you stack — that's a property of the weights, not the prompt; each regen fixes one axis and slips another. When 3–4 honest style regens still read wrong *in the same direction* (too rendered / gritty / realistic), stop out-prompting and **swap to a checkpoint whose native output already IS the target** (a flat-cartoon / illustration / anime SDXL finetune, e.g. Cartoon Arcadia XL). One swap does what a dozen prompt iterations can't, and it **solves cross-asset cohesion for free** — every asset inherits the model's one hand, so the creature-vs-effect whack-a-mole disappears.
- **Source one anonymously (no token):** query the Civitai API — `curl -s "https://civitai.com/api/v1/models?limit=20&types=Checkpoint&baseModels=SDXL%201.0&tag=cartoon&sort=Most%20Downloaded"` → parse `items[].name` + `modelVersions[0].files[0].downloadUrl`, then `curl -L --fail -o models/checkpoints/<name>.safetensors "<downloadUrl>"` (307-redirects to a B2 CDN, auto-issued token). You need a **single-file** `.safetensors`; HF diffusers-format repos (separate `unet/`,`vae/` folders) won't load in `CheckpointLoaderSimple`.
- **Gate it before the batch:** ComfyUI picks up a dropped checkpoint without restart (mtime rescan). Generate ONE sprite and confirm (a) the look is the target and (b) the **LayerDiffuse alpha-join is clean** (no haze/gray-interior matte) — a non-standard finetune can break the join. Record the chosen `checkpoint` in every recipe + `asset_pass`; it's now part of the locked visual system.
- Style words still matter — they now *reinforce* a willing model instead of fighting a hostile one (keep `flat bold cartoon, clean thick outlines, vibrant cel shading` positive, `anime, manga` negative for Western-not-anime).

## Abstract-effect subjects collapse — anchor to an actor, POV, or the world
An abstract effect ("forked chain lightning, no figures") is one of the worst subjects for an opaque SDXL card: the model's "fantasy art" distribution is scenes and characters, so a figure-less effect collapses to the nearest in-distribution thing — a random landscape, an invented caster, a weak scattered web, or literal trees from "branching." Don't burn a dozen gens fighting it. Give the model a subject it renders reliably **and** that ties to the game:
- **Actor-driven** — show the game's protagonist *performing* the effect (a recurring, consistently-described figure — same costume/palette every time — so the set coheres like a TCG's hero).
- **First-person POV (strong lever)** — frame it as the effect *leaving the actor's own hand* ("first-person POV down the caster's outstretched hand, `<effect>` bursting from the palm"). Reads instantly as the ability, and strips rendered-figure/background detail so it sits closer to a sprite's simplicity (helps cohesion).
- **World-anchored** — set it in the game's actual environment, not a model-picked vista; ties it to the world bible.
- Still audit with "could a player name this?" — an actor holding *fire* on a card named Chain Lightning is still a miss; negative the wrong element, name the right one.

## Per-entity flow
For each entity you make raster:
1. **Recipe** — compose JSON: `prompt = scaffold + this actor's subject` (the subject is *this actor as a member of the world-bible family*, never free-standing); plus `negative`, `seed`, `sampler`, `steps`, `cfg`, `checkpoint`, optional `lora`, `layerdiffuse:true`, `master_resolution`. Keep `sampler`/`steps`/`cfg` identical across the game's sprites. A `%lora%` template requires `lora` set; for a no-LoRA profile use a template that omits the token (an absent `lora` against a `%lora%` template fails loudly by design — attributable, not a bug).
   - **Proven defaults (feasibility gate):** an **SDXL finetune** as `checkpoint` (not base `sd_xl_base_1.0`, which renders flat/washed-out through LayerDiffuse). `sampler:"euler"`, `cfg:7–8`, `steps:20–25`. The LayerDiffuse templates bake the working FG-RGBA settings (`SDXL, Conv Injection` + scheduler `normal`); `Attention Injection`/`karras` produced mud in testing. `master_resolution`: 1024 for a hero/large actor, 512 for a minor prop — always downscale from the master.
   - **Optional levers (low-ROI vs. backgrounds — reach for backgrounds/sizing first):** `"scheduler":"karras"` (still unproven on GPU — confirm by eye, given the `karras`+`Attention Injection` "mud" finding); `"refine":true` routes to a 1.5× upscale + denoise-0.45 second pass (~1536² master — alpha-join GPU-verified clean, but the gain is marginal, so it's a crispness / high-DPI lever, not a fix for a "bad" sprite). `refine`+`lora` together is unsupported.
2. **Generate** — `node tools/comfy.mjs gen <id> <name> '<recipe-json>'` → writes `games/<id>/art/<name>.png` (RGBA). On a graph/unreachable error it fails loudly — fix the infra/recipe, don't fake the file.
3. **Import** — `godot --headless --path games/<id>/ --import` so the `.png.import` sidecar + cached texture exist **before** re-validation.
   - **Re-run `--import` after EVERY regeneration that overwrites an existing PNG, or Godot serves a STALE cached texture** (a regenerated sprite kept rendering as the old one because the cached `.ctex` wasn't invalidated). Overwriting in place doesn't reliably trigger re-import on a headless `--script`/screenshot run. Treat "regenerate → `--import` → render/validate" as one atomic sequence.
4. **Configure mobile import settings** (see Resolution & mobile density) — edit `<name>.png.import` so it's mobile-grade, then re-run `--import`.
5. **Rewire** — per the swap mechanism above: prefer `draw_texture*`-in-place; place at the primitive's footprint; remove/guard the primitive (no double-draw); logic untouched.
   - **Variable-width actors: tile exact-fit units, never stretch.** Fill a runtime-variable width by tiling N = `round(w / unit_size)` units that each fit exactly, so visual width matches collision width. Stretching a fixed-aspect sprite distorts it and misaligns visual vs. collision bounds.
   - **Tab-indented GDScript breaks exact-match edits.** The builder's GDScript uses tabs; the Edit tool's exact-match often fails on tab/space ambiguity. Reliable workaround — splice via PowerShell (`Get-Content`/`Set-Content` preserve tabs):
     ```powershell
     $lines = Get-Content path/Main.gd
     $out = $lines[0..($a-1)] + $new + $lines[($b+1)..($lines.Count-1)]  # replace 0-based [a..b]
     Set-Content path/Main.gd $out
     ```
     For a single line, `$lines[$i] = 'new line'` then `Set-Content`. Prefer this over repeated Edit retries when a splice isn't landing.

## Audit the composited, RUNNING game — not just the raw PNGs
Generating the hero actors and wiring them is **not** a finished pass — a re-skin that nails enemies + cards + background still reads unfinished if the surrounding UI is all primitives. Screenshot the actual running game and audit the composite; this is the art analog of the completeness-critic. Three moves:

**1. Inventory EVERY drawn element** and classify each `art` / `code-chrome-by-design` / `primitive-that-should-be-art`. Walk the renderer top to bottom — these start life as primitives and are easy to forget: card backs + draw/discard piles, HUD frame + portrait/avatar, resource orbs/crystals, HP-bar frames, buttons, status-effect icons, intent indicators (attack/defend shown as *text* vs. an icon), block/shield badges, relic/passive icons, currency, map/node icons, reward & win/lose screens. Produce a concrete **missing-asset list** and surface it with a scope decision — "I generated the heroes" ≠ "the pass is done." On a **re-audit** — or any pass over a build whose chrome a prior pass classified `code-chrome-by-design`/`left_primitive` — **re-challenge that classification from scratch**: a prior pass's "code chrome" label is NOT a PASS, and an inherited flat primitive sitting beside newly-painted art is the most common silent fidelity gap. Audit it as if seeing it for the first time.

**2. Hold every code-drawn element to the hero-art bar, judged at TRUE on-screen size.** Code-drawn primitives — bars, buttons, orbs, pips, gems, intent icons — are part of the visual system, not exempt. A flat default `draw_rect`/`draw_circle` reads as programmer-art next to painted assets and drags the whole screen down. For each:
- **Finished, not placeholder** — a deliberate shape, fill, outline, and a small cel highlight, not a half-drawn glyph. A simple icon that's *clearly* its thing (a crisp flame, a solid shield) beats an ornate ambiguous one.
- **Cohesive at the same fidelity — the binding test, and the one agents fail.** Against fully-painted art, a token built from `draw_circle`/`draw_arc`/`draw_rect`/`draw_polygon` is a **FINDING by default** — even with a radial gradient, a cel highlight, a bold outline, the right colour, and instant clarity. Those make it *finished*, not *painted*: **finished / legible / right-colour / clear are NECESSARY, NOT SUFFICIENT**, and a vector orb with a highlight is still a vector orb sitting on a painted card. The bar is the **one-hand test against the painted art** (NOT against your other code tokens): *would the illustrator who generated the cards/enemies have drawn this exact orb / ring / shield / gem / pip?* If you can't give an unqualified yes, it fails — and "PASS" requires a positive reason it reads as generated-painted, never just "it's deliberate/dimensional/clear." Fix: **generate it as a painted token from the same checkpoint** (the default). Style-in-code is allowed *only* when generation genuinely can't render the thing AND the code output is indistinguishable from a painted token (real rendered shading/texture) — a `draw_circle` gradient + a `draw_arc` ring does **NOT** qualify. **Fidelity-cohesion outranks crispness when the surrounding art is painted.**
- **Instant clarity at true size** — nameable in under a second? Small slots need bold, chunky, minimal-detail subjects; fine detail aliases to mush (a detailed sword-hilt intent icon turned to mush at ~18px). When a subject keeps fighting, switch to a clearer concrete object (snowflake → ice-shard).
- **Right value & semantic colour** — a token that should glow but reads muddy/dark fails even at the right shape (a "mana" orb came back a dark glossy sphere). Mana = bright blue, fire = warm amber, ice = cyan, health = green, gold = amber.
- **Legible numerals — AND a themed font, because the engine default is programmer-art.** Values on cost gems / pile counts / status stacks must be crisp and high-contrast at true size; a thin number on a small/dark badge fails (solid backing + shadow + size up). And **text must not collide with its own element** — a value drawn *on top of* its bar (the classic "24/30" over the HP fill) is a bug; move it beside/above or give it a backing pill. Separately, **the engine's default/fallback font (`ThemeDB.fallback_font`) is itself an unstyled art element** — generic digits on every card/bar/badge fight a painted set. Wire **one themed display font project-wide** (in both `draw_string` and any `Label`/pop-up override), not the fallback.
- **Re-roll, don't ship the first roll** — small-icon generation is unreliable (multi-subject, wrong colour, dark, ambiguous); budget 2–3 regens per icon with single-subject + colour locks. One subpar roll on each of ten tokens = a UI that reads cheap despite great hero art.

Treat **HP bars (player AND enemy), resource pips, and primary buttons (End Turn / confirm)** as first-class styled elements the audit names by default — "it's just a bar/button" is the rationalization that ships programmer-art.

**Code-token red flags — when you write one of these, you are PASSING programmer-art; flip it to a FINDING (every one passed a flat token in baseline testing):**
- "the cel highlight / gradient gives it a dimensional finish" → dimensional ≠ painted; a `draw_circle` orb is still a vector orb beside a painted card.
- "flat-ish but small and clearly-their-thing" → small is not an excuse (it's on every card, every turn), and clarity is a *different axis* from fidelity.
- "the invented ring/token language is cohesive across the indicators" → code tokens matching *each other* is a self-consistent programmer-art layer, NOT matching the *painted art* — run the one-hand test against the cards, not against your other tokens.
- "a crisp solid shape beats an ornate one" → true only versus an ornate *painted* token; it is not a license to ship a flat polygon next to painted art.

**3. Scan for visual bugs:** art **squished** by an aspect mismatch (generate backgrounds at the *exact* viewport aspect — a 1280×768 bg in a 1280×720 frame distorts), a sprite **not grounded** to its floor (transparent-padded square sprites float unless bottom-anchored), HUD text/bars **overlapping/clipping** (esp. over a busy bg with no panel behind), illegible chrome at true size, **z-order** mistakes, **double-draws** (a leftover primitive showing through), a **mis-cut token** (see below), and grain from missing mipmaps (below).

**Token framing & crop integrity — verify the ALPHA of every token, not just its look.** A token drawn with `draw_texture_rect` must be **ONE complete subject floating on transparency with a clean margin on all sides**. It is a FINDING when the PNG has **hard square/rectangular edges**, the subject is **clipped at the image border**, **opaque colour runs to the edge** (no transparent margin → draws as a cut-off square picture), or a **fragment of a neighbour** bleeds in. The high-risk source is the **salvage-crop**: pulling one subject out of a multi-subject generation sheet with a rectangular crop captures neighbour bodies and slices the subject — a rectangular crop is NOT a cutout. Salvaging requires masking to the single subject and cleaning the bleed to true transparency, then re-import. Check by reading the token's alpha channel / edges, not just glancing at the thumbnail — and confirm it again **composited at true size** (the bad crop reads as a smudged square blob in-game).

**4. Composition, legibility & colour-accessibility sweep — judge the screen as a WHOLE, not asset-by-asset.** Moves 1–3 grade each element; this grades how they sit *together* and whether a real player can read the result. Run it at the **busiest state** (full hand fanned, enemy intent + stacked status icons up, a reward/overlay open) and the **largest sizes**. The cohesion-of-elements analog of Step 0's cohesion-of-style.
- **Overlap / collision pass — ENUMERATE the element pairs that share each region, then inspect each pairing's boundary pixels in a MAGNIFIED crop.** Do not eyeball the holistic/downscaled frame and move on — that is exactly how an obvious collision gets waved through. Glancing at a 1× or 2× frame, two elements 6px apart and two elements overlapping by 6px look the same; the verdict only exists at the actual boundary. So **list the pairs** (intent icon ↔ name ↔ HP bar; cost badge ↔ name; pile badge ↔ pile label; hand cards ↔ End Turn ↔ piles; status icons ↔ portrait/feet; relics ↔ HUD) and **crop+zoom each tight pairing to 3×+** before you call it. A fanned hand SHOULD overlap card-to-card and a tooltip SHOULD sit above its card — but a sprite clipping the HUD panel, an intent icon touching the name, a badge over its label, two damage numbers stacking — those are bugs. The test: *did I position this overlap on purpose, or is it two systems drawing into the same pixels by accident?* Accidental → FINDING.
  - **A painted icon's footprint is its ART, not its `sz`/anchor — verify against rendered pixels, never the layout math.** A texture drawn at `s = sz * k` occupies a `2·s` box, and the visible blade/flame/sigil typically runs to the box edge and sits *off-centre*, so its real on-screen reach is far larger than the nominal `sz` implies. Layout math that "proves" a gap from the anchor point is worthless — the art overruns the anchor. (Precisely what slipped past this auditor once: a `sz=13` intent icon scaled `×1.8` was a ~47px box whose blade landed on the enemy name, while the spacing math read "clear." Caught only at 3× zoom, after first being dismissed as "minor.")
  - **There is NO "minor" tier when a non-text element contacts TEXT.** An icon, sprite, badge, bar edge, or border touching or overlapping a glyph is a FINDING, full stop. "It just sits right under it," "it only grazes the top," "close but still readable," "extends slightly past the panel" are the rationalizations that ship the collision — they are how this exact bug was downgraded to "minor" and missed. Text needs clear air on every side; element-on-text is binary, not graded.
- **Text-over-element pass — no string rides on top of something it doesn't belong to.** Generalises the "24/30 over the HP fill" rule to the whole screen: a numeral on its own bar, a card name riding into the cost badge, effect text clipped by the border/pip, a pile count over a card edge, a status-stack number off its icon. Gameplay text sits in its *own* reserved space (beside/above, or on a backing pill) — never floating on a busy element.
- **Legibility-over-background pass — EVERY text block needs a guaranteed solid backing, not just cards.** The full-bleed-card rule (a defined semi-transparent SOLID panel, never a gradient-to-transparent scrim alone) applies to ALL runtime text over non-uniform art: HUD values over the painted background, pile counts and floating combat numbers over the bg or over a sprite, the turn/phase banner, tooltips, overlay body text. A drop-shadow alone or a fading scrim FAILS over a bright/busy patch — that is exactly the "background behind text prevents legibility" bug. Read each text block against the *actual pixels behind it* at true size; if the backing isn't a solid panel/pill or the art behind is bright, it's a FINDING. This is the #1 reported legibility failure — sweep for it explicitly, don't assume the card rule covered the HUD.
- **Colour-accessibility sweep — contrast + colour-blind safety, judged on the composite.**
  - **Contrast ratio:** every text/icon-vs-its-backing pair clears a legible contrast at true size (target WCAG-ish ≥4.5:1 body, ≥3:1 large/bold). Thin light text on a mid-tone panel, or dark numerals on a dark badge, fail. Fix by solidifying/darkening the backing and lifting the text value — not by enlarging alone.
  - **Never encode meaning by hue alone.** State is signalled by colour (fire=amber, ice=cyan, lightning, Burn vs Chill, danger=red, mana=blue, health=green, affordable vs unaffordable). ~8% of players are red-green colour-blind and cheap phone panels in glare crush hue — so every colour-coded state must ALSO carry a non-colour cue (icon, shape, label, position). A red "can't afford" tint with no other signal, or Burn/Chill distinguished only by warm-vs-cool, is a FINDING. (This title's burn/chill/attack/defend icons are the right pattern — verify each colour-coded state actually has one.)
  - **Differ in VALUE, not only hue.** Two semantic colours sharing lightness (a red and a green at the same brightness) collapse for colour-blind users and in glare; ensure paired/opposed states also differ in brightness.
  - **Simulate it:** eyeball the frame desaturated/grayscale (kills hue, exposes value-only collisions) and mentally through a red-green filter — if two states become indistinguishable, add a non-colour cue.
- **Record each as a named finding** — *which two elements collide*, or *which text block over which backing* — as attributable as a subject drift, and run it through the same fix → re-render → fresh-eyes re-audit LOOP below.

**The audit is a LOOP, not one-shot.** Implementing the fixes isn't the end — re-screenshot and re-run the whole audit against the *new* frame, because (a) code-right ≠ screen-right (a restyled bar can still clip, a "centered" value can still sit a pixel off), and (b) fixes spawn new issues (a repositioned element creates a fresh collision; a newly-styled panel exposes a primitive that was hidden behind the old one; a bolder icon now overpowers its neighbour). Loop audit → fix → re-render until a full pass surfaces nothing new. Never call the pass done off the screenshot you *fixed against* — call it done off a clean re-audit of the screenshot that came *after* the fixes. **Re-audit with FRESH eyes — a clean pass (ideally a fresh subagent that didn't make the fix), never a glance at your own change.** You will rationalize your own code tokens and crops as "good enough" and your own near-collisions as "minor" — the eyeball-it-yourself shortcut is exactly how a flat code ring, a square-cropped token, and an icon-on-the-name overlap each shipped past a pass that *had* the rules to catch them. And **you do not get to self-certify a code token as "indistinguishable from painted" to keep it**: if you wrote `draw_circle`/`draw_arc`/`draw_rect` for a backing/orb/badge, default to FINDING and let the fresh pass judge it.

**Mipmaps — the grain fix (do this before blaming the art).** An asset authored ornate at high res and drawn into a small UI slot (a 768×1024 texture at 44px) **aliases into grain** with no mipmaps. Godot's importer defaults `mipmaps/generate=false`; set it **`=true`** in each downscaled texture's `.png.import` and re-import, AND set the canvas filter to a mipmap variant (`CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` on the drawing Node2D) — mipmaps need *both*. This de-grains every downscaled draw. Even so, a busy source thumbnails worse than a bold simple one — author small-display elements with fewer, larger shapes + thick outlines. **Verify the DOWNSCALED result at true size**, not the full-res PNG.

## Backgrounds & composition (where art quality actually lives)
Playtests proved sprites are usually already fine; "terrible" comes from **flat primitive backgrounds + heroes too small**, not sprite quality. So generate environment art and size the hero deliberately.
- **Background = full-frame OPAQUE image (no LayerDiffuse).** Use the plain `sdxl` template: `layerdiffuse:false`, no alpha, explicit non-square `width`/`height` matching the game's aspect (e.g. `1280×768` landscape, `768×1280` portrait — `comfy.mjs` honors distinct `width`/`height`). The prompt expresses `theme.setting` as a *scene/environment* ("a cozy autumn-woodland glade, soft depth, storybook") — the same world the sprites inhabit. Draw it as the **bottom layer** (root `_draw()` background, or a full-rect `Sprite2D` at `z_index` below all actors), replacing the flat primitive band/void. Record as a `reskinned` background, `origin:"raster"`. This **supersedes** the old "background left primitive is a deferred gap" default — a themed background is now in scope and expected.
- **Size the hero for the frame.** A detailed sprite floating tiny reads cheap. Place the hero to occupy a *prominent share* of its play area and clearly larger than/distinct from hazards. Sizing is a *runtime scale at wire time* (the `Sprite2D` scale / `draw_texture_rect` dest size), not a generation param — hitboxes untouched. Record the intent in `notes`.
- **Pixel-art backgrounds: the opaque `sdxl` template has NO LoRA node.** A pixel-art *sprite* uses `sdxl-layerdiffuse-lora` to apply `pixel-art-xl`; the opaque background template carries no `%lora%`, so get the pixel look from **prompt terms** ("pixel art, 8-bit, NES, chunky pixels") + the project's **NEAREST** texture filter. Record the LoRA-absence as a recipe `note`.
- **Full-playfield games: a background only fixes the MARGINS.** For a title whose playfield fills the screen (a lane-crosser whose flat lane bands ARE the frame), a full-frame background only enriches the visible margins — the flat playfield itself still reads flat. Fully fixing that needs **lane/surface tile textures** (a different technique, which also risks the lane-colour *readability* the gameplay depends on). Don't speculatively retexture a functional playfield — ship the margin/sizing win, record the lane-tile opportunity, let the owner direct.

## Text & chrome over full-bleed art
When a card/panel uses a **full-bleed painted illustration** (opaque art filling the rect, no authored frame) and code draws the gameplay text on top, the **generated PNG carries no border/panel/text** (those would bake in wrong values and fight legibility) — all chrome is code-drawn at runtime so one renderer serves every card:
- **A defined semi-transparent SOLID panel behind each text block — not a gradient scrim alone. This is the project-wide legibility primitive, not a card-only trick** — move 4's legibility pass applies it everywhere code draws text over non-uniform art (HUD, pile counts, floating combat numbers, banners, tooltips), not just cards. A gradient fades to transparent and so fails over a *bright* patch of art ("the text is hard to read"). A solid panel (`draw_rect` ~`Color(0.05, 0.04, 0.11, 0.80)`) gives **consistent** contrast regardless of what the model painted underneath; feather just its leading edge with a short gradient quad so it doesn't hard-cut into the painting. One panel for the bottom effect block, one for the top name.
- **Drop-shadowed text** (draw the string once near-black at +1px, then in the real colour).
- **Element border + cost badge + pip** stay code-drawn over everything, drawn *last* (gameplay-critical at-a-glance identity).
- **Scale text with the widget, not absolute px** — derive font sizes + chrome geometry from `rect.size` (e.g. `s = rect.size.y / base_h`), or big cards (reward cards, a 2× detail view) show tiny text.
- **Chrome-layout QA — audit the composited widget for collisions/clipping**, every state (affordable / unaffordable / selected) and the largest size: no element overlaps another (center the name in the space *right* of the cost badge, not under it), text fits its panel and isn't clipped by the card edge, the cost/border/pip stay clear of the text. A layout collision is an attributable chrome bug, exactly like a subject/tone drift.
- Immediate-mode gradient-quad helper (per-vertex colours): `draw_polygon(corners, [c_top,c_top,c_bot,c_bot])`.

## Mixed-method honesty
If an actor is genuinely better as crisp vector or a primitive — a HP bar, a geometric pickup, a HUD frame — you may leave it `svg`/`primitive`, and you must **say so** (record per-entity origin so a partial pass is a legible choice, not a silent gap). **When an actor fights the medium, mixed-method is the right call, not a cop-out:** a tiny or effect-like sprite (a ~14px glowing pickup) SDXL can't render coherently across retries is better as a procedural primitive (a glow-mote `draw_circle`). Vary subject phrase → `master_resolution` (1024→512→256) → `cfg ±1`; after 3–4 variations without a clean output, leave it primitive and record the finding. (This does **not** license crude code icons next to painted art — see the fidelity-cohesion bar in the composited audit; mixed-method is for genuine medium-fights, not for skipping fidelity.)

## Resolution & mobile density (recovering what SVG gave for free)
SVG covered every Android density bucket (mdpi → xxxhdpi) from one file; raster forfeits that, so replace it deliberately or the output is **not** app-store-ready:
- **Generate high-res masters** sized for the largest bucket the asset occupies (a generous power-of-two: **512²** minor prop, **1024²** hero actor). Always **downscale from the master**, never upscale.
- **Set mobile import settings explicitly** in each `.png.import`: `mipmaps/generate=true` (clean minification), a linear `filter`, a 2D-mobile compression (lossless for small sprite counts; VRAM-compressed if the title grows). Don't accept Godot's defaults silently. Record in the recipe's `import_settings` (`{mipmaps, filter, compression}`).
- **Pixel-art crispness:** set `process/size_limit` in the `.png.import` to a small target (64/128) so Godot resamples the 1024 master down cleanly at import, then draw with `TEXTURE_FILTER_NEAREST` (mipmaps off) to keep chunky pixels crisp. Don't draw a raw 1024 master tiny with nearest filtering — the alias noise is severe.
- **Footprint mapping is unchanged at runtime** — the texture scales to the primitive's on-screen footprint; the master being *larger* than that footprint is correct high-DPI headroom, **not** waste to "fix" by shrinking the master.
- Texture **atlasing** and whole-title APK **size budgeting** are **M2** packaging concerns, out of scope here. Generating proper masters now is what makes that step possible.

## Content & IP safety
SDXL can emit outputs resembling trademarked/copyrighted characters — an app-store rejection and legal risk:
- Put IP guards in **every** recipe's `negative`: `"logo, watermark, text, trademarked character, brand, celebrity likeness"`.
- Keep prompts to **generic descriptors** — never name a franchise, studio, or character.
- The **human A/B is the safety review** — the owner confirms nothing looks like protected IP before `styled`. (Outputs owned for commercial use under the SDXL Community License revenue threshold; re-verify the threshold at ship time.)

## Determinism
The committed **PNG is canonical** — a fresh clone runs identically. `recipes[]` is **provenance, not a bit-exact regeneration guarantee**: GPU matmul + RNG are non-deterministic, so the same recipe regenerates a *close* image, never the same pixels. "I have the seed" ≠ "I can reproduce the art."

---

# The `svg` method (geometric / UI / flat)

Use when the branch sent you to `svg` — abstract, geometric, neon/flat, hyper-casual, all UI, where vector resolution-independence is a real win (one file covers every Android density bucket). One file per builder-registered entity under `games/<id>/art/` (`player.svg`, `obstacle.svg`, …), every file conforming to the Step 0 system: same palette, stroke, form language, shading, `viewBox`/padding.
- Use a square `viewBox` (e.g. `0 0 100 100`) so scaling to a footprint is predictable.
- **Execute the shading model** — if it's "flat fill + outer glow halo," actually draw the halo (an oversized low-alpha shape behind, or an SVG `<filter>` blur). Asserting neon isn't executing neon.
- Keep files small and diffable — paths, `<rect>`, `<circle>`, gradients, filters. No embedded rasters.
- Rewire via the shared swap mechanism (`draw_texture*`-in-place preferred). Godot imports `.svg` as a texture via a `.svg.import` sidecar — commit it.

If a concept's `art_direction` leans representational enough that hand-authored vector would be weak, that's the signal you should be on the `raster` method — don't ship mediocre vector art to dodge generation.

---

## Recording the pass

1. Flip the re-skinned `assets[]` entries (arrays replace wholesale — pass the **full** array, re-skinned as `origin:"raster"|"svg"`, untouched as-is):
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ {\"type\":\"sprite\",\"name\":\"hero\",\"source\":\"art/hero.png\",\"origin\":\"raster\"}, ... ]}"
   ```
2. Write the `asset_pass` block (record the Step 0 system verbatim). The `raster` method additionally carries the style profile, the shared scaffold, and one recipe per generated PNG (arrays replace wholesale — pass the full `recipes[]`):
   ```
   node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"raster\",\"visual_system\":{\"world_bible\":\"...\",\"palette\":[...],\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\",\"prompt_scaffold\":\"...\",\"style\":{\"checkpoint\":\"...\",\"loras\":[...],\"style_prompt\":\"...\"}},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\",\"recipes\":[{\"name\":\"hero\",\"checkpoint\":\"...\",\"prompt\":\"...\",\"negative\":\"...\",\"seed\":123,\"sampler\":\"euler\",\"steps\":24,\"cfg\":7,\"master_resolution\":1024,\"layerdiffuse\":true,\"import_settings\":{\"mipmaps\":true,\"filter\":\"linear\",\"compression\":\"lossless\"}}]}}"
   ```
   (For `svg`, set `method:"svg"` and omit `style`/`prompt_scaffold`/`recipes`.)
3. Validate the manifest (still `playable` at this point): `node tools/manifest.mjs validate <id>` → expect `<id> OK`.

## Hand off to the validator
Do **not** set `styled` yourself. Hand off to `validator`, which re-runs the same gates on the rewired game (headless import + run clean; `selftest.gd` still `SELFTEST OK` if present; human A/B playtest) and advances `playable → styled` on success, or records legible `issues` (attributed almost always to `asset`) and stops on failure.

## Notes
- The `--import` pass must run before the validator's headless run, or `load("res://art/...")` returns null at runtime.
- If a re-skin looks *worse* or incoherent, that's a finding about the **visual system** (Step 0), not the individual files — fix the system and re-derive, don't patch one asset.
