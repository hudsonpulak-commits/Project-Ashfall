class_name Minimap
extends Control
## Draws pre-baked 1px-per-tile chunk images at an integer 2x scale around the
## player. Costs ~25 texture draws per redraw; no per-tile work per frame.
## Tap the minimap to walk there. 0.3.1: custom map markers (toggle on Map panel).

signal tapped_tile(tile: Vector2i)

const SCALE := 2
var world: World
var player: Actor
var others: Array = []
var markers_btn: Button
var _last_tile := Vector2i(1 << 20, 0)


func _init() -> void:
	custom_minimum_size = Vector2(84, 84)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 0.3.7.1 tiny toggle: show / hide map markers (player pins + quest markers)
	markers_btn = Button.new()
	markers_btn.name = "MarkersToggle"
	markers_btn.focus_mode = Control.FOCUS_NONE
	markers_btn.text = "M"
	markers_btn.add_theme_font_size_override("font_size", 7)
	markers_btn.position = Vector2(1, 1)
	markers_btn.size = Vector2(14, 12)
	markers_btn.custom_minimum_size = Vector2(14, 12)
	markers_btn.pressed.connect(func():
		MapPrefs.set_markers_shown(not MapPrefs.markers_shown())
		Events.say("Map markers: " + ("shown" if MapPrefs.markers_shown() else "hidden")))
	add_child(markers_btn)


func _process(_dt: float) -> void:
	if player and player.tile != _last_tile:
		_last_tile = player.tile
	queue_redraw()   # cheap; also animates AI dots


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#10140c"))
	if world == null or player == null:
		return
	var center := size / 2.0
	var pt := player.tile
	var half_tiles := int(ceil(size.x / SCALE / 2.0)) + 1
	var c0 := World.chunk_of(pt - Vector2i(half_tiles, half_tiles))
	var c1 := World.chunk_of(pt + Vector2i(half_tiles, half_tiles))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			var tex := world.minimap_texture(c)
			var origin := Vector2((c.x * World.CHUNK - pt.x) * SCALE, (c.y * World.CHUNK - pt.y) * SCALE) + center
			draw_texture_rect(tex, Rect2(origin.floor(), Vector2(World.CHUNK, World.CHUNK) * SCALE), false)
	# 0.3.1 custom markers (when the player has them and the toggle is on)
	if player is Player:
		var mm: MapMarkers = (player as Player).map_markers
		if mm.show_on_minimap and MapPrefs.markers_shown():
			for m in mm.markers:
				var mx := int(m["x"]) - pt.x
				var my := int(m["y"]) - pt.y
				if abs(mx) > half_tiles or abs(my) > half_tiles:
					continue
				var p := Vector2(mx * SCALE, my * SCALE) + center
				var ic: Texture2D = GameData.texture("ui", "marker_%s" % str(m["icon"]))
				var dest := Rect2((p - Vector2(4, 4)).floor(), Vector2(8, 8))
				draw_texture_rect(ic, dest, false, Color(str(m["colour"])))
	# 0.3.7 quest giver "?" / "!" + 0.3.7.1 objective area (Markers toggle)
	if player is Player and MapPrefs.markers_shown():
		var area = QuestSystem.objective_area(player, world)
		if area != null:
			var ap := Vector2((area.x - pt.x) * SCALE, (area.y - pt.y) * SCALE) + center
			ap = ap.clamp(Vector2(5, 5), size - Vector2(5, 5))   # off the minimap: pinned to its edge
			draw_circle(ap, 4.5, Color(0, 0, 0, 0.7))
			draw_circle(ap, 3.2, UIStyle.EMBER)
		for gid in QuestSystem.cfg().get("givers", {}).keys():
			var mk := QuestSystem.giver_marker(player, gid)
			var gt := QuestSystem.giver_tile(world, gid)
			if mk == "" or abs(gt.x - pt.x) > half_tiles or abs(gt.y - pt.y) > half_tiles:
				continue
			var gp := Vector2((gt.x - pt.x) * SCALE, (gt.y - pt.y) * SCALE) + center
			var f := get_theme_default_font()
			draw_rect(Rect2(gp + Vector2(-4, -10), Vector2(9, 11)), Color(0, 0, 0, 0.7))
			draw_string(f, gp + Vector2(-3, 0), mk, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f0e040"))
	for a in others:
		if is_instance_valid(a):
			var p2 := Vector2((a.tile.x - pt.x) * SCALE, (a.tile.y - pt.y) * SCALE) + center
			draw_rect(Rect2(p2.floor(), Vector2(SCALE, SCALE)), Color("#e2dccb"))
	draw_rect(Rect2(center.floor(), Vector2(SCALE, SCALE)), Color.WHITE)
	if markers_btn:
		markers_btn.modulate = Color.WHITE if MapPrefs.markers_shown() else Color(1, 1, 1, 0.45)
	draw_style_box(UIStyle.tex("minimap_frame", 4, 0), Rect2(-2, -2, size.x + 4, size.y + 4))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and player:
		var off: Vector2 = (ev.position - size / 2.0) / SCALE
		tapped_tile.emit(player.tile + Vector2i(floori(off.x), floori(off.y)))
		accept_event()
