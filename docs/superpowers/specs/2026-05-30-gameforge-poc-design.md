# GameForge — POC Technical Design

**Working name:** GameForge
**Status:** Approved design v1.0 — POC scope
**Date:** 2026-05-30
**Audience:** Claude Code (handoff document) + project owner
**Purpose:** Orient an agentic build of the proof-of-concept. Defines what the POC must prove, the minimal architecture, the per-title *manifest* that everything hangs off, the first skills to build, the repo layout, the post-POC roadmap, and what is explicitly out of scope.

This document supersedes the original Draft v0.1. It folds in four decisions settled during brainstorming (see §3).

---

## 1. What this is (and isn't)

GameForge is an AI pipeline that turns a short prompt into a playable mobile game, built as a set of **Agent Skills** invoked by Claude. The long-term vision is many genuinely-different titles across genres, with skills for generation, compliance, submission, and continuous maintenance (see §10 roadmap).

**This POC is deliberately smaller.** Its only job is to answer one question:

> Can a small set of skills reliably generate a game that compiles, runs, and is playable — across several different genres — with minimal hand-holding?

Everything else (store submission, monetization, the sustain-phase skills, production/API billing) is **out of scope for the POC** and is captured as future milestones in §10 so it doesn't get built prematurely.

---

## 2. Success criteria

The POC succeeds if, using interactive Claude Code on the owner's subscription:

1. From a one-line prompt, the pipeline produces a working game project for **at least 3 distinct genres** (e.g. an endless runner, a match-3, a top-down shooter).
2. Each generated project **opens and runs in the engine without manual code fixes**.
3. Each game is **playable** — its core loop functions — for at least ~60 seconds.
4. A **manifest** (§5) is produced and correct for each title.
5. When generation fails, the failure is **legible enough to attribute to a specific skill gap** (so the skill can be improved). "It just didn't work" is a POC failure; "the Builder skill doesn't scaffold input handling for touch" is a POC success.

Criterion 5 is the real point: the POC is a test of *skill quality and the iteration loop*, not of throughput. The deliverable of the POC is **better skills**, not the games themselves.

---

## 3. Settled decisions

These were confirmed during brainstorming and are now locked.

| Decision | Resolution | Notes |
|---|---|---|
| **Engine** | **Godot 4.x** (confirmed) | Text-based `.tscn` scenes + GDScript are LLM- and diff-friendly; free, no per-seat licensing at scale; exports to iOS + Android. Manifest, builder, and validator all assume Godot. |
| **Validation method** | **Hybrid: CLI + human playtest**, with a documented automation path | Programmatic checks via the Godot headless CLI set `status = "validated"`; a human playtest advances it to `"playable"`. See §6 `validator` for the future full-automation design. |
| **Assets in POC** | **Deferred (M1), but POC uses deliberate primitives** | No image/audio generation in the POC. `builder` must produce *intentional* primitive/procedural visuals — coherent palette, clean shapes, simple effects — not broken-looking placeholders. The `asset` skill is M1 (§10). |
| **Environment** | **Godot is NOT yet installed** — installation is Step 0 | Verified during brainstorming: no Godot on PATH, Program Files, Steam, scoop, or winget. The implementation plan begins with installing Godot 4.x + Android export templates and verifying the CLI before any scaffolding. |

Remaining defaults (unchanged from the original doc):

| Decision | Default | Rationale |
|---|---|---|
| Target platform for POC | **Android-first** | No Mac/Xcode dependency; fastest local test loop. |
| Dev machine | **PC (Windows) primary** | The full Android-first POC runs here with no Mac needed. Mac is the iOS publish leg only (§11). |
| Claude billing | **Interactive Claude Code on Pro/Max** | Human-in-the-loop phase; covered by subscription. API billing reserved for the future autonomous pipeline. |
| Repo location | **Current directory** (`mobile-gen/`) | Scaffold directly here rather than nesting a `gameforge/` subfolder; the folder name is cosmetic. |

---

## 4. Architecture (POC scope)

Three layers, kept distinct:

- **Skills** — folders containing a `SKILL.md` (YAML frontmatter `name` + `description`, then markdown instructions). These hold the *procedure and judgment*. Claude loads a skill's body only when relevant (progressive disclosure).
- **Agent runtime** — interactive Claude Code in the terminal. The owner drives it; Claude invokes skills and writes files.
- **Tools** — for the POC, mostly the local filesystem and the Godot CLI. (Asset generation, store APIs, etc. become MCP tools in later milestones — not now.)

Connecting them is the **manifest**: a per-title JSON file that is the single source of truth. Every skill reads from and writes to it. This is the most important thing to get right, because it's what later milestones (maintenance especially) depend on.

**Skills in scope for the POC:** `concept`, `builder`, `validator`.
**Deferred (do not build yet):** `asset`, `compliance`, `listing`, `submission`, `monitor`, `updater`, `troubleshooter` — each is a future milestone (§10).

---

## 5. The manifest (the spine)

One JSON file per title at `manifests/<title-id>.json`. POC fields below; reserved keys are included so the schema is extensible without restructuring later.

```json
{
  "id": "runner-0001",
  "name": "Neon Dash",
  "created_at": "2026-05-30T12:00:00Z",
  "updated_at": "2026-05-30T12:00:00Z",
  "status": "playable",                // concept | generated | validated | playable | failed
  "concept": {
    "genre": "endless runner",
    "core_loop": "tap to jump, avoid obstacles, score climbs with distance",
    "mechanics": ["jump", "obstacle spawning", "score", "game over + restart"],
    "art_direction": "neon vector, dark background",
    "target_platforms": ["android"],
    "differentiation_notes": "single-tap control; not a clone of a saturated title"
  },
  "build": {
    "engine": "godot",
    "engine_version": "4.x",
    "language": "gdscript",
    "project_path": "games/runner-0001/",
    "addons": [],
    "export_presets": ["android"]
  },
  "assets": [
    { "type": "sprite", "name": "player", "source": "placeholder", "origin": "primitive" }
  ],
  "validation": {
    "opens_in_editor": true,
    "runs": true,
    "core_loop_functional": true,
    "issues": []
  },

  "_reserved": {
    "compliance": null,
    "store": null,
    "maintenance": null
  }
}
```

Rules:
- The `builder` skill **must** emit a complete `build` block — this is what a future maintenance skill needs to reason about the title.
- `status` is advanced by skills as the title moves through the loop.
- Never delete `_reserved`; later milestones fill it in. Every `_reserved` key maps to a named milestone in §10.

---

## 6. Skills in scope

Each skill is `.claude/skills/<name>/SKILL.md`. Authoring convention example:

```markdown
---
name: builder
description: Generate a runnable Godot project from a concept spec in the manifest. Use after the concept skill has populated manifest.concept. Emits the build block and the game project files.
---

# Builder

[Instructions Claude follows: how to scaffold a Godot 4.x project, where to
write files, how to populate manifest.build, conventions for scenes/scripts,
how to wire touch input, how to keep the core loop minimal but functional,
how to produce deliberate primitive visuals...]
```

### `concept`
- **Purpose:** turn a one-line prompt into a structured, validated design spec.
- **Inputs:** prompt string; existing `manifests/` (to avoid near-duplicates).
- **Outputs:** populated `manifest.concept`; `status = "concept"`.
- **Notes:** includes a lightweight differentiation check (is this just a clone of a saturated genre?). Populates `art_direction`, which `builder` uses to drive its primitive visual style.

### `builder`
- **Purpose:** generate a runnable Godot project from `manifest.concept`.
- **Inputs:** `manifest.concept`.
- **Outputs:** a project under `games/<id>/`; populated `manifest.build`; `status = "generated"`.
- **Notes:**
  - Must produce a project that opens and runs without manual fixes.
  - Keep the core loop minimal but functional.
  - **Deliberate primitives:** use in-engine primitive/procedural art (shapes, palettes, simple particle effects) that looks *intentional* — coherent color palette derived from `concept.art_direction`, clean shapes, basic visual feedback. No external generated art (that's M1). Record each as `assets[] { source: "placeholder", origin: "primitive" }`.
  - Must wire touch/tap input for Android.

### `validator`
- **Purpose:** confirm the generated game opens, runs, and has a working core loop.
- **Inputs:** `manifest.build`, the project on disk.
- **Outputs:** populated `manifest.validation`; advances `status` to `validated`/`playable` or flips to `failed` with legible `issues`.
- **Validation method (hybrid):**
  1. **Programmatic (automated now):** run Godot headless via the CLI — project imports, runs without script errors, scene tree loads, no parse/load failures. On success, set `status = "validated"` and fill the booleans in `manifest.validation` that can be checked programmatically (`opens_in_editor`, `runs`).
  2. **Human playtest (manual now):** the owner playtests in the editor to confirm the core loop actually works (tap → jump, score climbs, game-over/restart). On confirmation, set `core_loop_functional = true` and advance `status = "playable"`.
- **Future full automation (documented, not built in POC):** the `core_loop_functional` check is the manual step to automate later. The intended design: `builder` emits a headless **self-test** scene/script that simulates input over N frames and asserts observable state changes (e.g. score increments, player Y changes on jump, game-over fires on collision), runnable via the Godot CLI in CI. The `validator` skill must include an inline comment marking exactly where this automated self-test would plug in (replacing the human playtest step), so the automation is designed-for, not bolted-on.
- **Notes:** prefer programmatic checks over guesswork; record *why* something failed in terms a skill author can act on (criterion #5).

---

## 7. Repo layout

```
mobile-gen/                          # current working directory (repo root)
├── docs/superpowers/specs/
│   └── 2026-05-30-gameforge-poc-design.md   # this document
├── .claude/
│   └── skills/
│       ├── concept/SKILL.md
│       ├── builder/SKILL.md
│       └── validator/SKILL.md
├── manifests/
│   └── <title-id>.json             # one per game (the spine)
├── games/
│   └── <title-id>/                 # generated Godot project
├── tools/                          # placeholder/local helper scripts (MCP later)
├── .gitignore                      # Godot 4 ignores (§11)
└── README.md
```

---

## 8. POC workflow (the loop)

For each test game:

1. Owner gives a one-line prompt in Claude Code.
2. `concept` → writes `manifest.concept`.
3. `builder` → generates `games/<id>/`, writes `manifest.build`.
4. `validator` → runs programmatic checks, writes `manifest.validation`, sets `status = "validated"`.
5. Owner playtests in the Godot editor → confirms core loop → `status = "playable"`.
6. Where output is wrong, owner identifies the responsible skill and **edits that `SKILL.md`**, then re-runs.
7. Repeat across ≥3 genres until the loop produces playable games reliably.

The deliverable of the POC is **better skills**, not the games.

---

## 9. Out of scope for the POC

Deferred — captured as milestones in §10, not to be built during the POC:

- Store submission, developer accounts, signing for distribution.
- Monetization (ads / IAP), store listings, ASO.
- Compliance, age ratings, privacy/data-safety automation.
- The sustain-phase skills: `monitor`, `updater`, `troubleshooter`.
- MCP tools for asset generation and store APIs.
- Autonomous/scheduled operation and any API/production billing.

These are real and planned — just not what the POC proves.

---

## 10. Roadmap — milestones beyond the POC

All deferred skills are eventually in scope. They are recorded here so the full arc stays legible and nothing is built prematurely. Each milestone is one skill (plus any MCP tool it needs) and fills in a piece of the manifest that is currently a placeholder. Ordered by the game lifecycle: **make it → make it real → make it legal → make it findable → ship it → keep it alive.**

| Milestone | Skill | Adds | Manifest target |
|---|---|---|---|
| **M0 (this spec)** | `concept`, `builder`, `validator` | Generation reliability across ≥3 genres, primitive visuals | `concept`, `build`, `validation` |
| **M1** | `asset` | Real art/audio via an asset-gen MCP tool, replacing POC primitives | `assets[]` (real sources) |
| **M2** | `compliance` | Age ratings, privacy/data-safety declarations, content-policy checks | `_reserved.compliance` |
| **M3** | `listing` | Store listing copy, screenshots, ASO metadata | `_reserved.store.listing` |
| **M4** | `submission` | Developer accounts, signing, build upload to Play/App Store via store-API MCP tools — **iOS/Mac leg activates here** | `_reserved.store.submission` |
| **M5** | `monitor` | Post-launch metrics / crash / review monitoring | `_reserved.maintenance` (begins) |
| **M6** | `updater` | Generate and ship updates driven by monitor signals | `_reserved.maintenance` |
| **M7** | `troubleshooter` | Diagnose and fix live issues — crashes, broken builds, policy strikes | `_reserved.maintenance` |

**Dependencies:**
- M1–M4 are largely independent, but `submission` (M4) realistically wants `compliance` (M2) and `listing` (M3) done first.
- M5–M7 (the "sustain phase") all depend on M4 — you cannot monitor or update a title that isn't live.
- **Autonomous/scheduled operation and API/production billing** are a cross-cutting concern that arrives with the sustain phase (M5+), not a milestone of its own. This is the point at which the pipeline must run unattended, so it is also where billing shifts from interactive subscription to API.

Each milestone gets its own spec → plan → implementation cycle.

---

## 11. Development environment & version control

**Machine roles.** Work is split across two machines, cleanly:

- **PC (Windows) — primary.** Skills, generation, the manifest, all code and asset work, plus Android export and playtesting. Because the POC is Android-first, the **entire POC runs here with no Mac involvement.**
- **Mac — iOS publish leg only.** Building, signing, and submitting an iOS app requires a Mac with Xcode. The Mac handles export → Xcode → sign → upload to App Store Connect, and isn't needed until iOS is on the table (post-POC, M4).

Claude Code runs on both machines under the same subscription; both are interactive/human-in-the-loop.

**Version control is the transfer mechanism — git from day one.** Do not copy files between machines by hand. The whole repo (skills, manifests, game projects) is plain files, so it's git-native:

- Develop and push on the PC.
- When it's time for iOS, pull the repo on the Mac and run the iOS export there.

**Cross-machine consistency requirements:**

- Pin the **same Godot version** on both machines; the manifest's `build.engine_version` is the source of truth.
- Install the iOS **export templates** on the Mac.
- The Apple toolchain lives on the Mac: Xcode, the $99/yr developer account (only at actual submission), signing certificates / provisioning profiles. Keep secrets (keystores, certs) **out of git**.

**`.gitignore` (Godot 4):**

```gitignore
# Godot 4 editor cache / generated
.godot/

# Build outputs
/builds/
*.apk
*.aab
*.ipa

# Secrets — never commit
*.keystore
*.p12
*.mobileprovision

# OS cruft
.DS_Store
Thumbs.db
```

---

## 12. First implementation tasks (Step 0 first)

0. **Install Godot 4.x** on the PC (Godot is currently not installed — verified during brainstorming). Install the standard Godot 4.x editor + **Android export templates**, put the binary on PATH so `godot --version` works, and verify a blank project can be created and run **headless from the CLI**. This is a hard prerequisite — nothing else can be validated without it.
1. **Initialize a git repository** and add the Godot `.gitignore` from §11.
2. Scaffold the repo layout in §7 (in the current directory).
3. Draft `concept/SKILL.md`, `builder/SKILL.md`, and `validator/SKILL.md` per §6, plus the manifest writer per §5.
4. Generate the first test game (an endless runner) end-to-end.
5. Report where the loop broke, in terms of which skill needs improvement (criterion #5).

---

## 13. Risks & notes

- **Primary risk:** generation reliability. If `builder` only works with heavy hand-holding, that's the finding to surface early, not paper over.
- **Rate limits:** full-game generation is token-heavy; iterating across several games may bump the interactive 5-hour/weekly caps (more so on Pro than Max). Pace runs; let windows reset.
- **Stay on-subscription:** if `ANTHROPIC_API_KEY` is set in the shell, Claude Code bills API rates instead of the plan — clear it for this phase.
- **iOS:** requires a Mac + Xcode and is the one step that cannot run on the PC (M4). Only relevant once Android-side generation is solid.
