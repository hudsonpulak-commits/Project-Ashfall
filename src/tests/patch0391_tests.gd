class_name Patch0391Tests
extends RefCounted
## 0.3.9.1: directional sheets (no doubled / mirrored heads or rears), clean
## human fronts, shields hidden on backs, fences only in runs of 3+.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func _frame(sid: String, dir: String) -> Image:
	var tex := GameData.actor_texture(sid, dir)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var fs := GameData.frame_size("actors", sid)
	return img.get_region(Rect2i(0, 0, fs.x, fs.y))


static func _opaque(img: Image, x: int, y: int) -> bool:
	return img.get_pixel(x, y).a > 0.5


## A naive "double": one half of the side frame mirrored onto the other half.
static func _same_as_mirrored_half(view: Image, side: Image, right_half: bool) -> bool:
	var w := side.get_width()
	var diff := 0
	var total := 0
	for y in side.get_height():
		for x in w:
			var sx := x
			if right_half and x < w / 2: sx = w - 1 - x
			if not right_half and x >= w / 2: sx = w - 1 - x
			var a := _opaque(view, x, y)
			var b := _opaque(side, sx, y)
			total += 1 if (a or b) else 0
			diff += 1 if (a != b or (a and not view.get_pixel(x, y).is_equal_approx(side.get_pixel(sx, y)))) else 0
	return total > 0 and diff <= total / 20


static func _width(img: Image) -> int:
	var lo := img.get_width()
	var hi := -1
	for y in img.get_height():
		for x in img.get_width():
			if _opaque(img, x, y):
				lo = mini(lo, x)
				hi = maxi(hi, x)
	return hi - lo + 1


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.9.1 directional sheets / shields / fence runs")
	var gen: WorldGen = world.gen
	# --- every creature/enemy/NPC directional frame: no doubled heads or rears ---
	var bad := []
	var narrow_bad := []
	for sid in GameData.sprites["actors"].keys():
		if str(sid).begins_with("gear_"):
			continue
		var side := _frame(sid, "side")
		var front := _frame(sid, "down")
		var back := _frame(sid, "up")
		var sym := _same_as_mirrored_half(side, side, true)   # a symmetric blob (slime) may keep its side frame
		if not sym:
			if _same_as_mirrored_half(front, side, true) or _same_as_mirrored_half(back, side, false):
				bad.append(sid)
		var fs := GameData.frame_size("actors", sid)
		if fs.x > 16 or fs.y <= 16:   # quadrupeds / small creatures: head-on is narrower than the side
			var blob := front.get_data() == side.get_data() and back.get_data() == side.get_data()   # symmetric blob keeps one view
			if not sym and not blob and (_width(front) >= _width(side) or _width(back) >= _width(side)):
				narrow_bad.append("%s %d/%d/%d" % [sid, _width(side), _width(front), _width(back)])
	check(bad.is_empty(), "sprites: no front/back frame is a mirrored half of the side (2 heads / 2 rears) %s" % [bad])
	check(narrow_bad.is_empty(), "sprites: creatures seen head-on / from behind are narrower than from the side %s" % [narrow_bad])
	var flips: bool = bool(GameData.sprite_def("actors", "cow").get("flip", true))
	var fc := Facing.new()
	fc.observe(0, 0, 1)
	check(flips and fc.dir == "down" and not (fc.left and fc.dir == "side"), "sprites: front/back views are never mirrored (flip only on the side sheet)")
	# --- human fronts: one face, two eyes symmetric about the middle ---
	var eyes_bad := []
	for sid in ["player", "npc", "villager", "citizen", "priest", "town_guard", "keeper_general"]:
		var f := _frame(sid, "down")
		var found := false
		for y in range(0, 12):
			var darks := []
			for x in range(3, 13):
				var c := f.get_pixel(x, y)
				if c.a > 0.5 and c.get_luminance() < 0.2:
					darks.append(x)
			if darks.size() == 2 and darks[0] + darks[1] == 15:
				found = true
				break
		if not found:
			eyes_bad.append(sid)
	check(eyes_bad.is_empty(), "sprites: human front faces have 2 symmetric eyes %s" % [eyes_bad])
	# --- shields: from behind only the edge peeks out, under the body ---
	var peek_bad := []
	for sid in GameData.sprites["actors"].keys():
		if not str(sid).begins_with("gear_shield"):
			continue
		var b := _frame(sid, "up")
		for y in b.get_height():
			for x in range(3, b.get_width()):
				if _opaque(b, x, y):
					peek_bad.append(sid)
					break
			if sid in peek_bad:
				break
	check(peek_bad.is_empty(), "shields: back sheets show only the edge outside the body %s" % [peek_bad])
	var shield_id := ""
	for iid in GameData.items.keys():
		if str(GameData.item(iid).get("gear", {}).get("slot", "")) == "shield":
			shield_id = iid
			break
	if shield_id != "":
		var keep: Dictionary = p.equipment.duplicate() if "equipment" in p else {}
		p.equipment["shield"] = shield_id
		p.facing.dir = "up"
		p._process(0.016)
		var sh: Sprite2D = p._layers.get("shield")
		check(sh != null and sh.get_index() < p._sprite.get_index(), "shields: drawn under the body when the player faces away")
		p.facing.dir = "side"
		p._process(0.016)
		check(sh != null and sh.get_index() > p._sprite.get_index(), "shields: drawn over the body from the side")
		p.equipment = keep
		p._process(0.016)
	# --- fences: every fence is in a 4-connected run of >= 3, never a post or a lone diagonal ---
	var short := []
	var odd := {}
	var seen := {}
	for src in [gen._town_objects, gen.road_decor]:
		for q in src.keys():
			if gen.autotile_group_at(q) != "fence_rural" or seen.has(q):
				continue
			var run := gen.fence_run_at(q)
			for c in run:
				seen[c] = true
				var pc := Autotile.piece_name(world.autotile_piece(c, "fence_rural").x)
				if pc in ["post", "diag_slash", "diag_back"]:
					odd[pc] = int(odd.get(pc, 0)) + 1
			if run.size() < 3:
				short.append("%s x%d" % [q, run.size()])
	check(short.is_empty() and odd.is_empty() and seen.size() > 100, "fences: every fence is a run of 3+ tiles, no lone posts or diagonals (%d fence tiles; short %s; odd %s)" % [seen.size(), short.slice(0, 6), odd])

	# --- every run endpoint is an end piece: a capped end post or a broken end ---
	var ends := 0
	var broken_ends := 0
	var not_end := []
	for q in seen.keys():
		var nbrs := 0
		for dd in Autotile.DIRS4:
			if gen.autotile_group_at(q + dd) == "fence_rural":
				nbrs += 1
		if nbrs != 1:
			continue
		var pc := world.autotile_piece(q, "fence_rural")
		if Autotile.piece_name(pc.x) != "end":
			not_end.append(q)
		ends += 1
		broken_ends += pc.y
	check(not_end.is_empty() and ends > 10 and broken_ends > 0 and broken_ends < ends * 0.5, "fences: every run ends in an end post or a broken end (%d ends, %d broken; bad %s)" % [ends, broken_ends, not_end.slice(0, 4)])
