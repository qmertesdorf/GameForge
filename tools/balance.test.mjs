// tools/balance.test.mjs
import { test, expect, describe } from "vitest";
import { bandPenalty, checkConstraints, aggregateSeeds } from "./balance.mjs";

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
