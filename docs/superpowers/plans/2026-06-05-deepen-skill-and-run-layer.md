# `deepen` Skill + Deckbuilder Run-Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `deepen` GameForge skill (the loop's first *iteration* skill), then dogfood it by growing `deckbuilder-0001`'s run layer from a hardcoded linear 5-node run into a Slay-the-Spire-style branching map with gold, a shop, events, campfires + card upgrades, and a real relic pool.

**Architecture:** Skill-first, dogfood-refine. Task 1 authors `deepen/SKILL.md`. Tasks 2–13 follow it: refactor-to-seam first (pure, behavior pinned), then one new sub-system at a time, each TDD'd against `games/deckbuilder-0001/selftest.gd` (existing assertions = regression guard; new assertion per system, written first). Combat rules (`CombatState`) stay intact except two surfaced seams — run-persistent HP threading and gold-on-victory. `RunController` becomes a state machine over node types; `Main.gd` routes to per-node-type screens. Task 14 finalizes (validator + `depth_pass`); Task 15 hardens the skill from what the dogfood taught.

**Tech Stack:** Godot 4.6.3 GDScript (headless `--script` self-test, no autoloads — data via `preload` + `static func`), seeded `RandomNumberGenerator` + Fisher–Yates (never `Array.shuffle()`).

---

## Conventions for every task

- **Self-test command** (the hard gate — run from repo root, godot shim per the godot-binary-path memory):
  ```
  godot --headless --path games/deckbuilder-0001/ --script res://selftest.gd
  ```
  Expected on success: a line `SELFTEST OK` and exit 0. Any `SELFTEST FAIL: …` or non-zero exit means the task is not done.
- **After editing any `.gd` that has a `.import` sibling or that Godot caches**, the self-test runs the script fresh, so no `--import` is needed for pure-logic `.gd` files. (The `--import` rule applies to *textures*, not scripts.)
- **Determinism:** every new RNG use goes through `rng.randi_range()` / the existing `_shuffle()` Fisher–Yates. Never `Array.shuffle()` (global RNG) and never `Math.random`-equivalents.
- **Data layers** (`RelicDB`, `EventDB`, `MapGen`, `CardDB`, `EnemyDB`) are reached via `preload(...)` + `static func` — NEVER autoload globals (headless `--script` does not instantiate autoloads).
- **View code** follows the existing `games/deckbuilder-0001/CombatView.gd` conventions (custom `_draw`, `refresh(...)` setter, `get_*_rect()` hit-testing). View tasks are accepted by a **real-renderer screenshot**, not the self-test, and final look is `visual-audit`'s job — not this plan's.
- **Commit after every task** with the message shown in its final step.

---

## Phase 0 — the skill (skill-first)

### Task 1: Author `deepen/SKILL.md` and insert it into the loop docs

**Files:**
- Create: `.claude/skills/deepen/SKILL.md`
- Modify: `README.md` (skill-loop section), `CLAUDE.md` (skill loop line)

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/deepen/SKILL.md` with exactly this content:

```markdown
---
name: deepen
description: Use when growing an already-playable Godot game along a depth axis (systemic / content / run-meta) without regressing proven behavior. The first ITERATION skill in the GameForge loop — it EXTENDS the rules engine (the deliberate inverse of the asset re-skin's frozen-logic rule), TDD-ing each new sub-system against selftest.gd as a regression guard, records manifest.depth_pass, loops back through validator, and does NOT advance status.
---

# deepen

Take an already-playable game and grow it along ONE depth axis — systemic (new
interacting mechanics), content (more of the same), or run-meta (map / events /
economy / progression) — without regressing what already works, and **prove** the new
depth landed. Every other GameForge skill is build-once; `deepen` is the loop's first
in-place ITERATION skill.

## Loop position

```
prompt → concept → builder → validator → playtest → ( deepen → validator → playtest )*  → asset → visual-audit → audio → packager
```

`deepen` operates in place on a `validated`/`playable` game and loops back through the
validator. It does **not** advance status — a deeper game is the same status, just
bigger.

## Inputs
- A game at status ≥ `validated` with a working `games/<id>/selftest.gd`.
- A chosen depth axis + scope (spec-given, or assessed per the method below).

## Outputs
- Extended game code; a grown `selftest.gd`; a `manifest.depth_pass` record.
- Durable lessons folded back into this skill.

## The method

1. **Assess depth.** Name the axis the game is thinnest on and the single
   highest-leverage expansion. Don't widen three axes at once.
2. **Decompose into sub-systems.** Each one purpose, with a clean interface
   (data layer + logic + screen). Find the **extension seams**: where the existing code
   already supports growth (e.g. a static-func data table) vs. where you must
   **refactor to create a seam first** (e.g. a hardcoded linear sequence → a
   data-driven state machine). **Refactor-for-seam before adding content.**
3. **TDD each new system on the self-test — the validation spine:**
   - **`deepen` EXTENDS the logic; it does NOT freeze it.** This is the deliberate
     inverse of the `asset`/re-skin "logic FROZEN" rule. Confusing the two is the
     classic mistake — re-skinning must not touch rules; deepening is *all about*
     touching them, safely.
   - Existing assertions are the **regression guard**. `SELFTEST OK` must hold after
     every change.
   - For each new system, **write its assertion first (RED) → implement → GREEN.**
     Prove new mechanics the same deterministic, headless way the original logic was.
   - **Never weaken or delete an existing assertion to make room.** If a new system
     genuinely changes old behavior, *surface it* — call it out and confirm it's
     intended — never silently overwrite the guard.
   - **A pure refactor adds no new behavior.** If the behavior it restructures isn't
     already covered, pin it with a **characterization assertion first** (one that
     passes both before and after the refactor), then refactor. Pure refactors add no
     *new-behavior* assertions.
4. **One sub-system at a time**, each independently self-tested and committed. Don't
   batch five then debug the soup. Keep a playable game at every step.
5. **Grow the UI per system**, reusing established chrome. Hand composited-screen
   judgment to `visual-audit` and correctness to `validator`. `deepen` owns *systems &
   content* — not pixels, not the gate mechanics.
6. **Record + codify.** Write `manifest.depth_pass` (axis, systems added, new-assertion
   count). Fold durable lessons back into this skill.

## manifest.depth_pass

```json
"depth_pass": {
  "axis": "run-meta | systemic | content",
  "systems_added": ["..."],
  "selftest_assertions_added": 0,
  "notes": "what changed, and any surfaced behavior-changes to previously-frozen logic"
}
```

## Boundaries / non-goals
- Not a re-skin (`asset` + `visual-audit`) and not the audio pass.
- Does not invent a new status or touch the packaging gate.
- Does not redesign from scratch — it grows what exists along one axis.

## Project gotchas (carry these)
- Headless `godot --script` does NOT instantiate autoloads → data layers via
  `preload` + `static func`.
- Seed every RNG; Fisher–Yates, never `Array.shuffle()`.
- Reset `user://save.json` before asserting on meta writes (stale-file false positives).
```

- [ ] **Step 2: Insert `deepen` into the README skill loop**

In `README.md`, find the skill-loop description (search for `concept` → `builder` → `validator`) and add `deepen` as the iteration step after the playtest, matching the loop diagram in the skill file above. Keep the surrounding prose style.

- [ ] **Step 3: Insert `deepen` into CLAUDE.md**

In `CLAUDE.md` under "## Skill loop (from README)", update the loop line to include the `( deepen → validator → playtest )*` iteration step, and add `deepen` to the sentence naming which skill owns what (it owns *iterating/growing a playable game's systems & content*).

- [ ] **Step 4: Verify the self-test still passes (no code changed, sanity baseline)**

Run the self-test command. Expected: `SELFTEST OK`. This establishes the green baseline before any code edits.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/deepen/SKILL.md README.md CLAUDE.md
git commit -m "feat(deepen): new iteration skill — method + loop insertion"
```

---

## Phase 1 — refactor-to-seam (pure; behavior pinned; zero new-behavior assertions)

### Task 2: Extract relics into a hook-based `RelicDB` (pure refactor)

Currently `RunController.start_node_combat()` hardcodes `if "ember_heart" in relics: cs.enemy.statuses["burn"] += 1`, and `grant_elite_relic()` appends `"storm_core"` which has **no effect at all**. We replace the inline surgery with a data-driven `RelicDB` hook table. `ember_heart` behavior is preserved exactly; `storm_core` stays a no-op here (its effect is added as a *new* system in Task 13).

**Files:**
- Create: `games/deckbuilder-0001/data/RelicDB.gd`
- Modify: `games/deckbuilder-0001/RunController.gd` (`start_node_combat`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the characterization assertion first (pins current behavior)**

The current behavior — `ember_heart` puts 1 Burn on the enemy at combat start — is NOT yet covered by the self-test. Pin it BEFORE refactoring. In `selftest.gd`, immediately after the Stage 4 Wildfire block (before `print("SELFTEST OK")` near line 126), add:

```gdscript
	# Stage 5 (characterization): the starting relic ember_heart applies 1 Burn at combat start.
	var RC5 := load("res://RunController.gd")
	var r5 = RC5.new()
	r5.start_run(SEED)
	var c5 = r5.start_node_combat()
	if c5.enemy.statuses.get("burn", 0) < 1:
		_fail("ember_heart did not apply 1 Burn at combat start"); return
```

- [ ] **Step 2: Run the self-test — expect PASS (behavior already exists)**

Run the self-test command. Expected: `SELFTEST OK`. (This is a characterization test of *existing* behavior, so it passes now. It will guard the refactor.)

- [ ] **Step 3: Create `RelicDB` with the hook table**

Create `games/deckbuilder-0001/data/RelicDB.gd`:

```gdscript
extends Node

# Data-driven relic table. Each relic declares which hook it fires on.
# Effects are applied by the static apply_* dispatchers (GDScript const dicts
# can't hold first-class funcs cleanly, so we match on id in the dispatcher).
# Hooks: on_run_start(run), on_combat_start(combat_state), on_combat_win(run).
const RELICS := {
	"ember_heart": {
		"id": "ember_heart", "name": "Ember Heart", "hook": "on_combat_start",
		"desc": "At combat start, apply 1 Burn to the enemy.",
	},
	"storm_core": {
		"id": "storm_core", "name": "Storm Core", "hook": "on_combat_start",
		"desc": "Gain +1 max mana each combat.",
	},
}

static func relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

static func all_ids() -> Array:
	return RELICS.keys()

# Apply every owned relic that fires on combat start. Mutates the combat state.
static func apply_combat_start(owned: Array, cs) -> void:
	for id in owned:
		match id:
			"ember_heart":
				cs.enemy["statuses"]["burn"] = cs.enemy.statuses.get("burn", 0) + 1
			# "storm_core" effect is implemented in Task 13 — no-op here.

# Apply every owned relic that fires at run start. Mutates the run.
static func apply_run_start(owned: Array, run) -> void:
	pass  # populated in Task 13

# Apply every owned relic that fires on combat win. Mutates the run.
static func apply_combat_win(owned: Array, run) -> void:
	pass  # populated in Task 13
```

- [ ] **Step 4: Replace the inline relic logic in `RunController`**

In `games/deckbuilder-0001/RunController.gd`, add the preload near the other consts (after line 9):

```gdscript
const RelicDB := preload("res://data/RelicDB.gd")
```

Then in `start_node_combat()`, replace this block:

```gdscript
	# Apply relics.
	if "ember_heart" in relics:
		cs.enemy.statuses["burn"] = cs.enemy.statuses.get("burn", 0) + 1

	return cs
```

with:

```gdscript
	# Apply relics via the data-driven hook table.
	RelicDB.apply_combat_start(relics, cs)

	return cs
```

- [ ] **Step 5: Run the self-test — expect PASS (behavior unchanged)**

Run the self-test command. Expected: `SELFTEST OK`. The characterization assertion proves `ember_heart` still works through the new seam; no behavior changed.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/data/RelicDB.gd games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/selftest.gd
git commit -m "refactor(deckbuilder-0001): relics → data-driven RelicDB hooks (pure, behavior pinned)"
```

---

## Phase 2 — run-persistent HP (first new system; surfaced behavior-change to combat)

### Task 3: Thread player HP across the run

Today each combat starts the player at full 70 HP (`CombatState.setup` hardcodes it). For campfires and survival stakes, HP must carry across the whole run. This is a **surfaced behavior-change** to the otherwise-intact combat rules: `CombatState.setup` gains an optional starting-HP arg; `RunController` owns `run_hp`/`run_max_hp` and reads HP back after each combat.

**Files:**
- Modify: `games/deckbuilder-0001/CombatState.gd:28-34` (`setup`)
- Modify: `games/deckbuilder-0001/RunController.gd` (`start_run`, `start_node_combat`, + new `sync_hp_from_combat`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertion first**

In `selftest.gd`, after the Stage 5 block from Task 2, add:

```gdscript
	# Stage 6: player HP persists across combats (run-level HP).
	# (Deliberately starts combat twice on the same run WITHOUT advancing, so this
	# stage stays valid after Task 5 swaps the linear node model for map traversal —
	# it proves HP threading, not navigation.)
	var RC6 := load("res://RunController.gd")
	var r6 = RC6.new()
	r6.start_run(SEED)
	var c6a = r6.start_node_combat()
	c6a.player_hp = 40              # simulate taking damage in combat 1
	r6.sync_hp_from_combat(c6a)     # write run HP back from the finished combat
	var c6b = r6.start_node_combat() # next combat should START at 40, not full 70
	if c6b.player_hp != 40:
		_fail("run HP did not persist: next combat started at %d, expected 40" % c6b.player_hp); return
```

- [ ] **Step 2: Run the self-test — expect FAIL**

Run the self-test command. Expected: `SELFTEST FAIL: run HP did not persist…` (because `sync_hp_from_combat` doesn't exist yet / HP isn't threaded). If it instead errors on the missing method, that also counts as RED.

- [ ] **Step 3: Add an optional starting-HP arg to `CombatState.setup`**

In `games/deckbuilder-0001/CombatState.gd`, change the signature and the HP init (lines 28–34):

```gdscript
func setup(seed_value: int, deck: Array, enemy_id: String, start_hp: int = -1) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	player_max_hp = 70
	player_hp = player_max_hp if start_hp < 0 else start_hp
	player_block = 0
```

(Default `-1` ⇒ full HP, so every existing call site is unchanged.)

- [ ] **Step 4: Thread run HP through `RunController`**

In `RunController.gd`, add run-HP fields and init them in `start_run` (after `relics = []` etc., around line 36):

```gdscript
var run_hp: int
var run_max_hp: int
```

In `start_run`, after `relics.append("ember_heart")`:

```gdscript
	run_max_hp = 70
	run_hp = run_max_hp
```

In `start_node_combat`, pass the run HP into setup. Change:

```gdscript
	cs.setup(rng.randi(), deck, enemy_id)
```

to:

```gdscript
	cs.setup(rng.randi(), deck, enemy_id, run_hp)
```

Add a new method (anywhere after `start_node_combat`):

```gdscript
func sync_hp_from_combat(cs) -> void:
	# Pull the player's surviving HP back to the run after a combat ends.
	run_hp = cs.player_hp
```

- [ ] **Step 5: Run the self-test — expect PASS**

Run the self-test command. Expected: `SELFTEST OK`.

- [ ] **Step 6: Wire HP sync into `Main.gd` so live play persists HP too**

In `games/deckbuilder-0001/Main.gd`, in `_check_combat_outcome()`, inside the non-boss win branch (after `_view.animate_enemy_death(func():` and before `_rewards = _run.offer_rewards()`), add the sync so live runs carry HP:

```gdscript
				_run.sync_hp_from_combat(_combat)
```

(Logic-only change; the self-test already proves the engine path. No new assertion needed — covered by Stage 6.)

- [ ] **Step 7: Commit**

```bash
git add games/deckbuilder-0001/CombatState.gd games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/Main.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): run-persistent player HP (combat HP-thread seam)"
```

---

## Phase 3 — branching map

### Task 4: `MapModel` + seeded `MapGen` (data + generation, combat-only types)

Replace the hardcoded `nodes` array with a generated branching graph. The generator is deterministic given the run seed. This task generates the graph and proves its shape; `RunController` traversal + the `MapView` come in Tasks 5–6. Node types are assigned here but only `combat`/`elite`/`boss` lead to combat for now; `event`/`shop`/`campfire`/`treasure` are placed and will be handled as their systems land.

**Map shape (concrete, deterministic):**
- `FLOORS = 10` rows, indexed `0..9`.
- Each non-boss floor has `WIDTH`-bounded columns: floors `1..8` have 2–3 nodes (rolled), floor `0` has 2 nodes (entry), floor `9` has exactly 1 node (the boss).
- Edges: each node connects to 1–2 nodes on the next floor whose column index is within ±1 of its own (prevents wild crossings), and **every** node gets ≥1 outgoing edge; the boss is reachable from all floor-8 nodes (force-connect any floor-8 node with no path to the boss).
- Type assignment by floor: floor 0 = `combat`; floor 9 = `boss`; floor 8 = `campfire` (always rest before boss); floors 1–7 weighted roll — `combat` 50%, `event` 20%, `elite` 12% (only on floors ≥3), `shop` 10%, `treasure` 8% — with a guarantee of **≥1 shop and ≥1 event** somewhere on floors 1–7 (force-place if the rolls produced none).

**Files:**
- Create: `games/deckbuilder-0001/MapModel.gd`
- Create: `games/deckbuilder-0001/MapGen.gd`
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 6, add:

```gdscript
	# Stage 7: the seeded map generator produces a valid, traversable branching graph.
	var MapGen := load("res://MapGen.gd")
	var rng7 := RandomNumberGenerator.new(); rng7.seed = SEED
	var map = MapGen.generate(rng7)
	# (a) boss is a single terminal node on the last floor.
	var boss_ids: Array = map.nodes_on_floor(map.floor_count() - 1)
	if boss_ids.size() != 1 or map.node(boss_ids[0]).type != "boss":
		_fail("map last floor is not a single boss node"); return
	# (b) every node has a path to the boss (full traversability).
	if not map.all_nodes_reach(boss_ids[0]):
		_fail("not every map node reaches the boss"); return
	# (c) at least one entry node on floor 0, all of type combat.
	var entries: Array = map.nodes_on_floor(0)
	if entries.is_empty():
		_fail("map has no entry nodes on floor 0"); return
	for e in entries:
		if map.node(e).type != "combat":
			_fail("floor-0 entry node was not combat"); return
	# (d) guarantees: at least one shop and one event somewhere.
	if map.count_type("shop") < 1 or map.count_type("event") < 1:
		_fail("map missing guaranteed shop/event node"); return
	# (e) no elite before floor 3.
	for fl in range(0, 3):
		for nid in map.nodes_on_floor(fl):
			if map.node(nid).type == "elite":
				_fail("elite placed before floor 3"); return
	# (f) determinism: same seed → identical structure.
	var rng7b := RandomNumberGenerator.new(); rng7b.seed = SEED
	var map2 = MapGen.generate(rng7b)
	if map.fingerprint() != map2.fingerprint():
		_fail("map generation is not deterministic for a fixed seed"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL**

Run the self-test command. Expected: a failure/parse-error on the missing `MapGen` (RED).

- [ ] **Step 3: Create `MapModel`**

Create `games/deckbuilder-0001/MapModel.gd`:

```gdscript
extends RefCounted

# A branching run map: rows ("floors") of nodes connected by edges.
# Pure data + query helpers. No rendering, no RNG (generation lives in MapGen).
#
# node = {"id": int, "floor": int, "col": int, "type": String, "next": Array[int]}

var _nodes: Dictionary = {}      # id -> node dict
var _floors: Array = []          # floor index -> Array[int] of node ids (ordered by col)
var _next_id: int = 0

func add_node(floor: int, col: int, type: String) -> int:
	var id: int = _next_id
	_next_id += 1
	_nodes[id] = {"id": id, "floor": floor, "col": col, "type": type, "next": []}
	while _floors.size() <= floor:
		_floors.append([])
	_floors[floor].append(id)
	return id

func connect(from_id: int, to_id: int) -> void:
	var nxt: Array = _nodes[from_id]["next"]
	if not (to_id in nxt):
		nxt.append(to_id)

func node(id: int) -> Dictionary:
	return _nodes.get(id, {})

func floor_count() -> int:
	return _floors.size()

func nodes_on_floor(floor: int) -> Array:
	if floor < 0 or floor >= _floors.size():
		return []
	return _floors[floor].duplicate()

func next_of(id: int) -> Array:
	return _nodes.get(id, {}).get("next", []).duplicate()

func count_type(type: String) -> int:
	var c: int = 0
	for id in _nodes:
		if _nodes[id]["type"] == type:
			c += 1
	return c

# Every node can reach target via forward edges.
func all_nodes_reach(target_id: int) -> bool:
	for id in _nodes:
		if not _reaches(id, target_id):
			return false
	return true

func _reaches(start_id: int, target_id: int) -> bool:
	if start_id == target_id:
		return true
	var stack: Array = [start_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if cur == target_id:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		for nx in _nodes.get(cur, {}).get("next", []):
			stack.append(nx)
	return false

# Stable string fingerprint of the whole structure (for determinism checks).
func fingerprint() -> String:
	var parts: Array = []
	var ids: Array = _nodes.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = _nodes[id]
		var nxt: Array = n["next"].duplicate(); nxt.sort()
		parts.append("%d:%d:%d:%s:%s" % [id, n["floor"], n["col"], n["type"], str(nxt)])
	return "|".join(parts)
```

- [ ] **Step 4: Create `MapGen`**

Create `games/deckbuilder-0001/MapGen.gd`:

```gdscript
extends RefCounted

const MapModel := preload("res://MapModel.gd")

const FLOORS := 10

# Generate a deterministic branching map from a seeded rng.
static func generate(rng: RandomNumberGenerator) -> MapModel:
	var m = MapModel.new()

	# 1) Place nodes floor by floor (types assigned after, so we can enforce guarantees).
	var floor_widths: Array = []
	for fl in range(FLOORS):
		var w: int
		if fl == 0:
			w = 2
		elif fl == FLOORS - 1:
			w = 1                      # boss floor
		else:
			w = rng.randi_range(2, 3)
		floor_widths.append(w)
		for col in range(w):
			m.add_node(fl, col, "combat")  # placeholder type, reassigned below

	# 2) Connect each node to 1-2 nodes on the next floor within col distance 1.
	for fl in range(FLOORS - 1):
		var here: Array = m.nodes_on_floor(fl)
		var there: Array = m.nodes_on_floor(fl + 1)
		for from_id in here:
			var from_col: int = m.node(from_id)["col"]
			# candidate targets within +-1 column
			var cands: Array = []
			for to_id in there:
				if abs(m.node(to_id)["col"] - from_col) <= 1:
					cands.append(to_id)
			if cands.is_empty():
				cands = there.duplicate()   # fallback: connect to anything
			_shuffle(cands, rng)
			var k: int = 1 if cands.size() == 1 else rng.randi_range(1, 2)
			for i in range(min(k, cands.size())):
				m.connect(from_id, cands[i])
		# Ensure every next-floor node has at least one incoming edge.
		for to_id in there:
			var has_in: bool = false
			for from_id in here:
				if to_id in m.next_of(from_id):
					has_in = true
					break
			if not has_in:
				# connect from the column-nearest source
				var best: int = here[0]
				var best_d: int = 9999
				for from_id in here:
					var d: int = abs(m.node(from_id)["col"] - m.node(to_id)["col"])
					if d < best_d:
						best_d = d; best = from_id
				m.connect(best, to_id)

	# 3) Assign types.
	var boss_id: int = m.nodes_on_floor(FLOORS - 1)[0]
	m.node(boss_id)["type"] = "boss"
	for nid in m.nodes_on_floor(FLOORS - 2):
		m.node(nid)["type"] = "campfire"     # always a rest before the boss
	for nid in m.nodes_on_floor(0):
		m.node(nid)["type"] = "combat"       # entries are combats
	for fl in range(1, FLOORS - 2):
		for nid in m.nodes_on_floor(fl):
			m.node(nid)["type"] = _roll_type(rng, fl)

	# 4) Guarantee at least one shop and one event on floors 1..(FLOORS-3).
	_guarantee_type(m, rng, "shop")
	_guarantee_type(m, rng, "event")

	return m

static func _roll_type(rng: RandomNumberGenerator, floor: int) -> String:
	var r: int = rng.randi_range(0, 99)
	if r < 50: return "combat"
	if r < 70: return "event"
	if r < 82:
		return "elite" if floor >= 3 else "combat"
	if r < 92: return "shop"
	return "treasure"

static func _guarantee_type(m, rng: RandomNumberGenerator, type: String) -> void:
	if m.count_type(type) >= 1:
		return
	# Force-place on a random combat node in the eligible band.
	var candidates: Array = []
	for fl in range(1, m.floor_count() - 2):
		for nid in m.nodes_on_floor(fl):
			if m.node(nid)["type"] == "combat":
				candidates.append(nid)
	if candidates.is_empty():
		return
	_shuffle(candidates, rng)
	m.node(candidates[0])["type"] = type

# Fisher-Yates with the seeded rng (NEVER Array.shuffle).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
```

- [ ] **Step 5: Run the self-test — expect PASS**

Run the self-test command. Expected: `SELFTEST OK`. If a guarantee/traversability assertion trips, inspect the generated `fingerprint()` for the failing seed and fix the generator (do not weaken the assertion).

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/MapModel.gd games/deckbuilder-0001/MapGen.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): seeded branching MapGen + MapModel (traversable graph)"
```

---

### Task 5: `RunController` traverses the map (state machine over node types)

Replace the linear `nodes`/`node_i` cursor with map traversal: the run tracks a *current node id* and the set of *available next node ids*; choosing one moves the cursor. Combat/elite/boss still start combats; the other types get stub handlers that this task makes safe no-ops (their real systems land in later tasks). `Main.gd` will route in Task 6.

**Files:**
- Modify: `games/deckbuilder-0001/RunController.gd` (replace linear node model with map traversal)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 7, add:

```gdscript
	# Stage 8: run traverses the generated map by choosing among available next nodes.
	var RC8 := load("res://RunController.gd")
	var r8 = RC8.new()
	r8.start_run(SEED)
	# Start node is a floor-0 entry; current type is combat.
	if r8.current_node().get("type", "") != "combat":
		_fail("run did not start on a combat entry node"); return
	# There is at least one available next node, and choosing it advances the cursor.
	var avail: Array = r8.available_next()
	if avail.is_empty():
		_fail("no available next nodes from the entry"); return
	var before_id: int = r8.current_node_id()
	r8.choose_next(avail[0])
	if r8.current_node_id() == before_id:
		_fail("choosing a next node did not move the cursor"); return
	# Walking the map greedily (always pick first available) eventually reaches the boss.
	var guard: int = 0
	while not r8.is_on_boss() and guard < 50:
		var nx: Array = r8.available_next()
		if nx.is_empty():
			break
		r8.choose_next(nx[0])
		guard += 1
	if not r8.is_on_boss():
		_fail("greedy walk did not reach the boss node"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL**

Run the self-test command. Expected: failure on missing `available_next` / `choose_next` / `current_node_id` / `is_on_boss` (RED).

- [ ] **Step 3: Replace the linear model with map traversal**

In `RunController.gd`:

Add the preload near the top consts:

```gdscript
const MapGen := preload("res://MapGen.gd")
```

Add fields (replace `var nodes: Array` / `var node_i: int` with):

```gdscript
var map               # MapModel
var cur_id: int
```

In `start_run`, replace the hardcoded `nodes = [...]` / `node_i = 0` block with:

```gdscript
	map = MapGen.generate(rng)
	# Start on the lowest-id floor-0 entry node.
	var entries: Array = map.nodes_on_floor(0)
	entries.sort()
	cur_id = entries[0]
```

Replace `current_node()` with:

```gdscript
func current_node() -> Dictionary:
	return map.node(cur_id)

func current_node_id() -> int:
	return cur_id

func available_next() -> Array:
	return map.next_of(cur_id)

func choose_next(node_id: int) -> void:
	if node_id in map.next_of(cur_id):
		cur_id = node_id

func is_on_boss() -> bool:
	return current_node().get("type", "") == "boss"
```

Update `start_node_combat()` — map nodes carry only a `type` (no `enemy` id, unlike the old linear nodes), so derive the enemy from the node type + floor and record it on the run for gold rewards. Replace the enemy-id line:

```gdscript
	var enemy_id: String = node.get("enemy", "")
```

with:

```gdscript
	var enemy_id: String = _enemy_for_node(node)
	current_enemy_id = enemy_id
```

Add the field near the other run fields:

```gdscript
var current_enemy_id: String
```

Add the helper:

```gdscript
func _enemy_for_node(node: Dictionary) -> String:
	match node.get("type", ""):
		"boss":  return "archmage"
		"elite": return "golem"
		_:
			# Regular combat: shallower floors face the imp, deeper ones the frost wraith.
			return "imp" if node.get("floor", 0) < 4 else "frost_wraith"
```

Replace the old `advance()` / `is_run_complete()` logic. The run is complete when the boss is defeated (handled by `on_boss_defeated`), not when a linear index overflows. Change `advance()` to a no-op shim that callers can still invoke after non-combat nodes are auto-resolved (it now just clears any per-node state — keep it minimal):

```gdscript
func advance() -> void:
	# With map traversal, advancing = choosing the next node (done via choose_next
	# in the UI). This shim remains for non-combat auto-resolve paths that pick the
	# first available next node when there is exactly one.
	var nx: Array = available_next()
	if nx.size() == 1:
		choose_next(nx[0])
```

Keep `is_run_complete()` returning `_complete` (still set by `on_boss_defeated`). Update `force_boss_defeat_for_test()` to walk to the boss via the map instead of `node_i = 4`:

```gdscript
func force_boss_defeat_for_test() -> void:
	var guard: int = 0
	while not is_on_boss() and guard < 50:
		var nx: Array = available_next()
		if nx.is_empty():
			break
		choose_next(nx[0])
		guard += 1
	on_boss_defeated()
```

`offer_rewards()`, `choose_reward()`, `take_rest()`, `grant_elite_relic()`, `on_boss_defeated()`, `is_run_lost()` are unchanged.

- [ ] **Step 4: Update the Stage-3 self-test that used the linear model**

The existing Stage 3 block calls `run.current_node()` / `run.advance()` and asserts the node changed after a reward. With map traversal, `advance()` only auto-moves when there's exactly one next node. Replace the Stage-3 advance assertion (the lines around the existing `var node_before … run.advance() … if run.current_node() == node_before`) with an explicit choose:

```gdscript
	var id_before: int = run.current_node_id()
	var nxt3: Array = run.available_next()
	if nxt3.is_empty():
		_fail("no next node after first combat reward"); return
	run.choose_next(nxt3[0])
	if run.current_node_id() == id_before:
		_fail("run did not advance after reward"); return
```

- [ ] **Step 5: Run the self-test — expect PASS**

Run the self-test command. Expected: `SELFTEST OK`.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): RunController traverses the branching map"
```

---

### Task 6: `MapView` screen + `Main.gd` routing to node types

The player now sees the map between nodes and clicks an available next node. `Main.gd` becomes a router: after each node resolves, show the map; when a node is chosen, dispatch to the right screen (combat exists; event/shop/campfire/treasure get placeholder auto-resolve until their tasks land).

**Files:**
- Create: `games/deckbuilder-0001/MapView.gd` + add a `MapView` node to `Main.tscn`
- Modify: `games/deckbuilder-0001/Main.gd` (router + new `MAP` state)
- Acceptance: real-renderer screenshot (no self-test change)

- [ ] **Step 1: Create `MapView.gd` (contract + skeleton)**

Create `games/deckbuilder-0001/MapView.gd`. It must implement this contract; rendering follows `CombatView.gd` conventions (a `Node2D` with custom `_draw`, redraws on `refresh`):

```gdscript
extends Node2D

# MapView — draws the branching run map and the player's current position.
# Contract used by Main.gd:
#   refresh(map, cur_id: int, available: Array) -> void   # store + queue_redraw
#   get_node_rect(node_id: int) -> Rect2                   # hit-test for taps
#   nodes_drawn() -> Array                                 # ids currently on screen
#
# Layout: floor 0 at the bottom, boss at the top; x by column. Draw edges first
# (thin lines between connected node centers), then node icons coloured by type
# (combat/elite/boss/event/shop/campfire/treasure), then a ring/glow on the
# current node and a brighter highlight on each available-next node. Reuse the
# CombatView palette + font.

var _map
var _cur_id: int = -1
var _available: Array = []

func refresh(map, cur_id: int, available: Array) -> void:
	_map = map
	_cur_id = cur_id
	_available = available
	queue_redraw()

func _draw() -> void:
	if _map == null:
		return
	# ... draw edges, then nodes, per the layout note above ...

func get_node_rect(node_id: int) -> Rect2:
	# Return the on-screen rect for a node's icon (must match _draw positions).
	return Rect2()

func _node_center(floor: int, col: int, width: int) -> Vector2:
	# Map (floor,col) → screen position. floor 0 bottom, last floor top.
	return Vector2()
```

The implementer fills `_draw` / `get_node_rect` / `_node_center` to match, following `CombatView.gd`'s drawing helpers and the 1280×720 landscape canvas.

- [ ] **Step 2: Add the `MapView` node to `Main.tscn`**

Open `games/deckbuilder-0001/Main.tscn` and add a child `Node2D` named `MapView` with `script = MapView.gd`, as a sibling of `CombatView`. Start it hidden (`visible = false`); `Main.gd` toggles visibility per state.

- [ ] **Step 3: Add a `MAP` state + router to `Main.gd`**

In `Main.gd`:

Add `MAP` to the enum: `enum State { COMBAT, REWARD, REST, WIN, LOSE, MAP, EVENT, SHOP, CAMPFIRE }` (add the later ones now so subsequent tasks don't re-edit the enum).

Add `@onready var _map_view: Node2D = $MapView`.

Replace `_begin_current_node()` so non-combat handling routes through the map. After a node resolves, the run shows the map (unless on boss/complete/lost). Add a helper `_show_map()`:

```gdscript
func _show_map() -> void:
	_state = State.MAP
	_combat = null
	_view.visible = false
	_map_view.visible = true
	_map_view.refresh(_run.map, _run.current_node_id(), _run.available_next())

func _enter_node() -> void:
	# Dispatch on the CURRENT node's type (already chosen on the map).
	if _run.is_run_complete():
		_state = State.WIN; _map_view.visible = false; _view.visible = true; _refresh(); return
	if _run.is_run_lost():
		_state = State.LOSE; _map_view.visible = false; _view.visible = true; _refresh(); return
	var ntype: String = _run.current_node().get("type", "")
	match ntype:
		"combat", "elite", "boss":
			_map_view.visible = false
			_view.visible = true
			_combat = _run.start_node_combat()
			_view.capture_enemy_max_hp(_combat.enemy.get("hp", 1))
			_state = State.COMBAT
			_refresh()
		"campfire":
			# Placeholder until Task 11: auto-heal a little, then back to the map.
			_run.take_rest("heal")
			_advance_to_map()
		_:
			# event / shop / treasure placeholders until their tasks: auto-skip.
			_advance_to_map()

func _advance_to_map() -> void:
	# After a non-combat node resolves, move to the map to pick the next node
	# (or end the run if we just cleared the boss).
	if _run.is_on_boss() and _run.is_run_complete():
		_state = State.WIN; _map_view.visible = false; _view.visible = true; _refresh(); return
	_show_map()
```

Change `_ready` flow: `_start_run()` should, after `start_run`, call `_enter_node()` (entry node is a combat). After the entry combat's reward, route to the map instead of the old linear advance.

In `_handle_reward_tap`, replace the `_run.advance(); _begin_current_node()` calls with `_show_map()` (the player picks the next node on the map). In the skip branch likewise.

Add map-tap handling in `_input`'s `match _state`:

```gdscript
			State.MAP:
				_handle_map_tap(pos)
```

and the handler:

```gdscript
func _handle_map_tap(pos: Vector2) -> void:
	for nid in _run.available_next():
		if _map_view.get_node_rect(nid).has_point(pos):
			_run.choose_next(nid)
			_enter_node()
			return
```

After a non-boss combat win + reward selection routes to `_show_map()`. After boss defeat, WIN as before. (The implementer reconciles the existing `_check_combat_outcome` reward flow to end by calling `_show_map()` rather than `_begin_current_node()`.)

- [ ] **Step 4: Run the self-test — expect PASS (no logic changed)**

Run the self-test command. Expected: `SELFTEST OK` (this task only touched `Main.gd`/views, not engine logic).

- [ ] **Step 5: Capture a real-renderer screenshot of the map**

Render the running game and confirm the map screen appears with clickable nodes and the player can walk floor-to-floor into combats. Use the project's `tools/godot/screenshot.gd`-style harness (or a throwaway `_shot.gd`) to capture `Main.tscn`. Save to `docs/superpowers/probe-data/deckbuilder-raster-v1/run_layer_map.png`. This is an acceptance artifact; final look is `visual-audit`'s job.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/MapView.gd games/deckbuilder-0001/Main.tscn games/deckbuilder-0001/Main.gd
git commit -m "feat(deckbuilder-0001): MapView screen + Main.gd node-type router"
```

---

## Phase 4 — gold economy

### Task 7: Gold earned from combat

Add gold to the run and grant it on combat victory, scaled by node type via an `EnemyDB` gold range. Spent in the shop (Task 8).

**Files:**
- Modify: `games/deckbuilder-0001/data/EnemyDB.gd` (add `gold_min`/`gold_max` per enemy)
- Modify: `games/deckbuilder-0001/RunController.gd` (`gold` field, `grant_combat_gold`, `spend_gold`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 8, add:

```gdscript
	# Stage 9: gold accrues from combat victories and never goes negative on spend.
	var RC9 := load("res://RunController.gd")
	var r9 = RC9.new()
	r9.start_run(SEED)
	if r9.gold != 0:
		_fail("run did not start with 0 gold"); return
	r9.grant_combat_gold("imp")
	if r9.gold <= 0:
		_fail("defeating imp granted no gold"); return
	var g0: int = r9.gold
	# Spend within budget succeeds and debits.
	if not r9.spend_gold(g0):
		_fail("spending exactly the current gold should succeed"); return
	if r9.gold != 0:
		_fail("gold not debited correctly after spend"); return
	# Overspend is rejected and leaves gold unchanged.
	if r9.spend_gold(1):
		_fail("overspend should be rejected"); return
	if r9.gold != 0:
		_fail("rejected spend must not change gold"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL**

Run the self-test command. Expected: failure on missing `gold`/`grant_combat_gold`/`spend_gold` (RED).

- [ ] **Step 3: Add gold ranges to `EnemyDB`**

In `data/EnemyDB.gd`, add `gold_min`/`gold_max` to each enemy dict. For `imp`: `"gold_min": 10, "gold_max": 15`. `frost_wraith`: `12/18`. `golem`: `25/35`. `archmage`: `45/55`. (Add the two keys inside each existing entry; `enemy()` already deep-duplicates so they carry through.)

- [ ] **Step 4: Add gold to `RunController`**

In `RunController.gd`, add the preload if not present (`EnemyDB` is used elsewhere indirectly — add it):

```gdscript
const EnemyDB := preload("res://data/EnemyDB.gd")
```

Add field + init (`gold = 0` in `start_run`):

```gdscript
var gold: int
```

Add methods:

```gdscript
func grant_combat_gold(enemy_id: String) -> void:
	var e: Dictionary = EnemyDB.enemy(enemy_id)
	var lo: int = e.get("gold_min", 5)
	var hi: int = e.get("gold_max", 10)
	gold += rng.randi_range(lo, hi)

func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
		return false
	gold -= amount
	return true
```

- [ ] **Step 5: Grant gold on live combat win**

In `Main.gd` `_check_combat_outcome()`, in the non-boss win branch (next to the `sync_hp_from_combat` call added in Task 3), add (using the enemy id recorded by `start_node_combat` in Task 5, since map nodes no longer carry an `enemy` field):

```gdscript
				_run.grant_combat_gold(_run.current_enemy_id)
```

(Engine path proven by Stage 9; this just wires live play.)

- [ ] **Step 6: Run the self-test — expect PASS**

Run the self-test command. Expected: `SELFTEST OK`.

- [ ] **Step 7: Commit**

```bash
git add games/deckbuilder-0001/data/EnemyDB.gd games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/Main.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): gold economy — earned per combat, spend-guarded"
```

---

## Phase 5 — shop

### Task 8: Shop inventory + buy/removal logic

A shop node offers a seeded inventory: 3 cards (priced ~50–75 gold), 1 relic (~120–150), and a card-removal service (~75). Buying debits gold and grants the item; removal deletes a chosen deck card. Logic only here; `ShopView` in Task 9.

**Files:**
- Modify: `games/deckbuilder-0001/RunController.gd` (`roll_shop`, `buy_card`, `buy_relic`, `buy_removal`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 9, add:

```gdscript
	# Stage 10: shop — seeded inventory, buying debits gold + grants, blocked when poor.
	var RCa := load("res://RunController.gd")
	var ra = RCa.new()
	ra.start_run(SEED)
	ra.gold = 500
	var shop: Dictionary = ra.roll_shop()
	if shop.get("cards", []).size() != 3:
		_fail("shop did not offer 3 cards"); return
	if not shop.has("relic") or not shop.has("removal_cost"):
		_fail("shop missing relic/removal entries"); return
	var deck_n: int = ra.deck.size()
	var first_card: String = shop["cards"][0]["id"]
	var price: int = shop["cards"][0]["cost"]
	var g_before: int = ra.gold
	if not ra.buy_card(shop, 0):
		_fail("buying an affordable card failed"); return
	if ra.gold != g_before - price:
		_fail("buy_card did not debit the price"); return
	if ra.deck.size() != deck_n + 1 or ra.deck[ra.deck.size() - 1] != first_card:
		_fail("buy_card did not add the card to the deck"); return
	# Removal shrinks the deck and costs gold.
	var dn2: int = ra.deck.size()
	if not ra.buy_removal(shop, 0):
		_fail("affordable removal failed"); return
	if ra.deck.size() != dn2 - 1:
		_fail("removal did not remove a card"); return
	# Too poor is rejected.
	ra.gold = 0
	if ra.buy_card(shop, 1):
		_fail("buying with 0 gold should be rejected"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL**

Run the self-test command. Expected: failure on missing `roll_shop`/`buy_card`/`buy_removal` (RED).

- [ ] **Step 3: Implement the shop in `RunController`**

Add the preload (if not present) `const RelicDB := preload("res://data/RelicDB.gd")` (added in Task 2) and `const CardDB` (already present). Add:

```gdscript
func roll_shop() -> Dictionary:
	# Seeded inventory. Cards drawn from CardDB, relic from un-owned RelicDB ids.
	var ids: Array = CardDB.all_ids().duplicate()
	_shuffle_run(ids)
	var cards: Array = []
	for i in range(3):
		var cid: String = ids[i]
		cards.append({"id": cid, "cost": rng.randi_range(50, 75)})
	# Relic: first un-owned relic id (or "" if none left).
	var relic_id: String = ""
	for rid in RelicDB.all_ids():
		if not (rid in relics):
			relic_id = rid
			break
	return {
		"cards": cards,
		"relic": {"id": relic_id, "cost": rng.randi_range(120, 150)},
		"removal_cost": 75,
		"removed": false,
	}

func buy_card(shop: Dictionary, index: int) -> bool:
	var cards: Array = shop.get("cards", [])
	if index < 0 or index >= cards.size():
		return false
	var entry: Dictionary = cards[index]
	if entry.get("bought", false):
		return false
	if not spend_gold(entry.get("cost", 999999)):
		return false
	deck.append(entry["id"])
	entry["bought"] = true
	return true

func buy_relic(shop: Dictionary) -> bool:
	var entry: Dictionary = shop.get("relic", {})
	var rid: String = entry.get("id", "")
	if rid == "" or entry.get("bought", false):
		return false
	if not spend_gold(entry.get("cost", 999999)):
		return false
	relics.append(rid)
	entry["bought"] = true
	return true

func buy_removal(shop: Dictionary, deck_index: int) -> bool:
	if shop.get("removed", false):
		return false
	if deck_index < 0 or deck_index >= deck.size():
		return false
	if not spend_gold(shop.get("removal_cost", 999999)):
		return false
	deck.remove_at(deck_index)
	shop["removed"] = true
	return true

# Fisher-Yates over the run's seeded rng (member helper; mirrors CombatState._shuffle).
func _shuffle_run(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
```

- [ ] **Step 4: Run the self-test — expect PASS**

Run the self-test command. Expected: `SELFTEST OK`.

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): shop inventory + buy/removal logic"
```

---

### Task 9: `ShopView` screen + routing

**Files:**
- Create: `games/deckbuilder-0001/ShopView.gd` + node in `Main.tscn`
- Modify: `games/deckbuilder-0001/Main.gd` (route `shop` node → `ShopView`)
- Acceptance: real-renderer screenshot

- [ ] **Step 1: Create `ShopView.gd` (contract + skeleton)**

Create `games/deckbuilder-0001/ShopView.gd`, following `CombatView.gd` conventions:

```gdscript
extends Node2D

# ShopView — merchant screen.
# Contract:
#   refresh(shop: Dictionary, gold: int, deck: Array) -> void
#   get_card_rect(i: int) -> Rect2        # 3 card-for-sale rects
#   get_relic_rect() -> Rect2
#   get_removal_rect() -> Rect2           # "remove a card" button
#   get_leave_rect() -> Rect2             # exit to map
# Draw: gold counter; 3 cards with prices (dim if bought/unaffordable);
# the relic with price; a removal button; a Leave button. Reuse CombatView palette/font.

var _shop: Dictionary = {}
var _gold: int = 0
var _deck: Array = []

func refresh(shop: Dictionary, gold: int, deck: Array) -> void:
	_shop = shop; _gold = gold; _deck = deck; queue_redraw()

func _draw() -> void:
	# ... per the layout note ...
	pass

func get_card_rect(i: int) -> Rect2: return Rect2()
func get_relic_rect() -> Rect2: return Rect2()
func get_removal_rect() -> Rect2: return Rect2()
func get_leave_rect() -> Rect2: return Rect2()
```

- [ ] **Step 2: Add `ShopView` node to `Main.tscn`** (sibling of `CombatView`, hidden by default).

- [ ] **Step 3: Route shop nodes in `Main.gd`**

In `_enter_node()`'s `match`, replace the `shop` fall-through with a real branch:

```gdscript
		"shop":
			_view.visible = false; _map_view.visible = false
			_shop_view.visible = true
			_active_shop = _run.roll_shop()
			_state = State.SHOP
			_shop_view.refresh(_active_shop, _run.gold, _run.deck)
```

Add `@onready var _shop_view: Node2D = $ShopView` and `var _active_shop: Dictionary = {}`. Add a `removal_mode` minimal interaction: tapping the removal button enters a deck-pick (for the slice, remove the first card via `buy_removal(_active_shop, 0)` to keep UI simple, or list the deck — implementer's call; the simple path is acceptable for this pass and noted for `visual-audit`/later polish). Add shop tap handling:

```gdscript
			State.SHOP:
				_handle_shop_tap(pos)
```
```gdscript
func _handle_shop_tap(pos: Vector2) -> void:
	if _shop_view.get_leave_rect().has_point(pos):
		_show_map(); return
	for i in 3:
		if _shop_view.get_card_rect(i).has_point(pos):
			_run.buy_card(_active_shop, i)
			_shop_view.refresh(_active_shop, _run.gold, _run.deck); return
	if _shop_view.get_relic_rect().has_point(pos):
		_run.buy_relic(_active_shop)
		_shop_view.refresh(_active_shop, _run.gold, _run.deck); return
	if _shop_view.get_removal_rect().has_point(pos):
		_run.buy_removal(_active_shop, 0)
		_shop_view.refresh(_active_shop, _run.gold, _run.deck); return
```

- [ ] **Step 4: Run the self-test — expect PASS** (only `Main.gd`/views changed). Expected: `SELFTEST OK`.

- [ ] **Step 5: Screenshot** the shop (`run_layer_shop.png` in probe-data). Acceptance artifact.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/ShopView.gd games/deckbuilder-0001/Main.tscn games/deckbuilder-0001/Main.gd
git commit -m "feat(deckbuilder-0001): ShopView screen + routing"
```

---

## Phase 6 — events

### Task 10: `EventDB` + event resolution logic

Data-driven events: each has a title, body, and 2–3 choices; each choice lists outcome effects (`gold`, `hp`, `add_card`, `remove_card`, `relic`). Resolution applies a chosen choice's effects to the run.

**Files:**
- Create: `games/deckbuilder-0001/data/EventDB.gd`
- Modify: `games/deckbuilder-0001/RunController.gd` (`roll_event`, `resolve_event_choice`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 10, add:

```gdscript
	# Stage 11: events — a chosen choice applies its outcome effects to the run.
	var RCb := load("res://RunController.gd")
	var rb = RCb.new()
	rb.start_run(SEED)
	rb.gold = 100
	rb.run_hp = 50
	var ev: Dictionary = rb.roll_event()
	if ev.get("choices", []).is_empty():
		_fail("event had no choices"); return
	# Find a choice that grants gold and verify it applies.
	var gold_choice: int = -1
	for i in ev["choices"].size():
		if ev["choices"][i].get("effects", {}).has("gold"):
			gold_choice = i; break
	if gold_choice < 0:
		_fail("no event choice grants gold to test"); return
	var g0: int = rb.gold
	var delta: int = ev["choices"][gold_choice]["effects"]["gold"]
	rb.resolve_event_choice(ev, gold_choice)
	if rb.gold != g0 + delta:
		_fail("event gold effect not applied"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL** (missing `roll_event`/`resolve_event_choice`). RED.

- [ ] **Step 3: Create `EventDB`**

Create `games/deckbuilder-0001/data/EventDB.gd`:

```gdscript
extends Node

# Data-driven events. Each choice's "effects" dict may contain:
#   "gold": int (delta), "hp": int (delta, capped at run_max_hp),
#   "add_card": String (card id appended to deck),
#   "remove_card": bool (remove first deck card),
#   "relic": String (relic id granted).
const EVENTS := {
	"wandering_alchemist": {
		"id": "wandering_alchemist",
		"title": "The Wandering Alchemist",
		"body": "A hooded figure offers a vial — for a price.",
		"choices": [
			{"label": "Drink it (heal 15)", "effects": {"hp": 15}},
			{"label": "Buy a secret (-40 gold, +relic)", "effects": {"gold": -40, "relic": "storm_core"}},
			{"label": "Decline", "effects": {}},
		],
	},
	"cursed_altar": {
		"id": "cursed_altar",
		"title": "Cursed Altar",
		"body": "Gold glints on a blood-stained altar.",
		"choices": [
			{"label": "Take the gold (+60, -10 HP)", "effects": {"gold": 60, "hp": -10}},
			{"label": "Cleanse a card (remove)", "effects": {"remove_card": true}},
			{"label": "Leave", "effects": {}},
		],
	},
	"arcane_font": {
		"id": "arcane_font",
		"title": "Arcane Font",
		"body": "Raw magic pools in a cracked basin.",
		"choices": [
			{"label": "Channel it (+1 card: chain_lightning)", "effects": {"add_card": "chain_lightning"}},
			{"label": "Rest here (heal 10)", "effects": {"hp": 10}},
		],
	},
}

static func all_ids() -> Array:
	return EVENTS.keys()

static func event(id: String) -> Dictionary:
	return EVENTS.get(id, {}).duplicate(true)
```

- [ ] **Step 4: Implement event roll + resolution in `RunController`**

Add the preload `const EventDB := preload("res://data/EventDB.gd")`. Add:

```gdscript
func roll_event() -> Dictionary:
	var ids: Array = EventDB.all_ids()
	var pick: String = ids[rng.randi_range(0, ids.size() - 1)]
	return EventDB.event(pick)

func resolve_event_choice(ev: Dictionary, choice_index: int) -> void:
	var choices: Array = ev.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var fx: Dictionary = choices[choice_index].get("effects", {})
	if fx.has("gold"):
		gold = max(0, gold + int(fx["gold"]))
	if fx.has("hp"):
		run_hp = clampi(run_hp + int(fx["hp"]), 0, run_max_hp)
	if fx.has("add_card"):
		deck.append(String(fx["add_card"]))
	if fx.get("remove_card", false) and not deck.is_empty():
		deck.remove_at(0)
	if fx.has("relic"):
		var rid: String = String(fx["relic"])
		if not (rid in relics):
			relics.append(rid)
```

- [ ] **Step 5: Run the self-test — expect PASS.** `SELFTEST OK`.

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/data/EventDB.gd games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): EventDB + event resolution"
```

---

### Task 11: `EventView` screen + routing

**Files:**
- Create: `games/deckbuilder-0001/EventView.gd` + node in `Main.tscn`
- Modify: `games/deckbuilder-0001/Main.gd` (route `event` node)
- Acceptance: screenshot

- [ ] **Step 1: Create `EventView.gd` (contract + skeleton)**

```gdscript
extends Node2D

# EventView — narrative event with choice buttons.
# Contract:
#   refresh(event: Dictionary) -> void
#   get_choice_rect(i: int) -> Rect2   # one rect per choice
# Draw: title, body text (wrapped), and a stacked button per choice (label text).
# Reuse CombatView palette/font; choices are full-width buttons.

var _event: Dictionary = {}

func refresh(event: Dictionary) -> void:
	_event = event; queue_redraw()

func _draw() -> void:
	pass

func get_choice_rect(i: int) -> Rect2: return Rect2()
```

- [ ] **Step 2: Add `EventView` to `Main.tscn`** (hidden sibling).

- [ ] **Step 3: Route event nodes in `Main.gd`**

Add `@onready var _event_view: Node2D = $EventView` and `var _active_event: Dictionary = {}`. In `_enter_node()`'s `match`, add:

```gdscript
		"event":
			_view.visible = false; _map_view.visible = false
			_event_view.visible = true
			_active_event = _run.roll_event()
			_state = State.EVENT
			_event_view.refresh(_active_event)
```

Add tap handling:

```gdscript
			State.EVENT:
				_handle_event_tap(pos)
```
```gdscript
func _handle_event_tap(pos: Vector2) -> void:
	var choices: Array = _active_event.get("choices", [])
	for i in choices.size():
		if _event_view.get_choice_rect(i).has_point(pos):
			_run.resolve_event_choice(_active_event, i)
			_show_map()
			return
```

- [ ] **Step 4: Run the self-test — expect PASS.** `SELFTEST OK`.

- [ ] **Step 5: Screenshot** (`run_layer_event.png`).

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/EventView.gd games/deckbuilder-0001/Main.tscn games/deckbuilder-0001/Main.gd
git commit -m "feat(deckbuilder-0001): EventView screen + routing"
```

---

## Phase 7 — campfire + card upgrades

### Task 12: Card upgrade transform in `CardDB`

A campfire can upgrade a card: `arcane_bolt` → `arcane_bolt+` with a better effect. Implement upgrades as a transform that, given a card id, returns its upgraded id and registers the upgraded card definition. Keep it data-driven: an `UPGRADES` table mapping base id → upgraded def.

**Files:**
- Modify: `games/deckbuilder-0001/data/CardDB.gd` (add `UPGRADES`, `upgrade_id`, `is_upgraded`, extend `card()`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 11, add:

```gdscript
	# Stage 12: card upgrades — upgraded card has a stronger effect and upgrades once.
	var base_card: Dictionary = CardDB.card("arcane_bolt")
	var up_id: String = CardDB.upgrade_id("arcane_bolt")
	if up_id == "arcane_bolt" or up_id == "":
		_fail("arcane_bolt has no upgrade id"); return
	var up_card: Dictionary = CardDB.card(up_id)
	if up_card.is_empty():
		_fail("upgraded card def not found"); return
	if up_card.effect.get("damage", 0) <= base_card.effect.get("damage", 0):
		_fail("upgraded arcane_bolt is not stronger"); return
	# An already-upgraded card does not upgrade again.
	if CardDB.upgrade_id(up_id) != up_id:
		_fail("an upgraded card should not upgrade further"); return
	if not CardDB.is_upgraded(up_id):
		_fail("is_upgraded should be true for the upgraded id"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL** (missing `upgrade_id`/`is_upgraded`). RED.

- [ ] **Step 3: Add upgrades to `CardDB`**

In `data/CardDB.gd`, after the `CARDS` const add an `UPGRADES` table and helpers. Each upgraded def is a full card dict with `+` appended to id/name and a buffed effect:

```gdscript
const UPGRADES := {
	"arcane_bolt": {"id": "arcane_bolt+", "name": "Arcane Bolt+", "element": "neutral", "cost": 1, "type": "attack", "effect": {"damage": 9}},
	"ward":        {"id": "ward+",        "name": "Ward+",        "element": "neutral", "cost": 1, "type": "skill",  "effect": {"block": 8}},
	"ember":       {"id": "ember+",       "name": "Ember+",       "element": "fire",    "cost": 1, "type": "attack", "effect": {"damage": 7, "burn": 3}},
	"frost_shard": {"id": "frost_shard+", "name": "Frost Shard+", "element": "ice",     "cost": 1, "type": "attack", "effect": {"damage": 6, "block": 6}},
	"spark":       {"id": "spark+",       "name": "Spark+",       "element": "lightning","cost": 0, "type": "attack", "effect": {"damage": 4, "lightning_bonus": 4}},
	"chain_lightning": {"id": "chain_lightning+", "name": "Chain Lightning+", "element": "lightning", "cost": 1, "type": "attack", "effect": {"damage": 7, "lightning_bonus": 8}},
}

# Upgraded id for a base card, or the same id if it has no upgrade / is already upgraded.
static func upgrade_id(id: String) -> String:
	if is_upgraded(id):
		return id
	if UPGRADES.has(id):
		return UPGRADES[id]["id"]
	return id

static func is_upgraded(id: String) -> bool:
	return id.ends_with("+")
```

Extend `card()` so upgraded ids resolve (they live in `UPGRADES`, keyed by base id):

```gdscript
static func card(id: String) -> Dictionary:
	if CARDS.has(id):
		return CARDS[id]
	# upgraded ids: find the upgrade def whose id matches.
	for base in UPGRADES:
		if UPGRADES[base]["id"] == id:
			return UPGRADES[base]
	return {}
```

- [ ] **Step 4: Run the self-test — expect PASS.** `SELFTEST OK`. (Existing combat assertions still pass — base cards unchanged.)

- [ ] **Step 5: Commit**

```bash
git add games/deckbuilder-0001/data/CardDB.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): card upgrade transform in CardDB"
```

---

### Task 13: Campfire logic + `CampfireView` + routing

Campfire offers two choices: **Rest** (heal 30% of max HP) or **Upgrade** (upgrade the first upgradeable deck card). Logic in `RunController`; a screen + routing.

**Files:**
- Modify: `games/deckbuilder-0001/RunController.gd` (`campfire_rest`, `campfire_upgrade`)
- Create: `games/deckbuilder-0001/CampfireView.gd` + node in `Main.tscn`
- Modify: `games/deckbuilder-0001/Main.gd` (route `campfire` node)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 12, add:

```gdscript
	# Stage 13: campfire — rest heals (capped); upgrade swaps a deck card for its + version.
	var RCc := load("res://RunController.gd")
	var rc = RCc.new()
	rc.start_run(SEED)
	rc.run_max_hp = 70
	rc.run_hp = 40
	rc.campfire_rest()
	if rc.run_hp <= 40 or rc.run_hp > rc.run_max_hp:
		_fail("campfire_rest did not heal within cap"); return
	# Upgrade: deck has arcane_bolt; after upgrade an arcane_bolt+ should appear.
	var had_base: bool = "arcane_bolt" in rc.deck
	if not had_base:
		_fail("starter deck unexpectedly lacks arcane_bolt"); return
	rc.campfire_upgrade()
	if not ("arcane_bolt+" in rc.deck):
		_fail("campfire_upgrade did not produce an upgraded card"); return
```

- [ ] **Step 2: Run the self-test — expect FAIL** (missing `campfire_rest`/`campfire_upgrade`). RED.

- [ ] **Step 3: Implement campfire logic in `RunController`**

```gdscript
func campfire_rest() -> void:
	var heal: int = int(round(run_max_hp * 0.30))
	run_hp = min(run_max_hp, run_hp + heal)

func campfire_upgrade() -> void:
	# Upgrade the first deck card that has an upgrade and isn't already upgraded.
	for i in deck.size():
		var id: String = deck[i]
		var up: String = CardDB.upgrade_id(id)
		if up != id:
			deck[i] = up
			return
```

- [ ] **Step 4: Run the self-test — expect PASS.** `SELFTEST OK`.

- [ ] **Step 5: Create `CampfireView.gd` (contract + skeleton)**

```gdscript
extends Node2D

# CampfireView — rest site with two choices.
# Contract:
#   refresh(run_hp: int, run_max_hp: int) -> void
#   get_rest_rect() -> Rect2
#   get_upgrade_rect() -> Rect2
# Draw: a campfire scene header, current HP, and two big buttons: Rest (heal 30%)
# and Upgrade a card. Reuse CombatView palette/font.

var _hp: int = 0
var _max: int = 0

func refresh(run_hp: int, run_max_hp: int) -> void:
	_hp = run_hp; _max = run_max_hp; queue_redraw()

func _draw() -> void:
	pass

func get_rest_rect() -> Rect2: return Rect2()
func get_upgrade_rect() -> Rect2: return Rect2()
```

- [ ] **Step 6: Add `CampfireView` to `Main.tscn`** (hidden sibling).

- [ ] **Step 7: Route campfire in `Main.gd`**

Replace the Task-6 placeholder `campfire` branch in `_enter_node()` with:

```gdscript
		"campfire":
			_view.visible = false; _map_view.visible = false
			_campfire_view.visible = true
			_state = State.CAMPFIRE
			_campfire_view.refresh(_run.run_hp, _run.run_max_hp)
```

Add `@onready var _campfire_view: Node2D = $CampfireView` and tap handling:

```gdscript
			State.CAMPFIRE:
				_handle_campfire_tap(pos)
```
```gdscript
func _handle_campfire_tap(pos: Vector2) -> void:
	if _campfire_view.get_rest_rect().has_point(pos):
		_run.campfire_rest(); _show_map(); return
	if _campfire_view.get_upgrade_rect().has_point(pos):
		_run.campfire_upgrade(); _show_map(); return
```

- [ ] **Step 8: Run the self-test — expect PASS.** `SELFTEST OK`.

- [ ] **Step 9: Screenshot** (`run_layer_campfire.png`).

- [ ] **Step 10: Commit**

```bash
git add games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/CampfireView.gd games/deckbuilder-0001/Main.tscn games/deckbuilder-0001/Main.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): campfire rest/upgrade + CampfireView + routing"
```

---

## Phase 8 — relic pool + treasure

### Task 14: Expand the relic pool + treasure node grant

Grow `RelicDB` from 2 to 7 relics with real hooks, implement `storm_core`'s effect (was a no-op), wire run-start and combat-win hooks into `RunController`, and make `treasure` nodes grant an un-owned relic.

**Relics (id → hook → effect):**
- `ember_heart` — on_combat_start — +1 Burn on enemy (existing).
- `storm_core` — on_combat_start — `cs.mana_max += 1` (NEW; was no-op).
- `iron_ward` — on_combat_start — `cs.player_block += 5` (start each combat with 5 block).
- `arcane_battery` — on_combat_start — draw 1 extra card at combat start (`cs._draw(1)`).
- `vitality_charm` — on_run_start — `run_max_hp += 10; run_hp += 10`.
- `gold_idol` — on_combat_win — `gold += 5`.
- `lucky_coin` — on_combat_win — `gold += 3`.

**Files:**
- Modify: `games/deckbuilder-0001/data/RelicDB.gd` (entries + dispatchers)
- Modify: `games/deckbuilder-0001/RunController.gd` (call `apply_run_start` in `start_run`; `apply_combat_win` on win; `grant_treasure_relic`)
- Test: `games/deckbuilder-0001/selftest.gd`

- [ ] **Step 1: Write the failing assertions first**

In `selftest.gd`, after Stage 13, add:

```gdscript
	# Stage 14: relic pool — each hook fires; storm_core now adds max mana; treasure grants.
	var RCd := load("res://RunController.gd")
	# storm_core: +1 max mana at combat start.
	var rd = RCd.new()
	rd.start_run(SEED)
	rd.relics.append("storm_core")
	var cd = rd.start_node_combat()
	if cd.mana_max < 4:
		_fail("storm_core did not raise max mana"); return
	# iron_ward: start combat with >=5 block.
	var rw = RCd.new()
	rw.start_run(SEED)
	rw.relics.append("iron_ward")
	var cw = rw.start_node_combat()
	if cw.player_block < 5:
		_fail("iron_ward did not grant starting block"); return
	# vitality_charm: on run start, +10 max HP.
	var rv = RCd.new()
	rv.relics.append("vitality_charm")        # owned before start_run applies run-start hooks
	rv.start_run(SEED)
	# start_run resets relics to [ember_heart]; to test run-start we apply explicitly:
	var RelicDB14 := load("res://data/RelicDB.gd")
	RelicDB14.apply_run_start(["vitality_charm"], rv)
	if rv.run_max_hp < 80:
		_fail("vitality_charm did not raise run max HP"); return
	# gold_idol: on combat win, +5 gold.
	var rg = RCd.new()
	rg.start_run(SEED)
	rg.relics.append("gold_idol")
	var g0: int = rg.gold
	RelicDB14.apply_combat_win(rg.relics, rg)
	if rg.gold < g0 + 5:
		_fail("gold_idol did not grant combat-win gold"); return
	# treasure: grants an un-owned relic.
	var rt = RCd.new()
	rt.start_run(SEED)
	var owned0: int = rt.relics.size()
	rt.grant_treasure_relic()
	if rt.relics.size() != owned0 + 1:
		_fail("treasure did not grant a relic"); return
```

> Note on `vitality_charm`: `start_run` resets `relics` to `["ember_heart"]`, so to keep this a pure unit check we apply the run-start hook explicitly. In live play, run-start relics are seeded before the reset only via meta-unlocks (out of scope); the hook itself is what we prove here.

- [ ] **Step 2: Run the self-test — expect FAIL** (storm_core no-op, missing hooks/`grant_treasure_relic`). RED.

- [ ] **Step 3: Expand `RelicDB`**

Replace the `RELICS` const and dispatchers in `data/RelicDB.gd`:

```gdscript
const RELICS := {
	"ember_heart":    {"id": "ember_heart",    "name": "Ember Heart",    "hook": "on_combat_start", "desc": "Combat start: apply 1 Burn."},
	"storm_core":     {"id": "storm_core",     "name": "Storm Core",     "hook": "on_combat_start", "desc": "+1 max mana each combat."},
	"iron_ward":      {"id": "iron_ward",      "name": "Iron Ward",      "hook": "on_combat_start", "desc": "Start each combat with 5 Block."},
	"arcane_battery": {"id": "arcane_battery", "name": "Arcane Battery",  "hook": "on_combat_start", "desc": "Draw 1 extra card at combat start."},
	"vitality_charm": {"id": "vitality_charm", "name": "Vitality Charm",  "hook": "on_run_start",    "desc": "+10 max HP."},
	"gold_idol":      {"id": "gold_idol",      "name": "Gold Idol",       "hook": "on_combat_win",   "desc": "+5 gold per combat."},
	"lucky_coin":     {"id": "lucky_coin",     "name": "Lucky Coin",      "hook": "on_combat_win",   "desc": "+3 gold per combat."},
}

static func relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

static func all_ids() -> Array:
	return RELICS.keys()

static func apply_combat_start(owned: Array, cs) -> void:
	for id in owned:
		match id:
			"ember_heart":
				cs.enemy["statuses"]["burn"] = cs.enemy.statuses.get("burn", 0) + 1
			"storm_core":
				cs.mana_max += 1
				cs.mana = cs.mana_max
			"iron_ward":
				cs.player_block += 5
			"arcane_battery":
				cs._draw(1)

static func apply_run_start(owned: Array, run) -> void:
	for id in owned:
		match id:
			"vitality_charm":
				run.run_max_hp += 10
				run.run_hp += 10

static func apply_combat_win(owned: Array, run) -> void:
	for id in owned:
		match id:
			"gold_idol":
				run.gold += 5
			"lucky_coin":
				run.gold += 3
```

- [ ] **Step 4: Wire run-start + combat-win hooks + treasure in `RunController`**

In `start_run`, after `run_hp = run_max_hp`, apply run-start relics (currently just `ember_heart`, but keep the call so unlocked run-start relics work):

```gdscript
	RelicDB.apply_run_start(relics, self)
```

Add a treasure grant method:

```gdscript
func grant_treasure_relic() -> void:
	# Grant the first un-owned relic (deterministic; seeded pick among un-owned).
	var pool: Array = []
	for rid in RelicDB.all_ids():
		if not (rid in relics):
			pool.append(rid)
	if pool.is_empty():
		return
	relics.append(pool[rng.randi_range(0, pool.size() - 1)])
```

In `Main.gd` `_check_combat_outcome()` non-boss win branch, after `grant_combat_gold`, apply combat-win relics:

```gdscript
				_run.apply_combat_win_relics()
```

Add the thin wrapper in `RunController` (so `Main` doesn't reach into `RelicDB`):

```gdscript
func apply_combat_win_relics() -> void:
	RelicDB.apply_combat_win(relics, self)
```

Route `treasure` nodes in `Main.gd` `_enter_node()` (replace the placeholder fall-through): treasure auto-grants a relic then returns to the map (a one-line reward; a fuller chest screen is a later polish):

```gdscript
		"treasure":
			_run.grant_treasure_relic()
			_advance_to_map()
```

- [ ] **Step 5: Run the self-test — expect PASS.** `SELFTEST OK`. (Stage 5's `ember_heart` characterization still passes — its dispatcher branch is unchanged.)

- [ ] **Step 6: Commit**

```bash
git add games/deckbuilder-0001/data/RelicDB.gd games/deckbuilder-0001/RunController.gd games/deckbuilder-0001/Main.gd games/deckbuilder-0001/selftest.gd
git commit -m "feat(deckbuilder-0001): 7-relic pool with hooks + treasure node grant"
```

---

## Phase 9 — finalize

### Task 15: Validator pass, `depth_pass` record, manifest update

**Files:**
- Modify: `manifests/deckbuilder-0001.json` (add `depth_pass`)
- Run: validator methods + full self-test

- [ ] **Step 1: Run the full self-test (final regression gate)**

Run the self-test command. Expected: `SELFTEST OK`. Count the new assertion stages added across Tasks 2–14 (Stages 5–14) for the `depth_pass` record.

- [ ] **Step 2: Run validator Methods 1 / 1.5 / 1.6 on the grown game**

Per `.claude/skills/validator/SKILL.md`, run the programmatic open/run check and the logic self-test methods. Expected: all pass (the game opens headless, the self-test is green, turn-based scripted-turn logic holds).

- [ ] **Step 3: Record `depth_pass` in the manifest**

In `manifests/deckbuilder-0001.json`, add a top-level `depth_pass` block:

```json
"depth_pass": {
  "axis": "run-meta",
  "systems_added": [
    "relic-hooks-refactor", "run-persistent-hp", "branching-map",
    "gold", "shop", "events", "card-upgrades", "campfire", "relic-pool", "treasure"
  ],
  "selftest_assertions_added": 10,
  "notes": "STS-style run layer over an intact CombatState. Surfaced behavior-change: CombatState.setup gained an optional start_hp arg for run-persistent HP; storm_core relic given a real effect (was a no-op). Combat rules otherwise unchanged. Views (Map/Shop/Event/Campfire) wired by deepen; final look is visual-audit's job."
}
```

(Set `selftest_assertions_added` to the actual count of new Stages from Step 1 if it differs from 10.)

- [ ] **Step 4: Validate the manifest**

Run: `node tools/manifest.mjs validate` (or the repo's manifest validator). Expected: OK.

- [ ] **Step 5: Commit**

```bash
git add manifests/deckbuilder-0001.json
git commit -m "chore(deckbuilder-0001): record run-layer depth_pass; validator green"
```

---

### Task 16: Harden `deepen/SKILL.md` from the dogfood (the real deliverable)

The whole point: the skill was a draft; now fold in what building the run layer actually taught.

**Files:**
- Modify: `.claude/skills/deepen/SKILL.md`

- [ ] **Step 1: Capture the dogfood lessons**

Review Tasks 2–15 and add a short "Lessons from first use" subsection to `deepen/SKILL.md` with the durable findings that actually surfaced. Seed it with these (confirm/adjust against what really happened during execution — do not record a lesson that didn't occur):
- **Characterization-before-refactor:** the `ember_heart` behavior wasn't covered, so the relic refactor needed a pin-first assertion. Generalize: *before a pure refactor, if the touched behavior isn't already asserted, add a characterization test that passes both before and after.* (This nuance is already in the method — confirm the wording matches reality.)
- **Surfaced behavior-changes are normal and must be named:** the `CombatState.setup(start_hp)` seam and giving `storm_core` a real effect both changed previously-frozen logic. The skill's "surface, don't swallow" rule earned its keep — note them in `depth_pass.notes`.
- **Logic-vs-view split kept the gate meaningful:** every system landed its selftest assertion *before* any screen existed, so the self-test never depended on rendering. Generalize the ordering rule: *prove the system headless first, wire the screen second.*
- Any *new* lesson the executor hit (e.g. a map-gen guarantee that needed a force-place, or a determinism trap) gets added here in the executor's own words.

- [ ] **Step 2: Update the memory pointer (if the agent maintains MEMORY.md)**

Add/refresh the deckbuilder thread's memory line to note the run-layer deepening + the new `deepen` skill (per the repo's memory conventions). Skip if memory is managed out-of-band.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/deepen/SKILL.md
git commit -m "docs(deepen): harden the skill from its first dogfood (run-layer)"
```

---

## Self-review notes (author)

- **Spec coverage:** Part-1 skill → Task 1 (+ hardened in Task 16). Part-2 systems → refactor seam (T2), HP (T3), map (T4–6), gold (T7), shop (T8–9), events (T10–11), upgrades+campfire (T12–13), relic pool + treasure (T14), validate + `depth_pass` (T15). Every spec table row maps to a task.
- **TDD discipline:** every logic system has assertion-first → RED → implement → GREEN → commit. View tasks are explicitly screenshot-accepted (no fake unit tests over rendering).
- **Type/name consistency:** `RunController` public surface used across tasks — `start_run`, `start_node_combat`, `current_node`, `current_node_id`, `available_next`, `choose_next`, `is_on_boss`, `sync_hp_from_combat`, `gold`, `grant_combat_gold`, `spend_gold`, `roll_shop`, `buy_card`/`buy_relic`/`buy_removal`, `roll_event`, `resolve_event_choice`, `campfire_rest`, `campfire_upgrade`, `grant_treasure_relic`, `apply_combat_win_relics`, `run_hp`/`run_max_hp`, `relics`, `deck`, `map`. `RelicDB`: `apply_combat_start`/`apply_run_start`/`apply_combat_win`, `all_ids`, `relic`. `CardDB`: `card`, `upgrade_id`, `is_upgraded`, `UPGRADES`. `MapModel`/`MapGen` query surface matches the self-test usages. Verified consistent across tasks.
- **Determinism & autoload rules** restated in the conventions block and used throughout (seeded Fisher–Yates in MapGen/shop; data via preload+static).
- **Known soft spots (acceptable for this pass, flagged for `visual-audit`/later):** shop card-removal uses a simplified "remove first card" interaction rather than a deck picker; treasure is a one-line auto-grant rather than a chest screen; `vitality_charm`/run-start relics only matter once meta-unlocks seed relics pre-`start_run` (out of scope). None block the gate.
