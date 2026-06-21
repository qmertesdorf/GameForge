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
