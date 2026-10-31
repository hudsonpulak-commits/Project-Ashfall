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
## 0.3.13 art-building wall sprites: id -> [Sprite2D, bottom sort y, art height].
## The walls sprite y-sorts at its bottom edge, so with the player in the first
## floor rows the FRONT wall art covered everything but the head (QA C2 smithy /
## shop). While the player is inside a building its walls sort at the top edge
## instead: the player (and the room's stations) draw over the front wall.
var _walls: Dictionary = {}


func setup(w) -> void:
	world = w
	z_index = 50
	_roof_tex = GameData.texture("buildings", "roof")
	_setup_town_art(w)
	for id in w.gen.building_order:
		var b: Dictionary = w.gen.buildings[id]
		alpha[id] = 1.0
		var r: Node2D
		if b.has("art"):
			r = _setup_art_building(w, b)
		else:
			var rr := _Roof.new()
			rr.b = b
			rr.tex = _roof_tex
			rr.tile = w.tile_px
			r = rr
		r.set("label_text", label_for(b))
		add_child(r)
		_roofs[id] = r
		# gfx audit: signs y-sort on the building's base (not on the z50 roof layer), so an
		# actor walking past in front of the facade draws over the sign
		var s := Sprite2D.new()
		s.name = "Sign_%s" % id
		s.centered = false
		var spos: Vector2 = w.tile_to_pos(b["sign"]) + Vector2(0, -2)
		var rb: Rect2i = b["rect"]
		var base_y: float = float(_walls[id][1]) if _walls.has(id) else float((rb.position.y + rb.size.y) * w.tile_px) - 1.0
		base_y = maxf(base_y, spos.y)
		s.position = Vector2(spos.x, base_y + 0.25)
		s.offset = Vector2(0, spos.y - base_y - 0.25)
		w.entity_layer.add_child(s)
		_signs[id] = s
		_keeper_facing[id] = Facing.new()
	refresh_all()


## 0.3.11 layered town art: the ground decal (curved roads, plaza) and the
## city wall ring (8 octant pieces, each y-sorted by its own base).
func _setup_town_art(w) -> void:
	var ring_def: Dictionary = WorldGen.town_art().get("ring", {})
	for tid in w.gen.town_order + w.gen.village_order:   # 0.3.16 villages with designer art too (Millbrook v1)
		var t: Dictionary = w.gen.towns[tid] if w.gen.towns.has(tid) else w.gen.villages[tid]
		if not t.has("art"):
			continue
		var a: Dictionary = t["art"]
		var org: Vector2 = Vector2(int(t["origin"][0]), int(t["origin"][1])) * float(w.tile_px)
		var tex = load(str(a.get("ground_decal", "")))
		if tex:
			var g := Sprite2D.new()
			g.name = "GroundDecal_%s" % tid
			g.centered = false
			g.texture = tex
			g.position = org
			g.z_index = 2
			w.ground_layer.add_child(g)
		# 0.3.11 v3.1: free y-sorted art (wall rows, round towers, gatehouse walls) and
		# fade sprites (gatehouse roofs) that fade while the player stands in their tiles
		for it in a.get("ysort", []):
			var yt = load(str(it["path"]))
			if yt == null:
				continue
			var ys := Sprite2D.new()
			ys.centered = false
			ys.texture = yt
			var base := float(it.get("base", yt.get_height()))
			ys.position = org + Vector2(float(it["pos"][0]), float(it["pos"][1]) + base - 1.0)
			ys.offset = Vector2(0, -base + 1.0)
			w.entity_layer.add_child(ys)
		for it in a.get("fades", []):
			var ft = load(str(it["path"]))
			if ft == null:
				continue
			var fs := Sprite2D.new()
			fs.name = "GateRoof_%s_%d" % [tid, _gate_roofs.size()]
			fs.centered = false
			fs.texture = ft
			fs.hframes = maxi(1, int(it.get("frames", 1)))   # 0.3.16 animated fades (Millbrook mill sails)
			if fs.hframes > 1:
				_anim_fades.append([fs, float(it.get("fps", 4))])
			fs.position = org + Vector2(float(it["pos"][0]), float(it["pos"][1]))
			var tl := {}
			for q in it.get("tiles", []):
				tl[Vector2i(int(t["origin"][0]) + int(q[0]), int(t["origin"][1]) + int(q[1]))] = true
			_gate_roofs.append([fs, tl])
			add_child(fs)
		var ro: Array = a.get("ring_origin_px", [])
		if ro.size() == 2:
			var segs: Dictionary = ring_def.get("segments", {})
			for k in segs.keys():
				var sg: Dictionary = segs[k]
				var st = load(str(sg["path"]))
				if st == null:
					continue
				var spr := Sprite2D.new()
				spr.name = "Wall_%s_%s" % [tid, k]
				spr.centered = false
				spr.texture = st
				var h := float(sg["size"][1])
				spr.position = org + Vector2(float(ro[0]) + float(sg["offset"][0]), float(ro[1]) + float(sg["offset"][1]) + h - 1.0)
				spr.offset = Vector2(0, -h + 1.0)
				w.entity_layer.add_child(spr)


## 0.3.11 a building drawn from layered art: floor under actors, ground walls
## y-sorted with them (doorway gap), upper storeys + roof in one fade group.
func _setup_art_building(w, b: Dictionary) -> Node2D:
	var d: Dictionary = WorldGen.town_art().get("buildings", {}).get(str(b["art"]), {})
	var r: Rect2i = b["rect"]
	var ph := float(d.get("px", [0, 0])[1])
	var tp: int = w.tile_px
	# 0.3.13 inset_x: the plan may carry an invisible collision rim left/right of the art (Fenhollow)
	var canvas: Vector2 = Vector2(r.position.x * tp + float(d.get("inset_x", 0)), r.position.y * tp - float(d.get("origin_y", 0)))
	var flip := bool(b.get("flip", false))
	var fl := Sprite2D.new()
	fl.centered = false
	fl.texture = load(str(d.get("floor", "")))
	fl.position = canvas
	fl.flip_h = flip
	fl.z_index = 3
	w.ground_layer.add_child(fl)
	var wl := Sprite2D.new()
	wl.name = "Walls_%s" % b["id"]
	wl.centered = false
	wl.texture = load(str(d.get("walls", "")))
	wl.flip_h = flip
	wl.position = Vector2(canvas.x, canvas.y + ph - 1.0)
	wl.offset = Vector2(0, -ph + 1.0)
	w.entity_layer.add_child(wl)
	_walls[b["id"]] = [wl, canvas.y + ph - 1.0, ph]
	# 0.3.14 sprite-bot *_night window layer: drawn over the walls, faded in by DayNight at dusk
	var np_: String = str(d.get("night", ""))
	if np_ != "" and ResourceLoader.exists(np_):
		var nl := Sprite2D.new()
		nl.name = "Night_%s" % b["id"]
		nl.centered = false
		nl.texture = load(np_)
		nl.flip_h = flip
		nl.offset = wl.offset
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		nl.material = mat
		nl.modulate.a = DayNight.lights_energy()
		nl.add_to_group("art_night_layer")
		wl.add_child(nl)
	var fg := _ArtRoof.new()
	fg.b = b
	fg.tile = tp
	fg.canvas = canvas
	for path in d.get("fade", []):
		var s := Sprite2D.new()
		s.centered = false
		s.texture = load(str(path))
		s.flip_h = flip
		s.position = canvas
		fg.add_child(s)
	# 0.4.4 batch_15 roof_night: a full replacement roof crossfaded over the day roof at dusk
	# (normal blend, same art_night_layer fade as the window layer; a child so it fades with the roof)
	var rn: String = str(d.get("roof_night", ""))
	if rn != "" and ResourceLoader.exists(rn) and fg.get_child_count() > 0:
		var rs := Sprite2D.new()
		rs.name = "RoofNight"
		rs.centered = false
		rs.texture = load(rn)
		rs.flip_h = flip
		rs.modulate.a = DayNight.lights_energy()
		rs.add_to_group("art_night_layer")
		fg.get_child(fg.get_child_count() - 1).add_child(rs)
	fg.show_label = not bool(b.get("no_keeper", false))
	# restyle batch 03: windmill sails -- their own layer, never fade, turn around the hub
	var sp_: String = str(d.get("sails", ""))
	if sp_ != "" and ResourceLoader.exists(sp_):
		var sl := _Sails.new()
		sl.name = "Sails_%s" % b["id"]
		sl.centered = false
		sl.texture = load(sp_)
		var hub: Array = d.get("sails_hub", [0, 0])
		var hv := Vector2(float(hub[0]), float(hub[1]))
		if flip:
			hv.x = float(sl.texture.get_width()) - hv.x
		sl.flip_h = flip
		sl.offset = -hv
		sl.position = canvas + hv
		sl.z_index = 1
		sl.add_to_group("art_sails")
		add_child(sl)
	return fg


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
		_roofs[id].set("label_text", label_for(b))
		_roofs[id].queue_redraw()
		_signs[id].texture = GameData.texture("buildings", sign_sprite(b))
		var k = world.object_at_loaded(b["keeper_at"])
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


## 0.3.19 under the roof (inside) it fades out; one tile north of a tall art
## building the roof still covers the player, so it fades to 40% instead.
func _roof_target(id: String, inside: String) -> float:
	if id == inside:
		return 0.0
	var b: Dictionary = world.gen.buildings.get(id, {})
	if _player_behind_roof(b):
		return 0.4
	return 1.0


func _player_behind_roof(b: Dictionary) -> bool:
	if b.is_empty() or not b.has("art") or player == null or not ("tile" in player):
		return false
	var r: Rect2i = b["rect"]
	var t: Vector2i = player.tile
	return t.y == r.position.y - 1 and t.x >= r.position.x and t.x < r.end.x


## A tile whose contents the roof is hiding right now.
func hides(p: Vector2i) -> bool:
	var b: Dictionary = world.gen.building_at(p)
	return not b.is_empty() and world.gen.is_roofed(p, b) and roof_alpha(b["id"]) > 0.5


## Advance the roof fades by dt seconds (also called directly by tests).
## 0.3.11 v3.1 gatehouse roofs: [Sprite2D, {tile: true}] - faded while the player is in the passage
var _roof_from := Vector2i(999999, 999999)   # last tile this view faded for
var _gate_roofs: Array = []
var _anim_fades: Array = []   # [Sprite2D, fps]
var _anim_fade_t := 0.0


func gate_roof_alpha(i: int) -> float:
	return (_gate_roofs[i][0] as Sprite2D).modulate.a


func step(dt: float) -> void:
	var inside := player_building()
	var rate := dt / maxf(0.01, roof_fade_s())
	var pt = player.tile if player != null and "tile" in player else Vector2i(-99999, -99999)
	# A teleport into the open must not leave a roof half-faded from the tile you left.
	# Entering still animates, so a short step does not pop the roof off.
	var jumped := _roof_from.x != 999999 and maxi(absi(pt.x - _roof_from.x), absi(pt.y - _roof_from.y)) > 1
	if player != null and "tile" in player:
		_roof_from = pt
	_anim_fade_t += dt
	for af in _anim_fades:
		var asp: Sprite2D = af[0]
		asp.frame = int(_anim_fade_t * float(af[1])) % asp.hframes
	for gr in _gate_roofs:
		var gs: Sprite2D = gr[0]
		gs.modulate.a = move_toward(gs.modulate.a, 0.0 if (gr[1] as Dictionary).has(pt) else 1.0, rate)
	for wid in _walls:
		var wv: Array = _walls[wid]
		var ws: Sprite2D = wv[0]
		var y0: float = float(wv[1]) - (float(wv[2]) - 2.0 if wid == inside else 0.0)
		if ws.position.y != y0:
			ws.offset.y += ws.position.y - y0
			ws.position.y = y0
	for id in alpha.keys():
		var target := _roof_target(id, inside)
		alpha[id] = target if jumped and target >= 0.999 else move_toward(float(alpha[id]), target, rate)
		_roofs[id].modulate.a = alpha[id]
		_roofs[id].visible = alpha[id] > 0.001


func _process(delta: float) -> void:
	if world == null:
		return
	var d := (1.0 / 60.0) if Tick.fixed_step else delta
	step(minf(d, 1.0 / 30.0))   # 0.3.11 a long frame (first draw of a big art sprite) must not pop the roof
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
			var o = world.object_at_loaded(p)   # 0.3.16 far buildings: don't generate chunks to hide nothing
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
		var k = world.object_at_loaded(b["keeper_at"])
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
			var o = world.object_at_loaded(b["displays"][i])
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
	_bubbles[b["id"]] = [l, Tick.now_ms() + 3500]


func _update_bubbles() -> void:
	for id in _bubbles.keys():
		var e: Array = _bubbles[id]
		if not is_instance_valid(e[0]):
			_bubbles.erase(id)
		elif Tick.now_ms() > int(e[1]) or roof_alpha(id) > 0.5:
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


## 0.3.11 the fade group of a layered-art building (upper storeys + roof as
## child sprites) plus the shop caption.
class _ArtRoof extends Node2D:
	var b: Dictionary
	var tile := 16
	var canvas := Vector2.ZERO
	var label_text := ""
	var show_label := true

	func _draw() -> void:
		if label_text == "" or not show_label:
			return
		var r: Rect2i = b["rect"]
		var f := ThemeDB.fallback_font
		var fs := 7
		var wd := f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := (r.position.x + r.size.x / 2.0) * tile
		var cy := (r.position.y + 0.5) * tile + 3
		draw_rect(Rect2(cx - wd / 2 - 3, cy - 8, wd + 6, 11), Color(0.12, 0.09, 0.06, 0.75))
		draw_string(f, Vector2(cx - wd / 2, cy), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f8ecc8"))


## 0.3.13 tests: the y the building's wall sprite sorts at right now (or NAN).
func walls_sort_y(id: String) -> float:
	return float((_walls[id][0] as Sprite2D).position.y) if _walls.has(id) else NAN


## restyle batch 03: mill sails, slowly turning (never part of a roof fade group).
class _Sails extends Sprite2D:
	var speed := 0.35   # rad/s
	func _process(delta: float) -> void:
		rotation = fposmod(rotation + speed * delta, TAU)
