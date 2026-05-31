import { test, expect, describe } from "vitest";
import { validate, newManifest } from "./manifest.mjs";

// A hand-built, fully-valid manifest used as the baseline across tests.
function validManifest() {
  return {
    id: "runner-0001",
    name: "Neon Dash",
    created_at: "2026-05-30T12:00:00Z",
    updated_at: "2026-05-30T12:00:00Z",
    status: "playable",
    concept: {
      genre: "endless runner",
      core_loop: "tap to jump, avoid obstacles",
      mechanics: ["jump", "score"],
      art_direction: "neon vector, dark background",
      target_platforms: ["android"],
      differentiation_notes: "single-tap control"
    },
    build: {
      engine: "godot",
      engine_version: "4.6.3.stable",
      language: "gdscript",
      project_path: "games/runner-0001/",
      addons: [],
      export_presets: ["android"]
    },
    assets: [{ type: "sprite", name: "player", source: "placeholder", origin: "primitive" }],
    validation: { opens_in_editor: true, runs: true, core_loop_functional: true, issues: [] },
    _reserved: { compliance: null, store: null, maintenance: null }
  };
}

describe("validate", () => {
  test("accepts a fully-formed manifest", () => {
    expect(validate(validManifest())).toEqual({ valid: true, errors: [] });
  });

  test("rejects an unknown status", () => {
    const m = validManifest();
    m.status = "shipped";
    const result = validate(m);
    expect(result.valid).toBe(false);
    expect(result.errors.join(" ")).toMatch(/status/);
  });

  test("rejects a missing required top-level key", () => {
    const m = validManifest();
    delete m._reserved;
    expect(validate(m).valid).toBe(false);
  });
});

describe("newManifest", () => {
  test("produces a schema-valid skeleton with status=concept", () => {
    const m = newManifest({ id: "runner-0001", name: "Neon Dash" }, "2026-05-30T12:00:00Z");
    expect(m.id).toBe("runner-0001");
    expect(m.name).toBe("Neon Dash");
    expect(m.status).toBe("concept");
    expect(m.created_at).toBe("2026-05-30T12:00:00Z");
    expect(m.updated_at).toBe("2026-05-30T12:00:00Z");
    expect(m._reserved).toEqual({ compliance: null, store: null, maintenance: null });
    expect(validate(m).valid).toBe(true);
  });

  test("throws when id or name is missing", () => {
    expect(() => newManifest({ id: "x" })).toThrow();
    expect(() => newManifest({ name: "y" })).toThrow();
  });
});
