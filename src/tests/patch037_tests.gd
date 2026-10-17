class_name Patch037Tests
extends RefCounted
## 0.3.7: quest system (Goblin Slayer), Goblin Warlord, influence, XP feedback.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static var _xp_lines: Array = []


static func _on_msg(text: String, kind: String = "") -> void:
	if kind == "xp":
		_xp_lines.append(text)


static func _take_xp_lines() -> String:
	var s := " | ".join(_xp_lines)
	_xp_lines.clear()
	return s


static func run(world: World, p: Player) -> void:
	Events.message.connect(_on_msg)
	print("  -- 0.3.7 quests / warlord / XP feedback")
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var id := "goblin_slayer"
	check(not QuestSystem.quest(id).is_empty() and QuestSystem.quest(id)["stages"].size() == 4, "quests.json: Goblin Slayer with 4 stages")
	# old save: no quest data -> not started
	var sv := p.to_save()
	sv.erase("quests")
	sv.erase("influence")
	p.from_save(sv)
	check(p.quests.is_empty() and p.influence == 0 and QuestSystem.state(p, id) == QuestSystem.NOT_STARTED, "old save loads with the quest not started, 0 influence")
	check(QuestSystem.giver_marker(p, "kell") == "?", "Kell shows '?' while the quest is available")
	var gt := QuestSystem.giver_tile(world, "kell")
	var kell: WorldObject = world.object_at(gt)
	check(kell != null and kell.def_id == "quest_giver" and world.gen.town_at(gt, 0) == "fenhollow", "Kell stands in Fenhollow")
	# talk (real interaction)
	p.place_at(world.find_free_tile_near(gt + Vector2i(0, 1), 2))
	world.set_focus(p.tile, true)
	p.interact(world, kell)
	WorldTests.ticks(15)
	check(QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS and QuestSystem.giver_marker(p, "kell") == "", "talking to Kell starts the quest; no marker while hunting")
	check(QuestSystem.progress_text(p, id).ends_with("Goblins 0/5"), "progress text: %s" % QuestSystem.progress_text(p, id))
	# AI kills don't count
	var gob: Enemy = world.enemies.nearest(p.tile, ["goblin"], 4000)
	var ai_killer = null
	for a in AIDirector.agents:
		if a and is_instance_valid(a):
			ai_killer = a
			break
	world.enemies.on_killed(gob, ai_killer, Tick.tick_count)
	check(int(p.quests[id]["count"]) == 0, "an AI's goblin kill doesn't advance your quest")
	for i in 5:
		world.enemies.on_killed(gob, p, Tick.tick_count)
	check(QuestSystem.state(p, id) == QuestSystem.READY and QuestSystem.giver_marker(p, "kell") == "!", "5 goblins: ready to report, Kell shows '!'")
	check(QuestSystem.objective_tile(p, world) == gt, "guidance points at Kell when it's time to talk")
	p.interact(world, kell)
	WorldTests.ticks(15)
	check(QuestSystem.progress_text(p, id).contains("Goblin Warlord 0/1"), "Kell sends you after the Warlord (%s)" % QuestSystem.progress_text(p, id))
	# the Warlord
	var wd: Dictionary = GameData.enemies["goblin_warlord"]
	check(int(wd["level"]) == 12 and int(wd["hp"]) == 42 and int(wd["max_hit"]) > int(GameData.enemies["goblin"]["max_hit"]), "Goblin Warlord: level 12, 42 HP (28 x1.5), hits harder than a goblin")
	var wl: Enemy = world.enemies.nearest(p.tile, ["goblin_warlord"], 4000)
	check(wl != null and wl.cheb(wl.home, world.gen.town_center("millbrook")) <= 25, "the Warlord lives near Millbrook")
	check(QuestSystem.objective_tile(p, world) == wl.tile, "guidance points at the Warlord")
	var marks0 := p.inventory.count(GameData.currency)
	wl.take_hit(999, p, Tick.tick_count)
	check(wl.dead and QuestSystem.state(p, id) == QuestSystem.READY, "killing the Warlord: ready to turn in")
	var t := Tick.tick_count
	while wl.dead and t < Tick.tick_count + 600:
		world.enemies.on_tick(t, [], wl.home)
		t += 1
	check(not wl.dead, "the Warlord respawns (%d ticks)" % (t - Tick.tick_count))
	p.interact(world, kell)
	WorldTests.ticks(15)
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and QuestSystem.giver_marker(p, "kell") == "", "turned in: completed, all markers gone")
	check(p.influence == 10 and p.inventory.count(GameData.currency) - marks0 == 150 and p.inventory.count("iron_sword") >= 1, "rewards: +10 Influence, 150 marks, iron sword")
	var sv2 := p.to_save()
	var q := Player.new()
	q.from_save(sv2)
	check(q.influence == 10 and QuestSystem.state(q, id) == QuestSystem.COMPLETED, "quest state and influence survive save/load")
	q.free()
	# XP feedback: one line per tick, session tracker
	p.flush_xp()
	p.session_xp.clear()
	p.skills.add_xp("attack", 12)
	p.skills.add_xp("vitality", 4)
	check(p.flush_xp() == "+12 Attack XP, +4 Vitality XP" and p.flush_xp() == "", "gains in one tick combine into one line")
	check(int(p.session_xp.get("attack", 0)) == 12, "session tracker counts Attack XP")
	_xp_case(world, p, "forestry", ["bronze_hatchet"], ["ash_tree"], [])
	_xp_case(world, p, "mining", ["bronze_pick"], ["copper_rock", "tin_rock"], [])
	_xp_case(world, p, "cooking", ["raw_carp", "raw_carp", "raw_carp"], ["oven", "hearth"], [])
	# melee
	p.inventory.clear()
	p.inventory.add("bronze_sword")
	p.equip_slot(0)
	var rat: Enemy = world.enemies.nearest(world.gen.town_spawn("fenhollow"), ["giant_rat"], 4000)
	rat.reset_far()
	rat.max_hp = 999
	rat.hp = 999
	p.place_at(world.find_free_tile_near(rat.tile + Vector2i(1, 0), 2))
	world.set_focus(p.tile, true)
	p.hp = p.max_hp()
	p.flush_xp()
	_take_xp_lines()
	var s0 := p.session_xp.duplicate()
	var line := ""
	p.attack(rat)
	for i in 40:
		WorldTests.ticks(1)
		p.flush_xp()
		var l2 := _take_xp_lines()
		if l2.contains("Attack XP") or l2.contains("Strength XP"):
			line = l2
			break
	p.stop()
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	rat.reset_far()
	var grew := int(p.session_xp.get("attack", 0)) > int(s0.get("attack", 0)) or int(p.session_xp.get("strength", 0)) > int(s0.get("strength", 0))
	check(line != "" and grew, "a melee hit writes an XP line (%s) and updates the tracker" % line)
	p.equipment.erase("weapon")
	p.inventory.slots = keep_inv
	p.stop()
	Events.message.disconnect(_on_msg)


static func _xp_case(world: World, p: Player, skill: String, give: Array, objs: Array, _x: Array) -> void:
	p.inventory.clear()
	for it in give:
		p.inventory.add(it)
	var o: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow"), objs, 80)
	p.place_at(world.find_free_tile_near(o.pos + Vector2i(0, 1), 2))
	world.set_focus(p.tile, true)
	p.flush_xp()
	_take_xp_lines()
	var s0 := int(p.session_xp.get(skill, 0))
	p.interact(world, o)
	var line := ""
	var nm := str(GameData.skill_by_id[skill]["name"])
	for i in 120:
		WorldTests.ticks(1)
		p.flush_xp()
		var l2 := _take_xp_lines()
		if l2.contains(nm + " XP"):
			line = l2
			break
	p.stop()
	check(line != "" and int(p.session_xp.get(skill, 0)) > s0, "%s writes an XP line (%s) and updates the tracker" % [nm, line])
