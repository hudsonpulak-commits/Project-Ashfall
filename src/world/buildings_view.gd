class_name BuildingsView
extends Node2D
## 0.3.0 walk-in buildings, the visual half (logic lives in WorldGen + Interactions):
##   - one roof per building over the footprint minus the facade row, drawn
##     above every entity; it fades out over roof_fade_s while the player is on
##     the doorway or inside THAT building, and back in when they leave.
##   - while a roof shows, actors (AI players) and interior objects under it are
##     hidden (they'd otherwise poke through at the facade).
##   - shop signs on the facade beside the door, keeper facing + idle, speech
##     bubbles, and the items shown on player-shop display stands.
## No scene change: everything lives on the same open-world map.

var world
var player: Node2D = null
var alpha: Dictionary = {}            # building id -> current roof alpha (1 = opaque)
var _roofs: Dictionary = {}           # building id -> Node2D (draws the roof)
var _signs: Dictionary = {}           # building id -> Sprite2D
var _bubbles: Dictionary = {}         # building id -> [Label, expires_at_ms]
var _keeper_facing: Dictionary = {}   # building id -> Facing
var _shop_version := -1
var _roof_tex: Texture2D


func setup(w) -> void:
	world = w
	z_index = 50
	_roof_tex = GameData.texture("buildings", "roof")
	for id in w.gen.building_order:
		var b: Dictionary = w.gen.buildings[id]
		alpha[id] = 1.0
		var r := _Roof.new()
		r.b = b
		r.tex = _roof_tex
		r.tile = w.tile_px
		r.label_text = label_for(b)
		add_child(r)
		_roofs[id] = r
		var s := Sprite2D.new()
		s.centered = false
		s.position = w.tile_to_pos(b["sign"]) + Vector2(0, -2)
		s.z_index = 1
		add_child(s)
		_signs[id] = s
		_keeper_facing[id] = Facing.new()
	refresh_all()


static func roof_fade_s() -> float:
	return float(GameData.buildings_cfg.get("roof_fade_s", 0.2))


## Roof caption: the shop's name (player shop: "For sale" / "<name>'s Shop").
func label_for(b: Dictionary) -> String:
	if b.is_empty():
		return ""
	if b["kind"] == "player_house":   # 0.3.8
		return "Your house" if _house_owned() else "Townhouse for sale · %d marks" % Player.house_price()
	if b["kind"] == "player":
		var ps = Market.player_shop(b["town"])
		return ps.title() if ps.owned else "For sale · %d marks" % PlayerShop.building_price()
	return str(b["name"])


func _house_owned() -> bool:
	return player != null and player is Player and player.house_owned


func sign_sprite(b: Dictionary) -> String:
	if b["kind"] == "player_house":
		return "sign_house" if _house_owned() else "sign_forsale"
	if b["kind"] == "player":
		return "sign_player" if Market.player_shop(b["town"]).owned else "sign_forsale"
	if b["kind"] == "smithy":
		return str(GameData.buildings_cfg.get("smithy", {}).get("sign", b["sign_sprite"]))
	if b["kind"] == "cookhouse":
		return str(GameData.buildings_cfg.get("cookhouse", {}).get("sign", b["sign_sprite"]))
	return str(b["sign_sprite"])


func keeper_sprite(b: Dictionary) -> String:
	if b["kind"] == "player_house":
		return "keeper_estate"
	if b["kind"] == "player":
		return "keeper_player" if Market.player_shop(b["town"]).owned else "keeper_estate"
	return str(b["keeper_sprite"])


func keeper_name(b: Dictionary) -> String:
	if b["kind"] == "player" and Market.player_shop(b["town"]).owned:
		return str(GameData.buildings_cfg.get("owned_keeper", "Your assistant"))
	return str(b["keeper"])


## Re-read ownership / names / signs (after buying a shop or loading a save).
func refresh_all() -> void:
	for id in _roofs.keys():
		var b: Dictionary = world.gen.buildings[id]
		_roofs[id].label_text = label_for(b)
		_roofs[id].queue_redraw()
		_signs[id].texture = GameData.texture("buildings", sign_sprite(b))
		var k = world.object_at(b["keeper_at"])
		if k and k.view and is_instance_valid(k.view):
			world.apply_keeper_sprite(k.view, keeper_sprite(b))
	_shop_version = -1


## Which building (id) the player counts as inside, else "".
func player_building() -> String:
	if player == null:
		return ""
	var b: Dictionary = world.gen.building_at(player.tile)
	if not b.is_empty() and world.gen.is_inside(player.tile, b):
		return b["id"]
	# 0.3.1: walking out, the logical tile is already outside while the sprite
	# is still in the doorway; keep the roof off until the feet are out too
	# (the roof fading back in over the head read as a blended sprite, QA C2).
	if "prev_tile" in player and player.prev_tile != player.tile and player.has_method("foot_px") \
			and player.position.distance_to(player.foot_px(player.tile)) > 1.0:
		var pt: Vector2i = player.prev_tile
		var b2: Dictionary = world.gen.building_at(pt)
		if not b2.is_empty() and world.gen.is_inside(pt, b2):
			return b2["id"]
	return ""


func roof_alpha(id: String) -> float:
	return float(alpha.get(id, 1.0))


## A tile whose contents the roof is hiding right now.
func hides(p: Vector2i) -> bool:
	var b: Dictionary = world.gen.building_at(p)
	return not b.is_empty() and world.gen.is_roofed(p, b) and roof_alpha(b["id"]) > 0.5


## Advance the roof fades by dt seconds (also called directly by tests).
func step(dt: float) -> void:
	var inside := player_building()
	var rate := dt / maxf(0.01, roof_fade_s())
	for id in alpha.keys():
		var target := 0.0 if id == inside else 1.0
		alpha[id] = move_toward(float(alpha[id]), target, rate)
		_roofs[id].modulate.a = alpha[id]
		_roofs[id].visible = alpha[id] > 0.001


func _process(delta: float) -> void:
	if world == null:
		return
	step(delta)
	_apply_hiding()
	_update_keepers()
	_update_displays()
	_update_bubbles()


## Actors (not the player) and interior objects under a showing roof are hidden.
func _apply_hiding() -> void:
	for a in get_tree().get_nodes_in_group("actors"):
		if a == player or not ("tile" in a):
			continue
		a.visible = not hides(a.tile)
	for id in world.gen.building_order:
		var b: Dictionary = world.gen.buildings[id]
		var show: bool = roof_alpha(id) <= 0.5
		for p in _interior_objects(b):
			var o = world.object_at(p)
			if o and o.view and is_instance_valid(o.view):
				o.view.visible = show and (o.sprite_id(world.tick) != "" or bool(o.def().get("keeper", false)))


func _interior_objects(b: Dictionary) -> Array:
	if not b.has("_objs"):
		var out: Array = []
		var r: Rect2i = b["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var p := Vector2i(x, y)
				if world.gen.is_roofed(p, b) and world.gen._town_objects.has(p):
					out.append(p)
		b["_objs"] = out
	return b["_objs"]


## Keepers face the customer (hysteresis, so a jittery approach doesn't flicker).
func _update_keepers() -> void:
	if player == null:
		return
	for id in world.gen.building_order:
		if roof_alpha(id) > 0.5:
			continue
		var b: Dictionary = world.gen.buildings[id]
		var k = world.object_at(b["keeper_at"])
		if k == null or k.view == null or not is_instance_valid(k.view):
			continue
		var f: Facing = _keeper_facing[id]
		var target: Vector2i = player.tile
		for a in get_tree().get_nodes_in_group("actors"):   # an AI at the counter outranks a browsing player
			if a != player and "tile" in a and a.tile == b["stand"]:
				target = a.tile
		f.observe(target.x - (b["keeper_at"] as Vector2i).x, Tick.tick_count)
		(k.view as Sprite2D).flip_h = f.left


## Player-shop stands show what's on them (icon, small; "x12" for stacks).
func _update_displays() -> void:
	var v := PlayerShop.version
	if v == _shop_version:
		return
	_shop_version = v
	for id in world.gen.building_order:
		var b: Dictionary = world.gen.buildings[id]
		if b["kind"] != "player":
			continue
		var ps = Market.player_shop(b["town"])
		for i in b["displays"].size():
			var o = world.object_at(b["displays"][i])
			if o == null or o.view == null or not is_instance_valid(o.view):
				_shop_version = -1        # view not built yet: try again next frame
				continue
			var spr: Sprite2D = o.view
			var icon: Sprite2D = spr.get_node_or_null("Item")
			if icon == null:
				icon = Sprite2D.new()
				icon.name = "Item"
				icon.scale = Vector2.ONE   # full 16 px item art: readable at zoom 2-3
				spr.add_child(icon)
			var slot = ps.slots[i] if i < ps.slots.size() else null
			icon.visible = slot != null
			if slot != null:
				icon.texture = GameData.icon(str(slot["item"]))
				icon.position = Vector2(0, -18)


## The keeper says a line: chat + a bubble over their head for a few seconds.
func keeper_say(b: Dictionary, line: String) -> void:
	Events.say("%s: \"%s\"" % [keeper_name(b), line], "npc")
	var old = _bubbles.get(b["id"])
	if old and is_instance_valid(old[0]):
		old[0].queue_free()
	# drawn at 4x and scaled down: crisp at every integer zoom (a 6 px font
	# scaled up by the camera blurs); grows UP from above the keeper's head
	const K := 4.0
	var l := Label.new()
	l.text = line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(80 * K, 0)
	l.add_theme_font_size_override("font_size", int(5 * K))
	l.add_theme_color_override("font_color", Color("#2a2018"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f8f0d8")
	sb.set_border_width_all(int(K))
	sb.border_color = Color("#3a2a18")
	sb.set_content_margin_all(2 * K)
	sb.set_corner_radius_all(int(2 * K))
	l.add_theme_stylebox_override("normal", sb)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 3
	l.scale = Vector2.ONE / K
	add_child(l)
	l.reset_size()
	var sz := l.get_combined_minimum_size() / K
	l.position = (world.tile_foot(b["keeper_at"]) + Vector2(-sz.x / 2.0, -26 - sz.y)).round()
	_bubbles[b["id"]] = [l, Time.get_ticks_msec() + 3500]


func _update_bubbles() -> void:
	for id in _bubbles.keys():
		var e: Array = _bubbles[id]
		if not is_instance_valid(e[0]):
			_bubbles.erase(id)
		elif Time.get_ticks_msec() > int(e[1]) or roof_alpha(id) > 0.5:
			e[0].queue_free()
			_bubbles.erase(id)


class _Roof extends Node2D:
	var b: Dictionary
	var tex: Texture2D
	var tile := 16
	var label_text := ""

	func _draw() -> void:
		var r: Rect2i = b["rect"]
		var fy: int = b["facade_y"]
		var y0 := r.position.y if fy != r.position.y else r.position.y + 1
		var y1 := r.end.y - 1 if fy == r.end.y - 1 else r.end.y      # exclusive
		var tint := Color(str(b["roof"]))
		var rows := y1 - y0
		var mid_row := y0 + rows / 2
		for y in range(y0, y1):
			for x in range(r.position.x, r.end.x):
				var px := 0 if x == r.position.x else (2 if x == r.end.x - 1 else 1)
				# top edge / ridge / eave rows use their nine-patch row; plain rows use shingles only
				var src_y := 4
				if y == y0:
					src_y = 0
				elif y == y1 - 1:
					src_y = 32
				elif y == mid_row:
					src_y = 16
				draw_texture_rect_region(tex, Rect2(x * tile, y * tile, tile, tile), Rect2(px * 16, src_y, 16, 16), tint)
		# eave overhang: a few px of roof shadow over the facade top
		var eave_y := (y1 * tile) if fy == r.end.y - 1 else (y0 * tile - 3)
		draw_rect(Rect2(r.position.x * tile, eave_y, r.size.x * tile, 3), Color(0, 0, 0, 0.35))
		if label_text != "":
			var f := ThemeDB.fallback_font
			var fs := 7
			var w := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var cx := (r.position.x + r.size.x / 2.0) * tile
			var cy := (y0 + rows / 2.0) * tile + 3
			draw_rect(Rect2(cx - w / 2 - 3, cy - 8, w + 6, 11), Color(0.12, 0.09, 0.06, 0.75))
			draw_string(f, Vector2(cx - w / 2, cy), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f8ecc8"))
