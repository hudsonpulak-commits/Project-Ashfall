class_name HUD
extends Control
## Portrait mobile HUD, built in code. Top: title/coords + minimap. Middle:
## open world (taps fall through to the game). Bottom: message log, current
## action, one switchable panel (Pack / Skills / Bank / Exchange / Menu) and
## the tab bar. Respects the device safe area (notches, gesture bars).

signal request_save()
signal request_reset()
signal request_main_menu()   # 0.3.2
signal zoom_step(delta: int)
signal minimap_tapped(tile: Vector2i)

const MAX_LOG := 6

var player: Player
var world: World

var safe: MarginContainer
var title_label: Label
var coords_label: Label
var minimap: Minimap
var log_box: VBoxContainer
var status_label: Label
var panel_host: PanelContainer
var panels: Dictionary = {}
var current_panel: String = ""
var tab_buttons: Dictionary = {}
var close_button: Button

var inv_slots: Array = []
var bank_pack_slots: Array = []
var bank_slots: Array = []
var bank_grid: GridContainer
var withdraw_qty: int = 1
var skill_rows: Dictionary = {}
var total_label: Label
var exchange_panel: ExchangePanel
var store_panel: StorePanel
var pshop_panel: PlayerShopPanel
var craft_panel: CraftPanel
var report_panel: ReportPanel
var map_panel: MapPanel
var panel_anchor := Vector2i.ZERO   # object the open panel belongs to
var _reset_armed := false
var hp_label: Label                # info line 3: total level + marks (HP / Prayer moved to the bars)
var hp_bar: StatBar
var prayer_bar: StatBar
var energy_bar: StatBar
var pack_actions: HBoxContainer
var worn_row: HBoxContainer
var set_label: Label               # full armour set -> Defence XP bonus line
var style_buttons: Dictionary = {}  # "accurate"/"aggressive" -> Button
var style_hint: Label
var _sel_slot := -1
var bank_tab := BankTabs.ALL     # 0.3.17 bank tab shown (-1 All, 0 main, 1..8 custom)
var bank_arrange := false        # 0.3.17 Arrange mode: taps select / move / swap / file into tabs
var _bank_sel := -1              # container index of the picked bank item
var bank_tab_scroll: ScrollContainer
var bank_tab_row: HBoxContainer
var bank_edit_row: HBoxContainer
var bank_arrange_btn: Button
var prayer_row: HBoxContainer
var multi_row: HBoxContainer
var multi_icon: TextureRect
var multi_label: Label
var prayer_icon: TextureRect
var prayer_label: Label
var prayer_buttons: Dictionary = {}   # buff id -> Button
var prayer_header: Label
var zone_banner: ZoneBanner         # 0.3.1 PK zone skull row + first-crossing warning
var clock_icon: TextureRect
var clock_label: Label
var clock_row: HBoxContainer


func setup(p: Player, w: World) -> void:
	player = p
	world = w
	theme = UIStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	minimap.world = w
	minimap.player = p
	quest_ui = QuestUI.new()   # 0.3.7 giver markers + guidance arrow
	quest_ui.player = p
	quest_ui.world = w
	add_child(quest_ui)
	move_child(quest_ui, 0)
	zone_banner.player = p
	zone_banner.world = w
	exchange_panel.setup(p)
	store_panel.setup(p)
	pshop_panel.setup(p, w)
	Events.player_shop_opened.connect(func(town, slot):
		pshop_panel.open(town, slot)
		panel_anchor = player.tile
		show_panel("pshop"))
	craft_panel.setup(p, w)
	map_panel.setup(p, w)
	Events.town_changed.connect(func(_t): _refresh_title())
	_refresh_title()
	Events.message.connect(_on_message)
	Events.inventory_changed.connect(_refresh_inventory)
	Events.inventory_changed.connect(func(): if current_panel == "quests": refresh_quests())   # 0.3.15 gather counters
	Events.bank_changed.connect(_refresh_bank)
	Events.xp_gained.connect(func(_s, _a): _refresh_skills())
	Events.action_changed.connect(func(t): status_label.text = t)
	Events.bank_opened.connect(func(): show_panel("bank"))
	Events.exchange_opened.connect(func(): _open_at("exchange"))
	Events.shop_opened.connect(func(shop):
		store_panel.shop = shop
		_open_at("store"))
	Events.station_opened.connect(func(st, pos):
		craft_panel.open(st, pos)
		panel_anchor = pos
		show_panel("craft"))
	Events.report_ready.connect(func(t, b):
		report_panel.show_report(t, b)
		show_panel("report"))
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_refresh_inventory()
	_refresh_bank()
	_refresh_skills()


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build() -> void:
	safe = MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore(safe)
	add_child(safe)
	var col := VBoxContainer.new()
	_ignore(col)
	col.add_theme_constant_override("separation", 2)
	safe.add_child(col)

	# --- top bar
	var top := HBoxContainer.new()
	_ignore(top)
	col.add_child(top)
	var info := VBoxContainer.new()
	_ignore(info)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	title_label = Label.new()
	title_label.text = "AshFall · Fenhollow"
	title_label.add_theme_color_override("font_color", UIStyle.ACCENT)
	title_label.add_theme_constant_override("outline_size", 3)
	info.add_child(_ignore(title_label))
	clock_row = HBoxContainer.new()
	_ignore(clock_row)
	clock_row.add_theme_constant_override("separation", 3)
	clock_icon = TextureRect.new()
	clock_icon.custom_minimum_size = Vector2(16, 16)
	clock_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clock_icon.texture = GameData.texture("ui", "icon_sun")
	clock_row.add_child(_ignore(clock_icon))
	clock_label = Label.new()
	clock_label.add_theme_constant_override("outline_size", 3)
	clock_label.add_theme_font_size_override("font_size", 10)
	clock_row.add_child(_ignore(clock_label))
	info.add_child(clock_row)
	coords_label = Label.new()
	coords_label.add_theme_constant_override("outline_size", 3)
	coords_label.add_theme_font_size_override("font_size", 10)
	info.add_child(_ignore(coords_label))
	hp_label = Label.new()
	hp_label.add_theme_constant_override("outline_size", 3)
	hp_label.add_theme_font_size_override("font_size", 10)
	info.add_child(_ignore(hp_label))
	prayer_row = HBoxContainer.new()
	_ignore(prayer_row)
	prayer_icon = TextureRect.new()
	prayer_icon.custom_minimum_size = Vector2(16, 16)
	prayer_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prayer_row.add_child(_ignore(prayer_icon))
	prayer_label = Label.new()
	prayer_label.add_theme_constant_override("outline_size", 3)
	prayer_label.add_theme_font_size_override("font_size", 10)
	prayer_row.add_child(_ignore(prayer_label))
	prayer_row.visible = false
	info.add_child(prayer_row)
	multi_row = HBoxContainer.new()
	_ignore(multi_row)
	var mi := TextureRect.new()
	multi_icon = mi
	mi.custom_minimum_size = Vector2(16, 16)
	mi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mi.texture = GameData.texture("ui", "multi_combat")
	multi_row.add_child(_ignore(mi))
	multi_label = Label.new()
	multi_label.add_theme_constant_override("outline_size", 3)
	multi_label.add_theme_font_size_override("font_size", 10)
	multi_label.add_theme_color_override("font_color", Color("#e8843a"))
	multi_row.add_child(_ignore(multi_label))
	multi_row.visible = false
	info.add_child(multi_row)
	zone_banner = ZoneBanner.new()
	add_child(zone_banner)
	zone_banner.attach_row(info)
	# 0.2.4: HP / Prayer / Energy bars beside the minimap (tap Energy = sprint)
	var bars := VBoxContainer.new()
	_ignore(bars)
	bars.add_theme_constant_override("separation", 3)
	top.add_child(bars)
	hp_bar = StatBar.new()
	hp_bar.label = "HP"
	hp_bar.fill_tex = "hp"
	bars.add_child(hp_bar)
	prayer_bar = StatBar.new()
	prayer_bar.label = "Prayer"
	prayer_bar.fill_tex = "prayer"
	bars.add_child(prayer_bar)
	energy_bar = StatBar.new()
	energy_bar.label = "Energy"
	energy_bar.fill_tex = "energy"
	energy_bar.custom_minimum_size = Vector2(84, 30)   # the sprint toggle: a bigger touch target
	energy_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	energy_bar.tapped.connect(func():
		Events.say(player.set_sprint(not player.sprint))
		_refresh_bars())
	bars.add_child(energy_bar)
	var right := VBoxContainer.new()
	_ignore(right)
	top.add_child(right)
	minimap = Minimap.new()
	minimap.tapped_tile.connect(func(t): minimap_tapped.emit(t))
	right.add_child(minimap)
	var zoom_row := HBoxContainer.new()
	_ignore(zoom_row)
	right.add_child(zoom_row)
	for z in [["-", -1], ["+", 1]]:
		var b := Button.new()
		b.text = z[0]
		b.custom_minimum_size = Vector2(40, 22)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): zoom_step.emit(z[1]))
		zoom_row.add_child(b)

	# --- open world area
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_ignore(spacer))

	# --- log + status
	log_box = VBoxContainer.new()
	_ignore(log_box)
	log_box.add_theme_constant_override("separation", 0)
	col.add_child(log_box)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#9ad070"))
	status_label.add_theme_constant_override("outline_size", 3)
	col.add_child(_ignore(status_label))

	# --- panel host
	panel_host = PanelContainer.new()
	panel_host.visible = false
	panel_host.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(panel_host)
	panels["pack"] = _build_pack_panel()
	panels["skills"] = _build_skills_panel()
	panels["bank"] = _build_bank_panel()
	exchange_panel = ExchangePanel.new()
	panels["exchange"] = exchange_panel
	store_panel = StorePanel.new()
	panels["store"] = store_panel
	pshop_panel = PlayerShopPanel.new()
	panels["pshop"] = pshop_panel
	craft_panel = CraftPanel.new()
	craft_panel.set_meta("hud", self)
	panels["craft"] = craft_panel
	report_panel = ReportPanel.new()
	report_panel.set_meta("hud", self)
	report_panel.setup()
	panels["report"] = report_panel
	map_panel = MapPanel.new()
	map_panel.set_meta("hud", self)
	panels["map"] = map_panel
	panels["menu"] = _build_menu_panel()
	panels["quests"] = _build_quest_panel()
	panels["dialog"] = _build_dialog_panel()
	panels["prayer"] = _build_prayer_panel()
	for k in panels.keys():
		panels[k].visible = false
		panel_host.add_child(panels[k])
	# 0.3.0: a close button on every panel (the shop panels cover the door)
	close_button = Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(26, 22)
	close_button.add_theme_font_size_override("font_size", 10)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(func(): show_panel(""))
	panel_host.add_child(close_button)

	# --- tab bar
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_STOP
	tabs.add_theme_constant_override("separation", 2)
	col.add_child(tabs)
	# no Bank tab: the bank opens only by walking to a bank chest
	for t in [["pack", "Pack"], ["skills", "Skills"], ["quests", "Quests"], ["map", "Map"], ["menu", "Menu"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = t[0]
		b.pressed.connect(func(): toggle_panel(key))
		tabs.add_child(b)
		tab_buttons[key] = b


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UIStyle.ACCENT)
	return l


func _grid(cols: int, n: int, store: Array, on_tap: Callable) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 2)
	for i in n:
		var s := ItemSlot.new()
		var idx := i
		s.pressed.connect(func(): on_tap.call(idx))
		g.add_child(s)
		store.append(s)
	return g


func _build_pack_panel() -> Control:
	var v := VBoxContainer.new()
	v.add_child(_header("Pack  (tap: pick up + actions · tap a slot: move/swap)"))
	var g := _grid(6, 24, inv_slots, _on_pack_tap)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	pack_actions = HBoxContainer.new()
	pack_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(pack_actions)
	worn_row = HBoxContainer.new()
	worn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(worn_row)
	set_label = UIKit.label("", 8, UIStyle.TEXT_DIM)
	set_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(set_label)
	return v


## Worn gear: one small button per slot (tap to take it off).
func _refresh_worn() -> void:
	if worn_row == null:
		return
	UIKit.clear(worn_row)
	worn_row.add_child(UIKit.label("Worn:", 8, UIStyle.TEXT_DIM))
	for slot in Player.SLOTS:
		var id: String = player.equipment.get(slot, "")
		var txt: String = slot.capitalize() if id == "" else GameData.item_name(id).left(9)
		if slot == "ammo" and id != "":
			txt = "%s x%d" % [GameData.item_name(id).get_slice(" ", 0).left(6), player.ammo_qty]
		var b := UIKit.button(txt, func():
			if id != "":
				var why := player.unequip(slot)
				Events.say(why if why != "" else "You take off the %s." % GameData.item_name(id).to_lower())
				_refresh_worn(), 0, 18)
		b.add_theme_font_size_override("font_size", 7)
		b.disabled = id == ""
		worn_row.add_child(b)
	worn_row.add_child(UIKit.label(Combat.equip_stat_line(player.combat_atk(), player.combat_def()), 7, UIStyle.TEXT_DIM))
	if set_label:
		var sb := Combat.set_bonus(player.armour_ids())
		if int(sb["tier"]) > 0:
			set_label.text = "Full %s set: Defence XP x%s" % [sb["name"], _fmt_mult(float(sb["mult"]))]
			set_label.add_theme_color_override("font_color", UIStyle.ACCENT)
		else:
			set_label.text = "No set bonus (helm, body, legs and shield of one tier)"
			set_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)


static func _fmt_mult(m: float) -> String:
	var t := "%.2f" % m
	while t.ends_with("0"):
		t = t.left(t.length() - 1)
	return t.trim_suffix(".")


func _refresh_pack_actions() -> void:
	for k in inv_slots.size():   # 0.3.17 gold frame on the picked-up item
		inv_slots[k].set_selected(k == _sel_slot and player.inventory.slots[k] != null)
	if pack_actions == null:
		return
	UIKit.clear(pack_actions)
	if _sel_slot < 0 or player.inventory.slots[_sel_slot] == null:
		_sel_slot = -1
		return
	var i := _sel_slot
	var id: String = player.inventory.slots[i]["id"]
	var it := GameData.item(id)
	pack_actions.add_child(UIKit.label(GameData.item_name(id).left(16) + ":", 8, UIStyle.ACCENT))
	if int(it.get("heals", 0)) > 0:
		pack_actions.add_child(UIKit.button("Eat", func():
			var h := player.eat_slot(i, Tick.tick_count)
			Events.say("You eat the %s. +%d HP." % [GameData.item_name(id).to_lower(), h])
			Events.player_hp_changed.emit(player.hp, player.max_hp())
			_sel_slot = -1
			_refresh_pack_actions(), 40))
	if int(it.get("bury_xp", 0)) > 0:
		pack_actions.add_child(UIKit.button("Bury", func():
			var xp := player.bury_slot(i)
			Events.say("You bury the bones. +%d Prayer XP." % xp)
			_sel_slot = -1
			_refresh_pack_actions(), 40))
	if str(it.get("gear", {}).get("slot", "")) in Player.SLOTS:
		pack_actions.add_child(UIKit.button("Equip", func():
			var why := player.equip_slot(i)
			Events.say(why if why != "" else "You equip the %s." % GameData.item_name(id).to_lower())
			_sel_slot = -1
			_refresh_pack_actions()
			_refresh_worn(), 44))
	if id == "flint" or (FireRules.is_log(id) and player.inventory.count("flint") > 0):
		pack_actions.add_child(UIKit.button("Light", func():   # 0.3.6 flint on a log
			var lg := id if FireRules.is_log(id) else FireRules.best_log(player.inventory)
			var why := FireRules.light(player, world, lg)
			Events.say(why if why != "" else "You strike the flint and the %s catches. A cooking fire burns." % GameData.item_name(lg).to_lower())
			Events.inventory_changed.emit()
			_sel_slot = -1
			_refresh_pack_actions(), 40))
	for tl in Interactions.PACK_STATIONS.keys():   # 0.4.0 Fletch (knife) / Sew (needle)
		var st_id: String = tl
		if player.inventory.count(st_id) > 0 and (id == st_id or pack_station_for(st_id, id) == st_id):
			pack_actions.add_child(UIKit.button("Fletch" if st_id == "knife" else "Sew", func():
				_sel_slot = -1
				_refresh_pack_actions()
				open_pack_craft(st_id, "" if id == st_id else id), 44))
	pack_actions.add_child(UIKit.button("Drop", func():
		player.drop_slot(i, Tick.tick_count)
		_sel_slot = -1
		_refresh_pack_actions(), 40))


func _build_skills_panel() -> Control:
	var v := VBoxContainer.new()
	total_label = _header("Skills")
	v.add_child(total_label)
	# combat style: which skill your damage trains (big touch targets)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_theme_constant_override("separation", 6)
	for st in ["accurate", "aggressive"]:
		var style: String = st
		var b := UIKit.button("", func():
			player.set_style(style)
			Events.say("Combat style: %s (%s XP)." % [Combat.style_label(style), GameData.skill_by_id[Combat.style_skill(style)]["name"]])
			_refresh_skills(), 160, 34)
		b.toggle_mode = true
		sr.add_child(b)
		style_buttons[style] = b
	v.add_child(sr)
	style_hint = UIKit.label("", 8, UIStyle.TEXT_DIM)
	style_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(style_hint)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 3)
	v.add_child(g)
	for s in GameData.skills:
		var row := VBoxContainer.new()
		row.custom_minimum_size = Vector2(160, 0)
		row.add_theme_constant_override("separation", 1)
		var l := Label.new()
		row.add_child(l)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color("#2a2418")
		bar_bg.custom_minimum_size = Vector2(150, 3)
		var bar := ColorRect.new()
		bar.color = Color(s.get("color", "#e8c050"))
		bar.size = Vector2(0, 3)
		bar_bg.add_child(bar)
		row.add_child(bar_bg)
		var tr := UIKit.label("", 7, UIStyle.TEXT_DIM)   # 0.3.7 session XP tracker
		row.add_child(tr)
		g.add_child(row)
		skill_rows[s["id"]] = [l, bar, tr]
	var pb := UIKit.button("Prayers  >", func(): show_panel("prayer"), 160, 34)
	pb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pb)
	return v


## Prayer: big buttons, one per buff (locked ones show their level).
func _build_prayer_panel() -> Control:
	var v := VBoxContainer.new()
	prayer_header = _header("Prayer")
	v.add_child(prayer_header)
	var sc := UIKit.scroll(230)
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	sc.add_child(g)
	for b in Prayer.buffs():
		var id: String = b["id"]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(168, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.icon = GameData.texture("ui", str(b.get("icon", "prayer_def")))
		btn.expand_icon = false
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 8)
		btn.clip_text = true
		btn.pressed.connect(func():
			var lvl := player.skills.level("prayer")
			if Prayer.is_active(player.prayer) and player.prayer["id"] == id:
				Prayer.deactivate(player.prayer)
				Events.say("You end %s." % b["name"])
			else:
				var why := Prayer.activate(player.prayer, id, lvl)
				Events.say(why if why != "" else "You call on %s (%d s at full points)." % [b["name"], int(round(Prayer.duration_ticks(lvl, id) * 0.6))])
			_refresh_prayer_panel())
		g.add_child(btn)
		prayer_buttons[id] = btn
	var back := UIKit.button("< Skills", func(): show_panel("skills"), 100, 28)
	v.add_child(back)
	return v


func _refresh_prayer_panel() -> void:
	var lvl := player.skills.level("prayer")
	var pts := Prayer.points(player.prayer, lvl)
	prayer_header.text = "Prayer %d  -  %d/%d points  -  bury bones to refill" % [lvl, int(ceil(pts)), int(Prayer.max_points(lvl))]
	var active := Prayer.is_active(player.prayer)
	for b in Prayer.buffs():
		var btn: Button = prayer_buttons[b["id"]]
		var locked := lvl < int(b["level"])
		var mine: bool = active and player.prayer.get("id", "") == b["id"]
		var pct := int(round(float(b["value"]) * 100))
		var eff: String = {"def": "foes -%d%% acc", "dmg": "+%d%% damage", "acc": "+%d%% accuracy", "gather": "+%d%% gathering"}.get(str(b["effect"]), "%d%%") % pct
		var state := "Lv %d  %s/t" % [int(b["level"]), str(b.get("drain", 1.0))]
		if mine:
			state = "ON %ds - tap: stop" % int(ceil(Prayer.ticks_left(player.prayer, lvl) * 0.6))
		btn.text = "%s\n%s  %s" % [b["name"], eff, state]
		btn.disabled = locked or (active and not mine) or (not active and pts < 1.0)


func _build_bank_panel() -> Control:
	var v := VBoxContainer.new()
	var hdr := HBoxContainer.new()
	v.add_child(hdr)
	var title := _header("Bank chest")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title)
	for q in [1, 10, -1]:
		var b := Button.new()
		b.text = "x%d" % q if q > 0 else "All"
		b.toggle_mode = true
		b.button_pressed = q == 1
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 22)
		var qq: int = q
		b.pressed.connect(func():
			withdraw_qty = qq
			for c in hdr.get_children():
				if c is Button and c.toggle_mode:
					c.button_pressed = c == b)
		hdr.add_child(b)
	var dep := Button.new()
	dep.text = "Deposit all"
	dep.focus_mode = Control.FOCUS_NONE
	dep.pressed.connect(func():
		if not _bank_in_reach():
			return
		var n := player.deposit_all(false)
		Events.say("You deposit %d item%s." % [n, "" if n == 1 else "s"]))
	hdr.add_child(dep)
	bank_arrange_btn = Button.new()
	bank_arrange_btn.text = "Arrange"
	bank_arrange_btn.name = "BankArrange"
	bank_arrange_btn.toggle_mode = true
	bank_arrange_btn.focus_mode = Control.FOCUS_NONE
	bank_arrange_btn.pressed.connect(func():
		bank_arrange = bank_arrange_btn.button_pressed
		_bank_sel = -1
		_refresh_bank())
	var arow := HBoxContainer.new()   # 0.3.17 own row: the header is full on a phone
	arow.add_child(bank_arrange_btn)
	arow.add_child(UIKit.label("  on: tap an item, then a slot to move / swap", 8, UIStyle.TEXT_DIM))
	v.add_child(arow)
	bank_tab_scroll = ScrollContainer.new()   # 0.3.19 phone: 8 tabs scroll instead of overflowing
	bank_tab_scroll.name = "BankTabScroll"
	bank_tab_scroll.custom_minimum_size = Vector2(0, 28)
	bank_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bank_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bank_tab_row = HBoxContainer.new()     # 0.3.17 All / Main / custom tabs / +
	bank_tab_row.add_theme_constant_override("separation", 2)
	bank_tab_scroll.add_child(bank_tab_row)
	v.add_child(bank_tab_scroll)
	bank_edit_row = HBoxContainer.new()
	bank_edit_row.add_theme_constant_override("separation", 2)
	v.add_child(bank_edit_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 76)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	bank_grid = _grid(6, 0, bank_slots, _on_bank_tap)
	bank_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bank_grid)
	v.add_child(_header("Pack  (tap to deposit)"))
	var g := _grid(6, 24, bank_pack_slots, _on_bank_pack_tap)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	return v


func _build_menu_panel() -> Control:
	var v := VBoxContainer.new()
	v.add_child(_header("Menu"))
	var save_b := Button.new()
	save_b.text = "Save now"
	save_b.pressed.connect(func(): request_save.emit())
	v.add_child(save_b)
	var menu_b := Button.new()
	menu_b.text = "Save and exit to main menu"
	menu_b.name = "MainMenuButton"
	menu_b.pressed.connect(func(): request_main_menu.emit())
	v.add_child(menu_b)
	var reset_b := Button.new()
	reset_b.text = "Reset progress"
	reset_b.pressed.connect(func():
		if _reset_armed:
			_reset_armed = false
			reset_b.text = "Reset progress"
			request_reset.emit()
		else:
			_reset_armed = true
			reset_b.text = "Tap again to erase your save")
	v.add_child(reset_b)
	var about := Label.new()
	about.text = "AshFall %s — an original game.\nTap the ground to walk; tap trees, rocks, pools,\nthe dummy, stations, shops, the Exchange board or\na bank chest. Map: see the continent, walk the roads." % ProjectSettings.get_setting("application/config/version", "")
	about.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	about.add_theme_font_size_override("font_size", 10)
	v.add_child(about)
	return v


# ----------------------------------------------------------------- panels --
func toggle_panel(key: String) -> void:
	show_panel("" if current_panel == key else key)


func show_panel(key: String) -> void:
	if key == "bank" and not _bank_in_reach():
		Events.say("Walk to a bank chest and tap it to bank.")
		key = ""
	current_panel = key
	if key == "quests":
		refresh_quests()
	for k in panels.keys():
		panels[k].visible = k == key
	panel_host.visible = key != ""
	for k in tab_buttons.keys():
		tab_buttons[k].button_pressed = k == key
	if key == "exchange":
		exchange_panel.open()
	elif key == "store":
		store_panel.open()
	elif key == "map":
		map_panel.open()
	elif key == "prayer":
		_refresh_prayer_panel()
	elif key == "skills":
		_refresh_skills()
	elif key == "bank":
		_refresh_bank()
	elif key == "pack":
		_refresh_worn()
	_reset_armed = false


## Opens a panel that belongs to the object the player is standing next to.
func _open_at(key: String) -> void:
	var ids := {"exchange": ["exchange_board"]}
	var o: WorldObject = world.find_nearest_object(player.tile, ids.get(key, []), 1)
	panel_anchor = o.pos if o else player.tile
	if key == "store":
		var sb: Dictionary = world.gen.building_for_shop(player.current_town, store_panel.shop)
		panel_anchor = sb["stand"] if not sb.is_empty() else player.tile
	show_panel(key)


## Live HP / Prayer / Energy values (HP on hit/eat/regen, Prayer on drain/bury/regen).
func _refresh_bars() -> void:
	if player == null or hp_bar == null:
		return
	hp_bar.set_values(player.hp, player.max_hp())
	var plv := player.skills.level("prayer")
	prayer_bar.set_values(Prayer.points(player.prayer, plv), Prayer.max_points(plv))
	energy_bar.set_values(player.energy, player.max_energy())
	energy_bar.set_highlight(player.sprint)
	energy_bar.prefix = ">> " if player.sprint else ""
	energy_bar.label = "Run" if player.sprint else "Energy"
	energy_bar.fill = Color("#e8c83a") if player.sprint else Color("#8ab83a")
	energy_bar.queue_redraw()


func _refresh_title() -> void:
	var t: String = world.gen.place_at(player.tile, 8)
	title_label.text = "AshFall · %s" % (world.gen.town_name(t) if t != "" else "the wilds")


func _bank_in_reach() -> bool:
	var chest: WorldObject = world.find_nearest_object(player.tile, ["bank_chest"], 3, bool(player.get("house_owned")))
	if chest != null:
		return true
	var ba: Vector2i = player.get("bank_at") if player.get("bank_at") != null else Vector2i(1 << 20, 0)
	return maxi(absi(ba.x - player.tile.x), absi(ba.y - player.tile.y)) <= 3   # opened at a banker


func _sync_bank_tab_name() -> void:
	if bank_edit_row == null or player == null or not bank_arrange or bank_tab < 1 or bank_tab > player.bank_tabs.size():
		return
	var ed := bank_edit_row.get_node_or_null("BankTabName") as LineEdit
	if ed == null:
		return
	var t := ed.text.strip_edges()
	if t == "" or t == str(player.bank_tabs[bank_tab - 1]["name"]):
		return
	BankTabs.rename(player, bank_tab, t)
	var btn := bank_tab_row.get_node_or_null("BankTab_%d" % (bank_tab + 1))
	if btn is Button:
		btn.text = t.left(7)


func _process(_dt: float) -> void:
	_sync_bank_tab_name()
	if log_box and log_box.get_child_count() > 0:   # 0.3.7.1 no overhead labels over the chat log
		var lr := log_box.get_global_rect()
		var top := lr.end.y
		for c in log_box.get_children():
			top = minf(top, (c as Control).get_global_rect().position.y)
		Overhead.block_rects = [Rect2(Vector2(0, top - 2), Vector2(get_viewport_rect().size.x, lr.end.y - top + 4))]
	else:
		Overhead.block_rects = []
	if player:
		var ph: String = DayNight.phase()
		var nightish := ph in ["night", "dusk"]
		clock_icon.texture = GameData.texture("ui", "icon_moon" if nightish else "icon_sun")
		clock_label.text = "Day %d  %02d:00  %s" % [Market.game_day() + 1, Market.game_hour(), ph.capitalize()]
		# Keep HUD text bright so night CanvasModulate never makes it unreadable.
		clock_label.add_theme_color_override("font_color", Color("#f0e8c0") if nightish else UIStyle.TEXT)
		coords_label.text = "%d, %d" % [player.tile.x, player.tile.y]
		hp_label.text = "Total %d  Combat %d  %d marks" % [player.skills.total_level(), Combat.combat_level(player.skills), player.inventory.count(GameData.currency)]
		_refresh_bars()
	if player:
		var plv := player.skills.level("prayer")
		if Prayer.is_active(player.prayer):
			var b := Prayer.buff(str(player.prayer["id"]))
			prayer_row.visible = true
			prayer_icon.texture = GameData.texture("ui", str(b.get("icon", "prayer_def")))
			prayer_label.text = "%s %d s" % [b.get("name", ""), int(ceil(Prayer.ticks_left(player.prayer, plv) * 0.6))]
			prayer_label.add_theme_color_override("font_color", Color("#e8e0b0"))
		else:
			prayer_row.visible = false
		if current_panel == "prayer" and Engine.get_process_frames() % 15 == 0:
			_refresh_prayer_panel()
		var zone := CombatRules.zone_at(player.tile)
		var pkz := PkRules.zone_at(player.tile)   # 0.3.1: PK zones are PvP + multi-combat
		var tnow := Tick.tick_count
		var skulled: bool = player.is_skulled(tnow)
		# PK zones: ZoneBanner's skull row names the zone; this row adds the skull timer
		# (and names plain multi-combat zones outside PK land)
		multi_row.visible = (not zone.is_empty() and pkz.is_empty()) or skulled
		if multi_row.visible:
			var txt := ""
			if not zone.is_empty() and pkz.is_empty():
				txt = "Multi-combat: %s" % str(zone.get("name", "zone"))
				multi_icon.texture = GameData.texture("ui", "multi_combat")
			else:
				multi_icon.texture = GameData.texture("ui", "skull")
			if skulled:
				var secs := int(ceil((player.skull_until - tnow) * 0.6))
				txt += ("  " if txt != "" else "") + "Skulled %d:%02d" % [secs / 60, secs % 60]
			multi_label.text = txt
	if current_panel == "bank" and not _bank_in_reach():
		show_panel("")
	if Engine.get_process_frames() % 30 == 0:
		_refresh_title()
	if current_panel == "pshop":
		var pb: Dictionary = world.gen.building_for_shop(pshop_panel.town, "player")
		if pb.is_empty() or not world.gen.is_inside(player.tile, pb):
			show_panel("")
	if current_panel in ["exchange", "store", "craft"] and not (current_panel == "craft" and craft_panel.is_pack()):
		var d := (player.tile - panel_anchor).abs()
		if maxi(d.x, d.y) > 1:
			show_panel("")


func _apply_safe_area() -> void:
	var m := [0, 0, 0, 0]  # left, top, right, bottom in viewport units
	if OS.has_feature("mobile"):
		var safe_r := DisplayServer.get_display_safe_area()
		var win := Vector2(DisplayServer.window_get_size())
		var vp := get_viewport_rect().size
		if win.x > 0 and win.y > 0:
			var k := vp / win
			m = [safe_r.position.x * k.x, safe_r.position.y * k.y, (win.x - safe_r.end.x) * k.x, (win.y - safe_r.end.y) * k.y]
	safe.add_theme_constant_override("margin_left", int(m[0]) + 4)
	safe.add_theme_constant_override("margin_top", int(m[1]) + 4)
	safe.add_theme_constant_override("margin_right", int(m[2]) + 4)
	safe.add_theme_constant_override("margin_bottom", int(m[3]) + 4)


# ---------------------------------------------------------------- refresh --
func _refresh_inventory() -> void:
	_refresh_worn()
	if _sel_slot >= 0 and player.inventory.slots[_sel_slot] == null:
		_sel_slot = -1
		_refresh_pack_actions()
	for i in inv_slots.size():
		inv_slots[i].set_item(player.inventory.slots[i])
		inv_slots[i].set_selected(i == _sel_slot and player.inventory.slots[i] != null)
		bank_pack_slots[i].set_item(player.inventory.slots[i])


func _refresh_bank() -> void:
	var used := []
	for s in player.bank.slots:
		if s != null:
			used.append(s)
	var need := maxi(24, int(ceil((used.size() + 1) / 6.0)) * 6)
	while bank_slots.size() < need:
		var s := ItemSlot.new()
		var idx := bank_slots.size()
		s.pressed.connect(func(): _on_bank_tap(idx))
		bank_grid.add_child(s)
		bank_slots.append(s)
	# bank slots map to container indices of non-empty entries on this tab, in order
	if bank_tab > player.bank_tabs.size():
		bank_tab = BankTabs.ALL
	var map := BankTabs.indices(player, player.bank, bank_tab)
	bank_grid.set_meta("map", map)
	for i in bank_slots.size():
		bank_slots[i].set_item(player.bank.slots[map[i]] if i < map.size() else null)
		bank_slots[i].set_selected(i < map.size() and map[i] == _bank_sel)
	_refresh_bank_tabs()


## 0.3.17 the tab row (All, Main, up to 8 custom, +) and, in Arrange on a custom tab,
## rename / icon-from-picked-item / delete.
func _refresh_bank_tabs() -> void:
	if bank_tab_row == null:
		return
	UIKit.clear(bank_tab_row)
	var entries := [[BankTabs.ALL, "All", ""], [0, "Main", ""]]
	for k in player.bank_tabs.size():
		entries.append([k + 1, str(player.bank_tabs[k]["name"]), str(player.bank_tabs[k]["icon"])])
	for e in entries:
		var tab: int = e[0]
		var b := UIKit.button(str(e[1]).left(7), func(): _on_bank_tab(tab), 0, 22)
		b.name = "BankTab_%d" % (tab + 1)
		b.toggle_mode = true
		b.button_pressed = tab == bank_tab
		b.add_theme_font_size_override("font_size", 8)
		if str(e[2]) != "":
			b.icon = GameData.icon(str(e[2]))
			b.expand_icon = false
		bank_tab_row.add_child(b)
	if player.bank_tabs.size() < BankTabs.MAX:
		var add := UIKit.button("+", func():
			var t := BankTabs.add(player)
			if t > 0:
				bank_tab = t
				Events.say("New bank tab. Arrange: rename it, or pick an item and tap Icon.")
			_refresh_bank(), 22, 22)
		add.name = "BankTabAdd"
		bank_tab_row.add_child(add)
	UIKit.clear(bank_edit_row)
	bank_edit_row.visible = bank_arrange and BANK_TABS_ON
	if bank_tab_scroll:
		bank_tab_scroll.visible = BANK_TABS_ON
	bank_tab_row.visible = BANK_TABS_ON
	if not bank_arrange:
		return
	if bank_tab < 1:
		bank_edit_row.add_child(UIKit.label("Arrange: tap an item, then a slot (move/swap) or a tab (file it).", 7, UIStyle.TEXT_DIM))
		return
	var ed := LineEdit.new()
	ed.name = "BankTabName"
	ed.text = str(player.bank_tabs[bank_tab - 1]["name"])
	ed.max_length = 12
	ed.custom_minimum_size = Vector2(90, 20)
	ed.placeholder_text = "Tab name"
	var tab_now := bank_tab
	# Live rename: a phone keyboard often never sends "submit". Keystrokes emit
	# text_changed. Godot 4.7 does not emit it when `text` is assigned, so
	# _process also copies the field (the QA bot types that way).
	ed.text_changed.connect(func(_t): _sync_bank_tab_name())
	bank_edit_row.add_child(ed)
	var icon_b := UIKit.button("Icon", func():
		if _bank_sel >= 0 and player.bank.slots[_bank_sel] != null:
			BankTabs.set_icon(player, tab_now, str(player.bank.slots[_bank_sel]["id"]))
			_bank_sel = -1
		else:
			Events.say("Pick an item first: its picture becomes the tab's icon.")
		_refresh_bank(), 34, 20)
	icon_b.name = "BankTabIcon"
	bank_edit_row.add_child(icon_b)
	var del_b := UIKit.button("Delete tab", func():
		BankTabs.remove(player, tab_now)
		bank_tab = 0
		Events.say("Tab deleted: its items are back on the main tab.")
		_refresh_bank(), 60, 20)
	del_b.name = "BankTabDelete"
	bank_edit_row.add_child(del_b)


func _on_bank_tab(tab: int) -> void:
	if bank_arrange and _bank_sel >= 0 and player.bank.slots[_bank_sel] != null and tab != BankTabs.ALL:
		var id: String = player.bank.slots[_bank_sel]["id"]
		BankTabs.assign(player, id, tab)
		Events.say("%s filed under %s." % [GameData.item_name(id), "Main" if tab == 0 else str(player.bank_tabs[tab - 1]["name"])])
		_bank_sel = -1
	else:
		bank_tab = tab
	_refresh_bank()


## 0.3.7 "+120 xp this session · 85 to Lv 6"
func skill_tracker_text(id: String) -> String:
	var lvl := player.skills.level(id)
	var gained := int(player.session_xp.get(id, 0))
	var to_next := "max" if lvl >= GameData.max_level else "%d to Lv %d" % [maxi(0, GameData.xp_for_level(lvl + 1) - int(player.skills.xp[id])), lvl + 1]
	return "+%d xp this session · %s" % [gained, to_next]


var quest_ui: QuestUI
var quest_box: VBoxContainer
var influence_label: Label
var quest_rows: Dictionary = {}    # quest id -> Label (tests / QA read colours)
const QUEST_COLORS := {"not_started": Color("#e05050"), "in_progress": Color("#f0d040"), "ready": Color("#f0d040"), "completed": Color("#60c060")}


func _build_quest_panel() -> Control:
	var v := VBoxContainer.new()
	v.add_child(_header("Quest Journal"))
	influence_label = UIKit.label("", 9, UIStyle.ACCENT)
	v.add_child(influence_label)
	quest_box = VBoxContainer.new()
	v.add_child(quest_box)
	Events.quests_changed.connect(refresh_quests)
	return v


var dialog_name: Label
var dialog_text: Label
var dialog_choices: HBoxContainer
var dialog_state: Dictionary = {}   # what's on screen (tests / QA)


func _build_dialog_panel() -> Control:
	var v := VBoxContainer.new()
	dialog_name = _header("")
	v.add_child(dialog_name)
	dialog_text = UIKit.label("", 10, UIStyle.TEXT)
	dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_text.custom_minimum_size = Vector2(320, 0)
	v.add_child(dialog_text)
	dialog_choices = HBoxContainer.new()
	dialog_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_choices.add_theme_constant_override("separation", 8)
	v.add_child(dialog_choices)
	Events.quest_dialog.connect(open_dialog)
	return v


## 0.3.7.1 the NPC dialog (quests.json "dialog" nodes).
func open_dialog(gid: String) -> void:
	var d := QuestSystem.dialog(player, gid)
	dialog_state = d
	dialog_name.text = str(d["name"])
	dialog_text.text = str(d["text"])
	UIKit.clear(dialog_choices)
	for c in d["choices"]:
		var act := str(c.get("action", "close"))
		var b := UIKit.button(str(c.get("label", "OK")), func():
			if str(d["quest"]) != "":
				QuestSystem.choose(player, str(d["quest"]), act)
			dialog_state = {}
			show_panel(""), 110, 34)
		b.name = "Choice_" + str(c.get("label", "OK"))
		dialog_choices.add_child(b)
	show_panel("dialog")


const BANK_TABS_ON := true   # 0.3.19 custom bank tabs on (create, rename, delete, file, save)
var quest_open := ""   # 0.3.17 the one expanded journal entry


func refresh_quests() -> void:
	if quest_box == null or player == null:
		return
	UIKit.clear(quest_box)
	quest_rows.clear()
	influence_label.text = "Influence: %d" % player.influence
	for q in QuestSystem.quests():
		var id: String = q["id"]
		var st := QuestSystem.state(player, id)
		# 0.3.17 collapsed list: name + status; tap to open the details under it
		var open := quest_open == id
		var b := UIKit.button("%s %s  —  %s" % ["v" if open else ">", str(q["name"]), QuestSystem.status_word(player, id)], func():
			quest_open = "" if quest_open == id else id
			refresh_quests(), 320, 26)
		b.name = "Quest_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", QUEST_COLORS.get(st, Color.WHITE))
		quest_box.add_child(b)
		quest_rows[id] = b
		if open:
			var d := UIKit.label("\n".join(QuestSystem.detail_lines(player, id, world.gen if world else null)), 9, UIStyle.TEXT_DIM)
			d.name = "QuestDetail"
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(300, 0)
			quest_box.add_child(d)


func _refresh_skills() -> void:
	total_label.text = "Skills  —  Total %d  ·  Combat %d" % [player.skills.total_level(), Combat.combat_level(player.skills)]
	for id in skill_rows.keys():
		var l: Label = skill_rows[id][0]
		var bar: ColorRect = skill_rows[id][1]
		var lvl := player.skills.level(id)
		l.text = "%s  %d" % [GameData.skill_by_id[id]["name"], lvl]
		l.tooltip_text = "%d xp" % int(player.skills.xp[id])
		bar.size.x = floorf(150.0 * player.skills.progress(id))
		(skill_rows[id][2] as Label).text = skill_tracker_text(id)
	var cur := player.current_style()
	for st in style_buttons.keys():
		var b: Button = style_buttons[st]
		b.text = "%s%s\n%s XP" % ["> " if st == cur else "", Combat.style_label(st), GameData.skill_by_id[Combat.style_skill(st)]["name"]]
		b.set_pressed_no_signal(st == cur)
	if style_hint:
		var w := player.weapon_id()
		style_hint.text = "Weapon: %s (default %s). Defence trains when you're attacked." % [GameData.item_name(w) if w != "" else "fists", Combat.style_label(Combat.default_style(w)).to_lower()]


# ------------------------------------------------------------------- taps --
## 0.4.0 the pack station (knife / needle) used by item a on item b, or "".
func pack_station_for(a: String, b: String) -> String:
	for tl in Interactions.PACK_STATIONS.keys():
		var other := b if a == tl else (a if b == tl else "")
		if other == "" or other == tl:
			continue
		for r in GameData.recipes_for_station(tl):
			if r["in"].has(other):
				return tl
	return ""


func open_pack_craft(st: String, filter: String = "") -> void:
	craft_panel.open(st, player.tile, filter)
	panel_anchor = player.tile
	show_panel("craft")


func _on_pack_tap(i: int) -> void:
	var s = player.inventory.slots[i]
	# 0.3.17 organizing: with an item picked, tap it again to put it down, an empty
	# slot to move it there, another item to swap the two
	if _sel_slot >= 0 and player.inventory.slots[_sel_slot] != null:
		if _sel_slot == i:
			_sel_slot = -1
			_refresh_pack_actions()
			return
		var was_empty: bool = s == null
		var a_id: String = player.inventory.slots[_sel_slot]["id"]
		var st := pack_station_for(a_id, s["id"]) if s != null else ""
		if st != "":      # 0.4.0 knife on a log (needle on a hide...) opens the window
			_sel_slot = -1
			_refresh_pack_actions()
			open_pack_craft(st, s["id"] if Interactions.PACK_STATIONS.has(a_id) else a_id)
			return
		player.inventory.move_slot(_sel_slot, i)
		Events.say("Moved." if was_empty else "Swapped.")
		_sel_slot = -1
		_refresh_pack_actions()
		Events.inventory_changed.emit()
		return
	_sel_slot = i if s != null else -1
	_refresh_pack_actions()
	if s == null:
		return
	var id: String = s["id"]
	var extra := ""
	if s.has("dur"):
		extra = " Wear: %d/%d." % [int(s["dur"]), int(GameData.item(id)["tool"]["durability"])]
	if not GameData.item(id).get("gear", {}).is_empty():
		extra += Combat.gear_note(id)
	Events.say("%s — about %d marks in %s.%s" % [GameData.item_name(id), Market.town(player.current_town).reference_price(id), world.gen.town_name(player.current_town), extra])


func _on_bank_pack_tap(i: int) -> void:
	if not _bank_in_reach():
		return
	var s = player.inventory.slots[i]
	if s == null:
		return
	var id: String = s["id"]
	var n := 0
	# deposit every copy of this item (non-stackables occupy many slots)
	for j in player.inventory.size():
		var t = player.inventory.slots[j]
		if t != null and t["id"] == id:
			n += player.deposit_slot(j)
	Events.say("Deposited %d x %s." % [n, GameData.item_name(id)])


func _on_bank_tap(i: int) -> void:
	if not _bank_in_reach():
		return
	var map: Array = bank_grid.get_meta("map", [])
	if bank_arrange:   # 0.3.17 pick up / put down / move / swap
		var tgt: int = map[i] if i < map.size() else -1
		if _bank_sel < 0:
			_bank_sel = tgt
		elif tgt == _bank_sel:
			_bank_sel = -1
		else:
			if tgt < 0:   # an empty cell: after the last item shown on this tab
				tgt = player.bank.slots.find(null, (map[-1] + 1) if not map.is_empty() else 0)
			if tgt >= 0:
				player.bank.move_slot(_bank_sel, tgt)
			_bank_sel = -1
		_refresh_bank()
		return
	if i >= map.size():
		return
	var q := withdraw_qty if withdraw_qty > 0 else 1 << 30
	var id: String = player.bank.slots[map[i]]["id"]
	var got := player.withdraw(map[i], q)
	if got == 0:
		Events.say("Your pack is full.")
	else:
		Events.say("Withdrew %d x %s." % [got, GameData.item_name(id)])


func _on_message(text: String, kind: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(260, 0)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_font_size_override("font_size", 10)
	if kind == "level":
		l.add_theme_color_override("font_color", UIStyle.ACCENT)
	elif kind == "xp":
		l.add_theme_color_override("font_color", Color("#9ad0f0"))   # 0.3.7 XP lines
	elif kind == "warn":
		l.add_theme_color_override("font_color", Color("#f08a6a"))   # 0.3.1 PK warnings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_box.add_child(l)
	while log_box.get_child_count() > MAX_LOG:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()
	var n := log_box.get_child_count()
	for i in n:
		(log_box.get_child(i) as Label).modulate.a = 0.45 + 0.55 * float(i + 1) / n
