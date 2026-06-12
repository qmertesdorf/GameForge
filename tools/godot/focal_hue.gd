extends SceneTree

# Print the dominant opaque hue of a transparent icon focal, as "#rrggbb", so the
# packager can pick an icon background that CONTRASTS the subject (ASO rule 3 —
# the subject must pop off its plate). Averages the RGB of sufficiently-opaque
# pixels (alpha >= 0.5), strided for speed. Run (headless):
#   godot --headless --path tools/godot/ --script res://focal_hue.gd -- <focal.png>
# Prints "FOCAL_HUE #rrggbb" (or "FOCAL_HUE none" if the focal is fully transparent).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("focal_hue: usage -- <focal.png>")
		quit(1); return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("focal_hue: failed to load %s" % args[0])
		quit(1); return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var step: int = max(1, int(max(w, h) / 256))   # cap the sample grid ~256² for speed
	var rsum := 0.0
	var gsum := 0.0
	var bsum := 0.0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a >= 0.5:
				rsum += c.r; gsum += c.g; bsum += c.b; n += 1
	if n == 0:
		print("FOCAL_HUE none")
		quit(0); return
	var r := int(round(rsum / n * 255.0))
	var g := int(round(gsum / n * 255.0))
	var b := int(round(bsum / n * 255.0))
	print("FOCAL_HUE #%02x%02x%02x" % [r, g, b])
	quit(0)
