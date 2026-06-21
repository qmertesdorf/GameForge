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
