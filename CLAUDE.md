# mobile-gen (GameForge) — project conventions

Project overview, the manifest spine, the skill loop, and the `comfy.mjs` raster/audio tools are documented in `README.md` — read it first. This file captures the **local AI generation environment** (the part not in the repo), so you know where the models live and how to boot the servers. Paths below use `$COMFYUI` for your ComfyUI install dir — substitute your own.

## Local AI generation environment

`tools/comfy.mjs` (raster + audio) assumes a **local ComfyUI** server is already running. It does not start or manage it. Default host `http://127.0.0.1:8188` (override `COMFY_HOST`). Quick reachability check: `node tools/comfy.mjs --check`.

- **GPU:** the raster stack was proven on a **16 GB-VRAM** card (RTX 5080 / Blackwell). It runs Juggernaut XL v9 fp16 with **no offload at 16 GB** (per README §M1.5); audio adds Stable Audio Open. Don't stack a large concurrent VRAM consumer — if another local model server (e.g. an Ollama instance) is resident, free it first: `Get-Process ollama* | Stop-Process -Force`.
- **ComfyUI:** pinned **v0.3.16 (commit `26c7baf`)**, venv on **torch 2.11.0+cu128** — exactly the pins the README requires for the LayerDiffuse join-patch and the `save_audio` soundfile-WAV patch. Don't upgrade ComfyUI without re-validating both patches.
  - **Boot it:** launch ComfyUI from its install dir, e.g. `$COMFYUI` running the venv python with `main.py --use-sage-attention`. A small launcher script (that `cd`s into the dir and passes args through) avoids hand-authoring the line each time.
  - `--use-sage-attention` is on by design (~30–35% faster sampling). **Do NOT add `--fast fp16_accumulation`** — this v0.3.16 build only exposes a bare, quality-deteriorating `--fast`; the granular form needs a newer ComfyUI. **Do NOT add a TorchCompile node on Flux while sage attention is active** (known noise/corruption bug).
- **Models:** the model files `comfy.mjs` relies on live under `$COMFYUI/models` (a junction to a fast SSD works well — faster loads, keeps the boot drive free): `checkpoints/` (Juggernaut XL v9, SDXL base, `stable-audio-open-1.0.safetensors`), `text_encoders/` (`t5-base.safetensors` for Stable Audio), plus `diffusion_models`, `clip_vision`, `vae`, `loras`, `layer_model`.

## Skill loop (from README)

prompt → `concept` → `builder` → `validator` → human playtest → `( deepen → validator → playtest )*` → `asset` → `visual-audit` → `audio` → `packager`. The deliverable is **better skills**, not the games. `deepen` owns iterating/growing a playable game's systems & content; the `asset`/`audio` skills own art/audio production and `visual-audit` owns judging the composited screen; `comfy.mjs` owns the deterministic, network-mocked HTTP plumbing (no GPU in CI).

## Pins that must stay in sync

- Godot `4.6.3.stable` — source of truth in `README.md` §Pinned Godot version and every manifest's `build.engine_version`.
- ComfyUI `v0.3.16` + torch `2.11.0+cu128` + the two local patches (LayerDiffuse RGBA join-patch, `save_audio` soundfile-WAV patch).
