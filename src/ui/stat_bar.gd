class_name StatBar
extends Control
## 0.2.4: compact labelled bar for the HUD column beside the minimap
## ("HP 11/20", "Prayer 10/10", "Energy 87/100"). `highlight` draws a bright
## frame (sprint on). Emits `tapped` when touched (the Energy bar toggles sprint).

signal tapped

var label := ""
var cur := 0.0
var max_v := 1.0
var fill := Color("#c83a3a")
var fill_tex := ""   # restyle batch 07: kit/bar_fill_<hp|prayer|energy>
var highlight := false
var highlight_color := Color("#f0e060")
var prefix := ""
const FILL_BANDS := {
	"hp": [Color8(200, 86, 42), Color8(122, 42, 42)],
	"prayer": [Color8(122, 138, 152), Color8(67, 80, 96)],
	"energy": [Color8(138, 148, 96), Color8(108, 122, 72)],
}


func _init() -> void:
	custom_minimum_size = Vector2(84, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(c: float, m: float) -> void:
	if is_equal_approx(c, cur) and is_equal_approx(m, max_v):
		return
	cur = c
	max_v = m
	queue_redraw()


func set_highlight(on: bool) -> void:
	if on != highlight:
		highlight = on
		queue_redraw()


func text() -> String:
	return "%s%s %d/%d" % [prefix, label, int(ceil(cur)), int(round(max_v))]


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UIStyle.tex("bar_frame", 3), r)
	var inner := r.grow(-3)
	var w := inner.size.x * clampf(cur / maxf(1.0, max_v), 0.0, 1.0)
	# batch 07 kit fill drawn as colour bands (texture draw rendered white on device)
	var bands: Array = FILL_BANDS.get(fill_tex, [fill, fill.darkened(0.4)])
	var hh := inner.size.y
	draw_rect(Rect2(inner.position, Vector2(w, hh)), bands[1])
	draw_rect(Rect2(inner.position, Vector2(w, ceilf(hh * 0.5))), bands[0])
	if highlight:
		draw_rect(r.grow(-0.5), UIStyle.EMBER, false, 2.0)
	var font := get_theme_default_font()
	var fs := 10
	var t := text()
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(maxf(3.0, (size.x - tw) / 2.0), (size.y + fs) / 2.0 - 1)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color.BLACK)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## 0.2.5 tap fix. On Android each touch arrives TWICE: as InputEventScreenTouch
## and, because project setting pointing/emulate_mouse_from_touch is on, as an
## emulated InputEventMouseButton. 0.2.4 acted on both presses, so one tap
## toggled sprint on and straight back off. Now exactly one source counts:
## the (real or emulated) left-mouse PRESS when emulation is on, else the
## touch press. Everything else (releases, the other source) is consumed so
## it never reaches the world tap handler, and a debounce drops repeats.
var touch_emulated: bool = ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)
var clock_skew_ms := 0          # tests advance time between taps
var _last_tap_ms := -100000
var taps := 0                   # accepted taps (tests)


func _now_ms() -> int:
	return Time.get_ticks_msec() + clock_skew_ms


func _gui_input(ev: InputEvent) -> void:
	var tap := false
	if ev is InputEventMouseButton:
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		tap = ev.pressed
		accept_event()
	elif ev is InputEventScreenTouch:
		tap = ev.pressed and not touch_emulated
		accept_event()
	else:
		return
	if not tap:
		return
	var now := _now_ms()
	if now - _last_tap_ms < int(GameData.fx.get("tap", {}).get("debounce_ms", 250)):
		return
	_last_tap_ms = now
	taps += 1
	tapped.emit()
