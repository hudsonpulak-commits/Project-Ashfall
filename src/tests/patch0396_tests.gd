class_name Patch0396Tests
extends RefCounted
## 0.3.9.6 texture pass (designer "0.3.9.7"): stone road / dark cobble variant
## strips, see-through moat bridge joins + inner corners, minimap colours.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func _img(cat: String, id: String) -> Image:
	var img := GameData.texture(cat, id).get_image()
	if img.is_compressed():
		img.decompress()
	return img


static func _avg(img: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 255:
				r += c.r8; g += c.g8; b += c.b8; n += 1
	return Color8(roundi(r / n), roundi(g / n), roundi(b / n)) if n > 0 else Color.MAGENTA


static func run(_main, world, _p) -> void:
	# --- variant strips: the tileset gets one tile per 16 px of strip width ---
	var bad := []
	for id in ["road_stone", "cobble", "cobble_dark"]:
		var t := WorldGen.TILE_NAMES.find(id)
		var w := GameData.texture("tiles", id).get_width()
		if t < 0 or world.variants_for(t) != w / 16 or w / 16 != 4:
			bad.append("%s: %d px -> %d variants" % [id, w, world.variants_for(t) if t >= 0 else -1])
	check(bad.is_empty(), "textures: road_stone, cobble, cobble_dark are 4-variant strips and the tileset has all 4 %s" % [bad])
	# deterministic + stable per cell, and all 4 variants actually used
	var seen := {}
	var stable := true
	for y in 40:
		for x in 40:
			var v1 := int(world.gen.hash01(x, y, 7) * 4) % 4
			var v2 := int(world.gen.hash01(x, y, 7) * 4) % 4
			stable = stable and v1 == v2
			seen[v1] = true
	check(stable and seen.size() == 4, "textures: the variant is a pure function of the cell (no flicker), all 4 used (%d)" % seen.size())
	# transitions keep the 16x16-grid 256-frame layout
	var tb := []
	for id in ["road_stone", "cobble", "cobble_dark"]:
		var img := _img("transitions", id)
		if img.get_width() != 256 or img.get_height() != 256:
			tb.append(id)
	check(tb.is_empty(), "textures: road_stone/cobble/cobble_dark transitions are 256x256 (16x16 frames) %s" % [tb])
	# --- moat: banks opaque under the see-through joins/corners; no void ---
	var mb := _img("autotile", "moat_border")
	var mc := _img("autotile", "moat_border_corners")
	var holes := []
	for m in 16:
		for y in 16:
			for x in 16:
				if mb.get_pixel(m * 16 + x, y).a8 != 255:
					holes.append("bank %d (%d,%d)" % [m, x, y])
					break
	var see_through := 0
	for k in 4:
		for y in 16:
			for x in 16:
				if mb.get_pixel((16 + k) * 16 + x, y).a8 == 0:
					see_through += 1
				if mc.get_pixel(k * 16 + x, y).a8 == 0:
					see_through += 1
	check(holes.is_empty(), "moat: every bank piece (layer 2, under the joins/corners) is fully opaque - no hole to the void %s" % [holes.slice(0, 4)])
	check(see_through > 0, "moat: bridge joins and inner corners are see-through overlays (%d clear px)" % see_through)
	# a moat tile next to a bridge: the bank (open toward the bridge) + exactly one join on top
	var nm := func(q: Vector2i) -> String:
		if q == Vector2i.ZERO:
			return "moat"
		if q == Vector2i(1, 0):
			return "bridge"
		if q == Vector2i(-1, 0):
			return "moat"
		return "grass"
	var cells: Array = world.overlay_cells(Vector2i.ZERO, nm)
	var banks := cells.filter(func(c): return c[0] == 2)
	var joins := cells.filter(func(c): return c[0] == 3)
	check(banks.size() == 1 and banks[0][2].x == 0b1010 and joins.size() == 1 and joins[0][2].x == 17,
		"moat: next to a bridge the open bank draws under one bridge join (no double join) %s" % [cells])
	# --- minimap colours = texture average ---
	var mm := []
	for id in ["road_stone", "cobble", "cobble_dark", "moat"]:
		var want := _avg(_img("tiles", id))
		var got := Color(GameData.sprite_def("tiles", id).get("minimap_color", "#ff00ff"))
		if absi(want.r8 - got.r8) > 2 or absi(want.g8 - got.g8) > 2 or absi(want.b8 - got.b8) > 2:
			mm.append("%s %s vs avg %s" % [id, got.to_html(false), want.to_html(false)])
	check(mm.is_empty(), "minimap: road_stone, cobble, cobble_dark, moat use their texture's average colour %s" % [mm])
