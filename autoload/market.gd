extends Node
## Market hub. Each town has its own TownMarket (order book, references, NPC
## shops, regulations); prices differ per town and supply/demand is local.
## The hub owns what is global: the clock (game days), the inflation monitor
## and its tunables (store buy-back factor, gathering/bounty/stipend
## multipliers), global faucets/sinks (bounties, stipends, upkeep), Guild
## notices and unique order ids. See docs/GDD.md §6.

signal day_closed(day: int)
signal trade_executed(town: String, item_id: String, qty: int, price: int, buyer: String, seller: String)
signal orders_changed(town: String)
signal notice(text: String)

const TICKS_PER_GAME_DAY := TownMarket.TICKS_PER_GAME_DAY
const TICKS_PER_GAME_HOUR := TownMarket.TICKS_PER_GAME_HOUR
const MAX_OPEN_ORDERS_PER_TRADER := TownMarket.MAX_OPEN_ORDERS_PER_TRADER
const MAX_ORDER_QTY := TownMarket.MAX_ORDER_QTY
const ORDER_TTL := TownMarket.ORDER_TTL
const MIN_ORDER_LIFETIME := TownMarket.MIN_ORDER_LIFETIME
const DAILY_BAND := TownMarket.DAILY_BAND
const TAX_RATE := TownMarket.TAX_RATE
const TAX_MIN_GROSS := TownMarket.TAX_MIN_GROSS
const BREAKER_MOVE := TownMarket.BREAKER_MOVE
const NPC_SELL_FACTOR := TownMarket.NPC_SELL_FACTOR
const DEFAULT_NPC_BUY_FACTOR := TownMarket.DEFAULT_NPC_BUY_FACTOR
const HISTORY_DAYS := TownMarket.HISTORY_DAYS

# --- tunables (EconomyMonitor adjusts these, bounded)
var npc_buy_factor: float = DEFAULT_NPC_BUY_FACTOR
var gather_mult: float = 1.0
var bounty_mult: float = 1.0
var stipend_mult: float = 1.0
var store_purse: float = 600.0       # marks per town per day the shops will pay for goods
const BOUNTY_PURSE := 450            # marks per day the Guild pays in bounties + training stipends (x bounty_mult)
var bounty_left: int = BOUNTY_PURSE

var enabled: bool = true
var tick: int = 0
var towns: Dictionary = {}           # town id -> TownMarket
var town_ids: Array = []
var shop_cfg: Dictionary = {}        # data/shop.json
var econ := {"faucet": 0, "sink": 0}  # global faucets/sinks today (bounties, stipends, upkeep)
var econ_history: Array = []         # per-day totals across towns + global
var notices: Array = []
var monitor = null                   # EconomyMonitor
var _next_id: int = 1
var player_shops: Dictionary = {}    # 0.3.0 town id -> PlayerShop


func _ready() -> void:
	var f := FileAccess.open("res://data/shop.json", FileAccess.READ)
	if f:
		shop_cfg = JSON.parse_string(f.get_as_text())
	monitor = load("res://src/economy/economy_monitor.gd").new()
	reset_prices()


func reset_prices() -> void:
	npc_buy_factor = DEFAULT_NPC_BUY_FACTOR
	gather_mult = 1.0
	bounty_mult = 1.0
	stipend_mult = 1.0
	store_purse = 600.0
	bounty_left = BOUNTY_PURSE
	towns.clear()
	town_ids = GameData.world.get("towns", ["fenhollow"]).duplicate()
	for id in town_ids:
		towns[id] = TownMarket.new(self, id, GameData.towns.get(id, {"name": id}))
	player_shops.clear()
	for id in town_ids:
		player_shops[id] = PlayerShop.new(id)
	PlayerShop.version += 1
	econ = {"faucet": 0, "sink": 0}
	econ_history.clear()
	notices.clear()
	_next_id = 1
	if monitor:
		monitor.reset()


func player_shop(id: String) -> PlayerShop:
	if not player_shops.has(id):
		player_shops[id] = PlayerShop.new(id)
	return player_shops[id]


## Owned shop with something on its stands in this town, else null.
func open_player_shop(id: String) -> PlayerShop:
	var ps: PlayerShop = player_shops.get(id)
	return ps if ps != null and ps.owned and not ps.stocked().is_empty() else null


func town(id: String) -> TownMarket:
	return towns.get(id, towns[town_ids[0]])


func next_order_id() -> int:
	_next_id += 1
	return _next_id - 1


func game_day() -> int:
	# 0.3.1: visible day/night cycle owns the clock AI + HUD follow.
	return DayNight.day_index()


func game_hour() -> int:
	return DayNight.hour()


## Average reference price across towns (for global views like the index).
func avg_reference(item: String) -> float:
	var n := 0.0
	for id in town_ids:
		n += towns[id].reference_price(item)
	return n / maxf(1.0, town_ids.size())


func tradeable(item: String) -> bool:
	return town(town_ids[0]).tradeable(item)


## Pays up to `amount` from today's bounty purse; returns what was paid.
func pay_bounty(amount: int) -> int:
	var paid := clampi(amount, 0, bounty_left)
	bounty_left -= paid
	record_faucet(paid)
	return paid


func record_faucet(amount: int) -> void:
	econ["faucet"] += amount


func record_sink(amount: int) -> void:
	econ["sink"] += amount


func coins_in_market() -> int:
	var n := 0
	for id in town_ids:
		n += towns[id].coins_in_market()
	return n


# -------------------------------------------------------------------- tick --
func on_tick(t: int) -> void:
	tick = t
	for id in town_ids:
		towns[id].tick = t
	if t > 0 and t % TICKS_PER_GAME_DAY == 0:
		end_of_day()
	elif t % 50 == 0:
		for id in town_ids:
			towns[id].housekeeping(t)


func end_of_day() -> void:
	var day := game_day()
	var total := {"faucet": int(econ["faucet"]), "sink": int(econ["sink"]), "tax": 0, "npc_bought": 0, "npc_sold": 0,
		"global_faucet": int(econ["faucet"]), "global_sink": int(econ["sink"]), "towns": {}}
	for id in town_ids:
		var e: Dictionary = towns[id].end_of_day(day)
		for k in ["faucet", "sink", "tax", "npc_bought", "npc_sold"]:
			total[k] = int(total[k]) + int(e.get(k, 0))
		total["towns"][id] = e
	total["day"] = day
	econ_history.append(total)
	while econ_history.size() > HISTORY_DAYS:
		econ_history.pop_front()
	econ = {"faucet": 0, "sink": 0}
	if monitor:
		monitor.run_daily(self)
	bounty_left = int(BOUNTY_PURSE * bounty_mult)
	day_closed.emit(day)


func _notice(text: String) -> void:
	notices.append({"tick": tick, "text": text})
	while notices.size() > 30:
		notices.pop_front()
	notice.emit(text)


# -------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	var ts := {}
	for id in town_ids:
		ts[id] = towns[id].to_save()
	return {
		"version": 2, "towns": ts, "econ": econ, "econ_history": econ_history, "notices": notices, "next_id": _next_id,
		"tunables": {"npc_buy_factor": npc_buy_factor, "gather_mult": gather_mult, "bounty_mult": bounty_mult, "stipend_mult": stipend_mult, "store_purse": store_purse, "bounty_left": bounty_left},
		"monitor": monitor.to_save() if monitor else {},
		"player_shops": _player_shops_save(),
	}


func _player_shops_save() -> Dictionary:
	var d := {}
	for id in player_shops.keys():
		d[id] = player_shops[id].to_save()
	return d


func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	if int(d.get("version", 1)) < 2:
		# single-market save (M1 / early M2): it becomes Fenhollow's market
		towns[town_ids[0]].from_save(d)
	else:
		for id in d.get("towns", {}).keys():
			if towns.has(id):
				towns[id].from_save(d["towns"][id])
	for id in player_shops.keys():          # pre-0.3.0 saves: every shop starts unowned
		player_shops[id] = PlayerShop.new(id)
	for id in d.get("player_shops", {}).keys():
		player_shop(id).from_save(d["player_shops"][id])
	econ = d.get("econ", econ)
	econ_history = d.get("econ_history", [])
	notices = d.get("notices", [])
	_next_id = int(d.get("next_id", 1))
	for id in town_ids:
		for oid in towns[id].orders.keys():
			_next_id = maxi(_next_id, int(oid) + 1)
	var tu: Dictionary = d.get("tunables", {})
	npc_buy_factor = float(tu.get("npc_buy_factor", DEFAULT_NPC_BUY_FACTOR))
	gather_mult = float(tu.get("gather_mult", 1.0))
	bounty_mult = float(tu.get("bounty_mult", 1.0))
	stipend_mult = float(tu.get("stipend_mult", 1.0))
	store_purse = float(tu.get("store_purse", 600.0))
	bounty_left = int(tu.get("bounty_left", BOUNTY_PURSE))
	if monitor:
		monitor.from_save(d.get("monitor", {}))
