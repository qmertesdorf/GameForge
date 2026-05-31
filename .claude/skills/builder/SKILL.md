---
name: builder
description: Use when generating a runnable Godot 4.x project from a manifest's concept block. Produces games/<id>/, writes manifest.build, and sets status to "generated".
---

# builder

Generate a Godot 4.x project that opens and runs **without manual code fixes**, with a minimal-but-functional core loop and deliberate primitive visuals.

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

## Deliberate primitives (no external art — that is M1)
Derive a coherent palette and shape language from `concept.art_direction`. Use in-engine drawing only: `ColorRect`, `Polygon2D`, `_draw()`, `Line2D`, simple `GPUParticles2D`/`CPUParticles2D`. Aim for *intentional* — clean shapes, a 3–5 color palette, basic visual feedback (a flash/particle on score or collision). Record each visual as an asset entry:
```
{ "type": "sprite", "name": "player", "source": "placeholder", "origin": "primitive" }
```

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
4. Apply the primitive visual style from `concept.art_direction`.
5. Write the build block:
   ```
   node tools/manifest.mjs merge <id> "{\"build\": {\"engine\": \"godot\", \"engine_version\": \"<pinned>\", \"language\": \"gdscript\", \"project_path\": \"games/<id>/\", \"addons\": [], \"export_presets\": [\"android\"]}}"
   ```
6. Record primitive assets:
   ```
   node tools/manifest.mjs merge <id> "{\"assets\": [ ...primitive entries... ]}"
   ```
7. Advance status:
   ```
   node tools/manifest.mjs set-status <id> generated
   node tools/manifest.mjs validate <id>
   ```
   Expected: `<id> OK`. Hand off to `validator`.

## Forward-looking (not required in POC)
The future automated `core_loop_functional` check expects a headless **self-test** scene that simulates input over N frames and asserts state changes. If cheap, emit `games/<id>/selftest.gd` now so the hook exists; otherwise leave it for the `validator`'s documented plug-in point.
