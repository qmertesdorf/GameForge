---
name: visual-audit
description: Use when judging the composited, assembled screen of a running Godot game — "does it look designed and read clearly?" — typically after the asset re-skin (before validator's styled gate) or standalone on any running game. Renders every game state, fans out one fresh auditor subagent per lens (inventory/completeness, fidelity/cohesion, composition/collision, legibility, colour-accessibility, structural-fidelity, polish/design-quality), dedupes + attributes findings, and drives the fix → re-render → re-audit loop. Records NOTHING to the manifest — outputs are code fixes (git) + a findings report.
---

# visual-audit

Grade the **assembled, running screen** of a Godot game — not the raw asset files. "The art is good" ≠ "the screen is good": a re-skin that nails every PNG still ships unfinished if a primitive HUD, an unreadable value, an icon-over-the-name collision, or a colour-blind-hostile state survives. This skill is the composited audit, extracted from `asset` so it is reusable on ANY running game and so independent fresh eyes — not the person who made the fix — render the verdict.

```
… → [playable] → asset (produce + asset_pass) → visual-audit (this skill) → validator(re-run) → [styled]
```

Also invocable standalone: point it at any running game to grade its screen.

## What this skill does NOT touch
- The per-PNG generation audit (subject/tone/cohesion of each generated image → regenerate) lives in `asset`; it runs at generation time and drives re-generation.
- Game logic. Fixes are visual (chrome code, import settings) or routed back to `asset` as regen requests. If a `selftest.gd` exists it must still print `SELFTEST OK` after fixes — and if a `uitest.gd` exists it must still print `UITEST OK`: audit fixes edit view/chrome code, which is exactly where taps silently break (mouse-filter shadowing, z-order, lost signal wiring), and no pixel lens can see input routing.
- The manifest. This is a transient gate: its outputs are code fixes (captured in git) and a findings report to the owner. The validator asserts "did the gate pass" via the human A/B when it advances to `styled`.

## Workflow

**1. Render every game state — not just one frame.** On the REAL renderer (NOT `--headless`; the dummy renderer cannot capture pixels). Reuse the `tools/godot/screenshot.gd` capture pattern, or write a throwaway harness that drives the game into each state and captures the viewport. **Enumerate the states and capture each as its own frame:** the busiest combat/gameplay state (full hand/HUD, statuses up, intent shown), AND each modal/overlay (every reward/shop screen, win, lose, map/rest). "Busiest state" reads as busy *combat* and the overlays then go un-audited — a real reward-overlay title shipped on bare scrim because only the combat frame was captured. Drive a deliberately cluttered state so every chrome element is present at once. Throwaway harness/crops are deleted at the end; preserve one representative post-fix frame under the game's dir if useful.

**2. Magnify — never judge from the downscaled frame.** Two elements 6px apart and two overlapping by 6px look identical at 1×/2×; the verdict only exists at the boundary. Crop + upscale tight regions to 3×+ with PowerShell `System.Drawing` (NearestNeighbor) before calling any pairing. The same tight crops feed the **measured-contrast** tool (see step 4): `node tools/contrast.mjs measure <crop.png>` returns the WCAG ratio of a text-vs-backing crop, so a contrast verdict is a number, not a guess.

**2a. Colour-vision-deficiency renders (for the colour-accessibility lens).** For each captured frame, generate `node tools/contrast.mjs cvd <frame.png> <outdir>` → a **grayscale + deuteranopia + protanopia** version. Hand these to the colour-accessibility auditor alongside the originals so it judges hue-only encoding and value collisions from the *actual* simulated frames, not a mental filter.

**2b. Deterministic text metrics (min-text-size gate + text-region locations).** Run `node tools/contrast.mjs text-metrics games/<id> [--min N]`. It instantiates the scene, reads each **Control** text node's RESOLVED font size + on-screen rect from the live tree, and **hard-fails (exit 2) any visible text below the floor** (default 18px; pass `--min` scaled to the design resolution). This is a computed gate — too-small text is a deterministic FAIL, not a VLM judgment call. Two uses: (1) the min-text-size finding goes straight into the report; (2) the emitted **rects are deterministically-located text regions** — feed them to the legibility/colour lenses' `measure` crops instead of eyeballing where the text is. **Coverage boundary (state it in the report):** this sees only Control-based text (Label/Button/RichTextLabel/…). Text drawn via a custom `_draw()`/`draw_string()` is invisible here and still needs the VLM legibility lens — a low `checked` count means the game draws its text in code, not that it has no text.

**3. Inventory setup pass (lens 1, runs first).** Walk the renderer top-to-bottom and produce the element + state map per `references/inventory-completeness.md`. This map is the input the six parallel lenses consume.

**3a. Structure brief (setup pass, for relational screens only).** If a captured screen has **relational / topological structure** (a map / tree / board with meaningful adjacency / ordered list), the orchestrator (you, here — NOT the lens subagent) reads the **model + generator + layout source** and emits a **structure brief** for that screen: the structure kind; the intended spatial grammar (what a row/column/edge *means*); the ground-truth instance (node list with floor/col/type, edge list, current node, reachable set); and the player's task. This is the ONLY place source/model is read — it keeps the Structural Fidelity lens pixel-only and its eyes fresh. A screen with no relational structure gets **no brief**, and the lens returns **N/A** for it.

**4. Fan out — one FRESH auditor subagent per parallel lens.** After the inventory setup pass (step 3), dispatch the **six** parallel-lens subagents concurrently — one per lens (Agent tool), each handed ONLY its reference + the rendered frames + the inventory map, each told to return a structured finding list and to default to FINDING when unsure:
- `references/fidelity-cohesion.md`
- `references/composition-collision.md`
- `references/legibility.md`
- `references/colour-accessibility.md`
- `references/structural-fidelity.md` *(hard gate; consumes the structure brief; N/A when none)*
- `references/polish-quality.md`

Independent fresh eyes per lens is the whole point: the intent-dagger-over-name and the dark-on-dark-numeral bugs both slipped past passes that *had the rules*, because one self-reviewing reviewer rationalises "minor." Do not collapse the lenses into one self-read.

**The legibility + colour-accessibility lenses MEASURE, they don't guess.** Both are handed the objective seam in `tools/contrast.mjs`: the auditor crops a suspect text region (step 2) and runs `measure` for the real WCAG contrast ratio + verdict, and the colour lens reads the CVD/grayscale renders from step 2a instead of simulating in its head. This is the same move as the packager's silhouette-ΔE icon gate — a measured number kills both the false positive ("this looks low-contrast" on text that reads) and the rationalised miss ("dark-on-dark, but probably fine"). Findings from these two lenses should carry the measured ratio.

**How every lens must judge — reason first, anchor to a concrete bar (mandatory).** Pointwise vibes ("looks 7/10") are unreliable; force the structure that isn't:
- **Reasoning trace before the verdict (CoT, required).** Every finding must lead with *what was observed* → *why it is/isn't a defect*, THEN the severity + fix. "Day counter is thin amber on the painted dusk sky, measured 2.1:1 → below the 4.5:1 body floor → blocker" — not a bare "low contrast". A verdict with no observation→reason chain is not a finished finding; default to FINDING when the chain is uncertain. This single rule is what stopped self-reviewers rationalising "minor".
- **Anchor to a reference, not an abstract sense.** Judge *against a named bar*, never "in general": the **measured number** for legibility/colour (the ratio IS the anchor), a **named shipped title** for polish/fidelity ("would this panel ship in Slay the Spire / Hades — and concretely, what do they do that this doesn't"), and the **structure brief's ground-truth** for structural-fidelity. A finding that can't name its anchor is a vibe — drop it or find the anchor. (There is deliberately no position-swap / multi-judge re-vote: the fan-out's lens-diversity is the independence mechanism; re-voting the same lens amplifies correlated error.)

**Five lenses catch DEFECTS (hard gates — fidelity, composition, legibility, colour-accessibility, and structural-fidelity); polish-quality grades DESIGN (is it good?).** A screen can pass every defect lens and still be flat/generic/default-positioned — polish-quality is the only lens that sees that gap. But it is **advisory, cost-triaged — NOT a hard gate**: its findings carry a `cheap/medium/expensive` cost tag; fix the cheap ones in the pass, and **surface medium/expensive composition changes for the owner to decide** rather than treating them as blockers. Don't let "redesign the whole layout" stall a defect pass.

**5. Collect, dedupe, attribute.** Merge the lens findings; dedupe (the same collision may surface from composition AND legibility); attribute each to a cause — `asset-production` (weak/missing/mis-styled art → regen request back to asset), `chrome-code` (a `_draw()`/styling fix), or `chrome-code-layout` (placement/grouping/anchoring/sizing — the polish lens's usual cause). A bad screen is always attributable; an unattributable "looks off" is not a finished finding. Keep the polish lens's cost tags through the merge so the owner can triage what to fix now vs. defer.

**6. Fix → re-render → re-audit LOOP.** Apply fixes, then RE-RENDER and RE-AUDIT against the *new* frames, because (a) code-right ≠ screen-right and (b) fixes spawn new issues (a repositioned element creates a fresh collision; a newly-styled panel exposes a primitive hidden behind the old one). Re-audit with FRESH eyes — ideally a fresh subagent that did NOT make the fix. Never call the pass done off the screenshot you *fixed against*; call it done off a clean re-audit of the screenshot that came *after* the fixes.

**7. Report.** Summarise findings (each attributed) and the resolution to the owner. Write nothing to the manifest. Hand off to `validator` (or back to `asset` if regen is needed).

## Mipmaps — the grain fix (do this before blaming the art)
An asset authored ornate at high res and drawn into a small UI slot (a 768×1024 texture at 44px) **aliases into grain** with no mipmaps. Godot's importer defaults `mipmaps/generate=false`; set it **`=true`** in each downscaled texture's `.png.import` and re-import, AND set the canvas filter to a mipmap variant (`CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` on the drawing Node2D) — mipmaps need *both*. This de-grains every downscaled draw. Even so, a busy source thumbnails worse than a bold simple one — author small-display elements with fewer, larger shapes + thick outlines. **Verify the DOWNSCALED result at true size**, not the full-res PNG.

## The lenses
| Lens | Reference | Runs |
| --- | --- | --- |
| Inventory & completeness | `references/inventory-completeness.md` | setup (first) |
| Fidelity & cohesion | `references/fidelity-cohesion.md` | parallel |
| Composition & collision | `references/composition-collision.md` | parallel |
| Legibility | `references/legibility.md` | parallel |
| Colour-accessibility | `references/colour-accessibility.md` | parallel |
| Structural fidelity | `references/structural-fidelity.md` | parallel (hard gate; relational screens only) |
| Polish & design-quality | `references/polish-quality.md` | parallel (advisory, cost-triaged) |
