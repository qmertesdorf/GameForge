extends SceneTree

# Judge whether a composed launcher/Play icon still reads at thumbnail size
# (~48 px) — ASO rules 6 & 9 ("if it doesn't communicate at ~48 px it's too
# complicated"). Loads the opaque composite icon, downscales to 48², and measures
# the perceptual colour distance (CIELAB ΔE76) between the centred subject region
# and the corner (background) regions. Our icons are always a centred subject on a
# plate, so a low centre-vs-corner ΔE means the subject no longer separates from
# the plate at thumbnail size (mush). ΔE (not plain luminance) is deliberate: a
# complementary pairing like coral-on-teal reads as high contrast yet has nearly
# equal luminance — only a chromatic metric scores it correctly. Advisory — prints
# a WARN, never fails the build.
#   godot --headless --path tools/godot/ --script res://icon_legibility.gd -- <icon.png>
# Prints "ICON_LEGIBILITY {json}" then "LEGIBILITY OK" or "LEGIBILITY WARN: ...".

const N := 48
const DELTAE_MIN := 22.0   # subject-vs-plate CIELAB ΔE76 floor at 48 px (noticeably distinct)

# sRGB (0..1) channel -> linear.
func _lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

# Mean sRGB Color -> CIELAB (D65).
func _lab(c: Color) -> Vector3:
	var r := _lin(c.r)
	var g := _lin(c.g)
	var b := _lin(c.b)
	var x := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var y := (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.0
	var z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var fx := _f(x)
	var fy := _f(y)
	var fz := _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))

func _f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0

func _mean(img: Image, x0: int, y0: int, x1: int, y1: int) -> Color:
	var rs := 0.0
	var gs := 0.0
	var bs := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			rs += c.r; gs += c.g; bs += c.b; n += 1
	n = max(1, n)
	return Color(rs / n, gs / n, bs / n, 1.0)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("icon_legibility: usage -- <icon.png>")
		quit(1); return
	var img := Image.load_from_file(args[0])
	if img == null:
		push_error("icon_legibility: failed to load %s" % args[0])
		quit(1); return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.resize(N, N, Image.INTERPOLATE_LANCZOS)

	# centre region = central 40% box (where the subject sits)
	var c0: int = int(N * 0.30)
	var c1: int = int(N * 0.70)
	var center := _mean(img, c0, c0, c1, c1)
	# background = the four corner boxes (15% each), averaged
	var k: int = int(N * 0.15)
	var cr := 0.0
	var cg := 0.0
	var cb := 0.0
	for cy in [0, N - k]:
		for cx in [0, N - k]:
			var m := _mean(img, cx, cy, cx + k, cy + k)
			cr += m.r; cg += m.g; cb += m.b
	var corner := Color(cr / 4.0, cg / 4.0, cb / 4.0, 1.0)

	var lab_c := _lab(center)
	var lab_k := _lab(corner)
	var de := (lab_c - lab_k).length()
	var json := '{"px":%d,"delta_e":%.1f,"delta_e_min":%.1f,"center_L":%.1f,"corner_L":%.1f}' % [N, de, DELTAE_MIN, lab_c.x, lab_k.x]
	print("ICON_LEGIBILITY %s" % json)
	if de < DELTAE_MIN:
		print("LEGIBILITY WARN: subject barely separates from the plate at %dpx (ΔE %.1f < %.1f) — make the subject larger or its colour contrast the background more" % [N, de, DELTAE_MIN])
	else:
		print("LEGIBILITY OK")
	quit(0)
