extends Node
## Loads all data-driven definitions (items, skills, world objects, recipes,
## AI personas, towns) from res://data/*.json and caches textures.
## Everything gameplay-tunable lives in JSON so designers can balance without code.

const DATA_DIR := "res://data/"

var items: Dictionary = {}
var currency: String = "marks"
var skills: Array = []            # ordered skill defs
var skill_by_id: Dictionary = {}
var max_level: int = 60
var xp_base: float = 100.0
var xp_growth: float = 1.085
var objects: Dictionary = {}
var recipes: Array = []
var personas: Array = []
var name_parts: Dictionary = {}
var enemies: Dictionary = {}      # data/enemies.json "enemies"
var camps: Array = []             # data/enemies.json "camps"
var drop_tables: Dictionary = {}  # data/drops.json "tables"
var prayers: Dictionary = {}      # data/prayers.json
var ai_chatter: Dictionary = {}   # 0.3.3 data/ai_chatter.json (AIChatter)
var ground_rules: Dictionary = {} # data/drops.json "ground" (private window, TTLs, AI looting)
var combat_zones: Dictionary = {} # data/combat_zones.json (single-way default, multi zones)
var fx: Dictionary = {}           # data/fx.json (hitsplat lifetime etc.)
var combat: Dictionary = {}       # data/combat.json (weapon classes, styles, defence XP, set bonus)
var player_cfg: Dictionary = {}   # data/player.json (energy / sprint)
var buildings_cfg: Dictionary = {}  # data/buildings.json (0.3.0 shop look + talk)
var player_shop_cfg: Dictionary = {}  # data/player_shop.json (0.3.0 player-owned shops)
var mines: Dictionary = {}        # data/mines.json (0.3.1 named mine clusters, travel factor)
var pk_zones: Dictionary = {}     # data/pk_zones.json (0.3.1 the Scorch: rect, warning, decor)
var town_npcs: Dictionary = {}    # data/town_npcs.json (0.3.1 guards + citizens per town)
var churches: Dictionary = {}      # data/churches.json (0.3.1 stone church + altar per town)
var enemy_bands: Dictionary = {}  # data/enemy_bands.json (0.3.1 distance-from-town band per enemy kind)
var map_markers_cfg: Dictionary = {}  # data/map_markers.json (0.3.1 custom map markers)
var daynight_cfg: Dictionary = {}  # data/daynight.json (0.3.1 day/night cycle)
var towns: Dictionary = {}
var villages: Dictionary = {}     # 0.3.1 data/towns/<id>.json with kind "village" (world.json "villages")
var villages_cfg: Dictionary = {} # data/villages.json (greetings, path search)
var world: Dictionary = {}        # data/world.json (continent, town list, roads)
var sprites: Dictionary = {}      # data/sprites.json: the ONLY id -> PNG mapping
var tile_size: int = 16
var tile_ids: Array = []          # tile type names in index order (WorldGen ids)

var _xp_table: PackedInt64Array = PackedInt64Array()
var _tex_cache: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	var it: Dictionary = _load_json("items.json")
	items = it.get("items", {})
	currency = it.get("currency", "marks")
	var sk: Dictionary = _load_json("skills.json")
	skills = sk.get("skills", [])
	max_level = int(sk.get("max_level", 60))
	var curve: Dictionary = sk.get("xp_curve", {})
	xp_base = float(curve.get("base", 100.0))
	xp_growth = float(curve.get("growth", 1.085))
	skill_by_id.clear()
	for s in skills:
		skill_by_id[s["id"]] = s
	objects = _load_json("objects.json").get("objects", {})
	recipes = _load_json("recipes.json").get("recipes", [])
	var pe: Dictionary = _load_json("personas.json")
	personas = pe.get("personas", [])
	name_parts = pe.get("name_parts", {})
	var en: Dictionary = _load_json("enemies.json")
	enemies = en.get("enemies", {})
	camps = en.get("camps", [])
	var dr: Dictionary = _load_json("drops.json")
	drop_tables = dr.get("tables", {})
	ground_rules = dr.get("ground", {})
	combat_zones = _load_json("combat_zones.json")
	fx = _load_json("fx.json")
	combat = _load_json("combat.json")
	player_cfg = _load_json("player.json")
	buildings_cfg = _load_json("buildings.json")
	player_shop_cfg = _load_json("player_shop.json")
	mines = _load_json("mines.json")
	pk_zones = _load_json("pk_zones.json")
	town_npcs = _load_json("town_npcs.json")
	churches = _load_json("churches.json")
	enemy_bands = _load_json("enemy_bands.json")
	map_markers_cfg = _load_json("map_markers.json")
	daynight_cfg = _load_json("daynight.json")
	villages_cfg = _load_json("villages.json")
	prayers = _load_json("prayers.json")
	ai_chatter = _load_json("ai_chatter.json")
	towns.clear()
	world = _load_json("world.json")
	for tid in world.get("towns", ["fenhollow"]):
		var t: Dictionary = _load_json("towns/%s.json" % tid)
		if not t.is_empty():
			towns[t["id"]] = t
	villages.clear()
	for vid in world.get("villages", []):
		var v: Dictionary = _load_json("towns/%s.json" % vid)
		if not v.is_empty():
			villages[v["id"]] = v
	sprites = _load_json("sprites.json")
	tile_size = int(sprites.get("tile_size", 16))
	var tiles: Dictionary = sprites.get("tiles", {})
	tile_ids = tiles.keys()
	tile_ids.sort_custom(func(a, b): return int(tiles[a].get("_order", 0)) < int(tiles[b].get("_order", 0)))
	_tex_cache.clear()
	_build_xp_table()


func _load_json(rel: String) -> Dictionary:
	var path := DATA_DIR + rel
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: bad JSON in %s" % path)
		return {}
	return parsed


# ---------------------------------------------------------------- XP curve --
func _build_xp_table() -> void:
	_xp_table.resize(max_level + 2)
	for lvl in range(0, max_level + 2):
		if lvl <= 1:
			_xp_table[lvl] = 0
		else:
			_xp_table[lvl] = int(floor(xp_base * (pow(xp_growth, lvl - 1) - 1.0) / (xp_growth - 1.0)))


## Total XP needed to reach `level`.
func xp_for_level(level: int) -> int:
	level = clampi(level, 1, max_level + 1)
	return _xp_table[level]


func level_for_xp(xp: int) -> int:
	var lvl := 1
	while lvl < max_level and xp >= _xp_table[lvl + 1]:
		lvl += 1
	return lvl


# ------------------------------------------------------------------ lookups --
func item(id: String) -> Dictionary:
	return items.get(id, {})


func item_name(id: String) -> String:
	return item(id).get("name", id)


func item_value(id: String) -> int:
	return int(item(id).get("value", 0))


func is_stackable(id: String) -> bool:
	return bool(item(id).get("stackable", false))


func object_def(id: String) -> Dictionary:
	return objects.get(id, {})


func recipes_for_station(station: String) -> Array:
	var out: Array = []
	for r in recipes:
		if r.get("station", "") == station:
			out.append(r)
	return out


# ------------------------------------------------------------------ sprites --
## Sprite definition for (category, id): {path, frame_size, frames, fps, anchor...}
## category is one of tiles / objects / actors / items / ui.
func sprite_def(category: String, id: String) -> Dictionary:
	return sprites.get(category, {}).get(id, {})


## Texture for a sprite id. Never returns null: unknown ids or missing files
## fall back to the magenta "missing" sprite so gaps are obvious in-game.
func texture(category: String, id: String) -> Texture2D:
	var d := sprite_def(category, id)
	var t: Texture2D = _tex(d.get("path", "")) if not d.is_empty() else null
	if t == null:
		if category == "items" and id != "unknown":
			return texture("items", "unknown")
		t = _tex(sprite_def("ui", "missing").get("path", ""))
	return t


## 0.3.9 actor sheet for a facing ("side" / "down" / "up"); falls back to the side sheet.
func actor_texture(id: String, dir: String) -> Texture2D:
	if dir != "side":
		var p: String = str(sprite_def("actors", id).get("dir_paths", {}).get(dir, ""))
		if p != "":
			var t := _tex(p)
			if t != null:
				return t
	return texture("actors", id)


func frame_size(category: String, id: String) -> Vector2i:
	var fs: Array = sprite_def(category, id).get("frame_size", [tile_size, tile_size])
	return Vector2i(int(fs[0]), int(fs[1]))


func frame_count(category: String, id: String) -> int:
	return int(sprite_def(category, id).get("frames", 1))


func icon(item_id: String) -> Texture2D:
	return texture("items", item_id)


var _tile_colors: Array = []


func tile_color(tile_index: int) -> Color:
	if _tile_colors.size() != tile_ids.size():
		_tile_colors.clear()
		for id in tile_ids:
			_tile_colors.append(Color(sprite_def("tiles", id).get("minimap_color", "#ff00ff")))
	if tile_index < 0 or tile_index >= _tile_colors.size():
		return Color.MAGENTA
	return _tile_colors[tile_index]


func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		push_warning("GameData: missing texture %s" % path)
	_tex_cache[path] = t
	return t
