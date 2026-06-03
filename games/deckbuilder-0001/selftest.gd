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
	# Stage 1.5: a neutral attack spends mana and damages the enemy.
	var ehp0: int = cs.enemy.hp
	var mana0: int = cs.mana
	var bolt_idx := _find_card(cs.hand, "arcane_bolt")
	if bolt_idx < 0:
		# guarantee a known card in hand deterministically for the test
		cs.hand.insert(0, "arcane_bolt"); bolt_idx = 0
	cs.play_card(bolt_idx)
	if cs.mana >= mana0:
		_fail("playing Arcane Bolt did not spend mana"); return
	if cs.enemy.hp != ehp0 - 6:
		_fail("Arcane Bolt dealt %d, expected 6" % (ehp0 - cs.enemy.hp)); return
	# Stage 2: Fire applies Burn; Lightning cashes it in for bonus damage; end_turn resolves enemy + ticks.
	cs.hand.insert(0, "ember")            # fire: damage + burn
	cs.mana = cs.mana_max                 # ensure castable for the deterministic test
	var ehp1: int = cs.enemy.hp
	cs.play_card(0)
	if cs.enemy.statuses.burn <= 0:
		_fail("Ember did not apply Burn"); return
	# Lightning into a Burning enemy: bonus branch must fire.
	cs.hand.insert(0, "chain_lightning") # lightning: base + lightning_bonus vs afflicted
	cs.mana = cs.mana_max
	var base: int = CardDB.card("chain_lightning").effect.get("damage", 0)
	var ehp2: int = cs.enemy.hp
	cs.play_card(0)
	if (ehp2 - cs.enemy.hp) <= base:
		_fail("Chain Lightning did not apply combo bonus vs Burning target"); return
	# End turn: enemy acts and Burn ticks + decrements.
	var php0: int = cs.player_hp
	var burn0: int = cs.enemy.statuses.burn
	var ehp3: int = cs.enemy.hp
	cs.end_turn()
	var acted: bool = (cs.player_hp < php0) or (cs.enemy.intent.get("type","") == "defend")
	if not acted:
		_fail("enemy did not act on end_turn"); return
	if not (cs.enemy.statuses.burn < burn0 and cs.enemy.hp < ehp3):
		_fail("Burn did not tick + decrement on end_turn"); return
	# --- Stage 3 (Task 13) appends here ---
	print("SELFTEST OK")
	quit(0)

func _find_card(hand: Array, id: String) -> int:
	for i in hand.size():
		if hand[i] == id:
			return i
	return -1
