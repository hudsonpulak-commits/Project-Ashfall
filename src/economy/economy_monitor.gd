class_name EconomyMonitor
extends RefCounted
## Inflation monitor. Runs once per game day (from Market.end_of_day).
##
## Measures: a value-weighted price index over a staple basket (1.0 = base
## values), the total money supply (player + agents + market escrow), and the
## day's faucets/sinks. Responds with small, bounded steps:
##   inflation (index or money supply rising fast)
##       -> cut coin faucets: lower the NPC buy factor, the bounty and the
##          stipend; nudge gathering up slightly (more goods)
##   deflation (index falling fast)
##       -> the opposite steps
##   glut (prices sliding while money still grows: goods are piling up and
##         the store buy-back is the main faucet)
##       -> shrink the daily store purse and the buy factor, slow gathering
##   otherwise -> relax 10 % back toward defaults.
## Every change is bounded (see LIMITS) and posted as a Guild notice.

const BASKET := ["ash_log", "alder_log", "copper_ore", "tin_ore", "iron_ore", "coal", "raw_carp", "cooked_carp",
	"bronze_bar", "iron_bar", "steel_bar", "plank", "reed_fibre", "bronze_hatchet", "bronze_pick"]
const TRIGGER := 0.01            # avg daily index change over 3 days
const MONEY_TRIGGER := 0.04      # avg daily money-supply growth over 3 days
const LIMITS := {
	"npc_buy_factor": [0.36, 0.54, 0.01],
	"bounty_mult": [0.8, 1.2, 0.05],
	"stipend_mult": [0.5, 1.2, 0.1],
	"gather_mult": [0.85, 1.1, 0.02],
	"store_purse": [300.0, 900.0, 50.0],
}
const DEFAULTS := {"npc_buy_factor": 0.45, "bounty_mult": 1.0, "stipend_mult": 1.0, "gather_mult": 1.0, "store_purse": 600.0}
const ITEM_LOW := 0.8            # per-item floor support below this x base (town price)
const ITEM_HIGH := 0.95          # ...steps back down above this
const ITEM_STEP := 0.05
const ITEM_BOOST_MAX := 0.3      # floor tops out at (npc_buy_factor + 0.3) x base
const GLUT_MONEY := 0.015        # money growth above this while prices fall = goods glut

## 0.3.1 level band (data/economy_monitor.json, optional; absent = 0.3.0 behaviour).
## The rate triggers above miss a slow steady slide (~0.5 %/day never reaches
## TRIGGER), so a long soak can drift 15-20 % with the monitor holding. Outside
## the band the monitor warms/cools unless the index is already recovering.
static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = {"_loaded": true}
		var f := FileAccess.open("res://data/economy_monitor.json", FileAccess.READ)
		if f:
			var p = JSON.parse_string(f.get_as_text())
			if typeof(p) == TYPE_DICTIONARY:
				_cfg.merge(p, true)
	return _cfg


## +1 warm / -1 cool / 0 none from the level band (index level, 3-day avg
## daily index and money change).
static func level_action(idx: float, d_idx: float, d_money: float) -> int:
	var band: Dictionary = cfg().get("level_band", {})
	if band.is_empty():
		return 0
	var recover := float(band.get("recovering_per_day", 0.002))
	if idx < float(band.get("low", 0.0)) and d_idx < recover and d_money <= float(band.get("max_money_growth", MONEY_TRIGGER)):
		return 1
	if idx > float(band.get("high", 99.0)) and d_idx > -recover:
		return -1
	return 0


var money_supply_provider: Callable   # set by main: () -> int
var days: Array = []                   # [{day, index, money, faucet, sink, tax, action}]


func reset() -> void:
	days.clear()


## Basket index across all towns (1.0 = base values).
func price_index(market) -> float:
	var num := 0.0
	var den := 0.0
	for id in BASKET:
		num += market.avg_reference(id)
		den += float(GameData.item_value(id))
	return num / maxf(1.0, den)


## Same index for one town.
func town_index(tm) -> float:
	var num := 0.0
	var den := 0.0
	for id in BASKET:
		num += float(tm.reference_price(id))
		den += float(GameData.item_value(id))
	return num / maxf(1.0, den)


func run_daily(market) -> void:
	var idx := price_index(market)
	var money := int(money_supply_provider.call()) if money_supply_provider.is_valid() else 0
	var last: Dictionary = market.econ_history[-1] if not market.econ_history.is_empty() else {}
	var rec := {"day": int(last.get("day", market.game_day())), "index": idx, "money": money,
		"faucet": int(last.get("faucet", 0)), "sink": int(last.get("sink", 0)), "tax": int(last.get("tax", 0)), "action": "hold"}
	days.append(rec)
	while days.size() > 60:
		days.pop_front()
	if days.size() >= 4:
		var d_idx: float = (days[-1]["index"] / maxf(0.0001, days[-4]["index"]) - 1.0) / 3.0
		var d_money: float = (float(days[-1]["money"]) / maxf(1.0, float(days[-4]["money"])) - 1.0) / 3.0
		var lvl := level_action(idx, d_idx, d_money)
		if lvl > 0:
			_step(market, 1)
			rec["action"] = "warm"
			market._notice("Guild notice: prices are sliding. Store buy-backs and bounties raised.")
		elif lvl < 0:
			_step(market, -1)
			rec["action"] = "cool"
			market._notice("Guild notice: prices are climbing. Store buy-backs and bounties trimmed.")
		elif d_idx > TRIGGER or (d_money > MONEY_TRIGGER and d_idx >= 0.0):
			_step(market, -1)
			rec["action"] = "cool"
			market._notice("Guild notice: prices are climbing. Store buy-backs and bounties trimmed.")
		elif d_idx < -TRIGGER / 2.0 and d_money > GLUT_MONEY:
			# (0.2.1: no longer cuts the buy factor; that deepened slumps)
			var lp: Array = LIMITS["store_purse"]
			market.store_purse = clampf(market.store_purse - float(lp[2]), lp[0], lp[1])
			var g: Array = LIMITS["gather_mult"]
			market.gather_mult = clampf(market.gather_mult - float(g[2]), g[0], g[1])
			rec["action"] = "glut"
			market._notice("Guild notice: goods are piling up. Shops buy less and gathering slows.")
		elif d_idx < -TRIGGER and d_money <= MONEY_TRIGGER:
			_step(market, 1)
			rec["action"] = "warm"
			market._notice("Guild notice: prices are sliding. Store buy-backs and bounties raised.")
		else:
			_relax(market)
	rec["floor_boosts"] = _item_floors(market)
	rec["npc_buy_factor"] = market.npc_buy_factor
	rec["gather_mult"] = market.gather_mult
	rec["bounty_mult"] = market.bounty_mult
	rec["store_purse"] = market.store_purse


## Per-item, per-town response (0.2.1). A good trading under ITEM_LOW x base
## in a town gets its store floor raised a step (the store buys the surplus
## up as town consumption, a goods sink paid from the bounded store purse);
## above ITEM_HIGH x base the boost steps back down. Returns boosted count.
func _item_floors(market) -> int:
	var n := 0
	for tid in market.town_ids:
		var tm = market.town(tid)
		for id in tm.reference.keys():
			var base := float(GameData.item_value(id))
			if base < 2.0:
				continue
			var r := float(tm.reference_price(id)) / base
			var b := float(tm.floor_boost.get(id, 0.0))
			if r < ITEM_LOW:
				b = minf(ITEM_BOOST_MAX, b + ITEM_STEP)
			elif r > ITEM_HIGH:
				b = maxf(0.0, b - ITEM_STEP)
			if b > 0.0:
				tm.floor_boost[id] = snappedf(b, 0.001)
				n += 1
			else:
				tm.floor_boost.erase(id)
	return n


## dir = -1 cools (inflation), +1 warms (deflation)
func _step(market, dir: int) -> void:
	for k in ["npc_buy_factor", "bounty_mult", "stipend_mult", "store_purse"]:
		var l: Array = LIMITS[k]
		market.set(k, clampf(float(market.get(k)) + dir * float(l[2]), l[0], l[1]))
	var g: Array = LIMITS["gather_mult"]
	market.gather_mult = clampf(market.gather_mult - dir * float(g[2]), g[0], g[1])


func _relax(market) -> void:
	for k in DEFAULTS.keys():
		var v := float(market.get(k))
		market.set(k, v + (float(DEFAULTS[k]) - v) * 0.1)


func to_save() -> Dictionary:
	return {"days": days}


func from_save(d: Dictionary) -> void:
	days = d.get("days", [])
