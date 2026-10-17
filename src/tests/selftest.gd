extends RefCounted
## Headless gameplay tests. Run:
##   godot --headless --path . -- --selftest
## Exit code = number of failed checks. Prints "SELFTEST PASS a/b".

static var passed := 0
static var failed := 0


static func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)


static func ticks(n: int) -> void:
	for i in n:
		Tick.step()


static func run(main) -> int:
	Tick.running = false
	passed = 0
	failed = 0
	var world: World = main.world
	var p: Player = main.player
	print("SELFTEST start (Godot %s)" % Engine.get_version_info()["string"])

	# --- data
	check(GameData.items.size() >= 20, "items loaded (%d)" % GameData.items.size())
	check(GameData.skills.size() == 14 and GameData.skill_by_id.has("archery") and GameData.skill_by_id.has("prayer") and GameData.skill_by_id.has("attack") and GameData.skill_by_id.has("strength")
		and GameData.skill_by_id.has("defence") and not GameData.skill_by_id.has("melee"), "14 skills defined (Attack, Strength, Defence replace Melee; incl. Prayer, Archery)")
	check(GameData.objects.size() >= 12, "world objects loaded")
	check(GameData.xp_for_level(2) == 100, "xp curve L2 = 100")
	var mono := true
	for l in range(2, GameData.max_level + 1):
		mono = mono and GameData.xp_for_level(l) > GameData.xp_for_level(l - 1)
	check(mono, "xp curve strictly increasing to cap")
	check(GameData.level_for_xp(GameData.xp_for_level(17)) == 17, "level_for_xp inverse")
	var missing := 0
	for cat in ["tiles", "objects", "actors", "items", "ui"]:
		for id in GameData.sprites.get(cat, {}).keys():
			if not ResourceLoader.exists(GameData.sprite_def(cat, id)["path"]):
				missing += 1
				printerr("    missing sprite ", cat, "/", id)
	check(missing == 0, "every mapped sprite PNG exists")
	for oid in GameData.objects.keys():
		var sid: String = GameData.objects[oid]["sprite"]
		if sid != "" and GameData.sprite_def("objects", sid).is_empty():
			missing += 1
			printerr("    object %s -> unmapped sprite %s" % [oid, sid])
	check(missing == 0, "every object sprite id is mapped")

	# --- world gen
	var g1 := WorldGen.new(42, GameData.towns["fenhollow"])
	var g2 := WorldGen.new(42, GameData.towns["fenhollow"])
	var c1 := g1.generate_chunk(Vector2i(3, -2))
	var c2 := g2.generate_chunk(Vector2i(3, -2))
	check(c1.tiles == c2.tiles and c1.objects.size() == c2.objects.size(), "world gen deterministic per seed")
	var waters := 0
	for cy in range(-4, 5):
		for cx in range(-4, 5):
			var ch := world.get_chunk(Vector2i(cx, cy))
			for t in ch.tiles:
				if t == WorldGen.TileType.WATER:
					waters += 1
	check(waters > 0, "wilderness has water (%d tiles in 9x9 chunks)" % waters)
	check(not world.is_blocked(world.gen.town_spawn()), "spawn tile walkable")
	var chest := world.find_nearest_object(world.gen.town_spawn(), ["bank_chest"], 40)
	check(chest != null and world.gen.town_at(chest.pos, 0) == "fenhollow", "bank chest in Fenhollow plaza")
	check(world.chunk_views.size() == 25, "5x5 chunk views streamed (%d)" % world.chunk_views.size())

	# --- pathfinding
	var path := Pathfinder.find_path(world, Vector2i(0, 0), [Vector2i(0, 9)], Vector2i(0, 9))
	check(not path.is_empty() and path[-1] == Vector2i(0, 9), "path spawn -> south road")
	var clean := true
	for q in path:
		clean = clean and not world.is_blocked(q)
	check(clean, "path avoids blocked tiles")
	var pond := Vector2i(1 << 20, 0)
	var fr: Rect2i = world.gen._town_rects["fenhollow"]
	for y in range(fr.position.y, fr.end.y):
		for x in range(fr.position.x, fr.end.x):
			if pond.x == 1 << 20 and world.gen.tile_at(x, y) == WorldGen.TileType.WATER and world.gen.tile_at(x + 1, y) == WorldGen.TileType.WATER and world.gen.tile_at(x, y + 1) == WorldGen.TileType.WATER:
				pond = Vector2i(x + 1, y + 1)
	var wpath := Pathfinder.find_path(world, Vector2i(0, 0), [pond], pond)
	check(wpath.is_empty(), "cannot path onto pond water")
	p.walk_to(world, pond)
	check(not p.path.is_empty() and not world.is_blocked(p.path[-1]), "tap on water walks to the shore instead")
	p.stop()

	# --- gathering
	p.place_at(Vector2i(0, 0))
	p.inventory.clear()
	p.inventory.add("bronze_hatchet")
	var tree: WorldObject = world.find_nearest_object(p.tile, ["ash_tree"], 30)
	check(tree != null, "ash tree near spawn")
	var xp0 := int(p.skills.xp["forestry"])
	p.interact(world, tree)
	var got := false
	for i in 400:
		Tick.step()
		if p.inventory.count("ash_log") > 0:
			got = true
			break
	check(got, "chopping yields an ash log (tile %s, tree %s)" % [p.tile, tree.pos])
	check(int(p.skills.xp["forestry"]) > xp0, "forestry xp gained")
	var dur_after: int = p.inventory.slots[p.inventory.best_tool_index("forestry")]["dur"]
	check(dur_after < int(GameData.item("bronze_hatchet")["tool"]["durability"]), "hatchet wears with use")
	p.stop()

	# --- pack full
	p.inventory.clear()
	for i in 24:
		p.inventory.add("copper_ore")
	check(p.inventory.is_full(), "24 non-stackables fill the pack")
	check(p.inventory.add("marks", 5) == 0, "full pack refuses a new stack")
	tree = world.find_nearest_object(p.tile, ["ash_tree"], 30)
	p.interact(world, tree)
	ticks(60)
	check(p.action.is_empty() and p.inventory.count("ash_log") == 0, "gathering stops when pack is full")

	# --- banking
	var chest_obj := world.find_nearest_object(world.gen.town_spawn(), ["bank_chest"], 40)
	var opened := [false]
	var cb := func(): opened[0] = true
	Events.bank_opened.connect(cb)
	p.interact(world, chest_obj)
	ticks(60)
	Events.bank_opened.disconnect(cb)
	check(opened[0], "walking to the chest opens the bank")
	var moved := p.deposit_all(false)
	check(moved == 24 and p.inventory.free_slots() == 24 and p.bank.count("copper_ore") == 24, "deposit all -> bank stacks 24 ore")
	var bi := -1
	for i in p.bank.slots.size():
		if p.bank.slots[i] != null and p.bank.slots[i]["id"] == "copper_ore":
			bi = i
	check(p.withdraw(bi, 10) == 10 and p.bank.count("copper_ore") == 14, "withdraw 10")

	# --- smelting (furnace) and cooking (hearth)
	p.inventory.clear()
	p.inventory.add("copper_ore", 3)
	p.inventory.add("tin_ore", 2)
	p.interact(world, world.find_nearest_object(p.tile, ["furnace"], 20))
	ticks(40)
	check(p.inventory.count("bronze_bar") == 2 and p.inventory.count("copper_ore") == 1 and p.inventory.count("tin_ore") == 0,
		"furnace: bronze bar = 1 copper ore + 1 tin ore (2+3 ore -> 2 bars, spare copper left)")
	p.inventory.clear()
	p.inventory.add("raw_carp", 3)
	p.interact(world, world.find_nearest_object(p.tile, ["hearth", "oven"], 40))
	ticks(40)
	check(p.inventory.count("cooked_carp") + p.inventory.count("charred_fish") == 3, "hearth: 3 carp cooked or charred")
	check(int(p.skills.xp["cooking"]) > 0, "cooking xp gained")

	# --- dummy
	var mxp := int(p.skills.xp["attack"]) + int(p.skills.xp["strength"])
	p.interact(world, world.find_nearest_object(p.tile, ["training_dummy"], 20))
	ticks(60)
	check(int(p.skills.xp["attack"]) + int(p.skills.xp["strength"]) > mxp, "training dummy gives Attack/Strength xp (by style)")
	p.stop()

	# --- tool breaks
	p.inventory.clear()
	p.inventory.add("bronze_pick", 1, 1)
	var tile_before_mine := p.tile
	var pits: Dictionary = world.gen.mine_by_id("fenhollow_pits")   # 0.3.1: rocks only in named mines
	p.place_at(world.find_free_tile_near(pits["c"] + Vector2i(0, int(pits["radius"]) + 2), 6))
	world.set_focus(p.tile, true)
	var rock: WorldObject = world.find_nearest_object(p.tile, ["copper_rock"], 30)
	p.interact(world, rock)
	for i in 400:
		Tick.step()
		if p.inventory.count("copper_ore") > 0:
			break
	check(p.inventory.count("bronze_pick") == 0, "a pick with 1 durability breaks on use (item sink)")
	check(rock.is_depleted(Tick.tick_count) or p.inventory.count("copper_ore") > 0, "rock depletes after yielding")
	ticks(int(GameData.object_def("copper_rock")["respawn"]) + 2)
	check(not rock.is_depleted(Tick.tick_count), "rock respawns")
	p.place_at(tile_before_mine)
	world.set_focus(p.tile, true)

	# --- save / load round trip
	SaveSystem.path_override = "user://selftest_save.json"
	p.inventory.add("iron_bar", 2)
	var snap: Dictionary = main.build_save()
	check(SaveSystem.save_game(snap.duplicate(true)), "save written")
	var loaded := SaveSystem.load_game()
	check(int(loaded.get("version", 0)) == SaveSystem.SAVE_VERSION, "save has version")
	var p2 := Player.new()
	p2.from_save(loaded["player"])
	check(p2.tile == p.tile and p2.inventory.count("iron_bar") == 2 and p2.bank.count("copper_ore") == 14
		and int(p2.skills.xp["forestry"]) == int(p.skills.xp["forestry"]), "player round-trips through save")
	p2.free()
	SaveSystem.delete_save()
	SaveSystem.path_override = ""

	# --- Exchange order book
	Market.reset_prices()
	var M: TownMarket = Market.town("fenhollow")
	var it := "iron_bar"
	var ref := M.reference_price(it)
	var band := M.price_band(it)
	check(band.x < ref and band.y > ref, "daily price band brackets reference")
	check(M.npc_buy_price(it) < ref and M.shop_price("general", it) > ref, "NPC store floor < ref < ceiling")
	check(M.tax_on(1000) == 20 and M.tax_on(10) == 0, "exchange tax 2% above 50 marks")
	check(M.validate_order("t_a", it, 1, band.y + 1, false) != "", "order outside the band is rejected")
	var r1 := M.place_order("t_a", it, 5, ref + 2, false)
	check(r1["ok"] and M.best_ask(it) == ref + 2, "sell order rests on the book")
	var r2 := M.place_order("t_b", it, 3, ref + 4, true)
	var box_b := M.pending("t_b")
	var box_a := M.pending("t_a")
	var gross := 3 * (ref + 2)
	check(int(box_b["items"].get(it, 0)) == 3 and int(box_b["coins"]) == 6, "buy crosses at the resting price; buyer refunded the difference")
	check(int(box_a["coins"]) == gross - M.tax_on(gross), "seller credited gross minus 2% tax")
	check(M.econ["tax"] == M.tax_on(gross), "tax recorded as a sink")
	check(M.place_order("t_a", it, 1, ref + 2, true)["ok"] == false, "self-trade is rejected")
	check(not M.cancel_order(r1["id"]), "orders can't be cancelled in their first ticks")
	M.tick += Market.MIN_ORDER_LIFETIME
	check(M.cancel_order(r1["id"]) and int(M.pending("t_a")["items"].get(it, 0)) == 2, "cancel returns unfilled escrow to the box")
	var placed := 0
	for i in 9:
		if M.place_order("t_c", "copper_ore", 1, M.price_band("copper_ore").x, true)["ok"]:
			placed += 1
	check(placed == Market.MAX_OPEN_ORDERS_PER_TRADER, "max %d open orders per trader" % Market.MAX_OPEN_ORDERS_PER_TRADER)
	check(M.coins_in_market() > 0, "buy escrow counted in money supply")
	M.place_order("t_d", it, 1, band.x, false)
	M.place_order("t_e", it, 1, band.x, true)
	M.place_order("t_d", it, 1, band.y, false)
	M.place_order("t_e", it, 1, band.y, true)
	check(M.is_halted(it), "circuit breaker halts an item after a sharp move")
	# player ops
	p.inventory.clear()
	p.bank.clear()
	p.inventory.add("copper_ore", 6)
	p.inventory.add(GameData.currency, 500)
	var cref := M.reference_price("copper_ore")
	check(TraderOps.place(p, "fenhollow", "copper_ore", 6, M.price_band("copper_ore").y, false) == "" and p.inventory.count("copper_ore") == 0, "player sell order escrows items from the pack")
	check(TraderOps.place(p, "fenhollow", "copper_ore", 1, M.price_band("copper_ore").y, true) != "" and TraderOps.coins(p) == 500, "player can't trade with own order (no escrow taken)")
	check(cref > 0, "copper ore has a reference price")
	var store_cost := M.shop_cost("general", "bronze_pick", 1)
	check(TraderOps.shop_buy(p, "fenhollow", "general", "bronze_pick", 1) == "" and TraderOps.coins(p) == 500 - store_cost, "general store sells at the ceiling (coin sink)")
	p.inventory.add("ash_log", 4)
	var c0 := TraderOps.coins(p)
	check(TraderOps.shop_sell(p, "fenhollow", "general", "ash_log", 4) == "" and TraderOps.coins(p) == c0 + 4 * M.npc_buy_price("ash_log"), "general store buys at the floor (coin faucet)")
	# day rollover + monitor
	Market.reset_prices()
	M = Market.town("fenhollow")
	var ore := "copper_ore"
	var r0 := M.reference_price(ore)
	M.day_stats[ore] = {"vol": 100, "value": 100 * (r0 * 2), "hi": r0 * 2, "lo": r0 * 2}
	M.end_of_day(1)
	check(M.reference_price(ore) > r0 and M.reference_price(ore) <= int(ceil(r0 * 1.12)) + 1, "day close moves reference toward VWAP within the band")
	var f0 := Market.npc_buy_factor
	Market.monitor._step(Market, -1)
	check(Market.npc_buy_factor < f0 and Market.gather_mult > 1.0, "inflation response cuts faucets and raises supply")
	Market.reset_prices()

	# --- recipes / anvil
	p.inventory.clear()
	p.skills.xp["smithing"] = GameData.xp_for_level(5)
	p.inventory.add("bronze_bar", 2)
	p.inventory.add("plank", 1)
	var anvil: WorldObject = world.find_nearest_object(p.tile, ["anvil"], 30)
	check(anvil != null, "anvil placed in Fenhollow")
	if anvil:
		p.start_recipe(world, anvil, "forge_bronze_hatchet", 1)
		ticks(60)
		check(p.inventory.count("bronze_hatchet") == 1 and p.inventory.count("bronze_bar") == 0, "anvil forges a bronze hatchet from bars + plank")
	check(not world.gen.building_for_shop("fenhollow", "general").is_empty(), "general store building in Fenhollow")

	# --- continent, towns, roads, regional markets
	var gen: WorldGen = world.gen
	check(gen.towns.size() == 4 and gen.capital == "highfen", "three towns + the capital Highfen on the continent")
	var b := gen.bounds()
	var ocean_ok := true
	for q in [b.position, b.end - Vector2i.ONE, Vector2i(b.position.x, 0), Vector2i(b.end.x - 1, -10), Vector2i(180, b.position.y), Vector2i(180, b.end.y - 1)]:
		ocean_ok = ocean_ok and gen.tile_at(q.x, q.y) == WorldGen.TileType.WATER
	check(ocean_ok, "the continent is surrounded by ocean")
	check(gen.tile_at(5000, 5000) == WorldGen.TileType.WATER, "beyond the coast is always water (impassable)")
	var spec_seen := {}
	var spec_dup := false
	for tid in gen.towns.keys():
		var c := gen.town_center(tid)
		var need := ["bank_chest", "exchange_board"]
		var have_all := not gen.building_for_shop(tid, "general").is_empty()
		for oid in need:
			have_all = have_all and world.find_nearest_object(c, [oid], 30) != null
		check(have_all, "%s has a bank chest, general store and Exchange" % gen.town_name(tid))
		for line in gen.towns[tid].get("specialists", []):
			check(not gen.building_for_shop(tid, line).is_empty(), "%s has its %s shop" % [gen.town_name(tid), line])
			if line == "cook":
				continue  # cookhouse is in every city
			spec_dup = spec_dup or spec_seen.has(line)
			spec_seen[line] = tid
	check(spec_seen.size() == 8 and not spec_dup, "8 unique gear specialist shops, none shared between towns")
	var min_d := 1 << 30
	for x in gen.town_order:
		for y in gen.town_order:
			if x < y and x != gen.capital and y != gen.capital:
				min_d = mini(min_d, int(Vector2(gen.town_center(x) - gen.town_center(y)).length()))
	var cap_d := 1 << 30
	for x in gen.town_order:
		if x != gen.capital:
			cap_d = mini(cap_d, int(Vector2(gen.town_center(x) - gen.town_center(gen.capital)).length()))
	check(min_d >= 250 and cap_d >= 150, "towns are far apart (closest pair %d tiles; capital %d from the nearest)" % [min_d, cap_d])
	var roads_ok := true
	for k in gen.roads.keys():
		var road: Array = gen.roads[k]
		for i in range(1, road.size()):
			var d: Vector2i = (road[i] - road[i - 1]).abs()
			roads_ok = roads_ok and maxi(d.x, d.y) == 1 and not (gen.tile_at(road[i].x, road[i].y) in WorldGen.BLOCKING_TILES)
	check(roads_ok and gen.roads.size() == 12, "roads link every pair of towns (via Highfen), 8-connected and walkable")
	var fen := Market.town("fenhollow")
	var cin := Market.town("cinderholt")
	check(cin.reference_price("iron_ore") < fen.reference_price("iron_ore"), "regional prices: ore is cheaper in the hills")
	var helm_p0 := fen.shop_price("helmets", "iron_helm")
	check(fen.shelf("helmets", "iron_helm") > 0 and cin.shop_items("helmets").is_empty(), "helmets only sold in Fenhollow")
	fen.shop_sell_to("helmets", "iron_helm", fen.shelf("helmets", "iron_helm") - 1)
	check(fen.shop_price("helmets", "iron_helm") > helm_p0, "specialist prices rise as the shelf empties")
	p.set_town("cinderholt")
	var cin_vault := p.bank
	p.set_town("fenhollow")
	check(cin_vault != p.bank, "each town's bank chest has its own vault")

	# --- AI players (records + tiers)
	var adv_pop := 0
	for k in AdvBrain.cfg().get("population", {}).values():
		adv_pop += int(k)
	check(AIDirector.records.size() == AIDirector.POPULATION + adv_pop, "%d AI agents spawned (40 + %d adventurers)" % [AIDirector.records.size(), adv_pop])
	var personas := {}
	for a in AIDirector.records:
		personas[a.persona_id()] = true
	check(personas.size() == GameData.personas.size(), "every persona represented (%d)" % personas.size())
	var ai_xp0 := 0
	for a in AIDirector.records:
		for v in a.skills.xp.values():
			ai_xp0 += int(v)
	ticks(600)
	var ai_xp1 := 0
	for a in AIDirector.records:
		for v in a.skills.xp.values():
			ai_xp1 += int(v)
	var on_blocked := false
	for v in AIDirector.agents:
		on_blocked = on_blocked or world.is_blocked(v.tile)
	var tc: Array = AIDirector.tier_counts
	print("    tiers detailed/nearby/world: ", tc)
	check(tc[0] >= 1 and tc[0] <= AIDirector.MAX_DETAILED and tc[0] + tc[1] + tc[2] == AIDirector.records.size(), "three tiers populated, detailed capped at %d" % AIDirector.MAX_DETAILED)
	check(AIDirector.agents.size() == tc[0], "one AIPlayer node per detailed agent")
	check(ai_xp1 > ai_xp0, "AI players skill on their own (+%d xp in 600 ticks)" % (ai_xp1 - ai_xp0))
	check(not on_blocked, "AI players never stand on blocked tiles")
	var n_orders := 0
	var n_trades := 0
	for tid in Market.town_ids:
		n_orders += Market.town(tid).orders.size()
		n_trades += Market.town(tid).trade_log.size()
	check(n_orders > 0 or n_trades > 0, "AI players use the Exchanges (%d open orders, %d trades)" % [n_orders, n_trades])
	var ai_save := AIDirector.to_save()
	var a0: AIAgent = AIDirector.records[0]
	var coins0 := a0.coins
	a0.coins = -1
	AIDirector.from_save(ai_save)
	check(a0.coins == coins0 or a0.view != null, "AI records round-trip through save")
	# offline catch-up
	var day0 := Market.game_day()
	var trips0 := AIDirector.trips_total
	var rep := AIDirector.simulate_offline(4800, Tick.tick_count, p.actor_id)
	Tick.tick_count = int(rep["end_tick"])
	check(int(rep["days"]) >= 1 and Market.game_day() > day0, "offline catch-up advances game days (%d)" % int(rep["days"]))
	check(AIDirector.trips_total > trips0, "travelling traders set off between towns (%d trips)" % (AIDirector.trips_total - trips0))

	_combat_tests(world, p)
	_loot_tests(world, p)
	_single_way_tests(world, p)
	_floor_tests()
	_bubble_tests(main, world, p)
	_metal_tests(main, world, p)
	_combat_skill_tests(main, world, p)
	_sprint_tests(main, world, p)
	_facing_tests(main, world, p)
	_tap_tests(main, p)
	_building_tests(main, world, p)
	_player_shop_tests(main, world, p)
	_smithy_tests(main, world, p)
	WorldTests.run(main, world, p)   # 0.3.1 world track: mines, bands, Scorch, roads/bridges, guards, citizens
	_marker_tests(main, world, p)
	_daynight_tests(main, world, p)
	for r in preload("res://src/tests/selftest_pk.gd").run(main, world, p):   # 0.3.1 adventurers + PK
		check(r[0], r[1])

	for r in preload("res://src/tests/selftest_chatter.gd").run(main, world, p):   # 0.3.3 AI chatter + idle
		check(r[0], r[1])

	# --- perf smoke: chunk generation cost
	var t0 := Time.get_ticks_usec()
	for i in 10:
		g1.generate_chunk(Vector2i(100 + i, 100))
	var per_chunk_ms := (Time.get_ticks_usec() - t0) / 10000.0
	print("    chunk data gen: %.2f ms/chunk (desktop)" % per_chunk_ms)
	check(per_chunk_ms < 50.0, "chunk gen under 50 ms on desktop")

	print("SELFTEST %s %d/%d" % ["PASS" if failed == 0 else "FAIL", passed, passed + failed])
	return failed


static func _combat_tests(world: World, p: Player) -> void:
	# --- enemies, drops, combat
	check(DropTable.validate().is_empty(), "drop tables valid %s" % str(DropTable.validate()))
	var drng := RandomNumberGenerator.new()
	drng.seed = 77
	var bones_n := 0
	var meat_n := 0
	for i in 2000:
		for d in DropTable.roll("giant_rat", drng):
			if d[0] == "bones":
				bones_n += 1
			elif d[0] == "raw_rat_meat":
				meat_n += 1
	check(bones_n == 2000, "giant rats always drop bones")
	check(meat_n > 1200 and meat_n < 1400, "rat meat is a common drop (~65%%: %d/2000)" % meat_n)
	var rare_n := 0
	var gob_bones := 0
	var rare_ids := []
	for e in GameData.drop_tables["goblin"]["rare"]["entries"]:
		rare_ids.append(e["item"])
	for i in 6000:
		for d in DropTable.roll("goblin", drng):
			if d[0] == "bones":
				gob_bones += 1
			elif d[0] in rare_ids:
				rare_n += 1
	check(gob_bones == 6000 and rare_n > 90 and rare_n < 270, "goblins: bones always, rare weapon ~3%% (%d/6000)" % rare_n)
	check(DropTable.expected_value("goblin", func(id): return float(GameData.item_value(id)) if id != GameData.currency else 1.0) > DropTable.expected_value("giant_rat", func(id): return float(GameData.item_value(id))), "goblin loot is worth more than rat loot")
	var em: EnemyManager = world.enemies
	var expect_n := 0
	for c in GameData.camps:
		expect_n += int(c["count"])
	for tid in GameData.town_npcs.get("towns", {}).keys():   # 0.3.1 guards + citizens
		expect_n += (GameData.town_npcs["towns"][tid].get("guards", []) as Array).size() + int(GameData.town_npcs["towns"][tid].get("citizens", {}).get("count", 0))
	for vid in world.gen.village_order:   # 0.3.1 village folk + pasture cows
		expect_n += int(world.gen.villages[vid].get("citizens", {}).get("count", 0))
	for pz in world.gen.pastures:
		expect_n += int(pz["count"])
	var kinds := {}
	var spawn_ok := true
	var bx := Rect2i(em.enemies[0].home, Vector2i.ONE)
	for e in em.enemies:
		kinds[e.kind] = true
		spawn_ok = spawn_ok and not world.is_blocked(e.home) and (world.gen.town_at(e.home, 0) == "" or e.town_ok())
		bx = bx.expand(e.home)
	check(em.enemies.size() == expect_n and kinds.has("giant_rat") and kinds.has("goblin"), "%d enemies spawned in camps + towns (rats, goblins, ...)" % em.enemies.size())
	check(spawn_ok and bx.size.x > 250, "camps sit on walkable land outside towns, spread across the continent (%d tiles wide)" % bx.size.x)
	var g: Enemy = em.nearest(Vector2i(48, 40), ["goblin"], 200)
	var t := Tick.tick_count + 100000
	var only_p: Array = [p]
	p.action = {}
	p.path.clear()
	p.hp = p.max_hp()
	var aggro := int(g.def["aggro"])
	var leash := int(g.def["leash"])
	p.place_at(world.find_free_tile_near(g.home + Vector2i(aggro + 4, 0), 2))
	if g.cheb(p.tile, g.tile) <= aggro:
		p.place_at(g.home + Vector2i(aggro + 5, 0))
	for i in 3:
		g.tick(t + i, world, only_p)
	check(g.target == null, "enemy ignores actors outside its aggro radius")
	g.reset_far()
	p.place_at(world.find_free_tile_near(g.home + Vector2i(aggro - 1, 0), 1))
	g.tick(t + 5, world, only_p)
	check(g.target == p, "enemy aggroes when an actor comes within %d tiles" % aggro)
	var max_leash := 0
	for i in 40:
		p.place_at(world.find_free_tile_near(g.home + Vector2i(mini(leash + 6, aggro + 2 + i), 0), 2))
		p.hp = p.max_hp()
		g.tick(t + 10 + i, world, only_p)
		max_leash = maxi(max_leash, g.cheb(g.tile, g.home))
	check(g.target == null and max_leash <= leash + 1, "leash: the goblin gives up past %d tiles (max %d from home)" % [leash, max_leash])
	p.place_at(world.find_free_tile_near(g.home + Vector2i(40, 0), 3))
	for i in 30:
		g.tick(t + 60 + i, world, only_p)
	check(not g.returning and g.cheb(g.tile, g.home) <= int(g.def["wander"]) + 1 and g.hp == g.max_hp, "it walks home and heals")
	# a real fight with a giant rat
	var rat: Enemy = em.nearest(Vector2i(-34, 22), ["giant_rat"], 200)
	rat.reset_far()
	p.inventory.clear()
	p.inventory.add("bronze_sword")
	for cs in Combat.COMBAT_SKILLS:
		p.skills.set_level(cs, 10)
	p.place_at(world.find_free_tile_near(rat.tile + Vector2i(1, 0), 1))
	p.attack(rat)
	var tt := t + 200
	var hits_taken := 0
	while not rat.dead and tt < t + 800:
		var hp_before := p.hp
		p.on_tick(tt, world)
		em.on_tick(tt, only_p, p.tile)
		if p.hp < hp_before:
			hits_taken += 1
		tt += 1
	var rat_tile := rat.tile
	check(rat.dead, "the player kills a giant rat in tick combat (%d ticks)" % (tt - t - 200))
	check(not world.ground.at(rat_tile).is_empty() and world.ground.at(rat_tile)[0]["id"] == "bones", "its bones lie on the ground")
	p.handle_tap(world, rat_tile)
	for i in 20:
		p.on_tick(tt + i, world)
	check(p.inventory.count("bones") >= 1, "tap the drop to walk over and pick it up")
	var pxp := int(p.skills.xp.get("prayer", 0))
	var bi := p.inventory.find("bones")
	check(p.bury_slot(bi) == 5 and int(p.skills.xp.get("prayer", 0)) == pxp + 5, "burying bones gives Prayer XP")
	var wait_t := tt + 30
	while rat.dead and wait_t < tt + 400:
		em.on_tick(wait_t, [], rat.home)
		wait_t += 1
	check(not rat.dead and rat.cheb(rat.tile, rat.home) <= 1, "rats respawn at their spot after a delay (%d ticks)" % (wait_t - tt))
	var cr := Interactions.recipe_by_id("cook_rat_meat")
	check(int(cr.get("level", 0)) == 1 and cr["fail"]["item"] == "burnt_meat" and int(GameData.item("cooked_rat_meat").get("heals", 0)) > 0, "rat meat cooks at level 1 into low-heal food that can burn")
	p.hp = 2
	p.inventory.add("cooked_rat_meat")
	var healed := p.eat_slot(p.inventory.find("cooked_rat_meat"), tt)
	check(healed == 4 and p.hp == 6, "eating food heals (rat meat 4)")
	p.inventory.add("bronze_cap")
	var def0 := p.combat_def()
	check(p.equip_slot(p.inventory.find("bronze_cap")) == "" and p.combat_def() > def0, "equipping a helmet raises defence")
	p.inventory.add("iron_helm")
	p.skills.set_level("defence", 1)
	check(p.equip_slot(p.inventory.find("iron_helm")).contains("Defence level 10"), "armour above your Defence level can't be worn")
	# death
	p.inventory.add(GameData.currency, 100)
	var death_spot := world.find_free_tile_near(g.home + Vector2i(20, 0), 3)
	p.place_at(death_spot)
	var deaths0 := p.deaths
	p.take_hit(p.hp + 5, g, tt)
	var pile := world.ground.at(death_spot, "player")
	check(p.deaths == deaths0 + 1 and p.hp == p.max_hp() and world.gen.town_at(p.tile, 8) != "", "death: respawn with full HP in the nearest town")
	var pile_coins := 0
	for q in pile:
		if q["id"] == GameData.currency:
			pile_coins = int(q["qty"])
	check(pile.size() >= 2 and pile_coins == 90 and world.ground.at(death_spot, "someone_else").is_empty(), "death pile keeps your pack for you only; healer keeps 10% coin")
	check(p.equipment.has("head"), "worn equipment is kept on death")
	world.ground.add(Vector2i(5, 5), "bones", 1, tt, 10)
	world.ground.on_tick((int((tt + 20) / 10.0) + 1) * 10)
	check(world.ground.at(Vector2i(5, 5)).is_empty(), "ground items despawn after their timer")
	# abstract AI fighters can flee or die
	var fighter: AIAgent = null
	for a in AIDirector.records:
		if a.persona_id() == "adventurer":
			fighter = a
			break
	for f in AIBrain.FOODS:
		fighter.stash.erase(f)
	fighter.hp = 2.0
	fighter.activity = {"type": "fight", "until": tt + 2000}
	var st0 := int(fighter.stats.get("deaths", 0)) + int(fighter.stats.get("fled", 0))
	AIBrain.simulate(fighter, 600, tt)
	check(int(fighter.stats.get("deaths", 0)) + int(fighter.stats.get("fled", 0)) > st0 and fighter.activity["type"] == "rest", "AI fighters without food flee or die")
	check(DropTable.expected_value("giant_rat", func(id): return AIBrain.value(fighter, id)) > 0.0, "AI values rat loot for its fight decision")
	fighter.stash["bones"] = 3
	fighter.prayer = {"id": "", "points": 0.0}
	fighter.hp = float(AIBrain.agent_max_hp(fighter))
	fighter.stash["cooked_carp"] = 20
	fighter.activity = {"type": "fight", "until": 900000}
	var picked := Prayer.ai_pick(fighter.prayer, fighter.skills.level("prayer"), 1.0, func(): return AIBrain.bury_one(fighter))
	check(picked != "" and fighter.stash_count("bones") < 3, "AI fighters bury bones to refill, then pick a buff before engaging (%s)" % picked)
	# --- prayer buffs (points pool)
	var tpl := int(GameData.prayers.get("ticks_per_level", 0))
	var dur_ok := tpl == 50
	for lvl in [1, 5, 10, 37, 60]:
		dur_ok = dur_ok and Prayer.duration_ticks(lvl) == lvl * tpl
	check(dur_ok and is_equal_approx(Prayer.duration_ticks(1) * 0.6, 30.0) and is_equal_approx(Prayer.duration_ticks(10) * 0.6, 300.0), "prayer duration = level x %d ticks (L1 = 30 s, L10 = 5 min)" % tpl)
	var bl: Array = Prayer.buffs()
	var ids := {}
	var asc := true
	for i in bl.size():
		ids[bl[i]["id"]] = true
		if i > 0:
			asc = asc and int(bl[i]["level"]) > int(bl[i - 1]["level"])
	check(bl.size() >= 8 and bl.size() <= 10 and ids.size() == bl.size() and asc, "%d prayer buffs with rising level requirements" % bl.size())
	var ps := {}
	check(Prayer.max_points(1) == float(tpl) and Prayer.max_points(7) == 7.0 * tpl, "prayer points pool = level x %d" % tpl)
	check(Prayer.activate(ps, "ember_grip", 1) != "", "stronger buffs are locked behind Prayer level")
	check(Prayer.activate(ps, "stillwater_ward", 1) == "" and Prayer.mult(ps, "def") == 0.95, "a buff applies while active (ward: foes' accuracy x0.95)")
	check(Prayer.activate(ps, "keen_sight", 10) != "", "only one buff at a time")
	var lasted := 0
	while Prayer.is_active(ps) and lasted < 1000:
		Prayer.tick(ps, 1)
		lasted += 1
	check(lasted == Prayer.duration_ticks(1) and lasted == 1 * tpl, "a full pool runs a 1/tick buff for level x %d ticks (lasted %d)" % [tpl, lasted])
	var ps5 := {}
	Prayer.activate(ps5, "stillwater_ward", 5)
	var lasted5 := 0
	while Prayer.is_active(ps5) and lasted5 < 1000:
		Prayer.tick(ps5, 5)
		lasted5 += 1
	check(lasted5 == 5 * tpl, "level 5: %d ticks = %.0f s" % [lasted5, lasted5 * 0.6])
	check(Prayer.points(ps, 1) == 0.0 and Prayer.activate(ps, "stillwater_ward", 1) != "", "at 0 points the buff ends and none can start")
	check(Prayer.duration_ticks(30, "stormbrand") < Prayer.duration_ticks(30, "stillwater_ward"), "stronger buffs drain faster (data drain rate)")
	Prayer.restore(ps, 1, float(GameData.item("bones").get("prayer_restore", 0)))
	check(is_equal_approx(Prayer.points(ps, 1), 0.2 * tpl), "burying bones restores 20% of max points")
	for i in 30:
		Prayer.tick(ps, 1)
	check(Prayer.points(ps, 1) > 0.2 * tpl, "points regenerate slowly with no buff active")
	p.inventory.add("bones")
	p.prayer = {"id": "", "points": 0.0}
	p.bury_slot(p.inventory.find("bones"))
	check(Prayer.points(p.prayer, p.skills.level("prayer")) > 0.0, "the player's Bury restores points too")
	var gp := {}
	Prayer.activate(gp, "reedsong", 10)
	check(Prayer.mult(gp, "gather") > 1.0 and Prayer.mult(gp, "dmg") == 1.0, "effects only apply to their own kind")


## 0.2.1: leftovers turn public after the private window; AI loots them.
static func _loot_tests(world: World, p: Player) -> void:
	var g: GroundItems = world.ground
	g.piles.clear()
	var rec: AIAgent = null
	for a in AIDirector.records:
		if a.persona_id() == "woodsman":
			rec = a
			break
	var ai := AIPlayer.new()
	ai.bind(rec, world)
	ai.think_cooldown = 100000
	var c: Vector2i = world.find_free_tile_near(world.gen.town_spawn("fenhollow") + Vector2i(6, 7), 4)
	var spot: Vector2i = world.find_free_tile_near(c + Vector2i(4, 0), 2)
	ai.place_at(c)
	var T := Tick.tick_count + 300000
	g.on_tick(T)
	var priv := GroundItems.private_ticks()
	g.add(spot, "bronze_bar", 2, T, -1, p.actor_id)
	var pile: Dictionary = g.piles[0]
	check(priv == 100 and int(pile["public_at"]) == T + priv and int(pile["until"]) == T + GroundItems.drop_ttl() and GroundItems.drop_ttl() == 500,
		"kill drops: private for %d ticks, despawn %d ticks after the drop" % [priv, GroundItems.drop_ttl()])
	check(g.at(spot, p.actor_id).size() == 1 and g.at(spot, "ai_x").is_empty(), "a private drop is visible only to its owner")
	var bars0 := rec.stash_count("bronze_bar")
	var tt := T
	while tt < T + priv - 1:
		g.on_tick(tt)
		ai.on_tick(tt, world)
		tt += 1
	check(g.piles.size() == 1 and rec.stash_count("bronze_bar") == bars0 and ai.action.get("kind", "") != "loot", "no AI pickup during the private window")
	while tt < T + priv + 60 and not g.piles.is_empty():
		g.on_tick(tt)
		ai.on_tick(tt, world)
		tt += 1
	check(g.piles.is_empty() and rec.stash_count("bronze_bar") == bars0 + 2 and ai.tile == spot, "a nearby AI walks over and loots public leftovers (%d ticks after they went public)" % (tt - T - priv))
	g.add(spot + Vector2i(0, 1), "burnt_meat", 1, tt, -1, "")
	ai.think_cooldown = 100000
	for i in 30:
		g.on_tick(tt + i)
		ai.on_tick(tt + i, world)
	check(g.piles.size() == 1, "AI skips junk worth less than %d" % int(GroundItems.rule("ai_loot_min_value", 3)))
	g.piles.clear()
	tt += 40
	g.add(spot, "bronze_bar", 5, tt, GroundItems.death_ttl(), p.actor_id, -1)
	g.add(spot, GameData.currency, 50, tt, GroundItems.death_ttl(), p.actor_id, -1)
	var coins0 := rec.coins
	for i in 700:
		g.on_tick(tt + i)
		ai.on_tick(tt + i, world)
	check(g.piles.size() == 2 and rec.coins == coins0 and rec.stash_count("bronze_bar") == bars0 + 2, "death piles are never taken by AI (700 ticks)")
	check(g.at(spot, p.actor_id).size() == 2, "...and stay visible to their owner")
	g.piles.clear()
	tt += 800
	g.on_tick(tt)
	g.add(spot, GameData.currency, 20, tt - 200, -1, p.actor_id)
	ai.place_at(c)
	for i in 30:
		g.on_tick(tt + i)
		ai.on_tick(tt + i, world)
	check(g.piles.is_empty() and rec.coins == coins0 + 20, "AI loots public coins into its purse")
	g.add(spot, "bronze_bar", 1, tt, -1, "")
	g.on_tick((int((tt + GroundItems.drop_ttl()) / 10.0) + 1) * 10)
	check(g.piles.is_empty(), "unclaimed public drops still despawn at the drop TTL")
	# abstract (tier-1) agents near a public pile may claim it
	tt += 2000
	g.on_tick(tt)
	g.add(spot, "bronze_bar", 3, tt - 150, -1, p.actor_id)
	var old_chance = GameData.ground_rules.get("abstract_claim_chance")
	var tiers := {}
	for a in AIDirector.records:
		tiers[a] = a.tier
		a.tier = 2
	rec.tier = 1
	var pos0 := rec.pos
	rec.pos = spot + Vector2i(2, 0)
	GameData.ground_rules["abstract_claim_chance"] = 1.0
	var ab0 := int(g.looted.get("abstract", 0))
	AIDirector._abstract_loot(world, tt)
	check(g.piles.is_empty() and int(g.looted.get("abstract", 0)) == ab0 + 3, "abstract nearby AI can claim public piles")
	GameData.ground_rules["abstract_claim_chance"] = old_chance
	for a in tiers.keys():
		a.tier = tiers[a]
	rec.pos = pos0
	ai.unbind()
	ai.free()


## 0.2.1: single-way combat by default; multi zones from data.
static func _single_way_tests(world: World, p: Player) -> void:
	var em: EnemyManager = world.enemies
	var g1: Enemy = em.nearest(Vector2i(48, 40), ["goblin"], 300)
	var g2: Enemy = null
	for e in em.enemies:
		if e != g1 and e.kind == "goblin" and e.cheb(e.home, g1.home) <= 8:
			g2 = e
			break
	check(g2 != null, "a goblin camp has several goblins")
	var T := Tick.tick_count + 400000
	var setup := func():
		for e in [g1, g2]:
			e.reset_far()
			e.last_combat_tick = -1000
			e.next_wander = T + 100000
		g2.tile = world.find_free_tile_near(g1.tile + Vector2i(2, 0), 1)
		p.action = {}
		p.path.clear()
		p.combat_foe = null
		p.last_combat_tick = -1000
		p.hp = p.max_hp()
		p.place_at(world.find_free_tile_near(g1.tile + Vector2i(1, 2), 1))
	setup.call()
	var both: bool = g1.cheb(p.tile, g1.tile) <= 4 and g2.cheb(p.tile, g2.tile) <= 4
	g1.tick(T, world, [p])
	g2.tick(T, world, [p])
	check(both and g1.target == p and g2.target == null and p.combat_foe == g1, "single-way: a second enemy can't aggro an engaged actor")
	check(CombatRules.can_attack(p, g2, T + 1) == "You're already under attack.", "...and the engaged actor can't open on a second enemy")
	# combat flag expiry
	var ct := CombatRules.combat_ticks()
	check(ct == 8 and CombatRules.actor_foe(p, T + ct - 1) == g1 and p.in_combat(T + ct - 1) and CombatRules.actor_foe(p, T + ct) == null and not p.in_combat(T + ct),
		"'in combat' lasts %d ticks after the last swing / aggro" % ct)
	g1.target = null
	g1.returning = false
	g2.tick(T + ct, world, [p])
	check(g2.target == p, "once the flag expires another enemy may engage")
	# a second actor can't attack an enemy someone else is fighting
	setup.call()
	var rec: AIAgent = null
	for a in AIDirector.records:
		if a.persona_id() == "adventurer":
			rec = a
			break
	var ai := AIPlayer.new()
	ai.bind(rec, world)
	ai.place_at(world.find_free_tile_near(g1.tile + Vector2i(-1, -1), 1))
	g1.target = ai
	g1.last_combat_tick = T + 50
	ai.combat_foe = g1
	ai.last_combat_tick = T + 50
	check(CombatRules.can_attack(p, g1, T + 51) == "Someone else is fighting that.", "a second actor can't attack an engaged enemy")
	Tick.tick_count = T + 51
	p.handle_tap(world, g1.tile)
	check(p.action.get("kind", "") != "fight", "player tap on it is refused ('Someone else is fighting that.')")
	p.attack(g1)
	p._fight_tick(T + 52, world)
	check(p.action.is_empty(), "a fight already under way stops if someone else holds the enemy")
	var other: Enemy = em.nearest(ai.tile, ["goblin"], 40, func(e): return CombatRules.can_attack(p, e, T + 51) == "")
	check(other != null and other != g1, "AI target picking skips enemies engaged by someone else")
	# a multi-combat zone lifts both rules
	var zone := {"id": "test_pit", "name": "Test pit", "rect": [g1.home.x - 12, g1.home.y - 12, 25, 25]}
	var shipped_zones: Array = (GameData.combat_zones["zones"] as Array).duplicate(true)
	GameData.combat_zones["zones"] = [zone]
	check(CombatRules.is_multi(g1.tile) and CombatRules.can_attack(p, g1, T + 51) == "", "multi zone: anyone may attack an engaged enemy")
	setup.call()
	g1.tick(T + 200, world, [p])
	g2.tick(T + 200, world, [p])
	check(g1.target == p and g2.target == p, "multi zone: several enemies may attack one actor")
	check(CombatRules.abstract_damage_mult("goblin") > 1.0, "abstract fights take extra damage at camps inside a multi zone")
	GameData.combat_zones["zones"] = shipped_zones
	check(CombatRules.zones().size() == 1 and str(CombatRules.zones()[0]["id"]) == "scorch" and not CombatRules.is_multi(g1.home)
		and CombatRules.abstract_damage_mult("goblin") == 1.0, "0.3.1 zones: only the Scorch is multi-combat; goblin camps sit outside it (abstract fights one-on-one)")
	for e in [g1, g2]:
		e.reset_far()
	p.combat_foe = null
	p.action = {}
	ai.unbind()
	ai.free()


## 0.2.1: per-item, per-town floor support for slumping goods.
static func _floor_tests() -> void:
	var saved := {}
	for tid in Market.town_ids:
		saved[tid] = [Market.town(tid).floor_boost.duplicate(), Market.town(tid).reference.duplicate()]
	var tm := Market.town("fenhollow")
	var id := "coal"
	var base := GameData.item_value(id)
	tm.floor_boost.clear()
	var p0 := tm.npc_buy_price(id)
	tm.reference[id] = int(base * 0.5)
	Market.monitor._item_floors(Market)
	check(float(tm.floor_boost.get(id, 0.0)) > 0.0 and tm.npc_buy_price(id) > p0, "a slumping good gets its store floor raised in that town (%d -> %d)" % [p0, tm.npc_buy_price(id)])
	for i in 20:
		Market.monitor._item_floors(Market)
	check(is_equal_approx(float(tm.floor_boost[id]), EconomyMonitor.ITEM_BOOST_MAX), "floor support is capped (+%.2f x base)" % EconomyMonitor.ITEM_BOOST_MAX)
	tm.reference[id] = int(base * 1.1)
	for i in 10:
		Market.monitor._item_floors(Market)
	check(not tm.floor_boost.has(id) and tm.npc_buy_price(id) == p0, "...and steps back down once the price recovers")
	for tid in saved.keys():
		Market.town(tid).floor_boost = saved[tid][0]
		Market.town(tid).reference = saved[tid][1]


## 0.2.2: one damage bubble per target; a new hit replaces the old one.
static func _bubble_tests(main, world: World, p: Player) -> void:
	var hb: HitBubbles = main.hit_bubbles if main.get("hit_bubbles") != null else null
	check(hb != null, "the game has a hit-bubble layer")
	if hb == null:
		return
	var e: Enemy = world.enemies.nearest(Vector2i(48, 40), ["goblin"], 300)
	for k in hb.bubbles.keys().duplicate():
		hb.clear_target(instance_from_id(k))
	var n0 := hb.get_child_count()
	p.position = Vector2(100, 200)
	Events.hitsplat.emit(p, p.tile, 3)
	var first: Label = hb.label_on(p)
	Events.hitsplat.emit(p, p.tile, 0)
	check(hb.count_on(p) == 1 and hb.value_on(p) == 0 and hb.label_on(p).text == "0" and not is_instance_valid(first) and hb.get_child_count() == n0 + 1,
		"two hits in a row on one actor leave exactly one bubble, showing the latest value (a miss replaces a 3)")
	var pos_a := hb.label_on(p).position
	Events.hitsplat.emit(p, p.tile, 2)
	check(hb.get_child_count() == n0 + 1 and hb.label_on(p).position == pos_a and hb.value_on(p) == 2, "the new bubble takes the same spot (no stacking or offset piles)")
	e.position = Vector2(300, 200)
	Events.hitsplat.emit(e, e.tile, 4)
	check(hb.count_on(p) == 1 and hb.count_on(e) == 1 and hb.value_on(p) == 2 and hb.value_on(e) == 4 and hb.get_child_count() == n0 + 2,
		"hits on different actors each keep their own bubble")
	p.position += Vector2(16, 0)
	hb._process(0.01)
	check(hb.label_on(p).position == pos_a + Vector2(16, 0), "a bubble follows its actor when it moves")
	hb._process(hb.lifetime())
	check(hb.count_on(p) == 0 and hb.count_on(e) == 0 and hb.get_child_count() == n0, "bubbles vanish after their lifetime (%.1f s, data/fx.json)" % hb.lifetime())


## 0.2.3: copper tier -> bronze (copper + tin), iron 40 % flat fail, steel = iron ore + coal.
static func _metal_tests(main, world: World, p: Player) -> void:
	# -- data: no copper_ gear/bar ids left anywhere except the ore (and its rock object)
	var rx := RegEx.new()
	rx.compile("copper_(?!ore\\b|rock\\b)")
	var blob := JSON.stringify([GameData.items.keys(), GameData.recipes, GameData.drop_tables, GameData.personas, Market.shop_cfg,
		GameData.objects, GameData.sprites.get("items", {}), GameData.towns])
	var hits := rx.search_all(blob)
	check(hits.is_empty(), "no 'copper_' gear/bar ids remain in data except copper_ore (%d found)" % hits.size())
	check(GameData.items.has("bronze_bar") and GameData.items.has("tin_ore") and GameData.items.has("steel_bar") and GameData.objects.has("tin_rock"),
		"bronze bar, tin ore, steel bar and tin rocks exist")
	var rb := Interactions.recipe_by_id("smelt_bronze")
	var ri := Interactions.recipe_by_id("smelt_iron")
	var rs := Interactions.recipe_by_id("smelt_steel")
	check(_ins(rb) == {"copper_ore": 1, "tin_ore": 1} and not rb.has("fail"), "bronze bar recipe = 1 copper ore + 1 tin ore, no fail")
	check(_ins(ri) == {"iron_ore": 1} and is_equal_approx(float(ri["fail"]["chance"]), 0.4) and not ri["fail"].has("item"),
		"iron bar recipe = 1 iron ore with a flat 40% fail chance (data value)")
	check(is_equal_approx(Interactions.fail_chance(ri, 12), 0.4) and is_equal_approx(Interactions.fail_chance(ri, 60), 0.4), "iron fail rate is flat (does not shrink with level)")
	check(_ins(rs) == {"iron_ore": 1, "coal": 1} and not rs.has("fail"), "steel bar recipe = 1 iron ore + 1 coal, no fail")
	var tin: WorldObject = world.find_gather_node(p.tile, "tin_rock", "fenhollow")   # 0.3.1: in the town's pits
	check(tin != null and int(GameData.objects["tin_rock"].get("level", 1)) == 1, "tin rocks spawn in the world (Mining 1)")
	# -- melee requirement ordering: bronze 1 < iron 10 < steel 20 < dusk 30, in every metal shop line
	var ok := true
	for line in ["helmets", "body", "legs", "swords", "axes", "maces", "shields"]:
		var groups := {}   # weapon class / armour slot -> ids in shop order (swords & daggers share a line)
		for id in Market.shop_cfg["lines"][line]:
			var gd0: Dictionary = GameData.items[id]["gear"]
			var key := str(gd0.get("class", gd0["slot"]))
			if not groups.has(key):
				groups[key] = []
			groups[key].append(id)
		for key in groups.keys():
			var arr: Array = groups[key]
			var prev := -1
			ok = ok and arr.size() == 4 and str(arr[2]).begins_with("steel_") and str(arr[3]).begins_with("dusk_")
			for i in arr.size():
				var it: Dictionary = GameData.items[arr[i]]
				var gear: Dictionary = it.get("gear", {})
				ok = ok and int(gear.get("tier", 0)) == i + 1 and int(gear.get("level", 0)) == [1, 10, 20, 30][i] and int(it["value"]) > prev
				prev = int(it["value"])
	check(ok, "every metal shop line is bronze/iron/steel/dusk per class: tiers 1-4, levels 1/10/20/30, rising value")
	# -- prices consistent with inputs (iron loses 40 % of ore)
	var v := func(id): return float(GameData.items[id]["value"])
	check(v.call("bronze_bar") >= v.call("copper_ore") + v.call("tin_ore"), "bronze bar is worth at least its two ores")
	check(v.call("iron_bar") * 0.6 >= v.call("iron_ore"), "iron bar value covers the expected ore cost (ore / 0.6)")
	check(v.call("steel_bar") >= v.call("iron_ore") + v.call("coal") and v.call("steel_bar") > v.call("iron_bar"), "steel bar is worth more than its inputs and an iron bar")

	# -- player smelting at a real furnace
	var fur: WorldObject = world.find_nearest_object(p.tile, ["furnace"], 200)
	p.stop()
	p.place_at(world.find_free_tile_near(fur.pos + Vector2i(0, 1), 2))
	p.inventory.clear()
	p.skills.set_level("smithing", 20)
	p.inventory.add("iron_ore", 2)
	p.inventory.add("coal", 2)
	p.start_recipe(world, fur, "smelt_steel", -1)
	ticks(40)
	check(p.inventory.count("steel_bar") == 2 and p.inventory.count("iron_ore") == 0 and p.inventory.count("coal") == 0, "furnace: steel consumes 1 iron ore + 1 coal per bar")
	var msgs: Array = []
	var cb := func(t, _k): msgs.append(t)
	Events.message.connect(cb)
	var trials := 0
	var bars := 0
	var ore_left := 0
	var xp0 := int(p.skills.xp["smithing"])
	p.rng.seed = 2303   # deterministic trial run
	for round in 8:   # ore doesn't stack: 8 packs of 25 = 200 trials
		p.inventory.clear()
		p.inventory.add("iron_ore", 25)
		trials += 25
		p.start_recipe(world, fur, "smelt_iron", -1)
		ticks(int(ri.get("ticks", 4)) * 25 + 30)
		bars += p.inventory.count("iron_bar")
		ore_left += p.inventory.count("iron_ore")
	Events.message.disconnect(cb)
	var rate := 1.0 - float(bars) / trials
	check(ore_left == 0, "failed iron smelts still use up the ore")
	check(rate > 0.30 and rate < 0.50, "iron smelting fails ~40%% of the time (%d/%d failed = %.0f%%)" % [trials - bars, trials, rate * 100.0])
	check(int(p.skills.xp["smithing"]) - xp0 == bars * int(ri["xp"]) + (trials - bars) * int(ri["fail"].get("xp", 0)), "a failed iron smelt gives no XP (fail.xp = 0)")
	check(msgs.has(str(ri["fail"]["message"])), "failure shows: \"%s\"" % ri["fail"]["message"])
	# AI side: flat chance over many simulated trials
	var ag := AIAgent.new()
	ag.rng.seed = 2303
	ag.skills.set_level("smithing", 30)
	check(is_equal_approx(AIBrain.fail_p(ag, ri), 0.4), "AI uses the same 40% iron fail rate")
	ag.stash_add("iron_ore", 2000)
	ag.activity = {"type": "craft", "recipe": "smelt_iron", "until": 1 << 40}
	var guard := 0
	while ag.stash_count("iron_ore") > 0 and guard < 5000:
		AIBrain.simulate(ag, 600, 0)
		guard += 1
	var arate := 1.0 - ag.stash_count("iron_bar") / 2000.0
	check(ag.stash_count("iron_ore") == 0 and absf(arate - 0.4) < 0.05, "AI abstract smelting also fails ~40%% (%.1f%% over 2000 ore)" % (arate * 100.0))

	# -- save migration v1 -> v2: copper_* items become bronze_* everywhere
	p.inventory.clear()
	p.inventory.add("bronze_sword")
	p.inventory.add("copper_ore", 3)
	p.bank.add("bronze_bar", 7)
	p.equipment["head"] = "bronze_cap"
	var spot := p.tile + Vector2i(1, 0)
	world.ground.add(spot, "bronze_mace", 1, Tick.tick_count, -1, p.actor_id)
	world.ground.add(spot, "bronze_greaves", 1, Tick.tick_count, GroundItems.death_ttl(), p.actor_id, -1)
	var snap: Dictionary = main.build_save()
	snap["version"] = 1
	var old_txt := JSON.stringify(snap).replace("bronze_", "copper_").replace("smelt_bronze", "smelt_copper")
	check(old_txt.contains("copper_sword") and old_txt.contains("copper_greaves"), "built a v1-style save with copper_* ids")
	SaveSystem.path_override = "user://selftest_v1.json"
	var f := FileAccess.open(SaveSystem.path_override, FileAccess.WRITE)
	f.store_string(old_txt)
	f.close()
	var mig := SaveSystem.load_game()
	var mtxt := JSON.stringify(mig)
	check(int(mig.get("version", 0)) == SaveSystem.SAVE_VERSION and rx.search(mtxt) == null and not mtxt.contains("smelt_copper"), "migration leaves no copper_ item/recipe ids in a v1 save")
	var p3 := Player.new()
	p3.from_save(mig["player"])
	check(p3.inventory.count("bronze_sword") == 1 and p3.inventory.count("copper_ore") == 3 and p3.bank.count("bronze_bar") == 7 and p3.equipment.get("head", "") == "bronze_cap",
		"migrated pack, bank and equipment hold bronze_* (copper ore untouched)")
	p3.free()
	var gi := GroundItems.new()
	gi.from_save(mig["world"]["ground"], Tick.tick_count)
	var gtxt := JSON.stringify(gi.piles)
	gi.free()
	check(gtxt.contains("bronze_mace") and gtxt.contains("bronze_greaves") and not gtxt.contains("copper_"), "migrated ground items and death piles hold bronze_*")
	SaveSystem.delete_save()
	SaveSystem.path_override = ""
	world.ground.piles = world.ground.piles.filter(func(pl): return pl.get("pos", Vector2i(-999, -999)) != spot)
	p.inventory.clear()
	p.equipment.erase("head")


static func _ins(r: Dictionary) -> Dictionary:
	var out := {}
	for k in r.get("in", {}).keys():
		out[k] = int(r["in"][k])
	return out


## 0.2.4: Attack / Strength / Defence, weapon classes, styles, Defence XP, set bonus.
static func _combat_skill_tests(main, world: World, p: Player) -> void:
	p.stop()
	p.inventory.clear()
	p.equipment.clear()
	p.combat_style = ""
	var sk := p.skills
	# -- equip requirements per class
	check(Combat.req_skill("iron_dagger") == "attack" and Combat.req_skill("iron_sword") == "attack" and Combat.req_skill("iron_battleaxe") == "attack"
		and Combat.req_skill("iron_mace") == "strength" and Combat.req_skill("iron_warhammer") == "strength"
		and Combat.req_skill("iron_helm") == "defence" and Combat.req_skill("iron_hauberk") == "defence" and Combat.req_skill("iron_legguards") == "defence"
		and Combat.req_skill("iron_kite_shield") == "defence" and Combat.req_skill("alder_longbow") == "archery",
		"stab/slash (dagger, sword, battle axe) need Attack, crush (mace, warhammer) need Strength, armour needs Defence (bows: Archery)")
	sk.set_level("attack", 10)
	sk.set_level("strength", 1)
	sk.set_level("defence", 1)
	var ok_atk := true
	for id in ["iron_dagger", "iron_sword", "iron_battleaxe"]:
		p.inventory.add(id)
		ok_atk = ok_atk and p.equip_slot(p.inventory.find(id)) == ""
	check(ok_atk, "Attack 10 wields iron daggers, swords and battle axes")
	p.inventory.add("iron_mace")
	p.inventory.add("iron_warhammer")
	p.inventory.add("iron_helm")
	var why_m := p.equip_slot(p.inventory.find("iron_mace"))
	var why_w := p.equip_slot(p.inventory.find("iron_warhammer"))
	var why_h := p.equip_slot(p.inventory.find("iron_helm"))
	check(why_m.contains("Strength level 10") and why_w.contains("Strength level 10") and why_h.contains("Defence level 10"),
		"...but not an iron mace / warhammer (Strength 10) or an iron helm (Defence 10)")
	sk.set_level("strength", 10)
	sk.set_level("defence", 10)
	check(p.equip_slot(p.inventory.find("iron_mace")) == "" and p.equip_slot(p.inventory.find("iron_helm")) == "", "with Strength 10 and Defence 10 they can be worn")
	sk.set_level("attack", 1)
	check(Combat.equip_error(sk, "iron_sword") != "" and Combat.equip_error(sk, "steel_warhammer").contains("Strength level 20")
		and Combat.equip_error(sk, "dusk_dagger").contains("Attack level 30"), "steel needs 20, dusk 30 (same tier levels for every class)")
	# a weapon you can't wield in the pack is not used either
	p.equipment.erase("weapon")
	p.inventory.clear()
	p.inventory.add("iron_sword")
	check(p.weapon_id() == "", "an unusable weapon in the pack isn't swung (Attack 1 vs iron sword)")

	# -- classes: speed, armour breaker
	check(Combat.weapon_ticks("bronze_dagger") == 3 and Combat.weapon_ticks("bronze_sword") == 4 and Combat.weapon_ticks("bronze_warhammer") == 5,
		"daggers swing every 3 ticks, swords every 4, warhammers every 5")
	var gob: Dictionary = GameData.enemies["goblin"]
	check(Combat.actor_accuracy(10, 5, int(gob["defence"]), Combat.armour_break("iron_mace")) > Combat.actor_accuracy(10, 5, int(gob["defence"]), Combat.armour_break("iron_sword")),
		"crush weapons break armour: same Attack/bonus hits a goblin more often with a mace (ignores %d%% of its defence)" % int(Combat.armour_break("iron_mace") * 100))
	var dg: Dictionary = GameData.item("steel_dagger")["gear"]
	var sw: Dictionary = GameData.item("steel_sword")["gear"]
	var wh: Dictionary = GameData.item("steel_warhammer")["gear"]
	var mc: Dictionary = GameData.item("steel_mace")["gear"]
	check(int(dg["atk"]) > int(sw["atk"]) and int(GameData.item("steel_dagger")["tool"]["power"]) < int(GameData.item("steel_sword")["tool"]["power"])
		and int(wh["str"]) > int(mc["str"]) and int(wh["str"]) >= int(GameData.item("steel_battleaxe")["gear"]["str"]) and int(wh["atk"]) < int(mc["atk"]),
		"daggers: more accuracy, lower max hit; warhammers: highest strength bonus, lower accuracy")
	var forge_ok := true
	for m in ["bronze", "iron", "steel"]:
		for k in ["dagger", "warhammer"]:
			var r := Interactions.recipe_by_id("forge_%s_%s" % [m, k])
			forge_ok = forge_ok and r.get("station", "") == "anvil" and r["out"].has("%s_%s" % [m, k]) and _ins(r).has(m + "_bar")
	check(forge_ok and Interactions.recipe_by_id("forge_dusk_dagger").is_empty() and Interactions.recipe_by_id("forge_dusk_warhammer").is_empty(),
		"bronze/iron/steel daggers and warhammers are forged at the anvil; dusk is shop-only")
	check("iron_dagger" in Market.shop_cfg["lines"]["swords"] and "steel_warhammer" in Market.shop_cfg["lines"]["maces"],
		"daggers sell at the swords shop, warhammers at the maces shop")
	var anvil: WorldObject = world.find_nearest_object(p.tile, ["anvil"], 200)
	p.place_at(world.find_free_tile_near(anvil.pos + Vector2i(0, 1), 2))
	p.inventory.clear()
	p.skills.set_level("smithing", 10)
	p.inventory.add("bronze_bar", 6)
	p.start_recipe(world, anvil, "forge_bronze_warhammer", 1)
	ticks(30)
	p.start_recipe(world, anvil, "forge_bronze_dagger", 1)
	ticks(30)
	check(p.inventory.count("bronze_warhammer") == 1 and p.inventory.count("bronze_dagger") == 1 and p.inventory.count("bronze_bar") == 0,
		"anvil: warhammer = 4 bars (metal haft), dagger = 2 bars")

	# -- style -> XP routing
	for cs in Combat.COMBAT_SKILLS:
		sk.set_level(cs, 5)
	var x0 := [int(sk.xp["attack"]), int(sk.xp["strength"]), int(sk.xp["vitality"])]
	Combat.award_hit_xp(sk, "accurate", 3)
	check(int(sk.xp["attack"]) - x0[0] == 12 and int(sk.xp["strength"]) == x0[1] and int(sk.xp["vitality"]) - x0[2] == 4, "Accurate: 3 damage -> 12 Attack XP (+4 Vitality), no Strength")
	Combat.award_hit_xp(sk, "aggressive", 3)
	check(int(sk.xp["strength"]) - x0[1] == 12 and int(sk.xp["attack"]) - x0[0] == 12, "Aggressive: 3 damage -> 12 Strength XP")
	p.inventory.clear()
	p.inventory.add("bronze_mace")
	p.equip_slot(p.inventory.find("bronze_mace"))
	var crush_default := p.current_style()
	p.inventory.add("bronze_dagger")
	p.equip_slot(p.inventory.find("bronze_dagger"))
	var stab_default := p.current_style()
	p.set_style("aggressive")
	check(crush_default == "aggressive" and stab_default == "accurate" and p.current_style() == "aggressive",
		"style follows the weapon (crush -> Aggressive, stab/slash -> Accurate) and can be switched any time")
	# real fights route XP by style
	var em: EnemyManager = world.enemies
	var routed := []
	for style in ["accurate", "aggressive"]:
		p.set_style(style)
		var rat: Enemy = em.nearest(Vector2i(-34, 22), ["giant_rat"], 300)
		rat.reset_far()
		p.hp = p.max_hp()
		p.place_at(world.find_free_tile_near(rat.tile + Vector2i(1, 0), 1))
		var a0 := int(sk.xp["attack"])
		var s0 := int(sk.xp["strength"])
		p.attack(rat)
		var tt := Tick.tick_count + 5000 + routed.size() * 1000
		var end := tt + 600
		while not rat.dead and tt < end:
			p.on_tick(tt, world)
			em.on_tick(tt, [p], p.tile)
			tt += 1
		routed.append([int(sk.xp["attack"]) - a0, int(sk.xp["strength"]) - s0, rat.dead])
		p.stop()
	check(routed[0][2] and routed[0][0] > 0 and routed[0][1] == 0 and routed[1][2] and routed[1][1] > 0 and routed[1][0] == 0,
		"a real fight on Accurate trains only Attack (+%d), on Aggressive only Strength (+%d)" % [routed[0][0], routed[1][1]])

	# -- Defence XP: on block and on hit, x full-set bonus
	p.equipment.clear()
	p.hp = p.max_hp()
	var g: Enemy = em.nearest(Vector2i(48, 40), ["goblin"], 300)
	var d0 := int(sk.xp["defence"])
	p.take_hit(0, g, Tick.tick_count)
	var d_block := int(sk.xp["defence"]) - d0
	p.take_hit(3, g, Tick.tick_count)
	var d_hit := int(sk.xp["defence"]) - d0 - d_block
	check(d_block == 2 and d_hit == 5, "Defence XP when attacked: a block/miss gives %d, a 3-damage hit gives %d (2 + 1 per damage)" % [d_block, d_hit])
	p.hp = p.max_hp()
	var sets := {
		"bronze": ["bronze_cap", "bronze_scale_vest", "bronze_greaves", "alder_buckler"],
		"iron": ["iron_helm", "iron_hauberk", "iron_legguards", "iron_kite_shield"],
		"steel": ["steel_helm", "steel_brigandine", "steel_legplates", "steel_heater_shield"],
		"dusk": ["dusk_helm", "dusk_cuirass", "dusk_tassets", "dusk_tower_shield"]}
	var mults := []
	for k in ["bronze", "iron", "steel", "dusk"]:
		mults.append(float(Combat.set_bonus(sets[k])["mult"]))
	check(mults == [1.25, 1.5, 1.75, 2.0], "full same-tier set bonus: bronze x1.25, iron x1.5, steel x1.75, dusk x2.0 (data)")
	check(is_equal_approx(float(Combat.set_bonus(["steel_helm", "steel_brigandine", "steel_legplates"])["mult"]), 1.0)
		and is_equal_approx(float(Combat.set_bonus(["steel_helm", "iron_hauberk", "steel_legplates", "steel_heater_shield"])["mult"]), 1.0)
		and is_equal_approx(float(Combat.set_bonus(["steel_helm", "steel_brigandine", "steel_legplates", "dusk_tower_shield"])["mult"]), 1.0),
		"no bonus for a partial (3 pieces) or mixed-tier set")
	for cs in Combat.COMBAT_SKILLS:
		sk.set_level(cs, 25)
	for id in sets["steel"]:
		p.inventory.add(id)
		p.equip_slot(p.inventory.find(id))
	check(is_equal_approx(p.set_mult(), 1.75), "wearing a full steel set: Defence XP x1.75")
	p.rng.seed = 2404
	var d1 := int(sk.xp["defence"])
	for i in 200:
		p.take_hit(0, g, Tick.tick_count)
		p.hp = p.max_hp()
	var per_block := (int(sk.xp["defence"]) - d1) / 200.0
	check(absf(per_block - 3.5) < 0.15, "...200 blocks average %.2f Defence XP each (2 x 1.75)" % per_block)
	p.equipment.erase("shield")
	check(is_equal_approx(p.set_mult(), 1.0), "taking the shield off ends the set bonus")
	p.equipment.clear()
	# Defence lowers enemy accuracy
	check(Combat.enemy_accuracy(gob, 0, 30) < Combat.enemy_accuracy(gob, 0, 1), "higher Defence: enemies hit you less often (%.0f%% vs %.0f%%)" % [Combat.enemy_accuracy(gob, 0, 30) * 100, Combat.enemy_accuracy(gob, 0, 1) * 100])

	# -- AI
	var adv: AIAgent = null
	for a in AIDirector.records:
		if a.persona_id() == "adventurer":
			adv = a
			break
	check(adv != null and AIBrain.is_fighter(adv) and adv.skills.level("defence") >= 1 and not adv.skills.xp.has("melee"), "adventurers are fighters with Attack/Strength/Defence")
	var ag := AIAgent.new()
	ag.persona = adv.persona if adv else {}
	ag.rng.seed = 77
	for cs in Combat.COMBAT_SKILLS:
		ag.skills.set_level(cs, 5)
	ag.stash_add("iron_mace", 1)
	ag.stash_add("iron_helm", 1)
	AIBrain.equip_from_stash(ag)
	check(ag.tools.get("melee", {}).is_empty() and ag.gear.is_empty(), "AI won't equip gear above its Strength / Defence")
	ag.skills.set_level("strength", 10)
	ag.skills.set_level("defence", 10)
	AIBrain.equip_from_stash(ag)
	check(str(ag.tools.get("melee", {}).get("id", "")) == "iron_mace" and str(ag.gear.get("head", {}).get("id", "")) == "iron_helm", "...and equips it once the levels allow")
	var fn_lo := Combat.expected_fight(gob, AIBrain.fight_stats(ag))
	ag.skills.set_level("defence", 30)
	var fn_hi := Combat.expected_fight(gob, AIBrain.fight_stats(ag))
	check(float(fn_hi["damage"]) < float(fn_lo["damage"]) and float(fn_lo["def_xp"]) > 0.0, "abstract fights use Defence (damage %.1f -> %.1f per kill) and earn Defence XP" % [float(fn_lo["damage"]), float(fn_hi["damage"])])
	ag.skills.set_level("defence", 10)
	ag.stash_add("cooked_carp", 200)
	ag.hp = AIBrain.agent_max_hp(ag)
	var xs := [int(ag.skills.xp["attack"]), int(ag.skills.xp["strength"]), int(ag.skills.xp["defence"])]
	ag.activity = {"type": "fight", "skill": "attack", "until": 1 << 40}
	for i in 40:
		AIBrain.simulate(ag, 100, Tick.tick_count)
		ag.activity = {"type": "fight", "skill": "attack", "until": 1 << 40}
	check(int(ag.skills.xp["attack"]) > xs[0] and int(ag.skills.xp["strength"]) > xs[1] and int(ag.skills.xp["defence"]) > xs[2],
		"AI fighters rotate styles: abstract fights train Attack (+%d), Strength (+%d) and Defence (+%d)" % [int(ag.skills.xp["attack"]) - xs[0], int(ag.skills.xp["strength"]) - xs[1], int(ag.skills.xp["defence"]) - xs[2]])

	# -- save migration v2 -> v3: Melee XP -> Attack, Strength and Defence
	var mx := GameData.xp_for_level(12)
	var old := {"version": 2, "player": {"skills": {"melee": mx, "vitality": GameData.xp_for_level(15), "mining": 50}, "equipment": {"head": "iron_helm", "weapon": "iron_warhammer"}},
		"ai": {"agents": [{"xp": {"melee": 400, "vitality": 1300}, "activity": {"type": "fight", "skill": "melee"}, "tools": {"melee": {"id": "bronze_sword", "dur": 9}}}]}}
	SaveSystem.path_override = "user://selftest_v2.json"
	var f := FileAccess.open(SaveSystem.path_override, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var mig := SaveSystem.load_game()
	var ps: Dictionary = mig["player"]["skills"]
	var ax: Dictionary = mig["ai"]["agents"][0]
	check(int(mig["version"]) == SaveSystem.SAVE_VERSION and not ps.has("melee") and int(ps["attack"]) == mx and int(ps["strength"]) == mx and int(ps["defence"]) == mx and int(ps["mining"]) == 50,
		"migration: the player's Melee XP is copied into Attack, Strength and Defence")
	check(int(ax["xp"]["attack"]) == 400 and int(ax["xp"]["defence"]) == 400 and not ax["xp"].has("melee") and ax["activity"]["skill"] == "attack" and ax["tools"].has("melee"),
		"migration: AI agents too (weapon slot kept)")
	var p4 := Player.new()
	p4.from_save(mig["player"])
	p4.equipment = mig["player"]["equipment"]
	check(Combat.equip_error(p4.skills, "iron_helm") == "" and Combat.equip_error(p4.skills, "iron_warhammer") == "" and p4.skills.level("attack") == 12,
		"migrated players keep access to the gear they wore (Melee 12 -> iron helm and warhammer still usable)")
	p4.free()
	SaveSystem.delete_save()
	SaveSystem.path_override = ""
	for cs in Combat.COMBAT_SKILLS:
		sk.set_level(cs, 10)
	p.inventory.clear()
	p.combat_style = ""
	p.hp = p.max_hp()


## 0.2.4: player sprint and energy (data/player.json).
static func _sprint_tests(main, world: World, p: Player) -> void:
	var c := Player.energy_cfg()
	p.stop()
	p.inventory.clear()
	p.place_at(world.find_free_tile_near(world.gen.town_spawn("fenhollow"), 2))
	p.energy = p.max_energy()
	check(p.set_sprint(true) == "Sprint on." and p.sprint, "tap Energy: sprint on")
	var dest := world.find_free_tile_near(p.tile + Vector2i(14, 0), 3)
	p.walk_to(world, dest)
	var n0 := p.path.size()
	var t := Tick.tick_count + 20000
	var from := p.tile
	p.on_tick(t, world)
	check(p.last_steps == 2 and p.path.size() == n0 - 2 and from != p.tile, "sprinting moves 2 tiles per tick")
	check(is_equal_approx(p.energy, p.max_energy() - float(c["sprint_drain"])), "...and drains %.1f energy per tick" % float(c["sprint_drain"]))
	p.stop()
	p.energy = 50.0
	p.on_tick(t + 1, world)
	check(p.sprint and is_equal_approx(p.energy, 50.0 + float(c["regen_idle"])), "standing still with sprint on doesn't drain (idle regen instead)")
	# auto-off at 0
	p.energy = 0.4
	p.walk_to(world, world.find_free_tile_near(p.tile + Vector2i(-12, 0), 3))
	p.on_tick(t + 2, world)
	check(not p.sprint and p.energy == 0.0, "at 0 energy sprint switches itself off")
	p.on_tick(t + 3, world)
	check(p.last_steps == 1, "...and you walk 1 tile per tick again")
	check(p.set_sprint(true) == "You're too tired to run." and not p.sprint, "can't start sprinting with no energy")
	# regen: walking / busy vs idle
	p.energy = 50.0
	p.on_tick(t + 4, world)
	var walk_regen := p.energy - 50.0
	p.stop()
	p.energy = 50.0
	p.on_tick(t + 5, world)
	var idle_regen := p.energy - 50.0
	check(idle_regen > walk_regen and walk_regen > 0.0 and is_equal_approx(walk_regen, float(c["regen_active"])) and is_equal_approx(idle_regen, float(c["regen_idle"])),
		"regen is faster when idle (%.2f/tick) than walking or busy (%.2f/tick)" % [idle_regen, walk_regen])
	p.energy = p.max_energy() - 0.1
	p.on_tick(t + 6, world)
	check(is_equal_approx(p.energy, p.max_energy()), "energy is clamped to its max (%d)" % int(p.max_energy()))
	# save / load
	p.energy = 37.5
	var d := p.to_save()
	var p5 := Player.new()
	p5.from_save(d)
	var old := d.duplicate()
	old.erase("energy")
	var p6 := Player.new()
	p6.from_save(old)
	check(is_equal_approx(p5.energy, 37.5) and is_equal_approx(p6.energy, p6.max_energy()), "energy survives save/load (old saves start full)")
	p5.free()
	p6.free()
	var view := AIPlayer.new()
	check(view.sprint_steps() == 0, "AI players never sprint")
	view.free()
	p.sprint = false
	p.energy = p.max_energy()


## 0.3.0 walk: immediate facing, straight diagonals, no camera jitter (the 0.2.5
## hysteresis was replaced after a phone test: it kept facing the old way).
static func _open_patch(world: World, c0: Vector2i, w: int, h: int) -> Vector2i:
	for r in range(4, 60):
		for oy in range(-r, r + 1, 3):
			for ox in range(-r, r + 1, 3):
				var o := c0 + Vector2i(ox, oy)
				var free := true
				for y in range(-1, h + 1):
					for x in range(-1, w + 1):
						if world.is_blocked(o + Vector2i(x, y)) or not world.gen.building_at(o + Vector2i(x, y)).is_empty():
							free = false
				if free:
					return o
	return Vector2i(1 << 20, 0)


## Walk to dest tick by tick; returns per-tick records {flip_left, vis_pts, steps, tile}.
static func _walk_log(world: World, p: Player, dest: Vector2i, t0: int) -> Array:
	var out: Array = []
	p.walk_to(world, dest)
	var t := t0
	var guard := 0
	while not p.path.is_empty() and guard < 80:
		p.on_tick(t, world)
		out.append({"left": p.facing.left, "pts": p._vis_pts.duplicate(), "steps": p.last_steps, "tile": p.tile})
		t += 1
		guard += 1
	return out


static func _facing_tests(main, world: World, p: Player) -> void:
	p.stop()
	p.sprint = false
	var origin := _open_patch(world, world.gen.town_spawn("fenhollow") + Vector2i(0, 40), 14, 14)
	check(origin.x != 1 << 20, "found an open 14x14 patch to walk on")
	if origin.x == 1 << 20:
		return
	var t := Tick.tick_count + 40000
	p.place_at(origin + Vector2i(1, 7))
	p.facing = Facing.new()
	p.facing.left = true
	# right, then left, then diagonal up-right, then down-left: one flip per change, on its FIRST tick
	var legs := [[Vector2i(12, 7), false], [Vector2i(3, 7), true], [Vector2i(9, 1), false], [Vector2i(3, 7), true]]
	var ok_first := true
	var ok_steady := true
	var flips0 := p.facing.flips
	for leg in legs:
		var log := _walk_log(world, p, origin + leg[0], t)
		t += log.size() + 2
		if log.is_empty():
			ok_first = false
			continue
		ok_first = ok_first and log[0]["left"] == leg[1]
		for r in log:
			ok_steady = ok_steady and r["left"] == leg[1]
	check(ok_first, "facing switches on the FIRST tick of every direction change (right, left, up-right, down-left)")
	check(ok_steady and p.facing.flips - flips0 == 4, "facing never changes within a leg: exactly 1 flip per change (%d flips for 4 changes)" % (p.facing.flips - flips0))
	# straight down: keeps facing
	var keep: bool = p.facing.left
	var vlog := _walk_log(world, p, p.tile + Vector2i(0, 5), t)
	t += vlog.size() + 2
	var kept := true
	for r in vlog:
		kept = kept and r["left"] == keep
	check(kept and not vlog.is_empty(), "walking straight down keeps the facing")
	# 45 degrees: every step diagonal, sprite moves in a straight monotonic line
	p.place_at(origin + Vector2i(1, 12))
	var dlog := _walk_log(world, p, origin + Vector2i(11, 2), t)
	t += dlog.size() + 2
	var all_diag := dlog.size() == 10
	var mono := true
	var prev: Vector2 = p.foot_px(origin + Vector2i(1, 12))
	for r in dlog:
		var q: Vector2 = r["pts"].back()
		all_diag = all_diag and r["steps"] == 1
		mono = mono and q.x > prev.x and q.y < prev.y and is_equal_approx(q.x - prev.x, prev.y - q.y)
		prev = q
	check(all_diag and mono, "a 45-degree walk is 10 diagonal steps on a straight, steady line (no up-then-over)")
	# shallow angle (10 right, 4 up): straight-line sprite path, monotonic, no axis staircase
	p.place_at(origin + Vector2i(1, 9))
	var a0: Vector2 = p.foot_px(p.tile)
	var a1: Vector2 = p.foot_px(origin + Vector2i(11, 5))
	var slog := _walk_log(world, p, origin + Vector2i(11, 5), t)
	t += slog.size() + 2
	var on_line := slog.size() == 10
	var smono := true
	prev = a0
	for r in slog:
		var q: Vector2 = r["pts"].back()
		var cross := absf((a1 - a0).cross(q - a0)) / (a1 - a0).length()
		on_line = on_line and cross < 0.01
		smono = smono and q.x > prev.x and q.y <= prev.y
		prev = q
	check(on_line and smono, "a shallow diagonal (10 x 4) is 10 steps with the sprite exactly on the straight line, monotonic in x and y")
	# sprint diagonal: 2 tiles per tick, still straight
	p.place_at(origin + Vector2i(1, 13))
	p.energy = p.max_energy()
	p.sprint = true
	var splog := _walk_log(world, p, origin + Vector2i(9, 5), t)
	t += splog.size() + 2
	p.sprint = false
	var sp_ok := splog.size() == 4
	for r in splog:
		var pts: Array = r["pts"]
		sp_ok = sp_ok and r["steps"] == 2 and pts.size() == 3 and is_equal_approx((pts[1] - pts[0]).cross(pts[2] - pts[1]), 0.0)
	check(sp_ok, "sprinting diagonally: 2 tiles per tick on one straight line (%d ticks)" % splog.size())
	# corner rule: slip past one tree corner, never a wall corner
	var tree: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow") + Vector2i(0, 40), ["ash_tree", "alder_tree"], 60)
	var tree_ok := false
	if tree:
		for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var cur: Vector2i = tree.pos - Vector2i(d.x, 0)
			if not world.is_blocked(cur) and not world.is_blocked(cur + d) and not world.is_blocked(cur + Vector2i(0, d.y)):
				tree_ok = tree_ok or Pathfinder.diag_ok(world, cur, d)
	var b: Dictionary = world.gen.building_for_shop("fenhollow", "general")
	var r0: Rect2i = b["rect"]
	var wall_cur := r0.position + Vector2i(-1, 1)        # outside the west wall, one row down
	var wall_a := Pathfinder.diag_ok(world, wall_cur, Vector2i(1, -1))
	var wall_b := Pathfinder.diag_ok(world, r0.position + Vector2i(-1, 0), Vector2i(1, -1))   # around the NW corner
	check(tree_ok and not wall_a and not wall_b, "diagonals may pass one tree corner but never cut a wall corner (tree %s, wall %s/%s)" % [tree_ok, wall_a, wall_b])
	# fight while standing: face the target
	var rat: Enemy = world.enemies.nearest(Vector2i(-34, 22), ["giant_rat"], 300)
	p.place_at(origin + Vector2i(5, 5))
	p.facing.left = false
	var rt0: Vector2i = rat.tile
	rat.tile = p.tile + Vector2i(-1, 0)
	p.action = {"kind": "fight", "enemy": rat}
	p.last_steps = 0
	p._update_facing()
	check(p.facing.left, "standing in a fight faces the target")
	rat.tile = rt0
	p.stop()
	# camera follows the SAME frame's player position (0.2.5 blur: one frame behind)
	p.place_at(origin + Vector2i(1, 1))
	p.walk_to(world, origin + Vector2i(8, 8))
	p.on_tick(t, world)
	t += 1
	main._process(0.0)
	check(main.camera.position == (p.trail_position(Tick.alpha()) - Vector2(0, GameData.tile_size / 2.0)).round() and p.position == p.trail_position(Tick.alpha()),
		"camera and avatar use the same frame's rounded position (no 1-frame lag jitter)")
	check(p.position == p.position.round(), "avatar drawn at whole pixels")
	p.stop()
	# walk cycle: data fps, continuous clock, grace across a 1-tick pause
	var fps_p := float(GameData.sprite_def("actors", "player")["fps"])
	var pfr := p._sprite.hframes
	var want := Facing.anim_frame(0.5, fps_p, pfr)
	check(is_equal_approx(p.anim_fps(), fps_p) and pfr == int(GameData.sprite_def("actors", "player")["frames"]) and want != Facing.anim_frame(0.5, 6.0, pfr),
		"walk cycle uses the sprite's data fps (%d) and frame count (%d), not a hard-coded 6 fps x 2" % [int(fps_p), pfr])
	p._tick_now = t
	p._last_move_t = t - 1
	p._anim_t = 0.5
	p._process(0.0)
	var f_walk := p._sprite.frame
	p._tick_now = t + 3
	p._process(0.0)
	check(f_walk == want and want != 0 and p._sprite.frame == 0, "one idle tick keeps the cycle running (no frame-0 pop); real idle returns to frame 0")
	# the art itself: no walk frame may be the mirror of another
	for sid in ["player", "npc", "goblin", "giant_rat", "keeper_general", "keeper_estate"]:
		var sdef: Dictionary = GameData.sprite_def("actors", sid)
		var img: Image = (load(str(sdef["path"])) as Texture2D).get_image()
		img.decompress()
		var fw := int(sdef["frame_size"][0])
		var fh := int(sdef["frame_size"][1])
		var nfr := int(sdef.get("frames", 1))
		var min_d := 1 << 30
		for i in nfr:
			for j in nfr:
				var a_img := img.get_region(Rect2i(i * fw, 0, fw, fh))
				var b_img := img.get_region(Rect2i(j * fw, 0, fw, fh))
				b_img.flip_x()
				var d := 0
				for y in fh:
					for x in fw:
						if not a_img.get_pixel(x, y).is_equal_approx(b_img.get_pixel(x, y)):
							d += 1
				min_d = mini(min_d, d)
		check(min_d >= 12, "%s: no animation frame is a mirror image of another (closest %d px)" % [sid, min_d])
	# art opt-out: flip false
	var sd: Dictionary = GameData.sprites["actors"]["player"]
	p.facing.left = true
	p._process(0.0)
	var mirrored := p._sprite.flip_h
	sd["flip"] = false
	p._process(0.0)
	check(mirrored and not p._sprite.flip_h, "sprites.json actor 'flip': false opts the art out of mirroring")
	sd["flip"] = true
	p.facing = Facing.new()


## 0.2.5: one Energy-bar tap = one sprint toggle, with Android's touch +
## emulated-mouse event pairs.
static func _tap_tests(main, p: Player) -> void:
	var bar: StatBar = main.hud.energy_bar
	var emu0 := bar.touch_emulated
	p.sprint = false
	p.energy = p.max_energy()
	var tap_seq := func():
		var tp := InputEventScreenTouch.new()
		tp.pressed = true
		var mp := InputEventMouseButton.new()
		mp.button_index = MOUSE_BUTTON_LEFT
		mp.pressed = true
		var tr := InputEventScreenTouch.new()
		tr.pressed = false
		var mr := InputEventMouseButton.new()
		mr.button_index = MOUSE_BUTTON_LEFT
		mr.pressed = false
		for ev in [tp, mp, tr, mr]:   # Android order: touch, emulated mouse, for press then release
			bar._gui_input(ev)
		bar.clock_skew_ms += 400          # next tap comes later than the debounce
	bar.touch_emulated = true
	var taps0 := bar.taps
	tap_seq.call()
	check(p.sprint and bar.taps == taps0 + 1, "one Android tap (touch + emulated mouse, press + release) turns sprint on exactly once")
	tap_seq.call()
	check(not p.sprint and bar.taps == taps0 + 2, "a second tap turns it off (two taps = two toggles)")
	bar.touch_emulated = false
	tap_seq.call()
	check(p.sprint and bar.taps == taps0 + 3, "with mouse emulation off, a touch+mouse pair still toggles once (debounce %d ms)" % int(GameData.fx["tap"]["debounce_ms"]))
	bar.touch_emulated = emu0
	p.sprint = false


# ------------------------------------------------------------- 0.3.0 buildings --
static func _run_until(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		Tick.step()
	return cond.call()


static func _outside_of(b: Dictionary) -> Vector2i:
	var r: Rect2i = b["rect"]
	var d: Vector2i = b["doors"][0]
	return d + (Vector2i(0, 3) if int(b["facade_y"]) == r.end.y - 1 else Vector2i(0, -3))


static func _building_tests(main, world: World, p: Player) -> void:
	var gen := world.gen
	var bv: BuildingsView = world.buildings_view
	var where := {}
	var ok_unique := true
	for sid in GameData.buildings_cfg["shops"].keys():
		if sid in ["general", "player", "cook"]:
			continue  # cookhouse is one per city
		var n := 0
		for id in gen.building_order:
			if gen.buildings[id]["shop"] == sid:
				n += 1
				where[sid] = gen.buildings[id]["town"]
		if n != 1:
			ok_unique = false
			printerr("    shop %s has %d buildings" % [sid, n])
	check(ok_unique and where.size() == 8, "every gear specialist shop id has exactly one building in exactly one town (%d)" % where.size())
	var per_town_ok := true
	for tid in Market.town_ids:
		var g := 0
		var pl := 0
		var ck := 0
		for id in gen.building_order:
			var b: Dictionary = gen.buildings[id]
			if b["town"] == tid:
				g += 1 if b["shop"] == "general" else 0
				pl += 1 if b["kind"] == "player" else 0
				ck += 1 if b["shop"] == "cook" else 0
		per_town_ok = per_town_ok and g == 1 and pl == (1 if tid == Market.shop_town() else 0) and ck == 1   # 0.3.8 player shop: Highfen only
		for sid in Market.town(tid).specialists:
			if sid == "cook":
				continue
			per_town_ok = per_town_ok and where.get(sid, "") == tid
	check(per_town_ok, "each town: general, cookhouse, its gear specialists (player shop: Highfen only)alists")
	var walls_ok := true
	var doors_ok := true
	var reach_ok := true
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		var r: Rect2i = b["rect"]
		for x in range(r.position.x, r.end.x):
			for y in [r.position.y, r.end.y - 1]:
				var t := Vector2i(x, y)
				if not (t in b["doors"]):
					walls_ok = walls_ok and world.is_blocked(t)
		for y in range(r.position.y, r.end.y):
			walls_ok = walls_ok and world.is_blocked(Vector2i(r.position.x, y)) and world.is_blocked(Vector2i(r.end.x - 1, y))
		for c in b["counter"]:
			walls_ok = walls_ok and world.is_blocked(c)
		for d in b["doors"]:
			doors_ok = doors_ok and not world.is_blocked(d)
		var path := Pathfinder.find_path(world, gen.town_spawn(b["town"]), [b["stand"]], b["stand"], 30000)
		if path.is_empty():
			reach_ok = false
			printerr("    unreachable: %s" % id)
	check(walls_ok, "building walls (except doorways) and counters block movement")
	check(doors_ok, "every doorway is walkable")
	check(reach_ok, "every building's counter front is reachable from its town spawn (%d buildings)" % gen.building_order.size())
	var b0: Dictionary = gen.building_for_shop("fenhollow", "general")
	var outside := _outside_of(b0)
	var pth := Pathfinder.find_path(world, outside, [b0["stand"]], b0["stand"], 4000)
	var through := false
	var clean := true
	for t in pth:
		through = through or t in b0["doors"]
		clean = clean and not world.is_blocked(t)
	check(not pth.is_empty() and through and clean, "a tap inside a shop paths in through the doorway, never through a wall")
	var b1: Dictionary = gen.building_for_shop("fenhollow", Market.town("fenhollow").specialists[0])
	p.place_at(outside)
	bv.player = p
	for i in 30:
		bv.step(0.05)
	var all_on := true
	for id in gen.building_order:
		all_on = all_on and bv.roof_alpha(id) >= 0.999
	check(all_on, "outside: every roof shows")
	p.place_at(b0["stand"])
	bv.step(0.1)
	check(bv.roof_alpha(b0["id"]) < 0.9 and bv.roof_alpha(b0["id"]) > 0.1, "the roof fades (not a pop): alpha %.2f after 0.1 s" % bv.roof_alpha(b0["id"]))
	bv.step(0.15)
	var others_on := true
	for id in gen.building_order:
		if id != b0["id"]:
			others_on = others_on and bv.roof_alpha(id) >= 0.999
	check(bv.roof_alpha(b0["id"]) <= 0.001 and others_on, "inside: only that building's roof is cut away (others stay on)")
	p.place_at(b0["doors"][0])
	bv.step(0.3)
	check(bv.roof_alpha(b0["id"]) <= 0.001, "standing in the doorway also cuts the roof away")
	if not AIDirector.agents.is_empty():
		var ai: AIPlayer = AIDirector.agents[0]
		var ai_tile0: Vector2i = ai.tile
		ai.place_at(b1["stand"])
		p.place_at(outside)
		bv.step(0.5)
		bv._apply_hiding()
		check(not ai.visible and bv.hides(b1["stand"]), "an AI inside a roofed building is hidden while its roof shows")
		p.place_at(b1["doors"][0])
		bv.step(0.5)
		bv._apply_hiding()
		check(ai.visible and p.visible, "... and visible once you step in (roof cut away); you are never hidden")
		ai.place_at(ai_tile0)
		ai.visible = true
	var opened := []
	var said := []
	var c1 := func(s): opened.append(s)
	var c2 := func(t, k): said.append([t, k])
	Events.shop_opened.connect(c1)
	Events.message.connect(c2)
	p.place_at(_outside_of(b1))
	p._greeted.clear()
	p.handle_tap(world, b1["keeper_at"])
	var arrived := _run_until(func(): return not opened.is_empty(), 120)
	Events.shop_opened.disconnect(c1)
	Events.message.disconnect(c2)
	check(arrived and p.tile == b1["stand"], "tapping the keeper walks you to the counter front (%s)" % str(p.tile))
	check(arrived and opened[0] == b1["shop"], "... and opens that building's shop (%s)" % str(opened))
	var greeted := false
	for m in said:
		if str(m[1]) == "npc" and str(m[0]).contains(str(b1["keeper"])):
			greeted = true
	check(greeted, "the keeper greets you in chat before the shop opens")
	opened.clear()
	Events.shop_opened.connect(c1)
	p.place_at(outside)
	p.handle_tap(world, b0["counter"][0])
	_run_until(func(): return not opened.is_empty(), 120)
	Events.shop_opened.disconnect(c1)
	check(opened == ["general"] and p.tile == b0["stand"], "tapping the counter opens the shop from the counter front")
	var kv = world.object_at(b1["keeper_at"])
	check(kv != null and kv.view != null and (kv.view as Sprite2D).hframes >= 2, "keepers are animated actor sheets")
	var wall: Vector2i = (b1["rect"] as Rect2i).position + Vector2i(1, 0)
	var sv := p.to_save()
	sv["tile"] = [wall.x, wall.y]
	var q := Player.new()
	q.from_save(sv)
	var moved: bool = main.relocate_if_walled(world, q)
	check(moved and not world.is_blocked(q.tile) and gen.building_at(q.tile).is_empty(), "an old save standing in a wall is moved to a free outdoor tile (%s -> %s)" % [str(wall), str(q.tile)])
	q.free()
	p.place_at(gen.town_spawn("fenhollow"))


static func _player_shop_tests(_main, world: World, p: Player) -> void:
	var tid := "fenhollow"
	var ps: PlayerShop = Market.player_shop(tid)
	var snap := ps.to_save()
	var coin: String = GameData.currency
	check(ps.buy_building(AIDirector.records[0]) != "" and not ps.owned, "an AI player can't buy the shop building")
	var have := p.inventory.count(coin)
	p.inventory.remove(coin, have)
	check(ps.buy_building(p) != "" and not ps.owned, "can't buy without %d marks" % PlayerShop.building_price())
	p.inventory.add(coin, 5000)
	check(ps.buy_building(p) == "" and ps.owned and p.inventory.count(coin) == 5000 - PlayerShop.building_price() and ps.owner_name == p.display_name,
		"buying deducts %d marks and sets ownership" % PlayerShop.building_price())
	check(world.buildings_view.label_for(world.gen.building_for_shop(Market.shop_town(), "player")) == ps.title() and ps.title() == "Your Shop", "the sign reads \"%s\" once owned (unnamed player)" % ps.title())
	ps.owner_name = "Hudson"
	check(ps.title() == "Hudson's Shop", "a named player gets \"<name>'s Shop\"")
	ps.owner_name = p.display_name
	p.inventory.add("bronze_arrows", 80)
	p.inventory.add("bronze_sword", 2)
	var ref := Market.town(tid).reference_price("bronze_arrows")
	check(ps.place(p, 2, "bronze_arrows", 80, maxi(1, ref)) == "" and int(ps.slots[2]["qty"]) == PlayerShop.cap_for("bronze_arrows") and p.inventory.count("bronze_arrows") == 30,
		"stackables cap at %d per stand (80 offered, 50 placed)" % PlayerShop.cap_for("bronze_arrows"))
	check(ps.take_back(p, 2) == "" and ps.slots[2] == null and p.inventory.count("bronze_arrows") == 80, "take back returns the whole stack to the pack")
	ref = maxi(2, ref)
	check(ps.place(p, 0, "bronze_arrows", 10, 0) != "", "price floor is 1")
	check(ps.place(p, 0, "bronze_arrows", 10, ref * 50) != "", "anti-manipulation: no more than 5x the going rate")
	check(ps.place(p, 0, "bronze_arrows", 10, ref) == "" and p.inventory.count("bronze_arrows") == 70 and int(ps.slots[0]["qty"]) == 10, "place 10 bronze arrows at ref %d" % ref)
	check(ps.place(p, 1, "bronze_sword", 1, 50) == "" and int(ps.slots[1]["qty"]) == 1, "a sword on stand 2")
	check(ps.place(p, 1, "bronze_sword", 1, 50) != "", "gear: one per stand")
	check(ps.reprice(0, ref + 3) == "" and int(ps.slots[0]["price"]) == ref + 3, "reprice")
	check(ps.take_back(p, 1) == "" and ps.slots[1] == null and p.inventory.count("bronze_sword") == 2, "take back a sword")
	check(ps.player_buy(p, 0) != "" and ps.ai_buy("player", 0, 1) == 0, "you can't buy from your own shop")
	var buyer: AIAgent = AIDirector.records[1]
	ps.lots_today.clear()
	var till0 := ps.till
	var cost := ps.ai_buy(buyer.id, 0, 5)
	var tax := Market.town(tid).tax_on(cost)
	check(cost == 5 * (ref + 3) and ps.till == till0 + cost - tax and int(ps.slots[0]["qty"]) == 5 and ps.log.size() >= 1, "AI purchase: till += price - tax (%d - %d)" % [cost, tax])
	var c0 := p.inventory.count(coin)
	var got := ps.collect(p)
	check(got == till0 + cost - tax and p.inventory.count(coin) == c0 + got and ps.till == 0, "collect the till at the counter (+%d)" % got)
	var un := ps.take_unseen()
	check(int(un["qty"]) >= 5 and int(un["coins"]) >= cost - tax, "away summary counts units and coins (%s)" % str(un))
	var sv := Market.to_save()
	ps.slots[0] = null
	ps.owned = false
	Market.from_save(JSON.parse_string(JSON.stringify(sv)))
	var ps2: PlayerShop = Market.player_shop(tid)
	check(ps2.owned and ps2.slots[0] != null and int(ps2.slots[0]["qty"]) == 5 and ps2.owner_name == p.display_name, "player shop (ownership, stands) survives save/load (JSON round trip)")
	var mo: Dictionary = JSON.parse_string(JSON.stringify(sv))
	mo.erase("player_shops")
	Market.from_save(mo)
	check(Market.player_shop(tid).owned == false, "an old save without player shops loads with unowned shops")
	Market.from_save(JSON.parse_string(JSON.stringify(sv)))
	ps = Market.player_shop(tid)
	var m := Market.town(tid)
	var item := "bronze_bar"
	var best := -1
	for cand in GameData.items.keys():
		if cand == coin:
			continue
		var w := 0
		for a in AIDirector.records:
			if a.town == tid:
				w += mini(1, AIBrain.shop_want(a, cand, true))
		if w > best:
			best = w
			item = cand
	var rref := maxi(1, m.reference_price(item))
	ps.slots[0] = {"item": item, "qty": 50, "price": rref, "dur": -1}
	var ch := []
	for mult in [0.8, 1.0, 1.3]:
		ch.append(ps.buy_chance(item, maxi(1, int(round(rref * mult)))))
	check(ch[0] > ch[1] and ch[1] > ch[2], "buy chance falls with price: 0.8x %.3f > 1.0x %.3f > 1.3x %.3f" % ch)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var sold := []
	for k in 3:
		var n := 0
		for t in 4000:
			if rng.randf() < ch[k]:
				n += 1
		sold.append(n)
	check(sold[0] > sold[1] and sold[1] > sold[2], "statistical: 4000 looks sell %d (0.8x) > %d (1.0x) > %d (1.3x)" % sold)
	var ai_snap := AIDirector.to_save()
	var units := []
	for mult in [0.8, 1.3]:
		var n2 := 0
		for round_ in 40:
			AIDirector.from_save(ai_snap)
			ps.lots_today.clear()
			ps.slots[0] = {"item": item, "qty": 100000, "price": maxi(1, int(round(rref * mult))), "dur": -1}   # never sells out: measures demand
			var u0 := int(ps.stats["units"])
			for a in AIDirector.records:
				if a.town == tid:
					AIBrain.shop_browse(a, Tick.tick_count)
			n2 += int(ps.stats["units"]) - u0
		units.append(n2)
	AIDirector.from_save(ai_snap)
	check(units[0] > units[1], "real AI agents (%d wanting it) buy more %s at 0.8x ref than 1.3x: %d vs %d units over 40 looks" % [best, item, units[0], units[1]])
	ps.from_save(snap)
	world.buildings_view.refresh_all()
	p.inventory.remove("bronze_arrows", p.inventory.count("bronze_arrows"))
	p.inventory.remove("bronze_sword", p.inventory.count("bronze_sword"))


static func _smithy_tests(_main, world: World, p: Player) -> void:
	var gen := world.gen
	var bv: BuildingsView = world.buildings_view
	var ok := true
	for tid in Market.town_ids:
		if tid == gen.capital:
			continue   # 0.3.8 Highfen has no smithy (its forge is in the player's house)
		var n := 0
		for id in gen.building_order:
			var b: Dictionary = gen.buildings[id]
			if b["town"] != tid or b["kind"] != "smithy":
				continue
			n += 1
			var has := {}
			var r: Rect2i = b["rect"]
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var o: WorldObject = world.object_at(Vector2i(x, y))
					if o and o.def_id in ["furnace", "anvil"]:
						has[o.def_id] = true
						ok = ok and gen.is_roofed(o.pos, b)
			ok = ok and has.size() == 2 and str(b["shop"]) in GameData.buildings_cfg["smithy"]["smith_shops"]
		ok = ok and n == 1
		# no furnace / anvil left out in the town
		var c := gen.town_spawn(tid)
		for y in range(-25, 26):
			for x in range(-30, 31):
				var o2: WorldObject = world.object_at(c + Vector2i(x, y))
				if o2 and o2.def_id in ["furnace", "anvil"] and gen.building_at(o2.pos).is_empty():
					ok = false
					printerr("    outdoor station %s at %s" % [o2.def_id, str(o2.pos)])
	check(ok, "every town has one Blacksmith (its weapon-smith shop) holding the furnace and anvil under the roof; none left outdoors")
	var b: Dictionary = gen.building_for_shop("fenhollow", "swords")
	check(b.get("kind", "") == "smithy" and bv.label_for(b) == "Blacksmith" and bv.sign_sprite(b) == "sign_smithy", "Fenhollow's sword shop is the Blacksmith (sign, caption)")
	var outside := _outside_of(b)
	p.place_at(outside)
	p.inventory.clear()
	p.skills.set_level("smithing", 20)
	p.inventory.add("copper_ore", 3)
	p.inventory.add("tin_ore", 3)
	p._greeted.clear()
	var said := []
	var c2 := func(t, k): said.append([t, k])
	Events.message.connect(c2)
	var fur: WorldObject = world.find_nearest_object(outside, ["furnace"], 20)
	var went := p.start_recipe(world, fur, "smelt_bronze", 3)
	var through := false
	var clean := true
	for t in 200:
		Tick.step()
		through = through or p.tile in b["doors"]
		clean = clean and not world.is_blocked(p.tile)
		if p.inventory.count("bronze_bar") >= 3 and p.action.is_empty():
			break
	check(went and through and clean and p.inventory.count("bronze_bar") == 3, "walk in through the door and smelt 3 bronze bars at the indoor furnace")
	var greeted := false
	for m in said:
		greeted = greeted or (str(m[1]) == "npc" and str(m[0]).contains(str(b["keeper"])))
	check(greeted, "the smith greets you as you walk in")
	bv.step(0.5)
	check(bv.roof_alpha(b["id"]) <= 0.001, "inside the Blacksmith the roof is cut away")
	var anv: WorldObject = world.find_nearest_object(p.tile, ["anvil"], 20)
	check(gen.building_at(anv.pos).get("id", "") == b["id"], "the nearest anvil is in the same building")
	p.start_recipe(world, anv, "forge_bronze_sword", 1)
	for t in 120:
		Tick.step()
		if p.inventory.count("bronze_sword") >= 1 and p.action.is_empty():
			break
	check(p.inventory.count("bronze_sword") == 1 and p.inventory.count("bronze_bar") == 0, "forge a bronze sword at the indoor anvil")
	p.walk_to(world, outside)
	var out_clean := true
	for t in 60:
		Tick.step()
		out_clean = out_clean and not world.is_blocked(p.tile)
		if p.tile == outside:
			break
	bv.step(0.5)
	check(p.tile == outside and out_clean and bv.roof_alpha(b["id"]) >= 0.999, "walk back out through the door; the roof returns")
	Events.message.disconnect(c2)
	# AI smiths: a path from anywhere in town to each station's interaction tiles exists (through the door)
	var ai_ok := true
	for id in gen.building_order:
		var bb: Dictionary = gen.buildings[id]
		if bb["kind"] != "smithy":
			continue
		for oid in ["furnace", "anvil"]:
			var st: WorldObject = world.find_nearest_object((bb["rect"] as Rect2i).get_center(), [oid], 8)
			var pth := Pathfinder.find_path(world, gen.town_spawn(bb["town"]), Pathfinder.interaction_tiles(st.pos), st.pos, 30000)
			var via := false
			for t2 in pth:
				via = via or t2 in bb["doors"]
			ai_ok = ai_ok and not pth.is_empty() and via
	check(ai_ok, "AI smiths can path from the plaza through the door to every indoor furnace and anvil")
	p.inventory.remove("bronze_sword", 1)
	p.place_at(gen.town_spawn("fenhollow"))


# ------------------------------------------------------------- 0.3.1 map markers --
static func _marker_tests(main, world: World, p: Player) -> void:
	print("--- 0.3.1 map markers ---")
	var cfg: Dictionary = GameData.map_markers_cfg
	check(cfg.get("max", 0) == 50 and cfg.get("icons", []).size() == 8 and cfg.get("colours", []).size() >= 6,
		"map_markers.json: cap 50, 8 icons, 6+ colours")
	var missing := 0
	for ic in cfg.get("icons", []):
		if GameData.sprite_def("ui", "marker_%s" % ic).is_empty() or not ResourceLoader.exists(GameData.sprite_def("ui", "marker_%s" % ic)["path"]):
			missing += 1
	check(missing == 0, "every marker icon has a sprite PNG")
	# data model
	p.map_markers.clear_all()
	var m1: Dictionary = p.map_markers.add(Vector2i(10, -5), "star", "#50a0e0", "Camp")
	check(not m1.is_empty() and p.map_markers.count() == 1 and str(m1["icon"]) == "star" and str(m1["label"]) == "Camp",
		"add marker with icon/colour/label")
	check(p.map_markers.update(int(m1["id"]), {"icon": "skull", "label": "Danger"}), "edit marker")
	check(str(p.map_markers.get_by_id(int(m1["id"]))["icon"]) == "skull", "edit stuck")
	var m2: Dictionary = p.map_markers.add(Vector2i(20, 0), "fish", "#60c060", "Pond")
	check(p.map_markers.count() == 2 and p.map_markers.remove(int(m1["id"])) and p.map_markers.count() == 1,
		"delete one marker leaves the other")
	# cap
	p.map_markers.clear_all()
	var filled := 0
	for i in MapMarkers.max_count():
		if not p.map_markers.add(Vector2i(i, 0), "pin").is_empty():
			filled += 1
	var overflow: Dictionary = p.map_markers.add(Vector2i(99, 99), "pin")
	check(filled == MapMarkers.max_count() and overflow.is_empty() and p.map_markers.is_full(),
		"cap at %d markers; further adds refused" % MapMarkers.max_count())
	p.map_markers.clear_all()
	# persist across save/load + v3 -> v4 migration
	p.map_markers.add(Vector2i(3, 7), "pickaxe", "#f0a040", "Mine")
	p.map_markers.add(Vector2i(-2, 4), "tree", "#60c060", "Logs")
	p.map_markers.show_on_minimap = false
	SaveSystem.path_override = "user://selftest_markers.json"
	SaveSystem.delete_save()
	check(SaveSystem.save_game(main.build_save()), "marker save written")
	var loaded: Dictionary = SaveSystem.load_game()
	check(int(loaded.get("version", 0)) == SaveSystem.SAVE_VERSION, "save version is %d" % SaveSystem.SAVE_VERSION)
	var p2 := Player.new()
	p2.from_save(loaded["player"])
	check(p2.map_markers.count() == 2 and not p2.map_markers.show_on_minimap
		and str(p2.map_markers.markers[0]["label"]) == "Mine"
		and str(p2.map_markers.markers[1]["icon"]) == "tree",
		"markers + minimap toggle round-trip through save")
	p2.free()
	# migration: a v3 save without map_markers gets an empty list
	var v3: Dictionary = main.build_save()
	v3["version"] = 3
	v3["player"].erase("map_markers")
	SaveSystem.delete_save()
	var f := FileAccess.open(SaveSystem._path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(v3))
	f.close()
	var mig: Dictionary = SaveSystem.load_game()
	check(int(mig["version"]) == SaveSystem.SAVE_VERSION and typeof(mig["player"].get("map_markers", null)) == TYPE_DICTIONARY
		and mig["player"]["map_markers"].get("list", [1]).is_empty(),
		"v3 -> v%d migration seeds empty map_markers" % SaveSystem.SAVE_VERSION)
	SaveSystem.delete_save()
	SaveSystem.path_override = ""
	p.map_markers.clear_all()
	# MapPanel long-press / short-tap (Android touch + emulated mouse) without double-fire
	var panel: MapPanel = main.hud.map_panel
	main.hud.show_panel("map")
	panel.open()
	panel.touch_emulated = true
	panel.clock_skew_ms = 0
	panel.taps = 0
	panel.long_presses = 0
	# place player so the map is centred somewhere walkable
	p.place_at(world.gen.town_spawn("fenhollow"))
	# force the view to have a size for hit-testing
	panel._view.size = Vector2(320, 220)
	var center: Vector2 = panel._view.size / 2.0
	# long-press: mouse press, advance clock past long_press_ms, process, release
	var lp_ms: int = int(cfg.get("long_press_ms", 450))
	var mp := InputEventMouseButton.new()
	mp.button_index = MOUSE_BUTTON_LEFT
	mp.pressed = true
	mp.position = center
	var tp := InputEventScreenTouch.new()
	tp.pressed = true
	tp.position = center
	panel._on_view_input(tp)   # ignored when touch_emulated
	panel._on_view_input(mp)
	panel.clock_skew_ms += lp_ms + 20
	panel._process(0.02)
	var mr := InputEventMouseButton.new()
	mr.button_index = MOUSE_BUTTON_LEFT
	mr.pressed = false
	mr.position = center
	panel._on_view_input(mr)
	check(panel.long_presses == 1 and panel._mode == "add" and panel.taps == 0,
		"one long-press opens add editor exactly once (no short-tap)")
	panel._draft_icon = "house"
	panel._draft_colour = "#a060e0"
	panel._label_edit.text = "Home"
	panel._save_draft()
	check(p.map_markers.count() == 1 and str(p.map_markers.markers[0]["icon"]) == "house"
		and str(p.map_markers.markers[0]["label"]) == "Home",
		"Save from add editor places the marker")
	# short tap on the marker opens edit (debounce + touch/mouse pair)
	panel.clock_skew_ms += 400
	var mpos: Vector2 = world.map_pixel(p.map_markers.tile_of(p.map_markers.markers[0])) * MapPanel.SCALE + panel._map_offset()
	var tap_seq := func(pos: Vector2):
		var t_p := InputEventScreenTouch.new()
		t_p.pressed = true
		t_p.position = pos
		var m_p := InputEventMouseButton.new()
		m_p.button_index = MOUSE_BUTTON_LEFT
		m_p.pressed = true
		m_p.position = pos
		var t_r := InputEventScreenTouch.new()
		t_r.pressed = false
		t_r.position = pos
		var m_r := InputEventMouseButton.new()
		m_r.button_index = MOUSE_BUTTON_LEFT
		m_r.pressed = false
		m_r.position = pos
		for ev in [t_p, m_p, t_r, m_r]:
			panel._on_view_input(ev)
	var taps0: int = panel.taps
	tap_seq.call(mpos)
	check(panel.taps == taps0 + 1 and panel._mode == "edit",
		"one Android tap on a marker opens edit exactly once")
	panel._draft_label = "Base"
	panel._label_edit.text = "Base"
	panel._save_draft()
	check(str(p.map_markers.markers[0]["label"]) == "Base", "edit save updates label")
	# delete with confirm (debounce, then two Deletes)
	panel.clock_skew_ms += 400
	tap_seq.call(mpos)
	check(panel._mode == "edit" and panel._edit_id >= 0, "re-tap opens edit before delete")
	var del_id: int = panel._edit_id
	panel._on_delete_pressed()
	check(panel._mode == "delete_armed" and p.map_markers.count() == 1 and panel._edit_id == del_id,
		"first Delete arms confirm")
	panel._on_delete_pressed()
	check(p.map_markers.count() == 0 and panel._mode == "", "second Delete removes the marker")
	# clear-all confirm
	p.map_markers.add(Vector2i(1, 1), "pin")
	p.map_markers.add(Vector2i(2, 2), "star")
	panel._cancel_edit()
	panel._on_clear_pressed()
	check(panel._mode == "clear_armed" and p.map_markers.count() == 2, "Clear all arms confirm")
	panel._on_clear_pressed()
	check(p.map_markers.count() == 0 and panel._mode == "", "Clear all (confirmed) empties markers")
	# Walk here sets a path to a nearby walkable tile
	var near: Vector2i = p.tile + Vector2i(6, 0)
	if world.is_blocked(near):
		near = p.tile + Vector2i(0, 6)
	var mw: Dictionary = p.map_markers.add(near, "sword", "#e05050", "Go")
	panel._begin_edit(mw)
	panel._walk_to_draft()
	check(not p.path.is_empty() or p.tile == near, "Walk here starts a path to the marker")
	p.stop()
	p.map_markers.clear_all()
	main.hud.show_panel("")
	panel.touch_emulated = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)


# ------------------------------------------------------------- 0.3.1 day/night --
static func _daynight_tests(main, world: World, p: Player) -> void:
	print("--- 0.3.1 day/night ---")
	var cfg: Dictionary = GameData.daynight_cfg
	check(float(cfg.get("cycle_s", 0)) == 900.0 and float(cfg.get("day_s", 0)) == 600.0 and float(cfg.get("night_s", 0)) == 300.0,
		"daynight.json: 15 min cycle (10 day + 5 night)")
	check(float(cfg.get("transition_s", 0)) >= 30.0 and float(cfg.get("transition_s", 0)) <= 45.0,
		"dusk/dawn transition 30-45 s")
	check(DayNight.ticks_per_cycle() == 1500, "cycle is 1500 ticks (900s / 0.6)")
	check(DayNight.modulate != null and is_instance_valid(DayNight.modulate), "CanvasModulate attached to the world")
	# Phases
	DayNight.debug_set_phase("day")
	check(DayNight.phase() == "day" and DayNight.lights_energy() < 0.05, "day phase: bright, lights off")
	var day_tint: Color = DayNight.tint()
	DayNight.debug_set_phase("dusk")
	check(DayNight.phase() == "dusk", "dusk phase")
	var dusk_tint: Color = DayNight.tint()
	check(dusk_tint != day_tint and DayNight.lights_energy() > 0.2 and DayNight.lights_energy() < 0.9,
		"dusk lerps tint and lights (e=%.2f)" % DayNight.lights_energy())
	DayNight.debug_set_phase("night")
	check(DayNight.phase() == "night" and DayNight.lights_energy() > 0.85, "night phase: lights on")
	var night_tint: Color = DayNight.tint()
	check(night_tint.b > night_tint.r, "night tint is blue-ish")
	DayNight.debug_set_phase("dawn")
	check(DayNight.phase() == "dawn", "dawn phase")
	# Smooth transition: step through dusk ticks, tint delta stays small
	var cyc: int = DayNight.ticks_per_cycle()
	var day_t: int = DayNight.day_ticks()
	var tr: int = DayNight.transition_ticks()
	DayNight._offset_ticks = (day_t - tr) - Tick.tick_count
	while DayNight._offset_ticks < 0:
		DayNight._offset_ticks += cyc
	DayNight.refresh()
	var prev: Color = DayNight.tint()
	var max_jump: float = 0.0
	for i in range(1, tr):
		DayNight._offset_ticks = (day_t - tr + i) - Tick.tick_count
		while DayNight._offset_ticks < 0:
			DayNight._offset_ticks += cyc
		DayNight.refresh()
		var cur: Color = DayNight.tint()
		var jump: float = absf(cur.r - prev.r) + absf(cur.g - prev.g) + absf(cur.b - prev.b)
		max_jump = maxf(max_jump, jump)
		prev = cur
	check(max_jump < 0.12, "dusk tint changes smoothly (max jump %.3f per tick)" % max_jump)
	# Lights exist in towns
	DayNight.ensure_lights(world)
	check(DayNight.lights_root != null and DayNight.lights_root.get_child_count() > 0,
		"town torches/windows spawned (%d lights)" % (DayNight.lights_root.get_child_count() if DayNight.lights_root else 0))
	# Clock drives AI schedules
	DayNight.debug_set_phase("day")
	var h_day: int = Market.game_hour()
	DayNight.debug_set_phase("night")
	var h_night: int = Market.game_hour()
	check(h_day != h_night and h_day >= 6 and h_day <= 18, "game hour follows the visible cycle (day %d, night %d)" % [h_day, h_night])
	# Persist
	DayNight.debug_set_phase("night")
	var off0: int = DayNight._offset_ticks
	SaveSystem.path_override = "user://selftest_daynight.json"
	SaveSystem.delete_save()
	check(SaveSystem.save_game(main.build_save()), "daynight save written")
	var loaded: Dictionary = SaveSystem.load_game()
	check(int(loaded.get("version", 0)) == SaveSystem.SAVE_VERSION and loaded.has("daynight"), "save v%d includes daynight" % SaveSystem.SAVE_VERSION)
	DayNight.debug_set_phase("day")
	DayNight.from_save(loaded["daynight"])
	check(DayNight._offset_ticks == off0 and DayNight.phase() == "night", "daynight offset round-trips; still night")
	SaveSystem.delete_save()
	SaveSystem.path_override = ""
	# HUD stays on a CanvasLayer (not darkened by world CanvasModulate)
	var hud_layer: Node = main.hud.get_parent()
	check(hud_layer is CanvasLayer and int(hud_layer.layer) >= 10, "HUD is on CanvasLayer >= 10 (not world-tinted)")
	DayNight.debug_set_phase("day")
