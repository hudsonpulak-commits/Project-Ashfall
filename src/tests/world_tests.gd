class_name WorldTests
extends RefCounted
## 0.3.1 world-track selftests (called from src/tests/selftest.gd): named mines
## + tiers, distance bands, the Scorch (data, tiles, warning), roads/bridges,
## town guards and citizens, chickens, wolves, AI mine routing, save migration,
## stone churches (walk in, pray at the altar, Prayer full, no XP, walk out).

static var ST = null


static func check(cond: bool, what: String) -> void:
	ST.check(cond, what)


static func ticks(n: int) -> void:
	for i in n:
		Tick.step()


static func run(main, world: World, p: Player) -> void:
	ST = load("res://src/tests/selftest.gd")
	print("  -- 0.3.1 world")
	_mine_tests(world)
	_band_tests(world)
	_road_tests(world)
	_scorch_tests(main, world, p)
	_creature_tests(world, p)
	_town_folk_tests(world, p)
	_routing_tests(world)
	_migration_tests(main, world, p)
	_church_tests(world, p)
	_combat_level_tests(world, p)
	ArcheryTests.run(world, p)   # 0.3.3
	MusicTests.run()   # 0.3.4
	Patch035Tests.run(world, p)   # 0.3.5
	_village_tests(world, p)
	_walled_city_tests(world, p)
	_cookhouse_tests(world, p)
	_walled_integration_tests(world, p)
	Patch036Tests.run(world, p)   # 0.3.6 (last: it advances ~250 ticks)
	Patch037Tests.run(world, p)   # 0.3.7
	Patch0371Tests.run(main, world, p)   # 0.3.7.1
	Patch038Tests.run(main, world, p)   # 0.3.8
	Patch039Tests.run(main, world, p)   # 0.3.9
	Patch0391Tests.run(main, world, p)   # 0.3.9.1
	Patch0392Tests.run(main, world, p)   # 0.3.9.2
	Patch0393Tests.run(main, world, p)   # 0.3.9.3
	Patch0394Tests.run(main, world, p)   # 0.3.9.4
	Patch0395Tests.run(main, world, p)   # 0.3.9.5
	Patch0396Tests.run(main, world, p)   # 0.3.9.6
	Patch0396VideoTests.run(main, world, p)   # 0.3.9.6 title video
	p.place_at(world.gen.town_spawn("fenhollow"))
	world.set_focus(p.tile, true)


# ------------------------------------------------------------------ mines --
static func _mine_tests(world: World) -> void:
	var gen := world.gen
	check(gen.mines.size() >= 10, "0.3.1 named mines loaded from data/mines.json (%d)" % gen.mines.size())
	var tiers_ok := true
	var why := []
	for tid in gen.town_order:
		if tid == gen.capital:
			continue   # 0.3.8 the capital has no mines / chickens / church of its own
		var pits := gen.mines.filter(func(m): return str(m.get("tier", "")) == "copper_tin" and gen.nearest_town(m["c"]) == tid)
		var ok_t := false
		for m in pits:
			var e := gen.town_edge_distance(m["c"])
			ok_t = ok_t or (e >= 15.0 and e <= 30.0 and float(m["ores"].get("copper_rock", 0)) > 0 and float(m["ores"].get("tin_rock", 0)) > 0)
		tiers_ok = tiers_ok and ok_t
		if not ok_t:
			why.append(tid)
	check(tiers_ok, "every town has a copper + tin mine 15-30 tiles outside it %s" % str(why))
	var iron_ok := true
	var coal_ok := true
	var scorch_ok := true
	var n_scorch := 0
	for m in gen.mines:
		var e := gen.town_edge_distance(m["c"])
		match str(m.get("tier", "")):
			"iron":
				iron_ok = iron_ok and e >= 50.0 and e <= 90.0 and not m["pk"]
			"coal":
				coal_ok = coal_ok and e >= 100.0 and not m["pk"]
			"scorch":
				n_scorch += 1
				scorch_ok = scorch_ok and m["pk"] and float(m.get("density", 0)) > 0.35
	check(iron_ok and gen.mines.filter(func(m): return m.get("tier") == "iron").size() >= 3, "iron mines sit 50-90 tiles out (one per town at least)")
	check(coal_ok and gen.mines.filter(func(m): return m.get("tier") == "coal").size() >= 2, "coal mines sit 100+ tiles from every town")
	check(scorch_ok and n_scorch >= 1, "the richest (densest iron + coal) mines are inside the Scorch (%d)" % n_scorch)
	# every mine is on land and holds every ore it lists
	var content_ok := true
	var counts := {}
	for m in gen.mines:
		var have := {}
		var r := int(ceil(float(m["radius"])))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q: Vector2i = m["c"] + Vector2i(dx, dy)
				var o := gen.object_at(q.x, q.y, gen.tile_at(q.x, q.y))
				if o.ends_with("_rock"):
					have[o] = int(have.get(o, 0)) + 1
		var tot := 0
		for k in have.values():
			tot += int(k)
		counts[m["id"]] = tot
		for ore in m["ores"].keys():
			content_ok = content_ok and int(have.get(ore, 0)) >= 1
		content_ok = content_ok and tot >= 8 and gen.tile_at(m["c"].x, m["c"].y) != WorldGen.TileType.WATER
	check(content_ok, "every mine has 8+ rocks on land, of every ore it lists %s" % str(counts))
	# no rocks anywhere else (no scattered rocks, none in towns)
	var stray := []
	for tid in gen.town_order:
		var c := gen.town_center(tid)
		for y in range(c.y - 110, c.y + 111):
			for x in range(c.x - 110, c.x + 111):
				var t := gen.tile_at(x, y)
				if t != WorldGen.TileType.DIRT and t != WorldGen.TileType.ASH:
					continue      # rocks only ever stood on dirt (now: mine ground) or Scorch ash
				var o := gen.object_at(x, y, t)
				if o.ends_with("_rock") and gen.mine_at(Vector2i(x, y), 1).is_empty():
					stray.append(Vector2i(x, y))
	check(stray.is_empty(), "no scattered rocks: every rock within 110 tiles of a town is inside a named mine (%d stray)" % stray.size())
	var town_rocks := 0
	for tid in gen.town_order:
		for q in gen._town_objects.keys():
			if str(gen._town_objects[q]).ends_with("_rock"):
				town_rocks += 1
	check(town_rocks == 0, "no rocks inside the towns any more (%d)" % town_rocks)
	# AI travel factor: nearer tiers pay better
	var f_cu := MineTravel.factor("fenhollow", "copper_rock")
	var f_fe := MineTravel.factor("fenhollow", "iron_rock")
	var f_co := MineTravel.factor("fenhollow", "coal_rock")
	check(f_cu > f_fe and f_fe > f_co and f_co >= float(GameData.mines["travel"]["min_factor"]) and f_cu <= 1.0,
		"AI mining pays less for far mines: copper %.2f > iron %.2f > coal %.2f (Fenhollow)" % [f_cu, f_fe, f_co])
	check(is_equal_approx(MineTravel.factor_def("fenhollow", GameData.object_def("iron_rock")), f_fe) and MineTravel.factor_def("fenhollow", GameData.object_def("ash_tree")) == 1.0,
		"travel factor applies to rocks only")


# ------------------------------------------------------------------ bands --
static func _band_tests(world: World) -> void:
	var gen := world.gen
	var bands: Dictionary = GameData.enemy_bands.get("bands", {})
	var bad := []
	for c in GameData.camps:
		var k := str(c["enemy"])
		var at := Vector2i(int(c["at"][0]), int(c["at"][1]))
		var b: Dictionary = bands.get(k, {})
		var e := gen.town_edge_distance(at)
		var pk := gen.is_pk(at)
		var ok := false
		if b.is_empty():
			ok = false
		elif bool(b.get("pk_only", false)):
			ok = pk
		else:
			ok = (e >= float(b["min"]) and e <= float(b["max"]) and not pk) or (pk and bool(b.get("pk", false)))
		if not ok:
			bad.append("%s@%s(%.0f)" % [k, str(at), e])
	check(bad.is_empty(), "every camp sits in its distance band (data/enemy_bands.json) %s" % str(bad))
	var lv := func(k): return int(GameData.enemies[k]["level"])
	check(lv.call("chicken") <= lv.call("giant_rat") and lv.call("giant_rat") < lv.call("wolf") and lv.call("wolf") < lv.call("goblin") and lv.call("goblin") < lv.call("cinder_brute"),
		"creatures get tougher with distance: chicken <= rat < wolf < goblin < Scorch brute")
	var mean := {}
	for c in GameData.camps:
		var k := str(c["enemy"])
		if not mean.has(k):
			mean[k] = [0.0, 0]
		mean[k][0] += gen.town_edge_distance(Vector2i(int(c["at"][0]), int(c["at"][1])))
		mean[k][1] += 1
	var md := func(k): return mean[k][0] / mean[k][1] if mean.has(k) else -1.0
	check(md.call("chicken") < md.call("giant_rat") and md.call("giant_rat") < md.call("wolf") and md.call("wolf") < md.call("goblin"),
		"camps by mean distance: chickens %.0f < rats %.0f < wolves %.0f < goblins %.0f tiles" % [md.call("chicken"), md.call("giant_rat"), md.call("wolf"), md.call("goblin")])
	var near_each := true
	for tid in gen.town_order:
		if tid == gen.capital:
			continue   # 0.3.8 the capital has no mines / chickens / church of its own
		var has := false
		for c in GameData.camps:
			if str(c["enemy"]) == "chicken" and gen.nearest_town(Vector2i(int(c["at"][0]), int(c["at"][1]))) == tid:
				has = true
		near_each = near_each and has
	check(near_each, "chickens right by every town")
	check(GameData.camps.filter(func(c): return str(c["enemy"]) == "cinder_brute").size() >= 1 and GameData.camps.filter(func(c): return world.gen.is_pk(Vector2i(int(c["at"][0]), int(c["at"][1])))).size() >= 2,
		"the Scorch has its own tougher camps (Cinder brutes)")


# ------------------------------------------------------------------ roads --
static func _road_ok(gen: WorldGen) -> Dictionary:
	var water := 0
	var unbridged := 0
	var blocked := 0
	var corner := 0
	var pk := 0
	var longest := 0
	for k in gen.roads.keys():
		var road: Array = gen.roads[k]
		for i in road.size():
			var q: Vector2i = road[i]
			var t := gen.tile_at(q.x, q.y)
			if t == WorldGen.TileType.WATER:
				water += 1
			if gen._terrain_at(q.x, q.y) == WorldGen.TileType.WATER and t != WorldGen.TileType.BRIDGE and gen.town_at(q, 0) == "":
				unbridged += 1
			if t in WorldGen.BLOCKING_TILES:
				blocked += 1
			if gen.is_pk(q):
				pk += 1
			if i > 0:
				var d: Vector2i = q - road[i - 1]
				if d.x != 0 and d.y != 0:
					var a := gen.tile_at(road[i - 1].x + d.x, road[i - 1].y)
					var b := gen.tile_at(road[i - 1].x, road[i - 1].y + d.y)
					if a == WorldGen.TileType.WATER or b == WorldGen.TileType.WATER or t == WorldGen.TileType.BRIDGE:
						corner += 1
						if corner <= 3:
							print("    corner %s at %d %s (a %d b %d t %d)" % [k, i, q, a, b, t])
	for br in gen.bridges:
		longest = maxi(longest, (br["tiles"] as Array).size())
	return {"water": water, "unbridged": unbridged, "blocked": blocked, "corner": corner, "pk": pk, "longest": longest, "bridges": gen.bridges.size()}


static func _road_tests(world: World) -> void:
	var gen := world.gen
	var r := _road_ok(gen)
	check(r["water"] == 0 and r["unbridged"] == 0 and r["blocked"] == 0, "no road tile is water: roads go round lakes, crossings are bridges %s" % str(r))
	check(r["corner"] == 0, "no diagonal road step cuts a water corner (bridges are 4-connected)")
	check(r["pk"] == 0, "roads keep out of the Scorch")
	check(r["longest"] <= int(GameData.world["road_rules"]["max_bridge"]), "bridges are short (longest %d tiles)" % r["longest"])
	var walk_ok := true
	for k in gen.roads.keys():
		for q in gen.roads[k]:
			walk_ok = walk_ok and not world.is_blocked(q)
	check(walk_ok, "every road tile (bridges included) is walkable")
	# the bridge rule itself: force cheap crossings on another seed
	var cfg: Dictionary = GameData.world.duplicate(true)
	cfg["road_rules"]["bridge_cost"] = 1.05
	cfg["road_rules"]["meander"] = 0.0
	var t0 := Time.get_ticks_msec()
	var g2 := WorldGen.new(7331, {}, cfg)
	var ms := Time.get_ticks_msec() - t0
	var r2 := _road_ok(g2)
	var bridge_tiles_ok := true
	for br in g2.bridges:
		for q in br["tiles"]:
			bridge_tiles_ok = bridge_tiles_ok and g2.tile_at(q.x, q.y) == WorldGen.TileType.BRIDGE and not (WorldGen.TileType.BRIDGE in WorldGen.BLOCKING_TILES)
	check(r2["bridges"] >= 1 and r2["water"] == 0 and r2["unbridged"] == 0 and r2["corner"] == 0 and bridge_tiles_ok,
		"cheap crossings become walkable 4-connected wooden bridges, never road-over-water %s" % str(r2))
	print("    road A* (3 roads, uncached): %d ms (desktop)" % ms)
	check(ms < 2500, "road A* builds 3 roads in under 2.5 s on desktop (%d ms; cached per process)" % ms)
	var g3 := WorldGen.new(7331)
	check(g3.roads == gen.roads, "roads are deterministic (and cached) per seed")


# ----------------------------------------------------------------- Scorch --
static func _scorch_tests(main, world: World, p: Player) -> void:
	var gen := world.gen
	var zs: Array = GameData.pk_zones.get("zones", [])
	check(zs.size() == 1 and str(zs[0]["id"]) == "scorch", "data/pk_zones.json defines the Scorch")
	var z: Dictionary = zs[0]
	var cz := CombatRules.zones().filter(func(x): return str(x.get("id", "")) == "scorch")
	check(cz.size() == 1 and cz[0]["rect"] == z["rect"], "the same Scorch rect is a multi-combat zone in data/combat_zones.json")
	var r := Rect2i(int(z["rect"][0]), int(z["rect"][1]), int(z["rect"][2]), int(z["rect"][3]))
	var inside := Vector2i(200, r.end.y - 10)
	var edge_in := Vector2i(200, r.end.y - 1)
	var outside := Vector2i(200, r.end.y + 1)
	check(world.is_pk(inside) and world.is_pk(edge_in) and not world.is_pk(outside) and CombatRules.is_multi(inside), "World.is_pk(): true inside the Scorch, false just south of it")
	var land_ash := 0
	var land := 0
	var edge_ok := true
	for x in range(r.position.x, r.end.x, 3):
		for y in range(r.end.y - 40, r.end.y):
			var t := gen.tile_at(x, y)
			if t == WorldGen.TileType.WATER:
				continue
			land += 1
			if t == WorldGen.TileType.ASH or t == WorldGen.TileType.ASH_EDGE:
				land_ash += 1
		var tb := gen.tile_at(x, r.end.y - 1)
		if tb != WorldGen.TileType.WATER:
			edge_ok = edge_ok and tb == WorldGen.TileType.ASH_EDGE and gen.tile_at(x, r.end.y) != WorldGen.TileType.ASH_EDGE
	check(land > 100 and land_ash == land, "the Scorch's land is charred ash (%d/%d tiles)" % [land_ash, land])
	check(edge_ok, "a visible charred border (ash_edge) runs along the Scorch boundary")
	var decor := {}
	for y in range(r.end.y - 60, r.end.y):
		for x in range(100, 400):
			var o := gen.object_at(x, y, gen.tile_at(x, y))
			if o in ["burnt_tree", "charred_stump", "embers"]:
				decor[o] = int(decor.get(o, 0)) + 1
	check(decor.size() == 3, "burnt trees, stumps and embers dot the Scorch %s" % str(decor))
	var live_trees := 0
	for y in range(r.end.y - 60, r.end.y):
		for x in range(100, 400):
			if gen.object_at(x, y, gen.tile_at(x, y)).ends_with("_tree") and gen.object_at(x, y, gen.tile_at(x, y)) != "burnt_tree":
				live_trees += 1
	check(live_trees == 0, "no living trees in the Scorch")
	var not_pk := true
	for tid in gen.town_order:
		var tr: Rect2i = gen._town_rects[tid]
		not_pk = not_pk and not world.is_pk(tr.position) and not world.is_pk(tr.end)
	check(not_pk, "no town lies in the Scorch")
	# the entry warning (HUD) on first crossing, chat line on later entries
	var zb: ZoneBanner = main.hud.zone_banner
	var said: Array = []
	var got: Array = []
	var c1 := func(t, _k): said.append(t)
	var c2 := func(id, w): got.append([id, w])
	Events.message.connect(c1)
	Events.zone_entered.connect(c2)
	p.zone_seen.clear()
	p.place_at(outside + Vector2i(0, 3))
	zb._process(0.016)
	check(not zb.row.visible and not zb.banner_showing(), "no Scorch HUD outside")
	p.place_at(inside)
	zb._process(0.016)
	check(zb.banner_showing() and zb.banner_label.text == "The Scorch - anyone can attack you" and zb.row.visible and p.zone_seen.has("scorch")
		and got.size() == 1 and got[0][0] == "scorch", "first crossing: banner 'The Scorch - anyone can attack you', skull row, zone_entered fires")
	for i in 400:
		zb._process(0.05)
	check(not zb.banner_showing() and zb.row.visible, "the banner fades after a few seconds; the skull row stays while inside")
	p.place_at(outside + Vector2i(0, 3))
	zb._process(0.016)
	p.place_at(inside)
	said.clear()
	zb._process(0.016)
	check(not zb.banner_showing() and said.has(str(GameData.pk_zones["zones"][0]["enter_line"])), "later crossings: a chat line, no banner")
	var sv: Dictionary = p.to_save()
	var p2 := Player.new()
	p2.from_save(sv)
	check(p2.zone_seen.has("scorch"), "the warning is remembered in the save")
	p2.free()
	Events.message.disconnect(c1)
	Events.zone_entered.disconnect(c2)
	p.place_at(gen.town_spawn("fenhollow"))
	zb._process(0.016)


# -------------------------------------------------------------- creatures --
static func _near(world: World, kind: String, at: Vector2i) -> Enemy:
	return world.enemies.nearest(at, [kind], 2000)


static func _calm(world: World, p: Player, e: Enemy, n: int = 20) -> bool:
	p.place_at(world.find_free_tile_near(e.tile + Vector2i(1, 0), 2))
	p.hp = p.max_hp()
	p.stop()
	world.set_focus(p.tile, true)
	var calm := true
	for i in n:
		Tick.step()
		calm = calm and e.target == null and p.hp == p.max_hp()
	return calm


static func _creature_tests(world: World, p: Player) -> void:
	var em := world.enemies
	var ch := _near(world, "chicken", world.gen.town_spawn("fenhollow"))
	check(ch != null and ch.max_hp == 3, "chickens (3 HP after 0.3.6 x1.5) spawn near Fenhollow")
	check(_calm(world, p, ch), "chickens never aggro, even next to you")
	var hp0 := p.hp
	p.inventory.add("bronze_sword")
	ch.take_hit(1, p, Tick.tick_count)
	ticks(10)
	check(ch.target == null and p.hp == hp0, "a hit chicken does not fight back")
	var drng := RandomNumberGenerator.new()
	drng.seed = 31
	var bones := 0
	var feath := 0
	var raw := 0
	for i in 400:
		for d in DropTable.roll("chicken", drng):
			match str(d[0]):
				"bones": bones += 1
				"feather": feath += 1
				"raw_chicken": raw += 1
	check(bones == 400 and feath == 400 and raw > 240 and raw < 360, "chicken drops: bones + feathers always, raw chicken ~75%% (%d/400)" % raw)
	var cr := Interactions.recipe_by_id("cook_chicken")
	check(not cr.is_empty() and int(cr["level"]) == 1 and int(cr["in"].get("raw_chicken", 0)) == 1 and cr["in"].size() == 1 and int(GameData.item("cooked_chicken").get("heals", 0)) > 0,
		"raw chicken cooks at Cooking 1 into a small heal")
	# wolves: aggressive and quick
	var wolf := _near(world, "wolf", world.gen.town_spawn("fenhollow"))
	check(wolf != null, "wolves spawn")
	wolf.reset_far()
	p.place_at(world.find_free_tile_near(wolf.home + Vector2i(4, 0), 2))
	p.hp = p.max_hp()
	world.set_focus(p.tile, true)
	var aggro := false
	for i in 12:
		Tick.step()
		if wolf.target == p:
			aggro = true
			break
	check(aggro, "wolves aggro when you come close")
	# quick: chase 2 tiles per tick when you run (leash permitting)
	wolf.reset_far()
	p.place_at(world.find_free_tile_near(wolf.home + Vector2i(5, 0), 2))
	wolf.target = p
	wolf.last_combat_tick = Tick.tick_count
	var d0 := wolf.cheb(wolf.tile, p.tile)
	Tick.step()
	var d1 := wolf.cheb(wolf.tile, p.tile)
	check(d0 - d1 == 2, "wolves are quick: they close 2 tiles per tick (%d -> %d)" % [d0, d1])
	wolf.reset_far()
	p.place_at(world.gen.town_spawn("fenhollow"))
	var wd := 0
	for i in 400:
		for d in DropTable.roll("wolf", drng):
			if d[0] == "wolf_pelt":
				wd += 1
	check(wd > 190 and wd < 290, "wolves drop bones + a wolf pelt ~60%% (%d/400)" % wd)
	var br := _near(world, "cinder_brute", Vector2i(250, -300))
	check(br != null and world.is_pk(br.home) and int(br.def["level"]) > int(GameData.enemies["goblin"]["level"]), "Cinder brutes (tougher than goblins) live in the Scorch")


# -------------------------------------------------------------- town folk --
static func _town_folk_tests(world: World, p: Player) -> void:
	var em := world.enemies
	var guards := {}
	var cits := {}
	var hp_ok := true
	var tints := {}
	for e in em.enemies:
		if e.kind == "town_guard":
			guards[e.town] = int(guards.get(e.town, 0)) + 1
		elif e.kind == "citizen" and world.gen.towns.has(e.town):   # village folk: _village_tests
			cits[e.town] = int(cits.get(e.town, 0)) + 1
			hp_ok = hp_ok and e.max_hp >= 5 and e.max_hp <= 8
			tints[e.tint.to_html()] = true
	var g_ok := guards.size() == world.gen.towns.size()
	for v in guards.values():
		g_ok = g_ok and v >= 2 and v <= 16   # 0.3.1: patrols + 2 stationary per gate
	var c_ok := cits.size() == world.gen.towns.size()
	for v in cits.values():
		c_ok = c_ok and v >= 4 and v <= 6
	check(g_ok, "2-16 guards (patrols + gate posts) each town %s" % str(guards))
	check(c_ok and hp_ok, "4-6 citizens (5-8 HP) wander each town %s" % str(cits))
	check(tints.size() >= 3, "citizens come in colour variants (%d)" % tints.size())
	var gl := int(GameData.enemies["town_guard"]["level"])
	check(gl > int(GameData.enemies["wolf"]["level"]) and int(GameData.enemies["town_guard"]["hp"]) < 4 * int(GameData.enemies["goblin"]["hp"]),
		"guards are mid level: above a wolf, below a goblin camp")
	# a guard walks its patrol
	var g: Enemy = null
	for e in em.enemies:
		if e.kind == "town_guard" and e.town == "fenhollow" and e.patrol.size() >= 4:
			g = e
	p.place_at(world.gen.town_spawn("fenhollow"))
	world.set_focus(p.tile, true)
	var visited := {}
	var stuck: int = 0
	var last := g.tile
	# 0.3.6 generate the chunks round the patrol first (pathing is otherwise
	# sensitive to which chunks happen to be generated already)
	var parked := []   # 0.3.7 wandering citizens (RNG) can stall the loop: park them
	for e3 in em.enemies:
		if e3 != g and not e3.dead and e3.kind != "town_guard" and e3.cheb(e3.tile, g.home) < 30:
			e3.dead = true
			e3.respawn_at = 1 << 30
			parked.append(e3)
	for a in AIDirector.agents:    # 0.3.7 idle AI players on the route would block the loop
		if a and is_instance_valid(a) and a._cheb(a.tile, g.home) < 30:
			a.place_at(world.find_free_tile_near(g.home + Vector2i(0, 60), 6, true))
			a.stop()
	for wp in g.patrol:
		for cy in range(-1, 2):
			for cx in range(-1, 2):
				world.get_chunk(world.chunk_of(wp) + Vector2i(cx, cy))
	for i in 700:   # a full loop of the longest walled-city patrol (stops once all are seen)
		Tick.step()
		for k in g.patrol.size():
			if g.tile == g.patrol[k]:
				visited[k] = true
		if visited.size() == g.patrol.size():
			break
		if i % 8 == 0 and OS.has_environment("PATROL_DEBUG"):
			print("    pd %d %s i=%d path=%d blocked_wp=%s" % [i, g.tile, g.patrol_i, g._patrol_path.size(), world.is_blocked(g.patrol[g.patrol_i])])
		if g.tile == last:
			stuck += 1
		last = g.tile
	if visited.size() != g.patrol.size():
		print("    guard patrol debug: patrol %s tile %s home %s target %s returning %s dead %s" % [str(g.patrol), g.tile, g.home, g.target, g.returning, g.dead])
	for e3 in parked:
		e3.dead = false
		e3.respawn_at = 0
	check(visited.size() == g.patrol.size(), "a guard walks its whole patrol loop (%d/%d waypoints)" % [visited.size(), g.patrol.size()])
	# non-aggressive, but fights back
	check(_calm(world, p, g), "guards never start a fight (you stand next to one)")
	p.hp = p.max_hp()
	p.place_at(world.find_free_tile_near(g.tile + Vector2i(1, 0)))
	g.take_hit(1, p, Tick.tick_count)
	var hit_back := false
	for i in 20:
		Tick.step()
		hit_back = hit_back or p.hp < p.max_hp()
	check(hit_back, "a guard fights back when attacked (inside the town too)")
	p.hp = p.max_hp()
	g.target = null
	g.reset_far()
	var cz: Enemy = null
	for e in em.enemies:
		if e.kind == "citizen" and e.town == "fenhollow":
			cz = e
	check(_calm(world, p, cz), "citizens never start a fight")
	cz.take_hit(1, p, Tick.tick_count)
	check(cz.target == p and int(cz.def["max_hit"]) <= 1, "citizens swing back weakly (max hit %d)" % int(cz.def["max_hit"]))
	cz.target = null
	cz.reset_far()
	var drng := RandomNumberGenerator.new()
	drng.seed = 7
	var rare := 0
	var bones := 0
	var coins := 0
	for i in 8000:
		for d in DropTable.roll("town_guard", drng):
			if d[0] == "bones":
				bones += 1
			elif d[0] == GameData.currency:
				coins += 1
			elif str(d[0]).begins_with("iron_"):
				rare += 1
	check(bones == 8000 and coins > 4000 and rare > 120 and rare < 300, "guard drops: bones always, coins often, rare iron gear ~1/40 (%d/8000)" % rare)
	var cb := 0
	var cmin := 99
	var cmax := 0
	for i in 2000:
		for d in DropTable.roll("citizen", drng):
			if d[0] == "bones":
				cb += 1
			elif d[0] == GameData.currency:
				cmin = mini(cmin, int(d[1]))
				cmax = maxi(cmax, int(d[1]))
	check(cb == 2000 and cmin >= 1 and cmax <= 5, "citizen drops: bones always, 1-5 marks (%d-%d), common low items" % [cmin, cmax])
	# town folk respawn
	cz.take_hit(99, p, Tick.tick_count)
	check(cz.dead, "a citizen can be killed")
	ticks(int(cz.def["respawn_ticks"]) + 2)
	check(not cz.dead and cz.hp == cz.max_hp, "citizens respawn")


# ---------------------------------------------------------------- routing --
static func _routing_tests(world: World) -> void:
	var gen := world.gen
	var spawn := gen.town_spawn("fenhollow")
	var ok := true
	var why := []
	for ore in ["copper_rock", "tin_rock", "iron_rock", "coal_rock"]:
		var o := world.find_gather_node(spawn, ore, "fenhollow")
		var m := gen.mine_at(o.pos, 1) if o else {}
		ok = ok and o != null and not m.is_empty() and not m["pk"]
		if o == null or m.is_empty():
			why.append(ore)
	check(ok, "AI routing: from Fenhollow every ore has a reachable named mine outside the Scorch %s" % str(why))
	var pits := world.find_gather_node(spawn, "copper_rock", "fenhollow")
	check(pits != null and str(gen.mine_at(pits.pos, 1)["id"]) == "fenhollow_pits", "AI miners pick their own town's pits for copper")
	var path := Pathfinder.find_path(world, spawn, Pathfinder.interaction_tiles(pits.pos), pits.pos, 20000)
	check(not path.is_empty(), "the Fenhollow pits are reachable on foot from the plaza (%d steps)" % path.size())
	var pros := {}
	for a in AIDirector.records:
		if a.persona_id() == "prospector":
			pros[a.home_town] = int(pros.get(a.home_town, 0)) + 1
	check(gen.town_order.all(func(t): return int(pros.get(t, 0)) >= 1), "every town has a prospector (personas min_per_town) %s" % str(pros))


# -------------------------------------------------------------- migration --
static func _migration_tests(main, world: World, p: Player) -> void:
	var gen := world.gen
	# an old save standing on a rock now in a mine
	var rock := world.find_gather_node(gen.town_spawn("cinderholt"), "copper_rock", "cinderholt")
	p.place_at(rock.pos)
	var moved: bool = main.relocate_if_walled(world, p)
	check(moved and not world.is_blocked(p.tile), "old save on a (new) mine rock: moved to a free tile")
	# an old save standing in a lake (0.3.0 roads crossed water)
	var lake := Vector2i(999999, 0)
	for y in range(-60, 60, 2):
		for x in range(-60, 120, 2):
			if lake.x == 999999 and gen._terrain_at(x, y) == WorldGen.TileType.WATER and gen.land_value(x, y) > WorldGen.OCEAN_LEVEL and not gen.road_tiles.has(Vector2i(x, y)):
				lake = Vector2i(x, y)
	p.place_at(lake)
	moved = main.relocate_if_walled(world, p)
	check(lake.x != 999999 and moved and not world.is_blocked(p.tile), "old save standing in lake water: moved ashore")
	# one save chain: a v3 (0.3.0) save picks up markers (v4), day/night (v5) and the world layout (v6)
	var v3 := {"version": 3, "tick": 10, "player": {"tile": [5, 5]}, "world": {"seed": 7331, "depleted": {"3,4": 50}, "ground": []}}
	var mig: Dictionary = SaveSystem._migrate(v3)
	check(int(mig["version"]) == SaveSystem.SAVE_VERSION and SaveSystem.SAVE_VERSION == 8 and mig["player"].has("map_markers")
		and mig.has("daynight") and typeof(mig["player"].get("zone_seen")) == TYPE_DICTIONARY and (mig["world"]["depleted"] as Dictionary).is_empty()
		and bool(mig.get("relayout_cities", false)),
		"save chain v3 -> v8: map markers + day/night + zone memory, old rock timers dropped, walled-city relayout flagged")
	var v6 := {"version": 6, "player": {"tile": [1, 1], "zone_seen": {}, "map_markers": []}, "daynight": {}, "world": {"seed": 7331}}
	var m6: Dictionary = SaveSystem._migrate(v6)
	check(int(m6["version"]) == 8 and bool(m6.get("relayout_cities", false)) and (m6["player"]["zone_seen"] as Dictionary).is_empty(), "save chain v6 -> v8 (walled cities, adventurers/PK) keeps v6 data")
	var m7: Dictionary = SaveSystem._migrate({"version": 7, "player": {"tile": [1, 1]}, "ai": {"version": 2, "agents": []}})
	check(not m7.has("relayout_cities"), "a v7 save is not re-laid out again")
	# 0.3.2 safety net: a migrated save is validated before it is used
	check(SaveSystem.validate(mig) == "" and SaveSystem.validate({"version": 3, "player": "x"}) != "" and SaveSystem.validate(null) != ""
		and SaveSystem.validate(SaveSystem._migrate({"version": 3, "player": "oops", "world": 7})) != "",
		"save validation: a migrated v3 save passes; damaged saves are rejected (not loaded half-way)")
	check(int(m7["version"]) == 8 and int(m7["player"]["skull_until"]) == -1 and not bool(m7["player"]["pk_warned"]) and m7["ai"].has("adv") and m7["ai"].has("gear_econ"),
		"save chain v7 -> v8 (adventurers + Scorch PK): no skull, rules card unseen, empty adventurer/gear-market blocks")
	# v7 load step: a player saved on an old Fenhollow street that is now a wall goes to the square
	var fr: Rect2i = gen._town_rects["fenhollow"]
	var wall_t := Vector2i(fr.position.x, fr.position.y + 3)
	p.place_at(wall_t)
	var rel: bool = main.apply_city_relayout(world, p)
	check(rel and p.tile == gen.town_spawn("fenhollow") and not world.is_blocked(p.tile), "v7 load: a player saved inside Fenhollow is put on its square %s" % str(p.tile))
	var out_t := gen.town_spawn("millbrook")
	p.place_at(out_t)
	check(not main.apply_city_relayout(world, p) and p.tile == out_t, "v7 load: a player outside the cities is not moved")
	world.ground.add(wall_t, "bones", 1, Tick.tick_count)
	var n_moved: int = main.relocate_piles_if_walled(world)
	var pile_ok := false
	for pl in world.ground.piles:
		if str(pl["id"]) == "bones" and Vector2(pl["pos"] - wall_t).length() <= 16.0 and not world.is_blocked(pl["pos"]):
			pile_ok = true
	check(n_moved >= 1 and pile_ok, "v7 load: ground items on a new city wall move to a free tile")
	world.ground.piles = world.ground.piles.filter(func(pl): return str(pl["id"]) != "bones")
	var zs := p.zone_seen.duplicate()
	p.zone_seen = {"scorch": true}
	var d := p.to_save()
	p.zone_seen = {}
	p.from_save(d)
	check(p.zone_seen.has("scorch") and d.has("map_markers"), "player save keeps both zone memory and map markers")
	p.zone_seen = zs
	p.place_at(gen.town_spawn("fenhollow"))


# ---------------------------------------------------------------- churches --
static func _church_tests(world: World, p: Player) -> void:
	var gen := world.gen
	var per_town := {}
	var stone_ok := true
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["kind"] != "church":
			continue
		per_town[b["town"]] = int(per_town.get(b["town"], 0)) + 1
		var r: Rect2i = b["rect"]
		var door: Vector2i = b["doors"][0]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var q := Vector2i(x, y)
				var t := gen.tile_at(x, y)
				var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
				if q == door:
					continue
				if edge and not t in [WorldGen.TileType.STONE_WALL, WorldGen.TileType.STONE_FRONT]:
					stone_ok = false
				if not edge and t != WorldGen.TileType.STONE_FLOOR:
					stone_ok = false
		var alt = world.object_at(b["altar"])
		stone_ok = stone_ok and alt != null and alt.def_id == "altar" and gen.is_inside(b["altar"] + Vector2i(0, 1 if door.y > b["altar"].y else -1), b)
	check(per_town.size() == gen.town_order.size() - int(gen.capital != "") and per_town.values().all(func(n): return n == 1),
		"0.3.1 one stone church per town %s" % str(per_town))
	check(stone_ok, "churches: grey stone walls + floor (not timber), an altar inside")
	var hook_ok := true
	for tid in gen.town_order:
		if tid == gen.capital:
			continue   # 0.3.8 the capital has no mines / chickens / church of its own
		var na := world.nearest_altar(gen.town_spawn(tid))
		hook_ok = hook_ok and na.get("town", "") == tid and not world.is_blocked(na["approach"])
	check(hook_ok, "World.nearest_altar(town spawn) is that town's altar, with a free approach tile")
	# walk in from the plaza, pray, walk out
	var tid := "fenhollow"
	var na := world.nearest_altar(gen.town_spawn(tid), tid)
	var b: Dictionary = gen.buildings[na["building"]]
	p.stop()
	p.action = {}
	p.place_at(gen.town_spawn(tid))
	world.set_focus(p.tile, true)
	var lvl := p.skills.level("prayer")
	p.prayer["points"] = 0.0
	var xp0 := int(p.skills.xp.get("prayer", 0))
	var obj = world.object_at(na["pos"])
	var started := p.interact(world, obj)
	var was_inside := false
	var kneel_ticks := 0
	var n := 0
	while n < 120 and not (p.action.is_empty() and p.path.is_empty()):
		Tick.step()
		n += 1
		was_inside = was_inside or gen.is_inside(p.tile, b)
		if p.path.is_empty() and p.action.get("kind", "") == "altar":
			kneel_ticks += 1
	var full := Prayer.points(p.prayer, p.skills.level("prayer")) >= Prayer.max_points(lvl) - 0.001
	check(started and was_inside and full, "tap the altar: walk in through the door, kneel, Prayer refilled to max (%.1f/%.1f after %d ticks)" % [Prayer.points(p.prayer, lvl), Prayer.max_points(lvl), n])
	check(kneel_ticks >= int(GameData.churches.get("kneel_ticks", 2)) - 1 and kneel_ticks <= 4, "the kneel takes ~%d ticks (%d)" % [int(GameData.churches.get("kneel_ticks", 2)), kneel_ticks])
	check(int(p.skills.xp.get("prayer", 0)) == xp0, "praying at the altar gives no Prayer XP")
	# the priest talks, no shop panel
	var opened := [0]
	var cb := func(_s): opened[0] += 1
	Events.shop_opened.connect(cb)
	p.on_shop(world, world.object_at(b["keeper_at"]))
	Events.shop_opened.disconnect(cb)
	check(opened[0] == 0, "tapping the priest talks (no shop panel)")
	# walk out
	var door: Vector2i = b["doors"][0]
	var out := door + (Vector2i(0, 3) if door.y == (b["rect"] as Rect2i).end.y - 1 else Vector2i(0, -3))
	p.walk_to(world, out)
	for i in 40:
		Tick.step()
		if p.path.is_empty():
			break
	check(not gen.is_inside(p.tile, b) and p.tile == out, "walk back out of the church (%s)" % str(p.tile))
	# AI players share the rule (Interactions): an AI actor at the approach tile prays too
	var ai_ok := false
	for a in p.get_tree().get_nodes_in_group("actors"):
		if a is AIPlayer and not a.dead and is_instance_valid(a):
			var keep_tile: Vector2i = a.tile
			var keep_action: Dictionary = a.action
			var keep_path: Array = a.path
			a.path = []
			a.place_at(na["approach"])
			a.prayer["points"] = 0.0
			a.action = {"pos": na["pos"], "kind": "altar", "progress": 0, "cooldown": 0}
			for i in 3:
				Interactions.perform(a, world, Tick.tick_count + i)
			ai_ok = Prayer.points(a.prayer, a.skills.level("prayer")) >= Prayer.max_points(a.skills.level("prayer")) - 0.001
			a.place_at(keep_tile)
			a.action = keep_action
			a.path = keep_path
			break
	check(ai_ok, "an AI player at World.nearest_altar() approach prays the same way")


# ----------------------------------------------------------- combat level --
static func _combat_level_tests(world: World, p: Player) -> void:
	var fresh := Skills.new()
	check(Combat.combat_level(fresh) == 2, "a new character is Combat %d (want 2: (1+1+1+10+1)/5 + 1/8)" % Combat.combat_level(fresh))
	var sk := Skills.new()
	for id in ["attack", "strength", "defence", "vitality"]:
		sk.set_level(id, 20)
	sk.set_level("prayer", 16)
	check(Combat.combat_level(sk) == 18, "Combat = floor((Atk+Str+Def+Vit+Arc)/5 + Prayer/8): 20s + Arc 1 + Prayer 16 = %d (want 18)" % Combat.combat_level(sk))
	check(int(GameData.combat.get("aggro_level_gap", 0)) == 10, "combat.json aggro_level_gap = 10")
	var keep: Dictionary = p.skills.xp.duplicate()
	var rat := _near(world, "giant_rat", world.gen.town_spawn("fenhollow"))
	for e in world.enemies.enemies:   # a rat with nobody else around (AIs would draw it off)
		if e.kind == "giant_rat" and not e.dead and AIDirector.agents.all(func(ai): return not is_instance_valid(ai) or e.cheb(ai.tile, e.home) > 8):
			rat = e
			break
	var aggro_test := func(lvl: int) -> bool:
		p.skills.xp = Skills.new().xp
		for id in ["attack", "strength", "defence", "vitality"]:
			p.skills.set_level(id, maxi(lvl, 10) if id == "vitality" else lvl)
		rat.target = null
		rat.reset_far()
		p.stop()
		p.hp = p.max_hp()
		p.place_at(world.find_free_tile_near(rat.tile + Vector2i(1, 0), 2, true))
		world.set_focus(p.tile, true)
		for i in 20:
			Tick.step()
			if rat.target == p:
				return true
		return false
	var low: bool = aggro_test.call(1)
	var high: bool = aggro_test.call(22)   # 0.3.6: rats are level 5, ignore Combat 15+
	check(low and not high, "rats (level 5) aggro a Combat %d player but ignore Combat 15+ (low %s, high %s)" % [Combat.combat_level(fresh), low, high])
	rat.take_hit(1, p, Tick.tick_count)
	check(rat.target == p, "...yet a rat you attack still fights back")
	rat.target = null
	rat.reset_far()
	# the Scorch too: a cinder brute (level 14) ignores Combat 24+
	var br := _near(world, "cinder_brute", Vector2i(300, -300))
	var ok_b := br != null and Combat.too_strong_for_aggro(br.level(), sk) == (Combat.combat_level(sk) >= 24) and not Combat.too_strong_for_aggro(br.level(), fresh)
	check(ok_b, "the rule holds in the Scorch (cinder brute level 14 vs Combat 18: still aggressive)")
	p.skills.xp = keep
	p.hp = p.max_hp()
	var e := Enemy.new()
	e.def = GameData.enemies["wolf"]
	check(e.display_name_level() == "Wolf (level 6)", "tapping an enemy names its level (%s)" % e.display_name_level())
	e.free()


# ------------------------------------------------- villages, wheat, cows --
static func _village_tests(world: World, p: Player) -> void:
	var gen := world.gen
	check(gen.village_order.size() >= 3 and gen.village_order.size() <= 4 and gen.towns.size() == 4, "3-4 villages between the cities (%s); 3 cities + the capital" % str(gen.village_order))
	var between_ok := true
	var bands_ok := true
	var parts_ok := true
	var path_ok := true
	var reach_ok := true
	var safe_ok := true
	var clear_ok := true
	var info := []
	for vid in gen.village_order:
		var v: Dictionary = gen.villages[vid]
		var c := gen.town_center(vid)
		# beside the road between its two cities
		var road: Array = gen.village_roads.get(vid, [])   # 0.3.8 its own dirt road to a town
		var dr := INF
		for q in road:
			dr = minf(dr, Vector2(q - c).length())
		between_ok = between_ok and dr < 25.0
		# distance bands are measured from the cities only
		bands_ok = bands_ok and gen.town_edge_distance(c) > 30.0 and gen.town_at(c, 0) == "" and gen.towns.has(gen.nearest_town(c))
		var houses := 0
		for bid in gen.building_order:
			if gen.buildings[bid]["town"] == vid and gen.buildings[bid]["kind"] == "house":
				houses += 1
		var has := {}
		var r: Rect2i = gen._village_rects[vid]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var oid := gen.object_id_at(Vector2i(x, y))
				if oid != "":
					has[oid] = true
		parts_ok = parts_ok and houses >= 2 and has.has("well") and has.has("quern") and has.has("hearth")
		var vp: Array = gen.village_paths.get(vid, [])
		var touches := false
		if not vp.is_empty():   # 0.3.8 the village's own road ends at a town gate
			for tid2 in gen.town_order:
				for q in gen.gate_outsides(tid2):
					touches = touches or maxi(absi(q.x - vp[-1].x), absi(q.y - vp[-1].y)) <= 3
		path_ok = path_ok and touches
		world.set_focus(gen.town_spawn(vid), true)
		for q in vp:
			path_ok = path_ok and not world.is_blocked(q)
		# cottages, the field gate and the pasture gate are reachable from the plaza
		var sp := gen.town_spawn(vid)
		var goals: Array = []
		for bid in gen.building_order:
			if gen.buildings[bid]["town"] == vid:
				goals.append(gen.buildings[bid]["stand"])
		for f in gen.farms:
			if f["village"] == vid:
				goals.append(f["gate"])
		for pz in gen.pastures:
			if pz["village"] == vid:
				goals.append(pz["gate"])
				safe_ok = safe_ok and not gen.safe_at(pz["center"])
		for g in goals:
			var okg: bool = g == sp or not Pathfinder.find_path(world, sp, [g], g, 6000).is_empty()
			if not okg:
				print("  unreachable from %s plaza %s: %s (blocked %s)" % [vid, sp, g, world.is_blocked(g)])
			reach_ok = reach_ok and okg
		if not vp.is_empty():
			reach_ok = reach_ok and not Pathfinder.find_path(world, sp, [vp[-1]], vp[-1], 6000).is_empty()
		safe_ok = safe_ok and gen.safe_at(sp) and gen.place_at(sp, 0) == vid
		info.append("%s road %.0f edge %.0f houses %d" % [vid, dr, gen.town_edge_distance(c), houses])
	for f in gen.farms:
		var fr: Rect2i = f["rect"]
		for y in range(fr.position.y + 1, fr.end.y - 1):
			for x in range(fr.position.x + 1, fr.end.x - 1):
				clear_ok = clear_ok and gen.object_id_at(Vector2i(x, y)) == "wheat"
	for pz in gen.pastures:
		var pr: Rect2i = pz["rect"]
		for y in range(pr.position.y + 1, pr.end.y - 1):
			for x in range(pr.position.x + 1, pr.end.x - 1):
				clear_ok = clear_ok and gen.object_at(x, y, gen.tile_at(x, y)) in ["", "fence_v"]   # 0.3.9 a paddock divider is fine
	check(between_ok, "each village has its own road starting at its gate %s" % str(info))
	check(bands_ok, "distance bands use the cities only (villages are not towns for bands/home/travel)")
	check(parts_ok, "every village has 2+ cottages, a well, a quern and a hearth")
	check(path_ok, "a path joins each village gate to the road %s" % str(gen.village_order.map(func(v): return [v, gen.village_paths.get(v, []).size(), gen.village_roads.has(v)])))
	check(reach_ok, "cottages, the wheat field and the pasture are reachable from each village plaza")
	check(safe_ok, "villages are safe zones; the pastures outside them are not")
	check(clear_ok, "fenced fields are all wheat; pastures have no trees or rocks")
	var vc := 0
	for e in world.enemies.enemies:
		if e.kind == "citizen" and gen.villages.has(e.town):
			vc += 1
	check(vc >= 2 * gen.village_order.size(), "villagers wander every village (%d)" % vc)
	check(str(GameData.object_def("well").get("type", "")) == "prop" and str(GameData.object_def("quern").get("station", "")) == "quern", "well (prop) and quern (station) objects")
	# a house: walk in, the villager talks (no shop panel)
	var hb: Dictionary = {}
	for bid in gen.building_order:
		if gen.buildings[bid]["kind"] == "house":
			hb = gen.buildings[bid]
			break
	var opened := []
	var cb := func(s): opened.append(s)
	Events.shop_opened.connect(cb)
	p.place_at(hb["stand"])
	world.set_focus(p.tile, true)
	p.on_shop(world, world.object_at(hb["keeper_at"]))
	Events.shop_opened.disconnect(cb)
	check(opened.is_empty() and str(hb["keeper_sprite"]) == "villager", "cottage villagers talk (no shop panel)")

	# ---- wheat: harvest -> regrows; 2 wheat -> flour at the quern; flour -> bread on the hearth
	var f0: Dictionary = gen.farms[0]
	world.set_focus(f0["center"], true)
	var keep: Dictionary = p.skills.xp.duplicate()
	p.inventory.clear()
	p.stop()
	var wobj: WorldObject = world.object_at(f0["center"])
	check(wobj != null and wobj.def_id == "wheat" and not wobj.blocks(), "wheat stands in the fenced field (walk-through crop)")
	p.place_at(f0["gate"])
	var got := false
	if wobj and p.interact(world, wobj):
		for i in 120:
			Tick.step()
			if p.inventory.count("wheat") > 0:
				got = true
				break
	var _fxp: int = p.skills.xp.get("foraging", 0)
	check(got and wobj.is_depleted(Tick.tick_count), "harvest wheat (Foraging 1): a sheaf, the stalk is cut to stubble")
	var back := false
	for i in int(GameData.object_def("wheat")["respawn"]) + 5:
		Tick.step()
		if not wobj.is_depleted(Tick.tick_count):
			back = true
			break
	check(back, "wheat regrows (%d ticks)" % int(GameData.object_def("wheat")["respawn"]))
	var vid0: String = f0["village"]
	var qpos := Vector2i.ZERO
	for q in gen.station_sites("quern"):
		if gen.village_at(q, 0) == vid0:
			qpos = q
	world.set_focus(qpos, true)
	p.inventory.clear()
	p.inventory.add("wheat", 2)
	p.place_at(world.find_free_tile_near(qpos + Vector2i(0, 1), 2, true))
	var made := false
	if p.start_recipe(world, world.object_at(qpos), "grind_flour", 1):
		for i in 60:
			Tick.step()
			if p.inventory.count("flour") > 0:
				made = true
				break
	check(made and p.inventory.count("wheat") == 0, "grind 2 wheat into flour at the village quern (Cooking)")
	p.skills.set_level("cooking", 10)
	var hearth: WorldObject = world.find_nearest_object(qpos, ["hearth"], 20)
	var baked := false
	if hearth and p.start_recipe(world, hearth, "bake_bread", 1):
		for i in 60:
			Tick.step()
			if p.inventory.count("bread") + p.inventory.count("burnt_bread") > 0:
				baked = true
				break
	var rb := Interactions.recipe_by_id("bake_bread")
	check(baked and str(rb.get("skill", "")) == "cooking" and str(rb.get("station", "")) == "hearth", "bake the flour into bread on the village hearth (Cooking %d)" % int(rb.get("level", 0)))
	check(int(GameData.item("bread").get("heals", 0)) > 0, "bread is food (heals %d)" % int(GameData.item("bread").get("heals", 0)))

	# ---- cows: 8 HP, passive, kick back weakly, always drop bones + beef + hide, respawn
	var pz0: Dictionary = gen.pastures[0]
	var cows := []
	for e in world.enemies.enemies:
		if e.kind == "cow" and (pz0["rect"] as Rect2i).has_point(e.home):
			cows.append(e)
	check(cows.size() == int(pz0["count"]), "%d cows graze in the pasture" % cows.size())
	var cow: Enemy = cows[0]
	check(cow.max_hp == 12 and cow.level() <= 3 and not cow.aggressive(), "cows: ~12 HP, low level (%d), passive" % cow.level())
	p.skills.xp = Skills.new().xp
	p.inventory.clear()
	p.hp = p.max_hp()
	check(_calm(world, p, cow), "a cow never starts a fight, even next to a new player")
	cow.take_hit(1, p, Tick.tick_count)
	check(cow.target == p and int(cow.def["max_hit"]) <= 1, "a hit cow kicks back (weakly: max hit %d)" % int(cow.def["max_hit"]))
	var drng := RandomNumberGenerator.new()
	drng.seed = 77
	var ok_d := true
	for i in 200:
		var ids := {}
		for d in DropTable.roll("cow", drng):
			ids[str(d[0])] = true
		ok_d = ok_d and ids.has("bones") and ids.has("raw_beef") and ids.has("cowhide")
	check(ok_d, "cows always drop bones, raw beef and a cowhide (200/200)")
	# kill one for real: drops land on the ground
	cow.target = null
	p.place_at(world.find_free_tile_near(cow.tile + Vector2i(1, 0), 2))
	while not cow.dead:
		cow.take_hit(cow.hp, p, Tick.tick_count)
		Tick.step()
	var items := {}
	for pile in world.ground.piles:
		if Vector2(pile["pos"] - cow.tile).length() <= 2.0:
			items[str(pile["id"])] = true
	check(cow.dead and items.has("raw_beef") and items.has("cowhide") and items.has("bones"), "killing a cow drops bones, raw beef and a cowhide %s" % str(items.keys()))
	var respawned := false
	for i in int(GameData.enemies["cow"]["respawn_ticks"]) + 10:
		Tick.step()
		if not cow.dead:
			respawned = true
			break
	check(respawned and (pz0["rect"] as Rect2i).has_point(cow.tile), "cows respawn in their pasture")
	var cbf := Interactions.recipe_by_id("cook_beef")
	check(int(cbf.get("level", 0)) == 5 and int(GameData.item("cooked_beef").get("heals", 0)) == 8, "raw beef cooks at Cooking 5 and heals 8 (0.3.6 tiered heals)")
	check(Market.town("fenhollow").npc_buy_price("cowhide") > 0 and GameData.item_value("cowhide") >= 10, "cowhide sells (general store buys at %d)" % Market.town("fenhollow").npc_buy_price("cowhide"))
	check((Market.shop_cfg.get("general_store", {}).get("stock", []) as Array).has("bread"), "the general store stocks bread")
	# ---- AI: a farmer in every town; fighters weigh up the cows; AIs find the fields
	var fpt := {}
	for a in AIDirector.records:
		if a.persona_id() == "farmer":
			fpt[a.home_town] = int(fpt.get(a.home_town, 0)) + 1
	check(gen.town_order.all(func(t): return t == gen.capital or int(fpt.get(t, 0)) >= 1), "a farmer persona lives in every city %s" % str(fpt))
	var herders := 0
	var fighters := 0
	for a in AIDirector.records:
		if AIBrain.is_fighter(a):
			fighters += 1
			herders += 1 if AIBrain.quarries(a).has("cow") else 0
	check(herders >= 1 and herders < fighters, "some AI fighters (herders, personas herd_share) also hunt the village cows: %d of %d" % [herders, fighters])
	var wn := world.find_gather_node(gen.town_center("fenhollow"), "wheat", "fenhollow")
	check(wn != null and gen.nearest_farm(wn.pos)["rect"].has_point(wn.pos), "AI farmers find the nearest village wheat field from their city")
	check(MineTravel.factor_def("fenhollow", GameData.object_def("wheat")) < 1.0, "walking out to the fields costs AIs time (factor %.2f)" % MineTravel.factor_def("fenhollow", GameData.object_def("wheat")))
	p.skills.xp = keep
	p.inventory.clear()
	p.hp = p.max_hp()
	p.stop()
	p.place_at(gen.town_spawn("fenhollow"))
	world.set_focus(p.tile, true)


# ------------------------------------------------------- walled cities --
static func _walled_city_tests(world: World, p: Player) -> void:
	print("  -- 0.3.1 walled cities")
	var gen := world.gen
	for tid in ["fenhollow", "cinderholt", "saltmere"]:
		var tdef: Dictionary = gen.towns[tid]
		var gates: Dictionary = tdef.get("gates", {})
		check(gates.size() == 4, "%s has N/S/E/W gates" % tid)
		var org: Vector2i = Vector2i(int(tdef["origin"][0]), int(tdef["origin"][1]))
		var wall_hits := 0
		var gate_hits := 0
		var rect: Rect2i = gen._town_rects[tid]
		for x in range(rect.position.x, rect.end.x):
			var top := gen.tile_at(x, rect.position.y)
			var bot := gen.tile_at(x, rect.end.y - 1)
			if top in WorldGen.BLOCKING_TILES:
				wall_hits += 1
			if bot in WorldGen.BLOCKING_TILES:
				wall_hits += 1
			if top in WorldGen.GATE_TILES:
				gate_hits += 1
			if bot in WorldGen.GATE_TILES:
				gate_hits += 1
		for y in range(rect.position.y, rect.end.y):
			var L := gen.tile_at(rect.position.x, y)
			var R := gen.tile_at(rect.end.x - 1, y)
			if L in WorldGen.BLOCKING_TILES:
				wall_hits += 1
			if R in WorldGen.BLOCKING_TILES:
				wall_hits += 1
			if L in WorldGen.GATE_TILES:
				gate_hits += 1
			if R in WorldGen.GATE_TILES:
				gate_hits += 1
		check(wall_hits >= 80 and gate_hits >= 8, "%s perimeter walls+gates (walls %d gates %d)" % [tid, wall_hits, gate_hits])
		# walk in and out every gate
		var spawn: Vector2i = gen.town_spawn(tid)
		for dir in gates.keys():
			var cells: Array = gates[dir]
			var mid: Vector2i = org + Vector2i(int(cells[1][0]), int(cells[1][1]))
			check(gen.tile_at(mid.x, mid.y) in WorldGen.GATE_TILES and not world.is_blocked(mid),
				"%s %s gate tile walkable" % [tid, dir])
			# outside neighbour
			var outside: Vector2i = mid
			match str(dir):
				"north": outside = mid + Vector2i(0, -1)
				"south": outside = mid + Vector2i(0, 1)
				"west": outside = mid + Vector2i(-1, 0)
				"east": outside = mid + Vector2i(1, 0)
			var path_in: Array = Pathfinder.find_path(world, outside, [spawn], spawn, 8000)
			var path_out: Array = Pathfinder.find_path(world, spawn, [outside], outside, 8000)
			var via_gate := false
			for q in path_in:
				if q == mid or (abs(q.x - mid.x) + abs(q.y - mid.y)) <= 1 and gen.tile_at(q.x, q.y) in WorldGen.GATE_TILES:
					via_gate = true
			check(not path_in.is_empty() and not path_out.is_empty(),
				"%s path in/out via %s gate (%d/%d steps)" % [tid, dir, path_in.size(), path_out.size()])
		# required buildings inside walls
		var need := {"general": false, "player": false, "cook": false, "church": false, "smithy": false}
		for id in gen.building_order:
			var b: Dictionary = gen.buildings[id]
			if b["town"] != tid:
				continue
			if b["kind"] == "church":
				need["church"] = true
			elif b["kind"] == "smithy":
				need["smithy"] = true
			elif b["shop"] in need:
				need[b["shop"]] = true
			# building centre inside town rect
			var c: Vector2i = (b["rect"] as Rect2i).get_center()
			check(rect.has_point(c), "%s building %s inside town rect" % [tid, b["id"]])
		check(need["general"] and not need["player"] and need["cook"] and need["church"] and need["smithy"],
			"%s has general, cookhouse, church, smithy and no player shop (0.3.8: Highfen only) %s" % [tid, str(need)])
		# unique wall tileset
		var sample := gen.tile_at(rect.position.x, rect.position.y + 2)
		match tid:
			"fenhollow":
				check(sample == WorldGen.TileType.PALISADE or sample in WorldGen.GATE_TILES, "fenhollow uses palisade walls")
			"cinderholt":
				check(sample == WorldGen.TileType.BASALT_WALL or sample in WorldGen.GATE_TILES, "cinderholt uses basalt walls")
			"saltmere":
				check(sample == WorldGen.TileType.SANDSTONE_WALL or sample in WorldGen.GATE_TILES, "saltmere uses sandstone walls")
	# gate guards: 2 stationary per gate, non-aggressive
	var gate_guards: int = 0
	var aggro := false
	for e in world.enemies.enemies:
		if e.kind != "town_guard":
			continue
		if e.patrol.size() == 1:
			gate_guards += 1
		if e.aggressive():
			aggro = true
	check(gate_guards >= 3 * 8 and not aggro, "2 stationary guards per gate across towns (%d), none aggressive" % gate_guards)
	# AI not stuck on walls: simulate a few agents near walls
	var stuck: int = 0
	for e in world.enemies.enemies:
		if e.kind != "town_guard" or e.patrol.size() != 1:
			continue
		var start: Vector2i = e.tile
		for i in 30:
			Tick.step()
		if world.is_blocked(e.tile):
			stuck += 1
		e.tile = start
		e.prev_tile = start
		e.home = start
	check(stuck == 0, "gate guards never end a tick on a wall tile")
	# save migration off a city wall
	var fen: Rect2i = gen._town_rects["fenhollow"]
	p.place_at(Vector2i(fen.position.x, fen.position.y + 3))
	if world.is_blocked(p.tile):
		var q: Vector2i = world.find_free_tile_near(p.tile, 16, true)
		p.place_at(q)
	check(not world.is_blocked(p.tile), "player relocated off city wall tile")
	p.place_at(gen.town_spawn("fenhollow"))


# ---------------------------------------------------------- cookhouse --
static func _cookhouse_tests(world: World, p: Player) -> void:
	print("  -- 0.3.1 cookhouse")
	var gen := world.gen
	for tid in gen.town_order:
		var b: Dictionary = gen.building_for_shop(tid, "cook")
		check(not b.is_empty() and b["kind"] == "cookhouse", "%s has a cookhouse building" % tid)
		var oven: WorldObject = null
		for pr in []: # find oven in building
			pass
		# scan building footprint for oven
		var r: Rect2i = b["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var o = world.object_at(Vector2i(x, y))
				if o and o.def_id == "oven":
					oven = o
		check(oven != null and str(oven.def().get("station", "")) == "hearth",
			"%s cookhouse has an oven (hearth station)" % tid)
		var m = Market.town(tid)
		check("cook" in m.specialists, "%s market lists cook specialist" % tid)
		var gp := m.shop_price("general", "cooked_carp")
		var cp := m.shop_price("cook", "cooked_carp")
		check(cp > 0 and cp < gp and cp <= int(ceil(gp * 0.85)),
			"%s cookhouse cooked_carp %d < general %d (~80%%)" % [tid, cp, gp])
		check(m.shelf("cook", "cooked_carp") > 0 and m.shelf("cook", "cooked_carp") <= 40,
			"%s cookhouse has finite stock (%d)" % [tid, m.shelf("cook", "cooked_carp")])
	# walk in, cook on oven, buy cheaper food
	var b2: Dictionary = gen.building_for_shop("fenhollow", "cook")
	var outside: Vector2i = b2["doors"][0] + Vector2i(0, 2)
	if world.is_blocked(outside):
		outside = b2["doors"][0] + Vector2i(0, -2)
	p.place_at(outside)
	p.inventory.clear()
	p.inventory.add("raw_carp", 2)
	p.inventory.add(GameData.currency, 200)
	var oven2: WorldObject = null
	var r2: Rect2i = b2["rect"]
	for y in range(r2.position.y, r2.end.y):
		for x in range(r2.position.x, r2.end.x):
			var o2 = world.object_at(Vector2i(x, y))
			if o2 and o2.def_id == "oven":
				oven2 = o2
	p.interact(world, oven2)
	for i in 80:
		Tick.step()
		if p.inventory.count("cooked_carp") + p.inventory.count("charred_fish") >= 1 and p.action.is_empty():
			break
	check(p.inventory.count("cooked_carp") + p.inventory.count("charred_fish") >= 1,
		"cook on the cookhouse oven (carp cooked or charred)")
	var m2 = Market.town("fenhollow")
	var price := m2.shop_price("cook", "cooked_rat_meat")
	var gprice := m2.shop_price("general", "cooked_carp")
	var before := p.inventory.count(GameData.currency)
	var cost := m2.shop_sell_to("cook", "cooked_rat_meat", 1)
	if cost > 0:
		p.inventory.remove(GameData.currency, cost)
		p.inventory.add("cooked_rat_meat", 1)
	check(cost > 0 and cost < gprice and p.inventory.count("cooked_rat_meat") >= 1,
		"buy cooked food from cookhouse cheaper than general staples (paid %d)" % cost)
	# AI can path to cookhouse door
	var path := Pathfinder.find_path(world, gen.town_spawn("fenhollow"), b2["doors"], b2["doors"][0], 5000)
	check(not path.is_empty(), "AI can path to the cookhouse door")
	p.place_at(gen.town_spawn("fenhollow"))


# ------------------------------------- walled cities x world/villages/night --
static func _walled_integration_tests(world: World, p: Player) -> void:
	print("  -- 0.3.1 walled cities: roads, villages, safety, night")
	var gen := world.gen
	# every road leaves a city through a gate (starts/ends at a gate approach)
	var gates_ok := true
	var why := []
	for k in gen.roads.keys():
		var road: Array = gen.roads[k]
		var ab: PackedStringArray = str(k).split("|")
		for end in [[ab[0], road[0]], [ab[1], road[-1]]]:
			var best := 1 << 30
			for q in gen.gate_outsides(end[0]):
				best = mini(best, maxi(absi(q.x - end[1].x), absi(q.y - end[1].y)))
			if best > (3 if end[0] == gen.capital else 2):
				gates_ok = false
				why.append("%s %s %d" % [k, end[0], best])
	check(gates_ok, "every road runs gate to gate (road ends within 2 tiles of a city gate) %s" % str(why))
	var through_ok := true
	for q in gen.road_tiles.keys():
		if gen.town_at(q, 0) != "" or gen.village_at(q, 0) != "":
			through_ok = false
		for f in gen.farms + gen.pastures:
			if (f["rect"] as Rect2i).has_point(q):
				through_ok = false
	check(through_ok, "no road crosses a city wall, a village, a field or a pasture")
	# each gate approach links to the road: walk from the gate to the road's first tile
	var walk_ok := true
	for k in ["fenhollow|cinderholt", "saltmere|fenhollow", "cinderholt|saltmere"]:
		var road: Array = gen.road_between(k.split("|")[0], k.split("|")[1])
		var spn: Vector2i = gen.town_spawn(k.split("|")[0])
		world.set_focus(spn, true)
		var path: Array = Pathfinder.find_path(world, spn, [road[0]], road[0], 8000)
		var via := false
		for q in path:
			via = via or gen.tile_at(q.x, q.y) in WorldGen.GATE_TILES
		walk_ok = walk_ok and not path.is_empty() and via
	check(walk_ok, "from each city square, the walk to its road goes out through a gate")
	# villages still sit outside the walls, beside their road
	var vill_ok := true
	for vid in gen.village_order:
		var vr: Rect2i = gen._village_rects[vid]
		for tid in gen.town_order:
			vill_ok = vill_ok and not (gen._town_rects[tid] as Rect2i).grow(20).intersects(vr)
	check(vill_ok, "villages stay clear of the city walls (20+ tiles)")
	# civic buildings wholly inside the walls; city interiors + gates are safe zones
	var inside_ok := true
	var bad := []
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if not gen.towns.has(b["town"]):
			continue
		var inner: Rect2i = (gen._town_rects[b["town"]] as Rect2i).grow(-1)
		if not inner.encloses(b["rect"]):
			inside_ok = false
			bad.append(id)
	check(inside_ok, "every city building (church, smithy, player shop, cook house...) lies inside its walls %s" % str(bad))
	var safe_ok := true
	for tid in gen.town_order:
		var r: Rect2i = gen._town_rects[tid]
		for y in range(r.position.y, r.end.y, 3):
			for x in range(r.position.x, r.end.x, 3):
				safe_ok = safe_ok and gen.safe_at(Vector2i(x, y))
		for q in gen.gate_outsides(tid):
			var g: Vector2i = q
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if gen.tile_at(q.x + d.x, q.y + d.y) in WorldGen.GATE_TILES:
					g = q + d
			safe_ok = safe_ok and (gen.safe_at(g) or tid == gen.capital)   # 0.3.8 Highfen's gates are bridge ends on the rect edge
	check(safe_ok, "walled cities are safe zones (whole interior and the gates)")
	# a rat just outside a gate never starts on a weak player standing in the gateway
	var tid0 := "fenhollow"
	var go: Vector2i = gen.gate_outside(tid0, gen.towns["cinderholt"]["center"])
	var gate_t := go
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if gen.tile_at(go.x + d.x, go.y + d.y) in WorldGen.GATE_TILES:
			gate_t = go + d
	var rat := _near(world, "giant_rat", go)
	var keep: Dictionary = p.skills.xp.duplicate()
	p.skills.xp = Skills.new().xp
	p.stop()
	p.place_at(gate_t)
	world.set_focus(p.tile, true)
	var old_home: Vector2i = rat.home
	rat.target = null
	rat.home = world.find_free_tile_near(go + (go - gate_t), 2, true)
	rat.tile = rat.home
	rat.prev_tile = rat.home
	var bit := false
	for i in 20:
		Tick.step()
		bit = bit or rat.target == p
	p.place_at(go + (go - gate_t))
	if rat.dead:     # an AI hunter may kill it meanwhile: bring it back on its spot
		rat._respawn()
		rat.tile = rat.home
		rat.prev_tile = rat.home
		rat.target = null
	var bit_out := false
	for ai in AIDirector.agents:   # passing AI hunters would draw the rat off
		if is_instance_valid(ai) and not ai.dead and rat.cheb(ai.tile, go) <= 16:
			ai.stop()
			ai.place_at(world.find_free_tile_near(ai.tile + Vector2i(0, 40), 6, true))
	var keep_mhp := rat.max_hp
	rat.max_hp = 999     # AI hunters nearby must not kill it mid-check
	rat.hp = 999
	for i in 20:
		if rat.target != null and rat.target != p:
			rat.target = null    # a passing AI hunter picked a fight with it: not what we test
		Tick.step()
		# any creature may be the one that starts on you (single combat: one at a time)
		bit_out = bit_out or world.enemies.enemies.any(func(e): return is_instance_valid(e) and e.target == p)
	rat.max_hp = keep_mhp
	rat.hp = mini(rat.hp, keep_mhp)
	check(not bit and bit_out and Combat.combat_level(p.skills) == 2,
		"a Combat 2 player in a city gateway is safe from a rat just outside (and aggroed a step out: %s)" % bit_out)
	rat.target = null
	p.hp = p.max_hp()
	rat.home = old_home
	rat.reset_far()
	p.skills.xp = keep
	# night: windows on every city facade (timber, basalt, plaster), cook houses too, torches at every gate
	var win_ok := true
	var styles := {}
	var cook_lit := 0
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if not gen.towns.has(b["town"]):
			continue
		var wins: Array = DayNight.window_tiles(world, b, 2)
		styles[b["style"]] = int(styles.get(b["style"], 0)) + 1
		var ok_b := wins.size() >= 1
		for wt in wins:
			ok_b = ok_b and not (wt in b["doors"]) and int(wt.y) == int(b["facade_y"])
		win_ok = win_ok and ok_b
		if b["kind"] == "cookhouse" and ok_b:
			cook_lit += 1
	check(win_ok and styles.size() >= 3, "every city facade gets lit windows at night (styles %s)" % str(styles))
	check(cook_lit == gen.town_order.size(), "each Cook House has lit windows at night (%d)" % cook_lit)
	var gt: Array = DayNight.gate_torch_tiles(world)
	var gt_ok := gt.size() == 8 * gen.town_order.size()
	for q in gt:
		gt_ok = gt_ok and gen.tile_at(q.x, q.y) in WorldGen.BLOCKING_TILES
	check(gt_ok, "a torch on the wall each side of every city gate (%d)" % gt.size())
	p.place_at(gen.town_spawn("fenhollow"))
	world.set_focus(p.tile, true)
