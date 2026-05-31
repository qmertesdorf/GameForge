extends Node2D

# ============================================================
# Aegis Grid III (match3-survival-0003) — match-3 / survival FUSION.
#
# THE FUSION (the run-004/005 fix): the survival threat is a BOARD STATE, not an
# off-board entity. "Blight" is a per-cell flag riding ON TOP of the gem grid.
# A blighted gem can ONLY be removed by including it in a 3+ match — so every swap
# is simultaneously a PUZZLE move (clear colors, chain combos for score) AND a
# DEFENSE move (purge blight before it spreads). There is no separate defense
# minigame; the same single action resolves both subsystems at once.
#
# SHARED-RESOURCE TENSION: the contested resource is the player's swap each tick.
# Spending it on a big same-color combo (points) costs a purge of advancing blight,
# and vice-versa. The triage between scoring and purging IS the game.
#
# CONCURRENCY CONTRACT (deliberate, tuned): the threat is reconciled to PUZZLE
# CADENCE, not a separate real-time clock — blight spreads exactly one step per
# tick (~3.5s), and the tick advances in IDLE, SWAPPING and RESOLVING. It never
# pauses for the player's discrete actions (you can't freeze the rot by dragging),
# but it also never runs on its own faster clock, so the two genres share one beat
# instead of feeling like two clocks. Difficulty ramps by SHORTENING the tick
# toward a floor.
#
# FORCING FUNCTION: a telegraphed SURGE every ~20s (board-edge amber glow + a
# shrinking countdown ring) makes the next tick spread blight TWICE — a tension
# spike layered on top of the steady continuous pressure (shared-space coupling
# first, telegraph spike second, per the skill's hybrid guidance).
#
# LOSS: per-column wall segments at the grid bottom. When blight occupies a
# column's bottom cell on a tick, that column's wall segment cracks (loses HP).
# When all 7 segments are destroyed -> game over, tap to restart.
#
# SALIENCE: the cross-subsystem causal link is loud:
#   - blighted gems are charcoal with a pulsing magenta rim + thin Line2D tendrils
#     reaching toward the neighbor they will infect NEXT,
#   - purging a blight fires a white cleansing flash + tracer that radiates from
#     the cleared cell, and the "BLIGHT" counter visibly drops,
#   - a column breach fractures that wall segment with jagged cracks + red flash
#     + screen shake.
#
# Headless-safe: no physics, no scene instancing; all state owned here and drawn
# via _draw(). selftest.gd drives this script's state directly.
#
# Godot 4.6 strict typing: clamp/lerp/min/max/abs and indexing untyped Array/
# Dictionary return Variant. Every receiving var is annotated explicitly
# (: float / : int / : Color) rather than relying on := inference.
# ============================================================

const VIEW_W := 720.0
const VIEW_H := 1280.0

# --- grid config ---
const COLS := 7
const ROWS := 8
const NUM_TYPES := 5
const EMPTY := -1

# board geometry (computed in _ready)
var cell_size := 0.0
var board_x := 0.0
var board_y := 0.0
const BOARD_MARGIN_X := 32.0
const BOARD_TOP := 300.0
const BOARD_BOTTOM_MARGIN := 150.0

var wall_y := 0.0   # y of the wall bar (just below the grid)

# --- palette: bioluminescent reef on deep navy ---
const COL_BG_TOP := Color(0.039, 0.055, 0.114)
const COL_BG_BOT := Color(0.012, 0.020, 0.043)
const COL_BOARD := Color(0.07, 0.10, 0.18, 0.55)
const COL_CELL := Color(0.11, 0.16, 0.26, 0.40)
const COL_WHITE := Color(1, 1, 1)
const COL_WALL := Color(0.25, 0.92, 0.98)        # cyan wall
const COL_ROT := Color(0.93, 0.16, 0.62)         # magenta-rot blight rim
const COL_CHARCOAL := Color(0.16, 0.15, 0.18)    # blighted gem body
const COL_SURGE := Color(1.0, 0.66, 0.18)        # amber surge telegraph

var GEM_COLORS := [
	Color(0.99, 0.42, 0.38),   # 0 coral  (triangle)
	Color(0.24, 0.84, 0.82),   # 1 teal   (square)
	Color(1.00, 0.78, 0.26),   # 2 amber  (diamond)
	Color(0.70, 0.45, 0.98),   # 3 violet (hexagon)
	Color(0.62, 0.92, 0.38),   # 4 lime   (circle)
]

var rng := RandomNumberGenerator.new()

# --- board state ---
var board: Array = []          # gem type per cell
var blight: Array = []         # bool per cell: is this cell corrupted?
var cell_offset: Array = []    # fall animation y-offset
var cell_pop: Array = []       # clear-pop timer
const POP_TIME := 0.28

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
var resolve_phase := 0
var resolve_timer := 0.0
const CLEAR_TIME := 0.28
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
# BLIGHT / SURVIVAL SYSTEM  (lives ON the board)
# ============================================================
# Blight ticks on the PUZZLE cadence (not a separate real-time clock). Each tick:
#   1. if a surge is armed, this tick spreads TWICE; else once,
#   2. each existing blighted cell tries to infect ONE adjacent (down-biased)
#      non-blighted gem,
#   3. a fresh blight SEED is added on the top row,
#   4. any column whose BOTTOM cell is blighted cracks that column's wall segment.
var blight_timer := 0.0
const TICK_BASE := 3.5         # seconds per blight tick at the start
const TICK_MIN := 1.6          # floor (fastest)
const TICK_STEP := 0.30        # shortened per ramp interval
const RAMP_INTERVAL := 22.0    # seconds between difficulty steps
var tick_interval := TICK_BASE

# per-column wall segments
var wall_seg_hp: Array = []        # float HP per column
const WALL_SEG_MAX := 3.0          # hits a segment takes before it's destroyed
const BREACH_HIT := 1.0            # HP a bottom-row blight removes from its segment per tick
var segments_alive := 0

# ---- FORCING FUNCTION: telegraphed surge ----
enum Surge { IDLE, ARMED }
var surge_state: int = Surge.IDLE
var surge_cooldown := 0.0          # seconds until the next surge telegraph begins
var surge_charge := 0.0            # 0..1 charge of the telegraph ring (fills toward fire)
const SURGE_INTERVAL := 20.0       # seconds between surges
const SURGE_TELEGRAPH := 4.0       # how long the telegraph charges before it fires
var surge_pending := false         # true => the NEXT blight tick spreads twice
var surge_flash := 0.0             # board-edge amber pulse intensity 1->0

# scoring
var score := 0
var blight_purged := 0
var max_combo := 0
var elapsed := 0.0

# --- juice ---
var shake_amt := 0.0
var shake_decay := 6.0
var flash_alpha := 0.0
var flash_col := Color(1, 1, 1)
var combo_pulse := 0.0
var combo_display := 0
var score_pop := 0.0
var blight_count_pop := 0.0
var cleanse_pulses: Array = []     # white radiating rings where blight was purged
var tracers: Array = []            # match -> threat tracers
var particles: Array = []
var plankton: Array = []
var game_over_t := 0.0
var seg_break_flash: Array = []    # per-column white crack flash 1->0

func _ready() -> void:
	rng.randomize()
	_compute_geometry()
	_init_plankton()
	_new_game()

func _compute_geometry() -> void:
	var avail_w: float = VIEW_W - 2.0 * BOARD_MARGIN_X
	var avail_h: float = VIEW_H - BOARD_TOP - BOARD_BOTTOM_MARGIN
	cell_size = min(avail_w / float(COLS), avail_h / float(ROWS))
	var board_w: float = cell_size * float(COLS)
	var board_h: float = cell_size * float(ROWS)
	board_x = (VIEW_W - board_w) * 0.5
	board_y = BOARD_TOP
	wall_y = board_y + board_h + 14.0

func _init_plankton() -> void:
	plankton.clear()
	for i in range(22):
		plankton.append({
			"pos": Vector2(rng.randf() * VIEW_W, rng.randf() * VIEW_H),
			"r": rng.randf_range(2.0, 6.0),
			"spd": rng.randf_range(8.0, 26.0),
			"col": GEM_COLORS[rng.randi() % NUM_TYPES],
			"phase": rng.randf() * TAU,
		})

# ------------------------------------------------------------
# Game setup
# ------------------------------------------------------------
func _new_game() -> void:
	board = []
	blight = []
	cell_offset = []
	cell_pop = []
	for r in range(ROWS):
		var row: Array = []
		var brow: Array = []
		var orow: Array = []
		var prow: Array = []
		for c in range(COLS):
			row.append(EMPTY)
			brow.append(false)
			orow.append(0.0)
			prow.append(0.0)
		board.append(row)
		blight.append(brow)
		cell_offset.append(orow)
		cell_pop.append(prow)
	_fill_board_no_matches()

	score = 0
	blight_purged = 0
	max_combo = 0
	combo = 0
	combo_display = 0
	elapsed = 0.0
	state = State.IDLE
	selected = Vector2i(-1, -1)
	particles.clear()
	tracers.clear()
	cleanse_pulses.clear()
	shake_amt = 0.0
	flash_alpha = 0.0
	combo_pulse = 0.0
	score_pop = 0.0
	blight_count_pop = 0.0
	game_over_t = 0.0

	# blight / survival state
	blight_timer = TICK_BASE
	tick_interval = TICK_BASE

	wall_seg_hp = []
	seg_break_flash = []
	for c in range(COLS):
		wall_seg_hp.append(WALL_SEG_MAX)
		seg_break_flash.append(0.0)
	segments_alive = COLS

	# surge / forcing-function state
	surge_state = Surge.IDLE
	surge_cooldown = SURGE_INTERVAL
	surge_charge = 0.0
	surge_pending = false
	surge_flash = 0.0

func _fill_board_no_matches() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var t: int = _pick_safe_type(r, c)
			board[r][c] = t
			blight[r][c] = false
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
	_update_plankton(delta)
	_update_particles(delta)
	_update_tracers(delta)
	_update_cleanse(delta)
	if shake_amt > 0.0:
		shake_amt = max(0.0, shake_amt - shake_decay * delta * shake_amt - 0.2 * delta)
	flash_alpha = max(0.0, flash_alpha - 3.0 * delta)
	combo_pulse = max(0.0, combo_pulse - 3.0 * delta)
	score_pop = max(0.0, score_pop - 3.0 * delta)
	blight_count_pop = max(0.0, blight_count_pop - 3.0 * delta)
	surge_flash = max(0.0, surge_flash - 1.5 * delta)
	for c in range(COLS):
		seg_break_flash[c] = max(0.0, seg_break_flash[c] - 2.5 * delta)

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

# The blight clock + the surge forcing function.
# CONCURRENCY CONTRACT: runs in IDLE, SWAPPING and RESOLVING — it never pauses for
# the player's discrete actions, but it is the SAME single clock the puzzle beats
# to (one spread per tick), so the genres share one beat.
func _update_survival(delta: float) -> void:
	elapsed += delta
	var step: int = int(elapsed / RAMP_INTERVAL)
	tick_interval = max(TICK_MIN, TICK_BASE - float(step) * TICK_STEP)

	_update_surge(delta)

	blight_timer -= delta
	if blight_timer <= 0.0:
		blight_timer += tick_interval
		_blight_tick()

# Surge telegraph state machine (the forcing function).
func _update_surge(delta: float) -> void:
	if surge_state == Surge.IDLE:
		surge_cooldown -= delta
		if surge_cooldown <= 0.0:
			surge_state = Surge.ARMED
			surge_charge = 0.0
	else:  # ARMED — the telegraph ring fills; when full the next tick doubles.
		surge_charge = min(1.0, surge_charge + delta / SURGE_TELEGRAPH)
		surge_flash = max(surge_flash, 0.4 + 0.4 * surge_charge)
		if surge_charge >= 1.0:
			surge_state = Surge.IDLE
			surge_cooldown = SURGE_INTERVAL
			surge_pending = true     # the very next blight tick spreads twice
			surge_flash = 1.0

# One blight tick on the puzzle cadence: spread (twice if a surge armed) + seed +
# breach check.
func _blight_tick() -> void:
	if state == State.GAMEOVER:
		return
	var spreads: int = 2 if surge_pending else 1
	surge_pending = false
	for s in range(spreads):
		_spread_blight_once()
	_seed_blight()
	_check_breaches()

# Each currently-blighted cell tries to infect ONE adjacent non-blighted gem.
# Down-biased so the rot advances toward the wall. Computed from a SNAPSHOT so a
# freshly-infected cell does not chain within the same tick.
func _spread_blight_once() -> void:
	var sources: Array = []
	for r in range(ROWS):
		for c in range(COLS):
			if blight[r][c] and board[r][c] != EMPTY:
				sources.append(Vector2i(c, r))
	for src in sources:
		var c: int = src.x
		var r: int = src.y
		# preference order: down, then sideways, then up
		var dirs: Array = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
		var targets: Array = []
		for d in dirs:
			var nc: int = c + d.x
			var nr: int = r + d.y
			if nc >= 0 and nc < COLS and nr >= 0 and nr < ROWS:
				if not blight[nr][nc] and board[nr][nc] != EMPTY:
					targets.append(Vector2i(nc, nr))
		if targets.is_empty():
			continue
		# down has priority; otherwise pick the first available preferred dir
		var pick: Vector2i = targets[0]
		blight[pick.y][pick.x] = true

# Add a fresh blight seed somewhere on the top row (a clean cell if possible).
func _seed_blight() -> void:
	var open: Array = []
	for c in range(COLS):
		if not blight[0][c] and board[0][c] != EMPTY:
			open.append(c)
	if open.is_empty():
		return
	var c: int = int(open[rng.randi() % open.size()])
	blight[0][c] = true

# Any column whose BOTTOM cell is blighted on this tick cracks that wall segment.
func _check_breaches() -> void:
	var br: int = ROWS - 1
	for c in range(COLS):
		if wall_seg_hp[c] <= 0.0:
			continue
		if blight[br][c] and board[br][c] != EMPTY:
			var before: float = wall_seg_hp[c]
			wall_seg_hp[c] = max(0.0, wall_seg_hp[c] - BREACH_HIT)
			seg_break_flash[c] = 1.0
			shake_amt = max(shake_amt, 5.0)
			flash_col = COL_ROT
			flash_alpha = max(flash_alpha, 0.30)
			if before > 0.0 and wall_seg_hp[c] <= 0.0:
				# segment destroyed
				segments_alive -= 1
				shake_amt = max(shake_amt, 12.0)
				flash_alpha = max(flash_alpha, 0.55)
				if segments_alive <= 0:
					_game_over()

func _game_over() -> void:
	if state == State.GAMEOVER:
		return
	state = State.GAMEOVER
	shake_amt = 16.0
	flash_col = COL_ROT
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
		# swap both gem type AND blight flag so corruption travels with the gem
		var ta: int = board[swap_a.y][swap_a.x]
		var tb: int = board[swap_b.y][swap_b.x]
		board[swap_a.y][swap_a.x] = tb
		board[swap_b.y][swap_b.x] = ta
		var ba: bool = blight[swap_a.y][swap_a.x]
		var bb: bool = blight[swap_b.y][swap_b.x]
		blight[swap_a.y][swap_a.x] = bb
		blight[swap_b.y][swap_b.x] = ba
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
	if combo > max_combo:
		max_combo = combo
	var cleared: int = matches.size()
	score += cleared * 10 * combo
	score_pop = 1.0

	# THE FUSION: count blighted cells inside this match BEFORE clearing — those
	# are purged. One action serves both genres at once.
	var purged: int = _apply_match_purge(matches)

	flash_col = COL_WHITE
	flash_alpha = max(flash_alpha, 0.22 if purged == 0 else 0.40)
	shake_amt = max(shake_amt, 2.5 + float(combo) * 1.0)
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

# Purge any blight in the matched group. Returns how many cells were purged.
# Fires the SALIENT cleanse feedback (white radiating ring + tracer + counter pop).
func _apply_match_purge(matches: Array) -> int:
	var purged := 0
	for cell in matches:
		var c: int = cell.x
		var r: int = cell.y
		if blight[r][c]:
			blight[r][c] = false
			purged += 1
			var center: Vector2 = _cell_center(c, r)
			cleanse_pulses.append({"pos": center, "life": 0.45, "max_life": 0.45})
			_spawn_burst(center, COL_WHITE)
	if purged > 0:
		blight_purged += purged
		blight_count_pop = 1.0
		score += purged * 50 * combo          # purging is worth more than plain clears
		flash_col = COL_WHITE
		shake_amt = max(shake_amt, 3.0 + float(purged))
	return purged

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
			blight[cell.y][cell.x] = false
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
					blight[write_r][c] = blight[r][c]
					board[r][c] = EMPTY
					blight[r][c] = false
					var prev_off: float = cell_offset[r][c]
					cell_offset[write_r][c] = float(write_r - r) * cell_size * -1.0 + prev_off
				write_r -= 1
		var spawn_index := 0
		for r in range(write_r, -1, -1):
			board[r][c] = rng.randi() % NUM_TYPES
			blight[r][c] = false       # refilled gems are always clean
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
		var spd: float = rng.randf_range(70.0, 220.0)
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
			p.vel.y += 200.0 * delta
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

func _update_cleanse(delta: float) -> void:
	var i := cleanse_pulses.size() - 1
	while i >= 0:
		var cp: Dictionary = cleanse_pulses[i]
		cp.life -= delta
		if cp.life <= 0.0:
			cleanse_pulses.remove_at(i)
		i -= 1

func _update_plankton(delta: float) -> void:
	for b in plankton:
		b.pos.y -= b.spd * delta
		b.phase += delta * 0.8
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

# ------------------------------------------------------------
# Rendering
# ------------------------------------------------------------
func _draw() -> void:
	var shake := Vector2.ZERO
	if shake_amt > 0.0:
		shake = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake_amt

	_draw_gradient_bg()
	_draw_plankton()

	draw_set_transform(shake, 0.0, Vector2.ONE)

	_draw_board_panel()
	_draw_tendrils()
	_draw_gems()
	_draw_cleanse()
	_draw_particles()
	_draw_tracers()
	_draw_wall()
	_draw_surge_edges()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_hud()
	_draw_flash()

	if state == State.GAMEOVER:
		_draw_game_over()

func _draw_gradient_bg() -> void:
	var steps := 26
	for i in range(steps):
		var f: float = float(i) / float(steps - 1)
		var col: Color = COL_BG_TOP.lerp(COL_BG_BOT, f)
		var y: float = f * VIEW_H
		draw_rect(Rect2(0, y, VIEW_W, VIEW_H / float(steps) + 1.0), col)

func _draw_plankton() -> void:
	for b in plankton:
		var a: float = 0.10 + 0.10 * sin(b.phase)
		var col: Color = b.col
		col.a = max(0.04, a)
		draw_circle(b.pos, b.r + 1.5, Color(col.r, col.g, col.b, col.a * 0.4))
		draw_circle(b.pos, b.r, col)

func _draw_board_panel() -> void:
	var w: float = cell_size * float(COLS)
	var h: float = cell_size * float(ROWS)
	var pad := 10.0
	draw_rect(Rect2(board_x - pad, board_y - pad, w + 2 * pad, h + 2 * pad), COL_BOARD, true)
	for r in range(ROWS):
		for c in range(COLS):
			var p := Vector2(board_x + c * cell_size, board_y + r * cell_size)
			draw_rect(Rect2(p.x + 3, p.y + 3, cell_size - 6, cell_size - 6), COL_CELL, true)

# Thin crackling tendrils from each blighted cell toward the neighbor it will
# infect NEXT (down-biased), so the threat is legible on the board.
func _draw_tendrils() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			if not blight[r][c] or board[r][c] == EMPTY:
				continue
			var src: Vector2 = _cell_center(c, r) + Vector2(0, cell_offset[r][c])
			var dirs: Array = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
			for d in dirs:
				var nc: int = c + d.x
				var nr: int = r + d.y
				if nc >= 0 and nc < COLS and nr >= 0 and nr < ROWS:
					if not blight[nr][nc] and board[nr][nc] != EMPTY:
						var dst: Vector2 = _cell_center(nc, nr)
						var mid: Vector2 = src.lerp(dst, 0.55)
						var jit: float = sin(sel_pulse * 9.0 + float(c + r)) * 4.0
						mid += Vector2(jit, -jit)
						var a: float = 0.35 + 0.25 * (0.5 + 0.5 * sin(sel_pulse * 7.0))
						draw_line(src, mid, Color(COL_ROT.r, COL_ROT.g, COL_ROT.b, a), 2.0)
						draw_line(mid, dst, Color(COL_ROT.r, COL_ROT.g, COL_ROT.b, a * 0.6), 1.5)
						break  # one tendril (the down-priority one) per cell

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
			var is_blight: bool = blight[r][c]
			var col: Color = COL_CHARCOAL if is_blight else GEM_COLORS[t]

			# halo (glow recipe): oversized low-alpha circles behind the shape
			var halo_col: Color = COL_ROT if is_blight else col
			var step: float = radius * 0.32
			for i in range(4):
				var hc := Color(halo_col.r, halo_col.g, halo_col.b, 0.12 - i * 0.025)
				if hc.a > 0.0:
					draw_circle(center, radius + float(i) * step, hc)

			_draw_gem_shape(t, center, radius, col)

			if is_blight:
				# pulsing magenta-rot rim
				var pulse: float = 0.55 + 0.45 * sin(sel_pulse * 8.0 + float(c + r))
				var rim := Color(COL_ROT.r, COL_ROT.g, COL_ROT.b, 0.55 + 0.4 * pulse)
				draw_arc(center, radius * 1.05, 0, TAU, 24, rim, 3.0)
				draw_arc(center, radius * 0.62, 0, TAU, 18, Color(COL_ROT.r, COL_ROT.g, COL_ROT.b, 0.5 * pulse), 2.0)
			else:
				# crisp shine highlight
				draw_circle(center - Vector2(radius * 0.28, radius * 0.28), radius * 0.18,
					Color(1, 1, 1, 0.35))

			if pop > 0.0:
				var fa: float = (pop / POP_TIME) * 0.8
				draw_circle(center, radius * 0.8, Color(1, 1, 1, fa))

func _draw_gem_shape(t: int, center: Vector2, radius: float, col: Color) -> void:
	match t:
		0:
			var pts := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.9, radius * 0.7),
				center + Vector2(-radius * 0.9, radius * 0.7),
			])
			draw_colored_polygon(pts, col)
		1:
			var s: float = radius * 1.5
			draw_rect(Rect2(center.x - s * 0.5, center.y - s * 0.5, s, s), col, true)
		2:
			var pts2 := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius, 0),
			])
			draw_colored_polygon(pts2, col)
		3:
			var pts3 := PackedVector2Array()
			for i in range(6):
				var a: float = PI / 6.0 + float(i) * (TAU / 6.0)
				pts3.append(center + Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(pts3, col)
		4:
			draw_circle(center, radius, col)
			draw_arc(center, radius, 0, TAU, 32, Color(1, 1, 1, 0.30), 2.0)

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

func _draw_cleanse() -> void:
	for cp in cleanse_pulses:
		var a: float = clamp(cp.life / cp.max_life, 0.0, 1.0)
		var r: float = lerp(cell_size * 0.8, cell_size * 0.2, a)
		draw_arc(cp.pos, r, 0, TAU, 32, Color(1, 1, 1, a), 4.0)
		draw_circle(cp.pos, r * 0.5, Color(1, 1, 1, a * 0.3))

func _draw_particles() -> void:
	for p in particles:
		var a: float = clamp(p.life / p.max_life, 0.0, 1.0)
		var col: Color = p.col
		col.a = a
		draw_circle(p.pos, p.size * a, col)

func _draw_tracers() -> void:
	for tr in tracers:
		var a: float = clamp(tr.life / tr.max_life, 0.0, 1.0)
		var col: Color = tr.col
		draw_line(tr.from, tr.to, Color(col.r, col.g, col.b, a * 0.4), 6.0)
		draw_line(tr.from, tr.to, Color(1, 1, 1, a), 2.0)

# Per-column wall segments at the grid bottom; cracked segments fracture.
func _draw_wall() -> void:
	var w: float = cell_size * float(COLS)
	var seg_w: float = w / float(COLS)
	var thick := 18.0
	for c in range(COLS):
		var sx: float = board_x + float(c) * seg_w
		var hp_frac: float = clamp(wall_seg_hp[c] / WALL_SEG_MAX, 0.0, 1.0)
		if wall_seg_hp[c] <= 0.0:
			# destroyed: dark gap with jagged red cracks
			draw_rect(Rect2(sx + 2, wall_y, seg_w - 4, thick), Color(0.08, 0.02, 0.05, 0.8), true)
			_draw_cracks(sx, seg_w, thick, COL_ROT, 0.7)
			continue
		var bright: float = lerp(0.4, 1.0, hp_frac)
		var wc := Color(COL_WALL.r * bright, COL_WALL.g * bright, COL_WALL.b * bright, 1.0)
		# halo behind the segment
		draw_rect(Rect2(sx, wall_y - 4, seg_w - 2, thick + 8),
			Color(COL_WALL.r, COL_WALL.g, COL_WALL.b, 0.20), true)
		draw_rect(Rect2(sx + 2, wall_y, seg_w - 4, thick), wc, true)
		# damage cracks scale with missing HP
		if hp_frac < 1.0:
			_draw_cracks(sx, seg_w, thick, Color(0.02, 0.04, 0.06), (1.0 - hp_frac) * 0.8)
		# break flash
		if seg_break_flash[c] > 0.0:
			draw_rect(Rect2(sx, wall_y - 6, seg_w, thick + 12),
				Color(1, 1, 1, seg_break_flash[c] * 0.7), true)

func _draw_cracks(sx: float, seg_w: float, thick: float, col: Color, alpha: float) -> void:
	var n := 3
	for i in range(n):
		var x0: float = sx + seg_w * (0.2 + 0.3 * float(i))
		var pts := PackedVector2Array([
			Vector2(x0, wall_y),
			Vector2(x0 + seg_w * 0.08, wall_y + thick * 0.5),
			Vector2(x0 - seg_w * 0.05, wall_y + thick),
		])
		draw_polyline(pts, Color(col.r, col.g, col.b, alpha), 2.0)

# Board-edge amber pulse while a surge telegraphs (the forcing-function spike).
func _draw_surge_edges() -> void:
	if surge_flash <= 0.0 and surge_state != Surge.ARMED:
		return
	var w: float = cell_size * float(COLS)
	var h: float = cell_size * float(ROWS)
	var pad := 14.0
	var a: float = clamp(surge_flash, 0.0, 1.0)
	var rect := Rect2(board_x - pad, board_y - pad, w + 2 * pad, h + 2 * pad)
	var edge := 6.0
	var ec := Color(COL_SURGE.r, COL_SURGE.g, COL_SURGE.b, 0.4 + 0.5 * a)
	# four edge bars
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, edge), ec, true)
	draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y - edge, rect.size.x, edge), ec, true)
	draw_rect(Rect2(rect.position.x, rect.position.y, edge, rect.size.y), ec, true)
	draw_rect(Rect2(rect.position.x + rect.size.x - edge, rect.position.y, edge, rect.size.y), ec, true)
	# shrinking countdown ring (top-center of board) while ARMED
	if surge_state == Surge.ARMED:
		var center := Vector2(VIEW_W * 0.5, board_y - 40.0)
		var frac: float = 1.0 - surge_charge
		var r: float = lerp(10.0, 40.0, frac)
		draw_arc(center, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 40,
			Color(COL_SURGE.r, COL_SURGE.g, COL_SURGE.b, 0.9), 4.0)

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

func _blight_total() -> int:
	var n := 0
	for r in range(ROWS):
		for c in range(COLS):
			if blight[r][c] and board[r][c] != EMPTY:
				n += 1
	return n

func _draw_hud() -> void:
	var font := _get_font()

	# SCORE (top-center, large, high-contrast) with a scale-pop on clears
	_draw_text(font, Vector2(VIEW_W * 0.5 - 60, 70), "SCORE", 22, Color(1, 1, 1, 0.55))
	var sc_size: int = int(48 * (1.0 + score_pop * 0.35))
	_draw_text(font, Vector2(VIEW_W * 0.5 - 70, 122), str(score), sc_size, COL_WHITE)

	# BLIGHT count (top-left) with a pop when it drops on a purge
	_draw_text(font, Vector2(30, 56), "BLIGHT", 20, Color(1, 1, 1, 0.5))
	var bcount: int = _blight_total()
	var bcol := COL_ROT if bcount > 0 else Color(0.4, 0.9, 0.6)
	var b_size: int = int(34 * (1.0 + blight_count_pop * 0.4))
	_draw_text(font, Vector2(30, 98), str(bcount), b_size, bcol)

	# WALL segments (top-right): alive / total
	_draw_text(font, Vector2(VIEW_W - 150, 56), "WALL", 20, Color(1, 1, 1, 0.5))
	var wcol := COL_WALL if segments_alive > 2 else Color(1.0, 0.5, 0.3)
	_draw_text(font, Vector2(VIEW_W - 150, 98), str(segments_alive) + "/" + str(COLS), 34, wcol)

	# SURGE warning banner when armed
	if surge_state == Surge.ARMED:
		var pulse: float = 0.6 + 0.4 * sin(sel_pulse * 12.0)
		var tcol := Color(COL_SURGE.r, COL_SURGE.g, COL_SURGE.b, 0.7 + 0.3 * pulse)
		_draw_text(font, Vector2(VIEW_W * 0.5 - 120, board_y - 70.0), "SURGE INCOMING", 34, tcol)

	# combo pulse near the grid when active
	if combo_pulse > 0.0 and combo_display >= 2:
		var pscale: float = 1.0 + combo_pulse * 0.6
		var size: int = int(40 * pscale)
		var ccol: Color = GEM_COLORS[combo_display % NUM_TYPES]
		ccol.a = clamp(combo_pulse + 0.3, 0.0, 1.0)
		_draw_text(font, Vector2(VIEW_W * 0.5 - 90, wall_y + 80.0),
			"x" + str(combo_display) + " COMBO", size, ccol)

func _draw_flash() -> void:
	if flash_alpha > 0.0:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H),
			Color(flash_col.r, flash_col.g, flash_col.b, flash_alpha * 0.35))

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.0, 0.0, 0.04, 0.66))
	var font := _get_font()
	var pulse: float = 1.0 + 0.05 * sin(game_over_t * 4.0)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 175, VIEW_H * 0.40), "WALL OVERRUN", int(48 * pulse), COL_ROT)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 120, VIEW_H * 0.40 + 70), "Score: " + str(score), 34, COL_WALL)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 150, VIEW_H * 0.40 + 116), "Blight purged: " + str(blight_purged), 24, Color(0.4, 0.9, 0.6))
	_draw_text(font, Vector2(VIEW_W * 0.5 - 150, VIEW_H * 0.40 + 152), "Best combo: x" + str(max_combo), 24, COL_WALL)
	if sin(game_over_t * 3.0) > -0.3:
		_draw_text(font, Vector2(VIEW_W * 0.5 - 150, VIEW_H * 0.40 + 220), "Tap to defend again", 28, Color(1, 1, 1, 0.8))
