extends RefCounted
## 0.4.2: the underworld rat den (data/underworld.json) under the Millbrook rat
## hole: organic layout, rats inside, Rat Mother fight below ground, the ladder
## back up, minimap / map, save/load underground, quest log text.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.4.2 underworld rat den")
	var gen := world.gen
	check(gen.dens.has("rat_den"), "the rat den is loaded from data/underworld.json")
	if not gen.dens.has("rat_den"):
		return
	var dd: Dictionary = gen.dens["rat_den"]
	var inner: Rect2i = dd["inner"]
	check(not gen.bounds().intersects(dd["rect"]), "the den pocket lies outside the continent map bounds")
	# organic: plenty of floor, no long straight wall edge
	var floor_n := 0
	var longest := 0
	for y in range(inner.position.y, inner.end.y):
		var run := 0
		for x in range(inner.position.x, inner.end.x):
			var t := gen.tile_at(x, y)
			floor_n += int(t == WorldGen.TileType.DEN_FLOOR)
			var edge := t == WorldGen.TileType.DEN_WALL and gen.tile_at(x, y + 1) == WorldGen.TileType.DEN_FLOOR
			run = run + 1 if edge else 0
			longest = maxi(longest, run)
	check(floor_n > 450, "the den has room to fight (%d floor cells)" % floor_n)
	check(longest <= 12, "den walls wind: longest straight wall face %d cells" % longest)
	check(GameData.tile_color(WorldGen.TileType.DEN_FLOOR) != Color.MAGENTA and GameData.tile_color(WorldGen.TileType.DEN_WALL) != Color.MAGENTA, "den tiles have minimap colours")
	check(WorldGen.TileType.DEN_WALL in WorldGen.BLOCKING_TILES and not (WorldGen.TileType.DEN_FLOOR in WorldGen.BLOCKING_TILES), "den walls block, den floor walks")
	# entrance -> den
	var hole_t: Vector2i = gen.den_entrance("rat_den")
	var hole: WorldObject = world.object_at(hole_t)
	check(hole != null and hole.def_id == "rat_den_entrance" and str(hole.def().get("type", "")) == "travel", "the Millbrook rat hole is a way down (%s)" % hole_t)
	var keep := p.tile
	p.place_at(gen.den_exit_tile("rat_den"))
	world.set_focus(p.tile, true)
	p.action = {"kind": "interact", "pos": hole_t}
	Interactions.perform(p, world, Tick.tick_count)
	check(world.den_at(p.tile) == "rat_den" and p.tile.distance_to(gen.den_arrival("rat_den")) <= 2.0, "climbing down puts you in the den by the ladder (%s)" % p.tile)
	world.set_focus(p.tile, true)
	WorldTests.ticks(1)
	check(DayNight.in_den() and DayNight.tint().v < 0.7, "underground the light is dim and fixed (tint %s)" % DayNight.tint())
	check(main.music_area(p.tile) == "ruins", "underground plays the ruins track")
	check(world.map_pixel(p.tile) == world.map_pixel(hole_t), "the world map shows you at the rat hole while below")
	check(world.den_map_texture("rat_den").get_width() == inner.size.x, "the map panel has a den layout inset")
	var mt := world.minimap_texture(World.chunk_of(p.tile))
	check(mt != null, "the minimap draws den chunks")
	# rats inside + the Rat Mother
	var rats := 0
	var mom: Enemy = null
	for e in world.enemies.enemies:
		if world.den_at(e.home) == "rat_den":
			if e.kind == "giant_rat":
				rats += 1
			elif e.kind == "rat_mother":
				mom = e
	check(rats >= 6, "giant rats live in the den (%d)" % rats)
	check(mom != null and world.den_at(mom.tile) == "rat_den", "the Rat Mother is in the den, not on the surface")
	var on_surface := world.enemies.nearest(hole_t, ["rat_mother"], 60)
	check(on_surface == null, "no Rat Mother waits by the surface hole any more")
	if mom != null:
		var path := Pathfinder.find_path(world, p.tile, Pathfinder.interaction_tiles(mom.tile), mom.tile, 20000)
		check(not path.is_empty(), "a winding way leads from the ladder to the Rat Mother (%d steps)" % path.size())
	# quest guidance from the surface points at the hole
	var qs: Dictionary = {}
	for q in QuestSystem.quests():
		if q["id"] == "a_dead_rat":
			qs = q
	check("rat hole" in str(qs["stages"][2]["text"]) and "den" in str(qs["stages"][2]["text"]), "the quest log sends you down the rat hole")
	check(QuestSystem.spawn_area("rat_mother", hole_t + Vector2i(0, 3)) == hole_t, "from the surface the Rat Mother objective marks the rat hole")
	check(QuestSystem.spawn_area("rat_mother", p.tile) == GameData.den_marker_tile("rat_den", "M"), "below ground the objective marks her chamber")
	# save / load underground
	var q2 := Player.new()
	q2.from_save(p.to_save())
	check(q2.tile == p.tile and world.den_at(q2.tile) == "rat_den" and not world.is_blocked(q2.tile), "a save made in the den loads back in the den")
	q2.free()
	var sv: Dictionary = JSON.parse_string(JSON.stringify(main.build_save()))
	check(SaveSystem.validate(SaveSystem._migrate(sv)) == "" and world.den_at(Vector2i(int(sv["player"]["tile"][0]), int(sv["player"]["tile"][1]))) == "rat_den", "the full save validates with the player underground")
	# ladder back up
	var lad: Vector2i = gen.den_marker("rat_den", "U")
	var lo: WorldObject = world.object_at(lad)
	check(lo != null and lo.def_id == "den_ladder_up", "a ladder leads back up (%s)" % lad)
	p.place_at(lad + Vector2i(0, 1))
	p.action = {"kind": "interact", "pos": lad}
	Interactions.perform(p, world, Tick.tick_count)
	check(world.den_at(p.tile) == "" and p.tile.distance_to(hole_t) <= 3.0, "climbing the ladder brings you out by the rat hole (%s)" % p.tile)
	world.set_focus(p.tile, true)
	WorldTests.ticks(1)
	check(not DayNight.in_den(), "daylight again on the surface")
	p.place_at(keep)
	world.set_focus(p.tile, true)
