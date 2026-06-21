// tools/balance.test.mjs
import { test, expect, describe } from "vitest";
import { bandPenalty, checkConstraints, aggregateSeeds, scoreCandidate } from "./balance.mjs";

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
