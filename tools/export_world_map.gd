extends SceneTree
## Standalone map export (no game code touched). Samples the REAL world
## generator (WorldGen + data/*.json) with the game's default seed and dumps
## raw grids + metadata for tools/render_world_map.py to draw.
##
##   $GODOT --headless --path . --script res://tools/export_world_map.gd -- [--seed=7331] [--out=build/map]
##
## Output: <out>/world_dump.json (meta, towns, roads, camps) and
##         <out>/world_tiles.bin (u8 per tile: tile type, 255 = ocean),
##         <out>/world_objects.bin (u8 per tile: index into meta.object_ids, 0 = none).

const DEFAULT_SEED := 7331   # mirrors src/main.gd DEFAULT_SEED (new games)
var _done := false


func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var seed_v := int(args.get("seed", DEFAULT_SEED))
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://build/map"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gd = root.get_node("GameData")
	var WG = load("res://src/world/world_gen.gd")   # loaded lazily: autoload globals exist only after startup
	var gen = WG.new(seed_v)
	var b: Rect2i = gen.bounds()
	var w: int = b.size.x
	var h: int = b.size.y
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	var objs := PackedByteArray()
	objs.resize(w * h)
	var obj_ids: Array = [""]
	var regs := PackedByteArray()   # 0.3.10 lore region index per tile (meta.region_ids)
	regs.resize(w * h)
	var reg_ids: Array = gen.region_map.ids
	var counts := {}
	var minx := 1 << 30; var miny := 1 << 30; var maxx := -(1 << 30); var maxy := -(1 << 30)
	for py in h:
		for px in w:
			var x: int = b.position.x + px
			var y: int = b.position.y + py
			var t: int = gen.tile_at(x, y)
			var code := t
			if t == WG.TileType.WATER and gen.land_value(x, y) < WG.OCEAN_LEVEL:
				code = 255
			else:
				minx = mini(minx, x); maxx = maxi(maxx, x)
				miny = mini(miny, y); maxy = maxi(maxy, y)
			tiles[py * w + px] = code
			regs[py * w + px] = maxi(0, reg_ids.find(gen.region_map.region_at(Vector2i(x, y))))
			var o: String = gen.object_at(x, y, t)
			if o != "" and not gd.object_def(o).is_empty():
				var i := obj_ids.find(o)
				if i < 0:
					obj_ids.append(o)
					i = obj_ids.size() - 1
				objs[py * w + px] = i
				counts[o] = int(counts.get(o, 0)) + 1
	var blocked := func(p: Vector2i) -> bool:
		var bx: int = p.x - b.position.x
		var by: int = p.y - b.position.y
		if bx < 0 or by < 0 or bx >= w or by >= h:
			return true
		var tt: int = tiles[by * w + bx]
		if tt == 255 or tt == WG.TileType.WATER:
			return true
		var oi: int = objs[by * w + bx]
		return oi != 0 and bool(gd.object_def(obj_ids[oi]).get("blocks", true))
	# same search as World.find_free_tile_near (square rings, row-major)
	var free_near := func(p: Vector2i, max_r: int) -> Vector2i:
		for r in max_r + 1:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var q := p + Vector2i(dx, dy)
					if not blocked.call(q):
						return q
		return p
	var camps: Array = []
	for camp in gd.camps:
		var raw := Vector2i(int(camp["at"][0]), int(camp["at"][1]))
		var at: Vector2i = free_near.call(raw, 10)
		var spread := int(camp.get("spread", 3))
		var spawns: Array = []
		for i in int(camp.get("count", 3)):
			var p: Vector2i = free_near.call(at + Vector2i((i % 3 - 1) * spread, (i / 3 - 1 + (i % 2)) * spread), 4)
			spawns.append([p.x, p.y])
		var edef: Dictionary = gd.enemies.get(str(camp["enemy"]), {}) if "enemies" in gd else {}
		camps.append({"enemy": camp["enemy"], "raw": [raw.x, raw.y], "at": [at.x, at.y], "count": camp.get("count", 3),
			"spawns": spawns, "aggro": edef.get("aggro", 0), "leash": edef.get("leash", 0), "level": edef.get("level", 0),
			"name": edef.get("name", camp["enemy"]), "tile_at": gen.tile_at(at.x, at.y)})
	var towns: Array = []
	for id in gen.town_order:
		var t: Dictionary = gen.towns[id]
		var r: Rect2i = gen._town_rects[id]
		towns.append({"id": id, "name": gen.town_name(id), "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
			"center": [gen.town_center(id).x, gen.town_center(id).y], "spawn": t.get("spawn", []),
			"specialists": t.get("specialists", []), "tagline": t.get("tagline", ""),
			"region": gen.regions.get(id, {}).get("label", ""), "style": str(t.get("building_style", "")),
			"gates": gen.gate_outsides(id).map(func(q): return [q.x, q.y])})
	# 0.3.1 villages, wheat fields, cow pastures, village paths
	var villages: Array = []
	for vid in gen.village_order:
		var vr: Rect2i = gen._village_rects[vid]
		villages.append({"id": vid, "name": gen.town_name(vid), "rect": [vr.position.x, vr.position.y, vr.size.x, vr.size.y],
			"center": [gen.town_center(vid).x, gen.town_center(vid).y], "between": gen.villages[vid].get("between", []),
			"edge_distance": snappedf(gen.town_edge_distance(gen.town_center(vid)), 0.1),
			"path": gen.village_paths.get(vid, []).map(func(q): return [q.x, q.y])})
	var farms: Array = []
	for fm in gen.farms:
		var fr2: Rect2i = fm["rect"]
		farms.append({"id": fm["id"], "village": fm["village"], "crop": fm["crop"], "rect": [fr2.position.x, fr2.position.y, fr2.size.x, fr2.size.y]})
	var pastures: Array = []
	for pz in gen.pastures:
		var pr2: Rect2i = pz["rect"]
		pastures.append({"id": pz["id"], "village": pz["village"], "enemy": pz["enemy"], "count": pz["count"], "rect": [pr2.position.x, pr2.position.y, pr2.size.x, pr2.size.y]})
	var buildings: Array = []        # 0.3.0 walk-in buildings
	for id in gen.building_order:
		var bd: Dictionary = gen.buildings[id]
		var br: Rect2i = bd["rect"]
		buildings.append({"id": id, "town": bd["town"], "kind": bd["kind"], "shop": bd["shop"], "name": bd["name"],
			"rect": [br.position.x, br.position.y, br.size.x, br.size.y], "doors": bd["doors"].map(func(d): return [d.x, d.y]),
			"altar": [bd["altar"].x, bd["altar"].y] if bd.has("altar") else null})
	var roads: Array = []
	for k in gen.roads.keys():
		var parts: PackedStringArray = k.split("|")
		if parts[0] < parts[1]:
			var pts: Array = []
			for p in gen.roads[k]:
				pts.append([p.x, p.y])
			roads.append({"from": parts[0], "to": parts[1], "tiles": pts})
	# 0.3.1: mines, PK zones, bridges, town guards/citizens, enemy distance bands
	var mines: Array = []
	for m in gen.mines:
		var rocks := {}
		var rr := int(ceil(float(m["radius"])))
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var q: Vector2i = m["c"] + Vector2i(dx, dy)
				var o2: String = gen.object_at(q.x, q.y, gen.tile_at(q.x, q.y))
				if o2.ends_with("_rock"):
					rocks[o2] = int(rocks.get(o2, 0)) + 1
		mines.append({"id": m["id"], "name": m.get("name", m["id"]), "tier": m.get("tier", ""), "center": [m["c"].x, m["c"].y],
			"radius": m["radius"], "ores": m.get("ores", {}), "pk": m["pk"], "rocks": rocks,
			"edge_distance": snappedf(gen.town_edge_distance(m["c"]), 0.1), "nearest_town": gen.nearest_town(m["c"])})
	var pk: Array = []
	for z in gen.pk_zones:
		var zr: Rect2i = z["r"]
		pk.append({"id": z["id"], "name": z.get("name", z["id"]), "rect": [zr.position.x, zr.position.y, zr.size.x, zr.size.y]})
	var bridges: Array = []
	for br in gen.bridges:
		bridges.append({"road": br["road"], "tiles": br["tiles"].map(func(q): return [q.x, q.y])})
	var npcs: Array = []
	for tid in gd.town_npcs.get("towns", {}).keys():
		var tdef: Dictionary = gd.town_npcs["towns"][tid]
		var org: Array = gd.towns[tid]["origin"]
		for gdef in tdef.get("guards", []):
			npcs.append({"town": tid, "kind": gdef.get("enemy", "town_guard"), "patrol": gdef["patrol"].map(func(q): return [int(q[0]) + int(org[0]), int(q[1]) + int(org[1])])})
		var cz: Dictionary = tdef.get("citizens", {})
		if not cz.is_empty():
			var a: Array = cz["area"]
			npcs.append({"town": tid, "kind": cz.get("enemy", "citizen"), "count": cz.get("count", 4), "area": [int(a[0]) + int(org[0]), int(a[1]) + int(org[1]), a[2], a[3]]})
	for c in camps:
		c["edge_distance"] = snappedf(gen.town_edge_distance(Vector2i(c["at"][0], c["at"][1])), 0.1)
		c["pk"] = gen.is_pk(Vector2i(c["at"][0], c["at"][1]))
	var meta := {"seed": seed_v, "origin": [b.position.x, b.position.y], "size": [w, h],
		"land_extent": [minx, miny, maxx, maxy], "tile_names": WG.TILE_NAMES,
		"tile_colors": WG.TILE_NAMES.map(func(n): return "#" + gd.tile_color(WG.TILE_NAMES.find(n)).to_html(false)),
		"object_ids": obj_ids, "object_counts": counts,
		"blocking_tiles": WG.BLOCKING_TILES, "region_ids": reg_ids,
		"region_names": reg_ids.map(func(r): return gen.region_map.region_name(r)),
		"region_tints": reg_ids.map(func(r): return str(gen.region_map.def(r).get("minimap_tint", "#ffffff"))),
		"object_blocks": obj_ids.map(func(o): return o != "" and bool(gd.object_def(o).get("blocks", true)))}
	var f := FileAccess.open(out_dir.path_join("world_dump.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"meta": meta, "towns": towns, "buildings": buildings, "roads": roads, "camps": camps,
		"zones": gd.combat_zones if "combat_zones" in gd else [],
		"mines": mines, "pk_zones": pk, "bridges": bridges, "town_npcs": npcs, "bands": gd.enemy_bands.get("bands", {}),
		"villages": villages, "farms": farms, "pastures": pastures}, " "))
	f.close()
	f = FileAccess.open(out_dir.path_join("world_tiles.bin"), FileAccess.WRITE)
	f.store_buffer(tiles); f.close()
	f = FileAccess.open(out_dir.path_join("world_objects.bin"), FileAccess.WRITE)
	f.store_buffer(objs); f.close()
	f = FileAccess.open(out_dir.path_join("world_regions.bin"), FileAccess.WRITE)
	f.store_buffer(regs); f.close()
	print("MAP_EXPORT ok seed=%d bounds=%s land=%s objects=%s" % [seed_v, b, meta["land_extent"], counts])
	return true
