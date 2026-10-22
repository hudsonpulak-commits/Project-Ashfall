class_name WorldRegions
extends RefCounted
## 0.3.10 the four lore regions (data/regions.json; docs/specs/Lore_2026-10-21.md):
## Cinder (north, cold boreal highlands), Central Ashfen (Highfen, rocky
## plateaus), Lower Ashfen (Fenhollow + Millbrook, fertile forest) and the Mere
## Lands (Saltmere, warm rainforest + beaches). Pure + seeded: the region at a
## tile is its nearest anchor after a noise warp; near a border the neighbour
## region dithers in over blend_tiles (soft biome transitions). Also owns the
## terrace elevation used for cliffs (WorldGen.cliff tiles).

var cfg: Dictionary
var ids: Array = []
var _anchors: Array = []        # [[Vector2, region id], ...]
var _warp := FastNoiseLite.new()
var _terrace := FastNoiseLite.new()
var _sea := FastNoiseLite.new()
var warp_tiles := 22.0
var blend_tiles := 26.0
var _cache: Dictionary = {}     # Vector2i -> [r1, r2, w1]
var _lcache: Dictionary = {}    # Vector2i -> terrace level
const CACHE_MAX := 60000


func _init(p_seed: int, p_cfg: Dictionary = {}) -> void:
	cfg = p_cfg if not p_cfg.is_empty() else GameData.regions_cfg
	ids = cfg.get("order", cfg.get("regions", {}).keys())
	for id in ids:
		for a in cfg["regions"][id].get("anchors", []):
			_anchors.append([Vector2(float(a[0]), float(a[1])), id])
	warp_tiles = float(cfg.get("warp_tiles", 22))
	blend_tiles = maxf(1.0, float(cfg.get("blend_tiles", 26)))
	_warp.seed = p_seed + 404
	_warp.frequency = 0.008
	_warp.fractal_octaves = 2
	_terrace.seed = p_seed + 505
	_terrace.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrace.frequency = float(cfg.get("terrace", {}).get("frequency", 0.011))
	_terrace.fractal_octaves = 2
	_sea.seed = p_seed + 606
	_sea.frequency = 0.02


func def(id: String) -> Dictionary:
	return cfg.get("regions", {}).get(id, {})


## [nearest region, second region, weight of the nearest 0.5..1].
func blend_at(p: Vector2i) -> Array:
	# sampled on a 4-tile grid (the warp + blend are smooth; ground dithers per tile)
	var k := Vector2i(p.x >> 2, p.y >> 2)
	var hit = _cache.get(k)
	if hit != null:
		return hit
	if _anchors.is_empty():
		return ["", "", 1.0]
	var c := k * 4 + Vector2i(2, 2)
	var q := Vector2(c) + Vector2(_warp.get_noise_2d(c.x, c.y), _warp.get_noise_2d(c.x + 9000, c.y - 9000)) * warp_tiles
	var best := {}
	for a in _anchors:
		var d: float = (a[0] as Vector2).distance_to(q)
		if d < float(best.get(a[1], INF)):
			best[a[1]] = d
	var r1 := ""
	var r2 := ""
	for id in best.keys():
		if r1 == "" or best[id] < best[r1]:
			r2 = r1
			r1 = id
		elif r2 == "" or best[id] < best[r2]:
			r2 = id
	if r2 == "":
		r2 = r1
	var w1 := 0.5 + 0.5 * clampf((float(best.get(r2, INF)) - float(best[r1])) / blend_tiles, 0.0, 1.0)
	var out := [r1, r2, w1]
	if _cache.size() > CACHE_MAX:
		_cache.clear()
	_cache[k] = out
	return out


## The region a tile belongs to (no dithering): HUD entry line, minimap tint, mines.
func region_at(p: Vector2i) -> String:
	return str(blend_at(p)[0])


func region_name(id: String) -> String:
	return str(def(id).get("name", id))


## Dithered region for ground / trees: inside the blend band the neighbour
## region wins with a chance that rises to 50% at the border.
func ground_region(p: Vector2i, h: float) -> String:
	var b := blend_at(p)
	return str(b[0]) if h < float(b[2]) else str(b[1])


## Smoothly blended numeric field of the region defs.
func field(p: Vector2i, key: String, dflt: float = 0.0) -> float:
	return field_b(blend_at(p), key, dflt)


## field() for an already looked-up blend_at result (hot path: world gen).
func field_b(b: Array, key: String, dflt: float = 0.0) -> float:
	var w: float = b[2]
	var d1: Dictionary = cfg["regions"].get(b[0], {})
	if w >= 1.0:
		return float(d1.get(key, dflt))
	return w * float(d1.get(key, dflt)) + (1.0 - w) * float(cfg["regions"].get(b[1], {}).get(key, dflt))


## Continuous terrace elevation: region base level + local relief noise.
func elevation(p: Vector2i) -> float:
	# bilinear between the 4-tile blend cells so terrace contours stay smooth (no boxy cliffs)
	var fx := (float(p.x) - 2.0) / 4.0
	var fy := (float(p.y) - 2.0) / 4.0
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - x0
	var ty := fy - y0
	var e := 0.0
	var rl := 0.0
	for j in 2:
		for i in 2:
			var w := (tx if i == 1 else 1.0 - tx) * (ty if j == 1 else 1.0 - ty)
			if w <= 0.0:
				continue
			var b := blend_at(Vector2i((x0 + i) * 4, (y0 + j) * 4))
			e += w * field_b(b, "elevation")
			rl += w * field_b(b, "relief")
	return e + rl * _terrace.get_noise_2d(p.x, p.y)


## Integer terrace level (cliffs sit where neighbouring levels differ).
func level(p: Vector2i) -> int:
	var l = _lcache.get(p)
	if l != null:
		return l
	if _lcache.size() > CACHE_MAX:
		_lcache.clear()
	var v := floori(elevation(p) + 0.5)
	_lcache[p] = v
	return v


## Beach tiles that drop below the land behind them (sea cliffs).
func sea_cliff(p: Vector2i) -> bool:
	return _sea.get_noise_2d(p.x, p.y) * 0.5 + 0.5 < field(p, "sea_cliffs") * 0.75
