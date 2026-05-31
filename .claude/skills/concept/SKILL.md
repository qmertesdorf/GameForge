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
   - `core_loop` — one or two sentences describing the second-to-second loop AND its **difficulty curve** (e.g. "tap to jump, avoid obstacles, score climbs with distance; starts gentle and ramps speed every ~10s up to a cap"). Naming the curve gives `builder` something to tune toward. **State the player's moment-to-moment decision** — answer "what is the player choosing each second?" A loop with no live decision plays as "brainless" even when it runs correctly (POC run-003: an auto-firing shooter). If simplifying controls for mobile removes the decision (auto-aim, auto-fire), restore one another way (a dodge/dash, a targetable special, limited ammo that forces aim, a risk/reward pickup).
   - `mechanics` — a short list of the concrete mechanics the builder must implement (e.g. ["jump", "obstacle spawning", "score", "game over + restart"]). Keep it minimal but complete — every item here is something `builder` must wire up. Include **at least one progression or reward beat** beyond bare survival (e.g. milestone pickups, a combo/streak, or speed tiers that change the visuals) so the loop has somewhere to go.
   - `art_direction` — a coherent primitive-art direction that `builder` can *execute*, not just a palette. Specify: a named palette + shape language, a **background treatment** (so there's no dead space — e.g. parallax lines/stars/gradient), and at least one **motion/feedback beat** (e.g. "screen flash + shake on death, score pulses on milestone"). Example: "neon vector on near-black; bright cyan/magenta shapes with additive glow; faint parallax grid scrolling behind; white flash + shake on crash." Be specific — vague art direction is the top cause of bland output.
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

## Hybrid / combination concepts (when the prompt blends two genres)
A combination prompt ("match-3 + survival", "runner + shooter") is handled by the same steps above — but a blend has one extra failure mode: the two genres **coexist** instead of **fusing**, so it plays as "genre A with something random happening at the same time" (POC run-004). The concept is where the fusion is won or lost. Make it explicit, in this priority order:

- **Prefer state/space fusion — the strongest lever.** The most cohesive blends make both genres act on the *same objects or the same space*, so a single action serves both at once. Don't bolt genre B on as a separate region of the screen running on its own clock — that produces a *periodic interrupt*, where the genres **alternate** (puzzle → defend beat → puzzle) instead of **fusing** into one continuous decision (POC run-005). Instead, put the threat *inside* genre A's world: e.g. for match-3 + survival, enemies corrupt gems on the grid, the advancing line eats grid rows, or threatened columns must be cleared to survive — so **every match is simultaneously a puzzle move and a defense move.** State in `core_loop` how a single player action pays off in both genres at once.
- **Align the tempos.** If the two genres' natural tempos differ (a deliberate puzzle vs. a real-time threat), reconcile them in the concept — slow the real-time side toward puzzle tempo, or make matching faster/continuous — or they will read as two games sharing a screen no matter how well-linked they are. Note the intended tempo reconciliation in `core_loop`.
- **Name the forcing function (supplement, not the mechanism).** State what makes the *second* genre's pressure continuously reshape the player's choices in the *first*. Answer: "what stops the player from just playing genre A and ignoring genre B?" A periodic telegraphed event (run-005) is a useful supplement, but on its own it only buys alternation — lead with state/space fusion above, then add a forcing function for spikes of tension.
- **Tie them through one shared resource or decision.** The strongest blends route both genres through a single resource the player must split (run-004: matches that could fuel offense OR defense). Put that contention in `core_loop` and `mechanics`.
- **Make the blend — not either genre — the differentiator.** `differentiation_notes` should explain why the *combination* is the hook, not just that it's "genre A but also B."
- **Honest caveat:** some genre pairs are intrinsically hard to fuse (orthogonal puzzle + real-time is the hardest). If a pairing resists state/space fusion, say so in `differentiation_notes` and pick the most fusable shared object available — don't ship a hollow blend.

## Notes
- Do NOT invent assets here. Art is the builder's job (deliberate primitives); this skill only sets `art_direction` to steer it.
- The differentiation check is lightweight — a sanity gate, not market research.
