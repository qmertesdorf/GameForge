# GameForge POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the GameForge POC — three Claude Agent Skills (`concept`, `builder`, `validator`) plus a manifest tool that together turn a one-line prompt into a playable Godot game, and prove the loop end-to-end on an endless runner.

**Architecture:** A per-title JSON **manifest** is the single source of truth (the "spine"). A small Node CLI (`tools/manifest.mjs`) owns all manifest reads/writes, status transitions, and schema validation — this is the only component with real logic, so it gets full TDD. The three skills are prose `SKILL.md` files that drive Claude through concept → build → validate, each reading and writing the manifest via the CLI. Godot 4.x runs the generated games (headless for automated checks, editor for human playtest).

**Tech Stack:** Node.js 24 (ESM, `.mjs`) · Vitest + Ajv (manifest tests/validation) · Godot 4.x stable (GDScript, text `.tscn` scenes) · Windows/PowerShell dev host · git as the cross-machine transfer mechanism.

---

## File Structure

What this plan creates or modifies, and each file's single responsibility:

| File | Responsibility |
|------|----------------|
| `package.json` | Node project manifest; declares ESM (`"type": "module"`) and the `test` script. |
| `schema/manifest.schema.json` | JSON Schema (the §5 contract) that `validate()` enforces. The shape of a title manifest. |
| `tools/manifest.mjs` | The manifest library + thin CLI: `newManifest`, `setStatus`, `merge`, `validate`, file helpers, and `create/set-status/merge/validate` commands. Only file with logic. |
| `tools/manifest.test.mjs` | Vitest unit tests for every exported manifest function. |
| `tools/harness.test.mjs` | One-line canary test proving the Vitest runner is wired up. |
| `tools/skills.test.mjs` | Structural test: every required skill folder has a `SKILL.md` with valid `name`/`description` frontmatter. |
| `.claude/skills/concept/SKILL.md` | Prompt → structured `manifest.concept`; `status = "concept"`. |
| `.claude/skills/builder/SKILL.md` | `manifest.concept` → runnable Godot project under `games/<id>/`; `manifest.build`; `status = "generated"`. |
| `.claude/skills/validator/SKILL.md` | Headless Godot checks + human-playtest protocol → `manifest.validation`; `status = "validated"`/`"playable"`/`"failed"`. |
| `manifests/.gitkeep` | Keeps the (otherwise empty) manifest directory in git. Real manifests land here as `<id>.json`. |
| `games/.gitkeep` | Keeps the generated-projects directory in git. |
| `README.md` | Repo orientation + the **pinned Godot version** (source of truth for `build.engine_version`). |
| `.gitignore` | Already present (§11); add `node_modules/`. |

---

## Task 0: Install & verify Godot 4.x (hard prerequisite)

This is environment setup, not code — no TDD. **Nothing downstream can be validated until `godot --version` works.** Godot is currently NOT installed (verified during brainstorming: not on PATH, Program Files, Steam, scoop, or winget).

**Files:**
- Modify: `README.md` (created in Task 1 — record the pinned version there; if running Task 0 first, just capture the version string and add it to README during Task 1)

- [ ] **Step 1: Install Godot 4.x via winget**

Run in PowerShell:

```powershell
winget install --exact --id GodotEngine.GodotEngine --accept-source-agreements --accept-package-agreements
```

Expected: winget reports "Successfully installed". (Use the standard, non-Mono package — the POC is GDScript-only, no C#.)

- [ ] **Step 2: Put the Godot binary on PATH and confirm the version**

winget installs the editor as something like `Godot_v4.x-stable_win64.exe`. Find it and create a stable `godot` alias on PATH. Run:

```powershell
$exe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine*" -Recurse -Filter "Godot_v*_win64.exe" | Select-Object -First 1
Write-Output $exe.FullName
& $exe.FullName --version
```

Expected: prints a version like `4.4.1.stable.official.<hash>`. **Record this exact version string** — it becomes the pinned `build.engine_version` and goes in `README.md` (Task 1, Step 6).

Create a `godot.cmd` shim on PATH so later tasks can call `godot` directly:

```powershell
$binDir = "$env:LOCALAPPDATA\GameForgeBin"
New-Item -ItemType Directory -Force $binDir | Out-Null
Set-Content "$binDir\godot.cmd" "@`"$($exe.FullName)`" %*"
[Environment]::SetEnvironmentVariable("Path", "$env:Path;$binDir", "User")
$env:Path = "$env:Path;$binDir"
godot --version
```

Expected: `godot --version` prints the same version string.

- [ ] **Step 3: Verify a blank project runs headless from the CLI**

```powershell
$tmp = "$env:TEMP\godot-smoke"
New-Item -ItemType Directory -Force $tmp | Out-Null
Set-Content "$tmp\project.godot" "config_version=5`n`n[application]`n`nconfig/name=`"smoke`"`n"
godot --headless --path $tmp --quit-after 5
Write-Output "exit code: $LASTEXITCODE"
Remove-Item -Recurse -Force $tmp
```

Expected: Godot boots headless, runs ~5 frames, quits with **exit code 0** and no `SCRIPT ERROR` / `ERROR` lines about missing project. This is exactly the check the `validator` skill will automate.

- [ ] **Step 4: Install Android export templates (for APK export — NOT required for POC validation)**

> **Why this is non-blocking:** POC success (§2) is "opens and runs in the engine" + "playable in editor" — neither needs export templates. Templates are only needed to build an actual `.apk`. Install them so the path is proven, but if the download is flaky, **do not let it block the rest of the plan** — note it and move on.

Download the templates `.tpz` matching the EXACT installed version (replace `4.4.1` with your version from Step 2):

```powershell
$ver = "4.4.1"   # <-- the version from Step 2, without the ".stable..." suffix
$tpz = "$env:TEMP\godot_templates.tpz"
Invoke-WebRequest "https://github.com/godotengine/godot/releases/download/$ver-stable/Godot_v$ver-stable_export_templates.tpz" -OutFile $tpz
$dest = "$env:APPDATA\Godot\export_templates\$ver.stable"
New-Item -ItemType Directory -Force $dest | Out-Null
Expand-Archive -Path $tpz -DestinationPath "$env:TEMP\godot_tpl" -Force
Copy-Item "$env:TEMP\godot_tpl\templates\*" $dest -Recurse -Force
Get-ChildItem $dest | Select-Object -First 3 Name
Remove-Item -Recurse -Force "$env:TEMP\godot_tpl", $tpz
```

Expected: `$dest` contains files like `android_release.apk`, `version.txt`. If the download 404s or the network blocks it, record "Android export templates: deferred" and continue.

- [ ] **Step 5: Commit nothing**

Task 0 produces no repo files (installs live outside the repo). The pinned version string gets committed in Task 1. No commit here.

---

## Task 1: Repo scaffold + Vitest harness

**Files:**
- Create: `package.json`
- Create: `tools/harness.test.mjs`
- Create: `manifests/.gitkeep`
- Create: `games/.gitkeep`
- Create: `README.md`
- Modify: `.gitignore` (add `node_modules/`)

- [ ] **Step 1: Add `node_modules/` to `.gitignore`**

Append to `C:\Users\quint\git\mobile-gen\.gitignore` (the file already has the §11 Godot entries):

```gitignore

# Node
node_modules/
```

- [ ] **Step 2: Create `package.json`**

`C:\Users\quint\git\mobile-gen\package.json`:

```json
{
  "name": "gameforge",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "description": "GameForge POC — skills + manifest tooling that turn a prompt into a playable Godot game.",
  "scripts": {
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "^3.0.0",
    "ajv": "^8.17.1",
    "ajv-formats": "^3.0.1"
  }
}
```

- [ ] **Step 3: Install dependencies**

Run: `npm install`
Expected: creates `node_modules/` and `package-lock.json`; no errors.

- [ ] **Step 4: Write the harness canary test (failing-then-passing in one shot)**

`C:\Users\quint\git\mobile-gen\tools\harness.test.mjs`:

```javascript
import { test, expect } from "vitest";

test("vitest harness is wired up", () => {
  expect(1 + 1).toBe(2);
});
```

- [ ] **Step 5: Run the test to confirm the runner works**

Run: `npm test`
Expected: PASS — `1 passed`. This proves Vitest is correctly configured before any real logic exists.

- [ ] **Step 6: Create directory placeholders and README**

Create empty `C:\Users\quint\git\mobile-gen\manifests\.gitkeep` and `C:\Users\quint\git\mobile-gen\games\.gitkeep` (both empty files).

`C:\Users\quint\git\mobile-gen\README.md` (replace `4.4.1.stable...` with the version from Task 0, Step 2):

```markdown
# GameForge (POC)

An AI pipeline that turns a one-line prompt into a playable mobile game, built as Claude Agent Skills. See `docs/superpowers/specs/2026-05-30-gameforge-poc-design.html` for the design.

## Pinned Godot version

`4.4.1.stable` — **source of truth** for every manifest's `build.engine_version`. Both machines must match (§11). Update here and in existing manifests if you bump it.

## Layout

- `.claude/skills/` — the `concept`, `builder`, `validator` skills.
- `manifests/<id>.json` — one manifest per title (the spine; §5).
- `games/<id>/` — generated Godot projects.
- `tools/manifest.mjs` — the manifest CLI (`create` / `set-status` / `merge` / `validate`).
- `schema/manifest.schema.json` — the manifest schema.

## The loop

prompt → `concept` → `builder` → `validator` → human playtest → edit the responsible `SKILL.md` → repeat across ≥3 genres. The deliverable is **better skills**, not the games.

## Manifest CLI

```
node tools/manifest.mjs create <id> "<name>"     # new skeleton, status=concept
node tools/manifest.mjs merge  <id> '<json>'      # deep-merge a partial (e.g. the concept block)
node tools/manifest.mjs set-status <id> <status>  # concept→generated→validated→playable | →failed
node tools/manifest.mjs validate <id>             # schema-check; exit 1 if invalid
```

## Tests

`npm test`
```

- [ ] **Step 7: Commit**

```bash
git add .gitignore package.json package-lock.json tools/harness.test.mjs manifests/.gitkeep games/.gitkeep README.md
git commit -m "chore: scaffold node/vitest harness and repo layout"
```

---

## Task 2: Manifest schema + `validate()`

**Files:**
- Create: `schema/manifest.schema.json`
- Create: `tools/manifest.mjs`
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write the failing test**

`C:\Users\quint\git\mobile-gen\tools\manifest.test.mjs`:

```javascript
import { test, expect, describe } from "vitest";
import { validate } from "./manifest.mjs";

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
      engine_version: "4.4.1.stable",
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — cannot resolve `./manifest.mjs` (or `validate` is not a function).

- [ ] **Step 3: Write the schema**

`C:\Users\quint\git\mobile-gen\schema\manifest.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gameforge.local/manifest.schema.json",
  "title": "GameForge Title Manifest",
  "type": "object",
  "additionalProperties": false,
  "required": ["id", "name", "created_at", "updated_at", "status", "concept", "build", "assets", "validation", "_reserved"],
  "properties": {
    "id": { "type": "string", "minLength": 1 },
    "name": { "type": "string", "minLength": 1 },
    "created_at": { "type": "string", "format": "date-time" },
    "updated_at": { "type": "string", "format": "date-time" },
    "status": { "enum": ["concept", "generated", "validated", "playable", "failed"] },
    "concept": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "genre": { "type": "string" },
        "core_loop": { "type": "string" },
        "mechanics": { "type": "array", "items": { "type": "string" } },
        "art_direction": { "type": "string" },
        "target_platforms": { "type": "array", "items": { "type": "string" } },
        "differentiation_notes": { "type": "string" }
      }
    },
    "build": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "engine": { "type": "string" },
        "engine_version": { "type": "string" },
        "language": { "type": "string" },
        "project_path": { "type": "string" },
        "addons": { "type": "array" },
        "export_presets": { "type": "array", "items": { "type": "string" } }
      }
    },
    "assets": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "type": { "type": "string" },
          "name": { "type": "string" },
          "source": { "type": "string" },
          "origin": { "type": "string" }
        }
      }
    },
    "validation": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "opens_in_editor": { "type": "boolean" },
        "runs": { "type": "boolean" },
        "core_loop_functional": { "type": "boolean" },
        "issues": { "type": "array", "items": { "type": "string" } }
      }
    },
    "_reserved": {
      "type": "object",
      "properties": {
        "compliance": {},
        "store": {},
        "maintenance": {}
      }
    }
  }
}
```

- [ ] **Step 4: Write the minimal implementation**

`C:\Users\quint\git\mobile-gen\tools\manifest.mjs`:

```javascript
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Ajv from "ajv";
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — 3 passed.

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat: manifest schema and validate()"
```

---

## Task 3: `newManifest()`

**Files:**
- Modify: `tools/manifest.mjs`
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/manifest.test.mjs` (add `newManifest` to the existing import from `./manifest.mjs`):

```javascript
import { newManifest } from "./manifest.mjs";

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
```

> Note: keep a single `import { validate, newManifest } from "./manifest.mjs";` line — merge the names rather than duplicating the import.

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — `newManifest is not a function`.

- [ ] **Step 3: Write the minimal implementation**

Add to `tools/manifest.mjs`:

```javascript
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — all newManifest + validate tests green.

- [ ] **Step 5: Commit**

```bash
git add tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat: newManifest() skeleton builder"
```

---

## Task 4: `setStatus()` with transition rules

Legal forward path: `concept → generated → validated → playable`. From any non-terminal status you may jump to `failed`. `playable` and `failed` are terminal. Re-setting the current status is a no-op (allowed).

**Files:**
- Modify: `tools/manifest.mjs`
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/manifest.test.mjs` (add `setStatus` and `STATUSES` to the import):

```javascript
import { setStatus, STATUSES } from "./manifest.mjs";

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — `setStatus is not a function` / `STATUSES` undefined.

- [ ] **Step 3: Write the minimal implementation**

Add to `tools/manifest.mjs`:

```javascript
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — all setStatus tests green.

- [ ] **Step 5: Commit**

```bash
git add tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat: setStatus() with transition rules"
```

---

## Task 5: `merge()` for block updates

Skills fill the manifest one block at a time (concept, then build, then validation). `merge()` deep-merges a partial patch and re-stamps `updated_at`. Objects merge recursively; arrays replace wholesale (so re-running a skill overwrites, not appends).

**Files:**
- Modify: `tools/manifest.mjs`
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/manifest.test.mjs` (add `merge` to the import):

```javascript
import { merge } from "./manifest.mjs";

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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — `merge is not a function`.

- [ ] **Step 3: Write the minimal implementation**

Add to `tools/manifest.mjs`:

```javascript
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — all merge tests green.

- [ ] **Step 5: Commit**

```bash
git add tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat: merge() for incremental block updates"
```

---

## Task 6: File helpers + CLI

The skills don't import the module — they shell out to `node tools/manifest.mjs <cmd>`. This task adds file read/write helpers and the CLI dispatcher, tested by spawning the CLI against a temp manifest directory (via the `GAMEFORGE_MANIFEST_DIR` env override) so tests never touch the real `manifests/`.

**Files:**
- Modify: `tools/manifest.mjs`
- Test: `tools/manifest.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `tools/manifest.test.mjs`:

```javascript
import { test as cliTest } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync as rf, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pjoin } from "node:path";
import { fileURLToPath as f2p } from "node:url";

const CLI = f2p(new URL("./manifest.mjs", import.meta.url));

function runCli(args, dir) {
  return execFileSync(process.execPath, [CLI, ...args], {
    env: { ...process.env, GAMEFORGE_MANIFEST_DIR: dir },
    encoding: "utf8"
  });
}

describe("CLI", () => {
  test("create → merge → set-status → validate round-trips on disk", () => {
    const dir = mkdtempSync(pjoin(tmpdir(), "gf-"));
    try {
      runCli(["create", "runner-0001", "Neon Dash"], dir);
      runCli(["merge", "runner-0001", JSON.stringify({ concept: { genre: "endless runner" } })], dir);
      runCli(["set-status", "runner-0001", "generated"], dir);
      const out = runCli(["validate", "runner-0001"], dir);
      expect(out).toMatch(/OK/);

      const m = JSON.parse(rf(pjoin(dir, "runner-0001.json"), "utf8"));
      expect(m.status).toBe("generated");
      expect(m.concept.genre).toBe("endless runner");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("validate exits non-zero on a hand-corrupted manifest", () => {
    const dir = mkdtempSync(pjoin(tmpdir(), "gf-"));
    try {
      runCli(["create", "bad-0001", "Bad"], dir);
      // Corrupt the status directly on disk, then validate.
      const p = pjoin(dir, "bad-0001.json");
      const m = JSON.parse(rf(p, "utf8"));
      m.status = "shipped";
      require("node:fs").writeFileSync(p, JSON.stringify(m));
      expect(() => runCli(["validate", "bad-0001"], dir)).toThrow();
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
```

> Note: `require` is not available in ESM. Replace the corrupt-write line with an imported `writeFileSync`. Add `writeFileSync` to the existing `node:fs` import group at the top of the test file and use it directly:
> ```javascript
> import { writeFileSync } from "node:fs";
> // ...
> writeFileSync(p, JSON.stringify(m));
> ```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: FAIL — the CLI has no command dispatcher yet; `validate runner-0001` errors or prints nothing matching `/OK/`.

- [ ] **Step 3: Write the minimal implementation**

Update the top-of-file imports in `tools/manifest.mjs` to add `writeFileSync`:

```javascript
import { readFileSync, writeFileSync } from "node:fs";
```

Add the manifest-dir resolution near the other path constants (just below `SCHEMA_PATH`):

```javascript
const MANIFEST_DIR = process.env.GAMEFORGE_MANIFEST_DIR || join(REPO_ROOT, "manifests");
```

Add the file helpers and CLI at the **end** of `tools/manifest.mjs`:

```javascript
export function manifestPath(id) {
  return join(MANIFEST_DIR, `${id}.json`);
}

export function readManifest(id) {
  return JSON.parse(readFileSync(manifestPath(id), "utf8"));
}

export function writeManifest(manifest) {
  const p = manifestPath(manifest.id);
  writeFileSync(p, JSON.stringify(manifest, null, 2) + "\n");
  return p;
}

function cli(argv) {
  const [cmd, ...rest] = argv;
  switch (cmd) {
    case "create": {
      const [id, ...nameParts] = rest;
      const m = newManifest({ id, name: nameParts.join(" ") });
      const { valid, errors } = validate(m);
      if (!valid) throw new Error("created manifest is invalid: " + errors.join("; "));
      console.log(`created ${writeManifest(m)}`);
      break;
    }
    case "merge": {
      const [id, json] = rest;
      writeManifest(merge(readManifest(id), JSON.parse(json)));
      console.log(`merged into ${id}`);
      break;
    }
    case "set-status": {
      const [id, status] = rest;
      writeManifest(setStatus(readManifest(id), status));
      console.log(`${id} -> ${status}`);
      break;
    }
    case "validate": {
      const [id] = rest;
      const { valid, errors } = validate(readManifest(id));
      if (valid) {
        console.log(`${id} OK`);
      } else {
        console.error(`${id} INVALID:\n${errors.join("\n")}`);
        process.exit(1);
      }
      break;
    }
    default:
      console.error("usage: node tools/manifest.mjs <create|merge|set-status|validate> ...");
      process.exit(2);
  }
}

if (fileURLToPath(import.meta.url) === process.argv[1]) {
  cli(process.argv.slice(2));
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS — CLI round-trip and the non-zero-exit test both green.

- [ ] **Step 5: Run the full suite**

Run: `npm test`
Expected: PASS — harness + all manifest tests green.

- [ ] **Step 6: Commit**

```bash
git add tools/manifest.mjs tools/manifest.test.mjs
git commit -m "feat: manifest file helpers and CLI"
```

---

## Task 7: `concept` skill (+ skills structural test)

This task also introduces `tools/skills.test.mjs`, which asserts that each REQUIRED skill folder (`concept`, `builder`, `validator`) has a `SKILL.md` whose YAML frontmatter declares a matching `name` and a non-empty `description`. After this task it stays red for `builder`/`validator` until Tasks 8–9 create them — that's intentional, those are their failing tests.

**Files:**
- Create: `tools/skills.test.mjs`
- Create: `.claude/skills/concept/SKILL.md`

- [ ] **Step 1: Write the failing structural test**

`C:\Users\quint\git\mobile-gen\tools\skills.test.mjs`:

```javascript
import { test, expect, describe } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const REQUIRED_SKILLS = ["concept", "builder", "validator"];

// Minimal frontmatter parse: grab the first --- ... --- block and read name/description.
function frontmatter(md) {
  const m = md.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const out = {};
  for (const line of m[1].split("\n")) {
    const kv = line.match(/^(\w+):\s*(.*)$/);
    if (kv) out[kv[1]] = kv[2].trim();
  }
  return out;
}

describe.each(REQUIRED_SKILLS)("skill: %s", (skill) => {
  const path = join(REPO_ROOT, ".claude", "skills", skill, "SKILL.md");

  test("SKILL.md exists", () => {
    expect(existsSync(path)).toBe(true);
  });

  test("has frontmatter with matching name and a description", () => {
    const fm = frontmatter(readFileSync(path, "utf8"));
    expect(fm).not.toBeNull();
    expect(fm.name).toBe(skill);
    expect(fm.description && fm.description.length).toBeGreaterThan(10);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run tools/skills.test.mjs`
Expected: FAIL — all three skills missing (`SKILL.md exists` false).

- [ ] **Step 3: Write `concept/SKILL.md`**

`C:\Users\quint\git\mobile-gen\.claude\skills\concept\SKILL.md`:

```markdown
---
name: concept
description: Use when turning a one-line game prompt into a structured, validated GameForge design concept. Writes the manifest.concept block and sets status to "concept".
---

# concept

Turn a one-line prompt into a structured, differentiated design concept and record it in a new manifest.

## Inputs
- A one-line prompt (e.g. "a neon endless runner").
- The existing `manifests/` directory — read it to avoid near-duplicate concepts.

## Outputs
- A new manifest at `manifests/<id>.json` with a populated `concept` block and `status = "concept"`.

## Steps

1. **Read existing manifests.** List `manifests/*.json` and skim each `concept.genre` + `name`. If the prompt would produce a near-duplicate of an existing title, say so and propose a differentiating twist before continuing.

2. **Derive the concept.** From the prompt, decide:
   - `genre` — short noun phrase (e.g. "endless runner", "match-3", "top-down shooter").
   - `core_loop` — one sentence describing the second-to-second loop (e.g. "tap to jump, avoid obstacles, score climbs with distance").
   - `mechanics` — a short list of the concrete mechanics the builder must implement (e.g. ["jump", "obstacle spawning", "score", "game over + restart"]). Keep it minimal but complete — every item here is something `builder` must wire up.
   - `art_direction` — a coherent primitive-art direction: a named palette + shape language (e.g. "neon vector on near-black; bright cyan/magenta shapes, thin glow"). `builder` derives its colors and shapes from this string, so be specific.
   - `target_platforms` — `["android"]` for the POC.
   - `differentiation_notes` — one line on how this avoids being a clone of a saturated title.

3. **Allocate an id.** Use `<genre-slug>-<NNNN>`, zero-padded, incrementing past any existing id with the same prefix (e.g. `runner-0001`). The slug is a short kebab form of the genre.

4. **Create the manifest skeleton:**
   ```
   node tools/manifest.mjs create <id> "<Title Name>"
   ```

5. **Write the concept block:**
   ```
   node tools/manifest.mjs merge <id> "{\"concept\": { ...the fields from step 2... }}"
   ```
   (On Windows PowerShell, prefer writing the JSON to a temp file and passing its contents, or use single quotes around the JSON to avoid escaping pain.)

6. **Validate:**
   ```
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`. The manifest is now at `status = "concept"` — hand off to `builder`.

## Notes
- Do NOT invent assets here. Art is the builder's job (deliberate primitives); this skill only sets `art_direction` to steer it.
- The differentiation check is lightweight — a sanity gate, not market research.
```

- [ ] **Step 4: Run the test to verify the concept case passes**

Run: `npx vitest run tools/skills.test.mjs`
Expected: the two `skill: concept` tests PASS; `builder` and `validator` still FAIL (expected — created in Tasks 8–9).

- [ ] **Step 5: Commit**

```bash
git add tools/skills.test.mjs .claude/skills/concept/SKILL.md
git commit -m "feat: concept skill + skills structural test"
```

---

## Task 8: `builder` skill

**Files:**
- Create: `.claude/skills/builder/SKILL.md`

- [ ] **Step 1: Confirm the failing test (builder case is red)**

Run: `npx vitest run tools/skills.test.mjs`
Expected: `skill: builder` tests FAIL (`SKILL.md exists` false). This is the failing test for this task.

- [ ] **Step 2: Write `builder/SKILL.md`**

`C:\Users\quint\git\mobile-gen\.claude\skills\builder\SKILL.md`:

````markdown
---
name: builder
description: Use when generating a runnable Godot 4.x project from a manifest's concept block. Produces games/<id>/, writes manifest.build, and sets status to "generated".
---

# builder

Generate a Godot 4.x project that opens and runs **without manual code fixes**, with a minimal-but-functional core loop and deliberate primitive visuals.

## Inputs
- `manifests/<id>.json` with a populated `concept` block (`status = "concept"`).
- The pinned Godot version from `README.md` (the source of truth for `engine_version`).

## Outputs
- A project under `games/<id>/`.
- A populated `manifest.build` block and `assets[]` entries.
- `status = "generated"`.

## Hard requirements
- The project MUST import and run headless with **no script errors** (the `validator` enforces this).
- Wire **touch/tap input** for Android (`InputEventScreenTouch` and/or `_input`), not just keyboard.
- Implement every mechanic listed in `concept.mechanics`, plus **game over + restart** so the loop is replayable.
- Keep one main scene runnable on launch (`run/main_scene` set in `project.godot`).

## Deliberate primitives (no external art — that is M1)
Derive a coherent palette and shape language from `concept.art_direction`. Use in-engine drawing only: `ColorRect`, `Polygon2D`, `_draw()`, `Line2D`, simple `GPUParticles2D`/`CPUParticles2D`. Aim for *intentional* — clean shapes, a 3–5 color palette, basic visual feedback (a flash/particle on score or collision). Record each visual as an asset entry:
```
{ "type": "sprite", "name": "player", "source": "placeholder", "origin": "primitive" }
```

## Reference scaffold (adapt to the genre)

`games/<id>/project.godot`:
```
config_version=5

[application]
config/name="<Title Name>"
run/main_scene="res://Main.tscn"

[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation="portrait"

[input]
tap={
"deadzone": 0.5,
"events": []
}
```

`games/<id>/Main.gd` (skeleton — fill the genre-specific loop):
```gdscript
extends Node2D

var score: int = 0
var alive: bool = true

func _ready() -> void:
	_start_game()

func _start_game() -> void:
	score = 0
	alive = true
	# spawn player + initial world here

func _input(event: InputEvent) -> void:
	# Android tap + desktop click both arrive here.
	if event is InputEventScreenTouch and event.pressed:
		_on_tap()
	elif event is InputEventMouseButton and event.pressed:
		_on_tap()

func _on_tap() -> void:
	if not alive:
		_start_game()
		return
	# core action (jump / shoot / swap ...) goes here

func _process(delta: float) -> void:
	if not alive:
		return
	# advance the world; on the loss condition call _game_over()

func _game_over() -> void:
	alive = false
	# show "tap to restart"
```

Create `Main.tscn` as a text scene referencing `Main.gd` on the root node, plus the primitive nodes the genre needs.

## Steps

1. Read `manifests/<id>.json`; confirm `concept` is populated.
2. Scaffold `games/<id>/` with `project.godot`, `Main.tscn`, `Main.gd`, and any extra scenes/scripts the mechanics need. Use the pinned `engine_version` from `README.md`.
3. Implement the core loop from `concept.core_loop` + `concept.mechanics`, including game-over + restart and touch input.
4. Apply the primitive visual style from `concept.art_direction`.
5. Write the build block:
   ```
   node tools/manifest.mjs merge <id> "{\"build\": {\"engine\": \"godot\", \"engine_version\": \"<pinned>\", \"language\": \"gdscript\", \"project_path\": \"games/<id>/\", \"addons\": [], \"export_presets\": [\"android\"]}}"
   ```
6. Record primitive assets:
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ ...primitive entries... ]}"
   ```
7. Advance status:
   ```
   node tools/manifest.mjs set-status <id> generated
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`. Hand off to `validator`.

## Forward-looking (not required in POC)
The future automated `core_loop_functional` check expects a headless **self-test** scene that simulates input over N frames and asserts state changes. If cheap, emit `games/<id>/selftest.gd` now so the hook exists; otherwise leave it for the `validator`'s documented plug-in point.
````

- [ ] **Step 3: Run the test to verify the builder case passes**

Run: `npx vitest run tools/skills.test.mjs`
Expected: `skill: concept` and `skill: builder` PASS; `validator` still FAIL.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/builder/SKILL.md
git commit -m "feat: builder skill"
```

---

## Task 9: `validator` skill

**Files:**
- Create: `.claude/skills/validator/SKILL.md`

- [ ] **Step 1: Confirm the failing test (validator case is red)**

Run: `npx vitest run tools/skills.test.mjs`
Expected: `skill: validator` tests FAIL. This is the failing test for this task.

- [ ] **Step 2: Write `validator/SKILL.md`**

`C:\Users\quint\git\mobile-gen\.claude\skills\validator\SKILL.md`:

````markdown
---
name: validator
description: Use when confirming a generated Godot game opens, runs, and has a working core loop. Runs headless checks, records manifest.validation, and advances status to validated/playable or failed.
---

# validator

Confirm a generated game opens, runs without script errors, and (via human playtest) has a working core loop. Make every failure **legible** — attribute it to a specific skill gap (POC success criterion #5).

## Inputs
- `manifests/<id>.json` with a populated `build` block (`status = "generated"`).
- The project on disk at `games/<id>/`.

## Outputs
- A populated `manifest.validation` block.
- `status = "validated"` (programmatic checks pass), then `"playable"` (human playtest passes), or `"failed"` with legible `issues`.

## Method 1 — Programmatic (automated now)

1. **Run the project headless** and capture output + exit code:
   ```
   godot --headless --path games/<id>/ --quit-after 120
   ```
   PASS when: exit code is 0 AND the output contains no `SCRIPT ERROR`, no `ERROR:`, and no "Failed to load" lines. (A clean run of ~120 frames means the scene tree loaded and `_process` ran without crashing.)

2. Record results:
   ```
   node tools/manifest.mjs merge <id> "{\"validation\": {\"opens_in_editor\": true, \"runs\": true, \"issues\": []}}"
   ```
   - On failure, set `runs: false` and put each error line in `issues` verbatim, then:
     ```
     node tools/manifest.mjs set-status <id> failed
     ```
     STOP and report which skill is responsible (almost always `builder`) and the precise error.

3. On success, advance:
   ```
   node tools/manifest.mjs set-status <id> validated
   ```

## Method 2 — Human playtest (manual now)

4. Ask the owner to open the project in the Godot editor and play for ~60 seconds, confirming the core loop from `concept.core_loop` (e.g. tap → jump, score climbs, game-over → restart works).

5. On confirmation:
   ```
   node tools/manifest.mjs merge <id> "{\"validation\": {\"core_loop_functional\": true}}"
   node tools/manifest.mjs set-status <id> playable
   ```
   If the loop is broken, record the specific failure in `issues`, set the loop boolean false, and attribute it to a skill (e.g. "builder did not wire restart on tap after game over"). Do NOT advance to `playable`.

## Future full automation — DESIGNED-FOR PLUG-IN POINT (do not build in POC)

```
# AUTOMATION HOOK (M0+ future): replace Method 2 with a headless self-test.
# builder emits games/<id>/selftest.gd that simulates input over N frames and
# asserts observable state changes:
#   - score increments after a simulated tap,
#   - player Y changes on jump,
#   - _game_over() fires on a forced collision.
# Run it here via:
#   godot --headless --path games/<id>/ --script res://selftest.gd
# A 0 exit + "SELFTEST OK" marker sets core_loop_functional=true automatically,
# letting status reach "playable" in CI with no human in the loop.
```

## Notes
- Some Godot CLI flags vary slightly by 4.x point release; if `--quit-after` is unavailable, fall back to `--headless --path games/<id>/ --quit` after confirming `--import` succeeds. Verify against the pinned version.
- Legibility is the product. "It didn't work" is a POC failure; "builder doesn't scaffold touch input" is a POC success.
````

- [ ] **Step 3: Run the test to verify all skills pass**

Run: `npx vitest run tools/skills.test.mjs`
Expected: PASS — all three skills green.

- [ ] **Step 4: Run the full suite**

Run: `npm test`
Expected: PASS — harness + manifest + skills tests all green.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "feat: validator skill"
```

---

## Task 10: End-to-end acceptance — first endless runner + skill-gap report

This is the POC's actual deliverable (§2, §8, §12 task 4–5): run the loop end-to-end on one genre, then **report where it broke in terms of which skill needs improvement**. It's interactive (Claude drives the skills, the owner playtests), so it's an acceptance task, not a unit test.

**Files:**
- Create (by running the skills): `manifests/runner-0001.json`, `games/runner-0001/...`
- Create: `docs/superpowers/poc-run-001.md` (the skill-gap report)

- [ ] **Step 1: Run `concept`**

In Claude Code, invoke the `concept` skill with the prompt: *"an endless runner where you tap to jump over neon obstacles."*
Expected: `manifests/runner-0001.json` exists, `status = "concept"`, `concept` block populated. Verify: `node tools/manifest.mjs validate runner-0001` → `OK`.

- [ ] **Step 2: Run `builder`**

Invoke the `builder` skill on `runner-0001`.
Expected: `games/runner-0001/` contains `project.godot`, `Main.tscn`, `Main.gd`; `manifest.build` populated; `status = "generated"`; `validate` → `OK`.

- [ ] **Step 3: Run `validator` — programmatic**

Invoke the `validator` skill on `runner-0001`.
Expected: `godot --headless --path games/runner-0001/ --quit-after 120` exits 0 with no script errors; `validation.opens_in_editor` / `runs` = true; `status = "validated"`. If it fails, that's a legitimate finding — capture it in Step 5, don't paper over it.

- [ ] **Step 4: Human playtest**

Open `games/runner-0001/` in the Godot editor (`godot --path games/runner-0001/ --editor`), press Play, and play ~60 seconds: tap jumps, score climbs, collision triggers game-over, tap restarts.
Expected: core loop works → validator sets `core_loop_functional = true`, `status = "playable"`. If not, record exactly what broke.

- [ ] **Step 5: Write the skill-gap report (the real deliverable)**

`C:\Users\quint\git\mobile-gen\docs\superpowers\poc-run-001.md` — for this run, record against the §2 success criteria:

```markdown
# POC Run 001 — endless runner (runner-0001)

**Prompt:** an endless runner where you tap to jump over neon obstacles.
**Final status:** <concept | generated | validated | playable | failed>

## Success criteria (§2)
1. Produced a working project: <yes/no>
2. Opened & ran without manual code fixes: <yes/no — if no, what was hand-fixed>
3. Playable ~60s, core loop functions: <yes/no>
4. Manifest correct: <yes/no — `validate` output>
5. Failure legible & attributable to a skill: <the finding>

## Where the loop broke (criterion #5 — the point of the POC)
- Responsible skill: <concept | builder | validator>
- What was wrong: <specific, e.g. "builder scaffolded keyboard input but no InputEventScreenTouch, so tap did nothing on Android">
- Proposed SKILL.md edit: <the concrete instruction to add/change>

## Next
- [ ] Apply the SKILL.md edit above.
- [ ] Re-run; then repeat the loop for genres 2 and 3 (match-3, top-down shooter) to satisfy the ≥3-genre criterion.
```

- [ ] **Step 6: Apply the first skill fix and commit**

Edit the responsible `SKILL.md` per the report (this is the POC loop — improving skills is the goal), then commit the run:

```bash
git add manifests/runner-0001.json games/runner-0001 docs/superpowers/poc-run-001.md .claude/skills
git commit -m "feat: first end-to-end POC run (endless runner) + skill-gap report"
```

- [ ] **Step 7: Repeat across ≥3 genres**

Re-run Steps 1–6 for at least two more distinct genres (e.g. match-3, top-down shooter), each with its own manifest id and run report (`poc-run-002.md`, `poc-run-003.md`). The POC succeeds (§2) when the loop reliably produces `status = "playable"` games across ≥3 genres and every failure along the way was legibly attributed to a specific skill. Each iteration's job is a sharper `SKILL.md`.

---

## Self-Review

**Spec coverage (each spec section → task):**
- §3 Settled decisions: Godot (Task 0), hybrid validation (Task 9 Methods 1+2), deliberate primitives (Task 8 callout), env/install-is-Step-0 (Task 0). ✓
- §5 Manifest (schema, `build` block required, `status` advancement, `_reserved` preserved): Tasks 2–6 (schema requires `_reserved`; `setStatus` enforces advancement; `newManifest` seeds `_reserved`). ✓
- §6 Skills (`concept`/`builder`/`validator`, incl. validator's documented automation plug-in point): Tasks 7–9 (validator's AUTOMATION HOOK comment = §6 callout requirement). ✓
- §7 Repo layout: Tasks 1, 7–9 create `.claude/skills/*`, `manifests/`, `games/`, `tools/`, `.gitignore`, `README.md`. ✓
- §8 Workflow loop & §12 first tasks (git done = `ee53910`; scaffold; draft 3 skills + manifest writer; first runner; report): Tasks 1–10. ✓
- §11 env/VCS (.gitignore + `node_modules`, pinned version source of truth): Task 1. ✓
- §13 risks (stay on-subscription, rate limits): operational — surfaced in README/run reports; no code task needed.

**Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N" left. Skill bodies are prose by nature (the spec defines them as markdown instructions), but each contains the concrete CLI commands and Godot specifics an engineer needs. ✓

**Type/name consistency:** `newManifest`, `setStatus`, `merge`, `validate`, `readManifest`, `writeManifest`, `manifestPath`, `STATUSES` are used identically in module, tests, and CLI. CLI commands (`create`/`merge`/`set-status`/`validate`) match the README and every SKILL.md. Status set `concept/generated/validated/playable/failed` is identical in schema enum, `STATUSES`, transition map, and skills. ✓

**One known gap surfaced deliberately:** Godot CLI flags (`--quit-after`, `--import`) vary by point release — the validator skill tells the engineer to verify against the pinned version rather than asserting one universal flag. This is the right call for a tool installed at execution time.
