# M2 — store-readiness (foundation) — design

**Date:** 2026-05-31 · **Milestone:** M2 (foundation slice) · **Status:** design approved, spec under review.

Builds on the GameForge POC + M1 (SVG re-skin), M1.5 (raster), M1.6 (audio). This is the **foundation** slice of M2 as named in the M1.5 roadmap (`docs/superpowers/specs/2026-05-31-m1.5-raster-asset-design.md` §12): *"app icon (+ all required sizes), splash, store screenshots, texture atlasing, APK size budget, Godot Android export presets — the title-level packaging that turns a folder of mobile-grade assets into a shippable build."*

## 1. Goal

Turn a folder of mobile-grade assets into the **inputs a shippable Android build needs**, with the same legible-attribution discipline as every prior milestone: a re-runnable tool + skill that derives the packaging set from the manifest, records it, and is gated by checks that attribute any failure to specific prose.

In scope (the **foundation**), every item CI-testable or headlessly verifiable **without the Android SDK**:

- **App icons** — all Android launcher densities (mdpi 48 → xxxhdpi 192), the 512² Google Play hi-res icon, and adaptive-icon layers (foreground/background at 432²).
- **Boot splash** — Godot `boot_splash` config + asset.
- **Store screenshots** — gameplay frames captured at Play Store dimensions, reusing the `SceneTree` screenshot harness (the real Vulkan renderer; `--headless`'s dummy renderer cannot capture pixels).
- **Texture atlas** — pack a game's sprite PNGs into one atlas with a coordinate map.
- **Asset size budget** — sum the shippable asset bytes, compare to a per-title budget, report a per-file breakdown and pass/fail.
- **Android export preset** — generate a valid `export_presets.cfg` for the game.

Explicitly **deferred to named gates** (not built or run this cycle):

- **The actual APK build** (`godot --headless --export-debug`) → an **Android-toolchain feasibility gate** (§8): needs the Android SDK + JDK, which are not configured here (`ANDROID_HOME`/`ANDROID_SDK_ROOT` are empty). This is the exact pattern of the ComfyUI gate (M1.5) and the Stable-Audio gate (M1.6) — an external toolchain stood up separately, then a one-shot pass/fail.
- **Icon / splash aesthetic A/B and real store submission** (account, signing keys, listing copy, legal) → **owner-gated**, like every art/audio A/B.

## 2. Pipeline placement

Packaging is a title-level bolt-on **after** a game has its art and audio identity (`styled` and/or `scored`):

```
… → asset → [styled] → audio → [scored] → packager → validator(packaging gate) → [packaged]
                                                                                       └→ (later) APK feasibility gate → store submission (owner)
```

`packaged` is a new **terminal** status, reached only after **both** polish passes are complete: the visual pass (`asset_pass`, owner A/B → `styled`) **and** the audio pass (`audio_pass`, owner A/B → `scored`). A primitive-art or silent game is not store-ready, so both identities are mandatory.

Because `status` is a single string that holds only one of `styled`/`scored` at a time, the gate keys off the **presence of both `asset_pass` and `audio_pass` blocks** — the source of truth the asset/audio skills already designate (*"the pass block, not the status string"*) — not the lossy status value. Audio is *orthogonal* (the audio skill lets a merely-`playable` game advance to `scored`), so reaching `scored` alone does **not** imply the visual pass happened — the gate checks for both blocks, each A/B-confirmed, explicitly. The canonical path is `playable → styled → scored → packaged`. For the foundation proof the tooling still runs against the current substrate regardless of status; the **end-to-end** `… → packaged` proof is gated on both owner A/Bs + the APK gate (§8, §9).

## 3. Architecture — the tested seam (matches `comfy.mjs`)

The whole codebase pairs a **pure, CI-tested JS seam** with an **external engine/server that does the heavy lifting**. M2 follows it:

- **`tools/package.mjs`** — pure, deterministic, vitest-tested functions, no GPU/SDK/engine:
  - `iconSizeTable()` → the canonical list of required icon outputs `{ name, px, kind }` (launcher densities, Play 512, adaptive 432 fg/bg).
  - `sizeBudget(files, budgetBytes)` → `{ total, perFile[], pass }` from a list of `{ path, bytes }`.
  - `exportPresetCfg(opts)` → a valid Android `export_presets.cfg` string from `{ name, package, icon paths, … }`.
  - `atlasLayout(rects)` → bin-packing of `{ name, w, h }` into `{ sheet:{w,h}, placements[] }` (shelf/MaxRects — deterministic, no pixels).
  - A CLI mirroring `comfy.mjs`: `node tools/package.mjs --check <id>` and subcommands that orchestrate the Godot-side pixel ops.
  - **Loud-failure contract:** throws with context, writes no partial output on error (same as `comfy.mjs`).
- **Godot-headless pixel scripts** (the engine is already the dependency; no Android SDK needed) — invoked by `package.mjs` for the operations that need real pixels:
  - resize a master PNG into each icon output (`Image.load` → `resize` → `save_png`),
  - render the atlas texture from `atlasLayout`'s placements,
  - capture screenshots at Play dimensions via the `SceneTree` harness.

This keeps everything that *can* be unit-tested in CI (the tables, math, config generation, packing layout) pure and network-/GPU-free, exactly like `comfy.mjs`'s `injectRecipe`.

Environment knobs (mirror `comfy.mjs`): `GAMEFORGE_GAMES_DIR` (default `games/`); an optional `GAMEFORGE_SIZE_BUDGET` override; Godot located via the README-pinned binary.

## 4. Schema / manifest changes (additive, non-breaking)

Promote the reserved `_reserved.store` slot into a first-class **`store_pass`** block, parallel to `asset_pass` / `audio_pass`:

```jsonc
"store_pass": {
  "icons": [ { "name": "ic_launcher_xxxhdpi", "px": 192, "kind": "launcher", "source": "store/icons/…png" }, … ],
  "splash": { "source": "store/splash.png", "show_image": true },
  "screenshots": [ { "name": "screen-1", "px": "1080x1920", "source": "store/screenshots/…png" }, … ],
  "atlas": { "sheet": "store/atlas.png", "map": "store/atlas.json", "sprite_count": 4 },
  "size_budget": { "total_bytes": 0, "budget_bytes": 0, "pass": true, "per_file": [ … ] },
  "export_preset": { "path": "export_presets.cfg", "platform": "android", "package": "com.gameforge.<id>" },
  "icon_master": "art/<hero>.png",
  "notes": "…"
}
```

- Add **`"packaged"`** to the `status` enum: `["concept","generated","validated","playable","styled","scored","packaged","failed"]`.
- `_reserved.store` either becomes `store_pass` or is left reserved and `store_pass` added at top level — chosen at plan time to keep `tools/manifest.mjs` untouched (free-string/array-replace handling, like the M1.5 additions). No change to top-level `required`.
- All additions are additive: existing manifests still validate.

## 5. The `packager` skill (new)

A new skill, branching on what the game has (like `asset` branches on `art_direction`):

- **Inputs:** a manifest with **both** `asset_pass` and `audio_pass` recorded and A/B-confirmed (per §2 — visual *and* audio identities complete); the game on disk; the pinned Godot.
- **Step 0 — derive the packaging set first** (the real deliverable, mirroring asset/audio Step 0): pick the **icon master** (a styled hero/character sprite, or a deliberately-composed master), the splash, which gameplay moments make good screenshots, the atlas membership, and the size budget for this title — recorded verbatim in `store_pass` so it is reviewable.
- **Flow:** run `package.mjs` (size table, budget, preset, atlas layout) + the Godot pixel scripts (icon resize, atlas render, screenshot capture) → write outputs under `games/<id>/store/` → record `store_pass` → hand off to `validator`.
- **Icon-master honesty:** for the foundation proof the master is *derived* from an existing sprite; the **final** icon/splash art is an **owner aesthetic A/B**, recorded as deferred in `notes` (the inverse of the asset skill's "flag what SVG does badly").
- **Do not** set `packaged` itself; hand to `validator`.

## 6. Validator extension — the packaging gate (Method 4)

Generalize `validator` with a packaging method that asserts, **headlessly and without the SDK**:

- **both `asset_pass` and `audio_pass` are present and each was owner-A/B-confirmed** — the §2 "both identities required" gate, checked via the pass blocks (the source of truth), **not** the lossy `status` string;
- every entry in `iconSizeTable()` exists at its **exact** pixel dimensions,
- the atlas image exists and its map covers every member sprite,
- `size_budget.pass` is true (total ≤ budget),
- `export_presets.cfg` exists and **parses** as a valid Godot preset,
- the game still imports + runs headless clean (regression guard).

On success advances the game → **`packaged`** (requires both pass blocks present + A/B-confirmed, per §2; the canonical incoming status is `scored`); on failure records legible `issues` (attributed to `packager` or `package.mjs`) and stops. The **icon/splash aesthetic A/B** and the **real APK build** are explicitly noted as the owner gate and the §8 feasibility gate — not asserted here.

## 7. Determinism & git

- Generated icons/atlas/screenshots are committed (canonical, like the raster PNGs); `*.png` is already `binary` in `.gitattributes`.
- `atlasLayout` and `iconSizeTable` are deterministic; `package.mjs` outputs are reproducible. Godot `Image.resize` is deterministic for a given master + interpolation mode (record the mode).
- `export_presets.cfg` is text and diffable.

## 8. Feasibility gate (deferred — Android toolchain)

Not run this cycle. When the owner stands up the toolchain: install the Android SDK + a compatible JDK, set `ANDROID_HOME`/`ANDROID_SDK_ROOT`, point Godot's editor settings at the SDK + the 4.6.3 export templates (already installed), then produce a debug APK:

```
godot --headless --path games/<id>/ --export-debug "Android" build/<id>-debug.apk
```

Pass/fail = a signed debug APK that installs and launches on a device/emulator. This is the exact shape of the M1.5 ComfyUI gate and the M1.6 Stable-Audio gate (`docs/superpowers/m1.5-feasibility-notes.md`): an external toolchain stood up once, a single decisive pass/fail, findings folded back into the skill/tool. Documented in a `docs/superpowers/m2-feasibility-notes.md` when run.

## 9. Proof run (deferred end-to-end; foundation lands now)

The end-to-end packaging proof — a **`scored`** game taken to **`packaged`** with a real APK — needs (a) a scored game (owner-gated) and (b) the §8 toolchain gate. So the *proof* is a clean bolt-on later, written up as the next `poc-run-NNN.md` at that time.

**This cycle delivers the foundation** so that proof is unblocked: `tools/package.mjs` + tests, the Godot pixel scripts, the `packager` skill, the `validator` packaging method, and the schema additions. The tooling is exercised against the current substrate (a `validated` proof game) to confirm it runs and the gate's CI-checkable assertions pass, without claiming a `packaged` status (illegal from `validated`).

## 10. Testing

- **`tools/package.mjs`** — vitest, pure (no GPU/SDK/engine): `iconSizeTable` completeness + exact px, `sizeBudget` math + pass/fail boundary, `exportPresetCfg` produces a parseable preset, `atlasLayout` packs without overlap and fits the sheet, error/loud-failure paths. Consistent with the all-JS, no-GPU-in-CI suite.
- **Schema additions** — covered by existing manifest-validation tests (new `store_pass` accepted; existing manifests still valid; `packaged` accepted).
- **Pixel output** (icon fidelity, atlas correctness on screen, screenshot framing) and the **APK** — gated by the §8 feasibility gate + owner aesthetic A/B; not automatable in CI.

## 11. M2-foundation scope (what this cycle delivers)

In scope:

- `tools/package.mjs` — the tested seam (icon table, size budget, export-preset generation, atlas layout) + CLI.
- Godot-headless pixel scripts — icon resize, atlas render, screenshot capture (no SDK).
- The **`packager`** skill + the **`validator`** packaging method (Method 4).
- Additive schema (`store_pass`, `packaged` status); committed outputs under `games/<id>/store/`.
- vitest coverage for `package.mjs`; manifest-validation coverage for the schema.

Explicitly **not** in this cycle (tracked, not silent):

- **Actual APK build** → §8 Android-toolchain feasibility gate (needs SDK+JDK).
- **Icon/splash aesthetic A/B, store listing copy, signing keys, real submission** → owner-gated.
- **iOS / other platforms, Play Console automation, CI APK builds** → out of scope; revisit only when Android end-to-end is proven.

## 12. Roadmap fit

M2 is the destination the M1.5 spec (§12) was paving toward; M1.5's per-asset density work is its down payment. This foundation slice makes the title-level packaging reachable and CI-verifiable without prematurely pulling in the Android toolchain, leaving two clean, well-named gates (the APK feasibility gate; the owner aesthetic A/B + submission) between here and a shipped build.
