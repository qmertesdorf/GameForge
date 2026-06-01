extends Node2D

# ============================================================
# Pixel Hop (crosser-0001) — lane-crossing hopper
# Node2D root, all rendering via _draw(), no physics bodies.
# Tap to hop forward one lane; swipe/drag sideways to sidestep.
# Reach the far edge for a point; hazard contact = game over.
# NES-ish retro palette, hard-edged rect primitives, snap hops.
# ============================================================

# --- Screen ---
const VIEW_W: float = 720.0
const VIEW_H: float = 1280.0

# --- Retro NES-ish palette ---
const COL_BG: Color         = Color(0.06, 0.06, 0.10)         # near-black border
const COL_LANE_GRASS: Color = Color(0.18, 0.55, 0.18)         # NES grass green
const COL_LANE_DIRT: Color  = Color(0.49, 0.31, 0.15)         # dirt brown
const COL_LANE_ROAD: Color  = Color(0.25, 0.25, 0.28)         # road grey
const COL_HERO: Color       = Color(0.10, 0.80, 0.85)         # cyan accent
const COL_HERO_DARK: Color  = Color(0.05, 0.45, 0.50)         # hero shadow detail
const COL_HAZARD: Color     = Color(0.90, 0.25, 0.20)         # red hazard block
const COL_HAZARD_DARK: Color= Color(0.55, 0.10, 0.08)         # hazard detail
const COL_SAFE_ZONE: Color  = Color(0.20, 0.65, 0.22)         # start/safe row
const COL_GOAL: Color       = Color(0.95, 0.85, 0.10)         # goal row (top)
const COL_HUD: Color        = Color(0.98, 0.95, 0.25)         # score yellow
const COL_WHITE: Color      = Color(1.0, 1.0, 1.0)
const COL_GRID: Color       = Color(1.0, 1.0, 1.0, 0.08)     # faint pixel grid

# --- Grid / lane layout ---
# The field occupies most of the screen vertically.
# Lane 0 = bottom safe row; lanes 1..NUM_HAZARD_LANES = hazard rows;
# lane NUM_HAZARD_LANES+1 = goal row (top).
const NUM_HAZARD_LANES: int = 5           # crossable hazard lanes
const TOTAL_LANES: int      = NUM_HAZARD_LANES + 2  # +safe bottom +goal top
# Pixel grid cell size: snaps all motion to a coarse grid (retro look)
const CELL: float = 48.0                  # px per grid cell
# Hero occupies one cell; field is centred on VIEW_W
const HERO_SIZE: float = 42.0            # slightly smaller than cell
const HAZARD_H: float  = 38.0
const LANE_H: float    = 96.0            # px per lane row

# Field vertical placement: centred in view with HUD at top
const FIELD_TOP: float  = 160.0          # y of goal (top lane top edge)
const FIELD_BOT: float  = FIELD_TOP + LANE_H * float(TOTAL_LANES)

# Number of horizontal cells
const NUM_CELLS_X: int = 9               # 9 × 48 = 432 px; field centred in 720
const FIELD_LEFT: float  = (VIEW_W - CELL * float(NUM_CELLS_X)) * 0.5
const FIELD_RIGHT: float = FIELD_LEFT + CELL * float(NUM_CELLS_X)

# --- Hero tuning ---
# Hero occupies a lane-row and a cell-column.
# Hopping forward moves lane_row up by 1 (lane increases = closer to goal).
# Sidestepping moves col_x left or right by 1 cell.
const HOP_ANIM_FRAMES: int = 3    # frames for the hop visual (small pop)
const SWIPE_MIN_PX: float  = 20.0 # minimum swipe distance to register a sidestep

# --- Difficulty tuning ---
# Ramps every ~3 crossings. Hard cap at MAX_TIER.
const RAMP_EVERY_N_CROSSINGS: int = 3
const MAX_TIER: int = 6
# Hazard base speed (px/s) and per-tier increment — designed so tier-0 is
# comfortably clearable and tier-6 is tight but possible.
const BASE_HAZARD_SPEED: float  = 140.0
const SPEED_PER_TIER: float     = 40.0
const MAX_HAZARD_SPEED: float   = BASE_HAZARD_SPEED + float(MAX_TIER) * SPEED_PER_TIER
# Spawn density (hazards per lane — higher = denser, harder).
# Gap is always >= CELL * 1.5 so a standing hero can always dodge by sidestepping.
const BASE_GAP_RATIO: float     = 0.55   # fraction of lane that is clear at tier 0
const MIN_GAP_RATIO: float      = 0.30   # cap at tier 6

# --- Speed-cross streak ---
# Completing a full crossing in under STREAK_TIME seconds (no backtrack) awards
# a streak bonus. Backtracking (hopping backward / sidestepping > BACK_STEPS)
# resets the streak timer as a penalty.
const STREAK_TIME: float       = 4.0    # seconds to cross for bonus
const STREAK_BONUS_BASE: int   = 3       # extra points per streak level (stacks)
const MAX_STREAK: int          = 5

# --- Juice ---
const SHAKE_MAG: float   = 14.0
const SHAKE_DECAY: float = 10.0
const FLASH_FRAMES: int  = 1             # 1-frame white flash on death

# ============================================================
# State
# ============================================================
var screen_w: float = VIEW_W
var screen_h: float = VIEW_H

# Hero grid position
var hero_lane: int = 0          # 0 = safe bottom; NUM_HAZARD_LANES+1 = goal
var hero_col: int  = 4          # 0-indexed column in NUM_CELLS_X grid

# Hop animation feedback (small y-offset pop, not smooth easing)
var hop_anim: int  = 0          # frames remaining for pop
var hop_dir: int   = 0          # +1=forward, -1=backward (for squash direction)

# Hazard lanes: array of NUM_HAZARD_LANES entries
# Each entry: { speed:float, dir:int (+1=right,-1=left), hazards:Array }
# Each hazard dict: { x:float, w:float } (hazard rect's left edge x, width)
var lanes: Array = []

# Scoring & progress
var score: int = 0
var best: int  = 0
var crossings: int = 0     # total crossings this run (for difficulty ramp)
var tier: int  = 0

# Streak tracking
var streak_count: int   = 0    # consecutive quick crossings
var cross_timer: float  = 0.0  # time spent on current crossing attempt
var backtrack_count: int = 0   # how many backward hops taken this crossing

# Game state
var alive: bool = true
var score_pulse: float = 0.0   # scale-pop on score tick

# Juice
var shake: float       = 0.0
var white_flash: int   = 0     # frames of white full-screen flash
var shake_offset: Vector2 = Vector2.ZERO

# Input state for swipe detection
var touch_start: Vector2 = Vector2.ZERO
var touch_active: bool   = false
var pending_sidestep: int = 0   # -1/0/+1 from swipe, consumed each frame

# HUD animation
var score_pop_timer: float = 0.0

# --- Audio (M1.6 audio_pass) ---
# Generated via Stable Audio Open; chiptune SFX one-shots + a looping chip bed.
var _audio_players: Dictionary = {}      # event -> AudioStreamPlayer
var audio_play_counts: Dictionary = {}   # event -> int, selftest hook

# --- Raster art (M1.5 asset_pass) ---
# Pixel-art RGBA sprites via ComfyUI + SDXL Juggernaut + pixel-art-xl LoRA + LayerDiffuse.
# Masters downscaled to 128px on import; drawn small with NEAREST filter = crisp pixels.
# Variable-width hazard bars are filled with N exact-fit demon units (no stretch).
const HERO_DRAW: float = 64.0    # visual size; collision footprint stays HERO_SIZE
const HAZ_UNIT: float  = 64.0    # target square size per tiled hazard-creature unit
var tex_hero: Texture2D = null
var tex_hazard: Texture2D = null

# ============================================================
# Init
# ============================================================
func _ready() -> void:
	randomize()
	var vp: Vector2 = get_viewport_rect().size
	screen_w = vp.x
	screen_h = vp.y
	# NEAREST filtering keeps the downscaled pixel-art sprites crisp (no blur).
	texture_filter = TEXTURE_FILTER_NEAREST
	tex_hero = load("res://art/hero.png")
	tex_hazard = load("res://art/hazard.png")
	_setup_audio()
	_start_game()


# ============================================================
# Audio (M1.6)
# ============================================================
func _setup_audio() -> void:
	if not _audio_players.is_empty():
		return   # idempotent (selftest may call this explicitly)
	_make_player("hop", "res://audio/hop.wav", false)
	_make_player("cross", "res://audio/cross.wav", false)
	_make_player("streak", "res://audio/streak.wav", false)
	_make_player("gameover", "res://audio/gameover.wav", false)
	_make_player("bgm", "res://audio/bgm.wav", true)
	if _audio_players.has("bgm"):
		var bgm: AudioStreamPlayer = _audio_players["bgm"]
		if bgm.stream != null and bgm.is_inside_tree():
			bgm.play()


func _make_player(event_name: String, path: String, looping: bool) -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	# Node name (PascalCase) is what audio_pass.events[].node references.
	p.name = "Sfx" + event_name.capitalize() if event_name != "bgm" else "MusicAmbient"
	var stream: Resource = load(path)
	if stream is AudioStreamWAV and looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if stream != null:
		p.stream = stream
	add_child(p)
	_audio_players[event_name] = p


func _play_sfx(event_name: String) -> void:
	# Count first so the selftest hook is robust even if a stream failed to load.
	audio_play_counts[event_name] = int(audio_play_counts.get(event_name, 0)) + 1
	var p: AudioStreamPlayer = _audio_players.get(event_name)
	if p != null and p.stream != null and p.is_inside_tree():
		p.play()


func _start_game() -> void:
	hero_lane = 0
	hero_col  = NUM_CELLS_X / 2
	hop_anim  = 0
	hop_dir   = 0

	score    = 0
	crossings = 0
	tier      = 0
	streak_count = 0
	cross_timer  = 0.0
	backtrack_count = 0

	alive = true
	shake = 0.0
	white_flash = 0
	score_pulse = 0.0
	score_pop_timer = 0.0
	pending_sidestep = 0
	touch_active = false

	_build_lanes()


func _build_lanes() -> void:
	# Build NUM_HAZARD_LANES hazard lanes with initial hazard placements.
	lanes.clear()
	for i in range(NUM_HAZARD_LANES):
		# Alternate direction per lane
		var dir: int = 1 if (i % 2 == 0) else -1
		var spd: float = _lane_speed(i)
		var lane_entry: Dictionary = {
			"speed": spd,
			"dir": dir,
			"hazards": []
		}
		_populate_lane(lane_entry, i)
		lanes.append(lane_entry)


func _lane_speed(lane_idx: int) -> float:
	# Each lane gets a slightly different speed for variety; tier amplifies all.
	var base: float = BASE_HAZARD_SPEED + float(lane_idx) * 12.0
	var spd: float = base + float(tier) * SPEED_PER_TIER
	return clamp(spd, BASE_HAZARD_SPEED, MAX_HAZARD_SPEED)


func _gap_ratio() -> float:
	var t: float = float(tier) / float(MAX_TIER)
	var g: float = lerp(BASE_GAP_RATIO, MIN_GAP_RATIO, t)
	return clamp(g, MIN_GAP_RATIO, BASE_GAP_RATIO)


func _populate_lane(lane_entry: Dictionary, _idx: int) -> void:
	# Fill a lane with hazard rects, leaving guaranteed gaps >= CELL * 2.
	# We lay out tiles across a virtual stretch 3× the field width (wrapping),
	# then let them scroll into view.
	var gap_r: float = _gap_ratio()
	lane_entry["hazards"] = []
	var x: float = 0.0
	var field_w: float = CELL * float(NUM_CELLS_X)
	var wrap: float = field_w * 2.5   # tile repeat width
	while x < wrap:
		var gap_w: float = CELL * 2.0 + randf() * CELL * (gap_r * 6.0)
		x += gap_w
		if x >= wrap:
			break
		var haz_w: float = CELL * (1.0 + randf() * 1.5)
		# Clamp so gap after never causes wrap issues
		haz_w = clamp(haz_w, CELL, CELL * 3.0)
		lane_entry["hazards"].append({ "x": x, "w": haz_w })
		x += haz_w


# ============================================================
# Input — tap to hop; swipe left/right to sidestep; restart
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_begin(event.position)
		else:
			_touch_end(event.position)
	elif event is InputEventScreenDrag:
		_touch_move(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_begin(event.position)
		else:
			_touch_end(event.position)
	elif event is InputEventMouseMotion:
		if touch_active:
			_touch_move(event.position)


func _touch_begin(pos: Vector2) -> void:
	touch_start  = pos
	touch_active = true
	if not alive:
		_start_game()


func _touch_move(pos: Vector2) -> void:
	if not touch_active:
		return
	if not alive:
		return
	# Detect horizontal swipe early so sidestep feels instant
	var dx: float = pos.x - touch_start.x
	var dy: float = pos.y - touch_start.y
	if abs(dx) > SWIPE_MIN_PX and abs(dx) > abs(dy) * 1.2:
		# Queue a sidestep (only one per touch gesture)
		pending_sidestep = 1 if dx > 0 else -1
		# Reset start so the same finger doesn't fire twice
		touch_start = pos


func _touch_end(pos: Vector2) -> void:
	if not touch_active:
		return
	touch_active = false
	if not alive:
		return
	var dx: float = pos.x - touch_start.x
	var dy: float = pos.y - touch_start.y
	# If it was more of a tap (tiny travel) → hop forward
	if abs(dx) < SWIPE_MIN_PX and abs(dy) < SWIPE_MIN_PX * 2.0:
		_hop(1)
	# Horizontal swipe on release as fallback
	elif abs(dx) > SWIPE_MIN_PX and abs(dx) > abs(dy) * 1.2 and pending_sidestep == 0:
		pending_sidestep = 1 if dx > 0 else -1


# ============================================================
# Core actions
# ============================================================
func _hop(dir: int) -> void:
	# dir: +1 = toward goal (forward), -1 = backward
	if not alive:
		return
	var new_lane: int = hero_lane + dir
	new_lane = clamp(new_lane, 0, NUM_HAZARD_LANES + 1)
	if new_lane == hero_lane:
		return
	hero_lane = new_lane
	hop_anim = HOP_ANIM_FRAMES
	hop_dir  = dir
	_play_sfx("hop")

	# Track backtracking for streak penalty
	if dir < 0:
		backtrack_count += 1

	# Crossing detection: reached the goal lane
	if hero_lane == NUM_HAZARD_LANES + 1:
		_on_crossing()


func _sidestep(dir: int) -> void:
	# dir: +1 = right, -1 = left
	if not alive:
		return
	var new_col: int = hero_col + dir
	new_col = clamp(new_col, 0, NUM_CELLS_X - 1)
	hero_col = new_col


func _on_crossing() -> void:
	crossings += 1
	# Base score per crossing
	var pts: int = 1

	# Speed-cross streak bonus: crossed quickly without backtracking
	var quick: bool = (cross_timer < STREAK_TIME and backtrack_count == 0)
	if quick:
		streak_count = min(streak_count + 1, MAX_STREAK)
		pts += streak_count * STREAK_BONUS_BASE
		_play_sfx("streak")   # rising arpeggio on a quick (bonus) crossing
	else:
		streak_count = 0

	score += pts
	best = max(best, score)
	score_pulse     = 1.0
	score_pop_timer = 0.22
	_play_sfx("cross")

	# Ramp difficulty every N crossings
	if crossings % RAMP_EVERY_N_CROSSINGS == 0:
		tier = min(tier + 1, MAX_TIER)

	# Reset field: hero goes back to bottom, field deepens (lanes respawn)
	hero_lane = 0
	cross_timer = 0.0
	backtrack_count = 0
	_build_lanes()


# ============================================================
# Main update loop
# ============================================================
func _process(delta: float) -> void:
	if alive:
		cross_timer += delta
		_apply_pending_sidestep()
		_update_hazards(delta)
		_check_collision()

	_update_juice(delta)
	queue_redraw()


func _apply_pending_sidestep() -> void:
	if pending_sidestep != 0:
		_sidestep(pending_sidestep)
		pending_sidestep = 0


func _update_hazards(delta: float) -> void:
	# Scroll each lane's hazards; wrap around the tile repeat width
	var field_w: float = CELL * float(NUM_CELLS_X)
	var wrap: float = field_w * 2.5
	for i in range(lanes.size()):
		var lane: Dictionary = lanes[i]
		var spd: float = float(lane["speed"])
		var dir: int   = int(lane["dir"])
		var hazards: Array = lane["hazards"]
		var dx: float = spd * float(dir) * delta
		for j in range(hazards.size()):
			var h: Dictionary = hazards[j]
			var new_x: float = float(h["x"]) + dx
			# Wrap within tile repeat
			new_x = fposmod(new_x, wrap)
			h["x"] = new_x


func _check_collision() -> void:
	if not alive:
		return
	# Hero only collides in hazard lanes (1..NUM_HAZARD_LANES)
	if hero_lane < 1 or hero_lane > NUM_HAZARD_LANES:
		return

	var lane_idx: int = hero_lane - 1   # 0-indexed into lanes[]
	if lane_idx >= lanes.size():
		return

	var lane: Dictionary = lanes[lane_idx]
	var hazards: Array = lane["hazards"]

	# Hero rect in field-local x coordinates
	var hero_left: float  = float(hero_col) * CELL + 4.0
	var hero_right: float = hero_left + HERO_SIZE - 8.0

	var field_w: float = CELL * float(NUM_CELLS_X)
	var wrap: float    = field_w * 2.5

	for h in hazards:
		var hx: float = float(h["x"])
		var hw: float = float(h["w"])
		# Check against primary position and wrap copies
		for offset in [0.0, wrap, -wrap]:
			var lx: float = hx + offset
			var rx: float = lx + hw
			if lx < hero_right and rx > hero_left:
				_game_over()
				return


func _game_over() -> void:
	alive       = false
	shake       = SHAKE_MAG
	white_flash = FLASH_FRAMES
	_play_sfx("gameover")


func _update_juice(delta: float) -> void:
	var new_shake: float = lerp(shake, 0.0, clamp(SHAKE_DECAY * delta, 0.0, 1.0))
	shake = new_shake
	if shake < 0.5:
		shake = 0.0
	if white_flash > 0:
		white_flash -= 1
	score_pulse = max(score_pulse - 3.5 * delta, 0.0)
	score_pop_timer = max(score_pop_timer - delta, 0.0)
	if hop_anim > 0:
		hop_anim -= 1


# ============================================================
# Rendering — all in _draw(), layered: BG → lanes → hazards
#             → hero → HUD
# ============================================================
func _draw() -> void:
	# Shake offset
	if shake > 0.0:
		shake_offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		shake_offset = Vector2.ZERO

	draw_set_transform(shake_offset, 0.0, Vector2.ONE)

	_draw_background()
	_draw_lanes()
	_draw_hazards_layer()
	_draw_hero()

	# White flash (death feedback) drawn over world, under HUD
	if white_flash > 0:
		draw_rect(Rect2(0, 0, screen_w, screen_h), Color(1, 1, 1, 0.85))

	# HUD always drawn last without shake
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()


func _draw_background() -> void:
	# Dark near-black fill outside field
	draw_rect(Rect2(0, 0, screen_w, screen_h), COL_BG)

	# Faint pixel-grid overlay on the field area (retro look)
	var field_w: float  = CELL * float(NUM_CELLS_X)
	var field_h: float  = LANE_H * float(TOTAL_LANES)
	# Vertical grid lines
	for cx in range(NUM_CELLS_X + 1):
		var gx: float = FIELD_LEFT + float(cx) * CELL
		draw_line(Vector2(gx, FIELD_TOP), Vector2(gx, FIELD_TOP + field_h), COL_GRID, 1.0)
	# Horizontal grid lines (every CELL row within each lane)
	var num_h_lines: int = int(field_h / CELL) + 1
	for ry in range(num_h_lines):
		var gy: float = FIELD_TOP + float(ry) * CELL
		draw_line(Vector2(FIELD_LEFT, gy), Vector2(FIELD_LEFT + field_w, gy), COL_GRID, 1.0)


func _draw_lanes() -> void:
	for ln in range(TOTAL_LANES):
		# Lane y: lane 0 = bottom; TOTAL_LANES-1 = top
		var lany: float = FIELD_TOP + float(TOTAL_LANES - 1 - ln) * LANE_H
		var lane_rect: Rect2 = Rect2(FIELD_LEFT, lany, CELL * float(NUM_CELLS_X), LANE_H)

		if ln == 0:
			# Safe starting row — grass
			draw_rect(lane_rect, COL_SAFE_ZONE)
		elif ln == NUM_HAZARD_LANES + 1:
			# Goal row — bright yellow stripe
			draw_rect(lane_rect, COL_GOAL)
			# Dashed finish line
			var dash_y: float = lany + LANE_H * 0.5
			var dash_w: float = 20.0
			var dash_gap: float = 12.0
			var cx: float = FIELD_LEFT
			while cx < FIELD_LEFT + CELL * float(NUM_CELLS_X):
				draw_line(Vector2(cx, dash_y), Vector2(cx + dash_w, dash_y), Color(1, 1, 1, 0.7), 4.0)
				cx += dash_w + dash_gap
		else:
			# Hazard lanes: alternate grass/dirt/road
			var mod3: int = ln % 3
			var col: Color
			if mod3 == 1:
				col = COL_LANE_DIRT
			elif mod3 == 2:
				col = COL_LANE_ROAD
			else:
				col = COL_LANE_GRASS
			draw_rect(lane_rect, col)
			# Lane edge lines (road markings)
			draw_line(Vector2(FIELD_LEFT, lany), Vector2(FIELD_LEFT + CELL * float(NUM_CELLS_X), lany), Color(0, 0, 0, 0.25), 2.0)


func _draw_hazards_layer() -> void:
	# Draw each lane's hazards as packs of tiled pixel-demon sprites.
	for i in range(lanes.size()):
		# lane index i → lane_row i+1
		var lane_row: int = i + 1
		var lane_y: float = FIELD_TOP + float(TOTAL_LANES - 1 - lane_row) * LANE_H

		var lane: Dictionary = lanes[i]
		var hazards: Array   = lane["hazards"]
		var field_w: float   = CELL * float(NUM_CELLS_X)
		var wrap: float      = field_w * 2.5

		for h in hazards:
			var hx: float = float(h["x"])
			var hw: float = float(h["w"])
			# Draw at primary position and wrap copies that are visible
			for offset in [0.0, wrap, -wrap]:
				var draw_x: float = FIELD_LEFT + hx + offset
				# Clip to field bounds + 1 cell margin
				if draw_x + hw < FIELD_LEFT - CELL:
					continue
				if draw_x > FIELD_LEFT + field_w + CELL:
					continue
				if tex_hazard == null:
					continue
				# Fill the bar with N exact-fit pixel-demon units (a pack of
				# creatures) so a variable bar width never stretches a sprite:
				# visual width == collision width, square pixels preserved.
				var unit_y: float = lane_y + (LANE_H - HAZ_UNIT) * 0.5
				var n: int = int(round(hw / HAZ_UNIT))
				if n < 1:
					n = 1
				var uw: float = hw / float(n)
				for k in range(n):
					draw_texture_rect(tex_hazard, Rect2(draw_x + float(k) * uw, unit_y, uw, HAZ_UNIT), false)


func _draw_hero() -> void:
	# Hero's screen position (snapped to cell grid — discrete, no smooth easing)
	# Cell center (discrete grid — no smooth easing).
	var cx: float = FIELD_LEFT + float(hero_col) * CELL + CELL * 0.5
	var cy: float = FIELD_TOP + float(TOTAL_LANES - 1 - hero_lane) * LANE_H + LANE_H * 0.5

	# Hop animation: small y offset pop (no smooth lerp — retro snap feel)
	var pop_y: float = 0.0
	if hop_anim > 0:
		pop_y = -8.0 * float(hop_anim) / float(HOP_ANIM_FRAMES) * float(hop_dir)

	# Pixel-art hero sprite, centered on its cell (visual ~64px; footprint = HERO_SIZE).
	if tex_hero != null:
		draw_texture_rect(tex_hero, Rect2(cx - HERO_DRAW * 0.5, cy - HERO_DRAW * 0.5 + pop_y, HERO_DRAW, HERO_DRAW), false)


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	# Dark HUD band at top
	draw_rect(Rect2(0, 0, screen_w, 152.0), Color(0, 0, 0, 0.65))

	# Score (top-center) with scale-pop
	var score_sz: float = 58.0 + score_pulse * 18.0
	var score_col: Color = COL_HUD.lerp(Color(1, 1, 1), score_pulse * 0.6)
	draw_string(font, Vector2(0, 76), str(score),
		HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), int(score_sz), score_col)

	# Streak indicator (top-right)
	if streak_count > 0:
		var sc: Color = Color(1.0, 0.55, 0.15)
		draw_string(font, Vector2(screen_w - 220.0, 55), "STREAK x" + str(streak_count),
			HORIZONTAL_ALIGNMENT_RIGHT, 210, 26, sc)

	# Tier (top-left)
	if tier > 0:
		draw_string(font, Vector2(20, 55), "TIER " + str(tier + 1),
			HORIZONTAL_ALIGNMENT_LEFT, 160, 24, Color(0.65, 0.90, 0.55, 0.75))

	# Cross timer indicator (shows remaining streak window)
	if alive and hero_lane > 0 and hero_lane <= NUM_HAZARD_LANES:
		var remaining: float = clamp(STREAK_TIME - cross_timer, 0.0, STREAK_TIME)
		var bar_w: float = (remaining / STREAK_TIME) * (screen_w * 0.5)
		var bar_x: float = screen_w * 0.25
		draw_rect(Rect2(bar_x, 120.0, screen_w * 0.5, 8.0), Color(0.2, 0.2, 0.2, 0.5))
		draw_rect(Rect2(bar_x, 120.0, bar_w, 8.0), Color(1.0, 0.8, 0.2, 0.85))

	# Game over overlay
	if not alive:
		draw_rect(Rect2(0, 0, screen_w, screen_h), Color(0, 0, 0, 0.52))
		draw_string(font, Vector2(0, screen_h * 0.42), "GAME OVER",
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 64, Color(0.95, 0.28, 0.22))
		draw_string(font, Vector2(0, screen_h * 0.51), "SCORE  " + str(score),
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 44, COL_HUD)
		if best > 0:
			draw_string(font, Vector2(0, screen_h * 0.58), "BEST  " + str(best),
				HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 32, Color(0.75, 0.68, 0.38))
		draw_string(font, Vector2(0, screen_h * 0.66), "TAP TO RESTART",
			HORIZONTAL_ALIGNMENT_CENTER, int(screen_w), 36, Color(1, 1, 1, 0.9))
