class_name Patch0310Tests
extends RefCounted
## 0.3.10 stage 1 (lore regions): region map + soft borders, region ground,
## elevation cliffs with ramps/stairs, region ores (dusk ore), lore trees,
## magic mushrooms, region entry line. Lore: docs/specs/Lore_2026-10-21.md.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	var gen: WorldGen = world.gen
	var rm: WorldRegions = gen.region_map
	check(rm != null and rm.ids.size() == 4 and rm.ids.has("cinder") and rm.ids.has("central") and rm.ids.has("lower") and rm.ids.has("mere"),
		"0.3.10 data/regions.json: Cinder, Central Ashfen, Lower Ashfen, the Mere Lands")
	var want := {"fenhollow": "lower", "highfen": "central", "cinderholt": "cinder", "saltmere": "mere"}
	var bad := []
	for tid in want.keys():
		if rm.region_at(gen.town_center(tid)) != want[tid]:
			bad.append(tid)
	for vid in gen.villages.keys():
		if vid == "millbrook" and rm.region_at(gen.villages[vid]["center"]) not in ["central", "cinder"]:
			bad.append(vid)
	check(bad.is_empty(), "towns sit in their lore regions (Millbrook between Highfen and Cinderholt) %s" % str(bad))
	check(rm.region_at(Vector2i(300, -300)) == "cinder" and gen.is_pk(Vector2i(300, -300)), "the Scorch is the northern half of Cinder")
	# soft border: somewhere between Fenhollow and Highfen the blend weight drops and both regions dither in
	var soft := false
	var a := gen.town_center("fenhollow")
	var b := gen.town_center("highfen")
	for i in 101:
		var q := Vector2i(Vector2(a).lerp(Vector2(b), i / 100.0))
		var bl := rm.blend_at(q)
		if float(bl[2]) < 0.75 and bl[0] != bl[1]:
			soft = true
	check(soft, "region borders blend (dithered ground over blend_tiles)")
	# sample the continent: ground, cliffs, trees per region
	var st := {}
	for r in rm.ids:
		st[r] = {"n": 0, "lvl": 0.0, "cliff": 0, "stairs": 0, "grass": {}, "trees": {}, "mush": 0, "rocky": 0}
	var cliff_on_road := 0
	var cliff_blocks := true
	var bd := gen.bounds()
	for y in range(bd.position.y, bd.end.y, 3):
		for x in range(bd.position.x, bd.end.x, 3):
			var q := Vector2i(x, y)
			var t := gen.tile_at(x, y)
			if t == WorldGen.TileType.WATER or gen.is_pk(q):
				continue
			var r := rm.region_at(q)
			var s: Dictionary = st[r]
			s["n"] += 1
			s["lvl"] += rm.level(q)
			if t in WorldGen.CLIFF_TILES:
				s["cliff"] += 1
				if gen.road_tiles.has(q) or gen.in_town(q):
					cliff_on_road += 1
			elif t == WorldGen.TileType.CLIFF_STAIRS:
				s["stairs"] += 1
			elif t == WorldGen.TileType.ROCKY:
				s["rocky"] += 1
			elif t in WorldGen.GRASS_TILES:
				s["grass"][t] = int(s["grass"].get(t, 0)) + 1
			var o := gen.object_at(x, y, t)
			if o.ends_with("_tree"):
				s["trees"][o] = int(s["trees"].get(o, 0)) + 1
			elif o == "magic_mushroom":
				s["mush"] += 1
	for t in WorldGen.CLIFF_TILES:
		cliff_blocks = cliff_blocks and t in WorldGen.BLOCKING_TILES
	var dens := func(r: String) -> float: return float(st[r]["cliff"]) / maxf(1.0, float(st[r]["n"]))
	var lvl := func(r: String) -> float: return float(st[r]["lvl"]) / maxf(1.0, float(st[r]["n"]))
	print("0.3.10 regions: ", st)
	check(lvl.call("cinder") > lvl.call("central") and lvl.call("central") > lvl.call("lower") and lvl.call("central") > lvl.call("mere"),
		"elevation: Cinder highest, Central higher, Lower Ashfen + the coast low (%.2f %.2f %.2f %.2f)" % [lvl.call("cinder"), lvl.call("central"), lvl.call("lower"), lvl.call("mere")])
	check(dens.call("mere") > 0.0 and dens.call("lower") > 0.0 and dens.call("cinder") > dens.call("central") and dens.call("central") > dens.call("lower") and dens.call("lower") > dens.call("mere"),
		"cliffs in every region: Cinder most > Central > Lower > Mere (%.4f %.4f %.4f %.4f)" % [dens.call("cinder"), dens.call("central"), dens.call("lower"), dens.call("mere")])
	check(cliff_blocks and cliff_on_road == 0, "cliff faces + lips block movement; never on roads or in towns")
	var stairs := 0
	for r in rm.ids:
		stairs += int(st[r]["stairs"])
	check(stairs > 0, "ramps / stone stairs cut through cliff lines (%d sampled)" % stairs)
	var gk := func(r: String, t: int) -> bool:
		var g: Dictionary = st[r]["grass"]
		var best := -1
		for k in g.keys():
			if best < 0 or g[k] > g[best]:
				best = k
		return best == t
	check(gk.call("cinder", WorldGen.TileType.GRASS_BOREAL) and gk.call("lower", WorldGen.TileType.GRASS_LUSH) and gk.call("mere", WorldGen.TileType.GRASS_TROPIC) and gk.call("central", WorldGen.TileType.GRASS),
		"ground: boreal grass in Cinder, lush in Lower Ashfen, tropical in the Mere, plain in Central")
	check(int(st["cinder"]["rocky"]) > int(st["central"]["rocky"]) and int(st["central"]["rocky"]) > int(st["lower"]["rocky"]), "rocky ground: Cinder > Central > Lower")
	var tr := func(r: String, id: String) -> int: return int(st[r]["trees"].get(id, 0))
	var tot := func(r: String) -> float:
		var n := 0
		for k in st[r]["trees"].keys():
			n += int(st[r]["trees"][k])
		return float(n) / maxf(1.0, float(st[r]["n"]))
	check(tot.call("lower") > tot.call("central") and tot.call("mere") > tot.call("central"), "Lower Ashfen + the Mere are forested, Central is open")
	check(tr.call("cinder", "spruce_tree") > 3 * (tr.call("lower", "spruce_tree") + tr.call("mere", "spruce_tree")) and tr.call("mere", "mahogany_tree") > 3 * (tr.call("cinder", "mahogany_tree") + tr.call("lower", "mahogany_tree"))
		and tr.call("lower", "blackthorn_tree") > 3 * tr.call("cinder", "blackthorn_tree") and tr.call("lower", "alder_tree") + tr.call("central", "alder_tree") > 3 * tr.call("cinder", "alder_tree"),
		"trees: spruce in Cinder, mahogany in the Mere, ash in Lower, oak in Lower + Central")
	var lv := {}
	for id in ["ash_tree", "pine_tree", "dead_tree", "alder_tree", "blackthorn_tree", "spruce_tree", "mahogany_tree"]:
		lv[id] = int(GameData.object_def(id).get("level", -1))
	check(lv == {"ash_tree": 1, "pine_tree": 1, "dead_tree": 1, "alder_tree": 15, "blackthorn_tree": 30, "spruce_tree": 45, "mahogany_tree": 60}
		and GameData.object_def("alder_tree")["name"] == "Oak tree" and GameData.object_def("blackthorn_tree")["name"] == "Ash tree",
		"woodcutting tiers: tree/pine/dead 1, oak 15, ash 30, spruce 45, mahogany 60 %s" % str(lv))
	check(int(st["lower"]["mush"]) + int(st["mere"]["mush"]) > 2 * (int(st["cinder"]["mush"]) + int(st["central"]["mush"])) and GameData.object_def("magic_mushroom").get("yield", "") == "magic_mushroom",
		"magic mushrooms grow mostly in Lower Ashfen + the Mere")
	var rec := {}
	for rr in GameData.recipes:
		if str(rr.get("id", "")) == "smelt_dusk_steel":
			rec = rr
	check(not GameData.item("dusk_ore").is_empty() and GameData.object_def("dusk_rock").get("yield", "") == "dusk_ore" and rec.get("in", {}).has("dusk_ore") and rec.get("out", {}).has("dusk_steel_bar"),
		"dusk ore (Cinder) smelts with coal into dusk steel bars")
	# a path across a cliff line exists (stairs / ramp) and never steps on a cliff tile
	var face := Vector2i(999999, 0)
	var c0 := gen.town_center("cinderholt") + Vector2i(-60, 30)
	for r in range(1, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c0 + Vector2i(dx, dy)
				if face.x == 999999 and gen.tile_at(q.x, q.y) == WorldGen.TileType.CLIFF_FACE and not world.is_blocked(q + Vector2i(0, 2)) and not world.is_blocked(q + Vector2i(0, -1)):   # 0.3.11 the face hangs into the cell below
					face = q
	var ok_path := false
	var on_cliff := false
	if face.x != 999999:
		var path: Array = Pathfinder.find_path(world, face + Vector2i(0, 2), [face + Vector2i(0, -1)], face + Vector2i(0, -1), 20000)
		ok_path = not path.is_empty()
		for q in path:
			on_cliff = on_cliff or world.tile_type(q) in WorldGen.CLIFF_TILES
	check(face.x != 999999 and world.is_blocked(face) and ok_path and not on_cliff, "pathfinding goes around a cliff by its stairs (from below %s to above)" % str(face))
	# region entry line
	var zb: ZoneBanner = main.hud.zone_banner
	zb._update_region(0.1)
	check(zb.current_region() == rm.region_at(p.tile), "the HUD tracks the region you stand in (%s)" % zb.current_region())
	zb.show_region(str(rm.def("mere")["banner"]))
	check(zb.region_label.visible and zb.region_label.text.begins_with("The Mere Lands"), "entering a region shows its title")
	# placeholder art is flagged for the designer
	var unflagged := []
	for pair in [["tiles", "grass_boreal"], ["objects", "tree_spruce"], ["objects", "tree_mahogany"], ["objects", "magic_mushroom"], ["objects", "rock_dusk"]]:
		if not "PLACEHOLDER" in str(GameData.sprite_def(pair[0], pair[1]).get("note", "")):
			unflagged.append(pair[1])
	check(unflagged.is_empty(), "0.3.10 recolour placeholders are flagged in data/sprites.json %s (0.3.11: cliffs now use the designer's tiles)" % str(unflagged))
