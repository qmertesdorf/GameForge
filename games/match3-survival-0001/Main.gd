extends Node2D

# ============================================================
# Aegis Grid (match3-survival-0001) — a match-3 / survival-defense HYBRID.
#
# A match-3 grid fills the LOWER screen. A battlefield strip ABOVE it shows an
# enemy line that advances in REAL TIME downward toward a wall at the grid's top
# edge. RED (attack) matches fire at the enemy line, damaging + pushing it back.
# BLUE (shield) matches repair wall HP. Combo chains charge a NOVA that clears
# the whole line when full. Loss = wall HP hits 0.
#
# Headless-safe: no physics, no scene instancing; all state owned here and
# rendered via _draw().
#
# Godot 4.6 strict-typing note: results of clamp/lerp/min/max and indexing
# untyped Array/Dictionary are Variant. Receiving vars are annotated explicitly
# (: float / : int / : Color) rather than relying on := inference.
# ============================================================

const VIEW_W := 720.0
const VIEW_H := 1280.0

# --- grid config ---
const COLS := 6
const ROWS := 7
const NUM_TYPES := 5
const EMPTY := -1

# gem type ids by role
const T_RED := 0      # attack
const T_BLUE := 1     # shield
# 2,3,4 are neutral fillers (green, amber, violet)

# board geometry (computed in _ready)
var cell_size := 0.0
var board_x := 0.0
var board_y := 0.0
const BOARD_MARGIN_X := 40.0
const BOARD_TOP := 560.0          # grid starts low; battlefield occupies above
const BOARD_BOTTOM_MARGIN := 60.0

# battlefield strip (above the grid, above the wall)
var field_top := 90.0             # below the HUD band
var field_bottom := 0.0           # = wall line (set from board geometry)
var wall_y := 0.0                 # the cyan wall sits at the grid's top edge

# --- palette ---
const COL_BG_TOP := Color(0.051, 0.043, 0.122)   # deep indigo #0d0b1f-ish
const COL_BG_BOT := Color(0.031, 0.024, 0.078)
const COL_BOARD := Color(0.10, 0.08, 0.20, 0.55)
const COL_CELL := Color(0.15, 0.12, 0.28, 0.40)
const COL_FIELD := Color(0.04, 0.03, 0.10, 0.85)
const COL_WHITE := Color(1, 1, 1)
const COL_WALL := Color(0.25, 0.92, 0.98)        # cyan wall
const COL_ENEMY := Color(0.98, 0.22, 0.78)       # magenta chevrons

# gem colors (red=attack, blue=shield, green, amber, violet)
var GEM_COLORS := [
	Color(0.98, 0.28, 0.30),   # 0 red    -> ATTACK (triangle)
	Color(0.30, 0.62, 0.99),   # 1 blue   -> SHIELD (square)
	Color(0.55, 0.92, 0.40),   # 2 green  (circle)
	Color(1.00, 0.74, 0.22),   # 3 amber  (diamond)
	Color(0.72, 0.45, 0.98),   # 4 violet (hexagon)
]

var rng := RandomNumberGenerator.new()

# --- board state ---
var board: Array = []          # board[r][c] = gem type 0..4, or EMPTY
var cell_offset: Array = []    # float fall offset (negative = above resting pos)
var cell_pop: Array = []       # float seconds remaining of pop scale animation
const POP_TIME := 0.28

# --- game state machine ---
enum State { IDLE, SWAPPING, RESOLVING, GAMEOVER }
var state: int = State.IDLE

# swap animation
var swap_a := Vector2i(-1, -1)
var swap_b := Vector2i(-1, -1)
var swap_t := 0.0
const SWAP_TIME := 0.16
var swap_back := false
var swap_pending_check := false

# resolve loop timing
var resolve_phase := 0          # 0=clearing(pop), 1=falling
var resolve_timer := 0.0
const CLEAR_TIME := 0.30
const FALL_TIME := 0.22
var combo := 0
var _pending_clear: Array = []

# --- selection / input ---
var selected := Vector2i(-1, -1)
var sel_pulse := 0.0
var drag_start_cell := Vector2i(-1, -1)
var drag_start_pos := Vector2.ZERO
var dragging := false

# ============================================================
# SURVIVAL-DEFENSE SYSTEM
# ============================================================
# The enemy line: a horizontal front that advances downward in real time. We
# model its position as a 0..1 "advance" value where 0 = far horizon (field_top)
# and 1 = the wall (field_bottom). It also has line HP; depleting line HP pushes
# the front back and spawns a tougher reinforcement row.
var enemy_advance := 0.0        # 0 (top) .. 1 (at wall)
var enemy_line_hp := 0.0
var enemy_line_max_hp := 0.0
var enemy_wave := 0             # reinforcement row index (toughness)
const ENEMY_BASE_HP := 60.0
const ENEMY_HP_STEP := 28.0     # per reinforcement wave

# advance speed in advance-units/sec; ramps over time, capped.
var advance_speed := 0.0
const ADVANCE_BASE := 0.030
const ADVANCE_STEP := 0.012     # added each ramp interval
const ADVANCE_CAP := 0.110
const RAMP_INTERVAL := 20.0

# wall
var wall_hp := 0.0
const WALL_MAX_HP := 100.0
var wall_breach_cooldown := 0.0 # seconds between breach damage ticks
const BREACH_DPS := 26.0        # wall HP lost per second while enemy at the wall

# offense / defense tuning
const RED_DAMAGE_PER_GEM := 9.0
const RED_PUSHBACK_PER_GEM := 0.020   # advance reduced per red gem matched
const BLUE_REPAIR_PER_GEM := 7.0
const COMBO_DAMAGE_MULT := 0.35       # extra fraction per combo level

# nova: charges from combos, fires automatically when full, clears the line
var nova_charge := 0.0          # 0..1
const NOVA_PER_GEM := 0.012     # base charge per matched gem
const NOVA_COMBO_BONUS := 0.030 # extra per combo level on a clear
var nova_flash := 0.0           # detonation sweep animation 1->0

# scoring
var score := 0
var enemies_destroyed := 0
var elapsed := 0.0

# --- juice ---
var shake_amt := 0.0
var shake_decay := 6.0
var flash_alpha := 0.0
var wall_pulse := 0.0           # cyan pulse along the wall on shield match
var line_hit_flash := 0.0       # enemy line hit flash 1->0
var tracers: Array = []         # attack tracer streaks {from, to, life, max_life, col}
var combo_pulse := 0.0
var combo_display := 0

# particle pool
var particles: Array = []

# bokeh ambient dots
var bokeh: Array = []

# game over
var game_over_t := 0.0

func _ready() -> void:
	rng.randomize()
	_compute_geometry()
	_init_bokeh()
	_new_game()

func _compute_geometry() -> void:
	var avail_w: float = VIEW_W - 2.0 * BOARD_MARGIN_X
	var avail_h: float = VIEW_H - BOARD_TOP - BOARD_BOTTOM_MARGIN
	cell_size = min(avail_w / float(COLS), avail_h / float(ROWS))
	var board_w: float = cell_size * float(COLS)
	var board_h: float = cell_size * float(ROWS)
	board_x = (VIEW_W - board_w) * 0.5
	board_y = BOARD_TOP + (avail_h - board_h) * 0.5
	# wall sits a bit above the grid's top edge
	wall_y = board_y - 18.0
	field_bottom = wall_y - 8.0

func _init_bokeh() -> void:
	bokeh.clear()
	for i in range(16):
		bokeh.append({
			"pos": Vector2(rng.randf() * VIEW_W, rng.randf() * VIEW_H),
			"r": rng.randf_range(14.0, 60.0),
			"spd": rng.randf_range(6.0, 22.0),
			"col": GEM_COLORS[rng.randi() % NUM_TYPES],
			"phase": rng.randf() * TAU,
		})

# ------------------------------------------------------------
# Game setup
# ------------------------------------------------------------
func _new_game() -> void:
	board = []
	cell_offset = []
	cell_pop = []
	for r in range(ROWS):
		var row: Array = []
		var orow: Array = []
		var prow: Array = []
		for c in range(COLS):
			row.append(EMPTY)
			orow.append(0.0)
			prow.append(0.0)
		board.append(row)
		cell_offset.append(orow)
		cell_pop.append(prow)
	_fill_board_no_matches()
	score = 0
	enemies_destroyed = 0
	combo = 0
	combo_display = 0
	elapsed = 0.0
	state = State.IDLE
	selected = Vector2i(-1, -1)
	particles.clear()
	tracers.clear()
	shake_amt = 0.0
	flash_alpha = 0.0
	combo_pulse = 0.0
	wall_pulse = 0.0
	line_hit_flash = 0.0
	nova_flash = 0.0
	game_over_t = 0.0

	# survival state
	wall_hp = WALL_MAX_HP
	enemy_advance = 0.0
	enemy_wave = 0
	enemy_line_max_hp = ENEMY_BASE_HP
	enemy_line_hp = enemy_line_max_hp
	advance_speed = ADVANCE_BASE
	wall_breach_cooldown = 0.0
	nova_charge = 0.0

func _fill_board_no_matches() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var t: int = _pick_safe_type(r, c)
			board[r][c] = t
			cell_offset[r][c] = 0.0
			cell_pop[r][c] = 0.0

func _pick_safe_type(r: int, c: int) -> int:
	var forbidden: Dictionary = {}
	if c >= 2 and board[r][c - 1] == board[r][c - 2] and board[r][c - 1] != EMPTY:
		forbidden[board[r][c - 1]] = true
	if r >= 2 and board[r - 1][c] == board[r - 2][c] and board[r - 1][c] != EMPTY:
		forbidden[board[r - 1][c]] = true
	var choices: Array = []
	for t in range(NUM_TYPES):
		if not forbidden.has(t):
			choices.append(t)
	if choices.is_empty():
		return rng.randi() % NUM_TYPES
	return int(choices[rng.randi() % choices.size()])

# ------------------------------------------------------------
# Main loop
# ------------------------------------------------------------
func _process(delta: float) -> void:
	_update(delta)
	queue_redraw()

func _update(delta: float) -> void:
	delta = min(delta, 0.05)
	sel_pulse += delta
	_update_bokeh(delta)
	_update_particles(delta)
	_update_tracers(delta)
	if shake_amt > 0.0:
		shake_amt = max(0.0, shake_amt - shake_decay * delta * shake_amt - 0.2 * delta)
	flash_alpha = max(0.0, flash_alpha - 3.5 * delta)
	combo_pulse = max(0.0, combo_pulse - 3.0 * delta)
	wall_pulse = max(0.0, wall_pulse - 2.5 * delta)
	line_hit_flash = max(0.0, line_hit_flash - 4.0 * delta)
	nova_flash = max(0.0, nova_flash - 1.6 * delta)

	match state:
		State.IDLE:
			_update_survival(delta)
		State.SWAPPING:
			_update_swap(delta)
			_update_survival(delta)
		State.RESOLVING:
			_update_resolve(delta)
			_update_survival(delta)
		State.GAMEOVER:
			game_over_t += delta

# The real-time advancing-threat system.
func _update_survival(delta: float) -> void:
	elapsed += delta
	# difficulty ramp: every RAMP_INTERVAL seconds advance speed steps up (capped)
	var step: int = int(elapsed / RAMP_INTERVAL)
	advance_speed = min(ADVANCE_CAP, ADVANCE_BASE + float(step) * ADVANCE_STEP)

	# advance the enemy line toward the wall
	enemy_advance += advance_speed * delta
	if enemy_advance >= 1.0:
		enemy_advance = 1.0
		# enemy is at the wall -> breach damage over time
		wall_hp -= BREACH_DPS * delta
		# steady tension feedback while breaching
		shake_amt = max(shake_amt, 2.0)
		if wall_hp <= 0.0:
			wall_hp = 0.0
			_trigger_game_over()

# Apply the outcome of a cleared match group by gem type.
func _apply_match_effects(matches: Array) -> void:
	var red_count := 0
	var blue_count := 0
	for cell in matches:
		var cc: int = cell.x
		var rr: int = cell.y
		var t: int = board[rr][cc]
		if t == T_RED:
			red_count += 1
		elif t == T_BLUE:
			blue_count += 1

	var combo_mult: float = 1.0 + COMBO_DAMAGE_MULT * float(max(0, combo - 1))

	# RED -> attack the enemy line (damage + pushback) with a tracer streak
	if red_count > 0:
		var dmg: float = float(red_count) * RED_DAMAGE_PER_GEM * combo_mult
		enemy_line_hp -= dmg
		var push: float = float(red_count) * RED_PUSHBACK_PER_GEM * combo_mult
		enemy_advance = max(0.0, enemy_advance - push)
		line_hit_flash = 1.0
		shake_amt = max(shake_amt, 3.0 + float(red_count))
		# tracers from the matched red cells up to the enemy line
		for cell in matches:
			if board[cell.y][cell.x] == T_RED:
				var src: Vector2 = _cell_center(cell.x, cell.y)
				var dst: Vector2 = Vector2(src.x, _enemy_line_y())
				tracers.append({
					"from": src, "to": dst, "life": 0.22, "max_life": 0.22,
					"col": GEM_COLORS[T_RED],
				})
		# line destroyed -> reinforcement wave (tougher), push the front back
		if enemy_line_hp <= 0.0:
			enemies_destroyed += 1
			score += 250
			_spawn_reinforcement(0.45)

	# BLUE -> repair the wall, cyan pulse along it
	if blue_count > 0:
		var repair: float = float(blue_count) * BLUE_REPAIR_PER_GEM * combo_mult
		wall_hp = min(WALL_MAX_HP, wall_hp + repair)
		wall_pulse = 1.0

	# nova charge from this clear (all matched gems contribute)
	var charge: float = float(matches.size()) * NOVA_PER_GEM
	charge += float(max(0, combo - 1)) * NOVA_COMBO_BONUS
	nova_charge = min(1.0, nova_charge + charge)
	if nova_charge >= 1.0:
		_fire_nova()

func _spawn_reinforcement(pushback: float) -> void:
	enemy_wave += 1
	enemy_advance = max(0.0, enemy_advance - pushback)
	enemy_line_max_hp = ENEMY_BASE_HP + float(enemy_wave) * ENEMY_HP_STEP
	enemy_line_hp = enemy_line_max_hp

func _fire_nova() -> void:
	# screen-clearing nova: destroy the current line, big pushback, reward beat
	nova_charge = 0.0
	nova_flash = 1.0
	flash_alpha = max(flash_alpha, 0.5)
	shake_amt = max(shake_amt, 12.0)
	enemies_destroyed += 1
	score += 400
	# fully reset the front to the horizon and bring in a fresh (tougher) wave
	_spawn_reinforcement(1.0)
	enemy_advance = 0.0

func _trigger_game_over() -> void:
	if state == State.GAMEOVER:
		return
	state = State.GAMEOVER
	shake_amt = 16.0
	flash_alpha = 0.6
	game_over_t = 0.0

# ------------------------------------------------------------
# Swap handling
# ------------------------------------------------------------
func _begin_swap(a: Vector2i, b: Vector2i, is_undo: bool) -> void:
	swap_a = a
	swap_b = b
	swap_t = 0.0
	swap_back = is_undo
	swap_pending_check = not is_undo
	state = State.SWAPPING

func _update_swap(delta: float) -> void:
	swap_t += delta
	if swap_t >= SWAP_TIME:
		var ta: int = board[swap_a.y][swap_a.x]
		var tb: int = board[swap_b.y][swap_b.x]
		board[swap_a.y][swap_a.x] = tb
		board[swap_b.y][swap_b.x] = ta
		if swap_pending_check:
			var matches: Array = _find_matches()
			if matches.is_empty():
				_begin_swap(swap_a, swap_b, true)
				shake_amt = max(shake_amt, 3.0)
			else:
				combo = 0
				state = State.RESOLVING
				_start_clear(matches)
		else:
			selected = Vector2i(-1, -1)
			state = State.IDLE
			swap_a = Vector2i(-1, -1)
			swap_b = Vector2i(-1, -1)

# ------------------------------------------------------------
# Match detection
# ------------------------------------------------------------
func _find_matches() -> Array:
	var matched: Dictionary = {}
	var result: Array = []
	# horizontal runs
	for r in range(ROWS):
		var run_start := 0
		while run_start < COLS:
			var t: int = board[r][run_start]
			var run_end := run_start
			if t != EMPTY:
				while run_end + 1 < COLS and board[r][run_end + 1] == t:
					run_end += 1
			if t != EMPTY and (run_end - run_start + 1) >= 3:
				for c in range(run_start, run_end + 1):
					var key: String = str(r) + "," + str(c)
					if not matched.has(key):
						matched[key] = true
						result.append(Vector2i(c, r))
			run_start = run_end + 1
	# vertical runs
	for c in range(COLS):
		var run_start := 0
		while run_start < ROWS:
			var t: int = board[run_start][c]
			var run_end := run_start
			if t != EMPTY:
				while run_end + 1 < ROWS and board[run_end + 1][c] == t:
					run_end += 1
			if t != EMPTY and (run_end - run_start + 1) >= 3:
				for r in range(run_start, run_end + 1):
					var key: String = str(r) + "," + str(c)
					if not matched.has(key):
						matched[key] = true
						result.append(Vector2i(c, r))
			run_start = run_end + 1
	return result

# ------------------------------------------------------------
# Resolve loop: clear -> fall/refill -> rescan
# ------------------------------------------------------------
func _start_clear(matches: Array) -> void:
	combo += 1
	var cleared: int = matches.size()
	score += cleared * 10 * combo

	# apply the survival/defense effects of this matched group BEFORE clearing
	# (needs the gem types still present in the board)
	_apply_match_effects(matches)

	# juice
	flash_alpha = max(flash_alpha, 0.30)
	shake_amt = max(shake_amt, 2.5 + float(combo) * 1.2)
	for cell in matches:
		var c: int = cell.x
		var r: int = cell.y
		cell_pop[r][c] = POP_TIME
		var pcol: Color = GEM_COLORS[board[r][c]] if board[r][c] != EMPTY else COL_WHITE
		_spawn_burst(_cell_center(c, r), pcol)

	if combo >= 2:
		combo_pulse = 1.0
		combo_display = combo

	resolve_phase = 0
	resolve_timer = CLEAR_TIME
	_pending_clear = matches.duplicate()

func _update_resolve(delta: float) -> void:
	resolve_timer -= delta
	for r in range(ROWS):
		for c in range(COLS):
			if cell_pop[r][c] > 0.0:
				cell_pop[r][c] = max(0.0, cell_pop[r][c] - delta)
			var off: float = cell_offset[r][c]
			if off != 0.0:
				off = lerp(off, 0.0, min(1.0, delta * 12.0))
				if abs(off) < 0.5:
					off = 0.0
				cell_offset[r][c] = off

	if resolve_timer > 0.0:
		return

	if resolve_phase == 0:
		for cell in _pending_clear:
			board[cell.y][cell.x] = EMPTY
		_pending_clear = []
		_apply_gravity_and_refill()
		resolve_phase = 1
		resolve_timer = FALL_TIME
	else:
		var more: Array = _find_matches()
		if more.is_empty():
			for r in range(ROWS):
				for c in range(COLS):
					cell_offset[r][c] = 0.0
			selected = Vector2i(-1, -1)
			swap_a = Vector2i(-1, -1)
			swap_b = Vector2i(-1, -1)
			state = State.IDLE
		else:
			_start_clear(more)

func _apply_gravity_and_refill() -> void:
	for c in range(COLS):
		var write_r := ROWS - 1
		for r in range(ROWS - 1, -1, -1):
			if board[r][c] != EMPTY:
				if write_r != r:
					board[write_r][c] = board[r][c]
					board[r][c] = EMPTY
					var prev_off: float = cell_offset[r][c]
					cell_offset[write_r][c] = float(write_r - r) * cell_size * -1.0 + prev_off
				write_r -= 1
		var spawn_index := 0
		for r in range(write_r, -1, -1):
			board[r][c] = rng.randi() % NUM_TYPES
			cell_offset[r][c] = -float(spawn_index + r + 2) * cell_size
			spawn_index += 1
			cell_pop[r][c] = 0.0

# ------------------------------------------------------------
# Particles & ambient
# ------------------------------------------------------------
func _spawn_burst(pos: Vector2, col: Color) -> void:
	var n := 8
	for i in range(n):
		var ang: float = rng.randf() * TAU
		var spd: float = rng.randf_range(80.0, 240.0)
		particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"life": rng.randf_range(0.3, 0.6),
			"max_life": 0.6,
			"col": col,
			"size": rng.randf_range(3.0, 7.0),
		})

func _update_particles(delta: float) -> void:
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0.0:
			particles.remove_at(i)
		else:
			p.vel *= (1.0 - 2.5 * delta)
			p.vel.y += 220.0 * delta
			p.pos += p.vel * delta
		i -= 1

func _update_tracers(delta: float) -> void:
	var i := tracers.size() - 1
	while i >= 0:
		var tr: Dictionary = tracers[i]
		tr.life -= delta
		if tr.life <= 0.0:
			tracers.remove_at(i)
		i -= 1

func _update_bokeh(delta: float) -> void:
	for b in bokeh:
		b.pos.y -= b.spd * delta
		b.phase += delta * 0.6
		if b.pos.y < -b.r:
			b.pos.y = VIEW_H + b.r
			b.pos.x = rng.randf() * VIEW_W

# ------------------------------------------------------------
# Input
# ------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if state == State.GAMEOVER:
		if (event is InputEventScreenTouch and event.pressed) or \
		   (event is InputEventMouseButton and event.pressed):
			_new_game()
		return

	var pos := Vector2.ZERO
	var is_down := false
	var is_up := false
	var is_move := false

	if event is InputEventScreenTouch:
		pos = event.position
		is_down = event.pressed
		is_up = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		is_down = event.pressed
		is_up = not event.pressed
	elif event is InputEventScreenDrag:
		pos = event.position
		is_move = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = event.position
		is_move = true
	else:
		return

	if state != State.IDLE:
		return

	if is_down:
		var cell := _pixel_to_cell(pos)
		if cell.x >= 0:
			drag_start_cell = cell
			drag_start_pos = pos
			dragging = true
			selected = cell
	elif is_move and dragging:
		var d := pos - drag_start_pos
		if d.length() > cell_size * 0.45:
			var dir := Vector2i.ZERO
			if abs(d.x) > abs(d.y):
				dir = Vector2i(1, 0) if d.x > 0 else Vector2i(-1, 0)
			else:
				dir = Vector2i(0, 1) if d.y > 0 else Vector2i(0, -1)
			var target := drag_start_cell + dir
			if _in_bounds(target):
				_begin_swap(drag_start_cell, target, false)
			dragging = false
			drag_start_cell = Vector2i(-1, -1)
	elif is_up:
		dragging = false

func _pixel_to_cell(pos: Vector2) -> Vector2i:
	var lx := pos.x - board_x
	var ly := pos.y - board_y
	if lx < 0.0 or ly < 0.0:
		return Vector2i(-1, -1)
	var c := int(lx / cell_size)
	var r := int(ly / cell_size)
	if c < 0 or c >= COLS or r < 0 or r >= ROWS:
		return Vector2i(-1, -1)
	return Vector2i(c, r)

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLS and cell.y >= 0 and cell.y < ROWS

# ------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------
func _cell_center(c: int, r: int) -> Vector2:
	return Vector2(board_x + (float(c) + 0.5) * cell_size,
		board_y + (float(r) + 0.5) * cell_size)

func _enemy_line_y() -> float:
	return lerp(field_top + 36.0, field_bottom, clamp(enemy_advance, 0.0, 1.0))

# ------------------------------------------------------------
# Rendering
# ------------------------------------------------------------
func _draw() -> void:
	var shake := Vector2.ZERO
	if shake_amt > 0.0:
		shake = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake_amt

	_draw_gradient_bg()
	_draw_bokeh()

	draw_set_transform(shake, 0.0, Vector2.ONE)

	# battlefield (behind/above the grid) then wall then grid
	_draw_battlefield()
	_draw_enemy_line()
	_draw_wall()
	_draw_tracers()
	_draw_board_panel()
	_draw_gems()
	_draw_particles()
	_draw_nova_sweep()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_hud()
	_draw_flash()

	if state == State.GAMEOVER:
		_draw_game_over()

func _draw_gradient_bg() -> void:
	var steps := 24
	for i in range(steps):
		var f: float = float(i) / float(steps - 1)
		var col: Color = COL_BG_TOP.lerp(COL_BG_BOT, f)
		var y: float = f * VIEW_H
		draw_rect(Rect2(0, y, VIEW_W, VIEW_H / float(steps) + 1.0), col)

func _draw_bokeh() -> void:
	for b in bokeh:
		var a: float = 0.05 + 0.03 * sin(b.phase)
		var col: Color = b.col
		col.a = max(0.02, a)
		draw_circle(b.pos, b.r, col)

# Battlefield strip with a faint receding hex/grid pattern toward a horizon.
func _draw_battlefield() -> void:
	var fx := BOARD_MARGIN_X
	var fw: float = VIEW_W - 2.0 * BOARD_MARGIN_X
	var fh: float = field_bottom - field_top
	draw_rect(Rect2(fx, field_top, fw, fh), COL_FIELD, true)
	# horizon glow line at the top of the field
	draw_rect(Rect2(fx, field_top, fw, 2.0), Color(0.5, 0.4, 0.9, 0.5), true)
	# receding perspective lines: verticals converging toward a vanishing point
	var vanish := Vector2(fx + fw * 0.5, field_top - 140.0)
	var n_lines := 7
	for i in range(n_lines + 1):
		var bx: float = fx + fw * float(i) / float(n_lines)
		var bottom := Vector2(bx, field_bottom)
		var topp: Vector2 = vanish.lerp(Vector2(bx, field_top), 0.85)
		draw_line(topp, bottom, Color(0.35, 0.30, 0.6, 0.18), 1.0)
	# horizontal depth bands (closer = brighter)
	var bands := 6
	for i in range(bands):
		var f: float = float(i) / float(bands - 1)
		var y: float = lerp(field_top + 6.0, field_bottom - 4.0, f)
		var a: float = 0.05 + 0.10 * f
		draw_line(Vector2(fx, y), Vector2(fx + fw, y), Color(0.4, 0.35, 0.7, a), 1.0)

# The enemy line: a row of angular magenta chevrons at the advancing front.
func _draw_enemy_line() -> void:
	var fx := BOARD_MARGIN_X
	var fw: float = VIEW_W - 2.0 * BOARD_MARGIN_X
	var y: float = _enemy_line_y()
	var n := COLS + 1
	# danger tint as it nears the wall
	var prox: float = clamp(enemy_advance, 0.0, 1.0)
	var base: Color = COL_ENEMY.lerp(Color(1.0, 0.15, 0.25), prox)
	var hitc: Color = base.lerp(COL_WHITE, line_hit_flash)
	var chev_w: float = fw / float(n)
	var ch: float = clamp(chev_w * 0.5, 10.0, 26.0)
	for i in range(n):
		var cx: float = fx + chev_w * (float(i) + 0.5)
		# glow halo behind
		draw_circle(Vector2(cx, y), ch * 1.4, Color(base.r, base.g, base.b, 0.18))
		# downward-pointing chevron
		var pts := PackedVector2Array([
			Vector2(cx - ch, y - ch * 0.6),
			Vector2(cx, y + ch * 0.7),
			Vector2(cx + ch, y - ch * 0.6),
			Vector2(cx + ch, y - ch * 0.1),
			Vector2(cx, y + ch * 1.15),
			Vector2(cx - ch, y - ch * 0.1),
		])
		draw_colored_polygon(pts, hitc)
	# line-HP bar riding just above the front
	var hp_frac: float = clamp(enemy_line_hp / max(1.0, enemy_line_max_hp), 0.0, 1.0)
	var hbw: float = fw * 0.7
	var hbx: float = fx + (fw - hbw) * 0.5
	var hby: float = y - ch - 14.0
	draw_rect(Rect2(hbx, hby, hbw, 6.0), Color(0, 0, 0, 0.4), true)
	draw_rect(Rect2(hbx, hby, hbw * hp_frac, 6.0), base, true)

# Cyan wall across the grid's top edge; brightness + thickness track HP.
func _draw_wall() -> void:
	var fx := BOARD_MARGIN_X
	var fw: float = VIEW_W - 2.0 * BOARD_MARGIN_X
	var hp_frac: float = clamp(wall_hp / WALL_MAX_HP, 0.0, 1.0)
	var thick: float = lerp(5.0, 16.0, hp_frac)
	var bright: float = lerp(0.35, 1.0, hp_frac)
	var wc := Color(COL_WALL.r * bright, COL_WALL.g * bright, COL_WALL.b * bright, 1.0)
	# pulse on shield repair
	if wall_pulse > 0.0:
		var pa: float = wall_pulse * 0.5
		draw_rect(Rect2(fx - 6, wall_y - thick - 6, fw + 12, thick + 12),
			Color(COL_WALL.r, COL_WALL.g, COL_WALL.b, pa), true)
	# glow halo
	draw_rect(Rect2(fx, wall_y - thick - 4.0, fw, thick + 8.0),
		Color(wc.r, wc.g, wc.b, 0.25), true)
	draw_rect(Rect2(fx, wall_y - thick, fw, thick), wc, true)

func _draw_tracers() -> void:
	for tr in tracers:
		var a: float = clamp(tr.life / tr.max_life, 0.0, 1.0)
		var col: Color = tr.col
		col.a = a
		draw_line(tr.from, tr.to, Color(col.r, col.g, col.b, a * 0.4), 7.0)
		draw_line(tr.from, tr.to, Color(1, 1, 1, a), 2.0)
		# hit flash at the enemy end
		draw_circle(tr.to, 10.0 * a, Color(1, 1, 1, a * 0.8))

func _draw_board_panel() -> void:
	var w: float = cell_size * float(COLS)
	var h: float = cell_size * float(ROWS)
	var pad := 10.0
	draw_rect(Rect2(board_x - pad, board_y - pad, w + 2 * pad, h + 2 * pad), COL_BOARD, true)
	for r in range(ROWS):
		for c in range(COLS):
			var p := Vector2(board_x + c * cell_size, board_y + r * cell_size)
			draw_rect(Rect2(p.x + 3, p.y + 3, cell_size - 6, cell_size - 6), COL_CELL, true)

func _draw_gems() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var t: int = board[r][c]
			if t == EMPTY:
				continue
			var center := _cell_center(c, r)
			center += _swap_visual_offset(c, r)
			center.y += cell_offset[r][c]

			var scale := 1.0
			var pop: float = cell_pop[r][c]
			if pop > 0.0:
				var pf: float = pop / POP_TIME
				scale = 1.0 + (1.0 - pf) * 0.6

			if selected == Vector2i(c, r) and state == State.IDLE:
				scale *= 1.0 + 0.10 * sin(sel_pulse * 9.0)

			var radius: float = cell_size * 0.36 * scale
			var col: Color = GEM_COLORS[t]

			var step: float = radius * 0.32
			for i in range(4):
				var hc := Color(col.r, col.g, col.b, 0.12 - i * 0.025)
				if hc.a > 0.0:
					draw_circle(center, radius + float(i) * step, hc)

			_draw_gem_shape(t, center, radius, col)

			# inner highlight so colors read instantly
			draw_circle(center - Vector2(radius * 0.28, radius * 0.28), radius * 0.18,
				Color(1, 1, 1, 0.35))

			if pop > 0.0:
				var fa: float = (pop / POP_TIME) * 0.8
				draw_circle(center, radius * 0.8, Color(1, 1, 1, fa))

func _draw_gem_shape(t: int, center: Vector2, radius: float, col: Color) -> void:
	match t:
		0:
			# red ATTACK -> upward triangle (reads as a fired bolt)
			var pts := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.9, radius * 0.7),
				center + Vector2(-radius * 0.9, radius * 0.7),
			])
			draw_colored_polygon(pts, col)
		1:
			# blue SHIELD -> rounded square
			var s: float = radius * 1.5
			draw_rect(Rect2(center.x - s * 0.5, center.y - s * 0.5, s, s), col, true)
		2:
			# green -> circle
			draw_circle(center, radius, col)
			draw_arc(center, radius, 0, TAU, 32, Color(1, 1, 1, 0.30), 2.0)
		3:
			# amber -> diamond
			var pts2 := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius, 0),
			])
			draw_colored_polygon(pts2, col)
		4:
			# violet -> hexagon
			var pts3 := PackedVector2Array()
			for i in range(6):
				var a: float = PI / 6.0 + float(i) * (TAU / 6.0)
				pts3.append(center + Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(pts3, col)

func _swap_visual_offset(c: int, r: int) -> Vector2:
	if state != State.SWAPPING:
		return Vector2.ZERO
	var cell := Vector2i(c, r)
	var f: float = clamp(swap_t / SWAP_TIME, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	if cell == swap_a:
		var dest := _cell_center(swap_b.x, swap_b.y)
		var src := _cell_center(swap_a.x, swap_a.y)
		return (dest - src) * f
	elif cell == swap_b:
		var dest2 := _cell_center(swap_a.x, swap_a.y)
		var src2 := _cell_center(swap_b.x, swap_b.y)
		return (dest2 - src2) * f
	return Vector2.ZERO

func _draw_particles() -> void:
	for p in particles:
		var a: float = clamp(p.life / p.max_life, 0.0, 1.0)
		var col: Color = p.col
		col.a = a
		draw_circle(p.pos, p.size * a, col)

func _draw_nova_sweep() -> void:
	if nova_flash <= 0.0:
		return
	# a full-width white sweep over the battlefield when nova fires
	var a: float = nova_flash * 0.7
	draw_rect(Rect2(0, field_top, VIEW_W, field_bottom - field_top),
		Color(1, 1, 1, a * 0.6), true)
	var sweep_y: float = lerp(field_bottom, field_top, nova_flash)
	draw_rect(Rect2(0, sweep_y - 8.0, VIEW_W, 16.0), Color(1, 1, 1, a), true)

func _draw_flash() -> void:
	if flash_alpha > 0.0:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(1, 1, 1, flash_alpha * 0.35))

# ------------------------------------------------------------
# HUD
# ------------------------------------------------------------
func _get_font() -> Font:
	if ThemeDB and ThemeDB.fallback_font:
		return ThemeDB.fallback_font
	return null

func _draw_text(font: Font, pos: Vector2, txt: String, size: int, col: Color) -> void:
	if font == null:
		return
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_hud() -> void:
	var font := _get_font()

	# WALL HP readout (top-left)
	var wall_frac: float = clamp(wall_hp / WALL_MAX_HP, 0.0, 1.0)
	_draw_text(font, Vector2(34, 40), "WALL", 22, Color(1, 1, 1, 0.6))
	var wcol := Color(0.95, 0.25, 0.25)
	if wall_frac > 0.5:
		wcol = COL_WALL
	elif wall_frac > 0.25:
		wcol = Color(1.0, 0.74, 0.22)
	_draw_text(font, Vector2(34, 78), str(int(round(wall_hp))), 38, wcol)
	# small wall-hp bar under it
	var wbx := 34.0
	var wby := 86.0
	var wbw := 200.0
	draw_rect(Rect2(wbx, wby, wbw, 8.0), Color(0, 0, 0, 0.4), true)
	draw_rect(Rect2(wbx, wby, wbw * wall_frac, 8.0), wcol, true)

	# NOVA charge readout (top-right) with a pulsing ring
	_draw_text(font, Vector2(VIEW_W - 150, 40), "NOVA", 22, Color(1, 1, 1, 0.6))
	var nbx := VIEW_W - 234.0
	var nby := 86.0
	var nbw := 200.0
	draw_rect(Rect2(nbx, nby, nbw, 8.0), Color(0, 0, 0, 0.4), true)
	var ncol := Color(0.9, 0.85, 1.0)
	draw_rect(Rect2(nbx, nby, nbw * nova_charge, 8.0), ncol, true)
	# pulsing ring as it charges
	var ring_c := Vector2(VIEW_W - 50, 52)
	var ring_r: float = 16.0 + 3.0 * sin(sel_pulse * 6.0) * nova_charge
	var ra: float = 0.3 + 0.6 * nova_charge
	draw_arc(ring_c, ring_r, 0, TAU * nova_charge, 28, Color(1, 1, 1, ra), 3.0)

	# SCORE (top-center)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 60, 40), "SCORE", 20, Color(1, 1, 1, 0.5))
	_draw_text(font, Vector2(VIEW_W * 0.5 - 50, 78), str(score), 30, COL_WHITE)

	# combo pulse near the grid when active
	if combo_pulse > 0.0 and combo_display >= 2:
		var pscale: float = 1.0 + combo_pulse * 0.6
		var size: int = int(40 * pscale)
		var ccol: Color = GEM_COLORS[combo_display % NUM_TYPES]
		ccol.a = clamp(combo_pulse + 0.3, 0.0, 1.0)
		_draw_text(font, Vector2(VIEW_W * 0.5 - 90, board_y - 40.0),
			"x" + str(combo_display) + " COMBO", size, ccol)

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.0, 0.0, 0.05, 0.65))
	var font := _get_font()
	var pulse: float = 1.0 + 0.05 * sin(game_over_t * 4.0)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 160, VIEW_H * 0.42), "WALL BREACHED", int(48 * pulse), Color(1, 0.3, 0.35))
	_draw_text(font, Vector2(VIEW_W * 0.5 - 120, VIEW_H * 0.42 + 70), "Score: " + str(score), 34, COL_WALL)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 150, VIEW_H * 0.42 + 120), "Enemies destroyed: " + str(enemies_destroyed), 24, Color(0.98, 0.5, 0.8))
	if sin(game_over_t * 3.0) > -0.3:
		_draw_text(font, Vector2(VIEW_W * 0.5 - 140, VIEW_H * 0.42 + 190), "Tap to defend again", 28, Color(1, 1, 1, 0.8))
