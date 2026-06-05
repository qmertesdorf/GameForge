extends Node

# Data-driven relic table. Each relic declares which hook it fires on.
# Effects are applied by the static apply_* dispatchers (GDScript const dicts
# can't hold first-class funcs cleanly, so we match on id in the dispatcher).
# Hooks: on_run_start(run), on_combat_start(combat_state), on_combat_win(run).
const RELICS := {
	"ember_heart": {
		"id": "ember_heart", "name": "Ember Heart", "hook": "on_combat_start",
		"desc": "At combat start, apply 1 Burn to the enemy.",
	},
	"storm_core": {
		"id": "storm_core", "name": "Storm Core", "hook": "on_combat_start",
		"desc": "Gain +1 max mana each combat.",
	},
}

static func relic(id: String) -> Dictionary:
	return RELICS.get(id, {})

static func all_ids() -> Array:
	return RELICS.keys()

# Apply every owned relic that fires on combat start. Mutates the combat state.
static func apply_combat_start(owned: Array, cs) -> void:
	for id in owned:
		match id:
			"ember_heart":
				cs.enemy["statuses"]["burn"] = cs.enemy.statuses.get("burn", 0) + 1
			# "storm_core" effect is implemented in Task 13 — no-op here.

# Apply every owned relic that fires at run start. Mutates the run.
static func apply_run_start(owned: Array, run) -> void:
	pass  # populated in Task 13

# Apply every owned relic that fires on combat win. Mutates the run.
static func apply_combat_win(owned: Array, run) -> void:
	pass  # populated in Task 13
