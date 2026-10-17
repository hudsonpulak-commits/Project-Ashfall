class_name Patch038Tests
extends RefCounted
## 0.3.8: Highfen capital (moat, gates), stone/dirt roads + roadside decor,
## player house, the only player shop (+ old-save migration), slimes.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func _road_ok(world: World, road: Array) -> String:
	for i in road.size():
		var q: Vector2i = road[i]
		if i > 0:
			var d: Vector2i = (q - (road[i - 1] as Vector2i)).abs()
			if maxi(d.x, d.y) != 1:
				return "gap at %s" % q
		if world.tile_type(q) in WorldGen.BLOCKING_TILES:
			return "blocked tile at %s (%s)" % [q, WorldGen.TILE_NAMES[world.tile_type(q)]]
		var o: WorldObject = world.object_at(q)
		if o != null and o.blocks():
			return "%s on the road at %s" % [o.def_id, q]
	return ""


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.8 Highfen / roads / house / shop / slime")
	var gen: WorldGen = world.gen
	var cap := gen.capital
	# 0.3.8.1 new characters start in Fenhollow's plaza next to Kell, not Highfen
	var ns := gen.town_spawn("fenhollow")
	var kell = world.find_nearest_object(ns, ["quest_giver"], 8)
	check(gen.place_at(ns, 8) == "fenhollow" and kell != null and not world.is_blocked(ns), "0.3.8.1 new character spawns in Fenhollow near Kell (%s, kell %s)" % [ns, kell.pos if kell else null])
	var hc: Vector2i = gen.town_center(cap) if cap != "" else Vector2i.ZERO
	check(cap == "highfen" and (hc - gen.continent_center).length() <= 2, "Highfen is the capital at the continent centre (%s)" % hc)
	# circle + moat + gates
	var moat := 0
	var wall := 0
	for a in range(0, 360, 10):
		var hit_m := false
		var hit_w := false
		for r in range(20, 37):
			var q := hc + Vector2i(roundi(cos(deg_to_rad(a)) * r), roundi(sin(deg_to_rad(a)) * r))
			var tt := gen.tile_at(q.x, q.y)
			hit_m = hit_m or tt == WorldGen.TileType.MOAT or tt == WorldGen.TileType.BRIDGE
			hit_w = hit_w or tt in [WorldGen.TileType.CAPITAL_WALL, WorldGen.TileType.CAPITAL_FRONT, WorldGen.TileType.GATE_CAPITAL]
		moat += int(hit_m)
		wall += int(hit_w)
	check(moat == 36 and wall == 36, "a round wall and a moat ring all the way round (%d/36 moat, %d/36 wall)" % [moat, wall])
	check(gen.gate_outsides(cap).size() == 4 and WorldGen.TileType.MOAT in WorldGen.BLOCKING_TILES, "4 gates with bridges over the moat; the moat can't be walked")
	# roads: every town -> Highfen by stone road, walkable, 2-3 wide
	var road_report := []
	var all_ok := true
	var wide := 0
	var samples := 0
	for tid in gen.town_order:
		if tid == cap:
			continue
		var road: Array = gen.road_between(tid, cap)
		var err := _road_ok(world, road) if not road.is_empty() else "no road"
		var stone := road.filter(func(q): return gen.road_tiles.get(q, -1) == WorldGen.TileType.ROAD_STONE).size()
		all_ok = all_ok and err == "" and stone > road.size() * 0.6
		road_report.append("%s %d tiles (%d stone) %s" % [tid, road.size(), stone, err])
		for i in range(20, road.size() - 20, 15):
			var q: Vector2i = road[i]
			if gen.road_tiles.get(q, -1) == WorldGen.TileType.BRIDGE:
				continue
			samples += 1
			var n := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				n += int(gen.road_tiles.has(q + d))
			wide += int(n >= 3)
	check(all_ok, "a walkable stone road from every town to Highfen (%s)" % ", ".join(road_report))
	check(samples > 0 and wide >= samples * 0.8, "main roads are 2-3 tiles wide (%d/%d samples)" % [wide, samples])
	var thru: Array = gen.road_between("fenhollow", "saltmere")
	check(not thru.is_empty() and _road_ok(world, thru) == "" and thru.any(func(q): return gen.town_at(q, 0) == cap), "town-to-town trips run through Highfen on walkable tiles")
	# village roads: dirt, winding
	var vrep := []
	var v_ok := true
	for vid in gen.village_roads.keys():
		var vr: Array = gen.village_roads[vid]
		var straight := Vector2(vr[-1] - vr[0]).length()
		var plen := 0.0
		for i in range(1, vr.size()):
			plen += Vector2(vr[i] - vr[i - 1]).length()
		var dirt := vr.filter(func(q): return gen.road_tiles.get(q, -1) == WorldGen.TileType.ROAD_DIRT).size()
		v_ok = v_ok and _road_ok(world, vr) == "" and dirt > vr.size() * 0.5 and plen > straight * 1.1
		vrep.append("%s %.0f/%.0f dirt %d/%d %s" % [vid, plen, straight, dirt, vr.size(), _road_ok(world, vr)])
	check(gen.village_roads.size() == 3 and v_ok, "each village has a winding dirt road to its town (%s)" % ", ".join(vrep))
	# decorations
	var kinds := {}
	for q in gen.road_decor.keys():
		kinds[gen.road_decor[q]] = int(kinds.get(gen.road_decor[q], 0)) + 1
	check(kinds.size() == 4 and gen.road_decor.keys().all(func(q): return not gen.road_tiles.has(q)), "fences, rocks, bushes and old logs line the roads, never on them (%s)" % str(kinds))
	var log_pos := Vector2i(1 << 20, 0)
	var dirs := [Vector2i(1, 0), Vector2i(0, 1)]
	var ldir := Vector2i.ZERO
	for q in gen.road_decor.keys():
		if gen.road_decor[q] != "old_log":
			continue
		for d in dirs:
			if not world.is_blocked(q - d * 2) and not world.is_blocked(q + d * 2) and not world.is_blocked(q - d) and not world.is_blocked(q + d):
				log_pos = q
				ldir = d
				break
		if ldir != Vector2i.ZERO:
			break
	world.set_focus(log_pos, true)
	var lg: WorldObject = world.object_at(log_pos)
	check(lg != null and lg.def_id == "old_log" and world.is_blocked(log_pos), "an old log blocks walking")
	check(Combat.line_of_sight(world, log_pos - ldir * 2, log_pos + ldir * 2), "...but an arrow flies over it (line of sight)")
	var path := Pathfinder.find_path(world, log_pos - ldir, [log_pos + ldir], log_pos + ldir)
	check(not path.has(log_pos), "pathing walks round the log (%d steps)" % path.size())
	# the only player shop
	var ps_b := []
	for bid in gen.buildings.keys():
		if gen.buildings[bid]["kind"] == "player":
			ps_b.append(bid)
	check(ps_b == ["highfen_player"] and Market.player_shops.keys() == ["highfen"], "the player shop exists only in Highfen (%s; markets %s)" % [str(ps_b), str(Market.player_shops.keys())])
	# old saves: shops in other towns migrate (ownership, till, stock; overflow + refund to the bank)
	var keep_m: Dictionary = Market.to_save()
	var stock := []
	for i in 8:
		stock.append({"item": "ash_log", "qty": 5, "price": 9, "dur": -1})
	var old := {"version": 2, "player_shops": {
		"fenhollow": {"owned": true, "owner": "Hud", "slots": stock, "till": 120},
		"saltmere": {"owned": true, "owner": "Hud", "slots": [{"item": "iron_sword", "qty": 1, "price": 300, "dur": -1}], "till": 30},
		"cinderholt": {"owned": false}}}
	Market.from_save(old)
	var hs: PlayerShop = Market.player_shop("highfen")
	var n_over := Market.shop_overflow.size()
	check(hs.owned and hs.till == 150 and hs.stocked().size() == 8, "old save: both owned shops merge into Highfen (till %d, %d stands stocked)" % [hs.till, hs.stocked().size()])
	var v0: int = p.vaults.get("highfen").count("iron_sword") if p.vaults.has("highfen") else 0
	var m0: int = p.vaults.get("highfen").count(GameData.currency) if p.vaults.has("highfen") else 0
	p.receive_shop_overflow()
	check(n_over == 2 and p.vaults["highfen"].count("iron_sword") == v0 + 1 and p.vaults["highfen"].count(GameData.currency) == m0 + PlayerShop.building_price(),
		"stock that didn't fit + a refund for the 2nd shop go to the Highfen bank (nothing lost)")
	p.vaults["highfen"].remove("iron_sword", 1)
	p.vaults["highfen"].remove(GameData.currency, PlayerShop.building_price())
	Market.from_save(keep_m)
	# the house
	var house: Dictionary = gen.buildings.get("highfen_house", {})
	var inside := {}
	for q in gen._town_objects.keys():
		if not house.is_empty() and (house["rect"] as Rect2i).has_point(q):
			var dd: Dictionary = GameData.object_def(str(gen._town_objects[q]))
			inside[str(dd.get("station", dd.get("type", "")))] = true
	var need := ["hearth", "furnace", "anvil", "workbench", "quern", "bank"]
	check(need.all(func(k): return inside.has(k)), "the townhouse has every station (%s) and a bank chest" % str(inside.keys()))
	p.house_owned = false
	var hw: Vector2i = house["rect"].position + Vector2i(4, 1)
	var anv: WorldObject = null
	for q in gen._town_objects.keys():
		if (house["rect"] as Rect2i).has_point(q) and gen._town_objects[q] == "anvil":
			world.set_focus(q, true)
			anv = world.object_at(q)
	check(anv != null and gen.is_private(anv.pos) and world.find_nearest_object(anv.pos, ["anvil"], 3) == null, "house benches are private: AIs never pick them")
	var coin: String = GameData.currency
	var c0 := p.inventory.count(coin)
	p.inventory.add(coin, Player.house_price())
	p._house_offer_ms = -1000000
	var r1 := p.house_clerk()
	var r2 := p.house_clerk()
	check(r1 == "offer" and r2 == "bought" and p.house_owned and p.inventory.count(coin) == c0, "buying the house: the clerk quotes, a second tap buys it (-%d marks)" % Player.house_price())
	var sv := p.to_save()
	var q2 := Player.new()
	q2.from_save(sv)
	check(q2.house_owned, "house ownership is saved")
	q2.free()
	p.house_owned = false
	# slimes
	var sd: Dictionary = GameData.enemies.get("slime", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 38
	var bones := 0
	var goo := 0
	for i in 300:
		for dr in DropTable.roll("slime", rng):
			bones += int(str(dr[0]) == "bones")
			goo += int(str(dr[0]) == "slime_goo")
	check(not sd.is_empty() and int(sd["level"]) <= 5 and bones == 0 and goo > 60, "slime: low level (%d), drops goo (%d) and never bones" % [int(sd.get("level", 0)), goo])
	var near := 0
	var total := 0
	for c in GameData.camps:
		if str(c["enemy"]) != "slime":
			continue
		total += 1
		var at := Vector2i(int(c["at"][0]), int(c["at"][1]))
		var dt := 1 << 20
		for tid in gen.town_order:
			dt = mini(dt, int((at - gen.town_center(tid)).length()))
		for vid in gen.village_order:
			dt = mini(dt, int((at - (gen.villages[vid]["center"] as Vector2i)).length()))
		near += int(dt < 60)
	check(total >= 7 and near == total, "slime camps by every town and village (%d/%d close)" % [near, total])
	# old save standing on a changed tile (the moat) is moved somewhere safe
	var keep_t := p.tile
	var mt := hc + Vector2i(-5, -34)
	world.set_focus(mt, true)
	p.place_at(mt)
	var moved: bool = main.relocate_if_walled(world, p)
	check(gen.tile_at(mt.x, mt.y) == WorldGen.TileType.MOAT and moved and not world.is_blocked(p.tile), "an old save standing in the moat is moved to a free tile (%s)" % p.tile)
	p.place_at(keep_t)
	world.set_focus(keep_t, true)
