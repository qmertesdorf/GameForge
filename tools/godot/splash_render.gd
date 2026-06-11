extends SceneTree

# Composite a master PNG onto a solid background as a centered boot-splash image.
# Run: godot --headless --path tools/godot/ --script res://splash_render.gd -- <master.png> <out.png> <WxH> <#RRGGBBAA>
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("splash_render: usage: -- <master.png> <out.png> <WxH> <#RRGGBBAA>")
		quit(1)
		return
	var master_path := args[0]
	var out_path := args[1]
	var dims := args[2].split("x", false)
	if dims.size() != 2:
		push_error("splash_render: bad size '%s' (expected WxH)" % args[2])
		quit(1)
		return
	var w := int(dims[0])
	var h := int(dims[1])
	var bg := Color.html(args[3])

	var master := Image.load_from_file(master_path)
	if master == null:
		push_error("splash_render: failed to load master %s" % master_path)
		quit(1)
		return
	if master.get_format() != Image.FORMAT_RGBA8:
		master.convert(Image.FORMAT_RGBA8)

	# Scale the master to fit ~60% of the smaller canvas axis, preserving aspect.
	var box := int(min(w, h) * 0.6)
	var mw := master.get_width()
	var mh := master.get_height()
	var scale := float(box) / float(max(mw, mh))
	var tw: int = max(1, int(round(mw * scale)))
	var th: int = max(1, int(round(mh * scale)))
	var scaled := master.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)

	var canvas := Image.create(w, h, false, Image.FORMAT_RGBA8)
	canvas.fill(bg)
	var ox := int((w - tw) / 2.0)
	var oy := int((h - th) / 2.0)
	canvas.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))

	var serr := canvas.save_png(out_path)
	if serr != OK:
		push_error("splash_render: failed to save %s (err %d)" % [out_path, serr])
		quit(1)
		return
	print("splash_render: wrote %s (%dx%d)" % [out_path, w, h])
	print("SPLASH_RENDER OK")
	quit(0)
