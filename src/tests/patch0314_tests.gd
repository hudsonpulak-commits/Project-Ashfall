class_name Patch0314Tests
extends RefCounted
## 0.3.14 Cinderholt redesign: a forge city in a basalt ring (front/back/side gates, towers), walk-in
## buildings whose roofs fade, and the Northern Guard camp on the plateau just north of the town.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	var gen: WorldGen = world.gen
	check(str(ProjectSettings.get_setting("application/config/version")) == "0.3.14", "version is 0.3.14")
	var t: Dictionary = gen.towns["cinderholt"]
	var org := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
	var gts: Dictionary = t.get("gate_tiles", {})
	check(str(t.get("walls", "")) == "basalt" and gts.size() == 4, "Cinderholt sits behind a basalt wall with 4 gates (front, back, 2 sides)")
	var spawn: Vector2i = gen.town_spawn("cinderholt")
	var hc: Vector2i = world.find_free_tile_near(org + Vector2i(42, 62), 4)
	var sealed := not Patch0311Tests._ring_flood(world, hc, org, gts, "")
	var opens := 0
	for g in gts.keys():
		if Patch0311Tests._ring_flood(world, hc, org, gts, g):
			opens += 1
	check(sealed and opens == 4, "Cinderholt's basalt ring has no collision holes or diagonal slip-throughs: sealed shut, open through each gate (%d/4)" % opens)
	var rq: Dictionary = t.get("ring_qa", {})
	check(int(rq.get("samples", 0)) > 1000 and int(rq.get("gap_count", -1)) == 0 and int(rq.get("diag_gaps", -1)) == 0,
		"Cinderholt wall-ring QA: %d ring-walk samples, %d gaps, no diagonal gaps" % [int(rq.get("samples", 0)), int(rq.get("gap_count", -1))])
	# the Northern Guard camp: palisade octagon north of the ridge, one gate
	var camp: Dictionary = t.get("camp", {})
	var kc := org + Vector2i(int(camp["center"][0]), int(camp["center"][1]))
	check(kc.y < hc.y - 30, "the Northern Guard camp lies just north of Cinderholt (lore 2026-10-21)")
	var cg := {"camp": camp.get("gate_tiles", [])}
	var cstart: Vector2i = world.find_free_tile_near(kc, 4)
	var csealed := not Patch0311Tests._ring_flood(world, cstart, org, cg, "")
	var copen := Patch0311Tests._ring_flood(world, cstart, org, cg, "camp")
	var cq: Dictionary = rq.get("camp", {})
	check(csealed and copen and int(cq.get("gap_count", -1)) == 0, "the camp palisade is sealed except its gate (ring QA %d samples, %d gaps)" % [int(cq.get("samples", 0)), int(cq.get("gap_count", -1))])
	world.set_focus(cstart, true)
	check(not Pathfinder.find_path(world, spawn, [cstart], cstart, 20000).is_empty(), "the camp is reachable from the town spawn (cliff stairs)")
	world.set_focus(spawn, true)
	# buildings walk-in, roofs fade, walls sort behind the player
	var bad := []
	var faded := 0
	var keep: Vector2i = p.tile
	var bv: BuildingsView = world.buildings_view
	var n := 0
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] != "cinderholt" or b.get("closed", false) or (b.get("doors", []) as Array).is_empty():
			continue
		n += 1
		var d: Vector2i = b["doors"][0]
		world.set_focus(d, true)
		if Pathfinder.find_path(world, spawn, [d], d, 20000).is_empty():
			bad.append(id)
		if faded < 3 and bv._roofs.has(id):
			p.place_at(d)
			bv.step(5.0)
			if bv.roof_alpha(id) == 0.0:
				faded += 1
	check(n >= 25 and bad.is_empty(), "every Cinderholt and camp door (%d) is walk-in from the spawn %s" % [n, str(bad)])
	check(faded == 3, "walking into Cinderholt buildings fades their roofs (%d/3)" % faded)
	var wall_ok := false
	var sm: Dictionary = gen.buildings.get("cinderholt_axes", {})
	if not sm.is_empty() and bv._walls.has("cinderholt_axes"):
		var y_out := bv.walls_sort_y("cinderholt_axes")
		p.place_at((sm["doors"][0] as Vector2i) + Vector2i(0, -1))
		bv.step(5.0)
		var y_in := bv.walls_sort_y("cinderholt_axes")
		p.place_at(keep)
		bv.step(5.0)
		wall_ok = y_in < y_out - 16.0 and bv.walls_sort_y("cinderholt_axes") == y_out
	check(wall_ok, "inside the Cinderholt smithy the walls sort behind the player, and back once outside")
	p.place_at(keep)
	world.set_focus(keep, true)
	for k in ["cinderholt_ng_command", "cinderholt_ng_barracks", "cinderholt_ng_tent_1"]:
		check(gen.buildings.has(k), "the camp has %s" % k)
	var ng: Dictionary = GameData.enemies.get("northern_guard", {})
	var ns: Dictionary = GameData.enemies.get("northern_soldier", {})
	check(int(ng.get("level", 0)) == 30 and int(ns.get("level", 0)) == 35 and int(ns.get("defence", 0)) > int(ng.get("defence", 0)),
		"Northern guards are level 30, soldiers level 35 and more heavily armoured")
	var objs := JSON.stringify(t.get("objects", {})) + JSON.stringify(t.get("art", {}))
	for o in ["ng_campfire", "ng_supply", "ng_banner", "ch_anvil", "ch_brazier", "ng_watchtower"]:
		check(objs.contains(o), "Cinderholt/camp places %s" % o)
