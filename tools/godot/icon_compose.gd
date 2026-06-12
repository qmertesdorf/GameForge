extends SceneTree

# Compose Android icon layers from a transparent focal PNG + a themed 2-stop
# background. Run (headless):
#   godot --headless --path tools/godot/ --script res://icon_compose.gd -- \
#       <focal.png> <outdir> <name:px:kind,...> <#topRRGGBB> <#botRRGGBB> [bg_style]
# kind ∈ { adaptive_fg | adaptive_bg | launcher | play }.
# bg_style ∈ { radial (default) | linear }. radial = a bright glow behind the
#   subject (top colour at centre → bottom colour at the edge) + a soft drop
#   shadow under the focal on the composite (legacy/Play) icons — the premium
#   app-store look. linear = the flat top→bottom 2-stop gradient.
const FG_SAFE := 0.66      # adaptive foreground: subject within Android's safe zone
const COMPOSITE_SAFE := 0.80  # legacy/Play: focal can fill more (not masked)
const SHADOW_ALPHA := 0.20    # drop-shadow opacity (soft, not heavy)
const SHADOW_DROP := 0.02     # drop-shadow vertical offset, as a fraction of px
const SHADOW_BLUR := 10       # down/up resize divisor; higher = softer, more diffuse

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("icon_compose: usage -- <focal.png> <outdir> <name:px:kind,...> <#top> <#bot> [bg_style]")
		quit(1); return
	var focal_path := args[0]
	var outdir := args[1]
	var specs := args[2].split(",", false)
	var top := Color.html(args[3])
	var bot := Color.html(args[4])
	var style := args[5] if args.size() > 5 else "radial"

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
			canvas = _bg(px, top, bot, style)
		elif kind == "adaptive_fg":
			canvas = Image.create(px, px, false, Image.FORMAT_RGBA8) # transparent; OS adds elevation
			_blend_focal(canvas, focal, px, FG_SAFE)
		elif kind == "launcher" or kind == "play":
			canvas = _bg(px, top, bot, style)
			if style == "radial":
				_drop_shadow(canvas, focal, px, COMPOSITE_SAFE)
			_blend_focal(canvas, focal, px, COMPOSITE_SAFE)
		else:
			push_error("icon_compose: unknown kind '%s'" % kind)
			quit(1); return
		var dest := outdir.path_join(icon_name + ".png")
		var serr := canvas.save_png(dest)
		if serr != OK:
			push_error("icon_compose: save failed %s (err %d)" % [dest, serr])
			quit(1); return
		print("icon_compose: wrote %s (%dx%d, %s, %s)" % [dest, px, px, kind, style])

	print("ICON_COMPOSE OK")
	quit(0)

# Dispatch the background fill by style.
func _bg(px: int, top: Color, bot: Color, style: String) -> Image:
	if style == "linear":
		return _linear(px, top, bot)
	return _radial(px, top, bot)

# Vertical 2-stop linear gradient, top→bot, square px×px (opaque).
func _linear(px: int, top: Color, bot: Color) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in range(px):
		var t := float(y) / float(max(1, px - 1))
		var col := top.lerp(bot, t)
		for x in range(px):
			img.set_pixel(x, y, col)
	return img

# Radial glow: `center` colour at the middle → `edge` colour by the rim, square
# px×px (opaque). maxr is just under the half-diagonal so the corners reach the
# edge colour (a soft vignette behind the subject).
func _radial(px: int, center: Color, edge: Color) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := float(px - 1) / 2.0
	var maxr := float(px) * 0.72
	for y in range(px):
		for x in range(px):
			var d := Vector2(float(x) - c, float(y) - c).length() / maxr
			img.set_pixel(x, y, center.lerp(edge, clampf(d, 0.0, 1.0)))
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

# Soft contact shadow under the focal: the focal silhouette in translucent black,
# blurred (down/up bilinear resize), offset down, blended below the focal.
func _drop_shadow(canvas: Image, focal: Image, px: int, ratio: float) -> void:
	var box := int(px * ratio)
	var fw := focal.get_width()
	var fh := focal.get_height()
	var scale := float(box) / float(max(fw, fh))
	var tw: int = max(1, int(round(fw * scale)))
	var th: int = max(1, int(round(fh * scale)))
	var sh := focal.duplicate() as Image
	sh.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	for y in range(th):
		for x in range(tw):
			var a := sh.get_pixel(x, y).a
			sh.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * SHADOW_ALPHA))
	# blur: shrink then grow with bilinear interpolation
	var bw: int = max(1, int(tw / float(SHADOW_BLUR)))
	var bh: int = max(1, int(th / float(SHADOW_BLUR)))
	sh.resize(bw, bh, Image.INTERPOLATE_BILINEAR)
	sh.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	var ox := int((px - tw) / 2.0)
	var oy := int((px - th) / 2.0) + int(px * SHADOW_DROP)
	canvas.blend_rect(sh, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
