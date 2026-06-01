# mobile-gen (GameForge) — project conventions

Project overview, the manifest spine, the skill loop, and the `comfy.mjs` raster/audio tools are documented in `README.md` — read it first. This file captures the **local AI generation environment** on this machine (the part not in the repo), so you know where the models live and how to boot the servers.

## Local AI generation environment (this machine)

`tools/comfy.mjs` (raster + audio) assumes a **local ComfyUI** server is already running. It does not start or manage it. Default host `http://127.0.0.1:8188` (override `COMFY_HOST`). Quick reachability check: `node tools/comfy.mjs --check`.

- **GPU:** NVIDIA RTX 5080, **16 GB VRAM — hard ceiling.** The raster stack runs Juggernaut XL v9 fp16 with **no offload on 16 GB** (per README §M1.5); audio adds Stable Audio Open. Don't stack a large concurrent VRAM consumer. If Ollama (used by the sibling `ecom-factory` project) is resident, free it first: `Get-Process ollama* | Stop-Process -Force`.
- **ComfyUI:** installed at `C:\Users\quint\ComfyUI`, pinned **v0.3.16 (commit `26c7baf`)**, venv on **torch 2.11.0+cu128** — exactly the pins the README requires for the LayerDiffuse join-patch and the `save_audio` soundfile-WAV patch. Don't upgrade ComfyUI without re-validating both patches.
  - **Boot it:** run `C:\Users\quint\ComfyUI\run_comfyui.bat`. It `cd`s into the dir and runs the venv python with `main.py --use-sage-attention` (extra args pass through via `%*`). Use the bat — don't hand-author a launch line.
  - `--use-sage-attention` is on by design (~30–35% faster sampling). **Do NOT add `--fast fp16_accumulation`** — this v0.3.16 build only exposes a bare, quality-deteriorating `--fast`; the granular form needs a newer ComfyUI. **Do NOT add a TorchCompile node on Flux while sage attention is active** (known noise/corruption bug).
- **Models:** `C:\Users\quint\ComfyUI\models` is a **junction → `D:\ComfyUI-models`** (Samsung 980 PRO, PCIe 4.0 — faster loads, keeps the C: boot drive free). The model files `comfy.mjs` relies on live there: `checkpoints/` (Juggernaut XL v9, SDXL base, `stable-audio-open-1.0.safetensors`), `text_encoders/` (`t5-base.safetensors` for Stable Audio), plus `diffusion_models`, `clip_vision`, `vae`, `loras`, `layer_model`. Drop new model files into those subfolders — they resolve to D: transparently.

## Skill loop (from README)

prompt → `concept` → `builder` → `validator` → human playtest → edit the responsible `SKILL.md` → repeat across ≥3 genres. The deliverable is **better skills**, not the games. The `asset`/`audio` skills own the art/audio judgment; `comfy.mjs` owns the deterministic, network-mocked HTTP plumbing (no GPU in CI).

## Pins that must stay in sync

- Godot `4.6.3.stable` — source of truth in `README.md` §Pinned Godot version and every manifest's `build.engine_version`.
- ComfyUI `v0.3.16` + torch `2.11.0+cu128` + the two local patches (LayerDiffuse RGBA join-patch, `save_audio` soundfile-WAV patch). See `docs/superpowers/m1.5-feasibility-notes.md` and `m1.6-feasibility-notes.md`.
