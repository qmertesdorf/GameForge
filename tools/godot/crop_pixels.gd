extends SceneTree

# Decode a crop PNG → emit its pixels as packed 0xRRGGBB ints for the pure-JS
# bimodal contrast measurer (contrast.mjs measureCrop). Thin: decode only, no
# scoring — same pure-JS-seam + thin-Godot-pixel-op split as the icon ops.
#   godot --headless --path tools/godot/ --script res://crop_pixels.gd -- <crop.png>
# Prints one line: CROP_PIXELS {"w":W,"h":H,"rgb":[...packed 0xRRGGBB...]}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("crop_pixels: usage -- <crop.png>")
		quit(1); return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("crop_pixels: failed to load %s" % args[0])
		quit(1); return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var rgb := PackedInt32Array()
	rgb.resize(w * h)
	for y in range(h):
		for x in range(w):
			var c := img.get_pixel(x, y)
			var r := int(round(c.r * 255.0))
			var g := int(round(c.g * 255.0))
			var b := int(round(c.b * 255.0))
			rgb[y * w + x] = (r << 16) | (g << 8) | b
	print("CROP_PIXELS %s" % JSON.stringify({"w": w, "h": h, "rgb": rgb}))
	quit(0)
