extends Node2D

# MapView — draws the branching run map and the player's current position.
# Pure visual renderer (owns NO rules). Reads a MapModel passed via refresh().
# Immediate-mode: refresh() stores state + queue_redraw(); _draw() does everything.
#
# Contract (used by Main.gd):
#   refresh(map, cur_id: int, available: Array) -> void   # store + queue_redraw
#   get_node_rect(node_id: int) -> Rect2                   # hit-test for taps
#
# Layout: floor 0 at the BOTTOM, boss at the TOP; x by column, centered. Edges are
# drawn first (thin lines between connected node centers), then node markers coloured
# by type, then a ring/glow on the CURRENT node and a brighter highlight + larger hit
# target on each AVAILABLE-next node. Canvas is 1280×720 landscape.

# Viewport
const W: float = 1280.0
const H: float = 720.0

# Background palette (mirrors CombatView)
const COL_BG_TOP    := Color(0.102, 0.063, 0.188)  # #1a1030 indigo
const COL_BG_BOT    := Color(0.176, 0.106, 0.306)  # #2d1b4e violet
const COL_WHITE     := Color(1, 1, 1)
const COL_PANEL     := Color(0.08, 0.06, 0.14, 0.88)

# Edge line colour
const COL_EDGE      := Color(0.55, 0.42, 0.85, 0.45)
const COL_EDGE_HOT  := Color(0.95, 0.85, 0.40, 0.85)   # edge toward an available node

# Node marker geometry
const NODE_R: float = 20.0
const NODE_R_AVAIL: float = 27.0   # larger hit target for available-next nodes

# Layout margins
const MARGIN_X: float = 120.0
const MARGIN_TOP: float = 70.0
const MARGIN_BOT: float = 80.0

# Per-type marker colours (each distinct).
const TYPE_COLORS := {
	"combat":   Color(0.80, 0.30, 0.30),   # red
	"elite":    Color(0.95, 0.45, 0.10),   # orange
	"boss":     Color(0.85, 0.15, 0.75),   # magenta
	"event":    Color(0.30, 0.70, 0.95),   # cyan-blue
	"shop":     Color(0.95, 0.80, 0.25),   # gold
	"campfire": Color(0.35, 0.85, 0.45),   # green
	"treasure": Color(0.60, 0.85, 0.95),   # pale aqua
	"rest":     Color(0.35, 0.85, 0.45),   # green (legacy alias)
}

# Short type labels for markers.
const TYPE_LABELS := {
	"combat":   "FIGHT",
	"elite":    "ELITE",
	"boss":     "BOSS",
	"event":    "?",
	"shop":     "SHOP",
	"campfire": "REST",
	"treasure": "LOOT",
	"rest":     "REST",
}

var _map
var _cur_id: int = -1
var _available: Array = []

var _font: Font = null


func _ready() -> void:
	if ResourceLoader.exists("res://art/ui_font.ttf"):
		_font = load("res://art/ui_font.ttf")


func refresh(map, cur_id: int, available: Array) -> void:
	_map = map
	_cur_id = cur_id
	_available = available
	queue_redraw()


# ─── _draw ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_background()
	if _map == null:
		return

	var fcount: int = _map.floor_count()
	if fcount <= 0:
		return

	# 1) Edges first — thin lines between connected node centers.
	for fl in range(fcount):
		for nid in _map.nodes_on_floor(fl):
			var from_c: Vector2 = _center_of(nid)
			for to_id in _map.next_of(nid):
				var to_c: Vector2 = _center_of(to_id)
				var hot: bool = (nid == _cur_id) and (to_id in _available)
				draw_line(from_c, to_c, COL_EDGE_HOT if hot else COL_EDGE, 3.0 if hot else 2.0)

	# 2) Node markers, coloured by type.
	for fl in range(fcount):
		for nid in _map.nodes_on_floor(fl):
			_draw_node(nid)

	# 3) Title / legend strip.
	_draw_header()


func _draw_background() -> void:
	var bands: int = 16
	for i in bands:
		var t0: float = float(i) / float(bands)
		var t1: float = float(i + 1) / float(bands)
		var c: Color = COL_BG_TOP.lerp(COL_BG_BOT, (t0 + t1) * 0.5)
		draw_rect(Rect2(0.0, t0 * H, W, (t1 - t0) * H), c)


func _draw_node(nid: int) -> void:
	var node: Dictionary = _map.node(nid)
	if node.is_empty():
		return
	var ntype: String = node.get("type", "")
	var center: Vector2 = _center_of(nid)
	var base_col: Color = TYPE_COLORS.get(ntype, Color(0.6, 0.6, 0.65))

	var is_current: bool = (nid == _cur_id)
	var is_available: bool = (nid in _available)
	var r: float = NODE_R_AVAIL if is_available else NODE_R

	# Current node: pulsing ring/glow behind the marker.
	if is_current:
		draw_circle(center, r + 14.0, Color(0.95, 0.90, 0.40, 0.18))
		draw_arc(center, r + 9.0, 0.0, TAU, 40, Color(0.98, 0.92, 0.45, 0.95), 3.0)

	# Available node: brighter glow halo to draw the eye.
	if is_available:
		draw_circle(center, r + 10.0, Color(base_col.r, base_col.g, base_col.b, 0.30))
		draw_arc(center, r + 6.0, 0.0, TAU, 40, Color(1, 1, 1, 0.85), 2.0)

	# Marker disc — brighten if it's a choosable node.
	var disc_col: Color = base_col
	if is_available:
		disc_col = base_col.lerp(COL_WHITE, 0.25)
	elif not is_current:
		disc_col = base_col.darkened(0.15)
	draw_circle(center, r, disc_col)
	draw_arc(center, r, 0.0, TAU, 40, Color(0.05, 0.04, 0.10, 0.85), 2.0)

	# Type label centered on the marker (short text).
	var label: String = TYPE_LABELS.get(ntype, ntype.to_upper())
	_draw_text(center + Vector2(0.0, r + 16.0), label, 12, COL_WHITE, true)


func _draw_header() -> void:
	var panel := Rect2(0.0, 0.0, W, 40.0)
	draw_rect(panel, Color(0.05, 0.04, 0.11, 0.82))
	_draw_text(Vector2(W * 0.5, 26.0), "Choose your path", 18,
		Color(0.92, 0.86, 0.55), true)


# ─── Geometry ─────────────────────────────────────────────────────────────────

func _center_of(node_id: int) -> Vector2:
	var node: Dictionary = _map.node(node_id)
	if node.is_empty():
		return Vector2(W * 0.5, H * 0.5)
	return _node_center(node.get("floor", 0), node.get("col", 0),
		_map.nodes_on_floor(node.get("floor", 0)).size())


func _node_center(floor: int, col: int, width: int) -> Vector2:
	# (floor,col) → screen position. floor 0 at BOTTOM, last floor at TOP; columns
	# spread horizontally and centered. _draw and get_node_rect share this so they
	# always agree.
	var fcount: int = _map.floor_count() if _map != null else 1
	var usable_h: float = H - MARGIN_TOP - MARGIN_BOT
	var y: float
	if fcount <= 1:
		y = H - MARGIN_BOT
	else:
		# floor 0 → bottom (H-MARGIN_BOT), floor (fcount-1) → top (MARGIN_TOP).
		var fy: float = float(floor) / float(fcount - 1)
		y = (H - MARGIN_BOT) - fy * usable_h

	var usable_w: float = W - 2.0 * MARGIN_X
	var x: float
	if width <= 1:
		x = W * 0.5
	else:
		var fx: float = float(col) / float(width - 1)
		x = MARGIN_X + fx * usable_w
	return Vector2(x, y)


func get_node_rect(node_id: int) -> Rect2:
	# On-screen rect for a node marker; matches the positions used in _draw.
	# Use the larger available-node radius so the tap target is generous.
	var center: Vector2 = _center_of(node_id)
	var r: float = NODE_R_AVAIL + 8.0
	return Rect2(center.x - r, center.y - r, r * 2.0, r * 2.0)


# ─── Text helper (mirrors CombatView) ─────────────────────────────────────────

func _draw_text(pos: Vector2, text: String, size: int, col: Color, centered: bool = false) -> void:
	var font: Font = _font if _font != null else ThemeDB.fallback_font
	if font == null:
		return
	var off := Vector2(0.0, 0.0)
	if centered:
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		off.x = -tw * 0.5
	# Shadow for legibility, then the fill.
	draw_string(font, pos + off + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.85))
	draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
