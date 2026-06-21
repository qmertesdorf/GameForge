# Balance Tuning via Parameter Search (P1-a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `deepen` a deterministic parameter-search harness that re-runs the existing `playtest.gd` bot across a tuning search-space and proposes a config that is winnable AND fair/well-paced — keeping the human playtest as the real fun gate.

**Architecture:** A pure, unit-testable JS core (`tools/balance.mjs`: band-penalty scoring, per-focus-point vector, across-seed aggregation, non-dominated/Pareto shortlist, deterministic grid+random+coordinate-descent search) + a thin Godot-spawning runner + CLI — mirroring the `tools/contrast.mjs` pure-core/Godot-shell split. The game exposes tunable constants via a `GF_TUNE` env-var seam (unset → identical behavior); the bot emits a machine-readable `PLAYTEST METRICS {json}` line the harness consumes. Dogfooded on `diver-0001`.

**Tech Stack:** Node ESM + vitest (existing `tools/*.test.mjs` posture), Godot 4.6.3 GDScript (`RefCounted` data layer + `SceneTree` bot), JSON specs.

**Conventions carried from the codebase:**
- Godot binary is NOT on PATH; tests guard on `GODOT_BIN`. Local runs set:
  `GODOT_BIN="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"`
- `tools/contrast.mjs` reads `process.env.GODOT_BIN || "godot"` — reuse that exact pattern.
- Pure functions are `export`ed and unit-tested with NO Godot; the Godot shell is guarded with `test.skipIf(!hasGodot)`.
- Run one test file: `npx vitest run tools/balance.test.mjs`. Run all: `npx vitest run`.
- Headless `godot --script` does not instantiate autoloads → the `GF_TUNE`/`GF_SEED` seam must live in a `preload`-able `RefCounted` with `static func`s.

---

## File Structure

- **Create `tools/balance.mjs`** — the harness. Pure core (`bandPenalty`, `checkConstraints`, `aggregateSeeds`, `scoreCandidate`, `nonDominated`, `enumerateCandidates`, `mulberry32`, `coordinateDescent`, `runSearch`) + Godot runner (`evalCandidate`) + `main()` CLI.
- **Create `tools/balance.test.mjs`** — vitest unit tests for the pure core (no Godot).
- **Create `games/diver-0001/Tune.gd`** — `RefCounted` with `static func`s reading `GF_TUNE` (JSON dict) + `GF_SEED`, cached.
- **Modify `games/diver-0001/DiveState.gd`** — route a small set of economy/crush tunables through `Tune`, defaulting to today's `const`s.
- **Modify `games/diver-0001/Main.gd`** — route the pre-seeded deep-treasure column geometry + the world RNG seed through `Tune`.
- **Modify `games/diver-0001/playtest.gd`** — emit the `PLAYTEST METRICS {json}` line; seed via `Tune`.
- **Create `games/diver-0001/balance.spec.json`** — search space + objective bands for the deep-commission tuning.
- **Modify `.claude/skills/deepen/SKILL.md`** — add the "Balance tuning (parameter search)" method subsection.
- **Modify `.claude/skills/playtest-audit/SKILL.md`** — document the `PLAYTEST METRICS` contract.

---

## Task 1: Band-penalty + constraint checking (pure)

**Files:**
- Create: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// tools/balance.test.mjs
import { test, expect, describe } from "vitest";
import { bandPenalty, checkConstraints } from "./balance.mjs";

describe("bandPenalty", () => {
  test("zero inside the band (inclusive ends)", () => {
    expect(bandPenalty(0.5, [0.4, 0.7])).toBe(0);
    expect(bandPenalty(0.4, [0.4, 0.7])).toBe(0);
    expect(bandPenalty(0.7, [0.4, 0.7])).toBe(0);
  });
  test("distance below the band", () => {
    expect(bandPenalty(0.2, [0.4, 0.7])).toBeCloseTo(0.2, 9);
  });
  test("distance above the band", () => {
    expect(bandPenalty(0.9, [0.4, 0.7])).toBeCloseTo(0.2, 9);
  });
});

describe("checkConstraints", () => {
  const agg = { clear_rate: 0.8, no_death_spiral: true, no_trivial_dominant: true };
  test("passes when all numeric floors and booleans satisfied → null", () => {
    expect(checkConstraints(agg, { clear_rate: 0.6, no_death_spiral: true })).toBeNull();
  });
  test("returns the offending key when a numeric floor fails", () => {
    expect(checkConstraints(agg, { clear_rate: 0.95 })).toBe("clear_rate");
  });
  test("returns the offending key when a boolean require fails", () => {
    expect(checkConstraints({ ...agg, no_death_spiral: false }, { no_death_spiral: true })).toBe("no_death_spiral");
  });
  test("a missing metric fails its constraint", () => {
    expect(checkConstraints({}, { clear_rate: 0.6 })).toBe("clear_rate");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — "Failed to resolve import './balance.mjs'" / functions not defined.

- [ ] **Step 3: Write minimal implementation**

```js
// tools/balance.mjs
// Deterministic balance-tuning parameter search for GameForge. Re-runs a game's
// playtest.gd bot across a tuning search-space and proposes a config that is winnable
// AND fair/well-paced. Pure scoring/search core (unit-tested, no Godot) + a thin
// Godot-spawning runner + CLI — same split as tools/contrast.mjs.
//
// HONESTY: this PROPOSES a config from an engagement PROXY (a heuristic, not a
// validated fun metric — none exists). The human playtest decides fun. Focus-points
// are reported separately; the composite is a search/sort signal, never a verdict.
//
// CLI:
//   node tools/balance.mjs <game-dir> <spec.json> [--seed N] [--budget N] [--seeds K]

// --- band penalty: distance a metric falls OUTSIDE its [lo,hi] band (0 inside) ---
export function bandPenalty(value, [lo, hi]) {
  if (value < lo) return lo - value;
  if (value > hi) return value - hi;
  return 0;
}

// --- hard constraints: numeric floors (req is a number) or boolean requires.
// Returns the first offending key, or null if all pass. ---
export function checkConstraints(agg, require = {}) {
  for (const [k, req] of Object.entries(require)) {
    const v = agg[k];
    if (typeof req === "boolean") {
      if (Boolean(v) !== req) return k;
    } else {
      if (typeof v !== "number" || v < req) return k;
    }
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): band-penalty + hard-constraint checks (pure core)"
```

---

## Task 2: Aggregate metrics across seeds (pure)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { aggregateSeeds } from "./balance.mjs";

describe("aggregateSeeds", () => {
  const invariants = ["solvent", "no_death_spiral"];
  const perSeed = [
    { solvent: true,  no_death_spiral: true,  time_to_first_goal: 1, min_margin_min: 8 },
    { solvent: true,  no_death_spiral: true,  time_to_first_goal: 3, min_margin_min: 2 },
    { solvent: false, no_death_spiral: true,  time_to_first_goal: 9, min_margin_min: 0 },
  ];

  test("clear_rate = fraction of seeds with ALL invariants true", () => {
    const agg = aggregateSeeds(perSeed, { invariants });
    expect(agg.clear_rate).toBeCloseTo(2 / 3, 9);
  });
  test("per-invariant booleans are AND across seeds (for require checks)", () => {
    const agg = aggregateSeeds(perSeed, { invariants });
    expect(agg.solvent).toBe(false);        // one seed false
    expect(agg.no_death_spiral).toBe(true); // all true
  });
  test("numeric metrics use the named aggregator; default mean", () => {
    const agg = aggregateSeeds(perSeed, { invariants, aggregators: { min_margin_min: "min" } });
    expect(agg.min_margin_min).toBe(0);                  // worst-case margin
    expect(agg.time_to_first_goal).toBeCloseTo((1 + 3 + 9) / 3, 9); // default mean
  });
  test("empty input → clear_rate 0, invariants false", () => {
    const agg = aggregateSeeds([], { invariants });
    expect(agg.clear_rate).toBe(0);
    expect(agg.solvent).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `aggregateSeeds` is not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
const AGGS = {
  mean: (a) => a.reduce((s, x) => s + x, 0) / a.length,
  min: (a) => Math.min(...a),
  max: (a) => Math.max(...a),
  median: (a) => {
    const s = [...a].sort((x, y) => x - y);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  },
};

// Aggregate K per-seed metric objects into one candidate-level metric object.
// clear_rate = fraction of seeds where every invariant boolean is true; each
// invariant is also reduced with AND (so a numeric floor on clear_rate plus a
// boolean require both work). Numeric metrics use aggregators[key] (default mean).
export function aggregateSeeds(perSeed, { invariants = [], aggregators = {} } = {}) {
  const agg = {};
  const n = perSeed.length;
  agg.clear_rate = n === 0 ? 0 : perSeed.filter((m) => invariants.every((k) => Boolean(m[k]))).length / n;
  for (const k of invariants) agg[k] = n > 0 && perSeed.every((m) => Boolean(m[k]));
  const numKeys = new Set();
  for (const m of perSeed) for (const k of Object.keys(m)) if (typeof m[k] === "number") numKeys.add(k);
  for (const k of numKeys) {
    const vals = perSeed.map((m) => m[k]).filter((v) => typeof v === "number");
    if (vals.length === 0) continue;
    const fn = AGGS[aggregators[k] || "mean"];
    agg[k] = fn(vals);
  }
  return agg;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS (all Task 1 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): across-seed metric aggregation (clear-rate + per-metric aggregators)"
```

---

## Task 3: Score a candidate — focus-point vector + composite (pure)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { scoreCandidate } from "./balance.mjs";

describe("scoreCandidate", () => {
  const objective = {
    require: { clear_rate: 0.6, no_death_spiral: true },
    bands: {
      clear_rate: { band: [0.6, 0.85], weight: 1 },
      time_to_first_goal: { band: [1, 2], weight: 2 },
    },
  };
  test("rejected candidate carries the offending key and infinite composite", () => {
    const agg = { clear_rate: 0.3, no_death_spiral: true, time_to_first_goal: 1 };
    const r = scoreCandidate(agg, objective);
    expect(r.rejected).toBe(true);
    expect(r.reason).toBe("clear_rate");
    expect(r.composite).toBe(Infinity);
  });
  test("survivor keeps a PER-FOCUS-POINT penalty vector AND a weighted composite", () => {
    const agg = { clear_rate: 0.7, no_death_spiral: true, time_to_first_goal: 4 };
    const r = scoreCandidate(agg, objective);
    expect(r.rejected).toBe(false);
    expect(r.penalties.clear_rate).toBeCloseTo(0, 9);     // in band
    expect(r.penalties.time_to_first_goal).toBeCloseTo(2 * 2, 9); // (4-2)*weight2
    expect(r.composite).toBeCloseTo(4, 9);
  });
  test("a fully in-band survivor scores composite 0", () => {
    const agg = { clear_rate: 0.7, no_death_spiral: true, time_to_first_goal: 1.5 };
    expect(scoreCandidate(agg, objective).composite).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `scoreCandidate` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
// Score one aggregated candidate. Hard-reject (composite Infinity) if a constraint
// fails. Otherwise keep the PER-FOCUS-POINT penalty vector (lower better, 0 = in
// band) AND a weighted-sum composite — the composite is the search's climb/sort
// signal and an at-a-glance summary, NOT a standalone verdict.
export function scoreCandidate(agg, objective) {
  const reason = checkConstraints(agg, objective.require || {});
  if (reason) return { rejected: true, reason, penalties: {}, composite: Infinity };
  const penalties = {};
  let composite = 0;
  for (const [k, spec] of Object.entries(objective.bands || {})) {
    const p = bandPenalty(agg[k], spec.band) * (spec.weight ?? 1);
    penalties[k] = p;
    composite += p;
  }
  return { rejected: false, reason: null, penalties, composite };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): per-focus-point penalty vector + composite scoring"
```

---

## Task 4: Non-dominated (Pareto) shortlist (pure)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { nonDominated } from "./balance.mjs";

describe("nonDominated", () => {
  const keys = ["a", "b"];
  test("drops a config beaten on EVERY focus-point", () => {
    const cands = [
      { id: "x", penalties: { a: 1, b: 1 } },
      { id: "y", penalties: { a: 2, b: 2 } }, // dominated by x
    ];
    expect(nonDominated(cands, keys).map((c) => c.id)).toEqual(["x"]);
  });
  test("keeps Pareto-incomparable configs (better on one, worse on another)", () => {
    const cands = [
      { id: "x", penalties: { a: 1, b: 3 } },
      { id: "y", penalties: { a: 3, b: 1 } },
    ];
    expect(nonDominated(cands, keys).map((c) => c.id).sort()).toEqual(["x", "y"]);
  });
  test("equal-on-all duplicates are not dropped (no strict domination)", () => {
    const cands = [
      { id: "x", penalties: { a: 1, b: 1 } },
      { id: "y", penalties: { a: 1, b: 1 } },
    ];
    expect(nonDominated(cands, keys).map((c) => c.id).sort()).toEqual(["x", "y"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `nonDominated` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
// A config is DOMINATED if another is <= on every focus-point penalty and < on at
// least one. The non-dominated set (Pareto front) is what the human chooses from —
// no focus-point is averaged away. Equal-on-all configs do not dominate each other.
export function nonDominated(candidates, keys) {
  return candidates.filter(
    (c) =>
      !candidates.some(
        (o) =>
          o !== c &&
          keys.every((k) => o.penalties[k] <= c.penalties[k]) &&
          keys.some((k) => o.penalties[k] < c.penalties[k]),
      ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): non-dominated (Pareto) shortlist over focus-points"
```

---

## Task 5: Candidate enumeration + deterministic PRNG (pure)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { mulberry32, paramValues, enumerateCandidates } from "./balance.mjs";

describe("mulberry32", () => {
  test("is deterministic for a fixed seed", () => {
    const a = mulberry32(42), b = mulberry32(42);
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
  });
  test("returns values in [0,1)", () => {
    const r = mulberry32(7);
    for (let i = 0; i < 100; i++) {
      const v = r();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);
    }
  });
});

describe("paramValues", () => {
  test("stepped range is inclusive of both ends", () => {
    expect(paramValues({ min: 0, max: 10, step: 5 })).toEqual([0, 5, 10]);
  });
  test("choices pass through verbatim", () => {
    expect(paramValues({ choices: [1, 4, 9] })).toEqual([1, 4, 9]);
  });
});

describe("enumerateCandidates", () => {
  const space = { x: { min: 0, max: 2, step: 1 }, y: { choices: ["a", "b"] } };
  test("grid is the full cartesian product", () => {
    const grid = enumerateCandidates(space, { random: 0, seed: 1 });
    expect(grid).toHaveLength(3 * 2);
    expect(grid).toContainEqual({ x: 1, y: "b" });
  });
  test("random samples are deterministic under a fixed seed", () => {
    const r1 = enumerateCandidates(space, { random: 4, seed: 9 });
    const r2 = enumerateCandidates(space, { random: 4, seed: 9 });
    expect(r1).toEqual(r2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `mulberry32`/`paramValues`/`enumerateCandidates` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
// Deterministic PRNG (mulberry32) so the whole search is reproducible from --seed.
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// The discrete value list for one param: a stepped [min,max] range (inclusive) or
// an explicit choices list.
export function paramValues(spec) {
  if (Array.isArray(spec.choices)) return [...spec.choices];
  const out = [];
  // guard against float drift on the last step
  for (let v = spec.min; v <= spec.max + 1e-9; v += spec.step) out.push(Math.round(v * 1e6) / 1e6);
  return out;
}

// Full grid (cartesian product) + `random` extra random points (deterministic).
export function enumerateCandidates(space, { random = 0, seed = 1 } = {}) {
  const keys = Object.keys(space);
  const lists = keys.map((k) => paramValues(space[k]));
  let grid = [{}];
  for (let i = 0; i < keys.length; i++) {
    const next = [];
    for (const partial of grid) for (const v of lists[i]) next.push({ ...partial, [keys[i]]: v });
    grid = next;
  }
  const rnd = mulberry32(seed);
  for (let r = 0; r < random; r++) {
    const cand = {};
    for (let i = 0; i < keys.length; i++) cand[keys[i]] = lists[i][Math.floor(rnd() * lists[i].length)];
    grid.push(cand);
  }
  return grid;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): deterministic candidate enumeration (grid + random)"
```

---

## Task 6: Coordinate-descent + runSearch orchestration (pure, injected evaluator)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { runSearch } from "./balance.mjs";

describe("runSearch (injected synthetic evaluator — no Godot)", () => {
  // Synthetic game: the bot "wins" (clear_rate 1) only when x in [3,7]; the ideal
  // time_to_first_goal sits at x=5. evalFn returns one agg per candidate.
  const space = { x: { min: 0, max: 10, step: 1 } };
  const objective = {
    invariants: ["solvent"],
    require: { clear_rate: 1, solvent: true },
    bands: { time_to_first_goal: { band: [1, 1], weight: 1 } },
    aggregators: { time_to_first_goal: "mean" },
    focus_points: ["time_to_first_goal"],
  };
  const evalFn = ({ x }) => ({
    solvent: x >= 3 && x <= 7,
    clear_rate: x >= 3 && x <= 7 ? 1 : 0,
    time_to_first_goal: 1 + Math.abs(x - 5), // minimised at x=5
  });

  test("finds the in-band optimum (x=5) and reports it best", () => {
    const res = runSearch({ search_space: space, objective }, evalFn, { seed: 1 });
    expect(res.best.params.x).toBe(5);
    expect(res.best.composite).toBe(0);
  });
  test("rejected candidates are excluded from ranking but counted", () => {
    const res = runSearch({ search_space: space, objective }, evalFn, { seed: 1 });
    expect(res.rejectedCount).toBeGreaterThan(0);
    expect(res.ranked.every((c) => !c.rejected)).toBe(true);
  });
  test("surfaces a non-dominated shortlist over the focus-points", () => {
    const res = runSearch({ search_space: space, objective }, evalFn, { seed: 1 });
    expect(res.shortlist.length).toBeGreaterThanOrEqual(1);
    expect(res.shortlist).toContainEqual(expect.objectContaining({ params: { x: 5 } }));
  });
  test("is deterministic under a fixed seed", () => {
    const a = runSearch({ search_space: space, objective }, evalFn, { seed: 3 });
    const b = runSearch({ search_space: space, objective }, evalFn, { seed: 3 });
    expect(a.best.params).toEqual(b.best.params);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `runSearch` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
// Local refinement: from a starting param dict, repeatedly try each param's
// adjacent grid values and keep any move that lowers the composite. Deterministic.
export function coordinateDescent(start, space, scoreFn) {
  const keys = Object.keys(space);
  const lists = Object.fromEntries(keys.map((k) => [k, paramValues(space[k])]));
  let cur = { ...start };
  let curScore = scoreFn(cur).composite;
  let improved = true;
  while (improved) {
    improved = false;
    for (const k of keys) {
      const idx = lists[k].findIndex((v) => v === cur[k]);
      for (const ni of [idx - 1, idx + 1]) {
        if (ni < 0 || ni >= lists[k].length) continue;
        const trial = { ...cur, [k]: lists[k][ni] };
        const s = scoreFn(trial).composite;
        if (s < curScore) { cur = trial; curScore = s; improved = true; }
      }
    }
  }
  return cur;
}

// Orchestrate the whole search: enumerate (grid + random) → evaluate each via the
// injected evalFn (the Godot runner in production, a synthetic fn in tests) → score
// → coordinate-descent refine around the best survivor → rank + Pareto shortlist.
// evalFn(params) returns an AGGREGATED metric object (already reduced across seeds).
export function runSearch(spec, evalFn, { seed = 1, random = 8 } = {}) {
  const space = spec.search_space;
  const objective = spec.objective;
  const focus = objective.focus_points || Object.keys(objective.bands || {});
  const cache = new Map();
  const key = (p) => JSON.stringify(p);
  const scoreOf = (params) => {
    const k = key(params);
    if (cache.has(k)) return cache.get(k);
    const agg = evalFn(params);
    const sc = scoreCandidate(agg, objective);
    const rec = { params, agg, ...sc };
    cache.set(k, rec);
    return rec;
  };

  for (const params of enumerateCandidates(space, { random, seed })) scoreOf(params);
  const survivors = [...cache.values()].filter((c) => !c.rejected);
  if (survivors.length) {
    const seed0 = survivors.reduce((a, b) => (b.composite < a.composite ? b : a));
    scoreOf(coordinateDescent(seed0.params, space, scoreOf)); // refine
  }

  const all = [...cache.values()];
  const ranked = all.filter((c) => !c.rejected).sort((a, b) => a.composite - b.composite);
  const shortlist = nonDominated(ranked, focus);
  return {
    best: ranked[0] || null,
    ranked,
    shortlist,
    rejectedCount: all.filter((c) => c.rejected).length,
    focus,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS (all prior + 4 new).

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): coordinate-descent + runSearch orchestration (injected evaluator)"
```

---

## Task 7: Metrics-line parsing (pure)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { parseMetricsLine } from "./balance.mjs";

describe("parseMetricsLine", () => {
  const stdout = [
    "PLAYTEST dive1 rig0: earned=168 ...",
    'PLAYTEST METRICS {"solvent":true,"time_to_first_goal":1,"min_margin_min":4.2}',
    "PLAYTEST OK",
  ].join("\n");
  test("extracts the JSON object from the PLAYTEST METRICS line", () => {
    expect(parseMetricsLine(stdout)).toEqual({ solvent: true, time_to_first_goal: 1, min_margin_min: 4.2 });
  });
  test("missing line → null", () => {
    expect(parseMetricsLine("PLAYTEST OK")).toBeNull();
  });
  test("malformed JSON → null", () => {
    expect(parseMetricsLine("PLAYTEST METRICS {not json}")).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `parseMetricsLine` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
// Extract the single machine-readable metrics object the bot prints. Tolerant: a
// crashed/incomplete run (no line, bad JSON) returns null and the runner treats it
// as a failed seed.
export function parseMetricsLine(stdout) {
  const m = String(stdout).match(/PLAYTEST METRICS (\{.*\})/);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): tolerant PLAYTEST METRICS line parsing"
```

---

## Task 8: Godot runner + CLI (I/O shell)

**Files:**
- Modify: `tools/balance.mjs`
- Test: `tools/balance.test.mjs` (guarded smoke check)

- [ ] **Step 1: Write the failing test**

```js
// append to tools/balance.test.mjs
import { execFileSync } from "node:child_process";
function godotAvailable() {
  try { execFileSync(process.env.GODOT_BIN || "godot", ["--version"], { stdio: ["ignore", "pipe", "pipe"] }); return true; }
  catch { return false; }
}
const hasGodot = godotAvailable();

import { makeGodotEvaluator } from "./balance.mjs";

describe("makeGodotEvaluator", () => {
  test("returns a function", () => {
    const ev = makeGodotEvaluator("games/diver-0001", { seeds: 2 });
    expect(typeof ev).toBe("function");
  });
  test.skipIf(!hasGodot)("evaluates a candidate to an aggregated metric object", () => {
    const ev = makeGodotEvaluator("games/diver-0001", { seeds: 2, invariants: ["solvent"] });
    const agg = ev({}); // empty GF_TUNE = production defaults
    expect(typeof agg.clear_rate).toBe("number");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tools/balance.test.mjs`
Expected: FAIL — `makeGodotEvaluator` not exported.

- [ ] **Step 3: Write minimal implementation**

```js
// append to tools/balance.mjs
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

function godotBin() { return process.env.GODOT_BIN || "godot"; }

// Run the game's playtest.gd once with a given GF_TUNE + GF_SEED. Returns the parsed
// metrics object, or null if the run produced no usable metrics line.
function runOneSeed(gameDir, tuneJson, seed, timeout) {
  try {
    const out = execFileSync(
      godotBin(),
      ["--headless", "--path", resolve(gameDir), "--script", "res://playtest.gd"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout,
        env: { ...process.env, GF_TUNE: JSON.stringify(tuneJson), GF_SEED: String(seed) } },
    );
    return parseMetricsLine(out);
  } catch (e) {
    return parseMetricsLine(e.stdout || ""); // timeout/non-zero exit can still have emitted metrics
  }
}

// Build the production evaluator: for a candidate, run K seeds, drop failed seeds,
// aggregate. Closes over the game dir + objective's invariants/aggregators.
export function makeGodotEvaluator(gameDir, { seeds = 5, invariants = [], aggregators = {}, timeout = 60000 } = {}) {
  return (params) => {
    const perSeed = [];
    for (let s = 0; s < seeds; s++) {
      const m = runOneSeed(gameDir, params, 1000 + s, timeout);
      if (m) perSeed.push(m);
    }
    return aggregateSeeds(perSeed, { invariants, aggregators });
  };
}

// --- CLI -----------------------------------------------------------------
function fmtPct(x) { return (x * 100).toFixed(0) + "%"; }

function main(argv) {
  const args = argv.slice(2);
  const pos = args.filter((a) => !a.startsWith("--"));
  const flag = (name, def) => { const i = args.indexOf(name); return i >= 0 ? Number(args[i + 1]) : def; };
  const gameDir = pos[0];
  const specPath = pos[1];
  if (!gameDir || !specPath) {
    console.error("usage: balance.mjs <game-dir> <spec.json> [--seed N] [--budget N] [--seeds K]");
    process.exit(2);
  }
  const spec = JSON.parse(readFileSync(specPath, "utf8"));
  const obj = spec.objective;
  const evalFn = makeGodotEvaluator(gameDir, {
    seeds: flag("--seeds", 5),
    invariants: obj.invariants || [],
    aggregators: obj.aggregators || {},
  });
  const res = runSearch(spec, evalFn, { seed: flag("--seed", 1), random: flag("--budget", 8) });

  console.log("\n=== BALANCE SEARCH (advisory — proposes a config; the human playtest decides fun) ===");
  console.log(`evaluated ${res.ranked.length + res.rejectedCount} configs (${res.rejectedCount} rejected by hard constraints)\n`);
  console.log("Best by composite engagement proxy (heuristic — a sort key, NOT a verdict):");
  if (res.best) {
    console.log("  params:    " + JSON.stringify(res.best.params));
    console.log("  composite: " + res.best.composite.toFixed(3));
    console.log("  focus-points (penalty / value):");
    for (const k of res.focus)
      console.log(`    ${k}: penalty ${(res.best.penalties[k] ?? 0).toFixed(3)}  value ${res.best.agg[k]}`);
    console.log("  clear_rate: " + fmtPct(res.best.agg.clear_rate ?? 0));
  } else {
    console.log("  (no config satisfied the hard constraints — widen the search space)");
  }
  console.log(`\nNon-dominated shortlist (${res.shortlist.length} configs — weigh the tradeoffs yourself):`);
  for (const c of res.shortlist.slice(0, 10))
    console.log("  " + JSON.stringify(c.params) + "  composite " + c.composite.toFixed(3) +
      "  [" + res.focus.map((k) => `${k} ${(c.penalties[k] ?? 0).toFixed(2)}`).join(", ") + "]");
  console.log("\nReminder: apply a chosen config to the game defaults, then re-run SELFTEST / UITEST / PLAYTEST.");
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main(process.argv);
```

> Note: the `import` statements added here must be hoisted to the top of `balance.mjs` with the other imports (ESM imports are file-scoped). Move the three `import` lines to the top of the file beside any existing imports; leave the function bodies where shown.

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tools/balance.test.mjs`
Expected: PASS — the non-guarded `returns a function` test passes; the `skipIf` Godot test runs only locally with `GODOT_BIN` set (it checks the plumbing returns a number — `clear_rate` is 0 from an empty seed set until Task 10 lands the metrics line, but 0 is still a number, so it passes once Godot is present; it only becomes *meaningful* after Task 10). In CI it stays skipped.

- [ ] **Step 5: Run full suite to confirm no regressions**

Run: `npx vitest run`
Expected: all prior tests still PASS (the new file adds tests, breaks none).

- [ ] **Step 6: Commit**

```bash
git add tools/balance.mjs tools/balance.test.mjs
git commit -m "feat(balance): Godot K-seed runner + advisory CLI report"
```

---

## Task 9: `GF_TUNE`/`GF_SEED` seam in diver-0001 (Tune.gd + DiveState + Main)

**Files:**
- Create: `games/diver-0001/Tune.gd`
- Modify: `games/diver-0001/DiveState.gd` (the economy/crush tunables)
- Modify: `games/diver-0001/Main.gd:21-23` (preseed geometry) and `Main.gd:83` (seed)

- [ ] **Step 1: Create the override helper**

Create `games/diver-0001/Tune.gd`:

```gdscript
extends RefCounted
class_name Tune
# GF_TUNE / GF_SEED override seam for balance search. UNSET → empty dict / the
# game's own default seed → IDENTICAL production behavior (zero runtime impact;
# players never set these). The balance.mjs harness sets GF_TUNE (a JSON object of
# parameter overrides) and GF_SEED (the world RNG seed) per candidate run.
# Static funcs only — headless `--script` has no autoloads (preload + static).

static var _cache: Dictionary = {}
static var _parsed: bool = false

static func dict() -> Dictionary:
	if not _parsed:
		_parsed = true
		var raw := OS.get_environment("GF_TUNE")
		if not raw.is_empty():
			var d = JSON.parse_string(raw)
			if d is Dictionary:
				_cache = d
	return _cache

static func num(key: String, default_value: float) -> float:
	var d := dict()
	return float(d.get(key, default_value))

static func int_of(key: String, default_value: int) -> int:
	var d := dict()
	return int(d.get(key, default_value))

static func seed_of(default_value: int) -> int:
	var raw := OS.get_environment("GF_SEED")
	return int(raw) if raw.is_valid_int() else default_value
```

- [ ] **Step 2: Route DiveState economy/crush tunables through Tune**

In `games/diver-0001/DiveState.gd`, route the two methods that read the tunables in our search space (`base_safe_depth`, `rig_step`, `base_drain`, `crush_mult`) through `Tune` (defaults preserve today's behavior). Replace the bodies of `max_safe_depth()` and `current_drain()` as follows.

Replace `max_safe_depth()` (currently lines ~100-102):

```gdscript
func max_safe_depth() -> float:
	# The Pressure Rig's job: each level unlocks deeper water before the crush bites.
	var base_safe := Tune.num("base_safe_depth", BASE_SAFE_DEPTH)
	var rig_step := Tune.num("rig_step", RIG_STEP)
	return base_safe + float(_lvl("rig")) * rig_step
```

Replace `current_drain()` (currently lines ~112-116):

```gdscript
func current_drain() -> float:
	var base_drain := Tune.num("base_drain", BASE_DRAIN)
	var crush := Tune.num("crush_mult", CRUSH_MULT)
	var base: float = base_drain + depth * DEPTH_DRAIN_FACTOR
	if depth > max_safe_depth():
		base *= crush          # the crush: past your rig, the deep eats your air
	return base * drain_mult()
```

- [ ] **Step 3: Route Main.gd preseed geometry + world seed through Tune**

In `games/diver-0001/Main.gd`, line 83, replace:

```gdscript
	state.seed_rng(20240620)
```

with:

```gdscript
	state.seed_rng(Tune.seed_of(20240620))
```

Then replace the body of `_preseed_treasures()` (currently lines 204-220) to read the column geometry from Tune. The deep-commission lever is `preseed_step`/`preseed_count` (a longer/denser column reaches more deep treasure into collectible water). New body:

```gdscript
func _preseed_treasures() -> void:
	# Guarantee collectible treasure in safe water from the first second — without
	# this the nearest spawn is SPAWN_AHEAD below the diver, deep past the crush, and
	# the dive is unwinnable (the balance bot caught exactly this). Seed a column down
	# through the Shallows and into the Reef so there is always something to bank.
	# Geometry is GF_TUNE-overridable (the deep-commission reach lever); defaults match.
	var preseed_from := Tune.num("preseed_from", PRESEED_FROM)
	var preseed_step := Tune.num("preseed_step", PRESEED_STEP)
	var preseed_count := Tune.int_of("preseed_count", PRESEED_COUNT)
	var d: float = preseed_from
	for _i in range(preseed_count):
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": d,
			"kind": "treasure",
			"zone": state.zone_for(d),
			"alive": true,
			"vx": 0.0,
		})
		d += preseed_step
	_last_treasure_d = d - SPAWN_AHEAD   # let rolling spawn continue below the seeded column
```

- [ ] **Step 4: Verify production behavior is unchanged (GF_TUNE unset)**

Run (set `GODOT` to the pinned binary first; one line):

```bash
GODOT="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"; "$GODOT" --headless --path games/diver-0001/ --script res://selftest.gd && "$GODOT" --headless --path games/diver-0001/ --script res://uitest.gd && "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd
```

Expected: `SELFTEST OK`, `UITEST OK`, `PLAYTEST OK` (unset env = identical to pre-change behavior).

- [ ] **Step 5: Verify an override actually moves the world**

Run (a deliberately punishing crush should drop earnings / fail solvency):

```bash
GODOT="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"; GF_TUNE='{"base_safe_depth":40,"crush_mult":12}' "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd
```

Expected: visibly worse metrics than Step 4 (lower `earned`, likely `PLAYTEST FAIL`) — proving the seam is live.

- [ ] **Step 6: Commit**

```bash
git add games/diver-0001/Tune.gd games/diver-0001/DiveState.gd games/diver-0001/Main.gd
git commit -m "feat(diver-0001): GF_TUNE/GF_SEED override seam for balance search (defaults preserve behavior)"
```

---

## Task 10: `PLAYTEST METRICS` line + GF_SEED in diver playtest.gd

**Files:**
- Modify: `games/diver-0001/playtest.gd`

- [ ] **Step 1: Seed the run from GF_SEED**

In `games/diver-0001/playtest.gd`, the bot uses the world the game seeds itself (Main.gd now reads `Tune.seed_of`). No bot change is needed for seeding IF the bot relies on Main's `_ready` seeding — confirm by reading `_run()`: it loads `Main.tscn` and lets `_ready()` run, so `GF_SEED` already flows through Task 9's Main.gd change. (If the bot re-seeds `main.state` itself anywhere, route that through `Tune.seed_of(20240620)` too.)

- [ ] **Step 2: Emit the machine-readable metrics line**

In `_run()`, just before the final `if fail_count == 0:` verdict block (after the `PLAYTEST summary:` print, ~line 126), assemble and print the metrics line. Add:

```gdscript
	# Machine-readable line for tools/balance.mjs (the tuning contract). Carries the
	# numbers already computed above — nothing new is simulated. Booleans mirror the
	# hard-gate invariants so the harness can hard-reject without re-deriving them.
	var metrics := {
		"solvent": d1.earned > 0,
		"first_goal_reachable": total_commissions > 0,
		"no_death_spiral": not d1.died_in_crush,
		"no_trivial_dominant": true,
		"gross_earned": gross_earned,
		"commissions_filled": total_commissions,
		"time_to_first_goal_dives": (1 if d1.commission > 0 else (2 if total_commissions > 0 else 99)),
		"min_margin_min": d1.min_margin,
		"max_depth": d1.max_depth,
		"rig_end": s.upgrades["rig"],
	}
	print("PLAYTEST METRICS " + JSON.stringify(metrics))
```

> The booleans here reuse the SAME conditions the existing `_fail(...)` checks already test, so a metrics `solvent:false` always coincides with a `PLAYTEST FAIL`. Keep them in sync if the gate logic changes.

- [ ] **Step 3: Verify the line is emitted and parseable (unset env)**

Run:

```bash
GODOT="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"; "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd
```

Expected: output still ends with `PLAYTEST OK`, and now also contains a `PLAYTEST METRICS {...}` line with `"solvent":true`.

- [ ] **Step 4: Verify GF_SEED produces different-but-reproducible runs**

Run twice with the same seed, then once with a different seed:

```bash
GODOT="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"; GF_SEED=1001 "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd | grep "PLAYTEST METRICS"; GF_SEED=1001 "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd | grep "PLAYTEST METRICS"; GF_SEED=2002 "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd | grep "PLAYTEST METRICS"
```

Expected: the two `GF_SEED=1001` lines are identical to each other; the `GF_SEED=2002` line differs (different spawn layout) — proving per-seed reproducibility for the search.

- [ ] **Step 5: Run the guarded Godot evaluator test from Task 8**

Run (local, with GODOT_BIN set):

```bash
GODOT_BIN="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe" npx vitest run tools/balance.test.mjs
```

Expected: the previously-skipped `makeGodotEvaluator` integration test now PASSES (`agg.clear_rate` is a number).

- [ ] **Step 6: Commit**

```bash
git add games/diver-0001/playtest.gd
git commit -m "feat(diver-0001): emit PLAYTEST METRICS line (the tuning contract)"
```

---

## Task 11: diver balance.spec.json + run the search + apply a config

**Files:**
- Create: `games/diver-0001/balance.spec.json`

- [ ] **Step 1: Write the balance spec**

Create `games/diver-0001/balance.spec.json` — search space targets the flagged "deep Trench commissions are sparse" item (the pre-seeded column reach/density + the crush economy), objective bands keep it winnable-but-not-trivial with a low time-to-first-goal:

```json
{
  "search_space": {
    "preseed_step": { "choices": [48, 56, 64] },
    "preseed_count": { "choices": [12, 16] },
    "base_safe_depth": { "min": 220, "max": 260, "step": 20 },
    "crush_mult": { "choices": [3.0, 4.0] }
  },
  "objective": {
    "invariants": ["solvent", "first_goal_reachable", "no_death_spiral", "no_trivial_dominant"],
    "require": { "clear_rate": 0.6, "no_death_spiral": true, "no_trivial_dominant": true },
    "bands": {
      "clear_rate": { "band": [0.6, 0.9], "weight": 2 },
      "time_to_first_goal_dives": { "band": [1, 2], "weight": 2 },
      "commissions_filled": { "band": [2, 6], "weight": 1 },
      "min_margin_min": { "band": [2, 12], "weight": 1 }
    },
    "aggregators": {
      "min_margin_min": "min",
      "time_to_first_goal_dives": "mean",
      "commissions_filled": "mean"
    },
    "focus_points": ["clear_rate", "time_to_first_goal_dives", "commissions_filled", "min_margin_min"]
  }
}
```

- [ ] **Step 2: Run the search**

Run:

```bash
GODOT_BIN="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe" node tools/balance.mjs games/diver-0001 games/diver-0001/balance.spec.json --seed 1 --seeds 3 --budget 6
```

Expected: the advisory report prints — a best config, a per-focus-point breakdown, and a non-dominated shortlist. (Wall-clock: grid is 3×2×3×2 = 36 configs + 6 random = 42, × 3 seeds ≈ 126 Godot boots — order of minutes. Each playtest boot is a few seconds. If still too slow, drop to `--seeds 2` and note the reduction in the depth_pass record — do NOT silently cap.)

- [ ] **Step 3: Read the shortlist and choose a config (HUMAN judgment)**

Pick a config from the non-dominated shortlist that best fills deep commissions (`commissions_filled` toward the upper band) WITHOUT pushing `clear_rate` to 1.0 (trivial) or `min_margin_min` to a cliff. Do NOT blindly take the lowest composite — weigh the tradeoffs. Record the chosen config and the reason.

- [ ] **Step 4: Apply the chosen config to the diver defaults**

Fold the chosen values into the `const` defaults in `DiveState.gd` / `Main.gd` (so production now ships the tuned values; the `GF_TUNE` seam stays for future searches). Example — if the search picks `preseed_step=48, preseed_count=16, base_safe_depth=240, crush_mult=4.0`, update those `const`s accordingly (only the ones that changed from today's values).

- [ ] **Step 5: Re-validate ALL gates on the applied defaults (env unset)**

Run:

```bash
GODOT="C:/Users/quint/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64_console.exe"; "$GODOT" --headless --path games/diver-0001/ --script res://selftest.gd && "$GODOT" --headless --path games/diver-0001/ --script res://uitest.gd && "$GODOT" --headless --path games/diver-0001/ --script res://playtest.gd
```

Expected: `SELFTEST OK`, `UITEST OK`, `PLAYTEST OK` — and the `PLAYTEST METRICS` line shows `commissions_filled` improved vs. the pre-tuning baseline from Task 10 Step 3.

- [ ] **Step 6: Commit**

```bash
git add games/diver-0001/balance.spec.json games/diver-0001/DiveState.gd games/diver-0001/Main.gd
git commit -m "feat(diver-0001): balance spec + tuned config (deep-commission reachability)"
```

---

## Task 12: Skill prose — deepen + playtest-audit

**Files:**
- Modify: `.claude/skills/deepen/SKILL.md`
- Modify: `.claude/skills/playtest-audit/SKILL.md`

- [ ] **Step 1: Add the balance-tuning subsection to `deepen`**

In `.claude/skills/deepen/SKILL.md`, inside "The method", after step 3 (the TDD/validation-spine step that already mentions re-running `PLAYTEST`), insert a new subsection. Use this exact prose:

```markdown
### Balance tuning (parameter search) — propose a config, don't hand-guess

A pass that changes **tuning** (systemic/run-meta retunes costs, gate depths, drain,
spawn geometry, the ramp) is exactly what makes a game unwinnable or unfair while every
logic assertion stays green. Instead of hand-guessing constants and re-running the bot,
**search** the tuning space against `playtest-audit`'s metrics:

1. **Add the `GF_TUNE`/`GF_SEED` seam** (a `preload`-able `Tune` static, per
   `games/diver-0001/Tune.gd`): the data layer reads each tunable from `Tune.num(...)`
   defaulting to its `const`. UNSET env → identical production behavior. Only seam the
   constants you intend to search.
2. **Emit the metrics contract:** `playtest.gd` must print one `PLAYTEST METRICS {json}`
   line (see `playtest-audit`) carrying the numbers it already computes + the invariant
   booleans.
3. **Declare a `balance.spec.json`** (search space + objective). The objective HARD-REJECTS
   any config failing the playtest invariants, then scores survivors by **distance OUTSIDE
   target BANDS** — never by maximization (maximizing earnings/clear-rate yields a trivially
   easy game). Use **single-player** metrics + a **retention/engagement proxy** (clear-rate
   in a *fair* band, low time-to-first-goal, accruing-but-not-instant economy, a smooth
   difficulty curve). NOT win-rate disparity. The realistic retention bar is top-quartile
   ~7-8% D7 (GameAnalytics def) — do NOT anchor on the old unverified "20%"; and we do not
   literally measure D7, so the proxy is a heuristic.
4. **Run** `node tools/balance.mjs <game-dir> <spec.json>` (each candidate is run across K
   seeds so "clear-rate" is meaningful and the config isn't seed-lucky).
5. **READ the per-focus-point breakdown + the non-dominated shortlist and CHOOSE** — weigh
   the tradeoffs yourself (great pacing vs. borderline economy); do not blindly take the
   lowest composite. The composite is a heuristic sort key, not a verdict.
6. **Apply** the chosen config to the defaults, then re-run the **full** gate set
   (`SELFTEST` / `UITEST` / `PLAYTEST`) with env unset.

**Honesty rule (load-bearing):** the tool **proposes**; the **human playtest decides fun**.
No validated automated fun proxy exists — the search guarantees winnable/fair/well-paced,
never *fun*. An owner "this isn't fun" overrides any proxy win. Record the chosen config +
why in `depth_pass.notes`.
```

- [ ] **Step 2: Verify the deepen edit reads correctly**

Read `.claude/skills/deepen/SKILL.md` around the insertion and confirm step numbering still flows (the new subsection sits between the existing numbered steps as a named subsection, not a renumber).

- [ ] **Step 3: Document the metrics contract in `playtest-audit`**

In `.claude/skills/playtest-audit/SKILL.md`, in the "## Metrics to report" section, append this paragraph:

```markdown
**Machine-readable contract (the tuning signal).** In addition to the human lines and the
`PLAYTEST OK`/`FAIL` verdict, print exactly one final line `PLAYTEST METRICS {json}` carrying
the numbers above **plus** the invariant booleans (`solvent`, `first_goal_reachable`,
`no_death_spiral`, `no_trivial_dominant`) so they coincide with the gate verdict. This line is
the contract `deepen`'s balance-search (`tools/balance.mjs`) consumes: it aggregates the metrics
across K seeds, hard-rejects configs whose invariants are false, and scores the rest against
target bands. The metrics are not just a human dump — they are the tuning oracle. Nothing new is
simulated to produce the line; it serialises what the bot already computed.
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/deepen/SKILL.md .claude/skills/playtest-audit/SKILL.md
git commit -m "docs(skills): deepen balance-tuning subsection + playtest-audit metrics contract"
```

---

## Task 13: Final verification + memory update

- [ ] **Step 1: Full test suite green**

Run: `npx vitest run`
Expected: all tests pass, including the new `tools/balance.test.mjs` (Godot-guarded ones skip in CI).

- [ ] **Step 2: All diver gates green on the tuned defaults**

Run the SELFTEST/UITEST/PLAYTEST one-liner from Task 11 Step 5.
Expected: `SELFTEST OK`, `UITEST OK`, `PLAYTEST OK`.

- [ ] **Step 3: Update the implementation-status memory**

Update `C:\Users\quint\.claude\projects\C--Users-quint-git-GameForge\memory\research-p0-implementation.md` (or a new `research-p1-implementation.md` + a MEMORY.md pointer): record P1-a DONE — `tools/balance.mjs` (+ tests), the `GF_TUNE`/`GF_SEED` seam + `PLAYTEST METRICS` contract, the diver dogfood result (chosen config, before/after `commissions_filled`), and that P1-b (CV defect pre-filter) is next.

- [ ] **Step 4: Confirm nothing unintended is staged**

Run: `git status` and `git log --oneline -13`
Expected: the 12 implementation commits + this plan/spec; the pre-existing uncommitted diver art/`_audit.gd` changes remain separate and uncommitted (do not fold them into P1-a commits).

---

## Notes for the implementer

- **Keep P1-a separable** from the pre-existing uncommitted diver changes (`Main.gd` art wiring, `_audit.gd`, `art/`). Stage only the files each task names.
- **No manifest schema change** in this plan — the tuning artifacts are `balance.spec.json` + tuned defaults + a `depth_pass.notes` line. If you choose to record a `depth_pass`, remember `schema/manifest.schema.json` is `additionalProperties:false` and run `node tools/manifest.mjs validate diver-0001` + `npx vitest run` first.
- **The composite is never a verdict.** Every report surface labels it "engagement proxy (heuristic)" and leads with the per-focus-point breakdown. The human chooses from the shortlist.
- If the search is too slow at 180×5, coarsen the spec (fewer steps/choices) and/or `--seeds 3`; note the reduction. Do not silently cap.
```
