class_name World
extends Node2D
## Owns the world: chunk data cache (for logic/pathing/AI), streamed chunk
## visuals around the camera focus, world-object state (depletion/respawn),
## and a y-sorted entity layer that actors are parented to.
##
## Rendering: one TileMapLayer per visible chunk using a TileSet built at
## runtime from data/sprites.json (so swapping a tile PNG needs no code).

signal object_changed(obj: WorldObject)

const CHUNK := WorldGen.CHUNK
const VIEW_RADIUS := 2          # chunks rendered around focus (5x5)
const UNLOAD_RADIUS := 3        # hysteresis so walking along a border doesn't thrash
const DATA_KEEP_RADIUS := 6     # chunk *data* kept around (AI/pathing)
const BUILDS_PER_FRAME := 2

var gen: WorldGen
var tile_px: int = 16
var chunks: Dictionary = {}          # Vector2i -> ChunkData
var chunk_views: Dictionary = {}     # Vector2i -> Node2D
var depleted: Dictionary = {}        # Vector2i -> respawn tick (authoritative)
var tick: int = 0

var ground_layer: Node2D
var entity_layer: Node2D             # y-sorted: objects + actors
var _tileset: TileSet
var _build_queue: Array = []
var _focus_chunk := Vector2i(999999, 999999)
var _animated: Array = []            # [Sprite2D, frames, fps]
var _anim_time := 0.0
var _mini_tex: Dictionary = {}       # Vector2i -> ImageTexture (minimap)
var ground: GroundItems              # items lying on tiles
var enemies: EnemyManager            # creature camps
var buildings_view: BuildingsView    # 0.3.0 roofs, signs, keepers, displays


func setup(world_seed: int) -> void:
	tile_px = GameData.tile_size
	gen = WorldGen.new(world_seed)
	ground_layer = Node2D.new()
	ground_layer.name = "Ground"
	ground_layer.z_index = -10
	add_child(ground_layer)
	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	entity_layer.y_sort_enabled = true
	add_child(entity_layer)
	ground = GroundItems.new()
	ground.name = "GroundItems"
	add_child(ground)
	move_child(ground, entity_layer.get_index())
	enemies = EnemyManager.new()
	enemies.name = "Enemies"
	add_child(enemies)
	_tileset = _build_tileset()
	buildings_view = BuildingsView.new()
	buildings_view.name = "Buildings"
	add_child(buildings_view)
	buildings_view.setup(self)


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	for i in WorldGen.TILE_NAMES.size():
		var tex := GameData.texture("tiles", WorldGen.TILE_NAMES[i])
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(tile_px, tile_px)
		var cols := maxi(1, tex.get_width() / tile_px)
		for v in cols:
			src.create_tile(Vector2i(v, 0))
		ts.add_source(src, i)
	return ts


func variants_for(tile_type: int) -> int:
	var src := _tileset.get_source(tile_type) as TileSetAtlasSource
	return src.get_tiles_count() if src else 1


# ------------------------------------------------------------- coordinates --
static func chunk_of(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))


func tile_to_pos(p: Vector2i) -> Vector2:
	return Vector2(p.x * tile_px, p.y * tile_px)


## Bottom-centre of a tile: where y-sorted sprites stand.
func tile_foot(p: Vector2i) -> Vector2:
	return Vector2(p.x * tile_px + tile_px * 0.5, (p.y + 1) * tile_px)


func pos_to_tile(v: Vector2) -> Vector2i:
	return Vector2i(floori(v.x / tile_px), floori(v.y / tile_px))


# -------------------------------------------------------------------- data --
func get_chunk(c: Vector2i) -> ChunkData:
	var ch: ChunkData = chunks.get(c)
	if ch == null:
		ch = gen.generate_chunk(c)
		for p in ch.objects.keys():
			if depleted.has(p):
				ch.objects[p].depleted_until = int(depleted[p])
		chunks[c] = ch
	return ch


func tile_type(p: Vector2i) -> int:
	var c := chunk_of(p)
	return get_chunk(c).tile_local(p.x - c.x * CHUNK, p.y - c.y * CHUNK)


func object_at(p: Vector2i) -> WorldObject:
	return get_chunk(chunk_of(p)).objects.get(p)


func is_blocked(p: Vector2i) -> bool:
	if tile_type(p) in WorldGen.BLOCKING_TILES:
		return true
	var o := object_at(p)
	return o != null and o.blocks()


## Nearest walkable tile. outdoor = also skip building footprints (AI strolls,
## save relocation) so nobody idles inside a shop or on its doorway.
## Blocked by terrain itself (water, walls), not by an object standing there.
func is_tile_blocked(p: Vector2i) -> bool:
	return tile_type(p) in WorldGen.BLOCKING_TILES


func find_free_tile_near(p: Vector2i, max_r: int = 12, outdoor: bool = false) -> Vector2i:
	for r in max_r + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if not is_blocked(q) and not (outdoor and not gen.building_at(q).is_empty()):
					return q
	return p


## Nearest object of the given def ids within radius (Chebyshev), not depleted.
func find_nearest_object(from: Vector2i, def_ids: Array, radius: int = 30) -> WorldObject:
	var best: WorldObject = null
	var best_d := 1 << 30
	var c0 := chunk_of(from - Vector2i(radius, radius))
	var c1 := chunk_of(from + Vector2i(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for o in get_chunk(Vector2i(cx, cy)).objects.values():
				if not (o.def_id in def_ids) or o.is_depleted(tick):
					continue
				var d := maxi(absi(o.pos.x - from.x), absi(o.pos.y - from.y))
				if d <= radius and d < best_d:
					best_d = d
					best = o
	return best


## 0.3.1 PK helpers (data/pk_zones.json); the PK rules live with the AI/PK track.
## 0.3.1 churches: the nearest altar (by tiles) from `from`, optionally in one
## town. {"pos": altar tile, "approach": tile to stand on (door side),
## "building": id, "town": id, "door": door tile}; {} if none. AI players use
## this (walk to "approach", then interact with the altar object).
func nearest_altar(from: Vector2i, town: String = "") -> Dictionary:
	var best: Dictionary = {}
	var bd := 1 << 30
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if not b.has("altar") or (town != "" and b["town"] != town):
			continue
		var a: Vector2i = b["altar"]
		var d := maxi(absi(a.x - from.x), absi(a.y - from.y))
		if d < bd:
			bd = d
			var door: Vector2i = b["doors"][0]
			var step := Vector2i(0, 1) if door.y > a.y else Vector2i(0, -1)
			best = {"pos": a, "approach": a + step, "building": id, "town": b["town"], "door": door}
	return best


func is_pk(p: Vector2i) -> bool:
	return gen.is_pk(p)


func pk_zone_at(p: Vector2i) -> Dictionary:
	return gen.pk_zone_at(p)


## 0.3.1 AI routing: a gather node of `def_id` for someone at `from` whose
## home town is `home_town`. Nearby first (as before); otherwise the closest
## named mine (data/mines.json) that holds it, Scorch mines last.
func find_gather_node(from: Vector2i, def_id: String, home_town: String = "", radius: int = 30) -> WorldObject:
	var o := find_nearest_object(from, [def_id], radius)
	if o != null:
		return o
	if bool(GameData.object_def(def_id).get("farm", false)):   # 0.3.1 village wheat fields
		var anchor0 := gen.town_center(home_town) if gen.towns.has(home_town) else from
		var f := gen.nearest_farm(anchor0, def_id)
		if f.is_empty():
			return null
		var r: Rect2i = f["rect"]
		return find_nearest_object(f["center"], [def_id], maxi(r.size.x, r.size.y))
	if not def_id.ends_with("_rock"):
		return null
	var anchor := gen.town_center(home_town) if gen.towns.has(home_town) else from
	var m := gen.nearest_mine(anchor, def_id, false)
	if m.is_empty():
		m = gen.nearest_mine(anchor, def_id, true)
	if m.is_empty():
		return null
	return find_nearest_object(m["c"], [def_id], int(ceil(float(m["radius"]))) + 1)


func deplete(o: WorldObject, ticks: int) -> void:
	o.depleted_until = tick + maxi(1, ticks)
	depleted[o.pos] = o.depleted_until
	_refresh_object_view(o)
	object_changed.emit(o)


var fires: Dictionary = {}   # 0.3.6 Vector2i -> tick the cooking fire burns out


## 0.3.6 a temporary cooking fire (a hearth station) that burns out by itself.
func add_fire(p: Vector2i, ticks: int) -> WorldObject:
	var o := WorldObject.new("cooking_fire", p)
	get_chunk(chunk_of(p)).objects[p] = o
	fires[p] = tick + maxi(1, ticks)
	var c := chunk_of(p)
	if chunk_views.has(c):
		_make_object_view(o)
		var objs: Array = chunk_views[c].get_meta("objects", [])
		objs.append(o)
	object_changed.emit(o)
	return o


func _expire_fires(t: int) -> void:
	for p in fires.keys():
		if int(fires[p]) > t:
			continue
		fires.erase(p)
		var ch := get_chunk(chunk_of(p))
		var o: WorldObject = ch.objects.get(p)
		if o and o.def_id == "cooking_fire":
			ch.objects.erase(p)
			if o.view and is_instance_valid(o.view):
				o.view.queue_free()
			o.view = null
			var c := chunk_of(p)
			if chunk_views.has(c):
				var objs: Array = chunk_views[c].get_meta("objects", [])
				objs.erase(o)
			object_changed.emit(o)


func on_tick(t: int) -> void:
	tick = t
	if not fires.is_empty():
		_expire_fires(t)
	if depleted.is_empty():
		return
	var done := []
	for p in depleted.keys():
		if int(depleted[p]) <= t:
			done.append(p)
	for p in done:
		depleted.erase(p)
		var c := chunk_of(p)
		if chunks.has(c):
			var o: WorldObject = chunks[c].objects.get(p)
			if o:
				o.depleted_until = 0
				_refresh_object_view(o)
				object_changed.emit(o)


# --------------------------------------------------------------- streaming --
func set_focus(p: Vector2i, immediate: bool = false) -> void:
	var c := chunk_of(p)
	if c == _focus_chunk and not immediate:
		return
	_focus_chunk = c
	# queue missing views, nearest first
	var want: Array = []
	for dy in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var cc := c + Vector2i(dx, dy)
			if not chunk_views.has(cc) and not (cc in _build_queue):
				want.append(cc)
	want.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	_build_queue.append_array(want)
	# unload far views
	for cc in chunk_views.keys():
		if maxi(absi(cc.x - c.x), absi(cc.y - c.y)) > UNLOAD_RADIUS:
			_free_view(cc)
	# prune far data (keep depletion state in `depleted`)
	for cc in chunks.keys():
		if maxi(absi(cc.x - c.x), absi(cc.y - c.y)) > DATA_KEEP_RADIUS:
			chunks.erase(cc)
			_mini_tex.erase(cc)
	if immediate:
		while not _build_queue.is_empty():
			_build_view(_build_queue.pop_front())


func _process(delta: float) -> void:
	var n := 0
	while n < BUILDS_PER_FRAME and not _build_queue.is_empty():
		var cc: Vector2i = _build_queue.pop_front()
		if maxi(absi(cc.x - _focus_chunk.x), absi(cc.y - _focus_chunk.y)) <= VIEW_RADIUS and not chunk_views.has(cc):
			_build_view(cc)
			n += 1
	_anim_time += delta
	for a in _animated:
		var spr: Sprite2D = a[0]
		if is_instance_valid(spr):
			spr.frame = int(_anim_time * float(a[2])) % int(a[1])


func _build_view(c: Vector2i) -> void:
	var ch := get_chunk(c)
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	var layer := TileMapLayer.new()
	layer.tile_set = _tileset
	layer.position = Vector2(c.x * CHUNK * tile_px, c.y * CHUNK * tile_px)
	for ly in CHUNK:
		for lx in CHUNK:
			var t := ch.tile_local(lx, ly)
			var wx := c.x * CHUNK + lx
			var wy := c.y * CHUNK + ly
			var nv := variants_for(t)
			var v := 0 if nv <= 1 else int(gen.hash01(wx, wy, 7) * nv) % nv
			layer.set_cell(Vector2i(lx, ly), t, Vector2i(v, 0))
	root.add_child(layer)
	ground_layer.add_child(root)
	chunk_views[c] = root
	var objs: Array = []
	for o in ch.objects.values():
		_make_object_view(o)
		objs.append(o)
	root.set_meta("objects", objs)


func _free_view(c: Vector2i) -> void:
	var root: Node2D = chunk_views[c]
	for o in root.get_meta("objects", []):
		if o.view and is_instance_valid(o.view):
			o.view.queue_free()
		o.view = null
	root.queue_free()
	chunk_views.erase(c)
	_animated = _animated.filter(func(a): return is_instance_valid(a[0]) and not a[0].is_queued_for_deletion())


func _make_object_view(o: WorldObject) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.position = tile_foot(o.pos)
	o.view = spr
	if o.def().get("keeper", false):
		var b: Dictionary = gen.buildings.get(str(o.meta.get("building", "")), {})
		apply_keeper_sprite(spr, buildings_view.keeper_sprite(b) if not b.is_empty() else "keeper_general")
	else:
		_apply_sprite(spr, o.sprite_id(tick))
	entity_layer.add_child(spr)


## Shopkeepers are drawn with an actor sheet (idle animation, faces right).
func apply_keeper_sprite(spr: Sprite2D, sid: String) -> void:
	spr.visible = true
	spr.texture = GameData.texture("actors", sid)
	var fs := GameData.frame_size("actors", sid)
	var frames := GameData.frame_count("actors", sid)
	spr.hframes = maxi(1, frames)
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)
	if frames > 1 and not spr.has_meta("animated"):
		spr.set_meta("animated", true)
		_animated.append([spr, frames, float(GameData.sprite_def("actors", sid).get("fps", 2))])


func _apply_sprite(spr: Sprite2D, sprite_id: String) -> void:
	if sprite_id == "":
		spr.visible = false
		return
	spr.visible = true
	spr.texture = GameData.texture("objects", sprite_id)
	var fs := GameData.frame_size("objects", sprite_id)
	var frames := GameData.frame_count("objects", sprite_id)
	spr.hframes = maxi(1, frames)
	spr.frame = 0
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)
	if frames > 1 and not spr.has_meta("animated"):
		spr.set_meta("animated", true)
		var fps := float(GameData.sprite_def("objects", sprite_id).get("fps", 3))
		_animated.append([spr, frames, fps])


func _refresh_object_view(o: WorldObject) -> void:
	if o.view and is_instance_valid(o.view):
		_apply_sprite(o.view, o.sprite_id(tick))


# ---------------------------------------------------------------- minimap --
func minimap_texture(c: Vector2i) -> ImageTexture:
	if _mini_tex.has(c):
		return _mini_tex[c]
	var ch := get_chunk(c)
	var img := Image.create(CHUNK, CHUNK, false, Image.FORMAT_RGBA8)
	for ly in CHUNK:
		for lx in CHUNK:
			img.set_pixel(lx, ly, GameData.tile_color(ch.tile_local(lx, ly)))
	for o in ch.objects.values():
		var lp: Vector2i = o.pos - c * CHUNK
		var t: String = o.def().get("type", "")
		var col := Color(0.2, 0.35, 0.15)
		if t == "bank" or t == "exchange" or t == "station":
			col = Color(1.0, 0.85, 0.3)
		elif o.def().get("skill", "") == "mining":
			col = Color(0.55, 0.55, 0.6)
		elif o.def().get("skill", "") == "angling":
			col = Color(0.8, 0.95, 1.0)
		elif t == "shop" or t == "display":
			col = Color(1.0, 0.85, 0.3)
		elif t == "prop" or t == "scenery":
			continue
		img.set_pixel(lp.x, lp.y, col)
	# 0.3.0 building footprints: roof colour, door marked
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		var r: Rect2i = b["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var q := Vector2i(x, y) - c * CHUNK
				if q.x < 0 or q.y < 0 or q.x >= CHUNK or q.y >= CHUNK:
					continue
				var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
				var col2 := Color(str(b["roof"])).darkened(0.35 if edge else 0.0)
				if Vector2i(x, y) in b["doors"]:
					col2 = Color("#f8f0d8")
				img.set_pixel(q.x, q.y, col2)
	var tex := ImageTexture.create_from_image(img)
	_mini_tex[c] = tex
	return tex


# --------------------------------------------------------------- world map --
const MAP_STEP := 5                  # tiles per map pixel
var _map_tex: ImageTexture = null


## Whole-continent map (1 px = MAP_STEP tiles), roads and towns drawn on top.
## Built once per session from the seed (no chunk data needed).
func world_map_texture() -> ImageTexture:
	if _map_tex:
		return _map_tex
	var b := gen.bounds()
	var w := int(b.size.x / MAP_STEP)
	var h := int(b.size.y / MAP_STEP)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ocean := Color("#1d4a66")
	for py in h:
		for px in w:
			var x := b.position.x + px * MAP_STEP + MAP_STEP / 2
			var y := b.position.y + py * MAP_STEP + MAP_STEP / 2
			var t := gen.tile_at(x, y)
			var col := GameData.tile_color(t)
			if t == WorldGen.TileType.WATER and gen.land_value(x, y) < WorldGen.OCEAN_LEVEL:
				col = ocean
			img.set_pixel(px, py, col)
	for p in gen.road_tiles.keys():
		var q: Vector2i = (p - b.position) / MAP_STEP
		if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
			img.set_pixel(q.x, q.y, Color("#e0c080"))
	for id in gen.towns.keys():
		var c: Vector2i = (gen.town_center(id) - b.position) / MAP_STEP
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q2 := c + Vector2i(dx, dy)
				if q2.x >= 0 and q2.y >= 0 and q2.x < w and q2.y < h:
					img.set_pixel(q2.x, q2.y, Color("#f8f0d8") if maxi(absi(dx), absi(dy)) < 2 else Color("#3a2a18"))
	# 0.3.0 building footprints (roof colour) over the town marker
	for bid in gen.building_order:
		var bd: Dictionary = gen.buildings[bid]
		var br: Rect2i = bd["rect"]
		for y in range(br.position.y, br.end.y, 2):
			for x in range(br.position.x, br.end.x, 2):
				var q3: Vector2i = (Vector2i(x, y) - b.position) / MAP_STEP
				if q3.x >= 0 and q3.y >= 0 and q3.x < w and q3.y < h:
					img.set_pixel(q3.x, q3.y, Color(str(bd["roof"])).darkened(0.2))
	_map_tex = ImageTexture.create_from_image(img)
	return _map_tex


func map_pixel(p: Vector2i) -> Vector2:
	return Vector2(p - gen.bounds().position) / MAP_STEP


# ------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	var d := {}
	for p in depleted.keys():
		d["%d,%d" % [p.x, p.y]] = int(depleted[p]) - tick   # remaining ticks
	return {"seed": gen.world_seed, "depleted": d, "ground": ground.to_save(tick)}


func from_save(d: Dictionary, now_tick: int) -> void:
	depleted.clear()
	ground.from_save(d.get("ground", []), now_tick)
	var dep: Dictionary = d.get("depleted", {})
	for k in dep.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() == 2:
			depleted[Vector2i(int(parts[0]), int(parts[1]))] = now_tick + int(dep[k])
	for ch in chunks.values():
		for o in ch.objects.values():
			o.depleted_until = int(depleted.get(o.pos, 0))
			_refresh_object_view(o)
