extends Node2D
# Fathom — view + input + spatial layer. Owns positions/collision/rendering and
# all juice; defers every economy rule to DiveState (the rules/rendering seam).
# Layered scene: scrolling depth-gradient background + parallax plankton (back),
# treasures/hazards/diver (play), air bar + counters + buttons (HUD).

const DiveStateC := preload("res://DiveState.gd")

const W: float = 720.0
const H: float = 1280.0
const DIVER_Y: float = 520.0          # fixed screen-y of the diver; the world scrolls past
const PX_PER_DEPTH: float = 3.0       # 1 depth unit = 3 px
const SPAWN_AHEAD: float = 270.0      # depth units below the diver where objects appear
const DESPAWN_BEHIND: float = 90.0    # depth units above the diver before recycling
const COLLIDE_R: float = 48.0
const DIVER_R: float = 26.0
const TREASURE_SPACING: float = 62.0  # 1 treasure per this much descent
const SAFE_DEPTH: float = 70.0        # no hazards in the calm first stretch (fairness)
const BASE_TREASURE_VALUE: float = 8.0

var state: DiveState
var diver_x: float = W * 0.5
var target_x: float = W * 0.5
# objects: { x:float, d:float, kind:String("treasure"|"hazard"), value:int, alive:bool }
var objects: Array = []
var plankton: Array = []               # { x:float, d:float }
var _last_treasure_d: float = 0.0
var _last_hazard_d: float = 0.0

# juice
var shake: float = 0.0
var flash: float = 0.0
var haul_pulse: float = 0.0
var bank_pulse: float = 0.0
var bubbles: Array = []                # { x:float, y:float, r:float, life:float }
var _bubble_t: float = 0.0

@onready var ascend_button: Button = $UI/AscendButton
@onready var dive_again_button: Button = $UI/DiveAgainButton

func _ready() -> void:
	state = DiveStateC.new()
	state.seed_rng(20240620)
	_seed_plankton()
	ascend_button.pressed.connect(_on_ascend_pressed)
	dive_again_button.pressed.connect(_on_dive_again_pressed)
	_start_dive()

func _seed_plankton() -> void:
	plankton.clear()
	for i in range(46):
		plankton.append({
			"x": state.rng.randf_range(0.0, W),
			"d": state.rng.randf_range(-200.0, 600.0),
		})

func _start_dive() -> void:
	state.start_dive()
	objects.clear()
	bubbles.clear()
	diver_x = W * 0.5
	target_x = W * 0.5
	_last_treasure_d = 0.0
	_last_hazard_d = 0.0
	_refresh_buttons()

func _next_dive() -> void:
	state.start_next_dive()
	objects.clear()
	bubbles.clear()
	diver_x = W * 0.5
	target_x = W * 0.5
	_last_treasure_d = 0.0
	_last_hazard_d = 0.0
	_refresh_buttons()

func _refresh_buttons() -> void:
	ascend_button.visible = state.active
	dive_again_button.visible = not state.active

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
		var lx: float = lerp(diver_x, target_x, clamp(delta * 10.0, 0.0, 1.0))
		diver_x = clamp(lx, 40.0, W - 40.0)
		_spawn(delta)
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
		var val: int = int(BASE_TREASURE_VALUE * (1.0 + d / 100.0))
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": d,
			"kind": "treasure",
			"value": val,
			"alive": true,
		})
	var hz_spacing: float = max(120.0 - float(state.dive_num) * 8.0, 64.0)
	if state.depth > SAFE_DEPTH and state.depth - _last_hazard_d >= hz_spacing:
		_last_hazard_d = state.depth
		objects.append({
			"x": state.rng.randf_range(60.0, W - 60.0),
			"d": state.depth + SPAWN_AHEAD,
			"kind": "hazard",
			"value": 0,
			"alive": true,
		})

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
				state.collect(int(obj.value))
				haul_pulse = 1.0
			else:
				state.hit_hazard()
				shake = 9.0
				flash = 0.8

func _handle_events(events: Array) -> void:
	for e in events:
		var t: String = e.get("type", "")
		if t == "banked":
			bank_pulse = 1.0
		elif t == "forfeit":
			shake = 12.0
			flash = 1.0
			_refresh_buttons()
		elif t == "air_low":
			flash = 0.4
	# active may have flipped to false this tick (banked/forfeit)
	if not state.active and ascend_button.visible:
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
	_draw_objects(off)
	_draw_diver(off)
	_draw_godrays()
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, clamp(flash * 0.5, 0.0, 0.6)))
	_draw_hud()

func _draw_background(off: Vector2) -> void:
	var strips: int = 32
	var sh: float = H / float(strips)
	for i in range(strips):
		var y: float = float(i) * sh
		var world_d: float = state.depth + (y - DIVER_Y) / PX_PER_DEPTH
		var dark: float = clamp(world_d / 700.0, 0.0, 1.0)
		var top := Color(0.05, 0.30, 0.34)
		var bottom := Color(0.01, 0.02, 0.05)
		var c: Color = top.lerp(bottom, dark)
		draw_rect(Rect2(off.x, y + off.y, W, sh + 1.0), c)

func _draw_plankton(off: Vector2) -> void:
	for p in plankton:
		var sy: float = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		# wrap the dot back to the bottom as it scrolls off the top
		var span: float = 800.0
		while sy < -20.0:
			p.d += span / PX_PER_DEPTH
			sy = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		while sy > H + 20.0:
			p.d -= span / PX_PER_DEPTH
			sy = DIVER_Y + (p.d - state.depth * 0.5) * PX_PER_DEPTH
		draw_circle(Vector2(p.x, sy) + off, 2.0, Color(0.5, 0.7, 0.8, 0.20))

func _draw_objects(off: Vector2) -> void:
	for obj in objects:
		if not obj.alive:
			continue
		var pos: Vector2 = Vector2(obj.x, _screen_y(obj.d)) + off
		if obj.kind == "treasure":
			_glow(pos, 26.0, Color(1.0, 0.85, 0.30))
			draw_circle(pos, 11.0, Color(1.0, 0.92, 0.55))
			draw_circle(pos, 5.0, Color(1.0, 1.0, 0.85))
		else:
			_glow(pos, 30.0, Color(0.95, 0.20, 0.65))
			draw_circle(pos, 15.0, Color(0.80, 0.12, 0.50, 0.85))
			# two faint tentacle strokes
			draw_line(pos, pos + Vector2(-7, 22), Color(0.95, 0.30, 0.70, 0.6), 3.0)
			draw_line(pos, pos + Vector2(8, 26), Color(0.95, 0.30, 0.70, 0.6), 3.0)

func _glow(pos: Vector2, r: float, col: Color) -> void:
	draw_circle(pos, r, Color(col.r, col.g, col.b, 0.16))
	draw_circle(pos, r * 0.66, Color(col.r, col.g, col.b, 0.22))

func _draw_diver(off: Vector2) -> void:
	var p: Vector2 = Vector2(diver_x, DIVER_Y) + off
	# headlamp cone (downward, into the dark)
	var cone := PackedVector2Array([
		p + Vector2(-8, 6), p + Vector2(8, 6),
		p + Vector2(64, 150), p + Vector2(-64, 150)
	])
	draw_colored_polygon(cone, Color(1.0, 0.92, 0.65, 0.07))
	# bubbles
	for b in bubbles:
		draw_circle(Vector2(b.x, b.y) + off, b.r, Color(0.8, 0.95, 1.0, 0.25 * clamp(b.life, 0.0, 1.0)))
	# body (pale silhouette) + warm lamp
	draw_circle(p, DIVER_R, Color(0.86, 0.93, 0.97, 0.96))
	draw_circle(p + Vector2(0, 16), 14.0, Color(0.78, 0.88, 0.94, 0.9))
	var fin := PackedVector2Array([p + Vector2(-18, 22), p + Vector2(18, 22), p + Vector2(0, 44)])
	draw_colored_polygon(fin, Color(0.7, 0.82, 0.9, 0.9))
	draw_circle(p + Vector2(10, -6), 4.0, Color(1.0, 0.85, 0.5))

func _draw_godrays() -> void:
	# faint shafts near the actual surface; fade out as you descend
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
	if low:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		fill = Color(1.0, 0.25 + 0.2 * pulse, 0.25)
	draw_rect(Rect2(bar_x + 2.0, bar_y + 2.0, (bar_w - 4.0) * af, bar_h - 4.0), fill)
	draw_string(font, Vector2(bar_x + 8.0, bar_y + 25.0), "AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.7))

	# depth (left) and banked score (right)
	draw_string(font, Vector2(30.0, 110.0), "DEPTH %dm" % int(state.depth), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.7, 0.85, 0.95))
	var score_scale: float = 28.0 + bank_pulse * 12.0
	draw_string(font, Vector2(W - 250.0, 110.0), "BANKED %d" % state.banked, HORIZONTAL_ALIGNMENT_RIGHT, 220, int(score_scale), Color(1.0, 0.92, 0.6))

	# unbanked haul (center, pulses on pickup) — the thing you stand to lose
	var haul_size: float = 40.0 + haul_pulse * 16.0
	var haul_col := Color(0.6, 1.0, 0.8)
	if not state.active:
		haul_col = Color(0.6, 0.7, 0.8, 0.6)
	draw_string(font, Vector2(0.0, 170.0), "HAUL  %d" % state.haul, HORIZONTAL_ALIGNMENT_CENTER, W, int(haul_size), haul_col)

	if not state.descending and state.active:
		draw_string(font, Vector2(0.0, 230.0), "ASCENDING…", HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(0.6, 0.9, 1.0))

	if not state.active:
		var msg: String = "DIVE OVER"
		if state.banked > 0:
			msg = "BANKED %d  •  TAP TO DIVE" % state.banked
		draw_string(font, Vector2(0.0, 700.0), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(0.85, 0.92, 1.0))
		if state.haul == 0 and state.max_depth_reached > 0.0:
			draw_string(font, Vector2(0.0, 660.0), "the deep kept your catch", HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(0.9, 0.5, 0.6))
