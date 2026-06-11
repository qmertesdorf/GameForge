extends SceneTree
## Headless self-test for Tide & Tally. Drives scripted days through the pure
## ShopState rules engine with a fixed seed and asserts each loop primitive.
## Prints exactly "SELFTEST OK" on success.
## Run: godot --headless --path games/shopkeep-0001/ --script res://selftest.gd

const ShopState := preload("res://ShopState.gd")
const ItemDB := preload("res://data/ItemDB.gd")
const UpgradeDB := preload("res://data/UpgradeDB.gd")
const MetaSave := preload("res://MetaSave.gd")


func _initialize() -> void:
	var ok: bool = _run()
	if ok:
		print("SELFTEST OK")
		quit(0)
	else:
		quit(1)


func _fail(reason: String) -> bool:
	print("SELFTEST FAIL: " + reason)
	return false


func _has_event(events: Array, type: String) -> bool:
	for e in events:
		var ev: Dictionary = e
		if String(ev["type"]) == type:
			return true
	return false


func _get_event(events: Array, type: String) -> Dictionary:
	for e in events:
		var ev: Dictionary = e
		if String(ev["type"]) == type:
			return ev
	return {}


func _total(d: Dictionary) -> int:
	var n: int = 0
	for k in d.keys():
		var c: int = d[k]
		n += c
	return n


func _run() -> bool:
	# ---- Stage 1: setup -> opening state populated -------------------------
	var s := ShopState.new()
	s.setup(1234, {})
	var ev: Array = s.start_day()
	if s.phase != ShopState.Phase.GATHER:
		return _fail("day does not start in GATHER")
	if s.gather_nodes.size() != ShopState.NODE_COUNT:
		return _fail("expected %d gather nodes, got %d" % [ShopState.NODE_COUNT, s.gather_nodes.size()])
	if s.demand.size() != 2:
		return _fail("expected 2 demand hints, got %d" % s.demand.size())
	if not _has_event(ev, "day_started"):
		return _fail("start_day produced no day_started event")
	if absf(s.tide_left - 25.0) > 0.001:
		return _fail("tide window at level 0 should be 25s")

	# Determinism: same seed -> same beach.
	var sa := ShopState.new()
	var sb := ShopState.new()
	sa.setup(777, {})
	sb.setup(777, {})
	sa.start_day()
	sb.start_day()
	for i in range(sa.gather_nodes.size()):
		var na: Dictionary = sa.gather_nodes[i]
		var nb: Dictionary = sb.gather_nodes[i]
		if String(na["res"]) != String(nb["res"]) or na["pos"] != nb["pos"]:
			return _fail("seeded RNG is not deterministic (node %d differs)" % i)

	# ---- Stage 2: gather = spend taps for resources, capacity + bank -------
	ev = s.tap_node(0)
	if not _has_event(ev, "node_collected"):
		return _fail("tapping a fresh node did not collect")
	if s.unbanked_total() != 1:
		return _fail("unbanked haul should be 1 after one tap")
	ev = s.tap_node(0)
	if not ev.is_empty():
		return _fail("tapping a taken node should be a no-op")
	# Fill to capacity (3 at level 0).
	var idx: int = 1
	while s.unbanked_total() < s.haul_capacity() and idx < s.gather_nodes.size():
		s.tap_node(idx)
		idx += 1
	if s.unbanked_total() != 3:
		return _fail("could not fill haul to capacity 3")
	# One more must refuse.
	while idx < s.gather_nodes.size():
		var node: Dictionary = s.gather_nodes[idx]
		if not node["taken"]:
			break
		idx += 1
	ev = s.tap_node(idx)
	if not _has_event(ev, "haul_full"):
		return _fail("tap beyond capacity should report haul_full")
	ev = s.bank()
	if not _has_event(ev, "banked"):
		return _fail("bank produced no banked event")
	if _total(s.resources) != 3 or s.unbanked_total() != 0:
		return _fail("bank should move all 3 carried into resources")

	# ---- Stage 3: tide sweep = unbanked haul is lost, phase advances -------
	idx += 1
	while idx < s.gather_nodes.size():
		var node2: Dictionary = s.gather_nodes[idx]
		if not node2["taken"]:
			break
		idx += 1
	s.tap_node(idx)
	if s.unbanked_total() != 1:
		return _fail("setup for tide test failed (expected 1 in hand)")
	ev = s.tick_gather(999.0)
	var tide: Dictionary = _get_event(ev, "tide_returned")
	if tide.is_empty():
		return _fail("tide never returned on a huge tick")
	var lost_count: int = tide["lost_count"]
	if lost_count != 1:
		return _fail("tide should sweep exactly the 1 unbanked item")
	if _total(s.resources) != 3:
		return _fail("banked resources must survive the tide")
	if s.phase != ShopState.Phase.CRAFT:
		return _fail("tide return should advance to CRAFT")

	# ---- Stage 4: craft = spend resources for stock (both sides) -----------
	s.resources = {"shell": 4, "driftwood": 2, "seaglass": 2, "pearl": 1}
	ev = s.craft("shell_charm")
	if not _has_event(ev, "crafted"):
		return _fail("crafting shell_charm with 4 shells failed")
	if s.resource_count("shell") != 2:
		return _fail("shell_charm should cost 2 shells (4 -> 2)")
	if s.stock != ["shell_charm"]:
		return _fail("crafted item missing from stock")
	ev = s.craft("pearl_ring")
	if not _has_event(ev, "crafted") or s.resource_count("pearl") != 0 or s.resource_count("seaglass") != 1:
		return _fail("pearl_ring craft did not deduct pearl+seaglass")
	ev = s.craft("tide_lantern")
	if not _has_event(ev, "craft_failed"):
		return _fail("crafting without a pearl should fail gracefully")
	if s.stock.size() != 2:
		return _fail("failed craft must not add stock")

	# ---- Stage 5: shelving, limited slots -----------------------------------
	ev = s.stock_shelf(0)
	if not _has_event(ev, "stocked") or s.shelves != ["shell_charm"] or s.stock != ["pearl_ring"]:
		return _fail("shelving the first stock item went wrong")
	s.stock_shelf(0)
	if s.shelves.size() != 2 or not s.stock.is_empty():
		return _fail("second shelving went wrong")
	var slots: int = s.shelf_slots()
	while s.shelves.size() < slots:
		s.shelves.append("shell_charm")
	s.stock.append("wind_chime")
	ev = s.stock_shelf(0)
	if not _has_event(ev, "shelves_full"):
		return _fail("overfilling shelves should report shelves_full")
	if s.stock != ["wind_chime"]:
		return _fail("rejected shelving must keep the item in stock")

	# ---- Stage 6: sell — demand bonus branch beats the base branch ---------
	s.phase = ShopState.Phase.SELL
	s.stock.clear()
	s.demand = ["shell_charm"]
	s.shelves = ["shell_charm", "seaglass_pendant"]
	s.patrons = [
		{"want": "shell_charm", "patience": 10.0, "max_patience": 10.0},
		{"want": "seaglass_pendant", "patience": 10.0, "max_patience": 10.0},
	]
	s.patrons_to_come = 0
	var gold0: int = s.gold
	ev = s.serve(0, 1)
	if not _has_event(ev, "wrong_item"):
		return _fail("offering the wrong item should be rejected")
	if s.gold != gold0 or s.shelves.size() != 2 or s.patrons.size() != 2:
		return _fail("wrong_item must not change any state")
	ev = s.serve(0, 0)
	var sale: Dictionary = _get_event(ev, "sale")
	if sale.is_empty():
		return _fail("serving the wanted item did not sell")
	var amount: int = sale["amount"]
	var bonus: bool = sale["bonus"]
	if not bonus or amount != 12:
		return _fail("in-demand shell_charm should sell for ceil(8*1.5)=12, got %d" % amount)
	if s.gold != gold0 + 12:
		return _fail("gold did not increase by the bonus price")
	ev = s.serve(0, 0)
	sale = _get_event(ev, "sale")
	if sale.is_empty():
		return _fail("second sale failed")
	var amount2: int = sale["amount"]
	var bonus2: bool = sale["bonus"]
	if bonus2 or amount2 != 18:
		return _fail("off-demand pendant should sell at base 18, got %d" % amount2)
	if not s.shelves.is_empty() or not s.patrons.is_empty():
		return _fail("sales should consume both shelf item and patron")

	# ---- Stage 7+8: patience drains (durational state) then day completes --
	s.shelves = ["wind_chime"]  # keep shop stocked so sold-out path doesn't fire
	s.patrons = [{"want": "pearl_ring", "patience": 3.0, "max_patience": 12.0}]
	s.patrons_to_come = 0
	ev = s.tick_sell(1.0)
	var p0: Dictionary = s.patrons[0]
	var left: float = p0["patience"]
	if absf(left - 2.0) > 0.001:
		return _fail("patience should drain 1.0/s on day 1, left=%f" % left)
	MetaSave.clear()
	ev = s.tick_sell(5.0)
	if not _has_event(ev, "patron_left"):
		return _fail("expired patience should walk the patron out")
	if not _has_event(ev, "day_complete"):
		return _fail("resolving the last patron should complete the day")
	if s.phase != ShopState.Phase.RESULTS:
		return _fail("day completion should land in RESULTS")
	if s.walkout_count != 1 or s.sales_count != 2:
		return _fail("day stats wrong (walkouts=%d sales=%d)" % [s.walkout_count, s.sales_count])

	# ---- Stage 9: persistence milestone wrote the save ---------------------
	var saved: Dictionary = MetaSave.read()
	if saved.is_empty():
		return _fail("day completion did not write user://save.json")
	for key in ["day", "gold", "upgrades", "resources", "stock", "shelves"]:
		if not saved.has(key):
			return _fail("save file missing key: " + key)
	var saved_gold: int = int(saved["gold"])
	if saved_gold != s.gold:
		return _fail("saved gold %d != live gold %d" % [saved_gold, s.gold])

	# ---- Stage 10: upgrades spend gold and change derived stats ------------
	s.gold = 200
	var slots_before: int = s.shelf_slots()
	ev = s.buy_upgrade("shelf")
	if not _has_event(ev, "upgrade_bought"):
		return _fail("buying Extra Shelf with 200g failed")
	if s.gold != 170:
		return _fail("Extra Shelf L1 should cost 30 (gold 200 -> 170), gold=%d" % s.gold)
	if s.shelf_slots() != slots_before + 1:
		return _fail("Extra Shelf did not add a slot")
	var haul_before: int = s.haul_capacity()
	s.buy_upgrade("haul")
	if s.haul_capacity() != haul_before + 1:
		return _fail("Bigger Basket did not raise haul capacity")
	s.gold = 0
	var lvl_before: int = s.upgrades["traffic"]
	ev = s.buy_upgrade("traffic")
	if not _has_event(ev, "upgrade_too_poor"):
		return _fail("broke purchase should report upgrade_too_poor")
	var lvl_after: int = s.upgrades["traffic"]
	if lvl_after != lvl_before:
		return _fail("broke purchase must not level the track")

	# ---- Stage 11: next day = progression + ramp + save ---------------------
	s.gold = 50
	ev = s.next_day()
	if s.day != 2 or s.phase != ShopState.Phase.GATHER:
		return _fail("next_day should advance to day 2 GATHER")
	if s.gather_nodes.size() != ShopState.NODE_COUNT:
		return _fail("day 2 beach did not respawn")
	var saved2: Dictionary = MetaSave.read()
	var saved_day: int = int(saved2["day"])
	if saved_day != 2:
		return _fail("next_day did not persist day=2")
	if s.patron_count() <= 4:
		return _fail("day 2 should ramp patron count past the day-1 base")

	# ---- Stage 12: save/load roundtrip --------------------------------------
	var s2 := ShopState.new()
	s2.setup(42, MetaSave.read())
	if s2.day != 2 or s2.gold != 50:
		return _fail("save/load roundtrip lost day/gold")
	var shelf_lvl: int = s2.upgrades["shelf"]
	if shelf_lvl != 1:
		return _fail("save/load roundtrip lost upgrades")

	# ---- Stage 13: arrivals through the real open_shop path ----------------
	var s3 := ShopState.new()
	s3.setup(9, {})
	s3.start_day()
	s3.finish_gather()
	if s3.phase != ShopState.Phase.CRAFT:
		return _fail("finish_gather should land in CRAFT")
	s3.resources = {"shell": 2}
	s3.craft("shell_charm")
	s3.stock_shelf(0)
	ev = s3.open_shop()
	if s3.phase != ShopState.Phase.SELL:
		return _fail("open_shop with stock should enter SELL")
	ev = s3.tick_sell(1.0)
	if not _has_event(ev, "patron_arrived") or s3.patrons.size() != 1:
		return _fail("first patron should arrive within ~0.8s of opening")

	# ---- Stage 14: loss condition — zero stock is a soft fail + restart ----
	var s4 := ShopState.new()
	s4.setup(11, {})
	s4.start_day()
	s4.finish_gather()
	ev = s4.open_shop()
	if not _has_event(ev, "day_failed") or s4.phase != ShopState.Phase.DAY_FAILED:
		return _fail("opening an empty shop should soft-fail the day")
	ev = s4.restart_day()
	if s4.phase != ShopState.Phase.GATHER or s4.gather_nodes.size() != ShopState.NODE_COUNT:
		return _fail("restart_day should rewind to a fresh GATHER")

	# Leave no residue: a real boot must not inherit the self-test's save.
	MetaSave.clear()
	return true
