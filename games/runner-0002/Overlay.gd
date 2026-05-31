extends Node2D

# Top overlay layer for the SVG re-skin: particles + HUD + crash flash must draw
# ABOVE the world-actor Sprite2Ds. Since a Node2D's own _draw() renders below its
# children (the sprites), this content is split into a higher-z_index child that
# delegates back to Main.draw_overlay(). Pure presentation — no game state here.

var game: Node2D = null


func _draw() -> void:
	if game != null:
		game.draw_overlay(self)
