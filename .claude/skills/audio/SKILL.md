---
name: audio
description: Use when giving a playable Godot game a coherent, prompt-derived audio identity — event SFX plus a looping music track — generated locally via ComfyUI + Stable Audio Open through tools/comfy.mjs. Derives an audio system from the concept, maps core-loop events to SFX, generates clips, wires AudioStreamPlayer nodes, records audio_pass, and advances status to "scored". Hands off to validator.
---

# Audio re-skin (local generative SFX + music)

Give a `playable`-or-better game an audio identity. Audio is orthogonal to the visual pass: a game may be `playable`, `styled`, or `scored` going in. The terminal status is `scored`; the `audio_pass` block — not the status string — is the source of truth for what was produced.

## Preconditions
- Game status is `playable`, `styled`, or `scored`.
- ComfyUI is reachable with Stable Audio Open installed: `node tools/comfy.mjs --check`.

## 1. Derive the audio system (do this first, once)
Read `concept.art_direction`, `concept.genre`, and theme. Author a shared `audio_system`:
- `model`: `"stable-audio-open-1.0"`.
- `mood_prompt`: one shared mood sentence threaded into every clip prompt for coherence (the audio analog of the visual prompt scaffold) — e.g. "warm, organic, gentle woodland atmosphere".
- `style_descriptors`: 2–4 tags (e.g. `["ambient", "soft", "acoustic"]` or `["chiptune", "8-bit", "upbeat"]`).

## 2. Map core-loop events to SFX
From `concept.core_loop` + the entity/signal set, list the discrete events that deserve a one-shot: typically a positive beat (collect/score), a negative beat (hurt/hit), a loss beat (game over), and the primary action (jump/hop/shoot). For each, record an `events[]` entry: `{ event, clip, node, signal }` where `node` is the `AudioStreamPlayer` you will add and `signal` is the Godot signal (or call site) that triggers it. Be honest: if an event has no SFX, leave it out and note it.

## 3. Author recipes
One recipe per SFX + one music recipe. Each prompt = `mood_prompt` + the clip-specific description. Defaults confirmed at the feasibility gate (`docs/superpowers/m1.6-feasibility-notes.md`):
- **SFX**: `kind:"sfx"`, `format:"wav"`, `duration_s` **1.0–2.0** (`EmptyLatentAudio` enforces a 1.0 s minimum — do not go below), `loop:false`, `steps` ~8, `cfg` ~5–6 — short, punchy, single sound; negative prompt excludes "music, melody, voice, speech". (cfg too high can clip the transient.)
- **Music**: `kind:"music"`, `format:"wav"`, `duration_s` 20–40, `steps` ~50, `cfg` ~7, `loop:true`, `import_settings:{loop:true, loop_offset:0}`. Target loop-friendly content (steady texture, no hard intro/outro) — seamless looping is imperfect for generative output (known limitation). Note: WAV music is uncompressed (~5 MB / 30 s stereo); acceptable for a milestone, OGG is a future size optimization.
- All recipes use `sampler:"dpmpp_3m_sde_gpu"` (scheduler `exponential` is baked into the template).
- **IP-safety**: never name artists or copyrighted tracks; negative prompt excludes "voice, speech, lyrics, vocals" for music unless intended. Document this in `notes`.

## 4. Generate each clip
`node tools/comfy.mjs gen-audio <id> <clip-name> '<recipe-json>'` → writes `games/<id>/audio/<name>.wav`. The file is canonical and committed; the recipe is provenance, not bit-exact (GPU/seed nondeterminism). Requires Stable Audio Open installed + the `save_audio` soundfile-WAV patch (see the feasibility notes — output is WAV regardless of any `format` field, on the pinned torch 2.11/cu128 stack).

## 5. Wire into the Godot scene
- Add one `AudioStreamPlayer` per SFX (named per the `events[]` `node`) and one for music.
- Set import flags: music stream `loop = true` (and `loop_offset` if needed); SFX one-shot.
- Music: `play()` on scene ready / loop start. SFX: `play()` from the mapped `signal`/call site, replayable (call `play()` each event; for rapid repeats consider a small pool or `AudioStreamPlayer` per channel).
- Keep wiring minimal and reuse the game's existing signal points; do not restructure the core loop.

## 6. Record `audio_pass` and advance status
Merge an `audio_pass` block (`method:"audio"`, `audio_system`, `recipes`, `events`, `notes`) via the manifest tool, then `node tools/manifest.mjs set-status <id> scored`. State plainly in `notes` what was produced and anything skipped (mixed honesty).

## 7. Hand off to validator
Run the validator's audio method to confirm files import, players reference valid streams, and SFX fire on events.
