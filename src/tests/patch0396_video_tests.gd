class_name Patch0396VideoTests
extends RefCounted
## 0.3.9.6 title video: a looping, muted, cover-fitted VideoStreamPlayer over
## the static title art, which stays as poster and fallback.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func _host(main) -> MainMenu:
	var mm := MainMenu.new()
	mm.set_meta("test_host", true)
	mm.size = Vector2(360, 780)
	main.add_child(mm)
	MainMenu.add_backdrop(mm)
	return mm


static func run(main, _world, _p) -> void:
	check(ResourceLoader.exists(MainMenu.TITLE_VIDEO) and FileAccess.get_file_as_bytes(MainMenu.TITLE_VIDEO).size() > 1000000,
		"title video: res://assets/ui/title_loop.ogv is in the project")
	check(ClassDB.class_exists("VideoStreamTheora"), "title video: the engine has Theora support")
	var mm := _host(main)
	mm._start_title_video()
	var v: VideoStreamPlayer = mm.video
	var still: Node = mm.get_node_or_null("TitleBg")
	check(v != null and v.loop and v.autoplay and v.expand and v.volume_db <= -60.0 and v.stream != null,
		"title video: the menu has a VideoStreamPlayer with loop, autoplay, expand, muted")
	check(still != null and mm._video_box != null and mm._video_box.get_index() == still.get_index() + 1,
		"title video: drawn over the static title art (poster / fallback), under the menu")
	if v != null:
		mm._video_box.size = Vector2(400, 900)   # narrower than 9:16 -> cover by height, crop the sides
		mm._fit_video()
		var covers := v.size.x >= 400.0 - 0.5 and v.size.y >= 900.0 - 0.5 and absf(v.size.x / v.size.y - 540.0 / 960.0) < 0.01
		check(covers and absf(v.position.x + v.size.x * 0.5 - 200.0) < 1.0, "title video: cover-fit, aspect kept, centred (%s at %s)" % [v.size, v.position])
	mm.stop_title_video()
	check(mm.video == null and mm._video_box == null and still != null and still.visible,
		"title video: stops and frees when leaving the menu; the still stays")
	mm.queue_free()
	# fallback: a missing / unreadable stream keeps the static art
	var mm2 := _host(main)
	mm2._start_title_video("res://assets/ui/missing_title_video.ogv")
	check(mm2.video == null and mm2.video_state == "fallback" and mm2.get_node_or_null("TitleBg") != null,
		"title video: no stream -> fallback to the static title art (%s)" % mm2.video_state)
	mm2.queue_free()
