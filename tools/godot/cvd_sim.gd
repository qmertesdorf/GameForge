extends SceneTree

# Render colour-vision-deficiency simulations of a frame so the colour-accessibility
# auditor SEES the red-green collapse (and value-only collisions, via grayscale)
# instead of imagining it. The matrices MUST stay in sync with contrast.mjs
# CVD_MATRIX (Machado et al. 2009, severity 1.0) — the JS mirror is unit-tested;
# this is the visible-image half that needs a PNG out, so it lives in GDScript.
#   godot --headless --path tools/godot/ --script res://cvd_sim.gd -- <frame.png> <outdir>
# Writes <outdir>/cvd_grayscale.png, cvd_deuteranopia.png, cvd_protanopia.png.
# Prints CVD_SIM OK.

const DEUT := [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]
const PROT := [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("cvd_sim: usage -- <frame.png> <outdir>")
		quit(1); return
	var src := Image.load_from_file(args[0])
	if src == null:
		push_error("cvd_sim: failed to load %s" % args[0])
		quit(1); return
	if src.get_format() != Image.FORMAT_RGBA8:
		src.convert(Image.FORMAT_RGBA8)
	var outdir := args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	_apply(src, "grayscale").save_png(outdir.path_join("cvd_grayscale.png"))
	_apply(src, "deuteranopia").save_png(outdir.path_join("cvd_deuteranopia.png"))
	_apply(src, "protanopia").save_png(outdir.path_join("cvd_protanopia.png"))
	print("CVD_SIM OK")
	quit(0)

func _apply(src: Image, type: String) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c := src.get_pixel(x, y)
			var r := c.r * 255.0
			var g := c.g * 255.0
			var b := c.b * 255.0
			var nr: float
			var ng: float
			var nb: float
			if type == "grayscale":
				var yv := 0.2126 * r + 0.7152 * g + 0.0722 * b
				nr = yv; ng = yv; nb = yv
			else:
				var m: Array = DEUT if type == "deuteranopia" else PROT
				nr = m[0][0] * r + m[0][1] * g + m[0][2] * b
				ng = m[1][0] * r + m[1][1] * g + m[1][2] * b
				nb = m[2][0] * r + m[2][1] * g + m[2][2] * b
			out.set_pixel(x, y, Color(clampf(nr, 0.0, 255.0) / 255.0, clampf(ng, 0.0, 255.0) / 255.0, clampf(nb, 0.0, 255.0) / 255.0, c.a))
	return out
