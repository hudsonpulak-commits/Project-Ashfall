class_name PlayerShopPanel
extends VBoxContainer
## 0.3.0 your shop: buy the empty building, then stock its 8 display stands
## from your pack, price them (local reference, Exchange bid/ask, store price
## and a deal label shown), take items back, reprice, collect the till.

var player: Player
var world
var town := ""
var sel := 0                      # selected stand
var pick := ""                    # item picked from the pack for an empty stand
var qty := 1
var price := 1
var _body: VBoxContainer
var _msg: Label


func setup(p: Player, w) -> void:
	player = p
	world = w
	add_theme_constant_override("separation", 2)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	add_child(_body)
	_msg = UIKit.label("", 9, Color("#f0a060"))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(300, 0)
	add_child(_msg)
	player.inventory.changed.connect(func(): if visible: refresh())


func shop() -> PlayerShop:
	return Market.player_shop(town)


func open(p_town: String, slot: int) -> void:
	town = p_town
	_msg.text = ""
	if slot >= 0:
		sel = slot
	_load_sel()
	refresh()


func _load_sel() -> void:
	var s = shop().slots[sel] if sel < shop().slots.size() else null
	pick = str(s["item"]) if s != null else ""
	price = int(s["price"]) if s != null else 1
	qty = 1


func _ref(item: String) -> int:
	return Market.town(town).reference_price(item)


func refresh() -> void:
	if _body == null or town == "":
		return
	UIKit.clear(_body)
	var ps := shop()
	var tname: String = Market.town(town).town_name
	if not ps.owned:
		_body.add_child(UIKit.label("Empty shop · %s" % tname, 11, UIStyle.ACCENT))
		var l := UIKit.label("A walk-in shop with a counter and 8 display stands. Stock it from your pack, set your prices, and townsfolk will buy, more often when your prices beat the market. Only you can own it.", 9, UIStyle.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		_body.add_child(l)
		_body.add_child(UIKit.button("Buy for %d marks (you have %d)" % [PlayerShop.building_price(), player.inventory.count(GameData.currency)], _buy, 0, 26))
		return
	_body.add_child(UIKit.label("%s · %s" % [ps.title(), tname], 11, UIStyle.ACCENT))
	var till := HBoxContainer.new()
	_body.add_child(till)
	till.add_child(UIKit.label("Till: %d marks  " % ps.till, 9))
	till.add_child(UIKit.button("Collect", _collect, 52))
	var ab := UIKit.button("Auto-bank: %s" % ("on" if ps.auto_bank else "off"), func():
		ps.auto_bank = not ps.auto_bank
		refresh(), 80)
	till.add_child(ab)
	_body.add_child(UIKit.label("Attractiveness %d%%  ·  sold %d units, %d marks so far" % [int(ps.attractiveness() * 100), int(ps.stats["units"]), int(ps.stats["revenue"])], 8, UIStyle.TEXT_DIM))
	# stands
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(grid)
	for i in ps.slots.size():
		var s = ps.slots[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = i == sel
		b.custom_minimum_size = Vector2(150, 22)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.position = Vector2(2, 3)
		b.add_child(h)
		if s != null:
			h.add_child(UIKit.icon(str(s["item"])))
			var dl := ps.deal_label(str(s["item"]), int(s["price"]))
			var lab := UIKit.label("%d x %d  %s" % [int(s["qty"]), int(s["price"]), dl[0]], 8, Color(dl[1]))
			lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(lab)
		else:
			var lab2 := UIKit.label("Stand %d: empty" % (i + 1), 8, UIStyle.TEXT_DIM)
			lab2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(lab2)
		var idx := i
		b.pressed.connect(func():
			sel = idx
			_load_sel()
			_msg.text = ""
			refresh())
		grid.add_child(b)
	_editor(ps)
	# sales log
	if not ps.log.is_empty():
		var lines := []
		for e in ps.log.slice(-4):
			lines.append("Day %d: %d %s @ %d" % [int(e["day"]), int(e["qty"]), GameData.item_name(str(e["item"])).to_lower(), int(e["price"])])
		lines.reverse()
		_body.add_child(UIKit.label("Recent sales:\n" + "\n".join(lines), 8, UIStyle.TEXT_DIM))


func _editor(ps: PlayerShop) -> void:
	var s = ps.slots[sel]
	var item := pick
	if item == "":
		_body.add_child(UIKit.label("Stand %d is empty: tap an item in your pack to stock it." % (sel + 1), 9))
	else:
		var m := Market.town(town)
		var alt := ps.alternative(item)
		var dl := ps.deal_label(item, price)
		_body.add_child(UIKit.label("%s  ·  ref %d · Exchange bid %s / ask %s · cheapest elsewhere %s" % [GameData.item_name(item), _ref(item),
			str(m.best_bid(item)) if m.best_bid(item) > 0 else "-", str(m.best_ask(item)) if m.best_ask(item) > 0 else "-", str(alt) if alt > 0 else "-"], 8, UIStyle.TEXT_DIM))
		var pr := HBoxContainer.new()
		_body.add_child(pr)
		pr.add_child(UIKit.label("Price ", 9))
		for d in [-10, -1, 1, 10]:
			var dd: int = d
			pr.add_child(UIKit.button("%+d" % dd, func():
				price = maxi(1, price + dd)
				refresh(), 30))
		pr.add_child(UIKit.button("=ref", func():
			price = maxi(1, _ref(item))
			refresh(), 34))
		var pl := UIKit.label(" %d  %s (x%.2f)" % [price, dl[0], float(price) / maxf(1.0, _ref(item))], 9, Color(dl[1]))
		pr.add_child(pl)
		var acts := HBoxContainer.new()
		_body.add_child(acts)
		var have := player.inventory.count(item)
		var room := PlayerShop.cap_for(item) - (int(s["qty"]) if s != null else 0)
		if have > 0 and room > 0:
			acts.add_child(UIKit.label("Qty ", 9))
			for d in [-5, -1, 1, 5]:
				var dq: int = d
				acts.add_child(UIKit.button("%+d" % dq, func():
					qty = clampi(qty + dq, 1, mini(room, player.inventory.count(item)))
					refresh(), 26))
			acts.add_child(UIKit.button("Place %d" % mini(qty, mini(room, have)), _place, 56))
		if s != null:
			acts.add_child(UIKit.button("Reprice", func(): _say(ps.reprice(sel, price), "Repriced to %d." % price), 54))
			acts.add_child(UIKit.button("Take back", func(): _say(ps.take_back(player, sel), "Back in your pack."), 64))
	# pack picker
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	_body.add_child(g)
	for i in player.inventory.slots.size():
		var sl = player.inventory.slots[i]
		var is_ := ItemSlot.new()
		is_.set_item(sl)
		var it: String = str(sl["id"]) if sl != null else ""
		is_.pressed.connect(func():
			if it == "" or it == GameData.currency:
				return
			if s != null and str(s["item"]) != it:
				_msg.text = "This stand shows %s: pick an empty stand for %s." % [GameData.item_name(str(s["item"])).to_lower(), GameData.item_name(it).to_lower()]
				return
			pick = it
			qty = mini(player.inventory.count(it), PlayerShop.cap_for(it))
			price = maxi(1, _ref(it)) if s == null else price
			refresh())
		g.add_child(is_)


func _say(why: String, ok: String) -> void:
	_msg.text = why if why != "" else ok
	if why == "" and shop().slots[sel] == null:
		pick = ""
	refresh()


func _buy() -> void:
	var why := shop().buy_building(player)
	_msg.text = why if why != "" else "The keys are yours! Tap a display stand or pick from your pack to stock it."
	if why == "" and world and world.buildings_view:
		world.buildings_view.refresh_all()
	refresh()


func _place() -> void:
	var why := shop().place(player, sel, pick, qty, price)
	_say(why, "On display: %s at %d marks each." % [GameData.item_name(pick).to_lower(), price])


func _collect() -> void:
	var got := shop().collect(player)
	_msg.text = "You take %d marks from the till." % got if got > 0 else "The till is empty."
	refresh()
