class_name Patch0393Tests
extends RefCounted
## 0.3.9.3: side-view shields are solid (the 0.3.9.2 side sheets were hollow
## rings - the body silhouette was cut out - so the shield looked transparent).


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(_main, _world, _p) -> void:
	var bad := []
	var body := Patch0391Tests._frame("player", "side")
	for sid in GameData.sprites["actors"].keys():
		var s := str(sid)
		if not (s.begins_with("gear_shield") or (s.begins_with("gear_item_") and s.contains("shield"))):
			continue
		var img := GameData.actor_texture(s, "right").get_image()
		if img.is_compressed():
			img.decompress()
		var fs := GameData.frame_size("actors", s)
		for f in GameData.frame_count("actors", s):
			var fr := img.get_region(Rect2i(f * fs.x, 0, fs.x, fs.y))
			# the shield layer is drawn over the body from the side: every opaque
			# pixel is visible; it must be big and solid where it covers the body
			var shown := 0
			var over_body := 0
			var holes := 0
			for y in fs.y:
				var xs := []
				for x in fs.x:
					if Patch0391Tests._opaque(fr, x, y):
						xs.append(x)
						shown += 1
						if x < body.get_width() and y < body.get_height() and Patch0391Tests._opaque(body, x, y):
							over_body += 1
				if xs.size() >= 2:
					for x in range(xs[0], xs[-1] + 1):
						if not Patch0391Tests._opaque(fr, x, y):
							holes += 1
			if shown < 40 or over_body < 12 or holes > 0:
				bad.append("%s f%d (shown %d, over body %d, holes %d)" % [s, f, shown, over_body, holes])
	check(bad.is_empty(), "shields: the side view is solid and clearly visible (40+ px, 12+ over the body, no holes) for every shield %s" % [bad])
