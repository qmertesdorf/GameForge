extends Node2D

# ============================================================
# Prism Cascade (match3-0001) — a juicy _draw()-based match-3 puzzle
# Drag to swap adjacent gems, line up 3+, trigger cascades before
# the timer drains. Headless-safe: no physics, no scene instancing,
# all state owned here and rendered via _draw().
# ============================================================

const VIEW_W := 720.0
const VIEW_H := 1280.0

# --- grid config ---
const COLS := 6
const ROWS := 8
const NUM_TYPES := 5
const EMPTY := -1

# board geometry (computed in _ready)
var cell_size := 0.0
var board_x := 0.0
var board_y := 0.0
const BOARD_MARGIN_X := 40.0
const BOARD_TOP := 220.0
const BOARD_BOTTOM_MARGIN := 60.0

# --- palette ---
const COL_BG_TOP := Color(0.078, 0.063, 0.149)   # deep indigo #141026-ish top
const COL_BG_BOT := Color(0.043, 0.031, 0.094)    # darker bottom
const COL_BOARD := Color(0.10, 0.08, 0.20, 0.55)
const COL_CELL := Color(0.15, 0.12, 0.28, 0.40)
const COL_WHITE := Color(1, 1, 1)

# gem colors (cyan, magenta, lime, amber, violet) — colorblind-distinct shapes too
var GEM_COLORS := [
	Color(0.25, 0.90, 0.95),   # 0 cyan       -> circle
	Color(0.98, 0.30, 0.78),   # 1 magenta    -> square
	Color(0.62, 0.95, 0.30),   # 2 lime       -> diamond
	Color(1.00, 0.74, 0.22),   # 3 amber      -> triangle
	Color(0.66, 0.45, 0.98),   # 4 violet     -> hexagon
]

var rng := RandomNumberGenerator.new()

# --- board state ---
# board[r][c] = gem type 0..4, or EMPTY
var board := []
# per-cell visual offset for fall/spawn animation (pixels, added to resting y)
var cell_offset := []   # float fall offset (positive = above resting pos, animates down to 0)
# per-cell pop animation timer (0 = none, >0 = popping)
var cell_pop := []      # float seconds remaining of pop scale animation
const POP_TIME := 0.28

# --- game state machine ---
enum State { IDLE, SWAPPING, RESOLVING, GAMEOVER }
var state := State.IDLE

# swap animation
var swap_a := Vector2i(-1, -1)
var swap_b := Vector2i(-1, -1)
var swap_t := 0.0
const SWAP_TIME := 0.16
var swap_back := false          # if true, this swap is the reject-undo nudge
var swap_pending_check := false # after a forward swap completes, check matches

# resolve loop timing
var resolve_phase := 0          # 0=clearing(pop), 1=falling
var resolve_timer := 0.0
const CLEAR_TIME := 0.30
const FALL_TIME := 0.22
var combo := 0                  # cascade chain multiplier within one resolve

# --- selection / input ---
var selected := Vector2i(-1, -1)
var sel_pulse := 0.0            # accumulates for selected-gem pulse
var drag_start_cell := Vector2i(-1, -1)
var drag_start_pos := Vector2.ZERO
var dragging := false

# --- scoring & timer ---
var score := 0
var timer_max := 30.0
var timer_val := 30.0
var drain_rate := 3.0           # base drain per second
const DRAIN_BASE := 3.0
const DRAIN_STEP := 0.9         # added per 20s step
const DRAIN_CAP := 8.5          # capped max drain
const DRAIN_STEP_INTERVAL := 20.0
var elapsed := 0.0
const TIMER_TOP_PER_GEM := 0.55 # seconds added per cleared gem (scaled by combo)

# --- juice ---
var shake_amt := 0.0
var shake_decay := 6.0
var flash_alpha := 0.0          # full-screen white flash on clears
var edge_flash := 0.0           # screen-edge color flash on 4+ chain
var edge_flash_col := Color(1, 1, 1)
var combo_pulse := 0.0          # combo counter pulse
var combo_display := 0          # last combo shown

# particle pool (simple structs as dictionaries)
var particles := []   # each: {pos, vel, life, max_life, col, size}

# bokeh ambient dots
var bokeh := []       # each: {pos, r, spd, col, phase}

# game over
var game_over_t := 0.0

func _ready() -> void:
	rng.randomize()
	_compute_geometry()
	_init_bokeh()
	_new_game()

func _compute_geometry() -> void:
	var avail_w := VIEW_W - 2.0 * BOARD_MARGIN_X
	var avail_h := VIEW_H - BOARD_TOP - BOARD_BOTTOM_MARGIN
	cell_size = min(avail_w / float(COLS), avail_h / float(ROWS))
	var board_w := cell_size * float(COLS)
	var board_h := cell_size * float(ROWS)
	board_x = (VIEW_W - board_w) * 0.5
	board_y = BOARD_TOP + (avail_h - board_h) * 0.5

func _init_bokeh() -> void:
	bokeh.clear()
	for i in range(18):
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
		var row := []
		var orow := []
		var prow := []
		for c in range(COLS):
			row.append(EMPTY)
			orow.append(0.0)
			prow.append(0.0)
		board.append(row)
		cell_offset.append(orow)
		cell_pop.append(prow)
	_fill_board_no_matches()
	score = 0
	combo = 0
	combo_display = 0
	timer_max = 30.0
	timer_val = 30.0
	drain_rate = DRAIN_BASE
	elapsed = 0.0
	state = State.IDLE
	selected = Vector2i(-1, -1)
	particles.clear()
	shake_amt = 0.0
	flash_alpha = 0.0
	edge_flash = 0.0
	combo_pulse = 0.0
	game_over_t = 0.0

# Fill the whole board so that NO 3-in-a-row exists at spawn.
func _fill_board_no_matches() -> void:
	for r in range(ROWS):
		for c in range(COLS):
			var t := _pick_safe_type(r, c)
			board[r][c] = t
			cell_offset[r][c] = 0.0
			cell_pop[r][c] = 0.0

# pick a gem type that does not complete a horizontal or vertical 3-run
func _pick_safe_type(r: int, c: int) -> int:
	var forbidden := {}
	# horizontal: two to the left same -> forbid
	if c >= 2 and board[r][c - 1] == board[r][c - 2] and board[r][c - 1] != EMPTY:
		forbidden[board[r][c - 1]] = true
	# vertical: two above same -> forbid
	if r >= 2 and board[r - 1][c] == board[r - 2][c] and board[r - 1][c] != EMPTY:
		forbidden[board[r - 1][c]] = true
	var choices := []
	for t in range(NUM_TYPES):
		if not forbidden.has(t):
			choices.append(t)
	if choices.is_empty():
		return rng.randi() % NUM_TYPES
	return choices[rng.randi() % choices.size()]

# ------------------------------------------------------------
# Main loop
# ------------------------------------------------------------
func _process(delta: float) -> void:
	_update(delta)
	queue_redraw()

func _update(delta: float) -> void:
	# clamp delta to avoid huge steps on first frame
	delta = min(delta, 0.05)
	sel_pulse += delta
	# ambient + fx always update
	_update_bokeh(delta)
	_update_particles(delta)
	if shake_amt > 0.0:
		shake_amt = max(0.0, shake_amt - shake_decay * delta * shake_amt - 0.2 * delta)
	flash_alpha = max(0.0, flash_alpha - 3.5 * delta)
	edge_flash = max(0.0, edge_flash - 2.2 * delta)
	combo_pulse = max(0.0, combo_pulse - 3.0 * delta)

	match state:
		State.IDLE:
			_update_timer(delta)
		State.SWAPPING:
			_update_swap(delta)
			_update_timer(delta)
		State.RESOLVING:
			_update_resolve(delta)
			_update_timer(delta)
		State.GAMEOVER:
			game_over_t += delta

func _update_timer(delta: float) -> void:
	elapsed += delta
	# step up drain every interval, capped
	var step := int(elapsed / DRAIN_STEP_INTERVAL)
	drain_rate = min(DRAIN_CAP, DRAIN_BASE + float(step) * DRAIN_STEP)
	timer_val -= drain_rate * delta
	if timer_val <= 0.0:
		timer_val = 0.0
		_trigger_game_over()

func _trigger_game_over() -> void:
	if state == State.GAMEOVER:
		return
	state = State.GAMEOVER
	shake_amt = 14.0
	flash_alpha = 0.5
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
		# commit the data swap (visual lerp is done in _draw using swap_t ratio)
		var ta: int = board[swap_a.y][swap_a.x]
		var tb: int = board[swap_b.y][swap_b.x]
		board[swap_a.y][swap_a.x] = tb
		board[swap_b.y][swap_b.x] = ta
		if swap_pending_check:
			# check for matches; if none, swap back with a nudge
			var matches := _find_matches()
			if matches.is_empty():
				_begin_swap(swap_a, swap_b, true)   # undo
				shake_amt = max(shake_amt, 3.0)
			else:
				# good swap -> start resolve cascade
				combo = 0
				state = State.RESOLVING
				_start_clear(matches)
		else:
			# undo finished -> back to idle
			selected = Vector2i(-1, -1)
			state = State.IDLE
			swap_a = Vector2i(-1, -1)
			swap_b = Vector2i(-1, -1)

# ------------------------------------------------------------
# Match detection
# ------------------------------------------------------------
# Returns array of Vector2i (col,row) cells that are part of any 3+ run.
func _find_matches() -> Array:
	var matched := {}   # use dict as set keyed by "r,c"
	var result := []
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
					var key := str(r) + "," + str(c)
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
					var key := str(r) + "," + str(c)
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
	var cleared := matches.size()
	# scoring: base 10 per gem, scaled by combo
	score += cleared * 10 * combo
	# timer top-up scaled by combo (capped contribution)
	var topup := cleared * TIMER_TOP_PER_GEM * (1.0 + 0.25 * float(combo - 1))
	timer_val = min(timer_max, timer_val + topup)

	# juice: pop animation, particles, flash, shake
	flash_alpha = max(flash_alpha, 0.35)
	shake_amt = max(shake_amt, 2.5 + float(combo) * 1.2)
	for cell in matches:
		var c: int = cell.x
		var r: int = cell.y
		cell_pop[r][c] = POP_TIME
		_spawn_burst(_cell_center(c, r), GEM_COLORS[board[r][c]] if board[r][c] != EMPTY else COL_WHITE)

	# combo reward beat: pulse + edge flash on big chains
	if combo >= 2:
		combo_pulse = 1.0
		combo_display = combo
	if combo >= 4:
		edge_flash = 1.0
		edge_flash_col = GEM_COLORS[(combo) % NUM_TYPES]
		shake_amt = max(shake_amt, 8.0)

	resolve_phase = 0
	resolve_timer = CLEAR_TIME
	# stash the matches to clear when pop completes
	_pending_clear = matches.duplicate()

var _pending_clear := []

func _update_resolve(delta: float) -> void:
	resolve_timer -= delta
	# advance pop timers
	for r in range(ROWS):
		for c in range(COLS):
			if cell_pop[r][c] > 0.0:
				cell_pop[r][c] = max(0.0, cell_pop[r][c] - delta)
			# ease fall offset toward 0
			if cell_offset[r][c] != 0.0:
				cell_offset[r][c] = lerp(cell_offset[r][c], 0.0, min(1.0, delta * 12.0))
				if abs(cell_offset[r][c]) < 0.5:
					cell_offset[r][c] = 0.0

	if resolve_timer > 0.0:
		return

	if resolve_phase == 0:
		# pop finished -> actually clear cells, then apply gravity + refill
		for cell in _pending_clear:
			board[cell.y][cell.x] = EMPTY
		_pending_clear = []
		_apply_gravity_and_refill()
		resolve_phase = 1
		resolve_timer = FALL_TIME
	else:
		# fall finished -> rescan for cascades
		var more := _find_matches()
		if more.is_empty():
			# settle: ensure no leftover offsets
			for r in range(ROWS):
				for c in range(COLS):
					cell_offset[r][c] = 0.0
			selected = Vector2i(-1, -1)
			swap_a = Vector2i(-1, -1)
			swap_b = Vector2i(-1, -1)
			state = State.IDLE
		else:
			_start_clear(more)

# Drop gems into empties per column, spawn new at top with a fall offset.
func _apply_gravity_and_refill() -> void:
	for c in range(COLS):
		# collect existing gems bottom-up
		var write_r := ROWS - 1
		for r in range(ROWS - 1, -1, -1):
			if board[r][c] != EMPTY:
				if write_r != r:
					board[write_r][c] = board[r][c]
					board[r][c] = EMPTY
					# carry over visual offset so it eases down from old pos
					cell_offset[write_r][c] = float(write_r - r) * cell_size * -1.0 + cell_offset[r][c]
				write_r -= 1
		# fill the remaining top cells with new gems falling in
		var spawn_index := 0
		for r in range(write_r, -1, -1):
			board[r][c] = rng.randi() % NUM_TYPES
			# start above the board so it falls into place
			cell_offset[r][c] = -float(spawn_index + r + 2) * cell_size
			spawn_index += 1
			cell_pop[r][c] = 0.0

# ------------------------------------------------------------
# Particles & ambient
# ------------------------------------------------------------
func _spawn_burst(pos: Vector2, col: Color) -> void:
	var n := 8
	for i in range(n):
		var ang := rng.randf() * TAU
		var spd := rng.randf_range(80.0, 240.0)
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
			p.vel *= (1.0 - 2.5 * delta)        # drag
			p.vel.y += 220.0 * delta            # gravity
			p.pos += p.vel * delta
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
		# tap anywhere to restart
		if (event is InputEventScreenTouch and event.pressed) or \
		   (event is InputEventMouseButton and event.pressed):
			_new_game()
		return

	# only accept input when idle
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
			# determine cardinal direction
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
		# tap-then-tap fallback: if released on same cell, keep selected;
		# if a previous selection exists and this is adjacent, swap.
		var cell := _pixel_to_cell(pos)
		if dragging and cell == drag_start_cell and cell.x >= 0:
			# this was a tap. handle tap-to-select / tap-adjacent-to-swap
			pass
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

	# 1) background vertical gradient (stacked rects)
	_draw_gradient_bg()
	# 2) ambient bokeh dots
	_draw_bokeh()

	# everything below gets the shake offset
	draw_set_transform(shake, 0.0, Vector2.ONE)

	# 3) board panel
	_draw_board_panel()
	# 4) gems (glow halo + shaped core)
	_draw_gems()
	# 5) particles
	_draw_particles()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# HUD (score, timer bar, combo)
	_draw_hud()

	# fx overlays
	_draw_flash()
	_draw_edge_flash()

	if state == State.GAMEOVER:
		_draw_game_over()

func _draw_gradient_bg() -> void:
	var steps := 24
	for i in range(steps):
		var f := float(i) / float(steps - 1)
		var col := COL_BG_TOP.lerp(COL_BG_BOT, f)
		var y := f * VIEW_H
		draw_rect(Rect2(0, y, VIEW_W, VIEW_H / float(steps) + 1.0), col)

func _draw_bokeh() -> void:
	for b in bokeh:
		var a: float = 0.05 + 0.03 * sin(b.phase)
		var col: Color = b.col
		col.a = max(0.02, a)
		draw_circle(b.pos, b.r, col)

func _draw_board_panel() -> void:
	var w := cell_size * float(COLS)
	var h := cell_size * float(ROWS)
	var pad := 10.0
	draw_rect(Rect2(board_x - pad, board_y - pad, w + 2 * pad, h + 2 * pad), COL_BOARD, true)
	# cell grid backing
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
			# apply swap visual lerp
			center += _swap_visual_offset(c, r)
			# apply fall offset
			center.y += cell_offset[r][c]

			# pop scale: scale up then vanish
			var scale := 1.0
			var pop: float = cell_pop[r][c]
			if pop > 0.0:
				var pf: float = pop / POP_TIME       # 1 -> 0
				scale = 1.0 + (1.0 - pf) * 0.6  # grows as it pops

			# selected gem pulse
			if selected == Vector2i(c, r) and state == State.IDLE:
				scale *= 1.0 + 0.10 * sin(sel_pulse * 9.0)

			var radius := cell_size * 0.36 * scale
			var col: Color = GEM_COLORS[t]

			# glow halo: 4 concentric translucent circles
			var step := radius * 0.32
			for i in range(4):
				var hc := Color(col.r, col.g, col.b, 0.12 - i * 0.025)
				if hc.a > 0.0:
					draw_circle(center, radius + float(i) * step, hc)

			# distinct shape per type
			_draw_gem_shape(t, center, radius, col)

			# white flash core on pop
			if pop > 0.0:
				var fa: float = (pop / POP_TIME) * 0.8
				draw_circle(center, radius * 0.8, Color(1, 1, 1, fa))

func _draw_gem_shape(t: int, center: Vector2, radius: float, col: Color) -> void:
	match t:
		0:
			# circle (cyan)
			draw_circle(center, radius, col)
			draw_arc(center, radius, 0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)
		1:
			# square (magenta)
			var s := radius * 1.5
			draw_rect(Rect2(center.x - s * 0.5, center.y - s * 0.5, s, s), col, true)
		2:
			# diamond (lime)
			var pts := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius, 0),
			])
			draw_colored_polygon(pts, col)
		3:
			# triangle (amber)
			var pts2 := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius * 0.9, radius * 0.7),
				center + Vector2(-radius * 0.9, radius * 0.7),
			])
			draw_colored_polygon(pts2, col)
		4:
			# hexagon (violet)
			var pts3 := PackedVector2Array()
			for i in range(6):
				var a := PI / 6.0 + float(i) * (TAU / 6.0)
				pts3.append(center + Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(pts3, col)

# during a swap, the two cells visually lerp toward each other
func _swap_visual_offset(c: int, r: int) -> Vector2:
	if state != State.SWAPPING:
		return Vector2.ZERO
	var cell := Vector2i(c, r)
	var f: float = clamp(swap_t / SWAP_TIME, 0.0, 1.0)
	# eased
	f = f * f * (3.0 - 2.0 * f)
	# Note: data swap happens at end, so during animation board still holds
	# pre-swap contents. a moves toward b, b moves toward a.
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

func _draw_flash() -> void:
	if flash_alpha > 0.0:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(1, 1, 1, flash_alpha * 0.35))

func _draw_edge_flash() -> void:
	if edge_flash <= 0.0:
		return
	var a := edge_flash * 0.55
	var col := Color(edge_flash_col.r, edge_flash_col.g, edge_flash_col.b, a)
	var thick := 60.0
	# top, bottom, left, right bands fading inward (approx with rects)
	draw_rect(Rect2(0, 0, VIEW_W, thick), col)
	draw_rect(Rect2(0, VIEW_H - thick, VIEW_W, thick), col)
	draw_rect(Rect2(0, 0, thick, VIEW_H), col)
	draw_rect(Rect2(VIEW_W - thick, 0, thick, VIEW_H), col)

# ------------------------------------------------------------
# HUD
# ------------------------------------------------------------
func _get_font() -> Font:
	# guarded: skip text rather than risk a headless error
	if ThemeDB and ThemeDB.fallback_font:
		return ThemeDB.fallback_font
	return null

func _draw_text(font: Font, pos: Vector2, txt: String, size: int, col: Color) -> void:
	if font == null:
		return
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_hud() -> void:
	var font := _get_font()
	# timer bar across the top
	var bar_x := 40.0
	var bar_y := 70.0
	var bar_w := VIEW_W - 80.0
	var bar_h := 28.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0, 0, 0, 0.35), true)
	var frac: float = clamp(timer_val / timer_max, 0.0, 1.0)
	# color shifts from cyan(full) to amber to red(low)
	var bar_col := Color(0.95, 0.25, 0.25)
	if frac > 0.5:
		bar_col = Color(0.25, 0.90, 0.95)
	elif frac > 0.25:
		bar_col = Color(1.0, 0.74, 0.22)
	# glow under bar
	draw_rect(Rect2(bar_x - 2, bar_y - 2, bar_w * frac + 4, bar_h + 4),
		Color(bar_col.r, bar_col.g, bar_col.b, 0.25), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w * frac, bar_h), bar_col, true)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(1, 1, 1, 0.15), false, 2.0)

	# score top-left
	_draw_text(font, Vector2(40, 150), "SCORE", 22, Color(1, 1, 1, 0.55))
	_draw_text(font, Vector2(40, 192), str(score), 40, COL_WHITE)

	# combo pulse (center-ish) when active
	if combo_pulse > 0.0 and combo_display >= 2:
		var pscale := 1.0 + combo_pulse * 0.6
		var size := int(46 * pscale)
		var col: Color = GEM_COLORS[combo_display % NUM_TYPES]
		col.a = clamp(combo_pulse + 0.3, 0.0, 1.0)
		_draw_text(font, Vector2(VIEW_W - 260, 192), "x" + str(combo_display) + " COMBO", size, col)

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.0, 0.0, 0.05, 0.65))
	var font := _get_font()
	var pulse := 1.0 + 0.05 * sin(game_over_t * 4.0)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 150, VIEW_H * 0.45), "GAME OVER", int(54 * pulse), COL_WHITE)
	_draw_text(font, Vector2(VIEW_W * 0.5 - 120, VIEW_H * 0.45 + 70), "Score: " + str(score), 36, Color(0.25, 0.90, 0.95))
	if sin(game_over_t * 3.0) > -0.3:
		_draw_text(font, Vector2(VIEW_W * 0.5 - 140, VIEW_H * 0.45 + 150), "Tap to play again", 28, Color(1, 1, 1, 0.8))
