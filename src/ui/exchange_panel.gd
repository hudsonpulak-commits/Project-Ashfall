class_name ExchangePanel
extends VBoxContainer
## The Exchange board: live order book (item list with reference, day change,
## best bid/ask), an order ticket (buy/sell, quantity and price within the
## daily band, tax preview), "My orders" with cancel, the collection box, and
## Guild notices/economy stats.

var player: Player
var view := "market"
var selected := ""
var is_buy := true
var qty := 1
var price := 0
var _body: VBoxContainer
var _list: VBoxContainer
var _ticket: VBoxContainer
var _collect_b: Button
var _clock: Label
var _msg: Label
var _dirty := true
var _accum := 0.0


func setup(p: Player) -> void:
	player = p
	add_theme_constant_override("separation", 2)
	var hdr := HBoxContainer.new()
	add_child(hdr)
	var t := UIKit.label("Exchange", 11, UIStyle.ACCENT)
	set_meta("title", t)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(t)
	_clock = UIKit.label("", 9, UIStyle.TEXT_DIM)
	hdr.add_child(_clock)
	_collect_b = UIKit.button("Collect", _collect, 0, 20)
	hdr.add_child(_collect_b)
	add_child(UIKit.tabs([["market", "Market"], ["orders", "My orders"], ["guild", "Guild"]], func(k):
		view = k
		refresh()))
	var sc := UIKit.scroll(128)
	add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	sc.add_child(_list)
	_ticket = VBoxContainer.new()
	_ticket.add_theme_constant_override("separation", 2)
	add_child(_ticket)
	_msg = UIKit.label("", 9, Color("#f0a060"))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(300, 0)
	add_child(_msg)
	Market.orders_changed.connect(func(_t): _dirty = true)
	Market.day_closed.connect(func(_d): _dirty = true)


func _m() -> TownMarket:
	return Market.town(player.current_town)


func open() -> void:
	_msg.text = ""
	refresh()


func _process(dt: float) -> void:
	if not visible:
		return
	_accum += dt
	if _dirty and _accum > 0.5:
		_accum = 0.0
		refresh()


func refresh() -> void:
	_dirty = false
	_clock.text = "Day %d %02d:00 " % [Market.game_day() + 1, Market.game_hour()]
	(get_meta("title") as Label).text = "%s Exchange" % _m().town_name
	var box := _m().pending(player.actor_id)
	var n := 0
	for k in box.get("items", {}).keys():
		n += int(box["items"][k])
	_collect_b.text = "Collect %dm %di" % [int(box.get("coins", 0)), n] if (int(box.get("coins", 0)) > 0 or n > 0) else "Box empty"
	_collect_b.disabled = _collect_b.text == "Box empty"
	UIKit.clear(_list)
	match view:
		"market":
			_build_market()
		"orders":
			_build_orders()
		_:
			_build_guild()
	_build_ticket()


func _build_market() -> void:
	var head := UIKit.label("Item               Ref   Day    Bid/Ask", 8, UIStyle.TEXT_DIM)
	_list.add_child(head)
	var ids: Array = []
	for id in _m().reference.keys():
		if _m().tradeable(id):
			ids.append(id)
	ids.sort_custom(func(a, b): return GameData.item_name(a) < GameData.item_name(b))
	for id in ids:
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(0, 18)
		row.toggle_mode = true
		row.button_pressed = id == selected
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.position = Vector2(2, 1)
		row.add_child(h)
		h.add_child(UIKit.icon(id))
		var ch := _m().day_change(id)
		var bb := _m().best_bid(id)
		var ba := _m().best_ask(id)
		var txt := "%-15s %4d %6s  %s/%s%s" % [GameData.item_name(id).left(15), _m().reference_price(id), UIKit.pct(ch),
			str(bb) if bb > 0 else "-", str(ba) if ba > 0 else "-", "  HALT" if _m().is_halted(id) else ""]
		var l := UIKit.label(txt, 8, Color("#9ad070") if ch > 0.001 else Color("#e07a5a") if ch < -0.001 else UIStyle.TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		var item_id: String = id
		row.pressed.connect(func(): select(item_id))
		_list.add_child(row)


func select(id: String) -> void:
	selected = id
	price = _m().best_ask(id) if is_buy and _m().best_ask(id) > 0 else _m().reference_price(id)
	if not is_buy and _m().best_bid(id) > 0:
		price = _m().best_bid(id)
	var band := _m().price_band(id)
	price = clampi(price, band.x, band.y)
	qty = 1
	_msg.text = ""
	refresh()


func _build_ticket() -> void:
	UIKit.clear(_ticket)
	if selected == "" or view != "market":
		return
	var band := _m().price_band(selected)
	price = clampi(price, band.x, band.y)
	var have := TraderOps.sellable(player, selected)
	var row1 := HBoxContainer.new()
	_ticket.add_child(row1)
	row1.add_child(UIKit.icon(selected))
	var info := UIKit.label("%s  · have %d · %d marks" % [GameData.item_name(selected), have, TraderOps.coins(player)], 9)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(info)
	for side in [[true, "Buy"], [false, "Sell"]]:
		var b := UIKit.button(side[1], func():
			is_buy = side[0]
			select(selected), 38)
		b.toggle_mode = true
		b.button_pressed = is_buy == side[0]
		row1.add_child(b)
	var row2 := HBoxContainer.new()
	_ticket.add_child(row2)
	row2.add_child(UIKit.label("Qty", 9, UIStyle.TEXT_DIM))
	for d in [-10, -1]:
		row2.add_child(UIKit.button(str(d), func(): _set_qty(qty + d), 26))
	var ql := UIKit.label(" %d " % qty, 10)
	ql.custom_minimum_size = Vector2(30, 0)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row2.add_child(ql)
	for d in [1, 10]:
		row2.add_child(UIKit.button("+%d" % d, func(): _set_qty(qty + d), 26))
	row2.add_child(UIKit.button("Max", func():
		_set_qty(have if not is_buy else int(TraderOps.coins(player) / maxf(1.0, price))), 30))
	var row3 := HBoxContainer.new()
	_ticket.add_child(row3)
	row3.add_child(UIKit.label("Price", 9, UIStyle.TEXT_DIM))
	row3.add_child(UIKit.button("-", func(): _set_price(price - 1), 22))
	var pl := UIKit.label(" %d " % price, 10, UIStyle.ACCENT)
	pl.custom_minimum_size = Vector2(30, 0)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row3.add_child(pl)
	row3.add_child(UIKit.button("+", func(): _set_price(price + 1), 22))
	row3.add_child(UIKit.button("Ref", func(): _set_price(_m().reference_price(selected)), 30))
	var gross := qty * price
	var tax := _m().tax_on(gross) if not is_buy else 0
	row3.add_child(UIKit.label(" band %d-%d" % [band.x, band.y], 8, UIStyle.TEXT_DIM))
	var row4 := HBoxContainer.new()
	_ticket.add_child(row4)
	var tl := UIKit.label(("Pay %d" if is_buy else "Get %d (tax %d)") % ([gross] if is_buy else [gross - tax, tax]), 9)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_child(tl)
	row4.add_child(UIKit.button(("Place buy" if is_buy else "Place sell"), _place, 80, 22))


func _set_qty(q: int) -> void:
	qty = clampi(q, 1, Market.MAX_ORDER_QTY)
	refresh()


func _set_price(p: int) -> void:
	var band := _m().price_band(selected)
	price = clampi(p, band.x, band.y)
	refresh()


func _place() -> void:
	var why := TraderOps.place(player, player.current_town, selected, qty, price, is_buy)
	if why == "":
		var pend := _m().pending(player.actor_id)
		var filled := int(pend.get("items", {}).get(selected, 0)) if is_buy else 0
		_msg.text = "Order placed: %s %d %s @ %d.%s" % ["buy" if is_buy else "sell", qty, GameData.item_name(selected).to_lower(), price,
			" Filled %d already - collect it." % filled if filled > 0 else ""]
		Events.say(_msg.text)
	else:
		_msg.text = why
	refresh()


func _collect() -> void:
	var s := TraderOps.collect(player, player.current_town)
	if s != "":
		Events.say(s)
	refresh()


func _build_orders() -> void:
	var mine := _m().open_orders_of(player.actor_id)
	_list.add_child(UIKit.label("Open orders %d/%d" % [mine.size(), Market.MAX_OPEN_ORDERS_PER_TRADER], 9, UIStyle.TEXT_DIM))
	if mine.is_empty():
		_list.add_child(UIKit.label("No open orders. Pick an item under Market.", 9))
	for o in mine:
		var row := HBoxContainer.new()
		row.add_child(UIKit.icon(o["item"]))
		var age := int((Market.ORDER_TTL - (_m().tick - int(o["tick"]))) / float(Market.TICKS_PER_GAME_HOUR))
		var l := UIKit.label("%s %s %d/%d @ %d  (%dh left)" % ["BUY " if o["buy"] else "SELL", GameData.item_name(o["item"]).left(13),
			int(o["filled"]), int(o["qty"]), int(o["price"]), maxi(0, age)], 9)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var oid: int = o["id"]
		row.add_child(UIKit.button("Cancel", func():
			var why := TraderOps.cancel(player, player.current_town, oid)
			_msg.text = why if why != "" else "Order cancelled; escrow returned."
			refresh(), 48))
		_list.add_child(row)
	_list.add_child(UIKit.label("Recent trades", 9, UIStyle.TEXT_DIM))
	var recent_trades: Array = _m().trade_log.slice(maxi(0, _m().trade_log.size() - 8))
	recent_trades.reverse()
	for tr in recent_trades:
		_list.add_child(UIKit.label("%s x%d @ %d" % [GameData.item_name(tr["item"]), int(tr["qty"]), int(tr["price"])], 8))


func _build_guild() -> void:
	var mon = Market.monitor
	var names := []
	for id in Market.town_ids:
		names.append(Market.town(id).town_name.left(6))
	_list.add_child(UIKit.label("Prices by town   " + "  ".join(names), 8, UIStyle.ACCENT))
	for item in ["copper_ore", "iron_ore", "coal", "raw_eel", "cooked_carp", "alder_log", "iron_bar", "iron_helm", "iron_hauberk", "iron_mace"]:
		var cols := []
		for id in Market.town_ids:
			cols.append("%6d" % Market.town(id).reference_price(item))
		var row := HBoxContainer.new()
		row.add_child(UIKit.icon(item))
		row.add_child(UIKit.label("%-13s %s" % [GameData.item_name(item).left(13), " ".join(cols)], 8))
		_list.add_child(row)
	_list.add_child(UIKit.label("Price index %.3f   Store buy-back x%.2f   Gathering x%.2f" % [mon.price_index(Market), Market.npc_buy_factor, Market.gather_mult], 8))
	_list.add_child(UIKit.label("Rules: band ±%d%%/day · tax %d%% on sales ≥%d · max %d orders · halt after a %d%% swing" % [
		int(Market.DAILY_BAND * 100), int(Market.TAX_RATE * 100), Market.TAX_MIN_GROSS, Market.MAX_OPEN_ORDERS_PER_TRADER, int(Market.BREAKER_MOVE * 100)], 8, UIStyle.TEXT_DIM))
	for d in mon.days.slice(maxi(0, mon.days.size() - 4)):
		_list.add_child(UIKit.label("Day %d: index %.3f, coin %d, in %d / out %d (%s)" % [int(d["day"]) + 1, float(d["index"]), int(d["money"]), int(d["faucet"]), int(d["sink"]), d["action"]], 8))
	var notes: Array = Market.notices.slice(maxi(0, Market.notices.size() - 6))
	notes.reverse()
	if notes.is_empty():
		_list.add_child(UIKit.label("No Guild notices yet.", 9))
	for n in notes:
		var l := UIKit.label("• " + str(n["text"]), 8)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		_list.add_child(l)
