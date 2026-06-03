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

# Internal intent index tracker.
var _intent_i: int = 0


func setup(seed_value: int, deck: Array, enemy_id: String) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	player_max_hp = 70
	player_hp = 70
	player_block = 0

	mana_max = 3
	mana = 0

	enemy = EnemyDB.enemy(enemy_id)
	# Ensure block and statuses keys exist on the mutable enemy copy.
	if not enemy.has("block"):
		enemy["block"] = 0
	if not enemy.has("statuses"):
		enemy["statuses"] = {"burn": 0, "chill": 0}

	# Build draw_pile as a copy of the deck, then Fisher-Yates shuffle
	# using the seeded rng (NOT Array.shuffle which uses the global RNG).
	draw_pile = deck.duplicate()
	_shuffle(draw_pile)

	hand = []
	discard_pile = []


func start_combat() -> void:
	_intent_i = 0
	enemy["intent"] = enemy["intents"][0]
	enemy["_intent_i"] = 0
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

	# Damage → enemy.
	if effect.has("damage"):
		var dmg: int = effect.get("damage", 0)
		enemy["hp"] -= dmg
		events.append({"type": "damage", "target": "enemy", "amount": dmg})

	# Block → player (Stage 1 wired, trivial).
	if effect.has("block"):
		var blk: int = effect.get("block", 0)
		player_block += blk
		events.append({"type": "block", "target": "player", "amount": blk})

	# Draw more cards (Stage 1 wired, trivial).
	if effect.has("draw"):
		var draw_n: int = effect.get("draw", 0)
		_draw(draw_n)
		events.append({"type": "draw", "amount": draw_n})

	# burn/chill/lightning_bonus/power are Stage 2/3 — no-op here.

	# Move card from hand to discard.
	hand.remove_at(hand_index)
	discard_pile.append(card_id)

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
