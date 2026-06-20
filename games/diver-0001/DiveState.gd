extends RefCounted
class_name DiveState
# Pure push-your-luck dive economy. No nodes, no rendering. Seedable RNG so
# selftest.gd is deterministic. Main.gd owns spatial positions/collision and
# calls collect()/hit_hazard(); this class owns air, haul, banking, the ramp,
# and the loss condition. The whole game is the GREED-vs-AIR tradeoff encoded
# in current_drain() (deeper => drains faster) against treasure value (deeper
# => richer, scored in Main).

const MAX_AIR: float = 100.0
const BASE_DRAIN: float = 6.0            # air/sec at the surface
const DEPTH_DRAIN_FACTOR: float = 0.02   # extra air/sec per unit of depth
const DESCEND_SPEED: float = 90.0        # depth units/sec while sinking
const ASCEND_SPEED: float = 150.0        # depth units/sec while rising (escape IS possible — but costs air)
const HAZARD_AIR_COST: float = 12.0
const DRAIN_RAMP_PER_DIVE: float = 0.08  # each completed dive drains a little faster
const MAX_DRAIN_MULT: float = 1.8        # hard cap on the ramp
const AIR_LOW_FRAC: float = 0.30

var rng := RandomNumberGenerator.new()
var air: float = MAX_AIR
var depth: float = 0.0
var max_depth_reached: float = 0.0
var descending: bool = true
var haul: int = 0
var banked: int = 0
var dive_num: int = 1
var active: bool = false
var _air_low_fired: bool = false

func seed_rng(s: int) -> void:
	rng.seed = s

func drain_mult() -> float:
	var m: float = 1.0 + DRAIN_RAMP_PER_DIVE * float(dive_num - 1)
	var capped: float = min(m, MAX_DRAIN_MULT)
	return capped

func current_drain() -> float:
	# The cost B of the tradeoff: the deeper you are, the faster air burns —
	# so every fathom of greed shortens the air you have left to climb back.
	return (BASE_DRAIN + depth * DEPTH_DRAIN_FACTOR) * drain_mult()

func air_frac() -> float:
	var f: float = clamp(air / MAX_AIR, 0.0, 1.0)
	return f

func start_dive() -> void:
	air = MAX_AIR
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
	# Treasure value joins the UNBANKED haul — worthless until you surface.
	if not active:
		return {}
	haul += value
	return {"type": "collect", "value": value}

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
		depth -= ASCEND_SPEED * delta
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
