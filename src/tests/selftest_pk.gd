extends RefCounted
## 0.3.1 adventurer AI + Scorch PK self-tests. Called from selftest.gd:
##   for r in PkSelftest.run(main, world, p): check(r[0], r[1])
## Returns [[ok, description], ...] (kept in its own file to keep merges with
## the other 0.3.1 tracks small).

static var out: Array = []


static func ok(cond: bool, what: String) -> void:
	out.append([cond, what])


static func _agent(sub: String, id: String, lv: int, seed: int) -> AIAgent:
	var a := AIAgent.new()
	a.id = id
	a.name = id
	a.persona = AdvBrain.persona_by_id(sub)
	a.rng.seed = seed
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	a.home_town = "fenhollow"
	a.town = "fenhollow"
	a.home = Vector2i(2, 2)
	a.pos = a.home
	AdvBrain.roll(a, rng)
	for sk in ["attack", "strength", "defence", "vitality"]:
		a.skills.xp[sk] = GameData.xp_for_level(lv)
	a.hp = float(AIBrain.agent_max_hp(a))
	return a


static func _view(a: AIAgent, world, at: Vector2i) -> AIPlayer:
	var v := AIPlayer.new()
	a.pos = at
	v.bind(a, world)
	a.view = v
	if AIDirector._parent:
		AIDirector._parent.add_child(v)
	v.place_at(world.find_free_tile_near(at, 4))
	a.pos = v.tile
	return v


static func _drop_view(v: AIPlayer) -> void:
	if v.agent:
		v.agent.view = null
	if v.get_parent():
		v.get_parent().remove_child(v)
	v.free()


static func run(_main, world: World, p: Player) -> Array:
	out = []
	var T := Tick.tick_count + 900000
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# ------------------------------------------------------------ zones --
	var zs := PkRules.zones()
	ok(not zs.is_empty() and PkRules.is_pk(Vector2i(236, -262)) and PkRules.is_pk(Vector2i(100, -300)) and not PkRules.is_pk(Vector2i(0, 0))
		and not PkRules.is_pk(Vector2i(330, -200)) and not PkRules.is_pk(Vector2i(300, 170)),
		"PK zone 'the Scorch' covers the north (y < -250); towns are outside")
	var spot := PkRules.random_spot(rng, world)
	var spot2 := PkRules.random_spot(rng, world)
	ok(PkRules.is_pk(spot) and PkRules.is_pk(spot2) and not world.is_blocked(spot), "raid spots are walkable tiles inside the zone (%s)" % str(spot))
	ok(CombatRules.is_multi(spot) and CombatRules.label(p) != "", "the whole PK zone is multi-combat")
	# ---------------------------------------------------- population --
	var n := {}
	for a in AIDirector.records:
		if AdvBrain.is_adv(a):
			n[AdvBrain.sub(a)] = int(n.get(AdvBrain.sub(a), 0)) + 1
	var pop_cfg: Dictionary = AdvBrain.cfg().get("population", {})
	var want := int(pop_cfg.get("hero", 0)) + int(pop_cfg.get("raider", 0)) + int(pop_cfg.get("opportunist", 0))
	ok(int(n.get("hero", 0)) + int(n.get("raider", 0)) + int(n.get("opportunist", 0)) == want and want >= 12 and AIDirector.records.size() == 40 + want,
		"%d adventurer-class AI on top of the 40; the population stays constant through Scorch resets (%s, %d resets so far)" % [want, str(n), AdvBrain.resets_total])
	var rlv := 99
	for a in AIDirector.records:
		if AdvBrain.is_raider(a) and a.gen == 1:     # (new players start at level 1)
			rlv = mini(rlv, AdvBrain.cb_level(a))
	ok(rlv >= 8, "the original raiders start as seasoned fighters (lowest cb %d)" % rlv)
	# ----------------------------------------------- targets / BiS ---
	var lo := _agent("hero", "t_lo", 3, 1)
	var hi := _agent("hero", "t_hi", 45, 2)
	hi.coins = 0
	var r_lo := AdvBrain.rank_targets(lo)
	var r_hi := AdvBrain.rank_targets(hi)
	var lo_ok := not r_lo.is_empty()
	for r in r_lo:
		lo_ok = lo_ok and int(r["ev"]["level"]) <= AdvBrain.cb_level(lo) + int(AdvBrain.cfg().get("level_margin", 6)) and not bool(r["pk"])
	ok(lo_ok, "a level-3 adventurer only picks safe, non-Scorch targets (best: %s)" % (str(r_lo[0]["kind"]) if lo_ok else "-"))
	var top_lv := func(rs: Array) -> int: return int(rs[0]["ev"]["level"]) if not rs.is_empty() else 0
	ok(top_lv.call(r_hi) > top_lv.call(r_lo), "target choice scales with level (cb3 -> %s, cb45 -> %s)" % [
		str(r_lo[0]["kind"]) if not r_lo.is_empty() else "-", str(r_hi[0]["kind"]) if not r_hi.is_empty() else "-"])
	var kinds_seen := {}
	for r in r_hi:
		kinds_seen[r["kind"]] = true
	ok(kinds_seen.size() >= 2, "targets come generically from enemies.json (%d kinds ranked)" % kinds_seen.size())
	var b_lo := AdvBrain.bis(lo)
	var b_hi := AdvBrain.bis(hi)
	var req_ok := true
	for s in b_lo.keys():
		req_ok = req_ok and (b_lo[s] == "" or Combat.equip_error(lo.skills, b_lo[s]) == "")
	var t_of := func(id: String) -> int: return int(GameData.item(id).get("gear", {}).get("tier", 0)) if id != "" else 0
	ok(req_ok and t_of.call(b_hi["body"]) > t_of.call(b_lo["body"]) and t_of.call(b_hi["weapon"]) >= 3,
		"best-in-slot respects level requirements (cb3 body %s, cb45 body %s, weapon %s)" % [b_lo["body"], b_hi["body"], b_hi["weapon"]])
	# ------------------------------------------------- gear buying ---
	var buyer := _agent("hero", "t_buyer", 22, 3)
	buyer.tools.erase("melee")
	buyer.gear.clear()
	buyer.give_tool("bronze_sword")
	buyer.coins = 20000
	AIDirector.records.append(buyer)
	var c0 := AdvBrain.counters.duplicate()
	var tier0: float = AdvBrain.gear_tier(buyer)["mean"]
	var coins0 := buyer.coins
	AdvBrain.gear_trade(buyer, T)
	var tier1: float = AdvBrain.gear_tier(buyer)["mean"]
	var bought := 0
	for k in AdvBrain.counters.keys():
		if str(k).begins_with("buy_"):
			bought += int(AdvBrain.counters[k]) - int(c0.get(k, 0))
	ok(tier1 > tier0 and bought >= 2 and buyer.coins < coins0 and int(AdvBrain.gear_tier(buyer)["max"]) == 3, "a level-22 adventurer buys steel upgrades in town and wears them (tier %.1f -> %.1f, %d buys, %d marks)" % [tier0, tier1, bought, coins0 - buyer.coins])
	ok(AdvBrain.commissions.size() >= 1, "pieces no shop or the Exchange has are commissioned from a smith (%d posted)" % AdvBrain.commissions.size())
	var all_ok := true
	for s in AdvBrain.cfg().get("slots", []):
		var cur := AdvBrain.current(buyer, s)
		all_ok = all_ok and (cur == "" or Combat.equip_error(buyer.skills, cur) == "")
	ok(all_ok, "everything it wears meets the level requirement")
	# ------------------------------------------------- commissions ---
	var smith: AIAgent = null
	for a in AIDirector.records:
		if a.persona_id() == "smith" and a.town == "fenhollow":
			smith = a
			break
	if smith == null:
		for a in AIDirector.records:
			if a.persona_id() == "smith":
				smith = a
				break
	var sm_town := smith.town
	var sm_xp: int = smith.skills.xp["smithing"]
	var sm_coins := smith.coins
	smith.town = buyer.town
	smith.skills.xp["smithing"] = GameData.xp_for_level(40)
	smith.stash_add("steel_bar", 3)
	AdvBrain.commissions.clear()
	buyer.coins = 5000
	AdvBrain.post_commission(buyer, "steel_helm", 400, T)
	ok(AdvBrain.has_commission(buyer.id, "head"), "an adventurer can commission a smith for a piece")
	var bc := buyer.coins
	var sc := smith.coins
	AdvBrain.smith_fill(smith, T + 10)
	ok(AdvBrain.commissions.is_empty() and AdvBrain.current(buyer, "head") == "steel_helm" and buyer.coins == bc - 400 and smith.coins == sc + 400,
		"a smith forges the commissioned steel helm; paid on delivery, coin moves agent to agent")
	smith.town = sm_town
	smith.skills.xp["smithing"] = sm_xp
	smith.coins = sm_coins
	# ------------------------------------- 0.3.1 gear market balance --
	var gm := Market.town(smith.town)
	var gid := "steel_sword"
	var g_base := GameData.item_value(gid)
	var g_ref0 = gm.reference.get(gid)
	var g_stash := smith.stash_count(gid)
	smith.stash_add(gid, -g_stash)
	var sm_orders: Dictionary = smith.my_orders.duplicate()
	smith.my_orders.clear()
	gm.reference[gid] = g_base
	var pf_free := GearEconomy.production_factor(smith, gid)
	var ge_pc: Dictionary = GearEconomy.cfg()["production"]
	var ge_heap := int(ge_pc["own_free"]) + 2 * int(ge_pc["own_span"])
	smith.stash_add(gid, ge_heap)
	var pf_stock := GearEconomy.production_factor(smith, gid)
	smith.stash_add(gid, -ge_heap)
	gm.reference[gid] = int(g_base * (float(ge_pc["price_stop"]) - 0.05))
	var pf_cheap := GearEconomy.production_factor(smith, gid)
	ok(pf_free > 0.95 and pf_stock < 0.35 and pf_cheap == 0.0 and GearEconomy.production_factor(smith, "bread") == 1.0,
		"demand-aware smithing: gear output scales down with unsold stock and a price under base (%.2f / %.2f with %d stocked / %.2f under price_stop; non-gear untouched)" % [pf_free, pf_stock, ge_heap, pf_cheap])
	GearEconomy.reset()
	# 0.3.1 monitor level band (data/economy_monitor.json)
	var lb: Dictionary = EconomyMonitor.cfg().get("level_band", {})
	ok(not lb.is_empty() and EconomyMonitor.level_action(float(lb["low"]) - 0.03, -0.004, 0.0) == 1 and EconomyMonitor.level_action(float(lb["low"]) - 0.03, 0.01, 0.0) == 0
		and EconomyMonitor.level_action(1.0, -0.004, 0.0) == 0 and EconomyMonitor.level_action(float(lb["high"]) + 0.03, 0.0, 0.0) == -1,
		"monitor level band: warms a slow slide below %.2f, not while recovering or inside the band; cools above %.2f" % [float(lb.get("low", 0)), float(lb.get("high", 0))])
	smith.stash_add(gid, 6)
	var ge_sc0 := smith.coins
	GearEconomy.scrap_surplus(smith)
	var ge_each := GearEconomy.scrap_price(gid)
	var ge_got := 6 - smith.stash_count(gid)
	var ge_purse := int(GearEconomy.cfg()["scrap"]["purse_per_town_day"])
	ok(ge_got >= 1 and smith.stash_count(gid) >= int(GearEconomy.cfg()["scrap"]["keep_producer"]) and smith.coins - ge_sc0 == ge_got * ge_each and ge_got * ge_each <= ge_purse and ge_each < int(g_base * 0.6),
		"a glutted wearable goes to the armourer for scrap below the market (%d x %d marks, purse %d/day, keeps %d)" % [ge_got, ge_each, ge_purse, smith.stash_count(gid)])
	smith.stash_add(gid, 20)
	var ge_sc1 := smith.coins
	for i in 10:
		GearEconomy.scrap_surplus(smith)
	ok(smith.coins - ge_sc1 + ge_got * ge_each <= ge_purse, "the scrap purse caps the faucet per town per day (%d paid today)" % (smith.coins - ge_sc1 + ge_got * ge_each))
	gm.reference[gid] = g_base
	var ge_sc2 := smith.coins
	var ge_n_before := smith.stash_count(gid)
	GearEconomy.reset()
	GearEconomy.scrap_surplus(smith)
	ok(smith.stash_count(gid) == ge_n_before or gm.depth(gid, false) > int(GearEconomy.cfg()["scrap"]["depth_free"]), "no scrapping while the piece sells near base")
	smith.stash_add(gid, -smith.stash_count(gid))
	# commission filled from finished stock (no bars used)
	smith.town = buyer.town
	smith.stash_add("iron_helm", 1)
	var ge_bars0 := smith.stash_count("iron_bar")
	buyer.gear.erase("head")
	buyer.coins = 5000
	AdvBrain.commissions.clear()
	AdvBrain.post_commission(buyer, "iron_helm", 150, T)
	AdvBrain.smith_fill(smith, T + 20)
	ok(AdvBrain.commissions.is_empty() and smith.stash_count("iron_helm") == 0 and smith.stash_count("iron_bar") == ge_bars0 and str(buyer.adv.get("buys", [[""]]).back()[0]) == "iron_helm",
		"a smith fills a commission from finished stock before forging (left %d, helm %d, bars %d->%d, head %s)" % [AdvBrain.commissions.size(), smith.stash_count("iron_helm"), ge_bars0, smith.stash_count("iron_bar"), AdvBrain.current(buyer, "head")])
	smith.town = sm_town
	smith.coins = sm_coins
	smith.stash_add(gid, g_stash)
	smith.my_orders = sm_orders
	if g_ref0 == null:
		gm.reference.erase(gid)
	else:
		gm.reference[gid] = g_ref0
	GearEconomy.reset()
	# ----------------------------------------------------- duel odds --
	var strong := _agent("raider", "t_strong", 35, 4)
	var weak := _agent("hero", "t_weak", 5, 5)
	var mid := _agent("raider", "t_mid", 18, 6)
	var mid2 := _agent("raider", "t_mid2", 18, 7)
	var foe := _agent("raider", "t_foe", 18, 8)
	var p1 := PkRules.win_p([PkRules.agent_stats(strong)], [PkRules.agent_stats(weak)])
	var pg1 := PkRules.win_p([PkRules.agent_stats(mid)], [PkRules.agent_stats(foe)])
	var pg2 := PkRules.win_p([PkRules.agent_stats(mid), PkRules.agent_stats(mid2)], [PkRules.agent_stats(foe)])
	ok(p1 > 0.95 and pg2 > pg1 + 0.15, "duel odds use the combat formulas: cb35 vs cb5 %.2f; ganging up 1v1 %.2f -> 2v1 %.2f" % [p1, pg1, pg2])
	# ------------------------------------------ abstract resolve -----
	strong.pos = spot
	weak.pos = spot2
	strong.coins = 1000
	weak.coins = 2000
	weak.gear.clear()
	for s in ["head", "body"]:
		weak.gear[s] = {"id": AdvBrain.cfg()["tier_sets"]["iron"][s], "dur": 100}
	weak.stash_add("cooked_carp", 4)
	var total0 := strong.coins + weak.coins
	var weak_id := weak.id
	var weak_name := weak.name
	var strong0 := strong.coins
	AdvBrain.estates.clear()
	var res := {}
	var tries := 0
	while tries < 40:
		tries += 1
		weak.rng.seed = 100 + tries
		strong.skull_until = -1
		var before_units := weak.gear.size() + weak.tools.size()
		strong0 = strong.coins
		res = AdvBrain.resolve([strong], weak, T + tries)
		if res["result"] == "gang_won":
			ok(int(res["kept"].size()) == 3 and before_units >= 1 and strong.skull_until == T + tries + PkRules.skull_ticks(),
				"abstract raid: the raider wins, is skulled for %d ticks; the victim keeps %d items" % [PkRules.skull_ticks(), res["kept"].size()])
			break
		weak.hp = float(AIBrain.agent_max_hp(weak))
	ok(res.get("result", "") == "gang_won", "raider beats a much weaker victim within 40 tries (%d)" % tries)
	var carried := mini(2000, int(PkRules.ai_cfg().get("carry_coins", 40)) + int(2000 * float(PkRules.ai_cfg().get("carry_coin_share", 0.05))))
	var looted_c := strong.coins - strong0
	ok(looted_c == carried - int(ceil(carried * PkRules.coin_fee())),
		"the killer gets the carried coin minus the 10%% healer fee (%d of %d)" % [looted_c, carried])
	# --- 0.3.1 new players: the loser quit; a new level-1 player has the slot
	ok(weak.id != weak_id and weak.id.begins_with(weak_id.split("~")[0] + "~") and weak.name != weak_name and weak.gen == 2 and weak.tint != "",
		"killed in the Scorch, the AI quits: a new player takes the slot (%s '%s' -> %s '%s', own tint %s)" % [weak_id, weak_name, weak.id, weak.name, weak.tint])
	var lv1 := true
	var fresh := Skills.new()
	for sk in fresh.xp.keys():
		lv1 = lv1 and weak.skills.level(sk) == fresh.level(sk)
	ok(lv1 and weak.coins == int(PkRules.ai_cfg().get("starter_coins", 25)) and weak.tools.has("melee") and weak.tools.has("forestry") and weak.gear.is_empty() and AdvBrain.is_adv(weak),
		"the new player starts like you did: level-1 skills, starter kit, %d marks; still an adventurer-class persona (%s)" % [weak.coins, weak.persona_id()])
	ok(weak.pos == weak.home and weak.skull_until == -1 and weak.hp == float(AIBrain.agent_max_hp(weak)) and int(weak.stats.get("pk_deaths", 0)) == 0,
		"the new player starts at its home, full HP, unskulled, with a clean record")
	var est: Dictionary = {}
	for e in AdvBrain.estates:
		if str(e["id"]) == "estate:" + weak_id:
			est = e
	ok(not est.is_empty() and int(est["units"]) >= 3, "the old character's bank and kept items go to an estate sale (%s units: %s)" % [est.get("units", 0), str(est.get("left", {})).substr(0, 80)])
	# estate sale: listed on the Exchange; proceeds are a sink
	var em: TownMarket = Market.town(str(est.get("town", "fenhollow")))
	AdvBrain.estate_tick(T + 50)
	var listed_e := em.open_orders_of(str(est.get("id", "")))
	ok(not listed_e.is_empty(), "estate goods are listed on the %s Exchange (%d orders)" % [str(est.get("town", "")), listed_e.size()])
	var shopper := _agent("hero", "t_estate_buyer", 5, 15)
	shopper.coins = 100000
	shopper.town = str(est.get("town", "fenhollow"))
	var o0: Dictionary = listed_e[0] if not listed_e.is_empty() else {}
	var sunk0 := int(AdvBrain.counters.get("estate_coins_sunk", 0))
	if not o0.is_empty():
		AIBrain.place_buy(shopper, str(o0["item"]), 1, int(o0["price"]))
	AdvBrain.estate_tick(T + 150)
	var sunk := int(AdvBrain.counters.get("estate_coins_sunk", 0)) - sunk0
	ok(sunk > 0 and int(em.pending(str(est.get("id", ""))).get("coins", 0)) == 0, "a sale's proceeds leave the game (%d marks sunk)" % sunk)
	# outside the Scorch: no reset
	var calm := _agent("hero", "t_calm", 15, 16)
	var calm_id := calm.id
	var calm_cb := AdvBrain.cb_level(calm)   # 0.3.3: Archery is in the formula
	calm.pos = Vector2i(5, 5)
	AIBrain.on_death(calm, T)
	ok(calm.id == calm_id and AdvBrain.cb_level(calm) == calm_cb, "an AI dying outside the Scorch is the same character afterwards")
	# clean up the estate orders
	for e in AdvBrain.estates:
		var mm: TownMarket = Market.town(str(e["town"]))
		for o in mm.open_orders_of(str(e["id"])):
			mm.cancel_order(int(o["id"]), true)
		mm.collect(str(e["id"]))
	AdvBrain.estates.clear()
	for oid in shopper.my_orders.keys():
		AIBrain.mk(shopper).cancel_order(oid, true)
	AIBrain.mk(shopper).collect(shopper.id)
	# skulled victim keeps nothing
	var vk := _agent("hero", "t_skulled", 10, 9)
	vk.skull_until = T + 5000
	var d := AdvBrain.pk_death(vk, T)
	ok(d["kept"].is_empty() and not d["lost"].is_empty(), "a skulled player keeps nothing (lost %d)" % d["lost"].size())
	var vk2 := _agent("hero", "t_unskulled", 10, 9)
	var d2 := AdvBrain.pk_death(vk2, T)
	var top := []
	for id in d2["kept"] + d2["lost"]:
		top.append(PkRules.unit_value(id))
	top.sort()
	top.reverse()
	var kv := 0
	for id in d2["kept"]:
		kv += PkRules.unit_value(id)
	ok(d2["kept"].size() == 3 and kv == top[0] + top[1] + top[2], "unskulled: the 3 most valuable units are kept (%s)" % str(d2["kept"]))
	# ------------------------------------------------- raid_tick ------
	var rd := _agent("raider", "t_raider", 30, 10)
	rd.activity = {"type": "raid", "spot": [spot.x, spot.y], "arrive": 0, "until": T + 5000}
	rd.pos = spot
	rd.tier = 2
	var vic := _agent("opportunist", "t_vic", 6, 11)
	vic.activity = {"type": "fight", "kind": "goblin", "camp": [spot.x, spot.y], "arrive": 0, "until": T + 5000}
	vic.pos = spot
	vic.tier = 2
	var f0 := int(AdvBrain.counters.get("pk_fights", 0))
	var k := 0
	while k < 60 and int(AdvBrain.counters.get("pk_fights", 0)) == f0:
		AdvBrain.raid_tick(T + 50 * k, [rd, vic])
		k += 1
	ok(int(AdvBrain.counters.get("pk_fights", 0)) > f0, "off-screen raiders find victims in the Scorch (after %d raid ticks)" % k)
	var safe_vic := _agent("hero", "t_safe", 6, 12)
	safe_vic.activity = vic.activity.duplicate()
	safe_vic.pos = Vector2i(0, 0)
	safe_vic.tier = 2
	rd.activity = {"type": "raid", "spot": [spot.x, spot.y], "arrive": 0, "until": T + 5000}
	rd.pos = spot
	var f1 := int(AdvBrain.counters.get("pk_fights", 0))
	for j in 60:
		AdvBrain.raid_tick(T + 50 * j, [rd, safe_vic])
	ok(int(AdvBrain.counters.get("pk_fights", 0)) == f1, "nobody outside the zone is ever raided")
	# raiders fence their loot on the Exchange
	var fence := _agent("raider", "t_fence", 25, 14)
	fence.coins = 100
	AIDirector.records.append(fence)
	PkRules.give_agent(fence, ["bronze_cap", "bronze_greaves", "iron_sword"], 30)
	AIBrain.trade(fence, T)
	var listed := 0
	for oid in fence.my_orders.keys():
		var o: Dictionary = fence.my_orders[oid]
		if not bool(o["buy"]) and str(o["item"]) in ["bronze_cap", "bronze_greaves", "iron_sword"]:
			listed += 1
	ok(listed >= 2 or fence.stash_count("bronze_cap") + fence.stash_count("bronze_greaves") + fence.stash_count("iron_sword") == 0,
		"a raider puts looted gear it doesn't need up for sale on the Exchange (%d sell orders)" % listed)
	for oid in fence.my_orders.keys():
		AIBrain.mk(fence).cancel_order(oid, true)
	fence.my_orders.clear()
	AIDirector.records.erase(fence)
	# churches (world track hook World.nearest_altar): guarded, and used when present
	var pr := _agent("hero", "t_pray", 20, 17)
	pr.skills.xp["prayer"] = GameData.xp_for_level(20)
	pr.prayer["points"] = 1.0
	var had_hook: bool = world.has_method("nearest_altar")
	var used_real := AdvBrain.visit_altar(pr)
	var real_full := Prayer.points(pr.prayer, 20) >= Prayer.max_points(20)
	pr.prayer["points"] = 1.0
	var gs := GDScript.new()
	gs.source_code = "extends RefCounted\nfunc nearest_altar(t: Vector2i):\n\treturn t + Vector2i(3, 2)\n"
	gs.reload()
	var real_world = AdvBrain.world
	AdvBrain.world = gs.new()
	var used_stub := AdvBrain.visit_altar(pr)
	AdvBrain.world = real_world
	ok((used_real == had_hook) and (real_full or not used_real) and used_stub and Prayer.points(pr.prayer, 20) >= Prayer.max_points(20),
		"adventurers / acolytes refill Prayer at a town altar via World.nearest_altar (hook present now: %s)" % had_hook)
	# --------------------------------------------- live PvP rules -----
	var saved_tile := p.tile
	var saved_eq := p.equipment.duplicate()
	var saved_skull := p.skull_until
	var hero := _agent("hero", "t_live", 12, 13)
	var v := _view(hero, world, Vector2i(0, 3))
	p.place_at(world.find_free_tile_near(Vector2i(0, 5), 3))
	ok(CombatRules.can_attack(p, v, T) == "You can only attack other players in the Scorch.", "outside the Scorch you can't attack an AI player")
	p.place_at(world.find_free_tile_near(spot, 4))
	v.place_at(world.find_free_tile_near(p.tile + Vector2i(1, 0), 2))
	hero.pos = v.tile
	ok(CombatRules.can_attack(p, v, T) == "" and CombatRules.can_attack(v, p, T) == "", "inside the Scorch anyone may attack anyone")
	p.skull_until = -1
	p.pvp_aggr.clear()
	v.pvp_aggr.clear()
	hero.skull_until = -1
	ok(PkRules.on_pvp_swing(p, v, T) and p.is_skulled(T + 1) and p.skull_until == T + PkRules.skull_ticks(), "the first strike skulls the attacker (%d min)" % int(PkRules.cfg().get("skull_minutes", 10)))
	ok(not PkRules.on_pvp_swing(v, p, T + 2) and not v.is_skulled(T + 3), "hitting back never skulls")
	ok(not PkRules.on_pvp_swing(p, v, T + 4), "further hits in the same fight don't re-skull")
	ok(not p.is_skulled(T + PkRules.skull_ticks() + 1), "the skull wears off after %d ticks" % PkRules.skull_ticks())
	# a real swing through the fight loop
	p.skull_until = -1
	p.pvp_aggr.clear()
	v.pvp_aggr.clear()
	p.action = {}
	p.combat_foe = null
	p.hp = p.max_hp()
	Tick.tick_count = T + 10
	p.attack(v)
	var swung := false
	for i in 12:
		Tick.step()
		if p.is_skulled(Tick.tick_count):
			swung = true
			break
	ok(swung and v.pvp_aggr.has(p.actor_id), "attacking an AI player in the Scorch through the fight loop skulls you")
	p.action = {}
	p.combat_foe = null
	# player death: keep 3
	var tnow := Tick.tick_count + 1
	p.skull_until = -1
	p.inventory.clear()
	p.equipment.clear()
	var pack := ["iron_sword", "bronze_cap", "steel_helm", "iron_hauberk", "cooked_carp", "cooked_carp", "ash_log"]
	for id in pack:
		p.inventory.add(id, 1)
	p.inventory.add(GameData.currency, 200)
	p.equipment["body"] = "dusk_cuirass"
	var all_ids: Array = pack + ["dusk_cuirass"]
	var vals := all_ids.map(func(id): return PkRules.unit_value(id))
	vals.sort()
	vals.reverse()
	p.last_attacker = v
	p.place_at(world.find_free_tile_near(spot, 4))
	var death_tile := p.tile
	p.hp = 0
	p.die(tnow)
	var ld := p.pk_last_death
	var kept_v := 0
	for id in ld.get("kept", []):
		kept_v += PkRules.unit_value(id)
	ok(ld.get("kept", []).size() == 3 and kept_v == vals[0] + vals[1] + vals[2] and p.equipment.get("body", "") == "dusk_cuirass",
		"you die in the Scorch: the 3 most valuable items are kept (%s), the worn one stays worn" % ", ".join(ld.get("kept", [])))
	ok(ld.get("coins", 0) == 180 and ld.get("fee", 0) == 20 and ld.get("lost", []).size() == 5, "everything else + coin minus the 10%% fee drops (%d items, %d marks)" % [ld.get("lost", []).size(), ld.get("coins", 0)])
	var piles := world.ground.piles.filter(func(q): return q["pos"] == death_tile)
	world.ground.now = tnow + 1
	var priv := not piles.is_empty()
	for q in piles:
		priv = priv and q["owner"] == v.actor_id and not world.ground.visible_to(q, "player") and world.ground.visible_to(q, v.actor_id)
	world.ground.now = tnow + int(PkRules.cfg().get("killer_private_ticks", 100))
	var pub := not piles.is_empty()
	for q in piles:
		pub = pub and world.ground.visible_to(q, "player") and world.ground.visible_to(q, "someone_else")
	ok(priv and pub, "the pile is private to the killer for %d ticks, then public (%d stacks)" % [int(PkRules.cfg().get("killer_private_ticks", 100)), piles.size()])
	ok(not PkRules.is_pk(p.tile) and p.hp == p.max_hp(), "you wake in town at full HP")
	world.ground.piles = world.ground.piles.filter(func(q): return q["pos"] != death_tile)
	# skulled: keep nothing
	p.inventory.clear()
	p.equipment.clear()
	p.inventory.add("iron_sword", 1)
	p.inventory.add("steel_helm", 1)
	p.place_at(world.find_free_tile_near(spot, 4))
	death_tile = p.tile
	p.skull_until = tnow + 5000
	p.die(tnow + 2)
	ok(p.pk_last_death.get("kept", ["x"]).is_empty() and p.pk_last_death.get("lost", []).size() == 2 and p.inventory.count("iron_sword") == 0,
		"die skulled: you keep nothing")
	world.ground.piles = world.ground.piles.filter(func(q): return q["pos"] != death_tile)
	# AI death on screen
	p.skull_until = -1
	v.place_at(world.find_free_tile_near(spot, 4))
	hero.pos = v.tile
	hero.gear.clear()
	for s in ["head", "body", "legs", "shield"]:
		hero.gear[s] = {"id": AdvBrain.cfg()["tier_sets"]["iron"][s], "dur": 100}
	v.sync_from_agent()
	v._refresh_gear_visual()
	var layers := v.gear_layer_ids()
	ok(layers.size() >= 4 and "gear_head_2" in layers and "gear_body_2" in layers, "worn gear shows on the AI sprite (%s)" % ", ".join(layers))
	# 0.3.1 player visible gear: same layers on your own sprite, swappable per item
	var eq0: Dictionary = p.equipment.duplicate()
	var pick := {"alder_buckler": "gear_shield_buckler_1", "iron_kite_shield": "gear_shield_kite_2", "steel_heater_shield": "gear_shield_heater_3",
		"dusk_tower_shield": "gear_shield_tower_4", "ash_shortbow": "gear_weapon_bow_1", "iron_warhammer": "gear_weapon_warhammer_2",
		"steel_dagger": "gear_weapon_dagger_3", "dusk_sword": "gear_weapon_sword_4", "bronze_cap": "gear_head_1", "steel_legplates": "gear_legs_3"}
	var bad := []
	for id in pick.keys():
		var got := Actor.gear_sprite_for(id, str(GameData.item(id)["gear"]["slot"]))
		if got != pick[id] and not (pick[id] == "gear_weapon_sword_4" and got == "gear_weapon_4"):
			bad.append("%s->%s" % [id, got])
	ok(bad.is_empty(), "gear art per type and tier: shields buckler/kite/heater/tower, bows, weapon classes %s" % str(bad))
	p.equipment = {}
	p._refresh_gear_visual()
	var steps := []
	var seq := [["head", "iron_helm", "gear_head_2"], ["body", "steel_brigandine", "gear_body_3"], ["legs", "dusk_tassets", "gear_legs_4"],
		["shield", "alder_buckler", "gear_shield_buckler_1"], ["weapon", "bronze_battleaxe", "gear_weapon_battleaxe_1"]]
	for st in seq:
		p.equipment[st[0]] = st[1]
		p._refresh_gear_visual()
		steps.append(st[2] in p.gear_layer_ids())
	ok(not false in steps and p.gear_layer_ids() == ["gear_legs_4", "gear_body_3", "gear_head_2", "gear_shield_buckler_1", "gear_weapon_battleaxe_1"],
		"player: equipping each slot draws it, legs < body < head < shield < weapon (%s)" % ", ".join(p.gear_layer_ids()))
	p.facing.dir = "down"   # 0.3.9.4: the order is per facing; facing the camera all 5 sit over the body
	p._sprite.flip_h = false
	p._layer_key = ""
	p._refresh_gear_visual()
	var body_i: int = p._sprite.get_index()
	ok(p._layers["legs"].get_index() == body_i + 1 and p._layers["weapon"].get_index() == body_i + 5, "player gear layers sit right above the body sprite")
	p._sprite.frame = 2
	p._sprite.flip_h = true
	p._sync_gear_layers()
	var synced := true
	for sl in p._layers.keys():
		synced = synced and p._layers[sl].frame == 2 and p._layers[sl].flip_h
	ok(synced, "player gear layers follow the walk frame and facing")
	steps.clear()
	for st in seq:
		p.equipment.erase(st[0])
		p._refresh_gear_visual()
		steps.append(not st[2] in p.gear_layer_ids())
	ok(not false in steps and p.gear_layer_ids().is_empty(), "player: unequipping each slot removes it")
	GameData.sprites["actors"]["gear_item_iron_helm"] = GameData.sprite_def("actors", "gear_head_4")
	ok(Actor.gear_sprite_for("iron_helm", "head") == "gear_item_iron_helm", "per-item art override (sprites.json gear_item_<id>)")
	GameData.sprites["actors"].erase("gear_item_iron_helm")
	p.equipment = eq0
	p._sprite.flip_h = false
	p._refresh_gear_visual()
	var units0 := hero.gear.size() + hero.tools.size()
	var dt := v.tile
	v.last_attacker = p
	var hid0 := hero.id
	var kills0 := int(PkRules.pk_log_total.get("kills", 0))
	v.die(tnow + 5)
	var lp := v.last_pk_drop
	var apiles := world.ground.piles.filter(func(q): return q["pos"] == dt)
	ok(lp.get("kept", []).size() == 3 and units0 > 3 and not apiles.is_empty() and apiles[0]["owner"] == p.actor_id and int(PkRules.pk_log_total.get("kills", 0)) == kills0 + 1,
		"an AI killed by you in the Scorch keeps 3, drops the rest for you (%d stacks)" % apiles.size())
	ok(not PkRules.is_pk(v.tile) and hero.hp == float(AIBrain.agent_max_hp(hero)) and hero.id != hid0 and v.actor_id == hero.id and v.display_name == hero.name
		and v.tint == Color(hero.tint) and v.inventory.count("iron_helm") == 0, "on screen too: a new player (%s) appears in town in its place" % hero.name)
	for e in AdvBrain.estates:
		var mm2: TownMarket = Market.town(str(e["town"]))
		mm2.collect(str(e["id"]))
	AdvBrain.estates.clear()
	world.ground.piles = world.ground.piles.filter(func(q): return q["pos"] != dt)
	# --------------------------------------------- save round trip ----
	hero.skull_until = T + 777
	hero.adv["target"] = "goblin"
	var h2 := AIAgent.new()
	h2.from_save(JSON.parse_string(JSON.stringify(hero.to_save())))
	AdvBrain.commissions.clear()
	AdvBrain.post_commission(buyer, "steel_heater_shield", 900, T)
	AdvBrain.estates = [{"id": "estate:t_old", "town": "fenhollow", "left": {"iron_helm": 2}, "until": T + 99, "coins": 5, "sold": 1, "units": 3}]
	var rt0 := AdvBrain.resets_total
	var cs: Dictionary = JSON.parse_string(JSON.stringify(AdvBrain.to_save()))
	AdvBrain.commissions.clear()
	AdvBrain.estates.clear()
	AdvBrain.resets_total = 0
	AdvBrain.from_save(cs)
	ok(AdvBrain.estates.size() == 1 and int(AdvBrain.estates[0]["left"]["iron_helm"]) == 2 and int(AdvBrain.estates[0]["until"]) == T + 99 and AdvBrain.resets_total == rt0,
		"estate sales in progress and the reset count survive a save round trip")
	AdvBrain.estates.clear()
	ok(h2.skull_until == T + 777 and str(h2.adv.get("target", "")) == "goblin" and AdvBrain.is_adv(h2) and AdvBrain.commissions.size() == 1 and int(AdvBrain.commissions[0]["price"]) == 900
		and h2.id == hero.id and h2.tint == hero.tint and h2.gen == hero.gen and h2.name == hero.name,
		"skull, adventurer state, a new player's identity (id, name, tint, generation) and commissions survive a save round trip")
	AdvBrain.commissions.clear()
	p.skull_until = -1
	ok(PkRules.zone_at(Vector2i(0, 0)).is_empty() and not p.is_skulled(Tick.tick_count), "HUD sees no PK row in town for an unskulled player")
	# --------------------------------------------- cleanup ------------
	_drop_view(v)
	AIDirector.records.erase(buyer)
	p.inventory.clear()
	p.equipment = saved_eq
	p.skull_until = saved_skull
	p.last_attacker = null
	p.pvp_aggr.clear()
	p.place_at(saved_tile if not PkRules.is_pk(saved_tile) else world.gen.town_spawn("fenhollow"))
	Tick.tick_count = T + 20000
	return out
