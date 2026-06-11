extends SceneTree
## Interaction self-test for Tide & Tally — the view<->input twin of selftest.gd.
## selftest.gd proves the RULES are right (drives the engine directly) and the
## visual audit proves the PIXELS are right; neither can see whether a tap on a
## control actually reaches its handler (mouse-filter shadowing, missing rebuild
## events). This script closes that seam: it boots Main.tscn headless and pushes
## REAL InputEventMouseButton clicks through the whole core loop —
## gather tap -> bank -> head to shop -> craft -> shelve -> open shop ->
## patron tap -> shelf tap -> sale -> results -> next day -> gather rebuilt —
## asserting ENGINE state after every click.
## Prints one "UITEST PASS/FAIL:" line per check, then exactly "UITEST OK" and
## exits 0, or "UITEST FAIL: <n> checks failed" and exits 1.
## Run: godot --headless --path games/shopkeep-0001/ --script res://uitest.gd

const ShopStateRef := preload("res://ShopState.gd")
const MetaSaveRef := preload("res://MetaSave.gd")

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
	# in_local_coords=true: positions are canvas/viewport coords — the headless
	# window ignores the project size, so window-coord pushes get mis-stretched.
	root.push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	root.push_input(up, true)


func _find_button(text: String) -> Button:
	for c in main.ui.get_children():
		if c is Button and (c as Button).text == text:
			return c
	return null


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	# The Next Day click below triggers MetaSave.write() — clear the real
	# user:// save at start AND end so the test never leaks state into the
	# next boot (same guard as selftest.gd).
	MetaSaveRef.clear()
	var scene: PackedScene = load("res://Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# Fresh-run guarantee: replace S with a virgin seeded state and rebuild the
	# view, so assertions are deterministic regardless of boot-time state.
	var S: RefCounted = ShopStateRef.new()
	S.setup(1234, {})
	main.S = S
	main._handle_events(S.start_day())
	main._rebuild_ui()
	await process_frame

	# ---- GATHER: tap a node via real input --------------------------------
	_check("boot_in_gather", S.phase == ShopStateRef.Phase.GATHER, "phase=%d" % S.phase)
	var node_keys: Array = main.node_boxes.keys()
	_check("gather_nodes_built", node_keys.size() > 0, "boxes=%d" % node_keys.size())
	if node_keys.size() > 0:
		var box: Control = main.node_boxes[node_keys[0]]
		_click(_center(box))
		await process_frame
		_check("gather_node_tap_lands", S.unbanked_total() == 1, "unbanked=%d" % S.unbanked_total())

	# ---- bank + head to shop via real button clicks ------------------------
	var bank_btn: Button = _find_button("Bank It")
	if bank_btn != null:
		_click(_center(bank_btn))
		await process_frame
		_check("bank_button_lands", S.unbanked_total() == 0 and main._dict_total(S.resources) >= 1, "banked=%d" % main._dict_total(S.resources))
	var go_btn: Button = _find_button("Head to Shop →")
	_check("head_to_shop_button_exists", go_btn != null)
	if go_btn != null:
		_click(_center(go_btn))
		await process_frame
		_check("head_to_shop_lands_in_craft", S.phase == ShopStateRef.Phase.CRAFT, "phase=%d" % S.phase)

	# ---- CRAFT: ensure materials, click the first Craft button -------------
	S.resources = {"shell": 8, "driftwood": 4, "seaglass": 4, "pearl": 2}
	main._rebuild_ui()
	await process_frame
	var craft_btn: Button = _find_button("Craft")
	_check("craft_button_exists", craft_btn != null)
	if craft_btn != null:
		_click(_center(craft_btn))
		await process_frame
		_check("craft_click_lands", S.stock.size() == 1, "stock=%d" % S.stock.size())
	# Craft a second item so the sell screen has 2 shelf tiles.
	main._handle_events(S.craft("shell_charm"))
	await process_frame
	# Shelve both via the workbench TapBoxes (rebuilt by the crafted events).
	for round_i in range(2):
		var tapped: bool = false
		for c in main.ui.get_children():
			if c is Control and c.has_signal("tapped") and c.size == Vector2(76, 76):
				_click(_center(c))
				tapped = true
				break
		await process_frame
		if not tapped:
			break
	_check("workbench_tap_shelves_items", S.shelves.size() == 2, "shelves=%d stock=%d" % [S.shelves.size(), S.stock.size()])

	# ---- open shop via real button -----------------------------------------
	var open_btn: Button = _find_button("Open Shop →")
	_check("open_shop_button_exists", open_btn != null)
	if open_btn != null:
		_click(_center(open_btn))
		await process_frame
		_check("open_shop_lands_in_sell", S.phase == ShopStateRef.Phase.SELL, "phase=%d" % S.phase)

	# ---- SELL: spawn one patron, then tap patron + shelf -------------------
	main._handle_events(S.tick_sell(0.9))
	await process_frame
	_check("patron_spawned", main.patron_views.size() >= 1, "views=%d" % main.patron_views.size())
	if main.patron_views.size() >= 1:
		var pv: Control = main.patron_views[0]["view"]
		_click(_center(pv))
		await process_frame
		_check("patron_tap_lands", main.sel_patron == 0, "sel_patron=%d" % main.sel_patron)
	# Force the patron to want what's on shelf 0 — makes the outcome
	# deterministic: a landing tap MUST produce a sale (sel_shelf legitimately
	# resets to -1 after any serve attempt, so checking it can't distinguish
	# "tap missed" from "tap landed but wrong item").
	if not S.patrons.is_empty() and not S.shelves.is_empty():
		S.patrons[0]["want"] = S.shelves[0]
	var first_tile: Control = null
	for t in main.shelf_tiles:
		if t != null:
			first_tile = t
			break
	_check("shelf_tile_exists", first_tile != null)
	if first_tile != null:
		_click(_center(first_tile))
		await process_frame
		_check("shelf_tap_sells", S.sales_count > 0, "sales=%d" % S.sales_count)

	# ---- drive day to RESULTS ----------------------------------------------
	for i in range(40):
		main._handle_events(S.tick_sell(50.0))
		if S.phase == ShopStateRef.Phase.RESULTS:
			break
	await process_frame
	_check("day_reaches_results", S.phase == ShopStateRef.Phase.RESULTS, "phase=%d" % S.phase)

	# ---- RESULTS: Next Day via real click ----------------------------------
	var day_before: int = S.day
	var next_btn: Button = _find_button("Next Day →")
	_check("next_day_button_exists", next_btn != null)
	if next_btn != null:
		_click(_center(next_btn))
		await process_frame
		_check("next_day_click_advances_state", S.day == day_before + 1 and S.phase == ShopStateRef.Phase.GATHER, "day=%d phase=%d" % [S.day, S.phase])
		# The view must follow the state into GATHER (regression: start_day
		# once mutated phase without emitting phase_changed -> dead screen).
		_check("next_day_rebuilds_gather_ui", main.tide_fill != null and main.node_boxes.size() > 0, "tide_fill=%s node_boxes=%d" % [str(main.tide_fill != null), main.node_boxes.size()])

	MetaSaveRef.clear()
	if fail_count == 0:
		print("UITEST OK")
		quit(0)
	else:
		print("UITEST FAIL: %d checks failed" % fail_count)
		quit(1)
