extends Node2D

# ============================================================
# Vector Storm (shooter-0001) — top-down neon shooter, _draw() based
# Node2D root, all state in arrays of dicts, no physics bodies.
# ============================================================

# --- Tunables: player ---
const PLAYER_SPEED: float = 540.0          # max move speed (px/s)
const PLAYER_ACCEL: float = 12.0           # lerp factor toward target velocity
const PLAYER_RADIUS: float = 22.0
const JOYSTICK_DEADZONE: float = 14.0      # px from origin before moving
const JOYSTICK_MAXDRAG: float = 120.0      # px drag = full speed
const INVULN_TIME: float = 1.6             # seconds of invulnerability after hit
const START_LIVES: int = 3

# --- Tunables: combat ---
const FIRE_COOLDOWN: float = 0.22          # seconds between shots
const BULLET_SPEED: float = 1050.0
const BULLET_LIFE: float = 1.4
const BULLET_RADIUS: float = 6.0
const AIM_RANGE: float = 2000.0            # only target enemies within range (always true here)

# --- Tunables: enemies / waves ---
const ENEMY_RADIUS: float = 24.0
const BASE_SPAWN_INTERVAL: float = 1.5     # gentle wave 1
const MIN_SPAWN_INTERVAL: float = 0.42     # spawn cap
const BASE_ENEMY_SPEED: float = 95.0       # well below player speed -> dodgeable
const MAX_ENEMY_SPEED: float = 250.0
const WAVE_TIME: float = 15.0
const MAX_WAVE: int = 9                     # ramp cap
const BASE_ENEMY_HP: int = 1
const SCORE_PER_KILL: int = 10

var screen_w: float = 720.0
var screen_h: float = 1280.0

# --- Player state ---
var ppos: Vector2 = Vector2.ZERO
var pvel: Vector2 = Vector2.ZERO
var paim: Vector2 = Vector2(0.0, -1.0)     # facing direction (toward target)
var lives: int = START_LIVES
var invuln: float = 0.0
var thrust: float = 0.0                     # 0..1, how hard we are moving (for trail/thruster)

# --- Virtual joystick ---
var stick_active: bool = false
var stick_origin: Vector2 = Vector2.ZERO
var stick_pos: Vector2 = Vector2.ZERO

# --- Combat state ---
var bullets: Array = []                    # {pos:Vector2, vel:Vector2, life:float}
var enemies: Array = []                    # {pos:Vector2, vel:Vector2, hp:int, maxhp:int, spin:float, hue:float}
var fire_timer: float = 0.0

# --- Wave / score state ---
var wave: int = 1
var wave_timer: float = 0.0
var spawn_timer: float = 0.0
var score: int = 0
var best: int = 0
var alive: bool = true

# --- Streak multiplier ---
var streak: int = 0                        # consecutive kills without taking a hit
var multiplier: int = 1
var mult_pulse: float = 0.0                # visual pulse when multiplier ticks

# --- Juice ---
var shake: float = 0.0
var flash: float = 0.0                      # white kill flash
var hurt_flash: float = 0.0                 # red edge flash on player hit
var particles: Array = []                   # {pos:Vector2, vel:Vector2, life:float, maxlife:float, col:Color, size:float}
var trail: Array = []                       # thruster trail {pos:Vector2, life:float}
var muzzle: float = 0.0                      # muzzle flash timer

# --- Background ---
var stars: Array = []                       # {pos:Vector2, z:float}
var grid_scroll: Vector2 = Vector2.ZERO     # grid offset (scrolls opposite ship motion)

const BG_COLOR: Color = Color(0.0235, 0.0314, 0.0588)   # #06080f
const CYAN: Color = Color(0.3, 1.0, 0.95)
const YELLOW: Color = Color(1.0, 0.95, 0.35)
const MAGENTA: Color = Color(1.0, 0.25, 0.55)


func _ready() -> void:
	randomize()
	var vp: Vector2 = get_viewport_rect().size
	screen_w = vp.x
	screen_h = vp.y
	for i in range(90):
		stars.append({
			"pos": Vector2(randf() * screen_w, randf() * screen_h),
			"z": randf() * 0.85 + 0.15
		})
	_reset()


func _reset() -> void:
	ppos = Vector2(screen_w * 0.5, screen_h * 0.5)
	pvel = Vector2.ZERO
	paim = Vector2(0.0, -1.0)
	lives = START_LIVES
	invuln = 0.0
	thrust = 0.0
	bullets.clear()
	enemies.clear()
	particles.clear()
	trail.clear()
	fire_timer = 0.0
	wave = 1
	wave_timer = 0.0
	spawn_timer = BASE_SPAWN_INTERVAL * 0.5
	score = 0
	alive = true
	streak = 0
	multiplier = 1
	mult_pulse = 0.0
	shake = 0.0
	flash = 0.0
	hurt_flash = 0.0
	muzzle = 0.0
	stick_active = false


# ============================================================
# Input — virtual joystick (touch + mouse), tap to restart
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
		_reset()
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
# Main loop
# ============================================================
func _process(delta: float) -> void:
	if alive:
		_update_player(delta)
		_update_waves(delta)
		_update_enemies(delta)
		_update_firing(delta)
		_update_bullets(delta)
		_check_collisions(delta)
	else:
		# Idle game-over state: keep particles/juice decaying, no entity logic.
		pass
	_update_particles(delta)
	_update_juice(delta)
	_update_background(delta)
	queue_redraw()


func _update_player(delta: float) -> void:
	if invuln > 0.0:
		invuln -= delta
	# Compute desired velocity from virtual joystick.
	var target_vel: Vector2 = Vector2.ZERO
	if stick_active:
		var drag: Vector2 = stick_pos - stick_origin
		var dist: float = drag.length()
		if dist > JOYSTICK_DEADZONE:
			var mag: float = clamp((dist - JOYSTICK_DEADZONE) / (JOYSTICK_MAXDRAG - JOYSTICK_DEADZONE), 0.0, 1.0)
			target_vel = drag.normalized() * (PLAYER_SPEED * mag)
	pvel = pvel.lerp(target_vel, clamp(PLAYER_ACCEL * delta, 0.0, 1.0))
	ppos += pvel * delta
	# Keep ship on screen.
	ppos.x = clamp(ppos.x, PLAYER_RADIUS, screen_w - PLAYER_RADIUS)
	ppos.y = clamp(ppos.y, PLAYER_RADIUS, screen_h - PLAYER_RADIUS)
	thrust = clamp(pvel.length() / PLAYER_SPEED, 0.0, 1.0)
	# Thruster trail (emitted behind the ship, opposite aim).
	if thrust > 0.18:
		var back: Vector2 = -paim
		trail.append({
			"pos": ppos + back * (PLAYER_RADIUS + 4.0),
			"life": 0.32
		})
	while trail.size() > 40:
		trail.pop_front()


func _update_waves(delta: float) -> void:
	wave_timer += delta
	if wave_timer >= WAVE_TIME and wave < MAX_WAVE:
		wave_timer = 0.0
		wave += 1
	# Spawn pacing ramps with wave, capped.
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_enemy()
		var t: float = float(wave - 1) / float(MAX_WAVE - 1)
		var interval: float = lerp(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, t)
		spawn_timer = interval


func _spawn_enemy() -> void:
	# Spawn just off a random edge.
	var edge: int = randi() % 4
	var pos: Vector2 = Vector2.ZERO
	if edge == 0:      # top
		pos = Vector2(randf() * screen_w, -ENEMY_RADIUS * 2.0)
	elif edge == 1:    # bottom
		pos = Vector2(randf() * screen_w, screen_h + ENEMY_RADIUS * 2.0)
	elif edge == 2:    # left
		pos = Vector2(-ENEMY_RADIUS * 2.0, randf() * screen_h)
	else:              # right
		pos = Vector2(screen_w + ENEMY_RADIUS * 2.0, randf() * screen_h)
	var t: float = float(wave - 1) / float(MAX_WAVE - 1)
	var spd: float = lerp(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, t)
	# Tougher enemies appear from wave 3 onward (1-3 hp scaled by wave).
	var hp: int = BASE_ENEMY_HP
	if wave >= 3 and randf() < 0.30 + t * 0.35:
		hp = 2
	if wave >= 6 and randf() < 0.20 + t * 0.30:
		hp = 3
	enemies.append({
		"pos": pos,
		"vel": Vector2.ZERO,
		"hp": hp,
		"maxhp": hp,
		"spin": randf() * TAU,
		"speed": spd
	})


func _update_enemies(delta: float) -> void:
	for e in enemies:
		var epos: Vector2 = e.pos
		var espeed: float = e.speed
		var to_player: Vector2 = ppos - epos
		var dir: Vector2 = to_player.normalized()
		var vel: Vector2 = dir * espeed
		e.vel = vel
		e.pos = epos + vel * delta
		e.spin = float(e.spin) + delta * 2.0


# ============================================================
# Auto-aim + auto-fire (guard empty enemy list!)
# ============================================================
func _update_firing(delta: float) -> void:
	fire_timer -= delta
	var target: Dictionary = _nearest_enemy()
	if target.is_empty():
		return  # nothing to shoot at -> don't fire, don't crash
	var tpos: Vector2 = target.pos
	var aim_dir: Vector2 = (tpos - ppos).normalized()
	if aim_dir != Vector2.ZERO:
		paim = paim.lerp(aim_dir, clamp(10.0 * delta, 0.0, 1.0)).normalized()
	if fire_timer <= 0.0:
		fire_timer = FIRE_COOLDOWN
		_fire(aim_dir)


func _nearest_enemy() -> Dictionary:
	# Returns {} when there are no enemies (empty-list guard).
	var best_d: float = AIM_RANGE * AIM_RANGE
	var found: Dictionary = {}
	for e in enemies:
		var epos: Vector2 = e.pos
		var d: float = ppos.distance_squared_to(epos)
		if d < best_d:
			best_d = d
			found = e
	return found


func _fire(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	var muzzle_pos: Vector2 = ppos + dir * (PLAYER_RADIUS + 6.0)
	bullets.append({
		"pos": muzzle_pos,
		"vel": dir * BULLET_SPEED,
		"life": BULLET_LIFE
	})
	muzzle = 0.09


func _update_bullets(delta: float) -> void:
	var keep: Array = []
	for b in bullets:
		var bpos: Vector2 = b.pos
		var bvel: Vector2 = b.vel
		bpos = bpos + bvel * delta
		b.pos = bpos
		b.life = float(b.life) - delta
		var on_screen: bool = bpos.x > -40.0 and bpos.x < screen_w + 40.0 and bpos.y > -40.0 and bpos.y < screen_h + 40.0
		if float(b.life) > 0.0 and on_screen:
			keep.append(b)
	bullets = keep


# ============================================================
# Collisions: bullet<->enemy and player<->enemy
# ============================================================
func _check_collisions(delta: float) -> void:
	# Bullet vs enemy.
	var dead_enemies: Array = []
	var spent_bullets: Array = []
	for b in bullets:
		if b in spent_bullets:
			continue
		var bpos: Vector2 = b.pos
		for e in enemies:
			if e in dead_enemies:
				continue
			var epos: Vector2 = e.pos
			var rad: float = BULLET_RADIUS + ENEMY_RADIUS
			if bpos.distance_squared_to(epos) <= rad * rad:
				spent_bullets.append(b)
				e.hp = int(e.hp) - 1
				_spawn_particles(epos, MAGENTA, 6, 130.0)
				if int(e.hp) <= 0:
					dead_enemies.append(e)
					_on_kill(epos)
				break
	for b in spent_bullets:
		bullets.erase(b)
	for e in dead_enemies:
		enemies.erase(e)

	# Player vs enemy (only when vulnerable).
	if invuln <= 0.0:
		for e in enemies:
			var epos: Vector2 = e.pos
			var rad: float = PLAYER_RADIUS + ENEMY_RADIUS
			if ppos.distance_squared_to(epos) <= rad * rad:
				_on_player_hit()
				break


func _on_kill(epos: Vector2) -> void:
	streak += 1
	# Multiplier steps up every 5 kills in a no-hit streak, capped at x8.
	var new_mult: int = clamp(1 + streak / 5, 1, 8)
	if new_mult != multiplier:
		multiplier = new_mult
		mult_pulse = 1.0
	score += SCORE_PER_KILL * multiplier
	best = max(best, score)
	_spawn_particles(epos, Color(1, 1, 1), 18, 280.0)
	_spawn_particles(epos, MAGENTA, 10, 200.0)
	flash = max(flash, 0.35)
	shake = max(shake, 6.0)


func _on_player_hit() -> void:
	lives -= 1
	invuln = INVULN_TIME
	streak = 0
	multiplier = 1
	shake = max(shake, 22.0)
	hurt_flash = 1.0
	_spawn_particles(ppos, CYAN, 22, 320.0)
	if lives <= 0:
		lives = 0
		alive = false
		_spawn_particles(ppos, CYAN, 40, 420.0)
		shake = max(shake, 34.0)


# ============================================================
# Particles & juice
# ============================================================
func _spawn_particles(pos: Vector2, col: Color, count: int, speed: float) -> void:
	for i in range(count):
		var ang: float = randf() * TAU
		var spd: float = randf_range(speed * 0.3, speed)
		var life: float = randf_range(0.3, 0.7)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": life,
			"maxlife": life,
			"col": col,
			"size": randf_range(2.0, 5.0)
		})


func _update_particles(delta: float) -> void:
	var keep: Array = []
	for p in particles:
		var ppos2: Vector2 = p.pos
		var pvel2: Vector2 = p.vel
		ppos2 = ppos2 + pvel2 * delta
		pvel2 = pvel2 * (1.0 - clamp(3.0 * delta, 0.0, 1.0))   # drag
		p.pos = ppos2
		p.vel = pvel2
		p.life = float(p.life) - delta
		if float(p.life) > 0.0:
			keep.append(p)
	particles = keep
	# Trail decay.
	for tr in trail:
		tr.life = float(tr.life) - delta
	var keept: Array = []
	for tr in trail:
		if float(tr.life) > 0.0:
			keept.append(tr)
	trail = keept


func _update_juice(delta: float) -> void:
	shake = lerp(shake, 0.0, clamp(8.0 * delta, 0.0, 1.0))
	if shake < 0.05:
		shake = 0.0
	flash = max(flash - delta * 1.8, 0.0)
	hurt_flash = max(hurt_flash - delta * 1.6, 0.0)
	muzzle = max(muzzle - delta, 0.0)
	mult_pulse = max(mult_pulse - delta * 1.5, 0.0)


func _update_background(delta: float) -> void:
	# Grid scrolls opposite ship motion -> no dead space, sense of speed.
	grid_scroll -= pvel * delta * 0.5


# ============================================================
# Rendering — background -> halos -> entities -> particles -> flashes -> HUD
# ============================================================
func _draw() -> void:
	var sh: Vector2 = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	draw_set_transform(sh, 0.0, Vector2.ONE)
	_draw_background()
	_draw_bullets()
	_draw_enemies()
	_draw_player()
	_draw_particles()
	# Flashes (drawn in shaken space is fine).
	if flash > 0.0:
		draw_rect(Rect2(0, 0, screen_w, screen_h), Color(1, 1, 1, flash * 0.5))
	if hurt_flash > 0.0:
		_draw_edge_flash(hurt_flash)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()


func _draw_background() -> void:
	draw_rect(Rect2(0, 0, screen_w, screen_h), BG_COLOR)
	# Parallax starfield.
	for s in stars:
		var base: Vector2 = s.pos
		var z: float = s.z
		var sx: float = fposmod(base.x + grid_scroll.x * z * 0.15, screen_w)
		var sy: float = fposmod(base.y + grid_scroll.y * z * 0.15, screen_h)
		draw_circle(Vector2(sx, sy), z * 2.2, Color(0.55, 0.85, 1.0, z * 0.5))
	# Scrolling grid (counter to ship motion).
	var spacing: float = 80.0
	var gcol: Color = Color(0.12, 0.5, 0.6, 0.10)
	var ox: float = fposmod(grid_scroll.x, spacing)
	var oy: float = fposmod(grid_scroll.y, spacing)
	var x: float = ox
	while x < screen_w:
		draw_line(Vector2(x, 0), Vector2(x, screen_h), gcol, 1.0)
		x += spacing
	var y: float = oy
	while y < screen_h:
		draw_line(Vector2(0, y), Vector2(screen_w, y), gcol, 1.0)
		y += spacing


func _draw_bullets() -> void:
	for b in bullets:
		var bpos: Vector2 = b.pos
		var bvel: Vector2 = b.vel
		var dir: Vector2 = bvel.normalized()
		# Glow halo.
		draw_circle(bpos, BULLET_RADIUS * 2.4, Color(YELLOW.r, YELLOW.g, YELLOW.b, 0.18))
		# Capsule body: a short thick line + cap.
		var tail: Vector2 = bpos - dir * 10.0
		draw_line(tail, bpos, YELLOW, BULLET_RADIUS * 1.6)
		draw_circle(bpos, BULLET_RADIUS, YELLOW)


func _draw_enemies() -> void:
	for e in enemies:
		var epos: Vector2 = e.pos
		var spin: float = e.spin
		var maxhp: int = e.maxhp
		var hp: int = e.hp
		# Bigger / brighter enemies for higher hp.
		var scale: float = 1.0 + float(maxhp - 1) * 0.22
		var rad: float = ENEMY_RADIUS * scale
		var col: Color = MAGENTA
		if maxhp >= 3:
			col = Color(1.0, 0.35, 0.25)   # red for toughest
		# Glow halo.
		draw_circle(epos, rad * 1.7, Color(col.r, col.g, col.b, 0.16))
		# Angular diamond/star shape (4-point rotated).
		var pts: PackedVector2Array = PackedVector2Array()
		var spikes: int = 4
		for i in range(spikes * 2):
			var ang: float = spin + float(i) * PI / float(spikes)
			var r: float = rad if (i % 2 == 0) else rad * 0.5
			pts.append(epos + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, col)
		# HP pips for damaged multi-hp enemies.
		if maxhp > 1 and hp < maxhp:
			draw_arc(epos, rad + 5.0, -PI / 2.0, -PI / 2.0 + TAU * (float(hp) / float(maxhp)), 16, Color(1, 1, 1, 0.7), 2.0)


func _draw_player() -> void:
	# Blink during invuln.
	var visible: bool = true
	if invuln > 0.0:
		visible = fmod(invuln, 0.16) > 0.08
	if not visible:
		return
	var ang: float = paim.angle() + PI / 2.0   # ship points along aim (tip = aim dir)
	# Glow halo.
	draw_circle(ppos, PLAYER_RADIUS * 1.9, Color(CYAN.r, CYAN.g, CYAN.b, 0.18))
	# Thruster trail.
	for tr in trail:
		var tp: Vector2 = tr.pos
		var l: float = float(tr.life) / 0.32
		draw_circle(tp, 5.0 * l + 1.0, Color(0.4, 0.9, 1.0, 0.35 * l))
	# Triangular ship.
	var fwd: Vector2 = Vector2(cos(paim.angle()), sin(paim.angle()))
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = ppos + fwd * (PLAYER_RADIUS + 6.0)
	var bl: Vector2 = ppos - fwd * PLAYER_RADIUS + side * PLAYER_RADIUS
	var br: Vector2 = ppos - fwd * PLAYER_RADIUS - side * PLAYER_RADIUS
	var tri: PackedVector2Array = PackedVector2Array([tip, bl, br])
	draw_colored_polygon(tri, CYAN)
	# Cockpit accent.
	draw_circle(ppos + fwd * 4.0, 4.0, Color(1, 1, 1, 0.85))
	# Muzzle flash at nose.
	if muzzle > 0.0:
		var f: float = muzzle / 0.09
		draw_circle(tip, 10.0 * f + 3.0, Color(1.0, 1.0, 0.6, 0.8 * f))
	# avoid 'ang' unused warning by referencing it harmlessly
	ang = ang


func _draw_particles() -> void:
	for p in particles:
		var pp: Vector2 = p.pos
		var life: float = float(p.life)
		var maxlife: float = float(p.maxlife)
		var a: float = clamp(life / maxlife, 0.0, 1.0)
		var col: Color = p.col
		var sz: float = float(p.size) * a
		draw_circle(pp, sz, Color(col.r, col.g, col.b, a))


func _draw_edge_flash(amt: float) -> void:
	var thickness: float = 70.0
	var c: Color = Color(1.0, 0.2, 0.25, amt * 0.55)
	draw_rect(Rect2(0, 0, screen_w, thickness), c)
	draw_rect(Rect2(0, screen_h - thickness, screen_w, thickness), c)
	draw_rect(Rect2(0, 0, thickness, screen_h), c)
	draw_rect(Rect2(screen_w - thickness, 0, thickness, screen_h), c)


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# Lives (top-left) as ship pips.
	for i in range(lives):
		var cx: float = 40.0 + float(i) * 38.0
		draw_circle(Vector2(cx, 50.0), 12.0, CYAN)
	draw_string(font, Vector2(30, 110), "SCORE " + str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, CYAN)
	draw_string(font, Vector2(30, 150), "WAVE " + str(wave), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.6, 0.8, 0.85))
	# Streak multiplier (top-right), pulses when it ticks up.
	var mscale: float = 32.0 + mult_pulse * 22.0
	var mcol: Color = Color(YELLOW.r, YELLOW.g, YELLOW.b, 1.0).lerp(Color(1, 1, 1), mult_pulse)
	if multiplier > 1:
		draw_string(font, Vector2(screen_w - 230, 70), "x" + str(multiplier), HORIZONTAL_ALIGNMENT_RIGHT, 200, int(mscale), mcol)
		draw_string(font, Vector2(screen_w - 230, 105), "STREAK " + str(streak), HORIZONTAL_ALIGNMENT_RIGHT, 200, 22, Color(0.7, 0.7, 0.5))
	if not alive:
		draw_string(font, Vector2(0, screen_h * 0.46), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, screen_w, 56, Color(1, 0.4, 0.45))
		draw_string(font, Vector2(0, screen_h * 0.52), "SCORE " + str(score), HORIZONTAL_ALIGNMENT_CENTER, screen_w, 36, CYAN)
		draw_string(font, Vector2(0, screen_h * 0.58), "TAP TO RESTART", HORIZONTAL_ALIGNMENT_CENTER, screen_w, 34, Color(1, 1, 1))
