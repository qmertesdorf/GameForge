# Arcane Deckbuilder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `deckbuilder-0001` — a landscape wizards' arcane-duel roguelike deckbuilder — through the GameForge loop, and upgrade the `builder` / `validator` / `asset` skills (plus schema/tooling) to handle a turn-based, UI-heavy, landscape genre the loop has never produced.

**Architecture:** Two co-equal tracks. **(A) Pipeline upgrades** — pure, vitest-backed edits to `schema/manifest.schema.json` and the `SKILL.md` files that make the loop orientation-aware and turn-based-aware. **(B) The game** — driven through `concept → builder → validator → asset → audio`, where a deterministic `selftest.gd` (seeded RNG, scripted turns) is the acceptance gate for the rules engine, and the build is decomposed into stages (`CombatState` → cards/elements → run/map → rewards/relics → meta) so the `builder` skill can produce each without one-shotting the whole game. Rules (`CombatState`, pure/headless) are fully decoupled from rendering (`CombatView`, owns juice).

**Tech Stack:** Godot 4.6.3.stable (GDScript), Node-based GameForge tooling (`tools/manifest.mjs`, `tools/package.mjs`, vitest), SVG art path (authored inline), ComfyUI/Stable Audio Open for audio (locked settings). Windows / PowerShell host.

**Spec:** `docs/superpowers/specs/2026-06-02-arcane-deckbuilder-design.md` (committed `fe5bb90`).

**Resolved open items (spec §8):**
- Manifest `id` = `deckbuilder-0001`. Concept block stays high-level; card pool / run nodes live as Godot data autoloads in the game (`games/deckbuilder-0001/data/`), **not** as new manifest fields — avoids bloating the `additionalProperties:false` `concept` schema.
- Orientation lives in a **new additive `build.orientation`** enum (`"portrait"|"landscape"`). Absent ⇒ portrait (back-compat with all 9 existing manifests). `builder` reads it for viewport + `window/handheld/orientation`; `validator`/`packager` splash/screenshot dims are parameterized via a `splashSize(orientation)` seam (packager-side staging owner-gated, but the seam + test land here so it isn't lost).
- `builder` one-shot vs staged: **staged** (Phases 4–8), and the decomposition is codified into `builder/SKILL.md` (Task 3) as the durable skill win.
- Turn-based validation: new **Method 1.6** in `validator/SKILL.md` (Task 5) + scripted-turn `selftest.gd` guidance in `builder/SKILL.md` (Task 3).
- Art: **SVG** path (Task 19) — geometric sigils / card frames / enemy silhouettes are SVG-native (`asset` skill already orientation-aware).

---

## File structure

**Pipeline (track A):**
- `schema/manifest.schema.json` — add `build.orientation` enum (Task 1).
- `tools/manifest.test.mjs` — orientation validation tests (Task 1).
- `tools/package.mjs` — `splashSize(orientation)` + landscape screenshot dims (Task 2).
- `tools/package.test.mjs` — orientation dimension tests (Task 2).
- `.claude/skills/builder/SKILL.md` — orientation-aware scaffold + staged-build decomposition + turn-based `selftest.gd` guidance (Task 3).
- `.claude/skills/validator/SKILL.md` — Method 1.6 turn-based logic self-test + orientation note (Task 5).
- `.claude/skills/asset/SKILL.md` — confirm/extend landscape + card-frame/silhouette guidance (Task 19, light edit).

**Game (track B) — `games/deckbuilder-0001/`:**
- `project.godot` — landscape 1280×720, `Main.tscn` main scene.
- `data/CardDB.gd` — card definitions (id, name, element, cost, type, effect spec). Autoload.
- `data/EnemyDB.gd` — enemy definitions (hp, intent script). Autoload.
- `CombatState.gd` — pure rules (`RefCounted`): hp/block/mana/piles/statuses, `play_card`, `end_turn`, `enemy_act`, win/lose, seeded RNG. **No rendering.**
- `RunController.gd` — 5-node map, progression, rest, elite/relic, reward (pick-1-of-3), boss.
- `MetaSave.gd` — read/write `user://save.json` (unlocks, ascension, best).
- `CombatView.gd` + `Main.gd` / `Main.tscn` — render `CombatState`, own all juice (tweens, pop-ups, shake, particles), UI (HP/mana/block, intent, hand fan, end-turn, pile counts, reward picker, win/lose).
- `selftest.gd` — headless `SceneTree` scripted-turn acceptance test (the TDD spine — grows each game stage).
- `art/` — SVG card frames, sigils, enemy silhouettes, wide background (Task 19).
- `audio/` — SFX + BGM WAVs (Task 20).
- `manifests/deckbuilder-0001.json` — the manifest spine.

---

## Track A — Pipeline upgrades (pure TDD, land first)

### Task 1: Add `build.orientation` to the manifest schema

**Files:**
- Modify: `schema/manifest.schema.json` (the `build` block, ~lines 51-62)
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write failing tests**

Add to `tools/manifest.test.mjs` inside the `describe("validate", ...)` block:

```javascript
  test("accepts build.orientation = landscape", () => {
    const m = validManifest();
    m.build.orientation = "landscape";
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("accepts build.orientation = portrait", () => {
    const m = validManifest();
    m.build.orientation = "portrait";
    expect(validate(m).valid).toBe(true);
  });

  test("accepts a manifest with no build.orientation (back-compat)", () => {
    const m = validManifest();
    delete m.build.orientation;
    expect(validate(m).valid).toBe(true);
  });

  test("rejects an unknown build.orientation", () => {
    const m = validManifest();
    m.build.orientation = "diagonal";
    const result = validate(m);
    expect(result.valid).toBe(false);
    expect(result.errors.join(" ")).toMatch(/orientation/);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: the four new tests FAIL — `diagonal` is currently accepted (no enum) and the schema has no `orientation` key, so the rejection test fails. (The accept tests fail only if `additionalProperties:false` rejects the unknown key — confirm the actual failure mode in output.)

- [ ] **Step 3: Add the enum to the schema**

In `schema/manifest.schema.json`, in the `build` object's `properties` (after `export_presets`), add:

```json
        "export_presets": { "type": "array", "items": { "type": "string" } },
        "orientation": { "enum": ["portrait", "landscape"] }
```

(Add a comma after the `export_presets` line. `orientation` is **not** added to any `required` array, so absence stays valid.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS, all four new tests green, no regressions.

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `npx vitest run`
Expected: PASS (was 190/190; now 194/194).

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.test.mjs
git commit -m "feat(schema): build.orientation enum (portrait|landscape, absent=portrait)"
```

---

### Task 2: Parameterize `splashSize()` and screenshot dims by orientation

**Files:**
- Modify: `tools/package.mjs` (`splashSize`, ~lines 242-246; `captureScreenshot`, ~lines 314-329)
- Test: `tools/package.test.mjs`

This lands the **seam** so packaging is orientation-ready; actually running packaging stays owner-gated (spec §2.1).

- [ ] **Step 1: Write failing tests**

Add to `tools/package.test.mjs` (import `splashSize` if not already imported at top of file — check the existing import line and extend it):

```javascript
  test("splashSize() defaults to portrait 1080x1920", () => {
    expect(splashSize()).toEqual({ w: 1080, h: 1920 });
  });

  test("splashSize('portrait') is 1080x1920", () => {
    expect(splashSize("portrait")).toEqual({ w: 1080, h: 1920 });
  });

  test("splashSize('landscape') swaps to 1920x1080", () => {
    expect(splashSize("landscape")).toEqual({ w: 1920, h: 1080 });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run tools/package.test.mjs`
Expected: the `landscape` test FAILS (`splashSize` ignores its argument, returns 1080×1920).

- [ ] **Step 3: Parameterize `splashSize`**

Replace `splashSize()` in `tools/package.mjs`:

```javascript
// Canonical boot-splash dimensions for the given orientation. Portrait is the
// default (absent build.orientation == portrait, per the manifest schema).
// Fresh object each call (no shared mutable singleton). Pure.
export function splashSize(orientation = "portrait") {
  return orientation === "landscape" ? { w: 1920, h: 1080 } : { w: 1080, h: 1920 };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run tools/package.test.mjs`
Expected: PASS. The existing call sites still work (default arg = portrait), so no regression.

- [ ] **Step 5: Run the full suite**

Run: `npx vitest run`
Expected: PASS (197/197).

- [ ] **Step 6: Commit**

```bash
git add tools/package.mjs tools/package.test.mjs
git commit -m "feat(package): splashSize(orientation) seam — landscape swaps to 1920x1080"
```

---

### Task 3: Make `builder/SKILL.md` orientation-aware + codify staged-build + turn-based self-test

**Files:**
- Modify: `.claude/skills/builder/SKILL.md`

No code test here — this is skill prose. The proof is that the builder run in Phases 4-8 follows it.

- [ ] **Step 1: Replace the hard-coded portrait `[display]` block**

In the "Reference scaffold" `project.godot` block (~lines 76-80), replace:

```
[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation="portrait"
```

with:

```
[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation="portrait"
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
```

and add this paragraph immediately above the scaffold block:

> **Orientation (read from the manifest — do NOT hard-code).** Read `build.orientation` from `manifests/<id>.json`. **Absent or `"portrait"`** → `viewport_width=720`, `viewport_height=1280`, `window/handheld/orientation="portrait"` (the values shown below). **`"landscape"`** → `viewport_width=1280`, `viewport_height=720`, `window/handheld/orientation="landscape"`. Lay out the scene for the chosen frame: a landscape game uses the **width** (e.g. a fanned card hand along the bottom, actors staged left↔right); a portrait game uses height. The `concept`/manifest is the source of truth — never assume portrait. Write the build block including the orientation you used so the `validator`/`packager` pick the matching splash/screenshot dims (`splashSize(orientation)`).

- [ ] **Step 2: Add a staged-build decomposition section**

After the "Hard requirements" section, add:

```markdown
## Staged build for systems-heavy genres (REQUIRED when the loop is too large to one-shot)

A turn-based deckbuilder, a tactics game, or any title with a rules engine + content DB + meta layer is too large to scaffold correctly in one pass — a one-shot produces a tangled `Main.gd` where rules and rendering are fused and nothing is testable. Decompose along the **rules/rendering seam** and build in dependency order, each stage gated by an assertion in `selftest.gd` before the next:

1. **Rules engine first, headless, pure.** A `RefCounted` (e.g. `CombatState.gd`) holding all state and rules — no nodes, no rendering, a **seedable** `RandomNumberGenerator` so runs are deterministic. Every rule (`play_card`, `end_turn`, `enemy_act`, win/lose) is a method that mutates state and returns a list of **events** (plain dictionaries) describing what happened. This is what `selftest.gd` drives.
2. **Content as data autoloads.** Card/enemy/item definitions live in data files (e.g. `data/CardDB.gd`, `data/EnemyDB.gd` autoloads returning typed Dictionaries) so the pool extends without touching the engine. Never inline content into the rules.
3. **Orchestration** (run/map/progression, e.g. `RunController.gd`) on top of the engine.
4. **Persistence** (`user://save.json` via a `MetaSave.gd`) — read at boot, write at the meta milestone.
5. **Rendering + juice LAST** (`CombatView.gd`): reads engine state, replays the engine's returned events as animations (tweens, pop-ups, shake, particles), and **never owns a rule.** If the view computes damage, the seam is broken — move it into the engine.

Build and self-test each stage before starting the next; commit per stage. The decomposition is the deliverable as much as the game — a fused build that "works" is a skill failure even if it runs.
```

- [ ] **Step 3: Extend the self-test section for turn-based / scripted-turn genres**

In the "Self-test for logic-heavy genres" section, after the lifecycle-gotcha paragraph, add:

```markdown
**Turn-based / scripted-turn genres (deckbuilder, tactics, roguelike):** a real-time `_process` loop does not exercise a turn-based engine — drive **scripted turns** through the rules engine directly with a **fixed RNG seed**, and assert the full turn cycle. The canonical script (adapt to the game):
- `setup(seed, deck, enemy_id)` then `start_combat()` → assert the opening hand was drawn (`hand.size() == 5`).
- Play a known attack card → assert mana spent **and** enemy HP dropped by the card's value.
- Play a status-setup card (e.g. Fire→Burn) → assert the status stack appears on the enemy.
- Play a payoff card into that status (e.g. Lightning vs Burning) → assert the **bonus** branch fired (damage > base).
- `end_turn()` → assert the enemy acted (player HP dropped or block absorbed) **and** statuses ticked (Burn dealt + decremented, Chill consumed).
- Force the enemy to lethal, resolve → assert `is_won()`; drive a reward pick → assert the pick-1-of-3 choice resolves and the run advances.
- Force player HP to 0 → assert `is_lost()`. Drive the meta milestone (boss kill) → assert `user://save.json` was written with the expected keys.
Seeded RNG makes every assertion deterministic; the `validator`'s Method 1.6 runs this and `fail`s the build on `SELFTEST FAIL`.
```

- [ ] **Step 4: Self-review the edits**

Re-read the three edited sections together. Confirm: the orientation paragraph and the `[display]` block agree; the staged-build section names the same files the plan's File Structure uses (`CombatState.gd`, `CardDB.gd`, `EnemyDB.gd`, `RunController.gd`, `MetaSave.gd`, `CombatView.gd`); no contradictions with the existing "Deliberate primitives" guidance (primitives still apply pre-asset-pass).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/builder/SKILL.md
git commit -m "feat(builder): orientation-aware scaffold + staged-build + turn-based selftest guidance"
```

---

### Task 4: Make `validator/SKILL.md` orientation-aware (splash/screenshot dims)

**Files:**
- Modify: `.claude/skills/validator/SKILL.md`

- [ ] **Step 1: Add an orientation note to Method 5 (packaging gate)**

In Method 5, item 3b (splash at canonical size), change the `splashSize()` reference to read orientation-aware. Replace the parenthetical `(`splashSize()` → 1080×1920, ...)` with:

> `store/splash.png` exists at the canonical boot-splash dimensions for the title's orientation (`splashSize(build.orientation)` → 1080×1920 portrait, **1920×1080 landscape**, read from the PNG's IHDR).

And in item (screenshots, wherever screenshot dims are asserted), add: "Screenshot dims follow orientation — portrait `720×1280`, landscape `1280×720`."

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "feat(validator): orientation-aware splash/screenshot dims in packaging gate"
```

---

### Task 5: Add Method 1.6 — turn-based logic self-test — to `validator/SKILL.md`

**Files:**
- Modify: `.claude/skills/validator/SKILL.md`

- [ ] **Step 1: Insert Method 1.6 after Method 1.5**

After the Method 1.5 section, add:

```markdown
## Method 1.6 — Turn-based logic self-test (automated; REQUIRED for turn-based genres)

Method 1 (clean headless run) and a real-time `_process` self-test cannot exercise a **turn-based** engine — nothing advances without a scripted turn, so a deckbuilder/tactics title can run "clean" for 120 frames while its combat math is wrong. For turn-based genres, `builder` emits a `selftest.gd` that drives **scripted turns through the rules engine with a fixed RNG seed** (see builder's "Turn-based / scripted-turn genres"). Run it exactly like Method 1.5:

```
godot --headless --path games/<id>/ --script res://selftest.gd
```

- **PASS** = exit 0 AND output contains `SELFTEST OK`. The scripted turn proved: opening hand drawn, a card spent mana + dealt its damage, a status (Burn/Chill) applied, the cross-element payoff (Lightning bonus vs an afflicted target) fired, the enemy acted and statuses ticked on `end_turn`, a win/lose transition resolved, the reward pick-1-of-3 advanced the run, and the meta save wrote `user://save.json`. Advance:
  ```
  node tools/manifest.mjs merge <id> "{\"validation\": {\"core_loop_functional\": true}}"
  node tools/manifest.mjs set-status <id> validated
  ```
- **FAIL** = `SELFTEST FAIL: <reason>` or non-zero exit. Record the reason verbatim in `issues`, set `core_loop_functional: false`, `set-status <id> failed`, and STOP — attribute it to `builder` with the precise assertion that failed (e.g. "builder: Lightning card dealt base damage to a Burning enemy — the combo-payoff branch never fired"). Catching a deckbuilder math bug headlessly is a POC success.

Determinism is mandatory: the seed is fixed in `selftest.gd`, so a flaky self-test is itself a `builder` finding (an unseeded RNG path in the engine). The human playtest (Method 2) still gates `playable` — the self-test proves the rules are correct, the human confirms it *feels* like a duel worth replaying.
```

- [ ] **Step 2: Self-review**

Confirm Method 1.6's advancement commands match Method 1.5's exactly (same `merge` + `set-status validated`), and that it references the same builder section name added in Task 3 Step 3.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "feat(validator): Method 1.6 turn-based scripted-turn logic self-test"
```

---

## Track B — Build the game through the loop

> Tracks A and B are sequenced A-then-B so the game is built **by** the upgraded skills (proving them). Phases 4-8 are a `builder` run; the executor dispatches the `builder` skill and holds it to the contracts below. The `selftest.gd` assertions are the **concrete acceptance code** — `builder` writes the engine to satisfy them. If `builder` cannot satisfy a contract, that gap is the finding: fix `builder/SKILL.md`, not the game by hand (spec §1 risk).

### Task 6: Run `concept` — write the `deckbuilder-0001` manifest

**Files:**
- Create: `manifests/deckbuilder-0001.json` (via `tools/manifest.mjs`)

- [ ] **Step 1: Invoke the `concept` skill** with the prompt: *"a landscape wizards' arcane-duel roguelike deckbuilder — elemental spell cards (fire/ice/lightning) that combo across each other, pick-1-of-3 card rewards, a ~5-node run to a boss, and a meta-progression seed."* Steer it to produce the theme/identity from spec §2 (deep indigo/violet, runic sigils, mana crystals).

- [ ] **Step 2: Create the manifest skeleton**

```
node tools/manifest.mjs create deckbuilder-0001 "Arcane Duel"
```

- [ ] **Step 3: Write the concept block** (concept skill writes this; the content must encode the spec)

```
node tools/manifest.mjs merge deckbuilder-0001 "{\"concept\": {\"genre\": \"roguelike deckbuilder\", \"core_loop\": \"Turn-based arcane duel: each turn draw 5 spell cards, spend 3 mana to cast fire/ice/lightning cards against a telegraphed enemy, then end turn and the enemy acts. The live decision each turn is solving the enemy's telegraphed intent — set up Burn/Chill with fire/ice, then cash it in with lightning for bonus damage, while budgeting block vs offense. Between fights, pick 1 of 3 new cards to deepen the deck. Difficulty ramps across a ~5-node run (combat, combat, rest, elite+relic, boss). One excellent run, not endless.\", \"mechanics\": [\"draw/hand/discard piles with reshuffle\", \"mana economy (3/turn)\", \"block (resets each turn)\", \"fire->Burn DoT\", \"ice->Block+Chill (enemy skips attack)\", \"lightning->bonus damage vs Burning/Chilled\", \"enemy intent telegraph\", \"pick-1-of-3 card reward\", \"~5-node run map with rest/elite/boss\", \"2 relics\", \"win/lose screens + restart\", \"meta save: unlock 1 card + ascension toggle on boss win\"], \"art_direction\": \"Arcane-sigil SVG vector: deep indigo/violet base; element-accented spell cards (fire amber/orange, ice cyan/white, lightning electric-yellow/violet); runic circles, mana crystals, glowing sigils, glyph-bordered card frames with a cost gem and per-element sigil; a wide arcane-chamber background (indigo->violet gradient, glowing floor runic circle, floating motes) composed for the 1280x720 frame; distinct enemy silhouettes (imp, frost-wraith, golem, boss archmage). Feedback: cards arc to center on cast, number pop-ups, enemy hit-flash + screen shake scaled to damage, status icons with stack counts, enemy death dissolve.\", \"target_platforms\": [\"android\"], \"differentiation_notes\": \"A tight, hand-crafted vertical-slice deckbuilder built around one discoverable hook — fire/ice set up a status, lightning cashes it in — rather than a wide card pool. Landscape-native (the project's first non-portrait title), so the fanned hand and card frames read large.\", \"theme\": {\"premise\": \"a lone mage's arcane duel through a sequence of monsters, casting elemental spell cards\", \"tone\": \"focused, mystical, escalating tension\", \"mood_keywords\": [\"arcane\", \"elemental\", \"mystical\", \"strategic\"], \"setting\": \"a candle-lit arcane duelling chamber ringed with glowing runes\"}}}"
```

- [ ] **Step 4: Validate**

```
node tools/manifest.mjs validate deckbuilder-0001
```
Expected: `deckbuilder-0001 OK`, `status = "concept"`.

- [ ] **Step 5: Commit**

```bash
git add manifests/deckbuilder-0001.json
git commit -m "feat(concept): deckbuilder-0001 arcane-duel concept (landscape, 3-element combo)"
```

---

### Task 7: Scaffold the landscape Godot project + the failing self-test

**Files:**
- Create: `games/deckbuilder-0001/project.godot`
- Create: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write `project.godot` (landscape, from the upgraded builder scaffold)**

```
config_version=5

[application]
config/name="Arcane Duel"
run/main_scene="res://Main.tscn"

[autoload]
CardDB="*res://data/CardDB.gd"
EnemyDB="*res://data/EnemyDB.gd"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/handheld/orientation="landscape"
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"

[input]
tap={
"deadzone": 0.5,
"events": []
}

[rendering]
renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
```

- [ ] **Step 2: Write `selftest.gd` Stage-1 skeleton (will fail — engine not built yet)**

This is the acceptance spine. Stage 1 covers combat-engine basics; later tasks extend it.

```gdscript
extends SceneTree

const SEED := 12345

func _fail(msg: String) -> void:
	print("SELFTEST FAIL: ", msg)
	quit(1)

func _init() -> void:
	var CombatState := load("res://CombatState.gd")
	if CombatState == null:
		_fail("CombatState.gd missing")
		return
	var cs = CombatState.new()
	# Deterministic deck: 10-card starter, fixed order via seed.
	cs.setup(SEED, CardDB.starter_deck(), "imp")
	cs.start_combat()
	if cs.hand.size() != 5:
		_fail("opening hand was %d, expected 5" % cs.hand.size())
		return
	# --- later stages append assertions here (Tasks 9, 11, 13, 15) ---
	print("SELFTEST OK")
	quit(0)
```

- [ ] **Step 3: Run it to confirm it fails (no engine yet)**

Run: `& "C:\Users\quint\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6.3-stable_win64_console.exe" --headless --path games/deckbuilder-0001/ --script res://selftest.gd`
Expected: `SELFTEST FAIL: CombatState.gd missing` (or an autoload/parse error — CardDB/EnemyDB not written yet). Either way, **non-zero exit** confirms the test is real.

- [ ] **Step 4: Commit**

```bash
git add games/deckbuilder-0001/project.godot games/deckbuilder-0001/selftest.gd
git commit -m "feat(builder): scaffold deckbuilder-0001 landscape project + failing selftest spine"
```

---

### Task 8: Build `CardDB` + `EnemyDB` data autoloads

**Files:**
- Create: `games/deckbuilder-0001/data/CardDB.gd`
- Create: `games/deckbuilder-0001/data/EnemyDB.gd`

**Contract (`builder` writes these to satisfy the engine + self-test):**
- `CardDB.starter_deck() -> Array` returns 10 card-id strings (deterministic order).
- `CardDB.card(id: String) -> Dictionary` returns `{id, name, element, cost, type, effect}` where `element ∈ {"neutral","fire","ice","lightning"}`, `type ∈ {"attack","skill","power"}`, and `effect` is a Dictionary the engine interprets (e.g. `{damage:6}`, `{block:5}`, `{damage:5, burn:2}`, `{block:5, chill:1}`, `{damage:8, lightning_bonus:6}`, `{draw:2}`, `{power:"wildfire"}`).
- `CardDB.all_ids() -> Array` — the ~16-card pool (for rewards).
- `EnemyDB.enemy(id: String) -> Dictionary` returns `{id, name, hp, intents}` where `intents` is an Array of `{type, value}` dicts cycled each turn (`type ∈ {"attack","defend","enrage"}`). Enemies: `imp`, `frost_wraith`, `golem` (elite), `archmage` (boss).

- [ ] **Step 1: Write `CardDB.gd`** — the ~16-card pool from spec §3.3 (Arcane Bolt, Ward, Meditate, Mana Surge; Ember, Flame Lash, Immolate, Wildfire; Frost Shard, Glacial Wall, Freeze, Blizzard; Spark, Chain Lightning, Overload, Thunderclap) and a 10-card `starter_deck()` (neutrals + one of each element + duplicates). Each as a const Dictionary keyed by id; the three accessor funcs above.

- [ ] **Step 2: Write `EnemyDB.gd`** — the four enemies with intent scripts (imp: small attacks; frost_wraith: attack/defend mix; golem elite: big attacks + enrage; archmage boss: higher HP, multi-turn intent pattern).

- [ ] **Step 3: Confirm autoloads parse**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --quit-after 5`
Expected: exit 0, no `SCRIPT ERROR` / parse errors (autoloads load even though `Main.tscn` doesn't exist yet — if Godot errors on the missing main scene, that's fine for this check; grep the output for `SCRIPT ERROR` specifically).

- [ ] **Step 4: Commit**

```bash
git add games/deckbuilder-0001/data/
git commit -m "feat(builder): CardDB (~16 cards, 10-card starter) + EnemyDB (4 enemies) data autoloads"
```

---

### Task 9: Build `CombatState` — the pure rules engine (Stage 1: piles, mana, basic attack)

**Files:**
- Create: `games/deckbuilder-0001/CombatState.gd`
- Modify: `games/deckbuilder-0001/selftest.gd` (append Stage-1.5 assertions)

**Contract:** `CombatState` (`extends RefCounted`) exposes:
- Properties: `player_hp:int`, `player_max_hp:int`, `player_block:int`, `mana:int`, `mana_max:int`, `draw_pile:Array`, `hand:Array`, `discard_pile:Array`, `enemy:Dictionary` (`{id,name,hp,max_hp,block,statuses:{burn:int,chill:int}, intent:Dictionary}`), `rng:RandomNumberGenerator`.
- `setup(seed:int, deck:Array, enemy_id:String) -> void` — seed the RNG, load the deck into `draw_pile` (shuffled by the seeded RNG), load the enemy from `EnemyDB`.
- `start_combat() -> void` — set the enemy's first intent, call `start_turn()`.
- `start_turn() -> void` — `player_block = 0`, `mana = mana_max` (3), draw 5 (reshuffling discard into draw when empty).
- `play_card(hand_index:int) -> Array` — validate cost ≤ mana; spend mana; apply `effect`; move card to discard; return an Array of event Dictionaries (`{type:"damage", target:"enemy", amount:6}` etc.).
- `is_won() -> bool` (`enemy.hp <= 0`), `is_lost() -> bool` (`player_hp <= 0`).

- [ ] **Step 1: Append the Stage-1.5 assertion to `selftest.gd`** (replace the `# --- later stages ---` marker)

```gdscript
	# Stage 1.5: a neutral attack spends mana and damages the enemy.
	var ehp0: int = cs.enemy.hp
	var mana0: int = cs.mana
	var bolt_idx := _find_card(cs.hand, "arcane_bolt")
	if bolt_idx < 0:
		# guarantee a known card in hand deterministically for the test
		cs.hand.insert(0, "arcane_bolt"); bolt_idx = 0
	cs.play_card(bolt_idx)
	if cs.mana >= mana0:
		_fail("playing Arcane Bolt did not spend mana"); return
	if cs.enemy.hp != ehp0 - 6:
		_fail("Arcane Bolt dealt %d, expected 6" % (ehp0 - cs.enemy.hp)); return
	# --- Stage 2 (Task 11) appends here ---
```

Add the helper at the bottom of `selftest.gd`:

```gdscript
func _find_card(hand: Array, id: String) -> int:
	for i in hand.size():
		if hand[i] == id:
			return i
	return -1
```

- [ ] **Step 2: Run — confirm it fails on the engine, not the harness**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --script res://selftest.gd`
Expected: `SELFTEST FAIL` referencing the engine (e.g. mana not spent) — proving the assertion bites before the engine exists / is incomplete.

- [ ] **Step 3: `builder` writes `CombatState.gd` Stage 1** to satisfy the contract above. Strict Godot 4.6 typing (annotate every `clamp`/`Array` read site, per builder's typing rules).

- [ ] **Step 4: Run — confirm PASS**

Run the same self-test command.
Expected: `SELFTEST OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/CombatState.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(builder): CombatState stage 1 — piles, mana, seeded RNG, basic attack"
```

---

### Task 10: Build `CombatState` Stage 2 — block, statuses (Burn/Chill), enemy turn, status tick

**Files:**
- Modify: `games/deckbuilder-0001/CombatState.gd`

**Contract additions:**
- `play_card` honors `block` (adds to `player_block`), `burn:N` (adds `enemy.statuses.burn`), `chill:N` (adds `enemy.statuses.chill`).
- `end_turn() -> Array` — run `enemy_act()`, then tick statuses, then `start_turn()`; return events.
- `enemy_act() -> Array` — if `enemy.statuses.chill > 0`, decrement and **skip** the attack (return a `{type:"chilled_skip"}` event); else resolve the telegraphed `enemy.intent` (`attack` → damage player, absorbed by `player_block` first; `defend` → `enemy.block`; `enrage` → buff). Then advance to the next intent in the cycle.
- Status tick: `burn` deals `burn` damage to the enemy then decrements by 1.

- [ ] **Step 1: This stage's assertions are added in Task 11** (they share the Stage-2 self-test block). Here, build the engine methods.

- [ ] **Step 2: `builder` extends `CombatState.gd`** with `end_turn`, `enemy_act`, status application + tick, block absorption. Keep all rules here (the view never computes them).

- [ ] **Step 3: Quick parse/run check**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --script res://selftest.gd`
Expected: still `SELFTEST OK` (Stage-1 assertions unaffected; new methods compile).

- [ ] **Step 4: Commit**

```bash
git add games/deckbuilder-0001/CombatState.gd
git commit -m "feat(builder): CombatState stage 2 — block, Burn/Chill, enemy turn, status tick"
```

---

### Task 11: Build the 3-element combo payoff + assert the full turn cycle

**Files:**
- Modify: `games/deckbuilder-0001/CombatState.gd`
- Modify: `games/deckbuilder-0001/selftest.gd`

**Contract:** lightning cards with `lightning_bonus:N` deal **base damage + N** when the enemy has `burn>0` OR `chill>0` (else base only). This is the spec §3.2 cash-in.

- [ ] **Step 1: Append Stage-2 assertions to `selftest.gd`** (replace the `# --- Stage 2 ---` marker)

```gdscript
	# Stage 2: Fire applies Burn; Lightning cashes it in for bonus damage; end_turn resolves enemy + ticks.
	cs.hand.insert(0, "ember")            # fire: damage + burn
	cs.mana = cs.mana_max                 # ensure castable for the deterministic test
	var ehp1: int = cs.enemy.hp
	cs.play_card(0)
	if cs.enemy.statuses.burn <= 0:
		_fail("Ember did not apply Burn"); return
	# Lightning into a Burning enemy: bonus branch must fire.
	cs.hand.insert(0, "chain_lightning") # lightning: base + lightning_bonus vs afflicted
	cs.mana = cs.mana_max
	var base: int = CardDB.card("chain_lightning").effect.get("damage", 0)
	var ehp2: int = cs.enemy.hp
	cs.play_card(0)
	if (ehp2 - cs.enemy.hp) <= base:
		_fail("Chain Lightning did not apply combo bonus vs Burning target"); return
	# End turn: enemy acts and Burn ticks + decrements.
	var php0: int = cs.player_hp
	var burn0: int = cs.enemy.statuses.burn
	var ehp3: int = cs.enemy.hp
	cs.end_turn()
	var acted := (cs.player_hp < php0) or (cs.enemy.intent.get("type","") == "defend")
	if not acted:
		_fail("enemy did not act on end_turn"); return
	if not (cs.enemy.statuses.burn < burn0 and cs.enemy.hp < ehp3):
		_fail("Burn did not tick + decrement on end_turn"); return
	# --- Stage 3 (Task 13) appends here ---
```

- [ ] **Step 2: Run — confirm it fails on the combo branch**

Run the self-test.
Expected: `SELFTEST FAIL: Chain Lightning did not apply combo bonus...` (the engine doesn't yet branch on enemy statuses).

- [ ] **Step 3: `builder` adds the lightning-bonus branch** in `play_card` (when resolving a `lightning_bonus` effect, check `enemy.statuses.burn>0 or enemy.statuses.chill>0`).

- [ ] **Step 4: Run — confirm PASS**

Expected: `SELFTEST OK`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/CombatState.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(builder): 3-element combo payoff (lightning bonus vs Burn/Chill) + full-turn-cycle selftest"
```

---

### Task 12: Build `MetaSave` — `user://save.json` persistence

**Files:**
- Create: `games/deckbuilder-0001/MetaSave.gd`

**Contract:** `MetaSave` (`RefCounted` or static) with `load_state() -> Dictionary` (returns `{unlocked_cards:Array, ascension:int, best:String}`, defaults if no file) and `save_state(state:Dictionary) -> void` (writes `user://save.json`). On boss win, `RunController` calls `save_state` adding 1 unlocked card + enabling the ascension toggle.

- [ ] **Step 1: `builder` writes `MetaSave.gd`** with `FileAccess` read/write of `user://save.json`, JSON-encoded, with safe defaults.

- [ ] **Step 2: Parse check**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --quit-after 5`
Expected: no `SCRIPT ERROR`.

- [ ] **Step 3: Commit**

```bash
git add games/deckbuilder-0001/MetaSave.gd
git commit -m "feat(builder): MetaSave — user://save.json (unlocks, ascension, best)"
```

---

### Task 13: Build `RunController` — 5-node run, rewards, rest, elite/relic, boss + meta write

**Files:**
- Create: `games/deckbuilder-0001/RunController.gd`
- Modify: `games/deckbuilder-0001/selftest.gd`

**Contract:** `RunController` (`RefCounted`) drives the run independent of rendering:
- `start_run(seed:int) -> void` — build the 5-node sequence: `combat(imp)`, `combat(frost_wraith)`, `rest`, `elite(golem)+relic`, `boss(archmage)`. Apply the starting relic ("Ember Heart": apply 1 Burn at combat start).
- `current_node() -> Dictionary`, `start_node_combat() -> CombatState` (returns a configured `CombatState` with relics applied).
- `offer_rewards() -> Array` — pick-1-of-3 card ids drawn from `CardDB.all_ids()` via the seeded RNG (excludes nothing for the slice).
- `choose_reward(card_id) -> void` (adds to the run deck; supports a skip), `take_rest(heal_or_remove) -> void`, `grant_elite_relic() -> void`.
- `advance() -> void` — move to the next node; on boss defeat call `MetaSave.save_state(...)`.
- `is_run_complete() -> bool`, `is_run_lost() -> bool`.

- [ ] **Step 1: Append Stage-3 assertions to `selftest.gd`** (replace the `# --- Stage 3 ---` marker)

```gdscript
	# Stage 3: win → reward pick-1-of-3 → run advances; boss win writes the meta save.
	var RunController := load("res://RunController.gd")
	var run = RunController.new()
	run.start_run(SEED)
	var combat = run.start_node_combat()
	combat.enemy.hp = 1
	combat.hand.insert(0, "arcane_bolt"); combat.mana = combat.mana_max
	combat.play_card(0)
	if not combat.is_won():
		_fail("forcing enemy to 1 HP + a hit did not win the combat"); return
	var rewards: Array = run.offer_rewards()
	if rewards.size() != 3:
		_fail("reward screen offered %d cards, expected 3" % rewards.size()); return
	run.choose_reward(rewards[0])
	var node_before := run.current_node()
	run.advance()
	if run.current_node() == node_before:
		_fail("run did not advance after reward"); return
	# Boss-win meta write (drive directly to the boss outcome).
	run.force_boss_defeat_for_test()
	var state: Dictionary = MetaSave.new().load_state()
	if state.get("unlocked_cards", []).is_empty():
		_fail("boss win did not unlock a card in user://save.json"); return
	# Lose path.
	combat.player_hp = 0
	if not combat.is_lost():
		_fail("player_hp 0 did not register as lost"); return
```

(Note: `force_boss_defeat_for_test()` is a deterministic test hook on `RunController` that runs the boss-win path — including `MetaSave.save_state` — without playing 5 nodes. A test-only hook is acceptable and keeps the self-test fast; document it as such in the engine.)

- [ ] **Step 2: Run — confirm it fails** (`RunController` not written).
Expected: `SELFTEST FAIL` on the reward/advance/meta assertions.

- [ ] **Step 3: `builder` writes `RunController.gd`** to satisfy the contract, including the `force_boss_defeat_for_test()` hook and the boss-win `MetaSave` call.

- [ ] **Step 4: Run — confirm full PASS**

Expected: `SELFTEST OK`, exit 0 — the entire scripted run (combat → combo → enemy turn → win → reward → advance → boss meta-write → lose) now passes deterministically.

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(builder): RunController — 5-node run, pick-1-of-3 rewards, relic, boss meta-write"
```

---

### Task 14: Build `CombatView` + `Main.tscn`/`Main.gd` — rendering, UI, landscape layout

**Files:**
- Create: `games/deckbuilder-0001/CombatView.gd`
- Create: `games/deckbuilder-0001/Main.gd`
- Create: `games/deckbuilder-0001/Main.tscn`

**Contract:** `Main` owns a `RunController` + the current `CombatState` and a `CombatView` that **renders state and replays events** — it must not compute a single rule. Landscape layout (spec §4.2): hand fans along the bottom width; enemy center/right with its intent telegraph above; player stats (HP/mana/block) bottom-left; draw/discard counts in the bottom corners; end-turn button bottom-right. Touch + click input both route to card-play / end-turn. Win/lose screens with restart. Reward picker (pick-1-of-3 + skip) between combats.

- [ ] **Step 1: `builder` writes `Main.tscn`** (root `Node2D` → `CombatView`, a `CanvasLayer` HUD with HP/mana/block labels, intent label, pile-count labels, an EndTurn `Button`, a reward-picker `Control`), `Main.gd` (wires input → `CombatState.play_card` / `RunController`), and `CombatView.gd` (draws the chamber background placeholder, the enemy, the fanned hand of card rects, reads `CombatState` each frame).

- [ ] **Step 2: Use deliberate primitives for now** (pre-asset-pass): indigo→violet gradient background (not a flat fill — the #1 complaint), card rects with element-colored borders + cost/name text, an enemy polygon silhouette, the glow recipe for sigils. Layered scene (background / play / HUD).

- [ ] **Step 3: Headless run clean**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --quit-after 120`
Expected: exit 0, no `SCRIPT ERROR` / `ERROR:` / "Failed to load".

- [ ] **Step 4: Self-test still green** (rendering must not have touched rules)

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --script res://selftest.gd`
Expected: `SELFTEST OK`.

- [ ] **Step 5: Write the build block + assets + advance status**

```
node tools/manifest.mjs merge deckbuilder-0001 "{\"build\": {\"engine\": \"godot\", \"engine_version\": \"4.6.3.stable\", \"language\": \"gdscript\", \"project_path\": \"games/deckbuilder-0001/\", \"addons\": [], \"export_presets\": [\"android\"], \"orientation\": \"landscape\"}}"
node tools/manifest.mjs merge deckbuilder-0001 "{\"assets\": [{\"type\":\"background\",\"name\":\"chamber\",\"source\":\"placeholder\",\"origin\":\"primitive\"},{\"type\":\"sprite\",\"name\":\"card_frame\",\"source\":\"placeholder\",\"origin\":\"primitive\"},{\"type\":\"sprite\",\"name\":\"enemy_imp\",\"source\":\"placeholder\",\"origin\":\"primitive\"}]}"
node tools/manifest.mjs set-status deckbuilder-0001 generated
node tools/manifest.mjs validate deckbuilder-0001
```
Expected: `deckbuilder-0001 OK`, `status = "generated"`.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/ manifests/deckbuilder-0001.json
git commit -m "feat(builder): CombatView + Main (landscape layout, primitives) — status generated"
```

---

### Task 15: Game feel / juice pass (deterministic, headless-safe)

**Files:**
- Modify: `games/deckbuilder-0001/CombatView.gd`, `games/deckbuilder-0001/Main.gd`

- [ ] **Step 1: `builder` wires the juice** (spec §4.1) by replaying the engine's returned events: cards lift on hover + arc to center on cast + sweep to discard; damage/block **number pop-ups**; enemy **hit-flash + screen shake scaled to damage**; mana orbs drain/fill; HP bars tween; status icons (flame/snowflake) with stack counts; enemy death dissolve + particle burst; intent telegraph animates in at the start of the enemy turn. All tween/timer-driven, reset cleanly on restart.

- [ ] **Step 2: Headless run clean + self-test green**

Run both:
`& "<godot-exe>" --headless --path games/deckbuilder-0001/ --quit-after 120` (exit 0, clean)
`& "<godot-exe>" --headless --path games/deckbuilder-0001/ --script res://selftest.gd` (`SELFTEST OK`)

- [ ] **Step 3: Commit**

```bash
git add games/deckbuilder-0001/
git commit -m "feat(builder): juice pass — card arcs, pop-ups, scaled shake, status icons, death dissolve"
```

---

### Task 16: Validator — programmatic + turn-based self-test → `validated`

**Files:**
- Modify: `manifests/deckbuilder-0001.json` (via `tools/manifest.mjs`)

- [ ] **Step 1: Invoke the `validator` skill.** Method 1 (clean headless run) then **Method 1.6** (turn-based scripted self-test, the one added in Task 5).

- [ ] **Step 2: Method 1 — clean run**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --quit-after 120`
Expected: exit 0, no `SCRIPT ERROR`/`ERROR:`/"Failed to load".

- [ ] **Step 3: Method 1.6 — turn-based self-test**

Run: `& "<godot-exe>" --headless --path games/deckbuilder-0001/ --script res://selftest.gd`
Expected: `SELFTEST OK`, exit 0.

- [ ] **Step 4: Record + advance**

```
node tools/manifest.mjs merge deckbuilder-0001 "{\"validation\": {\"opens_in_editor\": true, \"runs\": true, \"core_loop_functional\": true, \"issues\": []}}"
node tools/manifest.mjs set-status deckbuilder-0001 validated
node tools/manifest.mjs validate deckbuilder-0001
```
Expected: `deckbuilder-0001 OK`, `status = "validated"`.

- [ ] **Step 5: Commit**

```bash
git add manifests/deckbuilder-0001.json
git commit -m "feat(validator): deckbuilder-0001 passes Method 1 + Method 1.6 — status validated"
```

---

### Task 17: Capture skill findings from the build (the co-equal deliverable)

**Files:**
- Create: `docs/superpowers/poc-run-deckbuilder.md` (run log)
- Modify: any `SKILL.md` where the build surfaced a concrete gap

- [ ] **Step 1: Write the run log** — for each loop step (concept/builder/validator), record what the skill produced, where it strained on this turn-based/landscape/systems-heavy genre, and the **specific prose fix** applied (or the gap to fix). Attribute every friction point to a skill, per the POC legibility principle.

- [ ] **Step 2: Fold each concrete finding into the responsible `SKILL.md`** (e.g. if `builder` needed extra guidance on the rules/rendering seam, or `concept` lacked a way to express turn-based loops). Do **not** invent fixes for problems that didn't occur — only codify what the build actually surfaced.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/poc-run-deckbuilder.md .claude/skills/
git commit -m "docs(poc): deckbuilder build run log + skill findings codified"
```

---

### Task 18: Owner gate — human playtest → `playable`

**Files:**
- Modify: `manifests/deckbuilder-0001.json`

- [ ] **Step 1: Ask the owner** to open `games/deckbuilder-0001/` in the Godot editor and play a full run (~60s+): draw → cast fire/ice/lightning → solve the enemy intent → end turn → win → pick-1-of-3 → advance → reach the boss. Confirm the 3-element combo creates a real decision and the run is fun for 60+ seconds (spec success criteria).

- [ ] **Step 2: On confirmation, advance:**

```
node tools/manifest.mjs set-status deckbuilder-0001 playable
node tools/manifest.mjs validate deckbuilder-0001
```
If the loop is broken or unfun, record the specific failure in `validation.issues`, attribute it to a skill, do **not** advance.

- [ ] **Step 3: Commit**

```bash
git add manifests/deckbuilder-0001.json
git commit -m "feat(validator): owner playtest confirmed — status playable"
```

---

### Task 19: Asset pass (SVG) → owner A/B → `styled`

**Files:**
- Create: `games/deckbuilder-0001/art/*.svg` (card frames, per-element sigils, enemy silhouettes, wide chamber background)
- Modify: `games/deckbuilder-0001/CombatView.gd` (load SVGs), `manifests/deckbuilder-0001.json` (`asset_pass`)
- Light edit: `.claude/skills/asset/SKILL.md` (confirm landscape + card-frame/silhouette guidance, only if the run surfaces a gap)

- [ ] **Step 1: Invoke the `asset` skill, SVG method.** Derive a `world_bible` from `concept.theme` (one arcane-duel world). Produce: **card frames** (element-colored borders, per-element sigil, cost gem, readable type band — ~90% of player attention, concentrate polish here), **enemy silhouettes** (imp / frost-wraith / golem / archmage, distinct + sized), and the **wide chamber background** (1280×720: indigo→violet gradient, glowing floor runic circle, floating motes — explicitly not a flat fill). The asset skill is already orientation-aware (honors landscape width/height).

- [ ] **Step 2: Rewire `CombatView` to load the SVGs** (`load("res://art/...")` after `--import`), keeping logic untouched. Confirm `--import` ran (else `load` returns null).

- [ ] **Step 3: Validator Method 3 (re-skin re-validation)** — headless import + run clean, `selftest.gd` still `SELFTEST OK`, then owner A/B (looks more designed, reads as one coherent visual system, plays identically, cross-modal cohesion vs `concept.theme`). Record `asset_pass`.

- [ ] **Step 4: On owner A/B pass, advance:**

```
node tools/manifest.mjs set-status deckbuilder-0001 styled
node tools/manifest.mjs validate deckbuilder-0001
```

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/ manifests/deckbuilder-0001.json .claude/skills/asset/SKILL.md
git commit -m "feat(asset): SVG arcane card frames + enemy silhouettes + wide chamber bg — status styled"
```

---

### Task 20: Audio pass → owner A/B → `scored`

**Files:**
- Create: `games/deckbuilder-0001/audio/*.wav`
- Modify: `games/deckbuilder-0001/` (wire `AudioStreamPlayer`s), `manifests/deckbuilder-0001.json` (`audio_pass`)

- [ ] **Step 1: Invoke the `audio` skill** with the locked settings (steps 50-100, deterministic envelope, melody-forced anti-drone BGM, per-bed `volume_db`, rebuild-bed-from-PCM + autoplay wiring). Derive `sonic_character` from `concept.theme` (arcane/mystical): per-element card SFX (fire whoosh / ice crackle / lightning zap), card draw, block chime, hit thud, victory + defeat stings; a low melodic arcane BGM loop (spec §4.3).

- [ ] **Step 2: Wire the players + events**, confirm BGM `playing=true` via a non-headless probe (the imported-long-WAV gotcha — rebuild from PCM data).

- [ ] **Step 3: Validator Method 4** (audio pass) + owner audio A/B + cross-modal cohesion. Record `audio_pass`.

- [ ] **Step 4: On owner A/B pass, advance:**

```
node tools/manifest.mjs set-status deckbuilder-0001 scored
node tools/manifest.mjs validate deckbuilder-0001
```

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/ manifests/deckbuilder-0001.json
git commit -m "feat(audio): arcane SFX + melodic BGM (locked settings) — status scored"
```

---

## Out of scope (this plan)

- **Packaging → `packaged`** (icons/atlas/splash/screenshots/APK). Owner-gated, downstream. The `splashSize(orientation)` seam (Task 2) and the validator orientation note (Task 4) prepare for it; the actual packager-side landscape parameterization and Play upload are a separate owner-gated effort (spec §2.1, §8).
- Spec §7 v2 items: multiple characters, branching map, 30+ cards, full relic system, deep meta tree, daily seeds, card upgrades.

---

## Self-review notes (writing-plans checklist)

- **Spec coverage:** §1 framing → Track A + Task 17 (skill findings co-equal). §2 theme/identity → Task 6 concept + Task 19 art. §2.1 orientation → Tasks 1-5, 7, 14. §3.1 combat → Tasks 9-11. §3.2 elements → Task 11. §3.3 content → Task 8 (cards/enemies) + Task 13 (run/rewards/relics). §3.4 meta → Tasks 12-13. §4.1 juice → Task 15. §4.2 visual → Task 14 (layout) + Task 19 (art). §4.3 audio → Task 20. §5 validation Method → Tasks 5, 16. §6 architecture → Tasks 8-14 (one unit per file). §7 scope → "Out of scope" section. §8 open items → resolved at top.
- **Type consistency:** the `CombatState` API (`setup`/`start_combat`/`start_turn`/`play_card`/`end_turn`/`enemy_act`/`is_won`/`is_lost`, properties `hand`/`mana`/`mana_max`/`player_hp`/`player_block`/`enemy.statuses.{burn,chill}`/`enemy.intent`), `CardDB` (`starter_deck`/`card`/`all_ids`, effect keys `damage`/`block`/`burn`/`chill`/`lightning_bonus`/`draw`/`power`), `EnemyDB` (`enemy`, intents `attack`/`defend`/`enrage`), `RunController` (`start_run`/`start_node_combat`/`offer_rewards`/`choose_reward`/`advance`/`force_boss_defeat_for_test`/`is_run_complete`/`is_run_lost`), and `MetaSave` (`load_state`/`save_state`) are used identically in the self-test (the contract) and every task that references them.
- **Generative-task framing:** Phases 4-8 dispatch the `builder`/`asset`/`audio` skills (per the spec's "drive through the loop"); the **complete concrete code** in those tasks is the acceptance contract (`selftest.gd` assertions, the concept/manifest JSON, the API signatures), which the skills satisfy — hand-authoring the engine internals is explicitly disallowed (spec §1).
