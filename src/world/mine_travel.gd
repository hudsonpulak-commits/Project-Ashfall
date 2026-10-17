class_name MineTravel
extends RefCounted
## 0.3.1: how much a far-away mine costs an AI in walking time. Pure data
## (data/mines.json + town files), so the abstract AI sim can use it without
## a World. factor = 1 / (1 + d / ref_tiles), clamped to min_factor, where d
## is the distance from the town centre to the nearest mine holding that rock
## (Scorch mines only when no other mine has it). Non-rock nodes: 1.0.

static var _cache: Dictionary = {}
static var _ref = null    # the GameData.mines dict the cache was built from


static func _town_center(tid: String) -> Vector2:
	var t: Dictionary = GameData.towns.get(tid, {})
	if t.is_empty():
		return Vector2.ZERO
	var rows: Array = t["rows"]
	return Vector2(int(t["origin"][0]) + str(rows[0]).length() / 2, int(t["origin"][1]) + rows.size() / 2)


static func _in_pk(p: Vector2) -> bool:
	for z in GameData.pk_zones.get("zones", []):
		var a: Array = z.get("rect", [0, 0, 0, 0])
		if Rect2(a[0], a[1], a[2], a[3]).has_point(p):
			return true
	return false


## Distance (tiles) from town `tid` to its nearest mine with `def_id` (INF if none).
static func distance(tid: String, def_id: String) -> float:
	var c := _town_center(tid)
	var best := INF
	var best_pk := INF
	for m in GameData.mines.get("mines", []):
		if float(m.get("ores", {}).get(def_id, 0.0)) <= 0.0:
			continue
		var mc := Vector2(float(m["center"][0]), float(m["center"][1]))
		var d := c.distance_to(mc)
		if _in_pk(mc):
			best_pk = minf(best_pk, d)
		else:
			best = minf(best, d)
	return best if best < INF else best_pk


static func _check() -> void:
	if not is_same(_ref, GameData.mines):
		_cache.clear()
		_ref = GameData.mines


static func factor(tid: String, def_id: String) -> float:
	if not def_id.ends_with("_rock"):
		return 1.0
	_check()
	var k := tid + "|" + def_id
	if _cache.has(k):
		return _cache[k]
	var cfg: Dictionary = GameData.mines.get("travel", {})
	var d := distance(tid, def_id)
	var f := 1.0
	if d < INF:
		f = maxf(float(cfg.get("min_factor", 0.5)), 1.0 / (1.0 + d / float(cfg.get("ref_tiles", 260.0))))
	elif not GameData.mines.get("mines", []).is_empty():
		f = float(cfg.get("min_factor", 0.5))
	_cache[k] = f
	return f


## 0.3.1 village fields: same walking cost from the town to its nearest village
## (village centre from data/towns/<village>.json; the field sits beside it).
static func farm_factor(tid: String) -> float:
	_check()
	var k := tid + "|farm"
	if _cache.has(k):
		return _cache[k]
	var c := _town_center(tid)
	var best := INF
	for vid in GameData.villages.keys():
		var v: Dictionary = GameData.villages[vid]
		if v.get("farms", []).is_empty():
			continue
		var rows: Array = v["rows"]
		var vc := Vector2(int(v["origin"][0]) + str(rows[0]).length() / 2, int(v["origin"][1]) + rows.size() / 2)
		best = minf(best, c.distance_to(vc))
	var cfg: Dictionary = GameData.mines.get("travel", {})
	var f := float(cfg.get("min_factor", 0.5))
	if best < INF:
		f = maxf(f, 1.0 / (1.0 + best / float(cfg.get("ref_tiles", 260.0))))
	_cache[k] = f
	return f


## Same, from an object definition (AIBrain passes defs, not ids): mining rocks only.
static func factor_def(tid: String, d: Dictionary) -> float:
	if bool(d.get("farm", false)):
		return farm_factor(tid)
	if str(d.get("skill", "")) != "mining":
		return 1.0
	var k := tid + "|y|" + str(d.get("yield", ""))
	_check()
	if _cache.has(k):
		return _cache[k]
	var f := 1.0
	for oid in GameData.objects.keys():
		var od: Dictionary = GameData.objects[oid]
		if od.get("skill", "") == "mining" and od.get("yield", "") == d.get("yield", "") and oid.ends_with("_rock"):
			f = factor(tid, oid)
			break
	_cache[k] = f
	return f
