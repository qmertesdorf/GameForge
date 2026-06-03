# POC run — deckbuilder-0001 `Arcane Duel`: landscape turn-based deckbuilder

**Date:** 2026-06-02 · **Skills exercised:** `concept` + `builder` (staged) + `validator` (Method 1 + Method 1.6) · **Target:** `deckbuilder-0001`, the project's first turn-based, systems-heavy, landscape-native title.

This run's purpose — consistent with the project's stated deliverable — was to surface what the skills *can't* yet handle for a turn-based genre, fix the responsible `SKILL.md`, and leave the loop permanently better at it. The game is the vehicle; the findings are the product.

> **Status: `validated` (held).** Methods 1 (headless clean run, exit 0, no script errors) and 1.6 (scripted-turn self-test, `SELFTEST OK`) both pass. **Pending owner gates:** human playtest (→ `playable`), SVG asset pass + A/B (→ `styled`), audio pass + A/B (→ `scored`).

---

## What ran

Following the normal skill loop:

1. **`concept`** — Arcane Duel concept block: 3-element combo (fire/ice/lightning), telegraphed intent, ~5-node run, pick-1-of-3 rewards, 2 relics, meta-save seed. Landscape (1280×720) declared in `build.orientation`. Committed `5bce10e`.

2. **`builder` — staged build** (see [Staged build](#staged-build) below): the genre is too large to one-shot. Built in dependency order across 7 commits, each stage gated by a growing `selftest.gd` before the next began:
   - Scaffold + failing selftest spine (`604c3d8`)
   - CardDB (~16 cards, 10-card starter) + EnemyDB — initially as autoloads (`d3faa7b`), then **immediately refactored** to static `preload` classes after the headless probe (`d569e7e`)
   - CombatState stage 1 — piles, mana, seeded RNG, Fisher-Yates, basic attack (`ce6d445`)
   - CombatState stage 2 — Burn/Chill, enemy turn, status tick, lightning combo (`f6f225d`)
   - MetaSave — `user://save.json` round-trip (`07e2ef7`)
   - RunController — 5-node run, reward picker, relic, boss meta-write (`aaae1e9`)
   - CombatView + Main — landscape layout, gradient bg, fanned hand, enemy silhouette, all primitives (`9d47c94`)
   - Juice pass — card arcs, number pop-ups, scaled shake, status pulses, death dissolve (`adc3de5`)
   - Enrage + draw event handlers added (two events initially unhandled; added for legibility) (`02716f2`)

3. **`validator`** — Method 1 (headless 120-frame run, exit 0, zero script errors) + Method 1.6 (scripted-turn `selftest.gd`, `SELFTEST OK`). Both passed. Status advanced to `validated` (`e7ff4ef`).

---

## Staged build

The staged decomposition — rules engine → data layer → orchestration → persistence → rendering — was the key structural choice. Each stage was gated by an assertion in `selftest.gd` before the next started:

| Stage | File | Self-test gate |
|---|---|---|
| 1 | `CombatState.gd` (piles, mana, basic attack) | Arcane Bolt spends mana and deals exactly 6 |
| 1.5 | CardDB/EnemyDB static + CombatState wiring | Data resolves; Bolt asserts clean |
| 2 | CombatState (Burn/Chill/lightning combo/enemy turn/ticks) | Burn applies; Lightning combo fires bonus; end_turn resolves enemy + ticks |
| 3 | MetaSave + RunController | Win → reward pick resolves + run advances; boss win writes save.json with unlocked card |
| 4 | CombatView + Main (landscape, primitives) | Headless 120-frame run exits 0, no script errors; `SELFTEST OK` |

This produced a clean build with **zero rule-leak into the view** (verified: `CombatView.gd` owns no combat arithmetic; all damage/status logic lives in `CombatState.gd`) and zero build-error loops on the final render stage — the staged guidance in `builder/SKILL.md` validated end-to-end.

---

## Findings — each attributed to the responsible skill

### 1. [HIGHEST VALUE] Headless `--script` SceneTree runs don't instantiate autoloads — `builder/SKILL.md`

**What happened:** `CardDB` and `EnemyDB` were initially registered as `[autoload]` entries in `project.godot` (the natural pattern). The first headless `selftest.gd` run probed `Engine.has_singleton("CardDB")` → `false`; `/root/CardDB` was absent. The data layer was completely unreachable.

**Root cause:** `godot --script` starts a minimal `SceneTree` that does NOT process the `[autoload]` section of `project.godot`. This is a property of the headless invocation mode, not a bug — but it silently breaks any turn-based build that expects global singletons in its self-test.

**Fix (commit `d569e7e`):** removed the `[autoload]` block; converted `CardDB`/`EnemyDB` methods to `static func`; all callers (CombatState, RunController, selftest) reach them via `const CardDB := preload("res://data/CardDB.gd")` + `CardDB.card(...)`. The `selftest.gd` header comment now documents this explicitly.

**Durable rule:** for any turn-based/headless-tested title, the data layer MUST be static-accessible via `preload` — the `[autoload]` block is incompatible with `--script` self-tests. This is the single most impactful builder finding for this genre class.

### 2. Determinism requires a seeded Fisher–Yates, not `Array.shuffle()` — `builder/SKILL.md`

**What happened:** the design spec called for a seedable RNG for deterministic self-tests. The natural GDScript shuffle is `Array.shuffle()`, which draws from the global `RandomNumberGenerator` and ignores any custom seed.

**Fix (commit `ce6d445`):** `CombatState.setup()` creates a `RandomNumberGenerator`, sets `.seed`, and shuffles the draw pile with an explicit Fisher–Yates loop using `rng.randi_range()`. The commit message names this explicitly: *"Fisher-Yates shuffle via seeded rng (not Array.shuffle)"*.

**Durable rule:** `Array.shuffle()` uses the global RNG; it cannot be seeded. Every RNG path in a headless-tested game must use an explicit `RandomNumberGenerator` instance with a known seed, shuffled via Fisher–Yates.

### 3. Self-tests with persistent side-effects must reset that state — `builder/SKILL.md`

**What happened:** the boss-win meta test calls `MetaSave.save_state(...)` writing `user://save.json`, then asserts that `unlocked_cards` is non-empty. A stale `save.json` from a prior test run would false-positive that assertion without any boss kill actually having occurred.

**Fix (in `selftest.gd`):** immediately before the boss-defeat assertion, the self-test deletes `user://save.json` if it exists (`DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))`). The subsequent meta-write reflects only the current run.

**Durable rule:** any self-test that asserts on file-persistent state must reset that file before the relevant assertion, or a stale file from a prior run silently validates the wrong thing.

### 4. Input-driven animation paths are invisible to the headless gate — `builder/SKILL.md` (awareness note)

**What happened:** the headless runs (`--quit-after` and `--script`) feed no `InputEvent`, so `CombatView.gd`'s entire card-play, hover-lift, arc-to-center, and discard-sweep animation paths never fire during validation. A mismatch between the event `type`/payload keys the engine emits and what the view listens for would silently drop juice — no gate would catch it.

**What we did:** cross-checked `CombatView.gd`'s event listeners against every event dictionary `CombatState` returns. Two events (`draw`, `enemy_enrage`) were initially unhandled; handlers were added in commit `02716f2` for legibility. The mapping is now correct.

**Awareness note for builder:** the headless gate does NOT exercise view←engine event wiring. After writing the view, read both the engine's returned event dicts and the view's listener switch and manually verify the keys match. This check cannot be automated without a real input stream.

### 5. GDScript `:=` inference fails at parse time for not-yet-defined methods — `builder/SKILL.md`

**What happened:** `var n := run.current_node()` was written before `RunController` was defined. GDScript parse-time inference cannot resolve the return type, producing a type-inference error rather than a runtime one. This is distinct from the existing Variant-inference rule (which covers `Array`/`Dictionary` indexing).

**Fix:** use an explicit annotation: `var n: Dictionary = run.current_node()`. When the callee isn't yet visible in the parse pass, always annotate the receiver explicitly.

**Durable rule:** `:=` inference fails at parse time when the called method isn't yet defined. In a staged build where a later stage calls an earlier one, annotate explicitly rather than relying on inference.

### 6. The staged rules/rendering decomposition worked — `builder/SKILL.md` (confirmed)

The decomposition guidance added to `builder/SKILL.md` before this build was validated end-to-end. Seven committed stages, each gated, produced:
- **Zero rule-leak into the view** — `CombatView.gd` reads state and replays events, never computes rules.
- **Zero build-error loops on the final render stage** — by the time CombatView was written, all rules were proven correct.
- **A self-test that exercises the full rules path** before any rendering existed.

This is the strongest possible confirmation: the guidance held on a real, complex, first-of-genre build.

### 7. Orientation lever works end-to-end — `builder/SKILL.md` (confirmed)

`build.orientation:"landscape"` in the manifest flowed correctly through the orientation-aware builder scaffold (`viewport_width=1280`, `viewport_height=720`, `window/handheld/orientation="landscape"`) to a coherent wide layout. The `asset` skill was already orientation-aware; `builder` and `validator` (`splashSize(orientation)`) are now too. The pipeline is orientation-aware; `deckbuilder-0001` is the proof.

---

## Quality observation (pending owner playtest)

The primitive landscape layout already reads as an intentional toy: an indigo→violet gradient background with a runic floor circle and floating motes, a polygon enemy silhouette with HP bar and intent telegraph above it, element-colored card frames in a fanned hand along the wide bottom, player HP/mana orbs bottom-left, and an Ember Heart relic visible as a Burn stack at combat start. The combo system (fire→set up Burn; lightning→cash it in for bonus damage) fires and is tested by `selftest.gd`. Whether the game is *fun* is a human judgment — that's the playtest gate.

---

## What is NOT yet done (owner-gated)

| Gate | Required action | Status advance |
|---|---|---|
| Human playtest (~60 s) | Owner plays a run, confirms the loop is legible and the combo reads | `validated → playable` |
| SVG asset pass + A/B | `asset` skill re-skins cards, enemy, background per the arcane-sigil art direction | `playable → styled` |
| Audio pass + A/B | `audio` skill generates per-element SFX + melodic arcane BGM (locked settings) | `styled → scored` |
| Packaging | `packager` — orientation-aware splash/screenshot dims (landscape) + Android export | `scored → packaged` |

---

## Success criteria

1. ✅ `concept` block populated; manifest valid.
2. ✅ `builder` ran the staged build across 7 committed stages with a growing self-test gate at each.
3. ✅ Rules/rendering seam is clean — `CombatView` owns no rules (verified by reading both files).
4. ✅ Method 1 (headless clean run) + Method 1.6 (scripted-turn `selftest.gd`, `SELFTEST OK`) both pass.
5. ✅ Every shortfall above is legible and attributed to the responsible skill, with the exact edit it implies.
6. ✅ Durable findings #1–#5 folded into `builder/SKILL.md` (this task).
7. ⏳ **PENDING OWNER** — playtest → `playable`; then asset A/B → `styled`; then audio A/B → `scored`.

---

## Next

- ⏳ **Owner gate:** play `deckbuilder-0001` from first combat through at least a rest node (~60 s), confirm the loop is legible and the Fire→Lightning combo reads → advance to `playable`.
- ⏳ SVG asset pass (card frames, enemy silhouettes, background) → `styled`.
- ⏳ Audio pass (per-element SFX + arcane BGM) → `scored`.
- ✅ Findings #1–#7 folded into `builder/SKILL.md` (this task).
