class_name MapPrefs
extends RefCounted
## 0.3.7.1 map display preference: show markers (player pins + quest ?, !,
## objective areas) on the minimap and world map. user://settings.cfg [map].
const SETTINGS := "user://settings.cfg"
static var _loaded := false
static var _show := true


static func markers_shown() -> bool:
	if not _loaded:
		var cf := ConfigFile.new()
		if cf.load(SETTINGS) == OK:
			_show = bool(cf.get_value("map", "markers", true))
		_loaded = true
	return _show


static func set_markers_shown(v: bool) -> void:
	_show = v
	_loaded = true
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("map", "markers", v)
	cf.save(SETTINGS)


## Tests: forget the cached value (re-read from disk next time).
static func reload() -> void:
	_loaded = false
