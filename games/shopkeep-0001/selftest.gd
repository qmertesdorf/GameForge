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
	s.serve_cooldown = 0.0  # clear the register busy-timer; here we test sale math, not the cooldown
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

	# ---- Stage 15: patron archetypes — tourist premium + impatience ---------
	var s5 := ShopState.new()
	s5.setup(5, {})
	s5.phase = ShopState.Phase.SELL
	s5.demand = []
	s5.shelves = ["shell_charm", "shell_charm"]
	var mp5: float = s5.max_patience()
	var tp5: float = mp5 * s5.kind_patience_mult("tourist")
	s5.patrons = [
		{"kind": "tourist", "want": "shell_charm", "patience": tp5, "max_patience": tp5},
		{"kind": "local", "want": "shell_charm", "patience": mp5, "max_patience": mp5},
	]
	s5.patrons_to_come = 0
	var ev5: Array = s5.serve(0, 0)
	var sale5: Dictionary = _get_event(ev5, "sale")
	if sale5.is_empty():
		return _fail("archetype: serving a tourist did not sell")
	var tourist_amt: int = sale5["amount"]
	if tourist_amt != int(round(8.0 * ShopState.TOURIST_PRICE_MULT)):
		return _fail("tourist should pay round(base*TOURIST_PRICE_MULT), got %d" % tourist_amt)
	s5.serve_cooldown = 0.0  # clear register busy-timer; testing price math, not the cooldown
	ev5 = s5.serve(0, 0)  # index shifted after the first sale -> the local
	var sale5b: Dictionary = _get_event(ev5, "sale")
	if sale5b.is_empty():
		return _fail("archetype: serving the local did not sell")
	var local_amt: int = sale5b["amount"]
	if local_amt != 8:
		return _fail("local should pay base 8, got %d" % local_amt)
	if tourist_amt <= local_amt:
		return _fail("tourist premium (%d) should exceed local base (%d)" % [tourist_amt, local_amt])
	if not (s5.kind_patience_mult("tourist") < 1.0):
		return _fail("tourist patience multiplier should be < 1.0 (impatient)")
	if not (s5.kind_patience_mult("local") == 1.0):
		return _fail("local patience multiplier should be 1.0 (baseline)")

	# ---- Stage 16: reputation — locals build it, tourists don't, walkouts cost
	MetaSave.clear()
	var s6 := ShopState.new()
	s6.setup(6, {})
	s6.phase = ShopState.Phase.SELL
	s6.demand = []
	s6.shelves = ["shell_charm", "shell_charm"]
	s6.patrons = [
		{"kind": "local", "want": "shell_charm", "patience": 10.0, "max_patience": 10.0},
		{"kind": "tourist", "want": "shell_charm", "patience": 10.0, "max_patience": 10.0},
	]
	s6.patrons_to_come = 0
	var rep0: int = s6.reputation
	s6.serve(0, 0)  # local
	if s6.reputation != rep0 + ShopState.REP_PER_LOCAL:
		return _fail("serving a local should add REP_PER_LOCAL reputation")
	var rep_after_local: int = s6.reputation
	s6.serve_cooldown = 0.0  # clear register busy-timer; testing reputation, not the cooldown
	s6.serve(0, 0)  # tourist (index 0 after the local was consumed)
	if s6.reputation != rep_after_local:
		return _fail("serving a tourist must not change reputation")

	# A local walking out costs reputation.
	var s7r := ShopState.new()
	s7r.setup(71, {})
	s7r.phase = ShopState.Phase.SELL
	s7r.reputation = 2
	s7r.shelves = ["shell_charm"]   # keep stock so the sold-out path doesn't fire
	s7r.patrons = [{"kind": "local", "want": "pearl_ring", "patience": 0.5, "max_patience": 12.0}]
	s7r.patrons_to_come = 0
	var ev7r: Array = s7r.tick_sell(5.0)
	if not _has_event(ev7r, "patron_left"):
		return _fail("rep: impatient local should walk out")
	if s7r.reputation != 2 - ShopState.REP_ON_LOCAL_WALKOUT:
		return _fail("a local walkout should cost REP_ON_LOCAL_WALKOUT, rep=%d" % s7r.reputation)

	# Floor at zero; a tourist walkout costs nothing.
	var s8r := ShopState.new()
	s8r.setup(81, {})
	s8r.phase = ShopState.Phase.SELL
	s8r.reputation = 0
	s8r.shelves = ["shell_charm"]
	s8r.patrons = [{"kind": "tourist", "want": "pearl_ring", "patience": 0.5, "max_patience": 12.0}]
	s8r.patrons_to_come = 0
	s8r.tick_sell(5.0)
	if s8r.reputation != 0:
		return _fail("tourist walkout must not change rep / rep must never go negative")

	# Persistence: reputation survives the save/load roundtrip.
	s6.reputation = 5
	MetaSave.write(s6.snapshot())
	var s9r := ShopState.new()
	s9r.setup(99, MetaSave.read())
	if s9r.reputation != 5:
		return _fail("reputation lost across the save/load roundtrip")
	MetaSave.clear()

	# ---- Stage 17: standing orders — reputation's CRAFT destination ----------
	MetaSave.clear()
	# Gating: tier 0 issues none; each tier issues one pre-announced order.
	var so0 := ShopState.new()
	so0.setup(17, {})
	so0.reputation = 0
	so0.start_day()
	if so0.standing_orders.size() != 0:
		return _fail("no standing orders should exist at reputation tier 0")
	var so1 := ShopState.new()
	so1.setup(17, {})
	so1.reputation = ShopState.REP_PER_TIER
	so1.start_day()
	if so1.standing_orders.size() != 1:
		return _fail("tier 1 should issue 1 standing order, got %d" % so1.standing_orders.size())
	var so3 := ShopState.new()
	so3.setup(17, {})
	so3.reputation = ShopState.REP_PER_TIER * ShopState.MAX_REP_TIER
	so3.start_day()
	if so3.standing_orders.size() != ShopState.MAX_REP_TIER:
		return _fail("max tier should issue MAX_REP_TIER orders, got %d" % so3.standing_orders.size())

	# Fairness: without the Pry Bar, orders never demand an (uncraftable) pearl item.
	var sof := ShopState.new()
	sof.setup(3, {})
	sof.reputation = ShopState.REP_PER_TIER * ShopState.MAX_REP_TIER
	if sof.top_craftable_tier() != 2:
		return _fail("top craftable tier without the Pry Bar should be 2")
	for d in range(1, 7):
		sof.day = d
		sof.start_day()
		for o in sof.standing_orders:
			var od: Dictionary = o
			var rc: Dictionary = ItemDB.recipe(String(od["item"]))
			if rc["cost"].has("pearl"):
				return _fail("standing order demanded a pearl item without rare access")
	sof.upgrades["rare"] = 1
	if sof.top_craftable_tier() != 3:
		return _fail("the Pry Bar should raise top craftable tier to 3")

	# Serving a Regular fills the order, pays the loyalty multiplier, builds rep.
	var srv := ShopState.new()
	srv.setup(5, {})
	srv.reputation = ShopState.REP_PER_TIER
	srv.phase = ShopState.Phase.SELL
	srv.standing_orders = [{"item": "seaglass_pendant", "filled": false}]
	srv.demand = []
	srv.shelves = ["seaglass_pendant"]
	srv.patrons = [{"kind": "regular", "want": "seaglass_pendant", "patience": 10.0, "max_patience": 10.0}]
	srv.patrons_to_come = 0
	var rep_b: int = srv.reputation
	var evr: Array = srv.serve(0, 0)
	var saler: Dictionary = _get_event(evr, "sale")
	if saler.is_empty():
		return _fail("regular: serving the standing-order item did not sell")
	if not bool(saler.get("order_filled", false)):
		return _fail("serving a regular should report the standing order filled")
	var first_order: Dictionary = srv.standing_orders[0]
	if not bool(first_order["filled"]):
		return _fail("the standing order's filled flag was not set")
	var reg_amt: int = saler["amount"]
	if reg_amt != int(round(18.0 * ShopState.REGULAR_PRICE_MULT)):
		return _fail("regular should pay round(base*REGULAR_PRICE_MULT), got %d" % reg_amt)
	if srv.reputation != rep_b + ShopState.REP_PER_LOCAL:
		return _fail("serving a regular should still build reputation")

	# Decoupling: value (regular) is NOT aligned with urgency (tourist).
	if not (ShopState.REGULAR_PRICE_MULT > ShopState.TOURIST_PRICE_MULT):
		return _fail("regulars (value) should out-pay tourists (urgency)")
	if not (srv.kind_patience_mult("regular") > srv.kind_patience_mult("tourist")):
		return _fail("regulars should be MORE patient than tourists (value decoupled from urgency)")

	# Acquisition path: a Regular actually ARRIVES for each standing order through
	# the real open_shop -> tick_sell loop (guards against a dormant feature).
	MetaSave.clear()
	var sr2 := ShopState.new()
	sr2.setup(42, {})
	sr2.reputation = ShopState.REP_PER_TIER * ShopState.MAX_REP_TIER
	sr2.upgrades["rare"] = 1
	sr2.day = 6
	sr2.start_day()
	var orders_today: int = sr2.standing_orders.size()
	sr2.finish_gather()
	sr2.shelves = ["shell_charm", "seaglass_pendant", "wind_chime", "pearl_ring"]
	sr2.open_shop()
	var regulars_seen: int = 0
	var guard: int = 0
	while sr2.phase == ShopState.Phase.SELL and guard < 6000:
		var evs: Array = sr2.tick_sell(0.5)
		for e in evs:
			var ed: Dictionary = e
			if String(ed.get("type", "")) == "patron_arrived" and String(ed.get("kind", "")) == "regular":
				regulars_seen += 1
		guard += 1
	if regulars_seen < orders_today:
		return _fail("expected >= %d regulars for standing orders, saw %d" % [orders_today, regulars_seen])
	MetaSave.clear()

	# ---- Stage 18: serve-time contention — the register cooldown ------------
	# Serving occupies the register for SERVE_TIME; a second serve is refused
	# until it clears. Serve THROUGHPUT is the scarce shared resource that turns
	# "who do I serve next?" into a real triage (you cannot serve everyone).
	var sc := ShopState.new()
	sc.setup(18, {})
	sc.phase = ShopState.Phase.SELL
	sc.demand = []
	sc.shelves = ["shell_charm", "shell_charm"]
	sc.patrons = [
		{"kind": "local", "want": "shell_charm", "patience": 99.0, "max_patience": 99.0},
		{"kind": "local", "want": "shell_charm", "patience": 99.0, "max_patience": 99.0},
	]
	sc.patrons_to_come = 0
	var evc: Array = sc.serve(0, 0)
	if _get_event(evc, "sale").is_empty():
		return _fail("cooldown: the first serve should succeed")
	if absf(sc.serve_cooldown - ShopState.SERVE_TIME) > 0.001:
		return _fail("a sale should arm the register cooldown to SERVE_TIME")
	var gold_busy: int = sc.gold
	evc = sc.serve(0, 0)
	if not _has_event(evc, "register_busy"):
		return _fail("serving while the register is busy should report register_busy")
	if sc.gold != gold_busy or sc.shelves.size() != 1 or sc.patrons.size() != 1:
		return _fail("a refused (busy) serve must not change any state")
	sc.tick_sell(ShopState.SERVE_TIME + 0.01)
	if sc.serve_cooldown > 0.0:
		return _fail("the cooldown should clear after SERVE_TIME elapses")
	evc = sc.serve(0, 0)
	if _get_event(evc, "sale").is_empty():
		return _fail("serving after the cooldown clears should succeed")

	# Contention: with throughput capped, even OPTIMAL serving (front patron the
	# instant the register frees) cannot clear a rush before someone walks —
	# proving serving A costs you B (the triage the design needs).
	var sq := ShopState.new()
	sq.setup(19, {})
	sq.phase = ShopState.Phase.SELL
	sq.day = 1                       # patience_drain == DRAIN_BASE == 1.0/s
	sq.demand = []
	sq.shelves = ["shell_charm", "shell_charm", "shell_charm"]
	sq.patrons = [
		{"kind": "local", "want": "shell_charm", "patience": 1.5, "max_patience": 1.5},
		{"kind": "local", "want": "shell_charm", "patience": 1.5, "max_patience": 1.5},
		{"kind": "local", "want": "shell_charm", "patience": 1.5, "max_patience": 1.5},
	]
	sq.patrons_to_come = 0
	var guard2: int = 0
	while sq.phase == ShopState.Phase.SELL and guard2 < 400:
		sq.tick_sell(0.1)
		if sq.serve_cooldown <= 0.0 and not sq.patrons.is_empty() and not sq.shelves.is_empty():
			sq.serve(0, 0)
		guard2 += 1
	if sq.sales_count >= 3:
		return _fail("throughput too generous — served all 3 of a rush (no contention)")
	if sq.walkout_count < 1:
		return _fail("the throughput cap should force at least one walkout on a rush")
	MetaSave.clear()

	# ---- Stage 19: an UNFILLED standing order costs reputation at day end ----
	# This is the stake that makes pre-stocking the order (spending scarce pearls
	# in CRAFT) actually matter — ignoring an order is a reputation hit.
	var sm := ShopState.new()
	sm.setup(20, {})
	sm.reputation = ShopState.REP_PER_TIER * 2
	sm.phase = ShopState.Phase.SELL
	sm.standing_orders = [{"item": "pearl_ring", "filled": true}, {"item": "tide_lantern", "filled": false}]
	sm.shelves = ["shell_charm"]
	sm.patrons = []
	sm.patrons_to_come = 0
	var rep_pre: int = sm.reputation
	var evm: Array = sm.tick_sell(0.1)  # no patrons + none coming -> the day completes
	var dc: Dictionary = _get_event(evm, "day_complete")
	if dc.is_empty():
		return _fail("order-penalty: the day should complete with no patrons left")
	if int(dc["orders_total"]) != 2 or int(dc["orders_filled"]) != 1:
		return _fail("day_complete should report 1/2 orders filled, got %d/%d" % [int(dc["orders_filled"]), int(dc["orders_total"])])
	if sm.reputation != rep_pre - ShopState.REP_ON_ORDER_MISSED:
		return _fail("one unfilled order should cost REP_ON_ORDER_MISSED, rep=%d" % sm.reputation)
	MetaSave.clear()

	# Leave no residue: a real boot must not inherit the self-test's save.
	MetaSave.clear()
	return true
