import { test, expect, describe } from "vitest";
import { scoreGeometry } from "./scene-geom.mjs";

const VP = [720, 1280];
// minimal node factory — visible text/interactive node with given rect
const node = (over = {}) => ({
  path: "/root/Main/N", class: "Label", rect: [0, 0, 100, 30],
  paint: 0, z_index: 0, mod_a: 1, fill_a: null, has_texture: false,
  texture_null: false, interactive: false, is_text: true, visible: true,
  ...over,
});

describe("scoreGeometry — off-viewport", () => {
  test("a fully on-screen text node is clean", () => {
    const r = scoreGeometry([node({ rect: [10, 10, 100, 30] })], VP);
    expect(r.ok).toBe(true);
    expect(r.hard).toEqual([]);
    expect(r.checked).toBe(1);
  });

  test("a button clipped past the right edge is a hard finding", () => {
    const r = scoreGeometry([node({ class: "Button", interactive: true, is_text: false, rect: [680, 100, 100, 40] })], VP);
    expect(r.ok).toBe(false);
    expect(r.hard).toHaveLength(1);
    expect(r.hard[0]).toMatchObject({ kind: "offscreen", clippedPx: 60, fully: false });
  });

  test("a node entirely off-screen is flagged fully", () => {
    const r = scoreGeometry([node({ rect: [800, 100, 100, 40] })], VP);
    expect(r.hard[0]).toMatchObject({ kind: "offscreen", fully: true });
  });

  test("clipTol tolerates a 2px bleed but not a 3px one", () => {
    expect(scoreGeometry([node({ rect: [-2, 10, 100, 30] })], VP).ok).toBe(true);
    expect(scoreGeometry([node({ rect: [-3, 10, 100, 30] })], VP).ok).toBe(false);
  });

  test("a clipped NON-victim (decorative) node is not a hard off-viewport finding", () => {
    const r = scoreGeometry([node({ is_text: false, interactive: false, rect: [680, 100, 100, 40] })], VP);
    expect(r.hard).toEqual([]);
  });

  test("invisible nodes are skipped", () => {
    const r = scoreGeometry([node({ rect: [800, 100, 100, 40], visible: false })], VP);
    expect(r.checked).toBe(0);
    expect(r.hard).toEqual([]);
  });
});
