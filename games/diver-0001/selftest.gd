extends SceneTree
# Headless logic self-test for Fathom. Drives the pure DiveState engine with a
# fixed seed and asserts the push-your-luck economy: descent burns air, treasure
# only counts once banked, a cautious dive reliably banks (fairness), and a
# greedy dive that runs out of air forfeits the whole haul (the tradeoff is real).
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
	if s1.max_air != DiveStateC.BASE_MAX_AIR: fails.append("start_dive max_air not base at zero upgrades")
	if s1.haul != 0: fails.append("start_dive haul not 0")
	if not s1.descending: fails.append("start_dive should begin descending")

	# --- Stage 2: descending burns air and increases depth ---
	var s2 = DiveStateC.new()
	s2.seed_rng(2)
	s2.start_dive()
	var air2_before: float = s2.air
	for _i2 in range(10):
		s2.tick(0.1)
	if s2.depth <= 0.0: fails.append("descending did not increase depth")
	if s2.air >= air2_before: fails.append("descending did not burn air")

	# --- Stage 3: collect adds to the UNBANKED haul, banked unchanged ---
	var s3 = DiveStateC.new()
	s3.seed_rng(3)
	s3.start_dive()
	var bank3_before: int = s3.banked
	s3.collect(15)
	if s3.haul != 15: fails.append("collect did not add to haul")
	if s3.banked != bank3_before: fails.append("collect must not bank directly")

	# --- Stage 4: hitting a hazard drains air ---
	var s4 = DiveStateC.new()
	s4.seed_rng(4)
	s4.start_dive()
	var air4_before: float = s4.air
	s4.hit_hazard()
	if s4.air >= air4_before: fails.append("hazard did not drain air")
	if abs((air4_before - s4.air) - DiveStateC.HAZARD_AIR_COST) > 0.001:
		fails.append("hazard drained the wrong amount of air")

	# --- Stage 5: FAIRNESS — a cautious dive descends a little then banks ---
	var s5 = DiveStateC.new()
	s5.seed_rng(5)
	s5.start_dive()
	for _i5 in range(8):
		s5.tick(0.1)          # sink to a modest depth
	s5.collect(40)
	var bank5_before: int = s5.banked
	s5.set_ascending(true)
	var surfaced5: bool = false
	for _j5 in range(400):
		s5.tick(0.05)
		if not s5.active:
			surfaced5 = true
			break
	if not surfaced5: fails.append("cautious dive never resolved")
	if s5.banked != bank5_before + 40: fails.append("surfacing did not bank the haul")
	if s5.haul != 0: fails.append("haul not cleared after banking")

	# --- Stage 6: GREED — descend until air runs out: the haul is forfeited ---
	var s6 = DiveStateC.new()
	s6.seed_rng(6)
	s6.start_dive()
	s6.collect(120)
	var bank6_before: int = s6.banked
	var forfeited6: bool = false
	for _j6 in range(2000):
		s6.tick(0.1)          # keep descending (never ascend) — pure greed
		if not s6.active:
			forfeited6 = true
			break
	if not forfeited6: fails.append("greedy dive never ended")
	if s6.air > 0.0: fails.append("greedy dive ended with air to spare")
	if s6.haul != 0: fails.append("forfeit did not clear the haul")
	if s6.banked != bank6_before: fails.append("forfeit must not bank anything")

	# --- Stage 7: per-dive ramp — drain accelerates across dives, but is capped ---
	var s7 = DiveStateC.new()
	s7.seed_rng(7)
	s7.dive_num = 1
	var m7_d1: float = s7.drain_mult()
	s7.dive_num = 2
	var m7_d2: float = s7.drain_mult()
	if m7_d2 <= m7_d1: fails.append("drain ramp did not increase on dive 2")
	s7.dive_num = 99
	if s7.drain_mult() > DiveStateC.MAX_DRAIN_MULT + 0.001:
		fails.append("drain ramp exceeded its cap")

	# --- Stage 8: the cost B is depth-driven — deeper drains faster ---
	var s8 = DiveStateC.new()
	s8.seed_rng(8)
	s8.start_dive()
	s8.depth = 0.0
	var drain8_shallow: float = s8.current_drain()
	s8.depth = 300.0
	var drain8_deep: float = s8.current_drain()
	if drain8_deep <= drain8_shallow:
		fails.append("depth did not increase air drain (tradeoff cost missing)")

	# ===================== deepen run-meta pass =====================

	# --- Stage 9: upgrade purchase deducts banked and raises the level; broke = no-op ---
	var s9 = DiveStateC.new()
	s9.seed_rng(9)
	s9.banked = 200
	var cost9: int = s9.upgrade_cost("tank")
	var r9: Dictionary = s9.buy_upgrade("tank")
	if not r9.get("bought", false): fails.append("affordable upgrade was not bought")
	if s9.upgrades["tank"] != 1: fails.append("upgrade level did not increment")
	if s9.banked != 200 - cost9: fails.append("upgrade did not deduct banked score")
	# unaffordable purchase must be a no-op
	s9.banked = 0
	var r9b: Dictionary = s9.buy_upgrade("fins")
	if r9b.get("bought", false): fails.append("upgrade bought with no banked score")
	if s9.upgrades["fins"] != 0: fails.append("unaffordable upgrade still incremented level")

	# --- Stage 10: Tank upgrade raises max_air, and the next dive fills to it ---
	var s10 = DiveStateC.new()
	s10.seed_rng(10)
	var air10_base: float = s10.max_air_for()
	s10.upgrades["tank"] = 2
	var air10_up: float = s10.max_air_for()
	if air10_up <= air10_base: fails.append("tank upgrade did not raise max_air_for")
	s10.start_dive()
	if s10.max_air != air10_up: fails.append("start_dive did not apply upgraded max_air")
	if s10.air != air10_up: fails.append("dive did not fill to the upgraded tank")

	# --- Stage 11: Lantern upgrade multiplies collected treasure into the haul ---
	var s11 = DiveStateC.new()
	s11.seed_rng(11)
	s11.start_dive()
	s11.collect(100)
	var haul11_base: int = s11.haul        # mult 1.0 at level 0 -> 100
	var s11b = DiveStateC.new()
	s11b.seed_rng(111)
	s11b.upgrades["lamp"] = 2               # +50%
	s11b.start_dive()
	s11b.collect(100)
	if haul11_base != 100: fails.append("base lantern multiplier was not 1.0")
	if s11b.haul <= haul11_base: fails.append("lantern upgrade did not enrich the haul")

	# --- Stage 12: Fins raise ascend speed; Rebreather lowers drain to a floor ---
	var s12 = DiveStateC.new()
	s12.seed_rng(12)
	var asc12_base: float = s12.ascend_speed()
	s12.upgrades["fins"] = 3
	if s12.ascend_speed() <= asc12_base: fails.append("fins did not raise ascend speed")
	var drain12_base: float = s12.base_drain()
	s12.upgrades["rebreather"] = 2
	if s12.base_drain() >= drain12_base: fails.append("rebreather did not lower base drain")
	s12.upgrades["rebreather"] = 99        # absurd level must still respect the floor
	if s12.base_drain() < DiveStateC.MIN_DRAIN - 0.001: fails.append("rebreather broke the drain floor")

	# --- Stage 13: PERSISTENCE round-trips banked + upgrades (reset file first) ---
	MetaSaveRef.clear()
	MetaSaveRef.write(347, {"tank": 2, "fins": 1, "lamp": 0, "rebreather": 1}, 5)
	var loaded13: Dictionary = MetaSaveRef.read()
	if int(loaded13.get("banked", -1)) != 347: fails.append("persistence did not round-trip banked")
	if int(loaded13.get("dive_num", -1)) != 5: fails.append("persistence did not round-trip dive_num")
	var up13: Dictionary = loaded13.get("upgrades", {})
	if int(up13.get("tank", -1)) != 2 or int(up13.get("rebreather", -1)) != 1:
		fails.append("persistence did not round-trip upgrade levels")
	MetaSaveRef.clear()

	if fails.is_empty():
		print("SELFTEST OK")
		quit(0)
	else:
		print("SELFTEST FAIL: ", fails[0])
		for k in range(fails.size()):
			print("  - ", fails[k])
		quit(1)
