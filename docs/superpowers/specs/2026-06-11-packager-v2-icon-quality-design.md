# Packager v2 — app-store-grade store face

**Date:** 2026-06-11
**Status:** design approved, pre-implementation
**Skill under work:** `packager` (the deliverable is the skill, per README "better skills, not the games")
**Dogfood target:** `shopkeep-0001` (Tide & Tally), currently `packaged` with a "good enough for trial" icon

## 1. Motivation

The first end-to-end `packager` run (shopkeep-0001 → `packaged`) shipped, but it exposed three places where the skill made the operator improvise **outside** the re-runnable tool — exactly the skill-debt the GameForge ethos exists to kill:

- **Gap A — icon squish.** `tools/godot/icon_resize.gd` does a flat `Image.resize(px, px)` (square-stretch). The skill says the icon master is "the styled hero sprite … or a deliberately-composed master" and even shows `"icon_master": "art/<hero>.png"`. A non-square hero (the shell was 441×324) gets distorted. The operator hand-composed a square master in PIL to dodge it — undocumented, non-reproducible.
- **Gap B — screenshots only capture the boot phase.** `package.mjs screenshot` boots `Main.tscn` and grabs frame N — always the opening state (GATHER for shopkeep). The skill talks about "a mid-combo frame, a near-miss," but the tool cannot *reach* those moments. The operator hand-authored `_shot_phases.gd` to drive `ShopState` through phases. No codified support.
- **Gap C — splash opaque-bg trap.** Documented in the skill, but the only mitigation offered is "prefer a transparent-bg master." The operator applied a "match the master's bg colour" trick that the skill does not name.

Underneath all three sits the real quality bar the owner asked for: **the icon must be genuinely app-store-grade**, not a game sprite slapped on a flat colour. A latent correctness bug compounds this: `adaptive_foreground` and `adaptive_background` currently both receive the **same** squished master, which is not a valid Android adaptive icon (the foreground must be a transparent subject inside a safe-zone; the background must be a separate fill).

## 2. Goals / Non-goals

**Goals**
- Icon becomes a **purpose-built, GPU-authored** asset with **correct Android adaptive layers** (transparent focal foreground + themed background fill + composited legacy/Play icons).
- Screenshots gain a **codified, packager-owned harness pattern** for capturing chosen gameplay moments, with a tool runner and a template.
- Splash composites cleanly from the transparent focal (Gap C dissolves).
- All changes are **proven by dogfood**: shopkeep-0001's store face is regenerated to the new bar and re-gated through validator Method 5 + owner A/B.

**Non-goals**
- No changes to `concept`, `builder`, `asset`, `audio`, or `validator` skills. Blast radius is the `packager` skill + `package.mjs` + Godot pixel scripts + tests.
- Not generating the adaptive **background** with AI — it is a deterministic code gradient (Android masks/parallax-shifts the bg, so simple is correct and CI-safe).
- Not changing the validator Method 5 contract — it still verifies committed PNGs headlessly with no GPU. Only the *authoring* of the icon now needs a GPU (same posture as `asset`).
- Not real Play submission (still owner-gated).

## 3. Design

### 3.1 Icon — bespoke focal + correct adaptive layers

**Authoring (GPU step, like `asset`):** generate a bespoke icon **focal** via `tools/comfy.mjs` + the asset checkpoint (Cartoon Arcadia XL) with **LayerDiffuse → transparent-bg RGBA**, square (1024²). The prompt comes from a new **icon prompt scaffold** codified in the skill, derived from `concept.theme`:

> *single bold focal subject · centered · generous empty margins · simple iconic shape · high contrast · flat/clean · NO text, NO words, NO scene/background, NO multiple objects*

(plus the title's own subject, e.g. "a single scallop shell" for Tide & Tally). Square generation eliminates the squish at the source; the transparent focal is the source of every icon layer.

`store_pass.icon_master` is redefined as **the transparent focal PNG** (e.g. `store/icon_focal.png`). The composition layer is **source-agnostic**: it composes from any transparent RGBA focal — a generated one (the documented method) or, as a no-GPU fallback, an existing transparent sprite. This is *not* a co-equal "tiered" path; bespoke generation is **the** method, the sprite path is only an honest fallback when ComfyUI is unavailable.

**Composition (headless, deterministic) — new `tools/godot/icon_compose.gd` (replaces `icon_resize.gd`):**
- `ic_adaptive_foreground` (432²): the transparent focal, contain-fit into Android's **~66% center safe-zone**, transparent elsewhere.
- `ic_adaptive_background` (432²): a **code gradient/solid** from `concept.theme` palette (vertical 2-stop gradient by default).
- `ic_launcher_mdpi … xxxhdpi` + `ic_play_store` (512): the focal **composited over the gradient fill**, opaque, square, then downscaled (Lanczos). Real figure/ground depth, not flat-on-flat.

**Tool shape:** `node tools/package.mjs icons <id> [--bg "#RRGGBB,#RRGGBB"]`. The bg spec is read from `--bg`, else from an optional `store_pass.icon_bg` string, else defaulted from the palette's first two entries. `icon_compose.gd` receives: focal path, outdir, the icon spec table (name:px:kind), and the bg gradient stops.

### 3.2 Screenshots — codified harness pattern (packager-owned)

**Runner:** `node tools/package.mjs screenshot <id> --script res://_shots.gd` runs a **game-provided capture script** on the **real renderer** and collects every `wrote <path>` it prints (asserting a final `SHOTS OK`). With no `--script`, the existing boot-only `screenshot.gd` remains the fallback.

**Pattern + template:** ship `tools/godot/shots.template.gd` and codify in the skill the pattern the operator improvised:
1. Clear `user://save.json` at start (persistence games inherit a later day otherwise — the known shopkeep save gotcha).
2. Boot `Main.tscn`, wait for the opening phase to settle, capture the **boot moment**.
3. For each further showcase moment, grab the view's state member (e.g. `main.S`) and **drive it exactly like `selftest` Stage 6** — set `phase` / collections / counters directly, call `main._rebuild_ui()`, wait frames, capture.
4. Clear `user://save.json` at end; print `SHOTS OK`.

The packager fills the template per game (state-driving is inherently game-specific), runs it, and records `store_pass.screenshots[]` as `{name, px, source}` (drop the tool's absolute `path`, add `px`).

### 3.3 Splash — clean from the transparent focal

`package.mjs splash <id> [#RRGGBBAA]` composites **the transparent focal** (not the opaque legacy icon) over a themed background at `splashSize(orientation)`. The opaque-bg trap disappears. The skill keeps the "match the master's bg colour" note only as the fallback for when an opaque master is unavoidable.

### 3.4 Schema

`store_pass.icon_master` stays a `string` (now the transparent focal path). Add **optional** `store_pass.icon_bg` (`string`, e.g. `"#2fa6a0,#1c7d78"`) — additive, `additionalProperties:false` already allows only declared keys so this is a one-line addition. No other schema change.

## 4. Testing

`tools/package.test.mjs` additions (pure-JS seam + dimension checks, no GPU):
- `icon_compose` produces every `iconSizeTable()` entry at exact px; `ic_adaptive_foreground` has transparent corners; `ic_adaptive_background` is fully opaque; legacy/Play icons are opaque and composited (corner pixel == bg gradient, center has focal coverage). Use a tiny synthetic transparent focal PNG as the fixture.
- `screenshot --script` runner invokes the provided script and returns the collected outputs; missing `SHOTS OK` is an error; no `--script` falls back to boot capture.
- `--bg` parse + palette-default derivation.

RED/GREEN: write the failing tests first, then implement `icon_compose.gd` + the `package.mjs` changes until green. Keep `vitest` green overall.

## 5. Dogfood (the proof, on shopkeep-0001)

1. Boot ComfyUI (asset checkpoint + LayerDiffuse present; reboot per the README/infra gotcha if wedged).
2. Generate the Tide & Tally icon focal (transparent scallop shell, icon scaffold) via `comfy.mjs`.
3. `package.mjs icons` → new adaptive fg/bg + composited legacy/Play; `splash` from the focal; re-capture the 3 screenshots via a committed `_shots`-pattern script.
4. Re-merge `store_pass` (new `icon_master` = focal, `icon_bg`), re-run **validator Method 5** (verify + verify-build regression + the icon-px/adaptive checks), owner cross-modal cohesion + icon aesthetic A/B.
5. Replace the "good enough for trial" shell-on-flat-teal with a genuinely app-store-grade icon; commit + push; update memory.

Status note: shopkeep is already `packaged`; the dogfood **re-runs the packaging pass** on it (a legitimate re-package, not a status regression). If an A/B fails, record the finding and iterate the scaffold — the skill improvement is the deliverable regardless.

## 6. Blast radius / files

- `.claude/skills/packager/SKILL.md` — icon = bespoke gen (scaffold + GPU posture; update the "ComfyUI is NOT needed" line to "needed only for the icon focal"); correct adaptive-layer composition; screenshot harness pattern + template; splash-from-focal; `icon_master` redefinition.
- `tools/package.mjs` — `icons` rework (`--bg`, focal+gradient composition), `screenshot --script` runner, `splash` from focal.
- `tools/godot/icon_compose.gd` — new (composites layers); `icon_resize.gd` retired or kept as a thin shim.
- `tools/godot/shots.template.gd` — new capture-harness template.
- `tools/package.test.mjs` — new tests.
- `schema/manifest.schema.json` — `+ store_pass.icon_bg` (optional string).
- Dogfood artifacts under `games/shopkeep-0001/` (focal, store/ regen) + manifest.

## 7. Risks & gotchas

- **GPU dependency creep.** The icon focal now needs ComfyUI. Mitigated: it's an authoring step (committed PNGs verified headlessly), identical to `asset`; the sprite fallback keeps a no-GPU escape hatch.
- **LayerDiffuse focal quality.** Icon subjects must be a single bold object; the asset skill's known failure modes (empty-frame collapse, "three X" → blob, white-pearl attractor) apply — the scaffold forces a single centered subject to sidestep them.
- **Adaptive safe-zone math.** Foreground must sit inside ~66% center or launchers crop it; encode the ratio as a named constant in `icon_compose.gd`.
- **Real-renderer screenshots.** The `--script` runner must NOT be `--headless` (dummy renderer captures nothing) — same constraint as today's screenshot path.
- **Infra.** `godot`/`GODOT_BIN` and `ANDROID_HOME` are not persisted across sessions (set `GODOT_BIN` to the winget console.exe; `ANDROID_HOME` to `…/Android/Sdk`). ComfyUI may wedge on first gen — kill PID + relaunch.
