class_name MainMenu
extends Control
## 0.3.2 main menu: the app's first screen. New Game (slot + optional name,
## confirms before overwriting), Continue (most recent slot), Load Game (3
## slots: name, total / combat level, play time, last saved), Settings (stub),
## Quit. Android back closes a sub-page, then asks before quitting.
## Placeholder art: ui/menu_bg in data/sprites.json (swap the PNG to restyle).
## Tool/test launches (--selftest, --soak, --qa, --screenshot, --fresh,
## --save-path) skip the menu and go straight to the game scene.

const GAME_SCENE := "res://scenes/main.tscn"
const TOOL_ARGS := ["selftest", "screenshot", "qa", "soak", "fresh", "save-path"]

var args: Dictionary = {}
var pages: Dictionary = {}
var page := ""
var message: Label
var _quit_armed := false
var _new_slot := 1
var name_edit: LineEdit
var confirm_label: Label
var slot_box: VBoxContainer
var slot_mode := "load"     # "load" | "new"
var buttons: Dictionary = {}  # name -> Button (QA)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		args[s.substr(0, i) if i >= 0 else s] = s.substr(i + 1) if i >= 0 else true
	for k in TOOL_ARGS:
		if args.has(k):
			get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
			return
	get_tree().quit_on_go_back = false
	Tick.running = false
	_apply_pixel_scale()
	get_tree().root.size_changed.connect(_apply_pixel_scale)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.make_theme()
	add_backdrop(self)
	_build()
	_show("main")
	var pend := SaveSystem.boot_pending()
	if not pend.is_empty():
		_recovery(pend)
	elif SaveSystem.last_error != "":
		_say(SaveSystem.last_error, true)
		SaveSystem.last_error = ""
	SaveSystem.boot_log("BOOT menu shown at %d ms" % Time.get_ticks_msec())
	if args.has("qa-boot"):
		await get_tree().process_frame
		await get_tree().process_frame
		_print_layout()


# ------------------------------------------------------------ shared art --
static func add_backdrop(host: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b2418")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	var tex := GameData.texture("ui", "menu_bg")
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(tr)


static func title_label(text: String, size: int) -> Label:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", size)
	t.add_theme_color_override("font_color", UIStyle.ACCENT)
	t.add_theme_color_override("font_outline_color", Color("#2a1a08"))
	t.add_theme_constant_override("outline_size", 6)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_x", 2)
	t.add_theme_constant_override("shadow_offset_y", 2)
	return t


# ----------------------------------------------------------------- build --
func _build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 70)
	col.add_child(top)
	col.add_child(title_label("Ashfen", 40))
	var ver := Label.new()
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	ver.add_theme_constant_override("outline_size", 3)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	col.add_child(ver)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(center)
	var host := PanelContainer.new()
	host.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.BG_ALPHA, UIStyle.BORDER, 2, 8))
	host.custom_minimum_size = Vector2(250, 0)
	center.add_child(host)
	var stack := VBoxContainer.new()
	host.add_child(stack)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(230, 0)
	message.add_theme_font_size_override("font_size", 9)
	message.visible = false
	stack.add_child(message)
	# main page
	var m := VBoxContainer.new()
	m.add_theme_constant_override("separation", 6)
	stack.add_child(m)
	pages["main"] = m
	if _latest_slot() > 0:
		m.add_child(_btn("Continue", func(): _start("continue", _latest_slot())))
	m.add_child(_btn("New Game", func(): _open_slots("new")))
	m.add_child(_btn("Load Game", func(): _open_slots("load")))
	m.add_child(_btn("Settings", func(): _show("settings")))
	m.add_child(_btn("Quit", func(): get_tree().quit()))
	# slots page (load / new)
	var sp := VBoxContainer.new()
	sp.add_theme_constant_override("separation", 6)
	stack.add_child(sp)
	pages["slots"] = sp
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 6)
	sp.add_child(slot_box)
	sp.add_child(_btn("Back", func(): _show("main"), "SlotsBack"))
	# new game: name + confirm
	var np := VBoxContainer.new()
	np.add_theme_constant_override("separation", 6)
	stack.add_child(np)
	pages["new"] = np
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.custom_minimum_size = Vector2(230, 0)
	np.add_child(confirm_label)
	var nl := Label.new()
	nl.text = "Name your character (optional):"
	nl.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	np.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Adventurer"
	name_edit.max_length = 16
	name_edit.name = "NameEdit"
	np.add_child(name_edit)
	np.add_child(_btn("Start", func(): _start("new", _new_slot, name_edit.text), "StartNew"))
	np.add_child(_btn("Back", func(): _open_slots("new"), "NewBack"))
	# settings stub
	var st := VBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	stack.add_child(st)
	pages["settings"] = st
	var sl := Label.new()
	sl.text = "Settings\n\nSound, controls and display options\nare coming in a later version."
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(sl)
	st.add_child(_btn("Back", func(): _show("main"), "SettingsBack"))


func _btn(text: String, cb: Callable, key: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	var k := key if key != "" else text.replace(" ", "")
	b.name = k
	buttons[k] = b
	return b


func _show(p: String) -> void:
	page = p
	_quit_armed = false
	for k in pages.keys():
		pages[k].visible = k == p
	if args.has("qa-boot") and is_inside_tree():
		_print_layout_later()


func _say(text: String, warn: bool = false) -> void:
	message.text = text
	message.add_theme_color_override("font_color", Color("#ff9a7a") if warn else UIStyle.TEXT)
	message.visible = text != ""


# ----------------------------------------------------------------- slots --
func _latest_slot() -> int:
	var best := 0
	var best_t := -1
	for n in range(1, SaveSystem.SLOTS + 1):
		var info := SaveSystem.slot_info(n)
		if bool(info.get("exists", false)) and not info.has("error") and int(info.get("saved_unix", 0)) > best_t:
			best_t = int(info.get("saved_unix", 0))
			best = n
	return best


func _open_slots(mode: String) -> void:
	slot_mode = mode
	for c in slot_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "Load Game" if mode == "load" else "New Game: choose a slot"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", UIStyle.ACCENT)
	slot_box.add_child(head)
	for n in range(1, SaveSystem.SLOTS + 1):
		var info := SaveSystem.slot_info(n)
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 9)
		b.text = slot_text(info)
		b.name = "Slot%d" % n
		buttons["Slot%d" % n] = b
		if mode == "load":
			b.disabled = not bool(info.get("exists", false)) or info.has("error")
			b.pressed.connect(func(): _start("continue", n))
		else:
			b.pressed.connect(func(): _pick_new_slot(n, info))
		slot_box.add_child(b)
	_show("slots")


static func slot_text(info: Dictionary) -> String:
	var n := int(info.get("slot", 0))
	if not bool(info.get("exists", false)):
		return "Slot %d - empty" % n
	if info.has("error"):
		return "Slot %d - %s save" % [n, str(info["error"])]
	var secs := int(info.get("play_seconds", 0))
	var played := "%dh %02dm" % [secs / 3600, (secs / 60) % 60] if secs > 0 else "-"
	return "Slot %d - %s\nTotal %d  Combat %d  Played %s\nSaved %s" % [n, str(info.get("name", "Adventurer")), int(info.get("total", 0)),
		int(info.get("combat", 0)), played, when_text(int(info.get("saved_unix", 0)))]


static func when_text(unix: int) -> String:
	if unix <= 0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


func _pick_new_slot(n: int, info: Dictionary) -> void:
	_new_slot = n
	if bool(info.get("exists", false)):
		confirm_label.text = "Slot %d already holds %s. Starting a new game here will ERASE it." % [n, str(info.get("name", "a save"))]
		confirm_label.add_theme_color_override("font_color", Color("#ff9a7a"))
	else:
		confirm_label.text = "New game in slot %d." % n
		confirm_label.add_theme_color_override("font_color", UIStyle.TEXT)
	_show("new")


func _start(mode: String, slot: int, char_name: String = "") -> void:
	if mode == "new":
		SaveSystem.delete_slot(slot)
	SaveSystem.current_slot = slot
	SaveSystem.launch = {"mode": mode, "slot": slot, "name": char_name}
	SaveSystem.boot_log("BOOT menu -> %s slot %d" % [mode, slot])
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


## The previous start of a slot never reached gameplay (killed, hung or crashed
## while loading): offer to try again or set that save aside.
func _recovery(pend: Dictionary) -> void:
	var n := int(pend.get("slot", 1))
	SaveSystem.boot_done()
	_say("The last start of slot %d did not finish loading. You can try Continue again, or set that save aside (it is kept as a backup file) from Load Game." % n, true)
	var cb := func(): _set_aside(n)
	pages["main"].add_child(_btn("Set slot %d save aside" % n, cb, "SetAside"))


func _set_aside(n: int) -> void:
	var keep := SaveSystem.current_slot
	SaveSystem.current_slot = n
	var bk := SaveSystem.quarantine("did not finish loading")
	SaveSystem.current_slot = keep
	_rebuild()
	_say("Slot %d was set aside as %s." % [n, bk.get_file()], false)


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	pages.clear()
	buttons.clear()
	add_backdrop(self)
	_build()
	_show("main")


# --------------------------------------------------------- android back --
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if page == "new":
			_open_slots("new")
		elif page != "main":
			_show("main")
		elif _quit_armed:
			get_tree().quit()
		else:
			_quit_armed = true
			_say("Press back again to quit.")


func _apply_pixel_scale() -> void:
	var win := Vector2(get_tree().root.size)
	if win.x <= 0 or win.y <= 0:
		return
	get_tree().root.content_scale_factor = maxi(1, floori(minf(win.x / 360.0, win.y / 640.0)))


func _print_layout_later() -> void:
	for i in 3:   # let wrapped labels settle the layout first
		await get_tree().process_frame
	_print_layout()


## QA: where each visible button is on screen (window pixels).
func _print_layout() -> void:
	var k := get_tree().root.content_scale_factor
	for key in buttons.keys():
		var b: Button = buttons[key]
		if is_instance_valid(b) and b.is_visible_in_tree():
			var r := b.get_global_rect()
			SaveSystem.boot_log("MENU button %s %d %d %d %d" % [key, int(r.position.x * k), int(r.position.y * k), int(r.size.x * k), int(r.size.y * k)])
	SaveSystem.boot_log("MENU page %s" % page)
