class_name HitBubbles
extends Node2D
## Damage bubbles ("hitsplats"). At most ONE per target: a new hit on the same
## actor / enemy / object removes the previous bubble at once and shows the
## new value in the same spot. Bubbles follow their target node; misses (0)
## follow the same rule. Tunables: data/fx.json "hitsplat".

var bubbles: Dictionary = {}     # key (instance id) -> {label, target, anchor, age}


func cfg() -> Dictionary:
	return GameData.fx.get("hitsplat", {})


func lifetime() -> float:
	return float(cfg().get("lifetime_s", 0.6))


func _key(target) -> int:
	return target.get_instance_id() if target is Object else 0


## Show `amount` on `target` (a Node2D follows it; anything else is pinned at
## `tile`). Replaces any bubble already on that target.
func show_hit(target, tile: Vector2i, amount: int) -> void:
	var k := _key(target)
	clear_target(target)
	var box := Label.new()
	box.text = str(amount)
	box.add_theme_font_size_override("font_size", int(cfg().get("font_size", 6)))
	box.add_theme_color_override("font_color", Color.WHITE)
	box.add_theme_stylebox_override("normal", UIStyle.box(Color("#a8281e") if amount > 0 else Color("#2a5aa8"), Color.BLACK, 1, 1))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var ts := float(GameData.tile_size)
	var anchor := Vector2((tile.x + 0.5) * ts, (tile.y + 1) * ts)
	bubbles[k] = {"label": box, "target": target if target is Node2D else null, "anchor": anchor, "age": 0.0, "amount": amount}
	_place(bubbles[k])


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


func label_on(target) -> Label:
	return bubbles[_key(target)]["label"] if bubbles.has(_key(target)) else null


func _place(b: Dictionary) -> void:
	var t = b["target"]
	if t != null and is_instance_valid(t):
		b["anchor"] = t.position
	var off: Array = cfg().get("offset", [-4, -20])
	(b["label"] as Label).position = (b["anchor"] + Vector2(float(off[0]), float(off[1]))).round()


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
