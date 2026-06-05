extends RefCounted

# A branching run map: rows ("floors") of nodes connected by edges.
# Pure data + query helpers. No rendering, no RNG (generation lives in MapGen).
#
# node = {"id": int, "floor": int, "col": int, "type": String, "next": Array[int]}

var _nodes: Dictionary = {}      # id -> node dict
var _floors: Array = []          # floor index -> Array[int] of node ids (ordered by col)
var _next_id: int = 0

func add_node(floor: int, col: int, type: String) -> int:
	var id: int = _next_id
	_next_id += 1
	_nodes[id] = {"id": id, "floor": floor, "col": col, "type": type, "next": []}
	while _floors.size() <= floor:
		_floors.append([])
	_floors[floor].append(id)
	return id

func add_edge(from_id: int, to_id: int) -> void:
	var nxt: Array = _nodes[from_id]["next"]
	if not (to_id in nxt):
		nxt.append(to_id)

func node(id: int) -> Dictionary:
	return _nodes.get(id, {})

func floor_count() -> int:
	return _floors.size()

func nodes_on_floor(floor: int) -> Array:
	if floor < 0 or floor >= _floors.size():
		return []
	return _floors[floor].duplicate()

func next_of(id: int) -> Array:
	return _nodes.get(id, {}).get("next", []).duplicate()

func count_type(type: String) -> int:
	var c: int = 0
	for id in _nodes:
		if _nodes[id]["type"] == type:
			c += 1
	return c

# Every node can reach target via forward edges.
func all_nodes_reach(target_id: int) -> bool:
	for id in _nodes:
		if not _reaches(id, target_id):
			return false
	return true

func _reaches(start_id: int, target_id: int) -> bool:
	if start_id == target_id:
		return true
	var stack: Array = [start_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		if cur == target_id:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		for nx in _nodes.get(cur, {}).get("next", []):
			stack.append(nx)
	return false

# Stable string fingerprint of the whole structure (for determinism checks).
func fingerprint() -> String:
	var parts: Array = []
	var ids: Array = _nodes.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = _nodes[id]
		var nxt: Array = n["next"].duplicate(); nxt.sort()
		parts.append("%d:%d:%d:%s:%s" % [id, n["floor"], n["col"], n["type"], str(nxt)])
	return "|".join(parts)
