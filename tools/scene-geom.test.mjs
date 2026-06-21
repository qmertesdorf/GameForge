import { test, expect, describe } from "vitest";
import { scoreGeometry, sceneGeometryFile } from "./scene-geom.mjs";
import { execFileSync } from "node:child_process";

function godotAvailable() {
  try {
    execFileSync(process.env.GODOT_BIN || "godot", ["--version"], { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch { return false; }
}
const hasGodot = godotAvailable();

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

  test("bboxes expose a flagged finding's kind/path/rect for lens hand-off", () => {
    const r = scoreGeometry([node({ class: "Button", interactive: true, is_text: false, rect: [680, 100, 100, 40] })], VP);
    expect(r.bboxes).toEqual([{ kind: "offscreen", path: "/root/Main/N", rect: [680, 100, 100, 40] }]);
  });

  test("an empty node list is clean", () => {
    const r = scoreGeometry([], VP);
    expect(r).toMatchObject({ ok: true, checked: 0, hard: [], advisory: [], bboxes: [] });
  });
});

describe("scoreGeometry — occlusion", () => {
  const panel = (over = {}) => node({
    path: "/root/Main/Panel", class: "Panel", is_text: false, interactive: false,
    fill_a: 0.95, rect: [0, 0, 720, 1280], paint: 5, ...over,
  });

  test("a text node fully under an opaque higher-paint panel is hard-occluded", () => {
    const label = node({ path: "/root/Main/Label", rect: [100, 100, 200, 40], paint: 1 });
    const r = scoreGeometry([label, panel()], VP);
    expect(r.ok).toBe(false);
    expect(r.hard[0]).toMatchObject({ kind: "occluded" });
    expect(r.hard[0].victim.path).toBe("/root/Main/Label");
    expect(r.hard[0].occluder.path).toBe("/root/Main/Panel");
  });

  test("a node under a 0.5-alpha scrim is NOT occluded (scrim is not opaque)", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const r = scoreGeometry([label, panel({ fill_a: 0.5 })], VP);
    expect(r.hard).toEqual([]);
  });

  test("opaqueAlpha boundary: 0.92 panel occludes at default, not at a 0.95 threshold", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const nodes = [label, panel({ fill_a: 0.92 })];
    expect(scoreGeometry(nodes, VP).ok).toBe(false);                     // default 0.9
    expect(scoreGeometry(nodes, VP, { opaqueAlpha: 0.95 }).ok).toBe(true);
  });

  test("a LOWER-paint opaque panel does NOT occlude the text above it", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 9 });
    const r = scoreGeometry([label, panel({ paint: 1 })], VP);
    expect(r.hard).toEqual([]);
  });

  test("mod_a knocks a textured occluder below the opaque bar", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 1 });
    const sprite = node({ path: "/root/Main/Cover", class: "Sprite2D", is_text: false, has_texture: true, mod_a: 0.4, rect: [0, 0, 720, 1280], paint: 5 });
    expect(scoreGeometry([label, sprite], VP).hard).toEqual([]);
  });

  test("partial overlap (not full containment) is advisory, not hard", () => {
    const label = node({ rect: [100, 100, 400, 40], paint: 1 });
    const half = panel({ rect: [300, 0, 720, 1280], paint: 5 }); // covers right half only
    const r = scoreGeometry([label, half], VP);
    expect(r.hard).toEqual([]);
    expect(r.advisory.some((a) => a.kind === "overlap")).toBe(true);
  });

  test("z_index outranks paint order", () => {
    const label = node({ rect: [100, 100, 200, 40], paint: 9, z_index: 0 });
    const r = scoreGeometry([label, panel({ paint: 1, z_index: 1 })], VP);
    expect(r.hard[0]).toMatchObject({ kind: "occluded" });
  });

  test("a fully-contained NON-victim node is an overlap advisory, not hard-occluded", () => {
    const deco = node({ path: "/root/Main/Deco", class: "ColorRect", is_text: false, interactive: false, rect: [100, 100, 50, 50], paint: 1 });
    const r = scoreGeometry([deco, panel()], VP);
    expect(r.hard).toEqual([]);
    expect(r.advisory).toEqual([{ kind: "overlap", path: "/root/Main/Deco", class: "ColorRect", rect: [100, 100, 50, 50], over: "/root/Main/Panel" }]);
  });
});

describe("scoreGeometry — missing-texture", () => {
  test("a visible texture-requiring node with no texture is advisory", () => {
    const r = scoreGeometry([node({ path: "/root/Main/Icon", class: "TextureRect", is_text: false, texture_null: true, rect: [10, 10, 44, 44] })], VP);
    expect(r.hard).toEqual([]);
    expect(r.advisory).toHaveLength(1);
    expect(r.advisory[0]).toMatchObject({ kind: "missing-texture", path: "/root/Main/Icon" });
  });

  test("missing-texture findings appear in bboxes for lens hand-off", () => {
    const r = scoreGeometry([node({ class: "Sprite2D", is_text: false, texture_null: true, rect: [10, 10, 44, 44] })], VP);
    expect(r.bboxes.some((b) => b.kind === "missing-texture" && b.rect[2] === 44)).toBe(true);
  });
});

describe("sceneGeometryFile (Godot integration, guarded)", () => {
  test.skipIf(!hasGodot)("diver-0001 chrome is geometrically clean", () => {
    const r = sceneGeometryFile("games/diver-0001");
    expect(r.checked).toBeGreaterThan(0);   // it has Control chrome to see
    expect(r.hard).toEqual([]);             // clip/occlusion bugs were already fixed
  });
});
