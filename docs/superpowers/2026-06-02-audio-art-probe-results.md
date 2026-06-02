# A/B-round-3 probe results (calibration evidence for Phase-1 codify)

Live GPU calibration, owner judging by ear. Feeds the codify phase of
`specs/2026-06-02-audio-art-quality-fix-design.md`.

## AUDIO — LOCKED (owner-confirmed 2026-06-02)

### Root-cause findings (transferable skill lessons)
1. **SFX steps≈8 = broadband noise** = the "explosive/aggressive/gunshot" sound (ZCR up to 8.9k/s). **steps 50–100 → clean tone** (crosser coin ZCR 7506→782). The round-2 prompt-vocabulary fix could never work — wrong layer.
2. **SFX need a deterministic post-process envelope** (none existed; `genAudio` wrote raw bytes). Prototype that worked: **trim-to-event** (find first/last sample above −32 dB of peak, ±8 ms pad) → **loudness-normalize** to ~RMS 0.13 with a 0.97 peak clamp → **fade-in 6 ms / fade-out 40 ms**. Trimming the silence/pad is what makes a clip perceptibly loud; peak-normalize alone left them "too quiet."
3. **Cozy SFX timbre must name a concrete warm instrument.** Generic "bright wooden bell chime" / music-box / celesta read as "irritating tings." **Kalimba / thumb-piano (warm wooden pluck) = the cozy winner.**
4. **BGM: ambient/pad/sustained prompts collapse to a DRONE.** Fix = force a **plucked MELODY** + aggressive anti-drone negatives (`drone, pad, sustained, monotone, single note, held note, atmosphere, texture`) + **cfg 8**. Register matters too: cozy wants **low/warm** — add `high pitched, shrill, tinny, bright` to negatives.
5. Chiptune (crosser) is naturally melodic → a **mellow chiptune** prompt (cfg 6) worked first try once de-harshened.

### Locked settings
- **creature SFX:** kalimba/mbira warm-wooden-pluck timbre; steps 55, cfg 6, dur ~1.2s; + envelope seam. (negatives incl. explosion/harsh/electronic/gunshot)
- **creature BGM:** fingerpicked nylon-guitar lullaby, **low warm register**, simple repeating melody; steps 50, cfg 8; anti-drone + anti-high-pitch negatives. (winning probe: `_probe_bgm_creature_folklow`, seed 311)
- **crosser SFX:** clean square-wave chiptune; steps 100; + envelope seam.
- **crosser BGM:** mellow chiptune melody, soft square/triangle; steps 50, cfg 6. (winning probe: `_probe_bgm_crosser_mellow`, seed 202)
- **envelope seam (all SFX):** trim-to-event → loudness-normalize (RMS target + peak clamp) → fade-in 6 ms / fade-out 40 ms. To become a pure, vitest-tested `comfy.mjs` function applied in `genAudio` for `kind:"sfx"`.

### Audition tooling note (operational)
Hot-hardware audition done via `%TEMP%\play-*.ps1` (Core Audio endpoint-volume duck). Comfortable master ≈ **0.12** for loudness-normalized (~RMS 0.12–0.13) clips; the old too-quiet clips needed it and the steps-8 "gunshot" was too loud even at 0.05. Level-match candidates before auditioning so timbre (not volume) is judged.

## ART — probe done, KEY REFRAME (2026-06-02)

**The sprites are NOT the problem — empirical-first caught this before we tuned the wrong layer.**

- Probed creature hero (spirit) across sampler/steps (euler@24 vs dpmpp_2m@40 vs dpmpp_2m_sde@45, fixed seed). All three look like competent cute watercolor storybook creatures — **only marginal** difference. The hero is already decent.
- Viewed the shipped crosser pixel sprites (cyan blob hero, red ogre-blob hazard) in isolation: also **competent pixel art**, not "terrible." Pipeline already correct: `size_limit=128`, `TEXTURE_FILTER_NEAREST`, exact-fit tiled hazards (no stretch).
- **Captured in-game screenshots** (creature `store/screenshots/screen-1.png`; crosser `store/screenshots/probe-shot.png` — a THROWAWAY, delete on cleanup). These reveal the real causes of "terrible/not great":
  1. **Flat primitive backgrounds** — creature = dark-green void + flat tree/dot shapes; crosser = solid-color Frogger lanes. **No environment art** → whole frame reads cheap, regardless of sprite quality. (= the **M1.7-deferred background re-skin**.)
  2. **Hero too small** — crosser cyan hero is tiny next to the red hazards; creature fox is a small detail in a big empty field.
  3. **Detail mismatch** — detailed/painterly/pixel sprite floating on flat color blocks looks incongruous.

**Conclusion: tuning sprite *generation* (sampler/steps/refine/checkpoint) is LOW ROI — sprites are fine.** Art quality lives in the **backgrounds + composition/sizing.**

### ⏸ PENDING OWNER DECISION (the question being asked when the session was reset) — art fix scope:
- **(A, recommended) Backgrounds + sizing:** generate real environment/background art (opens the M1.7-deferred background-generation capability the `asset` skill lacks) to replace the flat blocks, AND scale up heroes / fix composition. The substantive fix.
- **(B) Sizing/composition only:** scale up heroes, tidy placement/contrast, keep flat backgrounds. Fast, partial.
- **(C) Also tune sprite gen:** low ROI; doesn't touch the real problem. Only as an add-on.

Sampler note for whenever sprite gen IS revisited: scheduler is hardcoded `"normal"` in `tools/comfy-templates/sdxl-layerdiffuse.json` KSampler; no `%scheduler%` token in `comfy.mjs` TOKENS — adding one (default "normal", recipes opt into "karras") is the cheap lever, plus there is no refine/hi-res pass in the template.
