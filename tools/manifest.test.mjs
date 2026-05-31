import { test, expect, describe } from "vitest";
import { validate, newManifest, setStatus, STATUSES, merge } from "./manifest.mjs";

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

describe("setStatus", () => {
  const base = () => newManifest({ id: "a", name: "A" }, "2026-05-30T12:00:00Z");

  test("exposes the five POC statuses", () => {
    expect(STATUSES).toEqual(["concept", "generated", "validated", "playable", "failed"]);
  });

  test("advances along the legal path and stamps updated_at", () => {
    const m = setStatus(base(), "generated", "2026-05-30T13:00:00Z");
    expect(m.status).toBe("generated");
    expect(m.updated_at).toBe("2026-05-30T13:00:00Z");
    expect(m.created_at).toBe("2026-05-30T12:00:00Z"); // unchanged
  });

  test("allows any non-terminal status to fail", () => {
    expect(setStatus(base(), "failed").status).toBe("failed");
  });

  test("rejects skipping a step", () => {
    expect(() => setStatus(base(), "playable")).toThrow(/concept -> playable/);
  });

  test("rejects an unknown status", () => {
    expect(() => setStatus(base(), "shipped")).toThrow(/unknown status/);
  });

  test("rejects leaving a terminal status", () => {
    const failed = setStatus(base(), "failed");
    expect(() => setStatus(failed, "generated")).toThrow();
  });

  test("treats re-setting the same status as a no-op", () => {
    expect(setStatus(base(), "concept").status).toBe("concept");
  });
});

describe("merge", () => {
  const base = () => newManifest({ id: "a", name: "A" }, "2026-05-30T12:00:00Z");

  test("deep-merges a nested block and stamps updated_at", () => {
    const m = merge(base(), { concept: { genre: "endless runner", mechanics: ["jump"] } }, "2026-05-30T13:00:00Z");
    expect(m.concept.genre).toBe("endless runner");
    expect(m.concept.mechanics).toEqual(["jump"]);
    expect(m.updated_at).toBe("2026-05-30T13:00:00Z");
    expect(m.status).toBe("concept"); // untouched
  });

  test("replaces arrays wholesale rather than concatenating", () => {
    const once = merge(base(), { concept: { mechanics: ["jump"] } });
    const twice = merge(once, { concept: { mechanics: ["jump", "double-jump"] } });
    expect(twice.concept.mechanics).toEqual(["jump", "double-jump"]);
  });

  test("does not mutate the input manifest", () => {
    const original = base();
    merge(original, { concept: { genre: "match-3" } });
    expect(original.concept.genre).toBeUndefined();
  });
});
