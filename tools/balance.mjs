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

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

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

// --- aggregators for numeric metrics across seeds ---
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

// --- deterministic PRNG (mulberry32) so the whole search is reproducible from --seed. ---
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// --- discrete value list for one param: a stepped [min,max] range (inclusive) or ---
// --- an explicit choices list. ---
export function paramValues(spec) {
  if (Array.isArray(spec.choices)) return [...spec.choices];
  const out = [];
  // guard against float drift on the last step
  for (let v = spec.min; v <= spec.max + 1e-9; v += spec.step) out.push(Math.round(v * 1e6) / 1e6);
  return out;
}

// --- full grid (cartesian product) + `random` extra random points (deterministic). ---
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

// Extract the single machine-readable metrics object the bot prints. Tolerant: a
// crashed/incomplete run (no line, bad JSON) returns null and the runner treats it
// as a failed seed.
export function parseMetricsLine(stdout) {
  const m = String(stdout).match(/PLAYTEST METRICS (\{.*\})/);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
}

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
      console.log(`    ${k}: penalty ${(res.best.penalties[k] ?? 0).toFixed(3)}  value ${res.best.agg[k] ?? "(n/a)"}`);
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
