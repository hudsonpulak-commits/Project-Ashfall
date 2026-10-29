extends Node2D
## 0.3.20 cheap scene life: chimney smoke, birds that flee, frogs in the
## Fenhollow marsh, butterflies in the meadows. Nothing here is interactive
## and nothing blocks a tile. Off-screen smoke pauses itself.


var birds: Array = []
var frogs: Array = []
var butterflies: Array = []
var smokes: Array = []
var _tile := 16
var _grass: Array = []
var _marsh := 7


func setup(world, grass: Array, marsh: int) -> void:
	_tile = world.tile_px
	_grass = grass
	_marsh = marsh
	var gen = world.gen
	var bird_tex := _dot(Color(0.42, 0.28, 0.16), 4)
	var frog_tex := _dot(Color(0.22, 0.55, 0.28), 3)
	var fly_tex := _dot(Color(0.85, 0.72, 0.35), 3)
	for tid in gen.town_order + gen.village_order:
		var home := _grass_outside(gen, gen.town_spawn(tid), "")
		if home.x < -90000:
			continue
		birds.append(_critter(bird_tex, home, "bird"))
		if birds.size() >= 8:
			break
	var marsh_tiles := _tiles_of(gen, gen.town_spawn("fenhollow"), _marsh, 5, 48)
	for p in marsh_tiles:
		frogs.append(_critter(frog_tex, p, "frog"))
	var meadow := 0
	var centre: Vector2i = gen.town_center("highfen")
	for r in [18, 26, 34, 42, 50, 58]:
		for d in [Vector2i(r, 8), Vector2i(-r, 12), Vector2i(10, r), Vector2i(-14, -r), Vector2i(r, -r)]:
			var q: Vector2i = centre + d
			if not _meadow(gen, q):
				continue
			butterflies.append(_critter(fly_tex, q, "butterfly"))
			meadow += 1
			if meadow >= 6:
				break
		if meadow >= 6:
			break
	_place_smoke(gen)


func step(focus: Vector2i, delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for b in birds:
		var home: Vector2i = b["home"]
		var far: int = maxi(absi(focus.x - home.x), absi(focus.y - home.y))
		if far <= 4 and not bool(b["flee"]):
			var away := home - focus
			if away == Vector2i.ZERO:
				away = Vector2i(4, -2)
			b["flee"] = true
			b["goal"] = home + away * 2
			b["until"] = t + 3.5
		if bool(b["flee"]) and t >= float(b["until"]):
			b["flee"] = false
			b["goal"] = home
		var goal: Vector2i = b["goal"]
		var spr: Sprite2D = b["spr"]
		var want := _px(goal)
		spr.position = spr.position.move_toward(want, 28.0 * delta if bool(b["flee"]) else 10.0 * delta)
		spr.visible = far < 48 or bool(b["flee"])
	for f in frogs:
		var spr2: Sprite2D = f["spr"]
		var hop := 1.0 if sin(t * 3.0 + float(f["phase"])) > 0.6 else 0.0
		spr2.position = _px(f["home"]) + Vector2(0, -hop)
		spr2.visible = maxi(absi(focus.x - f["home"].x), absi(focus.y - f["home"].y)) < 40
	for bf in butterflies:
		var spr3: Sprite2D = bf["spr"]
		var ph := float(bf["phase"])
		spr3.position = _px(bf["home"]) + Vector2(sin(t * 1.7 + ph) * 5.0, cos(t * 1.3 + ph) * 3.0)
		spr3.visible = maxi(absi(focus.x - bf["home"].x), absi(focus.y - bf["home"].y)) < 40


func _place_smoke(gen) -> void:
	var n := 0
	var tex := _dot(Color(0.78, 0.78, 0.76, 0.7), 2)
	for bid in gen.building_order:
		if n >= 12:
			break
		var b: Dictionary = gen.buildings[bid]
		if str(b.get("kind", "")) != "house":
			continue
		if absi(hash(str(b["id"]))) % 5 != 0:
			continue
		var r: Rect2i = b["rect"]
		var at := Vector2i(r.position.x + r.size.x / 2, r.position.y)
		var host := VisibleOnScreenEnabler2D.new()
		host.position = _px(at) + Vector2(0, -6)
		host.rect = Rect2(-16, -24, 32, 40)
		var puff := CPUParticles2D.new()
		puff.name = "Puff"
		puff.texture = tex
		puff.amount = 4
		puff.lifetime = 1.3
		puff.explosiveness = 0.05
		puff.direction = Vector2(0, -1)
		puff.spread = 12.0
		puff.gravity = Vector2(0, -6)
		puff.initial_velocity_min = 4.0
		puff.initial_velocity_max = 8.0
		puff.scale_amount_min = 1.0
		puff.scale_amount_max = 1.6
		puff.color = Color(0.75, 0.75, 0.72, 0.55)
		host.add_child(puff)
		host.enable_node_path = NodePath("Puff")
		add_child(host)
		smokes.append(host)
		n += 1


func _critter(tex: Texture2D, home: Vector2i, kind: String) -> Dictionary:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = _px(home)
	add_child(spr)
	return {"spr": spr, "home": home, "goal": home, "flee": false, "until": 0.0, "phase": hash(home) % 7, "kind": kind}


func _px(p: Vector2i) -> Vector2:
	return Vector2(p.x * _tile + _tile * 0.5, p.y * _tile + _tile * 0.5)


func _dot(c: Color, n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _grass_outside(gen, origin: Vector2i, region: String) -> Vector2i:
	for r in range(8, 36):
		for d in [Vector2i(r, 2), Vector2i(-r, -2), Vector2i(2, r), Vector2i(-3, -r)]:
			var p: Vector2i = origin + d
			if gen.town_at(p, 0) != "" or gen.village_at(p, 0) != "" or gen.road_tiles.has(p):
				continue
			var tile: int = gen.tile_at(p.x, p.y)
			if tile in _grass and (region == "" or gen.region_map.region_at(p) == region):
				return p
	return Vector2i(-99999, 0)


func _meadow(gen, p: Vector2i) -> bool:
	if gen.town_at(p, 2) != "" or gen.village_at(p, 2) != "" or gen.road_tiles.has(p):
		return false
	if gen.region_map.region_at(p) != "central":
		return false
	return gen.tile_at(p.x, p.y) in _grass


func _tiles_of(gen, origin: Vector2i, want: int, limit: int, radius: int) -> Array:
	var out: Array = []
	for y in range(origin.y - radius, origin.y + radius, 3):
		for x in range(origin.x - radius, origin.x + radius, 3):
			if gen.tile_at(x, y) != want:
				continue
			if gen.road_tiles.has(Vector2i(x, y)):
				continue
			out.append(Vector2i(x, y))
			if out.size() >= limit:
				return out
	return out
