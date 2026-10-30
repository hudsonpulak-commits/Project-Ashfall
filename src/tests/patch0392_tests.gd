class_name Patch0392Tests
extends RefCounted
## 0.3.9.2: designer art overhaul - moat inner corners, whole (uncropped)
## creature front/back frames.

const DIRS8 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


## Name lookup around a moat tile at (0,0): `set` maps offsets to tile names,
## everything else is grass.
static func _nm(set: Dictionary, centre := "moat") -> Callable:
	return func(q: Vector2i) -> String:
		if q == Vector2i.ZERO:
			return centre
		return set.get(q, "grass")


static func _corners(world, set: Dictionary) -> Array:
	return world.overlay_cells(Vector2i.ZERO, _nm(set)).filter(func(c): return c[0] == 4).map(func(c): return c[2].x)


static func run(_main, world, _p) -> void:
	# --- moat inner corners ---
	check(not GameData.sprite_def("autotile", "moat_border_corners").is_empty() and ResourceLoader.exists(GameData.sprite_def("autotile", "moat_border_corners")["path"]), "moat: inner-corner sheet registered and present")
	var want := {0: [Vector2i(0, -1), Vector2i(1, 0)], 1: [Vector2i(1, 0), Vector2i(0, 1)], 2: [Vector2i(0, 1), Vector2i(-1, 0)], 3: [Vector2i(-1, 0), Vector2i(0, -1)]}
	var ok4 := true
	for f in want.keys():
		var set := {}
		for d in want[f]:
			set[d] = "moat"
		var got := _corners(world, set)
		if got != [f]:
			ok4 = false
			printerr("    moat corner %d -> %s" % [f, got])
	check(ok4, "moat: an inner corner (NE/SE/SW/NW) where both sides are moat and the diagonal is land")
	var all_moat := {}
	for d in DIRS8:
		all_moat[d] = "moat"
	var bridge_diag := {Vector2i(0, -1): "moat", Vector2i(1, 0): "moat", Vector2i(1, -1): "bridge"}
	var straight := {Vector2i(0, -1): "moat", Vector2i(0, 1): "moat"}
	check(_corners(world, all_moat).is_empty() and _corners(world, bridge_diag).is_empty() and _corners(world, straight).is_empty(),
		"moat: no inner corner in open moat, next to a bridge diagonal, or along a straight bank")

	# --- creature front/back frames are whole (not cropped / sliced) ---
	# Up to 1 opaque pixel may touch the left/right frame edge (goblin ears).
	var bad := []
	for sid in ["cow", "chicken", "wolf", "giant_rat", "slime", "goblin", "goblin_warlord", "cinder_brute"]:
		if GameData.sprite_def("actors", sid).is_empty() or sid in Patch0391Tests.RESTYLE_CHIBI:
			continue
		var sw := Patch0391Tests._width(Patch0391Tests._frame(sid, "side"))
		for dir in ["down", "up"]:
			var img := GameData.actor_texture(sid, dir).get_image()
			if img.is_compressed():
				img.decompress()
			var fs := GameData.frame_size("actors", sid)
			for f in GameData.frame_count("actors", sid):
				var fr := img.get_region(Rect2i(f * fs.x, 0, fs.x, fs.y))
				var edge := 0
				for y in fs.y:
					edge += int(Patch0391Tests._opaque(fr, 0, y)) + int(Patch0391Tests._opaque(fr, fs.x - 1, y))
				var w := Patch0391Tests._width(fr)
				if edge > 1 or w < maxi(6, sw / 2):
					bad.append("%s %s f%d (w %d, side %d, edge px %d)" % [sid, dir, f, w, sw, edge])
	check(bad.is_empty(), "creatures: front/back frames are whole - at most 1 px touches the frame edge, at least half the side width %s" % [bad])
	# --- protected art and the exact title image ---
	var prot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/protected_art.json")).get("files", {})
	check(prot.size() > 400 and prot.has("assets/ui/title_bg.png"), "art: hand-drawn files are listed in protected_art.json (%d)" % prot.size())
