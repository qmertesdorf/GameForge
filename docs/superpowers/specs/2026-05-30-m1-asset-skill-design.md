# M1 — `asset` skill (SVG re-skin) — Design

> **Milestone M1 of the GameForge roadmap** (§10 of the POC spec, `2026-05-30-gameforge-poc-design.md`). Each milestone gets its own spec → plan → implement cycle. This is M1's spec.

**Date:** 2026-05-30 · **Status:** approved, pre-plan · **Depends on:** the M0 POC (`concept`/`builder`/`validator` + manifest spine), now wrapped on `main`.

---

## 1. Goal

Replace a playable game's deliberate **primitive** visuals with real, coherent **SVG art**, proving the manifest pipeline can take a title from "intentional toy" to "looks designed" — with the re-skin legibly recorded in the spine. As with M0, **the real deliverable is a sharp `asset` skill**, not the prettier game; every gap must be attributable to specific skill prose.

This fills the `assets[]` portion of the manifest with real sources (the M1 target named in the roadmap), via SVG specifically.

## 2. Scope

**In:**
- A new `asset` skill that runs as a **re-skin pass after `playable`**.
- A **coherent visual system** derived from `concept.art_direction` (see §5a) that governs every asset, so the game reads as one designed thing rather than a bag of individually-fine shapes — this *system* is the real deliverable, not the per-entity files.
- Claude-authored **SVG** art files, rasterized by Godot's native SVG importer, all conforming to that system.
- Rewiring a generated game's procedural `_draw()` primitives to display the SVGs via `Sprite2D`/`TextureRect`.
- Manifest changes: a new `styled` status, an `asset_pass` block (carrying the visual system), and `origin: "svg"` asset entries.
- Re-validation through the **existing** `validator` (no new validator skill).
- One end-to-end proof on a real `playable` title + a run report.

**Out (YAGNI / deferred):**
- **Raster / PNG art and local Stable Diffusion → M1.5.** Research on the local SD stack (ComfyUI + GGUF + LayerDiffuse on the RTX 3070; sd.cpp fallback) is complete and saved; M1.5 bundles it with the local **audio** model as one "local generative models" cycle.
- **Audio (SFX/music) → M1.5.**
- **App icon, adaptive icon, and store imagery → M3 (listing).** The `asset` skill *will* be the natural place to author the launcher icon (SVG → all density buckets), but that is a store-listing concern; M1 stays focused on in-game art. Noted here so M3 picks it up deliberately.
- **Representational / character / illustrated art → M1.5 (raster).** See §3a — the SVG aesthetic boundary.
- Re-skinning of **effects** — glow halos, particles, screen-shake, squash/stretch stay as code (they are motion, not art).
- No new MCP tool — SVG is authored inline as text, exactly as `builder` authors GDScript.
- No changes to `concept` or `builder` — `asset` consumes `concept.art_direction` as-is.

## 3. Why SVG (and why not local SD yet)

Claude cannot emit PNG pixels on-subscription, but it **can** author SVG as text. SVG is:
- **Deterministic & git-friendly** — small text files, diffable, regenerable, no binary blobs.
- **Dependency-free** — Godot 4.x natively imports `.svg` to crisp textures at any scale; no Python/ComfyUI runtime.
- **Genuinely "real art sources"** — gradients, paths, filters/glow far exceed in-engine primitives, satisfying the M1 `assets[]` target.

Local SD was researched first (the choice drives the whole plan). It is feasible on the owner's RTX 3070 8GB but heavy for an M1 re-skin: multi-GB weights, a hard ComfyUI/Python dependency, **non-bit-exact** GPU output (conflicts with a regenerable git-tracked pipeline), and **transparency limited to SDXL/SD1.5** (LayerDiffuse doesn't cover FLUX/SD3.5). It belongs in M1.5 alongside the audio model, not here. (See the saved research note for the full verified findings.)

### 3a. The SVG aesthetic boundary (honest scope)

SVG is the *right, production-grade* choice for the art this pipeline currently produces — abstract, geometric, neon/flat, hyper-casual, and all UI. Resolution independence is in fact an app-store **strength**: one vector covers every Android density bucket (mdpi→xxxhdpi) and any screen, with no per-density export.

SVG is the *wrong* tool for **representational, character, illustrated, or textured** art (a painted hero, a photoreal background). Hand-authoring those as vector yields weak results. That class of art is an **M1.5 (raster / local-SD)** concern. M1 does not attempt it.

This boundary is not a limitation to apologize for — it is a deliberate division of labor: **M1 = vector (geometric/UI), M1.5 = raster (representational)**, each matched to the generation method that does it well. The `asset` skill should state, in its `asset_pass.notes`, when a concept's `art_direction` leans representational enough that M1.5 would serve it better — so the choice is legible rather than silently producing mediocre vector art.

## 4. Placement in the pipeline

The proven M0 loop is untouched. `asset` is a clean bolt-on after `playable`:

```
concept → builder → validator → [playable] → asset → validator(re-run) → [styled]
```

## 5. Components

Four pieces, each with one responsibility:

| Component | Responsibility |
|---|---|
| `.claude/skills/asset/SKILL.md` | The new prose skill: read a `playable` manifest, derive an art spec from `concept.art_direction`, author SVGs, rewire the game to display them, record `assets[]` + `asset_pass`, advance to `styled`. |
| `games/<id>/art/*.svg` | Claude-authored vector art — one file per builder-registered visual entity (player, obstacle, pickup, background, …). |
| Texture-swap convention (in the game) | The documented pattern by which each SVG replaces its primitive: a `Sprite2D` (world) / `TextureRect` (HUD) loads the texture; the corresponding `_draw()` primitive is removed/guarded; transforms, movement, collision, logic are untouched. |
| Manifest tool (`tools/manifest.mjs` + `schema/manifest.schema.json`) | The only code with logic, so it gets TDD: add `styled` status + transition, the `asset_pass` block, and `origin:"svg"` asset entries. |

### 5a. The visual system is the deliverable (not the individual SVGs)

A real game-asset creator does not produce a pile of independently-acceptable shapes — it produces a **coherent visual system** and then applies it everywhere, so the game reads as *one designed thing*. This is the art analog of the M0 hybrid finding ("two systems that coexist instead of fuse," run-004): individually-fine assets that don't share a language look like a collage, not a game.

So the `asset` skill's **first** step is to derive an explicit, written **visual system** from `concept.art_direction`, before authoring any file:

- **Palette** — a fixed 3–5 colour set (with named roles: primary, accent, danger, background, etc.).
- **Line/stroke** — one stroke weight and join/cap style used throughout.
- **Form language** — corner radius, geometric vs. organic, level of detail.
- **Shading model** — flat / single-direction gradient / glow — pick one and apply it to every asset.
- **Scale & padding rules** — how each SVG maps to its primitive footprint, and consistent internal padding so assets sit together.

Every SVG must conform to that system. The system itself is recorded in `asset_pass.visual_system` (see §8) so it is reviewable, reusable, and the thing a run report critiques when the result looks incoherent. **"Each SVG is fine but they don't cohere" is the primary failure this section exists to prevent — and, when it happens, it is attributable to the visual system, not the individual files.**

## 6. Data flow

```
playable manifest ─► asset reads concept.art_direction
                  ─► derives a coherent VISUAL SYSTEM (palette/stroke/form/shading) ── §5a
                  ─► authors games/<id>/art/{player,obstacle,...}.svg, all conforming to it
                  ─► headless --import so Godot generates .svg.import + textures
                  ─► rewires Main.gd / Main.tscn: primitive _draw() → Sprite2D/TextureRect(texture)
                  ─► merge assets[] (origin:"svg") + asset_pass block
                  ─► set-status styled
                  ─► validator re-runs: headless clean + selftest OK + human A/B playtest
```

## 7. The SVG-swap mechanism (the technically hard part)

The builder draws procedurally — there are **no sprite slots to swap into**. So `asset` must both generate SVGs *and* rewire the game. Three sub-problems:

**a) How SVGs enter Godot.** Godot 4.x imports `.svg` as a texture via a `.svg.import` sidecar carrying a `scale` param. A headless `--import` pass generates these. `asset` runs that pass before re-validating, so textures exist at runtime.

**b) How primitives get replaced (the documented swap pattern).** Per builder-registered visual entity:
- Add a `Sprite2D` (world actors) or `TextureRect` (HUD/UI) that loads the entity's SVG, positioned/scaled to match the primitive's original footprint.
- **Remove or guard** the old `_draw()` code for that entity — delete the draw calls, keep the node's transform and game logic. A common failure is leaving the primitive *and* adding the sprite (double-draw); the skill must prevent it.
- Movement, collision, spawning, scoring — **unchanged**. Only the visual representation changes.

**c) What stays primitive.** Effects (glow, particles, screen-shake, squash/stretch) stay code — they are juice, not art. Backgrounds may stay procedural (parallax) **or** get a tiling SVG, at the skill's judgment from `art_direction`. The skill **records which entities were re-skinned vs. left primitive**, so a partial re-skin is a legible choice, not a silent gap.

**Failure attribution (the POC value):** a bad re-skin is always attributable — `asset` authored a poor SVG, mis-positioned/mis-scaled a sprite, or failed to remove the underlying primitive. Each is a specific, fixable prose gap.

## 8. Status model & manifest changes

**New status `styled`, terminal, after `playable`:**

```
concept → generated → validated → playable → styled
   (failed reachable from any non-terminal status)
```

- `STATUSES` → `["concept","generated","validated","playable","styled","failed"]`.
- `TRANSITIONS`: `playable: ["styled","failed"]`, `styled: []` (terminal). This makes `playable` **non-terminal** — a deliberate change applied consistently across the schema enum, the transition map, and the tests.
- Backward-compatible: existing run-00X manifests stay `playable` (valid); `styled` is reached only by running `asset`.

**New top-level `asset_pass` block** (peer of `build`/`validation`):

```json
"asset_pass": {
  "method": "svg",
  "visual_system": {
    "palette": ["#0a0a14", "#00e5ff", "#ff3df0", "#ffe24a"],
    "stroke": "2px round, additive glow",
    "form": "sharp-cornered geometric, low detail",
    "shading": "flat fill + outer glow halo"
  },
  "reskinned": ["player", "obstacle", "pickup"],
  "left_primitive": ["background", "glow", "particles"],
  "art_path": "games/<id>/art/",
  "notes": "background kept as procedural parallax; SVGs scaled to primitive footprints; art_direction is geometric, well within SVG scope (not representational)"
}
```

**`assets[]` entries** flip for re-skinned entities:
`{ "type":"sprite", "name":"player", "source":"placeholder", "origin":"primitive" }`
→ `{ "type":"sprite", "name":"player", "source":"art/player.svg", "origin":"svg" }`.

The schema currently constrains `assets[]` item fields loosely (string `source`/`origin`) and forbids unknown top-level keys, so `asset_pass` must be added to the schema (with `additionalProperties:false` and its own field constraints) and the status enum extended.

## 9. Validation

`asset` reuses the **existing `validator`** — no second validator skill. After the swap, the same gates re-run:

1. **Headless import + run clean** — exit 0, no `SCRIPT ERROR`/`ERROR:`/"Failed to load". Proves the SVGs import and the rewired scene runs.
2. **`selftest.gd` still `SELFTEST OK`** — proves the swap didn't break game logic (only visuals changed). For titles that have a selftest.
3. **Human A/B playtest** — owner confirms it *looks* better and still plays. This is the A/B that proves the skill, identical in spirit to every M0 run.

The validator gains one capability: advancing `playable → styled` (today it stops at `playable`). On failure it records legible `issues` and attributes them (almost always to `asset`), and does **not** advance to `styled`.

## 10. Testing

TDD on the only component with logic — `tools/manifest.mjs` + schema:
- `playable → styled` is legal; `styled` is terminal (cannot leave); `playable → failed` still legal.
- Schema accepts a manifest carrying `asset_pass` and `origin:"svg"` asset entries.
- Schema still accepts existing `playable` manifests (no regression).
- `skills.test.mjs` adds `asset` to the required-skills list (structural frontmatter check, like the other three skills).
- Existing 24 tests stay green; net new ≈ 5–6.

## 11. Deliverable (the proof)

Same shape as every M0 run: prove end-to-end on a real title. Run `asset` on an existing `playable` game (e.g. `runner-0002`, the best-looking baseline), A/B the SVG re-skin against the primitive original, and write a run report (`docs/superpowers/poc-run-007.md` or `m1-run-001.md`) attributing any gap to specific `asset` skill prose. The job of the run is to convert a felt visual gap into a concrete `SKILL.md` edit — exactly the M0 mechanism, now applied to art.

## 12. Success criteria

1. `asset` skill exists and runs the full re-skin on a `playable` title without manual code fixes.
2. The re-skinned game imports + runs headless clean and (if applicable) `selftest.gd` still passes.
3. Owner A/B playtest confirms the SVG version looks more designed than the primitive original, **reads as one coherent visual system** (not a set of mismatched shapes), and plays identically.
4. The manifest correctly reaches `status:"styled"` with a populated `asset_pass` block and `origin:"svg"` entries; `validate` OK at every transition.
5. Any shortfall is legible and attributable to specific `asset` skill prose (the POC value).
