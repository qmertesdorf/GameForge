extends Node2D

# Neon Dash II — endless runner with juice, layered visuals, and fair tuning.
# M1 SVG re-skin: world actors (player / obstacle / orb) are now Sprite2D nodes
# textured from games/runner-0002/art/*.svg. The background (bg/grid/stars/ground)
# stays procedural in _draw(); particles + HUD + flash move to a higher-z Overlay
# child so they stay above the sprites. Movement, collision, spawning, scoring,
# input, game-over/restart, and all juice timers are UNCHANGED — only the visual
# representation of the three actors changed. Collision still via Rect2 AABB.
# TAB-indented.

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

# --- SVG re-skin: crisp core of every SVG spans 60u of a 100u viewBox; the glow
# halo bleeds into the remaining padding. A sprite is scaled footprint / SVG_CORE
# so its crisp core matches the primitive's original footprint. ---
const SVG_CORE: float = 60.0

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
var current_shake: Vector2 = Vector2.ZERO  # computed per-frame; shared by bg draw + sprites

# Background star dots (precomputed, drift slowly with parallax).
var stars: Array = []   # each: { "pos": Vector2, "r": float, "speed": float }

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _font: Font = null
var _font_size: int = 32

# --- SVG re-skin nodes ---
var _tex_player: Texture2D = null
var _tex_obstacle: Texture2D = null
var _tex_orb: Texture2D = null
var player_sprite: Sprite2D = null
var obstacle_sprites: Array = []   # pooled Sprite2D, one per live obstacle
var orb_sprites: Array = []        # pooled Sprite2D, one per live (alive) orb
var overlay: Node2D = null


func _ready() -> void:
	_rng.randomize()
	# Headless-safe default font lookup; guard so a null never crashes the HUD.
	if ThemeDB.fallback_font != null:
		_font = ThemeDB.fallback_font
		_font_size = ThemeDB.fallback_font_size
	_build_stars()
	_build_sprites()
	_reset()


func _build_stars() -> void:
	stars.clear()
	for i in range(60):
		stars.append({
			"pos": Vector2(_rng.randf_range(0.0, VIEW_W), _rng.randf_range(0.0, GROUND_Y)),
			"r": _rng.randf_range(1.0, 3.0),
			"speed": _rng.randf_range(0.15, 0.45),  # parallax fraction of scroll speed
		})


# Create the textured actor nodes + the top overlay layer (M1 SVG re-skin).
func _build_sprites() -> void:
	_tex_player = load("res://art/player.svg")
	_tex_obstacle = load("res://art/obstacle.svg")
	_tex_orb = load("res://art/orb.svg")

	player_sprite = Sprite2D.new()
	player_sprite.texture = _tex_player
	player_sprite.z_index = 1
	add_child(player_sprite)

	overlay = Node2D.new()
	overlay.set_script(load("res://Overlay.gd"))
	overlay.z_index = 5
	add_child(overlay)
	overlay.game = self


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
	current_shake = Vector2.ZERO
	_update_sprites()
	queue_redraw()
	if overlay != null:
		overlay.queue_redraw()


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

	# Screen shake offset, computed once per frame and shared by the background
	# draw and every actor sprite so they shake together.
	current_shake = Vector2.ZERO
	if shake_timer > 0.0:
		var amt: float = (shake_timer / SHAKE_TIME) * SHAKE_MAG
		current_shake = Vector2(_rng.randf_range(-amt, amt), _rng.randf_range(-amt, amt))

	# Particles keep animating even on game over.
	_update_particles(delta)

	if game_over:
		_update_sprites()
		queue_redraw()
		overlay.queue_redraw()
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

	_update_sprites()
	queue_redraw()
	overlay.queue_redraw()


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


# === SVG re-skin: position/scale the textured actor nodes to match the primitive
# footprints they replaced. One Sprite2D per live obstacle / alive orb (pooled).
# All offset by current_shake so they shake with the background. ===
func _update_sprites() -> void:
	if player_sprite == null:
		return

	# Player: same squash/stretch the old _draw() applied, anchored at the feet.
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
	player_sprite.position = Vector2(PLAYER_X + PLAYER_SIZE * 0.5, (player_y + PLAYER_SIZE) - ph * 0.5) + current_shake
	player_sprite.scale = Vector2(pw / SVG_CORE, ph / SVG_CORE)

	# Obstacles: grow the pool as needed, place one sprite per live obstacle,
	# hide the rest. Tint the white SVG to the per-instance neon color.
	while obstacle_sprites.size() < obstacles.size():
		var os: Sprite2D = Sprite2D.new()
		os.texture = _tex_obstacle
		os.z_index = 1
		add_child(os)
		obstacle_sprites.append(os)
	for i in range(obstacle_sprites.size()):
		var osp: Sprite2D = obstacle_sprites[i]
		if i < obstacles.size():
			var r: Rect2 = obstacles[i]["rect"]
			osp.visible = true
			osp.position = r.position + r.size * 0.5 + current_shake
			osp.scale = Vector2(r.size.x / SVG_CORE, r.size.y / SVG_CORE)
			osp.modulate = obstacles[i]["color"]
		else:
			osp.visible = false

	# Orbs: same pooling, only the alive ones, with the pulse scale.
	var live: Array = []
	for orb in orbs:
		if orb["alive"]:
			live.append(orb)
	while orb_sprites.size() < live.size():
		var qs: Sprite2D = Sprite2D.new()
		qs.texture = _tex_orb
		qs.z_index = 1
		add_child(qs)
		orb_sprites.append(qs)
	for i in range(orb_sprites.size()):
		var qsp: Sprite2D = orb_sprites[i]
		if i < live.size():
			var pulse: float = 1.0 + 0.18 * sin(live[i]["phase"])
			qsp.visible = true
			qsp.position = live[i]["pos"] + current_shake
			qsp.scale = Vector2.ONE * (2.0 * ORB_RADIUS * pulse / SVG_CORE)
		else:
			qsp.visible = false


func _draw() -> void:
	# Background + ground only. Actors are Sprite2D children (z_index 1); the HUD,
	# particles and flash are drawn by the Overlay child (z_index 5). Background and
	# ground shake with the actors via the shared current_shake offset.
	draw_set_transform(current_shake, 0.0, Vector2.ONE)

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

	# === Play layer (ground only; actors are sprites) ===
	# Glowing ground line (halo + crisp).
	draw_line(Vector2(0.0, GROUND_Y), Vector2(VIEW_W, GROUND_Y), Color(accent.r, accent.g, accent.b, 0.30), 10.0)
	draw_line(Vector2(0.0, GROUND_Y), Vector2(VIEW_W, GROUND_Y), accent, 3.0)


# Drawn by the Overlay child (above the actor sprites): particles, HUD, crash flash.
func draw_overlay(ci: CanvasItem) -> void:
	# Particles (short-lived fading dots) — shake with the world.
	for p in particles:
		var t: float = 1.0 - (p["life"] / p["max"])
		var pc: Color = p["color"]
		ci.draw_circle(p["pos"] + current_shake, 5.0 * t + 1.0, Color(pc.r, pc.g, pc.b, t))

	# === HUD layer (no shake so the score stays steady) ===
	if _font != null:
		var pulse_size: int = _font_size + 24 + int(score_pulse * 18.0)
		var score_str: String = "%d" % int(score)
		# Approximate centering using string width.
		var sw: float = _font.get_string_size(score_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pulse_size).x
		ci.draw_string(_font, Vector2((VIEW_W - sw) * 0.5, 100.0), score_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pulse_size, COLOR_WHITE)

		# Combo readout under the score when above 1x.
		if combo > 1:
			var cstr: String = "x%d" % combo
			var cw: float = _font.get_string_size(cstr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x
			ci.draw_string(_font, Vector2((VIEW_W - cw) * 0.5, 150.0), cstr, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COLOR_ORB)

		if game_over:
			var go_str: String = "GAME OVER"
			var gw: float = _font.get_string_size(go_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size + 12).x
			ci.draw_string(_font, Vector2((VIEW_W - gw) * 0.5, VIEW_H * 0.5), go_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size + 12, COLOR_OBSTACLE_A)
			var tap_str: String = "TAP TO RESTART"
			var tw: float = _font.get_string_size(tap_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size).x
			ci.draw_string(_font, Vector2((VIEW_W - tw) * 0.5, VIEW_H * 0.5 + 50.0), tap_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, COLOR_PLAYER)

	# === Crash flash (full-screen decaying white overlay, on top of everything) ===
	if flash_timer > 0.0:
		var a: float = (flash_timer / FLASH_TIME) * 0.8
		ci.draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), Color(1, 1, 1, a), true)
