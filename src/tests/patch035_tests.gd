class_name Patch035Tests
extends RefCounted
## 0.3.5: bank buildings replace the open plaza chest, the plaza hearth is gone,
## archery reaches 10 tiles, the dummy pays 3x and blocks its counter-swing.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func bank_of(world: World, tid: String) -> Dictionary:
	for id in world.gen.building_order:
		var b: Dictionary = world.gen.buildings[id]
		if b["town"] == tid and b["kind"] == "bank":
			return b
	return {}


static func run(world: World, p: Player) -> void:
	print("  -- 0.3.5 banks / plaza / archery 10 / dummy")
	for tid in ["fenhollow", "cinderholt", "saltmere"]:
		var b := bank_of(world, tid)
		check(not b.is_empty(), "%s has a bank building" % tid)
		if b.is_empty():
			continue
		var r: Rect2i = b["rect"]
		var chests := 0
		var loose := 0
		var hearths := 0
		for y in range(r.position.y - 30, r.end.y + 30):
			for x in range(r.position.x - 30, r.end.x + 30):
				var o: WorldObject = world.object_at(Vector2i(x, y))
				if o and o.def_id == "bank_chest":
					if r.has_point(o.pos):
						chests += 1
					else:
						loose += 1
		var c := world.gen.town_center(tid)
		for y in range(c.y - 12, c.y + 13):
			for x in range(c.x - 12, c.x + 13):
				var o2: WorldObject = world.object_at(Vector2i(x, y))
				if o2 and o2.def_id == "hearth" and world.gen.building_at(o2.pos).is_empty():
					hearths += 1
		check(chests >= 1 and loose == 0, "%s: bank chest(s) inside the bank (%d), none loose in the plaza (%d)" % [tid, chests, loose])
		check(hearths == 0, "%s: plaza hearth/oven removed (%d left)" % [tid, hearths])
		var door: Vector2i = b["doors"][0]
		var out := door + Vector2i(0, 1)
		var path := Pathfinder.find_path(world, world.gen.town_spawn(tid), [out], out)
		var inner := Pathfinder.find_path(world, out, [b["stand"]], b["stand"])
		check(not world.is_blocked(door) and not path.is_empty() and not inner.is_empty(),
			"%s bank: door walkable, reachable from spawn and the counter stand" % tid)
	# the banker opens the bank
	var fb := bank_of(world, "fenhollow")
	var keeper: WorldObject = world.object_at(fb["keeper_at"])
	var opened := [false]
	var cb := func(): opened[0] = true
	Events.bank_opened.connect(cb)
	p.place_at(world.find_free_tile_near(fb["doors"][0] + Vector2i(0, 1), 2))
	world.set_focus(p.tile, true)
	if keeper:
		p.interact(world, keeper)
	for i in 80:
		WorldTests.ticks(1)
		if opened[0]:
			break
	Events.bank_opened.disconnect(cb)
	check(keeper != null and opened[0], "talking to the banker opens the bank")
	check(Combat.ranged_range() == 10, "0.3.5 archery range is 10 tiles (Chebyshev)")
	# dummy: 3x XP, blocked counter-swing trains Defence, no HP lost
	var dummy: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow"), ["training_dummy"], 60)
	p.hp = p.max_hp()
	var hp0 := p.hp
	var def0 := int(p.skills.xp.get("defence", 0))
	var mxp := int(p.skills.xp.get("vitality", 0))
	p.place_at(world.find_free_tile_near(dummy.pos + Vector2i(0, 1), 2))
	p.interact(world, dummy)
	var blocks := 0
	var def_gain := 0
	var splat0 := [0]
	var scb := func(t, _w, amt): if t == p and amt == 0: splat0[0] += 1
	Events.hitsplat.connect(scb)
	for i in 60:
		WorldTests.ticks(1)
		blocks = maxi(blocks, int(p.action.get("dummy_blocks", 0)))
	Events.hitsplat.disconnect(scb)
	def_gain = int(p.skills.xp.get("defence", 0)) - def0
	check(blocks > 0 and splat0[0] >= blocks and def_gain > 0 and p.hp == hp0,
		"dummy swings back: %d blocks shown, +%d Defence XP, HP %d -> %d (no damage)" % [blocks, def_gain, hp0, p.hp])
	check(Interactions.DUMMY_XP_MULT == 3 and int(p.skills.xp.get("vitality", 0)) > mxp, "dummy pays 3x hit XP (hits land: +%d Vitality)" % (int(p.skills.xp.get("vitality", 0)) - mxp))
	p.stop()
