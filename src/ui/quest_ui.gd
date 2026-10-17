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
			var l := Overhead.make(Color("#ffe030"))
			l.add_theme_font_size_override("font_size", 20)   # 0.3.7.1 bigger ? / !
			l.add_theme_constant_override("outline_size", 5)
			l.size = Vector2(40, 26)
			Overhead.place(l, 24.0)
			Overhead.attach(l, o.view)
			e = [l, o.view]
			_labels[gid] = e
		if not e.is_empty() and is_instance_valid(e[0]):
			(e[0] as Label).text = QuestSystem.giver_marker(player, gid)
	_update_arrow()
	queue_redraw()


var objective: Dictionary = {}
var marker_visible := false      # on-screen marker above the target
var marker_pos := Vector2.ZERO
var _t := 0.0


func _update_arrow() -> void:
	arrow_visible = false
	marker_visible = false
	objective = QuestSystem.objective(player, world)
	if objective.is_empty():
		return
	var tgt: Vector2i = objective["tile"]
	arrow_target = tgt
	var sp := _screen_of(tgt)
	var vs := get_viewport_rect().size
	var r := Rect2(Vector2(EDGE, TOP), vs - Vector2(EDGE * 2, TOP + BOTTOM))
	if r.has_point(sp):
		# on screen: a bouncing marker over the goblin / Warlord / camp (NPCs have their "!")
		if str(objective["kind"]) != "npc":
			marker_visible = true
			marker_pos = sp + Vector2(0, -34)
		return
	var c := r.get_center()
	var d := sp - c
	var k := minf(absf((r.size.x * 0.5) / d.x) if d.x != 0 else INF, absf((r.size.y * 0.5) / d.y) if d.y != 0 else INF)
	arrow_pos = c + d * k
	arrow_visible = true


func _screen_of(t: Vector2i) -> Vector2:
	return world.get_global_transform_with_canvas() * world.tile_foot(t)


func _draw() -> void:
	_t = Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + 0.18 * sin(_t * 6.0)
	var gold := Color("#ffd23a")
	if marker_visible:
		var bob := 3.0 * sin(_t * 5.0)
		var m := marker_pos + Vector2(0, bob)
		var tri := PackedVector2Array([m + Vector2(0, 9), m + Vector2(-8, -5), m + Vector2(8, -5)])
		draw_colored_polygon(tri, gold)
		tri.append(tri[0])
		draw_polyline(tri, Color.BLACK, 1.5)
	if not arrow_visible:
		return
	var sp := _screen_of(arrow_target)
	var dir := (sp - arrow_pos).normalized()
	var n := Vector2(-dir.y, dir.x)
	var L := 18.0 * pulse        # logical px (x3 on a 1080-wide phone = ~54 px)
	var tip := arrow_pos + dir * L * 0.6
	var pts := PackedVector2Array([tip, arrow_pos - dir * L * 0.5 + n * L * 0.55, arrow_pos - dir * L * 0.2, arrow_pos - dir * L * 0.5 - n * L * 0.55])
	draw_circle(arrow_pos, L * 0.75, Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, gold)
	pts.append(tip)
	draw_polyline(pts, Color.BLACK, 2.0)
