# POC Run 003 — top-down shooter (shooter-0001, "Vector Storm")

**Prompt/genre:** top-down shooter, one-thumb (drag-to-move + auto-fire). Third distinct genre; current skills.
**Final status:** playable
**Engine:** Godot 4.6.3.stable (headless clean at 120 / 600 / 3000 frames, exit 0, no script errors)

## Success criteria (§2)
1. Working project: **yes** — `games/shooter-0001/` (~470-line `Main.gd`, `_draw()` architecture, array-of-dict entities).
2. Ran without manual code fixes: **yes** — and with **zero build iterations** (see Finding B).
3. Playable ~60s, core loop functions: **yes** — owner: "it does play correctly."
4. Manifest correct: **yes** — `validate` OK at every transition.
5. Failure legible & attributable to a skill: **yes** — see findings.

## Owner verdict
> "It's pretty brainless because it shoots for you, but it does play correctly."

## ★ POC milestone: §2 ≥3-distinct-genre bar MET
Three genuinely different genres now reach `playable` from one **unchanged** skill set:
- endless runner — `runner-0002` (Neon Dash II)
- match-3 — `match3-0001` (Prism Cascade)
- top-down shooter — `shooter-0001` (Vector Storm)

The skills (`concept`/`builder`/`validator`) contain no genre-specific code — genre lives entirely in the manifest's `concept` block, which the genre-agnostic skill prose consumes. This is the POC's central claim, demonstrated.

## Findings

### Finding A — `concept`, design/agency: auto-fire made it "brainless"
- **What was wrong:** To keep input one-thumb, the concept specified auto-aim + auto-fire, leaving the player only movement. Removing the aim/shoot decision removed the skill expression — it plays correctly but feels passive.
- **Root cause:** The concept optimized for input simplicity without protecting **player agency** — a known mobile tension (accessible vs. engaging).
- **Proposed concept SKILL.md edit (next pass):** When simplifying controls for mobile, preserve at least one meaningful moment-to-moment decision. For an auto-fire shooter, give the player an active choice (manual fire/aim, a dodge/dash on a second tap, a targetable special, or limited ammo forcing aim). State the intended "what is the player deciding each second?" in `core_loop`.

### Finding B — `builder`, POSITIVE / findings compound: typing rule prevented all build errors
- **What happened:** Run 002 surfaced the Godot-4.6 strict-typing rule (annotate types off untyped Array/Dict; `clamp`/`lerp` return Variant). Carried into this build, it produced **zero build iterations** on a logic-heavier game (vector aim, multi-array collisions, waves). One adjacent nuance also appeared: `Array.filter()/.map()` return untyped `Array`, so assigning to a typed `Array[T]` needs care.
- **Conclusion:** Findings compound across runs — exactly the intended loop. Strengthens the case to bake the typing rule into `builder` SKILL.md in the next pass.

## Capability note — genre combinations (untested)
We've proven *distinct* genres. The owner's stated goal is "any number of games of any number of genres (or combination of genres)." Combinations (e.g. runner+shooter, match-3+RPG) are architecturally the same path — just another `concept` the same skills consume — but have **not yet been demonstrated**. That is the natural next probe.

## Meta-observation
The POC has now shown both halves of its thesis: (1) one skill set generalizes across distinct genres, and (2) skill-prose findings from each run measurably improve the next (Finding B). Remaining high-value probes: a genre **combination**, and then a consolidated **skill-iteration pass** applying the deferred findings (run-001 already applied; run-002/003 findings pending).
