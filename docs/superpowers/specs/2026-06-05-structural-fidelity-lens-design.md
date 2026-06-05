# Spec — Structural Fidelity lens (7th visual-audit lens)

Date: 2026-06-05
Status: design approved (brainstorming), pending writing-plans.

## Motivation

Owner playtested `deckbuilder-0001` and called the run **map "nonsensical."** Investigation
found the map *data* is sound — `MapGen.gd` builds a proper 10-floor branching DAG — but the
**render** of that data fails to communicate the structure. Crucially, **none of visual-audit's
six existing lenses caught it.** They are all **pixel-only and self-referential**: they judge the
frame against general principles (collisions, contrast, cohesion, composition) but nothing tells a
fresh auditor that *the nodes are supposed to form aligned lanes you traverse bottom-to-top.* The
polish lens grazed the symptom ("UI on a wallpaper") but its fixes were cosmetic (contact shadows,
bowed edges) — prettier, still untraceable.

This is the **inverse** of the polish-pass lesson that "pixel-only agents hallucinate structure."
Here a *real* structural defect exists that a pixel-only auditor **cannot see** without the
ground-truth data model. So we add the one lens that reads the render *against the model*.

## The map's actual bugs (the dogfood target — concrete)

1. **Inconsistent spatial grammar (the core defect).** `MapView.gd::_node_center()` places nodes
   by `col / (width-1)` — normalized *per that floor's own width*. A 2-wide floor puts nodes at
   screen-x ≈120 and ≈1160 (the two edges, nothing in the centre); a 3-wide floor fills the centre.
   Columns therefore never align into lanes. Worse, `MapGen` connects edges by *model* col-distance
   ≤1, but model-col-1 means "far right" on a 2-wide floor and "centre" on a 3-wide floor — so a
   far-right node can legally connect to a far-left node, drawing an edge clear across the screen →
   tangle. Fix = a **global column lattice**, not per-floor normalization.
2. **Figure/ground collapse.** Small flat node markers + dim edges float on a high-detail,
   high-contrast painted chamber (`bg_map.png`); the wallpaper wins, the edges vanish.
3. **Journey invisible.** Locked nodes are dimmed so hard that only the bottom two floors read; the
   player can't see where the paths lead, so can't plan.

## 4 locked design decisions (via AskUserQuestion, owner-approved)

1. **A new, 7th lens** — not a fold-in to polish or composition. (Each of those owns a different
   altitude; see Boundaries.)
2. **The orchestrator emits a "structure brief"** in visual-audit's setup pass; the auditor stays
   **pixel-only** and checks the render against that brief. This isolates all source/model reading to
   one place (the setup pass) and keeps the lens's fresh eyes genuinely fresh.
3. **A defect lens / HARD GATE** — it blocks `styled` like legibility and collision do, with
   tiers blocker / major / minor. It is **NOT advisory/cost-tagged** like the polish lens.
4. **Narrow scope** — fires only on **relational / topological** screens (graph/map, tree, board
   with meaningful adjacency, ordered list). It checks relationship faithfulness + traceability, NOT
   scalar truthfulness (an HP bar's fill level is inventory/legibility's job). It returns **N/A** on
   combat / shop / dialog screens that have no relational structure.

## The new lens

**Name (default):** `Structural Fidelity` — file `references/structural-fidelity.md`. (Owner liked
the design but did not pick among the alternates *Structural & Information Fidelity /
Representational Fidelity / Diagram Legibility*; default to **Structural Fidelity** unless the owner
objects.)

**Job.** For a relational-structure screen, verify the render is:
- **Faithful** — the pixels match the model: no phantom edges, no missing edges, no false
  adjacency, and reachability / current-node / locked-vs-available are drawn truthfully.
- **Traceable** — a player can reconstruct the structure from the render and follow the intended
  path (which nodes connect, where a choice leads, where they are now).

### Structure brief (the setup-pass change)

The orchestrator (visual-audit's setup pass) reads the **model + generator + view-layout source**
and emits a brief the auditor consumes:
- **Structure kind** (branching map / tree / board / ordered list).
- **Intended spatial grammar** — e.g. "floor = row, bottom→top = progress; column = lane;
  an edge means 'the player may move A→B'."
- **Ground-truth instance** — the node list (each with floor / col / type), the edge list, the
  current node, and the reachable set.
- **The player's task** on this screen (e.g. "choose the next node along a connected path to the
  boss").

**If there is no relational structure, the orchestrator emits no brief and the lens returns N/A.**
The brief is the *only* place code/model is read; the auditor never reads source.

### 4 axes

1. **Faithful encoding** — every drawn relationship corresponds to a model relationship and vice
   versa. Walk the edge list **both ways**: each model edge has a drawn connector, and each drawn
   connector is a real model edge (no phantom edges from overlapping lines; no missing edges).
2. **Consistent spatial grammar** — one **global** coordinate system, so the structure resolves into
   aligned, followable lanes. (The map's core bug: per-floor normalization breaks this.)
3. **Traceability & figure/ground** — nodes **and edges** read above the backdrop; connections go
   ring-to-ring with low crossing; the current node and the choosable next nodes are unambiguous.
4. **Complete & legible extent** — enough of the structure is visible to plan ahead; any fog/hiding
   is intentional (a designed fog-of-war) not accidental (clipped, dimmed into invisibility).

### Boundaries (in the doc — anti-double-bill)

- **vs Composition & collision** — composition finds spatial *bugs* (overlaps, crammed zones) with
  no reference model; this lens checks the layout against the *intended* structure. Composition can
  call a map "uncluttered" while this lens fails it for un-followable lanes.
- **vs Polish & design-quality** — polish asks "is it designed / premium?"; this asks "is it *true*
  and *traceable*?" A map can be tastefully arranged and still misrepresent the graph.
- **vs Inventory & completeness** — inventory checks an element is *present*; this checks the
  *relationships between* elements.
- **vs Legibility** — legibility checks you can read *text*; this checks you can read *structure*.

### Output per finding

`[SEVERITY blocker/major/minor] | AXIS | the failure + how a named shipped title (Slay the Spire /
Inscryption / Hades) renders it right | ATTRIBUTION | concrete fix`

- **ATTRIBUTION** is usually `chrome-code-layout` (the draw places nodes/edges wrong);
  occasionally `asset-production` (the backdrop is too busy to support the structure → scrim/regen
  request); rarely `logic-note` (the **model itself** is wrong — surface loudly, do not fix here:
  logic is frozen during a visual pass).
- Then a **verdict**: is the screen faithful + traceable? If not, the single highest-leverage fix.

### Red flags (in the doc)

- "Looks messy" with no reference to the model = **not a finding.** Name the lost relationship.
- Don't bill paint quality (that's fidelity) or text contrast (that's legibility); bill *structure*.
- "Add contrast" alone is not a fix — name the **relationship** that's lost and how to restore it.
- Never explain away a render bug because "the brief says the model is correct" — the model being
  correct is exactly what makes a faithfulness gap a *render* defect.
- Rubber-stamp guard: name what **does** read well (which lanes/edges are followable), so a clean
  screen and a broken one don't come back identical.

## Spine edits (`.claude/skills/visual-audit/SKILL.md`)

- **Setup pass** (inventory): add the structure-brief step — when a screen has relational structure,
  read model+generator+layout and emit the brief; otherwise no brief → lens N/A.
- "**five** parallel lenses" → "**six**"; add Structural Fidelity to the fan-out list (step 4) and
  the lens table.
- Update the **defect-vs-advisory** framing sentence: there are now **five defect (hard-gate) lenses**
  (fidelity, composition, legibility, colour, **structural-fidelity**) + **one advisory** lens
  (polish). Structural Fidelity is a hard gate.

## Testing / validation (writing-skills RED/GREEN dogfood)

- **RED** — render the deckbuilder map (the throwaway harness `_shot.gd` already exists +
  `_map_shot.png`); confirm the six existing lenses, run as fresh subagents, **miss** the structural
  defects (they did in practice — that's why we're building this).
- **GREEN** — give a fresh subagent ONLY `references/structural-fidelity.md` + the map frame + a
  structure brief; confirm it surfaces axis-2 (lane misalignment), axis-3 (figure/ground), and
  axis-4 (extent) findings the others missed, each attributed and with a concrete fix.
- Confirm the lens returns clean **N/A** when handed a non-relational screen (e.g. the combat frame)
  with no brief.

Logic stays FROZEN (`SELFTEST OK`). The map *fix* itself (global lattice + backdrop scrim + reveal
the journey) is a **separate, owner-deferred track** — this spec ships the lens, not the fix.

## Non-goals / YAGNI

- No manifest record (visual-audit writes nothing to the manifest; unchanged).
- Do **not** make the lens read source directly — all model reading stays in the setup-pass brief,
  to preserve fresh pixel-only eyes.
- Do **not** widen scope to scalar truthfulness (HP fills, counts) — that stays inventory/legibility.
- No game-logic change; the map fix is out of scope here.

## Open items

- Lens name: default **Structural Fidelity** unless the owner picks an alternate.
- (Deferred track, not this spec) actually fix the deckbuilder map with the lens's findings.
