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
	check(ok, "6 music tracks load from assets/music and loop")
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
