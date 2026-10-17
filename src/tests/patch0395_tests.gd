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
	_tier_colours()


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Most common opaque colour other than the outline ink (the darkest colour).
static func _dominant(img: Image) -> Color:
	var counts := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 255:
				var k := Color8(c.r8, c.g8, c.b8)
				counts[k] = int(counts.get(k, 0)) + 1
	var ink := Color.WHITE
	for k in counts.keys():
		if _lum(k) < _lum(ink):
			ink = k
	var best := Color.TRANSPARENT
	var n := -1
	for k in counts.keys():
		if k != ink and int(counts[k]) > n:
			n = int(counts[k]); best = k
	return best


static func _palette(img: Image) -> Dictionary:
	var out := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a8 == 255:
				out[Color8(c.r8, c.g8, c.b8).to_html(false)] = true
	return out


## 0.3.9.5 same tier = same colours in every facing: for each tier and armour
## slot the dominant colour of the side, front and back sheets has the same hue
## (within 25 deg) or all are greys (saturation < 0.15), and every front/back
## armour colour of a tier is one of that tier's side armour colours.
static func _tier_colours() -> void:
	var hue_bad := []
	var pal_bad := []
	for t in [1, 2, 3, 4]:
		var side_pal := {}
		var fb_pal := {}
		for slot in ["head", "body", "legs"]:
			var sid := "gear_%s_%d" % [slot, t]
			if GameData.sprite_def("actors", sid).is_empty():
				continue
			var doms := []
			for d in ["side", "down", "up"]:
				var img := _img(sid, d)
				doms.append(_dominant(img))
				if d == "side":
					side_pal.merge(_palette(img))
				else:
					fb_pal.merge(_palette(img))
			var c0: Color = doms[0]
			for c in doms.slice(1):
				var grey: bool = c0.s < 0.15 and c.s < 0.15
				var dh: float = absf(c0.h - c.h) * 360.0
				dh = minf(dh, 360.0 - dh)
				if not grey and (c0.s < 0.15 or c.s < 0.15 or dh > 25.0):
					hue_bad.append("T%d %s side #%s vs #%s" % [t, slot, c0.to_html(false), c.to_html(false)])
		for k in fb_pal.keys():
			if not side_pal.has(k):
				pal_bad.append("T%d #%s" % [t, k])
	check(hue_bad.is_empty(), "gear tiers: the dominant hue of each armour piece matches across side/front/back %s" % [hue_bad.slice(0, 6)])
	check(pal_bad.is_empty(), "gear tiers: front/back armour colours are the tier's side colours %s" % [pal_bad.slice(0, 6)])
