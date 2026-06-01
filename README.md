# GameForge (POC)

An AI pipeline that turns a one-line prompt into a playable mobile game, built as Claude Agent Skills. See `docs/superpowers/specs/2026-05-30-gameforge-poc-design.html` for the design.

## Pinned Godot version

`4.6.3.stable` — **source of truth** for every manifest's `build.engine_version`. Both machines must match (§11). Update here and in existing manifests if you bump it.

## Layout

- `.claude/skills/` — the `concept`, `builder`, `validator`, `asset` (re-skin/art), and `audio` (SFX+music) skills.
- `manifests/<id>.json` — one manifest per title (the spine; §5).
- `games/<id>/` — generated Godot projects.
- `tools/manifest.mjs` — the manifest CLI (`create` / `set-status` / `merge` / `validate`).
- `schema/manifest.schema.json` — the manifest schema.

## The loop

prompt → `concept` → `builder` → `validator` → human playtest → edit the responsible `SKILL.md` → repeat across ≥3 genres. The deliverable is **better skills**, not the games.

## Manifest CLI

```
node tools/manifest.mjs create <id> "<name>"     # new skeleton, status=concept
node tools/manifest.mjs merge  <id> '<json>'      # deep-merge a partial (e.g. the concept block)
node tools/manifest.mjs set-status <id> <status>  # concept→generated→validated→playable | →failed
node tools/manifest.mjs validate <id>             # schema-check; exit 1 if invalid
```

## Raster asset tool (M1.5)

`tools/comfy.mjs` turns a recipe into a committed RGBA PNG via a **local ComfyUI** server (assumed installed and running by the owner, like the Godot binary — not managed here). Default host `http://127.0.0.1:8188`, override with `COMFY_HOST`.

```
node tools/comfy.mjs --check                          # ping ComfyUI; report reachable + checkpoints
node tools/comfy.mjs gen <id> <asset-name> '<recipe>' # generate games/<id>/art/<name>.png
```

Stack: ComfyUI + SDXL (Juggernaut XL v9 fp16, **no offload on 16 GB**) + the **ComfyUI-layerdiffuse** node (RGBA at generation time, proven on an RTX 5080). Workflow-JSON templates with `%placeholder%` tokens live in `tools/comfy-templates/`. The `asset` skill's `raster` method owns the art judgment; `comfy.mjs gen` owns the deterministic HTTP plumbing (unit-tested with the network mocked — no GPU in CI).

**Required local setup (not in this repo):**
1. ComfyUI pinned to **v0.3.16** (commit `26c7baf`) — required for LoRA-patch compatibility.
2. A **one-line join-patch** to `custom_nodes/ComfyUI-layerdiffuse/layered_diffusion.py` `LayeredDiffusionDecodeRGBA.decode`: build the RGBA tensor directly (`torch.cat([rgb, alpha], -1)`) AND use the parent `decode`'s alpha as-is — do NOT invert it.
3. ComfyUI venv on **torch ≥2.7 / cu128** (we run 2.11.0+cu128) for any RTX 50-series/Blackwell GPU.

See `docs/superpowers/m1.5-feasibility-notes.md` for full gate findings.

## Audio asset tool (M1.6)

`tools/comfy.mjs gen-audio` generates SFX and music clips via the same local ComfyUI server (`COMFY_HOST`).

```
node tools/comfy.mjs gen-audio <id> <clip-name> '<recipe>' # writes games/<id>/audio/<name>.wav
```

The `audio` skill (`.claude/skills/audio/SKILL.md`) owns the audio judgment — deriving the audio system, mapping core-loop events to SFX, and authoring recipes. `comfy.mjs genAudio` owns the deterministic HTTP plumbing (same unit-tested, network-mocked, no-GPU-in-CI pattern as `gen`).

Template: `tools/comfy-templates/stable-audio.json`. Stable Audio Open uses a separate `CLIPLoader` loading `t5-base.safetensors` (`type:"stable_audio"`) that feeds both positive and negative `CLIPTextEncode`. KSampler uses `scheduler:"exponential"` (baked into the template). Clip duration comes from `EmptyLatentAudio` (minimum **1.0 s** — do not go below).

Output format is **WAV** for this milestone (Godot-native, lossless, matches the schema `format` enum, zero extra deps). A 30 s music track is ~5 MB uncompressed; OGG is a future optimization.

Proven recipe defaults:
- **SFX:** `kind:"sfx"`, `format:"wav"`, `duration_s` 1.0–2.0, `steps` ~8, `cfg` ~5–6, `sampler:"dpmpp_3m_sde_gpu"`. Negative excludes "music, melody, voice, speech".
- **Music:** `kind:"music"`, `format:"wav"`, `duration_s` 20–40, `steps` ~50, `cfg` ~7, `sampler:"dpmpp_3m_sde_gpu"`, `loop:true`.

**Required local setup (not in this repo):**
1. Two UNGATED model files: checkpoint `stable-audio-open-1.0.safetensors` from `Comfy-Org/stable-audio-open-1.0_repackaged` → `models/checkpoints/`; text encoder `t5-base.safetensors` from `ComfyUI-Wiki/t5-base` → `models/text_encoders/`.
2. A **`save_audio` soundfile-WAV patch** to `comfy_extras/nodes_audio.py`: under torch ≥2.11/cu128, `torchaudio.save` routes through TorchCodec (not installed, needs system FFmpeg). Patch `save_audio` to write WAV via `soundfile` (bundled libsndfile, no torchcodec/FFmpeg). This is the audio analog of the M1.5 LayerDiffuse join-patch.
3. Same ComfyUI v0.3.16 pin and torch 2.11.0+cu128 venv as the raster stack.

See `docs/superpowers/m1.6-feasibility-notes.md` for full gate findings.

## Tests

`npm test`
