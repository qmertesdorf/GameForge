extends SceneTree
# Headless logic self-test for Fathom (deepen v2: depth-as-destination model).
# Drives the pure DiveState engine with a fixed seed and asserts the economy:
# zones, the pressure CRUSH gate, the COMMISSION that requires reaching a zone,
# upgrade coherence (each upgrade changes a real parameter), and persistence.
# Prints exactly "SELFTEST OK" + exit 0, or "SELFTEST FAIL: <reason>" + exit 1.

const DiveStateC := preload("res://DiveState.gd")
const MetaSaveRef := preload("res://MetaSave.gd")

func _init() -> void:
	var fails: Array = []

	# --- Stage 1: start_dive populates the opening state ---
	var s1 = DiveStateC.new()
	s1.seed_rng(1)
	s1.start_dive()
	if not s1.active: fails.append("start_dive did not set active")
	if s1.depth != 0.0: fails.append("start_dive depth not 0")
	if s1.air != s1.max_air: fails.append("start_dive air not full")
	if s1.commission_have != 0: fails.append("start_dive did not reset commission_have")

	# --- Stage 2: descending burns air and increases depth ---
	var s2 = DiveStateC.new()
	s2.seed_rng(2)
	s2.start_dive()
	var air2_before: float = s2.air
	for _i2 in range(10):
		s2.tick(0.1)
	if s2.depth <= 0.0: fails.append("descending did not increase depth")
	if s2.air >= air2_before: fails.append("descending did not burn air")

	# --- Stage 3: zone boundaries ---
	var s3 = DiveStateC.new()
	if s3.zone_for(0.0) != 0: fails.append("zone_for(0) != Shallows")
	if s3.zone_for(float(DiveStateC.ZONE_BOUNDS[1]) - 1.0) != 0: fails.append("just above Reef boundary not Shallows")
	if s3.zone_for(float(DiveStateC.ZONE_BOUNDS[1])) != 1: fails.append("Reef boundary not zone 1")
	if s3.zone_for(float(DiveStateC.ZONE_BOUNDS[2])) != 2: fails.append("Trench boundary not zone 2")
	if s3.zone_value(2) <= s3.zone_value(0): fails.append("deeper zone is not worth more")

	# --- Stage 4: collect — zone value into haul; only target-zone+ counts to the order ---
	var s4 = DiveStateC.new()
	s4.seed_rng(4)
	s4.commission_zone = 1
	s4.start_dive()
	s4.collect(0)                # a Shallows treasure: scores but does NOT count to a Reef order
	if s4.haul != s4.zone_value(0): fails.append("collect did not add zone value to haul")
	if s4.commission_have != 0: fails.append("shallow treasure wrongly counted toward a deeper order")
	s4.collect(1)                # a Reef treasure: counts
	if s4.commission_have != 1: fails.append("target-zone treasure did not count toward the order")

	# --- Stage 5: hazard drains air ---
	var s5 = DiveStateC.new()
	s5.seed_rng(5)
	s5.start_dive()
	var air5_before: float = s5.air
	s5.hit_hazard()
	if abs((air5_before - s5.air) - DiveStateC.HAZARD_AIR_COST) > 0.001:
		fails.append("hazard drained the wrong amount of air")

	# --- Stage 6: the CRUSH — past max_safe_depth, air burns much faster ---
	var s6 = DiveStateC.new()
	s6.seed_rng(6)
	s6.start_dive()
	s6.upgrades["rig"] = 0
	s6.depth = s6.max_safe_depth() - 20.0
	var drain6_safe: float = s6.current_drain()
	s6.depth = s6.max_safe_depth() + 20.0
	var drain6_crush: float = s6.current_drain()
	if not s6.is_crushing(): fails.append("is_crushing false past the safe depth")
	if drain6_crush <= drain6_safe * 2.0: fails.append("crush did not sharply increase air drain")

	# --- Stage 7: Pressure Rig extends the safe depth (zone access) ---
	var s7 = DiveStateC.new()
	s7.seed_rng(7)
	s7.upgrades["rig"] = 0
	var safe7_lo: float = s7.max_safe_depth()
	s7.upgrades["rig"] = 2
	var safe7_hi: float = s7.max_safe_depth()
	if safe7_hi <= safe7_lo: fails.append("Pressure Rig did not extend max_safe_depth")
	# rig 0 reaches the Reef (so the first commission is achievable) but NOT the Trench;
	# an upgraded rig reaches the Trench.
	if safe7_lo < float(DiveStateC.ZONE_BOUNDS[1]): fails.append("rig 0 should safely reach the Reef (first commission must be achievable)")
	if safe7_lo >= float(DiveStateC.ZONE_BOUNDS[2]): fails.append("rig 0 should NOT reach the Trench")
	if safe7_hi < float(DiveStateC.ZONE_BOUNDS[2]): fails.append("upgraded rig should reach the Trench")

	# --- Stage 8: COMMISSION fills and pays a bonus on surfacing; the order advances ---
	var s8 = DiveStateC.new()
	s8.seed_rng(8)
	s8.commission_zone = 1
	s8.start_dive()
	s8.collect(1)
	s8.collect(1)               # commission_have == target
	if not s8.commission_complete(): fails.append("collecting the target did not complete the order")
	var bonus8: int = s8.commission_bonus()
	var expect8: int = s8.haul + bonus8
	var done8_before: int = s8.commissions_done
	var zone8_before: int = s8.commission_zone
	s8.set_ascending(true)
	var surfaced8: bool = false
	for _j8 in range(400):
		s8.tick(0.05)
		if not s8.active:
			surfaced8 = true
			break
	if not surfaced8: fails.append("commission dive never surfaced")
	if s8.banked != expect8: fails.append("surfacing did not pay haul + commission bonus")
	if s8.commissions_done != done8_before + 1: fails.append("commissions_done did not increment")
	if s8.commission_zone != zone8_before + 1: fails.append("filled order did not advance to a deeper zone")

	# --- Stage 9: GREED — air out deep forfeits the haul AND the order progress ---
	var s9 = DiveStateC.new()
	s9.seed_rng(9)
	s9.commission_zone = 1
	s9.start_dive()
	s9.collect(1)
	s9.collect(1)
	var bank9_before: int = s9.banked
	var done9_before: int = s9.commissions_done
	var forfeited9: bool = false
	for _j9 in range(3000):
		s9.tick(0.1)            # keep descending (greed) — the crush eats the air
		if not s9.active:
			forfeited9 = true
			break
	if not forfeited9: fails.append("greedy dive never ended")
	if s9.haul != 0: fails.append("forfeit did not clear the haul")
	if s9.banked != bank9_before: fails.append("forfeit must not bank anything")
	if s9.commissions_done != done9_before: fails.append("forfeit wrongly credited the commission")

	# --- Stage 10: upgrade purchase deducts banked + raises level; broke = no-op ---
	var s10 = DiveStateC.new()
	s10.seed_rng(10)
	s10.banked = 200
	var cost10: int = s10.upgrade_cost("rig")
	var r10: Dictionary = s10.buy_upgrade("rig")
	if not r10.get("bought", false): fails.append("affordable upgrade not bought")
	if s10.upgrades["rig"] != 1: fails.append("upgrade level did not increment")
	if s10.banked != 200 - cost10: fails.append("upgrade did not deduct banked")
	s10.banked = 0
	var r10b: Dictionary = s10.buy_upgrade("tank")
	if r10b.get("bought", false): fails.append("upgrade bought with no banked score")

	# --- Stage 11: every upgrade changes a real parameter (coherence) ---
	var s11 = DiveStateC.new()
	s11.seed_rng(11)
	var air11: float = s11.max_air_for()
	s11.upgrades["tank"] = 2
	if s11.max_air_for() <= air11: fails.append("tank did not raise max air")
	var asc11: float = s11.ascend_speed()
	s11.upgrades["fins"] = 2
	if s11.ascend_speed() <= asc11: fails.append("fins did not raise ascend speed")
	var lamp11: float = s11.lamp_range()
	s11.upgrades["lamp"] = 2
	if s11.lamp_range() <= lamp11: fails.append("lamp did not raise the light range")

	# --- Stage 12: persistence round-trips banked + upgrades + commission progress ---
	MetaSaveRef.clear()
	MetaSaveRef.write(420, {"rig": 2, "tank": 1, "lamp": 0, "fins": 1}, 6, 2, 3)
	var loaded12: Dictionary = MetaSaveRef.read()
	if int(loaded12.get("banked", -1)) != 420: fails.append("persistence lost banked")
	if int(loaded12.get("commission_zone", -1)) != 2: fails.append("persistence lost commission_zone")
	if int(loaded12.get("commissions_done", -1)) != 3: fails.append("persistence lost commissions_done")
	var up12: Dictionary = loaded12.get("upgrades", {})
	if int(up12.get("rig", -1)) != 2: fails.append("persistence lost upgrade levels")
	MetaSaveRef.clear()

	if fails.is_empty():
		print("SELFTEST OK")
		quit(0)
	else:
		print("SELFTEST FAIL: ", fails[0])
		for k in range(fails.size()):
			print("  - ", fails[k])
		quit(1)
