extends SceneTree

# Headless `--script` SceneTree runs do NOT instantiate project autoloads, so the
# data layers are reached via preloaded script classes (static funcs), never the
# autoload globals. The rules engine (CombatState) does the same.
const CardDB := preload("res://data/CardDB.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")
const MetaSave := preload("res://MetaSave.gd")

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
	# Stage 3: win → reward pick-1-of-3 → run advances; boss win writes the meta save.
	var RunController := load("res://RunController.gd")
	var run = RunController.new()
	run.start_run(SEED)
	var combat = run.start_node_combat()
	combat.enemy.hp = 1
	combat.hand.insert(0, "arcane_bolt"); combat.mana = combat.mana_max
	combat.play_card(0)
	if not combat.is_won():
		_fail("forcing enemy to 1 HP + a hit did not win the combat"); return
	var rewards: Array = run.offer_rewards()
	if rewards.size() != 3:
		_fail("reward screen offered %d cards, expected 3" % rewards.size()); return
	run.choose_reward(rewards[0])
	var node_before: Dictionary = run.current_node()
	run.advance()
	if run.current_node() == node_before:
		_fail("run did not advance after reward"); return
	# Ensure the meta-save assertion reflects THIS run, not a stale user://save.json.
	if FileAccess.file_exists("user://save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.json"))
	# Boss-win meta write (drive directly to the boss outcome).
	run.force_boss_defeat_for_test()
	var state: Dictionary = MetaSave.new().load_state()
	if state.get("unlocked_cards", []).is_empty():
		_fail("boss win did not unlock a card in user://save.json"); return
	# Lose path.
	combat.player_hp = 0
	if not combat.is_lost():
		_fail("player_hp 0 did not register as lost"); return
	# Stage 4: power cards have real, persistent effects.
	var CS2 := load("res://CombatState.gd")
	var p = CS2.new()
	p.setup(SEED, CardDB.starter_deck(), "imp")
	p.start_combat()
	# Overload: +2 damage to an afflicted enemy.
	p.enemy.statuses.burn = 1                      # afflict the enemy
	p.hand.insert(0, "arcane_bolt"); p.mana = p.mana_max
	var oh0: int = p.enemy.hp
	p.play_card(0)                                  # arcane_bolt = 6, no overload yet
	var base_hit: int = oh0 - p.enemy.hp
	p.hand.insert(0, "overload"); p.mana = p.mana_max
	p.play_card(0)                                  # activate Overload (power)
	p.enemy.statuses.burn = 1                       # keep afflicted
	p.hand.insert(0, "arcane_bolt"); p.mana = p.mana_max
	var oh1: int = p.enemy.hp
	p.play_card(0)                                  # arcane_bolt now +2 vs afflicted
	var boosted_hit: int = oh1 - p.enemy.hp
	if boosted_hit != base_hit + 2:
		_fail("Overload did not add +2 vs an afflicted enemy (base %d, boosted %d)" % [base_hit, boosted_hit]); return
	# Wildfire: attacks also apply Burn.
	var w = CS2.new()
	w.setup(SEED, CardDB.starter_deck(), "imp")
	w.start_combat()
	w.enemy.statuses.burn = 0
	w.hand.insert(0, "wildfire"); w.mana = w.mana_max
	w.play_card(0)                                  # activate Wildfire (power)
	w.hand.insert(0, "arcane_bolt"); w.mana = w.mana_max
	w.play_card(0)                                  # attack -> should also apply 1 Burn
	if w.enemy.statuses.burn < 1:
		_fail("Wildfire did not make an attack apply Burn"); return
	# --- end stages ---
	print("SELFTEST OK")
	quit(0)

func _find_card(hand: Array, id: String) -> int:
	for i in hand.size():
		if hand[i] == id:
			return i
	return -1
