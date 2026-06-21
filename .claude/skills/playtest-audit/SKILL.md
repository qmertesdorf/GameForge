---
name: playtest-audit
description: Use to empirically verify a playable Godot game is actually WINNABLE, FAIR, and PROGRESSABLE — by driving the REAL game loop with a headless competent-player bot that asserts playability invariants (can earn/progress/clear, the first goal is reachable, no death-spiral) and reports balance metrics. The gate the logic/UI self-tests structurally cannot be.
---

# playtest-audit

Prove the game can actually be *played to a good outcome*, not just that its rules are
correct. Emit `games/<id>/playtest.gd`: a headless bot that drives the **real** game loop
with a competent policy and asserts the title is winnable, fair, and lets a player make
progress. Prints per-step metrics then exactly `PLAYTEST OK` (exit 0) or
`PLAYTEST FAIL: <reason>` (exit 1).

## Why this exists (the gap it closes)

Every other gate is blind to balance:
- `selftest` proves **rules** by driving the engine *directly* — and that is exactly its
  blind spot. diver-0001's selftest "proved" a cautious dive banks by calling `collect()`
  at depth 0, asserting the *economy in the abstract*. It never simulated the **spatial
  reality**: treasure spawned 270m below the diver, past a crush line at 200m, so a real
  player **physically could not reach a treasure and return alive** — the game was 100%
  unwinnable and every logic/UI gate was green. The owner found it in ten seconds of play.
- `uitest` proves a tap reaches a handler. `visual-audit` proves the screen reads.
- the `deepen` design-depth audit *reads the code* and reasons on paper — it judged diver
  "deeper, not bigger" while the same build was unwinnable, because it never *played* it.

Winnability/fairness/economy-solvency are **emergent** properties of the assembled loop
(spawn geometry × collision × resource drain × difficulty ramp). The only way to see them
is to **play the real loop**. That is this skill.

## Loop position

A validation gate, like `selftest`/`uitest` — run it after `builder` and after every
`deepen` pass (tuning is exactly what deepen changes). `builder`/`deepen` emit
`playtest.gd`; the `validator` runs it and fails the build on `PLAYTEST FAIL`. It records
nothing to the manifest — its outputs are the pass/fail gate + a balance-metrics report
(and any code/tuning fixes that follow).

## The harness — drive the REAL loop, deterministically

A `SceneTree` script that instantiates the actual scene and steps it by hand so the bot
sees real spawns, real collision, real resource math:

```gdscript
extends SceneTree
var main
func _initialize() -> void: _run()
func _run() -> void:
    var scene: PackedScene = load("res://Main.tscn")
    main = scene.instantiate()
    root.add_child(main)
    await process_frame          # let _ready() run
    main.set_process(false)      # WE drive _process at a fixed dt — deterministic, no engine variance
    var DT := 1.0 / 60.0
    while main.<active> and guard < CAP:
        <set the bot's intent on the real input surface, e.g. main.target_x = ...>
        main._process(DT)        # the real spawn/move/collide/tick, stepped by us
    # read real state off main.<state> and assert invariants
```

- **Step the real `_process` yourself** with a fixed `dt` after `set_process(false)` — never
  rely on engine frame timing (variable `dt`, non-determinism). Seed every RNG; with a fixed
  seed + fixed `dt` the whole playthrough is reproducible.
- **The bot acts through the real input surface** the game already exposes (the steer target,
  the action methods) — not by reaching past the rules. If you must poke private state to set
  up a scenario, do it sparingly and say so.
- Reuse the genre's existing **headless boot** assumptions (no autoloads under `--script`,
  `preload` data layers — same gotchas as `selftest`/`uitest`).

## The bot — COMPETENT, not optimal

Model a *reasonable* player, not a theoretical-best solver and not a random flailer:
- A simple greedy-but-cautious policy (head for the nearest reward; retreat when the
  resource budget only just covers a safe exit, with a margin).
- If a **competent, cautious** player cannot earn / progress / survive, the tuning is
  broken — that is the finding. (diver's bot turned back at a safe margin and still banked
  0, because nothing was reachable.)
- Keep the bot's competence **honest**: a deliberately weak bot false-fails good games; an
  optimal one hides difficulty. When the bot is weaker than a human at a sub-skill (precise
  dodging/aiming), **REPORT** what it couldn't do rather than `FAIL` on it — flag it for the
  human playtest instead of gating on it (diver: the crude lerp-steering bot couldn't grab
  the sparse Trench treasures, so deep-commission fill is reported, not failed).

## Invariants to assert (instantiate per genre)

Gate on the ones that mean "a player can succeed":
- **Solvency / winnable.** A competent run reaches a *good* outcome at least sometimes:
  earns positive currency, clears the encounter, survives a wave, scores above zero. The
  anti-unwinnable gate. (diver: a careful rig-0 dive banks > 0.)
- **First goal reachable.** The first objective/commission/boss/quota is achievable from the
  starting loadout — not gated behind a resource you can only get *by* doing it (a deadlock).
- **Fairness / no death-spiral.** The player never dies on a turn where they played safely
  (no unavoidable hit, no spawn you cannot react to); a setback is recoverable, not terminal.
- **Progression solvency.** Across several sessions (buying upgrades / advancing), resources
  **accumulate** and the next tier is affordable — measured as **gross** earnings, not net
  balance (a bot that *spends* on upgrades has a low balance while clearly progressing).
- **No trivial dominant win.** A single repeated cheap action does not run the score to
  infinity (the inverse failure — the loop is solved). Pairs with `deepen`'s dominant-strategy test.

## Metrics to report (every run, pass or fail)

Print enough to *tune* from, not just a verdict: earnings/clear per session, the **minimum
resource margin** seen (how close to death a careful player runs), depth/wave/turn reached,
time-to-first-upgrade, commission/objective fill rate. These numbers are how the owner sets
difficulty — surface them even when the run passes.

## Honest reporting

Gate on the winnability invariants; **report** (don't `FAIL`) anything that's a bot-skill
limitation rather than a game flaw, and say which is which. A `PLAYTEST OK` must mean "a
competent player can succeed," and the metrics must name any difficulty the bot only barely
cleared — never let a silent cap read as "fully balanced."

## Gotchas (carry these)

- A logic self-test that drives the engine **directly** cannot see spatial/economic
  winnability — that is precisely why this gate exists. Do not "fix" a `PLAYTEST FAIL` by
  weakening `selftest`; fix the **tuning** (spawn geometry, gate depths, costs, the ramp).
- Stepping `_process` manually while the engine *also* auto-runs it double-ticks the world —
  `set_process(false)` first.
- Manual stepping means `_draw` never runs, so RNG used only in `_draw` (shake/parallax)
  won't desync the spawn RNG — keep spawn RNG in `_process` for a reproducible run.
- Clear any `user://` save at start AND end (a persisted economy leaks across runs and makes
  "can a *fresh* player win?" non-deterministic).

## Dogfood lesson (diver-0001)

The bug that motivated this skill: crush line (200m) shallower than both the commission zone
(Reef@240m) and the nearest treasure spawn (332m), so banking anything was impossible while
every logic/UI/design gate stayed green. The bot caught it on the first run (earned 0 across
8 dives). The fix was pure tuning — collectible treasure pre-seeded into safe water, the
rig-0 safe depth raised to cover the Shallows + first commission, deeper zones pulled up —
verified by re-running until `PLAYTEST OK` (dive 1 banks 168 incl. a filled commission).
