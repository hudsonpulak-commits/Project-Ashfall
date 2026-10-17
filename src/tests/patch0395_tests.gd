class_name Patch0395Tests
extends RefCounted
## 0.3.9.5: every helmet is a full-face helmet in every facing. With any helmet
## on, no skin-tone pixel of the body (player or npc) shows in the head rows of
## the composite, facing down, left, right or up; helmet sheets are alpha 0/255
## only and leave no enclosed gap against the body; the head layer always draws
## over the body.

const HEAD_ROWS := 12
const FACINGS := ["down", "left", "right", "up"]


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func skinish(c: Color) -> bool:
	var r := c.r8
	var g := c.g8
	var b := c.b8
	return c.a8 > 128 and r > 150 and r > g and g > b and r - b > 40


static func _img(sid: String, dir: String) -> Image:
	var img := GameData.actor_texture(sid, dir).get_image()
	if img.is_compressed():
		img.decompress()
	return img


static func _sheet_dir(facing: String) -> String:
	return "side" if facing == "left" or facing == "right" else facing


static func run(_main, _world, _p) -> void:
	var helms := {}
	for sid in GameData.sprites["actors"].keys():
		if str(sid).begins_with("gear_head_"):
			helms[str(sid)] = true
	for iid in GameData.items.keys():
		if str(GameData.item(iid).get("gear", {}).get("slot", "")) == "head":
			var s := Actor.gear_sprite_for(str(iid), "head")
			if s != "":
				helms[s] = true
	var skin := []
	var semi := []
	var gaps := []
	var n := 0
	for hid in helms.keys():
		for facing in FACINGS:
			var d := _sheet_dir(facing)
			var helm := _img(hid, d)
			var fs := GameData.frame_size("actors", hid)
			for y in helm.get_height():
				for x in helm.get_width():
					var a := helm.get_pixel(x, y).a8
					if a > 0 and a < 255:
						semi.append("%s/%s" % [hid, d])
						break
			for bid in ["player", "npc"]:
				var body := _img(bid, d)
				var bfs := GameData.frame_size("actors", bid)
				var nb := GameData.frame_count("actors", bid)
				for f in GameData.frame_count("actors", hid):
					n += 1
					var ho := f * fs.x
					var bo := mini(f, nb - 1) * bfs.x
					var left: bool = facing == "left"
					# composite pixel at screen (x, y): mirrored for left like flip_h
					var px := func(x: int, y: int) -> Color:
						var sx: int = (fs.x - 1 - x) if left else x
						var hc := helm.get_pixel(ho + sx, y)
						return hc if hc.a8 == 255 else body.get_pixel(bo + sx, y)
					# a skin-tone pixel that comes from the BODY (the helmet does not cover
					# it); a tan leather helmet's own colours are not skin
					var bad := 0
					for y in mini(HEAD_ROWS, fs.y):
						for x in fs.x:
							var sx: int = (fs.x - 1 - x) if left else x
							if helm.get_pixel(ho + sx, y).a8 < 255 and skinish(body.get_pixel(bo + sx, y)):
								bad += 1
					if bad > 0:
						skin.append("%s+%s %s f%d: %d px" % [hid, bid, facing, f, bad])
					var solid := func(x: int, y: int) -> bool: return px.call(x, y).a8 > 0
					var enc := Patch0394Tests.enclosed(fs.x, fs.y, solid).filter(func(c): return c.y < HEAD_ROWS)
					if not enc.is_empty():
						gaps.append("%s+%s %s f%d %s" % [hid, bid, facing, f, enc])
	check(helms.size() >= 4, "helmets: every head-slot item has a helmet sheet (%d sheets)" % helms.size())
	check(skin.is_empty(), "helmets: full face - no body skin in the head rows with any helmet, 4 facings, player + npc (%d composites) %s" % [n, skin.slice(0, 6)])
	check(semi.is_empty(), "helmets: sheets are fully opaque (alpha 0/255 only) %s" % [semi])
	check(gaps.is_empty(), "helmets: no enclosed gap between helmet and body in the head rows %s" % [gaps.slice(0, 6)])
	var under_ok := true
	for d in ["down", "side", "up"]:
		for l in [false, true]:
			if "head" in Actor.gear_layer_plan(d, l)["under"]:
				under_ok = false
	check(under_ok, "helmets: the head layer draws over the body in every facing")
