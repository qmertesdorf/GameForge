extends Node2D

# Neon Dash II — self-contained endless runner with juice, layered visuals,
# and fair tuning. All rendering via _draw() (draw_rect / draw_line / draw_circle);
# collision via Rect2 AABB. No physics bodies, no child scene instancing, so it
# runs cleanly under --headless. TAB-indented.

const VIEW_W: float = 720.0
const VIEW_H: float = 1280.0

# --- Palette (art direction) ---
const COLOR_BG: Color = Color("#080810")
const COLOR_PLAYER: Color = Color("#22e6ff")
const COLOR_OBSTACLE_A: Color = Color("#ff3df0")  # magenta
const COLOR_OBSTACLE_B: Color = Color("#ffe14d")  # yellow
const COLOR_ORB: Color = Color("#ffd23d")         # gold
const COLOR_WHITE: Color = Color(1, 1, 1, 1)

# Accent hues per speed tier (cycled when tiers exceed the list length).
const TIER_ACCENTS: Array = [
	Color("#22e6ff"),  # cyan
	Color("#3dff9e"),  # green
	Color("#ffe14d"),  # yellow
	Color("#ff8a3d"),  # orange
	Color("#ff3df0"),  # magenta
]

# --- Ground / player geometry ---
const GROUND_Y: float = 1080.0
const PLAYER_X: float = 160.0
const PLAYER_SIZE: float = 64.0

# --- Physics tuning ---
const GRAVITY: float = 2800.0
const JUMP_VELOCITY: float = -1250.0
const COYOTE_TIME: float = 0.10        # grace window after leaving ground
const INPUT_BUFFER: float = 0.12       # remembered tap just before landing

# --- Scroll / difficulty tuning ---
const BASE_SCROLL_SPEED: float = 380.0
const MAX_SCROLL_SPEED: float = 1050.0
const TIER_DURATION: float = 8.0       # seconds per speed tier
const TIER_SPEED_STEP: float = 95.0    # speed added per tier
const SPACING_SAFETY: float = 1.55     # multiplier on minimum clearable gap

# --- Orbs ---
const ORB_RADIUS: float = 22.0
const ORB_SPAWN_CHANCE: float = 0.55   # chance an obstacle is followed by an orb

# --- Juice tuning ---
const SHAKE_TIME: float = 0.25
const SHAKE_MAG: float = 26.0
const FLASH_TIME: float = 0.35
const SQUASH_TIME: float = 0.14

# --- Game state ---
var player_y: float = GROUND_Y - PLAYER_SIZE
var player_vy: float = 0.0
var on_ground: bool = true
var coyote_timer: float = 0.0
var buffer_timer: float = 0.0

var obstacles: Array = []   # each: { "rect": Rect2, "color": Color }
var orbs: Array = []        # each: { "pos": Vector2, "alive": bool, "phase": float }
var particles: Array = []   # each: { "pos": Vector2, "vel": Vector2, "life": float, "max": float, "color": Color }

var scroll_speed: float = BASE_SCROLL_SPEED
var spawn_x_cursor: float = VIEW_W      # x of the last spawned obstacle (for spacing)
var distance_since_spawn: float = 0.0

var elapsed: float = 0.0
var tier: int = 0

var score: float = 0.0
var combo: int = 1
var best_score: int = 0
var game_over: bool = false

# Juice state.
var shake_timer: float = 0.0
var flash_timer: float = 0.0
var squash_timer: float = 0.0          # >0 = squash (land), tracks via squash_kind
var squash_kind: int = 0               # 1 = takeoff (stretch), 2 = land (squash)
var score_pulse: float = 0.0           # decaying scale boost on HUD when orb grabbed
var bg_scroll: float = 0.0

# Background star dots (precomputed, drift slowly with parallax).
var stars: Array = []   # each: { "pos": Vector2, "r": float, "speed": float }

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _font: Font = null
var _font_size: int = 32


func _ready() -> void:
	_rng.randomize()
	# Headless-safe default font lookup; guard so a null never crashes _draw().
	if ThemeDB.fallback_font != null:
		_font = ThemeDB.fallback_font
		_font_size = ThemeDB.fallback_font_size
	_build_stars()
	_reset()


func _build_stars() -> void:
	stars.clear()
	for i in range(60):
		stars.append({
			"pos": Vector2(_rng.randf_range(0.0, VIEW_W), _rng.randf_range(0.0, GROUND_Y)),
			"r": _rng.randf_range(1.0, 3.0),
			"speed": _rng.randf_range(0.15, 0.45),  # parallax fraction of scroll speed
		})


func _reset() -> void:
	player_y = GROUND_Y - PLAYER_SIZE
	player_vy = 0.0
	on_ground = true
	coyote_timer = 0.0
	buffer_timer = 0.0
	obstacles.clear()
	orbs.clear()
	particles.clear()
	scroll_speed = BASE_SCROLL_SPEED
	spawn_x_cursor = VIEW_W
	distance_since_spawn = 0.0
	elapsed = 0.0
	tier = 0
	score = 0.0
	combo = 1
	game_over = false
	shake_timer = 0.0
	flash_timer = 0.0
	squash_timer = 0.0
	squash_kind = 0
	score_pulse = 0.0
	bg_scroll = 0.0
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var tapped: bool = false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed:
		tapped = true
	if tapped:
		_on_tap()


func _on_tap() -> void:
	if game_over:
		_reset()
		return
	buffer_timer = INPUT_BUFFER
	_try_jump()


func _try_jump() -> void:
	# Jump allowed if on ground or within coyote window, and a buffered tap exists.
	if buffer_timer <= 0.0:
		return
	if on_ground or coyote_timer > 0.0:
		player_vy = JUMP_VELOCITY
		on_ground = false
		coyote_timer = 0.0
		buffer_timer = 0.0
		squash_timer = SQUASH_TIME
		squash_kind = 1  # takeoff stretch


# Minimum horizontal gap (px) between obstacles that is always clearable, derived
# from the player's full jump airtime at the current scroll speed.
func _clearable_gap() -> float:
	var airtime: float = 2.0 * abs(JUMP_VELOCITY) / GRAVITY
	return scroll_speed * airtime * SPACING_SAFETY


func _process(delta: float) -> void:
	# Decay juice timers always (so death animation plays even after game over).
	if shake_timer > 0.0:
		shake_timer = max(0.0, shake_timer - delta)
	if flash_timer > 0.0:
		flash_timer = max(0.0, flash_timer - delta)
	if squash_timer > 0.0:
		squash_timer = max(0.0, squash_timer - delta)
	if score_pulse > 0.0:
		score_pulse = max(0.0, score_pulse - delta * 3.0)

	# Particles keep animating even on game over.
	_update_particles(delta)

	if game_over:
		queue_redraw()
		return

	elapsed += delta
	bg_scroll += scroll_speed * delta

	# Score climbs with time, scaled by combo multiplier.
	score += delta * 60.0 * float(combo)
	best_score = max(best_score, int(score))

	# Speed tiers: step up every TIER_DURATION up to the cap.
	var new_tier: int = int(elapsed / TIER_DURATION)
	if new_tier != tier:
		tier = new_tier
	scroll_speed = min(MAX_SCROLL_SPEED, BASE_SCROLL_SPEED + float(tier) * TIER_SPEED_STEP)

	# Input buffer decay + retry jump (lets a slightly-early tap still fire on land).
	if buffer_timer > 0.0:
		buffer_timer = max(0.0, buffer_timer - delta)
		_try_jump()

	# Coyote timer counts down while airborne after leaving ground.
	if not on_ground and coyote_timer > 0.0:
		coyote_timer = max(0.0, coyote_timer - delta)

	# Player physics: gravity + ground collision.
	var was_on_ground: bool = on_ground
	player_vy += GRAVITY * delta
	player_y += player_vy * delta
	var floor_y: float = GROUND_Y - PLAYER_SIZE
	if player_y >= floor_y:
		player_y = floor_y
		if not was_on_ground and player_vy > 0.0:
			# Just landed — squash juice.
			squash_timer = SQUASH_TIME
			squash_kind = 2
		player_vy = 0.0
		on_ground = true
		coyote_timer = COYOTE_TIME
	else:
		on_ground = false

	# Spawn pacing: spawn a new obstacle once the cursor has advanced a clearable gap.
	distance_since_spawn += scroll_speed * delta
	var gap_needed: float = _clearable_gap()
	if distance_since_spawn >= gap_needed:
		_spawn_obstacle()
		distance_since_spawn = 0.0

	var dx: float = scroll_speed * delta
	var player_rect: Rect2 = Rect2(PLAYER_X, player_y, PLAYER_SIZE, PLAYER_SIZE)

	# Advance + despawn obstacles, check collision.
	var kept_obs: Array = []
	for ob in obstacles:
		var r: Rect2 = ob["rect"]
		r.position.x -= dx
		ob["rect"] = r
		if r.position.x + r.size.x < -10.0:
			continue
		if player_rect.intersects(r):
			_trigger_game_over()
		kept_obs.append(ob)
	obstacles = kept_obs

	# Advance + collect orbs.
	var center: Vector2 = player_rect.position + player_rect.size * 0.5
	var kept_orbs: Array = []
	for orb in orbs:
		var pos: Vector2 = orb["pos"]
		pos.x -= dx
		orb["pos"] = pos
		orb["phase"] = orb["phase"] + delta * 4.0
		if pos.x < -ORB_RADIUS:
			continue
		if orb["alive"] and center.distance_to(pos) < (ORB_RADIUS + PLAYER_SIZE * 0.5):
			orb["alive"] = false
			_collect_orb(pos)
			continue
		kept_orbs.append(orb)
	orbs = kept_orbs

	queue_redraw()


func _spawn_obstacle() -> void:
	# Cap obstacle height so a coyote-aware jump always clears it.
	var h: float = _rng.randf_range(70.0, 190.0)
	var w: float = _rng.randf_range(46.0, 82.0)
	var color: Color = COLOR_OBSTACLE_A if _rng.randf() < 0.5 else COLOR_OBSTACLE_B
	var rect: Rect2 = Rect2(VIEW_W + w, GROUND_Y - h, w, h)
	obstacles.append({ "rect": rect, "color": color })

	# Sometimes float an orb in the arc above/after the obstacle as a reward beat.
	if _rng.randf() < ORB_SPAWN_CHANCE:
		var orb_x: float = VIEW_W + w + _rng.randf_range(90.0, 180.0)
		var orb_y: float = GROUND_Y - h - _rng.randf_range(120.0, 240.0)
		orb_y = clamp(orb_y, 320.0, GROUND_Y - 100.0)
		orbs.append({ "pos": Vector2(orb_x, orb_y), "alive": true, "phase": _rng.randf() * TAU })


func _collect_orb(pos: Vector2) -> void:
	combo += 1
	score += 50.0 * float(combo)
	score_pulse = 1.0
	# Small particle burst.
	for i in range(8):
		var ang: float = _rng.randf() * TAU
		var spd: float = _rng.randf_range(120.0, 300.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": 0.0,
			"max": _rng.randf_range(0.25, 0.5),
			"color": COLOR_ORB,
		})


func _update_particles(delta: float) -> void:
	var kept: Array = []
	for p in particles:
		p["life"] = p["life"] + delta
		if p["life"] >= p["max"]:
			continue
		var pos: Vector2 = p["pos"]
		pos += p["vel"] * delta
		p["pos"] = pos
		p["vel"] = p["vel"] * 0.90  # drag
		kept.append(p)
	particles = kept


func _trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	combo = 1
	best_score = max(best_score, int(score))
	shake_timer = SHAKE_TIME
	flash_timer = FLASH_TIME


func _accent() -> Color:
	return TIER_ACCENTS[tier % TIER_ACCENTS.size()]


# Helper: draw a neon shape as an oversized low-alpha halo plus a crisp core.
func _draw_glow_rect(r: Rect2, c: Color) -> void:
	var grow: Vector2 = r.size * 0.35 + Vector2(6, 6)
	var halo: Rect2 = Rect2(r.position - grow * 0.5, r.size + grow)
	draw_rect(halo, Color(c.r, c.g, c.b, 0.20), true)
	draw_rect(r, c, true)


func _draw_glow_circle(center: Vector2, radius: float, c: Color) -> void:
	draw_circle(center, radius * 1.9, Color(c.r, c.g, c.b, 0.20))
	draw_circle(center, radius, c)


func _draw() -> void:
	# Screen shake: offset the whole draw origin by a decaying random vector.
	var shake: Vector2 = Vector2.ZERO
	if shake_timer > 0.0:
		var amt: float = (shake_timer / SHAKE_TIME) * SHAKE_MAG
		shake = Vector2(_rng.randf_range(-amt, amt), _rng.randf_range(-amt, amt))
	draw_set_transform(shake, 0.0, Vector2.ONE)

	# === Background layer ===
	draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), COLOR_BG, true)

	var accent: Color = _accent()

	# Parallax grid (faint vertical + horizontal lines scrolling slower than play).
	var grid_color: Color = Color(accent.r, accent.g, accent.b, 0.06)
	var grid_spacing: float = 120.0
	var grid_off: float = fmod(bg_scroll * 0.25, grid_spacing)
	var gx: float = -grid_off
	while gx < VIEW_W:
		draw_line(Vector2(gx, 0.0), Vector2(gx, GROUND_Y), grid_color, 2.0)
		gx += grid_spacing
	var gy: float = 0.0
	while gy < GROUND_Y:
		draw_line(Vector2(0.0, gy), Vector2(VIEW_W, gy), grid_color, 2.0)
		gy += grid_spacing

	# Drifting star dots (slower parallax than grid).
	for s in stars:
		var sp: Vector2 = s["pos"]
		var sx: float = sp.x - fmod(bg_scroll * s["speed"], VIEW_W)
		if sx < 0.0:
			sx += VIEW_W
		draw_circle(Vector2(sx, sp.y), s["r"], Color(accent.r, accent.g, accent.b, 0.35))

	# === Play layer ===
	# Glowing ground line (halo + crisp).
	draw_line(Vector2(0.0, GROUND_Y), Vector2(VIEW_W, GROUND_Y), Color(accent.r, accent.g, accent.b, 0.30), 10.0)
	draw_line(Vector2(0.0, GROUND_Y), Vector2(VIEW_W, GROUND_Y), accent, 3.0)

	# Obstacles with glow halos.
	for ob in obstacles:
		_draw_glow_rect(ob["rect"], ob["color"])

	# Orbs (pulsing gold, glow halo).
	for orb in orbs:
		if not orb["alive"]:
			continue
		var pulse: float = 1.0 + 0.18 * sin(orb["phase"])
		_draw_glow_circle(orb["pos"], ORB_RADIUS * pulse, COLOR_ORB)

	# Particles (short-lived fading dots).
	for p in particles:
		var t: float = 1.0 - (p["life"] / p["max"])
		var pc: Color = p["color"]
		draw_circle(p["pos"], 5.0 * t + 1.0, Color(pc.r, pc.g, pc.b, t))

	# Player square with squash/stretch + glow halo.
	var sx2: float = 1.0
	var sy: float = 1.0
	if squash_timer > 0.0:
		var k: float = squash_timer / SQUASH_TIME  # 1 -> 0
		var amt2: float = 0.15 * k
		if squash_kind == 1:
			# takeoff: stretch tall
			sx2 = 1.0 - amt2
			sy = 1.0 + amt2
		else:
			# land: squash wide
			sx2 = 1.0 + amt2
			sy = 1.0 - amt2
	var pw: float = PLAYER_SIZE * sx2
	var ph: float = PLAYER_SIZE * sy
	# Anchor at the player's feet so squash/stretch stays grounded.
	var px: float = PLAYER_X + (PLAYER_SIZE - pw) * 0.5
	var py: float = (player_y + PLAYER_SIZE) - ph
	_draw_glow_rect(Rect2(px, py, pw, ph), COLOR_PLAYER)

	# === HUD layer (drawn last, no shake so the score stays steady) ===
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _font != null:
		var pulse_size: int = _font_size + 24 + int(score_pulse * 18.0)
		var score_str: String = "%d" % int(score)
		# Approximate centering using string width.
		var sw: float = _font.get_string_size(score_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pulse_size).x
		draw_string(_font, Vector2((VIEW_W - sw) * 0.5, 100.0), score_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pulse_size, COLOR_WHITE)

		# Combo readout under the score when above 1x.
		if combo > 1:
			var cstr: String = "x%d" % combo
			var cw: float = _font.get_string_size(cstr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x
			draw_string(_font, Vector2((VIEW_W - cw) * 0.5, 150.0), cstr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COLOR_ORB)

		if game_over:
			var go_str: String = "GAME OVER"
			var gw: float = _font.get_string_size(go_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size + 12).x
			draw_string(_font, Vector2((VIEW_W - gw) * 0.5, VIEW_H * 0.5), go_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size + 12, COLOR_OBSTACLE_A)
			var tap_str: String = "TAP TO RESTART"
			var tw: float = _font.get_string_size(tap_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x
			draw_string(_font, Vector2((VIEW_W - tw) * 0.5, VIEW_H * 0.5 + 50.0), tap_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COLOR_PLAYER)

	# === Crash flash (full-screen decaying white overlay, on top of everything) ===
	if flash_timer > 0.0:
		var a: float = (flash_timer / FLASH_TIME) * 0.8
		draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), Color(1, 1, 1, a), true)
