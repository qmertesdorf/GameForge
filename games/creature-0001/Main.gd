extends Node2D

# ============================================================
# Glade Spirit (creature-0001) — top-down creature forager
# Node2D root, all rendering via _draw(), no physics bodies.
# One-thumb drag-to-move, seed collection + streak combo,
# roaming thorn-sprite hazards, difficulty ramp, game-over + restart.
# ============================================================

# --- Screen ---
const VIEW_W: float = 720.0
const VIEW_H: float = 1280.0

# --- Palette: warm autumn forest ---
const COL_BG: Color        = Color(0.08, 0.18, 0.10)      # deep forest green
const COL_SPIRIT: Color    = Color(0.95, 0.70, 0.30)      # warm amber
const COL_SPIRIT_GLOW: Color = Color(1.0, 0.85, 0.45, 0.20)
const COL_SEED: Color      = Color(1.0, 0.88, 0.15)       # bright gold
const COL_SEED_GLOW: Color = Color(1.0, 0.95, 0.4, 0.22)
const COL_HAZARD: Color    = Color(0.62, 0.18, 0.22)      # rust-red thorn
const COL_HAZARD_GLOW: Color = Color(0.9, 0.25, 0.25, 0.18)
const COL_TREE_NEAR: Color  = Color(0.05, 0.14, 0.07)     # dark silhouette near
const COL_TREE_FAR: Color   = Color(0.06, 0.16, 0.08)     # dark silhouette far
const COL_HUD: Color       = Color(1.0, 0.92, 0.50)
const COL_WHITE: Color     = Color(1.0, 1.0, 1.0)
const COL_RED_FLASH: Color = Color(0.95, 0.15, 0.15, 0.55)

# --- Player tuning ---
const SPIRIT_SPEED: float    = 480.0     # max px/s
const SPIRIT_ACCEL: float    = 10.0      # lerp factor toward target vel
const SPIRIT_RADIUS: float   = 26.0
const JOYSTICK_DEAD: float   = 12.0      # px dead zone
const JOYSTICK_MAX: float    = 110.0     # px at full speed

# --- Seed tuning ---
const SEED_RADIUS: float     = 14.0
const SEED_COLLECT_R: float  = SPIRIT_RADIUS + SEED_RADIUS
const MAX_SEEDS: int         = 5
const SEED_SPAWN_INTERVAL: float = 1.6  # seconds between new seeds when under cap
const SEED_PULSE_SPEED: float = 3.5     # animation

# --- Streak / multiplier ---
const STREAK_FOR_MULT: int  = 3         # seeds per multiplier step
const MAX_MULTIPLIER: int   = 5
const SCORE_PER_SEED: int   = 10

# --- Hazard tuning ---
# Difficulty ramps every 12s. Hard cap at tier 6.
const RAMP_INTERVAL: float      = 12.0
const MAX_TIER: int              = 6
const BASE_HAZARD_SPEED: float   = 80.0
const SPEED_PER_TIER: float      = 28.0   # added per tier
const MAX_HAZARD_SPEED: float    = BASE_HAZARD_SPEED + MAX_TIER * SPEED_PER_TIER
const BASE_HAZARD_INTERVAL: float = 3.0   # seconds between spawns
const MIN_HAZARD_INTERVAL: float  = 1.0   # cap
const HAZARD_RADIUS: float       = 22.0
const HIT_RADIUS: float          = SPIRIT_RADIUS + HAZARD_RADIUS - 8.0  # slightly forgiving

# --- Juice tuning ---
const SHAKE_MAG: float   = 18.0
const SHAKE_DECAY: float = 9.0
const FLASH_DECAY: float = 2.2
const PICKUP_PULSE_DUR: float = 0.28  # seed pickup scale pop on HUD score

# --- Parallax tree bands ---
# Each band: { y_offset, height, z } — drawn tiled horizontally
const NUM_TREE_NEAR: int = 7
const NUM_TREE_FAR: int = 5

# ============================================================
# State
# ============================================================
var screen_w: float = VIEW_W
var screen_h: float = VIEW_H

# Player
var spirit_pos: Vector2 = Vector2.ZERO
var spirit_vel: Vector2 = Vector2.ZERO
var spirit_squash: float = 1.0   # y scale for squash/stretch feedback

# Virtual joystick
var stick_active: bool = false
var stick_origin: Vector2 = Vector2.ZERO
var stick_pos: Vector2 = Vector2.ZERO

# Seeds: typed arrays for Godot-4.6 safety
var seed_positions: Array[Vector2] = []
var seed_phases: Array[float] = []     # for pulse animation
var seed_timer: float = 0.0

# Hazards: untyped dicts (multi-field)
var hazards: Array = []    # { pos:Vector2, vel:Vector2, drift_angle:float }
var hazard_timer: float = 0.0

# Scoring
var score: int = 0
var best: int = 0
var streak: int = 0
var multiplier: int = 1
var mult_pulse: float = 0.0   # visual pulse on multiplier bump

# Game state
var alive: bool = true
var ramp_timer: float = 0.0
var tier: int = 0
var elapsed: float = 0.0

# Juice
var shake: float = 0.0
var hurt_flash: float = 0.0    # red vignette on hit
var score_pulse: float = 0.0   # scale-pop on score

# Particles
var particles: Array = []   # { pos, vel, life, maxlife, col, size }

# Background parallax
var tree_near: Array = []   # { x, width, height, y_top }
var tree_far: Array = []
var parallax_offset: float = 0.0   # scrolls gently
var ground_dots: Array = []        # faint leaf/texture dots on ground layer

# --- Audio (M1.6 audio_pass) ---
# Generated via Stable Audio Open; SFX one-shots + a looping ambient bed.
var _audio_players: Dictionary = {}      # event -> AudioStreamPlayer
var audio_play_counts: Dictionary = {}   # event -> int, selftest hook

# --- Raster art (M1.5 asset_pass) ---
# Painterly RGBA sprites generated via ComfyUI+SDXL(Juggernaut)+LayerDiffuse.
# spirit + hazard are raster; seed stays a procedural glow-mote (mixed-method).
const SPIRIT_DRAW: float = 110.0   # on-screen sprite size (px); footprint/hitbox = SPIRIT_RADIUS
const HAZARD_DRAW: float = 92.0
var tex_spirit: Texture2D = null
var tex_hazard: Texture2D = null


# ============================================================
# Init
# ============================================================
func _ready() -> void:
	randomize()
	var vp: Vector2 = get_viewport_rect().size
	screen_w = vp.x
	screen_h = vp.y
	# Linear filtering + mipmaps: 1024² masters shown at ~100px need clean minification.
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tex_spirit = load("res://art/spirit.png")
	tex_hazard = load("res://art/hazard.png")
	_setup_audio()
	_build_background()
	_start_game()


# ============================================================
# Audio (M1.6)
# ============================================================
func _setup_audio() -> void:
	if not _audio_players.is_empty():
		return   # idempotent (selftest may call this explicitly)
	_make_player("collect", "res://audio/collect.wav", false)
	_make_player("streak", "res://audio/streak.wav", false)
	_make_player("gameover", "res://audio/gameover.wav", false)
	_make_player("bgm", "res://audio/bgm.wav", true)
	# Bed starts via autoplay (set in _make_player BEFORE add_child) — an immediate
	# play() the same frame as add_child does not reliably start it (finding #4).


func _make_player(event_name: String, path: String, looping: bool) -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	# Node name (PascalCase) is what audio_pass.events[].node references.
	p.name = "Sfx" + event_name.capitalize() if event_name != "bgm" else "MusicAmbient"
	var stream: Resource = load(path)
	if looping and stream is AudioStreamWAV:
		# REAL bgm-not-playing root cause (A/B-round-2; supersedes the earlier
		# same-frame-play() guess): an IMPORTED long AudioStreamWAV (the ~30s bed)
		# silently refuses to play -- play() leaves playing=false, pos=0 -- while a
		# freshly-CONSTRUCTED AudioStreamWAV from the SAME PCM data plays. So rebuild
		# the bed stream in code and loop the whole sample.
		var src: AudioStreamWAV = stream
		var w := AudioStreamWAV.new()
		w.format = src.format
		w.mix_rate = src.mix_rate
		w.stereo = src.stereo
		w.data = src.data
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = src.data.size() / (4 if src.stereo else 2)  # 16-bit frames
		stream = w
	if stream != null:
		p.stream = stream
	if looping:
		# Start on tree entry (autoplay set BEFORE add_child).
		p.autoplay = true
		# Audible bed mixed UNDER the SFX (which play at 0 dB default).
		p.volume_db = -4.0
	add_child(p)
	_audio_players[event_name] = p


func _play_sfx(event_name: String) -> void:
	# Count first so the selftest hook is robust even if a stream failed to load.
	audio_play_counts[event_name] = int(audio_play_counts.get(event_name, 0)) + 1
	var p: AudioStreamPlayer = _audio_players.get(event_name)
	if p != null and p.stream != null and p.is_inside_tree():
		p.play()


func _build_background() -> void:
	# Far silhouette band — tall tree crowns, darker
	tree_far.clear()
	for i in range(NUM_TREE_FAR):
		var x: float = randf() * screen_w
		var w: float = randf_range(60.0, 130.0)
		var h: float = randf_range(160.0, 280.0)
		tree_far.append({ "x": x, "width": w, "height": h, "y_top": randf_range(0.0, 40.0) })
	# Near silhouette band — tree trunks + bases
	tree_near.clear()
	for i in range(NUM_TREE_NEAR):
		var x: float = randf() * screen_w
		var w: float = randf_range(40.0, 80.0)
		var h: float = randf_range(80.0, 150.0)
		tree_near.append({ "x": x, "width": w, "height": h, "y_top": randf_range(screen_h * 0.75, screen_h * 0.85) })
	# Ground texture dots
	ground_dots.clear()
	for i in range(60):
		ground_dots.append({
			"x": randf() * screen_w,
			"y": randf_range(screen_h * 0.82, screen_h),
			"r": randf_range(2.0, 5.0),
			"a": randf_range(0.05, 0.18)
		})


func _start_game() -> void:
	spirit_pos = Vector2(screen_w * 0.5, screen_h * 0.55)
	spirit_vel = Vector2.ZERO
	spirit_squash = 1.0
	stick_active = false

	seed_positions.clear()
	seed_phases.clear()
	seed_timer = 0.0

	hazards.clear()
	hazard_timer = 0.0

	score = 0
	streak = 0
	multiplier = 1
	mult_pulse = 0.0
	score_pulse = 0.0

	alive = true
	ramp_timer = 0.0
	tier = 0
	elapsed = 0.0

	shake = 0.0
	hurt_flash = 0.0

	particles.clear()

	# Seed a few seeds immediately so the field feels alive on start
	for i in range(3):
		_spawn_seed()


# ============================================================
# Input — virtual joystick (touch + mouse drag), tap to restart
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			_release()
	elif event is InputEventScreenDrag:
		_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			_release()
	elif event is InputEventMouseMotion:
		if stick_active:
			_drag(event.position)


func _press(pos: Vector2) -> void:
	if not alive:
		_start_game()
		return
	stick_active = true
	stick_origin = pos
	stick_pos = pos


func _drag(pos: Vector2) -> void:
	if not stick_active:
		return
	stick_pos = pos


func _release() -> void:
	stick_active = false


# ============================================================
# Main update loop
# ============================================================
func _process(delta: float) -> void:
	if alive:
		elapsed += delta
		_update_spirit(delta)
		_update_seeds(delta)
		_update_hazards(delta)
		_check_collisions()
		_update_difficulty(delta)
	_update_particles(delta)
	_update_juice(delta)
	_update_background(delta)
	queue_redraw()


func _update_spirit(delta: float) -> void:
	var target_vel: Vector2 = Vector2.ZERO
	if stick_active:
		var drag: Vector2 = stick_pos - stick_origin
		var dist: float = drag.length()
		if dist > JOYSTICK_DEAD:
			var mag: float = clamp((dist - JOYSTICK_DEAD) / (JOYSTICK_MAX - JOYSTICK_DEAD), 0.0, 1.0)
			target_vel = drag.normalized() * (SPIRIT_SPEED * mag)
	spirit_vel = spirit_vel.lerp(target_vel, clamp(SPIRIT_ACCEL * delta, 0.0, 1.0))
	spirit_pos += spirit_vel * delta
	# Clamp inside screen with padding
	spirit_pos.x = clamp(spirit_pos.x, SPIRIT_RADIUS + 10.0, screen_w - SPIRIT_RADIUS - 10.0)
	spirit_pos.y = clamp(spirit_pos.y, SPIRIT_RADIUS + 80.0, screen_h - SPIRIT_RADIUS - 40.0)
	# Squash/stretch: stretch when moving fast, relax when still
	var speed_ratio: float = clamp(spirit_vel.length() / SPIRIT_SPEED, 0.0, 1.0)
	var target_squash: float = 1.0 - speed_ratio * 0.2
	spirit_squash = lerp(spirit_squash, target_squash, clamp(12.0 * delta, 0.0, 1.0))


func _spawn_seed() -> void:
	# Pick a random position away from the spirit and other seeds
	var attempt: int = 0
	var pos: Vector2 = Vector2.ZERO
	while attempt < 20:
		pos = Vector2(
			randf_range(SEED_RADIUS + 60.0, screen_w - SEED_RADIUS - 60.0),
			randf_range(SEED_RADIUS + 120.0, screen_h - SEED_RADIUS - 80.0)
		)
		var ok: bool = true
		# Keep distance from spirit
		if spirit_pos.distance_squared_to(pos) < 140.0 * 140.0:
			ok = false
		# Keep distance from other seeds
		if ok:
			for sp in seed_positions:
				var sep: Vector2 = sp
				if sep.distance_squared_to(pos) < 70.0 * 70.0:
					ok = false
					break
		if ok:
			break
		attempt += 1
	seed_positions.append(pos)
	seed_phases.append(randf() * TAU)


func _update_seeds(delta: float) -> void:
	# Animate pulse phases
	for i in range(seed_phases.size()):
		seed_phases[i] = seed_phases[i] + SEED_PULSE_SPEED * delta
	# Spawn new seeds if under cap
	if seed_positions.size() < MAX_SEEDS:
		seed_timer += delta
		if seed_timer >= SEED_SPAWN_INTERVAL:
			seed_timer = 0.0
			_spawn_seed()


func _hazard_speed() -> float:
	var spd: float = BASE_HAZARD_SPEED + float(tier) * SPEED_PER_TIER
	return clamp(spd, BASE_HAZARD_SPEED, MAX_HAZARD_SPEED)


func _hazard_interval() -> float:
	var t: float = float(tier) / float(MAX_TIER)
	var interval: float = lerp(BASE_HAZARD_INTERVAL, MIN_HAZARD_INTERVAL, t)
	return interval


func _spawn_hazard() -> void:
	# Spawn off-screen edges
	var edge: int = randi() % 4
	var pos: Vector2 = Vector2.ZERO
	if edge == 0:
		pos = Vector2(randf() * screen_w, -HAZARD_RADIUS * 2.0)
	elif edge == 1:
		pos = Vector2(randf() * screen_w, screen_h + HAZARD_RADIUS * 2.0)
	elif edge == 2:
		pos = Vector2(-HAZARD_RADIUS * 2.0, randf() * screen_h)
	else:
		pos = Vector2(screen_w + HAZARD_RADIUS * 2.0, randf() * screen_h)
	# Drift toward spirit with a slight random angle offset (homing-ish but not perfect)
	var base_angle: float = (spirit_pos - pos).angle()
	var drift_angle: float = base_angle + randf_range(-0.35, 0.35)
	var spd: float = _hazard_speed()
	var vel: Vector2 = Vector2(cos(drift_angle), sin(drift_angle)) * spd
	hazards.append({
		"pos": pos,
		"vel": vel,
		"drift_angle": drift_angle,
		"wobble": randf() * TAU
	})


func _update_hazards(delta: float) -> void:
	hazard_timer += delta
	if hazard_timer >= _hazard_interval():
		hazard_timer = 0.0
		_spawn_hazard()
	var spd: float = _hazard_speed()
	for h in hazards:
		var hpos: Vector2 = h.pos
		# Gentle course-correction toward spirit (homing-ish drift)
		var target_angle: float = (spirit_pos - hpos).angle()
		var current_angle: float = h.drift_angle
		# Smooth angular correction, capped at 1.2 rad/s (not too snappy)
		var angle_diff: float = wrapf(target_angle - current_angle, -PI, PI)
		h.drift_angle = current_angle + clamp(angle_diff, -1.2 * delta, 1.2 * delta)
		var da: float = h.drift_angle
		h.vel = Vector2(cos(da), sin(da)) * spd
		h.pos = hpos + h.vel * delta
		h.wobble = float(h.wobble) + delta * 2.5
	# Cull hazards that have gone far off-screen
	var keep: Array = []
	for h in hazards:
		var hpos: Vector2 = h.pos
		if hpos.x > -200.0 and hpos.x < screen_w + 200.0 and hpos.y > -200.0 and hpos.y < screen_h + 200.0:
			keep.append(h)
	hazards = keep


func _check_collisions() -> void:
	if not alive:
		return
	# Seed collection
	var i: int = seed_positions.size() - 1
	while i >= 0:
		var sp: Vector2 = seed_positions[i]
		if spirit_pos.distance_squared_to(sp) <= SEED_COLLECT_R * SEED_COLLECT_R:
			seed_positions.remove_at(i)
			seed_phases.remove_at(i)
			_on_seed_collected(sp)
		i -= 1
	# Hazard collision
	for h in hazards:
		var hpos: Vector2 = h.pos
		if spirit_pos.distance_squared_to(hpos) <= HIT_RADIUS * HIT_RADIUS:
			_game_over()
			return


func _on_seed_collected(pos: Vector2) -> void:
	streak += 1
	# Multiplier steps up every STREAK_FOR_MULT consecutive seeds, capped
	var new_mult: int = clamp(1 + (streak - 1) / STREAK_FOR_MULT, 1, MAX_MULTIPLIER)
	if new_mult != multiplier:
		multiplier = new_mult
		mult_pulse = 1.0
		_play_sfx("streak")   # brighter cue when the multiplier steps up
	score += SCORE_PER_SEED * multiplier
	best = max(best, score)
	score_pulse = 1.0
	_play_sfx("collect")
	# Warm burst particles at seed location
	_spawn_particles(pos, COL_SEED, 12, 160.0)
	# Spirit squash-pop on pickup
	spirit_squash = 1.35


func _game_over() -> void:
	alive = false
	shake = SHAKE_MAG
	hurt_flash = 1.0
	_play_sfx("gameover")
	_spawn_particles(spirit_pos, COL_SPIRIT, 20, 280.0)
	_spawn_particles(spirit_pos, COL_HAZARD, 14, 200.0)


func _update_difficulty(delta: float) -> void:
	ramp_timer += delta
	if ramp_timer >= RAMP_INTERVAL and tier < MAX_TIER:
		ramp_timer = 0.0
		tier += 1


# ============================================================
# Particles
# ============================================================
func _spawn_particles(pos: Vector2, col: Color, count: int, speed: float) -> void:
	for i in range(count):
		var ang: float = randf() * TAU
		var spd: float = randf_range(speed * 0.3, speed)
		var life: float = randf_range(0.28, 0.65)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": life,
			"maxlife": life,
			"col": col,
			"size": randf_range(2.5, 6.0)
		})


func _update_particles(delta: float) -> void:
	var keep: Array = []
	for p in particles:
		var ppos: Vector2 = p.pos
		var pvel: Vector2 = p.vel
		ppos = ppos + pvel * delta
		pvel = pvel * (1.0 - clamp(3.5 * delta, 0.0, 1.0))
		p.pos = ppos
		p.vel = pvel
		p.life = float(p.life) - delta
		if float(p.life) > 0.0:
			keep.append(p)
	particles = keep


# ============================================================
# Juice update
# ============================================================
func _update_juice(delta: float) -> void:
	var new_shake: float = lerp(shake, 0.0, clamp(SHAKE_DECAY * delta, 0.0, 1.0))
	shake = new_shake
	if shake < 0.05:
		shake = 0.0
	hurt_flash = max(hurt_flash - FLASH_DECAY * delta, 0.0)
	score_pulse = max(score_pulse - 3.0 * delta, 0.0)
	mult_pulse = max(mult_pulse - 2.0 * delta, 0.0)
	spirit_squash = lerp(spirit_squash, 1.0, clamp(8.0 * delta, 0.0, 1.0))


func _update_background(delta: float) -> void:
	# Gentle parallax: tree silhouettes drift slowly opposite spirit motion
	parallax_offset += spirit_vel.x * delta * 0.04


# ============================================================
# Rendering
# ============================================================
func _draw() -> void:
	var sh: Vector2 = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform(sh, 0.0, Vector2.ONE)
	_draw_background()
	_draw_seeds()
	_draw_hazards()
	_draw_spirit()
	_draw_particles()
	if hurt_flash > 0.0:
		_draw_edge_flash(hurt_flash)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()


func _draw_background() -> void:
	# Deep forest green base
	draw_rect(Rect2(0, 0, screen_w, screen_h), COL_BG)

	# Far parallax tree silhouettes (crowns at top, slow drift)
	var far_cols: Color = COL_TREE_FAR
	for t in tree_far:
		var tx: float = t.x
		var tw: float = t.width
		var th: float = t.height
		var ty: float = t.y_top
		var ox: float = fposmod(tx - parallax_offset * 0.3, screen_w + tw) - tw
		# Rounded crown blob: draw as stacked ellipses
		var cx: float = ox + tw * 0.5
		var cy: float = ty + th * 0.4
		draw_circle(Vector2(cx, cy), tw * 0.55, far_cols)
		draw_circle(Vector2(cx - tw * 0.28, cy + th * 0.18), tw * 0.38, far_cols)
		draw_circle(Vector2(cx + tw * 0.28, cy + th * 0.18), tw * 0.38, far_cols)
		draw_rect(Rect2(ox + tw * 0.35, cy, tw * 0.3, th * 0.55), far_cols)

	# Ground color gradient — lighter in center (glade floor)
	var glade_rect: Rect2 = Rect2(screen_w * 0.1, screen_h * 0.3, screen_w * 0.8, screen_h * 0.55)
	draw_rect(glade_rect, Color(0.10, 0.22, 0.12, 0.35))

	# Ground texture dots (autumn leaves scatter)
	for d in ground_dots:
		var dx: float = fposmod(d.x - parallax_offset * 0.5, screen_w)
		draw_circle(Vector2(dx, d.y), d.r, Color(0.55, 0.38, 0.12, d.a))

	# Near silhouette tree trunks at bottom edges
	var near_cols: Color = COL_TREE_NEAR
	for t in tree_near:
		var tx: float = t.x
		var tw: float = t.width
		var th: float = t.height
		var ty: float = t.y_top
		var ox: float = fposmod(tx - parallax_offset * 0.7, screen_w + tw) - tw
		draw_rect(Rect2(ox + tw * 0.35, ty, tw * 0.3, th), near_cols)
		draw_circle(Vector2(ox + tw * 0.5, ty), tw * 0.42, near_cols)


func _draw_seeds() -> void:
	for i in range(seed_positions.size()):
		var sp: Vector2 = seed_positions[i]
		var phase: float = seed_phases[i]
		var pulse: float = 0.5 + 0.5 * sin(phase)
		var r: float = SEED_RADIUS * (0.88 + pulse * 0.22)
		# Glow halo
		draw_circle(sp, r * 2.2, Color(COL_SEED_GLOW.r, COL_SEED_GLOW.g, COL_SEED_GLOW.b, 0.18 + pulse * 0.12))
		# Second soft glow ring
		draw_circle(sp, r * 1.6, Color(COL_SEED.r, COL_SEED.g, COL_SEED.b, 0.22))
		# Core bright circle
		draw_circle(sp, r, COL_SEED)
		# White sparkle center
		draw_circle(sp, r * 0.35, Color(1.0, 1.0, 1.0, 0.9))


func _draw_hazards() -> void:
	for h in hazards:
		var hpos: Vector2 = h.pos
		# (No procedural halo: the dark thorn-sprite reads on its own; a small
		# primitive halo behind the larger sprite read as an odd disc.)
		# Painterly RGBA thorn-sprite, scaled to footprint, centered on hazard pos.
		if tex_hazard != null:
			draw_texture_rect(tex_hazard, Rect2(hpos - Vector2(HAZARD_DRAW, HAZARD_DRAW) * 0.5, Vector2(HAZARD_DRAW, HAZARD_DRAW)), false)


func _draw_spirit() -> void:
	var sq: float = spirit_squash   # y scale for squash/stretch
	var sx: float = 1.0 / max(sq, 0.6)  # compensate x so area stays ~constant
	# Glow halo (juice — stays procedural)
	var halo_r: float = SPIRIT_RADIUS * 1.8
	draw_circle(spirit_pos, halo_r, Color(COL_SPIRIT_GLOW.r, COL_SPIRIT_GLOW.g, COL_SPIRIT_GLOW.b, 0.22))
	# Painterly RGBA sprite, scaled to footprint, squash/stretch preserved.
	# (eyes/highlight are baked into the art now — primitive body removed.)
	if tex_spirit != null:
		var w: float = SPIRIT_DRAW * sx
		var h: float = SPIRIT_DRAW * sq
		draw_texture_rect(tex_spirit, Rect2(spirit_pos - Vector2(w, h) * 0.5, Vector2(w, h)), false)


func _draw_particles() -> void:
	for p in particles:
		var pp: Vector2 = p.pos
		var life: float = float(p.life)
		var maxlife: float = float(p.maxlife)
		var a: float = clamp(life / maxlife, 0.0, 1.0)
		var col: Color = p.col
		var sz: float = float(p.size) * a
		draw_circle(pp, sz, Color(col.r, col.g, col.b, a * 0.85))


func _draw_edge_flash(amt: float) -> void:
	var thickness: float = 80.0
	var c: Color = Color(COL_RED_FLASH.r, COL_RED_FLASH.g, COL_RED_FLASH.b, amt * 0.6)
	draw_rect(Rect2(0, 0, screen_w, thickness), c)
	draw_rect(Rect2(0, screen_h - thickness, screen_w, thickness), c)
	draw_rect(Rect2(0, 0, thickness, screen_h), c)
	draw_rect(Rect2(screen_w - thickness, 0, thickness, screen_h), c)


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# Score (top-center) with scale-pop on pickup
	var score_size: float = 54.0 + score_pulse * 20.0
	var score_col: Color = COL_HUD.lerp(Color(1, 1, 1), score_pulse * 0.7)
	draw_string(font, Vector2(0, 72), str(score),
		HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), int(score_size), score_col)
	# Streak / multiplier (top-right)
	if multiplier > 1 or streak > 0:
		var mult_size: float = 30.0 + mult_pulse * 16.0
		var mult_col: Color = Color(1.0, 0.75, 0.25).lerp(Color(1, 1, 1), mult_pulse)
		draw_string(font, Vector2(screen_w - 200.0, 55), "x" + str(multiplier),
			HORIZONTAL_ALIGNMENT_RIGHT, 190, int(mult_size), mult_col)
		draw_string(font, Vector2(screen_w - 200.0, 88), "streak " + str(streak),
			HORIZONTAL_ALIGNMENT_RIGHT, 190, 22, Color(0.85, 0.75, 0.45, 0.8))
	# Tier indicator (top-left, small)
	if tier > 0:
		draw_string(font, Vector2(20, 55), "tier " + str(tier + 1),
			HORIZONTAL_ALIGNMENT_LEFT, 160, 22, Color(0.65, 0.80, 0.55, 0.7))
	# Joystick ring guide (only when alive and pressing)
	if alive and stick_active:
		draw_arc(stick_origin, JOYSTICK_MAX, 0.0, TAU, 32, Color(1, 1, 1, 0.14), 2.0)
		draw_circle(stick_pos, 18.0, Color(1, 1, 1, 0.22))
	# Game over overlay
	if not alive:
		draw_rect(Rect2(0, 0, screen_w, screen_h), Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(0, screen_h * 0.42), "GAME OVER",
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 60, Color(0.95, 0.35, 0.35))
		draw_string(font, Vector2(0, screen_h * 0.50), "SCORE  " + str(score),
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 40, COL_HUD)
		if best > 0:
			draw_string(font, Vector2(0, screen_h * 0.57), "BEST  " + str(best),
				HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 30, Color(0.75, 0.68, 0.38))
		draw_string(font, Vector2(0, screen_h * 0.65), "TAP TO RESTART",
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 34, Color(1, 1, 1, 0.9))
