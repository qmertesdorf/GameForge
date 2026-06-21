// tools/balance.test.mjs
import { execFileSync } from "node:child_process";
import { test, expect, describe } from "vitest";
import { bandPenalty, checkConstraints, aggregateSeeds, scoreCandidate, nonDominated, mulberry32, paramValues, enumerateCandidates, parseMetricsLine } from "./balance.mjs";

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

import { runSearch, makeGodotEvaluator, coordinateDescent } from "./balance.mjs";

describe("coordinateDescent (direct, synthetic scoreFn)", () => {
  const space1 = { x: { min: 0, max: 10, step: 1 } };
  const scoreFn1 = (p) => ({ composite: Math.abs(p.x - 7) });
  test("descends from a start point to the local optimum", () => {
    expect(coordinateDescent({ x: 2 }, space1, scoreFn1).x).toBe(7);
  });
  test("a start already at the optimum stays put", () => {
    expect(coordinateDescent({ x: 7 }, space1, scoreFn1).x).toBe(7);
  });
  test("refines every axis on a multi-param space", () => {
    const space2 = { x: { min: 0, max: 5, step: 1 }, y: { min: 0, max: 5, step: 1 } };
    const sf = (p) => ({ composite: Math.abs(p.x - 3) + Math.abs(p.y - 4) });
    expect(coordinateDescent({ x: 0, y: 0 }, space2, sf)).toEqual({ x: 3, y: 4 });
  });
});

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

function godotAvailable() {
  try { execFileSync(process.env.GODOT_BIN || "godot", ["--version"], { stdio: ["ignore", "pipe", "pipe"] }); return true; }
  catch { return false; }
}
const hasGodot = godotAvailable();

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
