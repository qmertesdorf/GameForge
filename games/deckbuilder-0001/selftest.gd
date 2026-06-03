extends SceneTree

# Headless `--script` SceneTree runs do NOT instantiate project autoloads, so the
# data layers are reached via preloaded script classes (static funcs), never the
# autoload globals. The rules engine (CombatState) does the same.
const CardDB := preload("res://data/CardDB.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")

const SEED := 12345

func _fail(msg: String) -> void:
	print("SELFTEST FAIL: ", msg)
	quit(1)

func _init() -> void:
	var CombatState := load("res://CombatState.gd")
	if CombatState == null:
		_fail("CombatState.gd missing")
		return
	var cs = CombatState.new()
	# Deterministic deck: 10-card starter, fixed order via seed.
	cs.setup(SEED, CardDB.starter_deck(), "imp")
	cs.start_combat()
	if cs.hand.size() != 5:
		_fail("opening hand was %d, expected 5" % cs.hand.size())
		return
	# --- later stages append assertions here (Tasks 9, 11, 13, 15) ---
	print("SELFTEST OK")
	quit(0)

func _find_card(hand: Array, id: String) -> int:
	for i in hand.size():
		if hand[i] == id:
			return i
	return -1
