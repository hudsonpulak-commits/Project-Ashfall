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
## 0.3.9.6 looping title video (Ogg Theora, 540x960, 14.04 s seamless loop, no
## audio) over the static title art, which stays as poster / loading / fallback.
const TITLE_VIDEO := "res://assets/ui/title_loop.ogv"
const VIDEO_SIZE := Vector2(540, 960)
const VIDEO_TIMEOUT_MS := 4000     # no first frame by then -> keep the still
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
var video: VideoStreamPlayer = null   # 0.3.9.6 title video (null = static art)
var video_state := "none"             # none | loading | playing | fallback (tests / QA)
var _video_box: Control = null
var _video_t0 := 0


func _ready() -> void:
	if has_meta("test_host"):
		return   # 0.3.9.6 unit tests drive the title video helpers directly
	Music.set_title()     # 0.3.4: title theme on the menu (also after "exit to menu")
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
	_start_title_video.call_deferred()   # the still shows first; the video takes over once decoding
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
static func has_title_art() -> bool:
	var td := GameData.sprite_def("ui", "title_bg")
	return not td.is_empty() and ResourceLoader.exists(str(td.get("path", "")))


static func add_backdrop(host: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b2418")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	# 0.3.9 data-driven title art slot: ui/title_bg (assets/ui/title_bg.png) when the
	# file exists, else the placeholder ui/menu_bg. Cover-scaled, aspect kept.
	var tex: Texture2D = null
	var td := GameData.sprite_def("ui", "title_bg")
	var use_title := not td.is_empty() and ResourceLoader.exists(str(td.get("path", "")))
	tex = GameData.texture("ui", "title_bg") if use_title else GameData.texture("ui", "menu_bg")
	if tex:
		var tr := TextureRect.new()
		tr.name = "TitleBg" if use_title else "MenuBg"
		tr.texture = tex
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if use_title and str(td.get("filter", "linear")) == "linear" else CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(tr)


# ------------------------------------------------------- 0.3.9.6 video --
## Cover-fits a looping, muted VideoStreamPlayer behind the menu (above the
## still). The still (TitleBg) stays underneath as the poster while the stream
## opens and as the fallback when the file / Theora support / stream is missing
## or no frame arrives within VIDEO_TIMEOUT_MS.
func _start_title_video(path: String = TITLE_VIDEO) -> void:
	if not is_inside_tree() or not has_title_art():
		return
	video_state = "loading"
	var stream: VideoStream = null
	if ClassDB.class_exists("VideoStreamTheora") and ResourceLoader.exists(path):
		stream = load(path) as VideoStream
	if stream == null:
		_video_fallback("no stream: " + path)
		return
	_video_box = Control.new()
	_video_box.name = "TitleVideoBox"
	_video_box.clip_contents = true
	_video_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_video_box)
	move_child(_video_box, get_node("TitleBg").get_index() + 1)   # over the still, under the menu
	video = VideoStreamPlayer.new()
	video.name = "TitleVideo"
	video.stream = stream
	video.loop = true
	video.autoplay = true
	video.expand = true
	video.volume_db = -80.0          # the clip has no audio; muted anyway
	video.bus = &"Master"
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.modulate.a = 0.0           # hidden until the first frame is decoded
	_video_box.add_child(video)
	_video_box.resized.connect(_fit_video)
	_fit_video()
	_video_t0 = Time.get_ticks_msec()
	SaveSystem.boot_log("BOOT title video started at %d ms" % _video_t0)


func _fit_video() -> void:
	if video == null or _video_box == null:
		return
	var box := _video_box.size
	var k := maxf(box.x / VIDEO_SIZE.x, box.y / VIDEO_SIZE.y)   # cover, aspect kept
	video.size = VIDEO_SIZE * k
	video.position = (box - video.size) * 0.5


func _process(_dt: float) -> void:
	if video_state != "loading" or video == null:
		return
	var tex := video.get_video_texture()
	if video.is_playing() and tex != null and tex.get_width() > 0:
		video.modulate.a = 1.0
		video_state = "playing"
		SaveSystem.boot_log("BOOT title video first frame at %d ms" % Time.get_ticks_msec())
	elif Time.get_ticks_msec() - _video_t0 > VIDEO_TIMEOUT_MS:
		_video_fallback("no frame after %d ms" % VIDEO_TIMEOUT_MS)


func _video_fallback(why: String) -> void:
	stop_title_video()
	video_state = "fallback"
	SaveSystem.boot_log("BOOT title video fallback (%s): static title art" % why)


## Stops and frees the video (leaving the menu, fallback). Idempotent.
func stop_title_video() -> void:
	if video != null and is_instance_valid(video):
		video.stop()
		video.queue_free()
	video = null
	if _video_box != null and is_instance_valid(_video_box):
		_video_box.queue_free()
	_video_box = null
	if video_state == "playing" or video_state == "loading":
		video_state = "none"


func _exit_tree() -> void:
	stop_title_video()


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
	# 0.3.9 the title art carries the AshFall logo: hide our label, sit the menu
	# low over the dark foreground so the logo and the dragon stay visible
	var art := has_title_art()
	var tl := title_label("AshFall", 40)
	tl.visible = not art
	col.add_child(tl)
	var ver := Label.new()
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "")
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	ver.add_theme_constant_override("outline_size", 3)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	col.add_child(ver)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	if art:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		top.custom_minimum_size = Vector2(0, 0)
		ver.visible = false
	col.add_child(gap)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_SHRINK_END if art else Control.SIZE_EXPAND_FILL
	col.add_child(center)
	if art:
		ver.visible = true
		col.move_child(ver, col.get_child_count() - 1)   # version under the menu
		var foot := Control.new()
		foot.custom_minimum_size = Vector2(0, 6)
		col.add_child(foot)
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
	# 0.3.9.6 two columns: the menu stays on the dark river at the bottom of the
	# title video, clear of the bridge and the city
	var grid := GridContainer.new()
	grid.name = "MainGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	m.add_child(grid)
	for b in [_btn("New Game", func(): _open_slots("new")), _btn("Load Game", func(): _open_slots("load")),
			_btn("Settings", func(): _show("settings")), _btn("Quit", func(): get_tree().quit())]:
		b.custom_minimum_size = Vector2(107, 30)
		grid.add_child(b)
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
	sl.text = "Settings\n\nMusic volume"
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(sl)
	var vol := HSlider.new()       # 0.3.4 music volume (saved in user://settings.cfg)
	vol.name = "MusicVolume"
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = Music.volume
	vol.custom_minimum_size = Vector2(200, 28)
	vol.value_changed.connect(func(v): Music.set_volume(v))
	st.add_child(vol)
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
	stop_title_video()   # 0.3.9.6 no title video during loading / gameplay
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
