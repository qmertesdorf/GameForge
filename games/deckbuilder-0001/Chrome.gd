extends RefCounted

# Chrome.gd — shared styled-UI primitives for the run-layer views (Map/Shop/Event/
# Campfire). Mirrors CombatView's rendered chrome (vertical-gradient body, top gloss,
# bevel frame, gauge fill, solid label pills) so every screen reads as one designed
# hand instead of flat programmer-art slabs. Static, immediate-mode: pass the calling
# CanvasItem as `ci`. CombatView keeps its own copies (already audited) — this is for
# the run layer only.

const WHITE := Color(1, 1, 1)


# Vertical gradient fill via a 4-vertex polygon (top colour → bottom colour).
static func vscrim(ci: CanvasItem, rect: Rect2, top: Color, bot: Color) -> void:
	var pts := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))


# Drop-shadowed string. `pos` is the draw_string baseline anchor; centred horizontally
# when asked.
static func text_shadow(ci: CanvasItem, font: Font, pos: Vector2, text: String,
		size: int, col: Color, centered: bool = false) -> void:
	if font == null:
		return
	var off := Vector2.ZERO
	if centered:
		off.x = -font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	ci.draw_string(font, pos + off + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		size, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# Rendered button: drop shadow → vertical-gradient body → top gloss → bevel frame →
# top highlight → centred label. Matches CombatView's End Turn button.
static func button(ci: CanvasItem, font: Font, rect: Rect2, label: String,
		base: Color, size: int = 18) -> void:
	ci.draw_rect(Rect2(rect.position + Vector2(0, 3), rect.size), Color(0, 0, 0, 0.40))
	vscrim(ci, rect, base.lerp(WHITE, 0.22), base.darkened(0.32))
	ci.draw_rect(Rect2(rect.position + Vector2(2, 2),
		Vector2(rect.size.x - 4, rect.size.y * 0.40)), Color(1, 1, 1, 0.16))
	ci.draw_rect(rect, base.darkened(0.55), false, 2.5)
	ci.draw_rect(Rect2(rect.position + Vector2(2, 1), Vector2(rect.size.x - 4, 1)),
		Color(1, 1, 1, 0.22))
	text_shadow(ci, font, rect.get_center() + Vector2(0, size * 0.34), label, size, WHITE, true)


# Rendered gauge: dark trough + top inner shadow, vertical-gradient fill with gloss +
# bright leading edge, bevel frame. Matches CombatView's HP bar.
static func bar(ci: CanvasItem, rect: Rect2, frac: float, fill_col: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	ci.draw_rect(rect, Color(0.05, 0.04, 0.09, 0.95))
	vscrim(ci, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5)),
		Color(0, 0, 0, 0.40), Color(0, 0, 0, 0.0))
	if frac > 0.0:
		var fw: float = rect.size.x * frac
		var fill := Rect2(rect.position, Vector2(fw, rect.size.y))
		vscrim(ci, fill, fill_col.lerp(WHITE, 0.30), fill_col.darkened(0.45))
		ci.draw_rect(Rect2(fill.position + Vector2(0, 1),
			Vector2(fw, maxf(2.0, rect.size.y * 0.30))), Color(1, 1, 1, 0.22))
		ci.draw_rect(Rect2(rect.position.x + fw - 2.0, rect.position.y, 2.0, rect.size.y),
			Color(1, 1, 1, 0.32))
	ci.draw_rect(rect, Color(0.02, 0.02, 0.05, 0.92), false, 2.0)


# A short string on a DEFINED solid pill — guaranteed contrast over busy painted art
# (a shadow alone fails over a bright patch). `baseline` is the draw_string anchor.
static func label_pill(ci: CanvasItem, font: Font, baseline: Vector2, text: String,
		size: int, col: Color) -> void:
	if font == null:
		return
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad_x: float = 5.0
	var pill := Rect2(baseline.x - tw * 0.5 - pad_x, baseline.y - size * 0.92,
		tw + pad_x * 2.0, size * 1.28)
	ci.draw_rect(pill, Color(0.05, 0.04, 0.11, 0.82))
	text_shadow(ci, font, baseline, text, size, col, true)
