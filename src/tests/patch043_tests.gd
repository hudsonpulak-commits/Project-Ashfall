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
	var spots := [Vector2i(169, -94), Vector2i(166, -88)]
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
	world.set_focus(Vector2i(169, -94), true)
	var root = world.chunk_views.get(World.chunk_of(Vector2i(169, -94)))
	var mods := {}
	if root:
		for ch in root.get_children():
			if ch is TileMapLayer and (ch as TileMapLayer).modulate != Color.WHITE:
				mods[(ch as TileMapLayer).modulate] = true
	check(mods.size() == 1 and mods.has(World.GROUND_MOOD), "all tinted ground layers at 169,-94 share GROUND_MOOD (%s)" % str(mods.keys()))
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
