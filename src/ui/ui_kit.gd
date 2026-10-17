class_name UIKit
extends RefCounted
## Small helpers for building dense pixel-style panels in code.


static func label(text: String, size: int = 9, color: Color = UIStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w: int = 0, h: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(min_w, h)
	b.pressed.connect(cb)
	return b


static func icon(item_id: String) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = GameData.icon(item_id)
	ic.custom_minimum_size = Vector2(16, 16)
	ic.stretch_mode = TextureRect.STRETCH_KEEP
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


static func scroll(h: int) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size = Vector2(0, h)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


static func tabs(names: Array, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for n in names:
		var b := Button.new()
		b.text = n[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 9)
		b.custom_minimum_size = Vector2(0, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = n[0]
		b.pressed.connect(func():
			for c in row.get_children():
				c.button_pressed = c == b
			cb.call(key))
		row.add_child(b)
	(row.get_child(0) as Button).button_pressed = true
	return row


static func pct(f: float) -> String:
	return "%+.1f%%" % (f * 100.0)
