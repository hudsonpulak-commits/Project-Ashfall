class_name Patch0394Tests
extends RefCounted
## 0.3.9.4: side shields are fully opaque inside their outline, leave no gap
## against the body, and sit on the correct side (left hand: far side facing
## right, near side facing left).


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


## Cells of a w x h frame that are not solid and not reachable from the border.
static func enclosed(w: int, h: int, solid: Callable) -> Array:
	var seen := {}
	var q: Array = []
	for x in w:
		q.append(Vector2i(x, 0)); q.append(Vector2i(x, h - 1))
	for y in h:
		q.append(Vector2i(0, y)); q.append(Vector2i(w - 1, y))
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		if seen.has(c) or c.x < 0 or c.y < 0 or c.x >= w or c.y >= h or solid.call(c.x, c.y):
			continue
		seen[c] = true
		q.append(c + Vector2i(1, 0)); q.append(c + Vector2i(-1, 0)); q.append(c + Vector2i(0, 1)); q.append(c + Vector2i(0, -1))
	var out: Array = []
	for y in h:
		for x in w:
			if not seen.has(Vector2i(x, y)) and not solid.call(x, y):
				out.append(Vector2i(x, y))
	return out


static func _img(sid: String, dir: String) -> Image:
	var img := GameData.actor_texture(sid, dir).get_image()
	if img.is_compressed():
		img.decompress()
	return img


static func run(_main, _world, _p) -> void:
	var body := _img("player", "side")
	var bfs := GameData.frame_size("actors", "player")
	var nb := GameData.frame_count("actors", "player")
	var semi := []
	var holes := []
	var gaps := []
	for sid in GameData.sprites["actors"].keys():
		var s := str(sid)
		if not (s.begins_with("gear_shield") or (s.begins_with("gear_item_") and s.contains("shield"))):
			continue
		var img := _img(s, "right")
		var fs := GameData.frame_size("actors", s)
		for f in GameData.frame_count("actors", s):
			var o := f * fs.x
			var bo := mini(f, nb - 1) * bfs.x
			for y in fs.y:
				for x in fs.x:
					var a := img.get_pixel(o + x, y).a8
					if a > 0 and a < 255:
						semi.append("%s f%d (%d,%d)" % [s, f, x, y])
			var h1 := enclosed(fs.x, fs.y, func(x, y): return img.get_pixel(o + x, y).a8 == 255)
			if not h1.is_empty():
				holes.append("%s f%d %s" % [s, f, h1])
			var h2 := enclosed(fs.x, fs.y, func(x, y): return img.get_pixel(o + x, y).a8 == 255 or (x < bfs.x and y < bfs.y and body.get_pixel(bo + x, y).a8 > 128))
			if not h2.is_empty():
				gaps.append("%s f%d %s" % [s, f, h2])
	check(semi.is_empty(), "shields: side sheets have no semi-transparent pixels %s" % [semi.slice(0, 6)])
	check(holes.is_empty(), "shields: every side frame is fully opaque inside its outline (flood fill from outside) %s" % [holes.slice(0, 6)])
	check(gaps.is_empty(), "shields: no ground shows through between the body and the side shield %s" % [gaps.slice(0, 6)])
	var r := Actor.gear_layer_plan("side", false)
	var l := Actor.gear_layer_plan("side", true)
	var u := Actor.gear_layer_plan("up", false)
	var d := Actor.gear_layer_plan("down", false)
	check(r["under"] == ["shield"] and r["over"][-1] == "weapon" and l["under"] == ["weapon"] and l["over"][-1] == "shield"
		and u["under"] == ["shield"] and d["under"].is_empty() and d["over"] == Actor.GEAR_DRAW_ORDER,
		"gear order: facing right shield under the body; facing left shield on top, weapon under; back shield under; front unchanged")
