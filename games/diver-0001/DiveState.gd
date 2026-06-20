extends RefCounted
class_name DiveState
# Pure push-your-luck dive economy. No nodes, no rendering. Seedable RNG so
# selftest.gd is deterministic. Main.gd owns spatial positions/collision and
# calls collect()/hit_hazard(); this class owns air, haul, banking, the ramp,
# the loss condition, AND (deepen run-meta pass) the persistent upgrade economy.
#
# The whole game is the GREED-vs-AIR tradeoff encoded in current_drain() (deeper
# => drains faster) against treasure value (deeper => richer). The deepen pass
# adds a between-dive upgrade track that SHIFTS where the safe-banking depth
# sits — counter-pressure that deepens that same tradeoff across runs.
#
# DEPTH-PASS NOTE: the const MAX_AIR was promoted to a dynamic `max_air` var fed
# by the Tank upgrade (previously-frozen logic, surfaced deliberately). At zero
# upgrades, max_air == BASE_MAX_AIR, so the original behavior is preserved.

const BASE_MAX_AIR: float = 100.0
const BASE_DRAIN: float = 6.0            # air/sec at the surface (Rebreather reduces it)
const DEPTH_DRAIN_FACTOR: float = 0.02   # extra air/sec per unit of depth
const DESCEND_SPEED: float = 90.0        # depth units/sec while sinking
const BASE_ASCEND_SPEED: float = 150.0   # depth units/sec while rising (Fins raise it)
const HAZARD_AIR_COST: float = 12.0
const DRAIN_RAMP_PER_DIVE: float = 0.08  # each completed dive drains a little faster
const MAX_DRAIN_MULT: float = 1.8        # hard cap on the ramp
const AIR_LOW_FRAC: float = 0.30
const MIN_DRAIN: float = 2.5             # rebreather floor — never free air

# Run-meta upgrade catalog (data, not logic). Each shifts a dive parameter.
const UPGRADES: Dictionary = {
	"tank":       {"name": "Air Tank",   "max": 4, "base_cost": 50, "cost_step": 45},
	"fins":       {"name": "Fins",       "max": 4, "base_cost": 40, "cost_step": 35},
	"lamp":       {"name": "Lantern",    "max": 4, "base_cost": 60, "cost_step": 55},
	"rebreather": {"name": "Rebreather", "max": 3, "base_cost": 75, "cost_step": 65},
}

var rng := RandomNumberGenerator.new()
var air: float = BASE_MAX_AIR
var max_air: float = BASE_MAX_AIR
var depth: float = 0.0
var max_depth_reached: float = 0.0
var descending: bool = true
var haul: int = 0
var banked: int = 0
var dive_num: int = 1
var active: bool = false
var upgrades: Dictionary = {"tank": 0, "fins": 0, "lamp": 0, "rebreather": 0}
var _air_low_fired: bool = false

func seed_rng(s: int) -> void:
	rng.seed = s

func _lvl(key: String) -> int:
	var l: int = upgrades.get(key, 0)
	return l

# ---- upgrade-derived parameters ----
func max_air_for() -> float:
	return BASE_MAX_AIR + float(_lvl("tank")) * 16.0

func ascend_speed() -> float:
	return BASE_ASCEND_SPEED + float(_lvl("fins")) * 26.0

func treasure_mult() -> float:
	return 1.0 + float(_lvl("lamp")) * 0.25

func base_drain() -> float:
	var d: float = BASE_DRAIN - float(_lvl("rebreather")) * 0.7
	var floored: float = max(d, MIN_DRAIN)
	return floored

func drain_mult() -> float:
	var m: float = 1.0 + DRAIN_RAMP_PER_DIVE * float(dive_num - 1)
	var capped: float = min(m, MAX_DRAIN_MULT)
	return capped

func current_drain() -> float:
	# The cost B of the tradeoff: the deeper you are, the faster air burns —
	# so every fathom of greed shortens the air you have left to climb back.
	return (base_drain() + depth * DEPTH_DRAIN_FACTOR) * drain_mult()

func air_frac() -> float:
	var f: float = clamp(air / max_air, 0.0, 1.0)
	return f

# ---- upgrade economy ----
func upgrade_cost(key: String) -> int:
	if not UPGRADES.has(key):
		return -1
	var info: Dictionary = UPGRADES[key]
	var lvl: int = _lvl(key)
	if lvl >= int(info["max"]):
		return -1  # maxed out
	return int(info["base_cost"]) + lvl * int(info["cost_step"])

func can_buy(key: String) -> bool:
	var c: int = upgrade_cost(key)
	return c > 0 and banked >= c

func buy_upgrade(key: String) -> Dictionary:
	# Spends BANKED score (never the live haul). No-op if unaffordable/maxed.
	if not can_buy(key):
		return {"bought": false}
	var c: int = upgrade_cost(key)
	banked -= c
	upgrades[key] = _lvl(key) + 1
	return {"bought": true, "key": key, "cost": c, "level": upgrades[key]}

# ---- dive lifecycle ----
func start_dive() -> void:
	max_air = max_air_for()
	air = max_air
	depth = 0.0
	max_depth_reached = 0.0
	descending = true
	haul = 0
	active = true
	_air_low_fired = false

func start_next_dive() -> void:
	dive_num += 1
	start_dive()

func set_ascending(v: bool) -> void:
	if active:
		descending = not v

func toggle_ascend() -> void:
	if active:
		descending = not descending

func collect(value: int) -> Dictionary:
	# Treasure value (scaled by the Lantern upgrade) joins the UNBANKED haul —
	# worthless until you surface.
	if not active:
		return {}
	var gained: int = int(round(float(value) * treasure_mult()))
	haul += gained
	return {"type": "collect", "value": gained}

func hit_hazard() -> Dictionary:
	if not active:
		return {}
	air -= HAZARD_AIR_COST
	if air < 0.0:
		air = 0.0
	return {"type": "hazard"}

func tick(delta: float) -> Array:
	# Advance the dive one frame; returns view-facing events for juice/sfx.
	var events: Array = []
	if not active:
		return events
	if descending:
		depth += DESCEND_SPEED * delta
	else:
		depth -= ascend_speed() * delta
	if depth < 0.0:
		depth = 0.0
	if depth > max_depth_reached:
		max_depth_reached = depth
	air -= current_drain() * delta
	if not _air_low_fired and air_frac() <= AIR_LOW_FRAC:
		_air_low_fired = true
		events.append({"type": "air_low"})
	# Reaching the surface while ascending BANKS the haul (you made it — even on the last breath).
	if not descending and depth <= 0.0:
		var gained: int = haul
		banked += gained
		haul = 0
		active = false
		events.append({"type": "banked", "value": gained})
		return events
	# Air out while still under the surface FORFEITS the whole unbanked dive — the greed tax.
	if air <= 0.0:
		air = 0.0
		if depth > 0.0:
			haul = 0
			active = false
			events.append({"type": "forfeit"})
	return events
