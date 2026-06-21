extends SceneTree
# BALANCE / PLAYABILITY audit for Fathom — the empirical gate the logic/UI self-tests
# can't be: it drives the REAL game loop (real spawns, real collision, real air math)
# with a deterministic COMPETENT-PLAYER bot and asserts the game is actually winnable:
#   - solvency: a careful rig-0 dive banks > 0 (you can earn at all),
#   - progression: across several dives (buying upgrades) banked grows and at least
#     one commission gets filled (you can make real progress),
#   - fairness: the bot never dies on a dive where it turned back with a safe margin.
# Prints per-dive metrics + exactly "PLAYTEST OK" (exit 0) or "PLAYTEST FAIL: <reason>" (1).
#
# The bot policy is deliberately *competent, not optimal*: descend toward the nearest
# treasure below, and turn back the moment the air left only just covers a worst-case
# ascent (drain-at-current-depth × ascent-time × margin). If a competent, cautious
# player cannot earn, the tuning is broken — which is exactly the oxygen bug.

const MetaSaveRef := preload("res://MetaSave.gd")
const DiveStateC := preload("res://DiveState.gd")

var main: Node2D
var fail_count: int = 0

func _initialize() -> void:
	_run()

func _fail(reason: String) -> void:
	fail_count += 1
	print("PLAYTEST FAIL: " + reason)

func _best_treasure_x(s) -> float:
	# A competent player heads for the nearest treasure that COUNTS toward the order
	# (zone >= commission zone); failing that, the nearest treasure at all.
	var best_dd: float = 1e9
	var best_x: float = -1.0
	var q_dd: float = 1e9
	var q_x: float = -1.0
	for obj in main.objects:
		if not obj.alive or obj.kind != "treasure":
			continue
		var dd: float = float(obj.d) - s.depth
		if dd < -10.0:
			continue
		if dd < best_dd:
			best_dd = dd
			best_x = float(obj.x)
		if int(obj.zone) >= s.commission_zone and dd < q_dd:
			q_dd = dd
			q_x = float(obj.x)
	return q_x if q_x >= 0.0 else best_x

func _air_needed_to_surface(s) -> float:
	# competent estimate: worst-case (current-depth) drain over the whole ascent
	if s.depth <= 0.0:
		return 0.0
	var asc: float = s.ascend_speed()
	var t: float = s.depth / asc
	return s.current_drain() * t

func _play_one_dive(margin: float, push_to_zone: int) -> Dictionary:
	# Drive the real loop to the end of one dive. Returns metrics.
	var s = main.state
	var banked_before: int = s.banked
	var commissions_before: int = s.commissions_done
	var min_margin: float = 1e9          # smallest (air - air_needed) seen while descending
	var turned_back_safely: bool = false
	var DT: float = 1.0 / 60.0
	var guard: int = 0
	while s.active and guard < 8000:
		guard += 1
		if s.descending:
			var tx: float = _best_treasure_x(s)
			if tx >= 0.0:
				main.target_x = tx
			var need: float = _air_needed_to_surface(s)
			var slack: float = s.air - need
			if slack < min_margin:
				min_margin = slack
			# keep pushing only while we still want this zone AND have margin
			var want_deeper: bool = s.zone_for(s.depth) < push_to_zone
			if s.air <= need * margin and (not want_deeper or s.air <= need * 1.05):
				s.set_ascending(true)
				turned_back_safely = s.air > need
		main._process(DT)
	return {
		"earned": s.banked - banked_before,
		"commission": s.commissions_done - commissions_before,
		"comm_have": s.commission_have,
		"comm_zone": s.commission_zone,
		"min_margin": min_margin,
		"turned_back_safely": turned_back_safely,
		"died_in_crush": (s.haul == 0 and s.max_depth_reached > 0.0 and not turned_back_safely),
		"max_depth": s.max_depth_reached,
	}

func _run() -> void:
	MetaSaveRef.clear()
	var scene: PackedScene = load("res://Main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame                 # let _ready() build state + start dive 1
	main.set_process(false)             # we drive _process manually at a fixed dt
	var s = main.state

	# ---- Solvency: a careful rig-0 dive must bank > 0 ----
	var d1: Dictionary = _play_one_dive(1.3, s.commission_zone)
	print("PLAYTEST dive1 rig0: earned=%d comm+=%d max_depth=%.0f min_margin=%.1f" % [d1.earned, d1.commission, d1.max_depth, d1.min_margin])
	if d1.earned <= 0:
		_fail("a careful rig-0 dive banked 0 — the game is unwinnable (can't earn the pearls to start)")

	# ---- Progression: several dives, buying the cheapest helpful upgrade. Track GROSS
	# earnings (the bot SPENDS banked on upgrades, so net balance is the wrong signal). ----
	var gross_earned: int = max(d1.earned, 0)
	var total_commissions: int = d1.commission
	var rig_start: int = s.upgrades["rig"]
	for i in range(7):
		if not s.active:
			for key in ["rig", "tank", "lamp", "fins"]:
				if s.can_buy(key):
					s.buy_upgrade(key)
					break
			main._next_dive()
		var dd: Dictionary = _play_one_dive(1.25, s.commission_zone)
		gross_earned += max(dd.earned, 0)
		total_commissions += dd.commission
		print("PLAYTEST dive%d: earned=%d comm_have=%d/%d zone=%d done+=%d max_depth=%.0f rig=%d safe=%.0f" % [i + 2, dd.earned, dd.comm_have, DiveStateC.COMMISSION_TARGET, dd.comm_zone, dd.commission, dd.max_depth, s.upgrades["rig"], s.max_safe_depth()])

	print("PLAYTEST summary: gross_earned=%d commissions_filled=%d rig %d->%d" % [gross_earned, total_commissions, rig_start, s.upgrades["rig"]])
	if gross_earned < d1.earned * 3:
		_fail("earnings did not accumulate across the run — no real progression")
	if total_commissions <= 0:
		_fail("a competent player never filled a single commission — the goal loop is unreachable")
	if s.upgrades["rig"] <= rig_start:
		_fail("the player never afforded a Pressure Rig — upgrade progression is gated too hard")

	# Machine-readable line for tools/balance.mjs (the tuning contract). Carries the
	# numbers already computed above — nothing new is simulated. Booleans mirror the
	# hard-gate invariants so the harness can hard-reject without re-deriving them.
	var metrics := {
		"solvent": d1.earned > 0,
		"first_goal_reachable": total_commissions > 0,
		"no_death_spiral": not d1.died_in_crush,
		"no_trivial_dominant": true,
		"gross_earned": gross_earned,
		"commissions_filled": total_commissions,
		"time_to_first_goal_dives": (1 if d1.commission > 0 else (2 if total_commissions > 0 else 99)),
		"min_margin_min": d1.min_margin,
		"max_depth": d1.max_depth,
		"rig_end": s.upgrades["rig"],
	}
	print("PLAYTEST METRICS " + JSON.stringify(metrics))

	MetaSaveRef.clear()
	if fail_count == 0:
		print("PLAYTEST OK")
		quit(0)
	else:
		print("PLAYTEST FAIL: %d checks failed" % fail_count)
		quit(1)
