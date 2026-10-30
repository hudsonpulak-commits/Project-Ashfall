extends RefCounted
## 0.4.0: Ranged, Fletching (knife on a log), Crafting (needle + thread),
## tanning + spinning in every city's Crafting Supply, ranger armour,
## Night of 1000 Howls part 2 (Warden Pye, Greymaw), save v11.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.4.0 ranged, fletching, crafting, dire wolf")
	check(str(ProjectSettings.get_setting("application/config/version")) in ["0.4.0", "0.4.1", "0.4.2"], "version is 0.4.0 or later (0.4.2)")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(preset.contains("version/code=40") and preset.contains("version/name=\"0.4.2\""), "Android versionCode 40 / 0.4.2")
	_skills_and_save()
	_fletching(world, p)
	_crafting()
	_ranged(world, p)
	_cities(world)
	_dire_wolf(world, p)
	_text_and_art()


static func _skills_and_save() -> void:
	check(GameData.skill_by_id["archery"]["name"] == "Ranged" and GameData.skill_by_id.has("fletching") and GameData.skill_by_id.has("crafting") and not GameData.skill_by_id.has("joinery"),
		"Archery shows as Ranged; Fletching and Crafting exist; Joinery is gone")
	var old := {"version": 10, "player": {"tile": [0, 0], "skills": {"joinery": 4470, "archery": 1234, "vitality": 1200}},
		"ai": {"agents": [{"skills": {"joinery": 99, "vitality": 1}, "activity": {"skill": "joinery"}}]}}
	var m: Dictionary = SaveSystem._migrate(old)
	var ps: Dictionary = m["player"]["skills"]
	check(int(m["version"]) == 11 and SaveSystem.SAVE_VERSION == 11 and int(ps.get("fletching", 0)) == 4470 and not ps.has("joinery") and int(ps["archery"]) == 1234,
		"save v10 -> v11: Joinery XP becomes Fletching, Ranged (archery) XP kept")
	var ag: Dictionary = m["ai"]["agents"][0]
	check(int(ag["skills"]["fletching"]) == 99 and str(ag["activity"]["skill"]) == "crafting", "AI agents migrate too (joinery activities -> crafting)")
	var sk := Skills.new()
	sk.from_save({"joinery": 500})
	check(sk.xp.get("fletching", 0) == 500 and sk.xp.get("crafting", -1) == 0, "Skills.from_save carries old Joinery XP, Crafting starts at 0")
	for id in ["saw_plank", "twist_rod", "carve_alder_buckler"]:
		check(str(Interactions.recipe_by_id(id).get("skill", "")) == "crafting", "former Joinery recipe %s now uses Crafting" % id)


static func _fletching(world: World, p: Player) -> void:
	var counts := []
	for lg in ["ash", "alder", "spruce", "blackthorn", "mahogany"]:
		var r := Interactions.recipe_by_id("fletch_shafts_%s_log" % lg)
		counts.append(int(r.get("out", {}).get("arrow_shaft", 0)))
	var rising: bool = int(counts[0]) > 0
	for i in range(1, counts.size()):
		rising = rising and int(counts[i]) > int(counts[i - 1])
	check(rising, "higher-tier logs give more shafts %s" % str(counts))
	var ok_chain := not Interactions.recipe_by_id("fletch_headless").is_empty() and not Interactions.recipe_by_id("fletch_dusk_arrows").is_empty() and not Interactions.recipe_by_id("forge_dusk_arrowheads").is_empty()
	ok_chain = ok_chain and str(Interactions.recipe_by_id("forge_iron_arrowheads").get("station", "")) == "anvil"
	check(ok_chain, "shafts -> headless -> arrows; arrowheads are smithed at the anvil")
	var bows := true
	for b in ["ash_shortbow", "alder_longbow", "blackthorn_warbow"]:
		var found := false
		for r in GameData.recipes:
			if r["out"].has(b) and r["in"].has(b + "_u"):
				found = true
		bows = bows and found
	check(bows, "log -> unstrung bow -> strung bow for all three bows")
	# knife on a log, from the pack
	var saved_inv: Array = p.inventory.to_save()
	var saved_xp: Dictionary = p.skills.xp.duplicate()
	p.inventory.from_save([])
	p.inventory.add("ash_log", 2)
	var r0 := Interactions.recipe_by_id("fletch_shafts_ash_log")
	check(not Interactions.can_make(p, r0), "no knife in the pack: the log can't be fletched")
	p.inventory.add("knife", 1)
	check(Interactions.can_make(p, r0) and p.start_pack_recipe("knife", "fletch_shafts_ash_log", 2), "knife + log opens a pack recipe (no workbench)")
	for i in 40:
		if p.action.is_empty():
			break
		Interactions.perform(p, world, i)
	check(p.inventory.count("arrow_shaft") == 2 * int(r0["out"]["arrow_shaft"]) and p.inventory.count("ash_log") == 0 and p.inventory.count("knife") == 1,
		"quantity 2 makes exactly 2 batches of shafts and keeps the knife")
	p.inventory.from_save(saved_inv)
	p.skills.xp = saved_xp
	check(CraftPanel.QTY.has(1) and CraftPanel.QTY.has(-1) and CraftPanel.QTY.size() >= 3, "the crafting window offers a quantity choice (1/5/10/All)")


static func _crafting() -> void:
	var tiers := {"leather": [1, "bronze_bar", "leather"], "studded": [10, "iron_bar", ""], "wolfpelt": [20, "steel_bar", "tanned_wolf_pelt"], "direpelt": [30, "dusk_steel_bar", "tanned_dire_pelt"]}
	var ok := true
	var dusk_only_dire := true
	for r in GameData.recipes:
		if str(r.get("station", "")) == "needle":
			ok = ok and r["in"].has("thread") and (r.get("tools", []) as Array).has("needle") and str(r["skill"]) == "crafting"
			if r["in"].has("dusk_steel_bar"):
				dusk_only_dire = dusk_only_dire and str(r["id"]).contains("direpelt")
	check(ok, "every ranger piece is sewn with needle + thread (Crafting)")
	check(dusk_only_dire, "dusk bars only go into dire wolf pelt armour")
	for t in tiers.keys():
		var r := Interactions.recipe_by_id("sew_%s_coif" % t)
		check(int(r.get("level", -1)) == int(tiers[t][0]) and r["in"].has(tiers[t][1]), "%s ranger tier at Crafting %d with %s" % [t, int(tiers[t][0]), tiers[t][1]])
	check(int(GameData.item("wolfpelt_body")["gear"]["level"]) == 20, "wolf pelt set is worn at level 20")
	var hide_ok := true
	for r in GameData.recipes:
		hide_ok = hide_ok and not r["in"].has("greymaw_hide")
	check(hide_ok and not Interactions.recipe_by_id("tan_cowhide").is_empty(), "tanning: cowhide -> leather; Greymaw's quest hide is refused")
	check(Interactions.recipe_by_id("spin_simple_string")["in"].has("reed_fibre") and Interactions.recipe_by_id("spin_superior_string")["in"].has("flax"), "spinning: reed -> simple string, flax -> superior string")
	check(int(GameData.objects["flax_plant"].get("level", 0)) == 10 and str(GameData.objects["flax_plant"]["skill"]) == "foraging", "flax is a Foraging crop (level 10)")
	check(not GameData.is_stackable("plank") and not GameData.is_stackable("iron_ore") and not GameData.is_stackable("coal"), "planks, ore and coal still don't stack")


static func _ranged(world: World, p: Player) -> void:
	check(Combat.ranged_range() >= 99, "Ranged: no practical range limit (%d)" % Combat.ranged_range())
	var hx := Combat.armour_hit_xp(["direpelt_body"])
	check(is_equal_approx(hx, 1.0) and is_equal_approx(Combat.armour_hit_xp(["leather_body", "studded_body"]), 1.0), "Defence XP: dire pelt +1, leather/studded +0.5 per piece")
	check(Combat.req_skill("wolfpelt_body") == "archery", "ranger armour is worn with Ranged")
	var saved_eq: Dictionary = p.equipment.duplicate()
	var a0 := p.ranged_atk()
	p.equipment["body"] = "studded_body"
	check(p.ranged_atk() > a0 and p.ranged_str() > 0, "ranger armour raises Ranged accuracy and damage")
	p.equipment["body"] = "iron_hauberk" if GameData.items.has("iron_hauberk") else "iron_platebody"
	check(p.ranged_atk() == a0, "melee armour doesn't help a bow")
	p.equipment = saved_eq
	check(GameData.items.has("dusk_arrows") and int(GameData.item("dusk_arrows")["gear"].get("tier", 0)) == 4, "dusk arrows are the top tier")


static func _cities(world: World) -> void:
	for t in ["fenhollow", "highfen", "saltmere", "cinderholt"]:
		var b: Dictionary = world.gen.building_for_shop(t, "crafting")
		var ok := not b.is_empty()
		var wheel := false
		var tan := false
		if ok:
			var r: Rect2i = b["rect"]
			ok = r.size.x >= 5 and r.size.y >= 5
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var oid: String = world.gen.object_id_at(Vector2i(x, y))
					wheel = wheel or oid == "spinning_wheel"
					tan = tan or oid in ["tanning_rack", "tanning_vat"]
		check(ok and wheel and tan, "%s has a Crafting Supply (>= 5x5) with a spinning wheel and tanning inside" % t)
		check(Market.town(t).specialists.has("crafting"), "%s sells crafting supplies" % t)
	var line: Array = Market.shop_cfg.get("lines", {}).get("crafting", [])
	check(line.is_empty() or (line.has("needle") and line.has("thread") and line.has("knife") and line.has("feather")), "Crafting Supply sells needles, thread, knives, feathers")


static func _dire_wolf(world: World, p: Player) -> void:
	var saved_q: Dictionary = p.quests.duplicate(true)
	p.quests.erase("wolf_pelts")
	p.quests.erase("dire_wolf")
	check(not QuestSystem.available(p, "dire_wolf"), "part 2 is locked until Night of 1000 Howls part 1 is done")
	p.quests["wolf_pelts"] = {"stage": 0, "count": 0, "done": true}
	check(QuestSystem.available(p, "dire_wolf"), "an old save with part 1 done gets part 2 offered")
	var gm: Enemy = null
	for e in world.enemies.enemies:
		if e.kind == "greymaw":
			gm = e
	check(gm != null, "Greymaw exists in the world")
	if gm == null:
		p.quests = saved_q
		return
	DireWolf.manage(gm, 10, world, [p])
	check(gm.dead and not gm.visible, "Greymaw doesn't spawn before step 5")
	p.quests["dire_wolf"] = {"stage": DireWolf.HUNT_STAGE, "count": 0, "done": false}
	DireWolf.manage(gm, 11, world, [p])
	var farms := DireWolf.farm_tiles(world)
	check(not gm.dead and farms.size() == 3 and farms.has(gm.home), "step 5 active: Greymaw waits at one of the three farms")
	check(int(gm.def["leash"]) == 16 and int(gm.def.get("aggro", 1)) == 0 and int(gm.def["respawn_ticks"]) == 1000 and gm.level() == 34, "Greymaw: combat 34, leash 16, no aggro, 10 min respawn")
	var d := DireWolf.extra_drops(true, false, RandomNumberGenerator.new())
	check(d.has(["greymaw_hide", 1]), "the quest kill drops her hide")
	p.quests["dire_wolf"] = {"stage": 10, "count": 0, "done": true}
	gm.dead = true
	gm.respawn_at = 0
	DireWolf.manage(gm, 2000, world, [p])
	check(not gm.dead, "after the turn-in she respawns on the timer at a farm")
	p.quests = saved_q
	DireWolf.manage(gm, 2001, world, [p])


static func _text_and_art() -> void:
	var txt := FileAccess.get_file_as_string("res://data/quests.json").to_lower()
	check(not txt.contains("hero") and not txt.contains("chosen one") and not txt.contains("ash demon"), "quest text never says hero / chosen one / Ash Demon")
	check(GameData.frame_count("actors", "greymaw") == 4 and GameData.frame_count("actors", "dire_wolf") == 4 and GameData.sprite_def("actors", "greymaw").has("death_paths"), "Greymaw and dire wolves use the 4-frame sprites_040 strips")
	var art_ok := true
	for id in ["dusk_arrows", "knife", "needle", "flax", "greymaw_hide", "direpelt_body"]:
		art_ok = art_ok and str(GameData.sprite_def("items", id).get("path", "")).contains("v040")
	check(art_ok, "new items use the sprites_040 art")
	check(GameData.texture("objects", "tomb_headstone") != null and GameData.frame_size("objects", "tomb_headstone") == Vector2i(32, 40), "Elijah's headstone is a 32x40 prop")
