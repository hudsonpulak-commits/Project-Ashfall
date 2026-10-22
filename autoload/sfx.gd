extends Node
## 0.3.13 sound effects (autoload "Sfx"). Own "SFX" audio bus + its own volume
## setting (user://settings.cfg [audio] sfx), separate from Music: the music
## player and its fades are untouched. Files: res://assets/audio/sfx/<id>.ogg.
## Every hook is a no-op when its file is missing (so the NPC-hit hooks are
## safe until those sounds are delivered).

const DIR := "res://assets/audio/sfx/"
const BUS := "SFX"
const SETTINGS := "user://settings.cfg"
const VOICES := 6
## event -> file id. npc_hit_* are hooks for future files (no file yet).
const MAP := {
	"pickaxe_swing": "mining_tick",
	"ore_obtained": "mining_ting_rock",
	"axe_chop": "axe_solid",
	"player_damaged": "damage_hit",
	"anvil_strike": "anvil_ting_high",
	"furnace_smelting": "furnace_low",
	"npc_hit_humanoid": "npc_hit_humanoid",
	"npc_hit_creature": "npc_hit_creature",
}
const FURNACE_HOLD := 1.5   # s without a smelting tick before the loop stops

var volume := 0.8
var _streams: Dictionary = {}
var _voices: Array = []
var _next := 0
var _furnace: AudioStreamPlayer
var _furnace_left := 0.0
var last_event := ""          # for tests
var counts: Dictionary = {}   # event -> times fired (tests)


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for ev in MAP:
		var p: String = DIR + str(MAP[ev]) + ".ogg"
		_streams[ev] = load(p) if ResourceLoader.exists(p) else null
	for i in VOICES:
		var a := AudioStreamPlayer.new()
		a.bus = BUS
		add_child(a)
		_voices.append(a)
	_furnace = AudioStreamPlayer.new()
	_furnace.bus = BUS
	var fs = _streams.get("furnace_smelting")
	if fs is AudioStreamOggVorbis:
		fs = (fs as AudioStreamOggVorbis).duplicate()
		fs.loop = true
	_furnace.stream = fs
	add_child(_furnace)
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		volume = clampf(float(cf.get_value("audio", "sfx", volume)), 0.0, 1.0)
	_apply()


func _apply() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, volume)))


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("audio", "sfx", volume)
	cf.save(SETTINGS)


func has_sound(ev: String) -> bool:
	return _streams.get(ev) != null


## One-shot. Returns false (and does nothing) when the event has no file.
func play(ev: String) -> bool:
	var s = _streams.get(ev)
	if s == null:
		return false
	last_event = ev
	counts[ev] = int(counts.get(ev, 0)) + 1
	var a: AudioStreamPlayer = _voices[_next]
	_next = (_next + 1) % VOICES
	a.stream = s
	a.play()
	return true


## Called every tick the player is smelting; the loop stops by itself soon after.
func furnace_tick() -> void:
	if _furnace.stream == null:
		return
	counts["furnace_smelting"] = int(counts.get("furnace_smelting", 0)) + 1
	_furnace_left = FURNACE_HOLD
	if not _furnace.playing:
		_furnace.play()


func furnace_playing() -> bool:
	return _furnace.playing


## Future: an NPC/enemy got hit. humanoid -> npc_hit_humanoid, else npc_hit_creature.
func npc_hit(humanoid: bool) -> bool:
	return play("npc_hit_humanoid" if humanoid else "npc_hit_creature")


func _process(dt: float) -> void:
	if _furnace_left > 0.0:
		_furnace_left -= dt
		if _furnace_left <= 0.0:
			_furnace.stop()
