extends Node2D
# Fathom — view + input + spatial layer. Owns positions/collision/rendering and
# all juice; defers every economy rule to DiveState (the rules/rendering seam).
# Layered scene: scrolling depth-gradient background + parallax plankton (back),
# treasures/hazards/diver (play), air bar + counters + buttons (HUD).
#
# deepen v2: depth is a DESTINATION. The world is split into ZONES (Shallows/Reef/
# Trench); the deep is dark (Lantern reveals treasure), past your safe depth the
# pressure CRUSH burns air, and the per-dive COMMISSION can only be filled in a
# target zone — so you descend to reach a place, not to multiply a number.

const DiveStateC := preload("res://DiveState.gd")
const MetaSaveRef := preload("res://MetaSave.gd")

const W: float = 720.0
const H: float = 1280.0
const DIVER_Y: float = 520.0          # fixed screen-y of the diver; the world scrolls past
const PX_PER_DEPTH: float = 3.0       # 1 depth unit = 3 px
const SPAWN_AHEAD: float = 150.0      # depth units below the diver where objects appear
const DESPAWN_BEHIND: float = 90.0    # depth units above the diver before recycling
const PRESEED_FROM: float = 80.0      # first pre-seeded treasure depth (safe, collectible early)
const PRESEED_STEP: float = 52.0      # spacing of the pre-seeded column
const PRESEED_COUNT: int = 12         # seed a column from the Shallows down into the Trench
const COLLIDE_R: float = 48.0
const DIVER_R: float = 26.0
const TREASURE_SPACING: float = 62.0  # 1 treasure per this much descent
const HAZARD_FREE_DEPTH: float = 70.0 # no hazards in the calm first stretch (fairness)

# zone tints (background) and treasure colors
const ZONE_TREASURE_COL: Array = [
	Color(1.0, 0.92, 0.55),   # shallows: pale gold
	Color(0.55, 0.95, 1.0),   # reef: cyan pearl
	Color(0.95, 0.70, 1.0),   # trench: violet relic
]

# Claude-authored raster art (asset pass). Null-guarded everywhere: if a texture
# is missing the primitive draw still runs, so the game never hard-fails headless.
var tex_bg: Texture2D
var tex_diver: Texture2D
var tex_jelly: Texture2D
var tex_eel: Texture2D

var state: DiveState
var diver_x: float = W * 0.5
var target_x: float = W * 0.5
# objects: { x, d, kind:"treasure"|"hazard", zone:int, alive:bool, vx:float(homing hazards) }
var objects: Array = []
var plankton: Array = []               # { x:float, d:float }
var _last_treasure_d: float = 0.0
var _last_hazard_d: float = 0.0

# juice
var shake: float = 0.0
var flash: float = 0.0
var flash_col: Color = Color(1, 1, 1)
var haul_pulse: float = 0.0
var bank_pulse: float = 0.0
var commission_flash: float = 0.0
var bubbles: Array = []                # { x:float, y:float, r:float, life:float }
var _bubble_t: float = 0.0
# last-dive outcome (for the surface screen)
var _last_outcome: String = ""         # "" | "banked" | "forfeit"
var _last_commission_filled: bool = false
var _last_bonus: int = 0

@onready var ascend_button: Button = $UI/AscendButton
@onready var dive_again_button: Button = $UI/DiveAgainButton
@onready var ui_layer: CanvasLayer = $UI

# upgrade-screen buttons, built in code: key -> Button
var upgrade_buttons: Dictionary = {}
const UPGRADE_ORDER: Array = ["rig", "tank", "lamp", "fins"]
# per-gear accent for the shop-row dot icon (scannable identity, code-generated)
const UPGRADE_ICON_COL: Dictionary = {
	"rig": Color(1.0, 0.55, 0.25),
	"tank": Color(0.30, 0.85, 1.0),
	"lamp": Color(1.0, 0.85, 0.45),
	"fins": Color(0.55, 0.95, 0.60),
}

func _ready() -> void:
	state = DiveStateC.new()
	state.seed_rng(20240620)
	_load_meta()
	_seed_plankton()
	_load_art()
	ascend_button.pressed.connect(_on_ascend_pressed)
	dive_again_button.pressed.connect(_on_dive_again_pressed)
	ascend_button.add_theme_font_size_override("font_size", 26)
	dive_again_button.add_theme_font_size_override("font_size", 26)
	_style_button(ascend_button)
	_style_button(dive_again_button)
	# Seat DIVE AGAIN just below the upgrade list, inside the surface panel, so the
	# primary CTA reads as part of the shop card (not orphaned in the bottom gutter).
	dive_again_button.offset_left = 70.0
	dive_again_button.offset_top = 884.0
	dive_again_button.offset_right = W - 70.0
	dive_again_button.offset_bottom = 966.0
	_build_upgrade_buttons()
	_start_dive()

func _load_meta() -> void:
	var data: Dictionary = MetaSaveRef.read()
	if data.is_empty():
		return
	state.banked = int(data.get("banked", 0))
	state.dive_num = int(data.get("dive_num", 1))
	state.commission_zone = int(data.get("commission_zone", 1))
	state.commissions_done = int(data.get("commissions_done", 0))
	var up: Dictionary = data.get("upgrades", {})
	for k in UPGRADE_ORDER:
		state.upgrades[k] = int(up.get(k, 0))

func _save_meta() -> void:
	MetaSaveRef.write(state.banked, state.upgrades, state.dive_num, state.commission_zone, state.commissions_done)

func _build_upgrade_buttons() -> void:
	# The surface shop — one button per upgrade, shown only when a dive is over.
	var y: float = 470.0
	for key in UPGRADE_ORDER:
		var b := Button.new()
		b.offset_left = 52.0
		b.offset_top = y
		b.offset_right = W - 52.0
		b.offset_bottom = y + 80.0
		# 18px + clip_text: the longest label (Fins) can no longer run off the
		# right screen edge — it clips inside the (wider) button rect instead.
		b.add_theme_font_size_override("font_size", 18)
		b.clip_text = true
		_style_button(b)
		b.icon = _make_dot_icon(UPGRADE_ICON_COL[key])
		b.add_theme_constant_override("h_separation", 12)
		var nb: StyleBoxFlat = b.get_theme_stylebox("normal")
		nb.border_color = Color(1.0, 0.82, 0.4, 0.85)   # affordable rows = warm gold buy-affordance
		b.pressed.connect(_on_upgrade_pressed.bind(key))
		ui_layer.add_child(b)
		upgrade_buttons[key] = b
		y += 92.0

func _style_button(b: Button) -> void:
	# Themed bioluminescent chrome (dark teal glass + luminous cyan edge) so the
	# buttons belong to the painted trench world, not the flat default-Godot register.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.13, 0.17, 0.92)
	normal.set_corner_radius_all(10)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.30, 0.78, 0.86, 0.65)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.10, 0.21, 0.27, 0.95)
	hover.border_color = Color(0.45, 0.92, 1.0, 0.9)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.04, 0.09, 0.12, 0.95)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(0.05, 0.07, 0.09, 0.7)
	disabled.border_color = Color(0.30, 0.40, 0.44, 0.35)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.6, 0.66))

func _make_dot_icon(col: Color) -> ImageTexture:
	# a small soft-edged filled disc in the gear accent colour, for the shop rows
	var s: int = 30
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s * 0.5, s * 0.5)
	for yy in range(s):
		for xx in range(s):
			var d: float = Vector2(xx + 0.5, yy + 0.5).distance_to(c)
			var a: float = clamp(1.0 - (d - 8.0) / 5.0, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(xx, yy, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

func _seed_plankton() -> void:
	plankton.clear()
	for i in range(46):
		plankton.append({
			"x": state.rng.randf_range(0.0, W),
			"d": state.rng.randf_range(-200.0, 600.0),
		})

func _load_art() -> void:
	tex_bg = _try_load("res://art/background.png")
	tex_diver = _try_load("res://art/diver.png")
	tex_jelly = _try_load("res://art/hazard_jelly.png")
	tex_eel = _try_load("res://art/hazard_eel.png")

func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _start_dive() -> void:
	state.start_dive()
	_reset_dive_field()
	_refresh_buttons()

func _next_dive() -> void:
	state.start_next_dive()
	_reset_dive_field()
	_refresh_buttons()

func _reset_dive_field() -> void:
	objects.clear()
	bubbles.clear()
	diver_x = W * 0.5
	target_x = W * 0.5
	_last_treasure_d = 0.0
	_last_hazard_d = 0.0
	_preseed_treasures()

func _preseed_treasures() -> void:
	# Guarantee collectible treasure in safe water from the first second — without
	# this the nearest spawn is SPAWN_AHEAD below the diver, deep past the crush, and
	# the dive is unwinnable (the balance bot caught exactly this). Seed a column down
	# through the Shallows and into the Reef so there is always something to bank.
	var d: float = PRESEED_FROM
	for _i in range(PRESEED_COUNT):
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": d,
			"kind": "treasure",
			"zone": state.zone_for(d),
			"alive": true,
			"vx": 0.0,
		})
		d += PRESEED_STEP
	_last_treasure_d = d - SPAWN_AHEAD   # let rolling spawn continue below the seeded column

func _refresh_buttons() -> void:
	ascend_button.visible = state.active
	dive_again_button.visible = not state.active
	for key in UPGRADE_ORDER:
		var b: Button = upgrade_buttons[key]
		b.visible = not state.active
	if not state.active:
		_refresh_upgrade_labels()

func _refresh_upgrade_labels() -> void:
	for key in UPGRADE_ORDER:
		var b: Button = upgrade_buttons[key]
		var info: Dictionary = DiveStateC.UPGRADES[key]
		var lvl: int = state.upgrades[key]
		var cost: int = state.upgrade_cost(key)
		if cost < 0:
			b.text = "%s Lv%d • MAX" % [info["name"], lvl]
			b.disabled = true
		else:
			b.text = "%s Lv%d  (%s)  → %d" % [info["name"], lvl, info["blurb"], cost]
			b.disabled = not state.can_buy(key)

func _on_upgrade_pressed(key: String) -> void:
	var r: Dictionary = state.buy_upgrade(key)
	if r.get("bought", false):
		bank_pulse = 1.0
		_save_meta()
		_refresh_upgrade_labels()

# ---------------- input ----------------

func _on_ascend_pressed() -> void:
	state.set_ascending(true)

func _on_dive_again_pressed() -> void:
	_next_dive()

func _input(event: InputEvent) -> void:
	# Steer toward the touch/drag x, but only in the play area so the bottom
	# buttons own their own taps (their pressed signals do the rest).
	if event is InputEventScreenTouch and event.pressed:
		if event.position.y < 1080.0:
			target_x = event.position.x
	elif event is InputEventScreenDrag:
		if event.position.y < 1080.0:
			target_x = event.position.x
	elif event is InputEventMouseButton and event.pressed:
		if event.position.y < 1080.0:
			target_x = event.position.x
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.position.y < 1080.0:
			target_x = event.position.x

# ---------------- frame ----------------

func _process(delta: float) -> void:
	_decay_juice(delta)
	if state.active:
		# Fins sharpen steering — the felt, decision-relevant half of the upgrade:
		# maneuverability is what lets you out-dodge the Reef/Trench homing predators.
		var steer_rate: float = 10.0 + float(state._lvl("fins")) * 4.5
		var lx: float = lerp(diver_x, target_x, clamp(delta * steer_rate, 0.0, 1.0))
		diver_x = clamp(lx, 40.0, W - 40.0)
		_spawn(delta)
		_move_hazards(delta)
		_emit_bubbles(delta)
		var events: Array = state.tick(delta)
		_collide()
		_handle_events(events)
		_cull_objects()
	queue_redraw()

func _decay_juice(delta: float) -> void:
	shake = max(shake - delta * 60.0, 0.0)
	flash = max(flash - delta * 3.0, 0.0)
	haul_pulse = max(haul_pulse - delta * 4.0, 0.0)
	bank_pulse = max(bank_pulse - delta * 2.0, 0.0)
	commission_flash = max(commission_flash - delta * 1.5, 0.0)
	for b in bubbles:
		b.y -= delta * 70.0
		b.life -= delta
	var kept: Array = []
	for b in bubbles:
		if b.life > 0.0:
			kept.append(b)
	bubbles = kept

func _spawn(_delta: float) -> void:
	if not state.descending:
		return
	if state.depth - _last_treasure_d >= TREASURE_SPACING:
		_last_treasure_d = state.depth
		var d: float = state.depth + SPAWN_AHEAD
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": d,
			"kind": "treasure",
			"zone": state.zone_for(d),
			"alive": true,
			"vx": 0.0,
		})
	var hz_spacing: float = max(120.0 - float(state.dive_num) * 8.0, 64.0)
	if state.depth > HAZARD_FREE_DEPTH and state.depth - _last_hazard_d >= hz_spacing:
		_last_hazard_d = state.depth
		var hd: float = state.depth + SPAWN_AHEAD
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": hd,
			"kind": "hazard",
			"zone": state.zone_for(hd),
			"alive": true,
			"vx": 0.0,
		})

func _move_hazards(delta: float) -> void:
	# Zone-distinct behaviour: Shallows jellies just drift; Reef+ predators HOME on
	# the diver's column, so deeper water plays differently (you must out-steer them).
	for obj in objects:
		if obj.kind != "hazard" or not obj.alive:
			continue
		if obj.zone >= 1:
			var sy: float = _screen_y(obj.d)
			if sy > DIVER_Y - 200.0 and sy < H:
				var speed: float = 60.0 + float(obj.zone) * 50.0
				var dir: float = sign(diver_x - float(obj.x))
				var nx: float = clamp(float(obj.x) + dir * speed * delta, 40.0, W - 40.0)
				obj.x = nx

func _emit_bubbles(delta: float) -> void:
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		_bubble_t = 0.12
		bubbles.append({
			"x": diver_x + state.rng.randf_range(-10.0, 10.0),
			"y": DIVER_Y - 6.0,
			"r": state.rng.randf_range(2.0, 5.0),
			"life": state.rng.randf_range(0.6, 1.1),
		})

func _screen_y(d: float) -> float:
	return DIVER_Y + (d - state.depth) * PX_PER_DEPTH

func _collide() -> void:
	for obj in objects:
		if not obj.alive:
			continue
		var sy: float = _screen_y(obj.d)
		if abs(sy - DIVER_Y) <= COLLIDE_R and abs(obj.x - diver_x) <= COLLIDE_R:
			obj.alive = false
			if obj.kind == "treasure":
				var ev: Dictionary = state.collect(int(obj.zone))
				haul_pulse = 1.0
				if ev.get("qualifies", false):
					commission_flash = 1.0
			else:
				state.hit_hazard()
				shake = 9.0
				flash = 0.8
				flash_col = Color(1, 1, 1)

func _handle_events(events: Array) -> void:
	for e in events:
		var t: String = e.get("type", "")
		if t == "banked":
			bank_pulse = 1.0
			_last_outcome = "banked"
			_last_commission_filled = e.get("commission", false)
			_last_bonus = int(e.get("bonus", 0))
			if _last_commission_filled:
				commission_flash = 1.0
		elif t == "forfeit":
			shake = 12.0
			flash = 1.0
			flash_col = Color(0.9, 0.3, 0.4)
			_last_outcome = "forfeit"
			_last_commission_filled = false
			_refresh_buttons()
		elif t == "air_low":
			flash = 0.4
			flash_col = Color(1, 0.4, 0.4)
	# active may have flipped to false this tick (banked/forfeit) — persist + surface the shop
	if not state.active and ascend_button.visible:
		_save_meta()
		_refresh_buttons()

func _cull_objects() -> void:
	var kept: Array = []
	for obj in objects:
		var sy: float = _screen_y(obj.d)
		if obj.alive and sy > DIVER_Y - DESPAWN_BEHIND * PX_PER_DEPTH and sy < H + 80.0:
			kept.append(obj)
	objects = kept

# ---------------- draw ----------------

func _draw() -> void:
	var off: Vector2 = Vector2(0, 0)
	if shake > 0.0:
		off = Vector2(state.rng.randf_range(-shake, shake), state.rng.randf_range(-shake, shake))
	_draw_background(off)
	if state.active:
		_draw_plankton(off)
		_draw_safe_line(off)
		_draw_objects(off)
		_draw_diver(off)
		_draw_godrays()
		if state.is_crushing():
			_draw_crush_vignette()
		if flash > 0.0:
			draw_rect(Rect2(0, 0, W, H), Color(flash_col.r, flash_col.g, flash_col.b, clamp(flash * 0.5, 0.0, 0.6)))
	else:
		# Surfaced: darken the trench so the shop reads as a distinct screen — no
		# gameplay world, diver, or in-dive HUD bleeding under the overlay.
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.03, 0.06, 0.78))
	_draw_hud()

func _draw_background(off: Vector2) -> void:
	if tex_bg != null:
		# Painted trench backdrop (surface-lit top -> inky black bottom), then a
		# depth-driven darkening overlay so descending still visibly darkens the
		# water — preserving the gameplay depth-read the old strip gradient gave.
		draw_texture_rect(tex_bg, Rect2(off, Vector2(W, H)), false)
		var dk: float = clamp(state.depth / 620.0, 0.0, 1.0)
		draw_rect(Rect2(off, Vector2(W, H)), Color(0.004, 0.01, 0.03, dk * 0.85))
		return
	var strips: int = 32
	var sh: float = H / float(strips)
	for i in range(strips):
		var y: float = float(i) * sh
		var world_d: float = state.depth + (y - DIVER_Y) / PX_PER_DEPTH
		var dark: float = clamp(world_d / 620.0, 0.0, 1.0)
		var top := Color(0.05, 0.30, 0.34)
		var bottom := Color(0.005, 0.01, 0.03)
		var c: Color = top.lerp(bottom, dark)
		draw_rect(Rect2(off.x, y + off.y, W, sh + 1.0), c)

func _draw_plankton(off: Vector2) -> void:
	for p in plankton:
		var sy: float = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		var span: float = 800.0
		while sy < -20.0:
			p.d += span / PX_PER_DEPTH
			sy = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		while sy > H + 20.0:
			p.d -= span / PX_PER_DEPTH
			sy = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		draw_circle(Vector2(p.x, sy) + off, 2.0, Color(0.5, 0.7, 0.8, 0.18))

func _draw_safe_line(off: Vector2) -> void:
	# A bright line at your pressure-safe depth — below it, the crush bites. The
	# Pressure Rig pushes this line deeper, which is what makes the upgrade legible.
	var sy: float = _screen_y(state.max_safe_depth())
	if sy < -10.0 or sy > H + 10.0:
		return
	var col := Color(1.0, 0.55, 0.25, 0.5)
	var y: float = sy + off.y
	var x: float = 0.0
	while x < W:
		draw_line(Vector2(x, y), Vector2(x + 22, y), col, 2.0)
		x += 40.0

func _light_factor(pos: Vector2, zone: int) -> float:
	# In the deep dark, things fade unless they're inside the lantern's reach.
	if zone <= 0:
		return 1.0
	var diver_pos := Vector2(diver_x, DIVER_Y)
	var dist: float = pos.distance_to(diver_pos)
	var rng_px: float = state.lamp_range()
	var lit: float = clamp(1.0 - (dist - rng_px) / 120.0, 0.0, 1.0)
	var ambient: float = clamp(0.30 - float(zone) * 0.12, 0.05, 0.30)
	var result: float = max(lit, ambient)
	return result

func _draw_objects(off: Vector2) -> void:
	for obj in objects:
		if not obj.alive:
			continue
		var pos: Vector2 = Vector2(obj.x, _screen_y(obj.d)) + off
		var light: float = _light_factor(Vector2(obj.x, _screen_y(obj.d)), obj.zone)
		if obj.kind == "treasure":
			var base: Color = ZONE_TREASURE_COL[clamp(obj.zone, 0, ZONE_TREASURE_COL.size() - 1)]
			# Value is also encoded by SIZE (deeper zone = bigger = worth more) so the
			# richness read survives colour-blindness / grayscale — not hue alone.
			var tr: float = 9.0 + float(obj.zone) * 3.5
			var c := Color(base.r, base.g, base.b, light)
			_glow(pos, tr * 2.2 + float(obj.zone) * 3.0, Color(base.r, base.g, base.b, 0.15 * light))
			draw_circle(pos, tr, c)
			draw_circle(pos, tr * 0.45, Color(1.0, 1.0, 1.0, light))
		else:
			var htex: Texture2D = tex_eel if obj.zone >= 2 else tex_jelly
			if htex != null:
				# Jelly in the shallows/reef, sinister eel in the trench. Sized to
				# the hazard footprint; lantern darkness dims it via modulate alpha
				# (floored so a hazard is never fully invisible — fairness).
				var hw: float = 92.0
				var hh: float = hw * (float(htex.get_height()) / float(htex.get_width()))
				var hrect := Rect2(pos.x - hw * 0.5, pos.y - hh * 0.5, hw, hh)
				draw_texture_rect(htex, hrect, false, Color(1, 1, 1, clamp(0.4 + light, 0.0, 1.0)))
			else:
				var hc := Color(0.95, 0.20, 0.65)
				if obj.zone >= 2:
					hc = Color(0.55, 0.95, 0.55)   # trench predator: sickly green
				_glow(pos, 30.0, Color(hc.r, hc.g, hc.b, 0.16 * light))
				draw_circle(pos, 15.0, Color(hc.r, hc.g, hc.b, 0.85 * light))
				draw_line(pos, pos + Vector2(-7, 22), Color(hc.r, hc.g, hc.b, 0.6 * light), 3.0)
				draw_line(pos, pos + Vector2(8, 26), Color(hc.r, hc.g, hc.b, 0.6 * light), 3.0)

func _glow(pos: Vector2, r: float, col: Color) -> void:
	draw_circle(pos, r, Color(col.r, col.g, col.b, col.a * 0.5))
	draw_circle(pos, r * 0.7, Color(col.r, col.g, col.b, col.a * 0.9))
	draw_circle(pos, r * 0.4, Color(col.r, col.g, col.b, col.a * 1.3))

func _draw_diver(off: Vector2) -> void:
	var p: Vector2 = Vector2(diver_x, DIVER_Y) + off
	# headlamp cone (downward, into the dark) — wider/brighter with the Lantern
	var reach: float = 120.0 + float(state._lvl("lamp")) * 70.0
	var cone := PackedVector2Array([
		p + Vector2(-8, 6), p + Vector2(8, 6),
		p + Vector2(70, reach), p + Vector2(-70, reach)
	])
	draw_colored_polygon(cone, Color(1.0, 0.92, 0.65, 0.07))
	for b in bubbles:
		draw_circle(Vector2(b.x, b.y) + off, b.r, Color(0.8, 0.95, 1.0, 0.25 * clamp(b.life, 0.0, 1.0)))
	if tex_diver != null:
		# Painted free-diver, sized well above the hitbox (DIVER_R) so the hero
		# reads prominently; centered on the diver point, headlamp cone + bubbles
		# above stay code-drawn juice.
		var dw: float = 150.0
		var dh: float = dw * (float(tex_diver.get_height()) / float(tex_diver.get_width()))
		# Tint darker + cooler with depth so the hero picks up the deep's ambient
		# instead of reading as a bright pasted render in the dim crush zone.
		var dt: float = lerp(1.0, 0.52, clamp(state.depth / 480.0, 0.0, 1.0))
		draw_texture_rect(tex_diver, Rect2(p.x - dw * 0.5, p.y - dh * 0.5, dw, dh), false, Color(dt, dt * 1.02, dt * 1.1))
		return
	draw_circle(p, DIVER_R, Color(0.86, 0.93, 0.97, 0.96))
	draw_circle(p + Vector2(0, 16), 14.0, Color(0.78, 0.88, 0.94, 0.9))
	var fin := PackedVector2Array([p + Vector2(-18, 22), p + Vector2(18, 22), p + Vector2(0, 44)])
	draw_colored_polygon(fin, Color(0.7, 0.82, 0.9, 0.9))
	draw_circle(p + Vector2(10, -6), 4.0, Color(1.0, 0.85, 0.5))

func _draw_godrays() -> void:
	var vis: float = clamp(1.0 - state.depth / 160.0, 0.0, 1.0)
	if vis <= 0.0:
		return
	var surf_y: float = _screen_y(0.0)
	for i in range(4):
		var x: float = 80.0 + float(i) * 180.0
		var ray := PackedVector2Array([
			Vector2(x, surf_y), Vector2(x + 40, surf_y),
			Vector2(x + 130, surf_y + 320), Vector2(x + 50, surf_y + 320)
		])
		draw_colored_polygon(ray, Color(0.6, 0.85, 0.85, 0.05 * vis))

func _draw_crush_vignette() -> void:
	# pulsing inward red glow while past the safe depth — air is draining fast
	var pulse: float = 0.4 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.008)
	var band: float = 90.0
	draw_rect(Rect2(0, 0, W, band), Color(0.7, 0.1, 0.2, 0.10 * pulse))
	draw_rect(Rect2(0, H - band, W, band), Color(0.7, 0.1, 0.2, 0.14 * pulse))

func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	if not state.active:
		_draw_surface_screen(font)
		return
	# air bar (top) — the survival read-out, the thing you must watch
	var bar_x: float = 30.0
	var bar_y: float = 34.0
	var bar_w: float = W - 60.0
	var bar_h: float = 44.0
	# styled gauge: dark-glass channel + cyan hairline frame, gradient fill, an
	# air-valve bubble cap — a first-class HUD gauge, not a flat default bar.
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.04, 0.08, 0.10, 0.85))
	var af: float = state.air_frac()
	var low: bool = af <= DiveStateC.AIR_LOW_FRAC
	var fill := Color(0.2, 0.85, 1.0)
	if state.is_crushing():
		fill = Color(0.95, 0.45, 0.2)
	if low:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		fill = Color(1.0, 0.25 + 0.2 * pulse, 0.25)
	var fw: float = (bar_w - 6.0) * af
	draw_rect(Rect2(bar_x + 3.0, bar_y + 3.0, fw, bar_h - 6.0), fill)
	if fw > 1.0:
		draw_rect(Rect2(bar_x + 3.0, bar_y + 3.0, fw, (bar_h - 6.0) * 0.42), Color(1.0, 1.0, 1.0, 0.16))
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.32, 0.78, 0.86, 0.7), false, 2.0)
	draw_circle(Vector2(bar_x + 20.0, bar_y + bar_h * 0.5), 8.0, Color(0.7, 0.95, 1.0, 0.9))
	draw_circle(Vector2(bar_x + 24.0, bar_y + bar_h * 0.5 - 3.0), 2.5, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(bar_x + 39.0, bar_y + 31.0), "AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(bar_x + 38.0, bar_y + 30.0), "AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.98, 1.0, 0.95))

	# depth + zone (left), banked (right)
	var zname: String = state.zone_name(state.zone_for(state.depth))
	draw_string(font, Vector2(30.0, 120.0), "%dm · %s" % [int(state.depth), zname], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.7, 0.85, 0.95))
	var score_scale: float = 26.0 + bank_pulse * 12.0
	draw_string(font, Vector2(W - 250.0, 120.0), "BANKED %d" % state.banked, HORIZONTAL_ALIGNMENT_RIGHT, 220, int(score_scale), Color(1.0, 0.92, 0.6))

	# Backing pill behind the danger warnings so the red alarm text clears WCAG
	# over the pulsing red crush vignette (measured 4.39:1 without it).
	if state.is_crushing() or low:
		draw_rect(Rect2(36.0, 130.0, W - 72.0, 78.0), Color(0.05, 0.04, 0.11, 0.76))
	if state.is_crushing():
		draw_string(font, Vector2(0.0, 152.0), "⚠ PRESSURE CRUSH — air draining fast", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1.0, 0.58, 0.45))
	# explicit non-colour LOW-AIR flag (text cue mirrors the crush warning; the air
	# state must not rest on the bar's hue alone — it collapses under colour-blindness)
	if low:
		var lp: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		draw_string(font, Vector2(0.0, 182.0), "▲ LOW AIR — surface now", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(1.0, 0.52 + 0.28 * lp, 0.5))

	# COMMISSION (the reason to descend) — target zone + progress
	var ctz: String = state.zone_name(state.commission_target_zone())
	var cprog: String = "%d/%d" % [state.commission_have, DiveStateC.COMMISSION_TARGET]
	var ccol := Color(0.7, 1.0, 0.85) if state.commission_complete() else Color(0.85, 0.9, 0.7)
	var csize: int = int(24 + commission_flash * 10.0)
	draw_string(font, Vector2(0.0, 210.0), "ORDER: %d %s relics  %s" % [DiveStateC.COMMISSION_TARGET, ctz, cprog], HORIZONTAL_ALIGNMENT_CENTER, W, csize, ccol)
	if state.commission_complete():
		draw_string(font, Vector2(0.0, 242.0), "order filled — surface to cash it in", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(0.7, 1.0, 0.85))

	# unbanked haul (center) — the thing you stand to lose
	var haul_size: float = 36.0 + haul_pulse * 16.0
	draw_string(font, Vector2(0.0, 290.0), "HAUL  %d" % state.haul, HORIZONTAL_ALIGNMENT_CENTER, W, int(haul_size), Color(0.6, 1.0, 0.8))

	if not state.descending:
		draw_string(font, Vector2(0.0, 330.0), "ASCENDING…", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0.6, 0.9, 1.0))

func _draw_surface_screen(font: Font) -> void:
	# A defined panel container (the scene is already scrim-darkened) so the shop
	# reads as a distinct screen, not loose HUD text floating on live gameplay.
	var px: float = 36.0
	var pw: float = W - 72.0
	var py: float = 200.0
	var ph: float = 790.0
	draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.05, 0.11, 0.90))
	draw_rect(Rect2(px, py, pw, 4.0), Color(0.32, 0.78, 0.86, 0.7))                 # top accent
	draw_rect(Rect2(px, py + ph - 4.0, pw, 4.0), Color(0.32, 0.78, 0.86, 0.30))     # base accent
	draw_string(font, Vector2(0.0, 258.0), "SURFACE", HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color(0.92, 0.96, 1.0))
	draw_string(font, Vector2(0.0, 300.0), "banked  %d" % state.banked, HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(1.0, 0.92, 0.6))
	# outcome line for the dive that just ended
	if _last_outcome == "forfeit":
		draw_string(font, Vector2(0.0, 342.0), "the deep kept your catch", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(1.0, 0.62, 0.72))
	elif _last_outcome == "banked":
		var line := "catch banked safely"
		if _last_commission_filled:
			line = "ORDER FILLED  +%d bonus" % _last_bonus
		draw_string(font, Vector2(0.0, 342.0), line, HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0.7, 1.0, 0.85))
	var nz: String = state.zone_name(state.commission_target_zone())
	draw_string(font, Vector2(0.0, 394.0), "next order: %d %s relics  •  bonus %d" % [DiveStateC.COMMISSION_TARGET, nz, state.commission_bonus()], HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(0.75, 0.88, 1.0))
	draw_string(font, Vector2(0.0, 428.0), "upgrade your gear to reach deeper zones", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(0.72, 0.82, 0.92))
