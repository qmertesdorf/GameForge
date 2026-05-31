---
name: builder
description: Use when generating a runnable Godot 4.x project from a manifest's concept block. Produces games/<id>/, writes manifest.build, and sets status to "generated".
---

# builder

Generate a Godot 4.x project that opens and runs **without manual code fixes**, with a functional core loop, deliberate primitive visuals, and enough **game feel** that it reads as an intentional toy rather than a tech demo. "Runs without errors" is the floor, not the goal — a playtester should feel feedback on every action.

## Inputs
- `manifests/<id>.json` with a populated `concept` block (`status = "concept"`).
- The pinned Godot version from `README.md` (the source of truth for `engine_version`).

## Outputs
- A project under `games/<id>/`.
- A populated `manifest.build` block and `assets[]` entries.
- `status = "generated"`.

## Hard requirements
- The project MUST import and run headless with **no script errors** (the `validator` enforces this).
- Wire **touch/tap input** for Android (`InputEventScreenTouch` and/or `_input`), not just keyboard.
- Implement every mechanic listed in `concept.mechanics`, plus **game over + restart** so the loop is replayable.
- Keep one main scene runnable on launch (`run/main_scene` set in `project.godot`).
- Ship the **Game feel & juice** and **Tuning & fairness** requirements below — they are not optional polish, they are what separates "playable" from "terrible but playable" (see `docs/superpowers/poc-run-001.md`).

## Deliberate primitives (no external art — that is M1)
Derive a coherent palette and shape language from `concept.art_direction`. Use in-engine drawing only: `ColorRect`, `Polygon2D`, `_draw()`, `Line2D`, simple `GPUParticles2D`/`CPUParticles2D`. Aim for *intentional* — clean shapes and a 3–5 color palette. Record each visual as an asset entry:
```
{ "type": "sprite", "name": "player", "source": "placeholder", "origin": "primitive" }
```

Compose a **layered scene**, not a flat field of rects (flat is the #1 cause of "looks terrible"):
- **Background layer:** never leave dead space. Add cheap depth — a subtle gradient, parallax lines/dots/stars that scroll slower than the play layer, or a faint grid.
- **Play layer:** the actors (player, obstacles, pickups).
- **HUD layer:** a **large, high-contrast** score read-out (top-center is safe), drawn last so it's always readable.
- **Glow recipe for "neon"/primitive shapes:** draw an oversized, low-alpha halo *behind* each shape (e.g. a rect/circle ~1.5–2× the size at ~15–25% alpha), then the crisp shape on top. Thick additive `Line2D` reads as a glowing edge. Asserting a neon palette is not enough — you must *execute* the glow.

## Game feel & juice (REQUIRED — wire at least these)
Every action needs feedback. Cheap, headless-safe techniques:
- **Impact on death:** a brief screen shake (offset the camera/draw origin by a decaying random vector for ~0.2s) and/or a full-screen flash.
- **Reward on score/milestone:** a quick scale-pop or color pulse on the score, or a particle burst at the actor.
- **Squash/stretch:** scale the player non-uniformly on jump take-off and landing (even ±15% for a few frames reads as life).
- **Responsive controls:** act on input immediately; for a jump, allow a short **coyote-time** window (~0.1s after leaving the ground) and/or input buffering so taps feel honored, not dropped.
Keep effects timer/tween-driven and reset cleanly on restart.

## Tuning & fairness (REQUIRED)
A loop that is unfair or arbitrarily paced reads as broken even when it "works":
- **Make every challenge clearable.** Derive limits from the player's own capabilities — e.g. compute jump airtime/horizontal reach and set the *minimum* obstacle spacing so a perfectly-timed input always succeeds. Never spawn an unavoidable obstacle.
- **Start gentle, ramp gradually.** Define an explicit starting difficulty (speed/spawn rate) and a slow ramp with a hard cap (`MAX_*` constants), so the first ~10s is forgiving and tension builds.
- Pull the intended curve from `concept.core_loop` if it specifies one; otherwise choose sane defaults and note them in a comment.

## Reference scaffold (adapt to the genre)

`games/<id>/project.godot`:
```
config_version=5

[application]
config/name="<Title Name>"
run/main_scene="res://Main.tscn"

[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation="portrait"

[input]
tap={
"deadzone": 0.5,
"events": []
}
```

`games/<id>/Main.gd` (skeleton — fill the genre-specific loop):
```gdscript
extends Node2D

var score: int = 0
var alive: bool = true

func _ready() -> void:
	_start_game()

func _start_game() -> void:
	score = 0
	alive = true
	# spawn player + initial world here

func _input(event: InputEvent) -> void:
	# Android tap + desktop click both arrive here.
	if event is InputEventScreenTouch and event.pressed:
		_on_tap()
	elif event is InputEventMouseButton and event.pressed:
		_on_tap()

func _on_tap() -> void:
	if not alive:
		_start_game()
		return
	# core action (jump / shoot / swap ...) goes here

func _process(delta: float) -> void:
	if not alive:
		return
	# advance the world; on the loss condition call _game_over()

func _game_over() -> void:
	alive = false
	# show "tap to restart"
```

Create `Main.tscn` as a text scene referencing `Main.gd` on the root node, plus the primitive nodes the genre needs.

## Steps

1. Read `manifests/<id>.json`; confirm `concept` is populated.
2. Scaffold `games/<id>/` with `project.godot`, `Main.tscn`, `Main.gd`, and any extra scenes/scripts the mechanics need. Use the pinned `engine_version` from `README.md`.
3. Implement the core loop from `concept.core_loop` + `concept.mechanics`, including game-over + restart and touch input.
4. Apply the primitive visual style from `concept.art_direction` as a **layered scene** (background + play + HUD) with the glow recipe.
5. Wire the **Game feel & juice** feedback and apply **Tuning & fairness** (clearable spacing, gentle start + capped ramp).
6. Write the build block:
   ```
   node tools/manifest.mjs merge <id> "{\"build\": {\"engine\": \"godot\", \"engine_version\": \"<pinned>\", \"language\": \"gdscript\", \"project_path\": \"games/<id>/\", \"addons\": [], \"export_presets\": [\"android\"]}}"
   ```
7. Record primitive assets:
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ ...primitive entries... ]}"
   ```
8. Advance status:
   ```
   node tools/manifest.mjs set-status <id> generated
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`. Hand off to `validator`.

## Notes
- Importing a `.gd` script generates a sibling `<name>.gd.uid` file. This is expected Godot 4.x output, not stray junk — commit it alongside the script.

## Forward-looking (not required in POC)
The future automated `core_loop_functional` check expects a headless **self-test** scene that simulates input over N frames and asserts state changes. If cheap, emit `games/<id>/selftest.gd` now so the hook exists; otherwise leave it for the `validator`'s documented plug-in point.
