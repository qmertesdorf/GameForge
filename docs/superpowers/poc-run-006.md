# POC Run 006 — third A/B of the hybrid through the FUSION-upgraded skills (match3-survival-0003, "Aegis Grid III")

**What this run is:** the third A/B test of the POC mechanism, and the second one on the hardest axis (blend cohesion). Run-005 showed the *forcing-function* rule moved a coexisting blend toward a real one but stopped at a periodic **interrupt** — the genres alternated (puzzle → defend beat → puzzle) instead of fusing. Run-005's Finding A named the missing lever: **shared state/space + tempo alignment** (put the threat *on* the board so a single action serves both genres at once). This run applies that finding to `concept`, then re-generates the SAME match-3 + survival blend — but this time designed fusion-first — to answer: **did the state/space-fusion rule make the blend cohere?** It mirrors run-001→002 (quality) and run-004→005 (forcing-function cohesion).
**Final status:** playable
**Engine:** Godot 4.6.3.stable (headless clean at 120/600/3000; `selftest.gd` → `SELFTEST OK`, exit 0 — all verified independently of the builder subagent).

## The skill edits under test
1. `concept` — **state/space fusion rule (run-005 Finding A, HIGH).** Reordered the Hybrid section into a priority list led by "prefer state/space fusion" (both genres act on the same objects/space; the threat lives inside genre A's world so every action serves both) + a **tempo-alignment** check (reconcile mismatched genre tempos or they read as two clocks). The forcing function is demoted to an explicit *supplement, not the mechanism*. Added the honest caveat that orthogonal puzzle + real-time is intrinsically hard.
2. `builder` — **shared-space-fusion preference + telegraphed-vs-continuous distinction (run-005 Finding D, LOW).** "Prefer shared-space fusion over a periodic interrupt"; named the two distinct threat patterns (discrete telegraphed event vs. continuously-advancing threat) and said to lead with the continuous/shared-space coupling so the telegraph is a spike on top of fusion.
3. `builder` — **self-test lifecycle gotcha (run-005 Finding C, LOW).** One paragraph: in a headless `SceneTree` self-test, `_ready()` is deferred after `add_child`; drive setup explicitly before asserting.

24/24 vitest still green (frontmatter untouched).

## Owner verdict (the headline A/B result)
> **"More fused / coheres"** — it reads as one game now; matches serve both the puzzle and survival at once.

**A clean win.** Against run-005's "definitely more of a blend than before, but still kinda not cohesive," v3 crossed into "coheres as one game." So:
- ✅ **The POC mechanism holds a fourth time, and closes the gap run-005 opened.** Editing skill prose changed output in exactly the intended direction. Run-001→002 proved it for *quality*; run-004→005 for *forcing-function* cohesion; run-006 now shows the *state/space-fusion* rule pushes a blend from "interrupt" to "fused." The manifest-as-spine + prose-as-tuning-knob thesis is robust across three different kinds of edit.
- ✅ **Finding A was the right diagnosis.** Run-005 predicted that putting the threat *on the board* (so one action serves both genres) would move the needle where the forcing function alone could not. It did.

## Success criteria (§2)
1. Working project: **yes** — `games/match3-survival-0003/` (project.godot, Main.tscn, Main.gd, selftest.gd).
2. Ran without manual code fixes: **yes** — **0 game-code build iterations** (the Godot-4.6 typing rule held a 4th time; the self-test lifecycle gotcha was *pre-empted* by the new prose — the builder drove setup explicitly from the first draft, so the one fix that bit run-005 didn't recur).
3. Playable ~60s, core loop functions: **yes** — and `core_loop_functional` is backed by the automated self-test, not just the human.
4. Manifest correct: **yes** — `validate` OK at every transition.
5. Failure legible & attributable to a skill: **yes** — the residual gaps (Findings A & B below) are precise and attributable.

## What the upgraded skills produced (the A/B evidence)
The builder, following the edited prose (findings withheld out-of-band again, to test the SKILL.md itself), implemented the fusion as a **board-state threat** rather than an off-board entity:
- **Blight lives ON the grid** as a parallel `blight[r][c]` overlay riding on the gem grid; a blighted gem keeps its color but renders charcoal with a pulsing magenta rim and Line2D tendrils toward the neighbor it will infect next (legible threat on the board).
- **One action serves both genres:** `_start_clear()` purges any blighted cells caught in a match *before* clearing — the same swap that scores colors is the *only* thing that removes corruption. There is no separate defense action. This is the state/space fusion the new rule demanded.
- **Tempo reconciled to one clock:** blight advances on a single `blight_timer` at puzzle cadence (one spread + one top-row seed per tick, starting 3.5s, ramping toward a 1.6s floor), advancing during IDLE/SWAPPING/RESOLVING so the player can't pause it. Not a separate real-time clock beside the puzzle.
- **Forcing function as a spike, not the mechanism:** a telegraphed surge every ~20s (amber edge glow + shrinking countdown ring) doubles the next tick's spread — layered on top of the continuous shared-space pressure, exactly the "lead with fusion, telegraph is a spike" instruction.
- **Loss on the board:** 7 per-column wall segments at the grid bottom crack when blight breaches a column; all 7 gone → game over → tap restart.
- **A passing `selftest.gd`** asserting the fusion logic: a match purges blight, spread raises blight / purge lowers it, surge spread > normal spread, bottom-row blight cracks a segment, all-segments-gone fires `_game_over()`.

The builder's own assessment (not told the playtest verdict): the upgraded Hybrid section "named the shared resource (the swap each tick), told me to lead with continuous shared-space coupling and make the telegraph a spike on top." Independent corroboration that the edit drove the build at the builder layer — and this time the design-depth gap that remained in run-005 closed at the human layer too.

## Findings

### Finding A — `builder`, LOW: the "watch fairness over a 3000-frame run" instruction has no headless drive mechanism
- **What's underspecified:** the Hybrid section says to "watch the threat/HP values over your 3000-frame headless run" and assert fairness on both axes in `selftest.gd`, but a pure `--quit-after` frame run has **no synthesized player offense** — there's no steady stream of matches to confirm "steady offense out-paces the capped threat." The builder honestly reported it asserted the *mechanisms* (purge lowers blight, spread raises it, breach cracks a segment) but did **not** build an automated "winnable under steady play" simulation, because the prose implies one without saying how to drive offense headlessly.
- **Proposed `builder` edit (next pass):** either (a) drop the "watch fairness over the frame run" line as unactionable headlessly and keep fairness as a human-playtest concern, or (b) specify a concrete pattern — have `selftest.gd` synthesize N forced matches per simulated tick and assert the threat trends down under that cadence and up when offense stops. Pick one; today it reads as a check that can't actually be run.

### Finding B — POSITIVE: the fusion rule + builder prose pre-empted run-005's only build fix
- Run-005 lost its single iteration to the self-test lifecycle gotcha (Finding C). The new builder paragraph made the builder drive setup explicitly from the first draft, so run-006 took **zero** fixes of any kind. A cheap, LOW carry-forward measurably removed a class of iteration. Evidence that even small prose edits compound.

### Finding C — `concept`/`builder`, NOTE: `.gd.uid` files don't appear under headless-only runs
- The builder flagged that the `builder` Notes promise a sibling `.gd.uid` per script "to commit," but headless `--quit-after` / `--script` runs emit none (prior 0002 has none tracked either; `.uid` files are written by the editor's import pass). Minor doc drift — the Notes could say "the editor generates `.gd.uid` on import; headless-only runs may not, which is fine for the POC." Not blocking.

## Where this leaves the POC
- **Combination claim — now strongly demonstrated.** Trajectory across the hybrid runs: run-004 *coexist* (half-proven) → run-005 *interrupt/alternate* (forcing function helps, not enough) → run-006 **fused / coheres** (state/space fusion closes it). The POC has shown not just that the pipeline is blend-agnostic, but that we can **identify the specific concept lever for cohesion and confirm a prose edit moves it** — twice in a row on the hardest axis.
- **Mechanism — validated a 4th time, across three edit types** (quality, forcing-function cohesion, state/space-fusion cohesion). This is the core thesis, robust.
- **Automation — the logic-gate half of the M0+ hook is live and routine** (selftest authored by builder, run by validator, backs `core_loop_functional`). Human still gates *feel/cohesion*.

## Next (owner deciding)
- [x] Mark match3-survival-0003 `playable`; commit run-006.
- [ ] (cheap) Resolve Finding A on the next `builder` edit (make the fairness check actionable or drop it); fold Finding C doc note.
- [ ] (optional) The combination axis is now strongly demonstrated (mechanism proven 4×; cohesion lever identified AND its fix confirmed). Reasonable options: return to **breadth** (a 4th distinct single genre, e.g. brick breaker), or **wrap the POC** with a summary tying runs 001–006 to the §2 criteria.
