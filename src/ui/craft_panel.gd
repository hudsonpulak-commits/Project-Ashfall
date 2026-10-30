class_name CraftPanel
extends VBoxContainer
## Recipe picker for a station (anvil, furnace, hearth, workbench).

var player: Player
var world
var station := ""
var station_pos := Vector2i.ZERO
var filter_item := ""     # 0.4.0 knife-on-log: only recipes using this item
const QTY := [1, 5, 10, -1]   # 0.4.0 quantity choice (All = -1) on every station
var _title: Label
var _list: VBoxContainer


func setup(p: Player, w) -> void:
	player = p
	world = w
	add_theme_constant_override("separation", 2)
	_title = UIKit.label("", 11, UIStyle.ACCENT)
	add_child(_title)
	var sc := UIKit.scroll(170)
	add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	sc.add_child(_list)
	player.inventory.changed.connect(func():
		if visible:
			refresh())


func open(st: String, pos: Vector2i, filter: String = "") -> void:
	station = st
	station_pos = pos
	filter_item = filter
	refresh()


func is_pack() -> bool:
	return Interactions.PACK_STATIONS.has(station)


## 0.4.0 the recipes this window lists (pack stations: optionally by input).
func recipes() -> Array:
	var out: Array = []
	for r in GameData.recipes_for_station(station):
		if filter_item != "" and not r["in"].has(filter_item):
			continue
		out.append(r)
	return out


func refresh() -> void:
	var obj: WorldObject = null if is_pack() else world.object_at(station_pos)
	if is_pack():
		_title.text = GameData.skill_by_id[Interactions.PACK_STATIONS[station]]["name"]
		if filter_item != "":
			_title.text += ": " + GameData.item_name(filter_item)
	else:
		_title.text = obj.display_name() if obj else station.capitalize()
	UIKit.clear(_list)
	for r in recipes():
		var out_id: String = r["out"].keys()[0]
		var lvl_ok: bool = player.skills.level(r["skill"]) >= int(r.get("level", 1))
		var row := HBoxContainer.new()
		row.add_child(UIKit.icon(out_id))
		var ins := []
		for k in r["in"].keys():
			ins.append("%d/%d %s" % [player.inventory.count(k), int(r["in"][k]), GameData.item_name(k).to_lower()])
		var fail_tag := ""
		if r.get("fail", {}).has("chance"):   # flat failure rate (iron smelting) is shown up front
			fail_tag = "  %d%% fail" % roundi(float(r["fail"]["chance"]) * 100.0)
		var l := UIKit.label("%s  (%s %d)%s\n%s" % [GameData.item_name(out_id), GameData.skill_by_id[r["skill"]]["name"], int(r["level"]), fail_tag, ", ".join(ins)], 8,
			UIStyle.TEXT if lvl_ok else Color("#e07a5a"))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var can := lvl_ok and Interactions.can_make(player, r)
		var rid: String = r["id"]
		for q in QTY:
			var n: int = q
			var b := UIKit.button("All" if n < 0 else str(n), func(): _make(rid, n), 26, 22)
			b.disabled = not can
			b.name = "q%d" % n
			row.add_child(b)
		_list.add_child(row)


func _make(rid: String, count: int) -> void:
	if is_pack():
		if player.start_pack_recipe(station, rid, count):
			get_meta("hud").show_panel("")
		return
	var obj: WorldObject = world.object_at(station_pos)
	if obj == null:
		return
	if player.start_recipe(world, obj, rid, count):
		get_meta("hud").show_panel("")
