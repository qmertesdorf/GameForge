---
name: packager
description: Use when turning a fully-polished Godot title (both a confirmed visual asset_pass AND audio_pass) into the inputs an Android store build needs — launcher icons at every density, the Play 512 + adaptive layers, a boot splash, gameplay screenshots, a texture atlas, an asset size-budget report, and an Android export preset. Derives the packaging set from concept.theme, records store_pass, and hands off to validator's packaging gate for "packaged".
---

# packager

Turn a folder of mobile-grade assets into the **inputs a shippable Android build needs**, with the same legible-attribution discipline as every prior milestone: a re-runnable tool (`tools/package.mjs` + the `tools/godot/` pixel scripts) that derives the packaging set from the manifest, records it in `store_pass`, and is gated by `validator` Method 5. This runs as a title-level bolt-on **after** a game has both its visual and audio identity:

```
… → asset → [styled] → audio → [scored] → packager → validator(Method 5) → [packaged]
                                                                                 └→ (later) APK feasibility gate → store submission (owner)
```

## Inputs (both polish passes required)

- `manifests/<id>.json` carrying **both** an `asset_pass` (visual identity, owner A/B-confirmed → the game reached `styled`) **and** an `audio_pass` (audio identity, owner A/B-confirmed → the game reached `scored`). A primitive-art or silent game is **not** store-ready — both identities are mandatory (spec §2). The canonical incoming status is `scored`.
- The game on disk at `games/<id>/`, with its committed raster art under `games/<id>/art/`.
- The pinned Godot from `README.md` (`tools/package.mjs` spawns it for the pixel ops). ComfyUI **is** needed — but only for the single GPU step: generating the bespoke transparent icon focal. Everything else (atlas, screenshots, splash composite, budget, preset, build) reuses existing art or is fully deterministic.

## Outputs

- `games/<id>/store/icons/*.png` — every `iconSizeTable()` entry (launcher mdpi→xxxhdpi, Play 512, adaptive fg/bg 432).
- `games/<id>/store/atlas.png` + `games/<id>/store/atlas.json` — the texture atlas + coordinate map.
- `games/<id>/store/screenshots/*.png` — gameplay frames at the game's portrait resolution (the tool saves whatever the running game renders — `builder` ships 720×1280; it does not resize to a fixed Play-store target).
- `games/<id>/store/splash.png` (and the Godot `boot_splash` config).
- `games/<id>/export_presets.cfg` — a valid Android export preset.
- A populated `store_pass` block (icons, splash, screenshots, atlas, size_budget, export_preset, icon_master, notes).
- Hand-off to `validator` — **do not** set `packaged` yourself.

## Step 0 — Derive the packaging set FIRST (the real deliverable)

Like `asset`/`audio` Step 0, write the packaging decisions down **before** generating anything, anchored to `concept.theme` (premise/tone/mood_keywords/setting — the same modality-neutral world the visuals and audio express). The icon, splash, and screenshots are the title's **store face**; they must read as *that theme's world*, not a fourth independent interpretation. Decide and record verbatim in `store_pass`:

- **Icon master** — a **bespoke transparent focal** generated via `tools/comfy.mjs` + the asset checkpoint with **LayerDiffuse** (RGBA), square (1024²), recorded as `store_pass.icon_master` (e.g. `store/icon_focal.png`). Build the prompt in **four parts — subject → genre style → finish → palette — all derived from `concept.theme`** (these encode what ASO research finds in top-grossing game icons; the icon is one of the highest-CTR assets we ship):

  **1. Subject — the biggest CTR lever.** Pick exactly ONE dominant subject and crop it tight so it **fills ~70 % of the frame** (60–80 %), centered, edge-bleed allowed. A small subject adrift in empty canvas is the #1 amateur tell.
  - If the theme has a **character / mascot / creature**, lead with its **face**: a forward or 3⁄4-angle head with a clear **emotion** and **eyes meeting the viewer**. A face is an "eyeball magnet" and out-reads any object at thumbnail size. If the whole body would shrink the face below recognisable, **crop to just the head/face**.
  - If the theme's hero is an **object** (a sim/puzzle/cozy title with no character — e.g. shopkeep's shell), use that **single iconic hero object**, oversized and centered. Still ONE object, never a collection or a scene.

  **2. Genre style** — branch the expression/lighting/palette on `concept.theme` tone + genre:
  - **action / strategy / mid-core** → an **intense** face (angry / yelling / determined), 3⁄4 angle, dramatic rim light, **dark-saturated** palette (deep reds / golds / blues).
  - **cozy / casual / sim / match-3** → a **friendly, delighted / smiling** face *or* a glossy hero object, **warm-bright** palette, soft cheerful candy-gloss lighting.
  - **puzzle / word / arcade** → a **single iconic object or one giant glyph** on a clean radial-glow plate, maximally saturated, bold simple shape.

  **3. Finish (fixed — the app-store "mini-poster" look):** `glossy, dimensional, 3D-style cartoon · soft studio lighting · bright specular highlight + rim light + soft drop shadow · simple iconic silhouette · NO text · NO words · NO scene/background · NO multiple objects`. This is deliberately **more polished/glossy than the flat in-game sprites** — the icon is the store face; a flat scaffold yields a flat, un-app-storey icon (the dogfood needed `glossy · dimensional · 3d-style · studio lighting · highlight` to land it).

  **4. Palette:** restrain to **2–3 colours with ONE signature dominant hue** (shelf recognition), saturated. Keep the **subject's hue distinct from the icon background** so it pops — `icon_compose` draws the bg from the theme palette and `resolveIconBg` forces it to contrast the focal (see below), so choose a focal hue that reads as the complement of, not a sibling of, that background.

  (`comfy.mjs` checkpoint must be the **exact filename** incl. `.safetensors`, e.g. `cartoonArcadiaXL_v2.safetensors` — a newer ComfyUI rejects the bare name.)

  `icon_compose` builds the adaptive layers from this focal: the transparent foreground is placed inside the ~66% Android safe zone; the background defaults to a **radial glow + edge vignette** (the app-store look — `--bg-style linear` for the old flat gradient) behind the subject, with a **soft contact shadow** under the focal on the legacy/Play composites. The background colour is auto-derived from the `concept.theme` palette and **conditioned by `resolveIconBg`**: it is forced into a deep, saturated band that survives both light and dark store chrome, and — using the focal's dominant hue (probed by `focal_hue.gd`) — rotated to the subject's **complement** when the two would clash, so the subject always pops. An explicit `--bg "#top,#bottom"` or recorded `store_pass.icon_bg` is treated as a deliberate choice and used **verbatim** (no conditioning). This also fixes the old bug where the adaptive foreground and background were identical (square-stretched sprite used for both). The **final** icon/splash art is an **owner aesthetic A/B**, recorded as deferred in `notes`.

  **Legibility gate (48 px).** `icons` auto-runs `legibility` (`icon_legibility.gd`): it downscales the Play composite to 48 px and scores the **CIELAB ΔE** between the centred subject and the corner plate (ΔE, not luminance — a complementary pairing like coral-on-teal reads high-contrast yet has near-equal luminance). A ΔE below the floor prints a `LEGIBILITY WARN` (the subject won't pop at thumbnail size — enlarge it or push its colour further from the background). It is **advisory**: record a WARN in `store_pass.notes` and prefer to fix it, but it does not block the build.

  **Where the focal lives:** `comfy.mjs gen <id> icon_focal …` writes to `games/<id>/art/icon_focal.png`. **Move it to `games/<id>/store/icon_focal.png`** before composing — `atlas` packs every `art/*.png`, so a focal left under `art/` pollutes the sprite atlas. Set `store_pass.icon_master` to `store/icon_focal.png`.
- **Splash** — the boot image and whether to show it.
- **Screenshots** — which gameplay moments read best in a store listing (e.g. a mid-combo frame, a near-miss).
- **Atlas membership** — which sprite PNGs pack into the atlas.
- **Size budget** — the per-title byte budget (default 50 MiB; override via `GAMEFORGE_SIZE_BUDGET` or the tool opt).

## Flow

Run the tool (it pairs the pure JS seam with the Godot pixel scripts, exactly like `comfy.mjs`):

```
node tools/comfy.mjs gen <id> icon_focal '<recipe-json>'   # bespoke transparent icon focal (LayerDiffuse, square 1024², icon scaffold) -> games/<id>/art/icon_focal.png
mv games/<id>/art/icon_focal.png games/<id>/store/icon_focal.png   # keep the focal OUT of the sprite atlas; set store_pass.icon_master to store/icon_focal.png
node tools/package.mjs icons <id> [--bg "#top,#bottom"] [--bg-style radial|linear]   # focal -> adaptive fg/bg + composited legacy/Play; radial glow + drop shadow + auto-contrast bg by default; auto-runs the 48px legibility check
node tools/package.mjs legibility <id>   # ASO 48px ΔE check: does the subject still pop at thumbnail size? (also auto-run by `icons`; advisory WARN)
node tools/package.mjs atlas <id>        # pack art/*.png → store/atlas.png + atlas.json (headless Image)
node tools/package.mjs screenshot <id> --script res://_shots.gd   # run the game's capture harness on the REAL renderer
node tools/package.mjs splash <id> [#RRGGBBAA]   # composite the icon master onto a themed bg → store/splash.png (headless Image); pick the bg from concept.theme
node tools/package.mjs budget <id>       # sum store assets vs the budget (run AFTER icons/atlas/screenshot/splash so it includes them)
node tools/package.mjs preset <id>       # print the Android export_presets.cfg (redirect into games/<id>/export_presets.cfg)
node tools/package.mjs build <id>            # build the debug APK via headless Godot (toolchain-guarded: skips with exit 3 if ANDROID_HOME unset)
node tools/package.mjs build <id> --release --aab   # build the signed release AAB (needs tools/android-signing.local.json)
```

`screenshot <id> <name> [frames]` still works as the boot-only fallback (no harness script needed), but the `--script` form is preferred: it drives the game's own capture harness through showcase moments rather than capturing a single boot frame.

Then record `store_pass` (arrays replace wholesale — pass the full set):

```
node tools/manifest.mjs merge <id> "{\"store_pass\": { \"icon_master\": \"store/icon_focal.png\", \"icon_bg\": \"#top,#bottom\", \"icons\": [ … ], \"splash\": { … }, \"screenshots\": [ … ], \"atlas\": { … }, \"size_budget\": { … }, \"export_preset\": { \"path\": \"export_presets.cfg\", \"platform\": \"android\", \"package\": \"com.gameforge.<id>\" }, \"build_artifact\": { … }, \"notes\": \"…\" }}"
node tools/manifest.mjs validate <id>
```

Record `store_pass.build_artifact` from the `build` command's JSON (format, build_type, path, bytes, package). If the build skipped (exit 3, no Android toolchain), omit `build_artifact` and note the deferred toolchain gate — do not fabricate a record.

## Hard requirements & honesty

- **Headless vs real renderer.** Icon resize + atlas composite use Godot's `Image` API and run **headless**. Screenshots **must not** be headless — the dummy renderer captures no pixels; `package.mjs` runs the harness on the real Vulkan renderer (see the `asset` raster note + `godot-binary-path`).
- **Capture-harness pattern.** Copy `tools/godot/shots.template.gd` → `games/<id>/_shots.gd`. Edit the `const PHASE` preload and drive the view's state to each showcase moment the same way `selftest` Stage 6 does: set phase/collections directly, call `main._rebuild_ui()`, then capture. Clear `user://save.json` at the start and end of the script so each run is clean. The harness prints `wrote <path> (WxH)` per frame and `SHOTS OK` on completion. Commit `_shots.gd` alongside the game — it is a permanent artifact like `selftest.gd`, not a throwaway.
- **Recording screenshots — assemble the schema shape, don't paste tool output.** `package.mjs screenshot` returns `{name, source, path}`, but `store_pass.screenshots[]` records `{name, px, source}` (schema-validated). When you merge, **drop the tool's `path`** (it's an absolute disk path) and **add `px`** as the captured `"WxH"` (e.g. `"720x1280"`). Pasting the tool's object verbatim fails the very next `validate` step (extra `path`, missing `px`). (This applies to **boot mode**. The `--script` runner instead returns `{ script, shots: [{name, px, source}] }` — the `shots[]` entries are **already** schema-compliant; record `shots` directly as `store_pass.screenshots`, not the outer object.)
- **Mobile density.** Every launcher density comes from **downscaling** the high-res master, never upscaling — that is the app-store readiness the raster masters were sized for.
- **Boot splash.** `splash` composites the icon master (~60%, centered) onto a themed solid background at the canonical portrait size (`splashSize()` → 1080×1920) and returns the `boot_splash_cfg` block for `project.godot`'s `[application]` section. `store_pass.splash` records only `{source, show_image}`; splicing `boot_splash_cfg` into the game's `project.godot` is applied at **real-package time** alongside the export preset (the foundation commits the asset + record, not the runtime project change). The v2 icon focal is **transparent**, so the splash composites cleanly over whatever background colour you choose — no opaque-bg bleed. The old caution ("A splash composited from a master with an opaque background will show that background") applies only as a fallback when an opaque master is unavoidable; prefer the transparent focal.
- **IP safety.** The icon/splash/screenshots inherit the art's IP posture; do not introduce franchise/character/studio likenesses. The owner aesthetic A/B is the final IP review (same as `asset`).
- **Do not** edit `concept`, `builder`, `asset`, or `audio`. Consume `concept.theme` + the two pass blocks as-is.
- **Do not** set `packaged` — hand to `validator`.

## Deferred (named gates — track, do not fake)

- **APK/AAB build is now in scope** (no longer deferred): `node tools/package.mjs build <id>` shells out to headless Godot, guarded by `ANDROID_HOME`. On a toolchain-equipped machine it produces a debug APK (and `--release --aab` a signed AAB) and records `store_pass.build_artifact`. Without the SDK it skips cleanly (exit 3) — the same no-GPU/no-ComfyUI posture. The one-time machine setup (debug keystore, Godot editor SDK path, AVD) is documented in `README.md` → "Android export" + `tools/android-setup.ps1`.
- **Real store submission** (Play developer account, release-keystore custody, listing copy, content rating, legal) → owner-gated. The signed AAB is built locally now; uploading it is the owner step (Play developer account, release-keystore custody, listing copy, content rating, AAB upload).
- **Icon/splash aesthetic A/B** → owner-gated, like every art/audio A/B.

## Hand off to the validator

Hand off to `validator`, which runs **Method 5 — packaging gate** (both pass blocks present + A/B-confirmed; every icon at its exact px; atlas map covers every member; budget passes; export preset parses; headless run still clean; cross-modal cohesion A/B) and advances `scored → packaged` on success, or records legible `issues` (attributed to `packager`/`package.mjs`) and stops.
