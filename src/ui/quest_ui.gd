class_name QuestUI
extends Control
## 0.3.7 quest overlay: the giver's overhead "?" / "!" and the screen-edge
## guidance arrow to the current objective (hidden when it's on screen).

var player: Player
var world: World
var arrow_visible := false
var arrow_pos := Vector2.ZERO
var arrow_target := Vector2i.ZERO
var _labels: Dictionary = {}   # giver id -> [Label, owner view]
const EDGE := 22.0
const TOP := 110.0       # below the top bars / minimap
const BOTTOM := 70.0     # above the tab bar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func giver_label(gid: String) -> Label:
	var e: Array = _labels.get(gid, [])
	return e[0] if e.size() > 0 and is_instance_valid(e[0]) else null


func _process(_d: float) -> void:
	if player == null or world == null:
		return
	for gid in QuestSystem.cfg().get("givers", {}).keys():
		var t := QuestSystem.giver_tile(world, gid)
		var o: WorldObject = world.object_at(t) if t.x > -99999 else null
		var e: Array = _labels.get(gid, [])
		if o != null and o.view != null and is_instance_valid(o.view) and (e.is_empty() or not is_instance_valid(e[0]) or e[1] != o.view):
			var l := Overhead.make(Color("#f0e040"))
			l.add_theme_font_size_override("font_size", 14)
			Overhead.place(l, 24.0)
			Overhead.attach(l, o.view)
			e = [l, o.view]
			_labels[gid] = e
		if not e.is_empty() and is_instance_valid(e[0]):
			(e[0] as Label).text = QuestSystem.giver_marker(player, gid)
	_update_arrow()
	queue_redraw()


func _update_arrow() -> void:
	arrow_visible = false
	var tgt = QuestSystem.objective_tile(player, world)
	if tgt == null:
		return
	arrow_target = tgt
	var sp: Vector2 = world.get_global_transform_with_canvas() * world.tile_foot(tgt)
	var vs := get_viewport_rect().size
	var r := Rect2(Vector2(EDGE, TOP), vs - Vector2(EDGE * 2, TOP + BOTTOM))
	if r.has_point(sp):
		return    # on screen: no arrow
	var c := r.get_center()
	var d := sp - c
	var k := minf(absf((r.size.x * 0.5) / d.x) if d.x != 0 else INF, absf((r.size.y * 0.5) / d.y) if d.y != 0 else INF)
	arrow_pos = c + d * k
	arrow_visible = true


func _draw() -> void:
	if not arrow_visible:
		return
	var sp: Vector2 = world.get_global_transform_with_canvas() * world.tile_foot(arrow_target)
	var dir := (sp - arrow_pos).normalized()
	var n := Vector2(-dir.y, dir.x)
	var tip := arrow_pos + dir * 12.0
	var pts := PackedVector2Array([tip, arrow_pos - dir * 8.0 + n * 9.0, arrow_pos - dir * 3.0, arrow_pos - dir * 8.0 - n * 9.0])
	draw_colored_polygon(pts, Color("#f0d040"))
	pts.append(tip)
	draw_polyline(pts, Color.BLACK, 2.0)
