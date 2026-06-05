extends RefCounted

const CardDB := preload("res://data/CardDB.gd")
const EnemyDB := preload("res://data/EnemyDB.gd")

var player_hp: int
var player_max_hp: int
var player_block: int

var mana: int
var mana_max: int

var draw_pile: Array
var hand: Array
var discard_pile: Array

var enemy: Dictionary

var rng: RandomNumberGenerator

# Active power ids for this combat (persistent until combat ends).
var powers: Array = []

# Internal intent index tracker — single source of truth (enemy["_intent_i"] removed).
var _intent_i: int = 0


func setup(seed_value: int, deck: Array, enemy_id: String, start_hp: int = -1) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	player_max_hp = 70
	player_hp = player_max_hp if start_hp < 0 else start_hp
	player_block = 0

	mana_max = 3
	mana = 0

	powers = []

	enemy = EnemyDB.enemy(enemy_id)
	# Ensure block, statuses, and strength keys exist on the mutable enemy copy.
	if not enemy.has("block"):
		enemy["block"] = 0
	if not enemy.has("statuses"):
		enemy["statuses"] = {"burn": 0, "chill": 0}
	if not enemy.has("strength"):
		enemy["strength"] = 0

	# Build draw_pile as a copy of the deck, then Fisher-Yates shuffle
	# using the seeded rng (NOT Array.shuffle which uses the global RNG).
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)

	hand = []
	discard_pile = []


func start_combat() -> void:
	_intent_i = 0
	enemy["intent"] = enemy["intents"][0]
	# NOTE: enemy["_intent_i"] intentionally NOT set — _intent_i is the sole tracker.
	start_turn()


func start_turn() -> void:
	player_block = 0
	mana = mana_max
	_draw(5)


func _draw(n: int) -> void:
	for _i in range(n):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				# Both piles empty — stop early.
				return
			# Reshuffle discard into draw pile.
			draw_pile = discard_pile.duplicate()
			discard_pile = []
			_shuffle(draw_pile)
		if draw_pile.is_empty():
			return
		var card_id: String = draw_pile.pop_back()
		hand.append(card_id)


func play_card(hand_index: int) -> Array:
	if hand_index < 0 or hand_index >= hand.size():
		return []

	var card_id: String = hand[hand_index]
	var card: Dictionary = CardDB.card(card_id)
	if card.is_empty():
		return []

	var cost: int = card.get("cost", 0)
	if cost > mana:
		return []

	mana -= cost

	var effect: Dictionary = card.get("effect", {})
	var events: Array = []

	# Damage → enemy (with optional lightning combo bonus + Overload power bonus).
	if effect.has("damage"):
		var dmg: int = effect.get("damage", 0)

		# Lightning combo: bonus damage if enemy is Burning or Chilled.
		if effect.has("lightning_bonus"):
			var b: int = enemy.statuses.get("burn", 0)
			var c: int = enemy.statuses.get("chill", 0)
			if b > 0 or c > 0:
				var bonus: int = effect.get("lightning_bonus", 0)
				dmg += bonus

		# Overload power: global +2 vs afflicted (stacks with lightning_bonus).
		if "overload" in powers:
			var eb: int = enemy.statuses.get("burn", 0)
			var ec: int = enemy.statuses.get("chill", 0)
			if eb > 0 or ec > 0:
				dmg += 2

		enemy["hp"] -= dmg
		events.append({"type": "damage", "target": "enemy", "amount": dmg})

	# Block → player.
	if effect.has("block"):
		var blk: int = effect.get("block", 0)
		player_block += blk
		events.append({"type": "block", "target": "player", "amount": blk})

	# Draw more cards.
	if effect.has("draw"):
		var draw_n: int = effect.get("draw", 0)
		_draw(draw_n)
		events.append({"type": "draw", "amount": draw_n})

	# Status application — Burn.
	if effect.has("burn"):
		var n: int = effect.get("burn", 0)
		enemy["statuses"]["burn"] = enemy.statuses.get("burn", 0) + n
		events.append({"type": "status", "target": "enemy", "status": "burn", "amount": n})

	# Status application — Chill.
	if effect.has("chill"):
		var n: int = effect.get("chill", 0)
		enemy["statuses"]["chill"] = enemy.statuses.get("chill", 0) + n
		events.append({"type": "status", "target": "enemy", "status": "chill", "amount": n})

	# Power card activation — register the power id (idempotent).
	if effect.has("power"):
		var power_id: String = effect.get("power", "")
		if power_id != "" and not (power_id in powers):
			powers.append(power_id)
		events.append({"type": "power", "power": power_id})

	# Wildfire: if active and the card just played is an attack, apply +1 Burn.
	var card_type: String = card.get("type", "")
	if "wildfire" in powers and card_type == "attack":
		enemy["statuses"]["burn"] = enemy.statuses.get("burn", 0) + 1
		events.append({"type": "status", "target": "enemy", "status": "burn", "amount": 1})

	# Move card from hand to discard.
	hand.remove_at(hand_index)
	discard_pile.append(card_id)

	return events


func enemy_act() -> Array:
	var events: Array = []
	var intent: Dictionary = enemy.get("intent", {})

	# Chill: enemy skips its entire action this turn; chill decrements.
	var chill_stacks: int = enemy.statuses.get("chill", 0)
	if chill_stacks > 0:
		enemy["statuses"]["chill"] = chill_stacks - 1
		events.append({"type": "chilled_skip"})
		_advance_intent()
		return events

	var intent_type: String = intent.get("type", "")
	var iv: int = intent.get("value", 0)

	if intent_type == "attack":
		var strength: int = enemy.get("strength", 0)
		var total_dmg: int = iv + strength
		# Absorb with player_block first.
		var absorbed: int = min(player_block, total_dmg)
		player_block -= absorbed
		var overflow: int = total_dmg - absorbed
		player_hp -= overflow
		events.append({"type": "enemy_attack", "amount": total_dmg, "absorbed": absorbed, "damage_dealt": overflow})

	elif intent_type == "defend":
		enemy["block"] = enemy.get("block", 0) + iv
		events.append({"type": "enemy_defend", "amount": iv})

	elif intent_type == "enrage":
		var gain: int = 3
		enemy["strength"] = enemy.get("strength", 0) + gain
		events.append({"type": "enemy_enrage", "strength_gain": gain})

	_advance_intent()
	return events


func _advance_intent() -> void:
	var intents: Array = enemy.get("intents", [])
	if intents.is_empty():
		return
	_intent_i = (_intent_i + 1) % intents.size()
	enemy["intent"] = intents[_intent_i]


func _tick_statuses() -> Array:
	var events: Array = []

	# Burn: deal burn stacks as damage, then decrement.
	var burn: int = enemy.statuses.get("burn", 0)
	if burn > 0:
		enemy["hp"] -= burn
		enemy["statuses"]["burn"] = burn - 1
		events.append({"type": "burn_tick", "target": "enemy", "amount": burn})

	return events


func end_turn() -> Array:
	var events: Array = []

	# (a) Discard remaining hand.
	for card_id in hand:
		discard_pile.append(card_id)
	hand = []

	# (b) Enemy acts.
	var ev_act: Array = enemy_act()
	for e in ev_act:
		events.append(e)

	# (c) Tick statuses (Burn damage over time).
	var ev_tick: Array = _tick_statuses()
	for e in ev_tick:
		events.append(e)

	# (d) Begin next player turn (resets block/mana, draws 5).
	if not is_won() and not is_lost():
		start_turn()

	return events


func is_won() -> bool:
	return enemy.get("hp", 1) <= 0


func is_lost() -> bool:
	return player_hp <= 0


# Fisher-Yates in-place shuffle using the seeded rng.
func _shuffle(arr: Array) -> void:
	var n: int = arr.size()
	for i in range(n - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
