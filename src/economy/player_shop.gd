class_name PlayerShop
extends RefCounted
## 0.3.0 a player-owned shop (one empty building per town, data/player_shop.json).
## Only the player may buy the building or stock it; AI agents only buy FROM it,
## at their normal trading cadence (AIBrain.shop_browse / trader buy_quote), so
## it works while you're away exactly like while you watch. Proceeds minus the
## Exchange tax collect in the till; you take them at the counter (or auto-bank).

static var version := 0          # bumped on every change; views redraw on change

var town: String
var owned := false
var owner_name := ""
var slots: Array = []            # per display stand: null or {item, qty, price, dur}
var till := 0
var log: Array = []              # newest last: {day, item, qty, price, buyer}
var unseen := {"qty": 0, "coins": 0}   # sales since you last looked (the "while you were away" line)
var auto_bank := false
var lots_today: Dictionary = {}  # agent id -> purchases today (demand cap)
var stats := {"units": 0, "revenue": 0, "tax": 0}
var _day := -1


func _init(p_town: String = "") -> void:
	town = p_town
	slots.resize(slot_count())


static func cfg() -> Dictionary:
	return GameData.player_shop_cfg


static func ai_cfg() -> Dictionary:
	return cfg().get("ai", {})


static func building_price() -> int:
	return int(cfg().get("price", 1500))


static func slot_count() -> int:
	return int(cfg().get("slots", 8))


static func is_unit_item(item: String) -> bool:
	var it := GameData.item(item)
	return (it.has("gear") or it.has("tool")) and not bool(it.get("stackable", false))   # arrows stack


## Max units on one stand: 1 gear piece / tool, else stack_cap.
static func cap_for(item: String) -> int:
	return int(cfg().get("gear_cap", 1)) if is_unit_item(item) else int(cfg().get("stack_cap", 50))


func _bump() -> void:
	PlayerShop.version += 1


func stocked() -> Array:
	var out: Array = []
	for i in slots.size():
		if slots[i] != null:
			out.append(i)
	return out


# ---------------------------------------------------------------- owner --
## The player buys the building. AI never can (anything not a Player is refused).
func buy_building(buyer) -> String:
	if not (buyer is Player):
		return "Only you can buy a shop here."
	if owned:
		return "You already own this shop."
	var price := building_price()
	var coin: String = GameData.currency
	if buyer.inventory.count(coin) < price:
		return "You need %d marks in your pack (you have %d)." % [price, buyer.inventory.count(coin)]
	buyer.inventory.remove(coin, price)
	Market.record_sink(price)
	owned = true
	owner_name = str(buyer.display_name)
	_bump()
	return ""


## "<name>'s Shop" ("Your Shop" while the player has no name of their own).
func title() -> String:
	return "Your Shop" if owner_name in ["", "You"] else "%s's Shop" % owner_name


func price_error(item: String, price: int) -> String:
	if price < 1:
		return "The lowest price is 1 mark."
	var ref := Market.town(town).reference_price(item)
	var cap := int(ceil(maxf(1.0, ref) * float(cfg().get("price_cap_ref_mult", 5.0))))
	if price > cap:
		return "Guild rule: no more than %d marks (%.0fx the going rate)." % [cap, float(cfg().get("price_cap_ref_mult", 5.0))]
	return ""


## Put qty of item from the actor's pack onto stand i at price each.
func place(actor, i: int, item: String, qty: int, price: int) -> String:
	if not owned or not (actor is Player):
		return "You don't own this shop."
	if i < 0 or i >= slots.size():
		return "No such stand."
	if not Market.tradeable(item) or item == GameData.currency:
		return "You can't sell that here."
	var cur = slots[i]
	if cur != null and str(cur["item"]) != item:
		return "That stand already shows %s." % GameData.item_name(str(cur["item"])).to_lower()
	var have := int(cur["qty"]) if cur != null else 0
	qty = mini(qty, cap_for(item) - have)
	if qty <= 0:
		return "That stand is full (%d max)." % cap_for(item)
	var why := price_error(item, price)
	if why != "":
		return why
	var n: int = actor.inventory.count(item)
	if n <= 0:
		return "You have no %s." % GameData.item_name(item).to_lower()
	qty = mini(qty, n)
	var dur := -1
	if is_unit_item(item):
		var idx: int = actor.inventory.find(item)
		var s = actor.inventory.remove_at(idx)
		dur = int(s.get("dur", -1)) if s is Dictionary else -1
	else:
		actor.inventory.remove(item, qty)
	slots[i] = {"item": item, "qty": have + qty, "price": price, "dur": dur}
	_bump()
	return ""


func reprice(i: int, price: int) -> String:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return "Nothing on that stand."
	var why := price_error(str(slots[i]["item"]), price)
	if why != "":
		return why
	slots[i]["price"] = price
	_bump()
	return ""


## Back to the pack (qty -1 = all that fits).
func take_back(actor, i: int, qty: int = -1) -> String:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return "Nothing on that stand."
	var s: Dictionary = slots[i]
	var item: String = s["item"]
	var want := int(s["qty"]) if qty < 0 else mini(qty, int(s["qty"]))
	var got: int = actor.inventory.add(item, want, int(s.get("dur", -1)))
	if got <= 0:
		return "Your pack is full."
	s["qty"] = int(s["qty"]) - got
	if int(s["qty"]) <= 0:
		slots[i] = null
	_bump()
	return ""


## Till -> pack. Returns marks collected.
func collect(actor) -> int:
	if till <= 0 or not (actor is Player):
		return 0
	var got: int = actor.inventory.add(GameData.currency, till)
	till -= got
	_bump()
	return got


func take_unseen() -> Dictionary:
	var u := unseen.duplicate()
	unseen = {"qty": 0, "coins": 0}
	return u


# -------------------------------------------------------------- pricing --
## Cheapest other way to buy one unit in this town (Exchange ask, NPC shops), 0 = none.
func alternative(item: String) -> int:
	var q := AIBrain.buy_quote(Market.town(town), item, false)
	return int(q[0]) if str(q[1]) != "" else 0


## Deal quality: > 1 is cheaper than the best alternative / going rate.
func deal(item: String, price: int) -> float:
	var c := ai_cfg()
	var ref := float(maxi(1, Market.town(town).reference_price(item)))
	var alt := float(alternative(item))
	var anchor := minf(alt if alt > 0.0 else ref * float(c.get("no_alt_ref_mult", 1.15)), ref * float(c.get("alt_cap", 1.25)))
	return anchor / float(maxi(1, price))


## [label, colour] for the price panel ("Bargain" ... "Overpriced").
func deal_label(item: String, price: int) -> Array:
	var ratio := 1.0 / maxf(0.001, deal(item, price))
	for e in cfg().get("deal_labels", []):
		if ratio <= float(e[0]):
			return [str(e[1]), str(e[2])]
	return ["Overpriced", "#e06050"]


## 0.6 - 1.4: stocked stands, variety, items this town actually trades, decor (hook).
func attractiveness() -> float:
	var a: Dictionary = cfg().get("attract", {})
	var st := stocked()
	if st.is_empty():
		return 0.0
	var items := {}
	var demand := 0
	var m := Market.town(town)
	for i in st:
		var id: String = slots[i]["item"]
		items[id] = true
		if int(m.prev_day_vol.get(id, 0)) > 0:
			demand += 1
	var n := float(slots.size())
	return float(a.get("base", 0.6)) + float(a.get("fill", 0.3)) * st.size() / n \
		+ float(a.get("variety", 0.2)) * minf(1.0, items.size() / n) \
		+ float(a.get("demand", 0.3)) * float(demand) / st.size() + float(a.get("decor", 0.0))


## Chance an agent who wants the item buys it here on one look.
func buy_chance(item: String, price: int) -> float:
	var c := ai_cfg()
	var ref := float(maxi(1, Market.town(town).reference_price(item)))
	if price > ref * float(c.get("max_ref_mult", 1.6)):
		return 0.0
	var d := deal(item, price)
	var p := float(c.get("base", 0.3)) * pow(d, float(c.get("deal_exp", 3.0))) * attractiveness()
	var alt := alternative(item)
	if alt > 0 and price > alt:
		p *= float(c.get("pricey_mult", 0.15))
	return clampf(p, 0.0, float(c.get("max_chance", 0.95)))


func _roll_day() -> void:
	var day := Market.game_day()
	if day != _day:
		_day = day
		lots_today.clear()


func lots_left(agent_id: String) -> int:
	_roll_day()
	return int(ai_cfg().get("lots_per_agent_day", 3)) - int(lots_today.get(agent_id, 0))


## An AI agent buys qty from stand i. Returns the cost (0 = no sale).
## The buyer pays the full price; the till gets it minus the Exchange tax.
func ai_buy(buyer_id: String, i: int, qty: int) -> int:
	if buyer_id == "player" or not owned or i < 0 or i >= slots.size() or slots[i] == null:
		return 0
	if lots_left(buyer_id) <= 0:
		return 0
	var s: Dictionary = slots[i]
	qty = mini(qty, int(s["qty"]))
	if qty <= 0:
		return 0
	var gross := qty * int(s["price"])
	var tax := Market.town(town).tax_on(gross)
	till += gross - tax
	Market.record_sink(tax)
	stats["units"] = int(stats["units"]) + qty
	stats["revenue"] = int(stats["revenue"]) + gross - tax
	stats["tax"] = int(stats["tax"]) + tax
	unseen["qty"] = int(unseen["qty"]) + qty
	unseen["coins"] = int(unseen["coins"]) + gross - tax
	log.append({"day": Market.game_day(), "item": s["item"], "qty": qty, "price": int(s["price"]), "buyer": buyer_id})
	while log.size() > int(cfg().get("log_max", 40)):
		log.pop_front()
	lots_today[buyer_id] = int(lots_today.get(buyer_id, 0)) + 1
	s["qty"] = int(s["qty"]) - qty
	if int(s["qty"]) <= 0:
		slots[i] = null
	_bump()
	return gross


## Player trying to buy from their own shop: always refused (no self-trading).
func player_buy(_actor, _i: int) -> String:
	return "You can't buy from your own shop."


# ----------------------------------------------------------------- save --
func to_save() -> Dictionary:
	return {"owned": owned, "owner": owner_name, "slots": slots.duplicate(true), "till": till, "log": log.duplicate(true),
		"unseen": unseen.duplicate(), "auto_bank": auto_bank, "stats": stats.duplicate(), "lots": lots_today.duplicate(), "day": _day}


func from_save(d: Dictionary) -> void:
	owned = bool(d.get("owned", false))
	owner_name = str(d.get("owner", ""))
	slots.clear()
	slots.resize(slot_count())
	var arr: Array = d.get("slots", [])
	for i in mini(arr.size(), slots.size()):
		if arr[i] is Dictionary and GameData.items.has(str(arr[i].get("item", ""))):
			slots[i] = {"item": str(arr[i]["item"]), "qty": int(arr[i]["qty"]), "price": int(arr[i]["price"]), "dur": int(arr[i].get("dur", -1))}
	till = int(d.get("till", 0))
	log = d.get("log", [])
	unseen = d.get("unseen", {"qty": 0, "coins": 0})
	auto_bank = bool(d.get("auto_bank", false))
	stats = d.get("stats", stats)
	lots_today = d.get("lots", {})
	_day = int(d.get("day", -1))
	_bump()
