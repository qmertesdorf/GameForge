# Thematic Cohesion (`concept.theme` anchor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one optional, modality-neutral `theme` object to the `concept` manifest block and rewire every generator + the validator to honor it, so a title's visuals, audio, and (future) icon read as one coherent themed world by construction.

**Architecture:** Additive, non-breaking JSON-Schema change (`theme` is optional, so all existing manifests still validate) plus surgical prose edits to four skills. The `concept` skill derives `theme` first, then `art_direction` as its visual expression; `asset` and `audio` bind to `concept.theme` (the `audio` edit also fixes a dangling reference to a field that never existed); `validator` gains a cross-modal cohesion human-A/B line. The two active raster proof games get `theme` backfilled retroactively. No new tool; `tools/manifest.mjs` is untouched (its deep-merge already handles a new nested block).

**Tech Stack:** Node ESM, vitest, ajv (JSON Schema draft 2020-12), GDScript-adjacent Godot manifests. Tests run with `npx vitest run`.

---

## File Structure

- `schema/manifest.schema.json` — add the `theme` object under `concept.properties`. The single source of truth for manifest validity.
- `tools/manifest.test.mjs` — add three schema tests (theme accepted / themeless still valid / unknown theme prop rejected). The regression guard.
- `.claude/skills/concept/SKILL.md` — derive `theme` first, `art_direction` as its visual expression, no-contradiction contract.
- `.claude/skills/asset/SKILL.md` — note `art_direction` is the visual expression of `concept.theme`.
- `.claude/skills/audio/SKILL.md` — derive `mood_prompt`/`style_descriptors` from `concept.theme` (replaces the dangling non-existent-field reference).
- `.claude/skills/validator/SKILL.md` — cross-modal cohesion A/B line in Method 3 and Method 4 (+ forward note for the M2 packaging method).
- `manifests/creature-0001.json`, `manifests/crosser-0001.json` — backfill the `theme` block (via the manifest merge CLI).

Baseline before starting: `npx vitest run` → **69 passed**. Keep it green (it becomes 72 after Task 1).

---

## Task 1: Schema — the optional `theme` object on `concept`

**Files:**
- Modify: `schema/manifest.schema.json` (the `concept.properties` object, currently `schema/manifest.schema.json:17-24`)
- Test: `tools/manifest.test.mjs` (add to the `describe("validate", ...)` block, after the existing `audio_pass is optional` test near `tools/manifest.test.mjs:172`)

- [ ] **Step 1: Write the failing tests**

In `tools/manifest.test.mjs`, inside `describe("validate", () => { ... })`, immediately after the `test("audio_pass is optional ...")` test, add:

```javascript
  test("accepts a concept carrying a full theme object", () => {
    const m = validManifest();
    m.concept.theme = {
      premise: "a cozy autumn-woodland folktale",
      tone: "warm, gentle, a touch melancholy",
      mood_keywords: ["cozy", "organic", "storybook", "calm"],
      setting: "dappled autumn forest at golden hour"
    };
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("theme is optional (no regression for pre-theme manifests)", () => {
    const m = validManifest(); // concept has no theme
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("rejects an unknown key inside theme", () => {
    const m = validManifest();
    m.concept.theme = { premise: "x", bogus: true };
    expect(validate(m).valid).toBe(false);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: the "accepts a concept carrying a full theme object" and "rejects an unknown key inside theme" tests FAIL (the schema's `concept` block has `additionalProperties: false` and no `theme` property, so any `theme` is currently rejected as an unknown key). The "theme is optional" test passes already (it's the non-breaking guarantee). This proves the new property isn't yet allowed.

- [ ] **Step 3: Add the `theme` object to the schema**

In `schema/manifest.schema.json`, the `concept` block currently reads (lines ~14-25):

```json
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
```

Add a `theme` property (keep all existing properties; insert `theme` after `differentiation_notes`):

```json
    "concept": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "genre": { "type": "string" },
        "core_loop": { "type": "string" },
        "mechanics": { "type": "array", "items": { "type": "string" } },
        "art_direction": { "type": "string" },
        "target_platforms": { "type": "array", "items": { "type": "string" } },
        "differentiation_notes": { "type": "string" },
        "theme": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "premise": { "type": "string" },
            "tone": { "type": "string" },
            "mood_keywords": { "type": "array", "items": { "type": "string" } },
            "setting": { "type": "string" }
          }
        }
      }
    },
```

Note: `theme` is NOT added to any `required` list (the `concept` block has no `required` list at all), so themeless manifests stay valid — the non-breaking guarantee. `additionalProperties: false` inside `theme` is what makes the unknown-key test pass.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: PASS. The `validate` describe block goes from 14 to 17 tests; full file now reports 36 tests in that file.

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: **72 passed** (was 69; +3 from this task). No other file changed.

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.test.mjs
git commit -m "feat(schema): add optional concept.theme object (cross-modal anchor)"
```

---

## Task 2: `concept` skill — derive `theme` first, `art_direction` as its expression

**Files:**
- Modify: `.claude/skills/concept/SKILL.md` (the Steps list, currently step 2 "Derive the concept." at `.claude/skills/concept/SKILL.md:21`)

No automated test asserts skill prose content (`tools/skills.test.mjs` only checks frontmatter name + description length). Verification is: vitest stays green and the prose reads correctly. This is a documentation edit, not TDD.

- [ ] **Step 1: Insert a theme-first step before the concept derivation**

In `.claude/skills/concept/SKILL.md`, the Steps section currently opens:

```markdown
## Steps

1. **Read existing manifests.** ...

2. **Derive the concept.** From the prompt, decide:
   - `genre` — short noun phrase ...
```

Insert a new sub-step at the top of step 2's list (before `genre`), so step 2 begins by deriving the theme. Replace the line:

```markdown
2. **Derive the concept.** From the prompt, decide:
   - `genre` — short noun phrase (e.g. "endless runner", "match-3", "top-down shooter").
```

with:

```markdown
2. **Derive the concept.** From the prompt, decide:
   - `theme` — **decide this FIRST, before anything visual.** The one modality-neutral world the whole title expresses, recorded as `concept.theme`: `premise` (what the game *is about* as a world — e.g. "a cozy autumn-woodland folktale of a small forest spirit foraging glowing seeds"), `tone` (the emotional register — e.g. "warm, gentle, a touch melancholy"), `mood_keywords` (2–4 tags every modality can key off — e.g. `["cozy", "organic", "storybook", "calm"]`), and `setting` (the place/time — e.g. "dappled autumn forest at golden hour"). This is the cross-modal anchor: visuals, audio, and (at M2) the store icon all express it, so the title reads as one coherent world rather than three independent interpretations. Be specific — a vague theme is the upstream cause of a cross-modal cohesion failure (visuals say one thing, audio another).
   - `genre` — short noun phrase (e.g. "endless runner", "match-3", "top-down shooter").
```

- [ ] **Step 2: Make `art_direction` the visual expression of the theme**

In the same step-2 list, the `art_direction` bullet currently ends with:

```markdown
   - `art_direction` — a coherent primitive-art direction that `builder` can *execute*, not just a palette. Specify: a named palette + shape language, a **background treatment** (so there's no dead space — e.g. parallax lines/stars/gradient), and at least one **motion/feedback beat** (e.g. "screen flash + shake on death, score pulses on milestone"). Example: "neon vector on near-black; bright cyan/magenta shapes with additive glow; faint parallax grid scrolling behind; white flash + shake on crash." Be specific — vague art direction is the top cause of bland output.
```

Append a sentence to that bullet (keep all existing text, add to the end):

```markdown
   - `art_direction` — a coherent primitive-art direction that `builder` can *execute*, not just a palette. Specify: a named palette + shape language, a **background treatment** (so there's no dead space — e.g. parallax lines/stars/gradient), and at least one **motion/feedback beat** (e.g. "screen flash + shake on death, score pulses on milestone"). Example: "neon vector on near-black; bright cyan/magenta shapes with additive glow; faint parallax grid scrolling behind; white flash + shake on crash." Be specific — vague art direction is the top cause of bland output. **`art_direction` is the *visual expression* of `theme` — it must not contradict it** (a "spooky" theme cannot have a "cheerful pastel" art_direction; a "cozy storybook" theme must not render as "hard neon arcade"). Derive it *from* the theme you just set.
```

- [ ] **Step 3: Verify the prose reads correctly**

Re-read `.claude/skills/concept/SKILL.md` step 2. Confirm `theme` appears as the first bullet, `art_direction` references it, and no other steps broke. Run `npx vitest run` → **72 passed** (skill prose doesn't affect tests, but confirm no accidental file damage).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/concept/SKILL.md
git commit -m "feat(concept): derive theme first, art_direction as its visual expression"
```

---

## Task 3: `asset` + `audio` skills — bind to `concept.theme`

**Files:**
- Modify: `.claude/skills/asset/SKILL.md` (the "Choosing the method" / "Inputs" region near `.claude/skills/asset/SKILL.md:14-24`)
- Modify: `.claude/skills/audio/SKILL.md` (Step 1, `.claude/skills/audio/SKILL.md:15` — the dangling-field line)

Prose edits; verification is vitest-green + correct read.

- [ ] **Step 1: `asset` — note `art_direction` expresses `concept.theme`**

In `.claude/skills/asset/SKILL.md`, the "Choosing the method (branch on `concept.art_direction`)" section opens:

```markdown
## Choosing the method (branch on `concept.art_direction`)

This skill has **two methods**, picked from `art_direction`. Both share *all* the rewiring craft below ...
```

Insert one sentence immediately after that heading, before "This skill has two methods":

```markdown
## Choosing the method (branch on `concept.art_direction`)

`art_direction` is the **visual expression of `concept.theme`** (the title's modality-neutral world). The visual system you derive below must read as *that theme's world* — the same premise/tone/setting the audio and (at M2) the icon also express — not a free-standing aesthetic. Honor the theme; do not reinterpret it.

This skill has **two methods**, picked from `art_direction`. Both share *all* the rewiring craft below ...
```

- [ ] **Step 2: `audio` — replace the dangling-field reference with `concept.theme`**

In `.claude/skills/audio/SKILL.md`, Step 1 currently begins:

```markdown
## 1. Derive the audio system (do this first, once)
Read `concept.art_direction`, `concept.genre`, and theme. Author a shared `audio_system`:
```

The phrase "and theme" references a field that did not exist until this change. Replace those two lines with:

```markdown
## 1. Derive the audio system (do this first, once)
Read **`concept.theme`** — the title's modality-neutral world (premise/tone/mood_keywords/setting) — as the primary anchor, with `concept.genre` for form. The audio identity expresses the *same theme* the visuals do, sonically. Author a shared `audio_system`:
```

Then, in the same Step 1, the `mood_prompt` bullet currently reads:

```markdown
- `mood_prompt`: one shared mood sentence threaded into every clip prompt for coherence (the audio analog of the visual prompt scaffold) — e.g. "warm, organic, gentle woodland atmosphere".
```

Append a clause tying it to the theme (keep the existing text):

```markdown
- `mood_prompt`: one shared mood sentence threaded into every clip prompt for coherence (the audio analog of the visual prompt scaffold), derived from `concept.theme`'s `tone` + `mood_keywords` — e.g. for a "cozy autumn-woodland" theme, "warm, organic, gentle woodland atmosphere".
```

And the `style_descriptors` bullet:

```markdown
- `style_descriptors`: 2–4 tags (e.g. `["ambient", "soft", "acoustic"]` or `["chiptune", "8-bit", "upbeat"]`).
```

Append:

```markdown
- `style_descriptors`: 2–4 tags drawn from / consistent with `concept.theme.mood_keywords` (e.g. a "cozy/organic/storybook" theme → `["ambient", "soft", "acoustic"]`; a "retro/hard-edged/arcade" theme → `["chiptune", "8-bit", "upbeat"]`).
```

- [ ] **Step 3: Verify both prose edits**

Re-read both files' edited sections. Confirm `audio` no longer says "and theme" (dangling) anywhere and now names `concept.theme`. Run `npx vitest run` → **72 passed**.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/asset/SKILL.md .claude/skills/audio/SKILL.md
git commit -m "feat(asset,audio): bind visual + audio identity to concept.theme (fix audio's dangling field ref)"
```

---

## Task 4: `validator` — cross-modal cohesion A/B line

**Files:**
- Modify: `.claude/skills/validator/SKILL.md` (Method 3 human A/B step at `.claude/skills/validator/SKILL.md:74`; Method 4 at `.claude/skills/validator/SKILL.md:87-97`)

Prose edits; verification is vitest-green + correct read.

- [ ] **Step 1: Add the cohesion check to Method 3's human A/B**

In `.claude/skills/validator/SKILL.md`, Method 3 step 3 currently reads:

```markdown
3. **Human A/B playtest** — the owner confirms the re-skin (a) looks more designed than the primitive original, (b) **reads as one coherent visual system** rather than mismatched assets, and (c) plays identically.
```

Add a cross-modal clause (active when audio is also present). Replace that line with:

```markdown
3. **Human A/B playtest** — the owner confirms the re-skin (a) looks more designed than the primitive original, (b) **reads as one coherent visual system** rather than mismatched assets, and (c) plays identically.
   - **Cross-modal cohesion (when ≥2 modalities are present — e.g. the title also carries an `audio_pass`, or at M2 a `store_pass`):** confirm the visuals, audio, and (at M2) the icon **read as one themed world** — the same premise/tone/setting from `concept.theme` — not three independent interpretations. On failure, attribute it to a **`concept.theme` gap** (the anchor was too vague to align the modalities) or to a **skill that ignored the theme** (e.g. "audio: chose a chiptune mood for a cozy-storybook theme — ignored `concept.theme.tone`") — a specific, fixable prose cause, exactly like the within-modality cohesion finding above.
```

- [ ] **Step 2: Add the cohesion check to Method 4 (audio)**

In `.claude/skills/validator/SKILL.md`, Method 4's checklist currently ends at item 5 (IP-safety) followed by:

```markdown
5. **IP-safety.** Confirm no recipe prompt names an artist or copyrighted track; music negative prompt excludes vocals unless intended.

Record results in `manifest.validation.issues` as needed. Audio validation does not block the visual pass and vice-versa.
```

Insert a new item 6 before the "Record results" paragraph:

```markdown
5. **IP-safety.** Confirm no recipe prompt names an artist or copyrighted track; music negative prompt excludes vocals unless intended.
6. **Cross-modal cohesion (when the title also has an `asset_pass`).** Confirm the audio and the visuals **read as one themed world** — the same premise/tone/setting from `concept.theme`. A cozy-storybook look with an aggressive arcade soundtrack is a failure: attribute it to a `concept.theme` gap or to the `audio`/`asset` skill that ignored the theme, and record it. (Cohesion is a human judgment call, like every aesthetic gate — not automatable.)

Record results in `manifest.validation.issues` as needed. Audio validation does not block the visual pass and vice-versa.
```

- [ ] **Step 3: Verify the prose**

Re-read Method 3 and Method 4. Confirm the cohesion line appears in both, references `concept.theme`, and is gated on "≥2 modalities present." Run `npx vitest run` → **72 passed**.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/validator/SKILL.md
git commit -m "feat(validator): cross-modal cohesion A/B line in Methods 3 + 4"
```

---

## Task 5: Backfill `theme` into the two active raster proof games

**Files:**
- Modify: `manifests/creature-0001.json` (via `node tools/manifest.mjs merge`)
- Modify: `manifests/crosser-0001.json` (via `node tools/manifest.mjs merge`)

These two games already cohere (creature = painterly warm-woodland visuals + warm-woodland audio; crosser = pixel-art + chiptune). Backfilling `theme` records that retroactively and makes them valid inputs to the future theme-aware M2 packager. The older POC games (`runner-0002`, match-3, shooter) are left untouched — `theme` is optional and they are SVG-done, not M2 targets.

- [ ] **Step 1: Backfill `creature-0001`**

The merge CLI takes a JSON string. On Windows PowerShell, single-quote the JSON to avoid escaping pain. Run:

```bash
node tools/manifest.mjs merge creature-0001 '{"concept":{"theme":{"premise":"a cozy autumn-woodland folktale of a small forest spirit foraging glowing seeds","tone":"warm, gentle, a touch melancholy","mood_keywords":["cozy","organic","storybook","calm"],"setting":"dappled autumn forest at golden hour"}}}'
```

(The deep-merge adds `theme` under `concept` without disturbing `genre`/`core_loop`/`art_direction`/etc.)

- [ ] **Step 2: Backfill `crosser-0001`** (retro arcade / hard-edged pixel world — deliberately the opposite register from creature-0001)

```bash
node tools/manifest.mjs merge crosser-0001 '{"concept":{"theme":{"premise":"a snappy retro arcade lane-crossing dash through scrolling hazards","tone":"bright, punchy, high-energy","mood_keywords":["retro","arcade","crisp","8-bit"],"setting":"a chunky pixel landscape of grass and dirt lanes under flat daylight"}}}'
```

- [ ] **Step 3: Validate both manifests**

Run:

```bash
node tools/manifest.mjs validate creature-0001
node tools/manifest.mjs validate crosser-0001
```

Expected: `creature-0001 OK` and `crosser-0001 OK`. (Status stays `validated` for both — merge does not change status; this is documentation, not a regen.)

- [ ] **Step 4: Confirm the theme landed and nothing else changed**

Run: `git diff --stat manifests/creature-0001.json manifests/crosser-0001.json`
Expected: only additions inside the `concept` block of each (the `theme` object + `updated_at` bump). Spot-check with `git diff manifests/creature-0001.json` that `art_direction`, `core_loop`, etc. are untouched.

- [ ] **Step 5: Run the full suite once more**

Run: `npx vitest run`
Expected: **72 passed**.

- [ ] **Step 6: Commit**

```bash
git add manifests/creature-0001.json manifests/crosser-0001.json
git commit -m "feat(manifests): backfill concept.theme into creature-0001 + crosser-0001"
```

---

## Final: push to main

After all five tasks commit and `npx vitest run` reports **72 passed**:

```bash
git push origin main
```

(Owner has standing authorization to push to `main` — the per-push-ask rule is retired.)

---

## Self-Review (run after writing, before execution)

**Spec coverage** — every spec section maps to a task:
- Spec §3 (schema, additive/non-breaking) → Task 1 ✓
- Spec §4 (concept derives theme first + no-contradiction contract) → Task 2 ✓
- Spec §5 (asset binds to theme; audio binds to theme + fixes dangling field) → Task 3 ✓
- Spec §6 (validator cross-modal cohesion gate, Methods 3/4, M2 forward note) → Task 4 ✓ (M2 packaging method is folded in when M2 lands — noted in Task 4 Step 1's parenthetical; the spec defers the actual M2 method to the M2 spec)
- Spec §7 (backfill creature-0001 + crosser-0001; leave older POC games) → Task 5 ✓
- Spec §8 (schema test: accepted / themeless valid / unknown rejected; no new tool; vitest green) → Task 1 Steps 1–5 ✓
- Spec §9 scope exclusions (no M2, no regen, no older-game backfill, no automating cohesion) → respected; the validator line stays a human A/B ✓

**Placeholder scan** — no TBD/TODO/"add appropriate X"; every code/prose step shows the exact text. ✓

**Type/name consistency** — `theme` property name and its four sub-fields (`premise`, `tone`, `mood_keywords`, `setting`) are identical across the schema (Task 1), the concept skill prose (Task 2), and both backfill payloads (Task 5). `mood_keywords` is the array; the other three are strings, matching the schema. ✓
