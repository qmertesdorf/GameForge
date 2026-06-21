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
