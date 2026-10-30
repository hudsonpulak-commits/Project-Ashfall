extends RefCounted
## 0.3.20: villages match the Oct 29 lore, the wolf quest keeps its id,
## story props, and the words "hero" / "chosen one" / "Ash Demon" stay out
## of player-facing text. The internal adventurer id "hero" is not a label.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.20 villages, lore, scene life")
	check(str(ProjectSettings.get_setting("application/config/version")) in ["0.3.20", "0.4.0", "0.4.1"], "version is 0.3.20 or later (0.4.0)")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	check((preset.contains("version/code=37") or preset.contains("version/code=38") or preset.contains("version/code=39")), "Android versionCode is 37 or later")
	_villages(world)
	_quest_and_save(p)
	_story(world)
	_life(world, p)
	_facing(p)


static func _villages(world: World) -> void:
	var gen: WorldGen = world.gen
	var hf: Vector2i = gen.town_center("highfen")
	var ch: Vector2i = gen.town_center("cinderholt")
	var sm: Vector2i = gen.town_center("saltmere")
	var mb: Vector2i = gen.town_center("millbrook")
	var bb: Vector2i = gen.town_center("barrowby")
	var ox: Vector2i = gen.town_center("oxley")
	var hf_r: Rect2i = gen._town_rects["highfen"]
	check(mb.y < hf.y and mb.y > ch.y, "Millbrook is north of Highfen and south of Cinderholt (%s)" % mb)
	var seg := _dist_to_seg(mb, hf, ch)
	var to_fen := Vector2(mb - gen.town_center("fenhollow")).length()
	check(seg < to_fen, "Millbrook sits on the Highfen-Cinderholt side, not back toward Fenhollow (%.0f vs %.0f)" % [seg, to_fen])
	check(gen.village_roads.has("millbrook") and not (gen.village_roads["millbrook"] as Array).is_empty(), "Millbrook has a road")
	check(bb.y > hf_r.end.y and bb.y < sm.y and bb.y > ox.y and bb.y > mb.y, "Barrowby is the southernmost village, between Highfen and Saltmere (%s)" % bb)
	check(gen.village_roads.has("barrowby") and not (gen.village_roads["barrowby"] as Array).is_empty(), "Barrowby has a road")
	check(ox.x > hf_r.end.x and absi(ox.y - hf.y) < 80, "Oxley is east of Highfen, near the capital's latitude (%s)" % ox)
	check(gen.village_roads.has("oxley") and not (gen.village_roads["oxley"] as Array).is_empty(), "Oxley has a road")
	var linked := true
	for vid in ["millbrook", "barrowby", "oxley"]:
		var road: Array = gen.village_roads[vid]
		var hit := false
		for tid in gen.town_order:
			for g in gen.gate_outsides(tid):
				if maxi(absi(g.x - road[-1].x), absi(g.y - road[-1].y)) <= 10:
					hit = true
		linked = linked and hit and not world.is_blocked(road[0])
	check(linked, "each moved village's road reaches a town gate and is walkable")


static func _dist_to_seg(p: Vector2i, a: Vector2i, b: Vector2i) -> float:
	var ab := Vector2(b - a)
	var t := clampf(Vector2(p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return Vector2(p - a).distance_to(ab * t)


static func _quest_and_save(p: Player) -> void:
	var q: Dictionary = {}
	for quest in QuestSystem.cfg().get("quests", []):
		if str(quest.get("id", "")) == "wolf_pelts":
			q = quest
	check(str(q.get("name", "")) == "Night of 1000 Howls" and str(q.get("id", "")) == "wolf_pelts", "Wolf Pelts shows as Night of 1000 Howls and keeps its id")
	var stages: Array = q.get("stages", [])
	check(stages.size() == 1 and not JSON.stringify(q).to_lower().contains("dire"), "the Dire Wolf half is not in this update (%d stages)" % stages.size())
	var old := {"version": 9, "player": {"tile": [150, -140], "vaults": {"fenhollow": {"n": 3}}, "quests": {"wolf_pelts": {"stage": 1}}}, "world": {"seed": 7331}}
	var mig: Dictionary = SaveSystem._migrate(old)
	check(int(mig["version"]) == SaveSystem.SAVE_VERSION and (mig["player"]["tile"] as Array) == [213, -125], "a player left in old Millbrook wakes on the new plaza %s" % str(mig["player"]["tile"]))
	check(int(mig["player"]["vaults"]["fenhollow"]["n"]) == 3 and mig["player"]["quests"].has("wolf_pelts"), "the move leaves the bank and the old wolf_pelts save alone")
	var stay := {"version": 9, "player": {"tile": [200, -140]}, "world": {"seed": 7331}}
	var m2: Dictionary = SaveSystem._migrate(stay)
	check((m2["player"]["tile"] as Array) == [200, -140], "a tile that is still inside Millbrook is not teleported")
	var away := {"version": 9, "player": {"tile": [1, 1]}, "world": {"seed": 7331}}
	var m3: Dictionary = SaveSystem._migrate(away)
	check((m3["player"]["tile"] as Array) == [1, 1], "a player outside the old villages stays put")


static func _story(world: World) -> void:
	var gen: WorldGen = world.gen
	var marks: Dictionary = gen.story_marks
	var flower: Vector2i = marks.get("elijah_flowers", Vector2i(-99999, 0))
	var candle: Vector2i = marks.get("elijah_candles", Vector2i(-99999, 0))
	check(gen.object_id_at(flower) == "tomb_flowers" and gen.object_id_at(candle) == "tomb_candles", "Elijah's tomb has fresh flowers and candles")
	var cart: Vector2i = marks.get("raided_cart", Vector2i(-99999, 0))
	var beside := false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		if gen.road_tiles.has(cart + d):
			beside = true
	check(gen.object_id_at(cart) == "raided_cart" and beside and not gen.road_tiles.has(cart), "a raided trader's cart sits beside a road, not on it")
	var brutes := 0
	var cottages: Array = marks.get("burnt_cottages", [])
	for camp in GameData.camps:
		if str(camp.get("enemy", "")) != "cinder_brute":
			continue
		brutes += 1
		var at := Vector2i(int(camp["at"][0]), int(camp["at"][1]))
		var near := false
		for c in cottages:
			if maxi(absi((c as Vector2i).x - at.x), absi((c as Vector2i).y - at.y)) <= 4:
				near = true
		check(near, "a burnt cottage stands where Cinder brutes roam (%s)" % at)
	check(brutes >= 1 and cottages.size() >= brutes, "every Cinder brute camp has a burnt cottage")
	var mush: Array = marks.get("mushrooms", [])
	var den: Dictionary = gen.quest_sites.get("rat_den", {})
	var o := Vector2i(int(den["origin"][0]), int(den["origin"][1]))
	var mush_ok := mush.size() >= 3
	for m in mush:
		mush_ok = mush_ok and gen.object_id_at(m) == "magic_mushroom" and maxi(absi((m as Vector2i).x - o.x), absi((m as Vector2i).y - o.y)) <= 5
		mush_ok = mush_ok and not gen.road_tiles.has(m)
	check(mush_ok, "glowing mushrooms stand by the rat den, off the road")
	var wagon: Vector2i = marks.get("supply_wagon", Vector2i(-99999, 0))
	var spike: Vector2i = marks.get("spike_barrier", Vector2i(-99999, 0))
	check(gen.object_id_at(wagon) == "supply_wagon" and gen.object_id_at(spike) == "spike_barrier", "the Northern Guard camp has a supply wagon and a spiked barrier")
	var scaffolds: Array = marks.get("scaffolds", [])
	var churches := 0
	for bid in gen.building_order:
		if str(gen.buildings[bid].get("kind", "")) == "church":
			churches += 1
	var plank_ok := scaffolds.size() >= churches and churches >= 3
	for s in scaffolds:
		plank_ok = plank_ok and gen.object_id_at(s) == "scaffold_plank" and not gen.road_tiles.has(s)
	check(plank_ok, "each church has one scaffold plank, off the road (%d)" % scaffolds.size())
	check(str(GameData.object_def("scaffold_plank").get("type", "")) == "scenery" and not bool(GameData.object_def("scaffold_plank").get("blocks", true)), "a scaffold plank is one prop, not a stack of planks")
	var clutter := int(marks.get("clutter", 0))
	var on_road := 0
	for id in ["decor_crate", "decor_barrel", "decor_fence", "decor_flowers", "decor_signpost"]:
		if not GameData.objects.has(id):
			on_road += 1
	var road_clutter := 0
	for sid in gen.town_order + gen.village_order:
		var rr: Rect2i = gen._village_rects[sid] if gen._village_rects.has(sid) else gen._town_rects[sid]
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				var oid := gen.object_id_at(Vector2i(x, y))
				if oid.begins_with("decor_") and (gen.road_tiles.has(Vector2i(x, y)) or gen.tile_at(x, y) in WorldGen.ROAD_SURFACES):
					road_clutter += 1
	check(clutter >= 20 and on_road == 0 and road_clutter == 0, "crates, barrels, fences, flowers and signposts dress the settlements and stay off the roads (%d)" % clutter)


static func _life(world: World, p: Player) -> void:
	var life = world.ambient
	check(life != null and life.birds.size() >= 4 and life.frogs.size() >= 3 and life.butterflies.size() >= 3 and life.smokes.size() >= 4,
		"birds, marsh frogs, meadow butterflies and chimney smoke are in the world (%d %d %d %d)" % [life.birds.size(), life.frogs.size(), life.butterflies.size(), life.smokes.size()])
	var keep := p.tile
	if not life.birds.is_empty():
		var b: Dictionary = life.birds[0]
		var home: Vector2i = b["home"]
		p.place_at(home)
		world.set_focus(home, true)
		life.step(home, 0.2)
		check(bool(b["flee"]) and (b["goal"] as Vector2i) != home, "a bird flees when you walk up to it")
	p.place_at(keep)
	world.set_focus(keep, true)
	var frog_ok := true
	for f in life.frogs:
		var ft: Vector2i = f["home"]
		frog_ok = frog_ok and world.gen.tile_at(ft.x, ft.y) == WorldGen.TileType.MARSH
	check(frog_ok, "frogs sit in the marsh")
	var fly_ok := true
	for bf in life.butterflies:
		var bt: Vector2i = bf["home"]
		fly_ok = fly_ok and world.gen.region_map.region_at(bt) == "central" and world.gen.tile_at(bt.x, bt.y) in WorldGen.GRASS_TILES
	check(fly_ok, "butterflies stay in the central meadows")


static func _facing(p: Player) -> void:
	var blobs: Array = []
	for rel in ["quests.json", "churches.json", "buildings.json", "town_npcs.json", "ai_chatter.json", "villages.json", "objects.json"]:
		blobs.append(FileAccess.get_file_as_string("res://data/" + rel))
	var text := " ".join(blobs)
	var rx := RegEx.new()
	rx.compile("(?i)\\b(hero|heroes|chosen one|ash demon)\\b")
	var bad: Array = []
	# Keys named hero are the internal adventurer id. Strip those, then scan values.
	var cleaned := text.replace("\"hero\"", "\"id\"")
	var hit := rx.search(cleaned)
	while hit:
		bad.append(hit.get_string())
		hit = rx.search(cleaned, hit.get_end())
		if bad.size() > 6:
			break
	check(bad.is_empty(), "player-facing text never says hero, chosen one, or Ash Demon %s" % str(bad))
	check(str(GameData.personas.filter(func(a): return str(a.get("id", "")) == "hero")[0].get("label", "")) == "Adventurer",
		"the internal hero adventurer is labelled Adventurer")
	var idle: String = str(QuestSystem.cfg().get("givers", {}).get("smith_brannoc", {}).get("idle", ""))
	var voss: String = str(QuestSystem.cfg().get("givers", {}).get("sgt_voss", {}).get("idle", ""))
	check(idle.contains("Cindervill") and voss.contains("Cindervill") and not idle.to_lower().contains("ash demon"), "Brannoc and Voss blame the ore shortage on Cindervill")
	var church: String = " ".join(GameData.churches.get("greet", []))
	check(church.contains("lay") and church.contains("Scorch Line") and church.contains("Prayer"), "lay keepers say the head priest is holding the Scorch Line")
	var guards: Array = GameData.town_npcs.get("lore_talk", {}).get("saltmere", {}).get("town_guard", [])
	var gtxt := " ".join(guards).to_lower()
	check(gtxt.contains("old trainer") and gtxt.contains("elijah"), "Saltmere guards remember Elijah as the old trainer")
	var houses: Array = GameData.town_npcs.get("lore_talk", {}).get("highfen", {}).get("house", [])
	var htxt := " ".join(houses)
	check(htxt.contains("Prince Elijah") and htxt.contains("Avery") and htxt.contains("Sophia") and htxt.contains("Kylie") and htxt.contains("Queen Jessica"),
		"Highfen townsfolk gossip about the queen and the children")
