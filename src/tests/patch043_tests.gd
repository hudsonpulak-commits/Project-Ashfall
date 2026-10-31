extends RefCounted
## 0.4.3: ground layers share one mood tint (no bright cliff / shore strips beside dimmed
## grass), and the dirt road art has no repeating horizontal rut bands.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.4.3 ground tint audit, dirt road bands")
	var gen := world.gen
	var bad := 0
	var seen := 0
	var spots := [Vector2i(169, -94), Vector2i(166, -88), Vector2i(136, -113)]
	for vd in gen.villages.values():
		if (vd as Dictionary).has("center"):
			spots.append(vd["center"])
	for s in spots:
		for dy in range(-12, 13):
			for dx in range(-12, 13):
				var q: Vector2i = s + Vector2i(dx, dy)
				var nm: String = WorldGen.TILE_NAMES[gen.tile_at(q.x, q.y)]
				var ground: bool = nm.begins_with("cliff") or nm.begins_with("shore") or nm.begins_with("boardwalk") \
					or nm in ["grass", "dirt", "path", "road_dirt", "road", "sand", "marsh", "water", "shallow"]
				if not ground:
					continue
				for cell in world.overlay_cells(q, func(r: Vector2i) -> String: return WorldGen.TILE_NAMES[gen.tile_at(r.x, r.y)]):
					if cell[0] in [World.OVL_NAMES.find("walls"), World.OVL_NAMES.find("corners"), World.OVL_NAMES.find("joins"), World.OVL_NAMES.find("autotile")]:
						if nm.begins_with("cliff") or nm.begins_with("shore") or nm.begins_with("boardwalk"):
							bad += 1
					seen += 1
	check(seen > 0, "the tint audit sampled overlay cells (%d)" % seen)
	check(bad == 0, "no cliff / shore / boardwalk overlay piece lands on an untinted layer (%d found)" % bad)
	# rendered layers: every tinted chunk layer uses exactly GROUND_MOOD (adjacent layers same brightness)
	for sp in [Vector2i(169, -94), Vector2i(136, -113)]:
		world.set_focus(sp, true)
		var root = world.chunk_views.get(World.chunk_of(sp))
		var mods := {}
		var lone := 0
		if root:
			for ch in root.get_children():
				if ch is TileMapLayer:
					if (ch as TileMapLayer).modulate != Color.WHITE:
						mods[(ch as TileMapLayer).modulate] = true
					elif String(ch.name) in ["trans0", "trans1", "g_autotile", "g_joins"]:
						lone += 1
		check(mods.size() == 1 and mods.has(World.GROUND_MOOD) and lone == 0, "all ground layers (base, sand/shore/water edges, transitions) at %s share GROUND_MOOD (%s, %d untinted)" % [sp, str(mods.keys()), lone])
	# dirt road art: no row band darker than the tile mean by a wide margin
	var img := (load("res://assets/sprites/tiles/variants/road_dirt_x4.png") as Texture2D).get_image()
	var rows := []
	var tot := 0.0
	for y in 16:
		var r := 0.0
		for x in img.get_width():
			r += img.get_pixel(x, y).get_luminance()
		r /= img.get_width()
		rows.append(r)
		tot += r
	var mean := tot / 16.0
	var worst := 0.0
	for r in rows:
		worst = maxf(worst, mean - r)
	check(worst < 0.06, "road_dirt rows have no dark rut band (worst row %.3f below mean)" % worst)
	_specks(gen)


## 0.4.3 whole-map audit: no lone tile of one terrain inside another (grass specks
## in sand shores, sand dots in grass), counted against the raw generator.
static func _specks(gen: WorldGen) -> void:
	var b: Rect2i = gen.bounds()
	var t0 := Time.get_ticks_msec()
	var removed := 0
	var left := 0
	var grass_in_sand := 0
	for y in range(b.position.y + 1, b.end.y - 1):
		for x in range(b.position.x + 1, b.end.x - 1):
			var t := gen._terrain_at(x, y)
			if t == WorldGen.TileType.WATER:
				continue
			if t != gen._terr_lvl(x, y, 0):
				removed += 1
			var f := gen._terrain_family(t)
			var lone := true
			var sand_n := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := gen._terrain_at(x + d.x, y + d.y)
				sand_n += int(n == WorldGen.TileType.SAND)
				if gen._terrain_family(n) == f or n == WorldGen.TileType.WATER:
					lone = false
			left += int(lone)
			grass_in_sand += int(f == WorldGen.TileType.GRASS and sand_n == 4)
	print("    speck audit: %d lone tiles cleaned, %d left, %d grass-in-sand (%d ms)" % [removed, left, grass_in_sand, Time.get_ticks_msec() - t0])
	check(removed > 0, "the despeckle cleaned lone terrain tiles across the map (%d)" % removed)
	check(left == 0, "no lone single land tile of one terrain inside another anywhere on the map (thin beach strips against water allowed) (%d)" % left)
	check(grass_in_sand == 0, "no grass tile sits alone inside a sand shore (%d)" % grass_in_sand)
