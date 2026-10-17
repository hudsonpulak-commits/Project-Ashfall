class_name ItemSlot
extends Button
## One inventory/bank cell: 16px icon drawn at an integer 2x scale + quantity.

const SIZE := 36

var icon_rect: TextureRect
var qty_label: Label
var dur_bar: ColorRect
var item_id: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("normal", UIStyle.box(UIStyle.SLOT, UIStyle.BORDER, 1, 0))
	add_theme_stylebox_override("hover", UIStyle.box(UIStyle.SLOT, UIStyle.BORDER_HI, 1, 0))
	add_theme_stylebox_override("pressed", UIStyle.box(Color("#3a3020"), UIStyle.BORDER_HI, 1, 0))
	icon_rect = TextureRect.new()
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.size = Vector2(32, 32)
	icon_rect.position = Vector2(2, 2)
	icon_rect.scale = Vector2.ONE
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_rect)
	qty_label = Label.new()
	qty_label.add_theme_font_size_override("font_size", 9)
	qty_label.add_theme_color_override("font_color", Color("#f8e080"))
	qty_label.add_theme_color_override("font_outline_color", Color.BLACK)
	qty_label.add_theme_constant_override("outline_size", 3)
	qty_label.position = Vector2(2, -1)
	qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(qty_label)
	dur_bar = ColorRect.new()
	dur_bar.color = Color("#6ac04a")
	dur_bar.position = Vector2(3, SIZE - 4)
	dur_bar.size = Vector2(SIZE - 6, 2)
	dur_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dur_bar)


func set_item(slot) -> void:
	if slot == null:
		item_id = ""
		icon_rect.texture = null
		qty_label.text = ""
		dur_bar.visible = false
		tooltip_text = ""
		return
	item_id = slot["id"]
	var tex := GameData.icon(item_id)
	icon_rect.texture = tex
	# integer upscale of 16px art: 16 -> 32
	icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var q := int(slot.get("qty", 1))
	qty_label.text = _fmt(q) if (q > 1 or GameData.is_stackable(item_id)) else ""
	tooltip_text = GameData.item_name(item_id)
	if slot.has("dur"):
		var maxd := float(GameData.item(item_id).get("tool", {}).get("durability", 1))
		var f := clampf(float(slot["dur"]) / maxd, 0.0, 1.0)
		dur_bar.visible = true
		dur_bar.size.x = floorf((SIZE - 6) * f)
		dur_bar.color = Color("#6ac04a") if f > 0.3 else Color("#e05a3a")
	else:
		dur_bar.visible = false


static func _fmt(n: int) -> String:
	if n >= 10_000_000:
		return "%dM" % (n / 1_000_000)
	if n >= 100_000:
		return "%dK" % (n / 1000)
	return str(n)
