class_name LoadingScreen
extends CanvasLayer
## 0.3.2 loading screen: shown on the first frame of the game scene while the
## save is read/migrated, the world is built and the offline catch-up runs.
## Art: ui/menu_bg (data/sprites.json), same as the main menu.

var bar: ProgressBar
var label: Label
var _root: Control


func _init() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIStyle.make_theme()
	add_child(_root)
	MainMenu.add_backdrop(_root)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(240, 0)
	v.position -= Vector2(120, 10)
	v.add_theme_constant_override("separation", 8)
	_root.add_child(v)
	var t := MainMenu.title_label("Ashfen", 28)
	v.add_child(t)
	label = Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UIStyle.TEXT)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	v.add_child(label)
	bar = ProgressBar.new()
	bar.name = "LoadingBar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(240, 10)
	var bg := UIStyle.box(UIStyle.SLOT, UIStyle.BORDER, 1, 0)
	var fg := UIStyle.box(UIStyle.ACCENT, UIStyle.BORDER_HI, 1, 0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)


func set_progress(f: float, text: String) -> void:
	bar.value = clampf(f, 0.0, 1.0)
	label.text = text
	SaveSystem.boot_log("BOOT progress %d%% %s" % [int(f * 100), text])
