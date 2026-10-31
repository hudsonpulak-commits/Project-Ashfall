class_name MapPanel
extends VBoxContainer
## World map of the continent: towns labelled, roads, the player (white) and
## travelling traders (purple). 0.3.1: long-press to drop a custom marker;
## tap a marker to edit / delete / walk there. Clear-all with confirm.
## Markers also draw on the minimap (toggle).

const SCALE := 2                 # base map px per map texel at zoom 1
const ZOOM_MIN := 1.0
const ZOOM_MAX := 6.0
const DRAG_SLOP := 10.0          # tap vs drag (px)
var zoom := 1.0                  # 0.3.7.1 pinch / +- zoom
var _center := Vector2(-1, -1)   # map-texture px at the view centre (-1 = follow the player)
var _touches: Dictionary = {}    # touch index -> position
var _pinch_d := 0.0
var _multi := false              # a 2-finger gesture is running (no tap / long-press)
var _dragging := false
var _markers_btn: Button
var player: Player
var world
var _view: Control
var _info: Label
var _buttons: HBoxContainer
var _tools: VBoxContainer
var _blink := 0.0

# editor state
var _mode := ""                 # "" | "add" | "edit" | "clear_armed" | "delete_armed"
var _edit_id := -1
var _draft_tile := Vector2i.ZERO
var _draft_icon := "pin"
var _draft_colour := "#e05050"
var _draft_label := ""
var _icon_row: HBoxContainer
var _colour_row: HBoxContainer
var _label_edit: LineEdit
var _action_row: HBoxContainer
var _status: Label
var _minimap_btn: Button
var _clear_btn: Button

# long-press / tap (Android touch + emulated mouse)
var touch_emulated: bool = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)
var clock_skew_ms := 0
var _last_tap_ms := -100000
var taps := 0                   # accepted short taps (tests)
var long_presses := 0           # accepted long-presses (tests)
var _pressing := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _long_fired := false
var _press_source := ""         # "mouse" | "touch"


func setup(p: Player, w) -> void:
	player = p
	world = w
	add_theme_constant_override("separation", 2)
	_info = UIKit.label("", 9, UIStyle.ACCENT)
	add_child(_info)
	_view = Control.new()
	_view.custom_minimum_size = Vector2(0, 220)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_map)
	_view.gui_input.connect(_on_view_input)
	add_child(_view)
	_status = UIKit.label("Long-press the map to drop a marker.", 8, UIStyle.TEXT_DIM)
	add_child(_status)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 2)
	_tools.visible = false
	add_child(_tools)
	_tools.add_child(UIKit.label("Icon", 8, UIStyle.TEXT_DIM))
	_icon_row = HBoxContainer.new()
	_icon_row.add_theme_constant_override("separation", 2)
	_tools.add_child(_icon_row)
	_tools.add_child(UIKit.label("Colour", 8, UIStyle.TEXT_DIM))
	_colour_row = HBoxContainer.new()
	_colour_row.add_theme_constant_override("separation", 2)
	_tools.add_child(_colour_row)
	_label_edit = LineEdit.new()
	_label_edit.placeholder_text = "Label (optional)"
	_label_edit.max_length = MapMarkers.label_max()
	_label_edit.add_theme_font_size_override("font_size", 10)
	_label_edit.custom_minimum_size = Vector2(0, 22)
	_label_edit.text_changed.connect(func(t): _draft_label = t)
	_tools.add_child(_label_edit)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 2)
	_tools.add_child(_action_row)
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 2)
	_minimap_btn = UIKit.button("Minimap: on", func():
		player.map_markers.show_on_minimap = not player.map_markers.show_on_minimap
		_refresh_toggles()
		Events.say("Markers on minimap: " + ("on" if player.map_markers.show_on_minimap else "off")), 0, 22)
	_minimap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggles.add_child(_minimap_btn)
	_markers_btn = UIKit.button("Markers: on", func(): toggle_markers(), 0, 22)
	_markers_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggles.add_child(_markers_btn)
	var zo: Button = UIKit.button("-", func(): zoom_at(0.8, _view.size / 2.0), 26, 22)
	zo.name = "ZoomOut"
	toggles.add_child(zo)
	var zi: Button = UIKit.button("+", func(): zoom_at(1.25, _view.size / 2.0), 26, 22)
	zi.name = "ZoomIn"
	toggles.add_child(zi)
	_clear_btn = UIKit.button("Clear all", func(): _on_clear_pressed(), 0, 22)
	_clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggles.add_child(_clear_btn)
	add_child(toggles)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 2)
	add_child(_buttons)


func open() -> void:
	UIKit.clear(_buttons)
	for id in world.gen.town_order:
		var tid: String = id
		var b := UIKit.button("To " + world.gen.town_name(id), func():
			if player.start_travel(world, tid):
				get_meta("hud").show_panel(""), 0, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = player.current_town == id and world.gen.town_at(player.tile, 8) == id
		_buttons.add_child(b)
	_cancel_edit()
	_refresh_info()
	_refresh_toggles()
	_status.text = "Long-press the map to drop a marker. Tap a marker to edit."


func _refresh_info() -> void:
	var here: String = world.gen.place_at(player.tile, 8)
	var near: String = world.gen.nearest_town(player.tile)
	var d := int(Vector2(player.tile - world.gen.town_center(near)).length())
	_info.text = ("In %s" % world.gen.town_name(here)) if here != "" else ("Wilds, %d tiles from %s" % [d, world.gen.town_name(near)])
	_info.text += "   (%d, %d)   markers %d/%d" % [player.tile.x, player.tile.y, player.map_markers.count(), MapMarkers.max_count()]


func toggle_markers() -> void:
	MapPrefs.set_markers_shown(not MapPrefs.markers_shown())
	_refresh_toggles()
	Events.say("Map markers: " + ("shown" if MapPrefs.markers_shown() else "hidden"))


func _refresh_toggles() -> void:
	if _markers_btn:
		_markers_btn.text = "Markers: " + ("on" if MapPrefs.markers_shown() else "off")
	_minimap_btn.text = "Minimap: " + ("on" if player.map_markers.show_on_minimap else "off")
	if _mode == "clear_armed":
		_clear_btn.text = "Tap again to clear"
	else:
		_clear_btn.text = "Clear all"


func _process(dt: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_timed(dt)
	World.pmark("map_panel", _pt0)


func _process_timed(dt: float) -> void:
	if not visible:
		return
	_blink += dt
	_view.queue_redraw()
	# long-press fires while still held
	if _pressing and not _long_fired:
		var held := _now_ms() - _press_ms
		if held >= int(MapMarkers.cfg().get("long_press_ms", 450)):
			_long_fired = true
			_begin_add(_screen_to_tile(_press_pos))


func _now_ms() -> int:
	return Time.get_ticks_msec() + clock_skew_ms


## Map view local pos -> world tile.
func _screen_to_tile(local: Vector2) -> Vector2i:
	var off := _map_offset()
	var mp: Vector2 = (local - off) / _s()
	var b: Rect2i = world.gen.bounds()
	var tx := b.position.x + int(round(mp.x * float(World.MAP_STEP)))
	var ty := b.position.y + int(round(mp.y * float(World.MAP_STEP)))
	return Vector2i(tx, ty)


func _s() -> float:
	return float(SCALE) * zoom


func _map_offset() -> Vector2:
	var tex: ImageTexture = world.world_map_texture()
	var sz := Vector2(tex.get_size()) * _s()
	var vs := _view.size
	var cpx: Vector2 = world.map_pixel(player.tile) if _center.x < 0 else _center
	var pp: Vector2 = cpx * _s()
	var off := (vs / 2.0 - pp).floor()
	off.x = clampf(off.x, minf(0.0, vs.x - sz.x), maxf(0.0, (vs.x - sz.x) / 2.0))
	off.y = clampf(off.y, minf(0.0, vs.y - sz.y), maxf(0.0, (vs.y - sz.y) / 2.0))
	return off.floor()


## Map-texture px under a view-local point.
func _local_to_map(local: Vector2) -> Vector2:
	return (local - _map_offset()) / _s()


## Zoom by factor f keeping the map point under `focus` (view-local) fixed.
func zoom_at(f: float, focus: Vector2) -> void:
	var before := _local_to_map(focus)
	if _center.x < 0:
		_center = _local_to_map(_view.size / 2.0)
	zoom = clampf(zoom * f, ZOOM_MIN, ZOOM_MAX)
	# want: (focus - off) / s == before, with off = vs/2 - center*s
	_center = before - (focus - _view.size / 2.0) / _s()
	_clamp_center()
	_view.queue_redraw()


func pan_by(delta_local: Vector2) -> void:
	if _center.x < 0:
		_center = _local_to_map(_view.size / 2.0)
	_center -= delta_local / _s()
	_clamp_center()
	_view.queue_redraw()


func _clamp_center() -> void:
	var tsz := Vector2(world.world_map_texture().get_size())
	var half := _view.size / 2.0 / _s()
	_center.x = clampf(_center.x, minf(half.x, tsz.x / 2.0), maxf(tsz.x - half.x, tsz.x / 2.0))
	_center.y = clampf(_center.y, minf(half.y, tsz.y / 2.0), maxf(tsz.y - half.y, tsz.y / 2.0))


func _marker_at(local: Vector2) -> Dictionary:
	var off := _map_offset()
	var hit_r := float(MapMarkers.cfg().get("hit_radius_map_px", 10))
	var best := {}
	var best_d := hit_r
	for m in player.map_markers.markers:
		var q: Vector2 = world.map_pixel(player.map_markers.tile_of(m)) * _s() + off
		var d := local.distance_to(q)
		if d <= best_d:
			best_d = d
			best = m
	return best


func _on_view_input(ev: InputEvent) -> void:
	# 0.3.7.1 pinch zoom / drag pan (touch), wheel zoom (desktop)
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		if _touches.size() >= 2:
			_multi = true
			_pressing = false
			_long_fired = false
			var ps: Array = _touches.values()
			_pinch_d = (ps[0] as Vector2).distance_to(ps[1])
		if _touches.is_empty():
			var was_multi := _multi
			_multi = false
			if was_multi:
				_pressing = false
				_view.accept_event()
				return
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		_view.accept_event()
		if _touches.size() >= 2:
			var ps2: Array = _touches.values()
			var d := (ps2[0] as Vector2).distance_to(ps2[1])
			if _pinch_d > 1.0 and d > 1.0:
				zoom_at(d / _pinch_d, ((ps2[0] as Vector2) + (ps2[1] as Vector2)) / 2.0)
			_pinch_d = d
			return
		if not touch_emulated and _pressing:
			_drag_to(ev.position, ev.relative)
		return
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_at(1.25 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8, ev.position)
		_view.accept_event()
		return
	if _multi:
		_view.accept_event()
		return
	var press := false
	var release := false
	var pos := Vector2.ZERO
	var source := ""
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		source = "mouse"
		press = ev.pressed
		release = not ev.pressed
		_view.accept_event()
	elif ev is InputEventScreenTouch:
		pos = ev.position
		source = "touch"
		press = ev.pressed
		release = not ev.pressed
		_view.accept_event()
	elif ev is InputEventMouseMotion and _pressing:
		_drag_to(ev.position, ev.relative)   # 0.3.7.1 drag pans (past the slop)
		return
	else:
		return
	# Android: touch + emulated mouse. Count one source for press/release.
	if touch_emulated and source == "touch":
		return
	if not touch_emulated and source == "mouse" and _press_source == "touch":
		# when emu off, touch already counted; ignore trailing mouse
		return
	if press:
		_pressing = true
		_dragging = false
		_press_pos = pos
		_press_ms = _now_ms()
		_long_fired = false
		_press_source = source
		return
	if release and _pressing:
		_pressing = false
		if _long_fired or _dragging:
			_dragging = false
			return
		var now := _now_ms()
		if now - _last_tap_ms < int(GameData.fx.get("tap", {}).get("debounce_ms", 250)):
			return
		_last_tap_ms = now
		taps += 1
		_on_short_tap(_press_pos)   # 0.3.7.1 the tile under the finger-down point


func _drag_to(pos: Vector2, rel: Vector2) -> void:
	if not _dragging and _press_pos.distance_to(pos) > DRAG_SLOP:
		_dragging = true
		_long_fired = true    # no long-press once it's a drag
		rel = pos - _press_pos
	if _dragging:
		pan_by(rel)


func _on_short_tap(local: Vector2) -> void:
	var m := _marker_at(local)
	if not m.is_empty() and MapPrefs.markers_shown():
		_begin_edit(m)
		return
	if _mode in ["add", "edit", "delete_armed", "clear_armed"]:
		_cancel_edit()
		_status.text = "Long-press the map to drop a marker. Tap a marker to edit."
		return
	_begin_add(_screen_to_tile(local))   # 0.3.7.1 a plain tap drops a marker too (at the zoomed tile)


func _begin_add(tile: Vector2i) -> void:
	if player.map_markers.is_full():
		_status.text = "Marker limit reached (%d)." % MapMarkers.max_count()
		Events.say("You already have %d markers. Delete one first." % MapMarkers.max_count())
		return
	long_presses += 1
	_mode = "add"
	_edit_id = -1
	_draft_tile = tile
	_draft_icon = MapMarkers.default_icon()
	_draft_colour = MapMarkers.default_colour()
	_draft_label = ""
	_label_edit.text = ""
	_rebuild_editor()
	_status.text = "New marker at (%d, %d). Pick icon & colour, then Save." % [tile.x, tile.y]
	_view.queue_redraw()


func _begin_edit(m: Dictionary) -> void:
	_mode = "edit"
	_edit_id = int(m["id"])
	_draft_tile = player.map_markers.tile_of(m)
	_draft_icon = str(m["icon"])
	_draft_colour = str(m["colour"])
	_draft_label = str(m.get("label", ""))
	_label_edit.text = _draft_label
	_rebuild_editor()
	_status.text = "Edit marker #%d (%d, %d)." % [_edit_id, _draft_tile.x, _draft_tile.y]
	_view.queue_redraw()


func _cancel_edit() -> void:
	_mode = ""
	_edit_id = -1
	_tools.visible = false
	_refresh_toggles()
	_view.queue_redraw()


func _rebuild_editor() -> void:
	_tools.visible = true
	UIKit.clear(_icon_row)
	for ic in MapMarkers.icons():
		var id_ic: String = ic
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 24)
		b.toggle_mode = true
		b.tooltip_text = id_ic
		var tr := TextureRect.new()
		tr.texture = GameData.texture("ui", "marker_%s" % id_ic)
		tr.custom_minimum_size = Vector2(16, 16)
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.modulate = Color(_draft_colour if id_ic == _draft_icon else "#ffffff")
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
		tr.position = Vector2(6, 4)
		b.pressed.connect(func():
			if _draft_icon == id_ic:
				return
			_draft_icon = id_ic
			_rebuild_editor())
		_icon_row.add_child(b)
		b.set_pressed_no_signal(id_ic == _draft_icon)
	UIKit.clear(_colour_row)
	for col in MapMarkers.colours():
		var c: String = col
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(22, 22)
		b2.toggle_mode = true
		b2.modulate = Color(c)
		b2.pressed.connect(func():
			if _draft_colour == c:
				return
			_draft_colour = c
			_rebuild_editor())
		_colour_row.add_child(b2)
		b2.set_pressed_no_signal(c == _draft_colour)
	UIKit.clear(_action_row)
	if _mode == "add":
		_action_row.add_child(UIKit.button("Save", func(): _save_draft(), 0, 24))
		_action_row.add_child(UIKit.button("Cancel", func(): _cancel_edit(), 0, 24))
	elif _mode == "edit" or _mode == "delete_armed":
		_action_row.add_child(UIKit.button("Save", func(): _save_draft(), 0, 24))
		_action_row.add_child(UIKit.button("Walk here", func(): _walk_to_draft(), 0, 24))
		var del_txt := "Tap again to delete" if _mode == "delete_armed" else "Delete"
		_action_row.add_child(UIKit.button(del_txt, func(): _on_delete_pressed(), 0, 24))
		_action_row.add_child(UIKit.button("Cancel", func(): _cancel_edit(), 0, 24))
	for c in _action_row.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _save_draft() -> void:
	_draft_label = _label_edit.text.strip_edges().left(MapMarkers.label_max())
	if _mode == "add":
		var m := player.map_markers.add(_draft_tile, _draft_icon, _draft_colour, _draft_label)
		if m.is_empty():
			_status.text = "Could not add marker (full?)."
			return
		Events.say("Marker placed.")
		_status.text = "Saved marker #%d." % int(m["id"])
	elif _mode in ["edit", "delete_armed"]:
		player.map_markers.update(_edit_id, {
			"icon": _draft_icon, "colour": _draft_colour, "label": _draft_label
		})
		Events.say("Marker updated.")
		_status.text = "Updated marker #%d." % _edit_id
	_cancel_edit()
	_refresh_info()


func _walk_to_draft() -> void:
	player.walk_to(world, _draft_tile)
	Events.say("Walking to marker...")
	get_meta("hud").show_panel("")


func _on_delete_pressed() -> void:
	if _mode == "edit":
		_mode = "delete_armed"
		_rebuild_editor()
		_status.text = "Tap Delete again to confirm."
		return
	if _mode != "delete_armed" or _edit_id < 0:
		return
	var id := _edit_id
	var ok := player.map_markers.remove(id)
	Events.say("Marker deleted." if ok else "No marker to delete.")
	_status.text = "Deleted." if ok else "Delete failed."
	_cancel_edit()
	_refresh_info()


func _on_clear_pressed() -> void:
	if player.map_markers.count() == 0:
		_status.text = "No markers to clear."
		return
	if _mode != "clear_armed":
		_mode = "clear_armed"
		_refresh_toggles()
		_status.text = "Tap Clear all again to erase every marker."
		return
	var n := player.map_markers.clear_all()
	Events.say("Cleared %d markers." % n)
	_status.text = "Cleared %d markers." % n
	_cancel_edit()
	_refresh_info()


## Map texture scaled x2 (integer), centred on the continent; clipped to view.
func _draw_map() -> void:
	var tex: ImageTexture = world.world_map_texture()
	var sz := Vector2(tex.get_size()) * _s()
	var vs := _view.size
	var off := _map_offset()
	var pp: Vector2 = world.map_pixel(player.tile) * _s()
	_view.draw_rect(Rect2(Vector2.ZERO, vs), Color("#1d4a66"))
	_view.draw_texture_rect(tex, Rect2(off, sz), false)
	for a in AIDirector.records:
		if AIBrain.is_trader(a) and a.trip.has("to"):
			var q: Vector2 = world.map_pixel(a.pos) * _s() + off
			_view.draw_rect(Rect2(q.floor(), Vector2(2, 2)), Color("#d070f0"))
	var font := get_theme_default_font()
	for id in world.gen.towns.keys():
		var c: Vector2 = world.map_pixel(world.gen.town_center(id)) * _s() + off
		var name: String = world.gen.town_name(id)
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var lp := (c + Vector2(-w / 2.0, -8)).floor()
		_view.draw_rect(Rect2(lp + Vector2(-2, -9), Vector2(w + 4, 11)), Color(0, 0, 0, 0.6))
		_view.draw_string(font, lp, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIStyle.ACCENT)
	# 0.3.1 villages: smaller, paler labels
	for vid in world.gen.village_order:
		var vc: Vector2 = world.map_pixel(world.gen.town_center(vid)) * _s() + off
		var vname: String = world.gen.town_name(vid)
		var vw := font.get_string_size(vname, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var vp := (vc + Vector2(-vw / 2.0, -6)).floor()
		_view.draw_rect(Rect2(vp + Vector2(-2, -8), Vector2(vw + 4, 10)), Color(0, 0, 0, 0.45))
		_view.draw_string(font, vp, vname, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#e8dcb8"))
	# 0.3.7 quest giver "?" / "!" + 0.3.7.1 objective area (hidden with the Markers toggle)
	var show_m := MapPrefs.markers_shown()
	var area = QuestSystem.objective_area(player, world) if show_m else null
	if area != null:
		var aq: Vector2 = world.map_pixel(area) * _s() + off
		var pr := 5.0 + 1.5 * sin(_blink * 6.0)
		_view.draw_circle(aq, pr + 2.0, Color(0, 0, 0, 0.6))
		_view.draw_circle(aq, pr, Color("#e04040"))
		_view.draw_line(aq + Vector2(-3, -3), aq + Vector2(3, 3), Color.WHITE, 1.5)
		_view.draw_line(aq + Vector2(-3, 3), aq + Vector2(3, -3), Color.WHITE, 1.5)
	for gid in (QuestSystem.cfg().get("givers", {}).keys() if show_m else []):
		var mk := QuestSystem.giver_marker(player, gid)
		if mk != "":
			var gq: Vector2 = world.map_pixel(QuestSystem.giver_tile(world, gid)) * _s() + off
			_view.draw_rect(Rect2(gq + Vector2(-5, -12), Vector2(11, 13)), Color(0, 0, 0, 0.75))
			_view.draw_string(font, gq + Vector2(-3, -1), mk, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f0e040"))
	# custom markers
	for m in (player.map_markers.markers if show_m else []):
		_draw_marker_at(m, off, font, int(m["id"]) == _edit_id)
	# draft ghost while adding
	if _mode == "add":
		var ghost := {"icon": _draft_icon, "colour": _draft_colour, "label": _draft_label, "x": _draft_tile.x, "y": _draft_tile.y, "id": -1}
		_draw_marker_at(ghost, off, font, true)
	if int(_blink * 3.0) % 2 == 0:
		_view.draw_rect(Rect2((pp + off - Vector2(1, 1)).floor(), Vector2(4, 4)), Color.WHITE)
	var did: String = world.den_at(player.tile)
	if did != "":
		_draw_den_inset(did, font)
	_view.draw_rect(Rect2(Vector2.ZERO, vs), UIStyle.BORDER_HI, false, 1.0)


## 0.4.2 underground: the den's own layout in an inset (top right), you + the ladder up.
func _draw_den_inset(did: String, font: Font) -> void:
	var tex: ImageTexture = world.den_map_texture(did)
	var inner: Rect2i = world.gen.dens[did]["inner"]
	var vs := _view.size
	var k := maxf(1.0, floorf(minf(vs.x * 0.5 / float(inner.size.x), (vs.y - 24.0) / float(inner.size.y))))
	var sz := Vector2(inner.size) * k
	var o := Vector2(vs.x - sz.x - 6.0, 18.0).floor()
	_view.draw_rect(Rect2(o - Vector2(3, 15), sz + Vector2(6, 18)), Color(0, 0, 0, 0.85))
	_view.draw_texture_rect(tex, Rect2(o, sz), false)
	var title := "%s (underground)" % str(world.gen.dens[did].get("name", "Den"))
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_view.draw_string(font, (o + Vector2((sz.x - tw) / 2.0, -4)).floor(), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIStyle.ACCENT)
	var lad: Vector2i = world.gen.den_marker(did, "U")
	if lad.x > -99999:
		var lq := o + Vector2(lad - inner.position) * k
		_view.draw_rect(Rect2(lq - Vector2(1, 1), Vector2(k + 2, k + 2)), Color("#e0c080"))
	var me := o + Vector2(player.tile - inner.position) * k
	if int(_blink * 3.0) % 2 == 0:
		_view.draw_rect(Rect2(me - Vector2(1, 1), Vector2(k + 2, k + 2)), Color.WHITE)


func _draw_marker_at(m: Dictionary, off: Vector2, font: Font, selected: bool) -> void:
	var q: Vector2 = world.map_pixel(Vector2i(int(m["x"]), int(m["y"]))) * _s() + off
	var ic_tex: Texture2D = GameData.texture("ui", "marker_%s" % str(m["icon"]))
	var col := Color(str(m["colour"]))
	var dest := Rect2((q - Vector2(6, 12)).floor(), Vector2(12, 12))
	if selected:
		_view.draw_rect(dest.grow(2), Color(1, 1, 1, 0.35))
	_view.draw_texture_rect(ic_tex, dest, false, col)
	var lab := str(m.get("label", ""))
	if lab != "":
		var tw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var lp := (q + Vector2(-tw / 2.0, 4)).floor()
		_view.draw_rect(Rect2(lp + Vector2(-1, -8), Vector2(tw + 2, 10)), Color(0, 0, 0, 0.55))
		_view.draw_string(font, lp, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
