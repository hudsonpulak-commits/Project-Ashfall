extends Node
## 0.3.4 music (autoload "Music"). Based on Grok's MusicManager, reworked:
##  - combat cuts in INSTANTLY at full volume (no fade-in);
##  - leaving combat fades the combat track out over FADE_SEC, then the area
##    track (town theme inside a town, ambient elsewhere) starts;
##  - title on the main menu; every track loops; music volume setting
##    (user://settings.cfg); pauses while the Android app is in the background.
## Tracks: res://assets/music/<id>.ogg. Ogg Vorbis, not MP3: the size-optimised
## export template (tools/engine/ashfen_custom.py) has no MP3 module.

const FADE_SEC := 1.5
const DIR := "res://assets/music/"
const IDS := ["title", "ambient", "ambient_night", "combat", "fenhollow", "cinderholt", "saltmere", "highfen",
	"scorch", "guild", "ruins", "goblin"]
## 0.3.10 a slot can hold several tracks: <id>.ogg, <id>_2.ogg, <id>_3.ogg ...
## Each time the slot (re)starts it plays the next one in turn (rotation).
const MAX_VARIANTS := 6
const SETTINGS := "user://settings.cfg"

var player: AudioStreamPlayer
var current := ""            # track playing ("" = none)
var area := "ambient"        # where we'd be without combat
var in_combat := false
var fading := false
var fade_left := 0.0
var volume := 0.8            # 0..1, the music volume setting
var _tracks: Dictionary = {}
var _variants: Dictionary = {}   # 0.3.10 id -> [AudioStream...]
var _rot: Dictionary = {}        # 0.3.10 id -> next variant index


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	add_child(player)
	for id in IDS:
		var path: String = DIR + id + ".ogg"
		var s = load(path) if ResourceLoader.exists(path) else null
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_tracks[id] = s
		var vs: Array = [s] if s != null else []
		for k in range(2, MAX_VARIANTS + 1):
			var vp: String = DIR + "%s_%d.ogg" % [id, k]
			if not ResourceLoader.exists(vp):
				break
			var v = load(vp)
			if v is AudioStreamOggVorbis:
				(v as AudioStreamOggVorbis).loop = true
				vs.append(v)
		_variants[id] = vs
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		volume = clampf(float(cf.get_value("audio", "music", volume)), 0.0, 1.0)


func _db() -> float:
	return linear_to_db(maxf(0.0001, volume))


func _play(id: String) -> void:
	fading = false
	if _tracks.get(id) == null:
		player.stop()
		current = ""
		return
	if id != current or not player.playing:
		player.stop()
		player.stream = next_stream(id)
		player.play()
	current = id
	player.volume_db = _db()


## 0.3.10 rotation: the slot's next track (the only one when it has one).
func next_stream(id: String) -> AudioStream:
	var vs: Array = _variants.get(id, [])
	if vs.size() <= 1:
		return _tracks.get(id)
	var i := int(_rot.get(id, 0)) % vs.size()
	_rot[id] = i + 1
	return vs[i]


func variant_count(id: String) -> int:
	return (_variants.get(id, []) as Array).size()


## Main menu / back to the menu: the title theme, combat forgotten.
func set_title() -> void:
	in_combat = false
	area = "ambient"
	_play("title")


## Town id ("" = the wilds). 0.3.5: the old area track fades out over
## FADE_SEC, then the new one starts (from silence/title: at once).
## 0.3.6 night = true: the wilds play ambient_night (faded like any change).
func set_area(town_id: String, night := false) -> void:
	var wild := "ambient_night" if night and _tracks.get("ambient_night") != null else "ambient"
	var k := town_id.to_lower() if town_id != "" and _tracks.get(town_id.to_lower()) != null else wild
	if k == area and current == k:
		return
	area = k
	if in_combat or fading:
		return            # the running fade ends on the new area track
	if current == "" or current == "title" or not player.playing:
		_play(area)
	else:                 # 0.3.5 area change: fade the old track out first
		fading = true
		fade_left = FADE_SEC


## From the player's combat state every tick. true -> combat now, full volume.
func set_combat(active: bool) -> void:
	if active == in_combat:
		return
	in_combat = active
	if active:
		_play("combat")
	elif current == "combat":
		fading = true
		fade_left = FADE_SEC
	else:
		_play(area)


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	if not fading:
		player.volume_db = _db()
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("audio", "music", volume)
	cf.save(SETTINGS)


func _process(delta: float) -> void:
	var _pt0 := Time.get_ticks_usec()
	_process_timed(delta)
	World.pmark("music", _pt0)


func _process_timed(delta: float) -> void:
	step(delta)


## Fade driver (separate so tests can step it).
func step(delta: float) -> void:
	if not fading:
		return
	if in_combat:      # back into a fight mid-fade: snap to full
		fading = false
		player.volume_db = _db()
		return
	fade_left -= delta
	player.volume_db = linear_to_db(maxf(0.0001, volume * clampf(fade_left / FADE_SEC, 0.0, 1.0)))
	if fade_left <= 0.0:
		_play(area)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		player.stream_paused = false
