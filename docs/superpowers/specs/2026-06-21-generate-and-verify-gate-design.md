# Generate-and-verify gate — winnability by construction (P0c)

**Date:** 2026-06-21
**Status:** approved, implementing
**Source:** distilled from the 2026-06-21 overnight deep-research (Track 4 / MASTER-FINDINGS
P0c). The unifying research theme — *push correctness to deterministic verifiers; restrict
generators to proposing* — applied to winnability: make solvability a **generation-time
guarantee** so `playtest-audit` becomes confirmation, not discovery.

## Problem

GameForge games create discrete content instances at runtime (procedural maps, wave
compositions, shop economies, puzzle boards) from a seedable RNG. Today winnability is only
ever *discovered* after assembly by `playtest-audit`'s competent-player bot (`playtest.gd`),
which **samples** the assembled loop — it does not guarantee every instance the player sees is
solvable. The motivating failure: diver-0001 shipped 100% unwinnable (treasure past the crush
line) with every logic/UI/design gate green; only the bot eventually caught it.

## Solution: runtime in-game rejection sampling

The shipped game carries a generator **and** a fast in-game solver/feasibility checker. Every
discrete instance is produced through a `make_verified(seed)` path:

```
generate(rng) -> solver.is_solvable(instance) -> reject & reseed (bounded N) -> fallback template
```

Every instance the player ever sees is solver-verified. The bounded retry + known-good
fallback guarantees the loop always terminates with a winnable instance.

### Two solver tiers (the "solver / simulator" gate)

- **Exact solver** — combinatorial puzzles (nonogram / sort / block / path). Proves
  solvability outright; cheap because GameForge boards are small.
- **Simulation feasibility checker** — systemic games (survivors / economy / roguelike) where
  exact solving is intractable. A bounded competent-policy forward-sim that asserts a
  *reachable* good outcome exists. Reuses the `playtest.gd` competent-bot harness as a
  library, not a copy.

### Applicability boundary (do NOT force solvers everywhere)

The gate applies **only when solvability is a combinatorial / emergent property of a discrete
generated instance** (puzzle boards, generated maps/layouts, wave compositions, shop
economies). It does **not** apply to continuous action games where winnability is a
closed-form spacing property (e.g. a runner's obstacle spacing) — those stay covered by
builder's existing "derive limits from player capabilities" math + `playtest-audit`. The
builder skill carries an explicit decision test for this.

## Where it wires in (skill-prose + emitted-artifact work; NO manifest schema change)

### `builder/SKILL.md`
- Add the applicability decision test.
- If applicable: emit a `make_verified(seed)` generator path + a `Solver`/feasibility module
  on the seedable `RefCounted` rules engine that `selftest`/`playtest` already drive.
- `selftest.gd` gains generate-and-verify regression assertions over K seeds:
  1. every `make_verified` output passes the solver,
  2. the retry budget is rarely exhausted — fallback is the exception; flag if > X% fall back
     (generator mistuned),
  3. the fallback template is itself solvable.
- Mirror the existing guard culture: a solver-gate failure is a generator/tuning bug —
  **never weaken the solver to make it pass.**

### `deepen/SKILL.md`
- Content-axis complement: when a depth pass adds content that feeds discrete instances (new
  tiles/recipes/wave types/map pieces), it must keep `make_verified` green — re-run the
  generate-and-verify selftest, exactly as deepen already re-runs `playtest.gd` after tuning.
  Widening the instance space is the classic way to silently introduce unsolvable instances.

### `playtest-audit/SKILL.md`
- Light reframe discovery -> confirmation: when a game carries a `make_verified` gate,
  playtest-audit's winnability assertions confirm the upstream per-instance guarantee survived
  assembly (collision x resource-drain x ramp). It stays a hard gate regardless.

## Out of scope
- Manifest schema changes / a new `*_pass` block (enforced by `selftest`, which validator
  already runs).
- Build-time baked-level generation (considered, rejected: most GameForge titles are
  runtime-procedural; runtime rejection sampling covers them and finite lists alike).
- The other P0 items (P0a asset QC, P0b visual-audit) — separate specs / tasks.

## Verification — DONE (2026-06-21, Godot 4.6.3)
- Dogfood: `games/deckbuilder-0001` (a Slay-the-Spire-style run map — `MapGen.gd` had NO
  verification and `selftest.gd` checked only ONE seed). Retrofitted:
  - `MapGen.is_solvable(m)` — exact structural solver (single terminal boss + every node
    reaches the boss).
  - `MapGen.make_verified(rng)` — rejection-sample → `_fallback_map()` (known-good chain).
  - `RunController.start_run` now ships only verified maps.
  - `selftest.gd` Stage 7b: 200-seed guarantee (every `make_verified` solvable), raw
    first-try solvable rate ≥ 95%, fallback itself solvable, solver rejects a path-broken map.
- Result: `SELFTEST OK` (exit 0) and headless boot clean (exit 0, no SCRIPT ERROR) — the
  `make_verified` rewire regressed nothing. deckbuilder is cited as the skill's reference impl.
- The skill prose is the deliverable; the dogfood is the evidence it works.
