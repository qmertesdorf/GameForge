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
