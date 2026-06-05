extends RefCounted

const MapModel := preload("res://MapModel.gd")

const FLOORS := 10

# Generate a deterministic branching map from a seeded rng.
static func generate(rng: RandomNumberGenerator) -> MapModel:
	var m = MapModel.new()

	# 1) Place nodes floor by floor (types assigned after, so we can enforce guarantees).
	var floor_widths: Array = []
	for fl in range(FLOORS):
		var w: int
		if fl == 0:
			w = 2
		elif fl == FLOORS - 1:
			w = 1                      # boss floor
		else:
			w = rng.randi_range(2, 3)
		floor_widths.append(w)
		for col in range(w):
			m.add_node(fl, col, "combat")  # placeholder type, reassigned below

	# 2) Connect each node to 1-2 nodes on the next floor within col distance 1.
	for fl in range(FLOORS - 1):
		var here: Array = m.nodes_on_floor(fl)
		var there: Array = m.nodes_on_floor(fl + 1)
		for from_id in here:
			var from_col: int = m.node(from_id)["col"]
			# candidate targets within +-1 column
			var cands: Array = []
			for to_id in there:
				if abs(m.node(to_id)["col"] - from_col) <= 1:
					cands.append(to_id)
			if cands.is_empty():
				cands = there.duplicate()   # fallback: connect to anything
			_shuffle(cands, rng)
			var k: int = 1 if cands.size() == 1 else rng.randi_range(1, 2)
			for i in range(min(k, cands.size())):
				m.add_edge(from_id, cands[i])
		# Ensure every next-floor node has at least one incoming edge.
		for to_id in there:
			var has_in: bool = false
			for from_id in here:
				if to_id in m.next_of(from_id):
					has_in = true
					break
			if not has_in:
				# connect from the column-nearest source
				var best: int = here[0]
				var best_d: int = 9999
				for from_id in here:
					var d: int = abs(m.node(from_id)["col"] - m.node(to_id)["col"])
					if d < best_d:
						best_d = d; best = from_id
				m.add_edge(best, to_id)

	# 3) Assign types.
	var boss_id: int = m.nodes_on_floor(FLOORS - 1)[0]
	m.node(boss_id)["type"] = "boss"
	for nid in m.nodes_on_floor(FLOORS - 2):
		m.node(nid)["type"] = "campfire"     # always a rest before the boss
	for nid in m.nodes_on_floor(0):
		m.node(nid)["type"] = "combat"       # entries are combats
	for fl in range(1, FLOORS - 2):
		for nid in m.nodes_on_floor(fl):
			m.node(nid)["type"] = _roll_type(rng, fl)

	# 4) Guarantee at least one shop and one event on floors 1..(FLOORS-3).
	_guarantee_type(m, rng, "shop")
	_guarantee_type(m, rng, "event")

	return m

static func _roll_type(rng: RandomNumberGenerator, floor: int) -> String:
	var r: int = rng.randi_range(0, 99)
	if r < 50: return "combat"
	if r < 70: return "event"
	if r < 82:
		return "elite" if floor >= 3 else "combat"
	if r < 92: return "shop"
	return "treasure"

static func _guarantee_type(m, rng: RandomNumberGenerator, type: String) -> void:
	if m.count_type(type) >= 1:
		return
	# Force-place on a random combat node in the eligible band.
	var candidates: Array = []
	for fl in range(1, m.floor_count() - 2):
		for nid in m.nodes_on_floor(fl):
			if m.node(nid)["type"] == "combat":
				candidates.append(nid)
	if candidates.is_empty():
		return
	_shuffle(candidates, rng)
	m.node(candidates[0])["type"] = type

# Fisher-Yates with the seeded rng (NEVER Array.shuffle).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
