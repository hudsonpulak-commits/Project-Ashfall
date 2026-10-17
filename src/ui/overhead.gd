class_name Overhead
extends RefCounted
## 0.3.3 overhead name labels: "Name (cb)" on AI players, "Name (lvl)" on
## combat enemies. Outlined pixel text, sits above the HP bar and leaves the
## space above it free for chat bubbles. Colour = level vs the player.

static var viewer = null          # the Player (set in Player._ready)
const Y_OFF := 4.0                # world px between the sprite top and the text (HP bar sits at top - 3..-1)


## 0.3.4: labels live in a screen-space overlay (CanvasLayer under the HUD),
## not under the zoomed world camera. Root cause of "no names on my phone":
## 0.3.3 used an MSDF copy of the UI font, and the size-optimised export
## template is built without the msdfgen module, so the exported game drew no
## glyphs at all. Now: the normal UI font at FONT_SIZE logical px (x content
## scale on phones: 24 px on a 1080-wide screen), above every actor,
## positioned each frame over its owner.
const FONT_SIZE := 8
const LAYER := 5                  # world < labels < HUD (10)

static var _overlay: CanvasLayer = null
static var _entries: Array = []   # [label, owner]
static var block_rects: Array = []   # 0.3.7.1 screen rects labels must not draw over (chat log), set by the HUD


class _Overlay extends CanvasLayer:
	func _process(_d: float) -> void:
		Overhead.update_all()


static func make(font_color := Color(1, 1, 0.75)) -> Label:
	var l := Label.new()
	l.name = "OverheadLabel"
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", font_color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = Vector2(200, FONT_SIZE + 4)
	return l


## Remember the owner's sprite height (px) for the label's height.
static func place(l: Label, sprite_h: float) -> void:
	l.set_meta("sprite_h", sprite_h)


## Hook a label to its owner (instead of owner.add_child).
static func attach(l: Label, owner: Node2D) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = _Overlay.new()
		_overlay.name = "OverheadLabels"
		_overlay.layer = LAYER
		owner.get_tree().root.add_child.call_deferred(_overlay)
		_entries = _entries.filter(func(e): return is_instance_valid(e[0]))
	_overlay.add_child(l)
	l.modulate.a = 0.0
	_entries.append([l, owner])
	owner.tree_exiting.connect(func(): if is_instance_valid(l): l.queue_free())


## Every frame: follow the owner on screen; hide when the owner is hidden, dead
## or off screen; keep inside the screen edges; fade over your own head.
static func update_all() -> void:
	var keep: Array = []
	for e in _entries:
		if not is_instance_valid(e[0]):
			continue
		var l: Label = e[0]
		var o = e[1]
		if not is_instance_valid(o) or not o.is_inside_tree():
			l.queue_free()
			continue
		keep.append(e)
		var xf: Transform2D = o.get_global_transform_with_canvas()
		var sc := maxf(0.01, xf.get_scale().y)
		var vr: Vector2 = o.get_viewport_rect().size
		# bottom of the text sits Y_OFF world px above the sprite top
		var base_y: float = xf.origin.y - (float(l.get_meta("sprite_h", 24.0)) + Y_OFF) * sc
		var off: bool = xf.origin.x < -8.0 or xf.origin.x > vr.x + 8.0 or xf.origin.y < 0.0 or xf.origin.y > vr.y + 40.0
		if not l.visible or off or not o.is_visible_in_tree():
			l.modulate.a = 0.0
			continue
		var tw: float = l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 6.0
		var cx := clampf(xf.origin.x, tw / 2.0 + 2.0, vr.x - tw / 2.0 - 2.0)
		l.position = Vector2(roundf(cx - l.size.x / 2.0), roundf(base_y - l.size.y))
		var a := 1.0
		var lr := Rect2(Vector2(cx - tw / 2.0, l.position.y), Vector2(tw, l.size.y))
		var hidden := false
		for br in block_rects:
			if (br as Rect2).intersects(lr):
				hidden = true
		if hidden:     # 0.3.7.1 never draw over the chat log
			l.modulate.a = 0.0
			continue
		if viewer != null and is_instance_valid(viewer) and viewer != o and viewer.is_inside_tree():
			var vx: Transform2D = viewer.get_global_transform_with_canvas()
			var hr := Rect2(vx.origin + Vector2(-9, -44) * sc, Vector2(18, 22) * sc)
			if Rect2(Vector2(cx - tw / 2.0, l.position.y), Vector2(tw, l.size.y)).intersects(hr):
				a = 0.3
		l.modulate.a = a
	_entries = keep


## Labels drawn on screen right now (QA).
static func shown_count() -> int:
	var n := 0
	for e in _entries:
		if is_instance_valid(e[0]) and e[0].visible and e[0].modulate.a > 0.5:
			n += 1
	return n


## 0.3.3 call sites: positioning now happens in update_all.
static func clamp_on_screen(_l: Label, _owner: Node2D) -> void:
	pass


static func ai_text(name: String, skills: Skills) -> String:
	return "%s (%d)" % [name, Combat.combat_level(skills)]


## Green = lower than you, yellow = within 2, red = higher.
static func level_color(lvl: int) -> Color:
	var me := Combat.combat_level(viewer.skills) if viewer != null and is_instance_valid(viewer) else 1
	if lvl < me - 2:
		return Color("#6ae06a")
	if lvl > me + 2:
		return Color("#ff5a4a")
	return Color("#ffe04a")


## Enemies that can fight get a label; shopkeepers / citizens / chickens don't.
static func enemy_shows(def: Dictionary) -> bool:
	if def.has("show_level"):
		return bool(def["show_level"])
	return int(def.get("aggro", 0)) > 0 or (bool(def.get("retaliate", true)) and int(def.get("max_hit", 0)) > 0)


