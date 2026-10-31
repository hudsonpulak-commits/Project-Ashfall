class_name ZoneBanner
extends Control
## 0.3.1 zone HUD. While you stand in a PK zone (data/pk_zones.json) a skull
## row shows its name in the info column. The FIRST time you cross into a zone
## a big warning banner ("The Scorch - anyone can attack you") shows for a few
## seconds (remembered in the save: Player.zone_seen); later entries just add
## a chat line. Walking into a named mine (data/mines.json) names it in chat.
## Events.zone_entered / zone_left fire for other systems (PK rules, QA bot).

const BANNER_SECONDS := 4.5

var player: Player
var world: World
var row: HBoxContainer
var label: Label
var banner: PanelContainer
var banner_label: Label
var _in_zone := ""
var _mine_id := ""
var _banner_left := 0.0
var _started := false
var _region := ""                 # 0.3.10 lore region the player stands in
var region_label: Label           # 0.3.10 fading region title ("Lower Ashfen - ...")
var _region_left := 0.0
const REGION_SECONDS := 3.5
const REGION_CONFIDENCE := 0.62   # announce only once well inside (no flicker on the dithered border)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.04, 0.03, 0.92)
	sb.border_color = Color("#e0602a")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	banner.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 6)
	banner.add_child(hb)
	var sk := TextureRect.new()
	sk.texture = GameData.texture("ui", "pk_skull")
	sk.custom_minimum_size = Vector2(32, 32)
	sk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sk)
	banner_label = Label.new()
	banner_label.add_theme_font_size_override("font_size", 13)
	banner_label.add_theme_color_override("font_color", Color("#ffd0a0"))
	banner_label.add_theme_constant_override("outline_size", 3)
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.custom_minimum_size = Vector2(220, 0)
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(banner_label)
	banner.visible = false
	add_child(banner)
	region_label = Label.new()
	region_label.add_theme_font_size_override("font_size", 14)
	region_label.add_theme_color_override("font_color", Color("#f0e6c8"))
	region_label.add_theme_constant_override("outline_size", 4)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	region_label.visible = false
	add_child(region_label)


## The persistent skull row lives in the HUD's info column.
func attach_row(info: Container) -> void:
	row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(16, 16)
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.texture = GameData.texture("ui", "pk_skull")
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	label = Label.new()
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("#ff8a5a"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	row.visible = false
	info.add_child(row)


func banner_showing() -> bool:
	return banner.visible


func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_timed(dt)
	World.pmark("zone_banner", _pt0)


func _process_timed(dt: float) -> void:
	if player == null or world == null:
		return
	var z := world.pk_zone_at(player.tile)
	var zid := str(z.get("id", ""))
	if zid != _in_zone:
		if _in_zone != "":
			var old := _zone_def(_in_zone)
			Events.say(str(old.get("leave_line", "You leave %s." % old.get("name", "the zone"))))
			Events.zone_left.emit(_in_zone)
		_in_zone = zid
		DayNight.set_zone(zid)
		if zid != "":
			_enter(z)
	if row:
		row.visible = zid != ""
		if row.visible:
			label.text = "%s: anyone can attack" % str(z.get("name", "PK zone"))
	var m := world.gen.mine_at(player.tile, 1)
	var mid := str(m.get("id", ""))
	if mid != _mine_id:
		_mine_id = mid
		if mid != "" and _started:
			Events.say("%s (%s)." % [str(m.get("name", mid)), mine_summary(m)])
	_update_region(dt)
	_started = true
	if banner.visible:
		_banner_left -= dt
		banner.modulate.a = clampf(_banner_left / 0.8, 0.0, 1.0)
		var vs := get_viewport_rect().size
		banner.position = Vector2(roundf((vs.x - banner.size.x) / 2.0), roundf(vs.y * 0.24))
		if _banner_left <= 0.0:
			banner.visible = false


## 0.3.10 lore regions: chat line + a fading title on entry.
func _update_region(dt: float) -> void:
	var rm: WorldRegions = world.gen.region_map
	if rm != null and world.den_at(player.tile) == "":
		var b := rm.blend_at(player.tile)
		var rid := str(b[0])
		if rid != _region and (float(b[2]) >= REGION_CONFIDENCE or _region == ""):
			_region = rid
			Events.region_entered.emit(rid)
			if _started:
				show_region(str(rm.def(rid).get("banner", rm.region_name(rid))))
	if region_label.visible:
		_region_left -= dt
		region_label.modulate.a = clampf(_region_left / 0.8, 0.0, 1.0)
		var vs := get_viewport_rect().size
		region_label.size = Vector2(vs.x, 24)
		region_label.position = Vector2(0, roundf(vs.y * 0.17))
		if _region_left <= 0.0:
			region_label.visible = false


func current_region() -> String:
	return _region


func show_region(text: String) -> void:
	region_label.text = text
	region_label.visible = true
	region_label.modulate.a = 1.0
	_region_left = REGION_SECONDS
	Events.say("You enter %s." % text.get_slice(" - ", 0))


func _zone_def(id: String) -> Dictionary:
	for z in GameData.pk_zones.get("zones", []):
		if str(z.get("id", "")) == id:
			return z
	return {}


func _enter(z: Dictionary) -> void:
	var id := str(z.get("id", ""))
	var warning := str(z.get("warning", "%s - anyone can attack you" % z.get("name", "PK zone")))
	if not player.zone_seen.has(id):
		player.zone_seen[id] = true
		show_banner(warning)
		Events.say(warning)
	else:
		Events.say(str(z.get("enter_line", warning)))
	Events.zone_entered.emit(id, warning)


func show_banner(text: String) -> void:
	banner_label.text = text
	banner.visible = true
	banner.modulate.a = 1.0
	banner.reset_size()
	_banner_left = BANNER_SECONDS


## "copper & tin", "iron", ... from a mine's ore weights.
static func mine_summary(m: Dictionary) -> String:
	var ores: Dictionary = m.get("ores", {})
	var keys := ores.keys()
	keys.sort_custom(func(a, b): return float(ores[a]) > float(ores[b]))
	var names := []
	for k in keys:
		var y := str(GameData.object_def(k).get("yield", k))
		names.append(GameData.item_name(y).to_lower().replace(" ore", ""))
	return " & ".join(names)
