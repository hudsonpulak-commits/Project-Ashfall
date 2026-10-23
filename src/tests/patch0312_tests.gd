class_name Patch0312Tests
extends RefCounted
## 0.3.12 Saltmere v2: an open harbour town (no walls, no fort) from the designer's v2 set,
## a quay and piers on a basin with a channel open to the sea, walk-in buildings whose roofs fade.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	var gen: WorldGen = world.gen
	var t: Dictionary = gen.towns["saltmere"]
	var org := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
	check(str(t.get("walls", "")) == "none" and not t.has("gate_walls") and int(t.get("cliff_clear", -1)) == 1,
		"Saltmere is an open town: no walls, no gate walls, a 1-tile cliff margin")
	var fort := 0
	var arts := 0
	var roles := {}
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] != "saltmere":
			continue
		arts += int(b.has("art"))
		roles[str(b["kind"])] = true
		roles[str(id).trim_prefix("saltmere_")] = true
		if str(b.get("art", "")).contains("fort") or str(b.get("name", "")).to_lower().contains("fort"):
			fort += 1
	check(fort == 0 and arts >= 26, "Saltmere: %d layered-art buildings, no fort" % arts)
	for k in ["bank", "church", "general", "cook", "smithy", "player", "legs", "lighthouse"]:
		check(roles.has(k), "Saltmere keeps its %s" % k)
	# the basin + channel run open to the sea: flood the water from the basin and reach real ocean outside the rect
	var r: Rect2i = gen._town_rects["saltmere"]
	var start := org + Vector2i(40, 46)
	var water := func(q: Vector2i) -> bool: return gen.tile_at(q.x, q.y) == WorldGen.TileType.WATER
	var seen := {start: true}
	var stack := [start]
	var sea := false
	while not stack.is_empty() and not sea and seen.size() < 20000:
		var c: Vector2i = stack.pop_back()
		if not r.has_point(c) and gen.land_value(c.x, c.y) < WorldGen.OCEAN_LEVEL:
			sea = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and water.call(n):
				seen[n] = true
				stack.append(n)
	check(water.call(start) and sea, "Saltmere's basin floods out through the channel to the open sea (%d water tiles)" % seen.size())
	var narrow := 99
	for x in range(74, 104):   # 0.3.14 Saltmere grown 1.3x
		var run := 0
		var best := 0
		for y in range(39, 57):
			run = run + 1 if water.call(org + Vector2i(x, y)) else 0
			best = maxi(best, run)
		narrow = mini(narrow, best)
	check(narrow >= 4, "the channel is at least 4 tiles wide all the way out (narrowest %d)" % narrow)
	# every open door is reachable from the spawn (closed buildings and door-less ones skipped)
	var spawn := Vector2i(int(t["spawn"][0]), int(t["spawn"][1]))
	var bad := []
	var bv: BuildingsView = world.buildings_view
	var faded_ok := 0
	var keep: Vector2i = p.tile
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] != "saltmere" or b.get("closed", false) or (b.get("doors", []) as Array).is_empty():
			continue
		var d: Vector2i = b["doors"][0]
		world.set_focus(d, true)
		if Pathfinder.find_path(world, spawn, [d], d, 12000).is_empty():
			bad.append(id)
		if faded_ok < 3 and b.has("art") and bv._roofs.has(id):
			p.place_at(d)
			bv.step(5.0)
			if bv.roof_alpha(id) == 0.0:
				faded_ok += 1
	p.place_at(keep)
	world.set_focus(keep, true)
	check(bad.is_empty(), "every open Saltmere door is reachable from the spawn %s" % str(bad))
	check(faded_ok == 3, "walking into Saltmere buildings fades their upper storeys and roof (%d/3 sampled)" % faded_ok)
	var guards := 0
	var nj = JSON.parse_string(FileAccess.get_file_as_string("res://data/town_npcs.json"))
	guards = 0
	for g in nj["towns"]["saltmere"]["guards"]:
		guards += int((g.get("patrol", []) as Array).size() >= 2)
	check(guards == 10, "Saltmere's guards walk patrols instead of standing at gates (%d)" % guards)
