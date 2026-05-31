# GameForge POC — Summary & Retro

**Branch:** `gameforge-poc` · **Date:** 2026-05-30 · **Engine:** Godot 4.6.3.stable
**Spec:** `specs/2026-05-30-gameforge-poc-design.html` · **Plan:** `plans/2026-05-30-gameforge-poc.md`

## What the POC set out to prove

A one-line prompt can become a **playable Godot game** through three Claude Agent Skills
(`concept` → `builder` → `validator`) coordinated by a JSON **manifest** (the "spine").
The real deliverable is **better skills**, not the games: every run had to convert a felt
quality/cohesion gap into a *specific, attributable* `SKILL.md` edit (success criterion §2.5),
and the next run had to show the edit moved the output.

## The architecture (what got built)

- **Manifest tool** — `tools/manifest.mjs`, a Node/ESM CLI + library: `newManifest`,
  `setStatus` (enforced transition graph `concept→generated→validated→playable | →failed`),
  `merge` (deep-merge blocks, arrays replace), `validate` (Ajv against
  `schema/manifest.schema.json`), plus file helpers/CLI. The only component with real logic,
  so it has full TDD: **24/24 vitest tests green**.
- **Three skills** — prose `SKILL.md` files under `.claude/skills/{concept,builder,validator}/`.
  Genre lives *only* in the manifest's `concept` block; the skills are genre-agnostic.
- **Godot 4.6.3.stable** installed via winget + Android export templates; headless run is the
  validator's programmatic gate, `selftest.gd` (builder-emitted) is the logic gate.

## The runs (one skill set, genre lives in the manifest)

| Run | id | name | genre | result | what it proved |
|-----|----|----|-------|--------|----------------|
| 001 | `runner-0001` | Neon Dash | endless runner | playable ("terrible but playable") | pipeline works end-to-end; quality gap is attributable to `builder`/`concept` prose |
| 001 A/B | `runner-0002` | Neon Dash II | endless runner | "feels like a game" | **editing prose raises quality** (mechanism proven, 1st time) |
| 002 | `match3-0001` | Prism Cascade | match-3 | playable | 2nd genre; surfaced the Godot-4.6 strict-typing rule |
| 003 | `shooter-0001` | Vector Storm | top-down shooter | playable | **3rd distinct genre → §2 bar MET**; typing rule (carried fwd) → 0 build iterations |
| 004 | `match3-survival-0001` | Aegis Grid | match-3 + survival | playable ("coexist") | pipeline is **blend-agnostic**; but subsystems coexist, not fuse |
| 005 | `match3-survival-0002` | Aegis Grid II | match-3 + survival | playable ("interrupt/alternate") | forcing-function rule moved cohesion (mechanism 3rd time) — but genres still alternate |
| 006 | `match3-survival-0003` | Aegis Grid III | match-3 + survival | playable ("fused / coheres") | **state/space-fusion rule closes the cohesion gap** (mechanism 4th time) |

## What was proven against §2

1. **One skill set generalizes across ≥3 distinct genres.** Runner + match-3 + shooter all
   reached `playable` from an *unchanged* skill set (runs 001–003). The §2 ≥3-genre bar is met.
2. **Per-run skill findings improve the next run.** Findings compound: the run-002 typing rule,
   passed forward, gave runs 003/004/006 zero-iteration builds; run-005's self-test lifecycle
   note pre-empted run-006's only would-be fix.
3. **The POC mechanism — editing prose moves the output — confirmed 4×, across 3 edit types:**
   - *quality* (run-001→002): juice/visuals/tuning/depth edits → "feels like a game."
   - *forcing-function cohesion* (run-004→005): a telegraphed pressure event → blend stops
     merely coexisting, but only *alternates*.
   - *state/space-fusion cohesion* (run-005→006): put the threat *on the board* so one action
     serves both genres → blend *coheres as one game*.
4. **Combination axis: strongly demonstrated.** Trajectory coexist → interrupt → **fused**. The
   pipeline is blend-agnostic, and the specific concept lever for cohesion was *identified*
   (shared state/space + tempo alignment) and a prose edit moving it was *confirmed*.
5. **Failures are legible.** Every gap was attributed to a named skill with a concrete edit —
   no "it didn't work," always "skill X under-specifies Y."

## What the skills look like now

- **`concept`** — derives a differentiated concept; `core_loop` must state the per-second
  decision (agency rule); a **Hybrid/combination** section leads with *state/space fusion*
  (both genres act on the same objects; threat lives in genre A's world) + a tempo-alignment
  check, with the forcing-function demoted to a *supplement*.
- **`builder`** — required **Game feel & juice**, layered visuals + glow, **Tuning & fairness**;
  a **Godot-4.6 strict-typing rule** (annotate types when indexing untyped Array/Dict;
  `clamp`/`lerp`/`.filter()`/`.map()` return Variant); a **Hybrid / dual-loop** subsection
  (shared-resource contention; prefer shared-space coupling; telegraphed-vs-continuous threat
  distinction); `selftest.gd` **REQUIRED** for logic-heavy genres; self-test `_ready()`-deferred
  lifecycle note.
- **`validator`** — programmatic headless gate (exit 0, no script errors) + **Method 1.5** live
  logic gate (`selftest.gd` → `SELFTEST OK`) + human playtest gates feel/cohesion.

## Residual open findings (LOW — not blockers)

- **`builder`:** the Hybrid "watch fairness over a 3000-frame headless run" line is unactionable
  — a `--quit-after` run synthesizes no offense. Next builder edit: drop it (fairness = human
  concern) **or** specify a `selftest.gd` that synthesizes N forced matches/tick and asserts the
  threat trends down under steady offense.
- **doc note:** `.gd.uid` files are written by the editor's import pass; headless-only runs emit
  none. Builder Notes could say so explicitly. Harmless for the POC.

## Operational notes

- Pinned engine is **4.6.3.stable** (README is source of truth; the plan's `4.4.1` was a
  placeholder). Launch a game for playtest: `& "<godot.exe>" --path games/<id>/`.
- A usage-policy false-positive (likely the shooter's combat vocabulary) and intermittent
  garbled tool output were seen mid-session; all work/git history was cross-checked intact.
  See `usage-policy-note.md`.

## Verdict

**All §2 success criteria met.** The core thesis holds: with the manifest as the spine, output
quality and blend cohesion are a function of skill prose — and we can identify the responsible
lever, edit it, and measure the improvement. Next step: finish the `gameforge-poc` branch.
