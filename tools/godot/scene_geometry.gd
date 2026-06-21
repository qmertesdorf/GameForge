extends SceneTree

# Deterministic GEOMETRY probe for the visual-audit geometry pre-filter. Instantiates
# Main.tscn, lets the layout settle, then walks the tree for CanvasItem nodes and emits
# each visible node's on-screen rect + paint order + raw opacity signals + texture state.
# The JS side (scene-geom.mjs scoreGeometry) decides off-viewport / occlusion /
# missing-texture. Purely a READER — no scoring here (threshold stays a JS knob).
#
# Headless is fine — we read layout metrics (CPU-side), not pixels.
#   godot --headless --path games/<id>/ --script res://scene_geometry.gd
#
# LIMITATION: only introspectable CanvasItem geometry (Control rects, textured Node2D).
# Art drawn via a custom _draw()/draw_texture() is NOT visible here.
# LIMITATION: mod_a is a node's OWN alpha (modulate * self_modulate); ancestor modulate
# is NOT walked, so a node under a faded parent still reads opaque to the occlusion check.

# Texture-requiring node classes for the missing-texture check. AnimatedSprite2D is
# intentionally excluded: it uses sprite_frames (not `texture`) AND, as a Node2D that is
# neither Control nor Sprite2D, _rect_of() returns null for it so it is never emitted anyway.
const TEX_CLASSES := ["Sprite2D", "TextureRect", "TextureButton", "NinePatchRect"]
const TEXT_CLASSES := ["Label", "RichTextLabel", "Button", "LineEdit", "TextEdit", "CheckBox", "CheckButton", "OptionButton"]
const INTERACTIVE_CLASSES := ["Button", "TextureButton", "LineEdit", "TextEdit", "CheckBox", "CheckButton", "OptionButton", "HSlider", "VSlider"]

var _paint := 0

func _initialize() -> void:
	var packed := load("res://Main.tscn")
	if packed == null:
		push_error("scene_geometry: could not load res://Main.tscn")
		quit(1)
		return
	get_root().add_child(packed.instantiate())
	await _emit()

func _emit() -> void:
	for _i in range(10):       # let anchors/containers resolve sizes
		await process_frame
	var nodes: Array = []
	_walk(get_root(), nodes)
	var vp: Vector2 = get_root().get_visible_rect().size
	print("SCENE_GEOMETRY ", JSON.stringify({"viewport": [int(vp.x), int(vp.y)], "nodes": nodes}))
	quit(0)

func _walk(node: Node, out: Array) -> void:
	if node is CanvasItem:
		var ci := node as CanvasItem
		var rect = _rect_of(ci)
		if rect != null:
			var cls := ci.get_class()
			var has_tex := _has_texture(ci)
			out.append({
				"path": String(ci.get_path()),
				"class": cls,
				"rect": rect,
				"paint": _paint,
				"z_index": ci.z_index if ci is Node2D else 0,
				"mod_a": ci.modulate.a * ci.self_modulate.a,
				"fill_a": _fill_alpha(ci),
				"has_texture": has_tex,
				"texture_null": (cls in TEX_CLASSES) and not has_tex,
				"interactive": cls in INTERACTIVE_CLASSES,
				"is_text": _is_text(ci),
				"visible": ci.is_visible_in_tree(),
			})
		_paint += 1
	for child in node.get_children():
		_walk(child, out)

# On-screen rect [x,y,w,h] as ints, or null if the node has no measurable extent.
# Only Control (get_global_rect) and textured Sprite2D are measured; any other CanvasItem
# (e.g. a bare Node2D / custom _draw container) returns null here and is skipped by _walk.
func _rect_of(ci: CanvasItem):
	if ci is Control:
		var r: Rect2 = (ci as Control).get_global_rect()
		return [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
	if ci is Sprite2D and (ci as Sprite2D).texture != null:
		var s := ci as Sprite2D
		var sz: Vector2 = s.texture.get_size() * s.global_scale
		var pos: Vector2 = s.global_position
		if s.centered:
			pos -= sz * 0.5
		pos += s.offset
		return [int(pos.x), int(pos.y), int(sz.x), int(sz.y)]
	return null

func _has_texture(ci: CanvasItem) -> bool:
	if ci.has_method("get_texture"):
		return ci.get("texture") != null
	return false

# bg_color.a of a StyleBoxFlat panel/normal stylebox, or null when none.
func _fill_alpha(ci: CanvasItem):
	if not (ci is Control):
		return null
	var c := ci as Control
	for sb_name in ["panel", "normal"]:
		if c.has_theme_stylebox(sb_name):
			var sb := c.get_theme_stylebox(sb_name)
			if sb is StyleBoxFlat:
				return (sb as StyleBoxFlat).bg_color.a
	return null

func _is_text(ci: CanvasItem) -> bool:
	if not (ci.get_class() in TEXT_CLASSES):
		return false
	var t = ci.get("text")
	return t != null and String(t).strip_edges() != ""
