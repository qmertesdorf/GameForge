extends RefCounted
class_name DiveState
# Pure push-your-luck dive economy. No nodes, no rendering. Seedable RNG so
# selftest.gd is deterministic. Main.gd owns spatial positions/collision and
# calls collect()/hit_hazard(); this class owns air, haul, banking, depth ZONES,
# the pressure-crush gate, the per-dive COMMISSION, and the upgrade economy.
#
# DEPTH IS A DESTINATION, NOT A DIAL (deepen v2 repair of the depth-as-multiplier
# trap). Going deep is gated by the pressure CRUSH (air burns CRUSH_MULT× below
# your safe depth) which the Pressure Rig upgrade pushes back, and is *motivated*
# by the COMMISSION — a per-dive order that can only be filled by treasures from a
# target zone, so you descend to reach a place, not to multiply a number.

# ---- depth zones ----
const ZONE_BOUNDS: Array = [0.0, 160.0, 380.0]      # start depth of each zone
const ZONE_NAMES: Array = ["Shallows", "Reef", "Trench"]
const ZONE_VALUE: Array = [10, 24, 52]              # treasure value per zone (the deep pays)

const BASE_MAX_AIR: float = 100.0
const BASE_DRAIN: float = 6.0
const DEPTH_DRAIN_FACTOR: float = 0.012
const CRUSH_MULT: float = 4.0                        # air-burn multiplier below your safe depth
const DESCEND_SPEED: float = 90.0
const BASE_ASCEND_SPEED: float = 150.0
const HAZARD_AIR_COST: float = 12.0
const AIR_LOW_FRAC: float = 0.30
const DRAIN_RAMP_PER_DIVE: float = 0.04
const MAX_DRAIN_MULT: float = 1.5

# ---- upgrade-derived parameters ----
const BASE_SAFE_DEPTH: float = 240.0                 # rig 0 safely works the Shallows + upper Reef
const RIG_STEP: float = 160.0                        # each Pressure Rig level extends safe depth
const TANK_STEP: float = 22.0
const FINS_STEP: float = 26.0
const BASE_LAMP_RANGE: float = 150.0
const LAMP_STEP: float = 130.0

# Each upgrade changes what you can DO (not a flat stat nudge) and is felt in one buy.
const UPGRADES: Dictionary = {
	"rig":  {"name": "Pressure Rig", "max": 3, "base_cost": 40, "cost_step": 55, "blurb": "reach the next depth zone"},
	"tank": {"name": "Air Tank",     "max": 4, "base_cost": 35, "cost_step": 35, "blurb": "more air to work the deep"},
	"lamp": {"name": "Lantern",      "max": 3, "base_cost": 45, "cost_step": 45, "blurb": "see treasure in the dark deep"},
	"fins": {"name": "Fins",         "max": 3, "base_cost": 35, "cost_step": 35, "blurb": "sharper steering to dodge deep predators"},
}
const UPGRADE_KEYS: Array = ["rig", "tank", "lamp", "fins"]

# ---- commission: the reason to descend ----
const COMMISSION_TARGET: int = 2                     # qualifying treasures per order
const COMMISSION_BASE_BONUS: int = 60

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
var upgrades: Dictionary = {"rig": 0, "tank": 0, "lamp": 0, "fins": 0}
var commission_zone: int = 1                         # target zone (start: the Reef)
var commission_have: int = 0                         # qualifying treasures collected this dive
var commissions_done: int = 0
var _air_low_fired: bool = false

func seed_rng(s: int) -> void:
	rng.seed = s

func _lvl(key: String) -> int:
	var l: int = upgrades.get(key, 0)
	return l

# ---- zones ----
func zone_for(d: float) -> int:
	var z: int = 0
	for i in range(ZONE_BOUNDS.size()):
		if d >= float(ZONE_BOUNDS[i]):
			z = i
	return z

func zone_name(z: int) -> String:
	var idx: int = clamp(z, 0, ZONE_NAMES.size() - 1)
	return ZONE_NAMES[idx]

func zone_value(z: int) -> int:
	var idx: int = clamp(z, 0, ZONE_VALUE.size() - 1)
	return int(ZONE_VALUE[idx])

# ---- upgrade-derived parameters ----
func max_air_for() -> float:
	return BASE_MAX_AIR + float(_lvl("tank")) * TANK_STEP

func ascend_speed() -> float:
	return BASE_ASCEND_SPEED + float(_lvl("fins")) * FINS_STEP

func lamp_range() -> float:
	return BASE_LAMP_RANGE + float(_lvl("lamp")) * LAMP_STEP

func max_safe_depth() -> float:
	# The Pressure Rig's job: each level unlocks deeper water before the crush bites.
	return BASE_SAFE_DEPTH + float(_lvl("rig")) * RIG_STEP

func is_crushing() -> bool:
	return active and depth > max_safe_depth()

func drain_mult() -> float:
	var m: float = 1.0 + DRAIN_RAMP_PER_DIVE * float(dive_num - 1)
	var capped: float = min(m, MAX_DRAIN_MULT)
	return capped

func current_drain() -> float:
	var base: float = BASE_DRAIN + depth * DEPTH_DRAIN_FACTOR
	if depth > max_safe_depth():
		base *= CRUSH_MULT          # the crush: past your rig, the deep eats your air
	return base * drain_mult()

func air_frac() -> float:
	var f: float = clamp(air / max_air, 0.0, 1.0)
	return f

# ---- commission ----
func commission_target_zone() -> int:
	return commission_zone

func commission_bonus() -> int:
	return COMMISSION_BASE_BONUS * (commission_zone + 1)

func commission_complete() -> bool:
	return commission_have >= COMMISSION_TARGET

func _advance_commission() -> void:
	# Each filled order pushes the next one deeper — escalating the reason to upgrade
	# the rig and go further down. Caps at the deepest zone.
	if commission_zone < ZONE_NAMES.size() - 1:
		commission_zone += 1

# ---- upgrade economy ----
func upgrade_cost(key: String) -> int:
	if not UPGRADES.has(key):
		return -1
	var info: Dictionary = UPGRADES[key]
	var lvl: int = _lvl(key)
	if lvl >= int(info["max"]):
		return -1
	return int(info["base_cost"]) + lvl * int(info["cost_step"])

func can_buy(key: String) -> bool:
	var c: int = upgrade_cost(key)
	return c > 0 and banked >= c

func buy_upgrade(key: String) -> Dictionary:
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
	commission_have = 0
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

func collect(zone: int) -> Dictionary:
	# Treasure value is set by its ZONE (the deep pays). A treasure from the
	# commission's target zone (or deeper) also counts toward the order.
	if not active:
		return {}
	var gained: int = zone_value(zone)
	haul += gained
	var qualifies: bool = zone >= commission_zone
	if qualifies:
		commission_have += 1
	return {"type": "collect", "value": gained, "qualifies": qualifies, "zone": zone}

func hit_hazard() -> Dictionary:
	if not active:
		return {}
	air -= HAZARD_AIR_COST
	if air < 0.0:
		air = 0.0
	return {"type": "hazard"}

func tick(delta: float) -> Array:
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
	# Surface while ascending -> BANK the haul, and pay the commission if it's filled.
	if not descending and depth <= 0.0:
		var gained: int = haul
		banked += gained
		var did_commission: bool = commission_complete()
		var bonus: int = 0
		if did_commission:
			bonus = commission_bonus()
			banked += bonus
			commissions_done += 1
			_advance_commission()
		haul = 0
		active = false
		events.append({"type": "banked", "value": gained, "commission": did_commission, "bonus": bonus})
		return events
	# Air out while still under -> FORFEIT the whole unbanked dive (and its order progress).
	if air <= 0.0:
		air = 0.0
		if depth > 0.0:
			haul = 0
			active = false
			events.append({"type": "forfeit"})
	return events
