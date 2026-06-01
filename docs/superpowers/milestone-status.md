# GameForge — milestone status (2026-05-31)

Single source of truth for where the project stands. Updated each time a milestone gate clears or an owner-gated step completes.

---

## POC — DONE & shipped

Proved: a one-line prompt becomes a playable Godot game through `concept` → `builder` → `validator` coordinated by a JSON manifest. Three distinct genres reached `playable` from an unchanged skill set (runner, match-3, shooter — runs 001–003). Skill edits demonstrably moved output quality and blend cohesion (confirmed 4×). All §2 criteria met. Shipped to `github.com/qmertesdorf/mobile-gen`, branch `main`.

## M1 (asset skill / SVG re-skin) — DONE & merged

Proved: an `asset` skill can re-skin a generated game's SVG sprites at the concept level, producing a styled result. Confirmed on run-007 (runner-0002 → styled). Merged to `main`.

## M1.5 (raster/PNG via ComfyUI + SDXL + LayerDiffuse) — gate CLEARED; proof runs pending

**Foundation:** code merged (`11cefd4`). `tools/comfy.mjs gen`, workflow templates, `asset` skill raster method — all committed and passing CI (69/69 unit tests, network-mocked, no GPU in CI).

**Feasibility gate: CLEARED (2026-05-31, RTX 5080 16 GB).**

The earlier "gray interior" finding (gray interior, luma std ~13–17) was a misdiagnosis — it was reading the wrong mask region. The LayerDiffuse decoder is fine. Root cause: a one-line alpha-inversion sign error in the join-patch (`1.0 - mask` when the parent `decode` already returns opacity; corrected to use alpha as-is). After the fix: vivid interior (luma std 73.05), clean transparent background, 17.3% subject coverage. The RTX 5080 / Blackwell upgrade also required torch ≥2.7/cu128 (the old cu124 venv topped out at sm_90 and could not run Blackwell kernels).

**REMAINING (owner-gated):** raster re-skins for creature-0001 (painterly) and crosser-0001 (pixel-art) — runs poc-run-008/009 — require owner playtests (→ `playable`) and A/B review (→ `styled`).

## M1.6 (audio via ComfyUI + Stable Audio Open) — gate PASSED; proof runs staged

**Foundation + gate: PASSED (2026-05-31, RTX 5080).** Stable Audio Open verified end-to-end through `tools/comfy.mjs gen-audio`. Two blockers resolved during the gate: (1) the provisional `stable-audio.json` template was structurally wrong — corrected to a separate `CLIPLoader` loading `t5-base.safetensors` (`type:"stable_audio"`) feeding both positive and negative `CLIPTextEncode`, `scheduler:"exponential"`, duration from `EmptyLatentAudio` (min 1.0 s); (2) under torch 2.11/cu128, `torchaudio.save` routes through TorchCodec (not installed) — patched `comfy_extras/nodes_audio.py` `save_audio` to write WAV via `soundfile` (bundled libsndfile, no FFmpeg needed). Output is real WAV.

**Both proof games staged (`main` @ `562bc66`):** creature-0001 has a warm-woodland audio pass; crosser-0001 has a chiptune audio pass. Status held at `validated`.

**REMAINING (owner-gated):** playtest creature-0001 + crosser-0001 (→ `playable`); audio A/B review (→ `scored`); raster A/B review (→ `styled`); write poc-run-010/011 records.

---

## Owner-gated pending (summary)

| Action | Unblocks |
|--------|----------|
| Playtest creature-0001 | `playable` → audio A/B → `scored` |
| Playtest crosser-0001 | `playable` → audio A/B → `scored` |
| Audio A/B review (both) | `scored`; poc-run-010/011 |
| Raster A/B review (both) | `styled`; poc-run-008/009 |
| Write poc-run-008–011 records | milestone closure |
