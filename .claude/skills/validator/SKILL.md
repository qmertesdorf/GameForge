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

3. On success, advance:
   ```
   node tools/manifest.mjs set-status <id> validated
   ```

## Method 2 — Human playtest (manual now)

4. Ask the owner to open the project in the Godot editor and play for ~60 seconds, confirming the core loop from `concept.core_loop` (e.g. tap → jump, score climbs, game-over → restart works).

5. On confirmation:
   ```
   node tools/manifest.mjs merge <id> "{\"validation\": {\"core_loop_functional\": true}}"
   node tools/manifest.mjs set-status <id> playable
   ```
   If the loop is broken, record the specific failure in `issues`, set the loop boolean false, and attribute it to a skill (e.g. "builder did not wire restart on tap after game over"). Do NOT advance to `playable`.

## Future full automation — DESIGNED-FOR PLUG-IN POINT (do not build in POC)

```
# AUTOMATION HOOK (M0+ future): replace Method 2 with a headless self-test.
# builder emits games/<id>/selftest.gd that simulates input over N frames and
# asserts observable state changes:
#   - score increments after a simulated tap,
#   - player Y changes on jump,
#   - _game_over() fires on a forced collision.
# Run it here via:
#   godot --headless --path games/<id>/ --script res://selftest.gd
# A 0 exit + "SELFTEST OK" marker sets core_loop_functional=true automatically,
# letting status reach "playable" in CI with no human in the loop.
```

## Notes
- Some Godot CLI flags vary slightly by 4.x point release; if `--quit-after` is unavailable, fall back to `--headless --path games/<id>/ --quit` after confirming `--import` succeeds. Verify against the pinned version.
- Legibility is the product. "It didn't work" is a POC failure; "builder doesn't scaffold touch input" is a POC success.
