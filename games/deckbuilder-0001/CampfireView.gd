extends Node2D

# CampfireView — rest site with two choices.
# Contract:
#   refresh(run_hp: int, run_max_hp: int) -> void
#   get_rest_rect() -> Rect2
#   get_upgrade_rect() -> Rect2
# Draw: a campfire-scene header, current HP (e.g. "HP 40/70"), and two big buttons:
# "Rest (heal 30%)" and "Upgrade a Card". Reuse the EventView/ShopView palette + ui_font.

const Chrome := preload("res://Chrome.gd")

# Viewport
const W: float = 1280.0
const H: float = 720.0

# Palette (mirrors EventView / ShopView / CombatView)
const COL_BG_TOP     := Color(0.102, 0.063, 0.188)  # #1a1030 indigo
const COL_BG_BOT     := Color(0.176, 0.106, 0.306)  # #2d1b4e violet
const COL_WHITE      := Color(1, 1, 1)
const COL_PANEL      := Color(0.08, 0.06, 0.14, 0.88)
const COL_BTN        := Color(0.65, 0.25, 0.90)
const COL_BTN_BORDER := Color(0.85, 0.65, 1.00, 0.85)
const COL_AMBER      := Color(0.98, 0.72, 0.20)
const COL_HP_BAR     := Color(0.22, 0.70, 0.32)

# Layout
const HEADER_H: float = 48.0
const PANEL_X: float  = 240.0
const PANEL_W: float  = W - PANEL_X * 2.0   # 800 px centred
const TITLE_Y: float  = 90.0
const INFO_Y: float   = 180.0
const BTN_Y1: float   = 310.0
const BTN_Y2: float   = 430.0
const BTN_H: float    = 80.0

var _hp: int  = 0
var _max: int = 0
var _font: Font = null
var _tex_bg: Texture2D = null
var _tex_fire: Texture2D = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists("res://art/ui_font.ttf"):
		_font = load("res://art/ui_font.ttf")
	_tex_bg = _try_load("res://art/bg_campfire.png")
	_tex_fire = _try_load("res://art/prop_campfire.png")


func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func refresh(run_hp: int, run_max_hp: int) -> void:
	_hp  = run_hp
	_max = run_max_hp
	queue_redraw()


# ─── Public hit-test API ──────────────────────────────────────────────────────

func get_rest_rect() -> Rect2:
	return Rect2(PANEL_X, BTN_Y1, PANEL_W, BTN_H)


func get_upgrade_rect() -> Rect2:
	return Rect2(PANEL_X, BTN_Y2, PANEL_W, BTN_H)


# ─── _draw ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_background()
	_draw_header()
	_draw_campfire_art()
	_draw_hp_info()
	_draw_button(get_rest_rect(),    "Rest  (heal 30%)")
	_draw_button(get_upgrade_rect(), "Upgrade a Card")


func _draw_background() -> void:
	# Painted opaque background when present; gradient bands as a fallback.
	if _tex_bg != null:
		draw_texture_rect(_tex_bg, Rect2(0.0, 0.0, W, H), false)
		return
	var bands: int = 16
	for i in bands:
		var t0: float = float(i) / float(bands)
		var t1: float = float(i + 1) / float(bands)
		var c: Color = COL_BG_TOP.lerp(COL_BG_BOT, (t0 + t1) * 0.5)
		draw_rect(Rect2(0.0, t0 * H, W, (t1 - t0) * H), c)


func _draw_header() -> void:
	draw_rect(Rect2(0.0, 0.0, W, HEADER_H), Color(0.05, 0.04, 0.11, 0.88))
	draw_rect(Rect2(0.0, HEADER_H - 2.0, W, 2.0), Color(0.78, 0.58, 1.00, 0.75))
	_draw_text(Vector2(W * 0.5, 30.0), "Campfire", 22, COL_AMBER, true)


func _draw_campfire_art() -> void:
	var cx: float = W * 0.5
	# Painted bonfire prop centred above the HP panel. The PNG carries its own
	# transparent background + glow, so it draws straight over the scene.
	if _tex_fire != null:
		var fire_h: float = 200.0
		var aspect: float = float(_tex_fire.get_width()) / float(max(_tex_fire.get_height(), 1))
		var fire_w: float = fire_h * aspect
		draw_texture_rect(_tex_fire,
			Rect2(cx - fire_w * 0.5, 230.0 - fire_h * 0.5, fire_w, fire_h), false)
		return

	# ── Fallback: stylised procedural campfire (logs + flames + embers) ──
	var base_y: float = 258.0

	# Log pair
	draw_line(Vector2(cx - 52.0, base_y + 14.0), Vector2(cx + 12.0, base_y - 6.0),
		Color(0.38, 0.20, 0.08), 10.0)
	draw_line(Vector2(cx + 52.0, base_y + 14.0), Vector2(cx - 12.0, base_y - 6.0),
		Color(0.38, 0.20, 0.08), 10.0)

	# Ember glow (wide, soft circle)
	draw_circle(Vector2(cx, base_y + 6.0), 32.0, Color(0.95, 0.42, 0.05, 0.35))
	draw_circle(Vector2(cx, base_y + 2.0), 18.0, Color(1.00, 0.60, 0.10, 0.55))

	# Flame layers (bottom-to-top, narrowing)
	var flame_layers: Array = [
		[Color(0.95, 0.30, 0.04, 0.80), 24.0, 48.0],
		[Color(0.98, 0.58, 0.04, 0.85), 16.0, 34.0],
		[Color(1.00, 0.82, 0.20, 0.90), 10.0, 22.0],
		[Color(1.00, 0.96, 0.70, 0.95),  5.0, 10.0],
	]
	for layer in flame_layers:
		var col: Color  = layer[0]
		var radius: float = layer[1]
		var rise: float   = layer[2]
		draw_circle(Vector2(cx, base_y - rise), radius, col)

	# Flying sparks
	var sparks: Array = [
		[cx - 18.0, base_y - 62.0],
		[cx + 22.0, base_y - 70.0],
		[cx - 6.0,  base_y - 80.0],
		[cx + 8.0,  base_y - 55.0],
	]
	for s in sparks:
		draw_circle(Vector2(s[0], s[1]), 2.5, Color(1.00, 0.82, 0.20, 0.75))


func _draw_hp_info() -> void:
	# HP display panel
	var panel_rect := Rect2(PANEL_X, INFO_Y, PANEL_W, 50.0)
	draw_rect(panel_rect, COL_PANEL)
	draw_rect(panel_rect, Color(0.50, 0.40, 0.70, 0.45), false, 1.5)

	# Styled HP gauge (matches combat) instead of a flat fill.
	var bar_x: float = PANEL_X + 16.0
	var bar_y: float = INFO_Y + 28.0
	var bar_w: float = PANEL_W - 32.0
	var bar_h: float = 14.0
	var frac: float = float(_hp) / float(max(_max, 1))
	Chrome.bar(self, Rect2(bar_x, bar_y, bar_w, bar_h), frac, COL_HP_BAR)

	# HP text
	var hp_text: String = "HP  %d / %d" % [_hp, _max]
	_draw_text(Vector2(W * 0.5, INFO_Y + 18.0), hp_text, 18, Color(0.92, 0.88, 0.95), true)


func _draw_button(rect: Rect2, label: String) -> void:
	var font: Font = _font if _font != null else ThemeDB.fallback_font
	Chrome.button(self, font, rect, label, COL_BTN, 22)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _draw_text(pos: Vector2, text: String, size: int, col: Color,
		centered: bool = false, right_align: bool = false) -> void:
	var font: Font = _font if _font != null else ThemeDB.fallback_font
	if font == null:
		return
	var off := Vector2(0.0, 0.0)
	if centered:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		off.x = -tw * 0.5
	elif right_align:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		off.x = -tw
	# Shadow + fill (mirrors EventView._draw_text convention)
	draw_string(font, pos + off + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, size, Color(0, 0, 0, 0.85))
	draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
