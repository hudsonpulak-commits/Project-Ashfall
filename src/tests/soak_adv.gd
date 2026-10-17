extends RefCounted
## 0.3.1 soak add-on: adventurer progression curve, raider kill rate and PK
## coin flows. soak.gd calls day_row() at each day close and report() at the
## end (kept apart from soak.gd to keep merges small).

static var rows: Array = []
const TIER_ITEMS := ["bronze_sword", "iron_sword", "steel_sword", "bronze_cap", "iron_helm", "steel_helm", "iron_hauberk", "steel_brigandine", "dusk_helm"]
static var _pk0: Dictionary = {}
static var _c0: Dictionary = {}
static var _money0 := 0


static func start() -> void:
	rows = []
	_pk0 = PkRules.pk_log_total.duplicate()
	_c0 = AdvBrain.counters.duplicate()
	rows.append(day_row(0))


static func _d(now: Dictionary, base: Dictionary, k: String) -> int:
	return int(now.get(k, 0)) - int(base.get(k, 0))


static func day_row(day: int) -> Dictionary:
	var by := {}
	for a in AIDirector.records:
		if not AdvBrain.is_adv(a):
			continue
		var s := AdvBrain.sub(a)
		if not by.has(s):
			by[s] = {"n": 0, "cb": 0.0, "prayer": 0.0, "tier": 0.0, "tier_max": 0, "coins": 0, "kills": 0, "pk_kills": 0, "pk_deaths": 0, "pk_loot": 0}
		var b: Dictionary = by[s]
		var gt := AdvBrain.gear_tier(a)
		b["n"] += 1
		b["cb"] += AdvBrain.cb_level(a)
		b["prayer"] += a.skills.level("prayer")
		b["tier"] += float(gt["mean"])
		b["tier_max"] = maxi(int(b["tier_max"]), int(gt["max"]))
		b["coins"] += a.coins
		b["kills"] += int(a.stats.get("kills", 0))
		b["pk_kills"] += int(a.stats.get("pk_kills", 0))
		b["pk_deaths"] += int(a.stats.get("pk_deaths", 0))
		b["pk_loot"] += int(a.stats.get("pk_loot", 0))
	var per := {}
	for a in AIDirector.records:
		if AdvBrain.is_adv(a):
			per[a.id] = [AdvBrain.cb_level(a), a.coins, AIBrain.food_count(a), int(a.stats.get("deaths", 0))]
	for s in by.keys():
		var b: Dictionary = by[s]
		for k in ["cb", "prayer", "tier"]:
			b[k] = snappedf(float(b[k]) / maxf(1.0, b["n"]), 0.01)
	# 0.3.1 new players: level distribution of every AI, gear-tier supply and prices
	var cb_hist := {"1-5": 0, "6-10": 0, "11-15": 0, "16-20": 0, "21-30": 0, "31+": 0}
	var tot_lv := []
	for a in AIDirector.records:
		var cb := AdvBrain.cb_level(a)
		var key := "1-5" if cb <= 5 else ("6-10" if cb <= 10 else ("11-15" if cb <= 15 else ("16-20" if cb <= 20 else ("21-30" if cb <= 30 else "31+"))))
		cb_hist[key] += 1
		tot_lv.append(a.skills.total_level())
	tot_lv.sort()
	var supply := {}
	for a in AIDirector.records:
		var held := []
		for sk in a.tools.keys():
			held.append(a.tools[sk]["id"])
		for sl in a.gear.keys():
			held.append(a.gear[sl]["id"])
		for k in a.stash.keys():
			for i in mini(int(a.stash[k]), 50):
				held.append(k)
		for id in held:
			var tr := int(GameData.item(id).get("gear", {}).get("tier", 0))
			if tr > 0:
				supply[str(tr)] = int(supply.get(str(tr), 0)) + 1
	var listed := {}
	for tid in Market.town_ids:
		for o in Market.town(tid).orders.values():
			if not bool(o["buy"]):
				var tr2 := int(GameData.item(o["item"]).get("gear", {}).get("tier", 0))
				if tr2 > 0:
					listed[str(tr2)] = int(listed.get(str(tr2), 0)) + int(o["qty"]) - int(o["filled"])
	var orig := []
	for a in AIDirector.records:
		if AdvBrain.is_adv(a) and AdvBrain.sub(a) == "hero" and a.gen == 1:
			orig.append(float(AdvBrain.gear_tier(a)["mean"]))
	var prices := {}
	for id in TIER_ITEMS:
		var sum := 0.0
		for tid in Market.town_ids:
			sum += Market.town(tid).reference_price(id)
		prices[id] = snappedf(sum / Market.town_ids.size() / maxf(1.0, GameData.item_value(id)), 0.01)
	var c := AdvBrain.counters
	var pk := PkRules.pk_log_total
	return {"day": day, "subs": by, "cb_hist": cb_hist, "total_level_median": tot_lv[tot_lv.size() / 2] if not tot_lv.is_empty() else 0,
		"total_level_p10": tot_lv[tot_lv.size() / 10] if not tot_lv.is_empty() else 0, "total_level_p90": tot_lv[tot_lv.size() * 9 / 10] if not tot_lv.is_empty() else 0,
		"resets": AdvBrain.resets_total, "estates_open": AdvBrain.estates.size(), "estate_coins_sunk": int(c.get("estate_coins_sunk", 0)),
		"reset_coins_sunk": int(c.get("reset_coins_sunk", 0)), "gear_supply": supply, "gear_listed": listed, "orig_hero_tier": snappedf(orig.reduce(func(x, y): return x + y, 0.0) / maxf(1.0, orig.size()), 0.01), "orig_heroes": orig.size(), "tier_price_x_base": prices, "population": AIDirector.records.size(), "per": per, "pk_fights": _d(c, _c0, "pk_fights"), "raider_kills": _d(c, _c0, "raider_kills"),
		"raider_deaths": _d(c, _c0, "raider_deaths"), "escapes": _d(c, _c0, "pk_escapes"), "npc_pk_deaths": _d(c, _c0, "pk_npc_deaths"),
		"commissions_posted": _d(c, _c0, "commissions_posted"), "commissions_filled": _d(c, _c0, "commissions_filled"),
		"coin_dropped": _d(pk, _pk0, "coin_dropped"), "coin_fee": _d(pk, _pk0, "coin_fee"), "coin_looted": _d(pk, _pk0, "coin_looted"),
		"items_dropped": _d(pk, _pk0, "items_dropped"), "items_looted": _d(pk, _pk0, "items_looted")}


## [[criterion, pass], ...] and a JSON-able summary.
static func report(days: int) -> Array:
	var r0: Dictionary = rows[0]
	var r1: Dictionary = rows[-1]
	var out := []
	var h0: Dictionary = r0["subs"].get("hero", {})
	var h1: Dictionary = r1["subs"].get("hero", {})
	var curve := []
	for r in rows:
		var h: Dictionary = r["subs"].get("hero", {})
		curve.append("%.1f/%.2f" % [float(h.get("cb", 0)), float(h.get("tier", 0))])
	out.append(["adventurers level up over the run: hero mean cb %.1f -> %.1f, prayer %.1f -> %.1f" % [float(h0.get("cb", 0)), float(h1.get("cb", 0)),
		float(h0.get("prayer", 0)), float(h1.get("prayer", 0))], float(h1.get("cb", 0)) > float(h0.get("cb", 0)) + 1.0])
	out.append(["...and gear up: original heroes' mean gear tier %.2f -> %.2f (%d of them left; all heroes %.2f -> %.2f, max tier %d); curve cb/tier by day %s" % [float(r0["orig_hero_tier"]), float(r1["orig_hero_tier"]),
		int(r1["orig_heroes"]), float(h0.get("tier", 0)), float(h1.get("tier", 0)), int(h1.get("tier_max", 0)), ", ".join(curve)],
		float(r1["orig_hero_tier"]) >= float(r0["orig_hero_tier"]) or int(r1["orig_heroes"]) == 0])
	var kills := int(r1["raider_kills"])
	out.append(["raiders hunt in the Scorch (>= 1 kill per 15 days; prey is rare: opportunists from cb 10, heroes from cb 28): %d fights, %d kills (%.1f/day), %d raider deaths, %d escapes" % [int(r1["pk_fights"]), kills,
		kills / maxf(1.0, days), int(r1["raider_deaths"]), int(r1["escapes"])], kills >= int(days / 15) and kills <= days * 40])   # a rate: short soaks (< 15 days) need none
	var dropped := int(r1["coin_dropped"])
	var fee := int(r1["coin_fee"])
	var looted := int(r1["coin_looted"])
	out.append(["PK creates no coin: %d carried coin dropped, %d fee sunk, %d looted (<= dropped - fee)" % [dropped, fee, looted], looted <= dropped - fee])
	var resets := int(r1["resets"]) - int(r0["resets"])
	out.append(["Scorch deaths reset AI to new level-1 players: %d resets, population %d -> %d, %d marks of old purses + %d of estate proceeds sunk" % [resets,
		int(r0["population"]), int(r1["population"]), int(r1["reset_coins_sunk"]) - int(r0["reset_coins_sunk"]), int(r1["estate_coins_sunk"]) - int(r0["estate_coins_sunk"])],
		int(r0["population"]) == int(r1["population"]) and (resets > 0 or days < 15)])   # resets follow raider kills: judged on runs of 15+ days
	var hist_line := []
	for r in rows:
		if int(r["day"]) % maxi(1, int(days / 6.0)) == 0 or r == r1:
			hist_line.append("d%d %s" % [int(r["day"]), str(r["cb_hist"].values())])
	out.append(["AI level spread stays broad (cb buckets 1-5/6-10/11-15/16-20/21-30/31+): %s; total level p10/median/p90 %d/%d/%d -> %d/%d/%d" % [" | ".join(hist_line),
		int(r0["total_level_p10"]), int(r0["total_level_median"]), int(r0["total_level_p90"]), int(r1["total_level_p10"]), int(r1["total_level_median"]), int(r1["total_level_p90"])],
		int(r1["cb_hist"]["1-5"]) < int(r1["population"])])
	var worst := ""
	var worst_x := 1.0
	var swing := 0.0
	for id in TIER_ITEMS:
		for i in rows.size():
			var x := float(rows[i]["tier_price_x_base"][id])
			if absf(x - 1.0) > absf(worst_x - 1.0):
				worst_x = x
				worst = id
			if i > 0:
				swing = maxf(swing, absf(x / maxf(0.01, float(rows[i - 1]["tier_price_x_base"][id])) - 1.0))
	out.append(["gear tier supply %s -> %s units held by AI (+ listed on the Exchange %s -> %s); tier prices stay within 0.5-2x base (worst %s %.2fx, biggest day move %.0f%%)" % [str(r0["gear_supply"]), str(r1["gear_supply"]), str(r0["gear_listed"]), str(r1["gear_listed"]),
		worst, worst_x, swing * 100], worst_x >= 0.5 and worst_x <= 2.0])
	var gc: Dictionary = GearEconomy.counters
	out.append(["gear surplus sink: %d pieces scrapped at the armourer for %d marks (tiers %d/%d/%d/%d), %d estate pieces scrapped; %d commissions filled from stock" % [int(gc.get("scrap_units", 0)), int(gc.get("scrap_coins", 0)),
		int(gc.get("scrap_1", 0)), int(gc.get("scrap_2", 0)), int(gc.get("scrap_3", 0)), int(gc.get("scrap_4", 0)), int(AdvBrain.counters.get("estate_units_scrapped", 0)), int(AdvBrain.counters.get("commissions_from_stock", 0))], true])
	out.append(["adventurers commission smiths: %d posted, %d filled" % [int(r1["commissions_posted"]), int(r1["commissions_filled"])], true])
	return out


static func summary() -> Dictionary:
	return {"rows": rows, "counters": AdvBrain.counters, "gear_economy": GearEconomy.counters, "resets": AdvBrain.resets, "estates": AdvBrain.estates, "pk_totals": PkRules.pk_log_total, "pk_log_tail": PkRules.pk_log.slice(maxi(0, PkRules.pk_log.size() - 40)),
		"final": AIDirector.records.filter(func(a): return AdvBrain.is_adv(a)).map(func(a): return AdvBrain.snapshot(a).merged({"stats": a.stats, "stash": a.stash, "buys": a.adv.get("buys", []), "targets": a.adv.get("targets", {})}))}
