class_name WorldGen
extends RefCounted
## Deterministic, seeded world generation. Pure data: no nodes, no textures.
## The same seed always produces the same tiles and objects, so the save only
## needs to store *changes* (depleted nodes etc.), never the map.

enum TileType { GRASS, PATH, WATER, SAND, DIRT, COBBLE, PLANKS, MARSH, WALL, WALL_FRONT, FLOOR, DOORWAY, ASH, ASH_EDGE, BRIDGE,
	STONE_WALL, STONE_FRONT, STONE_FLOOR,
	PALISADE, PALISADE_FRONT, BASALT_WALL, BASALT_FRONT, SANDSTONE_WALL, SANDSTONE_FRONT,
	GATE_WOOD, GATE_BASALT, GATE_SAND, BOARDWALK, COBBLE_DARK, PLASTER, PLASTER_WALL, PLASTER_FRONT,
	ROAD_STONE, ROAD_DIRT, MOAT, MOAT_EDGE, CAPITAL_WALL, CAPITAL_FRONT, GATE_CAPITAL,
	CAPITAL_BLDG_WALL, CAPITAL_BLDG_FRONT, HOUSE_WALL, HOUSE_FRONT,
	GRASS_LUSH, GRASS_BOREAL, GRASS_TROPIC, ROCKY, CLIFF_FACE, CLIFF_LIP, CLIFF_SHADOW, CLIFF_STAIRS }
const TILE_NAMES := ["grass", "path", "water", "sand", "dirt", "cobble", "planks", "marsh", "wall", "wall_front", "floor", "doorway",
	"ash", "ash_edge", "bridge", "stone_wall", "stone_front", "stone_floor",
	"palisade", "palisade_front", "basalt_wall", "basalt_front", "sandstone_wall", "sandstone_front",
	"gate_wood", "gate_basalt", "gate_sand", "boardwalk", "cobble_dark", "plaster", "plaster_wall", "plaster_front",
	"road_stone", "road_dirt", "moat", "moat_edge", "capital_wall", "capital_front", "gate_capital",
	"capital_bldg_wall", "capital_bldg_front", "house_wall", "house_front",
	"grass_lush", "grass_boreal", "grass_tropic", "rocky", "cliff_face", "cliff_lip", "cliff_shadow", "cliff_stairs"]
const BLOCKING_TILES := [TileType.WATER, TileType.WALL, TileType.WALL_FRONT, TileType.STONE_WALL, TileType.STONE_FRONT,
	TileType.PALISADE, TileType.PALISADE_FRONT, TileType.BASALT_WALL, TileType.BASALT_FRONT,
	TileType.SANDSTONE_WALL, TileType.SANDSTONE_FRONT, TileType.PLASTER_WALL, TileType.PLASTER_FRONT,
	TileType.MOAT, TileType.CAPITAL_WALL, TileType.CAPITAL_FRONT, TileType.CAPITAL_BLDG_WALL, TileType.CAPITAL_BLDG_FRONT,
	TileType.HOUSE_WALL, TileType.HOUSE_FRONT, TileType.CLIFF_FACE, TileType.CLIFF_LIP]
## 0.3.8 arrows fly over open water (lakes, the moat); walls stop them
const SHOOT_OVER_TILES := [TileType.WATER, TileType.MOAT]
## 0.3.8 road surfaces (old PATH, stone capital roads, dirt village roads)
const ROAD_SURFACES := [TileType.PATH, TileType.ROAD_STONE, TileType.ROAD_DIRT]
const FLOOR_TILES := [TileType.FLOOR, TileType.STONE_FLOOR, TileType.PLASTER]
const GATE_TILES := [TileType.GATE_WOOD, TileType.GATE_BASALT, TileType.GATE_SAND, TileType.GATE_CAPITAL]
const CHUNK := 24
## 0.3.10 open grassland of every region (region grasses are recolours of grass)
const GRASS_TILES := [TileType.GRASS, TileType.GRASS_LUSH, TileType.GRASS_BOREAL, TileType.GRASS_TROPIC]
## 0.3.10 cliffs: face (south edge, rock face shows) and lip (other edges) block; shadow + stairs walk
const CLIFF_TILES := [TileType.CLIFF_FACE, TileType.CLIFF_LIP]
const ROAD_SPACING := 72

const OCEAN_LEVEL := 0.10
const BEACH_LEVEL := 0.15
const TOWN_DRY_RADIUS := 60.0
const REGION_RADIUS := 190.0

var world_seed: int
var _height := FastNoiseLite.new()
var _moist := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var region_map: WorldRegions          # 0.3.10 lore regions + terrace elevation (data/regions.json)
var _town: Dictionary = {}            # the home town (Fenhollow) for spawn
var towns: Dictionary = {}            # id -> town dict (with "center": Vector2i)
var town_order: Array = []
var _town_rects: Dictionary = {}      # id -> Rect2i
var _town_tiles: Dictionary = {}      # Vector2i -> tile type
var _town_objects: Dictionary = {}    # Vector2i -> object id
var _town_meta: Dictionary = {}       # Vector2i -> per-instance object data (shop, building, stand, slot)
var buildings: Dictionary = {}        # 0.3.0: building id -> building dict (absolute coords, see _load_buildings)
var building_order: Array = []
var _building_tiles: Dictionary = {}  # Vector2i -> building id (whole footprint incl. walls)
var continent_center := Vector2i(180, -10)
var continent_radius := 330.0
var regions: Dictionary = {}          # town id -> {"biome", "label"}
var roads: Dictionary = {}            # "a|b" -> Array[Vector2i] ordered a -> b (8-connected)
var road_tiles: Dictionary = {}       # Vector2i -> tile type (PATH, or BRIDGE over lake water)
var bridges: Array = []               # 0.3.1: [{"road": "a|b", "tiles": [Vector2i...]}] one entry per span
var mines: Array = []                 # 0.3.1: data/mines.json clusters (center Vector2i, radius, ores...)
var pk_zones: Array = []              # 0.3.1: data/pk_zones.json zones with "r": Rect2i
var _mine_grid: Dictionary = {}       # Vector2i(chunk) -> Array[mine index] (fast lookup)
var _road_cfg: Dictionary = {}
var _ramp_period := 36
var _ramp_width := 3
var _road_ramp := 3
var _keep_clear := 8
var capital := ""                     # 0.3.8 the capital's town id ("" = none)
var village_roads: Dictionary = {}    # 0.3.8 village id -> Array[Vector2i] village gate -> town gate (dirt)
var road_decor: Dictionary = {}       # 0.3.8 Vector2i -> roadside object id (fence / rock / bush / log)
# 0.3.1 villages (data/towns/<id>.json kind "village"): NOT cities. town_at /
# town_edge_distance / nearest_town ignore them (distance bands, home towns,
# travel, respawn stay city-only); village_at / safe_at / place_at see them.
var villages: Dictionary = {}         # id -> village dict (with "center")
var village_order: Array = []
var _village_rects: Dictionary = {}   # id -> Rect2i (the core rows: the safe zone)
var farms: Array = []                 # [{"id", "village", "rect": Rect2i, "crop", "gate": Vector2i, "center"}]
var pastures: Array = []              # [{"id", "village", "rect": Rect2i, "enemy", "count", "gate", "center"}]
var village_paths: Dictionary = {}    # village id -> Array[Vector2i] (gate -> road)
var _clear_rects: Array = []          # Rect2i: fields / pastures (no generated trees)

## 0.3.1 cache: A* roads are deterministic per seed + data, so build each
## distinct world once per process (tests build several WorldGens).
static var _road_cache: Dictionary = {}


## `town` may be a single town dict (tests/legacy) or omitted; the continent
## layout and all towns come from GameData.world / GameData.towns.
func _init(p_seed: int, town: Dictionary = {}, world_cfg: Dictionary = {}) -> void:
	world_seed = p_seed
	_height.seed = p_seed
	_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height.frequency = 0.018
	_height.fractal_octaves = 3
	_moist.seed = p_seed + 101
	_moist.frequency = 0.012
	_detail.seed = p_seed + 202
	_detail.frequency = 0.09
	_coast.seed = p_seed + 303
	_coast.frequency = 0.0045
	_coast.fractal_octaves = 4
	var cfg: Dictionary = world_cfg if not world_cfg.is_empty() else GameData.world
	if cfg.has("continent"):
		var c: Array = cfg["continent"]["center"]
		continent_center = Vector2i(int(c[0]), int(c[1]))
		continent_radius = float(cfg["continent"]["radius"])
	regions = cfg.get("regions", {})
	region_map = WorldRegions.new(p_seed)
	var tcfg: Dictionary = region_map.cfg.get("terrace", {})
	_ramp_period = maxi(8, int(tcfg.get("ramp_period", 36)))
	_ramp_width = clampi(int(tcfg.get("ramp_width", 3)), 1, _ramp_period - 4)
	_road_ramp = int(tcfg.get("road_ramp_tiles", 3))
	_keep_clear = int(tcfg.get("keep_clear_tiles", 8))
	var ids: Array = cfg.get("towns", [])
	if ids.is_empty() and not town.is_empty():
		ids = [town["id"]]
	for id in ids:
		var t: Dictionary = GameData.towns.get(id, town if town.get("id", "") == id else {})
		if not t.is_empty():
			_load_town(t)
	if not town.is_empty() and not towns.has(town["id"]):
		_load_town(town)
	_town = towns.get("fenhollow", towns.values()[0] if not towns.is_empty() else {})
	for id in towns.keys():
		if str(towns[id].get("kind", "")) == "capital":
			capital = id
	_load_pk_zones()
	_load_mines()
	_road_cfg = cfg.get("road_rules", {})
	_road_block = _village_footprints(cfg)
	var key := "%d|%s|%s|%s|%s" % [world_seed, str(ids), str(_road_cfg), str(_road_block), str(cfg.get("village_roads", []))]
	if _road_cache.has(key):
		var c: Dictionary = _road_cache[key]
		roads = c["roads"].duplicate()
		road_tiles = c["road_tiles"].duplicate()
		bridges = c["bridges"].duplicate(true)
		village_roads = c["village_roads"].duplicate(true)
		road_decor = c["decor"].duplicate()
	else:
		for pair in cfg.get("roads", []):
			if towns.has(pair[0]) and towns.has(pair[1]):
				_build_road(pair[0], pair[1])
		_compose_capital_roads()
		for pair in cfg.get("village_roads", []):
			if GameData.villages.has(pair[0]) and towns.has(pair[1]):
				_build_village_road(str(pair[0]), str(pair[1]))
		_place_road_decor()
		_road_cache[key] = {"roads": roads.duplicate(), "road_tiles": road_tiles.duplicate(), "bridges": bridges.duplicate(true),
			"village_roads": village_roads.duplicate(true), "decor": road_decor.duplicate()}
	for vid in cfg.get("villages", []):
		var v: Dictionary = GameData.villages.get(vid, {})
		if not v.is_empty():
			_load_village(v)
	_cells_ready = true


## 0.3.1 a village: core rows ("transparent" chars keep the terrain), cottages
## (walk-in "house" buildings), a fenced wheat field, a fenced cow pasture and
## a path from the village gate to the nearest road tile.
func _load_village(v: Dictionary) -> void:
	var origin := Vector2i(int(v["origin"][0]), int(v["origin"][1]))
	var rows: Array = v["rows"]
	var rect := Rect2i(origin, Vector2i(str(rows[0]).length(), rows.size()))
	var t := v.duplicate()
	t["center"] = rect.position + rect.size / 2
	villages[v["id"]] = t
	village_order.append(v["id"])
	_village_rects[v["id"]] = rect
	var tmap: Dictionary = v.get("tiles", {})
	var omap: Dictionary = v.get("objects", {})
	var clear := str(v.get("transparent", ""))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var p := origin + Vector2i(x, y)
			if tmap.has(ch):
				_town_tiles[p] = TILE_NAMES.find(tmap[ch])
			elif omap.has(ch):
				_town_tiles[p] = TILE_NAMES.find(omap[ch]["ground"])
				_town_objects[p] = omap[ch]["object"]
			elif clear.find(ch) < 0:
				_town_tiles[p] = region_grass(p)
	_load_buildings(v, origin)
	for f in v.get("farms", []):
		var fr := _fenced(origin, f, TILE_NAMES.find(str(f.get("ground", "dirt"))), str(f.get("crop", "wheat")))
		farms.append({"id": str(f["id"]), "village": v["id"], "rect": fr, "crop": str(f.get("crop", "wheat")),
			"gate": origin + Vector2i(int(f["gate"][0]), int(f["gate"][1])), "center": fr.position + fr.size / 2})
	for pz in v.get("pastures", []):
		var pr := _fenced(origin, pz, TileType.GRASS, "")
		pastures.append({"id": str(pz["id"]), "village": v["id"], "rect": pr, "enemy": str(pz.get("enemy", "cow")),
			"count": int(pz.get("count", 4)), "gate": origin + Vector2i(int(pz["gate"][0]), int(pz["gate"][1])), "center": pr.position + pr.size / 2})
	var whole := rect   # 0.3.1 no generated trees/rocks anywhere in the village footprint (+1 tile)
	for f in farms + pastures:
		if f["village"] == v["id"]:
			whole = whole.merge(f["rect"])
	_clear_rects.append(whole.grow(1))
	if village_roads.has(v["id"]):
		village_paths[v["id"]] = village_roads[v["id"]]   # 0.3.8 winding dirt road to its town
	elif v.has("gate"):
		village_paths[v["id"]] = _path_to_road(origin + Vector2i(int(v["gate"][0]), int(v["gate"][1])), int(GameData.villages_cfg.get("path_search", 30)))


## A fenced rect (village-local "rect"): fence posts on the rim except the gate,
## `ground` inside, `crop` (object id) on every inside tile when given.
func _fenced(origin: Vector2i, d: Dictionary, ground: int, crop: String) -> Rect2i:
	var a: Array = d["rect"]
	var r := Rect2i(origin + Vector2i(int(a[0]), int(a[1])), Vector2i(int(a[2]), int(a[3])))
	var gate := origin + Vector2i(int(d["gate"][0]), int(d["gate"][1]))
	_clear_rects.append(r)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var rim_y := y == r.position.y or y == r.end.y - 1
			var rim_x := x == r.position.x or x == r.end.x - 1
			if p == gate:
				_town_tiles[p] = TileType.PATH
			elif rim_y:
				_town_tiles[p] = region_grass(p)
				_town_objects[p] = "fence"
			elif rim_x:
				_town_tiles[p] = region_grass(p)
				_town_objects[p] = "fence_v"
			elif d.has("divider") and x == origin.x + int(d["divider"]["x"]) and y <= origin.y + int(d["divider"]["to_y"]):
				_town_tiles[p] = ground
				_town_objects[p] = "fence_v"   # 0.3.9 paddock divider
			else:
				_town_tiles[p] = ground
				if crop != "":
					_town_objects[p] = crop
	return r


## Path tiles from `from` to the nearest road tile (4-connected, longest axis
## first); stops at water. Returns the tiles laid.
func _path_to_road(from: Vector2i, search: int) -> Array:
	var best := Vector2i.ZERO
	var bd := INF
	for q in road_tiles.keys():
		var d := Vector2(q - from).length()
		if d < bd and road_tiles[q] in ROAD_SURFACES:
			bd = d
			best = q
	var out: Array = []
	if bd > search:
		return out
	var p := from
	var guard := 0
	while p != best and guard < search * 3:
		guard += 1
		if not _town_tiles.has(p) or _town_tiles[p] in GRASS_TILES:
			if _terrain_at(p.x, p.y) == TileType.WATER:
				break
			_town_tiles[p] = TileType.PATH
			out.append(p)
		var d := best - p
		if absi(d.x) >= absi(d.y):
			p.x += signi(d.x)
		else:
			p.y += signi(d.y)
	return out


func village_at(p: Vector2i, margin: int = 0) -> String:
	for id in _village_rects.keys():
		if (_village_rects[id] as Rect2i).grow(margin).has_point(p):
			return id
	return ""


## 0.3.1 safe ground: inside a city or a village (no starting aggro, no fights).
func safe_at(p: Vector2i) -> bool:
	return town_at(p, 0) != "" or village_at(p, 0) != ""


## The settlement (city first, else village) whose rect grown by margin holds p.
func place_at(p: Vector2i, margin: int = 6) -> String:
	var t := town_at(p, margin)
	return t if t != "" else village_at(p, margin)


## 0.3.1 authored station tiles (e.g. the village querns) for `station`.
## 0.3.8 inside the player's (buyable) house: stations / chest are the owner's only.
func is_private(p: Vector2i) -> bool:
	var bid := str(_town_meta.get(p, {}).get("building", ""))
	return bid != "" and str(buildings.get(bid, {}).get("kind", "")) == "player_house"


func station_sites(station: String) -> Array:
	var out: Array = []
	for p in _town_objects.keys():
		if is_private(p):
			continue
		if str(GameData.object_def(str(_town_objects[p])).get("station", "")) == station:
			out.append(p)
	return out


func in_clear_rect(p: Vector2i) -> bool:
	for r in _clear_rects:
		if (r as Rect2i).has_point(p):
			return true
	return false


func nearest_farm(from: Vector2i, crop: String = "") -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for f in farms:
		if crop != "" and f["crop"] != crop:
			continue
		var d := Vector2(from - (f["center"] as Vector2i)).length()
		if d < bd:
			bd = d
			best = f
	return best


func nearest_pasture(from: Vector2i, enemy: String = "") -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for pz in pastures:
		if enemy != "" and pz["enemy"] != enemy:
			continue
		var d := Vector2(from - (pz["center"] as Vector2i)).length()
		if d < bd:
			bd = d
			best = pz
	return best


func _load_town(town: Dictionary) -> void:
	var origin := Vector2i(int(town["origin"][0]), int(town["origin"][1]))
	var rows: Array = town["rows"]
	var rect := Rect2i(origin, Vector2i(rows[0].length(), rows.size()))
	var t := town.duplicate()
	t["center"] = rect.position + rect.size / 2
	towns[town["id"]] = t
	town_order.append(town["id"])
	_town_rects[town["id"]] = rect
	var tmap: Dictionary = town["tiles"]
	var omap: Dictionary = town["objects"]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			var p := origin + Vector2i(x, y)
			if tmap.has(ch):
				_town_tiles[p] = TILE_NAMES.find(tmap[ch])
			elif omap.has(ch):
				_town_tiles[p] = TILE_NAMES.find(omap[ch]["ground"])
				_town_objects[p] = omap[ch]["object"]
			else:
				_town_tiles[p] = region_grass(p)
	_load_buildings(town, origin)
	_ensure_gate_approaches(town, origin)


## Stamp a short clear approach just outside every gate (pier over water,
## path over land) so path in/out is never blocked by ocean or a tree.
func _ensure_gate_approaches(town: Dictionary, origin: Vector2i) -> void:
	var gates: Dictionary = town.get("gates", {})
	for dir in gates.keys():
		var cells: Array = gates[dir]
		if cells.is_empty():
			continue
		var mid_local: Array = cells[mini(1, cells.size() - 1)]
		var mid := origin + Vector2i(int(mid_local[0]), int(mid_local[1]))
		var step := Vector2i.ZERO
		match str(dir):
			"north": step = Vector2i(0, -1)
			"south": step = Vector2i(0, 1)
			"west": step = Vector2i(-1, 0)
			"east": step = Vector2i(1, 0)
		for i in range(1, 4):
			var p: Vector2i = mid + step * i
			var sides: Array[Vector2i] = [p]
			if step.x != 0:
				sides.append(p + Vector2i(0, -1))
				sides.append(p + Vector2i(0, 1))
			else:
				sides.append(p + Vector2i(-1, 0))
				sides.append(p + Vector2i(1, 0))
			for q in sides:
				if _town_rects.get(str(town["id"]), Rect2i()).has_point(q):
					continue
				var ter: int = _terrain_at(q.x, q.y)
				# Planks only over water (harbour pier); path on land so road
				# tiles that share the approach stay PATH for the roads selftest.
				var ground: int = TileType.PLANKS if ter == TileType.WATER else TileType.PATH
				_town_tiles[q] = ground
				_town_objects[q] = ""   # suppress wilderness trees/rocks on the approach


## 0.3.0 walk-in buildings (data/towns/*.json "buildings", town-local coords).
## Walls ring the footprint; the wall row holding the door is the facade
## (wall_front, never roofed); the door is walkable; the counter, keeper and
## props are blocking objects carrying per-instance meta.
func _load_buildings(town: Dictionary, origin: Vector2i) -> void:
	var shops: Dictionary = GameData.buildings_cfg.get("shops", {})
	var v := func(a) -> Vector2i: return origin + Vector2i(int(a[0]), int(a[1]))
	var defs: Array = town.get("buildings", []).duplicate()
	var church: Dictionary = GameData.churches.get("towns", {}).get(str(town["id"]), {})
	if not church.is_empty():
		defs.append(church)   # 0.3.1 one stone church per town (data/churches.json)
	for bd in defs:
		var r: Array = bd["rect"]
		var rect := Rect2i(v.call(r), Vector2i(int(r[2]), int(r[3])))
		var doors: Array = []
		for d in bd["door"]:
			doors.append(v.call(d))
		var facade: int = rect.end.y - 1 if (doors[0] as Vector2i).y == rect.end.y - 1 else rect.position.y
		var shop := str(bd.get("shop", ""))
		var sd: Dictionary = shops.get(shop, {})
		if str(bd.get("kind", "")) == "church":
			sd = GameData.churches
		var style := str(bd.get("style", sd.get("style", town.get("building_style", "timber"))))
		if str(bd.get("kind", "")) == "church":
			style = "stone"
		var wall_t := TileType.WALL
		var front_t := TileType.WALL_FRONT
		var floor_t := TileType.FLOOR
		match style:
			"stone":
				wall_t = TileType.STONE_WALL; front_t = TileType.STONE_FRONT; floor_t = TileType.STONE_FLOOR
			"basalt":
				wall_t = TileType.BASALT_WALL; front_t = TileType.BASALT_FRONT; floor_t = TileType.STONE_FLOOR
			"sandstone":
				wall_t = TileType.SANDSTONE_WALL; front_t = TileType.SANDSTONE_FRONT; floor_t = TileType.PLASTER
			"plaster":
				wall_t = TileType.PLASTER_WALL; front_t = TileType.PLASTER_FRONT; floor_t = TileType.PLASTER
			"capital":
				wall_t = TileType.CAPITAL_BLDG_WALL; front_t = TileType.CAPITAL_BLDG_FRONT; floor_t = TileType.STONE_FLOOR
			"house":
				wall_t = TileType.HOUSE_WALL; front_t = TileType.HOUSE_FRONT; floor_t = TileType.FLOOR
			_:
				style = "timber"
		var b := {
			"id": str(bd["id"]), "town": str(town["id"]), "kind": str(bd.get("kind", "shop")), "shop": shop,
			"name": str(bd.get("name", sd.get("name", ""))), "keeper": str(bd.get("keeper", sd.get("keeper", "Shopkeeper"))),
			"keeper_sprite": str(bd.get("keeper_sprite", sd.get("keeper_sprite", "keeper_general"))), "sign_sprite": str(bd.get("sign_sprite", sd.get("sign", "sign_general"))),
			"rect": rect, "doors": doors, "facade_y": facade, "keeper_at": v.call(bd["keeper_at"]), "stand": v.call(bd["stand"]),
			"sign": v.call(bd["sign"]), "counter": [], "displays": [], "roof": str(bd.get("roof", sd.get("roof", town.get("roof", "#8a6a4a")))),
			"style": style,
		}
		if bd.has("altar"):
			b["altar"] = v.call(bd["altar"])
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var p := Vector2i(x, y)
				_building_tiles[p] = b["id"]
				_town_objects.erase(p)
				var edge := x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1
				if p in doors:
					_town_tiles[p] = TileType.DOORWAY
				elif edge:
					_town_tiles[p] = front_t if y == facade else wall_t
				else:
					_town_tiles[p] = floor_t
		var meta := {"building": b["id"], "shop": shop, "stand": b["stand"], "town": b["town"]}
		for c in bd.get("counter", []):
			var p: Vector2i = v.call(c)
			b["counter"].append(p)
			_town_objects[p] = "shop_counter"
			_town_meta[p] = meta
		_town_objects[b["keeper_at"]] = "shopkeeper"
		_town_meta[b["keeper_at"]] = meta.merged({"name": b["keeper"], "keeper": true})
		for pr in bd.get("props", []):
			_town_objects[v.call(pr["at"])] = str(pr["object"])
			_town_meta[v.call(pr["at"])] = {"building": b["id"]}
		if b.has("altar"):
			_town_objects[b["altar"]] = "altar"
			_town_meta[b["altar"]] = {"building": b["id"], "town": b["town"]}
		var di := 0
		for dsp in bd.get("displays", []):
			var p: Vector2i = v.call(dsp)
			b["displays"].append(p)
			_town_objects[p] = "display_stand"
			_town_meta[p] = {"building": b["id"], "town": b["town"], "slot": di}
			di += 1
		buildings[b["id"]] = b
		building_order.append(b["id"])


## 0.3.1: the town object id placed at p ("" if none): props, stations, altar.
func object_id_at(p: Vector2i) -> String:
	return str(_town_objects.get(p, ""))


## Building whose footprint (walls included) holds p, else {}.
func building_at(p: Vector2i) -> Dictionary:
	return buildings.get(_building_tiles.get(p, ""), {})


## Inside for the roof: on the doorway or anywhere off the facade/walls in the footprint.
func is_inside(p: Vector2i, b: Dictionary) -> bool:
	if b.is_empty() or not (b["rect"] as Rect2i).has_point(p):
		return false
	return p in b["doors"] or (p.y != int(b["facade_y"]) and tile_at(p.x, p.y) in FLOOR_TILES)


## Tiles the roof covers (footprint minus the facade row).
func is_roofed(p: Vector2i, b: Dictionary) -> bool:
	return not b.is_empty() and (b["rect"] as Rect2i).has_point(p) and p.y != int(b["facade_y"])


func building_for_shop(town: String, shop: String) -> Dictionary:
	for id in building_order:
		var b: Dictionary = buildings[id]
		if b["town"] == town and b["shop"] == shop:
			return b
	return {}


func object_meta(p: Vector2i) -> Dictionary:
	return _town_meta.get(p, {})


## 0.3.1 roads: A* over the terrain between town centres. Ocean is
## impassable; lake water costs road_rules.bridge_cost per tile (a wooden
## bridge), so a road only crosses a lake where going round is much longer.
## Diagonal steps are not allowed past water, so every bridge span is a
## 4-connected walkable strip. Costs are data-driven (data/world.json
## "road_rules"); a little moisture noise makes the roads meander.
var _road_block: Array = []


func _build_road(a: String, b: String) -> void:
	var pa: Vector2i = towns[a]["center"]
	var pb: Vector2i = towns[b]["center"]
	# 0.3.1 walled cities: the road runs gate to gate (the pair of gates whose
	# outside tiles are closest), never through a wall or another town.
	var ga := gate_outside(a, pb)
	var gb := gate_outside(b, pa)
	if ga != Vector2i(1 << 30, 0) and gb != Vector2i(1 << 30, 0):
		var best := INF
		for qa in gate_outsides(a):
			for qb in gate_outsides(b):
				var d := Vector2(qa - qb).length()
				if d < best:
					best = d
					ga = qa
					gb = qb
		pa = ga
		pb = gb
	var raw := _road_astar(pa, pb)
	if raw.is_empty():
		push_error("WorldGen: no road %s -> %s" % [a, b])
		return
	# inside the towns actors walk the streets; the road list starts at the edge
	var ra: Rect2i = (_town_rects[a] as Rect2i).grow(1)
	var rb: Rect2i = (_town_rects[b] as Rect2i).grow(1)
	var tiles: Array = raw.filter(func(p): return not ra.has_point(p) and not rb.has_point(p))
	# 0.3.10 if the A* wandered through the rect corners (round capital walls),
	# reconnect the road straight to its gate so it always runs gate to gate
	if not tiles.is_empty() and _cheb(tiles[0], pa) > 2:
		var lead: Array = _line8(pa, tiles[0]).filter(func(p): return not ra.has_point(p) or p == pa)
		lead.pop_back()
		tiles = lead + tiles
	if not tiles.is_empty() and _cheb(tiles[-1], pb) > 2:
		var tail: Array = _line8(tiles[-1], pb).filter(func(p): return not rb.has_point(p) or p == pb)
		tail.pop_front()
		tiles = tiles + tail
	roads[a + "|" + b] = tiles
	var rev := tiles.duplicate()
	rev.reverse()
	roads[b + "|" + a] = rev
	var surf: int = TileType.ROAD_STONE if capital != "" and (a == capital or b == capital) else TileType.PATH
	_stamp_road(a + "|" + b, tiles, surf, 3)


## 0.3.8 lay a road: surface tiles (bridges over lake water) + widening to 2-3
## tiles (never into a town, a village footprint, the ocean or another road).
func _stamp_road(rid: String, tiles: Array, surf: int, width: int) -> void:
	var span: Array = []
	for p in tiles:
		var water: bool = _terrain_at(p.x, p.y) == TileType.WATER
		if road_tiles.has(p) and road_tiles[p] != TileType.PATH:
			if water and not span.is_empty():
				span.append(p)
			continue      # 0.3.8 a dirt road meeting a stone road keeps the stone
		road_tiles[p] = TileType.BRIDGE if water else surf
		if water:
			span.append(p)
		elif not span.is_empty():
			bridges.append({"road": rid, "tiles": span})
			span = []
	if not span.is_empty():
		bridges.append({"road": rid, "tiles": span})
	# brush: 2x2 always (2 wide whatever the heading), the opposite pair on
	# about half the tiles (3 wide)
	for p in tiles:
		var sides: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
		if width >= 3 and hash01(p.x, p.y, 31) < 0.55:
			sides += [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
		var on_bridge: bool = road_tiles.get(p, -1) == TileType.BRIDGE
		for sd in sides:
			var q: Vector2i = p + sd
			if road_tiles.has(q) or _blocked_for_road(q):
				continue
			var w: bool = _terrain_at(q.x, q.y) == TileType.WATER
			if w and (not on_bridge or land_value(q.x, q.y) < OCEAN_LEVEL):
				continue
			if on_bridge and not w:
				continue     # bridges stay their own width; no land spur beside them
			road_tiles[q] = TileType.BRIDGE if w else surf


func _blocked_for_road(q: Vector2i) -> bool:
	if _town_tiles.has(q):
		return true
	for id in _town_rects.keys():
		if (_town_rects[id] as Rect2i).grow(1).has_point(q):
			return true
	for r in _road_block:
		if (r as Rect2i).has_point(q):
			return true
	return false


## 0.3.8 every town has a road to the capital; a trip between two towns runs
## town -> capital gate -> along the avenues through the plaza -> out the gate
## facing the other town (one continuous 8-connected tile list).
func _compose_capital_roads() -> void:
	if capital == "":
		return
	var c: Vector2i = towns[capital]["center"]
	for a in town_order:
		for b in town_order:
			if a == b or a == capital or b == capital or roads.has(a + "|" + b):
				continue
			var ra: Array = roads.get(a + "|" + capital, [])
			var rb: Array = roads.get(capital + "|" + b, [])
			if ra.is_empty() or rb.is_empty():
				continue
			var ga := gate_outside(capital, ra[-1])
			var gb := gate_outside(capital, rb[0])
			var mid: Array = _line8(ra[-1], ga) + _line8(ga, c) + _line8(c, gb) + _line8(gb, rb[0])
			var out: Array = ra.duplicate()
			for q in mid:
				if q != out[-1]:
					out.append(q)
			for q in rb:
				if q != out[-1]:
					out.append(q)
			roads[a + "|" + b] = out


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Tiles from a to b (inclusive), 4-connected steps (no corner cutting).
func _line8(a: Vector2i, b: Vector2i) -> Array:
	var out: Array = [a]
	var p := a
	var guard := 0
	while p != b and guard < 4000:
		guard += 1
		var d := b - p
		if absi(d.x) >= absi(d.y):
			p.x += signi(d.x)
		else:
			p.y += signi(d.y)
		out.append(p)
	return out


## 0.3.8 a winding dirt road from a village gate to its town (data/world.json
## village_roads): same A*, more meander, 2 tiles wide.
func _build_village_road(vid: String, tid: String) -> void:
	var v: Dictionary = GameData.villages[vid]
	if not v.has("gate"):
		return
	var o := Vector2i(int(v["origin"][0]), int(v["origin"][1]))
	var g := o + Vector2i(int(v["gate"][0]), int(v["gate"][1]))
	var rows: Array = v["rows"]
	var rect := Rect2i(o, Vector2i(str(rows[0]).length(), rows.size()))
	var out_dir := Vector2i(0, 1)
	if g.y == rect.position.y: out_dir = Vector2i(0, -1)
	elif g.x == rect.position.x: out_dir = Vector2i(-1, 0)
	elif g.x == rect.end.x - 1: out_dir = Vector2i(1, 0)
	var start := g + out_dir
	var goal := gate_outside(tid, start)
	if goal == Vector2i(1 << 30, 0):
		goal = towns[tid]["center"]
	var keep := _road_cfg
	_road_cfg = keep.duplicate()
	_road_cfg["meander"] = float(keep.get("village_meander", 0.9))
	_road_cfg["margin"] = int(keep.get("village_margin", 70))
	# less direct: bend through a point pushed sideways off the straight line
	var mid := (start + goal) / 2
	var dv := Vector2(goal - start)
	var side := 1.0 if hash01(start.x, start.y, 51) < 0.5 else -1.0
	var bend := Vector2(-dv.y, dv.x).normalized() * dv.length() * float(keep.get("village_bend", 0.2)) * side
	var mq := mid + Vector2i(roundi(bend.x), roundi(bend.y))
	for k in 12:          # slide the bend point back towards the line until it is open land
		if _road_cost(mq.x, mq.y) > 0.0 and _road_cost(mq.x, mq.y) < 3.0:
			break
		mq = mid + Vector2i(roundi(bend.x * (1.0 - (k + 1) / 12.0)), roundi(bend.y * (1.0 - (k + 1) / 12.0)))
	var raw := _road_astar(start, mq)
	var raw2 := _road_astar(mq, goal)
	if raw.is_empty() or raw2.is_empty():
		raw = _road_astar(start, goal)
	else:
		raw.pop_back()
		raw += raw2
	_road_cfg = keep
	if raw.is_empty():
		push_error("WorldGen: no village road %s -> %s" % [vid, tid])
		return
	var rt: Rect2i = (_town_rects[tid] as Rect2i).grow(1)
	var tiles: Array = raw.filter(func(p): return not rt.has_point(p))
	village_roads[vid] = tiles
	_stamp_road("v:" + vid + "|" + tid, tiles, TileType.ROAD_DIRT, int(keep.get("village_width", 2)))


## 0.3.8 roadside decorations just beyond the road edge: fence runs, rocks,
## bushes and old logs. They block walking (objects.json) but not arrows
## (Combat.line_of_sight ignores objects). Never near gates or bridges.
func _place_road_decor() -> void:
	var dc: Dictionary = _road_cfg.get("decor", {})
	var lists: Array = []
	for k in roads.keys():
		var ab: PackedStringArray = str(k).split("|")
		if ab[0] < ab[1] and (ab[0] == capital or ab[1] == capital or capital == ""):
			lists.append(roads[k])
	for vid in village_roads.keys():
		lists.append(village_roads[vid])
	var skip := int(dc.get("gate_skip", 10))
	# 0.3.9 which road owns each centre tile (-1 = shared): fences leave junctions open
	var owner := {}
	for li in lists.size():
		for t in lists[li]:
			owner[t] = li if owner.get(t, li) == li else -1
	var jr := int(dc.get("junction_gap", 4))
	for li in lists.size():
		var tiles: Array = lists[li]
		for i in range(skip, tiles.size() - skip):
			var p: Vector2i = tiles[i]
			var dir: Vector2i = (tiles[mini(i + 1, tiles.size() - 1)] - tiles[maxi(i - 1, 0)]).sign()
			var perp := Vector2i(-dir.y, dir.x)
			if perp == Vector2i.ZERO or road_tiles.get(p, -1) == TileType.BRIDGE:
				continue
			var fence_run: bool = (i / int(dc.get("fence_run", 7))) % int(dc.get("fence_every", 6)) == 0
			for sgn in [1, -1]:
				var q: Vector2i = p + perp * sgn
				while road_tiles.has(q):
					q += perp * sgn
				q += perp * sgn          # one tile of verge between road and decor
				if road_decor.has(q) or road_tiles.has(q) or _blocked_for_road(q) or in_clear_rect(q):
					continue
				var t := _terrain_at(q.x, q.y)
				if not (t in GRASS_TILES or t == TileType.DIRT) or is_pk(q) or not mine_at(q, 3).is_empty():
					continue
				var r := hash01(q.x, q.y, 41)
				if fence_run and t in GRASS_TILES and not _near_other_road(q, li, owner, jr):
					road_decor[q] = "road_fence"
				elif r < float(dc.get("chance", 0.07)):
					var pick := hash01(q.x, q.y, 42)
					road_decor[q] = "boulder" if pick < 0.3 else ("bush" if pick < 0.65 else "old_log")
	_prune_short_fences(int(dc.get("fence_min_run", 3)))


## 0.3.9.1 every fence is a straight-joined run of >= min_run tiles: road fences
## in shorter 4-connected runs (lone posts, diagonal steps) are removed.
func _prune_short_fences(min_run: int) -> void:
	var seen := {}
	for q in road_decor.keys():
		if road_decor.get(q, "") != "road_fence" or seen.has(q):
			continue
		var comp := fence_run_at(q)
		for c in comp:
			seen[c] = true
		if comp.size() < min_run:
			for c in comp:
				if road_decor.get(c, "") == "road_fence":
					road_decor.erase(c)


## The 4-connected run of fence tiles (any fence object) containing q.
func fence_run_at(q: Vector2i) -> Array:
	var out: Array = []
	var stack: Array = [q]
	var seen := {q: true}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		out.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and autotile_group_at(n) == "fence_rural":
				seen[n] = true
				stack.append(n)
	return out


func _near_other_road(q: Vector2i, li: int, owner: Dictionary, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var o: int = owner.get(q + Vector2i(dx, dy), li)
			if o != li:
				return true
	return false


## Tiles just outside each city gate (middle gate cell + one step out).
func gate_outsides(tid: String) -> Array:
	var out: Array = []
	var t: Dictionary = towns.get(tid, {})
	var gates: Dictionary = t.get("gates", {})
	if gates.is_empty():
		return out
	var origin := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
	for dir in gates.keys():
		var cells: Array = gates[dir]
		if cells.is_empty():
			continue
		var m: Array = cells[mini(1, cells.size() - 1)]
		var step: Vector2i = {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "west": Vector2i(-1, 0), "east": Vector2i(1, 0)}.get(str(dir), Vector2i.ZERO)
		out.append(origin + Vector2i(int(m[0]), int(m[1])) + step)
	return out


## The gate-outside tile of `tid` nearest to `toward` (or (1<<30, 0) if the town has no gates).
func gate_outside(tid: String, toward: Vector2i) -> Vector2i:
	var best := Vector2i(1 << 30, 0)
	var bd := INF
	for q in gate_outsides(tid):
		var d := Vector2(q - toward).length()
		if d < bd:
			bd = d
			best = q
	return best


## 0.3.1 village footprints (core + fields + pastures, from data) that roads keep out of.
func _village_footprints(cfg: Dictionary) -> Array:
	var out: Array = []
	for vid in cfg.get("villages", []):
		var v: Dictionary = GameData.villages.get(vid, {})
		if v.is_empty():
			continue
		var o := Vector2i(int(v["origin"][0]), int(v["origin"][1]))
		var rows: Array = v["rows"]
		var r := Rect2i(o, Vector2i(str(rows[0]).length(), rows.size()))
		for k in ["farms", "pastures"]:
			for f in v.get(k, []):
				var a: Array = f["rect"]
				r = r.merge(Rect2i(o + Vector2i(int(a[0]), int(a[1])), Vector2i(int(a[2]), int(a[3]))))
		out.append(r.grow(1))
	return out


func _road_cost(x: int, y: int) -> float:
	var p := Vector2i(x, y)
	for id in _town_rects.keys():
		if (_town_rects[id] as Rect2i).has_point(p):
			return 1.0 if towns[id].get("gates", {}).is_empty() else -1.0   # walled: only via the gates
	for r in _road_block:
		if (r as Rect2i).has_point(p):
			return -1.0
	var t := _terrain_at(x, y)
	if t == TileType.WATER:
		if land_value(x, y) < OCEAN_LEVEL:
			return -1.0                                 # ocean: never
		return float(_road_cfg.get("bridge_cost", 9.0))
	var c := 1.0
	match t:
		TileType.MARSH: c = float(_road_cfg.get("marsh_cost", 1.8))
		TileType.SAND: c = float(_road_cfg.get("sand_cost", 1.3))
		TileType.DIRT: c = float(_road_cfg.get("dirt_cost", 1.1))
	if is_pk(p):
		c += float(_road_cfg.get("pk_cost", 20.0))     # roads keep out of the Scorch
	return c * (1.0 + float(_road_cfg.get("meander", 0.35)) * (_moist.get_noise_2d(x * 3.1, y * 3.1) + 1.0) * 0.5)


func _road_astar(pa: Vector2i, pb: Vector2i) -> Array:
	var m := int(_road_cfg.get("margin", 90))
	var r := Rect2i(Vector2i(mini(pa.x, pb.x), mini(pa.y, pb.y)), (pa - pb).abs() + Vector2i.ONE).grow(m)
	var w := r.size.x
	var hgt := r.size.y
	var n := w * hgt
	var ox := r.position.x
	var oy := r.position.y
	var bw := float(_road_cfg.get("bridge_cost", 9.0)) * 0.999   # 0.3.8 float32 cost cells: 1.05 stored as 1.0499999
	var hw := float(_road_cfg.get("heuristic_weight", 1.0))
	var cost := PackedFloat32Array()
	cost.resize(n)
	cost.fill(0.0)                    # 0 = not evaluated yet
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap: Array = []
	var s: int = (pa.y - oy) * w + (pa.x - ox)
	var goal: int = (pb.y - oy) * w + (pb.x - ox)
	g[s] = 0.0
	cost[s] = 1.0
	var counter := 0
	Pathfinder._push(heap, [0.0, 0, s])
	var dxs := [1, -1, 0, 0, 1, 1, -1, -1]
	var dys := [0, 0, 1, -1, 1, -1, 1, -1]
	while not heap.is_empty():
		var cur: int = Pathfinder._pop(heap)[2]
		if closed[cur] == 1:
			continue
		if cur == goal:
			break
		closed[cur] = 1
		var cx := cur % w
		var cy := cur / w
		var here_water: bool = cost[cur] >= bw
		var gc: float = g[cur]
		for k in 8:
			var qx: int = cx + dxs[k]
			var qy: int = cy + dys[k]
			if qx < 0 or qy < 0 or qx >= w or qy >= hgt:
				continue
			var i := qy * w + qx
			if closed[i] == 1:
				continue
			var c: float = cost[i]
			if c == 0.0:
				c = _road_cost(qx + ox, qy + oy)
				cost[i] = c
			if c < 0.0:
				continue
			var step := 1.0
			if k >= 4:
				if here_water or c >= bw:
					continue
				var ia := cy * w + qx
				var ib := qy * w + cx
				var ca: float = cost[ia]
				if ca == 0.0:
					ca = _road_cost(qx + ox, cy + oy)
					cost[ia] = ca
				var cb: float = cost[ib]
				if cb == 0.0:
					cb = _road_cost(cx + ox, qy + oy)
					cost[ib] = cb
				if ca < 0.0 or cb < 0.0 or ca >= bw or cb >= bw:
					continue              # no diagonal steps on or past water: bridges are 4-connected
				step = 1.4142
			var ng: float = gc + step * c
			if ng < g[i]:
				g[i] = ng
				came[i] = cur
				counter += 1
				var dx := absi(qx + ox - pb.x)
				var dy := absi(qy + oy - pb.y)
				Pathfinder._push(heap, [ng + ((dx + dy) - 0.5858 * mini(dx, dy)) * hw, counter, i])
	if came[goal] == -1:
		return []
	var out: Array = []
	var c2 := goal
	while c2 != -1:
		out.append(Vector2i(ox + c2 % w, oy + c2 / w))
		c2 = came[c2]
	out.reverse()
	return out


func road_between(a: String, b: String) -> Array:
	return roads.get(a + "|" + b, [])


func town_spawn(id: String = "") -> Vector2i:
	var t: Dictionary = towns.get(id, villages.get(id, _town)) if id != "" else _town
	if t.is_empty():
		return Vector2i.ZERO
	return Vector2i(int(t["spawn"][0]), int(t["spawn"][1]))


func town_center(id: String) -> Vector2i:
	if towns.has(id):
		return towns[id]["center"]
	return villages[id]["center"] if villages.has(id) else Vector2i.ZERO


func town_name(id: String) -> String:
	return str(towns.get(id, villages.get(id, {})).get("name", id.capitalize()))


func in_town(p: Vector2i) -> bool:
	return town_at(p, 0) != ""


## Town whose rectangle (grown by `margin`) contains p, else "".
func town_at(p: Vector2i, margin: int = 6) -> String:
	for id in _town_rects.keys():
		if (_town_rects[id] as Rect2i).grow(margin).has_point(p):
			return id
	return ""


func nearest_town(p: Vector2i) -> String:
	var best := ""
	var bd := INF
	for id in towns.keys():
		var d := Vector2(p - town_center(id)).length()
		if d < bd:
			bd = d
			best = id
	return best


## 0..1 influence of town `id`'s region at p (1 at the town, 0 beyond REGION_RADIUS).
func region_weight(id: String, x: int, y: int) -> float:
	if not towns.has(id):
		return 0.0
	var d := Vector2(Vector2i(x, y) - town_center(id)).length()
	return clampf(1.0 - d / REGION_RADIUS, 0.0, 1.0)


func _biome_weight(biome: String, x: int, y: int) -> float:
	var w := 0.0
	for id in regions.keys():
		if regions[id].get("biome", "") == biome:
			w = maxf(w, region_weight(id, x, y))
	return w


func bounds() -> Rect2i:
	var r := int(continent_radius * 1.2)
	return Rect2i(continent_center - Vector2i(r, r), Vector2i(r * 2, r * 2))


## Continent "landness": > OCEAN_LEVEL is land.
func land_value(x: int, y: int) -> float:
	var d := Vector2(Vector2i(x, y) - continent_center).length()
	if d > continent_radius * 1.15:
		return -1.0
	var v := 1.0 - d / continent_radius + _coast.get_noise_2d(x, y) * 0.45
	for id in towns.keys():
		var dt := Vector2(Vector2i(x, y) - town_center(id)).length()
		if dt < TOWN_DRY_RADIUS:
			v += (TOWN_DRY_RADIUS - dt) / TOWN_DRY_RADIUS * 0.6
	return v


## Integer hash -> [0,1). Stable across platforms (64-bit int math, masked).
## Seed-independent hash (0.3.9 autotile deterioration: same look in every world).
static func hash01_static(x: int, y: int, salt: int = 0) -> float:
	var n: int = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xffffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
	n = n ^ (n >> 16)
	return float(n & 0xffffff) / 16777216.0


func hash01(x: int, y: int, salt: int = 0) -> float:
	var n: int = (x * 374761393 + y * 668265263 + (world_seed + salt) * 2246822519) & 0xffffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
	n = n ^ (n >> 16)
	return float(n & 0xffffff) / 16777216.0


## Tile type at any world tile, without needing a chunk.
func tile_at(x: int, y: int) -> int:
	var p := Vector2i(x, y)
	if _town_tiles.has(p):
		return _town_tiles[p]
	if road_tiles.has(p):
		return road_tiles[p]
	var t := _terrain_at(x, y)
	if t == TileType.WATER:
		return t
	var z := _biome_zone_at(p)
	if not z.is_empty() and str(z.get("biome", "")) == "scorch":
		var zr: Rect2i = z["r"]
		var edge := mini(mini(p.x - zr.position.x, zr.end.x - 1 - p.x), mini(p.y - zr.position.y, zr.end.y - 1 - p.y))
		return TileType.ASH_EDGE if edge < int(z.get("edge_tiles", 2)) else TileType.ASH
	var mn := mine_at(p, 1)
	if not mn.is_empty() and str(mn.get("ground", "dirt")) == "dirt" and _mine_ground(p, mn):
		return TileType.DIRT
	var ct := _cliff_tile(p, t)
	if ct >= 0:
		return ct
	return t


# ------------------------------------------------------ 0.3.10 cliffs --
## Terrace level for cliff comparisons (beaches behind a sea cliff drop one).
func cliff_level(q: Vector2i) -> int:
	var l := region_map.level(q)
	if region_map.sea_cliff(q) and _is_beach(q):
		l -= 1
	return l


func _is_beach(q: Vector2i) -> bool:
	return land_value(q.x, q.y) < _beach_level(q)


func _beach_level(q: Vector2i) -> float:
	return BEACH_LEVEL + region_map.field(q, "beach_bonus")


## No cliffs in or around towns, villages, fields, mines, the Scorch or water.
func cliff_free(q: Vector2i) -> bool:
	if town_at(q, _keep_clear) != "" or village_at(q, _keep_clear) != "":
		return true
	if not mine_at(q, 3).is_empty() or not _biome_zone_at(q).is_empty():
		return true
	for r in _clear_rects:
		if (r as Rect2i).grow(3).has_point(q):
			return true
	return false


## Walkable ramp / stone stairs: near any road or authored tile, and where a
## cliff run crosses the coarse gap grid (every ramp_period tiles both ways):
## vertical gap strips cut east-west cliff runs, horizontal strips cut
## north-south runs. Any pocket larger than one grid cell must cross a strip
## that way, so no cliff line walls an area off -> every area stays reachable.
## `ns` = the lower side is north/south (an east-west run).
func is_ramp(q: Vector2i, ns: bool = true) -> bool:
	if ns and posmod(q.x, _ramp_period) < _ramp_width:
		return true
	if not ns and posmod(q.y, _ramp_period) < _ramp_width:
		return true
	for dy in range(-_road_ramp, _road_ramp + 1):
		for dx in range(-_road_ramp, _road_ramp + 1):
			var r := q + Vector2i(dx, dy)
			if road_tiles.has(r) or _town_tiles.has(r):
				return true
	return false


## Edge of a higher terrace: -1 none, 0 = lip with the lower side east/west,
## 1 = face (lower ground south), 2 = lip with the lower side north.
func _cliff_edge(p: Vector2i) -> int:
	var l := cliff_level(p)
	var res := -1
	for k in 4:
		var q: Vector2i = p + [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)][k]
		if cliff_level(q) < l and _terrain_at(q.x, q.y) != TileType.WATER:
			res = [1, 0, 0, 2][k]
			break
	if res < 0 or _is_beach(p) or cliff_free(p):
		return -1
	return res


## The cliff tile at p (or -1): face / lip / stairs on the high edge, shadow below a face.
func _cliff_tile(p: Vector2i, t: int) -> int:
	if t == TileType.WATER or t == TileType.ASH or t == TileType.ASH_EDGE:
		return -1
	var e := _cliff_edge(p)
	if e >= 0:
		return TileType.CLIFF_STAIRS if is_ramp(p, e != 0) or _extra_ramp(p) else (TileType.CLIFF_FACE if e == 1 else TileType.CLIFF_LIP)
	var n := p + Vector2i(0, -1)
	if cliff_level(p) < cliff_level(n) and _cliff_edge(n) == 1 and not is_ramp(n, true) and not _extra_ramp(n):
		return TileType.CLIFF_SHADOW
	return -1


# 0.3.10 per-cell pocket check: a small basin or knoll can close a cliff ring
# inside one ramp-grid cell. The first time a cell is asked, flood-fill it (plus
# a 2-tile rim) from its border; every walkable pocket that is not reached gets
# one cliff tile turned into stairs, next to reached ground. Cached per cell,
# deterministic (terrain + roads + towns only), so every area stays reachable.
var _cell_ramps: Dictionary = {}     # Vector2i cell -> {Vector2i: true}
var _cells_ready := false            # set at the end of _init (roads + villages known)


func _extra_ramp(p: Vector2i) -> bool:
	if not _cells_ready:
		return false
	var c := Vector2i(floori(float(p.x) / _ramp_period), floori(float(p.y) / _ramp_period))
	var hit = _cell_ramps.get(c)
	if hit == null:
		if _cell_ramps.size() > 4000:
			_cell_ramps.clear()
		hit = _analyse_cell(c)
		_cell_ramps[c] = hit
	return (hit as Dictionary).has(p)


func _analyse_cell(c: Vector2i) -> Dictionary:
	var extra := {}
	var o := c * _ramp_period - Vector2i(2, 2)
	var n := _ramp_period + 4
	var blk := PackedByteArray()      # 0 walkable, 1 cliff, 2 water
	blk.resize(n * n)
	var any_cliff := false
	for j in n:
		for i in n:
			var q := o + Vector2i(i, j)
			if _town_tiles.has(q) or road_tiles.has(q):
				continue
			if _terrain_at(q.x, q.y) == TileType.WATER:
				blk[j * n + i] = 2
				continue
			var e := _cliff_edge(q)
			if e >= 0 and not is_ramp(q, e != 0):
				blk[j * n + i] = 1
				any_cliff = true
	if not any_cliff:
		return extra
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
	for _iter in 12:
		var seen := PackedByteArray()
		seen.resize(n * n)
		var queue: Array = []
		for j in n:
			for i in n:
				if (i == 0 or j == 0 or i == n - 1 or j == n - 1) and blk[j * n + i] == 0:
					seen[j * n + i] = 1
					queue.append(Vector2i(i, j))
		var h := 0
		while h < queue.size():
			var v: Vector2i = queue[h]
			h += 1
			for d in dirs:
				var w: Vector2i = v + d
				if w.x >= 0 and w.y >= 0 and w.x < n and w.y < n and seen[w.y * n + w.x] == 0 and blk[w.y * n + w.x] == 0:
					seen[w.y * n + w.x] = 1
					queue.append(w)
		var pocket := -1
		for k in n * n:
			if blk[k] == 0 and seen[k] == 0:
				pocket = k
				break
		if pocket < 0:
			break
		# walk the pocket; open the first rim cliff whose far side is reached ground (else any rim cliff)
		var comp: Array = [Vector2i(pocket % n, pocket / n)]
		var inq := {comp[0]: true}
		var best := Vector2i(-1, -1)
		var fallback := Vector2i(-1, -1)
		var hh := 0
		while hh < comp.size() and best.x < 0:
			var v: Vector2i = comp[hh]
			hh += 1
			for d in dirs:
				var w: Vector2i = v + d
				if w.x < 0 or w.y < 0 or w.x >= n or w.y >= n:
					continue
				var b := blk[w.y * n + w.x]
				if b == 0 and not inq.has(w):
					inq[w] = true
					comp.append(w)
				elif b == 1:
					if fallback.x < 0:
						fallback = w
					var o2: Vector2i = w + d
					if o2.x >= 0 and o2.y >= 0 and o2.x < n and o2.y < n and seen[o2.y * n + o2.x] == 1:
						best = w
						break
		var pick := best if best.x >= 0 else fallback
		if pick.x < 0:
			break
		blk[pick.y * n + pick.x] = 0
		extra[o + pick] = true
	return extra


## Region-coloured open ground for a dithered region pick.
func region_grass(p: Vector2i) -> int:
	var rid := region_map.ground_region(p, hash01(p.x, p.y, 31))
	match str(region_map.def(rid).get("grass", "grass")):
		"grass_lush": return TileType.GRASS_LUSH
		"grass_boreal": return TileType.GRASS_BOREAL
		"grass_tropic": return TileType.GRASS_TROPIC
	return TileType.GRASS


## The generated terrain alone (no towns, roads, Scorch or mine ground).
func _terrain_at(x: int, y: int) -> int:
	var p := Vector2i(x, y)
	var v := land_value(x, y)
	if v < OCEAN_LEVEL:
		return TileType.WATER          # the ocean: impassable
	if v < _beach_level(p):
		return TileType.SAND
	var h := _height.get_noise_2d(x, y)
	# keep a dry ring around towns so they never flood
	for id in towns.keys():
		var dt := Vector2(p - town_center(id)).length()
		if dt < 34.0:
			h += (34.0 - dt) / 34.0 * 0.5
	if h < -0.34:
		return TileType.WATER          # inland lakes
	if h < -0.27:
		return TileType.SAND
	# 0.3.10 ground mix by lore region (data/regions.json), dithered at borders
	var rb := region_map.blend_at(p)
	var marsh := region_map.field_b(rb, "marsh")
	var m := _moist.get_noise_2d(x, y)
	if m > 0.32 - marsh * 0.25 and h < 0.05 + marsh * 0.15:
		return TileType.MARSH
	var dn := _detail.get_noise_2d(x, y)
	if dn > 0.62 - region_map.field_b(rb, "rocky") * 0.75:
		return TileType.ROCKY
	if _detail.get_noise_2d(x + 7000, y - 3000) > 0.5 - region_map.field_b(rb, "dirt") * 1.2:
		return TileType.DIRT
	return region_grass(p)


## True for tiles that are road over lake water (a bridge).
func is_bridge(p: Vector2i) -> bool:
	return int(road_tiles.get(p, -1)) == TileType.BRIDGE


# ------------------------------------------------------- 0.3.1 PK zones --
func _load_pk_zones() -> void:
	pk_zones.clear()
	for z in GameData.pk_zones.get("zones", []):
		var a: Array = z.get("rect", [0, 0, 0, 0])
		var zz: Dictionary = (z as Dictionary).duplicate(true)
		zz["r"] = Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
		pk_zones.append(zz)


## Terrain only (ash biome): the zone dict with its "r" Rect2i, from the
## world data loaded at generation (unaffected by PkRules test overrides).
func _biome_zone_at(p: Vector2i) -> Dictionary:
	for z in pk_zones:
		if (z["r"] as Rect2i).has_point(p):
			return z
	return {}


## PK zone holding p, else {}. Rules, HUD and AI all go through PkRules
## (the one is_pk helper; same data/pk_zones.json via GameData.pk_zones).
func pk_zone_at(p: Vector2i) -> Dictionary:
	return PkRules.zone_at(p)


func is_pk(p: Vector2i) -> bool:
	return PkRules.is_pk(p)


# --------------------------------------------------------- 0.3.1 mines --
## data/mines.json: named clusters; rocks spawn ONLY inside them.
func _load_mines() -> void:
	mines.clear()
	_mine_grid.clear()
	for md in GameData.mines.get("mines", []):
		var m: Dictionary = (md as Dictionary).duplicate(true)
		m["c"] = Vector2i(int(md["center"][0]), int(md["center"][1]))
		m["radius"] = float(md.get("radius", 6))
		m["pk"] = is_pk(m["c"])
		var tot := 0.0
		for k in m.get("ores", {}).keys():
			tot += float(m["ores"][k])
		m["_tot"] = maxf(tot, 0.0001)
		mines.append(m)
		var rr := int(ceil(float(m["radius"]))) + 3
		var c0 := Vector2i(floori(float(m["c"].x - rr) / CHUNK), floori(float(m["c"].y - rr) / CHUNK))
		var c1 := Vector2i(floori(float(m["c"].x + rr) / CHUNK), floori(float(m["c"].y + rr) / CHUNK))
		for cy in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var k2 := Vector2i(cx, cy)
				if not _mine_grid.has(k2):
					_mine_grid[k2] = []
				_mine_grid[k2].append(mines.size() - 1)


## Mine whose (ragged) area holds p, grown by `margin` tiles, else {}.
func mine_at(p: Vector2i, margin: int = 0) -> Dictionary:
	var k := Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))
	for i in _mine_grid.get(k, []):
		var m: Dictionary = mines[i]
		if Vector2(p - (m["c"] as Vector2i)).length() <= float(m["radius"]) + margin + 0.5:
			return m
	return {}


func _mine_ground(p: Vector2i, m: Dictionary) -> bool:
	var d := Vector2(p - (m["c"] as Vector2i)).length()
	return d <= float(m["radius"]) + (hash01(p.x, p.y, 13) * 2.0 - 0.5)


func mine_by_id(id: String) -> Dictionary:
	for m in mines:
		if str(m["id"]) == id:
			return m
	return {}


## Mines that yield the rock object `def_id` (e.g. "iron_rock").
func mines_with(def_id: String) -> Array:
	return mines.filter(func(m): return float(m.get("ores", {}).get(def_id, 0.0)) > 0.0)


## Closest mine with `def_id` to `from` (outside PK zones unless allow_pk).
func nearest_mine(from: Vector2i, def_id: String, allow_pk: bool = false) -> Dictionary:
	var best := {}
	var bd := INF
	for m in mines_with(def_id):
		if bool(m["pk"]) and not allow_pk:
			continue
		var d := Vector2(from - (m["c"] as Vector2i)).length()
		if d < bd:
			bd = d
			best = m
	return best


## Distance (tiles) from p to the nearest town's rectangle (0 inside a town).
func town_edge_distance(p: Vector2i) -> float:
	var best := INF
	for id in _town_rects.keys():
		var r: Rect2i = _town_rects[id]
		var dx := maxi(maxi(r.position.x - p.x, 0), p.x - (r.end.x - 1))
		var dy := maxi(maxi(r.position.y - p.y, 0), p.y - (r.end.y - 1))
		best = minf(best, Vector2(dx, dy).length())
	return best


## Distance (tiles) to the nearest town centre.
func town_distance(x: int, y: int) -> float:
	var best := INF
	for id in towns.keys():
		best = minf(best, Vector2(Vector2i(x, y) - town_center(id)).length())
	return best


## Object id (or "") generated at a tile. 0.3.1: rocks ONLY in the named
## mines of data/mines.json (ore mix per mine); trees thin out by distance as
## before; the Scorch gets burnt trees, stumps and embers instead.
## 0.3.9 autotile group of the placed fence/wall object at p ("" if none).
func autotile_group_at(p: Vector2i) -> String:
	var id: String = _town_objects.get(p, road_decor.get(p, ""))
	if id == "":
		return ""
	return str(GameData.sprite_def("objects", str(GameData.objects.get(id, {}).get("sprite", id))).get("autotile", ""))


func object_at(x: int, y: int, tile: int) -> String:
	var p := Vector2i(x, y)
	if _town_objects.has(p):
		return _town_objects[p]
	if road_decor.has(p):
		return road_decor[p]
	if town_at(p, 0) != "" or road_tiles.has(p) or _town_tiles.has(p) or village_at(p, 0) != "" or in_clear_rect(p):
		return ""
	var r := hash01(x, y, 1)
	var r2 := hash01(x, y, 2)
	if tile != TileType.WATER:
		var mn := mine_at(p, 1)
		if not mn.is_empty():
			return _mine_rock(p, mn)
	var dist := town_distance(x, y)
	if tile in GRASS_TILES or tile == TileType.ROCKY:
		# 0.3.10 trees by lore region (data/regions.json): density + species mix,
		# dithered at borders; magic mushrooms in damp forest of Lower Ashfen / the Mere
		var rid := region_map.ground_region(p, hash01(x, y, 33))
		var rd := region_map.def(rid)
		var tc := float(rd.get("tree_chance", 0.065)) * (0.35 if tile == TileType.ROCKY else 1.0)
		if r > 1.0 - tc:
			return "" if _beside_stairs(p) else _pick_tree(rd, r2, dist)
		if tile == TileType.ROCKY and r < 0.035:
			return "" if _beside_stairs(p) else "boulder"
		if tile != TileType.ROCKY and r < float(rd.get("mushrooms", 0.0)) and _moist.get_noise_2d(x, y) > 0.0:
			return "magic_mushroom"
		return ""
	match tile:
		TileType.MARSH:
			if r > 0.93:
				return "fenroot_patch" if r2 < 0.4 else "reed_bed"
			if r < float(region_map.def(region_map.region_at(p)).get("mushrooms", 0.0)) * 1.5:
				return "magic_mushroom"
		TileType.ASH, TileType.ASH_EDGE:
			var dec: Dictionary = GameData.pk_zones.get("decor", {})
			if r > 1.0 - float(dec.get("burnt_tree", 0.05)):
				return "burnt_tree"
			if r > 1.0 - float(dec.get("burnt_tree", 0.05)) - float(dec.get("charred_stump", 0.02)):
				return "charred_stump"
			if r2 < float(dec.get("embers", 0.012)) or (tile == TileType.ASH_EDGE and r2 < float(dec.get("edge_embers", 0.12))):
				return "embers"
		TileType.WATER:
			if r > 0.975 - region_map.field(p, "sea_cliffs") * 0.01 and _touches_land(x, y):
				return "fishing_spot"
	return ""


## 0.3.10 keep the landing of every ramp / stairs clear (no tree or boulder plugs it).
func _beside_stairs(p: Vector2i) -> bool:
	for d in STAIR_CLEAR:
		if tile_at(p.x + d.x, p.y + d.y) == TileType.CLIFF_STAIRS:
			return true
	return false

const STAIR_CLEAR := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(2, 0), Vector2i(-2, 0),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


## 0.3.10 a tree species from a region's weights; higher tiers keep their distance from towns.
func _pick_tree(rd: Dictionary, r2: float, dist: float) -> String:
	var trees: Dictionary = rd.get("trees", {"ash_tree": 1})
	var mins: Dictionary = region_map.cfg.get("tree_min_town", {})
	var tot := 0.0
	for k in trees.keys():
		if dist >= float(mins.get(k, 0)):
			tot += float(trees[k])
	var pick := r2 * tot
	for k in trees.keys():
		if dist < float(mins.get(k, 0)):
			continue
		pick -= float(trees[k])
		if pick <= 0.0:
			return str(k)
	return "ash_tree"


## A rock (or "") at p inside mine m: density falls off towards the rim.
func _mine_rock(p: Vector2i, m: Dictionary) -> String:
	var d := Vector2(p - (m["c"] as Vector2i)).length()
	var rad := float(m["radius"])
	if d > rad - 0.5:
		return ""
	var dens := float(m.get("density", 0.3)) * (1.0 - 0.45 * d / maxf(1.0, rad))
	if hash01(p.x, p.y, 11) >= dens:
		return ""
	var pick := hash01(p.x, p.y, 12) * float(m["_tot"])
	for k in m["ores"].keys():
		pick -= float(m["ores"][k])
		if pick <= 0.0:
			return str(k)
	return str(m["ores"].keys()[-1])


func _touches_land(x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if tile_at(x + d.x, y + d.y) != TileType.WATER:
			return true
	return false


func generate_chunk(c: Vector2i) -> ChunkData:
	var ch := ChunkData.new(c)
	var ox := c.x * CHUNK
	var oy := c.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			var t := tile_at(ox + lx, oy + ly)
			ch.tiles[ly * CHUNK + lx] = t
	for ly in CHUNK:
		for lx in CHUNK:
			var wp := Vector2i(ox + lx, oy + ly)
			var obj := object_at(wp.x, wp.y, ch.tiles[ly * CHUNK + lx])
			if obj != "" and not GameData.object_def(obj).is_empty():
				ch.objects[wp] = WorldObject.new(obj, wp)
				if _town_meta.has(wp):
					ch.objects[wp].meta = _town_meta[wp]
	return ch
