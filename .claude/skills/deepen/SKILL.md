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

## When `deepen` is REQUIRED (the `*` is not zero)

The loop writes `( deepen → validator → playtest )*`, and the POC read the `*` as
"optional" — so it ran **once across eleven titles** (only `deckbuilder-0001` has a
`depth_pass`). That is the single biggest reason the catalogue plays "weak": every other
game shipped at *first-playable depth* — a thin prototype with a solved loop and a content
ceiling a minute in. **A `playable` game is not a finished game; it is a prototype that
proved its loop runs.** At least **one** depth pass is REQUIRED before a title is a
candidate for `asset`/polish — the `asset` skill now gates on the presence of a
`depth_pass` and bounces a never-deepened game back here. Spend iterations *deepening one
good loop*, not restarting near-duplicates (the match3-survival 0001→0002→0003 churn re-
attempted a flawed concept three times instead of deepening one). Run `deepen` until the
**content-ceiling** and **dominant-strategy** tests below both pass at least once.

## Inputs
- A game at status ≥ `validated` with a working `games/<id>/selftest.gd`.
- A chosen depth axis + scope (spec-given, or assessed per the method below).

## Outputs
- Extended game code; a grown `selftest.gd`; a `manifest.depth_pass` record.
- Durable lessons folded back into this skill.

## The method

1. **Assess depth — diagnose *where* it's shallow before choosing what to add.** Run
   these two tests on the current game; they pinpoint the leak nearly every weak GameForge
   title shares:
   - **Content-ceiling test:** play (or read the loop) and ask *"on what beat does the game
     stop introducing anything new?"* — the last new mechanic, enemy, recipe, or rule the
     player meets. Both shipped POC games hit their ceiling early (shopkeep introduces nothing
     after day 4; match3-survival's only escalation is a shrinking timer on one static threat).
     Everything past the ceiling is the same system replayed — that's the "weak" the player
     feels. Your job is to push the ceiling out: stage in newness over the session.
   - **Progression-payoff test (reject DEPTH-AS-MULTIPLIER).** "Newness" must be new
     *gameplay*, not a bigger number on the same decision. For every progression vector the
     game offers — going deeper, levelling, scoring, a higher tier/day/wave — name **what the
     player DOES at tier N that they could not do at tier 1.** If the only answer is "the same
     action, for more points/value," the ceiling has **not** moved — that progression is a
     score multiplier wearing a costume, and it is the single most common reason a game with
     "progression" still feels shallow (diver-0001 shipped exactly this: depth only scaled
     treasure *value*, so there was no gameplay reason to descend — owner-rejected on
     playtest). A progression vector earns its keep only when reaching it **unlocks a new
     decision, a new interaction, or gated content that plays differently** — a destination,
     not a dial.
   - **Dominant-strategy test:** name the single move a skilled player repeats every beat. If
     it's strictly best (most reward *and* safest), the loop is **solved** and no amount of
     content fixes it — you must add a **cost / tradeoff** that makes the dominant move
     situational (this is the systemic axis, and the inverse of `concept`'s tradeoff gate:
     when `concept` let a solved loop through, `deepen` is where it gets repaired). match3
     -survival shipped solved (purge = both the safe move and the high-score move); fixing that
     is higher-leverage than any new content on top.
   - **Core-before-meta gate (don't bolt a wrapper onto a shallow core).** A run-meta or
     content layer *multiplies whatever the core loop already is*. If the core loop is the thin
     part — fails the dominant-strategy test, or offers one real decision — adding upgrades / a
     map / an economy on top just yields a **longer shallow game**, and the meta layer reads as
     busywork because the thing it wraps isn't worth repeating. Before choosing `run-meta` or
     `content`, confirm the **core loop itself** clears the dominant-strategy + progression-payoff
     bars. If it doesn't, the axis is **systemic** (fix the loop first) no matter how tempting the
     shiny meta layer is. (diver-0001's first deepen got this wrong: it added a run-meta upgrade
     economy over a one-decision core, so the upgrades had nothing meaningful to deepen.)
   - **Upgrade / reward-coherence test (for every unlock, upgrade, or reward you add).** Two
     questions per item: (1) *"what does the player DO differently after getting this?"* — if the
     answer is only "the same thing, slightly better," it's a dead stat, not a decision; prefer
     upgrades that **open new play or change a choice** (gate access to new content, enable a new
     tactic, flip a risk calculus) over flat ±X nudges. (2) *"can the player FEEL it on the very
     next run/dive?"* — a buff that needs 3–4 stacked levels before it's perceptible is invisible
     and reads as pointless (diver-0001: +16 air/level barely changed reachable depth, so the shop
     felt meaningless). Tune so one purchase visibly changes what the player can do.
   Then pick **ONE axis** — the one that addresses the leak the tests found — and the single
   highest-leverage expansion on it. Don't widen three axes at once. Per-axis playbook:
   - **systemic** (fixes a *solved/shallow* loop): add an *interacting* mechanic that creates a
     new decision — a cost on the dominant move, a second resource that contends with the first,
     a threat/opportunity that rewards a *different* response than the default. The test: after
     it lands, the dominant-strategy test must no longer have a single answer.
   - **content** (fixes a *low* ceiling on a loop that's *already* a real decision): more of the
     same *kind* — new recipes/enemies/cards/tiles — **staged in over the session**, not all at
     start, so the ceiling moves. Only reach for this once the dominant-strategy test passes;
     piling content onto a solved loop just makes a longer solved loop.
   - **run-meta** (fixes *"no reason to start run 2"*): a wrapper that makes sessions differ and
     accrue — a map/event/economy/unlock track, escalating modifiers, a persisted best or
     prestige. Gives the loop somewhere to *go* across plays.
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
     every change — and `UITEST OK` too if a `uitest.gd` exists: deepening adds
     screens and controls, and a new view that renders fine can still swallow taps
     or skip its rebuild event (invisible to selftest, which bypasses the view).
     New tappable screens get new `uitest.gd` checks, same RED→GREEN discipline.
   - **`PLAYTEST OK` too if a `games/<id>/playtest.gd` exists — deepening changes TUNING,
     which is exactly what breaks winnability.** A depth pass that retunes costs, gate
     depths, spawn geometry, or the ramp can make the game unwinnable while every logic
     assertion stays green (the `playtest-audit` skill exists because of exactly this).
     Re-run the balance bot after the pass; a `PLAYTEST FAIL` on re-validation is attributed
     to **this `deepen` pass**, and the fix is tuning, never weakening `selftest`.
   - **Keep the generate-and-verify gate green if the game has one (`make_verified` +
     `Solver`, per `builder`).** Adding content on the **content axis** is the classic way to
     silently introduce unsolvable instances: every new tile / recipe / wave type / map piece
     *widens the instance space the generator can deal*, and the solver guarantee only held
     over the *old* space. Re-run the generate-and-verify selftest assertions (every
     `make_verified` solvable over K seeds; fallback rate still rare; fallback still solvable)
     after the pass — a regression here is attributed to **this `deepen` pass**, and the fix is
     the generator / new content, **never weakening `Solver.is_solvable`**. If the depth pass
     adds discrete generated content to a game that *didn't* have the gate (e.g. the content
     axis turns a fixed layout into a procedural one), that is exactly when to **introduce**
     `make_verified` — treat it as a new sub-system with its own RED→GREEN assertions.
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
   content* — not pixels, not the gate mechanics. **New screens aren't self-test-gated**
   (the headless self-test never instantiates the scene tree), so gate them two other
   ways: a **headless boot check** (`godot --headless --path … --quit-after N`) that
   proves the router/view code parses and runs with no `SCRIPT ERROR`, plus a
   **throwaway real-renderer harness** (a `SceneTree` script that builds the relevant
   state, instantiates the view, waits ~200 frames, saves a PNG) for a visual sanity
   glance. Delete the throwaway; keep the PNG as a probe-data artifact.
6. **Verify the depth landed — INDEPENDENT design-depth audit (REQUIRED).** The agent that
   did the deepening cannot grade its own depth: it knows what it *intended* to add and reads
   the diff as proof, so it ships "bigger" believing it shipped "deeper" (diver-0001's first
   deepen passed its own assessment and was still owner-rejected as shallow). Fix it the way
   `visual-audit` fixes the screen — with **fresh, adversarial eyes**, but pointed at the
   *systems* instead of the pixels. **Dispatch a fresh subagent** (no knowledge of what you
   set out to add — give it only the running game + the concept) to play/read it and answer,
   bluntly:
   - **Is each progression vector a destination or a dial?** For going deeper / levelling /
     scoring: *what does the player DO at the top that they couldn't at the bottom?* "Same
     action, more points" = FAIL (depth-as-multiplier).
   - **Do the new systems change decisions?** Name a concrete moment the new mechanic/upgrade
     made the player choose differently. If none, it's inert.
   - **Is it more fun, or just more?** One sentence: did this make the game deeper, or longer?
   Treat a "just bigger / just longer" verdict as a **failed pass** — iterate (often the real
   fix is a different axis: the auditor saying "the upgrades are meaningless because the core
   loop is one decision" means you picked run-meta when the answer was systemic). Record the
   auditor's verdict in `depth_pass.notes`. Scale the audit to the change: one skeptic for a
   small content add, a fuller play-and-critique for a systemic/run-meta pass.
7. **Record + codify.** Write `manifest.depth_pass` (axis, systems added, new-assertion
   count, **and the independent audit's verdict**). Fold durable lessons back into this skill.

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
- A growing `selftest.gd` runs all stages in **one function scope** → give each stage's
  locals **unique names** (e.g. suffix with the stage number) or you get redeclaration
  parse errors as you append.
- Avoid GDScript method names that collide with `Object` built-ins (`connect`, `draw`,
  `set`, …) on your data/model classes — they parse-error or shadow silently.
- A new `manifest.depth_pass` field is **not free**: the manifest schema is
  `additionalProperties: false`, so add the field to `schema/manifest.schema.json` and
  re-run `node tools/manifest.mjs validate <id>` + the vitest suite before committing.

## Lessons from first use (run-layer dogfood)
- **The "surface, don't swallow" rule earns its keep.** Two changes touched
  previously-frozen combat logic — threading run-persistent HP through `setup()`, and
  giving a relic that had silently been a no-op a real effect. Both were named in
  `depth_pass.notes` rather than slipped in. When deepening forces a change to old
  behavior, that is normal — make it loud.
- **Prove the system headless first, wire the screen second.** Every sub-system landed
  its self-test assertion *before* any view existed, so the regression gate never
  depended on rendering. This ordering is what let view work stay a separate, lower-risk
  concern handed to `visual-audit`.
- **Check the acquisition path, not just the hook.** A hook that only fires at one
  moment (e.g. run-start) is dormant for anything acquired *after* that moment. When you
  add hook points, confirm the real in-game path that grants the thing actually triggers
  the hook — or record the limitation explicitly instead of shipping a dead feature.
