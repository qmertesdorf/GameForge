extends SceneTree

# Store-listing capture harness for Tide & Tally (the packager `--script` runner
# runs this on the REAL renderer). Drives the view's ShopState the same way
# selftest Stage 6 does, capturing three signature moments.
# Copied from tools/godot/shots.template.gd; committed like selftest.gd/uitest.gd.
#   godot --path games/shopkeep-0001/ --script res://_shots.gd -- <outdir>
const ShopState := preload("res://ShopState.gd")

func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var outdir := uargs[0] if uargs.size() > 0 else "store/screenshots"
	# Day-1 boot: clear any persisted save so we don't inherit a later day.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))

	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(180)

	# 1) GATHER — boot state: combing the tide pools.
	await _shot("%s/gather.png" % outdir)

	# 2) CRAFT — the workbench: materials + recipes + demand.
	var s = main.S
	s.phase = ShopState.Phase.CRAFT
	s.day = 3
	s.gold = 240
	s.resources = {"shell": 7, "driftwood": 5, "seaglass": 4, "pearl": 2}
	s.demand = ["wind_chime", "pearl_ring"]
	s.stock = ["shell_charm"]
	main._rebuild_ui()
	await _wait(90)
	await _shot("%s/craft.png" % outdir)

	# 3) SELL — shop's open: full shelves + a patron queue.
	s.phase = ShopState.Phase.SELL
	s.shelves = ["shell_charm", "seaglass_pendant", "wind_chime", "pearl_ring"]
	s.patrons = [
		{"want": "pearl_ring", "patience": 9.0, "max_patience": 12.0},
		{"want": "shell_charm", "patience": 6.0, "max_patience": 12.0},
		{"want": "wind_chime", "patience": 11.0, "max_patience": 12.0},
	]
	s.patrons_to_come = 2
	main._rebuild_ui()
	await _wait(90)
	await _shot("%s/sell.png" % outdir)

	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	print("SHOTS OK")
	quit(0)

func _wait(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _shot(path: String) -> void:
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("shots: save failed %s (err %d)" % [path, err]); quit(1); return
	print("wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
