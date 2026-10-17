class_name GearEconomy
## 0.3.1 gear market balance (data/gear_economy.json):
##  - demand-aware smithing: production of wearables backs off with unsold stock,
##    Exchange listing depth and a price under base (AIBrain.choose);
##  - surplus scrap: the town armourer buys surplus wearables at a scrap price
##    from a bounded daily purse (goods leave the game; a capped faucet);
##  - commissions are filled from finished stock first (AdvBrain.smith_fill).

const WEAR_SLOTS := ["head", "body", "legs", "shield", "weapon"]

static var _cfg: Dictionary = {}
static var spent: Dictionary = {}       # town -> marks paid out for scrap today
static var spent_day := -1
static var counters: Dictionary = {}    # scrap_units, scrap_coins, ...


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/gear_economy.json", FileAccess.READ)
		if f:
			var p = JSON.parse_string(f.get_as_text())
			if typeof(p) == TYPE_DICTIONARY:
				_cfg = p
	return _cfg


static func reset() -> void:
	spent.clear()
	spent_day = -1
	counters.clear()


static func count(key: String, n: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n


static func is_wearable(item: String) -> bool:
	return str(GameData.item(item).get("gear", {}).get("slot", "")) in WEAR_SLOTS


## Units of `item` this agent holds unsold: stash + its open asks (any town).
static func own_stock(agent: AIAgent, item: String) -> int:
	var n := agent.stash_count(item)
	for oid in agent.my_orders.keys():
		var o: Dictionary = agent.my_orders[oid]
		if str(o.get("item", "")) == item and not bool(o.get("buy", true)):
			var tm := Market.town(str(o.get("town", agent.town)))
			if tm and tm.orders.has(oid):
				n += int(tm.orders[oid]["qty"]) - int(tm.orders[oid]["filled"])
	return n


static func price_ratio(m: TownMarket, item: String) -> float:
	var base := float(GameData.item_value(item))
	return float(m.reference_price(item)) / base if base > 0.0 else 1.0


## Multiplier (0..1) on the utility of crafting `item`: wearables use
## "production", the intermediate goods listed in "stock_aware" (bars) use its
## own/depth terms (unsold listings count as stock, not only the stash); 1 otherwise.
static func production_factor(agent: AIAgent, item: String) -> float:
	var sa: Dictionary = cfg().get("stock_aware", {})
	if item in sa.get("items", []):
		var m2 := AIBrain.mk(agent)
		var own2 := own_stock(agent, item)
		var dep2 := m2.depth(item, false)
		var f2 := 1.0 / (1.0 + maxf(0.0, own2 - float(sa.get("own_free", 15))) / maxf(0.1, float(sa.get("own_span", 15)))) \
			/ (1.0 + maxf(0.0, dep2 - float(sa.get("depth_free", 30))) / maxf(0.1, float(sa.get("depth_span", 30))))
		var pb: Array = sa.get("price_band", {}).get(item, [])   # [stop, full] x base: back off in a local glut
		if pb.size() == 2:
			f2 *= clampf((price_ratio(m2, item) - float(pb[0])) / maxf(0.01, float(pb[1]) - float(pb[0])), 0.0, 1.0)
		return f2
	if not is_wearable(item):
		return 1.0
	var c: Dictionary = cfg().get("production", {})
	var m := AIBrain.mk(agent)
	var own := own_stock(agent, item)
	var dep := m.depth(item, false)
	var f := 1.0 / (1.0 + maxf(0.0, own - float(c.get("own_free", 2))) / maxf(0.1, float(c.get("own_span", 3))))
	f *= 1.0 / (1.0 + maxf(0.0, dep - float(c.get("depth_free", 4))) / maxf(0.1, float(c.get("depth_span", 6))))
	var stop := float(c.get("price_stop", 0.7))
	f *= clampf((price_ratio(m, item) - stop) / maxf(0.01, float(c.get("price_full", 0.95)) - stop), 0.0, 1.0)
	return f


## Wear per fight unit for AI fighters' gear (consumption that keeps smiths busy).
static func wear_mult() -> int:
	return maxi(1, int(cfg().get("ai_wear_mult", 1)))


static func _purse_left(town: String) -> int:
	if spent_day != Market.game_day():
		spent_day = Market.game_day()
		spent.clear()
	return maxi(0, int(cfg().get("scrap", {}).get("purse_per_town_day", 160)) - int(spent.get(town, 0)))


static func scrap_price(item: String) -> int:
	return maxi(1, int(floor(GameData.item_value(item) * float(cfg().get("scrap", {}).get("price_share", 0.35)))))


## Should a holder dump this wearable for scrap rather than list it?
static func is_surplus_market(m: TownMarket, item: String) -> bool:
	var s: Dictionary = cfg().get("scrap", {})
	return price_ratio(m, item) < float(s.get("scrap_below_price", 0.85)) or m.depth(item, false) > int(s.get("depth_free", 4))


## The town armourer buys up to `qty` of `item` for scrap. Returns marks paid.
static func sell_scrap(town: String, item: String, qty: int) -> Dictionary:
	var each := scrap_price(item)
	var q := mini(qty, _purse_left(town) / each)
	if q <= 0:
		return {"qty": 0, "paid": 0}
	spent[town] = int(spent.get(town, 0)) + q * each
	Market.record_faucet(q * each)
	count("scrap_units", q)
	count("scrap_coins", q * each)
	count("scrap_%d" % int(GameData.item(item).get("gear", {}).get("tier", 0)), q)
	return {"qty": q, "paid": q * each}


## Trading round: surplus wearables in the stash (not worn: equip_from_stash
## ran first) go for scrap when the market for them is glutted.
static func scrap_surplus(agent: AIAgent) -> void:
	if AIBrain.is_trader(agent):
		return
	var s: Dictionary = cfg().get("scrap", {})
	var m := AIBrain.mk(agent)
	var producer := agent.focus().has("smithing")
	var left := int(s.get("max_per_round", 6))
	for item in agent.stash.keys().duplicate():
		if left <= 0:
			break
		if not is_wearable(item) or not is_surplus_market(m, item):
			continue
		var keep := int(s.get("keep_producer", 1)) if producer else 0
		var q := mini(agent.stash_count(item) - keep, left)
		if q <= 0:
			continue
		var res := sell_scrap(agent.town, item, q)
		if int(res["qty"]) <= 0:
			break
		agent.stash_add(item, -int(res["qty"]))
		agent.coins += int(res["paid"])
		left -= int(res["qty"])


static func to_save() -> Dictionary:
	return {"spent": spent, "day": spent_day}


static func from_save(d: Dictionary) -> void:
	spent = d.get("spent", {}).duplicate()
	spent_day = int(d.get("day", -1))
