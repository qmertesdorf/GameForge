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
