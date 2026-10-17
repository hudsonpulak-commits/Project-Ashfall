extends RefCounted
## Headless economy soak test:
##   godot --headless --path . -- --fresh --soak=7 [--soak-out=DIR] [--no-traders]
## Runs N game days (2400 ticks each) with the full AI population across the
## three town markets and records one row per day: global + per-town price
## index, money supply, faucets/sinks, volume, per-town reference prices of
## key items, cross-town price spreads, trader trips. Writes soak.csv,
## soak_towns.csv and soak.json; exit code = number of failed criteria.
## tools/soak_chart.py renders the chart (and compares with a --no-traders run).

const INDEX_TOLERANCE := 0.15
const MONEY_TOLERANCE := 0.30
const REF_BOUNDS := [0.5, 2.0]
const KEY_ITEMS := ["copper_ore", "tin_ore", "iron_ore", "coal", "bronze_bar", "steel_bar", "raw_eel", "cooked_carp", "alder_log", "ash_log", "plank", "iron_bar", "iron_helm", "iron_hauberk", "iron_mace"]
const MAX_SPREAD := 2.0          # dearest/cheapest town must stay below this (bounded; day-0 design spread is ~1.55)
const MIN_MEAN_SPREAD := 1.02    # ...but gaps should not vanish entirely


static func _order_detail(a: AIAgent) -> Array:
	var out := []
	for id in a.my_orders.keys():
		var mine: Dictionary = a.my_orders[id]
		var tm := Market.town(str(mine.get("town", a.town)))
		var o: Dictionary = tm.orders.get(id, {})
		out.append({"id": id, "mine": mine, "live": not o.is_empty(), "qty": o.get("qty", 0), "price": o.get("price", 0), "tick": o.get("tick", 0)})
	return out


static func spread(item: String) -> float:
	var lo := INF
	var hi := 0.0
	for id in Market.town_ids:
		var p := float(Market.town(id).reference_price(item))
		lo = minf(lo, p)
		hi = maxf(hi, p)
	return hi / maxf(1.0, lo)


static func _row(main, day: int, trips_before: int) -> Dictionary:
	var last: Dictionary = Market.econ_history[-1] if (day > 0 and not Market.econ_history.is_empty()) else {}
	var vol := 0
	var town_vol := {}
	for tid in Market.town_ids:
		var tv := 0
		var tm := Market.town(tid)
		for id in tm.history.keys():
			var h: Array = tm.history[id]
			if day > 0 and not h.is_empty():
				tv += int(h[-1]["vol"])
		town_vol[tid] = tv
		vol += tv
	var acts := {}
	for a in AIDirector.records:
		var k: String = a.activity.get("type", "none")
		acts[k] = int(acts.get(k, 0)) + 1
	var towns := {}
	for tid in Market.town_ids:
		var refs := {}
		for id in KEY_ITEMS:
			refs[id] = Market.town(tid).reference_price(id)
		towns[tid] = {"index": snappedf(Market.monitor.town_index(Market.town(tid)), 0.0001), "volume": town_vol[tid], "refs": refs,
			"open_orders": Market.town(tid).orders.size()}
	var basket := {}
	for id in EconomyMonitor.BASKET:
		var per := []
		for tid in Market.town_ids:
			per.append(Market.town(tid).reference_price(id))
		basket[id] = per
	var spreads := {}
	var mean := 0.0
	for id in KEY_ITEMS:
		spreads[id] = snappedf(spread(id), 0.001)
		mean += spread(id)
	var traveling := 0
	for a in AIDirector.records:
		if a.trip.has("to"):
			traveling += 1
	return {
		"day": day, "tick": Tick.tick_count,
		"index": snappedf(Market.monitor.price_index(Market), 0.0001),
		"money": main.money_supply(), "ai_coins": AIDirector.money_supply(), "escrow": Market.coins_in_market(),
		"faucet": int(last.get("faucet", 0)), "sink": int(last.get("sink", 0)), "tax": int(last.get("tax", 0)),
		"global_faucet": int(last.get("global_faucet", 0)), "global_sink": int(last.get("global_sink", 0)),
		"npc_bought": int(last.get("npc_bought", 0)), "npc_sold": int(last.get("npc_sold", 0)),
		"volume": vol, "npc_buy_factor": snappedf(Market.npc_buy_factor, 0.001), "gather_mult": snappedf(Market.gather_mult, 0.001),
		"bounty_mult": snappedf(Market.bounty_mult, 0.001), "stipend_mult": snappedf(Market.stipend_mult, 0.001), "store_purse": int(Market.store_purse),
		"mean_spread": snappedf(mean / KEY_ITEMS.size(), 0.0001), "spreads": spreads, "basket": basket, "floor_boosts": _boosts(),
		"trips": AIDirector.trip_log.size() - trips_before, "traveling": traveling,
		"tiers": AIDirector.tier_counts.duplicate(), "activities": acts, "towns": towns,
		"monitor_action": Market.monitor.days[-1]["action"] if (day > 0 and not Market.monitor.days.is_empty()) else "",
	}


## 0.3.0: a simulated player shop in every town, restocked each game day to
## full stands at the current local reference price x mult (a diligent player).
const PSHOP_STOCK := ["cooked_carp", "ash_log", "coal", "bronze_bar", "iron_ore", "plank", "iron_bar", "bronze_hatchet"]


static func _pshop_restock(main, mult: float) -> void:
	for tid in Market.town_ids:
		var ps: PlayerShop = Market.player_shop(tid)
		ps.owned = true
		ps.owner_name = "Soak"
		ps.auto_bank = false
		for i in mini(PSHOP_STOCK.size(), ps.slots.size()):
			var it: String = PSHOP_STOCK[i]
			var price := maxi(1, int(round(Market.town(tid).reference_price(it) * mult)))
			ps.slots[i] = {"item": it, "qty": PlayerShop.cap_for(it), "price": price, "dur": -1}
		if ps.till > 0 and main and main.player:   # the player collects: coins stay in the money supply
			main.player.inventory.add(GameData.currency, ps.till)
		ps.till = 0
		PlayerShop.version += 1


static func run(main, days: int, out_dir: String, traders: bool = true, pshop_mult: float = -1.0) -> int:
	Tick.running = false
	if pshop_mult > 0.0:
		_pshop_restock(main, pshop_mult)
	var ps_units := [0]
	var ps_days: Array = []
	var ps_cb := func(d: int) -> void:
		if pshop_mult <= 0.0:
			return
		var u := 0
		var rev := 0
		var per := {}
		for tid in Market.town_ids:
			var ps: PlayerShop = Market.player_shop(tid)
			u += int(ps.stats["units"])
			rev += int(ps.stats["revenue"])
			per[tid] = int(ps.stats["units"])
		ps_days.append({"day": d, "units_total": u, "revenue_total": rev, "per_town": per})
		_pshop_restock(main, pshop_mult)
	Market.day_closed.connect(ps_cb)
	AIDirector.traders_enabled = traders
	DirAccess.make_dir_recursive_absolute(out_dir)
	var rows: Array = []
	var trip_count := [AIDirector.trips_total]
	rows.append(_row(main, 0, 0))
	var SA = preload("res://src/tests/soak_adv.gd")   # 0.3.1 adventurers / PK
	SA.start()
	var cb := func(d: int) -> void:
		SA.rows.append(SA.day_row(d))
		var r := _row(main, d, 0)
		r["trips"] = AIDirector.trips_total - trip_count[0]
		trip_count[0] = AIDirector.trips_total
		rows.append(r)
	Market.day_closed.connect(cb)
	var t0 := Time.get_ticks_msec()
	var total := days * Market.TICKS_PER_GAME_DAY
	var trips0 := AIDirector.trips_total
	for i in total:
		Tick.step()
		if i % 2400 == 2399:
			print("  soak day %d/%d done (%.1f s)" % [int(i / 2400.0) + 1, days, (Time.get_ticks_msec() - t0) / 1000.0])
	Market.day_closed.disconnect(cb)
	Market.day_closed.disconnect(ps_cb)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var all_trips := AIDirector.trips_total - trips0
	# ---- CSV: global
	var cols := ["day", "tick", "index", "money", "ai_coins", "escrow", "faucet", "sink", "global_faucet", "global_sink", "tax", "npc_bought", "npc_sold",
		"volume", "mean_spread", "trips", "traveling", "npc_buy_factor", "gather_mult", "bounty_mult", "stipend_mult", "store_purse", "monitor_action"]
	var lines := [",".join(cols)]
	for r in rows:
		var vals := []
		for c in cols:
			vals.append(str(r[c]))
		lines.append(",".join(vals))
	var f := FileAccess.open(out_dir.path_join("soak.csv"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	# ---- CSV: per town key prices
	var tl := ["day,town,index,volume," + ",".join(KEY_ITEMS)]
	for r in rows:
		for tid in Market.town_ids:
			var t: Dictionary = r["towns"][tid]
			var vals := [str(r["day"]), tid, str(t["index"]), str(t["volume"])]
			for id in KEY_ITEMS:
				vals.append(str(t["refs"][id]))
			tl.append(",".join(vals))
	f = FileAccess.open(out_dir.path_join("soak_towns.csv"), FileAccess.WRITE)
	f.store_string("\n".join(tl) + "\n")
	f.close()
	# ---- criteria
	var report := []
	var worst := 0.0
	for r in rows:
		worst = maxf(worst, absf(float(r["index"]) - 1.0))
	report.append(["price index within 1 +- %.0f%% every day (worst %.1f%%)" % [INDEX_TOLERANCE * 100, worst * 100], worst <= INDEX_TOLERANCE])
	var m0 := float(rows[0]["money"])
	var m1 := float(rows[-1]["money"])
	var dm := m1 / maxf(1.0, m0) - 1.0
	report.append(["money supply change within +- %.0f%% (%d -> %d, %+.1f%%)" % [MONEY_TOLERANCE * 100, int(m0), int(m1), dm * 100], absf(dm) <= MONEY_TOLERANCE])
	var oob := []
	for id in EconomyMonitor.BASKET:
		var rr := Market.avg_reference(id) / GameData.item_value(id)
		if rr < REF_BOUNDS[0] or rr > REF_BOUNDS[1]:
			oob.append("%s %.2fx" % [id, rr])
	report.append(["every basket price (town average) within %.1fx-%.1fx base %s" % [REF_BOUNDS[0], REF_BOUNDS[1], str(oob)], oob.is_empty()])
	var dead := 0
	for r in rows.slice(1):
		if int(r["volume"]) == 0:
			dead += 1
	report.append(["the Exchanges trade every day (%d days without volume)" % dead, dead == 0])
	var neg := 0
	for a in AIDirector.records:
		if a.coins < 0:
			neg += 1
		for k in a.stash.keys():
			if int(a.stash[k]) < 0:
				neg += 1
	report.append(["no negative coin/stash balances (%d)" % neg, neg == 0])
	var max_sp := 0.0
	var worst_item := ""
	for id in KEY_ITEMS:
		if spread(id) > max_sp:
			max_sp = spread(id)
			worst_item = id
	var mean_sp := float(rows[-1]["mean_spread"])
	if traders:
		report.append(["travelling traders made trips (%d)" % all_trips, all_trips >= 10])
		report.append(["cross-town price gaps stay bounded: max spread %.2fx (%s) <= %.1fx" % [max_sp, worst_item, MAX_SPREAD], max_sp <= MAX_SPREAD])
		report.append(["...but persist: mean spread %.3fx >= %.2fx" % [mean_sp, MIN_MEAN_SPREAD], mean_sp >= MIN_MEAN_SPREAD])
	else:
		report.append(["control run without traders: max spread %.2fx (%s), mean %.3fx" % [max_sp, worst_item, mean_sp], true])
	var pshop_summary := {}
	if pshop_mult > 0.0:
		var u_end := 0
		var r_end := 0
		var by_item := {}
		for tid in Market.town_ids:
			var ps: PlayerShop = Market.player_shop(tid)
			u_end += int(ps.stats["units"])
			r_end += int(ps.stats["revenue"])
			for e in ps.log:
				by_item[e["item"]] = int(by_item.get(e["item"], 0)) + int(e["qty"])
		pshop_summary = {"mult": pshop_mult, "units": u_end, "revenue": r_end, "units_per_day": float(u_end) / maxf(1.0, days),
			"units_per_day_per_town": float(u_end) / maxf(1.0, days) / Market.town_ids.size(), "revenue_per_day": float(r_end) / maxf(1.0, days),
			"days": ps_days, "recent_log_by_item": by_item}
		report.append(["player shops at %.2fx ref sell %.1f units/day across %d towns (%.1f marks/day after tax)" % [pshop_mult, pshop_summary["units_per_day"], Market.town_ids.size(), pshop_summary["revenue_per_day"]], u_end > 0])
	# 0.3.1 village farms: wheat harvested, flour + bread made, cows killed, beef cooked
	var farm := {}
	var farm_who := {}
	for a in AIDirector.records:
		for k in ["g:wheat", "m:flour", "m:bread", "k:cow", "m:cooked_beef", "k:giant_rat", "k:goblin"]:
			if a.stats.has(k):
				farm[k] = int(farm.get(k, 0)) + int(a.stats[k])
				var who: String = "%s %s" % [a.persona_id(), k]
				farm_who[who] = int(farm_who.get(who, 0)) + int(a.stats[k])
	print("FARM SUPPLY %s" % str(farm))
	print("FARM BY PERSONA %s" % str(farm_who))
	report.append(["village farms work: wheat %d, flour %d, bread %d harvested/made" % [int(farm.get("g:wheat", 0)), int(farm.get("m:flour", 0)), int(farm.get("m:bread", 0))],
		int(farm.get("g:wheat", 0)) > 0 and int(farm.get("m:flour", 0)) > 0 and int(farm.get("m:bread", 0)) > 0])
	report.append(["pasture cows get hunted: %d cows killed (rats %d, goblins %d), %d beef cooked" % [int(farm.get("k:cow", 0)), int(farm.get("k:giant_rat", 0)), int(farm.get("k:goblin", 0)), int(farm.get("m:cooked_beef", 0))],
		int(farm.get("k:cow", 0)) > 0])
	report.append_array(SA.report(days))
	report.append(["simulation speed: %d ticks in %.1f s (%.0fx real time)" % [total, secs, total * Tick.TICK_SECONDS / maxf(0.001, secs)], true])
	var fails := 0
	print("SOAK %d days, %d agents, %d towns, traders %s" % [days, AIDirector.records.size(), Market.town_ids.size(), "on" if traders else "OFF"])
	var crit := []
	for it in report:
		print("  %s %s" % ["ok  " if it[1] else "FAIL", it[0]])
		crit.append({"criterion": it[0], "pass": it[1]})
		if not it[1]:
			fails += 1
	var traders_state := []
	for a in AIDirector.records:
		if str(a.persona.get("id", "")) == "trader":
			var cargo := 0
			for k in a.stash.keys():
				cargo += int(a.stash[k])
			var boxes := {}
			var escrow := {}
			for tid in Market.town_ids:
				boxes[tid] = Market.town(tid).pending(a.id)
				var e := 0
				for o in Market.town(tid).orders.values():
					if o["trader"] == a.id:
						e += int(o["qty"]) * (int(o["price"]) if o["buy"] else 0)
				escrow[tid] = e
			traders_state.append({"id": a.id, "name": a.name, "town": a.town, "coins": a.coins, "cargo": cargo, "stash": a.stash,
				"boxes": boxes, "buy_escrow": escrow, "memo": a.memo,
				"trip": a.trip, "orders": a.my_orders.size(), "order_detail": _order_detail(a), "next_trade": a.next_trade_tick, "stats": a.stats, "activity": a.activity})
	var personas := {}
	for a in AIDirector.records:
		var pid: String = a.persona_id()
		if not personas.has(pid):
			personas[pid] = {"n": 0, "coins": 0, "stash": {}, "made": 0, "gathered": 0, "levels": {}, "orders": 0}
		var ps: Dictionary = personas[pid]
		ps["n"] += 1
		ps["coins"] += a.coins
		ps["orders"] += a.my_orders.size()
		ps["made"] += int(a.stats.get("made", 0))
		ps["gathered"] += int(a.stats.get("gathered", 0))
		for k in a.stash.keys():
			ps["stash"][k] = int(ps["stash"].get(k, 0)) + int(a.stash[k])
		for sk in a.focus():
			ps["levels"][sk] = str(ps["levels"].get(sk, "")) + "%d," % a.skills.level(sk)
	# 0.3.1 ore supply per home town (mines moved out of town: who still digs what)
	var ore_supply := {}
	for tid in Market.town_ids:
		ore_supply[tid] = {}
	for a in AIDirector.records:
		var ht: String = a.home_town
		if not ore_supply.has(ht):
			ore_supply[ht] = {}
		for k in a.stats.keys():
			var ks := str(k)
			if ks.begins_with("g:") and (ks.ends_with("_ore") or ks == "g:coal"):
				var item := ks.substr(2)
				ore_supply[ht][item] = int(ore_supply[ht].get(item, 0)) + int(a.stats[k])
	var ore_who := {}   # "persona@town" -> {ore: n}: which agents feed each town
	for a in AIDirector.records:
		var key: String = "%s@%s" % [a.persona_id(), a.home_town]
		for k in a.stats.keys():
			var ks := str(k)
			if ks.begins_with("g:") and (ks.ends_with("_ore") or ks == "g:coal"):
				if not ore_who.has(key):
					ore_who[key] = {}
				ore_who[key][ks.substr(2)] = int(ore_who[key].get(ks.substr(2), 0)) + int(a.stats[k])
	print("ORE BY PERSONA@TOWN %s" % str(ore_who))
	for tid in ore_supply.keys():
		var parts: Array = []
		for item in ["copper_ore", "tin_ore", "iron_ore", "coal"]:
			parts.append("%s %d (%.0f/day)" % [item, int(ore_supply[tid].get(item, 0)), float(ore_supply[tid].get(item, 0)) / maxf(1.0, days)])
		print("ORE SUPPLY %s: %s" % [tid, ", ".join(parts)])
	var pits_ok := true
	for tid in Market.town_ids:
		for ore in ["copper_ore", "tin_ore", "coal"]:
			pits_ok = pits_ok and int(ore_supply.get(tid, {}).get(ore, 0)) > 0
	print("  %s every town's AIs mine copper, tin AND coal (regional supply: no town at 0)" % ("ok  " if pits_ok else "FAIL"))
	crit.append({"criterion": "every town mines copper, tin and coal", "pass": pits_ok})
	if not pits_ok:
		fails += 1
	var js := FileAccess.open(out_dir.path_join("soak.json"), FileAccess.WRITE)
	js.store_string(JSON.stringify({"days": days, "agents": AIDirector.records.size(), "traders": traders, "towns": Market.town_ids,
		"key_items": KEY_ITEMS, "rows": rows, "criteria": crit, "seconds": secs, "notices": Market.notices,
		"trader_state": traders_state, "personas": personas, "ore_supply": ore_supply, "ore_by_persona_town": ore_who, "player_shop": pshop_summary, "trips": AIDirector.trip_log.slice(maxi(0, AIDirector.trip_log.size() - 60)), "adventurers": SA.summary()}, " "))
	js.close()
	print("SOAK %s -> %s" % ["PASS" if fails == 0 else "FAIL", ProjectSettings.globalize_path(out_dir)])
	return fails


static func _boosts() -> Dictionary:
	var out := {}
	for tid in Market.town_ids:
		out[tid] = Market.town(tid).floor_boost.duplicate()
	return out
