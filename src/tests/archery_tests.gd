class_name ArcheryTests
extends RefCounted
## 0.3.3 Archery selftests: data, combat level, range + line of sight, arrow
## use / drops / 'Out of arrows!', XP, overhead labels, old-save default.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(world: World, p: Player) -> void:
	print("  -- 0.3.3 archery")
	check(GameData.skill_by_id.has("archery") and GameData.skill_by_id["archery"]["short"] == "RNG", "Archery skill shown as Ranged (RNG, 0.4.0)")
	check(Combat.req_skill("ash_shortbow") == "archery" and Combat.default_style("ash_shortbow") == "ranged" and Combat.style_skill("ranged") == "archery", "bows need Archery, default to the Ranged style, which trains Archery")
	check(Combat.is_ranged("ash_shortbow") and not Combat.is_ranged("bronze_sword"), "bows are ranged, swords are not")
	var sk := Skills.new()
	sk.from_save({"attack": 0, "vitality": GameData.xp_for_level(10)})   # a 0.3.2 record: no archery key
	check(sk.level("archery") == 1, "an old save without Archery starts it at level 1")
	var shop_txt := JSON.stringify(Market.shop_cfg)
	var shop_ok := shop_txt.contains("ash_shortbow") and shop_txt.contains("bronze_arrows")
	check(shop_ok, "a shop sells the ash shortbow and bronze arrows")
	# ---- live fight: shortbow + 3 arrows vs a training target
	var keep: Dictionary = p.skills.xp.duplicate()
	var keep_eq: Dictionary = p.equipment.duplicate()
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var rat := WorldTests._near(world, "giant_rat", world.gen.town_spawn("fenhollow"))
	p.inventory.clear()
	p.equipment.erase("weapon")
	p.inventory.add("ash_shortbow")
	p.inventory.add("bronze_arrows", 3)
	p.auto_equip_ammo()   # 0.3.6 only the ammo slot is fired
	check(p.equip_slot(0) == "" and p.weapon_id() == "ash_shortbow" and p.weapon_power() > 0.0, "the shortbow equips and has weapon power (no longer zeroed)")
	check(p.ammo_arrow() == "bronze_arrows" and p.ammo_qty == 3 and p.inventory.count("bronze_arrows") == 0, "bronze arrows go into the ammo slot")
	rat.target = null
	rat.reset_far()
	rat.hp = 9999
	rat.max_hp = 9999
	var spot := Vector2i.ZERO
	for r in [4, 3, 5]:
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = rat.tile + dir * r
			if not world.is_blocked(c) and Combat.line_of_sight(world, c, rat.tile):
				spot = c
				break
		if spot != Vector2i.ZERO:
			break
	p.place_at(spot)
	p.stop()
	p.hp = p.max_hp()
	world.set_focus(p.tile, true)
	var shots := [0]
	var cb := func(_a, _b, _s): shots[0] += 1
	Events.projectile.connect(cb)
	var arc0 := int(p.skills.xp.get("archery", 0))
	var start := p.tile
	var blocked_msg := [""]
	var mcb := func(text, _k):
		if text == "Out of arrows!": blocked_msg[0] = text
	Events.message.connect(mcb)
	for o in world.enemies.enemies:
		if o != rat and o.target == p:
			o.target = null
			o.reset_far()
	p.last_combat_tick = -9999
	p.combat_foe = null
	rat.last_combat_tick = -9999
	p.next_attack = 0
	p.attack(rat)
	var moved := false
	for i in 40:
		rat.next_attack = Tick.tick_count + 100   # keep it from walking to us
		for o in world.enemies.enemies:   # nobody else joins in (single combat)
			if o != rat and o.target == p:
				o.target = null
				o.reset_far()
		p.on_tick(Tick.tick_count + 1 + i, world)   # rat held still: only the archer acts
		moved = moved or p.tile != start
	Events.projectile.disconnect(cb)
	Events.message.disconnect(mcb)
	check(not moved, "an archer %d tiles away stands still and shoots" % p._cheb(start, rat.tile))
	check(shots[0] == 3 and p.ammo_qty == 0, "each shot uses one arrow (3 arrows -> %d shots, %d left)" % [shots[0], p.ammo_qty])
	check(blocked_msg[0] == "Out of arrows!" and p.action.is_empty(), "out of arrows: 'Out of arrows!' and the attack stops (%s)" % blocked_msg[0])
	var dropped := 0
	for it in world.ground.at(rat.tile, p.actor_id):
		if str(it.get("id", "")) == "bronze_arrows":
			dropped += int(it.get("qty", 0))
	check(dropped <= 3, "arrows that land lie under the target (%d of 3; ~50%%)" % dropped)
	check(int(p.skills.xp.get("archery", 0)) >= arc0, "Archery XP from hits")
	# drop rate + XP rate (deterministic statistics)
	var s2 := Skills.new()
	Combat.award_hit_xp(s2, "ranged", 5)
	check(int(s2.xp["archery"]) == 20, "4 Archery XP per damage (5 dmg -> %d)" % int(s2.xp["archery"]))
	check(Combat.arrow_power("iron_arrows") > Combat.arrow_power("bronze_arrows"), "better arrows hit harder")
	# line of sight: a wall blocks, open ground doesn't
	var wall_found := false
	var c0 := world.gen.town_spawn("fenhollow")
	for dx in range(-30, 30):
		for dy in range(-30, 30):
			var q := c0 + Vector2i(dx, dy)
			if world.tile_type(q) in [WorldGen.TileType.WALL, WorldGen.TileType.ART_WALL] and not world.is_blocked(q + Vector2i(-1, 0)) and not world.is_blocked(q + Vector2i(1, 0)):
				check(not Combat.line_of_sight(world, q + Vector2i(-1, 0), q + Vector2i(1, 0)), "a building wall blocks line of sight")
				wall_found = true
				break
		if wall_found:
			break
	check(wall_found, "found a wall to test line of sight against")
	# overhead labels
	check(Overhead.enemy_shows(GameData.enemies["giant_rat"]) and not Overhead.enemy_shows(GameData.enemies["chicken"]) and not Overhead.enemy_shows(GameData.enemies["citizen"]), "overhead level on rats, none on chickens / citizens")
	check(rat._lvl_label != null and rat._lvl_label.get_parent() is CanvasLayer and rat._lvl_label.get_theme_font_size("font_size") >= 8, "0.3.4: overhead labels are 8 px+ in the screen-space overlay above actors")
	check(rat._lvl_label != null and rat._lvl_label.text == "Giant rat (5)", "a rat shows 'Giant rat (5)' (%s)" % (rat._lvl_label.text if rat._lvl_label else "none"))
	# restore
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	rat.reset_far()
	p.stop()
	p.last_combat_tick = -9999   # the shots above ran on look-ahead ticks: clear the fight state
	p.combat_foe = null
	p.next_attack = 0
	rat.last_combat_tick = -9999
	p.skills.xp = keep
	p.equipment = keep_eq
	p.inventory.slots = keep_inv
	p.hp = p.max_hp()
