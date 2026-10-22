class_name MusicTests
extends RefCounted
## 0.3.4 music: tracks load and loop, combat is full volume at once, leaving
## combat fades out over FADE_SEC then the area track plays, towns / wilds /
## title pick the right track.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run() -> void:
	print("  -- 0.3.4 music")
	var ok := true
	for id in Music.IDS:
		var s = Music._tracks.get(id)
		ok = ok and s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop
	check(ok, "%d music tracks load from assets/music and loop" % Music.IDS.size())
	var full := Music._db()
	Music.set_title()
	check(Music.current == "title", "main menu: title theme")
	Music.set_area("")
	check(Music.current == "ambient", "the wilds: ambient")
	Music.set_area("fenhollow")
	check(Music.fading and Music.current == "ambient", "0.3.5 entering Fenhollow fades the ambient track out first")
	var ta := 0.0
	while Music.fading and ta < 5.0:
		Music.step(1.0 / 60.0)
		ta += 1.0 / 60.0
	check(absf(ta - Music.FADE_SEC) <= 2.0 / 60.0, "0.3.5 area fade takes %.2f s (want %.1f)" % [ta, Music.FADE_SEC])
	check(Music.current == "fenhollow", "inside Fenhollow: the Fenhollow theme")
	Music.set_combat(true)
	check(Music.current == "combat" and is_equal_approx(Music.player.volume_db, full) and not Music.fading,
		"combat starts instantly at full volume (%.1f dB, same call, no fade-in)" % Music.player.volume_db)
	Music.set_combat(false)
	var t := 0.0
	var mid_db := 0.0
	while Music.current == "combat" and t < 5.0:
		Music.step(1.0 / 60.0)
		t += 1.0 / 60.0
		if absf(t - Music.FADE_SEC / 2.0) < 0.009:
			mid_db = Music.player.volume_db
	check(absf(t - Music.FADE_SEC) <= 2.0 / 60.0 and Music.current == "fenhollow",
		"leaving combat fades out in %.2f s (want %.1f) then the area track plays (%s)" % [t, Music.FADE_SEC, Music.current])
	check(mid_db < full - 3.0 and mid_db > -60.0, "half way through the fade the combat track is quieter (%.1f dB vs %.1f)" % [mid_db, full])
	Music.set_combat(true)
	Music.set_combat(false)
	Music.step(0.5)
	Music.set_combat(true)
	Music.step(1.0 / 60.0)
	check(Music.current == "combat" and is_equal_approx(Music.player.volume_db, full), "back into a fight mid-fade: full volume at once")
	Music.set_combat(false)
	Music.step(2.0)
	Music.set_area("")
	check(Music.fading and Music.current == "fenhollow", "0.3.5 leaving town fades the town theme out")
	Music.step(2.0)
	check(Music.current == "ambient", "leaving town: ambient")
	# 0.3.8 Highfen's own theme (Dropbox "Capital city music 1"), same fades, combat wins
	Music.set_area("highfen")
	check(Music.fading and Music.current == "ambient", "0.3.8 entering Highfen fades the ambient track out first")
	Music.step(2.0)
	check(Music.current == "highfen" and ResourceLoader.exists("res://assets/music/highfen.ogg"), "inside Highfen: the capital theme (highfen.ogg)")
	Music.set_combat(true)
	check(Music.current == "combat", "combat overrides the Highfen theme")
	Music.set_combat(false)
	Music.step(2.0)
	check(Music.current == "highfen", "after the fight the Highfen theme returns")
	Music.set_area("")
	Music.step(4.0)
	# 0.3.10 Hudson's new tracks: new slots, rotation, proximity areas
	var slots_ok := true
	for id in ["scorch", "guild", "ruins", "goblin"]:
		slots_ok = slots_ok and Music._tracks.get(id) is AudioStreamOggVorbis
	check(slots_ok, "0.3.10 scorch, guild, ruins and goblin music slots load")
	var a: AudioStream = Music.next_stream("ambient")
	var b: AudioStream = Music.next_stream("ambient")
	var c: AudioStream = Music.next_stream("ambient")
	check(Music.variant_count("ambient") == 2 and a != b and a == c and Music.next_stream("combat") == Music._tracks["combat"],
		"0.3.10 a slot with several tracks rotates (ambient day 1 / day 3); single-track slots repeat")
	var main = (Engine.get_main_loop() as SceneTree).current_scene
	check(main != null and main.has_method("music_area"), "0.3.10 main has music_area")
	if main and main.has_method("music_area"):
		var gob := Vector2i.ZERO
		for camp in GameData.camps:
			if str(camp["enemy"]) == "goblin":
				gob = Vector2i(int(camp["at"][0]), int(camp["at"][1]))
				break
		check(main.music_area(Vector2i(300, -300)) == "scorch" and main.music_area(gob) == "goblin"
			and main.music_area(main.world.gen.town_center("highfen")) == "highfen",
			"0.3.10 music areas: the Scorch, near a goblin camp, towns")
