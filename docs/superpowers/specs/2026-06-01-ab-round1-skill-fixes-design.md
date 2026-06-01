# A/B-Round-1 skill fixes — design

**Date:** 2026-06-01
**Status:** approved (owner)
**Origin:** A/B Round 1 (`main`@`8531b06`) surfaced 4 recurring skill gaps (2 asset, 2 audio) across two genres (creature-0001, crosser-0001). This spec fixes the responsible `SKILL.md` prose, with two additive schema fields to record the new derived systems.

## Problem (the 4 findings, verbatim cause)

Recorded in each proof manifest's `validation.issues`:

1. **asset — within-game visual INCOHESION.** Sprites are generated from independently-derived subjects with no shared world/character design language: creature shows a fox vs thorns; crosser shows a sci-fi **cyan robot** hero vs a fantasy **red ogre/demon** hazard. The existing raster `prompt_scaffold` + `style` pin only the *rendering style* (painterly, palette, params) — they never pin the *fictional world or character family* the subjects belong to. So two sprites can be individually clean yet read as different worlds.
2. **asset — background never re-skinned.** `asset_pass.recipes` only cover hero/hazard; the background stays flat primitive bands, so sprites float on untextured primitives, breaking the one-rendered-system goal. Static themed backdrop is in-principle asset scope; scrolling/parallax/animation is M1.7.
3. **audio — SFX not theme-bound.** SFX default to an aggressive/electronic/explosive character regardless of theme — wrong for *both* the cozy-woodland creature AND the bright-arcade crosser (the contrast proves it's a generic default, not a one-off mismatch). §1 derives a `mood_prompt`/`style_descriptors` (which steer the *music* mood) but nothing pins the *SFX timbre/material*, and §3's "short, **punchy**" default biases toward explosive transients.
4. **audio — BGM never plays.** Probe-confirmed `MusicAmbient.playing=false, pos=0` after 90 frames. Root cause: the looping bed's `play()` is called synchronously inside `_ready` immediately after `add_child` (`_setup_audio`), which does not reliably start an `AudioStreamPlayer` that frame; SFX work because they fire later in gameplay. Secondary: the bed was also mixed ~13 dB under SFX.

## Decisions (owner)

- **Background (finding #2): M1.7-deferred.** No background generation in this work. The asset skill must *record* the missing-backdrop gap honestly (in `left_primitive` + `notes`) rather than silently omit it. Static-backdrop generation waits for the M1.7 animation/backgrounds milestone.
- **Capture (findings #1, #3): recorded fields.** Add two optional schema fields with vitest, consistent with how `visual_system` already records the system verbatim — so the bible/sonic-character are reviewable, critique-able artifacts, not just prose.
- **World bible is method-neutral.** Lives in asset Step 0 and applies to both `svg` and `raster` (robot-vs-ogre divergence is possible in SVG too). Raster binds it hardest (per-recipe subjects), but the derivation is shared.
- **No manifest backfill.** creature-0001/crosser-0001 were generated under the old skills; inventing post-hoc bibles would be dishonest. Their `validation.issues` already document the gaps.

## Scope

Edits only to:
- `schema/manifest.schema.json` — 2 new optional string fields.
- the schema vitest (the existing `asset_pass`/`audio_pass` schema tests) — accept-with / accept-without / reject-unknown-sibling.
- `.claude/skills/asset/SKILL.md` — findings #1, #2.
- `.claude/skills/audio/SKILL.md` — findings #3, #4.

No tool changes, no background generation, no `concept`/`builder` edits, no manifest backfill. vitest stays green (currently 136/136; +2–3 schema tests expected).

## Part A — Schema

Inside the existing `additionalProperties:false` objects:

1. `asset_pass.visual_system.world_bible` — `{ "type": "string" }`, optional. The shared world/character design language derived from `concept.theme` that every sprite is an instance of.
2. `audio_pass.audio_system.sonic_character` — `{ "type": "string" }`, optional. The SFX sound-material/timbre vocabulary derived from `concept.theme` that every SFX recipe is bound to.

Both optional → all 9 committed manifests stay valid. Tests mirror the existing symmetric pattern: a manifest with the field validates; one without it still validates; an unknown sibling field is rejected (proves `additionalProperties:false` still bites).

## Part B — `asset/SKILL.md`

### Finding #1 — world/character bible (Step 0, method-neutral)
Add a sub-step to **Step 0 — Derive the visual system FIRST**, before palette/form/etc., applying to *both* methods:

> **Derive the world/character bible first.** From `concept.theme.setting` + `premise`, pin **one fictional world and one character family** before writing any entity's subject or silhouette. Every actor — hero, hazard, pickup — is an *inhabitant of that one world*, drawn from that one family (same materials, same era/genre, same "what kind of thing is this"). The hero and the hazard must read as belonging together (not a cyan robot vs a red ogre). This is the **subject-level** sibling of the style/scaffold cohesion below, which pins only *how things are rendered*, never *what world they're from* — the gap that let two individually-clean sprites read as different worlds. Record it verbatim in `asset_pass.visual_system.world_bible`.

Then, in the **raster** Step 0(b)/per-entity flow, bind every recipe subject to the bible: a recipe's subject is "*this actor as a member of the world_bible's family*", composed onto the shared scaffold — never a free-standing subject. Add to the existing "each sprite is fine but they don't cohere" note that subject-world divergence (not just style divergence) is a `world_bible` finding.

For **svg**, fold the bible into the existing Step 0 form-language guidance: the one signature silhouette per actor must be a variation *within the one character family*, not an unrelated shape.

### Finding #2 — record the background gap
Strengthen the existing "**c) What stays primitive**" / backgrounds prose: when the background is left as a primitive (the M1.7-deferred default), it **must** be recorded in `left_primitive` + called out in `asset_pass.notes` as a known cohesion gap deferred to M1.7 (static themed backdrop), never silently omitted. A sprite set floating on untextured primitive bands undercuts the one-rendered-system goal, and that must be a legible recorded choice.

## Part C — `audio/SKILL.md`

### Finding #3 — SFX sonic character (§1 + §3)
- **§1:** add `sonic_character` to the derived `audio_system`: from `concept.theme`, pin the SFX **sound-material/timbre vocabulary** (the audio sibling of the visual `world_bible`). Examples: a cozy/organic theme → "soft organic wooden/leaf/cloth taps, gentle, no electronic transients"; a retro/arcade theme → "crisp 8-bit square/triangle-wave blips, clean chip transients". Record verbatim in `audio_pass.audio_system.sonic_character`.
- **§3:** every SFX recipe prompt = `mood_prompt` + `sonic_character` + the clip-specific event description. Reframe the "short, **punchy**, single sound" default: the *envelope* (short, single-shot, ~1–2 s) stays theme-neutral, but the *timbre/material* MUST come from `sonic_character` — do not default to punchy/explosive transients. Make the SFX negative prompt theme-aware (e.g. a cozy theme excludes "explosion, harsh, distortion, aggressive, electronic"; an arcade theme keeps chip transients but still excludes "explosion, noise burst"). Note explicitly that an aggressive/explosive SFX character that ignores `sonic_character` is the finding #3 failure and is attributable to this step.

### Finding #4 — BGM must actually play (§5 + hard req)
- **§5:** replace "Music: `play()` on scene ready / loop start" with the working pattern: start the looping bed via **`autoplay = true` set on the `AudioStreamPlayer` before `add_child`**, or a **deferred/awaited `play()`** a frame after `add_child`. State the failure mode explicitly: an immediate in-`_ready` `play()` called the same frame as `add_child` does **not** reliably start the stream (probe-confirmed `playing=false`); SFX escape this only because they fire later.
- **Levels:** the music bed must be audible but sit sensibly under SFX — set `volume_db` deliberately (the proof had the bed ~13 dB under *and* not playing). Avoid burying it.
- **Verification:** add a line (hard requirements / hand-off) that the validator/owner must confirm the bed is *actually playing* (`playing=true`, advancing position), not merely wired — the probe pattern that caught this.

## Out of scope / honest boundaries
- **No backfill** of the new fields into existing proof manifests.
- **Proving the fix is owner-gated A/B Round 2.** Re-running `asset`/`audio` needs ComfyUI+GPU (not CI). The autonomous deliverable here is the skill prose + schema + tests; the playtest that confirms the bible/sonic-character fix cohesion is a later owner A/B — the same autonomous/gated split as every prior milestone.

## Success criteria
- Schema has both optional fields; vitest green with the new accept/reject tests; all 9 committed manifests still validate.
- `asset/SKILL.md` derives a method-neutral world/character bible bound to every subject, and records the deferred-background gap.
- `audio/SKILL.md` derives an SFX `sonic_character` bound to every SFX recipe (no implicit explosive default) and starts the music bed with `autoplay`/deferred-`play()` at a balanced level.
- Every change is attributable to a specific finding; nothing claims the A/B itself is re-passed (that's owner-gated).
