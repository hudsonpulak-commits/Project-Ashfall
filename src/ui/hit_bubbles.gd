class_name HitBubbles
extends Node2D
## Damage bubbles ("hitsplats"). At most ONE per target: a new hit on the same
## actor / enemy / object removes the previous bubble at once and shows the
## new value in the same spot. Bubbles follow their target node; misses (0)
## follow the same rule. Tunables: data/fx.json "hitsplat".

var screen_gate := true          # tests turn the on-screen gate for heal/poison off
var bubbles: Dictionary = {}     # key (instance id) -> {label, target, anchor, age}


func cfg() -> Dictionary:
	return GameData.fx.get("hitsplat", {})


func lifetime() -> float:
	return float(cfg().get("lifetime_s", 0.6))


func _key(target) -> int:
	return target.get_instance_id() if target is Object else 0


## Show `amount` on `target` (a Node2D follows it; anything else is pinned at
## `tile`). Replaces any bubble already on that target.
## restyle: splat colours (dark palette). Healing is never red; a heal of 0 shows nothing.
const SPLAT_COLORS := {"hit": "#a8281e", "block": "#2a5aa8", "heal": "#2e7a36", "poison": "#6a2e8a"}


static func splat_color(amount: int, kind: String = "hit") -> Color:
	if kind == "heal" or kind == "poison":
		return Color(SPLAT_COLORS[kind])
	return Color(SPLAT_COLORS["hit"] if amount > 0 else SPLAT_COLORS["block"])


func show_hit(target, tile: Vector2i, amount: int, kind: String = "hit") -> void:
	if kind == "heal" and amount <= 0:
		return
	# regen ticks everywhere: only bubble a heal / poison tick that is on screen
	if screen_gate and kind != "hit" and target is Node2D and is_inside_tree() and not _on_screen(target as Node2D):
		return
	var k := _key(target)
	clear_target(target)
	var box := Label.new()
	box.text = str(amount)
	box.add_theme_font_size_override("font_size", int(cfg().get("font_size", 6)))
	box.add_theme_color_override("font_color", Color.WHITE)
	box.add_theme_stylebox_override("normal", UIStyle.box(splat_color(amount, kind), Color.BLACK, 1, 1))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var ts := float(GameData.tile_size)
	var anchor := Vector2((tile.x + 0.5) * ts, (tile.y + 1) * ts)
	bubbles[k] = {"label": box, "target": target if target is Node2D else null, "anchor": anchor, "age": 0.0, "amount": amount, "kind": kind}
	_place(bubbles[k])


func _on_screen(n: Node2D) -> bool:
	if not n.is_inside_tree():
		return false
	var sp: Vector2 = n.get_global_transform_with_canvas().origin
	return get_viewport_rect().grow(32).has_point(sp)


func clear_target(target) -> void:
	var k := _key(target)
	if bubbles.has(k):
		var old: Label = bubbles[k]["label"]
		if is_instance_valid(old):
			remove_child(old)
			old.free()
		bubbles.erase(k)


## How many bubbles are on `target` right now (0 or 1) and the value shown.
func count_on(target) -> int:
	return 1 if bubbles.has(_key(target)) else 0


func value_on(target) -> int:
	return int(bubbles[_key(target)]["amount"]) if bubbles.has(_key(target)) else -1


func kind_on(target) -> String:
	return str(bubbles[_key(target)].get("kind", "hit")) if bubbles.has(_key(target)) else ""


func label_on(target) -> Label:
	return bubbles[_key(target)]["label"] if bubbles.has(_key(target)) else null


func _place(b: Dictionary) -> void:
	var t = b["target"]
	if t != null and is_instance_valid(t):
		b["anchor"] = t.position
	var off: Array = cfg().get("offset", [-4, -20])
	# restyle: 16x16 humanoids (player / AI players) sit 8 px lower than the old 16x24 art
	var dy := 0.0
	if t != null and is_instance_valid(t) and t is Actor:
		dy = float(t.body_height_delta())
	(b["label"] as Label).position = (b["anchor"] + Vector2(float(off[0]), float(off[1]) + dy)).round()


func _process(delta: float) -> void:
	var life := lifetime()
	var fade := float(cfg().get("fade_s", 0.2))
	for k in bubbles.keys():
		var b: Dictionary = bubbles[k]
		var lab: Label = b["label"]
		b["age"] = float(b["age"]) + delta
		var t = b["target"]
		if float(b["age"]) >= life or not is_instance_valid(lab) or (t != null and not is_instance_valid(t)):
			if is_instance_valid(lab):
				remove_child(lab)
				lab.free()
			bubbles.erase(k)
			continue
		_place(b)
		lab.modulate.a = clampf((life - float(b["age"])) / maxf(0.01, fade), 0.0, 1.0)
