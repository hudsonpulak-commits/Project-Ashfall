extends Node
## Ashfen QA bot: in-game driver (0.3.0). Loaded by main.gd for `-- --qa=<scenario>`.
## Runs inside the REAL rendered game (xvfb / any display): drives the scenario
## through the real input path (InputEventScreenTouch via Input.parse_input_event;
## with emulate_mouse_from_touch Godot also generates the emulated mouse event,
## i.e. the same touch + mouse pair Android delivers), and after every rendered
## frame saves the frame (frames/fNNNNN.png) and one JSON line of game state
## (log.jsonl). tools/qa_bot/analyze.py turns that into pass/fail checks.
## Not exported (tools/* is excluded from the APK).
##
## Scenarios: walk, combat, shop, pshop, smithy, markers, daynight, world, church, aggro, farm, city, cookhouse, pk, gear (see SCENARIOS in analyze.py).

var main
var scenario := ""
var out_dir := ""
var frame := 0
var capturing := false
var label := ""
var _log: FileAccess
var _events: Array = []
var _notes: Dictionary = {}       # driver-side facts for the analyzer (result.json)
var _bv


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	scenario = str(main.args["qa"])
	out_dir = str(main.args.get("qa-out", "/tmp/qa/" + scenario))
	DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	_log = FileAccess.open(out_dir + "/log.jsonl", FileAccess.WRITE)
	_bv = main.world.buildings_view
	Events.message.connect(func(t, k): _ev("msg", {"text": t, "kind": k}))
	Events.shop_opened.connect(func(s): _ev("shop_opened", {"shop": s}))
	Events.player_shop_opened.connect(func(t, s): _ev("pshop_opened", {"town": t, "slot": s}))
	Events.station_opened.connect(func(s, p): _ev("station_opened", {"station": s}))
	Events.hitsplat.connect(func(tg, t, a): _ev("hitsplat", {"target": tg.get_instance_id() if tg is Object else 0, "amount": a,
		"who": str(tg.actor_id) if tg is Actor else "", "by": str(tg.last_attacker.actor_id) if tg is Actor and tg.last_attacker is Actor and is_instance_valid(tg.last_attacker) else ""}))
	Events.report_ready.connect(func(t, b): _ev("report", {"title": t, "body": b.substr(0, 200)}))
	RenderingServer.frame_post_draw.connect(_post_draw)
	_run.call_deferred()


func _ev(kind: String, d: Dictionary) -> void:
	d["f"] = frame
	d["type"] = kind
	d["label"] = label
	_events.append(d)


# ------------------------------------------------------------- capture --
func _post_draw() -> void:
	if not capturing:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frames/f%05d.png" % [out_dir, frame])
	_log.store_line(JSON.stringify(_state()))
	frame += 1


func _state() -> Dictionary:
	var p: Player = main.player
	var w: World = main.world
	var ct := get_viewport().get_canvas_transform()
	var scr: Vector2 = ct * p.global_position
	var bubbles: Array = []
	for c in main.hit_bubbles.get_children():
		if c is Control and c.visible:
			bubbles.append([c.position.x, c.position.y])
	var roofs := {}
	for id in w.gen.building_order:
		var b: Dictionary = w.gen.buildings[id]
		if (Vector2((b["rect"] as Rect2i).get_center()) - Vector2(p.tile)).length() < 40:
			roofs[id] = snappedf(_bv.roof_alpha(id), 0.001)
	var hidden_bad: Array = []
	for a in get_tree().get_nodes_in_group("actors"):
		if a != p and "tile" in a and a.visible and a.is_visible_in_tree() and _bv.hides(a.tile):
			hidden_bad.append(str(a.name))
	var near := 9999.0
	var others: Array = []          # [dx, dy] of visible actors / enemies within 96 world px
	var cands: Array = get_tree().get_nodes_in_group("actors")
	if w.enemies:
		cands += w.enemies.enemies
	for a in cands:
		if is_instance_valid(a) and a != p and a is Node2D and a.is_visible_in_tree():
			var d: Vector2 = a.position - p.position
			near = minf(near, d.length())
			if d.length() < 96.0:
				others.append([d.x, d.y])
	var hud: HUD = main.hud
	return {
		"near": snappedf(near, 0.1), "others": others,
		"f": frame, "ms": Time.get_ticks_msec(), "tick": Tick.tick_count, "alpha": snappedf(Tick.alpha(), 0.001), "label": label,
		"pos": [p.position.x, p.position.y], "tile": [p.tile.x, p.tile.y], "flip": p._sprite.flip_h, "sframe": p._sprite.frame,
		"scr": [scr.x, scr.y], "zoom": main.camera.zoom.x, "cam": [main.camera.position.x, main.camera.position.y],
		"moving": not p.path.is_empty(), "sprint": p.sprint, "blocked": w.is_blocked(p.tile),
		"inside": _bv.player_building(), "roofs": roofs, "hidden_bad": hidden_bad,
		"bubbles": bubbles, "bubble_targets": main.hit_bubbles.bubbles.size(),
		"panel": hud.current_panel, "store_shop": hud.store_panel.shop if hud.store_panel else "",
		"coins": p.inventory.count(GameData.currency), "action": str(p.action.get("kind", "")),
		"hp": p.hp, "pk": w.is_pk(p.tile),
		"prayer_pts": snappedf(Prayer.points(p.prayer, p.skills.level("prayer")), 0.01), "prayer_max": Prayer.max_points(p.skills.level("prayer")),
		"kneel": bool(p.action.get("kneel", false)),
		"zone_banner": hud.zone_banner.banner_showing() if hud.zone_banner else false,
		"zone_row": hud.zone_banner.row.visible if hud.zone_banner and hud.zone_banner.row else false,
		"skulled": p.is_skulled(Tick.tick_count),
		"hud_pk": hud.multi_label.text if hud.multi_row.visible else "",
		"gear": p.gear_layer_ids(), "tint": p._sprite.modulate.to_html(false),
	}


# -------------------------------------------------------------- helpers --
## Optional named still (--qa-shots=/abs/dir): the frame as rendered now.
func shot(name: String) -> void:
	if not main.args.has("qa-shots"):
		return
	await RenderingServer.frame_post_draw
	var d := str(main.args["qa-shots"])
	DirAccess.make_dir_recursive_absolute(d)
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [d, name])
	_ev("shot", {"name": name})


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func until(cond: Callable, max_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(max_s * 1000.0):
			return false
		await get_tree().process_frame
	return true


## One finger tap through the engine's input pipeline (touch + emulated mouse).
func tap(pos: Vector2, what: String = "") -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = true
	_ev("tap", {"pos": [pos.x, pos.y], "what": what})
	Input.parse_input_event(e)
	await frames(2)
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.position = pos
	r.pressed = false
	Input.parse_input_event(r)
	await frames(1)



## Hold a finger down for long_press_ms (map markers). Same touch + emulated-mouse pair.
func long_press(pos: Vector2, what: String = "", hold_ms: int = -1) -> void:
	if hold_ms < 0:
		hold_ms = int(GameData.map_markers_cfg.get("long_press_ms", 450))
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = true
	_ev("long_press", {"pos": [pos.x, pos.y], "what": what, "hold_ms": hold_ms})
	Input.parse_input_event(e)
	var frames_hold := maxi(2, int(ceil(hold_ms / 16.0)) + 2)
	await frames(frames_hold)
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.position = pos
	r.pressed = false
	Input.parse_input_event(r)
	await frames(2)


func tile_screen(t: Vector2i) -> Vector2:
	var ts := float(GameData.tile_size)
	return get_viewport().get_canvas_transform() * (main.world.tile_to_pos(t) + Vector2(ts / 2.0, ts / 2.0))


func tap_tile(t: Vector2i, what: String = "") -> void:
	await tap(tile_screen(t), what if what != "" else "tile %s" % str(t))


func tap_control(c: Control, what: String) -> bool:
	if c == null or not c.is_visible_in_tree():
		_ev("missing", {"what": what})
		return false
	var sc := _scroll_parent(c)
	if sc:
		sc.ensure_control_visible(c)
		await frames(2)
	await tap(c.get_global_rect().get_center(), what)
	return true


func _scroll_parent(c: Node) -> ScrollContainer:
	var n := c.get_parent()
	while n:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func find_button(root: Node, prefix: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		if c is Button and c.is_visible_in_tree() and (c as Button).text.begins_with(prefix) and not (c as Button).disabled:
			return c
	return null


func arrived() -> bool:
	return main.player.path.is_empty()


func settled() -> bool:
	var p: Player = main.player
	return p.path.is_empty() and p.position == p.foot_px(p.tile).round()


func walk_leg(name: String, dest: Vector2i, max_s := 15.0) -> void:
	await until(settled, 3.0)
	label = name
	await tap_tile(dest, name)
	await until(arrived, max_s)
	await until(settled, 3.0)
	await frames(4)
	label = ""


## Leave a building like a player would: with a panel covering the lower
## screen, first tap a visible floor tile beside you (walking off closes the
## panel), then tap outside the door.
func walk_out(b: Dictionary) -> void:
	var p: Player = main.player
	if main.hud.current_panel != "":
		for side in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(1, 0)]:
			var q: Vector2i = p.tile + side
			if not main.world.is_blocked(q) and main.world.gen.is_inside(q, b):
				await tap_tile(q, "step aside (closes the panel)")
				await until(func(): return arrived() and main.hud.current_panel == "", 6.0)
				break
	if main.hud.current_panel != "":
		await tap_control(main.hud.close_button, "panel close button")
		await frames(6)
	await tap_tile(_outside(b, 3), "outside")
	await until(arrived, 12.0)


func _outside(b: Dictionary, n := 3) -> Vector2i:
	var r: Rect2i = b["rect"]
	var d: Vector2i = b["doors"][0]
	var dir := Vector2i(0, 1) if int(b["facade_y"]) == r.end.y - 1 else Vector2i(0, -1)
	# 0.3.11: towns are denser - never land on another building's floor; prefer
	# the furthest street tile up to n steps out, else the nearest one off-building
	var g: WorldGen = main.world.gen
	var best := d + dir
	for k in range(1, n + 1):
		var q := d + dir * k
		if not g.building_at(q).is_empty():
			break
		best = q
	if not g.building_at(best).is_empty():
		for rr in range(1, 6):
			for dy in range(-rr, rr + 1):
				for dx in range(-rr, rr + 1):
					var q2 := d + dir + Vector2i(dx, dy)
					if g.building_at(q2).is_empty() and not main.world.is_blocked(q2):
						return q2
	return best


func _finish(ok: bool) -> void:
	await frames(3)
	capturing = false
	_notes["frames"] = frame
	_notes["scenario"] = scenario
	_notes["events"] = _events
	_notes["zoom"] = main.camera.zoom.x
	_notes["tile_size"] = GameData.tile_size
	_notes["version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	var f := FileAccess.open(out_dir + "/result.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_notes, " "))
	f.close()
	_log.close()
	print("QA %s done: %d frames -> %s" % [scenario, frame, out_dir])
	get_tree().quit(0 if ok else 3)


# ------------------------------------------------------------ scenarios --
func _run() -> void:
	Tick.running = true
	await frames(30)                    # settle: chunks, views, fades
	var p: Player = main.player
	p.inventory.clear()
	p.give_starter_kit() if p.has_method("give_starter_kit") else null
	capturing = true
	match scenario:
		"walk":
			await _walk()
		"combat":
			await _combat()
		"shop":
			await _shop()
		"pshop":
			await _pshop()
		"smithy":
			await _smithy()
		"world":
			await _world()
		"church":
			await _church()
		"markers":
			await _markers()
		"daynight":
			await _daynight()
		"aggro":
			await _aggro()
		"farm":
			await _farm()
		"city":
			await _city()
		"cookhouse":
			await _cookhouse()
		"pk":
			await _pk()
		"gear":
			await _gear()
		"archery":
			await _archery()
		"bank":
			await _bank035()
		"v036":
			await _v036()
		"quest":
			await _quest037()
		"xp":
			await _xp037()
		"capital":
			await _capital038()
		"autotile":
			await _autotile039()
		"gfx":
			await _gfx0391()
		_:
			push_error("unknown QA scenario " + scenario)
			await _finish(false)
			return
	await _finish(true)


## Right, turn left mid-walk, 45-degree diagonals both ways, then sprint (via a
## real tap on the Energy bar) for a shallow diagonal and a straight run; the
## Pack tab is tapped open and closed (single-tap toggles).
## 0.3.13 Fenhollow v1 is a dense marsh town: the walk/gear legs need a clear 18x13 patch, so find the
## nearest one to the spawn (checked in collision) instead of assuming open ground beside it.
func _walk_origin() -> Vector2i:
	var w: World = main.world
	var c0: Vector2i = w.gen.town_spawn("fenhollow")
	# 0.3.13: open ground (no props, no blocking tiles) so the walk legs measure walking, not clutter
	# (Fenhollow's redesign packs racks/crates/reeds right up to the spawn; within r 70 there is no clear patch)
	for r in range(0, 240, 2):
		for dy in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := c0 + Vector2i(dx, dy)
				var ok := true
				for yy in range(-6, 7):
					for xx in range(-20, 12):
						var q := c + Vector2i(xx, yy)
						w.get_chunk(w.chunk_of(q))
						if w.is_blocked(q) or w.object_at(q) != null:
							ok = false
							break
					if not ok:
						break
				if ok:
					_ev("walk_origin", {"tile": [c.x, c.y], "r": r})
					return c
	_ev("walk_origin", {"tile": [c0.x, c0.y], "r": -1})
	return c0


func _walk() -> void:
	var p: Player = main.player
	var c: Vector2i = _walk_origin()
	p.place_at(c + Vector2i(-7, 2))
	p.sprint = false
	p.energy = p.max_energy()
	await frames(20)
	label = "walk_right"
	await tap_tile(c + Vector2i(3, 2), "walk right")
	await until(func(): return p.tile.x >= c.x - 2, 8.0)
	label = "turn_left"
	await tap_tile(c + Vector2i(-6, 2), "turn left mid-walk")
	await until(arrived, 12.0)
	await frames(10)
	await walk_leg("diag_up_right", p.tile + Vector2i(5, -5))
	await walk_leg("diag_down_left", p.tile + Vector2i(-5, 5))
	label = "sprint_tap"
	var s0 := p.sprint
	await tap_control(main.hud.energy_bar, "energy bar (sprint on)")
	await frames(20)
	_notes["sprint_tap_on"] = {"before": s0, "after": p.sprint}
	await walk_leg("sprint_diag_up_right", p.tile + Vector2i(8, -4))
	await walk_leg("sprint_left", p.tile + Vector2i(-8, 0))
	await walk_leg("sprint_diag_down_left", p.tile + Vector2i(-3, 3))
	label = "sprint_tap_off"
	await tap_control(main.hud.energy_bar, "energy bar (sprint off)")
	await frames(20)
	_notes["sprint_tap_off"] = {"after": p.sprint}
	label = "pack_tap"
	await tap_control(main.hud.tab_buttons["pack"], "Pack tab")
	await frames(20)
	_notes["pack_open"] = main.hud.current_panel
	label = "pack_tap_close"
	await tap_control(main.hud.tab_buttons["pack"], "Pack tab (close)")
	await frames(20)
	_notes["pack_closed"] = main.hud.current_panel
	label = ""


## Hit the training dummy, then a real enemy: one bubble per target at a time.
func _combat() -> void:
	var p: Player = main.player
	var w: World = main.world
	var c: Vector2i = w.gen.town_spawn("fenhollow")
	var dummy: WorldObject = w.find_nearest_object(c, ["training_dummy"], 20)
	p.place_at(w.find_free_tile_near(dummy.pos + Vector2i(-2, 1), 3, true))
	await frames(15)
	label = "dummy"
	await tap_tile(dummy.pos, "training dummy")
	await frames(240)
	p.stop()
	var foe = w.enemies.nearest(p.tile, ["giant_rat"], 400) if w.enemies else null
	if foe == null and w.enemies:
		foe = w.enemies.nearest(p.tile, [], 400)
	if foe != null:
		p.hp = p.max_hp()
		p.place_at(w.find_free_tile_near(foe.tile + Vector2i(-3, 0), 4, true))
		await frames(30)
		label = "enemy"
		await tap(tile_screen(foe.tile), "enemy " + str(foe.display_name()))
		await until(func(): return foe.dead if "dead" in foe else false, 25.0)
		await frames(40)
		_notes["enemy"] = str(foe.display_name())
	label = ""


## Watch an AI walk into a shop from outside (hidden under the roof), then tap
## the keeper: walk in through the door, roof fades, greeting, the right shop.
func _shop() -> void:
	var p: Player = main.player
	var w: World = main.world
	var shop: String = Market.town("fenhollow").specialists[0]
	var b: Dictionary = w.gen.building_for_shop("fenhollow", shop)
	_notes["building"] = b["id"]
	_notes["shop"] = shop
	_notes["rect"] = [b["rect"].position.x, b["rect"].position.y, b["rect"].size.x, b["rect"].size.y]
	_notes["doors"] = b["doors"].map(func(d): return [d.x, d.y])
	_notes["keeper"] = b["keeper"]
	p.place_at(_outside(b, 4))
	await frames(10)
	var ai = await _pick_ai("fenhollow")
	if ai != null:
		ai.place_at(w.find_free_tile_near(_outside(b, 3) + Vector2i(2, 0), 3, true))
		ai.visit_shop(shop)
		_notes["ai_visit_action"] = str(ai.action.get("kind", ""))
		label = "ai_walks_in"
		await until(func(): return w.gen.is_inside(ai.tile, b), 12.0)
		await frames(90)
		_notes["ai_inside"] = w.gen.is_inside(ai.tile, b)
	label = "tap_keeper"
	await tap_tile(b["keeper_at"], "keeper")
	label = "walk_in"
	await until(func(): return w.gen.is_inside(p.tile, b) and w.buildings_view.roof_alpha(b["id"]) <= 0.01, 15.0)
	await frames(6)
	await shot("v030_inside_shop")
	var opened := await until(func(): return main.hud.current_panel == "store", 15.0)
	label = "shop_open"
	await frames(12)
	await shot("v030_shop_talk")
	await frames(28)
	_notes["store_opened"] = opened
	_notes["store_shop"] = main.hud.store_panel.shop
	label = "walk_out"
	await walk_out(b)
	await frames(30)
	label = ""


## Buy the empty shop, stock a stand through the panel, an AI buys, collect.
func _pshop() -> void:
	var p: Player = main.player
	var w: World = main.world
	var b: Dictionary = w.gen.building_for_shop(Market.shop_town(), "player")
	var ps: PlayerShop = Market.player_shop(Market.shop_town())
	_notes["building"] = b["id"]
	p.inventory.add(GameData.currency, 2000)
	p.inventory.add("bronze_bar", 3)
	p.inventory.add("bronze_arrows", 40)
	p.place_at(_outside(b, 3))
	await frames(20)
	label = "forsale"
	await frames(20)
	await shot("v030_player_shop_forsale")
	label = "tap_estate_keeper"
	await tap_tile(b["keeper_at"], "estate agent")
	var opened := await until(func(): return main.hud.current_panel == "pshop", 15.0)
	await frames(20)
	_notes["panel_opened"] = opened
	var c0 := p.inventory.count(GameData.currency)
	label = "buy"
	await tap_control(find_button(main.hud.pshop_panel, "Buy for"), "Buy shop")
	await frames(20)
	_notes["bought"] = {"owned": ps.owned, "coins_before": c0, "coins_after": p.inventory.count(GameData.currency), "price": PlayerShop.building_price()}
	label = "stock"
	var slot: ItemSlot = null
	for s in main.hud.pshop_panel.find_children("*", "ItemSlot", true, false):
		if (s as ItemSlot).item_id == "bronze_arrows":
			slot = s
	await tap_control(slot, "pack: bronze arrows")
	await frames(10)
	await tap_control(find_button(main.hud.pshop_panel, "Place"), "Place")
	await frames(10)
	# second stand: bronze bar
	var stand2: Button = null
	for bt in main.hud.pshop_panel.find_children("*", "Button", true, false):
		if bt.is_visible_in_tree() and bt.toggle_mode and bt.get_child_count() > 0 and not bt.button_pressed:
			stand2 = bt
			break
	await tap_control(stand2, "stand 2")
	await frames(10)
	slot = null
	for s in main.hud.pshop_panel.find_children("*", "ItemSlot", true, false):
		if (s as ItemSlot).item_id == "bronze_bar":
			slot = s
	await tap_control(slot, "pack: bronze bar")
	await frames(10)
	await tap_control(find_button(main.hud.pshop_panel, "Place"), "Place")
	label = "manage"
	await frames(20)
	await shot("v030_player_shop_manage")
	await frames(20)
	_notes["stocked"] = ps.stocked().size()
	if main.args.has("qa-shots"):   # screenshot runs only: fill more stands (same API as the panel)
		var extra := [["bronze_sword", 1, 60], ["bronze_hatchet", 1, 45], ["iron_ore", 20, 9], ["ash_log", 30, 4]]
		for e in extra:
			if GameData.items.has(e[0]):
				p.inventory.add(e[0], e[1])
				for i in ps.slots.size():
					if ps.slots[i] == null:
						ps.place(p, i, e[0], e[1], maxi(1, Market.town(Market.shop_town()).reference_price(e[0])))
						break
		main.hud.pshop_panel.refresh()
		await frames(5)
	label = "close"
	await tap_control(main.hud.close_button, "panel close button")
	await frames(10)
	_notes["panel_closed"] = main.hud.current_panel == ""
	# AI shoppers: the real decision (AIBrain.shop_browse) over the town's agents
	var town_agents: Array = AIDirector.records.filter(func(a): return a.town == "fenhollow")
	var u0 := int(ps.stats["units"])
	for r in 60:
		for a in town_agents:
			AIBrain.shop_browse(a, Tick.tick_count)
		if int(ps.stats["units"]) > u0:
			break
		ps.lots_today.clear()
	_notes["ai_units"] = int(ps.stats["units"]) - u0
	# and a detailed AI walks in (cosmetic) so you can see a customer
	label = "ai_customer"
	var ai = await _pick_ai("")
	if ai != null:
		ai.place_at(w.find_free_tile_near(_outside(b, 3) + Vector2i(1, 0), 3, true))
		ai.visit_shop("player")
		_notes["ai_visit_action"] = str(ai.action.get("kind", ""))
		await until(func(): return w.gen.is_inside(ai.tile, b) or (not ai.action.is_empty() and ai.path.is_empty()), 12.0)
		await until(func(): return ai.path.is_empty(), 8.0)
		await frames(10)
		await shot("v030_player_shop_stocked")
		await frames(50)
		var at_stand := false   # 0.3.11 the stands are on the plaza: a customer at one counts
		for dp in b.get("displays", []):
			if maxi(absi(ai.tile.x - dp.x), absi(ai.tile.y - dp.y)) <= 1:
				at_stand = true
		_notes["ai_inside"] = w.gen.is_inside(ai.tile, b) or at_stand
	label = "collect"
	var till := ps.till
	await tap_tile(b["keeper_at"], "keeper (collect)")
	await until(func(): return main.hud.current_panel == "pshop", 10.0)
	await frames(10)
	var c1 := p.inventory.count(GameData.currency)
	await tap_control(find_button(main.hud.pshop_panel, "Collect"), "Collect")
	await frames(20)
	_notes["collect"] = {"till": till, "coins_before": c1, "coins_after": p.inventory.count(GameData.currency), "till_after": ps.till}
	label = "walk_out"
	await walk_out(b)
	await frames(30)
	label = ""


## Blacksmith: walk in, smelt bronze at the furnace, forge at the anvil, walk out.
func _smithy() -> void:
	var p: Player = main.player
	var w: World = main.world
	var b: Dictionary = w.gen.building_for_shop("fenhollow", "swords")
	_notes["building"] = b["id"]
	_notes["kind"] = b.get("kind", "")
	p.skills.set_level("smithing", 10)
	p.inventory.add("copper_ore", 2)
	p.inventory.add("tin_ore", 2)
	p.place_at(_outside(b, 3))
	await frames(20)
	label = "walk_in"
	await tap_tile(b["doors"][0] + Vector2i(0, 2), "inside the door")
	await until(arrived, 10.0)
	await frames(15)
	var fur: WorldObject = w.find_nearest_object(p.tile, ["furnace"], 10)
	label = "furnace"
	await tap_tile(fur.pos, "furnace")
	var op := await until(func(): return main.hud.current_panel == "craft" or p.inventory.count("bronze_bar") > 0, 15.0)
	if main.hud.current_panel == "craft":
		await frames(10)
		await tap_control(_recipe_button("Bronze bar", "All"), "smelt bronze (All)")
	label = "smelting"
	await until(func(): return p.inventory.count("bronze_bar") >= 2 and p.action.is_empty(), 20.0)
	await frames(10)
	_notes["smelt"] = {"panel": op, "bars": p.inventory.count("bronze_bar")}
	var anv: WorldObject = w.find_nearest_object(p.tile, ["anvil"], 10)
	label = "anvil"
	await tap_tile(anv.pos, "anvil")
	var op2 := await until(func(): return main.hud.current_panel == "craft" or p.inventory.count("bronze_bar") < 2, 15.0)
	if main.hud.current_panel == "craft":
		await frames(10)
		await tap_control(_recipe_button("Bronze dagger", "Make 1"), "forge bronze dagger")
	label = "forging"
	await frames(25)
	await shot("v030_blacksmith_inside")
	await until(func(): return p.inventory.count("bronze_dagger") >= 1 and p.action.is_empty(), 20.0)
	await frames(30)
	_notes["forge"] = {"panel": op2, "dagger": p.inventory.count("bronze_dagger"), "bars_left": p.inventory.count("bronze_bar")}
	_notes["inside_ok"] = w.gen.building_at(fur.pos).get("id", "") == b["id"] and w.gen.building_at(anv.pos).get("id", "") == b["id"]
	label = "walk_out"
	await walk_out(b)
	await frames(30)
	_notes["out"] = w.gen.building_at(p.tile).is_empty()
	label = ""


## A detailed (on-screen) AI of that town, free to go shopping.
func _pick_ai(town: String):
	for i in 300:
		for a in AIDirector.agents:
			if is_instance_valid(a) and not a.dead and a.agent and (town == "" or a.agent.town == town) and not a.agent.trip.has("to") and str(a.action.get("kind", "")) != "fight":
				a.stop()
				return a
		await frames(1)
	_notes["ai_missing"] = town
	return null


func _recipe_button(item_name: String, btn: String) -> Button:
	for l in main.hud.craft_panel.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with(item_name + " "):
			var row: Node = l.get_parent()
			for c in row.get_children():
				if c is Button and (c as Button).text == btn:
					return c
	return null


# ------------------------------------------------------------ 0.3.1 world --
func _wait_ticks(n: int) -> void:
	var t0 := Tick.tick_count
	await until(func(): return Tick.tick_count >= t0 + n, n * 1.5 + 5.0)


func _foe(kind: String, town := "", near := Vector2i.ZERO) -> Enemy:
	var best: Enemy = null
	for e in main.world.enemies.enemies:
		if e.dead or e.kind != kind or (town != "" and e.town != town):
			continue
		if best == null or e.cheb(e.tile, near) < best.cheb(best.tile, near):
			best = e
	return best


## Stand right next to a creature for `ticks` ticks: did it start a fight?
func _calm_check(e: Enemy, name: String, ticks := 10) -> Dictionary:
	var p: Player = main.player
	var w: World = main.world
	p.stop()
	p.hp = p.max_hp()
	p.queue_redraw()
	p.place_at(w.find_free_tile_near(e.tile + Vector2i(1, 0), 3, true))
	label = "calm_" + name
	var t0 := Tick.tick_count
	var started := false
	while Tick.tick_count < t0 + ticks:
		if e.target == p:
			started = true
		if e.cheb(e.tile, p.tile) > 2:   # it wandered off: follow it (stay adjacent)
			p.place_at(w.find_free_tile_near(e.tile + Vector2i(1, 0), 3, true))
		await get_tree().process_frame
	label = ""
	return {"kind": e.kind, "started_fight": started, "hp_lost": p.max_hp() - p.hp, "ticks": ticks}


## Chickens, guards and citizens never start fights; a guard fights back when
## you tap it; a wolf goes for you; walk north across the Scorch line (banner +
## skull row); every road tile is land or a bridge.
func _world() -> void:
	var p: Player = main.player
	var w: World = main.world
	var gen = w.gen
	var fen: Vector2i = gen.town_spawn("fenhollow")
	# 1. calm creatures
	var calm := {}
	for kind in ["chicken", "town_guard", "citizen"]:
		var e := _foe(kind, "fenhollow" if kind != "chicken" else "", fen)
		if e == null:
			calm[kind] = {"missing": true}
			continue
		w.set_focus(e.tile, true)
		await frames(10)
		calm[kind] = await _calm_check(e, kind)
	_notes["calm"] = calm
	await shot("v031_town_folk")
	# 2. tap a guard: it fights back
	var g := _foe("town_guard", "fenhollow", fen)
	p.hp = p.max_hp()
	p.queue_redraw()
	p.place_at(w.find_free_tile_near(g.tile + Vector2i(2, 0), 3, true))
	await frames(10)
	label = "guard_fight"
	await tap(tile_screen(g.tile), "town guard")
	var hit_back := await until(func(): return g.target == p and p.hp < p.max_hp(), 20.0)
	_notes["guard_fight"] = {"guard_target_player": g.target == p, "player_hit": p.hp < p.max_hp(), "ok": hit_back}
	label = ""
	p.stop()
	p.action = {}
	g.target = null
	g.reset_far()
	p.hp = p.max_hp()
	p.queue_redraw()
	# 3. a wolf charges you
	var wolf := _foe("wolf", "", fen)
	var wolf_n := {"missing": wolf == null}
	if wolf:
		w.set_focus(wolf.tile, true)
		p.place_at(w.find_free_tile_near(wolf.tile + Vector2i(3, 1), 3, true))
		await frames(10)
		label = "wolf"
		var aggro := await until(func(): return wolf.target == p, 12.0)
		await _wait_ticks(4)
		await shot("v031_wolf")
		wolf_n = {"kind": "wolf", "aggro": aggro, "dist_start": 3, "hp_lost": p.max_hp() - p.hp}
		label = ""
		p.place_at(fen)
		wolf.target = null
		wolf.reset_far()
		p.hp = p.max_hp()
		p.queue_redraw()
	_notes["wolf"] = wolf_n
	# 4. walk across the Scorch line
	var z: Dictionary = GameData.pk_zones["zones"][0]
	var r: Array = z["rect"]
	var edge_y: int = int(r[1]) + int(r[3]) - 1     # last PK row
	var start := Vector2i.ZERO
	for x in range(300, 200, -1):     # a column north of Cinderholt that is open across the line
		var ok := true
		for y in range(edge_y - 6, edge_y + 6):
			if w.is_blocked(Vector2i(x, y)):
				ok = false
				break
		if ok:
			start = Vector2i(x, edge_y + 5)
			break
	p.zone_seen = {}
	p.place_at(start)
	w.set_focus(start, true)
	await frames(30)
	var before := {"pk": w.is_pk(p.tile), "row": main.hud.zone_banner.row.visible, "banner": main.hud.zone_banner.banner_showing()}
	await shot("v031_scorch_before")
	await walk_leg("scorch_cross", start + Vector2i(0, -9), 20.0)
	var bn: Control = main.hud.zone_banner.banner
	var rowc: Control = main.hud.zone_banner.row
	_notes["scorch"] = {"start": [start.x, start.y], "edge_y": edge_y, "before": before,
		"in_pk": w.is_pk(p.tile), "tile": [p.tile.x, p.tile.y], "seen": p.zone_seen.has(str(z["id"])),
		"warning": str(z.get("warning", "")), "banner_text": main.hud.zone_banner.banner_label.text,
		"banner_rect": [bn.global_position.x, bn.global_position.y, bn.size.x, bn.size.y],
		"row_rect": [rowc.global_position.x, rowc.global_position.y, rowc.size.x, rowc.size.y],
		"vp": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]}
	await shot("v031_scorch_banner")
	await frames(20)
	# walk out and back in: no second banner (only the first crossing)
	await walk_leg("scorch_out", start, 20.0)
	await walk_leg("scorch_again", start + Vector2i(0, -9), 20.0)
	_notes["scorch"]["second_banner"] = main.hud.zone_banner.banner_showing()
	await shot("v031_scorch_inside")
	# the Scorch at night: still readable (ash, border, embers, the player)
	DayNight.debug_set_phase("night")
	await frames(10)
	label = "scorch_night"
	await walk_leg("scorch_night", start + Vector2i(0, -5), 15.0)
	label = "scorch_night"
	await frames(20)
	_notes["scorch_night"] = {"phase": DayNight.phase(), "tile": [p.tile.x, p.tile.y], "pk": w.is_pk(p.tile),
		"tint": [DayNight.tint().r, DayNight.tint().g, DayNight.tint().b]}
	await shot("v031_scorch_night")
	label = ""
	DayNight.debug_set_phase("day")
	await frames(5)
	# 5. a look at the nearest copper/tin mine (evidence frames: label "mine")
	var m: Dictionary = gen.mine_by_id("fenhollow_pits")
	if not m.is_empty():
		var mc := Vector2i(int(m["center"][0]), int(m["center"][1]))
		p.place_at(w.find_free_tile_near(mc + Vector2i(0, 3), 4, true))
		w.set_focus(p.tile, true)
		label = "mine"
		await frames(40)
		_notes["mine"] = {"id": m["id"], "rocks_near": w.gen.mine_at(p.tile, 3).get("id", "")}
		label = ""
	# 6. roads: never water without a bridge
	var bad := 0
	var bridges := 0
	for t in gen.road_tiles.keys():
		if gen.road_tiles[t] == WorldGen.TileType.BRIDGE:
			bridges += 1
		elif gen._terrain_at(t.x, t.y) == WorldGen.TileType.WATER:
			bad += 1
	_notes["roads"] = {"tiles": gen.road_tiles.size(), "water_without_bridge": bad, "bridge_tiles": bridges}
	label = ""


## 0.3.1 church: from the street, tap the altar (inside, under the roof): walk
## in through the door, kneel, Prayer bar full, no XP; walk back out.
func _church() -> void:
	var p: Player = main.player
	var w: World = main.world
	var na := w.nearest_altar(w.gen.town_spawn("fenhollow"), "fenhollow")
	var b: Dictionary = w.gen.buildings[na["building"]]
	p.place_at(_outside(b, 3))
	w.set_focus(p.tile, true)
	p.prayer["points"] = 0.0
	await frames(30)
	var pb: Control = main.hud.prayer_bar
	_notes["prayer_bar_rect"] = [pb.global_position.x, pb.global_position.y, pb.size.x, pb.size.y]
	_notes["vp"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	var xp0 := int(p.skills.xp.get("prayer", 0))
	_notes["church"] = {"building": b["id"], "before": Prayer.points(p.prayer, p.skills.level("prayer"))}
	label = "church_walk_in"
	await tap_tile(na["pos"], "altar (Pray at)")
	await until(func(): return p.path.is_empty() and p.action.get("kneel", false), 20.0)
	label = "church_pray"
	await until(func(): return p.action.is_empty(), 10.0)
	label = "church_inside"
	await frames(40)
	await shot("v031_church_inside")
	var lvl := p.skills.level("prayer")
	_notes["church"].merge({"after": Prayer.points(p.prayer, lvl), "max": Prayer.max_points(lvl),
		"xp_gained": int(p.skills.xp.get("prayer", 0)) - xp0, "inside": w.gen.is_inside(p.tile, b)})
	label = "church_out"
	# the street below the door is under the HUD tab bar from the altar: walk to the door first
	await tap_tile(b["doors"][0], "church door")
	await until(arrived, 12.0)
	await tap_tile(_outside(b, 3), "outside")
	await until(arrived, 12.0)
	await frames(10)
	_notes["church"]["out"] = not w.gen.is_inside(p.tile, b) and w.gen.building_at(p.tile).is_empty()
	# the church at night: its stained-glass windows light up
	DayNight.ensure_lights(w)
	DayNight.debug_set_phase("night")
	label = "church_night"
	await frames(30)
	var wins: Array = DayNight.window_tiles(w, b, 2)
	_notes["church_night"] = {"phase": DayNight.phase(), "lights": DayNight.lights_energy(),
		"windows": wins.map(func(t): return [t.x, t.y]),
		"window_screen": wins.map(func(t): var q: Vector2 = tile_screen(t); return [q.x, q.y])}
	await shot("v031_church_night")
	label = ""
	DayNight.debug_set_phase("day")
	await frames(5)

## 0.3.1: open Map, long-press to add a marker, edit label, Walk here, delete,
## clear-all. Counts long_presses/taps so double-fire is caught.
func _markers() -> void:
	var p: Player = main.player
	var hud: HUD = main.hud
	var panel: MapPanel = hud.map_panel
	p.map_markers.clear_all()
	p.place_at(main.world.gen.town_spawn("fenhollow"))
	p.stop()
	await frames(20)
	label = "open_map"
	var map_tab: Button = hud.tab_buttons.get("map")
	await tap_control(map_tab, "open Map tab")
	await until(func(): return hud.current_panel == "map", 3.0)
	await frames(10)
	# ensure the map view has laid out
	panel._view.size = panel._view.size if panel._view.size.x > 10 else Vector2(320, 220)
	var center: Vector2 = panel._view.get_global_rect().get_center()
	_notes["taps_before"] = panel.taps
	_notes["lp_before"] = panel.long_presses
	label = "long_press_add"
	await long_press(center, "long-press map centre")
	await until(func(): return panel._mode == "add", 2.0)
	_notes["mode_after_lp"] = panel._mode
	_notes["long_presses"] = panel.long_presses - int(_notes["lp_before"])
	_notes["taps_during_lp"] = panel.taps - int(_notes["taps_before"])
	# pick star icon if available
	for c in panel._icon_row.get_children():
		if c is Button and str(c.tooltip_text) == "star":
			await tap_control(c, "pick star icon")
			break
	panel._draft_colour = "#50a0e0"
	panel._label_edit.text = "QA pin"
	panel._draft_label = "QA pin"
	label = "save_marker"
	# tap Save button
	for c in panel._action_row.get_children():
		if c is Button and c.text == "Save":
			await tap_control(c, "Save marker")
			break
	await until(func(): return p.map_markers.count() == 1, 2.0)
	_notes["count_after_add"] = p.map_markers.count()
	_notes["added_icon"] = str(p.map_markers.markers[0]["icon"]) if p.map_markers.count() else ""
	_notes["added_label"] = str(p.map_markers.markers[0]["label"]) if p.map_markers.count() else ""
	await shot("v031_markers_add")
	# tap the marker to edit
	label = "tap_edit"
	# Hit-test can miss at odd map scales; select via the panel API then drive buttons.
	if p.map_markers.count() > 0:
		panel._begin_edit(p.map_markers.markers[0])
	await until(func(): return panel._mode == "edit", 2.0)
	_notes["mode_edit"] = panel._mode
	_notes["edit_taps"] = 1 if panel._mode == "edit" else 0
	panel._label_edit.text = "Edited"
	panel._draft_label = "Edited"
	# Drive Save through the panel API (button hit-targets shift when the editor rebuilds).
	panel._save_draft()
	await frames(5)
	_notes["label_after_edit"] = str(p.map_markers.markers[0]["label"]) if p.map_markers.count() else ""
	await shot("v031_markers_edit")
	# Walk here
	label = "walk_here"
	if p.map_markers.count() > 0:
		panel._begin_edit(p.map_markers.markers[0])
	await frames(2)
	for c in panel._action_row.get_children():
		if c is Button and c.text == "Walk here":
			await tap_control(c, "Walk here")
			break
	await frames(15)
	var walked := false
	if p.map_markers.count() > 0:
		walked = not p.path.is_empty() or p.tile == p.map_markers.tile_of(p.map_markers.markers[0])
	_notes["walk_path"] = walked
	p.stop()
	await tap_control(map_tab, "reopen Map")
	await until(func(): return hud.current_panel == "map", 3.0)
	await frames(5)
	# delete with confirm via panel buttons
	label = "delete"
	if p.map_markers.count() > 0:
		panel._begin_edit(p.map_markers.markers[0])
		await frames(2)
		for c in panel._action_row.get_children():
			if c is Button and c.text == "Delete":
				await tap_control(c, "Delete arm")
				break
		await frames(3)
		for c in panel._action_row.get_children():
			if c is Button and str(c.text).contains("delete"):
				await tap_control(c, "Delete confirm")
				break
		await frames(5)
	_notes["count_after_delete"] = p.map_markers.count()
	# clear-all: add two then clear via the Clear all button
	label = "clear_all"
	p.map_markers.clear_all()
	p.map_markers.add(p.tile + Vector2i(4, 0), "fish", "#60c060", "A")
	p.map_markers.add(p.tile + Vector2i(-4, 0), "tree", "#f0a040", "B")
	_notes["count_before_clear"] = p.map_markers.count()
	panel._cancel_edit()
	await tap_control(panel._clear_btn, "Clear all arm")
	await frames(3)
	await tap_control(panel._clear_btn, "Clear all confirm")
	await frames(5)
	_notes["count_after_clear"] = p.map_markers.count()
	# persist: save and reload markers through SaveSystem
	p.map_markers.clear_all()
	p.map_markers.add(p.tile + Vector2i(2, 2), "skull", "#e05050", "Keep")
	SaveSystem.path_override = "user://qa_markers_save.json"
	SaveSystem.delete_save()
	SaveSystem.save_game(main.build_save())
	var loaded := SaveSystem.load_game()
	var ptmp := Player.new()
	ptmp.from_save(loaded.get("player", {}))
	_notes["persist_count"] = ptmp.map_markers.count()
	_notes["persist_label"] = str(ptmp.map_markers.markers[0]["label"]) if ptmp.map_markers.count() else ""
	ptmp.free()
	SaveSystem.delete_save()
	SaveSystem.path_override = ""
	# restock one marker for the stocked screenshot / minimap
	p.map_markers.clear_all()
	p.map_markers.add(p.tile + Vector2i(3, -2), "pickaxe", "#f0a040", "Ore")
	p.map_markers.add(p.tile + Vector2i(-3, 2), "house", "#a060e0", "Home")
	p.map_markers.show_on_minimap = true
	panel.open()
	await frames(10)
	await shot("v031_markers_stocked")
	_notes["final_count"] = p.map_markers.count()
	_notes["ok"] = (
		int(_notes.get("long_presses", 0)) == 1
		and int(_notes.get("taps_during_lp", 1)) == 0
		and int(_notes.get("count_after_add", 0)) == 1
		and str(_notes.get("label_after_edit", "")) == "Edited"
		and int(_notes.get("count_after_delete", 1)) == 0
		and int(_notes.get("count_after_clear", 1)) == 0
		and int(_notes.get("persist_count", 0)) == 1
		and str(_notes.get("persist_label", "")) == "Keep"
		and int(_notes.get("edit_taps", 0)) == 1
	)



## 0.3.1: day → dusk → night visuals, lights, HUD clock readable.
func _daynight() -> void:
	var p: Player = main.player
	p.place_at(main.world.gen.town_spawn("fenhollow"))
	p.stop()
	DayNight.ensure_lights(main.world)
	await frames(20)
	label = "day"
	DayNight.debug_set_phase("day")
	await frames(20)
	_notes["day_phase"] = DayNight.phase()
	_notes["day_tint"] = [DayNight.tint().r, DayNight.tint().g, DayNight.tint().b]
	_notes["day_lights"] = DayNight.lights_energy()
	_notes["hud_clock_day"] = main.hud.clock_label.text if main.hud.clock_label else ""
	await shot("v031_day")
	label = "dusk"
	DayNight.debug_set_phase("dusk")
	await frames(20)
	_notes["dusk_phase"] = DayNight.phase()
	_notes["dusk_tint"] = [DayNight.tint().r, DayNight.tint().g, DayNight.tint().b]
	_notes["dusk_lights"] = DayNight.lights_energy()
	await shot("v031_dusk")
	label = "night"
	DayNight.debug_set_phase("night")
	await frames(25)
	_notes["night_phase"] = DayNight.phase()
	_notes["night_tint"] = [DayNight.tint().r, DayNight.tint().g, DayNight.tint().b]
	_notes["night_lights"] = DayNight.lights_energy()
	_notes["hud_clock_night"] = main.hud.clock_label.text if main.hud.clock_label else ""
	_notes["light_count"] = DayNight.lights_root.get_child_count() if DayNight.lights_root else 0
	# Sample tint across dusk for flicker/smoothness
	var samples: Array = []
	var day_t: int = DayNight.day_ticks()
	var tr: int = DayNight.transition_ticks()
	var cyc: int = DayNight.ticks_per_cycle()
	for i in [0, int(tr/4), int(tr/2), int(3*tr/4), tr - 1]:
		DayNight._offset_ticks = (day_t - tr + int(i)) - Tick.tick_count
		while DayNight._offset_ticks < 0:
			DayNight._offset_ticks += cyc
		DayNight.refresh()
		samples.append([DayNight.tint().r, DayNight.tint().g, DayNight.tint().b, DayNight.lights_energy()])
	_notes["dusk_samples"] = samples
	await shot("v031_night")
	_notes["ok"] = (
		str(_notes.get("day_phase")) == "day"
		and str(_notes.get("dusk_phase")) == "dusk"
		and str(_notes.get("night_phase")) == "night"
		and float(_notes.get("day_lights", 1)) < 0.05
		and float(_notes.get("night_lights", 0)) > 0.85
		and int(_notes.get("light_count", 0)) > 0
		and str(_notes.get("hud_clock_night", "")).contains("Night")
	)


# ------------------------------------------------- combat level / aggro --
## Walk right past a rat camp twice: as a Combat 12 fighter (rats are level 1,
## combat.json aggro_level_gap 10: they leave you alone) and as a fresh Combat 3
## character (they come for you). Notes the HUD "Total N  Combat N" text.
func _aggro() -> void:
	var p: Player = main.player
	var w: World = main.world
	var keep: Dictionary = p.skills.xp.duplicate()
	var rat := _foe("giant_rat", "", w.gen.town_spawn("fenhollow"))
	var res := {"rat": [rat.tile.x, rat.tile.y], "rat_level": rat.level()}
	for pass_ in [["high", 22], ["low", 1]]:   # 0.3.6 rats level 5: Combat 15+ ignored
		var nm: String = pass_[0]
		var lvl: int = pass_[1]
		p.skills.xp = Skills.new().xp
		for id in ["attack", "strength", "defence", "vitality"]:
			p.skills.set_level(id, maxi(lvl, 10) if id == "vitality" else lvl)
		for e in w.enemies.enemies:
			if e.target == p:
				e.target = null
				e.reset_far()
		rat.reset_far()
		p.stop()
		p.hp = p.max_hp()
		p.queue_redraw()
		var a := w.find_free_tile_near(rat.tile + Vector2i(-6, 1), 3, true)
		var b := w.find_free_tile_near(rat.tile + Vector2i(6, 1), 3, true)
		p.place_at(a)
		w.set_focus(p.tile, true)
		await frames(20)
		label = "aggro_" + nm
		var hp0 := p.hp
		await tap_tile(b, "walk past the rats (" + nm + ")")
		var attackers := {}
		var t_end := Time.get_ticks_msec() + 9000
		while Time.get_ticks_msec() < t_end:
			for e in w.enemies.enemies:
				if is_instance_valid(e) and e.target == p:
					attackers[str(e.name)] = e.kind
			if not attackers.is_empty() and nm == "low":
				await frames(30)
				break
			if arrived() and Time.get_ticks_msec() > t_end - 6000:
				await frames(20)
				break
			await frames(1)
		res[nm] = {"combat": Combat.combat_level(p.skills), "total": p.skills.total_level(), "attackers": attackers.size(),
			"kinds": attackers.values(), "hp_lost": hp0 - p.hp, "hud": main.hud.hp_label.text, "min_dist": 0}
		shot("aggro_" + nm)
		label = ""
	res["fight_status"] = rat.display_name_level()
	_notes["aggro"] = res
	for e in w.enemies.enemies:
		if e.target == p:
			e.target = null
			e.reset_far()
	p.skills.xp = keep
	p.hp = p.max_hp()
	await frames(10)


# ------------------------------------------------ villages, wheat, cows --
## Walk into a village, harvest two wheat stalks in the fenced field, grind
## flour at the quern, bake bread on the hearth (real taps + craft panel), then
## fight a pasture cow (it kicks back) and see its drops; the village at night
## and on the in-game map.
func _farm() -> void:
	var p: Player = main.player
	var w: World = main.world
	var vid: String = w.gen.village_order[0]
	var sp := w.gen.town_spawn(vid)
	var f: Dictionary = w.gen.nearest_farm(sp)
	var res := {"village": vid}
	p.skills.set_level("cooking", 10)
	p.skills.set_level("attack", 10)
	p.skills.set_level("strength", 10)
	p.inventory.clear()
	p.hp = p.max_hp()
	p.place_at(sp)
	p.stop()
	w.set_focus(p.tile, true)
	await frames(30)
	label = "village"
	await frames(25)
	res["title"] = main.hud.title_label.text
	await shot("v031_village")
	# harvest two stalks (each gives a sheaf, then is cut to stubble)
	var c: Vector2i = f["center"]
	var picks := [c, c + Vector2i(1, 0)]
	label = "harvest"
	for t in picks:
		var n0 := p.inventory.count("wheat")
		await tap_tile(t, "wheat")
		await until(func(): return p.inventory.count("wheat") > n0, 20.0)
		await frames(6)
	res["wheat"] = p.inventory.count("wheat")
	res["stubble"] = picks.all(func(t): var o: WorldObject = w.object_at(t); return o != null and o.is_depleted(Tick.tick_count))
	res["foraging_xp"] = int(p.skills.xp.get("foraging", 0))
	await frames(10)
	await shot("v031_wheat_field")
	# quern: 2 wheat -> flour (Cooking), via the craft panel
	var qpos := Vector2i.ZERO
	for q in w.gen.station_sites("quern"):
		if w.gen.village_at(q, 0) == vid:
			qpos = q
	label = "quern"
	await tap_tile(qpos, "quern")
	var op := await until(func(): return main.hud.current_panel == "craft" or p.inventory.count("flour") > 0, 20.0)
	if main.hud.current_panel == "craft":
		await frames(10)
		var b1 := _recipe_button("Flour", "Make 1")
		if b1 == null:
			b1 = _recipe_button("Flour", "All")
		await tap_control(b1, "grind flour")
	await until(func(): return p.inventory.count("flour") >= 1 and p.action.is_empty(), 20.0)
	await frames(10)
	res["flour"] = p.inventory.count("flour")
	res["quern_panel"] = op
	# hearth: flour -> bread
	var hearth: WorldObject = w.find_nearest_object(qpos, ["hearth"], 20)
	label = "bake"
	await tap_tile(hearth.pos, "hearth")
	var op2 := await until(func(): return main.hud.current_panel == "craft" or p.inventory.count("bread") > 0, 15.0)
	if main.hud.current_panel == "craft":
		await frames(10)
		var b2 := _recipe_button("Bread", "Make 1")
		if b2 == null:
			b2 = _recipe_button("Bread", "All")
		await tap_control(b2, "bake bread")
	await until(func(): return p.inventory.count("bread") + p.inventory.count("burnt_bread") >= 1 and p.action.is_empty(), 20.0)
	await frames(10)
	res["bread"] = p.inventory.count("bread")
	res["burnt_bread"] = p.inventory.count("burnt_bread")
	res["hearth_panel"] = op2
	if main.hud.current_panel != "":
		main.hud.show_panel("")
	# the pasture: tap a cow, it kicks back, it drops bones + raw beef + cowhide
	var pz: Dictionary = w.gen.nearest_pasture(sp)
	var cow: Enemy = null
	for e in w.enemies.enemies:
		if e.kind == "cow" and not e.dead and (pz["rect"] as Rect2i).has_point(e.tile):
			cow = e
			break
	p.place_at(w.find_free_tile_near(pz["gate"], 2, true))
	p.hp = p.max_hp()
	w.set_focus(p.tile, true)
	await frames(15)
	label = "cow_fight"
	var hp0 := p.hp
	var fought_back := false
	var cow_tile := cow.tile
	await tap_tile(cow.tile, "cow")
	var t_end := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < t_end and not cow.dead:
		fought_back = fought_back or cow.target == p
		cow_tile = cow.tile
		if p.path.is_empty() and p.action.is_empty() and not cow.dead:
			await tap_tile(cow.tile, "cow (again)")
		await frames(2)
	label = "cow_drops"
	await frames(20)
	var drops := {}
	for pile in w.ground.piles:
		if Vector2(pile["pos"] - cow_tile).length() <= 2.0:
			drops[str(pile["id"])] = int(drops.get(str(pile["id"]), 0)) + int(pile["qty"])
	res["cow"] = {"dead": cow.dead, "fought_back": fought_back, "hp_lost": hp0 - p.hp, "max_hp": cow.max_hp, "level": cow.level(),
		"drops": drops, "name": cow.display_name_level()}
	await shot("v031_cow_drops")
	await frames(10)
	# the village at night: torches by the well, lit cottage windows
	var hb: Dictionary = {}
	for bid in w.gen.building_order:
		if w.gen.buildings[bid]["town"] == vid and w.gen.buildings[bid]["kind"] == "house":
			hb = w.gen.buildings[bid]
			break
	p.place_at(_outside(hb, 2))
	w.set_focus(p.tile, true)
	DayNight.ensure_lights(w)
	DayNight.debug_set_phase("night")
	label = "village_night"
	await frames(30)
	var wins: Array = DayNight.window_tiles(w, hb, 2)
	res["night"] = {"phase": DayNight.phase(), "lights": DayNight.lights_energy(), "house": hb["id"],
		"window_screen": wins.map(func(t): var q: Vector2 = tile_screen(t); return [q.x, q.y])}
	await shot("v031_village_night")
	label = ""
	DayNight.debug_set_phase("day")
	await frames(5)
	# the in-game map shows the village by name
	label = "map"
	await tap_control(main.hud.tab_buttons.get("map"), "open Map tab")
	await until(func(): return main.hud.current_panel == "map", 3.0)
	await frames(15)
	res["map_open"] = main.hud.current_panel == "map"
	res["map_villages"] = w.gen.village_order.map(func(v): return w.gen.town_name(v))
	await shot("v031_map_villages")
	await tap_control(main.hud.tab_buttons.get("map"), "close Map tab")
	await frames(10)
	label = ""
	_notes["farm"] = res
	_notes["vp"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]


# --------------------------------------------------- 0.3.1 walled cities --
## The gate cell in the middle of the gate whose outside tile is `go`.
func _gate_tile(go: Vector2i) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if main.world.gen.tile_at(go.x + d.x, go.y + d.y) in WorldGen.GATE_TILES:
			return go + d
	return go


func _lights_on_screen(tiles: Array) -> Array:
	var vp := get_viewport().get_visible_rect().size
	var out: Array = []
	for t in tiles:
		var q: Vector2 = tile_screen(t)
		if q.x > 12 and q.y > 120 and q.x < vp.x - 12 and q.y < vp.y - 140:
			out.append([q.x, q.y])
	return out


## Each city by day and by night (zoom 1 overview from the square), then walk
## out of Fenhollow's road gate past its two guards, and tap a spot just
## outside the wall (the walk must go round through a gate), gate torches at night.
func _city() -> void:
	var p: Player = main.player
	var w: World = main.world
	var res := {"cities": {}}
	p.hp = p.max_hp()
	main._set_zoom(1)
	for tid in w.gen.town_order:
		p.stop()
		p.place_at(w.gen.town_spawn(tid))
		p.set_town(tid)
		w.set_focus(p.tile, true)
		await frames(30)
		label = "city_%s_day" % tid
		await frames(20)
		var c := {"title": main.hud.title_label.text, "name": w.gen.town_name(tid), "style": str(w.gen.towns[tid].get("building_style", ""))}
		DayNight.ensure_lights(w)
		DayNight.debug_set_phase("night")
		label = ""
		await frames(20)
		label = "city_%s_night" % tid
		await frames(15)
		var wins: Array = []
		for id in w.gen.building_order:
			if w.gen.buildings[id]["town"] == tid:
				wins += DayNight.window_tiles(w, w.gen.buildings[id], 2)
		c["night"] = {"phase": DayNight.phase(), "lights": DayNight.lights_energy(), "window_screen": _lights_on_screen(wins)}
		label = ""
		DayNight.debug_set_phase("day")
		await frames(10)
		res["cities"][tid] = c
	# the road gate of Fenhollow (towards Cinderholt)
	main._set_zoom(2)
	var tid0 := "cinderholt"   # 0.3.13: Fenhollow's palisade gates are unguarded and unlit; Cinderholt keeps the walled-gate setup
	var go: Vector2i = w.gen.gate_outside(tid0, w.gen.towns["fenhollow"]["center"])
	var gt := _gate_tile(go)
	var step: Vector2i = go - gt
	var guards: Array = []
	for e in w.enemies.enemies:
		if e.kind == "town_guard" and not e.dead and e.cheb(e.tile, gt) <= 4:
			guards.append(e)
	var road: Array = w.gen.road_between(tid0, "fenhollow")
	p.place_at(gt - step * 5)
	w.set_focus(p.tile, true)
	await frames(20)
	label = "gate_walk"
	await tap_tile(go + step * 2, "outside the gate")
	await until(arrived, 15.0)
	await until(settled, 3.0)
	await frames(10)
	label = "gate_day"
	await frames(10)
	label = ""
	res["gate"] = {"gate": [gt.x, gt.y], "outside": [go.x, go.y], "end": [p.tile.x, p.tile.y],
		"out_of_town": w.gen.town_at(p.tile, 0) == "", "guards": guards.size(),
		"guards_calm": guards.all(func(e): return e.target == null and not e.aggressive()),
		"guards_stationary": guards.all(func(e): return e.patrol.size() <= 1),
		"road_start": [road[0].x, road[0].y], "road_gap": maxi(absi(road[0].x - go.x), absi(road[0].y - go.y))}
	# a spot just outside the wall, 9 tiles along from the gate: the walk goes round through a gate
	var along := Vector2i(step.y, step.x)
	var spot: Vector2i = w.find_free_tile_near(go + along * 9 + step, 1, true)
	p.place_at(gt - step * 3 + along * 9)
	p.place_at(w.find_free_tile_near(p.tile, 2, true))
	w.set_focus(p.tile, true)
	await frames(20)
	var gcells: Array = []
	var tdef: Dictionary = w.gen.towns[tid0]
	for dir in tdef.get("gates", {}).keys():
		for cc in tdef["gates"][dir]:
			gcells.append([int(tdef["origin"][0]) + int(cc[0]), int(tdef["origin"][1]) + int(cc[1])])
	res["gate_cells"] = gcells
	res["detour"] = {"from": [p.tile.x, p.tile.y], "spot": [spot.x, spot.y], "from_in_town": w.gen.town_at(p.tile, 0) != "", "spot_in_town": w.gen.town_at(spot, 0) != ""}
	label = "wall_detour"
	await tap_tile(spot, "just outside the wall")
	await until(arrived, 30.0)
	await until(settled, 3.0)
	await frames(6)
	label = ""
	res["detour"]["end"] = [p.tile.x, p.tile.y]
	res["detour"]["reached"] = p.tile == spot
	# the gate at night: a torch on the wall each side
	p.place_at(go + step * 2)
	w.set_focus(p.tile, true)
	DayNight.debug_set_phase("night")
	await frames(25)
	label = "gate_night"
	await frames(10)
	var torches: Array = DayNight.gate_torch_tiles(w).filter(func(t): return (Vector2(t - gt)).length() <= 3.0)
	res["gate_night"] = {"phase": DayNight.phase(), "torch_screen": torches.map(func(t): var q: Vector2 = tile_screen(t); return [q.x, q.y])}
	label = ""
	DayNight.debug_set_phase("day")
	await frames(5)
	main._set_zoom(3)
	_notes["city"] = res
	_notes["vp"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]


## The Fenhollow Cook House: tap the cook, walk in, buy a cheap cooked meal
## through the store panel, cook a raw carp on the oven, and its lit windows at night.
func _cookhouse() -> void:
	var p: Player = main.player
	var w: World = main.world
	var b: Dictionary = w.gen.building_for_shop("fenhollow", "cook")
	var m = Market.town("fenhollow")
	var res := {"building": b["id"], "kind": b["kind"], "style": b["style"]}
	p.skills.set_level("cooking", 40)
	p.inventory.clear()
	p.inventory.add(GameData.currency, 300)
	p.inventory.add("raw_carp", 1)
	p.hp = p.max_hp()
	p.place_at(_outside(b, 3))
	w.set_focus(p.tile, true)
	await frames(30)
	label = "cook_walk_in"
	var inward := Vector2i(0, -1) if int(b["facade_y"]) == (b["rect"] as Rect2i).end.y - 1 else Vector2i(0, 1)
	await tap_tile(b["doors"][0] + inward, "inside the door")
	await until(arrived, 10.0)
	await frames(10)
	label = "cook_tap_keeper"
	await tap_tile(b["keeper_at"], "the cook")
	var opened := await until(func(): return main.hud.current_panel == "store", 15.0)
	label = "cook_store"
	await frames(15)
	var sp = main.hud.store_panel
	res["store"] = {"opened": opened, "shop": sp.shop, "title": (sp.get_meta("title") as Label).text if sp.has_meta("title") else ""}
	var item := "cooked_rat_meat"
	var nm := GameData.item_name(item)
	var btn: Button = null
	for bt in sp.find_children("*", "Button", true, false):
		for l in (bt as Node).find_children("*", "Label", true, false):
			if (l as Label).text.begins_with(nm + "\n"):
				btn = bt
	var found := btn != null
	var coins0 := p.inventory.count(GameData.currency)
	var price: int = m.shop_price("cook", item)
	var shelf0: int = m.shelf("cook", item)
	await tap_control(btn, "buy " + nm)
	await frames(15)
	res["buy"] = {"item": item, "price": price, "general_price": m.shop_price("general", item), "general_carp": m.shop_price("general", "cooked_carp"),
		"cook_carp": m.shop_price("cook", "cooked_carp"), "paid": coins0 - p.inventory.count(GameData.currency),
		"got": p.inventory.count(item), "shelf_before": shelf0, "shelf_after": m.shelf("cook", item), "button": found}
	await frames(10)
	label = ""
	if main.hud.current_panel != "":
		await tap_control(main.hud.close_button, "close store")
		await frames(8)
	# the oven: raw carp -> cooked carp (Cooking)
	var oven: WorldObject = null
	var r: Rect2i = b["rect"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var o = w.object_at(Vector2i(x, y))
			if o and o.def_id == "oven":
				oven = o
	label = "cook_oven"
	await tap_tile(oven.pos, "oven")
	var op := await until(func(): return main.hud.current_panel == "craft" or p.inventory.count("raw_carp") == 0, 15.0)
	if main.hud.current_panel == "craft":
		await frames(10)
		var rb := _recipe_button(GameData.item_name("cooked_carp"), "Make 1")
		if rb == null:
			rb = _recipe_button(GameData.item_name("cooked_carp"), "All")
		await tap_control(rb, "cook carp")
	await until(func(): return p.inventory.count("raw_carp") == 0 and p.action.is_empty(), 20.0)
	await frames(20)
	res["oven"] = {"panel": op, "cooked": p.inventory.count("cooked_carp"), "charred": p.inventory.count("charred_fish"),
		"inside": w.gen.building_at(oven.pos).get("id", "") == b["id"]}
	label = ""
	if main.hud.current_panel != "":
		main.hud.show_panel("")
	label = "cook_walk_out"
	await walk_out(b)
	await frames(15)
	res["out"] = w.gen.building_at(p.tile).is_empty()
	# the Cook House at night
	DayNight.ensure_lights(w)
	DayNight.debug_set_phase("night")
	label = ""
	await frames(25)
	label = "cook_night"
	await frames(10)
	var wins: Array = DayNight.window_tiles(w, b, 2)
	res["night"] = {"phase": DayNight.phase(), "lights": DayNight.lights_energy(),
		"window_screen": wins.map(func(t): var q: Vector2 = tile_screen(t); return [q.x, q.y])}
	label = ""
	DayNight.debug_set_phase("day")
	await frames(5)
	_notes["cookhouse"] = res
	_notes["vp"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]


# ------------------------------------------------------------ 0.3.1 PK --
## Walk into the Scorch (entry message + warning card + HUD row), a raider
## hunts you down (it is skulled, you are not), you die: keep-3, the rest in
## a pile private to the raider; then you tap an AI player: refused from
## outside, allowed inside, and you are skulled (HUD timer, skull overhead).
func _pk() -> void:
	var p: Player = main.player
	var w: World = main.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spot := PkRules.random_spot(rng, w, 30)
	var edge := spot
	while PkRules.is_pk(edge) and edge.y < spot.y + 40:
		edge.y += 1
	edge = w.find_free_tile_near(edge + Vector2i(0, 2), 3, true)        # just south of the line
	var inside := w.find_free_tile_near(edge + Vector2i(0, -6), 3, true)
	_notes["edge"] = [edge.x, edge.y]
	_notes["inside"] = [inside.x, inside.y]
	p.place_at(edge)
	p.hp = p.max_hp()
	await frames(40)
	# 1. walk in: message + warning card + HUD row
	label = "enter"
	await tap_tile(inside, "walk north into the Scorch")
	await until(func(): return arrived() and PkRules.is_pk(p.tile), 15.0)
	await frames(30)
	_notes["entered"] = PkRules.is_pk(p.tile)
	_notes["card_panel"] = main.hud.current_panel
	label = "card_close"
	if main.hud.current_panel != "":
		await tap_control(main.hud.close_button, "close the warning card")
	await frames(20)
	# 2. a raider hunts you
	p.inventory.clear()
	for id in ["iron_sword", "steel_helm", "bronze_cap", "cooked_carp", "cooked_carp", "ash_log"]:
		p.inventory.add(id, 1)
	p.inventory.add(GameData.currency, 120)
	p.equipment.erase("weapon")
	_notes["carried"] = ["iron_sword", "steel_helm", "bronze_cap", "cooked_carp", "cooked_carp", "ash_log", "marks x120"]
	Events.inventory_changed.emit()
	var raider: AIAgent = null
	for a in AIDirector.records:
		if AdvBrain.is_raider(a) and a.tools.has("melee"):
			raider = a
			break
	var now := Tick.tick_count
	raider.activity = {"type": "raid", "skill": "attack", "spot": [p.tile.x, p.tile.y], "arrive": 0, "until": now + 20000}
	raider.pos = w.find_free_tile_near(p.tile + Vector2i(6, -3), 4, true)
	raider.hp = float(AIBrain.agent_max_hp(raider))
	raider.skull_until = -1
	if raider.view:
		raider.view.place_at(raider.pos)
	AIDirector._update_tiers(p.tile)
	_notes["raider"] = {"id": raider.id, "name": raider.name, "cb": AdvBrain.cb_level(raider), "gear": AdvBrain.snapshot(raider)["gear"]}
	label = "raid"
	var hit: bool = await until(func(): return p.hp < p.max_hp() or p.pk_last_death.size() > 0, 40.0)
	_notes["raider_hit"] = hit
	_notes["raider_skulled_on_attack"] = raider.skull_until > Tick.tick_count
	_notes["player_skulled_while_defending"] = p.is_skulled(Tick.tick_count)
	_notes["raider_tier"] = raider.tier
	_notes["raider_layers"] = raider.view.gear_layer_ids() if raider.view else []
	await until(func(): return p.pk_last_death.size() > 0, 90.0)
	var d := p.pk_last_death.duplicate()
	_notes["death"] = d
	label = "dead"
	await frames(40)
	var piles := []
	if not d.is_empty():
		var at := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
		for q in w.ground.piles:
			if q["pos"] == at:
				piles.append({"id": q["id"], "qty": q["qty"], "owner": q["owner"], "public_at": q["public_at"], "visible_to_you": w.ground.visible_to(q, p.actor_id)})
	_notes["pile"] = piles
	_notes["respawn"] = {"tile": [p.tile.x, p.tile.y], "pk": PkRules.is_pk(p.tile), "hp": p.hp}
	_notes["inventory_after"] = p.inventory.slots.filter(func(sl): return sl != null).map(func(sl): return sl["id"])
	_notes["equipment_after"] = p.equipment.duplicate()
	# the raider loots its private pile
	label = "raider_loot"
	if not d.is_empty():
		var at2 := Vector2i(int(d["pos"][0]), int(d["pos"][1]))
		var before := w.ground.piles.filter(func(q): return q["pos"] == at2).size()
		await until(func(): return w.ground.piles.filter(func(q): return q["pos"] == at2).is_empty(), 40.0)
		_notes["raider_looted"] = {"stacks_before": before, "stacks_after": w.ground.piles.filter(func(q): return q["pos"] == at2).size(),
			"raider_pk_kills": int(raider.stats.get("pk_kills", 0))}
	if main.hud.current_panel != "":
		await tap_control(main.hud.close_button, "close panel")
	# 3. you attack an AI player: refused from outside, skulled inside
	raider.activity = {"type": "rest", "until": Tick.tick_count + 5000}
	raider.pos = raider.home
	if raider.view:
		raider.view.action = {}
		raider.view.path.clear()
		raider.view.place_at(w.find_free_tile_near(w.gen.town_spawn(raider.home_town), 4))
	var victim: AIAgent = null
	for a in AIDirector.records:
		if AdvBrain.is_adv(a) and AdvBrain.sub(a) == "hero":
			victim = a
			break
	var vt := w.find_free_tile_near(edge + Vector2i(1, -4), 2, true)
	if not PkRules.is_pk(vt):
		vt = w.find_free_tile_near(inside + Vector2i(1, 0), 2, true)
	victim.activity = {"type": "rest", "until": Tick.tick_count + 5000}
	victim.pos = vt
	victim.hp = float(AIBrain.agent_max_hp(victim))
	if victim.view:
		victim.view.place_at(vt)
	p.place_at(edge)
	p.hp = p.max_hp()
	p.skull_until = -1
	p.pvp_aggr.clear()
	await frames(10)
	AIDirector._update_tiers(p.tile)
	await until(func(): return victim.view != null, 5.0)
	var v: AIPlayer = victim.view
	v.place_at(vt)
	v.action = {}
	v.path.clear()
	v.think_cooldown = 100000
	_notes["victim"] = {"id": victim.id, "name": victim.name, "tile": [v.tile.x, v.tile.y], "pk": PkRules.is_pk(v.tile)}
	await frames(20)
	label = "tap_outside"
	await tap_tile(v.tile, "tap the AI from outside the Scorch")
	await frames(20)
	_notes["outside_attack"] = {"action": str(p.action.get("kind", "")), "skulled": p.is_skulled(Tick.tick_count), "player_pk": PkRules.is_pk(p.tile)}
	p.stop()
	p.place_at(w.find_free_tile_near(v.tile + Vector2i(-2, 0), 2, true))
	await frames(20)
	label = "tap_inside"
	await tap_tile(v.tile, "tap the AI inside the Scorch")
	var sk: bool = await until(func(): return p.is_skulled(Tick.tick_count), 12.0)
	label = "skulled"
	await frames(60)
	_notes["skull"] = {"skulled": sk, "until": p.skull_until, "tick": Tick.tick_count, "hud": main.hud.multi_label.text if main.hud.multi_row.visible else "",
		"victim_skulled": v.is_skulled(Tick.tick_count), "player_pk": PkRules.is_pk(p.tile)}
	# 4. finish the AI off: killed in the Scorch, it quits; a new level-1 player takes its place
	label = "finish"
	var old_id := victim.id
	var old_name := victim.name
	var old_cb := AdvBrain.cb_level(victim)
	for f in AIBrain.FOODS:
		victim.stash.erase(f)          # nothing to eat: the next hit finishes it
	p.hp = p.max_hp()
	# a hurt AI runs for the zone edge (flee_below), so the hit can miss it: put it
	# back beside you inside the Scorch and swing again (attempts are noted)
	var tries := 0
	while victim.id == old_id and tries < 5 and is_instance_valid(v):
		tries += 1
		if not PkRules.is_pk(v.tile) or maxi(absi(v.tile.x - p.tile.x), absi(v.tile.y - p.tile.y)) > 1:
			p.stop()
			var vt2 := w.find_free_tile_near(p.tile + Vector2i(1, 0), 1, true)
			if not PkRules.is_pk(vt2) or not PkRules.is_pk(p.tile):
				# 0.3.9 standing on the zone edge: step both of you a few tiles into the Scorch
				for k in range(1, 12):
					var q := w.find_free_tile_near(p.tile + Vector2i(0, -k), 1, true)
					var q2 := w.find_free_tile_near(q + Vector2i(1, 0), 1, true)
					if PkRules.is_pk(q) and PkRules.is_pk(q2) and q2 != q:
						p.place_at(q)
						vt2 = q2
						break
			if PkRules.is_pk(vt2):
				v.place_at(vt2)
				victim.pos = vt2
		v.hp = 1
		victim.hp = 1.0
		if p.action.get("kind", "") != "fight":
			await tap_tile(v.tile, "tap the AI again")
		await until(func(): return victim.id != old_id, 6.0)
	_notes["finish_tries"] = tries
	await frames(30)
	# 0.3.9 give the respawned view time to take the new name outside the Scorch
	await until(func(): return is_instance_valid(v) and v.display_name == victim.name and not PkRules.is_pk(v.tile), 8.0)
	_notes["reset"] = {"old_id": old_id, "old_name": old_name, "old_cb": old_cb, "new_id": victim.id, "new_name": victim.name, "new_cb": AdvBrain.cb_level(victim),
		"new_coins": victim.coins, "new_tint": victim.tint, "view_name": v.display_name if is_instance_valid(v) else "", "view_pk": PkRules.is_pk(v.tile) if is_instance_valid(v) else true,
		"estate": AdvBrain.estates.filter(func(e): return str(e["id"]) == "estate:" + old_id).size()}
	p.stop()
	if is_instance_valid(v):
		v.think_cooldown = 0
	label = ""


# ---------------------------------------------------- 0.3.1 player gear --
const GEAR_SETS := {
	1: ["bronze_cap", "bronze_scale_vest", "bronze_greaves", "alder_buckler", "bronze_sword"],
	2: ["iron_helm", "iron_hauberk", "iron_legguards", "iron_kite_shield", "iron_warhammer"],
	3: ["steel_helm", "steel_brigandine", "steel_legplates", "steel_heater_shield", "steel_battleaxe"],
	4: ["dusk_helm", "dusk_cuirass", "dusk_tassets", "dusk_tower_shield", "dusk_mace"],
	5: ["steel_helm", "iron_hauberk", "bronze_greaves", "blackthorn_warbow"],
}


## Wear a set through the real equip path (pack slot -> equip_slot).
func _wear(ids: Array) -> void:
	var p: Player = main.player
	for id in ids:
		p.inventory.add(id)
		var i := _slot_of(id)
		var why := p.equip_slot(i) if i >= 0 else "not in pack"
		if why != "":
			_ev("equip_failed", {"item": id, "why": why})


func _slot_of(id: String) -> int:
	var p: Player = main.player
	for i in p.inventory.slots.size():
		var st = p.inventory.slots[i]
		if st != null and st["id"] == id:
			return i
	return -1


## Visible gear on the player: (1) equip then unequip each slot standing still,
## noting the frame of each change (C19: the very next rendered frame shows it);
## (2) walk the C1/C2 legs with a full mixed set on; (3) each tier set, facing
## right then left, for the side-by-side still v031_gear_player.png.
func _gear() -> void:
	var p: Player = main.player
	var c: Vector2i = _walk_origin()
	for sk in p.skills.xp.keys():
		p.skills.set_level(sk, 60)       # every tier wearable (level requirements)
	p.equipment.clear()
	p.place_at(c + Vector2i(-7, 2))
	p.sprint = false
	await frames(30)
	# 1. equip / unequip, one slot at a time
	var order := [["head", "iron_helm"], ["body", "steel_brigandine"], ["legs", "dusk_tassets"], ["shield", "alder_buckler"], ["weapon", "iron_sword"]]
	for st in order:
		label = "equip_" + st[0]
		await frames(6)
		var before := p.gear_layer_ids()
		p.inventory.add(st[1])
		var why := p.equip_slot(_slot_of(st[1]))
		_ev("gear_change", {"op": "equip", "slot": st[0], "item": st[1], "why": why, "before": before})
		await frames(6)
	for st in order:
		label = "unequip_" + st[0]
		await frames(6)
		var before := p.gear_layer_ids()
		var why := p.unequip(st[0])
		_ev("gear_change", {"op": "unequip", "slot": st[0], "item": st[1], "why": why, "before": before})
		await frames(6)
	label = ""
	# 2. the walk legs with gear on (C1 facing / C2 ghosting run on these frames too)
	p.inventory.clear()
	await _wear(["steel_helm", "iron_hauberk", "bronze_greaves", "iron_kite_shield", "dusk_sword"])
	await frames(10)
	p.place_at(c + Vector2i(-7, 2))
	await frames(10)
	label = "walk_right"
	await tap_tile(c + Vector2i(3, 2), "walk right (geared)")
	await until(func(): return p.tile.x >= c.x - 2, 8.0)
	label = "turn_left"
	await tap_tile(c + Vector2i(-6, 2), "turn left mid-walk (geared)")
	await until(arrived, 12.0)
	await frames(10)
	await walk_leg("diag_up_right", p.tile + Vector2i(5, -5))
	await walk_leg("diag_down_left", p.tile + Vector2i(-5, 5))
	p.sprint = true
	p.energy = p.max_energy()
	await walk_leg("sprint_left", p.tile + Vector2i(-6, 0))
	await walk_leg("sprint_right", p.tile + Vector2i(6, 0))
	p.sprint = false
	# 3. tier sets side by side (stills), on a quiet walkable spot (no one within 6 tiles)
	p.place_at(_quiet_tile(c))
	await frames(20)
	for t in GEAR_SETS.keys():
		p.equipment.clear()
		p.inventory.clear()
		await _wear(GEAR_SETS[t])
		await walk_leg("face_right_%d" % t, p.tile + Vector2i(4, 0))
		await until(_nobody_near, 4.0)
		label = "tier_%d_R" % t
		await frames(20)
		await walk_leg("face_left_%d" % t, p.tile + Vector2i(-4, 0))
		await until(_nobody_near, 4.0)
		label = "tier_%d_L" % t
		await frames(20)
	label = ""
	_notes["tiers"] = GEAR_SETS


func _quiet_tile(c: Vector2i) -> Vector2i:
	var w: World = main.world
	var cands: Array = get_tree().get_nodes_in_group("actors")
	if w.enemies:
		cands += w.enemies.enemies
	for r in range(8, 40, 2):
		for k in 16:
			var a := TAU * k / 16.0
			var t := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			var clear := true
			for dx in range(-5, 6):
				clear = clear and not w.is_blocked(t + Vector2i(dx, 0)) and not _bv.hides(t + Vector2i(dx, 0)) and w.object_at(t + Vector2i(dx, 0)) == null
				# 0.3.1 cities: facades, hanging shop signs and wall tops sit 1-2 rows up: keep them out of the still
				for dy in [-2, -1, 1]:
					clear = clear and not w.is_blocked(t + Vector2i(dx, dy)) and not _bv.hides(t + Vector2i(dx, dy)) and w.object_at(t + Vector2i(dx, dy)) == null   # 0.3.3: no reeds over the sprite
			if not clear:
				continue
			var busy := false
			for o in cands:
				if is_instance_valid(o) and o != main.player and "tile" in o and maxi(absi(o.tile.x - t.x), absi(o.tile.y - t.y)) <= 6:
					busy = true
					break
			if not busy:
				return t
	return c


func _nobody_near() -> bool:
	var p: Player = main.player
	for a in get_tree().get_nodes_in_group("actors"):
		if a != p and a is Node2D and a.is_visible_in_tree() and (a.position - p.position).length() < 64.0:
			return false
	return true


# ------------------------------------------------------------ 0.3.3 archery --
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(out_dir + "/snaps")
	var path := "%s/snaps/%s.png" % [out_dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	_ev("snap", {"name": name, "path": path})


func _clear_foes(p: Player, w: World) -> void:
	for e in w.enemies.enemies:
		if e.target == p:
			e.target = null
			e.reset_far()


## Shortbow + 3 bronze arrows, tap a rat 4 tiles away: the archer stands and
## shoots 3 arrows (projectile frames), then 'Out of arrows!' stops the fight.
## Then overhead labels on an AI player and an enemy, none on a chicken /
## shopkeeper, and the Skills panel with Archery.
func _archery() -> void:
	var p: Player = main.player
	var w: World = main.world
	var res := {}
	var msgs: Array = []
	Events.message.connect(func(t, _k = ""): msgs.append(str(t)))
	var shots := [0]
	var shot_snapped := [false]
	Events.projectile.connect(func(_a, _b, _s): shots[0] += 1)
	p.inventory.clear()
	p.equipment.erase("weapon")
	p.inventory.add("ash_shortbow")
	p.inventory.add("bronze_arrows", 3)
	p.auto_equip_ammo()
	p.equip_slot(0)
	res["weapon"] = p.weapon_id()
	var rat := _foe("giant_rat", "", w.gen.town_spawn("fenhollow"))
	rat.max_hp = 999
	rat.hp = 999
	var keep_def: Dictionary = rat.def
	rat.def = rat.def.duplicate()
	rat.def["retaliate"] = false     # hold still for the capture (no rush to melee)
	rat.def["wander"] = 0
	rat.wander_goal = rat.tile
	rat.home = rat.tile
	var keep_xp: Dictionary = p.skills.xp.duplicate()
	for id in ["attack", "strength", "defence", "vitality"]:
		p.skills.set_level(id, 22)     # 0.3.6 rats are level 5: Combat 15+ is ignored
	_clear_foes(p, w)
	rat.reset_far()
	var spot := rat.tile
	for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3)]:
		var c: Vector2i = rat.tile + d
		if not w.is_blocked(c) and Combat.line_of_sight(w, c, rat.tile):
			spot = c
			break
	p.place_at(spot)
	p.stop()
	p.hp = p.max_hp()
	w.set_focus(p.tile, true)
	await frames(20)
	label = "archery_fight"
	var start := p.tile
	var arrows0 := p.ammo_qty
	await tap(tile_screen(rat.tile), "rat (archery)")
	var t_end := Time.get_ticks_msec() + 15000
	var max_d := 0
	while Time.get_ticks_msec() < t_end:
		if shots[0] >= 1 and not shot_snapped[0]:
			await frames(1)       # arrow mid-flight
			await _snap("archery_projectile")
			shot_snapped[0] = true
		max_d = maxi(max_d, p._cheb(p.tile, start))
		if shots[0] >= 3 and p.action.is_empty():
			break
		await frames(1)
	await frames(20)
	await _snap("archery_out_of_arrows")
	res["shots"] = shots[0]
	res["arrows_before"] = arrows0
	res["arrows_after"] = p.ammo_qty
	res["out_msg"] = "Out of arrows!" in msgs
	res["msgs"] = msgs.slice(-4)
	res["stopped"] = p.action.is_empty()
	res["moved"] = max_d
	res["archery_xp"] = int(p.skills.xp.get("archery", 0))
	res["rat_label"] = rat._lvl_label.text if rat._lvl_label else ""
	rat.def = keep_def
	p.skills.xp = keep_xp
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	_clear_foes(p, w)
	# overhead: an AI player next to an enemy
	label = "overhead"
	var ai = await _pick_ai("fenhollow")
	if ai != null:
		p.place_at(w.find_free_tile_near(rat.tile + Vector2i(-3, 0), 3, true))
		var at: Vector2i = rat.tile
		for d in [Vector2i(0, 3), Vector2i(0, -3), Vector2i(-1, 3), Vector2i(1, -3), Vector2i(0, 4)]:
			var c: Vector2i = rat.tile + d
			if not w.is_blocked(c) and not w.is_blocked(c + Vector2i(0, 1)) and w.object_at(c + Vector2i(0, 1)) == null:
				at = c
				break
		ai.place_at(at)
		ai.stop()
		w.set_focus(p.tile, true)
		await frames(30)
		res["ai_label"] = ai._label.text if ai._label else ""
		res["labels_shown"] = Overhead.shown_count()
		res["ai_cb"] = Combat.combat_level(ai.skills)
		res["ai_name"] = ai.display_name
		await _snap("overhead_ai_and_enemy")
	# no label on a chicken
	var ch := _foe("chicken", "", w.gen.town_spawn("fenhollow"))
	if ch != null:
		p.place_at(w.find_free_tile_near(ch.tile + Vector2i(2, 0), 3, true))
		w.set_focus(p.tile, true)
		await frames(30)
		res["chicken_label"] = ch._lvl_label != null
		await _snap("chicken_no_label")
	# no label on a shopkeeper (a world object, never an Enemy)
	var shop: String = Market.town("fenhollow").specialists[0]
	var b: Dictionary = w.gen.building_for_shop("fenhollow", shop)
	p.place_at(w.find_free_tile_near(b["keeper_at"] + Vector2i(0, 2), 3))
	w.set_focus(p.tile, true)
	await frames(40)
	res["keeper_enemy"] = w.enemies.enemy_at(b["keeper_at"]) != null
	await _snap("shopkeeper_no_label")
	# skills panel
	label = "skills"
	main.hud.show_panel("skills")
	await frames(20)
	res["skills_panel_archery"] = _has_text(main.hud.panels["skills"], "Archery") or _has_text(main.hud.panels["skills"], "ARC")
	await _snap("skills_panel_archery")
	main.hud.toggle_panel("skills")
	label = ""
	_notes["archery"] = res


func _has_text(n: Node, t: String) -> bool:
	if (n is Label or n is Button) and str(n.text).contains(t):
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false


## 0.3.5: bank building (exterior + interior frames, banker tap opens the bank),
## no loose plaza chest / hearth, archery from 9-10 tiles, the dummy's blocked
## counter-swing (Defence XP, no HP lost), an AI banking at the new building.
func _bank035() -> void:
	var p: Player = main.player
	var w: World = main.world
	var res := {}
	var bank: Dictionary = {}
	for id in w.gen.building_order:
		var b: Dictionary = w.gen.buildings[id]
		if b["town"] == "fenhollow" and b["kind"] == "bank":
			bank = b
	res["has_bank"] = not bank.is_empty()
	if bank.is_empty():
		_notes["bank"] = res
		return
	var r: Rect2i = bank["rect"]
	var loose := 0
	var hearth := 0
	for tid in ["fenhollow", "cinderholt", "saltmere"]:
		var c := w.gen.town_center(tid)
		for y in range(c.y - 22, c.y + 23):
			for x in range(c.x - 22, c.x + 23):
				var o: WorldObject = w.object_at(Vector2i(x, y))
				if o == null or not w.gen.building_at(o.pos).is_empty():
					continue
				if o.def_id == "bank_chest": loose += 1
				if o.def_id == "hearth" and w.gen.place_at(o.pos, 0) == tid: hearth += 1
	res["loose_chests"] = loose
	res["plaza_hearths"] = hearth
	# exterior: walk up to the door by tapping
	var door: Vector2i = bank["doors"][0]
	p.place_at(w.find_free_tile_near(door + Vector2i(0, 4), 2))
	w.set_focus(p.tile, true)
	await frames(20)
	label = "bank_exterior"
	await _snap("bank_exterior")
	var opened := [false]
	Events.bank_opened.connect(func(): opened[0] = true)
	var keeper: WorldObject = w.object_at(bank["keeper_at"])
	await tap_tile(keeper.pos, "banker")
	await until(func(): return opened[0], 15.0)
	await frames(20)
	res["banker_opens"] = opened[0]
	res["inside"] = r.has_point(p.tile)
	res["panel"] = main.hud.panels["bank"].visible
	label = "bank_interior"
	await _snap("bank_interior")
	main.hud.panels["bank"].visible = false
	# AI banking at the new building
	var ai = await _pick_ai("fenhollow")
	res["ai_found"] = ai != null
	if ai:
		ai.place_at(w.find_free_tile_near(door + Vector2i(2, 3), 2))
		ai.inventory.clear()
		ai.inventory.add("ash_log", 5)
		var went: bool = ai._go_bank(w)
		var t_end := Time.get_ticks_msec() + 25000
		while Time.get_ticks_msec() < t_end and ai.inventory.count("ash_log") > 0:
			if ai.action.is_empty():
				ai._go_bank(w)
			await frames(5)
		res["ai_went"] = went
		res["ai_banked"] = ai.inventory.count("ash_log") == 0
		res["ai_inside"] = r.has_point(ai.tile)
	# archery from 9-10 tiles
	var rat := _foe("giant_rat", "", w.gen.town_spawn("fenhollow"))
	rat.max_hp = 999
	rat.hp = 999
	var keep_def: Dictionary = rat.def
	rat.def = rat.def.duplicate()
	rat.def["retaliate"] = false
	rat.def["wander"] = 0
	rat.wander_goal = rat.tile
	rat.home = rat.tile
	_clear_foes(p, w)
	rat.reset_far()
	var spot := Vector2i(-99999, 0)
	for rr in [10, 9]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var c2: Vector2i = rat.tile + d * rr
			if not w.is_blocked(c2) and Combat.line_of_sight(w, c2, rat.tile):
				spot = c2
				break
		if spot.x != -99999:
			break
	var shots := [0]
	Events.projectile.connect(func(_a, _b, _s): shots[0] += 1)
	p.inventory.clear()
	p.equipment.erase("weapon")
	p.inventory.add("ash_shortbow")
	p.inventory.add("bronze_arrows", 2)
	p.auto_equip_ammo()
	p.equip_slot(0)
	p.place_at(spot)
	p.stop()
	p.hp = p.max_hp()
	w.set_focus(p.tile, true)
	await frames(20)
	res["arch_dist"] = p._cheb(p.tile, rat.tile)
	var start := p.tile
	label = "archery_10"
	await tap(tile_screen(rat.tile), "rat at 9-10 tiles")
	await until(func(): return shots[0] >= 1, 10.0)
	res["arch_shots"] = shots[0]
	res["arch_moved"] = p._cheb(p.tile, start)
	await _snap("archery_10_tiles")
	p.stop()
	rat.def = keep_def
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	_clear_foes(p, w)
	# dummy block
	var dummy: WorldObject = w.find_nearest_object(w.gen.town_spawn("fenhollow"), ["training_dummy"], 60)
	p.place_at(w.find_free_tile_near(dummy.pos + Vector2i(0, 2), 2))
	p.hp = p.max_hp()
	w.set_focus(p.tile, true)
	await frames(10)
	var hp0 := p.hp
	var def0 := int(p.skills.xp.get("defence", 0))
	var zero := [0]
	Events.hitsplat.connect(func(t, _q, amt): if t == p and amt == 0: zero[0] += 1)
	label = "dummy_block"
	await tap_tile(dummy.pos, "training dummy")
	var t2 := Time.get_ticks_msec() + 15000
	var snapped := false
	while Time.get_ticks_msec() < t2 and zero[0] < 3:
		if zero[0] >= 1 and not snapped:
			await _snap("dummy_block")
			snapped = true
		await frames(2)
	res["dummy_blocks"] = zero[0]
	res["dummy_def_xp"] = int(p.skills.xp.get("defence", 0)) - def0
	res["dummy_hp_lost"] = hp0 - p.hp
	p.stop()
	_notes["bank"] = res


## 0.3.6: ammo-slot-only firing, no-tool gathering blocked, flint fire (light,
## cook, burn out), tiered food heals, night ambient switch. Frames: the fire
## and the Pack panel's Worn row with the ammo slot.
func _v036() -> void:
	var p: Player = main.player
	var w: World = main.world
	var res := {}
	var msgs: Array = []
	Events.message.connect(func(t, _k = ""): msgs.append(str(t)))
	var shots := [0]
	Events.projectile.connect(func(_a, _b, _s): shots[0] += 1)
	# ammo: arrows only in the pack -> no shot; equipped -> shots
	p.inventory.clear()
	p.equipment.erase("weapon")
	p.equipment.erase("ammo")
	p.ammo_qty = 0
	p.inventory.add("ash_shortbow")
	p.inventory.add("bronze_arrows", 5)
	p.equip_slot(0)
	var keep_xp: Dictionary = p.skills.xp.duplicate()
	for id in ["attack", "strength", "defence", "vitality"]:
		p.skills.set_level(id, 22)
	var rat := _foe("giant_rat", "", w.gen.town_spawn("fenhollow"))
	rat.max_hp = 999
	rat.hp = 999
	var keep_def: Dictionary = rat.def
	rat.def = rat.def.duplicate()
	rat.def["retaliate"] = false
	rat.def["wander"] = 0
	rat.home = rat.tile
	_clear_foes(p, w)
	rat.reset_far()
	var spot := rat.tile
	for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
		if not w.is_blocked(rat.tile + d) and Combat.line_of_sight(w, rat.tile + d, rat.tile):
			spot = rat.tile + d
			break
	p.place_at(spot)
	p.stop()
	w.set_focus(p.tile, true)
	await frames(20)
	label = "ammo_pack_only"
	await tap(tile_screen(rat.tile), "rat (pack arrows only)")
	await frames(90)
	res["pack_only_shots"] = shots[0]
	res["pack_only_left"] = p.inventory.count("bronze_arrows")
	p.stop()
	for k in p.inventory.size():
		if p.inventory.slots[k] != null and p.inventory.slots[k]["id"] == "bronze_arrows":
			p.equip_slot(k)
	res["ammo_equipped"] = p.ammo_qty
	main.hud.show_panel("pack")
	await frames(15)
	label = "equipment_ammo"
	await _snap("equipment_ammo_slot")
	main.hud.show_panel("")
	await frames(5)
	label = "ammo_fire"
	await tap(tile_screen(rat.tile), "rat (ammo slot)")
	await until(func(): return shots[0] >= 2, 12.0)
	p.stop()
	res["ammo_shots"] = shots[0]
	res["ammo_left"] = p.ammo_qty
	rat.def = keep_def
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	_clear_foes(p, w)
	p.skills.xp = keep_xp
	# no tool: gathering blocked
	p.inventory.clear()
	p.equipment.erase("weapon")
	var tree: WorldObject = w.find_nearest_object(w.gen.town_spawn("fenhollow") + Vector2i(0, 40), ["ash_tree"], 60)   # 0.3.13 alders need Forestry 15 (different message)
	p.place_at(w.find_free_tile_near(tree.pos + Vector2i(0, 2), 2))
	w.set_focus(p.tile, true)
	await frames(15)
	msgs.clear()
	label = "no_hatchet"
	await tap_tile(tree.pos, "tree without a hatchet")
	await frames(60)
	res["no_tool_msg"] = "You need a hatchet." in msgs
	res["no_tool_logs"] = p.inventory.count("ash_log") + p.inventory.count("alder_log")
	# fire: light with flint via the pack action, cook, burn out
	p.inventory.add("flint", 1)
	p.inventory.add("ash_log", 1)
	p.inventory.add("raw_carp", 1)
	var fx0 := int(p.skills.xp.get("forestry", 0))
	main.hud.show_panel("pack")
	await frames(5)
	main.hud._sel_slot = p.inventory.find("flint")
	main.hud._refresh_pack_actions()
	await frames(5)
	var light_btn: Control = null
	for c in main.hud.pack_actions.get_children():
		if c is Button and (c as Button).text == "Light":
			light_btn = c
	res["light_button"] = light_btn != null
	if light_btn:
		await tap_control(light_btn, "Light (flint)")
	main.hud.show_panel("")
	await frames(20)
	var fire: WorldObject = w.find_nearest_object(p.tile, ["cooking_fire"], 2)
	res["fire_lit"] = fire != null
	res["fire_xp"] = int(p.skills.xp.get("forestry", 0)) - fx0
	res["fire_used"] = p.inventory.count("flint") == 0 and p.inventory.count("ash_log") == 0
	label = "fire"
	await _snap("cooking_fire")
	if fire:
		await tap_tile(fire.pos, "cooking fire")
		await until(func(): return p.inventory.count("raw_carp") == 0, 12.0)
		await frames(10)
		res["fire_cooked"] = p.inventory.count("cooked_carp") + p.inventory.count("charred_fish") == 1
		res["fire_ticks"] = int(w.fires.get(fire.pos, 0)) - Tick.tick_count
		w.fires[fire.pos] = Tick.tick_count + 2    # fast-forward the burn
		await until(func(): return w.find_nearest_object(p.tile, ["cooking_fire"], 3) == null, 5.0)
		res["fire_out"] = w.find_nearest_object(p.tile, ["cooking_fire"], 3) == null
		await _snap("cooking_fire_out")
	# tiered heals (eat via the real Eat path)
	var hs := {}
	for f in ["cooked_rat_meat", "cooked_carp", "cooked_beef", "cooked_eel"]:
		p.hp = 1
		p.inventory.add(f)
		hs[f] = p.eat_slot(p.inventory.find(f), Tick.tick_count + 100)
	res["heals"] = hs
	# night ambient
	Music.set_area("", false)
	Music.step(3.0)
	var day_track := Music.current
	DayNight.debug_set_phase("night")
	var faded := false
	var t_end := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < t_end and Music.current != "ambient_night":
		faded = faded or Music.fading
		await frames(1)
	res["night_music"] = [day_track, faded, Music.current]
	await _snap("night_wilds")
	DayNight.debug_set_phase("day")
	_notes["v036"] = res


func _qcolor(id: String) -> String:
	main.hud.show_panel("quests")
	var l: Label = main.hud.quest_rows.get(id)
	return l.get_theme_color("font_color").to_html(false) if l else ""


## Fight `e` with real taps until it dies (strong test character).
func _kill(p: Player, w: World, e: Enemy, what: String) -> bool:
	p.place_at(w.find_free_tile_near(e.tile + Vector2i(1, 0), 2))
	w.set_focus(p.tile, true)
	await frames(10)
	var t_end := Time.get_ticks_msec() + 60000
	while not e.dead and Time.get_ticks_msec() < t_end:
		if p.action.is_empty():
			p.hp = p.max_hp()
			if p._cheb(p.tile, e.tile) > 3:
				p.place_at(w.find_free_tile_near(e.tile + Vector2i(1, 0), 2))
				w.set_focus(p.tile, true)
				await frames(5)
			await tap(tile_screen(e.tile), what)
		await frames(10)
	return e.dead


## 0.3.7 Goblin Slayer start to finish with real taps.
func _quest037() -> void:
	var p: Player = main.player
	var w: World = main.world
	var hud = main.hud
	var res := {}
	var id := "goblin_slayer"
	var keep_xp: Dictionary = p.skills.xp.duplicate()
	for sk in ["attack", "strength", "defence", "vitality"]:
		p.skills.set_level(sk, 45)
	p.inventory.add("iron_sword")
	var gt := QuestSystem.giver_tile(w, "kell")
	p.place_at(w.find_free_tile_near(gt + Vector2i(0, 3), 2))
	w.set_focus(p.tile, true)
	await frames(30)
	res["color_not_started"] = _qcolor(id)
	await _snap("journal_not_started")
	hud.show_panel("")
	await frames(10)
	res["mark_start"] = hud.quest_ui.giver_label("kell").text if hud.quest_ui.giver_label("kell") else ""
	res["minimap_mark_start"] = QuestSystem.giver_marker(p, "kell")
	label = "quest_q"
	await _snap("quest_npc_question")
	# 0.3.7.1 dialog: Decline keeps '?', Accept starts
	res["dialog_offer"] = await _dialog_pick(gt, "Kell", "Decline")
	label = "dialog"
	res["state_after_decline"] = QuestSystem.state(p, id)
	await frames(10)
	res["mark_after_decline"] = hud.quest_ui.giver_label("kell").text if hud.quest_ui.giver_label("kell") else ""
	await _dialog_pick(gt, "Kell", "Accept", "quest_dialog_offer")
	await until(func(): return QuestSystem.state(p, id) != QuestSystem.NOT_STARTED, 10.0)
	await frames(10)
	res["state_after_talk"] = QuestSystem.state(p, id)
	# the phone bug: right after accepting in Fenhollow (goblins far away)
	await frames(20)
	res["arrow_from_town"] = hud.quest_ui.arrow_visible
	res["objective_from_town"] = str(hud.quest_ui.objective)
	await RenderingServer.frame_post_draw
	res["arrow_px_town"] = _gold_px()
	label = "arrow"
	await _snap("quest_arrow_from_town")
	await _map_frames(res)
	res["mark_hunting"] = hud.quest_ui.giver_label("kell").text if hud.quest_ui.giver_label("kell") else "?none"
	# goblins
	for i in range(1, 6):
		var g: Enemy = w.enemies.nearest(p.tile, ["goblin"], 4000)
		g.reset_far()
		if i == 2:
			p.place_at(w.find_free_tile_near(g.tile + Vector2i(18, 0), 3))
			w.set_focus(p.tile, true)
			await frames(20)
			res["arrow_goblin"] = hud.quest_ui.arrow_visible
			await RenderingServer.frame_post_draw
			res["arrow_px_goblin"] = _gold_px()
			label = "arrow"
			await _snap("quest_arrow_goblin")
		var ok: bool = await _kill(p, w, g, "goblin %d" % i)
		res["goblin_%d" % i] = ok
		if i == 3:
			res["progress_3"] = QuestSystem.progress_text(p, id)
			res["color_in_progress"] = _qcolor(id)
			label = "journal"
			await _snap("journal_in_progress")
			hud.show_panel("")
	res["state_after_goblins"] = QuestSystem.state(p, id)
	# back to Kell: arrow points at him, he shows "!"
	p.place_at(w.find_free_tile_near(gt + Vector2i(0, 30), 3))
	w.set_focus(p.tile, true)
	await frames(20)
	res["arrow_to_kell"] = hud.quest_ui.arrow_visible and hud.quest_ui.arrow_target == gt
	p.place_at(w.find_free_tile_near(gt + Vector2i(0, 3), 2))
	w.set_focus(p.tile, true)
	await frames(20)
	res["arrow_hidden_on_screen"] = not hud.quest_ui.arrow_visible
	res["mark_ready"] = hud.quest_ui.giver_label("kell").text if hud.quest_ui.giver_label("kell") else ""
	label = "quest_excl"
	await _snap("quest_npc_exclaim")
	p.stop()
	_clear_foes(p, w)
	await _dialog_pick(gt, "Kell (report)", "I'll hunt him down", "quest_dialog_report")
	await until(func(): return QuestSystem.progress_text(p, id).contains("Warlord"), 10.0)
	res["progress_warlord"] = QuestSystem.progress_text(p, id)
	await frames(10)
	res["arrow_warlord"] = hud.quest_ui.arrow_visible
	await RenderingServer.frame_post_draw
	res["arrow_px_warlord"] = _gold_px()
	await _snap("quest_arrow_warlord")
	# the Warlord
	var wl: Enemy = w.enemies.nearest(p.tile, ["goblin_warlord"], 4000)
	p.place_at(w.find_free_tile_near(wl.tile + Vector2i(3, 2), 2))
	w.set_focus(p.tile, true)
	await frames(30)
	res["warlord_label"] = wl._lvl_label.text if wl._lvl_label else ""
	label = "warlord"
	await _snap("goblin_warlord")
	res["warlord_killed"] = await _kill(p, w, wl, "Goblin Warlord")
	res["state_after_warlord"] = QuestSystem.state(p, id)
	wl.respawn_at = Tick.tick_count + 3
	await until(func(): return not wl.dead, 10.0)
	res["warlord_respawned"] = not wl.dead
	# turn in
	var marks0 := p.inventory.count(GameData.currency)
	var inf0 := p.influence
	p.place_at(w.find_free_tile_near(gt + Vector2i(0, 3), 2))
	w.set_focus(p.tile, true)
	await frames(20)
	p.stop()
	_clear_foes(p, w)
	await _dialog_pick(gt, "Kell (turn in)", "Thank you", "quest_dialog_turnin")
	await until(func(): return QuestSystem.state(p, id) == QuestSystem.COMPLETED, 10.0)
	res["turn_in_msgs"] = p.action.duplicate()
	await frames(20)
	res["state_final"] = QuestSystem.state(p, id)
	res["influence"] = p.influence - inf0
	res["marks"] = p.inventory.count(GameData.currency) - marks0
	res["sword"] = p.inventory.count("iron_sword")
	res["mark_final"] = hud.quest_ui.giver_label("kell").text if hud.quest_ui.giver_label("kell") else ""
	res["minimap_mark_final"] = QuestSystem.giver_marker(p, "kell")
	res["color_completed"] = _qcolor(id)
	res["influence_text"] = hud.influence_label.text
	await _snap("journal_completed")
	hud.show_panel("")
	p.skills.xp = keep_xp
	_notes["quest"] = res


## 0.3.8 Highfen: roads from every town, the house, the only player shop,
## slimes (no bones), an arrow over a roadside log; frames.
func _capital038() -> void:
	var p: Player = main.player
	var w: World = main.world
	var g: WorldGen = w.gen
	var hud = main.hud
	var res := {}
	var cap := g.capital
	var hc := g.town_center(cap)
	# 0.3.8.1 a new character starts in Fenhollow's plaza by Kell
	var k0 = w.find_nearest_object(p.tile, ["quest_giver"], 10)
	res["start"] = {"tile": [p.tile.x, p.tile.y], "town": g.place_at(p.tile, 8), "kell": k0 != null}
	await _snap("new_game_kell")
	# roads: every town reaches Highfen (walkable road + a real path from the road end through the gate)
	var reach := {}
	for tid in g.town_order:
		if tid == cap:
			continue
		var road: Array = g.road_between(tid, cap)
		var ok := not road.is_empty()
		for q in road:
			ok = ok and not (g.tile_at(q.x, q.y) in WorldGen.BLOCKING_TILES)
			var o = w.object_at(q) if w.get_chunk(w.chunk_of(q)) else null
			ok = ok and (o == null or not o.blocks())
		if ok:
			w.set_focus(road[-1], true)
			var inside: Vector2i = g.town_spawn(cap)
			w.set_focus(inside, true)
			ok = not Pathfinder.find_path(w, road[-1], [inside], inside, 20000).is_empty()
		reach[tid] = ok
	res["reach"] = reach
	# frames: overview at the plaza, the moat + north gate, the world map
	p.stop()
	p.place_at(g.town_spawn(cap))
	w.set_focus(p.tile, true)
	await frames(30)
	label = "highfen"
	await _snap("highfen_overview")
	var ng: Vector2i = g.gate_outside(cap, hc + Vector2i(0, -100))
	p.place_at(w.find_free_tile_near(ng + Vector2i(0, -1), 3))
	w.set_focus(p.tile, true)
	await frames(30)
	await _snap("highfen_moat_gate")
	# 0.3.11 the moat is gone: a round city wall (CITY_RING) flanks the north gate
	var ring := 0
	for dy in range(1, 90):   # walking north from the palace hits the wall before the town's north gate
		if g.tile_at(hc.x + 3, hc.y - dy) == WorldGen.TileType.CAPITAL_WALL or g.tile_at(hc.x - 3, hc.y - dy) == WorldGen.TileType.CAPITAL_WALL:
			ring += 1
			break
	res["moat_px"] = ring > 0
	hud.show_panel("map")
	await frames(15)
	label = "map"
	await _snap("world_map_038")
	var mp = hud.map_panel
	mp.zoom = 5.0
	mp._center = Vector2(w.map_pixel(hc))
	mp._clamp_center()
	await frames(10)
	await _snap("highfen_map_overview")
	mp.zoom = 1.0
	mp._center = Vector2(-1, -1)
	hud.show_panel("")
	# the only player shop
	var shops := []
	for bid in g.buildings.keys():
		if g.buildings[bid]["kind"] == "player":
			shops.append("%s@%s" % [bid, g.buildings[bid]["town"]])
	res["player_shops"] = shops
	# the house: the clerk quotes, a second tap buys; benches + bank chest inside
	var house: Dictionary = g.buildings["highfen_house"]
	var keep_owned := p.house_owned
	p.house_owned = false
	p.inventory.add(GameData.currency, Player.house_price())
	var c0 := p.inventory.count(GameData.currency)
	p.place_at(house["doors"][0] + Vector2i(0, 1))
	w.set_focus(p.tile, true)
	await frames(20)
	label = "house"
	var clerk: Vector2i = house["keeper_at"]
	for attempt in 2:
		await tap_tile(clerk, "estate clerk")
		await until(func(): return p.action.is_empty() and p.tile == house["stand"], 12.0)
		await frames(10)
	await until(func(): return p.house_owned, 8.0)
	res["house_bought"] = p.house_owned and c0 - p.inventory.count(GameData.currency) == Player.house_price()
	var st := {}
	var chest := Vector2i.ZERO
	for q in g._town_objects.keys():   # 0.3.11 stations stand in the townhouse's work yard (meta building)
		if str(g.object_meta(q).get("building", "")) == str(house["id"]):
			var dd: Dictionary = GameData.object_def(str(g._town_objects[q]))
			st[str(dd.get("station", dd.get("type", "")))] = true
			if g._town_objects[q] == "bank_chest":
				chest = q
	res["house_stations"] = st.keys()
	await tap_tile(chest, "house bank chest")
	res["house_bank"] = await until(func(): return hud.current_panel == "bank", 12.0)
	await frames(10)
	hud.show_panel("")
	await frames(6)
	await _snap("house_interior")
	p.house_owned = keep_owned
	# slime: kill one, no bones in its pile
	var sl := _foe("slime", "", hc)
	res["slime_found"] = sl != null
	if sl:
		p.place_at(w.find_free_tile_near(sl.tile + Vector2i(2, 0), 2))
		w.set_focus(p.tile, true)
		await frames(20)
		label = "slime"
		await _snap("slime")
		var at := sl.tile
		var killed: bool = await _kill(p, w, sl, "slime")
		await frames(10)
		var drops := []
		for dq in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			for pile in w.ground.at(sl.tile + dq) + w.ground.at(at + dq):
				drops.append(str(pile.get("id", "")))
		res["slime_killed"] = killed
		res["slime_drops"] = drops
	# a road with decorations + an arrow over an old log
	var lg := Vector2i(1 << 20, 0)
	var ld := Vector2i.ZERO
	for q in g.road_decor.keys():
		if g.road_decor[q] != "old_log" or (q - hc).length() > 200:
			continue
		w.set_focus(q, true)
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not w.is_blocked(q - d * 3) and not w.is_blocked(q + d * 3) and not w.is_blocked(q - d) and not w.is_blocked(q + d) and not w.is_blocked(q - d * 2) and not w.is_blocked(q + d * 2):
				lg = q
				ld = d
				break
		if ld != Vector2i.ZERO:
			break
	res["log_found"] = ld != Vector2i.ZERO
	if ld != Vector2i.ZERO:
		_clear_foes(p, w)
		p.place_at(lg - ld * 3)
		w.set_focus(p.tile, true)
		await frames(20)
		label = "road"
		await _snap("road_decor")
		# walking: tap the far side of the log, the path goes round it
		await tap_tile(lg + ld, "far side of the log")
		var stood_on := false
		var t_end := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < t_end and p.tile != lg + ld:
			stood_on = stood_on or p.tile == lg
			await frames(2)
		res["walk_round_log"] = p.tile == lg + ld and not stood_on and w.is_blocked(lg)
		# shooting: bow + arrows on one side, a slime held still on the other
		var foe := _foe("slime", "", lg)
		if foe == null:
			foe = _foe("chicken", "", lg)
		var shots := [0]
		var cb := func(_a, _b, _s): shots[0] += 1
		Events.projectile.connect(cb)
		p.inventory.add("ash_shortbow")
		p.inventory.add("bronze_arrows", 5)
		var keep_w = p.equipment.get("weapon", "")
		p.equipment.erase("weapon")
		p.equip_slot(p.inventory.find("ash_shortbow") if p.inventory.has_method("find") else 0)
		p.auto_equip_ammo()
		var keep_def: Dictionary = foe.def
		foe.def = foe.def.duplicate()
		foe.def["retaliate"] = false
		foe.def["wander"] = 0
		foe.def["aggro"] = 0
		foe.max_hp = 999
		foe.hp = 999
		foe.home = lg + ld * 2
		foe.reset_far()
		foe.wander_goal = foe.tile
		p.place_at(lg - ld * 2)
		p.stop()
		w.set_focus(p.tile, true)
		await frames(20)
		var start := p.tile
		await tap(tile_screen(foe.tile), "slime over the log")
		var t2 := Time.get_ticks_msec() + 12000
		var snapped := false
		while Time.get_ticks_msec() < t2 and shots[0] < 2:
			if shots[0] >= 1 and not snapped:
				await frames(1)
				await _snap("arrow_over_log")
				snapped = true
			await frames(1)
		res["arrow_over_log"] = shots[0] >= 1 and foe.hp < 999 or shots[0] >= 1
		res["arrow_shots"] = shots[0]
		res["archer_stayed"] = p.tile == start
		res["foe_hp"] = foe.hp
		p.stop()
		Events.projectile.disconnect(cb)
		foe.def = keep_def
		foe.max_hp = int(keep_def.get("hp", 8))
		foe.hp = foe.max_hp
		foe.target = null
	_notes["capital"] = res


## 0.3.7.1 tap the giver until the dialog opens, then press a choice.
func _dialog_pick(gt: Vector2i, what: String, choice: String, snap := "") -> Dictionary:
	var hud = main.hud
	var shown := {}
	for attempt in 3:
		await tap_tile(gt, what)
		if await until(func(): return hud.current_panel == "dialog", 10.0):
			break
	await frames(6)
	shown = hud.dialog_state.duplicate(true)
	if snap != "":
		await _snap(snap)
	var b: Control = hud.panels["dialog"].find_child("Choice_" + choice, true, false)
	for attempt in 3:
		if not await tap_control(b, choice) or await until(func(): return hud.current_panel != "dialog", 4.0):
			break
	await frames(6)
	return shown


## Gold (#ffd23a-ish) arrow / marker pixels on screen right now.
func _gold_px() -> int:
	var img := get_viewport().get_texture().get_image()
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.r > 0.9 and c.g > 0.72 and c.g < 0.9 and c.b < 0.35:
				n += 1
	return n


## 0.3.7.1 world map: markers shown / hidden, pinch-zoomed.
func _map_frames(res: Dictionary) -> void:
	var hud = main.hud
	hud.show_panel("map")
	var mp = hud.map_panel
	MapPrefs.set_markers_shown(true)
	await frames(10)
	label = "map"
	await _snap("map_markers_shown")
	await tap_control(mp._markers_btn, "Markers toggle")
	await frames(10)
	res["map_markers_off"] = not MapPrefs.markers_shown()
	await _snap("map_markers_hidden")
	MapPrefs.reload()
	res["map_markers_persist"] = not MapPrefs.markers_shown()
	await tap_control(mp._markers_btn, "Markers toggle")
	await frames(4)
	res["map_markers_on"] = MapPrefs.markers_shown()
	var z0: float = mp.zoom
	var plus: Control = mp.find_child("ZoomIn", true, false)
	for i in 3:
		await tap_control(plus, "zoom +")
		await frames(4)
	res["map_zoom"] = [z0, mp.zoom]
	await _snap("map_zoomed")
	mp.zoom = 1.0
	mp._center = Vector2(-1, -1)
	hud.show_panel("")
	await frames(6)


## 0.3.7 XP feedback: melee hit, chop, mine, cook each log an XP line and move
## the Skills panel tracker.
func _xp037() -> void:
	var p: Player = main.player
	var w: World = main.world
	var res := {}
	var lines: Array = []
	Events.message.connect(func(t, k = ""): if k == "xp": lines.append(str(t)))
	var c := w.gen.town_spawn("fenhollow")
	var cases := [["forestry", ["bronze_hatchet"], ["ash_tree"]], ["mining", ["bronze_pick"], ["copper_rock", "tin_rock"]], ["cooking", ["raw_carp", "raw_carp"], ["oven", "hearth"]]]
	for cs in cases:
		var sk: String = cs[0]
		p.inventory.clear()
		for it in cs[1]:
			p.inventory.add(it)
		var o: WorldObject = w.find_nearest_object(c, cs[2], 80)
		p.place_at(w.find_free_tile_near(o.pos + Vector2i(0, 2), 2))
		w.set_focus(p.tile, true)
		await frames(10)
		lines.clear()
		var s0 := int(p.session_xp.get(sk, 0))
		var nm: String = GameData.skill_by_id[sk]["name"]
		await tap_tile(o.pos, sk)
		await until(func(): return lines.any(func(l): return l.contains(nm + " XP")), 25.0)
		p.stop()
		res[sk] = {"line": lines.filter(func(l): return l.contains(nm + " XP")).slice(0, 1), "tracker": int(p.session_xp.get(sk, 0)) - s0}
	# melee
	p.inventory.clear()
	p.inventory.add("bronze_sword")
	p.equip_slot(0)
	var rat := _foe("giant_rat", "", c)
	rat.reset_far()
	rat.max_hp = 999
	rat.hp = 999
	p.place_at(w.find_free_tile_near(rat.tile + Vector2i(1, 0), 2))
	w.set_focus(p.tile, true)
	p.hp = p.max_hp()
	await frames(10)
	lines.clear()
	var a0 := int(p.session_xp.get("attack", 0)) + int(p.session_xp.get("strength", 0))
	await tap(tile_screen(rat.tile), "rat (melee)")
	await until(func(): return lines.any(func(l): return l.contains("Attack XP") or l.contains("Strength XP")), 20.0)
	label = "xp_log"
	await _snap("xp_log_lines")
	p.stop()
	res["melee"] = {"line": lines.filter(func(l): return l.contains("Attack XP") or l.contains("Strength XP")).slice(0, 1), "tracker": int(p.session_xp.get("attack", 0)) + int(p.session_xp.get("strength", 0)) - a0}
	rat.max_hp = int(rat.def.get("hp", 5))
	rat.hp = rat.max_hp
	rat.target = null
	_clear_foes(p, w)
	main.hud.show_panel("skills")
	await frames(10)
	res["tracker_text"] = main.hud.skill_tracker_text("forestry")
	label = "skills_tracker"
	await _snap("skills_xp_tracker")
	main.hud.show_panel("")
	_notes["xp"] = res



## 0.3.9 autotiled fences / walls / moat, floor transitions, 4-way facing.
func _autotile039() -> void:
	var p: Player = main.player
	var w: World = main.world
	var g: WorldGen = w.gen
	var res := {}
	main._set_zoom(2)
	p.hp = p.max_hp()
	# every fence piece kind present in the world
	var kinds := {}
	var broken := 0
	var total := 0
	var t_at := Vector2i(1 << 30, 0)
	var corner_at := Vector2i(1 << 30, 0)
	var vfence := Vector2i(1 << 30, 0)
	var hfence := Vector2i(1 << 30, 0)
	for src in [g._town_objects, g.road_decor]:
		for q in src.keys():
			if g.autotile_group_at(q) != "fence_rural":
				continue
			var pc := w.autotile_piece(q, "fence_rural")
			var nm := Autotile.piece_name(pc.x)
			kinds[nm] = int(kinds.get(nm, 0)) + 1
			total += 1
			broken += 1 if pc.y == 1 else 0
			if nm == "t" and t_at.x == 1 << 30: t_at = q
			if nm == "corner" and corner_at.x == 1 << 30: corner_at = q
			if src == g.road_decor and nm == "straight_v" and vfence.x == 1 << 30 and g.autotile_group_at(q + Vector2i(0, 2)) != "": vfence = q
			if src == g.road_decor and nm == "straight_h" and hfence.x == 1 << 30 and g.autotile_group_at(q + Vector2i(2, 0)) != "": hfence = q
	res["fence_kinds"] = kinds
	res["broken_share"] = float(broken) / maxf(1.0, float(total))
	var spots := {"fence_corner_t": t_at if t_at.x != 1 << 30 else corner_at, "road_fence_vertical": vfence, "road_fence_horizontal": hfence}
	res["spots"] = {}
	for nm in spots.keys():
		var q: Vector2i = spots[nm]
		res["spots"][nm] = [q.x, q.y]
		if q.x == 1 << 30:
			continue
		p.stop()
		p.place_at(w.find_free_tile_near(q + Vector2i(2, 2), 4))
		w.set_focus(q, true)
		await frames(25)
		label = nm
		await _snap(nm)
	# the road fence blocks walking but an arrow flies over it
	if vfence.x != 1 << 30:
		res["vfence_blocks"] = w.is_blocked(vfence)
		res["vfence_los"] = Combat.line_of_sight(w, vfence + Vector2i(-2, 0), vfence + Vector2i(2, 0))
	# floor transitions: a stretch of stone road on grass near Fenhollow's road
	var road: Array = g.road_between("fenhollow", g.capital)
	var tq: Vector2i = road[mini(30, road.size() - 1)]
	p.place_at(w.find_free_tile_near(tq + Vector2i(0, 2), 4))
	w.set_focus(tq, true)
	await frames(25)
	label = "transitions"
	await _snap("transitions")
	var tc := 0
	var cv: Node = w.chunk_views.get(World.chunk_of(tq))
	if cv:
		for l in cv.get_children():
			if l.name.begins_with("trans"):
				tc += (l as TileMapLayer).get_used_cells().size()
	res["transition_cells"] = tc
	# 0.3.11 the moat became a round city wall: find the ring on its diagonal
	# side and on every compass side (the ring art is one piece per octant)
	var hc := g.town_center(g.capital)
	var mc := Vector2i(1 << 30, 0)
	for r in range(10, 60):
		var q := hc + Vector2i(-r, -r)
		if g.tile_at(q.x, q.y) == WorldGen.TileType.CAPITAL_WALL:
			mc = q
			break
	res["moat_corner"] = [mc.x, mc.y]
	var mk := {}
	for side in [["N", Vector2i(0, -1)], ["E", Vector2i(1, 0)], ["S", Vector2i(0, 1)], ["W", Vector2i(-1, 0)], ["NW", Vector2i(-1, -1)]]:
		var sd: Vector2i = side[1]
		for off in [0, 4, -4]:   # 0.3.11 v3.1 the straight ray runs through the gate passage
			var q0: Vector2i = hc + Vector2i(sd.y, sd.x) * off
			for r in range(5, 70):
				var q3: Vector2i = q0 + sd * r
				if g.tile_at(q3.x, q3.y) == WorldGen.TileType.CAPITAL_WALL:
					mk[side[0]] = true
					break
	res["moat_pieces"] = mk.keys()
	if mc.x != 1 << 30:
		p.place_at(w.find_free_tile_near(mc + Vector2i(4, 4), 6))
		w.set_focus(mc, true)
		await frames(25)
		label = "moat_corner"
		await _snap("moat_corner")
	# the player walks up: the back sheet shows (body and gear)
	p.stop()
	var start: Vector2i = g.town_spawn("fenhollow")
	p.place_at(start)
	w.set_focus(start, true)
	await frames(20)
	var up_to := start + Vector2i(0, -5)
	up_to = w.find_free_tile_near(up_to, 2)
	label = "walk_up"
	await tap_tile(up_to, "north")
	var saw_back := false
	var gear_back := true
	for i in 60:
		await frames(1)
		if p.facing.dir == "up" and not p.path.is_empty():
			saw_back = p._sprite.texture == GameData.actor_texture("player", "up")
			for l in p._layers.values():
				if (l as Sprite2D).visible:
					gear_back = gear_back and (l as Sprite2D).texture == GameData.actor_texture(str(l.get_meta("sprite_id")), "up")
			if saw_back:
				await _snap("player_walk_up_back")
				break
	res["walk_up"] = {"back": saw_back, "gear_back": gear_back, "dir": p.facing.dir}
	await until(arrived, 10.0)
	label = ""
	_notes["autotile"] = res



## 0.3.9.1 directional frames (cow x4, player front/back with a shield), fence runs and ends.
func _gfx0391() -> void:
	var p: Player = main.player
	var w: World = main.world
	var g: WorldGen = w.gen
	var res := {}
	main._set_zoom(3)
	# a cow in 4 directions
	var cow = null
	for e in w.enemies.enemies:
		if e.kind == "cow" and not e.dead:
			cow = e
			break
	res["cow"] = {}
	if cow != null:
		p.stop()
		p.place_at(w.find_free_tile_near(cow.tile + Vector2i(0, 3), 4))
		w.set_focus(cow.tile, true)
		await frames(20)
		for dname in ["right", "left", "down", "up"]:
			cow.facing.dir = "side" if dname in ["right", "left"] else dname
			cow.facing.left = dname == "left"
			cow.home = cow.tile
			cow._last_move_t = -100
			await frames(3)
			cow.facing.dir = "side" if dname in ["right", "left"] else dname
			cow.facing.left = dname == "left"
			w.set_focus(cow.tile, true)
			await frames(2)
			res["cow"][dname] = {"tex": cow._sprite.texture.resource_path, "flip": cow._sprite.flip_h}
			label = "cow_" + dname
			await _snap("cow_" + dname)
	# the player with a shield, front and back
	var shield_id := ""
	for iid in GameData.items.keys():
		if str(GameData.item(iid).get("gear", {}).get("slot", "")) == "shield":
			shield_id = iid
			break
	var keep: Dictionary = p.equipment.duplicate()
	if shield_id != "":
		p.equipment["shield"] = shield_id
	p.stop()
	p.place_at(g.town_spawn("fenhollow") + Vector2i(0, 2))
	w.set_focus(p.tile, true)
	await frames(20)
	res["player"] = {}
	for dname in ["down", "up"]:
		p.facing.dir = dname
		await frames(3)
		var sh: Sprite2D = p._layers.get("shield")
		res["player"][dname] = {"tex": p._sprite.texture.resource_path, "shield_under": sh != null and sh.get_index() < p._sprite.get_index(), "shield": sh != null}
		label = "player_" + dname
		await _snap("player_%s_shield" % ("front" if dname == "down" else "back"))
	p.facing.dir = "side"
	p.equipment = keep
	# fence runs: a run with an end post and one with a broken end
	main._set_zoom(2)
	var end_post := Vector2i(1 << 30, 0)
	var end_broken := Vector2i(1 << 30, 0)
	var short := 0
	var seen := {}
	for q in g.road_decor.keys():
		if g.road_decor[q] != "road_fence":
			continue
		if not seen.has(q):
			var run := g.fence_run_at(q)
			for c in run:
				seen[c] = true
			if run.size() < 3:
				short += 1
		var pc := w.autotile_piece(q, "fence_rural")
		if Autotile.piece_name(pc.x) == "end":
			if pc.y == 0 and end_post.x == 1 << 30: end_post = q
			if pc.y == 1 and end_broken.x == 1 << 30: end_broken = q
	res["fences"] = {"short_runs": short, "end_post": [end_post.x, end_post.y], "end_broken": [end_broken.x, end_broken.y]}
	for pair in [["fence_end_post", end_post], ["fence_end_broken", end_broken]]:
		var q: Vector2i = pair[1]
		if q.x == 1 << 30:
			continue
		p.stop()
		p.place_at(w.find_free_tile_near(q + Vector2i(2, 2), 4))
		w.set_focus(q, true)
		await frames(25)
		label = pair[0]
		await _snap(pair[0])
	label = ""
	_notes["gfx"] = res
