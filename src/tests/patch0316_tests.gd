class_name Patch0316Tests
extends RefCounted
## 0.3.16 the last four Lore_2026-10-21 side quests on the data-driven quest system:
## We Need Steel! (gather -> deliver to another npc), Can We Fix It? (repairable farm
## props), Finding Clip Clop (kill -> escort a follower home), A Dead Rat is a Good
## Rat (kill -> talk -> boss -> talk). Real kills through the enemy manager.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	print("  -- 0.3.16 side quests")
	check((str(ProjectSettings.get_setting("application/config/version")).begins_with("0.3.") or str(ProjectSettings.get_setting("application/config/version")).begins_with("0.4.")), "version is 0.3.x")
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var keep_q: Dictionary = p.quests.duplicate(true)
	var keep_inf: int = p.influence
	var keep_tile: Vector2i = p.tile
	p.world_ref = world
	for id in ["we_need_steel", "can_we_fix_it", "finding_clip_clop", "a_dead_rat"]:
		p.quests.erase(id)
	QuestSystem.sync(p)
	_steel(world, p)
	_fix(world, p)
	_clip_clop(world, p)
	_rats(world, p)
	_map_tester(world)
	_bite(world, p)
	check(p.influence - keep_inf == 20, "four side quests: +5 Influence each (%d)" % (p.influence - keep_inf))
	var q := Player.new()
	q.from_save(p.to_save())
	var all := true
	for id in ["we_need_steel", "can_we_fix_it", "finding_clip_clop", "a_dead_rat"]:
		all = all and QuestSystem.state(q, id) == QuestSystem.COMPLETED
	check(all and q.influence == p.influence, "the four quests and Influence survive save/load")
	QuestSystem.sync(q)
	check(QuestSystem.done_ids.has("can_we_fix_it"), "a loaded save keeps the farm repaired")
	q.free()
	var txt := JSON.stringify(QuestSystem.cfg()).to_lower()
	check(not txt.contains("ash demon"), "quest text never names the Ash Demon")
	for gid in ["smith_brannoc", "sgt_voss", "farmer_garrow", "wenna_tamsin", "old_mabel"]:
		var gt := QuestSystem.giver_tile(world, gid)
		var clear := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := gt + Vector2i(dx, dy)
				if c != gt and (world.gen.building_at(c).size() > 0 or world.tile_type(c) in WorldGen.BLOCKING_TILES or world.gen.is_cliff(c.x, c.y)):
					clear = false
		check(gt.x > -99999 and clear, "%s stands in the open (5x5 clear) at %s" % [QuestSystem.giver_name(gid), gt])
	p.inventory.slots = keep_inv
	p.quests = keep_q
	p.influence = keep_inf
	QuestSystem.sync(p)
	world.refresh_repair_views()
	p.place_at(keep_tile)
	Events.inventory_changed.emit()


static func _talk(world, p, gid: String) -> Dictionary:
	var gt := QuestSystem.giver_tile(world, gid)
	p.place_at(world.find_free_tile_near(gt + Vector2i(0, 1), 2))
	world.set_focus(p.tile, true)
	return QuestSystem.dialog(p, gid)


static func _kill(world, p, kind: String, n: int, near: Vector2i) -> int:
	var done := 0
	for i in n:
		var e = world.enemies.nearest(near, [kind], 200)
		if e == null:
			break
		p.place_at(world.find_free_tile_near(e.tile + Vector2i(1, 0), 2))
		world.set_focus(p.tile, true)
		e.take_hit(9999, p, Tick.tick_count)
		done += int(e.dead)
		WorldTests.ticks(1)
	return done


static func _steel(world, p) -> void:
	var id := "we_need_steel"
	var gt := QuestSystem.giver_tile(world, "smith_brannoc")
	check(world.gen.town_at(gt, 0) == "cinderholt" and world.object_at(gt) != null, "Brannoc stands in Cinderholt at %s" % gt)
	var vt := QuestSystem.giver_tile(world, "sgt_voss")
	var camp: Array = world.gen.towns["cinderholt"]["camp"]["center"]
	var cc := Vector2i(int(world.gen.towns["cinderholt"]["origin"][0]) + int(camp[0]), int(world.gen.towns["cinderholt"]["origin"][1]) + int(camp[1]))
	check(maxi(absi(vt.x - cc.x), absi(vt.y - cc.y)) <= 14, "Sergeant Voss stands in the Northern Guard camp (%s, camp %s)" % [vt, cc])
	check(QuestSystem.giver_marker(p, "smith_brannoc") == "?" and QuestSystem.giver_marker(p, "sgt_voss") == "", "'?' over Brannoc, nothing over Voss yet")
	var d := _talk(world, p, "smith_brannoc")
	check(d["node"] == "offer" and str(d["text"]).contains("redirected"), "Brannoc's offer notes the shortage despite redirected mines")
	QuestSystem.choose(p, id, "accept")
	for it in ["iron_ore", "coal", "guard_steel_bundle"]:
		p.inventory.remove(it, p.inventory.count(it))
	check(QuestSystem.progress_text(p, id).contains("Iron ore 0/5") and QuestSystem.progress_text(p, id).contains("Coal 0/10"), "journal: %s" % QuestSystem.progress_text(p, id))
	p.inventory.add("iron_ore", 5)
	p.inventory.add("coal", 10)
	check(QuestSystem.giver_marker(p, "smith_brannoc") == "!" and QuestSystem.objective_tile(p, world) == gt, "ore and coal in the pack: '!' over Brannoc, guidance to him")
	QuestSystem.choose(p, id, "advance")
	check(p.inventory.count("iron_ore") == 0 and p.inventory.count("coal") == 0 and p.inventory.count("guard_steel_bundle") == 1, "Brannoc takes the ore and coal and hands over the finished steel")
	check(QuestSystem.state(p, id) == QuestSystem.READY and QuestSystem.giver_marker(p, "sgt_voss") == "!" and QuestSystem.giver_marker(p, "smith_brannoc") == "", "delivery: '!' moves to Sergeant Voss")
	check(QuestSystem.objective_tile(p, world) == vt, "guidance points at the Guard camp")
	check(_talk(world, p, "smith_brannoc")["node"] == "stage_1", "Brannoc reminds you to take it up")
	var m0: int = p.inventory.count(GameData.currency)
	var xp0: int = p.skills.xp.get("smithing", 0)
	var dv := _talk(world, p, "sgt_voss")
	check(dv["quest"] == id and dv["node"] == "stage_1", "Voss's turn-in dialog")
	QuestSystem.choose(p, id, "advance")
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and p.inventory.count("guard_steel_bundle") == 0, "steel delivered: quest complete")
	check(p.inventory.count(GameData.currency) - m0 == 300 and int(p.skills.xp.get("smithing", 0)) - xp0 == 1500, "rewards: 300 marks, 1500 Smithing XP")
	check(QuestSystem.dialog(p, "sgt_voss")["text"] != "" and QuestSystem.dialog(p, "smith_brannoc")["node"] == "completed", "both npcs talk afterwards")


static func _fix(world, p) -> void:
	var id := "can_we_fix_it"
	var gt := QuestSystem.giver_tile(world, "farmer_garrow")
	var ct: Vector2i = world.gen.town_center("cinderholt")
	check(gt.x > -99999 and maxi(absi(gt.x - ct.x), absi(gt.y - ct.y)) < 120 and world.gen.town_at(gt, 0) == "", "Farmer Garrow's farm lies outside Cinderholt (%s)" % gt)
	var props: Array = []
	for o in world.get_chunk(world.chunk_of(gt)).objects.values() + world.get_chunk(world.chunk_of(gt + Vector2i(0, -10))).objects.values():
		if o.def().has("repair_quest") and not props.has(o):
			props.append(o)
	var walls := props.filter(func(o): return o.def_id == "farm_wall_repair")
	var fences := props.filter(func(o): return o.def_id == "farm_fence_repair")
	check(walls.size() >= 3 and fences.size() >= 3, "broken fences (%d) and a damaged wall (%d) on the farm" % [fences.size(), walls.size()])
	check(not walls.is_empty() and walls[0].sprite_id(0) == "farm_wall_damaged" and fences.size() > 0 and world.autotile_piece(fences[0].pos, "fence_rural").y == 1, "before: damaged wall sprite, broken fence row")
	QuestSystem.choose(p, id, "accept")
	p.inventory.remove("plank", p.inventory.count("plank"))
	p.inventory.add("plank", 8)
	check(QuestSystem.giver_marker(p, "farmer_garrow") == "!", "8 planks: '!' over Garrow")
	_talk(world, p, "farmer_garrow")
	QuestSystem.choose(p, id, "advance")
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and p.inventory.count("plank") == 0, "planks handed in")
	world.refresh_repair_views()
	check(walls[0].sprite_id(0) == "farm_wall" and walls[0].display_name() == "Farm wall" and world.autotile_piece(fences[0].pos, "fence_rural").y == 0, "after: wall mended, fences whole")


static func _clip_clop(world, p) -> void:
	var id := "finding_clip_clop"
	var gt := QuestSystem.giver_tile(world, "wenna_tamsin")
	var horse = QuestSystem.follower(world, "clip_clop")
	var den = world.find_nearest_object(horse.tile if horse else Vector2i.ZERO, ["wolf_den"], 12)
	check(horse != null and den != null, "Clip Clop waits by the wolf den")
	check(world.enemies.nearest(den.pos if den else Vector2i.ZERO, ["wolf"], 12) != null, "wolves prowl around the den")
	check(horse != null and CombatRules.can_attack(p, horse, Tick.tick_count) != "", "Clip Clop can't be attacked")
	check(world.gen.town_at(gt, 0) == "" and maxi(absi(gt.x - 58), absi(gt.y)) < 90, "Wenna's farm lies just east of Fenhollow (%s)" % gt)
	QuestSystem.choose(p, id, "accept")
	# 0.3.17 only wolves killed by the den (15 tiles) count
	var dp: Vector2i = den.pos if den else Vector2i.ZERO
	QuestSystem.on_kill(p, "wolf", dp + Vector2i(40, 0))
	QuestSystem.on_kill(p, "wolf")
	check(int(p.quests[id].get("count", 0)) == 0, "0.3.17 wolves killed far from the den (or nowhere) don't count for Clip Clop")
	check(QuestSystem.kill_in_area(p, QuestSystem.current_stage(p, id), dp + Vector2i(14, 3)) and not QuestSystem.kill_in_area(p, QuestSystem.current_stage(p, id), dp + Vector2i(16, 0)), "0.3.17 the den area is 15 tiles")
	var hk: int = _kill(world, p, "wolf", 3, dp)
	check(hk == 3 and int(p.quests[id]["stage"]) == 1, "3 wolves killed by the den: lead him home")
	p.place_at(world.find_free_tile_near(horse.tile + Vector2i(1, 0), 2))
	world.set_focus(p.tile, true)
	WorldTests.ticks(2)
	var start: Vector2i = p.tile
	for i in 6:
		p.place_at(world.find_free_tile_near(p.tile + Vector2i(-1, 0), 1))
		world.set_focus(p.tile, true)
		WorldTests.ticks(1)
	WorldTests.ticks(4)
	check(maxi(absi(horse.tile.x - p.tile.x), absi(horse.tile.y - p.tile.y)) <= 2, "Clip Clop follows you (horse %s, you %s, from %s)" % [horse.tile, p.tile, start])
	check(QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS, "not home yet")
	_talk(world, p, "wenna_tamsin")
	WorldTests.ticks(4)
	check(QuestSystem.state(p, id) == QuestSystem.READY and QuestSystem.giver_marker(p, "wenna_tamsin") == "!", "Clip Clop home with you: '!' over Wenna")
	check(QuestSystem.dialog(p, "wenna_tamsin")["node"] == "stage_1", "Wenna's turn-in dialog")
	QuestSystem.choose(p, id, "advance")
	WorldTests.ticks(2)
	var pad: Vector2i = world.gen.site_point("tamsin_farm", "paddock")
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and maxi(absi(horse.home.x - pad.x), absi(horse.home.y - pad.y)) <= 3, "Clip Clop lives in the Tamsin paddock now (%s)" % horse.tile)


static func _rats(world, p) -> void:
	var id := "a_dead_rat"
	var gt := QuestSystem.giver_tile(world, "old_mabel")
	check(world.gen.village_at(gt, 0) == "millbrook", "Old Mabel stands in Millbrook at %s" % gt)
	check(QuestSystem.giver_marker(p, "old_mabel") == "?", "'?' over Mabel")
	QuestSystem.choose(p, id, "accept")
	var nest := Vector2i(0, 0)
	for c in GameData.camps:
		if c.get("enemy", "") == "giant_rat" and "Dead Rat" in str(c.get("note", "")):
			nest = Vector2i(int(c["at"][0]), int(c["at"][1]))
	var rq: Dictionary = {}
	for q in QuestSystem.cfg().get("quests", []):
		if q.get("id", "") == id:
			rq = q
	var enc: Dictionary = rq.get("encounter", {}).get("rat_mother", {})
	var so: Array = QuestSystem.cfg().get("sites", {}).get(str(enc.get("site", "")), {}).get("origin", [0, 0])
	var want_at: Array = [int(so[0]) + int(enc.get("at", [0, 0])[0]), int(so[1]) + int(enc.get("at", [0, 0])[1])]
	check(world.gen.village_at(nest, 0) == "" and world.gen.village_at(nest, 12) == "millbrook", "the rat nest sits just outside Millbrook (%s)" % nest)
	check(_kill(world, p, "giant_rat", 6, nest) == 6 and int(p.quests[id]["stage"]) == 1, "6 giant rats: back to Mabel")
	check(QuestSystem.giver_marker(p, "old_mabel") == "!" and _talk(world, p, "old_mabel")["node"] == "stage_1", "Mabel asks about the big one")
	QuestSystem.choose(p, id, "advance")
	var mom = world.enemies.nearest(nest, ["rat_mother"], 40)
	var hole = world.find_nearest_object(mom.tile if mom else nest, ["rat_den_entrance"], 6)
	var camp_at: Array = []
	for c in GameData.camps:
		if c.get("enemy", "") == "rat_mother":
			camp_at = c["at"]
	check(hole != null and camp_at == want_at, "Rat Mother waits by the rat-den entrance; her spot comes from the quest's encounter data (%s)" % str(camp_at))
	check(mom != null and str(mom.def.get("sprite", "")) == "rat_mother" and float(mom.def.get("scale", 1)) == 1.0 and mom.max_hp > 30, "the Rat Mother wears her own 48x48 sprite (no scaled rat) and is tough")
	check(QuestSystem.objective(p, world).get("kind", "") in ["enemy", "area"], "guidance points at the Rat Mother")
	check(_kill(world, p, "rat_mother", 1, nest) == 1 and QuestSystem.state(p, id) == QuestSystem.READY, "Rat Mother slain: back to Mabel")
	var m0: int = p.inventory.count(GameData.currency)
	_talk(world, p, "old_mabel")
	QuestSystem.choose(p, id, "advance")
	check(QuestSystem.state(p, id) == QuestSystem.COMPLETED and p.inventory.count(GameData.currency) - m0 == 120, "rats done: 120 marks")


## 0.3.16 Map Tester (2026-10-23) fixes.
static func _map_tester(world) -> void:
	var gen: WorldGen = world.gen
	for pr in [["fenhollow", Vector2i(6, -36)], ["cinderholt", Vector2i(296, -200)]]:
		var sp: Vector2i = gen.town_spawn(pr[0])
		var goal: Vector2i = pr[1]
		var best := goal
		for r in 4:   # nearest walkable tile of the reported pocket
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if best == goal and world.is_blocked(goal):
						var q := goal + Vector2i(dx, dy)
						if not world.is_blocked(q):
							best = q
		check(not world.is_blocked(best) and not Pathfinder.find_path(world, sp, [best], best, 20000).is_empty(), "%s: the pocket by %s is reachable now (%s)" % [pr[0], goal, best])
	var legacy := 0
	for bid in gen.building_order:
		var b: Dictionary = gen.buildings[bid]
		for wt in DayNight.window_tiles(world, b, 2):
			if gen.object_id_at(wt) != "stained_glass":
				legacy += 1
	check(legacy == 0, "no building anywhere gets the legacy orange night-window overlay (%d)" % legacy)
	for c in [Vector2i(149, 135), Vector2i(164, 135), Vector2i(164, 127), Vector2i(277, -26), Vector2i(292, -26), Vector2i(292, -18)]:
		var b2: Dictionary = gen.building_at(c)
		if not b2.is_empty():
			check(DayNight.window_tiles(world, b2, 2).is_empty(), "%s: no legacy window glow" % b2["id"])
	var ta: Dictionary = GameData.load_json("res://data/town_art.json")["buildings"] if GameData.has_method("load_json") else JSON.parse_string(FileAccess.get_file_as_string("res://data/town_art.json"))["buildings"]
	for k in ["v3_smithy_large", "v3_elijah_tomb"]:
		var np_: String = str(ta.get(k, {}).get("night", ""))
		check(np_ != "" and FileAccess.file_exists(np_), "%s has a night layer (%s)" % [k, np_])
	var blk := func(q: Vector2i) -> bool: return gen.tile_at(q.x, q.y) in [WorldGen.TileType.CLIFF_FACE, WorldGen.TileType.CLIFF_LIP, WorldGen.TileType.CLIFF_FOOT]
	var lone := []
	var n := 0
	for y in range(-120, 120):
		for x in range(240, 480):
			var q := Vector2i(x, y)
			if not blk.call(q):
				continue
			n += 1
			var orth := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				orth = orth or blk.call(q + d)
			var diag := 0
			for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				diag += int(blk.call(q + d))
			if diag == 1 and not orth:   # a corner-only stub (diagonal runs are drawn with diagonal pieces and stay)
				lone.append(q)
	check(n > 100 and lone.is_empty() and not blk.call(Vector2i(360, 41)), "no blocking cliff stub (face, lip or foot) hangs off a run by one corner (%d scanned, lone %s)" % [n, str(lone.slice(0, 5))])


## 0.3.17 the Rat Mother plays her 2-frame bite strip on each attack, then walks again.
static func _bite(world, p) -> void:
	var rm = null
	for e in world.enemies.enemies:
		if e.kind == "rat_mother":
			rm = e
			break
	if rm != null and rm.dead:
		rm._respawn()   # an earlier quest test may have killed her
	if rm == null:
		check(false, "0.3.17 a Rat Mother to test the bite")
		return
	var keep_hp: int = p.hp
	rm.target = p
	rm._attack(Tick.tick_count)
	p.hp = keep_hp
	check(rm.is_biting(), "0.3.17 a Rat Mother attack starts the bite animation")
	rm._process(0.01)
	var sp: Sprite2D = rm._sprite
	check(sp.hframes == 2 and sp.texture != null and sp.texture.get_width() == 96 and sp.frame == 0, "0.3.17 bite: wind-up frame of the 96x48 strip (%d frames, frame %d)" % [sp.hframes, sp.frame])
	rm._process(0.2)
	check(rm.is_biting() and sp.frame == 1, "0.3.17 bite: lunge frame next")
	rm._process(0.2)
	check(not rm.is_biting() and sp.hframes == 4 and sp.texture.get_width() == 192, "0.3.17 bite ends: back on the 4-frame walk sheet")
	rm.target = null
