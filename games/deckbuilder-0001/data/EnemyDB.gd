extends Node

const ENEMIES := {
	"imp": {
		"id": "imp",
		"name": "Imp",
		"hp": 30,
		"gold_min": 10,
		"gold_max": 15,
		"intents": [
			{"type": "attack", "value": 7},
			{"type": "attack", "value": 9},
			{"type": "defend", "value": 5},
		]
	},
	"frost_wraith": {
		"id": "frost_wraith",
		"name": "Frost Wraith",
		"hp": 40,
		"gold_min": 12,
		"gold_max": 18,
		"intents": [
			{"type": "attack", "value": 8},
			{"type": "defend", "value": 7},
			{"type": "attack", "value": 10},
			{"type": "defend", "value": 5},
		]
	},
	"golem": {
		"id": "golem",
		"name": "Stone Golem",
		"hp": 70,
		"gold_min": 25,
		"gold_max": 35,
		"intents": [
			{"type": "attack", "value": 12},
			{"type": "enrage", "value": 0},
			{"type": "attack", "value": 15},
			{"type": "defend", "value": 10},
			{"type": "attack", "value": 18},
		]
	},
	"archmage": {
		"id": "archmage",
		"name": "Archmage",
		"hp": 110,
		"gold_min": 45,
		"gold_max": 55,
		"intents": [
			{"type": "attack", "value": 10},
			{"type": "attack", "value": 14},
			{"type": "defend", "value": 12},
			{"type": "attack", "value": 18},
			{"type": "attack", "value": 10},
			{"type": "defend", "value": 8},
			{"type": "enrage", "value": 0},
			{"type": "attack", "value": 22},
		]
	},
}

static func enemy(id: String) -> Dictionary:
	var base: Dictionary = ENEMIES.get(id, {})
	if base.is_empty():
		return {}
	return base.duplicate(true)
