# POC run 008 — M1.5 `asset` raster method (style A, painterly): re-skin of `creature-0001`

**Date:** 2026-05-31 · **Skill exercised:** `asset` (raster method) + `validator` (Method 3, PNG) · **Target:** `creature-0001` ("Glade Spirit"), the set's first **representational/painterly** `validated` title — built specifically as the raster proof target (a soft forest-spirit, organic thorn hazards, an autumn glade), exactly the art SVG does badly.

This is the first of M1.5's two style-distinct proofs (§9). It runs the `asset` skill's **raster** method end-to-end on a real title: derive a per-game style profile, generate RGBA sprites locally via ComfyUI + SDXL + LayerDiffuse through `tools/comfy.mjs`, rewire the immediate-mode `_draw()` to textures, and convert every felt gap into a concrete `SKILL.md` edit — the same mechanism as runs 001–007, now on locally-generated raster art. Run 009 (`crosser-0001`, pixel-art, style B) is the deliberately-contrasting second proof; the pair is the "one system, two distinct looks" evidence the milestone needs.

> **Status: `validated` (held).** The programmatic gate passed; the **owner A/B playtest + IP-safety sign-off are pending** (see [A/B](#ab) and [Success criteria](#success-criteria-9--11)). `validated → styled` is intentionally illegal — `playable` is the required intermediate gate, reached only by an owner playtest.

## What ran

Following `.claude/skills/asset/SKILL.md` (raster method):

1. **Confirmed the stack** — `node tools/comfy.mjs --check` against the local ComfyUI server (RTX 5080, ComfyUI v0.3.16, Juggernaut XL v9 + ComfyUI-layerdiffuse with the gate's no-invert join-patch, torch 2.11+cu128). The feasibility gate (see `docs/superpowers/m1.5-feasibility-notes.md`) had already cleared the LayerDiffuse decoder; throughput ~20–40 s per 1024² master.
2. **Derived the style profile + visual system first** (Step 0, raster): chose a painterly/storybook SDXL profile from `concept.art_direction`, fixed a shared prompt scaffold + sampler/steps/cfg, and wrote the palette/form/shading/scale system down before generating anything. Recorded verbatim in `asset_pass.visual_system` (incl. `.style` and `.prompt_scaffold`).
3. **Generated the raster sprites** — `node tools/comfy.mjs gen creature-0001 spirit '<recipe>'` and `… hazard '<recipe>'` → `games/creature-0001/art/{spirit,hazard}.png` (RGBA, transparent background). One recipe per PNG, identical sampler/steps/cfg, recorded in `asset_pass.recipes[]`.
4. **Decided mixed-method for the seed** — the `seed` pickup was deliberately **left primitive** (a procedural glow-mote), a recorded `left_primitive` choice; see [Iteration](#iteration-history). The parallax tree background also stays procedural (depth/motion, not a hero asset).
5. **Imported with explicit mobile settings** — `godot --headless --path games/creature-0001/ --import` to make the `.png.import` sidecars, then set each to mobile-grade (`mipmaps=true`, `LINEAR_WITH_MIPMAPS` filter, lossless compression) and re-imported.
6. **Rewired the game** — replaced the spirit's and hazard's `_draw()` primitives with `draw_texture_rect()` *in place* inside the existing single-`_draw()` loop (z-order, screen-shake transform, and squash/stretch preserved for free). Removed the hazard's oversized procedural glow-halo (it read as a disc behind the larger sprite). Movement, collision, spawning, scoring, streak combo, difficulty ramp, and game-over/restart are byte-for-byte unchanged.
7. **Recorded the pass** — `assets[]` flipped to `origin:"raster"` for `spirit`/`hazard` (`seed` left `origin:"primitive"`); `asset_pass` block populated with the style profile, scaffold, and both recipes; `node tools/manifest.mjs validate creature-0001` → OK.
8. **Re-validated (programmatic gate)** — headless run clean (zero `SCRIPT ERROR`/`ERROR:`/"Failed to load"), `selftest.gd` still `SELFTEST OK`. **Visual-verified** by composing a play frame with a `SceneTree` screenshot harness on the real Vulkan renderer (not `--headless`, whose dummy renderer can't capture pixels — see the raster method's note) and inspecting the result.

## The style profile + visual system (the real deliverable)

A different game looks different because it **picked a different profile** — that choice is the milestone's whole point, recorded so it is reviewable and reusable.

| Axis | Decision |
|---|---|
| **Style profile** | Checkpoint `juggernautXL_v9.safetensors`, **no LoRA**. Style prompt: *painterly storybook illustration, soft hand-painted brushwork, cozy childrens book art*. |
| **Prompt scaffold** | `painterly storybook illustration, soft hand-painted brushwork, cozy childrens book art, warm autumn woodland palette of amber rust and gold, soft diffuse magical lighting, single centered subject, full body, clean transparent background, high detail,` — every sprite = scaffold + actor subject, so the set reads as one family. |
| **Palette** | `#0E2E10` deep forest-green field · `#F2B34D` warm amber spirit · `#FFE026` bright gold seed-mote · `#9E3B2E` rust thorn (danger) · `#2A2A1E` charcoal hazard body. |
| **Form** | Soft rounded painterly storybook creatures; deliberate silhouette contrast between the smooth round amber hero and the spiky bristled dark hazard, so threat reads at a glance. |
| **Shading** | Painterly soft-brushwork with soft diffuse magical lighting on the creatures; flat dark procedural field + parallax tree silhouettes behind. |
| **Scale** | 1024² masters for spirit + hazard, downscaled at runtime to ~110 px / ~92 px footprints; mipmaps on, `LINEAR_WITH_MIPMAPS`, lossless (2 sprites). |

Re-skinned (raster): **spirit, hazard**. Left primitive (deliberate, recorded): **seed** (procedural glow-mote — see below), **background** (parallax tree silhouettes — depth/motion, not a hero asset).

### Recipes (provenance)

| Sprite | seed | sampler | steps | cfg | master | LayerDiffuse | subject (after scaffold) |
|---|---|---|---|---|---|---|---|
| `spirit` | 101 | euler | 24 | 7.5 | 1024² | yes | *a small round cute glowing forest spirit creature, fluffy amber body, big friendly eyes, gentle soft inner glow, adorable* |
| `hazard` | 323 | euler | 24 | 7.5 | 1024² | yes | *a small round menacing thorn monster, compact solid spiky ball-shaped creature densely covered in sharp rust-red and charcoal thorns, two glowing angry yellow eyes, dangerous bramble beast, floating isolated* |

Both negatives carry the IP guards (`logo, watermark, text, trademarked character, brand, celebrity likeness, …`); the hazard negative additionally excludes the over-elaboration terms learned during iteration (`ring, wreath, circle, hollow, crown, donut, … ground, floor, shadow, autumn leaves, scene`). The committed **PNG is canonical**; recipes are provenance, not a bit-exact regeneration guarantee (GPU matmul + RNG are non-deterministic).

## Iteration history

- **`spirit` — accepted on pass 1.** The scaffold + subject produced a coherent, adorable amber forest-spirit with clean transparent alpha straight away.
- **`hazard` — 3 passes.** (1) cute-fox-with-a-ground-shadow (too friendly, and the shadow broke the transparent-isolate); (2) a hollow thorn-*wreath* (the prompt invited a decorative ring); (3) a solid spiky thorn-critter — accepted. Fix that landed it: pin "single centered subject … floating isolated" in the positive and push `ring/wreath/circle/hollow/ground/shadow/scene` into the negative.
- **`seed` — 4 passes, then left primitive (mixed-method).** SDXL repeatedly over-elaborated a ~14 px glowing dot: autumn-leaf scene → wreath → hanging ornament → row-of-blobs. A procedural glow-mote (`draw_circle` core + halo + white sparkle + pulse) is the higher-quality pickup and is exactly what immediate-mode does best. Recorded as `left_primitive` — a legible choice, not a silent gap.
- **Glow-halo cleanup.** The hazard's old procedural glow-halo had been sized for the small primitive blob; behind the larger raster sprite it read as an odd disc, so it was removed along with the primitive draw call.

## A/B

> **PENDING OWNER.** The owner A/B playtest is the gate that advances `playable → styled` and is the IP-safety review (§10: "the art itself is gated by the human A/B playtest — not automatable"). Re-skin frames were rendered via the `SceneTree` screenshot harness (real Vulkan renderer, RTX 5080) and sent to the owner for review; the committed before/after pair for this report is captured at sign-off.

| Before (primitive `_draw`) | After (raster re-skin) |
|---|---|
| _pending — `img/poc-run-008-before.png`_ | _pending — `img/poc-run-008-after.png`_ |

**Expected read (for the owner to confirm):** the after-frame should read as one coherent painterly storybook scene — a soft glowing amber spirit and a bristled, unmistakably-threatening thorn beast that share one illustrated language, gliding over the procedural autumn field with the gold seed-mote still popping as a primitive. It must play identically (logic untouched; headless run clean; `SELFTEST OK`), and nothing may resemble protected IP.

## Findings — each attributable to specific `asset` SKILL.md prose (the POC value)

This run **originated** three of the reusable raster lessons; all three are now folded into `.claude/skills/asset/SKILL.md` (commits `c5f973d`, `426ceb6`).

1. **[Prompt scaffolding] An unconstrained subject invites a scene, and the negatives don't fire.** The hazard and (especially) the seed came back as wreaths/ornaments/leaf-scenes because the positive prompt itself implied multiplicity/decoration. → **Edit applied:** Step 0(b) now mandates `"single centered subject, full body, clean transparent background"` in the shared scaffold and pushes `scene, multiple characters, frame, border, ring, wreath, ground, floor, shadow` into the shared negative.
2. **[Mixed-method] A tiny effect-like actor fights the medium — make it primitive.** The ~14 px seed never rendered cleanly across 4 tries; a procedural glow-mote is strictly better. → **Edit applied:** "Mixed-method honesty" now says to vary in order (subject phrase → `master_resolution` 1024→512→256 → `cfg` ±1) and, after 3–4 variations without a clean output, leave the actor primitive and record the finding.
3. **[Rewire craft] A glow-halo sized for the old primitive reads as a disc behind a bigger sprite.** → **Edit applied:** the Rewire step now calls out removing stale glow-halos along with the primitive draw call.

Two structural confirmations (no edit needed, but worth recording):

4. **`draw_texture_rect()`-in-place was the right swap for the builder's single-`_draw()` architecture** — preserved z-order, the shake transform, and squash/stretch with zero node-tree surgery (the run-007 finding #1/#2 generalization held for raster).
5. **The feasibility gate's pins were load-bearing.** With ComfyUI v0.3.16 + the no-invert join-patch + torch cu128 in place, LayerDiffuse produced vivid, correctly-isolated RGBA on the first generation — no haze, no gray-interior. The stack-version sensitivity documented in the skill is real and the documented pins are correct.

## Success criteria (§9 / §11)

1. ✅ The `asset` **raster** method ran the full re-skin — recipe → `comfy.mjs` gen → import → rewire → record — producing committed RGBA PNGs and a populated `asset_pass`.
2. ✅ Art style applied as a **first-class per-game profile** (painterly Juggernaut, no LoRA), recorded verbatim; this is style A of the two-style proof, chosen to contrast maximally with run-009's pixel-art.
3. ✅ **Mobile-grade per asset** — 1024² masters, explicit mobile import settings (mipmaps + linear-mip + lossless), downscale-from-master.
4. ✅ Re-skinned game imports + runs **headless clean**; `selftest.gd` still `SELFTEST OK`; logic untouched. Visual-verified via the screenshot harness.
5. ✅ Manifest carries `asset_pass` (style + scaffold + 2 recipes) + `origin:"raster"`/`"primitive"` entries and is `validate`-OK; **status correctly held at `validated`** (the `validated → styled` jump is illegal by design).
6. ✅ Every shortfall is legible and attributed to specific `asset` prose, with the exact edit it implies — and the three edits are applied.
7. ⏳ **PENDING OWNER** — ~60 s playtest → `playable`, then human A/B + **IP-safety sign-off** → `styled`. Until then the run is not "styled" and this report's A/B + IP-safety lines stay open.

## Next

- ⏳ **Owner gate:** playtest `creature-0001` (~60 s) → `playable`; then A/B vs. the primitive original + IP-safety review → `styled`. Capture the before/after frames into `docs/superpowers/img/poc-run-008-{before,after}.png` and fill the [A/B](#ab) + criterion 7 at sign-off.
- ✅ Findings #1–#3 already folded into `.claude/skills/asset/SKILL.md` (the run's real deliverable).
- ➡️ Pairs with **`poc-run-009.md`** (`crosser-0001`, pixel-art, style B) — same skill + tool, different profile — for the "one system, two distinct looks" milestone evidence.
