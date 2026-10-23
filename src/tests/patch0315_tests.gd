class_name Patch0315Tests
extends RefCounted
## 0.3.15 side quests on the data-driven quest system: Wolf Pelts (Odric the Hunter, Fenhollow)
## and Chicken Slayer (Quartermaster Hale, Northern Guard, Fenhollow). "gather" stages,
## XP rewards, placed givers, markers, dialog, save/load. Plus the cliff/water rule.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	print("  -- 0.3.15 side quests")
	check(str(ProjectSettings.get_setting("application/config/version")) >= "0.3.15", "version is 0.3.15+")
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var keep_q: Dictionary = p.quests.duplicate(true)
	var keep_inf: int = p.influence
	# drops: wolves can drop pelts, chickens raw chicken + feathers
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pelts := 0
	var feathers := 0
	var meat := 0
	for i in 200:
		for d in DropTable.roll("wolf", rng):
			if d[0] == "wolf_pelt": pelts += int(d[1])
		for d in DropTable.roll("chicken", rng):
			if d[0] == "feather": feathers += int(d[1])
			if d[0] == "raw_chicken": meat += int(d[1])
	check(pelts > 60 and feathers > 200 and meat > 100, "wolves drop pelts (%d/200), chickens feathers (%d) and raw chicken (%d)" % [pelts, feathers, meat])
	check(int(GameData.items["wolf_pelt"].get("value", 0)) > 0, "wolf pelts keep their trade value (existing use)")
	_quest(world, p, "wolf_pelts", "hunter_odric", {"wolf_pelt": 5}, 120, "archery")
	_quest(world, p, "chicken_slayer", "qm_hale", {"raw_chicken": 10, "feather": 30}, 80, "cooking")
	check(p.influence - keep_inf == 10, "both side quests: +5 Influence each (%d)" % (p.influence - keep_inf))
	var sv: Dictionary = p.to_save()
	var q := Player.new()
	q.from_save(sv)
	check(q.influence == p.influence and QuestSystem.state(q, "wolf_pelts") == QuestSystem.COMPLETED and QuestSystem.state(q, "chicken_slayer") == QuestSystem.COMPLETED,
		"side-quest state and Influence survive save/load")
	q.free()
	# in-progress gather survives save/load too
	p.quests.erase("wolf_pelts")
	QuestSystem.choose(p, "wolf_pelts", "accept")
	var q2 := Player.new()
	q2.from_save(p.to_save())
	check(QuestSystem.state(q2, "wolf_pelts") == QuestSystem.IN_PROGRESS, "an accepted gather quest loads in progress")
	q2.free()
	# lore: no Ash Demon in quest text
	var txt := JSON.stringify(QuestSystem.cfg()).to_lower()
	check(not txt.contains("ash demon"), "quest text never names the Ash Demon")
	p.inventory.slots = keep_inv
	p.quests = keep_q
	p.influence = keep_inf
	Events.inventory_changed.emit()
	_cliffs(world)


static func _quest(world, p, id: String, gid: String, items: Dictionary, marks: int, skill: String) -> void:
	var gt := QuestSystem.giver_tile(world, gid)
	var obj: WorldObject = world.object_at(gt)
	check(obj != null and str(obj.def().get("giver", "")) == gid and world.gen.town_at(gt, 0) == "fenhollow" and world.gen.building_at(gt).is_empty(),
		"%s stands on a Fenhollow street at %s" % [QuestSystem.giver_name(gid), gt])
	check(world.find_free_tile_near(gt + Vector2i(0, 1), 2, true) != gt, "%s can be reached" % gid)
	check(QuestSystem.giver_marker(p, gid) == "?", "%s shows '?' with a quest on offer" % gid)
	for it in items.keys():
		p.inventory.remove(it, p.inventory.count(it))
	var opened := [""]
	var cb := func(g): opened[0] = g
	Events.quest_dialog.connect(cb)
	p.place_at(world.find_free_tile_near(gt + Vector2i(0, 1), 2))
	world.set_focus(p.tile, true)
	p.interact(world, obj)
	WorldTests.ticks(15)
	Events.quest_dialog.disconnect(cb)
	var d := QuestSystem.dialog(p, gid)
	check(opened[0] == gid and d["node"] == "offer" and str(d["quest"]) == id and QuestSystem.state(p, id) == QuestSystem.NOT_STARTED, "talking to %s offers %s (not started)" % [gid, id])
	QuestSystem.choose(p, id, "accept")
	check(QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS and QuestSystem.giver_marker(p, gid) == "", "%s accepted: in progress, no marker" % id)
	check(QuestSystem.dialog(p, gid)["node"] == "in_progress" and QuestSystem.progress_text(p, id).contains(" 0/"), "progress: %s" % QuestSystem.progress_text(p, id))
	var o := QuestSystem.objective(p, world)
	check(not o.is_empty() and o["kind"] in ["enemy", "area"], "guidance points at the %s while gathering" % str(QuestSystem.quest(id)["stages"][0]["source"][0]))
	check(QuestSystem.choose(p, id, "advance") == "" and QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS, "can't hand in an empty pack")
	var first: String = items.keys()[0]
	p.inventory.add(first, int(items[first]) - 1)
	check(QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS, "one short: still in progress (%s)" % QuestSystem.progress_text(p, id))
	for it in items.keys():
		p.inventory.add(it, int(items[it]) - p.inventory.count(it))
	check(QuestSystem.state(p, id) == QuestSystem.READY and QuestSystem.giver_marker(p, gid) == "!", "%s: all items in the pack, '!' over %s" % [id, gid])
	check(QuestSystem.objective_tile(p, world) == gt, "guidance points back at %s" % gid)
	var m0: int = p.inventory.count(GameData.currency)
	var inf0: int = p.influence
	var xp0: int = p.skills.xp.get(skill, 0) if p.skills.get("xp") is Dictionary else 0
	p.interact(world, obj)
	WorldTests.ticks(15)
	check(QuestSystem.dialog(p, gid)["node"] == "stage_0", "turn-in dialog")
	QuestSystem.choose(p, id, "advance")
	var gone := true
	for it in items.keys():
		gone = gone and p.inventory.count(it) == 0
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and gone and QuestSystem.giver_marker(p, gid) == "", "%s handed in: items taken, completed, marker gone" % id)
	check(p.influence - inf0 == 5 and p.inventory.count(GameData.currency) - m0 == marks, "%s rewards: +5 Influence, %d marks" % [id, marks])
	if p.skills.get("xp") is Dictionary:
		check(int(p.skills.xp.get(skill, 0)) > xp0, "%s rewards %s XP" % [id, skill])
	check(QuestSystem.dialog(p, gid)["node"] == "completed", "%s thanks you afterwards" % gid)


## 0.3.15 Hudson's rule: no cliff within 3 tiles (Chebyshev < 3) of water. Scans the
## generated wilds around the spawn and his reported spot (108,-99).
static func _cliffs(world) -> void:
	var gen: WorldGen = world.gen
	var bad := []
	var n := 0
	for c in [Vector2i(108, -99), Vector2i(0, 0), Vector2i(-150, 60), Vector2i(220, -60), Vector2i(60, -160)]:
		for y in range(c.y - 60, c.y + 61):
			for x in range(c.x - 60, c.x + 61):
				if not gen.is_cliff(x, y):
					continue
				n += 1
				var near := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						if gen.tile_at(x + dx, y + dy) == WorldGen.TileType.WATER:
							near = true
				if near and bad.size() < 5:
					bad.append(Vector2i(x, y))
				elif near:
					bad.append(null)
	check(n > 50 and bad.is_empty(), "no cliff within 3 tiles of water (%d cliff tiles scanned, %d too close %s)" % [n, bad.size(), str(bad.slice(0, 5))])
