extends SceneTree

# Headless self-test for Aegis Grid III (match3-survival-0003).
# Drives Main.gd's state directly (no real input, no frame waiting) and asserts
# the OBSERVABLE state changes a human would check on this FUSION:
#   1. a known 3-in-a-row swap clears those cells (match path fires),
#   2. THE FUSION: a match that includes a blighted cell PURGES it (one action,
#      both genres) — blight count drops and blight_purged increments,
#   3. blight SPREADS on a tick (an isolated seed infects a neighbor),
#   4. the FORCING FUNCTION: a surge makes the next tick spread TWICE (>1 new),
#   5. a bottom-row blight CRACKS that column's wall segment on a tick,
#   6. _game_over() fires when all wall segments are destroyed.
# Prints exactly "SELFTEST OK" (exit 0) or "SELFTEST FAIL: <reason>" (exit != 0).

const MainScript := preload("res://Main.gd")

func _fail(reason: String) -> void:
	print("SELFTEST FAIL: " + reason)
	quit(1)

func _ok() -> void:
	print("SELFTEST OK")
	quit(0)

# NOTE: in a SceneTree script, add_child() defers _ready(), so we drive the same
# setup _ready() does explicitly to guarantee board/geometry exist synchronously.
func _make() -> Node2D:
	var m: Node2D = MainScript.new()
	get_root().add_child(m)
	m.rng.randomize()
	m._compute_geometry()
	m._init_plankton()
	m._new_game()
	return m

# Force a deterministic board with no incidental matches and no blight.
func _clear_board(m) -> void:
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.board[r][c] = (c + r) % 3 + 2   # only neutral types 2,3,4
			m.blight[r][c] = false
			m.cell_offset[r][c] = 0.0
			m.cell_pop[r][c] = 0.0

func _count_blight(m) -> int:
	var n := 0
	for r in range(m.ROWS):
		for c in range(m.COLS):
			if m.blight[r][c]:
				n += 1
	return n

func _init() -> void:
	# ---- Test 1: a known 3-in-a-row swap clears cells ----
	var m = _make()
	_clear_board(m)
	# coral (type 0) row at row 3 cols 0,1; third coral one cell below at (2,4).
	# Swapping (2,4)<->(2,3) completes a horizontal 3.
	m.board[3][0] = 0
	m.board[3][1] = 0
	m.board[3][2] = 2
	m.board[4][2] = 0
	if not m._find_matches().is_empty():
		_fail("board had a match before the test swap")
		return
	m.state = m.State.IDLE
	m._begin_swap(Vector2i(2, 3), Vector2i(2, 4), false)
	var guard := 0
	while m.state == m.State.SWAPPING and guard < 200:
		m._update_swap(1.0)
		guard += 1
	if m.state != m.State.RESOLVING:
		_fail("valid 3-swap did not enter RESOLVING (state=%d)" % m.state)
		return
	guard = 0
	while m.state == m.State.RESOLVING and guard < 500:
		m._update_resolve(1.0)
		guard += 1
	if m.combo <= 0:
		_fail("3-in-a-row swap never incremented combo / cleared")
		return
	m.queue_free()

	# ---- Test 2: THE FUSION — a match including blight purges it ----
	m = _make()
	_clear_board(m)
	# build a coral 3-in-a-row at row 2 cols 0,1,2, and blight the middle one.
	m.board[2][0] = 0
	m.board[2][1] = 0
	m.board[2][2] = 0
	m.blight[2][1] = true
	var purged_before: int = m.blight_purged
	var blight_before: int = _count_blight(m)
	m.combo = 1
	var n_purged: int = m._apply_match_purge([Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])
	if n_purged != 1:
		_fail("match over a blighted cell purged %d, expected 1" % n_purged)
		return
	if m.blight[2][1]:
		_fail("blighted cell still blighted after a match purged it")
		return
	if m.blight_purged != purged_before + 1:
		_fail("blight_purged counter did not increment on purge")
		return
	if _count_blight(m) != blight_before - 1:
		_fail("total blight did not drop after purge")
		return
	m.queue_free()

	# ---- Test 3: blight SPREADS on a tick ----
	m = _make()
	_clear_board(m)
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.blight[r][c] = false
	# a single isolated seed in the interior should infect a neighbor on spread.
	m.blight[2][3] = true
	var before_spread: int = _count_blight(m)
	m._spread_blight_once()
	if _count_blight(m) <= before_spread:
		_fail("blight did not spread to a neighbor (%d -> %d)" % [before_spread, _count_blight(m)])
		return
	# down-bias: the cell directly below should be the one infected
	if not m.blight[3][3]:
		_fail("blight spread but not down-biased (expected (3,3) infected)")
		return
	m.queue_free()

	# ---- Test 4: FORCING FUNCTION — a surge doubles the spread on next tick ----
	# Single-spread baseline vs surge-spread from the SAME starting state.
	m = _make()
	_clear_board(m)
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.blight[r][c] = false
	# three separated seeds so each can independently infect (no overlap).
	m.blight[2][0] = true
	m.blight[2][3] = true
	m.blight[2][6] = true
	var single_start: int = _count_blight(m)
	m.surge_pending = false
	m._blight_tick()                       # one spread + one seed
	var single_new: int = _count_blight(m) - single_start

	# reset to the same start, this time with a surge armed
	m = _make()
	_clear_board(m)
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.blight[r][c] = false
	m.blight[2][0] = true
	m.blight[2][3] = true
	m.blight[2][6] = true
	var surge_start: int = _count_blight(m)
	m.surge_pending = true
	m._blight_tick()                       # double spread + one seed
	var surge_new: int = _count_blight(m) - surge_start
	if surge_new <= single_new:
		_fail("surge tick did not spread more than a normal tick (%d vs %d)" % [surge_new, single_new])
		return
	if m.surge_pending:
		_fail("surge_pending not consumed after the tick")
		return
	m.queue_free()

	# ---- Test 5: a bottom-row blight cracks that column's wall segment ----
	m = _make()
	_clear_board(m)
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.blight[r][c] = false
	var br: int = m.ROWS - 1
	m.blight[br][2] = true                 # bottom-row blight in column 2
	var seg_before: float = m.wall_seg_hp[2]
	m._check_breaches()
	if not (m.wall_seg_hp[2] < seg_before):
		_fail("bottom-row blight did not crack the wall segment (%f -> %f)" % [seg_before, m.wall_seg_hp[2]])
		return
	m.queue_free()

	# ---- Test 6: _game_over() fires when ALL segments destroyed ----
	m = _make()
	_clear_board(m)
	for r in range(m.ROWS):
		for c in range(m.COLS):
			m.blight[r][c] = false
	m.state = m.State.IDLE
	# leave exactly one segment with 1 hit left; blight every bottom cell so the
	# breach pass drains them; force all others to already-destroyed.
	for c in range(m.COLS):
		m.wall_seg_hp[c] = 0.0
	m.segments_alive = 1
	m.wall_seg_hp[3] = m.BREACH_HIT        # one breach hit destroys it
	m.blight[m.ROWS - 1][3] = true
	m._check_breaches()
	if m.wall_seg_hp[3] > 0.0:
		_fail("last segment not destroyed by breach (hp=%f)" % m.wall_seg_hp[3])
		return
	if m.state != m.State.GAMEOVER:
		_fail("_game_over did not fire when all segments destroyed (state=%d)" % m.state)
		return
	m.queue_free()

	# ===================== deepen (systemic) =====================

	# ---- Test 7: purging is NO LONGER score-dominant ----
	# _apply_match_purge must not add score directly (the old +purged*50*combo
	# bonus is gone). Scoring lives only in _start_clear; purge's reward is survival.
	m = _make()
	_clear_board(m)
	m.board[2][0] = 0
	m.board[2][1] = 0
	m.board[2][2] = 0
	m.blight[2][1] = true
	m.combo = 3
	m.score = 1000
	var t7_purged: int = m._apply_match_purge([Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)])
	if t7_purged != 1:
		_fail("test7: expected 1 purge, got %d" % t7_purged)
		return
	if m.score != 1000:
		_fail("test7: purge still changed score directly (%d != 1000) — purge is dominant again" % m.score)
		return
	m.queue_free()

	# ---- Test 8: the STREAK multiplier builds and scales score ----
	m = _make()
	_clear_board(m)
	# multiplier is monotonic non-decreasing as streak climbs through the tiers
	m.streak = 0
	var t8_m0: float = m.streak_mult()
	m.streak = m.STREAK_TIERS[m.STREAK_TIERS.size() - 1]   # top tier
	var t8_mtop: float = m.streak_mult()
	if not (t8_mtop > t8_m0):
		_fail("test8: streak multiplier did not rise across tiers (%f -> %f)" % [t8_m0, t8_mtop])
		return
	# a scoring resolve increments the streak and applies the multiplier
	var t8_cells: Array = [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5)]
	m.streak = 0
	m.combo = 0
	m.score = 0
	m._start_clear(t8_cells)
	var t8_low: int = m.score
	if m.streak != 1:
		_fail("test8: a scoring resolve did not increment streak (streak=%d)" % m.streak)
		return
	m.streak = m.STREAK_TIERS[m.STREAK_TIERS.size() - 1] - 1   # next resolve reaches the top tier
	m.combo = 0
	m.score = 0
	m._start_clear(t8_cells)
	var t8_high: int = m.score
	if not (t8_high > t8_low):
		_fail("test8: high-streak resolve did not out-score a streak-0 resolve (%d <= %d)" % [t8_high, t8_low])
		return
	m.queue_free()

	# ---- Test 9: a wall breach WIPES the streak ----
	m = _make()
	_clear_board(m)
	for r9 in range(m.ROWS):
		for c9 in range(m.COLS):
			m.blight[r9][c9] = false
	m.streak = 8
	var t9_br: int = m.ROWS - 1
	m.blight[t9_br][2] = true        # bottom-row blight -> breach this column on the pass
	m._check_breaches()
	if m.streak != 0:
		_fail("test9: a breach did not wipe the streak (streak=%d)" % m.streak)
		return
	m.queue_free()

	_ok()
