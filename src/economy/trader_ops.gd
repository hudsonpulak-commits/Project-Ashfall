class_name TraderOps
extends RefCounted
## Player-side Exchange and shop operations in one town. Escrow comes from the
## pack first, then that town's vault (the board accepts vault funds).
## Every function returns "" on success or a player-readable reason.


static func coins(p: Actor) -> int:
	return p.inventory.count(GameData.currency) + p.bank.count(GameData.currency)


static func pay(p: Actor, amount: int) -> bool:
	if amount < 0 or coins(p) < amount:
		return false
	var from_pack := mini(amount, p.inventory.count(GameData.currency))
	p.inventory.remove(GameData.currency, from_pack)
	p.bank.remove(GameData.currency, amount - from_pack)
	return true


static func receive_coins(p: Actor, amount: int) -> void:
	if amount <= 0:
		return
	if p.inventory.add(GameData.currency, amount) < amount:
		p.bank.add(GameData.currency, amount)


## Tools can only be listed unused (full durability), so wear can't be laundered.
static func _is_fresh(s: Dictionary) -> bool:
	var t: Dictionary = GameData.item(s["id"]).get("tool", {})
	return t.is_empty() or int(s.get("dur", 0)) >= int(t.get("durability", 0))


static func sellable(p: Actor, item: String) -> int:
	var n := 0
	for c in [p.inventory, p.bank]:
		for s in c.slots:
			if s != null and s["id"] == item and _is_fresh(s):
				n += int(s["qty"])
	return n


static func _take_items(p: Actor, item: String, qty: int) -> int:
	var left := qty
	for c in [p.inventory, p.bank]:
		for i in c.size():
			if left <= 0:
				break
			var s = c.slots[i]
			if s == null or s["id"] != item or not _is_fresh(s):
				continue
			var take := mini(left, int(s["qty"]))
			if take >= int(s["qty"]):
				c.remove_at(i)
			else:
				s["qty"] = int(s["qty"]) - take
				c.changed.emit()
			left -= take
	return qty - left


static func place(p: Actor, town: String, item: String, qty: int, price: int, is_buy: bool) -> String:
	var m := Market.town(town)
	var why := m.validate_order(p.actor_id, item, qty, price, is_buy)
	if why != "":
		return why
	if is_buy:
		if not pay(p, qty * price):
			return "You need %d marks for that order." % (qty * price)
	else:
		if sellable(p, item) < qty:
			return "You don't have %d %s to sell." % [qty, GameData.item_name(item).to_lower()]
		_take_items(p, item, qty)
	var res := m.place_order(p.actor_id, item, qty, price, is_buy)
	if not res["ok"]:
		if is_buy:
			receive_coins(p, qty * price)
		else:
			p.bank.add(item, qty)
		return str(res["reason"])
	return ""


## Moves the collection box into the pack (overflow goes to the bank).
static func collect(p: Actor, town: String) -> String:
	var box := Market.town(town).collect(p.actor_id)
	var c := int(box.get("coins", 0))
	receive_coins(p, c)
	var parts := []
	if c > 0:
		parts.append("%d marks" % c)
	var items: Dictionary = box.get("items", {})
	for k in items.keys():
		var q := int(items[k])
		var got := p.inventory.add(k, q)
		if got < q:
			p.bank.add(k, q - got)
		parts.append("%d %s" % [q, GameData.item_name(k).to_lower()])
	return "Collected: " + ", ".join(parts) if not parts.is_empty() else ""


static func cancel(p: Actor, town: String, order_id: int) -> String:
	var m := Market.town(town)
	var o: Dictionary = m.orders.get(order_id, {})
	if o.is_empty() or o["trader"] != p.actor_id:
		return "That order is gone."
	if not m.cancel_order(order_id):
		return "Orders can't be cancelled in their first few seconds."
	collect(p, town)
	return ""


static func shop_buy(p: Actor, town: String, shop: String, item: String, qty: int) -> String:
	var m := Market.town(town)
	if not item in m.shop_items(shop):
		return "This shop doesn't sell that."
	if m.shelf(shop, item) >= 0 and m.shelf(shop, item) < qty:
		return "Only %d left on the shelf." % m.shelf(shop, item)
	if p.inventory.room_for(item) < qty:
		return "Your pack is full."
	var cost := m.shop_cost(shop, item, qty)
	if not pay(p, cost):
		return "You need %d marks." % cost
	m.shop_sell_to(shop, item, qty)
	p.inventory.add(item, qty)
	return ""


static func shop_sell(p: Actor, town: String, shop: String, item: String, qty: int) -> String:
	if item == GameData.currency:
		return "Shops don't buy coin."
	var m := Market.town(town)
	if shop != "general" and m.shop_line_of(item) != shop:
		return "This shop only buys %s." % str(Market.shop_cfg.get("line_names", {}).get(shop, shop)).to_lower()
	var n := mini(qty, p.inventory.count(item))
	if n <= 0:
		return "You have none of that in your pack."
	if m.npc_pay(shop, item) <= 0:
		return "Nobody here will pay anything for that."
	var res := m.npc_buy_from(p.actor_id, item, n, shop)
	if int(res["qty"]) <= 0:
		if m.purse_left() < m.npc_pay(shop, item):
			return "The shops here have spent today's coin. Try tomorrow or another town."
		return "The shop has all the %s it needs today." % GameData.item_name(item).to_lower()
	p.inventory.remove(item, int(res["qty"]))
	receive_coins(p, int(res["paid"]))
	if int(res["qty"]) < n:
		return "The shop only wanted %d today." % int(res["qty"])
	return ""
