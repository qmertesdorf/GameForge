extends SceneTree

# Compose Android icon layers from a transparent focal PNG + a 2-stop vertical
# gradient background. Run (headless):
#   godot --headless --path tools/godot/ --script res://icon_compose.gd -- \
#       <focal.png> <outdir> <name:px:kind,...> <#topRRGGBB> <#botRRGGBB>
# kind ∈ { adaptive_fg | adaptive_bg | launcher | play }.
const FG_SAFE := 0.66      # adaptive foreground: subject within Android's safe zone
const COMPOSITE_SAFE := 0.80  # legacy/Play: focal can fill more (not masked)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("icon_compose: usage -- <focal.png> <outdir> <name:px:kind,...> <#top> <#bot>")
		quit(1); return
	var focal_path := args[0]
	var outdir := args[1]
	var specs := args[2].split(",", false)
	var top := Color.html(args[3])
	var bot := Color.html(args[4])

	var focal := Image.load_from_file(focal_path)
	if focal == null:
		push_error("icon_compose: failed to load focal %s" % focal_path)
		quit(1); return
	if focal.get_format() != Image.FORMAT_RGBA8:
		focal.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(outdir)

	for spec in specs:
		var parts := spec.split(":")
		if parts.size() != 3:
			push_error("icon_compose: bad spec '%s' (name:px:kind)" % spec)
			quit(1); return
		var icon_name := parts[0]
		var px := int(parts[1])
		var kind := parts[2]
		var canvas: Image
		if kind == "adaptive_bg":
			canvas = _gradient(px, top, bot)
		elif kind == "adaptive_fg":
			canvas = Image.create(px, px, false, Image.FORMAT_RGBA8) # transparent
			_blend_focal(canvas, focal, px, FG_SAFE)
		elif kind == "launcher" or kind == "play":
			canvas = _gradient(px, top, bot)
			_blend_focal(canvas, focal, px, COMPOSITE_SAFE)
		else:
			push_error("icon_compose: unknown kind '%s'" % kind)
			quit(1); return
		var dest := outdir.path_join(icon_name + ".png")
		var serr := canvas.save_png(dest)
		if serr != OK:
			push_error("icon_compose: save failed %s (err %d)" % [dest, serr])
			quit(1); return
		print("icon_compose: wrote %s (%dx%d, %s)" % [dest, px, px, kind])

	print("ICON_COMPOSE OK")
	quit(0)

# Vertical 2-stop linear gradient, top→bot, square px×px (opaque).
func _gradient(px: int, top: Color, bot: Color) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in range(px):
		var t := float(y) / float(max(1, px - 1))
		var col := top.lerp(bot, t)
		for x in range(px):
			img.set_pixel(x, y, col)
	return img

# Contain-fit the focal into `ratio` of the canvas, centered, alpha-composited.
func _blend_focal(canvas: Image, focal: Image, px: int, ratio: float) -> void:
	var box := int(px * ratio)
	var fw := focal.get_width()
	var fh := focal.get_height()
	var scale := float(box) / float(max(fw, fh))
	var tw: int = max(1, int(round(fw * scale)))
	var th: int = max(1, int(round(fh * scale)))
	var scaled := focal.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	var ox := int((px - tw) / 2.0)
	var oy := int((px - th) / 2.0)
	canvas.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
