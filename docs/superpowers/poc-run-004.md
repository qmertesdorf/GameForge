# POC Run 004 — genre COMBINATION demo: match-3 + survival (match3-survival-0001, "Aegis Grid")

**Prompt/genre:** a match-3 puzzle where every match fuels your defenses against an advancing threat — survive by matching to attack/repair while a real-time threat presses in. **First hybrid / combination concept** (all prior runs were single genres). Built with the current, **unchanged** skill set.
**Final status:** playable
**Engine:** Godot 4.6.3.stable (headless clean at 120 / 600 / 3000 frames, exit 0, no script errors — verified independently of the builder subagent)

## Why this run existed
The owner's stated goal is "any number of games of any number of genres **(or combination of genres)**." Runs 001–003 proved the skills generalize across *distinct* genres (runner, match-3, shooter), all `playable` from one unchanged skill set. The combination half was the one untested claim. This run probes it with a deliberately **orthogonal** blend — puzzle (slow, deliberate) fused with survival (real-time pressure) — chosen over the lower-risk runner+shooter precisely because orthogonal subsystems are the harder, more informative test.

## Success criteria (§2)
1. Produced a working project: **yes** — `games/match3-survival-0001/` (~32 KB `Main.gd`, `_draw()` physics-free architecture, adapted from `match3-0001`).
2. Opened & ran without manual code fixes: **yes** — and again with **zero build iterations** (see Finding B).
3. Playable ~60s, core loop functions: **yes** — owner played it; match-3 loop, advancing threat, wall HP / game-over / restart all function.
4. Manifest correct: **yes** — `validate` OK at every transition; status walked concept → generated → validated → playable.
5. Failure legible & attributable to a skill: **yes** — and this run produced the POC's sharpest skill finding yet (see Finding A).

## Owner verdict
> "It works. I wouldn't say this super qualifies as survival — it's basically just match-3 and something else randomly is happening on the screen at the same time, but I suppose you could consider it 'surviving'."

This is a "plays correctly, but the concept didn't land" verdict — directly analogous to run-003's shooter ("brainless but plays correctly" → still `playable`). The match-3 loop is genuinely functional; the *blend* is what's weak.

## ★ What the combination demo actually showed (the headline result)
The result splits cleanly into a **yes** and a **no**, and the split is the finding:

- **YES — the pipeline is genre-architecture-agnostic.** The unchanged `concept`/`builder`/`validator` skills consumed a *blended* concept exactly as they consume a single-genre one. A hybrid really is "just another `concept` block the same skills read" — mechanically confirmed. The build needed **zero** hand-fixes and zero build iterations on the most logic-dense game in the POC so far (a full match-3 grid PLUS a concurrent real-time survival subsystem).
- **NO — the skills do not ensure the genres INTERLOCK.** They produced two subsystems that *coexist on one screen* rather than *fuse into one loop*. The survival threat reads as ambient ("something else randomly happening") instead of as pressure that reshapes how you match. The intended moment-to-moment decision (match red for offense vs. blue for defense, under a closing threat) exists in the code but isn't *felt*, because nothing forces the player off the path of just matching whatever's convenient.

So the combination claim is **half-proven**: the loop *runs* across blended genres, but "playable" ≠ "the blend coheres." That gap is the product of this run.

## Findings

### Finding A — `concept` (primary) + `builder` (secondary), HIGH value: the skills produce *coexisting* subsystems, not an *interlocked* blend
- **What was wrong:** Both genres are present and causally wired (red matches damage the line, blue matches repair the wall, combos charge a nova), but the survival layer doesn't compel attention. Optimal play is "just match anything," and the threat becomes background animation. The blend is additive (A + B on screen) rather than multiplicative (B changes how you play A).
- **Root cause — `concept`:** The concept block named the two subsystems and the causal link between them, but specified **no forcing function** — no mechanic that makes the secondary genre *continuously reshape the primary genre's decisions*. The `concept` skill has no rule for hybrids; it captured "what are the two genres" but not "what makes the player unable to ignore subsystem B while doing A."
- **Root cause — `builder`:** No dual-loop guidance. The builder implemented both subsystems competently but with weak coupling and under-salient feedback, so the player doesn't perceive the match→threat causal loop tightly enough to plan around it. (The builder subagent independently flagged this — see its note below.)
- **Proposed `concept` SKILL.md edit (DEFERRED):** Add a **"Hybrid / combination concepts"** rule: when blending genres, the concept MUST name the *forcing function* — the mechanic that makes the secondary genre's pressure continuously reshape the primary genre's moment-to-moment choices (not merely coexist). Require an explicit answer to "what makes the player unable to ignore subsystem B while doing A?" e.g. the threat escalates fast enough, or punishes neglect hard enough, that match-priority MUST shift toward defense at predictable moments. Make the blend, not either genre, the thing `core_loop` describes.
- **Proposed `builder` SKILL.md edit (DEFERRED):** Add a **"Dual-loop / shared-resource concepts"** subsection (verbatim candidate from the builder subagent below): name the shared-resource tension explicitly; decide and state whether real-time elements pause during discrete player actions; make the causal link between subsystems **salient** via strong, legible feedback (the player must SEE match→effect); and define fairness across both axes — "the dominant strategy must neither trivially win nor be unwinnable."

> Builder subagent's own words (it was not told the playtest verdict — independent corroboration): "The unchanged builder SKILL.md is written almost entirely around a *single-actor* loop … For a hybrid it gave no guidance on (a) two interacting subsystems sharing one input channel — the core tension is resource contention, which the skill never names, (b) a real-time subsystem running concurrently with a turn-ish/resolve subsystem … a design call the skill is silent on, and (c) fairness across two axes … A short 'Hybrid / dual-loop concepts' subsection … would make this reproducible rather than improvised."

### Finding B — `builder`, POSITIVE / findings keep compounding: the typing rule held a THIRD time
- **What happened:** The Godot-4.6 strict-typing rule (surfaced run-002, confirmed run-003) was passed forward again. On the most logic-dense build yet (match grid + cascade + concurrent real-time survival), it produced **zero build iterations** — the builder proactively annotated every `clamp`/`lerp`/`min`/`max` result and every untyped Array/Dictionary index. 100% coverage; nothing slipped through.
- **Conclusion:** Three consecutive runs now confirm this rule eliminates GDScript build-error loops. The case to bake it into `builder` SKILL.md is now overwhelming — it is the single highest-confidence deferred edit.

## Deferred skill-edit backlog (unchanged policy: batch the edits, then re-validate)
Carried from prior runs, plus this run's additions:
1. **`builder` — Godot-4.6 strict-typing rule** (run-002/003/004; HIGHEST confidence). Bake it in.
2. **`concept` — preserve ≥1 moment-to-moment decision / player agency** (run-003).
3. **`validator` — build the `selftest.gd` automation hook for logic-heavy genres** (run-002/003).
4. **NEW — `concept` — "Hybrid / combination concepts" forcing-function rule** (this run, Finding A).
5. **NEW — `builder` — "Dual-loop / shared-resource concepts" subsection** (this run, Finding A).

Note that #2 (agency) and #4 (forcing function) are the same theme seen from two angles: a game is "brainless" when the player has no decision (shooter), and a blend is "two things at once" when the second genre doesn't *force* a decision in the first. A consolidated `concept` edit could address both: **every concept must state what the player is deciding each second, and a hybrid must state what makes the second genre's pressure drive that decision.**

## Where this leaves the POC
- **§2 ≥3-distinct-genre bar:** already MET (runs 001–003).
- **Combination claim:** mechanically demonstrated (pipeline is blend-agnostic, 0 build iterations); **qualitatively incomplete** (the skills don't yet make blends cohere). This is a legible, attributable skill gap, not a pipeline failure — i.e. the intended POC outcome.
- **Strongest signal to date that it's time for the consolidated skill-iteration pass:** the deferred backlog now has 5 items, two of them (typing rule, forcing-function/agency) are high-confidence and mutually reinforcing across runs. The natural next move is option (b) from the owner's menu — apply the backlog to the SKILL.md files and re-validate (ideally re-gen *this* hybrid through the upgraded skills as the A/B test, the way runner-0002 validated the run-001 edits).

## Next
- [x] Mark match3-survival-0001 `playable`.
- [ ] (recommended) Consolidated skill-iteration pass: apply the 5 deferred edits, then re-gen Aegis Grid II through the upgraded skills and A/B whether the blend now coheres.
- [ ] (optional) A second hybrid through the *current* skills for one more combination data point before editing.
