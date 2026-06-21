# Balance tuning via parameter search (P1-a)

**Date:** 2026-06-21
**Status:** approved, implementing
**Source:** distilled from the 2026-06-21 overnight deep-research (Tracks 3+4+1 /
MASTER-FINDINGS roadmap item #4). The unifying research theme — *push correctness to
deterministic verifiers; restrict generators/LLMs to proposing and to relative judgments* —
applied to balance: a deterministic search proposes a tuning config; the **human playtest
still decides fun**. No validated automated proxy for fun/retention exists (the research's
#1 open problem), so the engagement metric here is an explicitly-labeled heuristic, never
ground truth.

## Problem

`deepen` changes tuning (costs, gate/crush depths, drain rates, spawn geometry, the
difficulty ramp), and tuning is exactly what silently breaks winnability and fairness — the
reason `playtest-audit` exists. Today that tuning is done **by hand**: a human guesses
constants, runs `playtest.gd`, reads the metrics, and adjusts. `playtest.gd` already computes
rich balance metrics (earnings, commissions filled, per-dive `min_margin`, max depth, upgrade
affordability) but only ever uses them for a binary pass/fail and a human-readable dump.
There is no systematic way to *search* the tuning space for a config that is not just winnable
but **fair and well-paced** (succeeds with limited margin, rewards early, accrues without
grind or ceiling, no difficulty cliff).

Roadmap framing carried verbatim so it can't drift: optimize **single-player** metrics
(clear-rate, time-to-first-goal, economy solvency) + a **retention proxy** — **NOT** win-rate
disparity (that's a multiplayer signal). The realistic retention bar is **top-quartile ~7-8%
D7 (GameAnalytics 2024 definition), median ~3.4-3.9%** — do **NOT** anchor on the earlier
unverified "D7 ≥ 20%". We do not and cannot literally measure D7 from a bot; that number only
frames ambition.

## Solution: a seeded parameter-search harness over the existing bot

A new Node tool re-runs the existing `playtest.gd` bot once per candidate tuning config,
parses a machine-readable metrics line, **hard-rejects** configs that fail any playtest-audit
invariant, scores survivors by **distance outside target bands** (not by maximization), and
reports a ranked, advisory list of configs for a human to choose from.

Method: **simple parameter-search** (grid + random + coordinate-descent), not Bayesian
optimization. For the ~3-6 params a small game tunes this is sample-sufficient, deterministic,
dependency-light, and dogfoodable today. BO can be a later escalation if the search ever
becomes the bottleneck.

## Components

### 1. Metrics contract — `PLAYTEST METRICS {json}` (prerequisite)

`playtest.gd` gains **one machine-readable final line** in addition to the existing
human-readable lines and the `PLAYTEST OK`/`PLAYTEST FAIL: <reason>` verdict:

```
PLAYTEST METRICS {"solvent":true,"first_goal_reachable":true,"no_death_spiral":true,
  "no_trivial_dominant":true,"gross_earned":412,"commissions_filled":3,
  "time_to_first_goal_dives":1,"min_margin_min":4.2,"min_margin_series":[12.1,6.3,4.2,...],
  "max_depth":520,"upgrades_bought":4,...}
```

- Carries the numbers the bot already computes — nothing new is simulated, only emitted.
- The four invariant booleans mirror the existing gate so the harness can hard-reject without
  re-deriving them.
- **Backward-compatible:** the `OK/FAIL` line and human lines are unchanged; existing
  validator wiring is untouched.
- `playtest-audit/SKILL.md` documents this line as **the tuning contract**: the metrics are
  not just a human dump, they are the search signal.

### 2. Tuning-override seam in the game — `GF_TUNE`

The game's data layer reads tuning overrides from the `GF_TUNE` environment variable (a JSON
object) at boot and applies them on top of the hardcoded defaults:

```gdscript
# in the seedable data layer, at load/setup
static func _tune() -> Dictionary:
    var raw := OS.get_environment("GF_TUNE")
    if raw.is_empty(): return {}
    var d = JSON.parse_string(raw)
    return d if d is Dictionary else {}
# each tunable constant: var x := float(_tune().get("x", DEFAULT_X))
```

- **Unset `GF_TUNE` → identical behavior → zero production/runtime impact.** Players never see
  it; only the search harness sets it.
- This is a benign *refactor-to-create-a-seam* — exactly the move `deepen` already preaches —
  not a logic change. Defaults preserve all proven behavior; `selftest` still passes unchanged.
- Only the constants declared in a game's balance spec need the seam; do not parameterize the
  whole game.

### 3. `tools/balance.mjs` — the search harness

Structured like `comfy.mjs` / `contrast.mjs`: a **pure, unit-testable core** + a thin
Godot-spawning I/O shell + a CLI.

- **Input:** a per-game *balance spec* (JSON) —
  - `search_space`: `param → {min,max,step}` (continuous/stepped) or `{choices:[...]}`
    (discrete);
  - `objective`: per-metric `{band:[lo,hi], weight}` entries + the hard-constraint invariant
    keys;
  - `run`: how to invoke the bot (godot binary, `--script playtest.gd`, the game dir, a
    per-candidate timeout).
- **Runner (I/O shell):** for each candidate, evaluate over **K seeds** (default K small,
  e.g. 5) — spawn `godot --headless --script playtest.gd` once per seed with `GF_TUNE=<json>`
  and `GF_SEED=<n>` set, capture stdout, parse each `PLAYTEST METRICS` line, then **aggregate
  across seeds**: `clear-rate = fraction of seeds with all hard-constraint invariants true`;
  band metrics use the robust aggregate that matches their risk (worst-case `min_margin`, mean
  `time_to_first_goal`, etc.). Multi-seed is what makes "clear-rate" meaningful and the chosen
  config robust rather than seed-lucky. A run that crashes / times out / emits no metrics line
  counts as a failed seed (logged, not fatal).
- **Scoring (pure core):**
  - **Hard-reject** any config whose aggregate violates a hard constraint — `clear-rate` below
    the required floor, or any seed exhibiting a death-spiral / trivial dominant win / first
    goal unreachable. (A config must be robustly winnable across seeds, not just on a lucky
    one.) Rejected configs are reported but never rank.
  - **Two layers — focus-points for the human, one scalar only for the machine.** Each band
    target is kept as a **distinct focus-point**: `penaltyᵢ` = the distance the metric falls
    *outside* its band (0 inside). The harness retains the **per-focus-point penalty vector**
    (not just its sum). The summed `Σ weightᵢ · penaltyᵢ` exists **only as the optimizer's
    internal climb signal** (coordinate-descent / grid-ranking need a scalar to hill-climb) —
    it is plumbing, never a headline "engagement score". **Lower is better; the goal is
    in-band, not extremal** — this keeps "fair, not trivially easy".
- **Search (pure core, seeded → deterministic):** grid over the declared space, plus random
  sampling and coordinate-descent refinement around the best grid point (climbing the internal
  scalar). A fixed seed makes the whole search reproducible.
- **Output:** the verdict is presented **per focus-point** — a table whose columns are the
  distinct band-targets (clear-rate, time-to-first-goal, economy solvency, curve smoothness),
  each cell showing the metric value + its band penalty, so the human sees the *tradeoffs*
  ("great pacing, borderline economy"). The **composite total is shown too**, as an
  at-a-glance summary column labeled "engagement proxy (heuristic)" — surfaced *alongside* the
  breakdown, never *instead of* it, so it reads as a rough one-glance sort key, not a verdict.
  The harness also surfaces a **non-dominated shortlist** (configs not beaten by another on
  *every* focus-point — a Pareto front), not just the single argmin of the composite. An
  explicit **advisory** banner: this proposes; the human playtest decides. Rationale: showing
  *only* a composite reifies "fun" into one figure (the overclaim the no-validated-fun-proxy
  finding warns against) and hides the tradeoffs the human is there to weigh — so the
  breakdown leads and the total rides alongside; this mirrors visual-audit's validated
  **per-lens fan-out** over a collapsed-only pointwise score.
- **CLI:** `node tools/balance.mjs <game-dir> <spec.json> [--seed N] [--budget N]`.

### 4. The objective (band targets, not maximization)

- **Hard constraints (reject, from playtest-audit):** `solvent`, `first_goal_reachable`,
  `no_death_spiral`, `no_trivial_dominant`.
- **Band targets (penalize distance outside the band):**
  - **clear-rate / solvency margin** in a *fair* band — the competent bot succeeds, but with
    limited headroom (not 100% trivial, not a coin-flip);
  - **time-to-first-goal** low — first reward/commission within the first session/dive (D1
    proxy);
  - **economy solvency** positive and accruing, but neither instant (no ceiling) nor punishing
    (no grind) — a band on gross-earned-vs-cost pacing;
  - **difficulty-curve smoothness** — `min_margin_series` has no cliff/spike across the ramp
    (band on the max step-to-step drop).
- **Reported as distinct focus-points, with the composite alongside — not collapsed into it.**
  The four band-targets are reported separately (the per-focus-point penalty vector + a
  non-dominated shortlist, per §3). The weighted-sum composite is **also surfaced** as an
  at-a-glance summary / sort key under the label **"engagement proxy (heuristic)"** — it rides
  *alongside* the breakdown, never replaces it. It doubles as the search's internal climb
  signal. No focus-point is averaged away; the proxy is never presented as truth and never
  overrides an owner "this isn't fun".

### 5. Skill prose

- **`deepen/SKILL.md`** gains a **"Balance tuning (parameter search)"** subsection in the
  method:
  - *When:* after a pass that changes tuning (systemic/run-meta), or when `playtest.gd`
    metrics sit near a cliff / outside a band.
  - *How:* declare the search space + objective bands → run `balance.mjs` → **read the
    per-focus-point breakdown + the non-dominated shortlist** (weigh the tradeoffs across
    clear-rate / pacing / economy / smoothness yourself — do not just take the lowest composite)
    → apply the chosen config to the defaults → re-run the **full** gate set
    (`SELFTEST OK` / `UITEST OK` / `PLAYTEST OK`).
  - *Honesty rule (load-bearing):* the tool **proposes**, the human playtest **decides** fun;
    the objective targets **bands, not maxima**; an owner "not fun" verdict overrides any proxy
    win; record the chosen config + why in `depth_pass.notes`. The engagement proxy is a
    heuristic, consistent with "no validated fun proxy exists — keep the human checkpoint".
- **`playtest-audit/SKILL.md`** documents the `PLAYTEST METRICS` contract (§Metrics to report)
  so the bot's numbers are understood as the tuning signal, not just a human dump.

### 6. Dogfood — `diver-0001`

- Add the `GF_TUNE` seam to diver's tunable constants (rig safe-depth / crush line, air drain,
  upgrade costs, treasure + commission spawn geometry).
- Add the `PLAYTEST METRICS` line to `games/diver-0001/playtest.gd`.
- Write `games/diver-0001/balance.spec.json` pointed at the **flagged open balance item** —
  "deep Trench commissions are sparse" (the bot reports it; tune spawn geometry / commission
  depths so deep commissions are fillable without making shallow ones trivial).
- Run the search, show it lands an in-band config, apply it, and re-run `SELFTEST` / `UITEST`
  / `PLAYTEST` all green on Godot 4.6.3.

## Testing

- **`tools/balance.test.mjs`** unit-tests the pure core with **no Godot**: band-penalty math
  (inside band = 0, outside = distance, weights applied), the **per-focus-point penalty vector
  is retained, not just its sum**, the **non-dominated shortlist** correctly drops dominated
  configs and keeps Pareto-incomparable ones (a config better on pacing but worse on economy
  survives), hard-reject on a false invariant, search determinism under a fixed seed,
  coordinate-descent improves the internal scalar on a synthetic objective, metrics-line
  parsing (well-formed, malformed, missing → reject). Mock the runner so the search logic is
  exercised against synthetic metric vectors.
- Full vitest suite stays green.
- Dogfood gates (`SELFTEST`/`UITEST`/`PLAYTEST`) green on the real game after the chosen
  config is applied.

## Boundaries / non-goals

- **Not** a fun oracle. The engagement proxy is a heuristic; the human playtest remains the
  real gate. (Consistent with the deferred "automated fun proxy" research problem.)
- **Not** win-rate disparity / any multiplayer metric — single-player metrics only.
- **No manifest schema change.** The tuning artifacts are `balance.spec.json` (per game) + the
  chosen config folded into the game's defaults + a note in the existing `depth_pass.notes`.
  No new manifest field, so `schema/manifest.schema.json` is untouched.
- **No Bayesian optimization** in this pass — simple parameter-search only; BO is a later
  escalation if search cost ever dominates.
- Does not auto-apply a config. The harness proposes; a human (via `deepen`) chooses and
  applies, then re-validates.

## Project gotchas (carry these)

- Headless `godot --script` does not instantiate autoloads → the `GF_TUNE` read must live in a
  `preload`-able data layer / `static func`, same constraint as `selftest`/`playtest`.
- Seed every RNG; with fixed `GF_SEED` + fixed `dt` + fixed `GF_TUNE`, a single candidate run
  is fully reproducible — required for a deterministic search. `playtest.gd` must route its
  RNG seed through `GF_SEED` (defaulting to its current fixed seed when unset, so the standalone
  gate behaves exactly as today).
- Clear `user://save.json` at the start AND end of each candidate run (a persisted economy
  leaking across candidates poisons "can a *fresh* player win?").
- `GF_TUNE` must be applied to **defaults**, never to a persisted save; the seam reads it at
  setup, not after load.
</content>
</invoke>
