# Thematic cohesion — the concept `theme` anchor — design

**Date:** 2026-05-31 · **Type:** cross-cutting precursor (lands **before** M2) · **Status:** design approved, spec under review.

A focused change that makes **cross-modal thematic cohesion** a decided-early, first-class concern. Today each modality interprets the concept independently — `asset` reads `concept.art_direction` (a visual brief), `audio` derives its mood from `art_direction` + a "theme" **that is not a real manifest field**, and M2's icon would read `art_direction` too. Nothing binds them to one world, so a spooky-visuals / light-hearted-audio / arcade-icon split is currently unguarded. The cohesion seen in the proof games was hand-authored, not structural. This precursor fixes that **before** M2 generates the first store icon.

## 1. Goal

Introduce **one modality-neutral `theme`** in the `concept` block that every modality expresses — visuals, audio, and the store icon — so a title reads as a single coherent world. The `theme` is decided **first, at concept time, before any asset generation**. This is the cross-modal analog of the within-modality "one coherent visual system" / "shared mood scaffold" discipline the skills already enforce.

The real deliverable, as always, is a **better skill set** — here the fix is a shared source-of-truth field plus the prose that makes every generator and the validator honor it.

## 2. Pipeline placement

`theme` is set at the very start and read by everything downstream:

```
prompt → concept (writes theme FIRST, then art_direction as its visual expression)
       → builder → validator → [playable]
       → asset   (visual system ← theme via art_direction)
       → audio   (mood_prompt   ← theme)
       → packager (M2: icon + screenshots ← theme)
       → validator (cross-modal cohesion A/B at each pass)
```

Lands before M2 so the M2 `packager` spec can derive the icon from `theme`.

## 3. Schema / manifest changes (additive, non-breaking)

Add an **optional** `theme` object to the `concept` block:

```jsonc
"theme": {
  "premise":       "a cozy autumn-woodland folktale",
  "tone":          "warm, gentle, a touch melancholy",
  "mood_keywords": ["cozy", "organic", "storybook", "calm"],
  "setting":       "dappled autumn forest at golden hour"
}
```

- The `theme` object uses `additionalProperties: false` with the four properties above (all strings except `mood_keywords`, an array of strings). None individually required — but the `concept` skill always authors a complete `theme` going forward.
- `theme` is **optional** on `concept` (not added to any `required` list), so existing manifests without it still validate — **non-breaking**, consistent with how the `asset_pass`/`audio_pass`/`store_pass` additions were handled.
- `tools/manifest.mjs` is unchanged (object merge handles a new nested block).

## 4. The `concept` skill — derive `theme` first

The `concept` skill gains a step, ordered **before** `art_direction`:

- **Derive `theme` first** from the prompt — the modality-neutral premise/tone/mood/setting that the whole title expresses. Record it in `concept.theme`.
- **Then derive `art_direction` as the theme's *visual* expression** — palette, shape language, background, motion beats that *render* the theme. Add an explicit contract line: `art_direction` must not contradict `theme` (a "spooky" theme cannot have a "cheerful pastel" art_direction).
- The existing `core_loop` / `mechanics` / `differentiation_notes` steps are unchanged.

This makes the theme the **decided-early anchor**, not an afterthought reverse-engineered from the art.

## 5. Downstream skills bind to the shared `theme`

Light, surgical prose edits — each generator names `concept.theme` as the cross-modal anchor for its medium:

- **`asset`** — Step 0 already derives a visual system from `art_direction`; add that `art_direction` is the **visual expression of `concept.theme`**, and the visual system must read as that theme's world.
- **`audio`** — replace the current "Read `concept.art_direction`, `concept.genre`, and theme" (which references a **non-existent** field) with "derive `mood_prompt` + `style_descriptors` from **`concept.theme`**" — the real field. The audio identity expresses the same theme as the visuals, sonically.
- **`packager`** (M2, when resumed) — the icon master + screenshot selection express `concept.theme`; folded into the M2 spec at that time (noted here as the forward dependency).

No behavior in `builder` changes (it still executes `art_direction`'s primitives).

## 6. The `validator` cross-modal cohesion gate

Add a **human-A/B** line (cohesion is a judgment call, not automatable), active when **two or more modalities are present** on the title:

> Confirm the visuals, audio, and (at M2) the icon **read as one themed world** — the same premise/tone/setting — not three independent interpretations.

Placed in Method 3 (`playable → styled`, after `asset`), Method 4 (audio, `→ scored`), and the M2 packaging method. On failure, attribute it to a **`concept.theme` gap** (the anchor was too vague to align the modalities) or to a **skill that ignored the theme** — a specific, fixable prose cause, exactly like the within-modality cohesion finding. This is the cross-modal analog of the existing "reads as one coherent visual system" check.

## 7. Backfill the active proof games

Write a `theme` block into `creature-0001` and `crosser-0001` — they already cohere (painterly warm-woodland visuals + warm-woodland audio; pixel-art + chiptune), so this **records the theme retroactively** and makes them valid inputs to the theme-aware M2 packager. Example for `creature-0001`:

```jsonc
"theme": {
  "premise": "a cozy autumn-woodland folktale of a small forest spirit foraging glowing seeds",
  "tone": "warm, gentle, a touch melancholy",
  "mood_keywords": ["cozy", "organic", "storybook", "calm"],
  "setting": "dappled autumn forest at golden hour"
}
```

`crosser-0001` gets its own (retro arcade / hard-edged pixel world). The older POC games (`runner-0002`, match-3, shooter) are **left untouched** — they are SVG-done, not M2 targets, and `theme` is optional.

## 8. Testing

- **Schema test** — the new `theme` object is accepted; a manifest **without** `theme` still validates (the non-breaking guarantee); a `theme` with an unknown property is rejected (`additionalProperties: false`).
- **No new tool**; `tools/manifest.mjs` untouched. The full vitest suite stays green (currently 69/69).

## 9. Scope

In scope:

- The optional `theme` object on `concept` (schema).
- `concept` skill: derive `theme` first, `art_direction` as its visual expression + the no-contradiction contract.
- `asset` / `audio` prose: bind to `concept.theme` (audio's edit also fixes the dangling non-existent-field reference).
- `validator`: the cross-modal cohesion A/B line in Methods 3, 4, and the M2 packaging method.
- Backfill `theme` into `creature-0001` + `crosser-0001`.

Explicitly **not** in scope:

- **M2 itself** — resumes immediately after this lands; its `packager` derives the icon from `theme`.
- **Re-running any generation** — the proof games already cohere; the backfill is documentation, not a regen.
- **Older POC game backfill** — `theme` is optional; they are done and not M2 targets.
- **Automating cohesion** — it stays a human A/B (like every aesthetic gate).

## 10. Roadmap fit

This is the missing upstream piece beneath the north star's *"each game internally cohesive"* — extended from *within* a modality to *across* modalities. It costs one optional field + targeted prose, blocks nothing, and makes every future multi-modal title (and the M2 icon) cohere by construction rather than by luck.
