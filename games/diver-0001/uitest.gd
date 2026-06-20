extends SceneTree
## Interaction self-test for Fathom — the view<->input twin of selftest.gd.
## selftest.gd proves the RULES (drives DiveState directly); this proves that a
## real tap on a control reaches its handler: steering, the ASCEND button, and
## the DIVE AGAIN restart. Boots Main.tscn headless, pushes real
## InputEventMouseButton clicks, and asserts ENGINE state after each.
## Prints one "UITEST PASS/FAIL:" line per check, then exactly "UITEST OK" and
## exits 0, or "UITEST FAIL: <n> checks failed" and exits 1.
## Run: godot --headless --path games/diver-0001/ --script res://uitest.gd

var main: Node2D
var fail_count: int = 0


func _initialize() -> void:
	_run()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fail_count += 1
	var tag: String = "PASS" if ok else "FAIL"
	print("UITEST %s: %s %s" % [tag, name, detail])


func _click(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	root.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up, true)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	var scene: PackedScene = load("res://Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var S: RefCounted = main.state

	# ---- boot: a dive is active and descending ----------------------------
	_check("boot_dive_active", S.active and S.descending, "active=%s descending=%s" % [str(S.active), str(S.descending)])

	# ---- steering: a tap in the play area sets the steer target -----------
	_click(Vector2(150.0, 400.0))
	await process_frame
	_check("steer_tap_lands", abs(main.target_x - 150.0) < 0.001, "target_x=%.1f" % main.target_x)

	# ---- ASCEND button: clicking it flips the dive to ascending -----------
	# Force a non-trivial depth first so the tick after the click can't surface
	# (and bank) before we read the flag — keeps the assertion deterministic.
	S.depth = 220.0
	S.descending = true
	_check("ascend_button_visible", main.ascend_button.visible)
	_click(_center(main.ascend_button))
	await process_frame
	_check("ascend_button_lands", not S.descending, "descending=%s" % str(S.descending))

	# ---- DIVE AGAIN: when the dive is over, the restart button starts a new dive
	S.active = false
	main._refresh_buttons()
	await process_frame
	_check("dive_again_visible_when_over", main.dive_again_button.visible and not main.ascend_button.visible)
	var dive_before: int = S.dive_num
	_click(_center(main.dive_again_button))
	await process_frame
	_check("dive_again_starts_new_dive", S.active and S.descending and S.dive_num == dive_before + 1, "active=%s dive=%d" % [str(S.active), S.dive_num])

	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)
