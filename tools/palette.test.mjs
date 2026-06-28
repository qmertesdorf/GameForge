import { test, expect, describe } from "vitest";
import { DB32 } from "./palette.mjs";
import { hexToRgb } from "./color.mjs";

describe("DB32 palette", () => {
  test("has 32 entries", () => {
    expect(DB32.length).toBe(32);
  });
  test("every entry is a valid hex colour", () => {
    for (const hex of DB32) expect(() => hexToRgb(hex)).not.toThrow();
  });
  test("has no duplicate colours", () => {
    expect(new Set(DB32.map((h) => h.toLowerCase())).size).toBe(32);
  });
});
