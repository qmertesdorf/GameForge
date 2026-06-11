extends SceneTree

# TEMPLATE — copy to games/<id>/_shots.gd and fill the moments. Captures store-
# listing frames on the REAL renderer (NOT --headless). package.mjs passes the
# screenshots outdir as the first user arg.
#   godot --path games/<id>/ --script res://_shots.gd -- <outdir>
const PHASE := preload("res://ShopState.gd")  # EDIT: the game's state script, if any

func _initialize() -> void:
	var outdir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "store/screenshots"
	# Persistence games: clear the save so we boot a fresh run, not an inherited day.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))

	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(180)

	# 1) the boot moment
	await _shot("%s/one.png" % outdir)

	# 2..N) drive the view's state to each showcase moment, like selftest, then rebuild.
	#   var s = main.S
	#   s.phase = PHASE.Phase.SELL
	#   s.shelves = [...] ; s.patrons = [...]
	#   main._rebuild_ui()
	#   await _wait(90)
	#   await _shot("%s/two.png" % outdir)

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
