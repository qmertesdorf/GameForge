extends RefCounted

# RunController orchestrates a full deckbuilder run:
#   5 nodes: combat(imp) → combat(frost_wraith) → rest → elite(golem) → boss(archmage)
# Sits on top of CombatState (combat rules). Headless/pure — no rendering, no autoload.

const CardDB := preload("res://data/CardDB.gd")
const CombatState := preload("res://CombatState.gd")
const MetaSave := preload("res://MetaSave.gd")

# Run state.
var rng: RandomNumberGenerator
var deck: Array
var nodes: Array
var node_i: int
var relics: Array
var _complete: bool
var _lost: bool


func start_run(seed_value: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	deck = CardDB.starter_deck().duplicate()

	nodes = [
		{"type": "combat", "enemy": "imp"},
		{"type": "combat", "enemy": "frost_wraith"},
		{"type": "rest"},
		{"type": "elite",  "enemy": "golem"},
		{"type": "boss",   "enemy": "archmage"},
	]
	node_i = 0

	relics = []
	_complete = false
	_lost = false

	# Starting relic: ember_heart — at start of combat, apply 1 Burn to the enemy.
	relics.append("ember_heart")


func current_node() -> Dictionary:
	if node_i < 0 or node_i >= nodes.size():
		return {}
	return nodes[node_i]


func start_node_combat() -> CombatState:
	var node: Dictionary = current_node()
	var enemy_id: String = node.get("enemy", "")

	var cs: CombatState = CombatState.new()
	cs.setup(rng.randi(), deck, enemy_id)
	cs.start_combat()

	# Apply relics.
	if "ember_heart" in relics:
		cs.enemy.statuses["burn"] = cs.enemy.statuses.get("burn", 0) + 1

	return cs


func offer_rewards() -> Array:
	# Return exactly 3 DISTINCT card ids drawn from CardDB.all_ids() using the seeded rng.
	# Deterministic given the seed: shuffle a copy of all_ids() and take the first 3.
	var all_ids: Array = CardDB.all_ids().duplicate()

	# Fisher-Yates shuffle using our seeded rng.
	var n: int = all_ids.size()
	for i in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = all_ids[i]
		all_ids[i] = all_ids[j]
		all_ids[j] = tmp

	# Return the first 3 distinct ids (already distinct since all_ids has no duplicates).
	var result: Array = []
	for k in range(3):
		result.append(all_ids[k])
	return result


func choose_reward(card_id: String) -> void:
	# Empty string = explicit skip; just no-op.
	if card_id.is_empty():
		return
	deck.append(card_id)


func take_rest(action: String) -> void:
	if action == "heal":
		# No persistent player HP across combats in this slice — recorded no-op.
		pass
	elif action == "remove":
		# Remove the first card from the deck (card removal).
		if not deck.is_empty():
			deck.remove_at(0)


func grant_elite_relic() -> void:
	relics.append("storm_core")


func advance() -> void:
	node_i += 1
	if node_i >= nodes.size():
		_complete = true


func is_run_complete() -> bool:
	return _complete


func is_run_lost() -> bool:
	return _lost


func on_boss_defeated() -> void:
	# Write meta-progression: unlock 1 new card + bump ascension + record best.
	var meta: MetaSave = MetaSave.new()
	var state: Dictionary = meta.load_state()

	var unlocked: Array = state.get("unlocked_cards", [])

	# Pick the first card from all_ids not already unlocked (deterministic).
	var candidate: String = ""
	for id in CardDB.all_ids():
		if not (id in unlocked):
			candidate = id
			break

	# Fallback: just use "immolate" (should always be available on a fresh save).
	if candidate.is_empty():
		candidate = "immolate"

	unlocked.append(candidate)
	state["unlocked_cards"] = unlocked
	state["ascension"] = max(state.get("ascension", 0), 1)
	# Record best as the boss enemy name.
	state["best"] = "archmage"

	meta.save_state(state)
	_complete = true


# TEST-ONLY: jump the cursor to the boss node and invoke the boss-win path directly.
# This lets the self-test exercise the meta write without playing all 5 nodes.
func force_boss_defeat_for_test() -> void:
	node_i = 4  # boss node index
	on_boss_defeated()
