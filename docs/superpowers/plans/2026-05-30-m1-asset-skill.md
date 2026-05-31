# M1 — `asset` skill (SVG re-skin) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `asset` skill that re-skins a `playable` Godot game with coherent Claude-authored SVG art, recording the pass in the manifest and advancing it to a new terminal `styled` status.

**Architecture:** Three deliverables. (1) **Schema + manifest tooling** — the only code with logic, so it gets TDD: a new `styled` status, a `playable → styled` transition, and a top-level `asset_pass` block. (2) **The `asset` SKILL.md** — prose that derives a written visual system from `concept.art_direction`, authors conforming SVGs, rewires the procedural `_draw()` game to display them via `Sprite2D`/`TextureRect`, and records the pass. (3) **A proof run** on a real `playable` title, with a run report attributing any visual gap to specific skill prose. The proven M0 loop (`concept → builder → validator → playable`) is untouched; `asset` is a clean bolt-on.

**Tech Stack:** Node.js (ESM), Ajv 2020 + ajv-formats (JSON-Schema draft 2020-12), Vitest, Godot 4.6.3.stable (native SVG importer), GDScript.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `schema/manifest.schema.json` | Add `styled` to the `status` enum; add the `asset_pass` block (optional, `additionalProperties:false`). `assets[]` is unchanged — `origin`/`source` are already free strings. | Modify |
| `tools/manifest.mjs` | Add `"styled"` to `STATUSES`; make `playable` non-terminal (`["styled","failed"]`) and `styled` terminal (`[]`). | Modify |
| `tools/manifest.test.mjs` | Update the hard-coded statuses assertion; add transition + schema tests. | Modify |
| `tools/skills.test.mjs` | Add `"asset"` to `REQUIRED_SKILLS`. | Modify |
| `.claude/skills/asset/SKILL.md` | The new prose skill (visual system → SVGs → swap → manifest → `styled`). | Create |
| `.claude/skills/validator/SKILL.md` | Document the one new capability: advancing `playable → styled` after a re-skin. | Modify |
| `games/<id>/art/*.svg` | Claude-authored vector art, one per re-skinned entity. Produced **during the proof run**, not in a code task. | Create (run) |
| `docs/superpowers/poc-run-007.md` | The proof run report. | Create (run) |

**Conventions discovered in the codebase (do not deviate):**
- Godot is on PATH as `godot` (a `.cmd` shim). Headless run check: `godot --headless --path games/<id>/ --quit-after 120`. Import pass: `godot --headless --path games/<id>/ --import`.
- Manifest edits go through the CLI: `node tools/manifest.mjs <merge|set-status|validate> <id> ...`. Arrays in `merge` **replace** wholesale (so flipping `assets[]` means passing the full new array). Objects deep-merge.
- The generated game is a **single `Node2D`** whose `Main.tscn` is bare (`[node name="Main" type="Node2D"]` + script); **all** visuals live in `Main.gd`'s `_draw()`. There are no existing sprite slots — the swap *adds* `Sprite2D`/`TextureRect` child nodes and removes/guards the matching `_draw()` calls.
- Tests run with `npm test` (vitest). 24 tests are green today; this plan adds ≈ 5–6 and edits 2.

---

## Task 1: `styled` status + transitions (manifest.mjs + schema)

**Files:**
- Modify: `tools/manifest.mjs:48` (`STATUSES`) and `tools/manifest.mjs:51-57` (`TRANSITIONS`)
- Modify: `schema/manifest.schema.json:13` (`status` enum)
- Test: `tools/manifest.test.mjs` (edit the existing statuses test at line 75; add transition tests)

- [ ] **Step 1: Update the existing statuses assertion to expect six statuses (this is the failing test)**

In `tools/manifest.test.mjs`, replace the existing test at lines 75-77:

```javascript
  test("exposes the five POC statuses", () => {
    expect(STATUSES).toEqual(["concept", "generated", "validated", "playable", "failed"]);
  });
```

with:

```javascript
  test("exposes the six statuses through styled", () => {
    expect(STATUSES).toEqual(["concept", "generated", "validated", "playable", "styled", "failed"]);
  });
```

- [ ] **Step 2: Add the transition tests next to the existing `setStatus` tests**

In `tools/manifest.test.mjs`, inside the `describe("setStatus", ...)` block, after the `test("rejects leaving a terminal status", ...)` test (around line 101), add:

```javascript
  test("advances playable -> styled", () => {
    const playable = { ...base(), status: "playable" };
    const styled = setStatus(playable, "styled", "2026-05-30T14:00:00Z");
    expect(styled.status).toBe("styled");
    expect(styled.updated_at).toBe("2026-05-30T14:00:00Z");
  });

  test("allows playable -> failed", () => {
    const playable = { ...base(), status: "playable" };
    expect(setStatus(playable, "failed").status).toBe("failed");
  });

  test("rejects leaving styled (terminal)", () => {
    const styled = { ...base(), status: "styled" };
    expect(() => setStatus(styled, "playable")).toThrow(/illegal transition/);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npm test -- tools/manifest.test.mjs`
Expected: FAIL — `exposes the six statuses` fails (`STATUSES` still has 5), and the three new transition tests fail (`playable` is currently terminal so `playable -> styled` throws "illegal transition", and `setStatus` rejects `"styled"` as an unknown status).

- [ ] **Step 4: Add `styled` to `STATUSES` in `tools/manifest.mjs`**

Replace line 48:

```javascript
export const STATUSES = ["concept", "generated", "validated", "playable", "failed"];
```

with:

```javascript
export const STATUSES = ["concept", "generated", "validated", "playable", "styled", "failed"];
```

- [ ] **Step 5: Make `playable` non-terminal and `styled` terminal in `TRANSITIONS`**

Replace the `TRANSITIONS` map at `tools/manifest.mjs:51-57`:

```javascript
const TRANSITIONS = {
  concept: ["generated", "failed"],
  generated: ["validated", "failed"],
  validated: ["playable", "failed"],
  playable: [],
  failed: []
};
```

with:

```javascript
const TRANSITIONS = {
  concept: ["generated", "failed"],
  generated: ["validated", "failed"],
  validated: ["playable", "failed"],
  playable: ["styled", "failed"],
  styled: [],
  failed: []
};
```

- [ ] **Step 6: Add `styled` to the schema `status` enum**

In `schema/manifest.schema.json`, replace line 13:

```json
    "status": { "enum": ["concept", "generated", "validated", "playable", "failed"] },
```

with:

```json
    "status": { "enum": ["concept", "generated", "validated", "playable", "styled", "failed"] },
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `npm test -- tools/manifest.test.mjs`
Expected: PASS — all manifest tests green, including the four updated/added ones.

- [ ] **Step 8: Commit**

```bash
git add tools/manifest.mjs tools/manifest.test.mjs schema/manifest.schema.json
git commit -m "feat: add terminal 'styled' status and playable->styled transition"
```

---

## Task 2: `asset_pass` block in the schema

**Files:**
- Modify: `schema/manifest.schema.json` (add `asset_pass` to `properties`)
- Test: `tools/manifest.test.mjs` (schema-acceptance tests)

**Note:** `asset_pass` is added to `properties` but **not** to the top-level `required` array, so existing `playable` manifests that lack it still validate (backward compatibility). The top-level object is `additionalProperties:false`, which is exactly why `asset_pass` must be declared — without it, any manifest carrying the block would be rejected.

- [ ] **Step 1: Write the failing schema-acceptance tests**

In `tools/manifest.test.mjs`, inside the `describe("validate", ...)` block, after the `test("rejects a missing required top-level key", ...)` test (around line 51), add:

```javascript
  test("accepts a styled manifest carrying asset_pass and origin:svg assets", () => {
    const m = validManifest();
    m.status = "styled";
    m.assets = [{ type: "sprite", name: "player", source: "art/player.svg", origin: "svg" }];
    m.asset_pass = {
      method: "svg",
      visual_system: {
        palette: ["#0a0a14", "#00e5ff", "#ff3df0", "#ffe24a"],
        stroke: "2px round, additive glow",
        form: "sharp-cornered geometric, low detail",
        shading: "flat fill + outer glow halo",
        scale: "SVGs scaled to primitive footprints; 10% internal padding"
      },
      reskinned: ["player", "obstacle", "pickup"],
      left_primitive: ["background", "glow", "particles"],
      art_path: "games/runner-0002/art/",
      notes: "background kept procedural; art_direction is geometric, well within SVG scope"
    };
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("rejects an unknown key inside asset_pass", () => {
    const m = validManifest();
    m.status = "styled";
    m.asset_pass = { method: "svg", bogus: true };
    expect(validate(m).valid).toBe(false);
  });

  test("still accepts an existing playable manifest with no asset_pass (no regression)", () => {
    const m = validManifest(); // status: "playable", no asset_pass
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- tools/manifest.test.mjs`
Expected: FAIL — `accepts a styled manifest carrying asset_pass...` fails because the top-level schema is `additionalProperties:false` and `asset_pass` is not yet a known property. (`rejects an unknown key inside asset_pass` may currently fail-open for the wrong reason — both go green once the block is added.)

- [ ] **Step 3: Add the `asset_pass` block to the schema**

In `schema/manifest.schema.json`, add the following property to the top-level `properties` object, immediately after the `validation` property's closing brace (after line 60, before the `_reserved` property):

```json
    "asset_pass": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "method": { "type": "string" },
        "visual_system": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "palette": { "type": "array", "items": { "type": "string" } },
            "stroke": { "type": "string" },
            "form": { "type": "string" },
            "shading": { "type": "string" },
            "scale": { "type": "string" }
          }
        },
        "reskinned": { "type": "array", "items": { "type": "string" } },
        "left_primitive": { "type": "array", "items": { "type": "string" } },
        "art_path": { "type": "string" },
        "notes": { "type": "string" }
      }
    },
```

(Leave the top-level `required` array unchanged — `asset_pass` stays optional.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- tools/manifest.test.mjs`
Expected: PASS — all three new tests green.

- [ ] **Step 5: Run the full suite to confirm no regression**

Run: `npm test`
Expected: PASS — all tests green (24 prior + the new ones from Tasks 1–2).

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.test.mjs
git commit -m "feat: add optional asset_pass block to manifest schema"
```

---

## Task 3: The `asset` SKILL.md + structural skills test

**Files:**
- Modify: `tools/skills.test.mjs:7` (`REQUIRED_SKILLS`)
- Create: `.claude/skills/asset/SKILL.md`

- [ ] **Step 1: Add `"asset"` to the required-skills list (the failing test)**

In `tools/skills.test.mjs`, replace line 7:

```javascript
const REQUIRED_SKILLS = ["concept", "builder", "validator"];
```

with:

```javascript
const REQUIRED_SKILLS = ["concept", "builder", "validator", "asset"];
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test -- tools/skills.test.mjs`
Expected: FAIL — `skill: asset > SKILL.md exists` fails (file does not exist yet); the frontmatter test fails for the same reason.

- [ ] **Step 3: Create `.claude/skills/asset/SKILL.md` with this exact content**

````markdown
---
name: asset
description: Use when re-skinning a playable Godot game with coherent Claude-authored SVG art. Derives a visual system from concept.art_direction, authors SVGs, rewires primitive _draw() to Sprite2D/TextureRect, records asset_pass, and sets status to "styled".
---

# asset

Replace a `playable` game's deliberate **primitive** visuals with real, coherent **SVG art**, so the title goes from "intentional toy" to "looks designed" — with the re-skin legibly recorded in the manifest. The real deliverable is a sharp re-skin **system**, not the prettier game: every gap must be attributable to specific prose here. This runs as a clean bolt-on **after `playable`**:

```
concept → builder → validator → [playable] → asset → validator(re-run) → [styled]
```

## Inputs
- `manifests/<id>.json` with a populated `concept` block and `status = "playable"`.
- The generated project on disk at `games/<id>/` (a single `Node2D` whose `Main.gd` draws every entity procedurally in `_draw()`).
- The pinned Godot version from `README.md`.

## Outputs
- `games/<id>/art/*.svg` — one Claude-authored vector file per re-skinned entity.
- A rewired `Main.gd` / `Main.tscn` displaying those SVGs via `Sprite2D` (world) / `TextureRect` (HUD).
- A populated `asset_pass` block and flipped `assets[]` entries (`origin:"svg"`).
- `status = "styled"` (after the validator re-run passes).

## Hard requirements
- The re-skinned project MUST still import and run **headless with no script errors** (the `validator` re-enforces this).
- Game **logic is untouched** — movement, collision, spawning, scoring, input, and game-over/restart behave exactly as before. Only the *visual representation* changes.
- No double-draw: for every re-skinned entity the old `_draw()` primitive is removed or guarded. Leaving the primitive *and* adding the sprite is the most common failure — prevent it.
- No new MCP tool and no new dependency: author SVG inline as text, exactly as `builder` authors GDScript. Godot's native importer rasterizes it.
- Do **not** edit `concept` or `builder`. Consume `concept.art_direction` as-is.

## Step 0 — Derive the visual system FIRST (the real deliverable)

A real asset creator does not produce a pile of independently-acceptable shapes — it produces **one coherent visual system** and applies it everywhere, so the game reads as a single designed thing. "Each SVG is fine but they don't cohere" is the **primary failure** this step exists to prevent (the art analog of the M0 hybrid finding, "two systems that coexist instead of fuse"). When it happens, it is attributable to *this system*, not the individual files.

Before authoring **any** SVG, write the system down explicitly from `concept.art_direction`:

- **Palette** — a fixed 3–5 colour set with named roles (primary, accent, danger, background, …). Every fill/stroke comes from this set.
- **Line/stroke** — one stroke weight and one join/cap style, used throughout.
- **Form language** — corner radius, geometric vs. organic, level of detail. Pick one and hold it.
- **Shading model** — flat / single-direction gradient / glow halo — pick **one** and apply it to every asset.
- **Scale & padding** — how each SVG maps to its primitive's footprint, plus consistent internal padding so assets sit together (e.g. all art drawn into a square `viewBox` with the same % padding).

This system is recorded verbatim in `asset_pass.visual_system` (below) so it is reviewable, reusable, and the thing a run report critiques when the result looks incoherent.

## The SVG aesthetic boundary (be honest about scope)

SVG is the *right* tool for the art this pipeline produces today — abstract, geometric, neon/flat, hyper-casual, all UI. Resolution independence is an app-store strength: one vector covers every Android density bucket. SVG is the *wrong* tool for **representational, character, illustrated, or textured** art (a painted hero, a photoreal background) — that is an **M1.5 (raster / local-SD)** concern.

If a concept's `art_direction` leans representational enough that hand-authored vector would be weak, **say so in `asset_pass.notes`** ("art_direction calls for an illustrated character; SVG would be mediocre here — M1.5 would serve it better") rather than silently shipping poor vector art. Re-skin what SVG does well; flag what it doesn't.

## Authoring the SVGs

One file per builder-registered visual entity, under `games/<id>/art/` (e.g. `player.svg`, `obstacle.svg`, `pickup.svg`). Every file conforms to the Step 0 system: same palette, same stroke, same form language, same shading model, same `viewBox`/padding convention.

- Use a square `viewBox` (e.g. `0 0 100 100`) so scaling to a footprint is predictable.
- Execute the shading model — if it is "flat fill + outer glow halo", actually draw the halo (an oversized, low-alpha shape behind, or an SVG `<filter>` blur), don't just assert it. Asserting neon is not executing neon.
- Keep files small and diffable — paths, `<rect>`, `<circle>`, gradients, filters. No embedded rasters.

## The SVG-swap mechanism (the technically hard part)

The builder draws procedurally — there are **no sprite slots to swap into**, and `Main.tscn` is a bare `Node2D` with all rendering in `Main.gd`'s `_draw()`. So you must both generate SVGs *and* rewire the game.

**a) Get the SVGs into Godot.** Godot 4.x imports `.svg` as a texture via a `.svg.import` sidecar (carrying a `scale` param). Run a headless import pass so the sidecars and cached textures exist **before** re-validating:
```
godot --headless --path games/<id>/ --import
```
Commit the generated `*.svg.import` sidecars alongside the art (expected Godot output, like `.gd.uid`).

**b) Replace each primitive (the documented swap pattern).** Per re-skinned entity:
- Load the texture and display it with a node positioned/scaled to the primitive's original footprint:
  - **World actors** (player, obstacles, pickups) → `Sprite2D` with `texture = load("res://art/<name>.svg")`, placed at the same world transform the `_draw()` used. For pooled/spawned collections (e.g. obstacles), create one `Sprite2D` per live instance and move it each frame to the position the primitive was drawn at, instead of a `draw_*` call.
  - **HUD/UI** → `TextureRect` under the HUD layer.
- **Remove or guard** the matching `_draw()` code for that entity — delete its `draw_rect`/`draw_circle`/glow calls; keep the node's transform and all game logic. Verify you did not leave the primitive drawing underneath the sprite (double-draw).
- Movement, collision, spawning, scoring — **unchanged**.

**c) What stays primitive.** Effects (glow halos, particles, screen-shake, squash/stretch, flash) stay code — they are *motion/juice*, not art. Backgrounds may stay procedural (parallax grid/stars) **or** get a tiling SVG — your judgment from `art_direction`. **Record which entities you re-skinned vs. left primitive** so a partial re-skin is a legible choice, not a silent gap.

**Failure attribution (the POC value):** a bad re-skin is always attributable — you authored a poor SVG, mis-positioned/mis-scaled a sprite, or failed to remove the underlying primitive. Each is a specific, fixable prose gap.

## Recording the pass

1. Flip the re-skinned `assets[]` entries (arrays replace wholesale — pass the **full** array, re-skinned entries as `origin:"svg"`, untouched ones as-is):
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ {\"type\":\"sprite\",\"name\":\"player\",\"source\":\"art/player.svg\",\"origin\":\"svg\"}, ... ]}"
   ```
2. Write the `asset_pass` block (record the Step 0 system verbatim):
   ```
   node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"svg\",\"visual_system\":{\"palette\":[...],\"stroke\":\"...\",\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\"},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\"}}"
   ```
3. Validate the manifest (still `playable` at this point):
   ```
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`.

## Hand off to the validator

Do **not** set `styled` yourself. Hand off to `validator`, which re-runs the same gates on the rewired game (headless import + run clean; `selftest.gd` still `SELFTEST OK` if present; human A/B playtest) and advances `playable → styled` on success, or records legible `issues` (attributed almost always to `asset`) and stops on failure.

## Notes
- The import pass (`--import`) must run before the validator's headless run, or `load("res://art/...svg")` returns null at runtime.
- If a re-skin makes the game look *worse* or incoherent, that is a finding about the **visual system** (Step 0), not the individual files — fix the system and re-derive, don't patch one SVG.
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npm test -- tools/skills.test.mjs`
Expected: PASS — `skill: asset > SKILL.md exists` and `has frontmatter with matching name and a description` both green (frontmatter `name: asset`, description > 10 chars).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/asset/SKILL.md tools/skills.test.mjs
git commit -m "feat: add asset skill (SVG re-skin pass) + structural test"
```

---

## Task 4: Teach `validator` to advance `playable → styled`

**Files:**
- Modify: `.claude/skills/validator/SKILL.md`

The validator reuses its existing gates on the rewired game; it gains exactly one capability — advancing `playable → styled` after a re-skin (today it stops at `playable`). No new validator skill, no test change (the skill is prose; its frontmatter test already passes).

- [ ] **Step 1: Add a re-skin re-validation section to `validator/SKILL.md`**

In `.claude/skills/validator/SKILL.md`, immediately before the `## Notes` section at the end, insert:

```markdown
## Method 3 — Re-skin re-validation (`playable → styled`, after the `asset` skill)

When `asset` has re-skinned a `playable` title, re-run the same gates on the rewired game and advance to the terminal `styled` status on success:

1. **Headless import + run clean** — `godot --headless --path games/<id>/ --quit-after 120`, exit 0 with no `SCRIPT ERROR` / `ERROR:` / "Failed to load". Proves the SVGs import and the rewired scene runs.
2. **`selftest.gd` still `SELFTEST OK`** (if the title has one) — proves the swap changed only visuals, not logic.
3. **Human A/B playtest** — the owner confirms the SVG version (a) looks more designed than the primitive original, (b) **reads as one coherent visual system** rather than mismatched shapes, and (c) plays identically.

On all three passing:
```
node tools/manifest.mjs set-status <id> styled
node tools/manifest.mjs validate <id>
```
On failure, record the specific issue in `validation.issues`, attribute it to `asset` (e.g. "asset: left the primitive obstacle drawing under the sprite — double-draw", or "asset: SVGs individually fine but palette/stroke don't cohere — visual_system gap"), and do **not** advance to `styled`. The game stays `playable`; the fix is a specific `asset` SKILL.md edit.
```

- [ ] **Step 2: Run the full suite to confirm nothing broke**

Run: `npm test`
Expected: PASS — all tests green (the validator frontmatter test still passes; prose edits don't affect tests).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "docs: validator advances playable->styled after re-skin"
```

---

## Task 5: Proof run — re-skin a real `playable` title + run report

This is the M0-shaped proof: run the new skill end-to-end and convert any felt visual gap into a concrete `SKILL.md` edit. It is execution + a report, not TDD.

**Files:**
- Create: `games/<id>/art/*.svg` and `*.svg.import` (the re-skin)
- Modify: `games/<id>/Main.gd`, `games/<id>/Main.tscn` (the swap)
- Modify: `manifests/<id>.json` (via CLI — `assets[]`, `asset_pass`, `status`)
- Create: `docs/superpowers/poc-run-007.md` (the report)

- [ ] **Step 1: Pick the target and ensure it is `playable`**

Prefer `runner-0002` (the best-looking baseline). It is currently `status: "validated"`, **not** `playable` — so first take it to `playable` via the validator's human playtest (`Method 2`), or pick an already-`playable` title (`runner-0001`, `shooter-0001`, `match3-survival-0003`). Confirm: `node tools/manifest.mjs validate <id>` → OK and the manifest reads `"status": "playable"`.

- [ ] **Step 2: Run the `asset` skill end-to-end**

Follow `.claude/skills/asset/SKILL.md` exactly: derive the visual system from `concept.art_direction`, author `games/<id>/art/*.svg`, run `godot --headless --path games/<id>/ --import`, rewire `Main.gd`/`Main.tscn` (add `Sprite2D`/`TextureRect`, guard the matching `_draw()` calls), then merge `assets[]` (`origin:"svg"`) and the `asset_pass` block.

- [ ] **Step 3: Re-validate (programmatic gate)**

Run: `godot --headless --path games/<id>/ --quit-after 120`
Expected: exit 0, no `SCRIPT ERROR` / `ERROR:` / "Failed to load". If a `selftest.gd` exists, also run `godot --headless --path games/<id>/ --script res://selftest.gd` and expect `SELFTEST OK`. Fix `asset` prose / the swap until clean — do not paper over it.

- [ ] **Step 4: Human A/B playtest and advance to `styled`**

Have the owner A/B the SVG re-skin against the primitive original (e.g. `git stash` the swap or open both). Confirm it looks more designed, reads as one coherent system, and plays identically. Then:
```
node tools/manifest.mjs set-status <id> styled
node tools/manifest.mjs validate <id>
```
Expected: `<id> OK` and `"status": "styled"`.

- [ ] **Step 5: Write the run report**

Create `docs/superpowers/poc-run-007.md` following the shape of the existing `poc-run-00X.md` reports: what was re-skinned vs. left primitive, the visual system used, the A/B outcome, and — the POC value — **every felt gap attributed to specific `asset` SKILL.md prose**, with the exact edit it implies. If the result was incoherent, attribute it to the `visual_system` section (Step 0), not the individual files.

- [ ] **Step 6: Apply any skill edits the run surfaced, then commit the whole proof**

Edit `.claude/skills/asset/SKILL.md` (and/or `validator/SKILL.md`) per the report's findings. Then run `npm test` (expect all green) and commit:
```bash
git add games/<id>/ manifests/<id>.json docs/superpowers/poc-run-007.md .claude/skills/
git commit -m "feat: M1 proof run — SVG re-skin of <id> to styled + run report"
```

---

## Self-Review

**1. Spec coverage** (each numbered/lettered spec section → task):
- §1 Goal (sharp `asset` skill, re-skin legibly recorded) → Tasks 3, 5.
- §2 Scope: new `asset` skill after `playable` → T3; visual system as deliverable → T3 Step 0; SVG authored inline → T3; rewire `_draw()` → Sprite2D/TextureRect → T3; manifest `styled` + `asset_pass` + `origin:"svg"` → T1, T2; re-validate via existing validator → T4; one end-to-end proof + report → T5. Out-of-scope items (raster/audio/icons/representational) are deferred — no tasks, correct.
- §3 / §3a Why SVG + aesthetic boundary → captured in T3 ("The SVG aesthetic boundary" section, with the `asset_pass.notes` flag).
- §4 Pipeline placement → T3 header diagram + T4.
- §5 Components (4) → SKILL.md (T3), `art/*.svg` (T5), swap convention (T3), manifest tool (T1/T2).
- §5a Visual system first → T3 Step 0; recorded in `asset_pass.visual_system` → T2 schema + T3.
- §6 Data flow → T3 + T5 cover each arrow.
- §7 Swap mechanism (a/b/c + failure attribution) → T3 "The SVG-swap mechanism".
- §8 Status model + `asset_pass` + `assets[]` flip → T1 (status/transitions), T2 (`asset_pass` schema). Note confirmed: `assets[]` needs no schema change (free-string `origin`).
- §9 Validation (3 gates + validator advances `playable→styled`) → T4 + T5 Steps 3–4.
- §10 Testing (transition legality, schema accepts `asset_pass`/`origin:svg`, no regression, `skills.test` adds `asset`, ≈5–6 net new) → T1 (3 transition tests), T2 (3 schema tests), T3 (skills test). Net new = 6 + 1 edited assertion. ✓
- §11 Deliverable (run on a playable title, A/B, report attributing gaps) → T5.
- §12 Success criteria → T5 verifies all five.

**2. Placeholder scan:** No "TBD"/"add error handling"/"write tests for the above". All code/test/edit steps show literal content; the full `SKILL.md` is inline. The `art/*.svg` and `Main.gd` rewire are deliberately produced *during the proof run* (T5) following the skill prose — they cannot be pre-authored without the live game in hand, and the spec frames them as the run's output, not a code task. This is intentional, not a placeholder.

**3. Type/name consistency:** `STATUSES` six-element array matches the schema enum (both: concept, generated, validated, playable, styled, failed). `TRANSITIONS` keys cover all six statuses. `asset_pass` field names (`method`, `visual_system{palette,stroke,form,shading,scale}`, `reskinned`, `left_primitive`, `art_path`, `notes`) are identical across the schema (T2), the test fixture (T2), and the SKILL.md merge command (T3). The test helper `base()` returns a `concept`-status manifest, so transition tests construct `{...base(), status:"playable"|"styled"}` explicitly — correct.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-30-m1-asset-skill.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
