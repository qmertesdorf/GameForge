# A/B-Round-1 Skill Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 4 recurring skill gaps from A/B Round 1 — asset visual incohesion (#1) + unrecorded background gap (#2), audio SFX not theme-bound (#3) + BGM-never-plays bug (#4) — by editing `asset/SKILL.md` and `audio/SKILL.md`, backed by two additive optional schema fields.

**Architecture:** Two new optional string fields record the new derived systems (`asset_pass.visual_system.world_bible`, `audio_pass.audio_system.sonic_character`); both go inside existing `additionalProperties:false` objects, so they are TDD'd via schema validation (a manifest carrying the field must validate; the existing reject-unknown-sibling tests prove the closed object still bites). The two SKILL.md files are then edited to derive and bind those systems. Background generation stays M1.7-deferred — the asset skill only *records* the gap. No manifest backfill; the A/B re-pass is owner-gated.

**Tech Stack:** Node ESM, vitest (`npm test` → `vitest run`), JSON Schema (Ajv via `tools/manifest.mjs`), Markdown skill files.

**Spec:** `docs/superpowers/specs/2026-06-01-ab-round1-skill-fixes-design.md`

---

## File Structure

- `schema/manifest.schema.json` — add 2 optional string fields (Tasks 1, 2).
- `tools/manifest.test.mjs` — add accept-with + reject-unknown-sibling tests for each field (Tasks 1, 2). Validation is via `validate()` imported from `tools/manifest.mjs`, which loads this schema.
- `.claude/skills/asset/SKILL.md` — findings #1 (world bible, method-neutral) + #2 (record background gap) (Task 3).
- `.claude/skills/audio/SKILL.md` — findings #3 (SFX `sonic_character`) + #4 (BGM autoplay/deferred-play + levels + verify) (Task 4).

No tool changes, no `concept`/`builder` edits, no manifest backfill, no background generation.

---

## Task 1: Schema field `asset_pass.visual_system.world_bible`

**Files:**
- Modify: `schema/manifest.schema.json:100` (inside `asset_pass.properties.visual_system.properties`)
- Test: `tools/manifest.test.mjs` (inside the `describe("validate", …)` block)

- [ ] **Step 1: Write the failing tests**

Add these two tests immediately after the existing `test("rejects an unknown key inside visual_system.style", …)` test (currently ends around line 146) in `tools/manifest.test.mjs`:

```js
  test("accepts an asset_pass whose visual_system carries world_bible", () => {
    const m = validManifest();
    m.status = "styled";
    m.assets = [{ type: "sprite", name: "hero", source: "art/hero.png", origin: "raster" }];
    m.asset_pass = {
      method: "raster",
      visual_system: {
        world_bible: "one storybook autumn-woodland: every actor is a soft felt forest creature; hazards are bramble/thorn from the same world",
        palette: ["#1a1226", "#e0b15a"],
        form: "stout painted creatures, soft edges",
        shading: "painterly, single warm key light",
        scale: "512px masters downscaled to footprint"
      },
      reskinned: ["hero", "hazard"],
      art_path: "games/creature-0001/art/"
    };
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("rejects an unknown key inside visual_system", () => {
    const m = validManifest();
    m.status = "styled";
    m.asset_pass = {
      method: "raster",
      visual_system: { world_bible: "x", bogus: true }
    };
    expect(validate(m).valid).toBe(false);
  });
```

- [ ] **Step 2: Run the tests to verify the first fails**

Run: `npx vitest run tools/manifest.test.mjs -t "world_bible"`
Expected: the accept-with test FAILS — `validate(m).valid` is `false` because `additionalProperties:false` on `visual_system` rejects the unknown `world_bible` key. (The reject-unknown-sibling test passes already.)

- [ ] **Step 3: Add the schema field**

In `schema/manifest.schema.json`, line 100 currently reads:

```json
            "prompt_scaffold": { "type": "string" },
```

Add the new property immediately after it (so the block becomes):

```json
            "prompt_scaffold": { "type": "string" },
            "world_bible": { "type": "string" },
```

- [ ] **Step 4: Run the tests to verify both pass**

Run: `npx vitest run tools/manifest.test.mjs -t "world_bible"`
Expected: both tests PASS.

- [ ] **Step 5: Run the full manifest suite (no regression)**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: all PASS (the existing styled/raster manifest tests still validate; the 9 committed manifests are unaffected since the field is optional).

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.test.mjs
git commit -m "feat(schema): asset_pass.visual_system.world_bible (finding #1 record)"
```

---

## Task 2: Schema field `audio_pass.audio_system.sonic_character`

**Files:**
- Modify: `schema/manifest.schema.json:158` (inside `audio_pass.properties.audio_system.properties`)
- Test: `tools/manifest.test.mjs` (inside the `describe("validate", …)` block)

- [ ] **Step 1: Write the failing tests**

Add these two tests immediately after the existing `test("audio_pass is optional (no regression for pre-audio manifests)", …)` test (currently around line 174) in `tools/manifest.test.mjs`:

```js
  test("accepts an audio_pass whose audio_system carries sonic_character", () => {
    const m = validManifest();
    m.status = "scored";
    m.audio_pass = {
      method: "audio",
      audio_system: {
        model: "stable-audio-open-1.0",
        mood_prompt: "warm gentle woodland atmosphere",
        style_descriptors: ["ambient", "soft"],
        sonic_character: "soft organic wooden/leaf/cloth taps, gentle, no electronic transients"
      }
    };
    expect(validate(m)).toEqual({ valid: true, errors: [] });
  });

  test("rejects an unknown key inside audio_system", () => {
    const m = validManifest();
    m.status = "scored";
    m.audio_pass = {
      method: "audio",
      audio_system: { sonic_character: "x", bogus: true }
    };
    expect(validate(m).valid).toBe(false);
  });
```

- [ ] **Step 2: Run the tests to verify the first fails**

Run: `npx vitest run tools/manifest.test.mjs -t "sonic_character"`
Expected: the accept-with test FAILS — `additionalProperties:false` on `audio_system` rejects the unknown `sonic_character` key. (The reject-unknown-sibling test passes already.)

- [ ] **Step 3: Add the schema field**

In `schema/manifest.schema.json`, lines 156–158 currently read:

```json
            "model": { "type": "string" },
            "mood_prompt": { "type": "string" },
            "style_descriptors": { "type": "array", "items": { "type": "string" } }
```

`style_descriptors` is the last property (no trailing comma). Add a comma to it and append the new property:

```json
            "model": { "type": "string" },
            "mood_prompt": { "type": "string" },
            "style_descriptors": { "type": "array", "items": { "type": "string" } },
            "sonic_character": { "type": "string" }
```

- [ ] **Step 4: Run the tests to verify both pass**

Run: `npx vitest run tools/manifest.test.mjs -t "sonic_character"`
Expected: both tests PASS.

- [ ] **Step 5: Run the full manifest suite (no regression)**

Run: `npx vitest run tools/manifest.test.mjs`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add schema/manifest.schema.json tools/manifest.test.mjs
git commit -m "feat(schema): audio_pass.audio_system.sonic_character (finding #3 record)"
```

---

## Task 3: `asset/SKILL.md` — world bible (#1) + record background gap (#2)

This is a prose task: no new unit test exists for skill prose. Verification is (a) the `skills.test.mjs` regression (frontmatter/registration still valid) and (b) a manual checklist confirming each required edit landed. Each edit below is an exact-match `Edit`.

**Files:**
- Modify: `.claude/skills/asset/SKILL.md`

- [ ] **Step 1: Edit A1 — add the world-bible bullet as the FIRST item in Step 0**

Find:

```
Before authoring **any** SVG, write the system down explicitly from `concept.art_direction`:

- **Palette** — a fixed 3–5 colour set with named roles (primary, accent, danger, background, …). Every fill/stroke comes from this set.
```

Replace with:

```
Before authoring **any** SVG, write the system down explicitly from `concept.art_direction`:

- **World/character bible (derive this FIRST)** — from `concept.theme.setting` + `premise`, pin **one fictional world and one character family** before any subject or silhouette is chosen. Every actor — hero, hazard, pickup — is an *inhabitant of that one world*, drawn from that one family (same materials, same era/genre, same "what kind of thing is this"). The hero and the hazard must read as belonging together — **not a cyan robot vs a red ogre** (the crosser-0001 finding). This is the *subject-level* sibling of the palette/form/shading below, which pin only *how* things are rendered, never *what world they are from*; that missing sibling is what let two individually-clean sprites read as different worlds. Recorded verbatim in `asset_pass.visual_system.world_bible`. Applies to **both** methods.
- **Palette** — a fixed 3–5 colour set with named roles (primary, accent, danger, background, …). Every fill/stroke comes from this set.
```

- [ ] **Step 2: Edit A2 — tie the SVG signature silhouette to the one character family**

Find:

```
Pick one and hold it. Then give **each** actor *one* signature silhouette detail (a directional notch on the player, an inner facet on a pickup) — staying within the form language.
```

Replace with:

```
Pick one and hold it. Then give **each** actor *one* signature silhouette detail (a directional notch on the player, an inner facet on a pickup) — staying within the form language **and within the one character family from the world bible** (a variation on the shared family, never an unrelated shape).
```

- [ ] **Step 3: Edit A3 — record the background gap in section c)**

Find:

```
**c) What stays primitive.** Effects (glow halos, particles, screen-shake, squash/stretch, flash) stay code — they are *motion/juice*, not art. Backgrounds may stay procedural (parallax grid/stars) **or** get a tiling SVG — your judgment from `art_direction`. **Record which entities you re-skinned vs. left primitive** so a partial re-skin is a legible choice, not a silent gap.
```

Replace with:

```
**c) What stays primitive.** Effects (glow halos, particles, screen-shake, squash/stretch, flash) stay code — they are *motion/juice*, not art. Backgrounds may stay procedural (parallax grid/stars) **or** get a tiling SVG — your judgment from `art_direction`. **Record which entities you re-skinned vs. left primitive** so a partial re-skin is a legible choice, not a silent gap. **A background left primitive is a cohesion gap, not a free pass:** sprites floating on untextured primitive bands undercut the one-rendered-system goal, so when you leave the background primitive (the M1.7-deferred default — a *static themed backdrop* is in-scope in principle, but its generation waits for M1.7), you **must** list it in `left_primitive` and name it in `asset_pass.notes` as a known M1.7-deferred cohesion gap — never silently omit it.
```

- [ ] **Step 4: Edit A4 — bind each raster recipe subject to the bible**

Find:

```
1. **Recipe** — compose the JSON recipe: `prompt` = `scaffold + this actor's subject`; plus `negative`, `seed`, `sampler`, `steps`, `cfg`, `checkpoint`, optional `lora`, `layerdiffuse: true`, and `master_resolution` (see Resolution below).
```

Replace with:

```
1. **Recipe** — compose the JSON recipe: `prompt` = `scaffold + this actor's subject`, where the subject is **this actor as a member of the world-bible family** (Step 0) — never a free-standing description; plus `negative`, `seed`, `sampler`, `steps`, `cfg`, `checkpoint`, optional `lora`, `layerdiffuse: true`, and `master_resolution` (see Resolution below).
```

- [ ] **Step 5: Edit A5 — name subject-world divergence in the cohesion note**

Find:

```
**"Each sprite is fine but they don't cohere"** is the same *primary failure* the SVG method guards against — here prevented by the profile + shared scaffold + fixed params, **not** by independent per-actor prompts. Incoherence within one game is a finding about the **scaffold/profile**, never about an individual PNG.
```

Replace with:

```
**"Each sprite is fine but they don't cohere"** is the same *primary failure* the SVG method guards against — here prevented by the **world bible** + profile + shared scaffold + fixed params, **not** by independent per-actor prompts. There are two kinds of incoherence: *style* divergence (caught by the profile/scaffold/params) and **subject-world divergence** (caught by the world bible) — a cyan-robot hero next to a red-ogre hazard is the latter, a finding about the **world bible**, never about an individual PNG.
```

- [ ] **Step 6: Edit A6 — add `world_bible` to the svg recording example**

Find:

```
   node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"svg\",\"visual_system\":{\"palette\":[...],\"stroke\":\"...\",\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\"},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\"}}"
```

Replace with:

```
   node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"svg\",\"visual_system\":{\"world_bible\":\"...\",\"palette\":[...],\"stroke\":\"...\",\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\"},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\"}}"
```

- [ ] **Step 7: Edit A7 — add `world_bible` to the raster recording example**

Find:

```
node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"raster\",\"visual_system\":{\"palette\":[...],\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\",\"prompt_scaffold\":\"...\",\"style\":{\"checkpoint\":\"...\",\"loras\":[...],\"style_prompt\":\"...\"}},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\",\"recipes\":[{\"name\":\"hero\",\"checkpoint\":\"...\",\"prompt\":\"...\",\"negative\":\"...\",\"seed\":123,\"sampler\":\"...\",\"steps\":30,\"cfg\":6.5,\"master_resolution\":1024,\"layerdiffuse\":true,\"lora\":\"...\",\"import_settings\":{\"mipmaps\":true,\"filter\":\"linear\",\"compression\":\"lossless\"}}]}}"
```

Replace with:

```
node tools/manifest.mjs merge <id> "{\"asset_pass\": {\"method\":\"raster\",\"visual_system\":{\"world_bible\":\"...\",\"palette\":[...],\"form\":\"...\",\"shading\":\"...\",\"scale\":\"...\",\"prompt_scaffold\":\"...\",\"style\":{\"checkpoint\":\"...\",\"loras\":[...],\"style_prompt\":\"...\"}},\"reskinned\":[...],\"left_primitive\":[...],\"art_path\":\"games/<id>/art/\",\"notes\":\"...\",\"recipes\":[{\"name\":\"hero\",\"checkpoint\":\"...\",\"prompt\":\"...\",\"negative\":\"...\",\"seed\":123,\"sampler\":\"...\",\"steps\":30,\"cfg\":6.5,\"master_resolution\":1024,\"layerdiffuse\":true,\"lora\":\"...\",\"import_settings\":{\"mipmaps\":true,\"filter\":\"linear\",\"compression\":\"lossless\"}}]}}"
```

- [ ] **Step 8: Verify the regression suite + manual checklist**

Run: `npx vitest run tools/skills.test.mjs`
Expected: PASS (skill frontmatter/registration unchanged).

Manual checklist — grep to confirm each edit landed:

Run: `grep -c "World/character bible\|world-bible family\|world_bible\|subject-world divergence\|cohesion gap, not a free pass" .claude/skills/asset/SKILL.md`
Expected: a count of **7 or more** (the phrases appear across Edits A1–A7).

- [ ] **Step 9: Commit**

```bash
git add .claude/skills/asset/SKILL.md
git commit -m "fix(asset): world/character bible from concept.theme + record bg gap (#1,#2)"
```

---

## Task 4: `audio/SKILL.md` — SFX sonic_character (#3) + BGM bug (#4)

Prose task, same verification model as Task 3 (regression + manual checklist). Each edit is an exact-match `Edit`.

**Files:**
- Modify: `.claude/skills/audio/SKILL.md`

- [ ] **Step 1: Edit B1 — add the `sonic_character` bullet to §1**

Find:

```
- `style_descriptors`: 2–4 tags drawn from / consistent with `concept.theme.mood_keywords` (e.g. a "cozy/organic/storybook" theme → `["ambient", "soft", "acoustic"]`; a "retro/hard-edged/arcade" theme → `["chiptune", "8-bit", "upbeat"]`).
```

Replace with:

```
- `style_descriptors`: 2–4 tags drawn from / consistent with `concept.theme.mood_keywords` (e.g. a "cozy/organic/storybook" theme → `["ambient", "soft", "acoustic"]`; a "retro/hard-edged/arcade" theme → `["chiptune", "8-bit", "upbeat"]`).
- `sonic_character`: the **SFX sound-material/timbre vocabulary** derived from `concept.theme` — the audio sibling of the visual world bible, and the thing that keeps SFX *on theme* instead of defaulting to generic explosive transients. Name the materials and timbre: a cozy/organic theme → "soft organic wooden/leaf/cloth taps, gentle, no electronic transients"; a retro/arcade theme → "crisp 8-bit square/triangle-wave blips, clean chip transients". Recorded verbatim in `audio_pass.audio_system.sonic_character`. **`mood_prompt`/`style_descriptors` steer the music mood; `sonic_character` governs the SFX** — both are required.
```

- [ ] **Step 2: Edit B2 — reframe the SFX recipe defaults around `sonic_character`**

Find:

```
- **SFX**: `kind:"sfx"`, `format:"wav"`, `duration_s` **1.0–2.0** (`EmptyLatentAudio` enforces a 1.0 s minimum — do not go below), `loop:false`, `steps` ~8, `cfg` ~5–6 — short, punchy, single sound; negative prompt excludes "music, melody, voice, speech". (cfg too high can clip the transient.)
```

Replace with:

```
- **SFX**: `kind:"sfx"`, `format:"wav"`, `duration_s` **1.0–2.0** (`EmptyLatentAudio` enforces a 1.0 s minimum — do not go below), `loop:false`, `steps` ~8, `cfg` ~5–6. Each SFX prompt = `mood_prompt` + **`sonic_character`** + the clip-specific event description. The *envelope* is theme-neutral — **short, single-shot** (~1–2 s) — but the **timbre/material MUST come from `sonic_character`**: do **not** default to a punchy/explosive transient. An aggressive/electronic/explosive SFX character that ignores `sonic_character` is the **finding-#3 failure** (the same explosive palette was wrong for *both* a cozy-woodland and a bright-arcade theme) and is attributable to this step. The negative prompt always excludes "music, melody, voice, speech", **plus a theme-aware exclusion**: a cozy/organic theme adds "explosion, harsh, distortion, aggressive, electronic"; an arcade theme keeps chip transients but still excludes "explosion, noise burst". (cfg too high can clip the transient.)
```

- [ ] **Step 3: Edit B3 — fix the BGM start + add a levels bullet in §5**

Find:

```
- Music: `play()` on scene ready / loop start. SFX: `play()` from the mapped `signal`/call site, replayable (call `play()` each event; for rapid repeats consider a small pool or `AudioStreamPlayer` per channel).
```

Replace with:

```
- **Music — start it so it actually plays.** Set **`autoplay = true` on the music `AudioStreamPlayer` *before* `add_child`**, or call `play()` **deferred/awaited a frame after** `add_child` (`await get_tree().process_frame` then `play()`, or `call_deferred("play")`). An immediate in-`_ready` `play()` called the **same frame** as `add_child` does **not** reliably start the stream — this is the confirmed **finding-#4 bug** (`MusicAmbient.playing=false, pos=0` after 90 frames); SFX escaped it only because they fire later in gameplay.
- **Levels:** set the music `volume_db` deliberately so the bed is **audible but sits under** the SFX — do not bury it (the proof bed was mixed ~13 dB under SFX *and* not playing). Balance the two.
- SFX: `play()` from the mapped `signal`/call site, replayable (call `play()` each event; for rapid repeats consider a small pool or `AudioStreamPlayer` per channel).
```

- [ ] **Step 4: Edit B4 — note `sonic_character` in the §6 record step**

Find:

```
## 6. Record `audio_pass` and advance status
Merge an `audio_pass` block (`method:"audio"`, `audio_system`, `recipes`, `events`, `notes`) via the manifest tool, then `node tools/manifest.mjs set-status <id> scored`.
```

Replace with:

```
## 6. Record `audio_pass` and advance status
Merge an `audio_pass` block (`method:"audio"`, `audio_system` — including `sonic_character` — `recipes`, `events`, `notes`) via the manifest tool, then `node tools/manifest.mjs set-status <id> scored`.
```

- [ ] **Step 5: Edit B5 — require the validator/owner to confirm the bed is actually playing (§7)**

Find:

```
## 7. Hand off to validator
Run the validator's audio method to confirm files import, players reference valid streams, and SFX fire on events.
```

Replace with:

```
## 7. Hand off to validator
Run the validator's audio method to confirm files import, players reference valid streams, and SFX fire on events — **and that the music bed is actually playing.** Confirm `MusicAmbient.playing == true` with an advancing `get_playback_position()` a few frames in, not merely that the node exists and is wired (a wired bed can still be silent — that is exactly the finding-#4 bug, caught by this probe).
```

- [ ] **Step 6: Verify the regression suite + manual checklist**

Run: `npx vitest run tools/skills.test.mjs`
Expected: PASS (skill frontmatter/registration unchanged).

Manual checklist — grep to confirm each edit landed:

Run: `grep -c "sonic_character\|autoplay = true\|finding-#4\|finding-#3\|volume_db\|playing == true" .claude/skills/audio/SKILL.md`
Expected: a count of **8 or more** (`sonic_character` appears 3×, plus the other phrases across B2–B5).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/audio/SKILL.md
git commit -m "fix(audio): SFX sonic_character from theme + BGM autoplay/levels (#3,#4)"
```

---

## Task 5: Final full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run: `npm test`
Expected: all PASS — 136 prior tests + 4 new (2 per schema field) = **140 passing**, 0 failing.

- [ ] **Step 2: Re-validate every committed manifest (no regression)**

Run: `for f in manifests/*.json; do node tools/manifest.mjs validate "$(basename "${f%.json}")"; done`
Expected: each prints `<id> OK` (all 9 still valid — the new fields are optional and absent from them).

If any step fails, stop and fix before claiming completion.

---

## Self-Review

**Spec coverage:**
- Part A field 1 (`world_bible`) → Task 1. ✓
- Part A field 2 (`sonic_character`) → Task 2. ✓
- Part A "accept-with / accept-without / reject-unknown-sibling" → Tasks 1/2 add accept-with + reject-sibling; accept-without is covered by the pre-existing styled/scored manifest tests (called out in Task 1/2 Step 5). ✓
- Part B #1 (world bible, method-neutral, raster subject binding, svg silhouette) → Task 3 Edits A1, A2, A4, A5. ✓
- Part B #2 (record background gap) → Task 3 Edit A3. ✓
- Part B recording examples carry `world_bible` → Task 3 Edits A6, A7. ✓
- Part C #3 (sonic_character §1 + §3 reframe + theme-aware negative + record) → Task 4 Edits B1, B2, B4. ✓
- Part C #4 (autoplay/deferred-play, levels, verify-playing) → Task 4 Edits B3, B5. ✓
- "vitest stays green / all 9 manifests valid" → Task 5. ✓
- Out-of-scope (no backfill, A/B re-pass owner-gated) → respected: no task touches existing manifests or claims a re-pass.

**Placeholder scan:** No "TBD/TODO"; every code/prose step shows exact find/replace text or test code. The `...` inside the recording-example merge strings are literal placeholders that exist in the skill prose itself (author-fills-in), not plan gaps.

**Type/name consistency:** Field names `world_bible` and `sonic_character` are spelled identically in schema, tests, skill prose, and merge examples across all tasks. Both placed inside the correct `additionalProperties:false` object (`visual_system` / `audio_system`).
