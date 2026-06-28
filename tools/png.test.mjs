import { test, expect, describe } from "vitest";
import { decodePng, encodePng } from "./png.mjs";

describe("encodePng", () => {
  for (const ch of [3, 4]) {
    test(`round-trips ${ch}-channel data through decodePng`, () => {
      const w = 5, h = 4;
      const data = new Uint8Array(w * h * ch);
      for (let i = 0; i < data.length; i++) data[i] = (i * 7) & 255;
      const png = encodePng(w, h, ch, data);
      const out = decodePng(png);
      expect(out.width).toBe(w);
      expect(out.height).toBe(h);
      expect(out.channels).toBe(ch);
      expect(Array.from(out.data)).toEqual(Array.from(data));
    });
  }
  test("rejects an unsupported channel count", () => {
    expect(() => encodePng(1, 1, 2, new Uint8Array(2))).toThrow(/3 or 4 channels/);
  });
});
