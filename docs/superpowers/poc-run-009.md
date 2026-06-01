# POC run 009 — M1.5 `asset` raster method (style B, pixel-art): re-skin of `crosser-0001`

**Date:** 2026-05-31 · **Skill exercised:** `asset` (raster method) + `validator` (Method 3, PNG) · **Target:** `crosser-0001` ("Pixel Hop"), the set's **pixel-art / retro** lane-crossing hopper — built as M1.5's style-B proof, a deliberately **hard-edged** look chosen to contrast maximally with run-008's soft painterly creatures.

This is the **second** of M1.5's two style-distinct proofs (§9), and the decisive one: it runs the **same `asset` skill and the same `tools/comfy.mjs`, unchanged** — only the per-game **style profile** differs (a pixel-art LoRA + nearest-filter import instead of a painterly checkpoint). Run-008 + run-009 together are the core milestone evidence: **one system, two deliberately different looks, each internally cohesive.** Per the compounding-findings pattern (§9), this report also records whether run-008's findings carried forward — i.e. whether the *edited* prose held.

> **Status: `validated` (held).** The programmatic gate passed; the **owner A/B playtest + IP-safety sign-off are pending** (see [A/B](#ab) and [Success criteria](#success-criteria-9--11)). `validated → styled` is intentionally illegal — `playable` is the required intermediate gate.

## What ran

Following `.claude/skills/asset/SKILL.md` (raster method), identical path to run-008 — only the profile and import settings differ:

1. **Confirmed the stack** — `node tools/comfy.mjs --check` (same RTX 5080 / ComfyUI v0.3.16 / Juggernaut v9 + LayerDiffuse + join-patch / torch cu128 as run-008; ComfyUI was left running on `:8188`).
2. **Derived the pixel-art profile + visual system first** (Step 0, raster): from `concept.art_direction` chose Juggernaut v9 **+ the `pixel-art-xl` LoRA**, a hard-edged retro scaffold, and a NES-ish limited palette. The `%lora%`-bearing template (`sdxl-layerdiffuse-lora`) is selected automatically because the recipe sets `lora`.
3. **Generated the raster sprites** — `node tools/comfy.mjs gen crosser-0001 hero '<recipe>'` and `… hazard '<recipe>'` → `games/crosser-0001/art/{hero,hazard}.png` (RGBA). Identical sampler/steps/cfg across both; recorded in `asset_pass.recipes[]`.
4. **Imported for crisp pixels** — `godot --headless --path games/crosser-0001/ --import`, then set each `.png.import` to the **pixel-art recipe**: downscale the 1024² master to 128 px via `process/size_limit=128`, `TEXTURE_FILTER_NEAREST`, **mipmaps off**, lossless; re-imported. (See [the crispness technique](#two-techniques-this-run-pinned-down).)
5. **Rewired the game** — replaced the hero's and hazard's `_draw()` primitives with `draw_texture_rect()` in place inside the existing single-`_draw()` loop (z-order, hop-pop, shake preserved). The variable-width hazard bars use the **exact-fit tiling** technique below. Lanes, goal row, HUD, and the faint pixel grid stay procedural (flat retro bands — correct for the aesthetic, recorded as `left_primitive`). Tap-hop, swipe-sidestep, per-lane scroll, collision, crossing/score, speed-streak, difficulty ramp, and game-over/restart are byte-for-byte unchanged.
6. **Recorded the pass** — `assets[]` flipped to `origin:"raster"` for `hero`/`hazard`; `asset_pass` populated with the profile, scaffold, and both recipes; `node tools/manifest.mjs validate crosser-0001` → OK.
7. **Re-validated (programmatic gate)** — headless run clean, `selftest.gd` still `SELFTEST OK`. **Visual-verified** via the `SceneTree` screenshot harness on the real Vulkan renderer (RTX 5080), as in run-008.

## The style profile + visual system (the real deliverable)

| Axis | Decision |
|---|---|
| **Style profile** | Checkpoint `juggernautXL_v9.safetensors` **+ LoRA `pixel-art-xl.safetensors`**. Style prompt: *pixel art sprite, pixelated, 8-bit retro video game character, crisp hard-edged chunky pixels, limited bright retro NES palette*. |
| **Prompt scaffold** | `pixel art sprite, pixelated, 8-bit retro video game character, crisp hard-edged chunky pixels, limited bright retro NES palette, clean single centered subject, full body, flat colors, clean transparent background,` |
| **Palette** | `#0F0F1A` near-black border · `#2EA02E / #7D4F26 / #404048` NES grass/dirt/road lane bands · `#19CCD9` cyan hero · `#E63A33` red hazard demon (danger) · `#F2D90F` goal-row yellow. |
| **Form** | Hard-edged blocky pixel-art sprites; a chunky upright cyan robot hero vs. a red horned demon hazard — deliberate hard silhouette + complementary cyan/red contrast so threat reads instantly. |
| **Shading** | Flat limited-palette pixel shading, crisp hard pixel edges (no gradients/antialias); procedural flat lane bands + faint pixel grid behind. |
| **Scale / crispness** | 1024² masters → `process/size_limit=128` on import → drawn at 64 px (clean ÷2) with `TEXTURE_FILTER_NEAREST`, **mipmaps off** = crisp pixels. Hero ~64 px centered on its cell; each variable-width hazard bar tiled with exact-fit units (below). |

Re-skinned (raster): **hero, hazard**. Left primitive (deliberate, recorded): **background, lanes, goal_row** — flat retro bands are the correct aesthetic, not a shortfall.

### Recipes (provenance)

| Sprite | seed | LoRA | sampler | steps | cfg | master | import |
|---|---|---|---|---|---|---|---|
| `hero` | 401 | pixel-art-xl | euler | 24 | 7.5 | 1024² | nearest, no-mips, lossless |
| `hazard` | 402 | pixel-art-xl | euler | 24 | 7.5 | 1024² | nearest, no-mips, lossless |

Subjects (after scaffold): hero = *a cute chunky cyan robot creature hero, bright cyan and teal body, big friendly square eyes, blocky pixel character, brave*; hazard = *a menacing angry red pixel monster creature, blocky red and dark-red hazard beast, spiky hard-edged, evil glowing eyes, dangerous*. Both negatives carry the IP guards plus the anti-smooth terms that enforce the hard-edged look: `smooth, blurry, antialiased, soft, painterly, gradient, realistic, photo, 3d render`. The committed **PNG is canonical**; recipes are provenance, not bit-exact.

## Iteration history

- **`hero` — accepted on pass 1.** The `pixel-art-xl` LoRA + the hard-edged scaffold nailed a chunky cyan robot with clean transparent alpha first try.
- **`hazard` — accepted on pass 1.** Same — a blocky red demon, instantly readable as the threat against the cyan hero.

Both sprites landing on pass 1 is itself the headline finding (below): run-008's prompt-constraint and anti-scene edits, now baked into the scaffold, prevented the wreath/scene failures that cost run-008 three hazard passes.

## Two techniques this run pinned down

These became **lessons #4 and #5** in `.claude/skills/asset/SKILL.md` (and are the reason this run, not run-008, surfaced them):

1. **Variable-width actors → tile exact-fit units, never stretch.** The game scrolls hazard *bars* of continuous width (`CELL … CELL×3`); a single fixed-aspect demon sprite stretched to fill one would distort the pixels and decouple visual width from collision width. Instead each bar is filled with `N = round(w / HAZ_UNIT)` exact-fit demon units (`uw = w/N`) — a "pack of monsters." Visual width == collision width, and no sprite is ever stretched.
2. **Pixel-art crispness = `size_limit` downscale + `NEAREST`, in that order.** Drawing a raw 1024² master tiny with a nearest filter *aliases* badly (severe shimmer). The fix is to let Godot's importer resample the master down to 128 px first (`process/size_limit=128`), *then* draw it at 64 px with `TEXTURE_FILTER_NEAREST` and mipmaps off — the resample does the clean minification, nearest keeps the chunky pixels.

## A/B

> **PENDING OWNER.** The owner A/B playtest is the gate that advances `playable → styled` and is the IP-safety review (§10). Re-skin frames were rendered via the `SceneTree` screenshot harness (real Vulkan renderer, RTX 5080) and sent to the owner; the committed before/after pair for this report is captured at sign-off.

| Before (primitive `_draw`) | After (raster re-skin) |
|---|---|
| _pending — `img/poc-run-009-before.png`_ | _pending — `img/poc-run-009-after.png`_ |

**Expected read (for the owner to confirm):** the after-frame should read as a crisp retro pixel-art board — a chunky cyan robot hopping between flat NES-green/dirt lanes packed with rows of hard-edged red demons — visibly a *different* art identity from run-008's soft painterly woodland, yet produced by the same skill and tool. It must play identically (logic untouched; headless clean; `SELFTEST OK`), and nothing may resemble protected IP.

## Findings — compounding-findings record (§9)

The decisive question for run-009 is whether run-008's *edited* prose held. It did:

1. **[Findings carried forward — the headline] Both sprites landed on pass 1.** Run-008's edits (single-centered-subject scaffold + anti-scene/anti-smooth negatives, lesson #1) were already in the prose and in the scaffold this run inherited; the wreath/scene over-elaboration that cost run-008 three hazard passes simply did not recur. The edited prose paid off on the very next run — exactly the compounding the milestone wants.
2. **[Mixed-method awareness held] No actor needed downgrading here.** Lesson #2's discipline (leave an actor primitive when it fights the medium) was applied as a *check*: both hero and hazard suit raster, and the flat lanes/goal/grid correctly stay primitive — a mixed-method outcome reached deliberately, recorded in `left_primitive`, not by accident.
3. **[New — lesson #4] Variable-width actors need exact-fit tiling, not stretching.** Surfaced by the continuous-width hazard bars. → **Edit applied:** the Rewire step now documents the `N = round(w/unit)` tile-pack technique (visual width == collision width).
4. **[New — lesson #5] Pixel-art crispness is a two-step import recipe.** Surfaced by the 1024→tiny pixel-art requirement. → **Edit applied:** "Resolution & mobile density" now documents `process/size_limit` downscale **then** `NEAREST` (with the explicit anti-alias warning against raw-1024-tiny-nearest).
5. **[New — lesson #6, tooling] Tab-indented GDScript defeats exact-match edits.** Rewiring `Main.gd` (tab-indented) repeatedly failed the Edit tool's exact-match; a PowerShell line-index splice (read → reconstruct around the range → write back) was the reliable path. → **Edit applied:** the Rewire step now documents the splice snippet, noting `Get-Content`/`Set-Content` preserve tab indentation.
6. **[Profile generality confirmed] The same skill + same `comfy.mjs` produced a visibly distinct style** purely by swapping the profile (LoRA + nearest import) — the `%lora%` template auto-selection worked, and no skill/tool code changed between run-008 and run-009. This is the M1.5 thesis, demonstrated.

## Success criteria (§9 / §11)

1. ✅ The `asset` **raster** method ran the full re-skin with the **same skill + tool as run-008, unchanged** — only the style profile differed.
2. ✅ Art style applied as a **first-class per-game profile** (pixel-art LoRA + nearest import), recorded verbatim — style B, the deliberate hard-edged contrast to run-008's painterly style A.
3. ✅ **Mobile-grade per asset** — 1024² masters, explicit pixel-art import recipe (`size_limit`/nearest/no-mips/lossless), downscale-from-master.
4. ✅ Re-skinned game imports + runs **headless clean**; `selftest.gd` still `SELFTEST OK`; logic untouched. Visual-verified via the screenshot harness.
5. ✅ Manifest carries `asset_pass` (profile + scaffold + 2 recipes) + `origin:"raster"` entries and is `validate`-OK; **status correctly held at `validated`**.
6. ✅ **Compounding-findings recorded:** run-008's edits held (both sprites pass 1), and three new lessons (#4 tiling, #5 crispness, #6 splice) are surfaced and folded into the skill.
7. ⏳ **PENDING OWNER** — ~60 s playtest → `playable`, then human A/B + **IP-safety sign-off** → `styled`. Until then the run is not "styled" and this report's A/B + IP-safety lines stay open.

## Next

- ⏳ **Owner gate:** playtest `crosser-0001` (~60 s) → `playable`; then A/B vs. the primitive original + IP-safety review → `styled`. Capture the before/after frames into `docs/superpowers/img/poc-run-009-{before,after}.png` and fill the [A/B](#ab) + criterion 7 at sign-off.
- ✅ Lessons #4–#6 already folded into `.claude/skills/asset/SKILL.md` (commits `c5f973d`, `426ceb6`) — the run's real deliverable.
- 🎯 **Milestone evidence complete (pending the two owner A/Bs):** run-008 (painterly) + run-009 (pixel-art) demonstrate one unchanged system producing two cohesive, visibly distinct art identities — the M1.5 §9 thesis. After both owner A/Bs, finalize `poc-run-010/011` (if used for the styled milestone wrap) per the queue.
