---
name: validator
description: Use when confirming a generated Godot game opens, runs, and has a working core loop. Runs headless checks, records manifest.validation, and advances status to validated/playable or failed.
---

# validator

Confirm a generated game opens, runs without script errors, and (via human playtest) has a working core loop. Make every failure **legible** — attribute it to a specific skill gap (POC success criterion #5).

## Inputs
- `manifests/<id>.json` with a populated `build` block (`status = "generated"`).
- The project on disk at `games/<id>/`.

## Outputs
- A populated `manifest.validation` block.
- `status = "validated"` (programmatic checks pass), then `"playable"` (human playtest passes), or `"failed"` with legible `issues`.

## Method 1 — Programmatic (automated now)

1. **Run the project headless** and capture output + exit code:
   ```
   godot --headless --path games/<id>/ --quit-after 120
   ```
   PASS when: exit code is 0 AND the output contains no `SCRIPT ERROR`, no `ERROR:`, and no "Failed to load" lines. (A clean run of ~120 frames means the scene tree loaded and `_process` ran without crashing.)

2. Record results:
   ```
   node tools/manifest.mjs merge <id> "{\"validation\": {\"opens_in_editor\": true, \"runs\": true, \"issues\": []}}"
   ```
   - On failure, set `runs: false` and put each error line in `issues` verbatim, then:
     ```
     node tools/manifest.mjs set-status <id> failed
     ```
     STOP and report which skill is responsible (almost always `builder`) and the precise error.

3. On a clean run, **do not advance yet** — proceed to Method 1.5. The build is structurally sound, but "runs clean" is not "plays correctly"; the logic gate decides whether it reaches `validated`.

## Method 1.5 — Logic self-test (automated; REQUIRED if `games/<id>/selftest.gd` exists)

Headless error-checking cannot catch logic bugs in logic-heavy genres (match-3, hybrids): a mis-detected match, broken gravity, or an offense action that never damages the threat all run clean and only fail a human (POC runs 002–004). `builder` now emits `games/<id>/selftest.gd` for such genres — run it:
```
godot --headless --path games/<id>/ --script res://selftest.gd
```
- **PASS** = exit code 0 AND output contains `SELFTEST OK`. Then advance:
  ```
  node tools/manifest.mjs merge <id> "{\"validation\": {\"core_loop_functional\": true}}"
  node tools/manifest.mjs set-status <id> validated
  ```
  (`core_loop_functional` is now backed by an assertion, not just a hopeful human — the human playtest in Method 2 confirms *feel*, the self-test confirms *logic*.)
- **FAIL** = `SELFTEST FAIL: <reason>` or non-zero exit. Record the reason verbatim in `issues`, set `core_loop_functional: false`, `set-status <id> failed`, and STOP — attribute it to `builder` with the precise assertion that failed (e.g. "builder: a 3-in-a-row swap did not clear any cells"). This is a POC success: a logic bug was caught automatically.
- **No `selftest.gd` for a logic-heavy genre** is itself a `builder` finding — note it ("shipped no automated proof its loop works"), then advance to `validated` on the clean run and lean harder on Method 2. For a genuinely trivial arcade loop, absence is fine.

## Method 2 — Human playtest (manual now)

4. Ask the owner to open the project in the Godot editor and play for ~60 seconds, confirming the core loop from `concept.core_loop` (e.g. tap → jump, score climbs, game-over → restart works).

5. On confirmation:
   ```
   node tools/manifest.mjs merge <id> "{\"validation\": {\"core_loop_functional\": true}}"
   node tools/manifest.mjs set-status <id> playable
   ```
   If the loop is broken, record the specific failure in `issues`, set the loop boolean false, and attribute it to a skill (e.g. "builder did not wire restart on tap after game over"). Do NOT advance to `playable`.

## Toward full automation — what's built vs. what remains

Method 1.5 above is the first half of this hook, now **live** for logic-heavy genres: `builder` emits `selftest.gd`, the validator runs it, and `SELFTEST OK` backs `core_loop_functional` with an assertion instead of a hope. What it does NOT yet do is **replace the human playtest** — the self-test proves the loop's *logic* is correct, but `playable` still requires a human to confirm it *feels* right (juice, fairness, that a blend actually coheres). The remaining future step is to grow `selftest.gd` coverage (and add feel heuristics) until `status` can reach `playable` in CI with no human in the loop. Until then: self-test gates `validated`, human gates `playable`.

## Notes
- Some Godot CLI flags vary slightly by 4.x point release; if `--quit-after` is unavailable, fall back to `--headless --path games/<id>/ --quit` after confirming `--import` succeeds. Verify against the pinned version.
- Legibility is the product. "It didn't work" is a POC failure; "builder doesn't scaffold touch input" is a POC success.
