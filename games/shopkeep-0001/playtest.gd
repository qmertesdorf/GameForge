extends SceneTree
# BALANCE / PLAYABILITY audit for Tide & Tally — the empirical gate the logic/UI
# self-tests can't be. Drives the REAL game loop with a deterministic COMPETENT
# cashier bot across a multi-day run and asserts the deepened game is actually:
#   - SOLVENT:      a competent day-1 banks > 0 (you can earn at all),
#   - PROGRESSABLE: reputation climbs to tier 1 so the Regulars destination (standing
#     orders) opens, gross gold accrues, upgrades buy,
#   - FAIR / no death-spiral: a competent player never hits "nothing to sell",
#   - a REAL TRIAGE, not a free reflex: demand SATURATES supply — more patrons want
#     goods than the shop can serve+stock — so "who do I serve next?" is a forced
#     allocation (unserved_frac > 0), AND that allocation is a genuine DECISION: a
#     value-first policy and an urgent-first policy reach materially different gold/rep
#     (the policy-divergence probe, run in the standalone gate).
# Prints per-day metrics + exactly "PLAYTEST OK" (exit 0) or "PLAYTEST FAIL: …" (1),
# plus one machine-readable "PLAYTEST METRICS {json}" line for tools/balance.mjs.
#
# WHY drive ShopState directly (not Main._process): Main.gd is a pure replay view
# ("never owns a rule"); the ENTIRE game loop lives in ShopState. Driving the rules
# engine IS driving the real loop here, deterministic with a fixed seed + fixed dt.
# The action methods (tap_node/craft/serve/…) are the same surface the view taps.
#
# WHAT THE BOT FOUND (recorded so the metric isn't mistaken for a redesign): the
# serve-time COOLDOWN this deepen pass added rarely forces a walkout, because the shop
# is STOCK-limited and sells OUT every day (soldout_days≈all, forced_walkouts≈0) — the
# cooldown adds queue WAIT (blocked_ticks) but stockout/mismatch end the rush before
# throughput does. The live decision the system actually creates is allocating scarce
# stock by VALUE under saturated demand; the cooldown makes serve-ORDER matter under
# time pressure. So winnability gates on the robust saturation signal (unserved_frac),
# and the policy-divergence probe is what proves the triage is a real decision.
#
# Bot policy is COMPETENT, not optimal. Two policies share all non-serve play:
#   urgent  — serve the most-URGENT servable patron (walkout-minimising; the gate run),
#   value   — serve the highest-VALUE servable patron (gold-chasing; divergence probe).

const ShopState := preload("res://ShopState.gd")
const ItemDB := preload("res://data/ItemDB.gd")
const UpgradeDB := preload("res://data/UpgradeDB.gd")
const MetaSave := preload("res://MetaSave.gd")
const TuneRef := preload("res://Tune.gd")

const DAYS: int = 12
const DT: float = 0.1          # fixed sell-phase tick step (deterministic)
const SELL_GUARD: int = 8000
const SEED_DEFAULT: int = 20240621

var fail_count: int = 0

func _initialize() -> void:
	_run()

func _fail(reason: String) -> void:
	fail_count += 1
	print("PLAYTEST FAIL: " + reason)


# ----- competent CRAFT priority: orders first, then demand, then value -------
func _craft_priority(s) -> Array:
	var prio: Array = []
	for o in s.standing_orders:
		var od: Dictionary = o
		var it: String = String(od["item"])
		if not prio.has(it):
			prio.append(it)
	for d in s.demand:
		var did: String = d
		if not prio.has(did):
			prio.append(did)
	var by_price: Array = ItemDB.RECIPE_ORDER.duplicate()
	by_price.sort_custom(func(a, b): return ItemDB.base_price(a) > ItemDB.base_price(b))
	for r in by_price:
		var rid: String = r
		if not prio.has(rid):
			prio.append(rid)
	return prio


func _play_gather(s) -> void:
	# Efficient comber: grab every node, banking when the basket fills. (Gathering
	# is not the subsystem under test — a competent player clears the beach; the
	# pressure we measure is at the register.)
	for i in range(s.gather_nodes.size()):
		var nd: Dictionary = s.gather_nodes[i]
		if nd["taken"]:
			continue
		if s.unbanked_total() >= s.haul_capacity():
			s.bank()
		s.tap_node(i)
	s.bank()
	s.finish_gather()


func _play_craft(s) -> void:
	var slots: int = s.shelf_slots()
	var prio: Array = _craft_priority(s)
	for rid_v in prio:                       # pass 1: one of each distinct prio item
		var rid: String = rid_v
		if s.shelves.size() + s.stock.size() >= slots:
			break
		if s.can_craft(rid):
			s.craft(rid)
	for rid_v2 in prio:                      # pass 2: top up with the most valuable craftable
		var rid2: String = rid_v2
		while s.shelves.size() + s.stock.size() < slots and s.can_craft(rid2):
			s.craft(rid2)
	while not s.stock.is_empty() and s.shelves.size() < slots:
		s.stock_shelf(0)


func _pick_servable(s, policy: String) -> Dictionary:
	# Among patrons whose want is on a shelf, choose by policy:
	#   urgent — lowest patience (walkout-minimising), value — highest sale value.
	var best_p: int = -1
	var best_shelf: int = -1
	var best_key: float = -1e9
	for pi in range(s.patrons.size()):
		var p: Dictionary = s.patrons[pi]
		var want: String = p["want"]
		var shelf: int = -1
		for si in range(s.shelves.size()):
			if String(s.shelves[si]) == want:
				shelf = si
				break
		if shelf < 0:
			continue
		var k: float
		if policy == "value":
			var price: float = float(ItemDB.base_price(want))
			if s.demand.has(want):
				price *= ItemDB.DEMAND_BONUS
			k = price * s.kind_price_mult(String(p.get("kind", "local")))
		else:
			k = -float(p["patience"])        # urgent: smallest patience → largest key
		if k > best_key:
			best_key = k
			best_p = pi
			best_shelf = shelf
	return {"patron": best_p, "shelf": best_shelf}


func _play_sell(s, policy: String) -> Dictionary:
	var arrived: int = 0
	var forced_walkouts: int = 0      # left while their want WAS on a shelf = throughput-lost
	var blocked_ticks: int = 0        # ticks the register was busy WITH a servable patron waiting
	var sold_out: int = 0
	var orders_total: int = s.standing_orders.size()
	var gold_before: int = s.gold
	var guard: int = 0
	while s.phase == ShopState.Phase.SELL and guard < SELL_GUARD:
		guard += 1
		var ev: Array = s.tick_sell(DT)
		for e in ev:
			var evd: Dictionary = e
			var t: String = evd["type"]
			if t == "patron_arrived":
				arrived += 1
			elif t == "patron_left":
				if s.shelves.has(String(evd["want"])):
					forced_walkouts += 1
			elif t == "day_complete" and bool(evd.get("sold_out", false)):
				sold_out = 1
		var pick: Dictionary = _pick_servable(s, policy)
		if int(pick["patron"]) >= 0:
			if s.serve_cooldown <= 0.0:
				s.serve(int(pick["patron"]), int(pick["shelf"]))
			else:
				blocked_ticks += 1
	var orders_filled: int = 0
	for o in s.standing_orders:
		var od: Dictionary = o
		if bool(od["filled"]):
			orders_filled += 1
	return {
		"arrived": arrived, "served": s.sales_count, "walkouts": s.walkout_count,
		"forced_walkouts": forced_walkouts, "blocked_ticks": blocked_ticks, "sold_out": sold_out,
		"orders_total": orders_total, "orders_filled": orders_filled, "income": s.gold - gold_before,
	}


func _play_results(s) -> void:
	# Competent reinvestment: shop capacity & patience first (more sales / fewer
	# losses), then gathering reach, then the Pry Bar (pearls → top-tier orders),
	# then traffic. Buy cheapest-affordable in that priority until broke.
	var order: Array = ["shelf", "patience", "haul", "rare", "tide", "traffic"]
	var bought: bool = true
	while bought:
		bought = false
		for tr_v in order:
			var tr: String = tr_v
			var c: int = UpgradeDB.cost(tr, s.upgrades[tr])
			if c >= 0 and s.gold >= c:
				s.buy_upgrade(tr)
				bought = true
				break
	s.next_day()


# Play a whole DAYS-long run under one serve policy. verbose → per-day prints.
func _play_run(seed_value: int, policy: String, verbose: bool) -> Dictionary:
	MetaSave.clear()
	var s = ShopState.new()
	s.setup(seed_value, {})
	s.start_day()
	var R := {
		"day1_income": 0, "gross": 0, "arrived": 0, "served": 0, "walkouts": 0,
		"forced": 0, "blocked": 0, "soldout_days": 0, "orders_filled": 0,
		"reached_tier1": false, "first_order_day": 99, "day_failed": false,
		"days_played": 0, "final_rep": 0, "upgrades": 0,
	}
	var upgrades_start: int = _upgrade_sum(s)
	for di in range(DAYS):
		var day: int = s.day
		_play_gather(s)
		if s.phase != ShopState.Phase.CRAFT:
			if verbose:
				_fail("day %d did not reach CRAFT after gathering" % day)
			break
		_play_craft(s)
		s.open_shop()
		if s.phase == ShopState.Phase.DAY_FAILED:
			R["day_failed"] = true
			if verbose:
				_fail("day %d ended with nothing to sell (a competent bot should always stock)" % day)
			break
		var m: Dictionary = _play_sell(s, policy)
		R["days_played"] = int(R["days_played"]) + 1
		if day == 1:
			R["day1_income"] = int(m["income"])
		R["gross"] = int(R["gross"]) + int(m["income"])
		R["arrived"] = int(R["arrived"]) + int(m["arrived"])
		R["served"] = int(R["served"]) + int(m["served"])
		R["walkouts"] = int(R["walkouts"]) + int(m["walkouts"])
		R["forced"] = int(R["forced"]) + int(m["forced_walkouts"])
		R["blocked"] = int(R["blocked"]) + int(m["blocked_ticks"])
		R["soldout_days"] = int(R["soldout_days"]) + int(m["sold_out"])
		R["orders_filled"] = int(R["orders_filled"]) + int(m["orders_filled"])
		if int(m["orders_filled"]) > 0 and day < int(R["first_order_day"]):
			R["first_order_day"] = day
		if s.reputation_tier() >= 1:
			R["reached_tier1"] = true
		if verbose:
			print("PLAYTEST day%d: arrived=%d served=%d walk=%d (forced=%d) blocked=%d soldout=%d income=%dg rep=%d(T%d) orders=%d/%d shelves=%d" % [
				day, int(m["arrived"]), int(m["served"]), int(m["walkouts"]), int(m["forced_walkouts"]),
				int(m["blocked_ticks"]), int(m["sold_out"]), int(m["income"]), s.reputation, s.reputation_tier(),
				int(m["orders_filled"]), int(m["orders_total"]), s.shelf_slots()])
		if s.phase == ShopState.Phase.RESULTS:
			_play_results(s)
	R["final_rep"] = s.reputation
	R["upgrades"] = _upgrade_sum(s) - upgrades_start
	MetaSave.clear()
	return R


func _run() -> void:
	var seed_value: int = TuneRef.seed_of(SEED_DEFAULT)
	# Gate run: the urgent (walkout-minimising) policy — the competent baseline.
	var R: Dictionary = _play_run(seed_value, "urgent", true)

	var arrived: int = int(R["arrived"])
	var served: int = int(R["served"])
	var unserved: int = maxi(0, arrived - served)
	var unserved_frac: float = float(unserved) / float(maxi(1, arrived))
	var gross: int = int(R["gross"])
	var day1: int = int(R["day1_income"])

	print("PLAYTEST summary: days=%d gross=%dg arrived=%d served=%d unserved=%d(%.0f%%) walk=%d forced=%d blocked_ticks=%d soldout_days=%d orders_filled=%d upgrades=%d rep=%d" % [
		int(R["days_played"]), gross, arrived, served, unserved, unserved_frac * 100.0,
		int(R["walkouts"]), int(R["forced"]), int(R["blocked"]), int(R["soldout_days"]),
		int(R["orders_filled"]), int(R["upgrades"]), int(R["final_rep"])])

	# Policy-divergence probe — the proof the triage is a real DECISION, not a reflex.
	# Same seed → identical gather/demand/spawn; only serve-ORDER differs, so any
	# gold/rep gap is attributable to the allocation choice. Run ALWAYS (incl. per
	# search candidate) so the search optimises the REAL signal, not a proxy.
	var V: Dictionary = _play_run(seed_value, "value", false)
	var dgold: int = int(V["gross"]) - gross
	var drep: int = int(V["final_rep"]) - int(R["final_rep"])
	var dorders: int = int(V["orders_filled"]) - int(R["orders_filled"])
	# A real triage: the two policies reach materially different gold OR rep. This is
	# SEED-DEPENDENT (some days' patron mix just doesn't pit value against urgency), so
	# it is REPORTED here and judged in AGGREGATE by the balance search (mean
	# triage_div_gold band) — NOT a per-seed hard gate (that would flake on seed noise).
	var divergence_real: bool = absi(dgold) >= maxi(50, int(0.05 * float(gross))) or absi(drep) >= 3
	print("PLAYTEST divergence (value-first vs urgent-first): Δgold=%+dg Δrep=%+d Δorders=%+d  real=%s  [value gross=%dg rep=%d | urgent gross=%dg rep=%d]" % [
		dgold, drep, dorders, str(divergence_real), int(V["gross"]), int(V["final_rep"]), gross, int(R["final_rep"])])

	# ---- hard winnability gates ----
	if day1 <= 0:
		_fail("a competent day-1 banked 0 gold — the game is unwinnable")
	if gross < day1 * 3:
		_fail("gross earnings did not accumulate across the run — no real progression")
	if not bool(R["reached_tier1"]):
		_fail("a competent player never reached Reputation tier 1 — the Regulars destination never opens")
	if int(R["upgrades"]) <= 0:
		_fail("the player never afforded a single upgrade — progression is gated too hard")
	if unserved <= 0:
		_fail("no excess demand: a competent bot served EVERY patron who arrived — 'who do I serve next?' is a free reflex (no_trivial_dominant)")

	var metrics := {
		"solvent": day1 > 0,
		"first_goal_reachable": bool(R["reached_tier1"]),
		"no_death_spiral": not bool(R["day_failed"]),
		"no_trivial_dominant": unserved > 0,
		"divergence_real": divergence_real,
		"triage_div_gold": absi(dgold),
		"triage_div_rep": absi(drep),
		"gross_earned": gross,
		"day1_income": day1,
		"arrived_total": arrived,
		"served_total": served,
		"unserved_frac": snappedf(unserved_frac, 0.001),
		"walkout_total": int(R["walkouts"]),
		"forced_walkouts": int(R["forced"]),
		"blocked_ticks": int(R["blocked"]),
		"soldout_days": int(R["soldout_days"]),
		"orders_filled": int(R["orders_filled"]),
		"first_order_day": int(R["first_order_day"]),
		"upgrades_bought": int(R["upgrades"]),
		"days_played": int(R["days_played"]),
	}
	print("PLAYTEST METRICS " + JSON.stringify(metrics))

	if fail_count == 0:
		print("PLAYTEST OK")
		quit(0)
	else:
		print("PLAYTEST FAIL: %d checks failed" % fail_count)
		quit(1)


func _upgrade_sum(s) -> int:
	var n: int = 0
	for k in s.upgrades.keys():
		n += int(s.upgrades[k])
	return n
