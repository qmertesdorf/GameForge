extends SceneTree

# Deterministic text-metrics probe for the visual-audit legibility gate. Instantiates
# the game's Main.tscn, lets the Control layout settle, then walks the tree for
# text-bearing Control nodes and emits each one's RESOLVED font size + on-screen
# rect + text. The JS side (contrast.mjs scoreTextMetrics) scores min-text-size, and
# the emitted rects give the legibility/colour lenses deterministically-LOCATED text
# regions to measure (instead of VLM-guessed crops).
#
# Headless is fine — we read layout metrics (CPU-side), not pixels.
#   godot --headless --path games/<id>/ --script res://text_metrics.gd
#
# LIMITATION: only Control-based text (Label/RichTextLabel/Button/LineEdit/...) is
# visible here. Text drawn via a custom _draw() draw_string() is NOT introspectable
# and still needs the VLM legibility lens — the gate reports what it can SEE and
# never claims to have covered custom-drawn text.

func _initialize() -> void:
	var packed := load("res://Main.tscn")
	if packed == null:
		push_error("text_metrics: could not load res://Main.tscn")
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
	print("TEXT_METRICS ", JSON.stringify({"viewport": [vp.x, vp.y], "nodes": nodes}))
	quit(0)

func _walk(node: Node, out: Array) -> void:
	if node is Control:
		var c := node as Control
		var txt: String = ""
		if c.has_method("get_text"):
			var t = c.get("text")
			if t != null:
				txt = str(t)
		if txt.strip_edges() != "":
			var size_key := "normal_font_size" if c is RichTextLabel else "font_size"
			var fs: int = 0
			if c.has_method("get_theme_font_size"):
				fs = c.get_theme_font_size(size_key)
			var r: Rect2 = c.get_global_rect()
			out.append({
				"path": String(c.get_path()),
				"class": c.get_class(),
				"text": txt.substr(0, 40),
				"font_size": fs,
				"rect": [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)],
				"visible": c.is_visible_in_tree()
			})
	for child in node.get_children():
		_walk(child, out)
