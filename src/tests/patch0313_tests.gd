class_name Patch0313Tests
extends RefCounted
## 0.3.13 Fenhollow v1: a marsh town inside a continuous wooden palisade (4 gates, watchtowers), raised
## boardwalks, winding mud lanes, walk-in buildings whose roofs fade, new players start beside Kell.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	var gen: WorldGen = world.gen
	var t: Dictionary = gen.towns["fenhollow"]
	var org := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
	check(str(t.get("walls", "")) == "palisade" and (t.get("gates", {}) as Dictionary).size() == 4,
		"Fenhollow sits behind a palisade with 4 gates")
	# the palisade ring walked in collision (same 8-connected, diagonal-gap-aware flood as Highfen)
	var gts: Dictionary = t.get("gate_tiles", {})
	var spawn: Vector2i = gen.town_spawn("fenhollow")
	var hc: Vector2i = world.find_free_tile_near(org + Vector2i(37, 30), 4)   # the green at the town centre
	var sealed := not Patch0311Tests._ring_flood(world, hc, org, gts, "")
	var opens := 0
	for g in gts.keys():
		if Patch0311Tests._ring_flood(world, hc, org, gts, g):
			opens += 1
	check(gts.size() == 4 and sealed and opens == 4, "Fenhollow's palisade has no collision holes or diagonal slip-throughs: sealed with the gates shut, open through each of the 4 gates (%d/4)" % opens)
	var rq: Dictionary = t.get("ring_qa", {})
	check(int(rq.get("samples", 0)) > 1000 and int(rq.get("gap_count", -1)) == 0 and (rq.get("gates", []) as Array).size() == 4,
		"Fenhollow's palisade reads as one continuous wall: %d ring-walk samples, %d gaps, openings only at the 4 gates" % [int(rq.get("samples", 0)), int(rq.get("gap_count", -1))])
	var gate_fades := 0
	for f in (t.get("art", {}) as Dictionary).get("fades", []):
		if str(f.get("path", "")).contains("gate"):
			gate_fades += 1
	check(gate_fades >= 4, "each Fenhollow gatehouse has a roof that fades when walked under (%d)" % gate_fades)
	# buildings: the designer's v1 set, every role present, every open door walkable from the spawn
	var designs := {}
	var roles := {}
	var bad := []
	var keep: Vector2i = p.tile
	var bv: BuildingsView = world.buildings_view
	var faded := 0
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] != "fenhollow":
			continue
		if b.has("art"):
			designs[str(b["art"])] = true
		roles[str(id).trim_prefix("fenhollow_")] = true
		if b.get("closed", false) or (b.get("doors", []) as Array).is_empty():
			continue
		var d: Vector2i = b["doors"][0]
		world.set_focus(d, true)
		if Pathfinder.find_path(world, spawn, [d], d, 12000).is_empty():
			bad.append(id)
		if faded < 3 and b.has("art") and bv._roofs.has(id):
			p.place_at(d)
			bv.step(5.0)
			if bv.roof_alpha(id) == 0.0:
				faded += 1
	p.place_at(keep)
	world.set_focus(keep, true)
	check(designs.size() >= 15, "Fenhollow uses %d of the designer's v1 building designs" % designs.size())
	for k in ["bank", "church", "general", "cook", "swords", "helmets", "archery", "player", "kell_lodge", "guard_post"]:
		check(roles.has(k), "Fenhollow keeps its %s" % k)
	check(bad.is_empty(), "every open Fenhollow door is walk-in from the spawn %s" % str(bad))
	check(faded == 3, "walking into Fenhollow buildings fades their roofs (%d/3 sampled)" % faded)
	# new players start beside Kell
	var kell := org + Vector2i(int(t["kell"]["at"][0]), int(t["kell"]["at"][1]))
	check(spawn.distance_to(kell) <= 3.0 and not world.is_blocked(spawn), "new players start beside Kell (%.1f tiles)" % spawn.distance_to(kell))
	var gsafe := true
	for g in gts.keys():
		for q in gts[g]:
			gsafe = gsafe and gen.safe_at(org + Vector2i(int(q[0]), int(q[1])))
	check(gsafe, "Fenhollow's 4 gate passages are inside the safe zone")
	_saltmere_v3(world, gen)
	_highfen_v4(world, gen)


## 0.3.13 Saltmere v3: large smithy (smith out of the warehouse), Elijah's tomb, harbour entrance, v3 ships/props
static func _saltmere_v3(world, gen: WorldGen) -> void:
	var t: Dictionary = gen.towns["saltmere"]
	var org := Vector2i(int(t["origin"][0]), int(t["origin"][1]))
	var arts := {}
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] == "saltmere":
			arts[str(id)] = str(b.get("art", ""))
	check(arts.get("saltmere_maces", "") == "v3_smithy_large", "Saltmere's smith works in the v3 large smithy, not the warehouse (%s)" % arts.get("saltmere_maces", "?"))
	check(arts.get("saltmere_elijah_tomb", "") == "v3_elijah_tomb", "Elijah's tomb stands in Saltmere")
	var he: Dictionary = t.get("harbour_entrance", {})
	var pass_ok := not (he.get("passage", []) as Array).is_empty()
	for q in he.get("passage", []):
		pass_ok = pass_ok and not world.is_blocked(org + Vector2i(int(q[0]), int(q[1])))
	check(pass_ok, "the Saltmere harbour entrance arch can be walked through")
	var s := JSON.stringify(t.get("art", {}))
	check(s.contains("v3_ship_galleon") and s.contains("v3_ship_sloop") and s.contains("v3_rowboat_") and ResourceLoader.exists("res://assets/sprites/towns/saltmere/tiles/v3_quay_corner_nw.png"),
		"Saltmere uses the v3 galleon, sloop, rowboats and quay corner tiles")
	check(JSON.stringify(t.get("objects", {})).contains("sm3_town_sign"), "Saltmere has the v3 town sign")


## 0.3.13 Highfen v4: new civic buildings + props; single ring road (outer ring, 60/120 spokes dropped)
static func _highfen_v4(world, gen: WorldGen) -> void:
	var t: Dictionary = gen.towns["highfen"]
	var arts := {}
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] == "highfen":
			arts[str(b.get("art", ""))] = str(id)
	for a in ["v4_guild", "v4_cookhouse", "v4_player_shop", "v4_smithy", "v4_general_store"]:
		check(arts.has(a), "Highfen has the v4 %s" % a)
	for a in ["guild_knights", "shop_smith", "shop_general", "v3_cookhouse"]:
		check(not arts.has(a), "Highfen's replaced %s is gone" % a)
	check(arts.get("v4_player_shop", "") == "highfen_player" and arts.get("v4_guild", "") == "highfen_guild" and arts.get("v4_general_store", "") == "highfen_general",
		"the v4 player shop, guild and general store keep their roles")
	var objs := JSON.stringify(t.get("objects", {}))
	for o in ["hf4_statue_knight", "hf4_lamp_post", "hf4_banner_", "hf4_tree_oak"]:
		check(objs.contains(o), "Highfen places the v4 %s" % o)
	var rq: Dictionary = t.get("ring_qa", {})
	check(int(rq.get("gap_count", -1)) == 0 and (rq.get("gates", []) as Array).size() == 4, "Highfen's wall ring stays continuous after the v4 street plan")
