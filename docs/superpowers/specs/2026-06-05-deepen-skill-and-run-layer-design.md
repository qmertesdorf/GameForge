# Design — the `deepen` skill + deckbuilder STS-style run layer

**Date:** 2026-06-05
**Status:** approved (brainstorming → spec)
**Vehicle game:** `games/deckbuilder-0001` (status `playable`)

## North star

The deliverable is a **better skill**, not the game. GameForge's loop is build-once
(`concept → builder → validator → playtest`) and nothing owns *iterating on an
already-playable game* — yet the project's 5th quality axis is "expandable depth /
retention." This work creates the missing skill, **`deepen`**, and proves it by
dogfooding it on a real expansion of the deckbuilder's run layer.

Approach chosen: **skill-first, dogfood-refine.** Draft `deepen/SKILL.md` from first
principles + this project's accumulated wisdom, then build the run-layer expansion *by
following it*, hardening the skill wherever reality fights the draft.

---

## Part 1 — the `deepen` skill (the real deliverable)

**Purpose.** Given an already-playable game, grow a chosen depth axis (systemic /
content / run-meta) **without regressing proven behavior**, and **prove** the new depth
actually landed.

**Loop position.** `deepen` is the loop's first *iteration* skill (everything else is
build-once). It operates in place on a `validated`/`playable` game and loops back through
the validator. It does **not** advance status — a deeper game is the same status, just
bigger:

```
prompt → concept → builder → validator → playtest → ( deepen → validator → playtest )*  → asset → visual-audit → audio → packager
```

**Inputs:** a game at ≥ `validated` with a working `selftest.gd`; a chosen depth axis +
scope (spec-given here; the skill guides the assessment when run autonomously).

**Outputs:** extended game code; a grown `selftest.gd`; a `manifest.depth_pass` record;
a hardened `deepen/SKILL.md`.

### The method (the reusable spine)

1. **Assess depth.** Name the axis the game is thin on and the highest-leverage
   expansion.
2. **Decompose into sub-systems.** Each one purpose, clean interface (data layer +
   logic + screen). Identify **extension seams**: where existing code already supports
   extension (e.g. `CardDB` static funcs) vs. where you must **refactor to create a seam
   first** (e.g. a hardcoded linear run → a node-type state machine).
   **Refactor-for-seam before adding content** — a pure refactor adds behavior nowhere,
   so the existing selftest staying green *is* its proof (zero new assertions).
3. **TDD each new system on the selftest** — the validation spine, and the deliberate
   inverse of the reskin rule:
   - **`deepen` EXTENDS logic; it does NOT freeze it.** (Stated explicitly because it is
     the exact opposite of the `asset`/reskin "logic FROZEN" gate and easy to confuse.)
   - Existing assertions = **regression guard**; must stay `SELFTEST OK` after every
     change.
   - Each new system: **write its assertion first (RED) → implement → GREEN.** New
     mechanics are proven the same deterministic, headless way the original logic was.
   - **Never weaken or delete an existing assertion to make room.** If a new system
     changes old behavior, **surface it** (call it out, confirm it's intended) — do not
     silently overwrite.
4. **One sub-system at a time**, each independently selftested. Don't batch five then
   debug the soup. A playable game at every step.
5. **Grow the UI per system**, reusing established chrome. Hand composited-screen
   judgment to `visual-audit` and correctness to `validator` — `deepen` owns *systems &
   content*, not pixels or the gate mechanics.
6. **Record + codify.** Write a lightweight `manifest.depth_pass` block (axis, systems
   added, new-assertion count) for provenance; fold durable lessons back into the skill.

### `manifest.depth_pass` shape (lightweight)

```json
"depth_pass": {
  "axis": "run-meta",
  "systems_added": ["branching-map", "gold", "shop", "events", "campfire", "card-upgrades", "relic-pool"],
  "selftest_assertions_added": 0,
  "notes": "STS-style run layer; combat rules intact except HP-thread + gold-grant seams"
}
```
(`selftest_assertions_added` filled at the end from the actual count.)

### Skill boundaries / non-goals

- Not a re-skin (that's `asset` + `visual-audit`) and not the audio pass.
- Does not invent a new status or touch the packaging gate.
- Does not redesign the game from scratch — it grows what exists along one axis.

---

## Part 2 — first worked example: deckbuilder STS-style run layer

The deepening axis is **run & meta structure** (the retention engine). We replace the
hardcoded linear 5-node run with a Slay-the-Spire-style branching map and the
out-of-combat systems that hang off it.

### What stays intact

Combat rules (`CombatState`) are unchanged **except two threaded seams**, both surfaced
behavior-changes (not silent):
- `CombatState` accepts a **starting player HP** and reports **ending player HP** →
  run-persistent HP (today the slice has none; HP was full each combat).
- Victory grants **gold** (enemy-scaled).

### Refactor-to-seam first (pure structure; selftest green; zero new assertions)

- **Relics:** inline `if "ember_heart" in relics` surgery → a **`RelicDB`** with a hook
  interface (`on_run_start` / `on_combat_start` / …). `ember_heart` and `storm_core`
  behave identically through it; adding relics becomes data, not surgery. This is the
  exemplar of the skill's refactor-first rule.

### New sub-systems (each TDD'd — assertion first, then implementation)

| System | Files (new / grown) | Selftest proves |
|---|---|---|
| Run-persistent HP | `RunController`, `CombatState` seam | HP carries across two combats; campfire heal raises it, capped at max |
| **Branching map** | `MapModel.gd`, `MapGen.gd` (seeded) | Generated graph is fully traversable; every path reaches the boss; node-type counts within bounds |
| Gold economy | `RunController`, combat seam | Gold accrues from combat, debits on purchase, never goes negative |
| Events | `data/EventDB.gd` | A chosen event's outcome applies its effects (gold / hp / card add+remove / relic) |
| Shop | shop logic in `RunController` | Purchase debits gold + grants item; blocked when too poor; card-removal service works |
| Campfire | `RunController` + card upgrades | Heal-% path and upgrade-card path both fire |
| Card upgrades | `CardDB` upgrade transform | Upgraded card has an improved effect; a card upgrades at most once |
| Relic pool (~6–8) | `RelicDB` | Each relic's hook fires; treasure / elite / boss / shop grant flows work |

### Run flow / control

- `RunController` becomes a **state machine** over node types
  (combat / elite / event / campfire / shop / treasure / boss).
- `Main.gd` routes to the screen for the current node type.

### New UI screens (`deepen` wires them; `visual-audit` owns the look afterward)

- `MapView` — the branching map; highlights available next nodes; click to choose.
- `EventView` — event text + choice buttons.
- `CampfireView` — heal / upgrade choice.
- `ShopView` — inventory grid, prices, current gold, buy interaction.
- `CombatView` + reward flow — unchanged.

### Sequencing (keeps a playable game at every step)

The implementation plan will order the work so the selftest is green after each:

1. Relic `RelicDB` refactor (pure; zero new assertions).
2. Run-persistent HP (combat HP-thread seam + first new assertion).
3. Branching map: `MapModel` + `MapGen`, navigable with **combat nodes only**
   (game playable on a real map immediately).
4. Gold economy (combat grant seam).
5. Shop node + `ShopView`.
6. Events + `EventDB` + `EventView`.
7. Campfire + card upgrades + `CampfireView`.
8. Relic pool expansion + treasure node.
9. Screen polish hand-off note to `visual-audit` (out of this plan's scope).

### Validation & gates

- `selftest.gd` is the hard gate after **every** task: existing assertions = regression
  guard, plus the new per-system assertion(s). `SELFTEST OK` or the task isn't done.
- Validator Methods 1 / 1.5 / 1.6 re-run on the grown game.
- Owner playtests the deeper run loop (status stays `playable`).
- Record `manifest.depth_pass`.

### Out of scope (future passes — the skill repeats)

- Multiple acts / floors, multiple bosses, ascension tiers beyond the current write.
- Audio for the new screens (the later `audio` pass owns it).
- The genre-neutrality application test of the asset/visual-audit skills (separate,
  deferred thread).
- Art for the new screens beyond reusing existing chrome (`asset`/`visual-audit` own it
  later).

---

## Risks / watch-items

- **Combat HP-thread is a real behavior change** to an otherwise-frozen `CombatState`.
  Surface it explicitly; keep every existing combat assertion green.
- **Map-gen determinism:** seeded Fisher–Yates / `rng.randi_range` only (no
  `Array.shuffle()` global RNG) — the project's standing determinism rule.
- **Headless autoload gotcha:** data layers reached via `preload` + `static func`, never
  autoload globals (`godot --script` does not instantiate autoloads). Applies to the new
  `RelicDB` / `EventDB` / `MapGen`.
- **Scope is large for one pass.** Strict one-system-at-a-time sequencing with the
  selftest gate is the control; if the pass runs long, it can be split at any green
  checkpoint.
