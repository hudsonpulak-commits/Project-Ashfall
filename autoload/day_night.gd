extends Node
## 0.3.1 day/night cycle. One cycle = data/daynight.json cycle_s real seconds
## (default 15 min: 10 day + 5 night) with dusk/dawn lerps. Drives world
## CanvasModulate tint, town lights, HUD clock icon, and the game hour used by
## AI persona schedules. HUD lives on a CanvasLayer so it is never darkened.

signal phase_changed(phase: String)

var modulate: CanvasModulate
var lights_root: Node2D
var _phase := "day"
var _tint := Color.WHITE
var _progress := 0.0          # 0..1 within the current cycle
var _lights_energy := 0.0
var _offset_ticks := 0        # save-friendly phase offset within the cycle
var _built_lights := false


func cfg() -> Dictionary:
	return GameData.daynight_cfg


func ticks_per_cycle() -> int:
	return maxi(1, int(round(float(cfg().get("cycle_s", 900)) / Tick.TICK_SECONDS)))


func day_ticks() -> int:
	return maxi(1, int(round(float(cfg().get("day_s", 600)) / Tick.TICK_SECONDS)))


func night_ticks() -> int:
	return maxi(1, ticks_per_cycle() - day_ticks())


func transition_ticks() -> int:
	return maxi(1, int(round(float(cfg().get("transition_s", 40)) / Tick.TICK_SECONDS)))


## Absolute tick used for phase (Tick.tick_count + saved offset).
func cycle_tick() -> int:
	return Tick.tick_count + _offset_ticks


func cycle_index() -> int:
	return int(cycle_tick() / ticks_per_cycle())


func tick_in_cycle() -> int:
	return posmod(cycle_tick(), ticks_per_cycle())


## 0..23 hour aligned to the visible cycle. hour_at_cycle_start (default 6)
## is the hour at the beginning of the day phase (after dawn).
func hour() -> int:
	var start := int(cfg().get("hour_at_cycle_start", 6))
	var h := start + int(float(tick_in_cycle()) / float(ticks_per_cycle()) * 24.0)
	return posmod(h, 24)


func day_index() -> int:
	# Keep "Day N" in sync with Market when possible; fall back to cycle count.
	return cycle_index()


func phase() -> String:
	return _phase


func tint() -> Color:
	return _tint


func lights_energy() -> float:
	return _lights_energy


func is_night() -> bool:
	return _phase == "night" or _phase == "dusk"


func is_day() -> bool:
	return _phase == "day" or _phase == "dawn"


## 0.3.1 PK zone the player stands in (ZoneBanner -> Events.zone_entered/left).
var _zone := ""


## 0.4.2 underground: inside a den the sky never reaches; fixed den tint, torches lit.
var _den := ""


func set_den(den_id: String) -> void:
	if den_id != _den:
		_den = den_id
		refresh()


func in_den() -> bool:
	return _den != ""


func set_zone(zone_id: String) -> void:
	if zone_id != _zone:
		_zone = zone_id
		refresh()


func setup_world(world: Node2D) -> void:
	# CanvasModulate on the default canvas darkens the world; the HUD sits on
	# CanvasLayer 10 and stays readable. Lights use their own CanvasLayer with
	# follow_viewport so warm glows are not also multiplied by the night tint.
	if modulate and is_instance_valid(modulate):
		modulate.queue_free()
	modulate = CanvasModulate.new()
	modulate.name = "DayNightModulate"
	world.add_child(modulate)
	if lights_root and is_instance_valid(lights_root):
		var parent := lights_root.get_parent()
		if parent:
			parent.queue_free()
		else:
			lights_root.queue_free()
	var layer := CanvasLayer.new()
	layer.name = "DayNightLightsLayer"
	layer.layer = 5
	layer.follow_viewport_enabled = true
	world.get_parent().add_child(layer)
	lights_root = Node2D.new()
	lights_root.name = "DayNightLights"
	layer.add_child(lights_root)
	_built_lights = false
	refresh()


func ensure_lights(world) -> void:
	if _built_lights or world == null or lights_root == null:
		return
	_built_lights = true
	var lc: Dictionary = cfg().get("lights", {})
	var torch_col := Color(str(lc.get("torch_color", "#ffb060")))
	var win_col := Color(str(lc.get("window_color", "#ffd878")))
	var glow_scale := float(lc.get("glow_scale", 1.6))
	# Torches near each town plaza / roads into town
	var n_torch := int(lc.get("torches_per_town", 4))
	for tid in world.gen.town_order:
		var center: Vector2i = world.gen.town_center(tid)
		var offsets := [Vector2i(-6, 0), Vector2i(6, 0), Vector2i(0, -6), Vector2i(0, 6),
			Vector2i(-4, -4), Vector2i(4, 4)]
		for i in mini(n_torch, offsets.size()):
			_add_light(world, center + offsets[i], "torch", torch_col, glow_scale)
	# 0.3.1 walled cities: a torch on the wall either side of every gate
	for t in gate_torch_tiles(world):
		_add_light(world, t, "torch", torch_col, glow_scale)
	# 0.3.1 villages: a couple of torches by the well
	for vid in world.gen.village_order:
		var vs: Vector2i = world.gen.town_spawn(vid)
		var voff := [Vector2i(-3, 0), Vector2i(3, 0)]
		for i in mini(int(GameData.villages_cfg.get("torches_per_village", 2)), voff.size()):
			_add_light(world, vs + voff[i], "torch", torch_col, glow_scale)
	# 0.4.0 Elijah's headstone: candle glow overlay at night
	var hs: Vector2i = world.gen.story_marks.get("elijah_headstone", Vector2i(-99999, 0))
	if hs.x > -90000:
		_add_light(world, hs, "tomb", Color("#d0be91"), glow_scale)
	# 0.4.2 den torches ('T' cells of data/underworld.json rows)
	for did in world.gen.dens.keys():
		for tt in world.gen.dens[did].get("markers", {}).get("T", []):
			_add_light(world, tt, "torch", torch_col, glow_scale)
	# Lit windows on each building facade
	var n_win := int(lc.get("windows_per_building", 2))
	var glass_col := Color(str(lc.get("stained_glass_color", "#ffb8d0")))
	for id in world.gen.building_order:
		for w in window_tiles(world, world.gen.buildings[id], n_win):
			var stained: bool = world.gen.object_id_at(w) == "stained_glass"
			_add_light(world, w, "window", glass_col if stained else win_col, glow_scale * 0.85)


## 0.3.1 walled cities: the wall tiles flanking each gate (torch sconces).
static func gate_torch_tiles(world) -> Array:
	var out: Array = []
	for tid in world.gen.town_order:
		var t: Dictionary = world.gen.towns[tid]
		var gates: Dictionary = t.get("gate_walls", t.get("gates", {}))   # 0.3.8 Highfen: the wall gates, not the bridge ends
		if gates.is_empty() or str(t.get("walls", "")) == "none":
			continue   # 0.3.12 open towns have no gate walls
		var o := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
		for dir in gates.keys():
			var cells: Array = gates[dir]
			if cells.is_empty():
				continue
			var along := Vector2i(1, 0) if str(dir) in ["north", "south"] else Vector2i(0, 1)
			var c0 := o + Vector2i(int(cells[0][0]), int(cells[0][1]))
			var c1 := o + Vector2i(int(cells[-1][0]), int(cells[-1][1]))
			if c1.x < c0.x or c1.y < c0.y:
				var tmp := c0
				c0 = c1
				c1 = tmp
			out.append(c0 - along)
			out.append(c1 + along)
	return out


## 0.3.1: facade tiles that get a lit window at night. Stained-glass windows on
## the facade (churches) light up as they are; otherwise n evenly spaced
## facade tiles, never the door or the sign (0.3.0 put one on the door).
static func window_tiles(world, b: Dictionary, n_win: int) -> Array:
	var r: Rect2i = b["rect"]
	if b.has("art"):   # 0.3.14 layered-art buildings: no legacy glowing window overlay; the art's own windows only
		return []
	var fy := int(b.get("facade_y", r.end.y - 1))
	var out: Array = []
	if world.gen.has_method("object_id_at"):
		for x in range(r.position.x, r.end.x):
			if world.gen.object_id_at(Vector2i(x, fy)) == "stained_glass":
				out.append(Vector2i(x, fy))
	return out   # 0.3.16 Hudson: the legacy orange window overlay is never drawn (only stained glass lights up)


func _add_light(world, tile: Vector2i, kind: String, col: Color, glow_scale: float) -> void:
	var n := Node2D.new()
	n.position = world.tile_to_pos(tile) + Vector2(GameData.tile_size / 2.0, GameData.tile_size / 2.0)
	n.set_meta("kind", kind)
	n.set_meta("base_color", col)
	var spr := Sprite2D.new()
	spr.texture = GameData.texture("ui", "light_%s" % kind)
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate = col
	if kind == "tomb":   # 0.4.0 2-frame overlay drawn over the 32x40 headstone
		spr.hframes = 2
		spr.modulate = Color.WHITE
		spr.position = Vector2(0, -12)
		n.set_meta("anim", 2)
	n.add_child(spr)
	var glow := Sprite2D.new()
	glow.texture = GameData.texture("ui", "light_glow")
	glow.centered = true
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.modulate = Color(col.r, col.g, col.b, 0.55)
	glow.scale = Vector2(glow_scale, glow_scale)
	glow.z_index = -1
	n.add_child(glow)
	n.modulate.a = 0.0
	lights_root.add_child(n)


func refresh() -> void:
	var cyc := ticks_per_cycle()
	var day_t := day_ticks()
	var tr := transition_ticks()
	var t := tick_in_cycle()
	_progress = float(t) / float(cyc)
	var dt: Array = cfg().get("day_tint", [1, 1, 1])
	var nt: Array = cfg().get("night_tint", [0.36, 0.4, 0.7])
	var day_c := Color(float(dt[0]), float(dt[1]), float(dt[2]))
	var night_c := Color(float(nt[0]), float(nt[1]), float(nt[2]))
	var new_phase := "day"
	var tint := day_c
	var lights := 0.0
	if t < day_t:
		# day; dusk in the last transition_s
		if t >= day_t - tr:
			new_phase = "dusk"
			var u := float(t - (day_t - tr)) / float(tr)
			tint = day_c.lerp(night_c, clampf(u, 0.0, 1.0))
			lights = clampf(u, 0.0, 1.0)
		else:
			new_phase = "day"
			tint = day_c
			lights = 0.0
	else:
		# night; dawn in the last transition_s of the cycle
		var nt_i := t - day_t
		var night_len := cyc - day_t
		if nt_i >= night_len - tr:
			new_phase = "dawn"
			var u2 := float(nt_i - (night_len - tr)) / float(tr)
			tint = night_c.lerp(day_c, clampf(u2, 0.0, 1.0))
			lights = 1.0 - clampf(u2, 0.0, 1.0)
		else:
			new_phase = "night"
			tint = night_c
			lights = 1.0
	# 0.3.1: inside a PK zone the embers keep the night readable (data: zone_night_floor)
	if _zone != "":
		var zf: Array = cfg().get("zone_night_floor", {}).get(_zone, [])
		if zf.size() == 3:
			tint = Color(maxf(tint.r, float(zf[0])), maxf(tint.g, float(zf[1])), maxf(tint.b, float(zf[2])))
	if _den != "":
		var dt2: Array = GameData.underworld.get("dens", {}).get(_den, {}).get("tint", [0.6, 0.55, 0.58])
		tint = Color(float(dt2[0]), float(dt2[1]), float(dt2[2]))
		lights = 1.0
	_tint = tint
	_lights_energy = lights
	if new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
	else:
		_phase = new_phase
	if modulate and is_instance_valid(modulate):
		modulate.color = _tint
	_apply_lights()


func _apply_lights() -> void:
	# 0.3.14 art buildings light their own windows (*_night layers), no overlay
	var tree := get_tree()
	if tree:
		for nl in tree.get_nodes_in_group("art_night_layer"):
			nl.modulate.a = _lights_energy
	if lights_root == null or not is_instance_valid(lights_root):
		return
	var e := _lights_energy * float(cfg().get("lights", {}).get("glow_energy_night", 0.9))
	for n in lights_root.get_children():
		n.modulate.a = e
		# subtle flicker on torches only (stable hash, no frame flicker)
		if str(n.get_meta("kind", "")) == "torch" and e > 0.05:
			var flicker := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.012 + n.get_instance_id() * 0.01)
			n.modulate.a = e * flicker


func _process(_dt: float) -> void:
	refresh()


## Jump the cycle so the current phase matches `phase` (tests / QA).
func debug_set_phase(phase: String) -> void:
	var day_t := day_ticks()
	var cyc := ticks_per_cycle()
	var tr := transition_ticks()
	var target := 0
	match phase:
		"day":
			target = tr + 10
		"dusk":
			target = day_t - tr / 2
		"night":
			target = day_t + tr + 10
		"dawn":
			target = cyc - tr / 2
		_:
			target = 0
	_offset_ticks = target - Tick.tick_count
	while _offset_ticks < 0:
		_offset_ticks += cyc
	refresh()


func to_save() -> Dictionary:
	return {"offset_ticks": _offset_ticks, "phase": _phase}


func from_save(d: Dictionary) -> void:
	_offset_ticks = int(d.get("offset_ticks", 0))
	refresh()
