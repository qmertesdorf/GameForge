extends Node

# Data-driven relic table. Each relic declares which hook it fires on.
# Effects are applied by the static apply_* dispatchers (GDScript const dicts
# can't hold first-class funcs cleanly, so we match on id in the dispatcher).
# Hooks: on_run_start(run), on_combat_start(combat_state), on_combat_win(run).
const RELICS := {
	"ember_heart":    {"id": "ember_heart",    "name": "Ember Heart",    "hook": "on_combat_start", "desc": "Combat start: apply 1 Burn."},
	"storm_core":     {"id": "storm_core",     "name": "Storm Core",     "hook": "on_combat_start", "desc": "+1 max mana each combat."},
	"iron_ward":      {"id": "iron_ward",      "name": "Iron Ward",      "hook": "on_combat_start", "desc": "Start each combat with 5 Block."},
	"arcane_battery": {"id": "arcane_battery", "name": "Arcane Battery",  "hook": "on_combat_start", "desc": "Draw 1 extra card at combat start."},
	"vitality_charm": {"id": "vitality_charm", "name": "Vitality Charm",  "hook": "on_run_start",    "desc": "+10 max HP."},
	"gold_idol":      {"id": "gold_idol",      "name": "Gold Idol",       "hook": "on_combat_win",   "desc": "+5 gold per combat."},
	"lucky_coin":     {"id": "lucky_coin",     "name": "Lucky Coin",      "hook": "on_combat_win",   "desc": "+3 gold per combat."},
}

static func relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

static func all_ids() -> Array:
	return RELICS.keys()

static func apply_combat_start(owned: Array, cs) -> void:
	for id in owned:
		match id:
			"ember_heart":
				cs.enemy["statuses"]["burn"] = cs.enemy.statuses.get("burn", 0) + 1
			"storm_core":
				cs.mana_max += 1
				cs.mana = cs.mana_max
			"iron_ward":
				cs.player_block += 5
			"arcane_battery":
				cs._draw(1)

static func apply_run_start(owned: Array, run) -> void:
	for id in owned:
		match id:
			"vitality_charm":
				run.run_max_hp += 10
				run.run_hp += 10

static func apply_combat_win(owned: Array, run) -> void:
	for id in owned:
		match id:
			"gold_idol":
				run.gold += 5
			"lucky_coin":
				run.gold += 3
