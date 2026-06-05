# Lens: Polish & design-quality

Used by the `visual-audit` skill (parallel). Judges the assembled screen as a **designed composition** — not "are there defects?" (the other four lenses own that) but **"is this actually GOOD?"**. A screen can pass every defect lens — no collisions, fully legible, cohesive art, colour-safe — and still be **mediocre**: flat, generic, default-positioned. That gap is this lens's entire job. The bar is a **named shipped title**: *would this screen ship in Slay the Spire / Hades / a top-100 premium mobile game?*

**Boundary vs Fidelity & cohesion.** Fidelity-cohesion judges *each element* ("does this token belong to one painted hand?"). This lens judges *the whole screen* ("is the composition designed?") — where elements sit, what the eye lands on, how the UI relates to the art. A screen can pass fidelity (every asset is beautiful) and fail polish (the beautiful assets are arranged like a spreadsheet). Different altitude; run them independently.

## The discipline that keeps this from becoming "make it nicer"
This lens is worthless if it emits taste-mush. Every finding MUST carry, or it is discarded:
1. **A named-game comparison** — *which* shipped title does this better, and how. "StS hard-dims unreachable nodes so the 2–3 choices are the brightest things on screen." This is the anti-vagueness device — if you can't name how a real game solves it, you don't have a finding.
2. **An attribution** — almost always **`chrome-code-layout`** (placement / grouping / anchoring / sizing — a layout-code fix, distinct from the defect lenses' `chrome-code`-*styling* and `asset-production`). Occasionally `asset-production` (the art itself can't support the composition — e.g. a background with no clean lane for the UI) or `out-of-scope-redesign`.
3. **A concrete fix** — the specific move, not "improve it."
4. **A cost tag — `cheap` / `medium` / `expensive`.** This is the triage mechanism: polish findings range from a one-line layout tweak to a full redesign. **The polish lens is ADVISORY, not a hard gate** (unlike legibility/collision, which block). Cheap findings should be fixed in the pass; medium/expensive ones are **surfaced for the owner to decide**, never silently treated as blockers. Tag honestly so the owner can triage.

Also required: a closing **"what genuinely meets the bar"** note that names what already ships (usually the art). This forces you to *discriminate* art-layer from composition-layer instead of trashing everything — and a lens that only ever complains is noise.

## Axes
1. **Integration** — do foreground gameplay/UI elements relate to the art behind them, or **float on top like UI pasted on a wallpaper**? If the background depicts structure — a path, platforms, a shop counter, shelves, a casting table — do interactive elements sit *on / with* that structure (with contact shadows seating them), or ignore it on a separate plane? (Map nodes floating in front of painted walkways instead of standing on them; shop cards in dead air instead of on the merchant's counter.)
2. **Visual hierarchy** — at a **one-second glance**, is the most important thing — the current state, the choice the player must make, the threat they must react to — the **most salient**? Or does everything read at one flat weight with nowhere for the eye to land? Watch the inversions: a low-frequency confirm button (End Turn) louder than the play surface; the enemy's attack intent (the key read) the weakest element; "available vs locked" too subtle so locked options still pop.
3. **Use of space / composition** — is content placed where the composition wants it (the focal area, along the art's leading lines), or **crammed into dead/busy/dark zones while the bright focal area sits empty**? Are there large unbalanced dead gutters? Premium screens use the painting's own focal point and leading lines; default layouts distribute to edges/grids that fight the art.
4. **Elegance / redundancy** — is the same information conveyed **two+ ways when one would do** (a clear painted icon AND a redundant text label on every node; a "RELIC" header above an already-named relic; a cost shown twice on a card)? Does removing an element make it cleaner with no loss? Premium UIs are confident and spare; over-labelling is a "default UI" tell and it flattens hierarchy.
5. **Intentionality / finish** — does every element look **placed and sized by a designer**, or default-positioned by code? Two peer buttons on two different alignment grids; a flat black letterbox title bar that hard-clips the painting instead of a shaped/painted plate; mechanically-even spacing that fights an organic scene. Consistent rhythm, margins, and one alignment grid read as "someone who cared designed this."

## Output per finding
`[SEVERITY blocker/major/minor | COST cheap/medium/expensive] | AXIS | shortfall + the shipped-game pattern that does it better | ATTRIBUTION (chrome-code-layout / asset-production / out-of-scope-redesign) | concrete fix`

Then the **verdict**: does the screen meet the premium bar, and roughly how far off (e.g. "one focused chrome-layout pass away, no art redo").

## Red flags — when you write one of these, you are emitting mush; fix or cut it
- "It could feel more premium / polished" with no axis, no named comparison, no fix → **not a finding.** Name the axis and the game, or cut it.
- "Add some juice / make it pop" → name the *element* and the *specific* treatment (dim the 10 locked nodes to 40%, pulse the 3 available) — vague energy is not actionable.
- Flagging an element the fidelity lens already owns (this token is code-not-painted) → that's fidelity-cohesion's call; your job is *where it sits and how it relates*, not its paint quality. Don't double-bill.
- Tagging a full-redesign finding `cheap`, or omitting the cost tag → the owner can't triage; an expensive composition change dressed as a quick fix derails the pass.
- Trashing every screen equally → if a heavily-polished screen and a rough one come back with the same severity, you're not discriminating. Use the "what meets the bar" note to prove you can tell them apart.
