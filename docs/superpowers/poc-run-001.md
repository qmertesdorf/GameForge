# POC Run 001 — endless runner (runner-0001)

**Prompt:** an endless runner where you tap to jump over neon obstacles.
**Final status:** playable
**Engine:** Godot 4.6.3.stable (headless run clean, exit 0, no script errors)

## Success criteria (§2)
1. Produced a working project: **yes** — `games/runner-0001/` (project.godot, Main.tscn, Main.gd).
2. Opened & ran without manual code fixes: **yes** — builder's `_draw()`-based, physics-free architecture + guarded `ThemeDB.fallback_font` ran clean headless on the first attempt, zero GDScript iterations.
3. Playable ~60s, core loop functions: **yes** — owner playtest confirmed jump, scrolling obstacles + speed ramp, climbing score, collision→game-over, tap-to-restart all work.
4. Manifest correct: **yes** — `validate runner-0001` → OK at every transition; status walked concept → generated → validated → playable.
5. Failure legible & attributable to a skill: **yes** — see below.

## Owner verdict
> "It's terrible but playable… just a super simple game with bad assets, good for a POC but definitely nowhere near shippable."

This is the intended POC outcome: the **pipeline works end-to-end**. The gap is **quality**, and it is cleanly attributable to skill instructions, not pipeline bugs. All four quality dimensions were flagged weak: game feel/juice, visuals/polish, difficulty/balance, and depth (too sparse).

## Where the loop broke (criterion #5 — the point of the POC)

The pipeline did not "break" — every stage succeeded. What broke is **output quality**, and the responsible skill is overwhelmingly **`builder`** (with a secondary `concept` gap). The builder skill optimizes only for "runs without errors" and "minimal-but-functional," so it produces the floor of playability and nothing above it.

### Finding 1 — Game feel / juice — responsible skill: `builder`
- **What was wrong:** Jump and collisions have no feedback — no squash/stretch, no landing impact, no particles on score, no screen shake on death. Movement reads as flat and lifeless.
- **Root cause:** builder's only feedback guidance is "a flash/particle on score or collision" buried in one sentence; it's optional and vague, so it gets skipped.
- **Proposed SKILL.md edit:** Add a required **"Game feel & juice"** section listing concrete, cheap-to-implement feedback the builder must wire (impact flash, screen shake on death, particle/scale-pop on score, responsive jump with a short coyote-time window).

### Finding 2 — Visuals / polish — responsible skill: `builder` (secondary: `concept`)
- **What was wrong:** "neon" was asserted in colors but not executed — no actual glow, no background/parallax, flat dead space, score text hard to see.
- **Root cause:** builder treats primitives as "draw a colored rect" rather than "compose a readable, layered scene." `concept.art_direction` named a palette but not background or motion.
- **Proposed SKILL.md edit (builder):** Require a **layered scene** — background layer (parallax lines/dots/gradient), play layer, and a readable HUD (large high-contrast score, top-center). Add a concrete glow recipe for primitives (oversized translucent halo behind each shape; thick additive `Line2D`). **(concept):** require `art_direction` to specify a background treatment and at least one motion/feedback beat, not just colors.

### Finding 3 — Difficulty / balance — responsible skill: `builder` (secondary: `concept`)
- **What was wrong:** Pacing/spacing felt arbitrary — not tuned for fairness or a satisfying ramp.
- **Root cause:** builder has no tuning guidance; spawn spacing isn't derived from whether a gap is actually clearable by the jump arc.
- **Proposed SKILL.md edit (builder):** Add a **"Tuning & fairness"** rule: derive minimum obstacle spacing from the player's jump airtime so every gap is clearable; define an explicit starting difficulty and a gradual ramp (cap the max). **(concept):** `core_loop` should state the intended difficulty curve ("starts gentle, ramps every ~10s").

### Finding 4 — Too sparse / boring — responsible skill: `concept`
- **What was wrong:** Survive-and-score only; no variety, reward beats, or sense of progression.
- **Root cause:** concept under-specifies loop *depth* — it captures the second-to-second action but no progression/reward structure, so builder has nothing to build toward.
- **Proposed SKILL.md edit (concept):** Require `core_loop`/`mechanics` to include at least one **progression or reward beat** (milestone pickups, combo/streak, speed tiers with visual change) beyond bare survival.

## Next
- [x] Mark runner-0001 `playable`.
- [x] Apply first skill edits (builder: game feel, layered visuals, tuning/fairness; concept: art-direction depth + a reward beat).
- [ ] Re-run to validate the edits raise quality (optional re-gen of runner-0001, or fold into genre 2).
- [ ] Repeat the loop for genres 2 and 3 (e.g. match-3, top-down shooter) to satisfy the ≥3-genre criterion; write `poc-run-002.md`, `poc-run-003.md`.

## Meta-observation
The POC's thesis holds: with the manifest as the spine, **quality is a function of skill prose**. "Terrible but playable" is the correct floor for skills that only demand "runs + functional." Each run report's job is to convert a felt quality gap into a specific, attributable `SKILL.md` edit — which is exactly what this run produced.
