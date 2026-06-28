# Pixel-Art-as-a-Style Foundation — Design

**Date:** 2026-06-27
**Status:** Approved (design); pending implementation plan
**Scope:** Foundation only. Pixel-art *animation* (frames / `AnimatedSprite2D` / character movement) is a **separate, later spec** — see "Out of Scope".

## Goal

Make `art_direction: pixel` produce *real* pixel art — native-resolution, palette-locked, hard-edged — that reads as deliberately designed, with cohesion **guaranteed by a deterministic gate** rather than eyeballed. This aligns with GameForge's core philosophy: push correctness to deterministic, GPU-free verifiers; restrict the stochastic model to proposing.

### Why this approach

Pixel-art *generation* is already wired: `pixel-art-xl.safetensors` is installed, `comfy.mjs` has the `lora` recipe field + `sdxl-layerdiffuse-lora` template that applies it, the asset skill already documents pixel conventions (NEAREST filter, import downsample), and `tools/cutout.py` exists for clean alpha. The gap is that the current path generates at 1024px and downsamples *at import*, which yields "pixel-flavored but soft, off-palette" output. The fix is a deterministic post-process (downscale → palette-quantize → harden alpha) plus a QC gate — **not** more reliance on the LoRA holding a palette (it won't) and **not** GPU-side quantization (un-testable, couples correctness to the non-deterministic graph).

Approach chosen: **deterministic post-process tool + QC gate** (Approach A). Rejected: generation-only (status-quo soft/off-palette failure mode); ComfyUI-graph quantization (un-testable, pinned-node risk).

## Palette decision

**House palette: DawnBringer 32 (DB32).** One known, battle-tested palette for every pixel game (chosen over per-game palettes for maximum cohesion; over PICO-8's 16 for flexibility across creatures/divers/shopkeepers). Implemented as a single swappable constant so it can be changed centrally later.

## Components

### 1. `tools/palette.mjs`
DB32 as 32 hex-color constants, exported. Single house palette. No per-game palettes.

### 2. `tools/pixelize.mjs` — deterministic converter (GPU-free, pure Node)
Input: a 1024px RGBA PNG (the LoRA generation). Options: `{ native: 64, palette: DB32, alphaThreshold: 128, mode: 'sprite' | 'background' }`.

Pipeline:
1. Load via existing `png.mjs`.
2. **Downscale** longest side to `native` (sprite mode, default 64px) or fixed dimensions (background mode), box-average, aspect-preserved, integer output dims.
3. Per output pixel: alpha `< alphaThreshold` → fully transparent (α=0); else α=255 and RGB → **nearest DB32 color** (ΔE via existing `color.mjs`).
4. Write the native-res PNG — the committed file is canonical.

Returns `{ outPath, nativeSize, offPaletteFixed }`. Deterministic; unit-tested against synthetic images.

### 3. `tools/asset-qc.mjs` — new `pixel-purity` gate (opt-in)
Given `{ pixel: { palette, native } }`, **fail** the PNG unless:
- every opaque pixel ∈ palette (off-palette count = 0),
- dimensions are at native res (≤ native on the long side),
- no partial-alpha fringe (count of pixels with 0 < α < 255 ≈ 0; hard edges).

Returns pass/fail + counts. The "can't-be-rationalized" verifier that makes palette cohesion a guarantee.

### 4. asset-skill `pixel` path
- Record style in `asset_pass.visual_system.style`: `{ loras: ["pixel-art-xl"], style_prompt: "pixel art, …", native: 64, palette: "DB32" }`.
- Per sprite: gen via `sdxl-layerdiffuse-lora` → `pixelize.mjs` → `asset-qc` pixel gate → commit native PNG.
- Backgrounds: opaque `sdxl` template + pixel prompt terms (no LoRA node) → `pixelize` (background mode, larger native, same palette) → commit.
- Textures wired as today (`draw_texture_rect` / `Sprite2D`) at **integer-scaled** destination sizes.

### 5. Godot / project defaults
asset/builder sets `project.godot` → `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest) project-wide; `.png.import` NEAREST + mipmaps off. Keeps pixels crisp at mobile resolution.

### 6. visual-audit
No structural change — pixel art passes the existing lenses, and `asset-qc` gates palette/res/alpha deterministically upstream. Add a note to the skill that pixel fidelity (softness/palette) is gated by `asset-qc pixel-purity`, so auditors don't re-litigate it.

## Proving ground

Re-skin **crosser-0001** end-to-end via the pixel path (already has 3 raster assets: background, hero, hazard — a fair apples-to-apples test). Owner eyeballs the composited running screen.

**Success criteria:** `pixel-purity` passes on all committed PNGs + visual-audit clean + owner confirms "reads as designed pixel art." Note: crosser's full playfield means the background win is mostly in the margins (the flat lane playfield stays flat — a known limitation, not a regression).

## Testing

- `tools/pixelize.test.mjs`: synthetic gradient/alpha input → assert output dims, every pixel ∈ DB32, hard alpha (no partial-alpha pixels).
- Extend `tools/asset-qc.test.mjs`: `pixel-purity` pass case (clean palette PNG) + fail cases (off-palette pixel, soft alpha, wrong res).
- Full existing suite stays green (`node --test`).

## Out of scope (explicit)

- **Animation** — frames, sprite sheets, `AnimatedSprite2D`/`SpriteFrames`, `Skeleton2D`/`AnimationPlayer`, character movement. This is the **next spec**.
- Per-game custom palettes (using house DB32).
- ComfyUI workflow-graph changes.
