# A/B-round-3 audio + art quality fix — calibrate → codify

**Date:** 2026-06-02
**Status:** approved design, pre-implementation
**Supersedes round:** A/B-round-2 (`main`@`d862c4e`) — which fixed cohesion (`world_bible`) and BGM *playback*, but left three quality gaps that owner playtests of creature-0001 + crosser-0001 exposed.

## Problem (grounded in owner playtests, 2026-06-02)

Both proof games were re-played after round 2. Cross-genre verdict:

| | creature-0001 (cozy raster) | crosser-0001 (chiptune pixel) | Read |
|---|---|---|---|
| Art cohesion | more cohesive (cats vs. evil cats) | maybe more cohesive (blob family) | ✅ `world_bible` works — keep |
| Art quality | "not great" | "terrible" | ❌ **systemic** raster quality |
| SFX | "explosive default sounds" | "aggressive explosions" | ❌ **systemic** — both genres |
| BGM | audible, "single toned … annoying" (drone) | "not single toned" but "grating" | ◐ playback fixed; content weak |

**Root causes (evidence, not guess):**
- **SFX harshness is generation params, not prompt wording.** Round 2's `sonic_character` fix operated at the prompt layer and the SFX are *still* explosive in both genres. Waveform analysis of the shipped clips: generated at **steps≈8** (under-denoised broadband noise — ZCR up to 8,866/s) **with a sharp percussive onset and no applied envelope** (`gameover` attack ≈25 ms, peak at 61 ms). The prompts/negatives are fine; the harshness lives below them. `genAudio` in `tools/comfy.mjs` writes ComfyUI's raw bytes with **no post-process seam** — so there is nowhere an envelope is applied today.
- **BGM content is weak** (drone in creature, grating in crosser) even though *playback* now works. Pad prompts collapse to static tone; needs evolving-texture prompts + per-genre seeds.
- **Raster art quality is low** in both. The asset skill's raster Step 0 exposes checkpoint/loras/style_prompt/steps/cfg/master-resolution but the current recipes yield poor output and there is no refine/hi-res pass.

## Principle (owner directive, 2026-06-02)

**Asset generation (raster) is the default for art. Do not fall back to SVG to dodge a quality problem.** SVG is reserved for cases with a genuinely good reason — a pure UI/HUD/geometric element where vector resolution-independence is a real win. The remedy for "terrible" raster is to **lift raster quality**, not retreat to vectors.

## Why empirical-first

Round 2 specced a fix from reasoning (prompt vocabulary) and only discovered it was the wrong layer at playtest. This round flips it: gather GPU evidence **before** committing skill changes. The codify plan is written only after the probe proves what works.

## Phase 0 — Calibration probe (interactive, GPU; produces evidence, no committed skill changes)

Requires ComfyUI booted (`node tools/comfy.mjs --check` green; free Ollama first; RTX 5080 / 16 GB ceiling).

**SFX (cheap — seconds each).** One cozy SFX (creature `collect`) + one chiptune SFX (crosser action), each generated at:

| variant | steps | post-process |
|---|---|---|
| A (baseline) | 8 | none |
| B | 50 | none |
| C | 100 | none |
| D | 50 | + prototype JS fade-in/peak-normalize envelope |

Pre-screen all via the waveform metrics that found the bug (ZCR / crest / onset); **owner makes the final "clean + on-theme" call.** Hypothesis: harshness = steps; "explosive" onset = the missing envelope.

**BGM (slower — ~1 min each).** creature: 2 variants (new seed; + an "evolving, slow-movement, layered" prompt to kill the drone). crosser: 1–2 variants (softer, lower-cfg to kill the grating).

**Art (slowest, murkiest — lift raster, no SVG retreat).** creature hero (storybook raster) at baseline vs. higher steps/cfg vs. **+ a refine/hi-res second pass**; crosser hero (pixel) similar. An SVG render stays only as a throwaway *sanity-check to see the gap*, never as the remedy. Claude views the PNGs and pre-ranks; **owner makes the aesthetic call.**

**Probe output:** a short evidence note (winning settings per thread) that feeds Phase 1. Throwaway clips/images live in a scratch dir, not committed.

## Phase 1 — Codify the winners (via writing-plans, after the probe)

- `tools/comfy.mjs`: add a **deterministic WAV post-process seam** (decode → fade-in attack + peak-normalize, optional trim-to-onset → re-encode) — pure, vitest-tested, mirroring the `package.mjs` pure-seam pattern. Applied to SFX inside `genAudio` (gated so music is untouched or handled separately).
- `audio/SKILL.md`: correct the SFX `steps` guidance to the probe winner; make the "envelope" a **real applied fade** (point at the new seam), not just a duration; BGM evolving-texture prompt guidance + per-genre seed note.
- `asset/SKILL.md`: bake the probe-proven raster defaults (params and/or a refine-pass step); re-tilt the method branch to **raster-default**, SVG reserved for clear geometric/UI cases with stated justification.
- Keep vitest green; add tests for the new envelope seam.

## Phase 2 — Regenerate + re-verify

Regenerate creature-0001 + crosser-0001 audio (and art if the probe yields a real lift), re-import, technical verify (selftest, headless run, non-headless audio probe `playing==true`, screenshot), then owner re-playtest → advance status (`styled→scored`, etc.) or iterate.

## Judging roles
- **Audio:** owner's ears decide; Claude pre-screens with waveform metrics.
- **Art:** Claude views + pre-ranks the candidates; owner makes the aesthetic call.

## Out of scope
- Background re-skin (M1.7-deferred). Android APK gate (separate owner-gated feasibility step). OGG-for-music migration (noted as a future cleaner BGM path, not this round).

## Success criteria
- SFX no longer read as "explosive" in either genre (owner-confirmed); the cause is fixed at the generation/post-process layer, not the prompt.
- BGM is a pleasant non-drone, non-grating loop in both.
- Raster art is materially better (owner-confirmed) via lifted raster, not SVG fallback.
- The fixes are codified in the skills + a vitest-tested `comfy.mjs` seam, so the *next* game benefits — the deliverable is better skills, not just these two games.
