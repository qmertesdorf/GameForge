# Lens: Structural Fidelity

Used by the `visual-audit` skill (parallel, **hard gate**). The only lens that checks a render
against the game's **ground-truth data model** — supplied as a **structure brief** by the setup pass,
NOT read from source here. You stay **pixel-only**: you judge whether the drawn screen faithfully and
legibly represents the structure the brief describes.

**Fires only on relational / topological screens** — a branching map, a tree, a board with
meaningful adjacency, an ordered list. If the setup pass emitted **no structure brief** (combat,
shop, dialog — screens with no relational structure), this lens returns **N/A**. Do not invent
structure to critique.

**Job.** Verify the render is:
- **Faithful** — the pixels match the model: no phantom edges, no missing edges, no false adjacency;
  reachability, the current node, and locked-vs-available are drawn truthfully.
- **Traceable** — a player can reconstruct the structure from the render and follow the intended path
  (which nodes connect, where a choice leads, where they are now).

## The structure brief you are given
The setup pass hands you: the **structure kind**; the **intended spatial grammar** (e.g. "floor =
row, bottom→top = progress, column = lane, an edge means 'the player may move A→B'"); the
**ground-truth instance** (node list with floor/col/type, edge list, current node, reachable set);
and the **player's task** on this screen. Check the frame against this — both directions.

## Axes
1. **Faithful encoding** — every drawn relationship is a real model relationship and vice versa.
   **Walk the edge list both ways:** each model edge has exactly one drawn connector between the right
   two nodes; each drawn line is a real model edge. Phantom edges (two unrelated lines crossing read
   as a connection), missing edges, and **false adjacency** (two nodes drawn touching/aligned that the
   model does not connect) are blockers — they teach the player a graph that isn't there. Slay the
   Spire draws exactly one path segment per real edge and nothing between unconnected nodes.
2. **Consistent spatial grammar** — the structure resolves into **aligned, followable lanes** under
   one **global** coordinate system. The classic failure: positions normalized **per-row by that
   row's own width**, so a 2-wide row sits at the screen edges and a 3-wide row fills the centre —
   columns never line up and an edge can shoot clear across the screen. A real map (StS / Inscryption)
   pins every node to a global column lattice so lanes read top-to-bottom and edges stay short.
3. **Traceability & figure/ground** — nodes **and the edges between them** read **above the
   backdrop**; connections go ring-to-ring with low crossing; the **current node** and the
   **choosable next nodes** are unambiguous. Edges dimmed into the painted background, or a current/
   reachable state distinguishable only by a subtle tint, fail this — the player can't follow the
   path. Hades/StS keep the path a high-contrast ribbon over any art and make "you are here" + "you
   may go here" the loudest marks.
4. **Complete & legible extent** — enough of the structure is visible to **plan ahead**. Any fog or
   hiding must be **intentional** (a designed fog-of-war that reveals as you advance), not
   **accidental** (nodes dimmed into invisibility, clipped off-canvas, or so low-contrast only the
   nearest row reads). If the brief says all floors are knowable, all floors must read.

## Output per finding
`[SEVERITY blocker/major/minor] | AXIS | the failure + how a named shipped title (Slay the Spire /
Inscryption / Hades) renders it right | ATTRIBUTION | concrete fix`

- **ATTRIBUTION** is usually `chrome-code-layout` (the draw places nodes/edges wrong). Occasionally
  `asset-production` (the backdrop is too busy/contrasty to support the structure → a scrim or
  calmer-bg regen request). **Rarely `logic-note`** — the **model itself** is wrong (the brief's
  edge list is nonsensical). Surface a `logic-note` **loudly and do NOT fix it here**: logic is frozen
  during a visual pass; it goes back to the owner / a deepen pass.

Then the **verdict**: is the screen **faithful + traceable**? If not, name the single
highest-leverage fix (usually: one global-lattice layout change, or one scrim that lifts the path off
the backdrop).

## Red flags — emit one of these and you are not doing this lens's job
- **"Looks messy / cluttered"** with no reference to the model → that's the composition lens, and
  without naming a lost *relationship* it's mush. Name which edge/lane/current-marker is wrong.
- **Billing paint or text contrast** — "this node art is muddy" is fidelity; "this label is hard to
  read" is legibility. Your unit is the **relationship between** elements, not any single element.
- **"Add contrast"** as a whole fix → name the **relationship** being lost (the path, the lane, the
  you-are-here) and how to restore it (lattice / scrim / brighten the reachable set), not a generic
  contrast bump.
- **Explaining away a render bug because "the brief says the model is correct."** The model being
  correct is exactly what makes a faithfulness gap a **render** defect — that's a finding, not a pass.
- **Critiquing a screen with no brief.** No brief → **N/A**. Don't manufacture structure.
- **Rubber-stamp guard:** name what **does** read well (which lanes/edges/markers are followable), so
  a faithful screen and a broken one don't come back identical.
