class_name Patch036Tests
extends RefCounted
## 0.3.6: ammo slot, tools to gather, tiered food heals, flint cooking fires,
## enemy HP x1.5 + new levels, night ambient music.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(world: World, p: Player) -> void:
	print("  -- 0.3.6 ammo / tools / food / fire / enemies / night music")
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var keep_eq: Dictionary = p.equipment.duplicate()
	# ammo slot
	check("ammo" in Player.SLOTS, "the player has an ammo equipment slot")
	p.inventory.clear()
	p.equipment.erase("ammo")
	p.ammo_qty = 0
	p.inventory.add("bronze_arrows", 5)
	check(p.ammo_arrow() == "", "arrows in the pack are not fired (ammo slot empty)")
	var i := -1
	for k in p.inventory.size():
		if p.inventory.slots[k] != null and p.inventory.slots[k]["id"] == "bronze_arrows":
			i = k
	check(p.equip_slot(i) == "" and p.ammo_arrow() == "bronze_arrows" and p.ammo_qty == 5 and p.inventory.count("bronze_arrows") == 0, "equip: the whole arrow stack goes to the ammo slot")
	p.use_ammo("bronze_arrows")
	check(p.ammo_qty == 4, "a shot uses one arrow from the ammo slot")
	check(p.unequip("ammo") == "" and p.inventory.count("bronze_arrows") == 4 and not p.equipment.has("ammo"), "unequip returns the arrows to the pack")
	var sv := p.to_save()
	sv.erase("ammo_qty")
	(sv["equipment"] as Dictionary).erase("ammo")
	var q := Player.new()
	q.from_save(sv)
	check(q.ammo_arrow() == "bronze_arrows" and q.ammo_qty == 4, "old save: pack arrows are auto-equipped into the ammo slot")
	q.free()
	check(Actor.new().ammo_arrow() == "", "AI archers still pick arrows from their pack (base actor path)")
	# tools
	p.inventory.clear()
	p.equipment.erase("weapon")
	var tree: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow") + Vector2i(0, 40), ["ash_tree"], 60)   # 0.3.13 an alder (Forestry 15) can be nearer now
	var msgs: Array = []
	var mcb := func(t, _k = ""): msgs.append(str(t))
	Events.message.connect(mcb)
	p.place_at(world.find_free_tile_near(tree.pos + Vector2i(1, 0), 2))
	world.set_focus(p.tile, true)
	p.interact(world, tree)
	WorldTests.ticks(20)
	check(p.inventory.count("ash_log") + p.inventory.count("alder_log") == 0 and "You need a hatchet." in msgs, "no hatchet: 'You need a hatchet.' and no logs")
	check(not Interactions.has_gather_tool(p, "mining") and Interactions.TOOL_NEEDED["mining"] == "You need a pickaxe.", "no pickaxe: mining blocked with 'You need a pickaxe.'")
	p.inventory.add("bronze_hatchet")
	check(Interactions.has_gather_tool(p, "forestry"), "a hatchet in the pack is enough")
	p.inventory.clear()
	p.equipment["weapon"] = "bronze_hatchet"
	check(Interactions.has_gather_tool(p, "forestry") == (str(GameData.item("bronze_hatchet").get("tool", {}).get("skill", "")) == "forestry"), "a wielded hatchet counts")
	p.equipment.erase("weapon")
	check(FileAccess.get_file_as_string("res://data/shop.json").contains("bronze_hatchet") and FileAccess.get_file_as_string("res://data/shop.json").contains("bronze_pick") and FileAccess.get_file_as_string("res://data/shop.json").contains("\"flint\""), "general store sells hatchet, pickaxe and flint")
	# food tiers
	var foods: Array = []
	for r in GameData.recipes:
		if str(r.get("skill", "")) == "cooking":
			for o in r.get("out", {}).keys():
				if int(GameData.item(o).get("heals", 0)) > 0:
					foods.append([int(r.get("level", 1)), int(GameData.item(o)["heals"]), str(o)])
	foods.sort_custom(func(a, b): return a[0] < b[0])
	var rising := foods.size() >= 4
	for k in range(1, foods.size()):
		if foods[k][0] > foods[k - 1][0]:
			rising = rising and foods[k][1] > foods[k - 1][1]
	check(rising, "cooked food heals rise with recipe tier %s" % str(foods))
	# fire
	check(FireRules.burn_ticks("ash_log") == 200 and FireRules.burn_ticks("alder_log") == 300 and FireRules.burn_ticks("blackthorn_log") == 400, "fire burns 2 / 3 / 4 min by log tier")
	check(FireRules.fire_xp("blackthorn_log") > FireRules.fire_xp("ash_log"), "higher tier logs give more Forestry XP")
	p.place_at(world.find_free_tile_near(world.gen.town_spawn("fenhollow") + Vector2i(0, 30), 4, true))
	world.set_focus(p.tile, true)
	p.inventory.clear()
	check(FireRules.light(p, world, "ash_log") == "You need flint.", "no flint: no fire")
	p.inventory.add("flint", 2)
	p.inventory.add("ash_log", 1)
	var fx0 := int(p.skills.xp.get("forestry", 0))
	check(FireRules.light(p, world, "ash_log") == "", "flint on an ash log lights a fire")
	var fire: WorldObject = world.find_nearest_object(p.tile, ["cooking_fire"], 2)
	check(fire != null and p.inventory.count("flint") == 1 and p.inventory.count("ash_log") == 0 and int(p.skills.xp["forestry"]) > fx0, "1 flint + 1 log used, Forestry XP, fire on the ground")
	p.inventory.add("raw_carp", 2)
	p.interact(world, fire)
	WorldTests.ticks(30)
	check(p.inventory.count("cooked_carp") + p.inventory.count("charred_fish") == 2, "cook on the fire like a hearth")
	WorldTests.ticks(200)
	check(world.find_nearest_object(p.tile, ["cooking_fire"], 3) == null and world.fires.is_empty(), "the fire burns out by itself")
	Events.message.disconnect(mcb)
	# enemies
	var E := GameData.enemies
	check(int(E["town_guard"]["level"]) == 30 and int(E["giant_rat"]["level"]) == 5 and int(E["goblin"]["level"]) == 8, "levels: guard 30, rat 5, goblin 8")
	check(int(E["chicken"]["hp"]) == 3 and int(E["wolf"]["hp"]) == 12 and int(E["cinder_brute"]["hp"]) == 36, "enemy HP x1.5 (chicken 3, wolf 12, brute 36)")
	check(int(E["town_guard"]["defence"]) > int(E["cinder_brute"]["defence"]) and int(E["goblin"]["max_hit"]) > int(E["wolf"]["max_hit"]), "stats raised to match the new levels")
	# night music
	Music.set_title()
	Music.set_area("", false)
	Music.set_area("", true)
	check(Music.fading, "night falls in the wilds: the day ambient fades out")
	Music.step(2.0)
	check(Music.current == "ambient_night", "then the night ambient plays")
	Music.set_area("fenhollow", true)
	Music.step(2.0)
	check(Music.current == "fenhollow", "town theme still wins at night")
	Music.set_area("", false)
	Music.step(2.0)
	check(Music.current == "ambient", "day: back to the day ambient")
	p.inventory.slots = keep_inv
	p.equipment = keep_eq
	p.stop()
