extends SceneTree

# Emit an aligned thumbnail grid for the pure-JS legibility scorer
# (package.mjs scoreIconLegibility). Loads the composed Play icon + the transparent
# focal, downscales the composite to N², and builds an N² subject MASK by contain-
# fitting the focal's alpha into the SAME COMPOSITE_SAFE box icon_compose uses — so
# the mask lands exactly where the subject sits in the composite. Prints one line:
#   ICON_LEGIBILITY_GRID {"n":48,"rgb":[...packed 0xRRGGBB...],"alpha":[...0..255...]}
# Scoring + the WARN/OK verdict live in JS (the testable seam, like the rest of the
# pure package.mjs functions); this script only decodes pixels — there is no Godot
# unit test for it, same as icon_compose.gd / atlas_render.gd.
#   godot --headless --path tools/godot/ --script res://icon_legibility.gd -- <composite.png> <focal.png>
#
# Why a SILHOUETTE mask and not centre-vs-corner (the metric this replaces): the old
# gate compared the icon's centre box to its corners, so a dark-cored subject on a
# bright same-hue plate scored "high contrast" even while its rim melted into the
# plate. The mask lets JS measure the subject's OUTLINE against the plate right
# behind it — the contrast that actually decides whether it reads at thumbnail size.

const N := 48
const COMPOSITE_SAFE := 0.80   # MUST match icon_compose.gd's launcher/Play focal placement

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("icon_legibility: usage -- <composite.png> <focal.png>")
		quit(1); return
	var comp := Image.load_from_file(args[0])
	if comp == null:
		push_error("icon_legibility: failed to load composite %s" % args[0])
		quit(1); return
	var focal := Image.load_from_file(args[1])
	if focal == null:
		push_error("icon_legibility: failed to load focal %s" % args[1])
		quit(1); return
	if comp.get_format() != Image.FORMAT_RGBA8:
		comp.convert(Image.FORMAT_RGBA8)
	if focal.get_format() != Image.FORMAT_RGBA8:
		focal.convert(Image.FORMAT_RGBA8)
	comp.resize(N, N, Image.INTERPOLATE_LANCZOS)

	# Subject mask: contain-fit the focal into COMPOSITE_SAFE of N², centered —
	# identical geometry to icon_compose._blend_focal — copied with alpha intact.
	var box := int(N * COMPOSITE_SAFE)
	var fw := focal.get_width()
	var fh := focal.get_height()
	var scale := float(box) / float(max(fw, fh))
	var tw: int = max(1, int(round(fw * scale)))
	var th: int = max(1, int(round(fh * scale)))
	var scaled := focal.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	var mask := Image.create(N, N, false, Image.FORMAT_RGBA8)  # fully transparent
	var ox := int((N - tw) / 2.0)
	var oy := int((N - th) / 2.0)
	mask.blit_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))

	var rgb := PackedInt32Array()
	var alpha := PackedInt32Array()
	rgb.resize(N * N)
	alpha.resize(N * N)
	for y in range(N):
		for x in range(N):
			var c := comp.get_pixel(x, y)
			var r := int(round(c.r * 255.0))
			var g := int(round(c.g * 255.0))
			var b := int(round(c.b * 255.0))
			rgb[y * N + x] = (r << 16) | (g << 8) | b
			alpha[y * N + x] = int(round(mask.get_pixel(x, y).a * 255.0))
	print("ICON_LEGIBILITY_GRID %s" % JSON.stringify({"n": N, "rgb": rgb, "alpha": alpha}))
	quit(0)
