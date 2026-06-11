extends RefCounted
## Static upgrade tracks: 3 tool tracks (gathering) + 3 shop tracks (selling).
## preload + static funcs only — no autoload (headless self-test rule).

const TOOL_TRACKS: Array = ["haul", "tide", "rare"]
const SHOP_TRACKS: Array = ["shelf", "patience", "traffic"]

const TRACKS: Dictionary = {
	"haul": {"name": "Bigger Basket", "desc": "+1 carried before banking", "max": 4, "costs": [20, 45, 80, 130]},
	"tide": {"name": "Tide Charts", "desc": "+6s gathering window", "max": 4, "costs": [25, 50, 90, 140]},
	"rare": {"name": "Pry Bar", "desc": "Rarer finds in far pools", "max": 2, "costs": [60, 120]},
	"shelf": {"name": "Extra Shelf", "desc": "+1 shop shelf slot", "max": 4, "costs": [30, 60, 100, 150]},
	"patience": {"name": "Cozy Decor", "desc": "Patrons wait longer", "max": 3, "costs": [40, 80, 140]},
	"traffic": {"name": "Sign Board", "desc": "+1 patron each day", "max": 3, "costs": [35, 70, 120]},
}


static func track(id: String) -> Dictionary:
	return TRACKS[id]


static func max_level(id: String) -> int:
	var t: Dictionary = TRACKS[id]
	return t["max"]


## Cost of buying the NEXT level given the current one; -1 when maxed.
static func cost(id: String, current_level: int) -> int:
	var t: Dictionary = TRACKS[id]
	var mx: int = t["max"]
	if current_level >= mx:
		return -1
	var costs: Array = t["costs"]
	return costs[current_level]
