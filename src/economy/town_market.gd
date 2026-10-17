class_name TownMarket
extends RefCounted
## One town's regulated market: a continuous limit order book per item
## (price-time priority, trades at the resting price, escrow up front, per-town
## collection boxes) plus the town's NPC shops (general store + specialists
## with finite stock). Regulations per town: daily price band around the
## town's reference, circuit breaker, sales tax (sink), NPC floor/ceiling,
## open-order and daily volume limits. The Market autoload owns one of these
## per town and runs the day close / monitor for all of them.

const TAX_RATE := 0.02
const TAX_MIN_GROSS := 50
const DAILY_BAND := 0.12
const BREAKER_MOVE := 0.08          # move within BREAKER_WINDOW ticks that halts an item
const BREAKER_WINDOW := 300
const HALT_TICKS := 300
const BREAKER_MIN_MARKS := 2.0      # cheap items: 1-mark ticks never trip the breaker
const NPC_SELL_FACTOR := 1.60
const DEFAULT_NPC_BUY_FACTOR := 0.45
const NPC_DAILY_BUY_CAP := 25        # store buys at most this many of each item per day (all sellers)
const MAX_OPEN_ORDERS_PER_TRADER := 8
const MAX_DAILY_VOLUME_SHARE := 0.25
const MIN_DAILY_VOLUME_CAP := 200
const ORDER_TTL := 2400
const MIN_ORDER_LIFETIME := 5
const TICKS_PER_GAME_DAY := 1500   # 0.3.1: 15 real-min day/night cycle (was 2400 = 24 min)
const TICKS_PER_GAME_HOUR := 62    # 1500/24 ≈ 62.5; 62 → 1488 ticks ≈ 14.9 min
const EMA_ALPHA := 0.3
const HISTORY_DAYS := 60
const MAX_ORDER_QTY := 10000

# --- tunables adjusted by the EconomyMonitor (bounded) ---

var hub                              # the Market autoload
var town_id: String = ""
var town_name: String = ""
var bias: Dictionary = {}            # item -> starting price multiplier (local supply)
var specialists: Array = []          # specialist shop lines in this town
var shop_stock: Dictionary = {}      # specialist item -> units on the shelf
var tick: int = 0
var reference: Dictionary = {}       # item -> int
var day_open: Dictionary = {}        # item -> int (reference at day start)
var orders: Dictionary = {}          # id -> order dict
var books: Dictionary = {}           # item -> {"bids": [ids], "asks": [ids]}
var collection: Dictionary = {}      # trader -> {"coins": int, "items": {id: qty}}
var halted_until: Dictionary = {}    # item -> tick
var recent: Dictionary = {}          # item -> [[tick, price], ...] (breaker window)
var day_stats: Dictionary = {}       # item -> {"vol", "value", "hi", "lo"}
var trader_day_vol: Dictionary = {}  # "trader|item" -> qty
var prev_day_vol: Dictionary = {}    # item -> qty
var history: Dictionary = {}         # item -> [{day, ref, vwap, vol, hi, lo}]
var econ := {"faucet": 0, "sink": 0, "tax": 0, "npc_bought": 0, "npc_sold": 0}  # today
var trade_log: Array = []            # last 40 trades for UI
var by_trader: Dictionary = {}       # trader -> {order_id: true} (index; rebuilt on load)
var npc_day_bought: Dictionary = {}  # item -> qty bought by the store today
var floor_boost: Dictionary = {}     # item -> extra NPC buy factor (monitor props up slumping goods here)
var npc_day_spent := 0               # marks the town's shops paid out today (bounded by Market.store_purse)


func _init(p_hub, id: String, town: Dictionary) -> void:
	hub = p_hub
	town_id = id
	town_name = str(town.get("name", id.capitalize()))
	bias = town.get("price_bias", {})
	specialists = town.get("specialists", [])
	reset_prices()


func reset_prices() -> void:
	reference.clear()
	day_open.clear()
	orders.clear()
	by_trader.clear()
	books.clear()
	collection.clear()
	halted_until.clear()
	recent.clear()
	day_stats.clear()
	trader_day_vol.clear()
	npc_day_bought.clear()
	npc_day_spent = 0
	prev_day_vol.clear()
	history.clear()
	trade_log.clear()
	econ = {"faucet": 0, "sink": 0, "tax": 0, "npc_bought": 0, "npc_sold": 0}
	for id in GameData.items.keys():
		if id != GameData.currency:
			reference[id] = maxi(1, int(round(GameData.item_value(id) * float(bias.get(id, 1.0)))))
			day_open[id] = reference[id]
	shop_stock.clear()
	var spec: Dictionary = hub.shop_cfg.get("specialist", {})
	for line in specialists:
		var ids: Array = hub.shop_cfg.get("lines", {}).get(line, [])
		if line == "cook":
			var ck: Dictionary = hub.shop_cfg.get("cookhouse", {})
			var start := int(ck.get("start_stock", 24))
			for item in ids:
				shop_stock[str(item)] = start
			continue
		for i in ids.size():
			shop_stock[ids[i]] = _tier_value(spec.get("start_stock", [6, 3, 2]), ids[i]) * (20 if GameData.is_stackable(ids[i]) else 1)


func _tier_value(arr: Array, item: String) -> int:
	var t := int(GameData.item(item).get("gear", {}).get("tier", 1))
	return int(arr[clampi(t - 1, 0, arr.size() - 1)])


# ------------------------------------------------------------------ prices --
func tradeable(item_id: String) -> bool:
	return reference.has(item_id) and GameData.item_value(item_id) > 0


func reference_price(item_id: String) -> int:
	return int(reference.get(item_id, GameData.item_value(item_id)))


## The NPC floor is anchored to the item's BASE value (not the market price), so
## it acts as a real price floor; the monitor tunes npc_buy_factor.
func npc_buy_price(item_id: String) -> int:
	return maxi(0, int(floor(GameData.item_value(item_id) * (hub.npc_buy_factor + float(floor_boost.get(item_id, 0.0))))))


func npc_sell_price(item_id: String) -> int:
	return maxi(1, int(ceil(reference_price(item_id) * NPC_SELL_FACTOR)))


func price_band(item_id: String) -> Vector2i:
	var r := reference_price(item_id)
	return Vector2i(maxi(1, int(floor(r * (1.0 - DAILY_BAND)))), maxi(1, int(ceil(r * (1.0 + DAILY_BAND)))))


func tax_on(gross: int) -> int:
	return int(floor(gross * TAX_RATE)) if gross >= TAX_MIN_GROSS else 0


func best_bid(item_id: String) -> int:
	var b: Array = books.get(item_id, {}).get("bids", [])
	return int(orders[b[0]]["price"]) if not b.is_empty() else 0


func best_ask(item_id: String) -> int:
	var a: Array = books.get(item_id, {}).get("asks", [])
	return int(orders[a[0]]["price"]) if not a.is_empty() else 0


func depth(item_id: String, is_buy: bool) -> int:
	var n := 0
	for oid in books.get(item_id, {}).get("bids" if is_buy else "asks", []):
		n += int(orders[oid]["qty"]) - int(orders[oid]["filled"])
	return n


func day_change(item_id: String) -> float:
	var o := float(day_open.get(item_id, reference_price(item_id)))
	var last := last_price(item_id)
	return (last - o) / maxf(1.0, o)


func last_price(item_id: String) -> int:
	var r: Array = recent.get(item_id, [])
	if not r.is_empty():
		return int(r[-1][1])
	var st: Dictionary = day_stats.get(item_id, {})
	return int(st.get("last", reference_price(item_id)))


func is_halted(item_id: String) -> bool:
	return int(halted_until.get(item_id, 0)) > tick


func open_orders_of(trader: String) -> Array:
	var out := []
	for id in by_trader.get(trader, {}).keys():
		if orders.has(id):
			out.append(orders[id])
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out


func open_count(trader: String) -> int:
	return by_trader.get(trader, {}).size()


func _add_order(o: Dictionary) -> void:
	orders[o["id"]] = o
	if not by_trader.has(o["trader"]):
		by_trader[o["trader"]] = {}
	by_trader[o["trader"]][o["id"]] = true


func _drop_order(o: Dictionary) -> void:
	orders.erase(o["id"])
	var m: Dictionary = by_trader.get(o["trader"], {})
	m.erase(o["id"])
	if m.is_empty():
		by_trader.erase(o["trader"])


func daily_cap(item_id: String) -> int:
	return maxi(MIN_DAILY_VOLUME_CAP, int(prev_day_vol.get(item_id, 0) * MAX_DAILY_VOLUME_SHARE))


## Checks every regulation. Returns "" if OK, else a player-readable reason.
func validate_order(trader: String, item_id: String, qty: int, price: int, _is_buy: bool) -> String:
	if not hub.enabled:
		return "The Exchange is closed."
	if not tradeable(item_id):
		return "That can't be traded on the Exchange."
	if qty <= 0 or qty > MAX_ORDER_QTY:
		return "Invalid quantity."
	var band := price_band(item_id)
	if price < band.x or price > band.y:
		return "Price must be within today's band (%d-%d)." % [band.x, band.y]
	if open_count(trader) >= MAX_OPEN_ORDERS_PER_TRADER:
		return "You already have %d open orders." % MAX_OPEN_ORDERS_PER_TRADER
	for o in open_orders_of(trader):
		if o["item"] == item_id and bool(o["buy"]) != _is_buy:
			if (_is_buy and price >= int(o["price"])) or ((not _is_buy) and price <= int(o["price"])):
				return "That would trade with your own order."
	var used := int(trader_day_vol.get(trader + "|" + item_id, 0))
	if used + qty > daily_cap(item_id):
		return "Daily volume limit for this item reached (%d/day)." % daily_cap(item_id)
	return ""


## Places an order whose escrow the caller has ALREADY taken (coins = qty*price
## for buys; the items for sells). Returns {ok, id} or {ok:false, reason}.
func place_order(trader: String, item_id: String, qty: int, price: int, is_buy: bool) -> Dictionary:
	var why := validate_order(trader, item_id, qty, price, is_buy)
	if why != "":
		return {"ok": false, "reason": why}
	var o := {"id": hub.next_order_id(), "trader": trader, "item": item_id, "qty": qty, "filled": 0,
		"price": price, "buy": is_buy, "tick": tick, "spent": 0}
	_add_order(o)
	_match(o)
	if orders.has(o["id"]):
		_insert(o)
	hub.orders_changed.emit(town_id)
	return {"ok": true, "id": o["id"]}


func cancel_order(order_id: int, force: bool = false) -> bool:
	var o: Dictionary = orders.get(order_id, {})
	if o.is_empty():
		return false
	if not force and tick - int(o["tick"]) < MIN_ORDER_LIFETIME:
		return false
	_remove_from_book(o)
	_drop_order(o)
	var left := int(o["qty"]) - int(o["filled"])
	if left > 0:
		if o["buy"]:
			_credit(o["trader"], left * int(o["price"]))
		else:
			_credit_item(o["trader"], o["item"], left)
	hub.orders_changed.emit(town_id)
	return true


func _insert(o: Dictionary) -> void:
	if not books.has(o["item"]):
		books[o["item"]] = {"bids": [], "asks": []}
	var side: Array = books[o["item"]]["bids" if o["buy"] else "asks"]
	var i := 0
	while i < side.size():
		var p := int(orders[side[i]]["price"])
		if (o["buy"] and int(o["price"]) > p) or ((not o["buy"]) and int(o["price"]) < p):
			break
		i += 1
	side.insert(i, o["id"])


func _remove_from_book(o: Dictionary) -> void:
	if books.has(o["item"]):
		books[o["item"]]["bids" if o["buy"] else "asks"].erase(o["id"])


func _match(o: Dictionary) -> void:
	var item: String = o["item"]
	if is_halted(item) or not books.has(item):
		return
	var opp: Array = books[item]["asks" if o["buy"] else "bids"]
	while int(o["filled"]) < int(o["qty"]) and not opp.is_empty() and not is_halted(item):
		var r: Dictionary = orders[opp[0]]
		var crosses: bool = (int(r["price"]) <= int(o["price"])) if o["buy"] else (int(r["price"]) >= int(o["price"]))
		if not crosses:
			break
		if r["trader"] == o["trader"]:
			break   # no self-trading: stop matching rather than wash-trade
		var q := mini(int(o["qty"]) - int(o["filled"]), int(r["qty"]) - int(r["filled"]))
		var price := int(r["price"])
		var buy: Dictionary = o if o["buy"] else r
		var sell: Dictionary = r if o["buy"] else o
		_execute(item, q, price, buy, sell)
		if int(r["filled"]) >= int(r["qty"]):
			opp.pop_front()
			_drop_order(r)
	if int(o["filled"]) >= int(o["qty"]):
		_drop_order(o)


func _execute(item: String, q: int, price: int, buy: Dictionary, sell: Dictionary) -> void:
	buy["filled"] = int(buy["filled"]) + q
	sell["filled"] = int(sell["filled"]) + q
	var gross := q * price
	var tax := tax_on(gross)
	# buyer: items + refund of (limit - price) escrow
	_credit_item(buy["trader"], item, q)
	var refund := (int(buy["price"]) - price) * q
	if refund > 0:
		_credit(buy["trader"], refund)
	_credit(sell["trader"], gross - tax)
	econ["tax"] += tax
	econ["sink"] += tax
	var st: Dictionary = day_stats.get(item, {"vol": 0, "value": 0, "hi": price, "lo": price})
	st["vol"] = int(st["vol"]) + q
	st["value"] = int(st["value"]) + gross
	st["hi"] = maxi(int(st["hi"]), price)
	st["lo"] = mini(int(st["lo"]), price)
	st["last"] = price
	day_stats[item] = st
	for t in [buy["trader"], sell["trader"]]:
		var k: String = t + "|" + item
		trader_day_vol[k] = int(trader_day_vol.get(k, 0)) + q
	var r: Array = recent.get(item, [])
	r.append([tick, price])
	while not r.is_empty() and int(r[0][0]) < tick - BREAKER_WINDOW:
		r.pop_front()
	recent[item] = r
	var first := float(r[0][1])
	if absf(price - first) > maxf(BREAKER_MOVE * first, BREAKER_MIN_MARKS):
		halted_until[item] = tick + HALT_TICKS
		_notice("Trading in %s paused for 3 minutes after a sharp move." % GameData.item_name(item).to_lower())
		recent[item] = []
	trade_log.append({"tick": tick, "item": item, "qty": q, "price": price, "buyer": buy["trader"], "seller": sell["trader"]})
	if trade_log.size() > 40:
		trade_log.pop_front()
	hub.trade_executed.emit(town_id, item, q, price, buy["trader"], sell["trader"])


# -------------------------------------------------------------- collection --
func _box(trader: String) -> Dictionary:
	if not collection.has(trader):
		collection[trader] = {"coins": 0, "items": {}}
	return collection[trader]


func _credit(trader: String, coins: int) -> void:
	_box(trader)["coins"] = int(_box(trader)["coins"]) + coins


func _credit_item(trader: String, item: String, q: int) -> void:
	var items: Dictionary = _box(trader)["items"]
	items[item] = int(items.get(item, 0)) + q


func pending(trader: String) -> Dictionary:
	return collection.get(trader, {"coins": 0, "items": {}})


## Removes and returns everything waiting for `trader`.
func collect(trader: String) -> Dictionary:
	var b: Dictionary = collection.get(trader, {"coins": 0, "items": {}})
	collection.erase(trader)
	return b


## Put items back in the box (e.g. the player's pack was full).
func return_to_box(trader: String, item: String, q: int) -> void:
	if q > 0:
		_credit_item(trader, item, q)


# --------------------------------------------------------------- NPC shops --
## Items a shop sells: "general" or a specialist line id.
func shop_items(shop: String) -> Array:
	if shop == "general":
		return hub.shop_cfg.get("general_store", {}).get("stock", [])
	if shop == "cook":
		return hub.shop_cfg.get("cookhouse", {}).get("stock", hub.shop_cfg.get("lines", {}).get("cook", []))
	if not shop in specialists:
		return []
	return hub.shop_cfg.get("lines", {}).get(shop, [])


func shop_line_of(item: String) -> String:
	var g: Dictionary = GameData.item(item).get("gear", {})
	return str(g.get("line", ""))


## Units on the shelf (-1 = unlimited, general store staples).
func shelf(shop: String, item: String) -> int:
	if shop == "general":
		return -1
	return int(shop_stock.get(item, 0))


func max_shelf(item: String) -> int:
	if item in hub.shop_cfg.get("cookhouse", {}).get("stock", []):
		return int(hub.shop_cfg.get("cookhouse", {}).get("max_stock", 40))
	var spec: Dictionary = hub.shop_cfg.get("specialist", {})
	return _tier_value(spec.get("max_stock", [8, 5, 3]), item) * (20 if GameData.is_stackable(item) else 1)


## What the shop charges for one unit (scarcity raises specialist prices).
func shop_price(shop: String, item: String) -> int:
	var ref := float(reference_price(item))
	if shop == "general":
		return maxi(1, int(ceil(ref * float(hub.shop_cfg.get("general_store", {}).get("sell_factor", 1.6)))))
	if shop == "cook":
		# ~80% of the general-store price (data/shop.json cookhouse.sell_factor).
		return maxi(1, int(ceil(ref * float(hub.shop_cfg.get("cookhouse", {}).get("sell_factor", 1.28)))))
	var spec: Dictionary = hub.shop_cfg.get("specialist", {})
	var fill := clampf(float(shelf(shop, item)) / maxf(1.0, max_shelf(item)), 0.0, 1.0)
	return maxi(1, int(ceil(ref * float(spec.get("sell_factor", 1.15)) * (1.0 + float(spec.get("scarcity_markup", 0.6)) * (1.0 - fill)))))


## Sells `qty` from a shop (caller has checked coins). Returns total cost or -1.
func shop_sell_to(shop: String, item: String, qty: int) -> int:
	if not item in shop_items(shop) or qty <= 0:
		return -1
	var cost := 0
	if shop == "general":
		cost = shop_price(shop, item) * qty
	else:
		if shelf(shop, item) < qty:
			return -1
		for i in qty:
			cost += shop_price(shop, item)
			shop_stock[item] = int(shop_stock[item]) - 1
	econ["sink"] += cost
	econ["npc_sold"] += qty
	return cost


func shop_cost(shop: String, item: String, qty: int) -> int:
	if shop == "general":
		return shop_price(shop, item) * qty
	var cost := 0
	var keep := int(shop_stock.get(item, 0))
	for i in qty:
		cost += shop_price(shop, item)
		shop_stock[item] = int(shop_stock.get(item, 0)) - 1
	shop_stock[item] = keep
	return cost


## Marks the town's shops can still pay out today (daily purse = coin faucet cap).
func purse_left() -> int:
	return maxi(0, int(hub.store_purse) - npc_day_spent)


func npc_buy_room(item_id: String) -> int:
	return maxi(0, NPC_DAILY_BUY_CAP - int(npc_day_bought.get(item_id, 0)))


## What a shop pays per unit: the general store pays the floor; a specialist
## pays a little more for its own line (and puts it back on the shelf).
func npc_pay(shop: String, item_id: String) -> int:
	if shop != "general" and shop in specialists and shop_line_of(item_id) == shop:
		var spec: Dictionary = hub.shop_cfg.get("specialist", {})
		return int(floor(GameData.item_value(item_id) * float(spec.get("buy_factor", 0.55)) * hub.npc_buy_factor / DEFAULT_NPC_BUY_FACTOR))
	return npc_buy_price(item_id)


## The shop buys up to its daily cap. Returns {"qty": accepted, "paid": coins}.
func npc_buy_from(_trader: String, item_id: String, qty: int, shop: String = "general") -> Dictionary:
	var each := npc_pay(shop, item_id)
	var q := mini(qty, npc_buy_room(item_id))
	if each > 0:
		q = mini(q, purse_left() / each)
	if each <= 0 or item_id in hub.shop_cfg.get("general_store", {}).get("no_buy", []):
		q = 0
	var paid := each * q
	npc_day_spent += paid
	npc_day_bought[item_id] = int(npc_day_bought.get(item_id, 0)) + q
	if q > 0 and shop != "general" and shop_stock.has(item_id):
		shop_stock[item_id] = int(shop_stock[item_id]) + q
	econ["faucet"] += paid
	econ["npc_bought"] += q
	return {"qty": q, "paid": paid}


func _restock() -> void:
	for item in shop_stock.keys():
		var mx := max_shelf(item)
		var n := int(shop_stock[item])
		if n < mx:
			var step := 4 if str(item).begins_with("cooked_") else (5 if GameData.is_stackable(item) else 1)
			shop_stock[item] = mini(mx, n + step)


# -------------------------------------------------------------------- tick --
## Called by the hub every 50 ticks (not on day close).
func housekeeping(t: int) -> void:
	tick = t
	_expire_orders()
	_rematch_halted()
	var every := int(hub.shop_cfg.get("specialist", {}).get("restock_ticks", 200))
	if "cook" in specialists:
		every = mini(every, int(hub.shop_cfg.get("cookhouse", {}).get("restock_ticks", 300)))
	if t % every == 0:
		_restock()


func _expire_orders() -> void:
	var dead := []
	for o in orders.values():
		if tick - int(o["tick"]) > ORDER_TTL:
			dead.append(o["id"])
	for id in dead:
		cancel_order(id, true)


func _rematch_halted() -> void:
	for item in halted_until.keys():
		if int(halted_until[item]) <= tick and int(halted_until[item]) > tick - 60:
			var b: Dictionary = books.get(item, {})
			if b.is_empty() or b["bids"].is_empty():
				continue
			var top: Dictionary = orders[b["bids"][0]]
			_remove_from_book(top)
			_match(top)
			if orders.has(top["id"]):
				_insert(top)


## Day close for this town: reference prices move toward the day's VWAP (or the
## book mid when nothing traded), clamped to the band. Returns the day's econ.
func end_of_day(day: int) -> Dictionary:
	for item in reference.keys():
		var r := float(reference[item])
		var st: Dictionary = day_stats.get(item, {})
		var vol := int(st.get("vol", 0))
		var target := r
		if vol > 0:
			target = float(st["value"]) / vol
		else:
			var bb := best_bid(item)
			var ba := best_ask(item)
			if bb > 0 and ba > 0:
				target = (bb + ba) / 2.0
			elif bb > r:
				target = bb
			elif ba > 0 and ba < r:
				target = ba
		var nr := r + EMA_ALPHA * (target - r)
		nr = clampf(nr, r * (1.0 - DAILY_BAND), r * (1.0 + DAILY_BAND))
		var base := float(GameData.item_value(item))
		nr = clampf(nr, maxf(1.0, base * 0.25), base * 4.0)
		var new_ref := maxi(1, int(round(nr)))
		if new_ref == int(r) and absf(target - r) >= 1.0:
			new_ref = int(r) + (1 if target > r else -1)
		new_ref = clampi(new_ref, maxi(1, int(base * 0.25)), int(ceil(base * 4.0)))
		reference[item] = new_ref
		day_open[item] = new_ref
		var h: Array = history.get(item, [])
		h.append({"day": day, "ref": new_ref, "vwap": (float(st["value"]) / vol) if vol > 0 else 0.0,
			"vol": vol, "hi": int(st.get("hi", 0)), "lo": int(st.get("lo", 0))})
		while h.size() > HISTORY_DAYS:
			h.pop_front()
		history[item] = h
		prev_day_vol[item] = vol
	for o in orders.values().duplicate():
		var band := price_band(o["item"])
		if int(o["price"]) < band.x or int(o["price"]) > band.y:
			cancel_order(o["id"], true)
	_expire_orders()
	day_stats.clear()
	trader_day_vol.clear()
	npc_day_bought.clear()
	npc_day_spent = 0
	recent.clear()
	var snapshot := econ.duplicate()
	econ = {"faucet": 0, "sink": 0, "tax": 0, "npc_bought": 0, "npc_sold": 0}
	return snapshot


func _notice(text: String) -> void:
	hub._notice("%s: %s" % [town_name, text])


## Coins held in escrow (buy orders) + this town's collection boxes.
func coins_in_market() -> int:
	var n := 0
	for o in orders.values():
		if o["buy"]:
			n += (int(o["qty"]) - int(o["filled"])) * int(o["price"])
	for b in collection.values():
		n += int(b["coins"])
	return n


# -------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	var ol := []
	for o in orders.values():
		ol.append(o)
	return {
		"reference": reference, "day_open": day_open, "orders": ol, "collection": collection,
		"halted_until": halted_until, "day_stats": day_stats, "trader_day_vol": trader_day_vol,
		"prev_day_vol": prev_day_vol, "npc_day_bought": npc_day_bought, "npc_day_spent": npc_day_spent, "history": history, "econ": econ,
		"trade_log": trade_log, "shop_stock": shop_stock, "floor_boost": floor_boost,
	}


func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in d.get("reference", {}).keys():
		if reference.has(k):
			reference[k] = int(d["reference"][k])
	for k in d.get("day_open", {}).keys():
		day_open[k] = int(d["day_open"][k])
	orders.clear()
	by_trader.clear()
	books.clear()
	var ol: Array = d.get("orders", [])
	ol.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	for o in ol:
		o["id"] = int(o["id"])
		for key in ["qty", "filled", "price", "tick", "spent"]:
			o[key] = int(o.get(key, 0))
		_add_order(o)
		_insert(o)
	collection = _int_dict_deep(d.get("collection", {}))
	floor_boost.clear()
	for k in d.get("floor_boost", {}).keys():
		floor_boost[k] = float(d["floor_boost"][k])
	halted_until = d.get("halted_until", {})
	day_stats = d.get("day_stats", {})
	trader_day_vol = d.get("trader_day_vol", {})
	prev_day_vol = d.get("prev_day_vol", {})
	npc_day_bought = d.get("npc_day_bought", {})
	npc_day_spent = int(d.get("npc_day_spent", 0))
	history = d.get("history", {})
	econ = d.get("econ", econ)
	trade_log = d.get("trade_log", [])
	for k in d.get("shop_stock", {}).keys():
		if shop_stock.has(k):
			shop_stock[k] = int(d["shop_stock"][k])


func _int_dict_deep(src: Dictionary) -> Dictionary:
	var out := {}
	for t in src.keys():
		var items := {}
		for k in src[t].get("items", {}).keys():
			items[k] = int(src[t]["items"][k])
		out[t] = {"coins": int(src[t].get("coins", 0)), "items": items}
	return out
