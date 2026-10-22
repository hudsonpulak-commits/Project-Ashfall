class_name Patch039Tests
extends RefCounted
## 0.3.9: autotiled fences / walls / moat, floor transitions, 4-way facing, title art.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.9 autotile / transitions / facing / title")
	var gen: WorldGen = world.gen
	# --- autotile mask -> piece ---
	var set_of := func(cells: Array) -> Callable:
		return func(q: Vector2i) -> bool: return q in cells
	var o := Vector2i(0, 0)
	var cases := {
		"post": [], "end": [Vector2i(1, 0)], "straight_h": [Vector2i(1, 0), Vector2i(-1, 0)],
		"straight_v": [Vector2i(0, -1), Vector2i(0, 1)], "corner": [Vector2i(0, -1), Vector2i(1, 0)],
		"t": [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)], "cross": [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)],
		"diag_slash": [Vector2i(1, -1), Vector2i(-1, 1)], "diag_back": [Vector2i(-1, -1), Vector2i(1, 1)]}
	var bad := []
	for want in cases.keys():
		var got := Autotile.piece_name(Autotile.piece_at(o, set_of.call(cases[want])))
		if got != want:
			bad.append("%s->%s" % [want, got])
	check(bad.is_empty(), "autotile: neighbour mask picks post/end/straight/corner/T/4-way/diagonal pieces %s" % [bad])
	check(Autotile.piece_at(o, set_of.call([Vector2i(1, 0), Vector2i(0, 1)])) == Autotile.E | Autotile.S, "autotile: E+S joins -> the SE corner frame (6)")
	check(Autotile.piece_at(o, set_of.call([Vector2i(1, 0), Vector2i(1, 1)])) == Autotile.E, "autotile: an orthogonal join wins over a diagonal")
	var nb := 0
	for i in 2000:
		if Autotile.is_broken(Vector2i(i, i * 7 % 113)):
			nb += 1
	check(nb > 220 and nb < 380 and Autotile.is_broken(Vector2i(5, 9)) == Autotile.is_broken(Vector2i(5, 9)), "autotile: ~15%% of rural fence pieces are broken, deterministically (%d/2000)" % nb)
	check(GameData.sprite_def("autotile", "fence_rural").get("broken_row", 0) == 1 and not GameData.sprite_def("autotile", "wall_capital_wall").has("broken_row"), "autotile: rural fences have a broken row, city walls none")
	# --- transitions ---
	var g := "grass"
	check(Autotile.transition_frame("road_stone", ["road_stone", g, g, g, g, g, g, g]) == 1, "transition: a road to the north -> N edge frame")
	check(Autotile.transition_frame("road_stone", [g, g, g, g, g, "road_stone", g, g]) == 2 << 4, "transition: a road only at NE -> NE corner frame")
	check(Autotile.transition_frame("road_stone", ["road_stone", g, g, g, g, "road_stone", g, g]) == 1, "transition: a corner next to an edge is folded into the edge")
	check(Autotile.overlays_for("grass", ["dirt", "road_stone", "sand", g, g, g, g, "water"]) == ["dirt", "road_stone"], "transition: up to 2 higher-priority floors, highest drawn last; lower ones and water never blend")
	check(Autotile.overlays_for("water", ["grass", g, g, g, g, g, g, g]).is_empty() and Autotile.overlays_for("stone_wall", [g, g, g, g, g, g, g, g]).is_empty(), "transition: water and walls never get blends")
	var nmf := func(names: Dictionary) -> Callable:
		return func(q: Vector2i) -> String: return names.get(q, "grass")
	var cells := world.overlay_cells(o, nmf.call({o: "grass", Vector2i(0, -1): "dirt"}))
	check(cells.size() == 1 and cells[0][0] == 0 and cells[0][2] == Vector2i(1, 0), "transition: the world places a dirt N-edge overlay on grass (%s)" % [cells])
	# --- moat / walls on the tile overlay ---
	var mo := {o: "moat", Vector2i(1, 0): "moat", Vector2i(0, 1): "moat", Vector2i(-1, 0): "bridge", Vector2i(0, -1): "moat_edge"}
	cells = world.overlay_cells(o, nmf.call(mo))
	var moat_piece := -1
	var join := -1
	for c in cells:
		if c[0] == 2: moat_piece = c[2].x
		if c[0] == 3: join = c[2].x
	check(moat_piece == (Autotile.E | Autotile.S | Autotile.W) and join == 16 + 3, "moat: bank on the north (T piece) + a bridge join on the west (%s)" % [cells])
	# 0.3.11 v3.1 Highfen's capital_wall is drawn by the designer's 45-degree wall art: no tile caps
	check(world.overlay_cells(o, nmf.call({o: "capital_wall", Vector2i(1, 0): "capital_wall"})).filter(func(c): return c[0] == 2).is_empty(), "walls: capital_wall gets no tile caps (art-drawn)")
	var wl := {o: "stone_wall", Vector2i(1, 0): "stone_wall", Vector2i(0, 1): "stone_wall"}
	cells = world.overlay_cells(o, nmf.call(wl))
	check(cells.size() == 1 and cells[0][0] == 2 and cells[0][2] == Vector2i(Autotile.E | Autotile.S, 0), "walls: a city wall corner gets the corner cap (%s)" % [cells])
	cells = world.overlay_cells(o, nmf.call({o: "stone_wall", Vector2i(1, -1): "stone_wall", Vector2i(-1, 1): "stone_wall"}))
	check(cells.size() == 1 and cells[0][2] == Vector2i(Autotile.DIAG_SLASH, 0), "walls: a 45-degree wall run gets the diagonal cap")
	# 0.3.11b Highfen's wall is tiled again (capital_wall, autotiled) with round towers along it
	var hc := gen.town_center(gen.capital)
	var ring_n := 0
	var towers := 0
	for y in range(-36, 37):
		for x in range(-36, 37):
			if gen.tile_at(hc.x + x, hc.y + y) == WorldGen.TileType.CAPITAL_WALL:
				ring_n += 1
			if str(gen._town_objects.get(hc + Vector2i(x, y), "")) == "hf_wall_tower":
				towers += 1
	check(ring_n > 300 and towers >= 8, "walls: Highfen's thick tiled wall (%d capital_wall tiles) with %d towers" % [ring_n, towers])
	# --- fences in the world: pens and road fences ---
	var pen_corner := Vector2i(1 << 30, 0)
	var road_f: Array = []
	for q in gen._town_objects.keys():
		if gen.autotile_group_at(q) == "fence_rural" and gen.autotile_group_at(q + Vector2i(1, 0)) != "" and gen.autotile_group_at(q + Vector2i(0, 1)) != "" and gen.autotile_group_at(q + Vector2i(-1, 0)) == "" and gen.autotile_group_at(q + Vector2i(0, -1)) == "":
			pen_corner = q
			break
	check(pen_corner.x != 1 << 30 and world.autotile_piece(pen_corner, "fence_rural").x == (Autotile.E | Autotile.S), "fences: a pen's top-left fence is a corner piece (%s)" % pen_corner)
	var vert := 0
	var horiz := 0
	var run_ok := true
	for q in gen.road_decor.keys():
		if gen.road_decor[q] != "road_fence":
			continue
		road_f.append(q)
		var pc := world.autotile_piece(q, "fence_rural").x
		if pc == 5: vert += 1
		if pc == 10: horiz += 1
		if pc in [5, 10]:
			# the run is parallel to the road: the road runs the same way beside it
			var along := Vector2i(0, 1) if pc == 5 else Vector2i(1, 0)
			var side := Vector2i(along.y, along.x)
			var near := false
			for k in range(1, 5):
				for sg in [1, -1]:
					if gen.road_tiles.has(q + side * k * sg) and gen.road_tiles.has(q + side * k * sg + along):
						near = true
			run_ok = run_ok and near
	check(vert > 5 and horiz > 5 and run_ok, "road fences run parallel to their road: %d vertical, %d horizontal straights" % [vert, horiz])
	var at_junction := 0
	# junction tiles: centre tiles shared by 2 roads; fences keep >= 3 tiles away
	var owner := {}
	var shared: Array = []
	var lists: Array = []
	for k in gen.roads.keys():
		var ab: PackedStringArray = str(k).split("|")
		if ab[0] < ab[1] and (ab[0] == gen.capital or ab[1] == gen.capital):
			lists.append(gen.roads[k])
	for vid in gen.village_roads.keys():
		lists.append(gen.village_roads[vid])
	for li in lists.size():
		for t in lists[li]:
			if owner.has(t) and owner[t] != li:
				shared.append(t)
			owner[t] = li
	for q in road_f:
		for s in shared:
			if maxi(absi(q.x - s.x), absi(q.y - s.y)) <= 2:
				at_junction += 1
				break
	check(at_junction == 0, "road fences leave the junctions open (%d fences within 2 tiles of a junction)" % at_junction)
	if not road_f.is_empty():
		var f: Vector2i = road_f[0]
		check(world.is_blocked(f) and (Combat.line_of_sight(world, f + Vector2i(0, -2), f + Vector2i(0, 2)) or Combat.line_of_sight(world, f + Vector2i(-2, 0), f + Vector2i(2, 0))), "road fences still block walking; arrows fly over (%s)" % f)
	# --- facing ---
	var fc := Facing.new()
	fc.observe(0, 0, -1)
	check(fc.dir == "up" and Facing.sheet_for(fc) == "back", "facing: moving up shows the back")
	fc.observe(0, 0, 1)
	check(fc.dir == "down" and Facing.sheet_for(fc) == "front", "facing: moving down shows the front")
	fc.observe(-1, 0, 0)
	check(fc.dir == "side" and fc.left, "facing: moving left shows the side, mirrored")
	fc.observe(1, 0, 0)
	check(fc.dir == "side" and not fc.left, "facing: moving right shows the side")
	fc.observe(2, 0, -1)
	check(fc.dir == "side", "facing: a mostly-sideways diagonal keeps the side sheet")
	var missing := 0
	for sid in GameData.sprites["actors"].keys():
		var dp: Dictionary = GameData.sprite_def("actors", sid).get("dir_paths", {})
		for k in ["up", "down"]:
			if not ResourceLoader.exists(str(dp.get(k, ""))):
				missing += 1
	check(missing == 0, "facing: every actor and gear sheet has front and back sheets (%d missing)" % missing)
	p.facing.dir = "up"
	p._process(0.016)
	var gear_ok := true
	for l in p._layers.values():
		if (l as Sprite2D).visible:
			gear_ok = gear_ok and (l as Sprite2D).texture == GameData.actor_texture(str(l.get_meta("sprite_id")), "up")
	check(p._sprite.texture == GameData.actor_texture("player", "up") and not p._sprite.flip_h and gear_ok, "facing: the player's body and gear layers switch to the back sheet")
	p.facing.dir = "side"
	p._process(0.016)
	check(p._sprite.texture == GameData.texture("actors", "player"), "facing: back to the side sheet")
	# --- title art slot ---
	check(MainMenu.has_title_art() and GameData.sprite_def("ui", "title_bg")["path"] == "res://assets/ui/title_bg.png", "title: the data-driven title art slot is filled")
