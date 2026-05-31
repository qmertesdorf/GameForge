# POC Run 002 — match-3 (match3-0001, "Prism Cascade")

**Prompt/genre:** match-3 puzzle (second genre; built with the upgraded skills from run 001).
**Final status:** playable
**Engine:** Godot 4.6.3.stable (headless clean at 120 / 600 / 3000 frames, exit 0, no script errors)

## Success criteria (§2)
1. Produced a working project: **yes** — `games/match3-0001/` (783-line `Main.gd`, `_draw()` architecture).
2. Opened & ran without manual code fixes: **yes** — no hand-fixes after generation; the builder self-resolved its own build errors (see Finding 1).
3. Playable ~60s, core loop functions: **yes** — owner playtest: "all functionality is correct… feels like a genuine match-3 game."
4. Manifest correct: **yes** — `validate` OK at every transition; concept → generated → validated → playable.
5. Failure legible & attributable to a skill: **yes** — see findings.

## Owner verdict
> "Looks good, all functionality is correct. The timer is insanely fast but not sure that's really skill feedback for this iteration. It feels like a genuine match-3 game."

A genuinely different genre (grid logic, match detection, cascades, drag-to-swap) produced correct, good-feeling output from the **same** skills — strong evidence the run-001 skill upgrades generalize beyond the runner.

## Findings (carry-forward — skill edits DEFERRED until the genre sample is larger, per owner)

### Finding 1 — `builder`, HIGH value: Godot 4.6 strict-typing trips `:=` on untyped containers
- **What happened:** The match-3 *algorithm* was correct on the first try. Every build error was GDScript strict typing: indexing untyped `Array`/`Dictionary` returns `Variant`, and Godot 4.6 treats inferred-Variant as an error; `clamp`/`lerp` also return `Variant` even with float args. Six `:=` inferences had to become explicit `: float` / `: Color`, and one dead conditional was removed. The builder fixed these itself, but it cost an iteration loop.
- **Proposed builder SKILL.md edit (next pass):** Add a "Godot 4.6 typing" rule: when indexing untyped Arrays/Dictionaries or assigning the result of `clamp`/`lerp`/`min`/`max`, annotate the receiving variable's type explicitly — do NOT rely on `:=` inference. (Optionally: prefer typed containers, e.g. `var board: Array[Array]`.)

### Finding 2 — `validator`, reinforced: "runs clean" ≠ "plays correctly"
- **What happened:** Headless validation confirms no script errors, but match-3 *logic* bugs (mis-detected matches, broken gravity, stuck cascades) would not throw — they'd pass the programmatic gate and only fail a human playtest. This genre makes the gap obvious in a way the runner did not.
- **Proposed validator SKILL.md direction (next pass):** Prioritize the already-documented automation plug-in point — a `selftest.gd` that simulates input and asserts observable state changes (e.g. a known swap clears the expected cells; the board has no floating gaps after a resolve). Logic-heavy genres need it most.

### Finding 3 — `builder`, LOW confidence / possibly one-off: timer too aggressive
- **What happened:** The timer drains far too fast. The builder's "gentle start" tuning guidance produced defaults that aren't gentle enough for this genre.
- **Disposition:** Owner flagged this as not the signal for this iteration. Log only; revisit difficulty-tuning guidance after a larger sample shows whether mis-tuning is systematic or per-genre noise.

## Sample status toward §2 (≥3 genres reaching `playable`)
- ✅ endless runner — `runner-0002` (Neon Dash II), playable.
- ✅ match-3 — `match3-0001` (Prism Cascade), playable.
- ⏳ next: top-down twin-stick shooter (`shooter-0001`).

## Meta-observation
Two distinct genres now reach `playable` from one skill set with no hand-tuning — the POC's central claim is holding across genres, not just within one. The most valuable signal so far is **Finding 1** (a concrete, reusable builder rule) — exactly the kind of legible, skill-attributable output the POC exists to produce.
