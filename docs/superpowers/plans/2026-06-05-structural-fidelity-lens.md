# Structural Fidelity Lens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 7th `visual-audit` lens, **Structural Fidelity**, that checks a relational-structure screen's render against a ground-truth "structure brief" emitted by the orchestrator's setup pass.

**Architecture:** One new reference file `references/structural-fidelity.md` (the pixel-only lens checklist) + spine edits to `SKILL.md` (setup pass emits the structure brief; six parallel lenses; lens table; defect-vs-advisory framing). The auditor never reads source — all model-reading is isolated to the setup-pass brief, preserving fresh pixel-only eyes. Validated by a RED/GREEN dogfood on the deckbuilder run map.

**Tech Stack:** Markdown skill docs; Godot 4.6.3 real-renderer harness (`_shot.gd` → `_map_shot.png`) for the dogfood; fresh Agent-tool subagents as the test harness; PowerShell `System.Drawing` for zoom crops.

**Source of truth:** `docs/superpowers/specs/2026-06-05-structural-fidelity-lens-design.md`.

---

### Task 1: Write the Structural Fidelity lens reference

**Files:**
- Create: `.claude/skills/visual-audit/references/structural-fidelity.md`
- Mold (read, do not edit): `.claude/skills/visual-audit/references/polish-quality.md` (newest lens, closest structural register), `.claude/skills/visual-audit/references/composition-collision.md` (adjacent spatial lens, for the boundary wording).

- [ ] **Step 1: Read the two mold files** so the new doc matches the house voice (terse, named-game comparisons, explicit red-flags, output-line grammar).

Run: open `polish-quality.md` and `composition-collision.md`.
Expected: confirm the section shape — intro paragraph (job + boundary), `## Axes`, `## Output per finding`, `## Red flags`.

- [ ] **Step 2: Write `references/structural-fidelity.md`** with this exact content:

```markdown
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
```

- [ ] **Step 3: Verify the file matches the lens-doc shape**

Run: confirm the new file has `# Lens: Structural Fidelity`, an intro with the N/A scope rule, `## Axes` (4), `## Output per finding`, `## Red flags` — same skeleton as `polish-quality.md`.
Expected: PASS (structure parallel to the other lenses).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/visual-audit/references/structural-fidelity.md
git commit -m "feat(visual-audit): add Structural Fidelity lens reference"
```

---

### Task 2: Wire the lens into the spine (`SKILL.md`)

**Files:**
- Modify: `.claude/skills/visual-audit/SKILL.md` — four edits: (a) setup-pass structure-brief step in workflow §3, (b) fan-out list §4 "five → six", (c) the defect-vs-advisory sentence in §4, (d) lens table.
- Modify: `.claude/skills/visual-audit/SKILL.md` frontmatter `description` — append the new lens to the parenthesized lens list.

- [ ] **Step 1: Add the structure-brief step to the inventory setup pass (§3).**

Locate workflow step 3 ("Inventory setup pass"). Append a paragraph after it:

```markdown
**3a. Structure brief (setup pass, for relational screens only).** If a captured screen has
**relational / topological structure** (a map / tree / board with meaningful adjacency / ordered
list), the orchestrator (you, here — NOT the lens subagent) reads the **model + generator + layout
source** and emits a **structure brief** for that screen: the structure kind; the intended spatial
grammar (what a row/column/edge *means*); the ground-truth instance (node list with floor/col/type,
edge list, current node, reachable set); and the player's task. This is the ONLY place source/model
is read — it keeps the Structural Fidelity lens pixel-only and its eyes fresh. A screen with no
relational structure gets **no brief**, and the lens returns **N/A** for it.
```

- [ ] **Step 2: Update the fan-out list (§4) — five → six, add the lens.**

In step 4 ("Fan out"), change "dispatch the **five** parallel-lens subagents" to "**six**", and add to the bulleted reference list:

```markdown
- `references/structural-fidelity.md` *(hard gate; consumes the structure brief; N/A when none)*
```

- [ ] **Step 3: Update the defect-vs-advisory framing sentence (§4).**

Find the paragraph beginning "**The first four lenses catch DEFECTS**". Replace its first sentence so the count and membership are right:

```markdown
**Five lenses catch DEFECTS (hard gates — fidelity, composition, legibility, colour-accessibility,
and structural-fidelity); polish-quality grades DESIGN (is it good?).** A screen can pass every
defect lens and still be flat/generic/default-positioned — polish-quality is the only lens that sees
that gap.
```

(Leave the rest of that paragraph — the advisory/cost-triage description of polish — unchanged.)

- [ ] **Step 4: Add the lens to the table (§"The lenses").**

Insert a row before the Polish row:

```markdown
| Structural fidelity | `references/structural-fidelity.md` | parallel (hard gate; relational screens only) |
```

- [ ] **Step 5: Update the frontmatter `description`.**

In the YAML `description`, change the parenthesized lens list `(inventory/completeness, fidelity/cohesion, composition/collision, legibility, colour-accessibility, polish/design-quality)` to include structural fidelity:

```
(inventory/completeness, fidelity/cohesion, composition/collision, legibility, colour-accessibility, structural-fidelity, polish/design-quality)
```

- [ ] **Step 6: Re-read `SKILL.md` end-to-end** for consistency — no remaining "five parallel lenses", the table has 7 rows (1 setup + 6 parallel), the brief step references the lens by name.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/visual-audit/SKILL.md
git commit -m "feat(visual-audit): wire Structural Fidelity into the spine (structure brief + 6th parallel lens)"
```

---

### Task 3: RED/GREEN dogfood on the deckbuilder run map

This is the lens's test. The "RED" evidence (the 6 existing lenses miss the structural defect) is
already established in practice; this task proves the **GREEN**: the new lens, given only its
reference + the map frame + a structure brief, surfaces the defects — and returns **N/A** on a
non-relational screen.

**Files:**
- Use (untracked, throwaway): `games/deckbuilder-0001/_shot.gd`, `games/deckbuilder-0001/_map_shot.png`.
- Read for the brief: `games/deckbuilder-0001/MapGen.gd`, `MapModel.gd`, `MapView.gd`.
- No source files change in this task (logic FROZEN).

- [ ] **Step 1: (Re)render the map frame.**

Run (PowerShell):
```
$env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
godot --path games/deckbuilder-0001 -s _shot.gd
```
Expected: `_map_shot.png` written at 1280×720 showing the run map (the harness waits for `@onready`, calls `_show_map()`, waits, saves). If Godot isn't on PATH, use the winget console exe per the `godot-binary-path` memory.

- [ ] **Step 2: Build the structure brief** (orchestrator role) by reading `MapModel.gd` (node/edge fields), `MapGen.gd` (how floors/cols/edges are generated), `MapView.gd::_node_center()` (how cols map to screen-x). Produce: structure kind (branching map), intended grammar (floor=row bottom→top, col=lane, edge=legal move), the actual node list (floor/col/type), edge list, current node, reachable set, player task.

Expected: a concrete brief naming the real nodes/edges of the rendered seed — NOT generic prose.

- [ ] **Step 3: GREEN — dispatch a fresh subagent** (Agent tool, general-purpose) given **only** `references/structural-fidelity.md` + `_map_shot.png` (+ zoom crops if it asks) + the structure brief, told to return findings in the lens's output grammar. Do NOT tell it where the bug is.

Expected: it surfaces — attributed, with concrete fixes — at minimum **axis-2** (per-floor normalization → lanes don't align / cross-screen edges), **axis-3** (figure/ground: edges/nodes lost on `bg_map.png`), and **axis-4** (journey invisible: only the bottom rows read). This is the pass criterion.

- [ ] **Step 4: N/A check — dispatch a second fresh subagent** given the same reference + a **non-relational** frame (render the combat state, or reuse an existing combat frame from `docs/superpowers/probe-data/deckbuilder-raster-v1/`) and **no structure brief**.

Expected: it returns **N/A** (no relational structure / no brief) rather than inventing findings. This proves the scope guard.

- [ ] **Step 5: If the lens under-fires** (misses axis-2/3/4) or **over-fires** (flags paint/text, or invents structure on the N/A frame), revise `references/structural-fidelity.md` and re-run Steps 3-4 with a fresh subagent. Loop until both pass. Amend Task 1's commit or add a fixup commit.

- [ ] **Step 6: Record the dogfood result** — preserve the map frame and a one-paragraph summary of the GREEN findings to `docs/superpowers/probe-data/deckbuilder-raster-v1/` (e.g. `structural-fidelity-dogfood.md` + the map png) as the validation artifact.

Run:
```bash
git add docs/superpowers/probe-data/deckbuilder-raster-v1/
git commit -m "test(visual-audit): RED/GREEN dogfood of Structural Fidelity on the deckbuilder map"
```

---

### Task 4: Finalize

- [ ] **Step 1: Delete throwaway harness** (per the project's throwaway-cleanup discipline) — only if it is NOT needed for the deferred map-fix track. Confirm with the owner first; the `structural-fidelity-lens` memory notes the deferred fix track may reuse `_shot.gd`.

```bash
# only after owner confirms the harness isn't needed for the deferred map fix:
git rm --cached games/deckbuilder-0001/_shot.gd 2>$null
Remove-Item games/deckbuilder-0001/_shot.gd, games/deckbuilder-0001/_map_shot.png -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Update the parent docs if needed.** The skill loop in `README.md`/`CLAUDE.md` references `visual-audit` generically (not the lens count), so likely no change — verify there's no hardcoded "six lenses"/"five lenses" count anywhere.

Run: `grep -rn "five lenses\|six lenses\|5 lenses\|6 lenses" README.md CLAUDE.md .claude/skills/`
Expected: only the updated `visual-audit/SKILL.md` references; fix any stragglers.

- [ ] **Step 3: Final review + push (owner-gated).** Summarize the change to the owner; push only when authorized (the deckbuilder thread last pushed `origin/main @ eceeac6`; the spec commit `606b707` + these commits are ahead).

---

## Self-review notes
- **Spec coverage:** new lens doc (Task 1) ↔ spec "The new lens"; spine edits (Task 2) ↔ spec "Spine edits"; RED/GREEN + N/A (Task 3) ↔ spec "Testing/validation"; name default + deferred map fix ↔ spec "Open items". All sections covered.
- **No placeholders:** the full lens doc and every spine edit are quoted verbatim; the brief (Task 3 Step 2) is generated from named source files, not stubbed.
- **Consistency:** lens filename `references/structural-fidelity.md`, attribution token `chrome-code-layout`, and the "N/A when no brief" rule are identical across the doc, the spine edits, and the test.
