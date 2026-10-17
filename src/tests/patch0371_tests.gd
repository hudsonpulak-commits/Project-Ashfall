class_name Patch0371Tests
extends RefCounted
## 0.3.7.1: objective always guided, quest dialog, map markers toggle, map
## pinch / drag / tap, overhead labels kept off the chat log.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.7.1 guidance / dialog / map")
	var id := "goblin_slayer"
	var keep_q: Dictionary = p.quests.duplicate(true)
	p.quests.clear()
	p.place_at(world.gen.town_spawn("fenhollow"))
	world.set_focus(p.tile, true)
	# dialog: opening never starts; decline keeps '?'
	var opened := [""]
	var cb := func(g): opened[0] = g
	Events.quest_dialog.connect(cb)
	var kell: WorldObject = world.object_at(QuestSystem.giver_tile(world, "kell"))
	p.place_at(world.find_free_tile_near(kell.pos + Vector2i(0, 1), 2))
	p.interact(world, kell)
	WorldTests.ticks(15)
	Events.quest_dialog.disconnect(cb)
	var d := QuestSystem.dialog(p, "kell")
	var labels := []
	for c in d["choices"]:
		labels.append(str(c["label"]))
	check(opened[0] == "kell" and QuestSystem.state(p, id) == QuestSystem.NOT_STARTED, "tapping Kell opens his dialog and does NOT start the quest")
	check(d["name"] == "Kell" and str(d["text"]).length() > 20 and labels == ["Accept", "Decline"], "offer dialog: Kell's lines with Accept / Decline")
	check(QuestSystem.choose(p, id, "decline") != "" and QuestSystem.state(p, id) == QuestSystem.NOT_STARTED and QuestSystem.giver_marker(p, "kell") == "?", "Decline: quest stays not started, still '?'")
	QuestSystem.choose(p, id, "accept")
	check(QuestSystem.state(p, id) == QuestSystem.IN_PROGRESS, "Accept starts it")
	check(str(QuestSystem.dialog(p, "kell")["text"]).contains("Goblins 0/5"), "in progress: a reminder line with progress")
	# objective ALWAYS during a kill stage, even with every goblin far away
	var o := QuestSystem.objective(p, world)
	check(not o.is_empty() and str(o["kind"]) in ["enemy", "area"], "goblin step from Fenhollow: an objective exists (%s)" % str(o))
	var dead := []
	for e in world.enemies.enemies:
		if e.kind == "goblin" and not e.dead:
			e.dead = true
			dead.append(e)
	o = QuestSystem.objective(p, world)
	check(not o.is_empty() and str(o["kind"]) == "area", "all goblins dead: point at the nearest goblin camp (%s)" % str(o))
	for e in dead:
		e.dead = false
	check(QuestSystem.objective_area(p, world) != null, "map/minimap objective area: the goblin camp")
	var ga = QuestSystem.objective_area(p, world)
	p.quests[id] = {"stage": 2, "count": 0, "done": false}
	var o2 := QuestSystem.objective(p, world)
	var wa = QuestSystem.objective_area(p, world)
	check(not o2.is_empty() and wa != null and wa != ga, "Warlord step: objective + its own map area (%s)" % str(wa))
	p.quests[id] = {"stage": 3, "count": 0, "done": false}
	check(str(QuestSystem.dialog(p, "kell")["node"]) == "stage_3" and str(QuestSystem.dialog(p, "kell")["text"]).contains("Warlord is dead"), "turn-in dialog shows completion text")
	# map markers toggle persists in settings.cfg
	MapPrefs.set_markers_shown(false)
	MapPrefs.reload()
	check(not MapPrefs.markers_shown(), "Markers toggle off is saved (settings.cfg) and survives a reload")
	MapPrefs.set_markers_shown(true)
	MapPrefs.reload()
	check(MapPrefs.markers_shown(), "and back on")
	# overhead labels never draw over the chat log
	var l := Overhead.make()
	l.text = "Test (1)"
	var owner := Node2D.new()
	world.entity_layer.add_child(owner)
	owner.position = world.tile_foot(p.tile)
	Overhead.attach(l, owner)
	Overhead.block_rects = [Rect2(Vector2(-10000, -10000), Vector2(20000, 20000))]
	Overhead.update_all()
	check(l.modulate.a == 0.0, "an overhead label inside the chat-log area is hidden")
	Overhead.block_rects = []
	owner.queue_free()
	# world map: pinch zoom, drag pan, tap at zoom drops the marker on the right tile
	var hud = main.hud
	hud.show_panel("map")
	var mp = hud.map_panel
	mp.touch_emulated = false
	var keep_size: Vector2 = mp._view.size
	mp._view.size = Vector2(340, 220)
	mp.zoom = 1.0
	mp._center = Vector2(-1, -1)
	var z0: float = mp.zoom
	_touch(mp, 0, Vector2(150, 110), true)
	_touch(mp, 1, Vector2(190, 110), true)
	_drag(mp, 1, Vector2(250, 110), Vector2(60, 0))
	_touch(mp, 1, Vector2(250, 110), false)
	_touch(mp, 0, Vector2(150, 110), false)
	check(mp.zoom > z0 * 2.0 and mp.zoom <= MapPanel.ZOOM_MAX, "pinch out zooms in (%.2f -> %.2f)" % [z0, mp.zoom])
	var c0: Vector2 = mp._center
	mp.clock_skew_ms += 1000
	_touch(mp, 0, Vector2(170, 110), true)
	_drag(mp, 0, Vector2(185, 110), Vector2(15, 0))
	_drag(mp, 0, Vector2(215, 120), Vector2(30, 10))
	_touch(mp, 0, Vector2(215, 120), false)
	check(mp._center.x < c0.x and mp._mode != "add", "one-finger drag pans (centre %.1f -> %.1f) and drops no marker" % [c0.x, mp._center.x])
	mp.clock_skew_ms += 1000
	var tap_at := Vector2(120, 90)
	var want: Vector2i = mp._screen_to_tile(tap_at)
	_touch(mp, 0, tap_at, true)
	_touch(mp, 0, tap_at + Vector2(3, 2), false)
	check(mp._mode == "add" and mp._draft_tile == want, "a tap at zoom %.1f drops the marker on tile %s (%s)" % [mp.zoom, want, mp._draft_tile])
	mp._cancel_edit()
	mp.zoom = 1.0
	mp._center = Vector2(-1, -1)
	mp.touch_emulated = true
	mp._view.size = keep_size
	mp._touches.clear()
	mp.clock_skew_ms = 0
	mp._last_tap_ms = -100000
	hud.show_panel("")
	p.quests = keep_q


static func _touch(mp, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	mp._on_view_input(e)


static func _drag(mp, idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	mp._on_view_input(e)
