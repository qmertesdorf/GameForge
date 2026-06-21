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

func _ready() -> void:
	state = DiveStateC.new()
	state.seed_rng(20240620)
	_load_meta()
	_seed_plankton()
	ascend_button.pressed.connect(_on_ascend_pressed)
	dive_again_button.pressed.connect(_on_dive_again_pressed)
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
		b.offset_left = 70.0
		b.offset_top = y
		b.offset_right = W - 70.0
		b.offset_bottom = y + 80.0
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_on_upgrade_pressed.bind(key))
		ui_layer.add_child(b)
		upgrade_buttons[key] = b
		y += 92.0

func _seed_plankton() -> void:
	plankton.clear()
	for i in range(46):
		plankton.append({
			"x": state.rng.randf_range(0.0, W),
			"d": state.rng.randf_range(-200.0, 600.0),
		})

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
	_draw_plankton(off)
	_draw_safe_line(off)
	_draw_objects(off)
	_draw_diver(off)
	_draw_godrays()
	if state.is_crushing():
		_draw_crush_vignette()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(flash_col.r, flash_col.g, flash_col.b, clamp(flash * 0.5, 0.0, 0.6)))
	_draw_hud()

func _draw_background(off: Vector2) -> void:
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
			var c := Color(base.r, base.g, base.b, light)
			_glow(pos, 24.0 + float(obj.zone) * 6.0, Color(base.r, base.g, base.b, 0.16 * light))
			draw_circle(pos, 11.0, c)
			draw_circle(pos, 5.0, Color(1.0, 1.0, 1.0, light))
		else:
			var hc := Color(0.95, 0.20, 0.65)
			if obj.zone >= 2:
				hc = Color(0.55, 0.95, 0.55)   # trench predator: sickly green
			_glow(pos, 30.0, Color(hc.r, hc.g, hc.b, 0.16 * light))
			draw_circle(pos, 15.0, Color(hc.r, hc.g, hc.b, 0.85 * light))
			draw_line(pos, pos + Vector2(-7, 22), Color(hc.r, hc.g, hc.b, 0.6 * light), 3.0)
			draw_line(pos, pos + Vector2(8, 26), Color(hc.r, hc.g, hc.b, 0.6 * light), 3.0)

func _glow(pos: Vector2, r: float, col: Color) -> void:
	draw_circle(pos, r, Color(col.r, col.g, col.b, col.a))
	draw_circle(pos, r * 0.66, Color(col.r, col.g, col.b, col.a * 1.4))

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
	# air bar (top, large, the most important read-out)
	var bar_x: float = 30.0
	var bar_y: float = 36.0
	var bar_w: float = W - 60.0
	var bar_h: float = 34.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.0, 0.0, 0.0, 0.45))
	var af: float = state.air_frac()
	var low: bool = af <= DiveStateC.AIR_LOW_FRAC
	var fill := Color(0.2, 0.85, 1.0)
	if state.is_crushing():
		fill = Color(0.95, 0.45, 0.2)
	if low:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		fill = Color(1.0, 0.25 + 0.2 * pulse, 0.25)
	draw_rect(Rect2(bar_x + 2.0, bar_y + 2.0, (bar_w - 4.0) * af, bar_h - 4.0), fill)
	draw_string(font, Vector2(bar_x + 8.0, bar_y + 25.0), "AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.7))

	# depth + zone (left), banked (right)
	var zname: String = state.zone_name(state.zone_for(state.depth))
	draw_string(font, Vector2(30.0, 110.0), "%dm · %s" % [int(state.depth), zname], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.7, 0.85, 0.95))
	var score_scale: float = 26.0 + bank_pulse * 12.0
	draw_string(font, Vector2(W - 250.0, 110.0), "BANKED %d" % state.banked, HORIZONTAL_ALIGNMENT_RIGHT, 220, int(score_scale), Color(1.0, 0.92, 0.6))

	if state.is_crushing() and state.active:
		draw_string(font, Vector2(0.0, 140.0), "⚠ PRESSURE CRUSH — air draining fast", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1.0, 0.5, 0.35))

	# COMMISSION (the reason to descend) — target zone + progress
	if state.active:
		var ctz: String = state.zone_name(state.commission_target_zone())
		var cprog: String = "%d/%d" % [state.commission_have, DiveStateC.COMMISSION_TARGET]
		var ccol := Color(0.7, 1.0, 0.85) if state.commission_complete() else Color(0.85, 0.9, 0.7)
		var csize: int = int(24 + commission_flash * 10.0)
		draw_string(font, Vector2(0.0, 200.0), "ORDER: %d %s relics  %s" % [DiveStateC.COMMISSION_TARGET, ctz, cprog], HORIZONTAL_ALIGNMENT_CENTER, W, csize, ccol)
		if state.commission_complete():
			draw_string(font, Vector2(0.0, 232.0), "order filled — surface to cash it in", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(0.7, 1.0, 0.85))

	# unbanked haul (center) — the thing you stand to lose
	var haul_size: float = 36.0 + haul_pulse * 16.0
	var haul_col := Color(0.6, 1.0, 0.8)
	if not state.active:
		haul_col = Color(0.6, 0.7, 0.8, 0.6)
	draw_string(font, Vector2(0.0, 280.0), "HAUL  %d" % state.haul, HORIZONTAL_ALIGNMENT_CENTER, W, int(haul_size), haul_col)

	if not state.descending and state.active:
		draw_string(font, Vector2(0.0, 320.0), "ASCENDING…", HORIZONTAL_ALIGNMENT_CENTER, W, 24, Color(0.6, 0.9, 1.0))

	if not state.active:
		_draw_surface_screen(font)

func _draw_surface_screen(font: Font) -> void:
	# outcome line for the dive that just ended
	if _last_outcome == "forfeit":
		draw_string(font, Vector2(0.0, 250.0), "the deep kept your catch", HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(0.95, 0.5, 0.62))
	elif _last_outcome == "banked":
		var line := "catch banked safely"
		if _last_commission_filled:
			line = "ORDER FILLED  +%d bonus" % _last_bonus
		draw_string(font, Vector2(0.0, 250.0), line, HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(0.6, 0.95, 0.8))
	# surface shop header + next order
	draw_string(font, Vector2(0.0, 330.0), "SURFACE", HORIZONTAL_ALIGNMENT_CENTER, W, 36, Color(0.9, 0.94, 1.0))
	var nz: String = state.zone_name(state.commission_target_zone())
	draw_string(font, Vector2(0.0, 384.0), "next order: %d %s relics  •  bonus %d" % [DiveStateC.COMMISSION_TARGET, nz, state.commission_bonus()], HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color(0.7, 0.85, 1.0))
	draw_string(font, Vector2(0.0, 420.0), "upgrade the rig to reach deeper zones ↓", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(0.55, 0.68, 0.82))
