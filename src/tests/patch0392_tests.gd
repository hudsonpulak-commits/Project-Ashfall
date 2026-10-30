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
	# restyle: moats take the organic shore pass (corners are baked into the 256-frame
	# water_shore sheet), so no separate layer-4 corner pieces are drawn
	var cset := {Vector2i(0, -1): "moat", Vector2i(1, 0): "moat"}
	var cc: Array = world.overlay_cells(Vector2i.ZERO, _nm(cset))
	var shore := cc.filter(func(c): return c[0] == 2)
	check(shore.size() == 1 and _corners(world, cset).is_empty(), "moat: a corner moat cell draws one shore frame from the water_shore pass (no layer-4 corner piece) %s" % [cc])
	var all_moat := {}
	for d in DIRS8:
		all_moat[d] = "moat"
	check(world.overlay_cells(Vector2i.ZERO, _nm(all_moat)).filter(func(c): return c[0] == 2).is_empty(), "moat: open moat (no land around) draws no shore edge")

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
