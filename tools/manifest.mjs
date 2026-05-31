import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Ajv from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(__dirname, "..");
const SCHEMA_PATH = join(REPO_ROOT, "schema", "manifest.schema.json");

let _validator;
function getValidator() {
  if (!_validator) {
    const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
    const ajv = new Ajv({ allErrors: true });
    addFormats(ajv);
    _validator = ajv.compile(schema);
  }
  return _validator;
}

export function validate(manifest) {
  const v = getValidator();
  const valid = v(manifest);
  return {
    valid,
    errors: valid ? [] : v.errors.map((e) => `${e.instancePath || "/"} ${e.message}`)
  };
}

export function newManifest({ id, name } = {}, now = new Date().toISOString()) {
  if (!id || !name) throw new Error("newManifest requires both id and name");
  return {
    id,
    name,
    created_at: now,
    updated_at: now,
    status: "concept",
    concept: {},
    build: {},
    assets: [],
    validation: { issues: [] },
    _reserved: { compliance: null, store: null, maintenance: null }
  };
}

export const STATUSES = ["concept", "generated", "validated", "playable", "failed"];

// Legal forward transitions. Any non-terminal status may also go to "failed".
const TRANSITIONS = {
  concept: ["generated", "failed"],
  generated: ["validated", "failed"],
  validated: ["playable", "failed"],
  playable: [],
  failed: []
};

export function setStatus(manifest, status, now = new Date().toISOString()) {
  if (!STATUSES.includes(status)) {
    throw new Error(`unknown status: ${status}`);
  }
  if (status === manifest.status) {
    return { ...manifest, updated_at: now };
  }
  const allowed = TRANSITIONS[manifest.status] ?? [];
  if (!allowed.includes(status)) {
    throw new Error(`illegal transition: ${manifest.status} -> ${status}`);
  }
  return { ...manifest, status, updated_at: now };
}

function deepMerge(base, patch) {
  if (Array.isArray(patch)) return patch.slice();
  if (patch && typeof patch === "object") {
    const out = Array.isArray(base) ? {} : { ...(base ?? {}) };
    for (const [k, v] of Object.entries(patch)) {
      const canRecurse =
        v && typeof v === "object" && !Array.isArray(v) &&
        base?.[k] && typeof base[k] === "object" && !Array.isArray(base[k]);
      out[k] = canRecurse ? deepMerge(base[k], v) : Array.isArray(v) ? v.slice() : v;
    }
    return out;
  }
  return patch;
}

export function merge(manifest, patch, now = new Date().toISOString()) {
  const merged = deepMerge(manifest, patch);
  merged.updated_at = now;
  return merged;
}
