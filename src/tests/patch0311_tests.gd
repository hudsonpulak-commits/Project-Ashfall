class_name Patch0311Tests
extends RefCounted
## 0.3.11 stage 2 portion 1: round walled Highfen from the designer's layered
## art (walk-in buildings whose upper storeys + roof fade together), plus the
## cliff fixes: diagonal gaps closed, new cliff look (face south, rims elsewhere).


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world, p) -> void:
	var gen: WorldGen = world.gen
	# ---- cliffs: diagonal gaps
	var gaps := 0
	var fills := 0
	var cliffs := 0
	var blk := func(q: Vector2i) -> bool: return gen.tile_at(q.x, q.y) in [WorldGen.TileType.CLIFF_FACE, WorldGen.TileType.CLIFF_LIP]
	for y in range(-260, 260, 3):
		for x in range(-260, 260, 3):
			var q := Vector2i(x, y)
			if not blk.call(q):
				continue
			cliffs += 1
			for d in [Vector2i(1, 1), Vector2i(1, -1)]:
				var o: Vector2i = q + d
				if blk.call(o) and not blk.call(Vector2i(o.x, q.y)) and not blk.call(Vector2i(q.x, o.y)):
					var a := Vector2i(o.x, q.y)
					var b := Vector2i(q.x, o.y)
					gaps += 1
					# a left-open gap is only allowed by stairs/roads, and no diagonal step may cross it
					if Pathfinder.diag_ok(world, a, b - a):
						fills -= 1000
				if gen.cliff_gap_fill(o) or gen.cliff_gap_fill(q + Vector2i(d.x, 0)):
					fills += 1
	check(cliffs > 50 and fills >= 0, "0.3.11 cliff tiles touching only at a corner never leave a walkable diagonal gap (%d cliffs sampled, %d corner pairs left by stairs/roads)" % [cliffs, gaps])
	# synthetic: two blocked orthogonals forbid the diagonal step
	var f0 := Vector2i(1 << 16, 1 << 16)
	check(not Pathfinder.diag_ok(_FakeWorld.new([f0 + Vector2i(1, 0), f0 + Vector2i(0, 1)]), f0, Vector2i(1, 1)), "no diagonal step between two blocked tiles")
	# a filled corner cell blocks and gets an inner-corner piece
	var filled := Vector2i(1 << 30, 0)
	for y in range(-260, 260):
		for x in range(-260, 260, 2):
			if gen.tile_at(x, y) == WorldGen.TileType.CLIFF_LIP and gen.cliff_mask(Vector2i(x, y)) == 0 and gen.cliff_low_diag(Vector2i(x, y)) >= 0:
				filled = Vector2i(x, y)
				break
		if filled.x != 1 << 30:
			break
	check(filled.x != 1 << 30 and world.is_blocked(filled) and str(world.cliff_pieces(filled, "cliff_lip", ["", "", "", ""])[-1][0]).begins_with("cliff_corner_inner_"),
		"diagonal cliff gaps are filled with a blocking inner-corner cliff (%s)" % str(filled))
	# ---- cliffs: the designer's tiles (normal + cinder sets)
	var slots := ["cliff_face_s_a", "cliff_face_s_b", "cliff_face_s_c", "cliff_face_s_d", "cliff_rim_n", "cliff_rim_e", "cliff_rim_w",
		"cliff_rim_n_b", "cliff_rim_e_b", "cliff_rim_w_b", "cliff_stairs", "cliff_shadow", "cliff_top", "cliff_top_dirt"]
	for d in ["ne", "nw", "se", "sw"]:
		slots.append("cliff_corner_outer_" + d)
		slots.append("cliff_corner_inner_" + d)
	var have := slots.filter(func(k): return world._overlay_src.has("autotile/" + k) and world._overlay_src.has("autotile/cinder_" + k))
	check(have.size() == slots.size(), "designer cliff tiles registered, normal + cinder (%d/%d)" % [have.size(), slots.size()])
	var face := Vector2i(1 << 30, 0)
	var rim := Vector2i(1 << 30, 0)
	var foot_ok := true
	var nfaces := 0
	for y in range(-260, 260):
		for x in range(-260, 260, 2):
			var t := gen.tile_at(x, y)
			if t == WorldGen.TileType.CLIFF_FACE:
				nfaces += 1
				# 2 clear rows below every south face: a blocked overhang cell, then the shadow row
				foot_ok = foot_ok and gen.tile_at(x, y + 1) == WorldGen.TileType.CLIFF_FOOT and not (gen.tile_at(x, y + 2) in WorldGen.BLOCKING_TILES and gen.object_id_at(Vector2i(x, y + 2)) == "")
				if face.x == 1 << 30 and gen.cliff_mask(Vector2i(x, y)) == 4:
					face = Vector2i(x, y)
			if rim.x == 1 << 30 and t == WorldGen.TileType.CLIFF_LIP and gen.cliff_mask(Vector2i(x, y)) == 1:
				rim = Vector2i(x, y)
	check(nfaces > 0 and foot_ok, "every south face hangs into a blocked cell with a clear shadow row below (%d faces)" % nfaces)
	var fp: Array = world.cliff_pieces(face, "cliff_face", []) if face.x != 1 << 30 else []
	var bp: Array = world.cliff_pieces(face + Vector2i(0, 1), "cliff_foot", ["cliff_face"]) if face.x != 1 << 30 else []
	check(fp.size() == 1 and str(fp[0][0]).begins_with("cliff_face_s_") and fp[0][1] == 0 and bp.size() == 1 and bp[0][0] == fp[0][0] and bp[0][1] == 1,
		"south edges draw the 16x32 face over the edge cell and the cell below (%s)" % str(fp))
	var rp: Array = world.cliff_pieces(rim, "cliff_lip", []) if rim.x != 1 << 30 else []
	check(rp.size() == 1 and str(rp[0][0]).begins_with("cliff_rim_n") and world.cliff_base_tile(rim, WorldGen.TileType.CLIFF_LIP) in WorldGen.GRASS_TILES,
		"north edges draw the thin rim over region ground")
	var cin := Vector2i(300, -300)
	check(world.cliff_palette(cin) == "cinder_" and world.cliff_palette(gen.town_center("fenhollow")) == "", "the Cinder region uses the cinder cliff set")
	# ---- Highfen
	var hf: Dictionary = gen.towns["highfen"]
	var hc := gen.town_center("highfen")
	var pal: Dictionary = gen.buildings.get("highfen_palace", {})
	var pc: Vector2i = (pal["rect"] as Rect2i).get_center() if not pal.is_empty() else Vector2i(9999, 0)
	var fnt: WorldObject = null
	world.set_focus(hc, true)
	fnt = world.find_nearest_object(hc, ["hf_fountain"], 6)
	check(not pal.is_empty() and absi(pc.x - hc.x) <= 3 and pc.y < hc.y and pal.get("art", "") == "v3_keep" and fnt != null,
		"Highfen: the palace (throne room) stands on the north side of the central plaza, the fountain at its centre")
	var guild: Dictionary = gen.buildings.get("highfen_guild", {})
	var gin := Vector2i(1 << 30, 0)
	if not guild.is_empty():
		var gr: Rect2i = guild["rect"]
		for y in range(gr.position.y, gr.end.y):
			for x in range(gr.position.x, gr.end.x):
				if gen.is_inside(Vector2i(x, y), guild) and not (Vector2i(x, y) in guild["doors"]) and gin.x == 1 << 30:
					gin = Vector2i(x, y)
	check(gin.x != 1 << 30 and main.music_area(gin) == "guild" and ((guild["rect"] as Rect2i).get_center() - hc).length() < 17,
		"the Guild of Knights is inside the walls and plays the guild music")
	var inside_w := 0
	var outside_w := 0
	var arts := 0
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if b["town"] != "highfen":
			continue
		arts += int(b.has("art"))
		var dd := ((b["rect"] as Rect2i).get_center() - hc).length()
		if b["kind"] == "house":
			if dd > 19:
				outside_w += 1
			else:
				inside_w += 1
	check(arts >= 30 and outside_w >= 15, "Highfen: %d layered-art buildings, %d houses ring the outside of the wall (%d inside)" % [arts, outside_w, inside_w])
	for id in ["highfen_bank", "highfen_cook", "highfen_general", "highfen_player", "highfen_house", "highfen_church"]:
		var b: Dictionary = gen.buildings.get(id, {})
		# 0.3.13 Highfen v4: the larger v4 buildings fill the band freed by the dropped outer ring road (< 26 = inside the wall)
		check(not b.is_empty() and ((b["rect"] as Rect2i).get_center() - hc).length() < 26, "%s relocated inside the city wall" % id)
	# walking in fades the uppers and roof together, no scene change
	var bv: BuildingsView = world.buildings_view
	var hb: Dictionary = gen.buildings["highfen_guild"]
	var keep: Vector2i = p.tile
	world.set_focus(hb["doors"][0], true)
	p.place_at(hb["doors"][0])
	bv.step(5.0)
	var fg: Node2D = bv._roofs["highfen_guild"]
	var n_fade := fg.get_child_count()
	check(bv.roof_alpha("highfen_guild") == 0.0 and not fg.visible and n_fade == 3, "in the guild doorway the 2 upper storeys + roof fade out together (%d layers)" % n_fade)
	p.place_at(hb["doors"][0] + Vector2i(0, 3))
	bv.step(5.0)
	check(bv.roof_alpha("highfen_guild") == 1.0 and fg.visible, "walking out brings them back")
	p.place_at(keep)
	world.set_focus(keep, true)
	var cob := 0
	for y in range(-30, 31):
		for x in range(-30, 31):
			if gen.tile_at(hc.x + x, hc.y + y) in [WorldGen.TileType.COBBLE, WorldGen.TileType.ROAD_STONE]:
				cob += 1
	check(str(hf.get("art", {}).get("ground_decal", "")).ends_with("ground_decal.png") and cob > 400, "Highfen's roads, rings and plaza are cobble tiles (%d) under the designer's 45-degree cobble autotile" % cob)
	var hroofs := []   # 0.3.13 Fenhollow has gate roofs too: only Highfen's count here
	for i in bv._gate_roofs.size():
		if str((bv._gate_roofs[i][0] as Sprite2D).name).contains("_highfen_"):
			hroofs.append(i)
	var gr_n: int = hroofs.size()
	var sg: Array = hf["gate_walls"]["south"]
	p.place_at(Vector2i(int(hf["origin"][0]) + int(sg[0][0]), int(hf["origin"][1]) + int(sg[0][1])))
	bv.step(5.0)
	var faded := 0
	for i in hroofs:
		if bv.gate_roof_alpha(i) == 0.0:
			faded += 1
	check(gr_n == 4 and faded == 1, "Highfen's 4 gatehouse roofs: standing in the S passage fades only that roof (%d/%d)" % [faded, gr_n])
	# 0.3.11 v3.1b the wall ring walked in collision: an 8-connected flood from the plaza (diagonal steps
	# allowed unless both orthogonal tiles block, like Pathfinder.diag_ok) is sealed with all 4 gates
	# closed, and gets outside through each gate on its own; the visual walk is the generator's ring_qa
	var org := Vector2i(int(hf["origin"][0]), int(hf["origin"][1]))
	var gts: Dictionary = hf.get("gate_tiles", {})
	var sealed := _ring_flood(world, hc, org, gts, "")
	var opens := 0
	for g in gts.keys():
		if _ring_flood(world, hc, org, gts, g):
			opens += 1
	var rq: Dictionary = hf.get("ring_qa", {})
	check(gts.size() == 4 and not sealed and opens == 4, "Highfen's wall ring has no collision holes or diagonal slip-throughs: sealed with the gates shut, open through each of the 4 gates (%d/4)" % opens)
	check(int(rq.get("samples", 0)) > 1000 and int(rq.get("gap_count", -1)) == 0 and (rq.get("gates", []) as Array).size() == 4, "Highfen's wall ring reads as one continuous wall: %d centreline samples, %d gaps, openings only at the 4 gates" % [int(rq.get("samples", 0)), int(rq.get("gap_count", -1))])


static func _ring_flood(world, start: Vector2i, org: Vector2i, gts: Dictionary, open_gate: String) -> bool:
	var shut := {}
	for g in gts.keys():
		if g != open_gate:
			for t in gts[g]:
				shut[org + Vector2i(int(t[0]), int(t[1]))] = true
	var blk := func(q: Vector2i) -> bool: return shut.has(q) or (world.is_blocked(q) and q != start)
	var seen := {start: true}
	var q := [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		if absi(c.x - start.x) > 36 or absi(c.y - start.y) > 32:
			return true
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n := c + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or seen.has(n) or blk.call(n):
					continue
				if dx != 0 and dy != 0 and blk.call(c + Vector2i(dx, 0)) and blk.call(c + Vector2i(0, dy)):
					continue
				seen[n] = true
				q.append(n)
	return false


class _FakeWorld:
	var blocked: Array
	func _init(b: Array) -> void:
		blocked = b
	func is_blocked(q: Vector2i) -> bool:
		return q in blocked
