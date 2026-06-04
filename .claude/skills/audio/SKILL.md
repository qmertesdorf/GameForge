---
name: audio
description: Use when giving a playable Godot game a coherent, prompt-derived audio identity — event SFX plus a looping music track — generated locally via ComfyUI + Stable Audio Open through tools/comfy.mjs. Derives an audio system from the concept, maps core-loop events to SFX, generates clips, wires AudioStreamPlayer nodes, records audio_pass, and advances status to "scored". Hands off to validator.
---

# Audio re-skin (local generative SFX + music)

Give a `playable`-or-better game an audio identity. Audio is orthogonal to the visual pass: a game may be `playable`, `styled`, or `scored` going in. The terminal status is `scored`; the `audio_pass` block — not the status string — is the source of truth for what was produced.

**Failure attribution (the POC value, same as `asset`):** a bad or absent clip is always attributable — a wrong event→SFX map, an unwired `AudioStreamPlayer`/signal, a clip that ignores `concept.theme`, or an *infra* failure in `comfy.mjs` (ComfyUI down) — never an unattributable gap. Each is a specific, fixable prose/recipe cause.

## Inputs
- `manifests/<id>.json` with a populated `concept` block (and `concept.theme`); game status is `playable`, `styled`, or `scored`.
- The game on disk at `games/<id>/`.
- ComfyUI reachable with Stable Audio Open installed: `node tools/comfy.mjs --check`. A failure here is *infra*, attributable to the stack — **stop** and ask the owner to start ComfyUI; never fake a clip.

## Outputs
- `games/<id>/audio/*.wav` — one committed clip per recipe (event SFX + a looping music track).
- Added `AudioStreamPlayer` nodes (+ their `*.wav.import` sidecars) wired to the mapped events.
- A populated `audio_pass` block and terminal `status = "scored"` (after step 6).

## Hard requirements
- **Game logic is untouched** — core loop, existing signals, and `selftest.gd` (if present) behave exactly as before. Audio only *adds* `AudioStreamPlayer` nodes + `play()` calls at existing signal points; it must not restructure the loop or break the self-test (the validator re-enforces this, Method 4).
- **Run `--import` after generating clips, before re-validation** (step 5b) — without the `.wav.import` sidecars the validator's headless run can't load the streams.
- **No new tool or dependency** — clips come from `tools/comfy.mjs`; wiring is plain GDScript/scene edits.
- **Do not** edit `concept`/`builder`/`asset`. Consume `concept.theme` as-is (reading it is not editing it).

## 1. Derive the audio system (do this first, once)
Read **`concept.theme`** — the title's modality-neutral world (premise/tone/mood_keywords/setting) — as the primary anchor, with `concept.genre` for form. The audio identity expresses the *same theme* the visuals do, sonically. Author a shared `audio_system`:
- `model`: `"stable-audio-open-1.0"`.
- `mood_prompt`: one shared mood sentence threaded into every clip prompt for coherence (the audio analog of the visual prompt scaffold), derived from `concept.theme`'s `tone` + `mood_keywords` — e.g. for a "cozy autumn-woodland" theme, "warm, organic, gentle woodland atmosphere".
- `style_descriptors`: 2–4 tags drawn from / consistent with `concept.theme.mood_keywords` (e.g. a "cozy/organic/storybook" theme → `["ambient", "soft", "acoustic"]`; a "retro/hard-edged/arcade" theme → `["chiptune", "8-bit", "upbeat"]`).
- `sonic_character`: the **SFX sound-material/timbre vocabulary** derived from `concept.theme` — the audio sibling of the visual world bible, and the thing that keeps SFX *on theme* instead of defaulting to generic explosive transients. Name the materials and timbre: a cozy/organic theme → name a **concrete warm instrument** — "kalimba / thumb-piano (warm wooden pluck), soft organic taps, no electronic transients" (a *generic* "bell chime"/music-box/celesta reads as irritating metallic "tings" — name a specific warm instrument instead); a retro/arcade theme → "crisp 8-bit square/triangle-wave blips, clean chip transients". Recorded verbatim in `audio_pass.audio_system.sonic_character`. **`mood_prompt`/`style_descriptors` steer the music mood; `sonic_character` governs the SFX** — both are required.

## 2. Map core-loop events to SFX
From `concept.core_loop` + the entity/signal set, list the discrete events that deserve a one-shot: typically a positive beat (collect/score), a negative beat (hurt/hit), a loss beat (game over), and the primary action (jump/hop/shoot). For each, record an `events[]` entry: `{ event, clip, node, signal }` where `node` is the `AudioStreamPlayer` you will add and `signal` is the Godot signal (or call site) that triggers it. Be honest: if an event has no SFX, leave it out and note it.

## 3. Author recipes
One recipe per SFX + one music recipe. Each prompt = `mood_prompt` + the clip-specific description. Defaults confirmed at the feasibility gate (`docs/superpowers/m1.6-feasibility-notes.md`):
- **SFX**: `kind:"sfx"`, `format:"wav"`, `duration_s` **1.0–2.0** (`EmptyLatentAudio` enforces a 1.0 s minimum — do not go below), `loop:false`, **`steps` 50–100** (cozy ≈55, chiptune ≈100), `cfg` ~5–6. **steps too low (≈8) is the explosive-SFX root cause** — under-denoised broadband noise (a high zero-crossing rate) reads as a gunshot; 50–100 yields a clean tone. Each SFX prompt = `mood_prompt` + **`sonic_character`** + the clip-specific event description; name the warm instrument (kalimba) for cozy themes, clean square/triangle chip for arcade. The **envelope is now a real, deterministic post-process applied automatically** by `comfy.mjs` `genAudio` to every `kind:"sfx"` clip (`envelopeSfxWav`: trim-to-event → loudness-normalize to RMS ~0.13 with a 0.97 peak clamp → fade-in 6 ms / fade-out 40 ms) — you do **not** hand-apply it, but you must still generate at 50–100 steps so the *content* is clean before the envelope shapes it. The negative prompt always excludes "music, melody, voice, speech", **plus a theme-aware exclusion**: a cozy/organic theme adds "explosion, harsh, distortion, aggressive, electronic, gunshot"; an arcade theme keeps chip transients but still excludes "explosion, noise burst". (cfg too high can clip the transient.)
- **Music**: `kind:"music"`, `format:"wav"`, `duration_s` 20–40, `steps` ~50, `loop:true`, `import_settings:{loop:true, loop_offset:0}`. **Force a plucked/repeating MELODY, never an ambient pad** — ambient/pad/sustained prompts collapse to a DRONE ("single-toned, annoying"). Use `cfg` **8** and add aggressive anti-drone negatives: `"drone, pad, sustained, monotone, single note, held note, atmosphere, texture"`. **Register matters**: a cozy theme wants a **low, warm** bed — add `"high pitched, shrill, tinny, bright"` to the negatives and name a warm instrument (fingerpicked nylon-guitar lullaby). A naturally-melodic style (chiptune) needs only a "mellow" framing at `cfg` ~6. Target loop-friendly content (steady repeating melody, no hard intro/outro) — seamless looping is imperfect for generative output (known limitation). Note: WAV music is uncompressed (~5 MB / 30 s stereo); acceptable for a milestone, OGG is a future size optimization.
- All recipes use `sampler:"dpmpp_3m_sde_gpu"` (scheduler `exponential` is baked into the template).
- **IP-safety**: never name artists or copyrighted tracks; negative prompt excludes "voice, speech, lyrics, vocals" for music unless intended. Document this in `notes`.

**Reference settings (owner-confirmed by ear; provenance in `docs/superpowers/2026-06-02-audio-art-probe-results.md`):**
- cozy/organic SFX: kalimba/mbira warm-wooden-pluck; steps ~55, cfg ~6, dur ~1.2 s + auto envelope.
- cozy/organic BGM: fingerpicked nylon-guitar lullaby, low/warm register, simple repeating melody; steps ~50, cfg ~8; anti-drone + anti-high-pitch negatives.
- arcade/retro SFX: clean square-wave chiptune; steps ~100 + auto envelope.
- arcade/retro BGM: mellow chiptune melody, soft square/triangle; steps ~50, cfg ~6.

## 4. Generate each clip
`node tools/comfy.mjs gen-audio <id> <clip-name> '<recipe-json>'` → writes `games/<id>/audio/<name>.wav`. The file is canonical and committed; the recipe is provenance, not bit-exact (GPU/seed nondeterminism). Requires Stable Audio Open installed + the `save_audio` soundfile-WAV patch (see the feasibility notes — output is WAV regardless of any `format` field, on the pinned torch 2.11/cu128 stack).

## 5. Wire into the Godot scene
- Add one `AudioStreamPlayer` per SFX (named per the `events[]` `node`) and one for music.
- Set import flags: for the music bed, `compress/mode=0` (PCM) in its `.wav.import` — **required** by the rebuild below (a QOA/ADPCM import returns compressed bytes in `.data`, which the rebuild would copy as if raw PCM and corrupt). SFX one-shot.
- **Music — start it so it actually plays.** A *long* IMPORTED `AudioStreamWAV` (the ~20–40 s bed) **silently refuses to play** — `play()` leaves `playing=false, pos=0` even on the real WASAPI driver, with explicit `play()` and a valid 30 s stream — while short SFX from the same generator play fine. A freshly **constructed** `AudioStreamWAV` built from the *same* PCM data **does** play. So **rebuild the bed stream in code** before wiring it:
  ```gdscript
  var src := load("res://audio/bgm.wav") as AudioStreamWAV
  var w := AudioStreamWAV.new()
  w.format = src.format; w.mix_rate = src.mix_rate; w.stereo = src.stereo
  w.data = src.data
  w.loop_mode = AudioStreamWAV.LOOP_FORWARD
  w.loop_begin = 0
  w.loop_end = src.data.size() / (4 if src.stereo else 2)  # 16-bit frames
  p.stream = w
  ```
  Then set **`autoplay = true` *before* `add_child`** so it starts on tree entry (deferred/awaited `play()` is a fallback). Autoplay/deferred alone does **not** fix the silent bed — the imported long stream must be rebuilt. (Confirm with the §7 probe: a wired, autoplaying bed can still be silent if not rebuilt.) A future cleaner fix is OGG/Vorbis for music, which sidesteps the WAV path entirely.
- **Levels:** set the music `volume_db` deliberately so the bed is **audible but sits under** the SFX — do not bury it. **Set `volume_db` per-game from the bed's ACTUAL loudness, never a flat default.** Music is NOT envelope-normalized (only SFX are), so raw bed loudness swings wildly by genre: a fingerpicked acoustic lullaby may come back ~RMS 0.04 (already ~11 dB *under* the ~RMS 0.13 SFX → it needs a small BOOST, e.g. `volume_db +2`, or it vanishes), while a dense chiptune bed may come back ~RMS 0.20 (~4 dB *above* the SFX → it needs a firm CUT, e.g. `volume_db -12`, to sit under). Measure the bed (or judge by ear at playtest) and pick the sign accordingly — a single flat default is wrong across genres.
- SFX: `play()` from the mapped `signal`/call site, replayable (call `play()` each event; for rapid repeats consider a small pool or `AudioStreamPlayer` per channel).
- Keep wiring minimal and reuse the game's existing signal points; do not restructure the core loop.

## 5b. Import the clips (before re-validation)
Run the headless import pass so Godot makes each `.wav.import` sidecar + cached stream **before** the validator's headless run (the audio analog of the `asset` method's `--import` gotcha):
```
godot --headless --path games/<id>/ --import
```
Commit the generated `*.wav.import` sidecars alongside the clips (expected Godot output, like `.png.import`).

## 6. Record `audio_pass` and advance status
Merge an `audio_pass` block (`method:"audio"`, `audio_system` — including `sonic_character` — `recipes`, `events`, `notes`) via the manifest tool, then `node tools/manifest.mjs set-status <id> scored`. State plainly in `notes` what was produced and anything skipped (mixed honesty). (`method:"audio"` is a constant provenance tag — the block name already says it's audio — **not** a branch key; unlike `asset_pass.method` (`svg`/`raster`), no consumer reads it.)

## 7. Hand off to validator
Run the validator's audio method to confirm files import, players reference valid streams, and SFX fire on events — **and that the music bed is actually playing.** Confirm `MusicAmbient.playing == true` with an advancing `get_playback_position()` a few frames in, not merely that the node exists and is wired (a wired, autoplaying bed can still be silent if the long imported WAV wasn't rebuilt per §5 — caught by this probe). The probe must run on the **real audio driver** (`godot --path ... --script`, NOT `--headless`, whose dummy driver reports `playing=false` even for a good stream).
