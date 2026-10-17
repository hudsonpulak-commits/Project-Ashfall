class_name StorePanel
extends VBoxContainer
## General store: buys staples at the CEILING (a coin sink) and buys anything
## from your pack at the FLOOR (a faucet, capped per item per day).

var player: Player
var shop := "general"
var _buy_list: VBoxContainer
var _sell_grid: GridContainer
var _slots: Array = []
var _msg: Label
var _qty := 1


func setup(p: Player) -> void:
	player = p
	add_theme_constant_override("separation", 2)
	var hdr := HBoxContainer.new()
	add_child(hdr)
	var t := UIKit.label("General store", 11, UIStyle.ACCENT)
	set_meta("title", t)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(t)
	for q in [1, 5]:
		var b := UIKit.button("x%d" % q, func():
			_qty = q
			refresh(), 30)
		b.toggle_mode = true
		hdr.add_child(b)
	var hint := UIKit.label("", 9, UIStyle.TEXT_DIM)
	set_meta("hint", hint)
	add_child(hint)
	_buy_list = VBoxContainer.new()
	_buy_list.add_theme_constant_override("separation", 1)
	add_child(_buy_list)
	var hint2 := UIKit.label("", 9, UIStyle.TEXT_DIM)
	set_meta("hint2", hint2)
	add_child(hint2)
	_sell_grid = GridContainer.new()
	_sell_grid.columns = 6
	_sell_grid.add_theme_constant_override("h_separation", 2)
	_sell_grid.add_theme_constant_override("v_separation", 2)
	_sell_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_sell_grid)
	for i in 24:
		var s := ItemSlot.new()
		var idx := i
		s.pressed.connect(func(): _sell(idx))
		_sell_grid.add_child(s)
		_slots.append(s)
	_msg = UIKit.label("", 9, Color("#f0a060"))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(300, 0)
	add_child(_msg)
	player.inventory.changed.connect(refresh)


func open() -> void:
	_msg.text = ""
	refresh()


func refresh() -> void:
	if _buy_list == null:
		return
	for c in get_child(0).get_children():
		if c is Button:
			c.button_pressed = c.text == "x%d" % _qty
	var m := Market.town(player.current_town)
	var line_names: Dictionary = Market.shop_cfg.get("line_names", {})
	if shop == "general":
		var gb: Dictionary = GameData.towns.get(player.current_town, {})
		var gname := "%s general store" % m.town_name
		for bd in gb.get("buildings", []):
			if str(bd.get("shop", "")) == "general":
				gname = str(bd.get("name", gname))
		(get_meta("title") as Label).text = gname
		(get_meta("hint") as Label).text = "Basic goods (price = local Exchange ref x%.1f)" % float(Market.shop_cfg.get("general_store", {}).get("sell_factor", 1.6))
		(get_meta("hint2") as Label).text = "Sell from pack: buys almost anything at the floor"
	elif shop == "cook":
		var o2: Dictionary = GameData.buildings_cfg.get("shops", {}).get("cook", {})
		(get_meta("title") as Label).text = str(o2.get("name", "Cook House"))
		(get_meta("hint") as Label).text = "Cooked meals ~80%% of general-store price (ref x%.2f). Finite stock." % float(Market.shop_cfg.get("cookhouse", {}).get("sell_factor", 1.28))
		(get_meta("hint2") as Label).text = "Ovens inside are free to use. Stock restocks slowly."
	else:
		var o: Dictionary = GameData.buildings_cfg.get("shops", {}).get(shop, {})
		(get_meta("title") as Label).text = "%s · %s" % [o.get("name", shop), line_names.get(shop, shop)]
		(get_meta("hint") as Label).text = "Only in %s. Price rises as the shelf empties." % m.town_name
		(get_meta("hint2") as Label).text = "Sell from pack: buys %s only" % str(line_names.get(shop, shop)).to_lower()
	UIKit.clear(_buy_list)
	var stock: Array = m.shop_items(shop)
	var row: HBoxContainer = null
	for i in stock.size():
		if i % 2 == 0:
			row = HBoxContainer.new()
			_buy_list.add_child(row)
		var id: String = stock[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 26)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.position = Vector2(2, 2)
		h.add_theme_constant_override("separation", 3)
		b.add_child(h)
		h.add_child(UIKit.icon(id))
		var shelf := m.shelf(shop, id)
		# full name on line 1 (never cut), price and shelf on line 2
		var l := UIKit.label("%s\n%d marks%s" % [GameData.item_name(id), m.shop_price(shop, id), ("  (%d left)" % shelf) if shelf >= 0 else ""], 8)
		l.add_theme_constant_override("line_spacing", -2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		b.disabled = shelf == 0
		b.pressed.connect(func(): _buy(id))
		row.add_child(b)
	for i in _slots.size():
		_slots[i].set_item(player.inventory.slots[i])


func _buy(id: String) -> void:
	var cost := Market.town(player.current_town).shop_cost(shop, id, _qty)
	var why := TraderOps.shop_buy(player, player.current_town, shop, id, _qty)
	_msg.text = why if why != "" else "Bought %d %s for %d marks." % [_qty, GameData.item_name(id).to_lower(), cost]
	refresh()


func _sell(i: int) -> void:
	var s = player.inventory.slots[i]
	if s == null:
		return
	var id: String = s["id"]
	var n := player.inventory.count(id) if not GameData.is_stackable(id) else mini(int(s["qty"]), _qty)
	if not GameData.is_stackable(id):
		n = mini(n, _qty)
	var m := Market.town(player.current_town)
	var each := m.npc_pay(shop, id)
	var why := TraderOps.shop_sell(player, player.current_town, shop, id, n)
	_msg.text = why if why != "" else "Sold %d %s for %d marks each (%d more wanted today)." % [n, GameData.item_name(id).to_lower(), each, m.npc_buy_room(id)]
	refresh()
