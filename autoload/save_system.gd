extends Node
## JSON save at user://ashfen_save.json, written atomically (tmp + rename) so a
## crash or the OS killing the app mid-write can't corrupt the save.
## See docs/GDD.md "Save format". Bump SAVE_VERSION and add a migrate step on
## any breaking change.

const SAVE_PATH := "user://ashfen_save.json"
const TMP_PATH := "user://ashfen_save.tmp"
const BACKUP_PATH := "user://ashfen_save.bak"
const SAVE_VERSION := 8      # 4 = map markers, 5 = 0.3.1 day/night cycle, 6 = 0.3.1 world layout (mines, Scorch, churches), 7 = 0.3.1 walled cities, 8 = 0.3.1 adventurers + Scorch PK

const SLOTS := 3                 # 0.3.2 save slots (slot 1 = the pre-0.3.2 file, so old saves just appear there)
const BOOT_MARK := "user://ashfen_boot.json"   # 0.3.2 boot watchdog: set while a slot loads, cleared in gameplay

var path_override: String = ""   # tests write elsewhere
var current_slot := 1            # 0.3.2: the slot the game loads from / saves to
## 0.3.2 launch request from the main menu to the game scene:
## {"mode": "new"|"continue", "slot": n, "name": "..."}; empty = legacy (load slot 1 or new).
var launch: Dictionary = {}
var last_error := ""             # 0.3.2: why the last load failed (shown by the main menu)


## 0.3.2 boot trace: printed, and with --qa-boot also appended (flushed) to
## user://qa_boot.log so the exported-build QA can follow along live.
func boot_log(line: String) -> void:
	print(line)
	if not "--qa-boot" in OS.get_cmdline_user_args():
		return
	var p := "user://qa_boot.log"
	var f := FileAccess.open(p, FileAccess.READ_WRITE) if FileAccess.file_exists(p) else FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()


func slot_path(n: int) -> String:
	return SAVE_PATH if n <= 1 else "user://ashfen_save_slot%d.json" % n


func _path() -> String:
	return path_override if path_override != "" else slot_path(current_slot)


func has_save() -> bool:
	return FileAccess.file_exists(_path())


func save_game(state: Dictionary) -> bool:
	state["version"] = SAVE_VERSION
	state["saved_unix"] = int(Time.get_unix_time_from_system())
	var tmp := _path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write %s (%s)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(state, "", false))
	f.close()
	var dir := DirAccess.open("user://")
	var abs_main := ProjectSettings.globalize_path(_path())
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(_path()):
		DirAccess.copy_absolute(abs_main, abs_main + ".bak")
	var err := DirAccess.rename_absolute(abs_tmp, abs_main)
	if err != OK:
		push_error("SaveSystem: rename failed %s" % err)
		return false
	return dir != null


func load_game() -> Dictionary:
	var r := load_checked()
	return r.get("data", {}) if bool(r.get("ok", false)) else {}


## 0.3.2 safety net: parse + migrate with validation. A file that is not JSON,
## does not migrate to SAVE_VERSION, or lacks the player/world blocks is moved
## aside (<save>.bad-<unix>.json) and reported, never loaded half-way.
## {"ok": bool, "data": Dictionary, "error": String, "backup": String}
func load_checked() -> Dictionary:
	last_error = ""
	var tried := false
	for p in [_path(), _path() + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		tried = true
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("SaveSystem: %s unreadable, trying backup" % p)
			continue
		var m = _migrate((data as Dictionary).duplicate(true))
		var why := validate(m)
		if why == "":
			return {"ok": true, "data": m, "error": "", "backup": ""}
		push_warning("SaveSystem: %s failed to migrate: %s" % [p, why])
		last_error = why
	if not tried:
		return {"ok": true, "data": {}, "error": "", "backup": ""}
	if last_error == "":
		last_error = "the save file could not be read"
	var bk := quarantine(last_error)
	return {"ok": false, "data": {}, "error": last_error, "backup": bk}


## Empty string = loadable; otherwise the reason.
static func validate(m) -> String:
	if typeof(m) != TYPE_DICTIONARY:
		return "migration did not return a save"
	if int(m.get("version", -1)) != SAVE_VERSION:
		return "migration stopped at version %s" % str(m.get("version", "?"))
	if typeof(m.get("player")) != TYPE_DICTIONARY or typeof(m.get("world", {})) != TYPE_DICTIONARY:
		return "player/world data missing"
	if typeof((m["player"] as Dictionary).get("tile", [0, 0])) != TYPE_ARRAY:
		return "player position missing"
	return ""


## Move the current slot's files aside (kept for support) so the slot is free.
func quarantine(reason: String) -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var dest := _path().trim_suffix(".json") + ".bad-%d.json" % stamp
	if FileAccess.file_exists(_path()):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(_path()), ProjectSettings.globalize_path(dest))
	for p in [_path(), _path() + ".bak", _path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var f := FileAccess.open(dest + ".txt", FileAccess.WRITE)
	if f:
		f.store_string("Ashfen %s could not load this save: %s\n" % [ProjectSettings.get_setting("application/config/version", ""), reason])
		f.close()
	push_warning("SaveSystem: bad save moved to %s (%s)" % [dest, reason])
	return dest


# ------------------------------------------------------- 0.3.2 slot info --
## What the Load screen shows for slot n (reads the file; no migration).
func slot_info(n: int) -> Dictionary:
	var p := slot_path(n)
	if not FileAccess.file_exists(p):
		p = p + ".bak"
		if not FileAccess.file_exists(p):
			return {"slot": n, "exists": false}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"slot": n, "exists": true, "error": "unreadable"}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return {"slot": n, "exists": true, "error": "damaged"}
	var pl: Dictionary = d.get("player", {}) if typeof(d.get("player")) == TYPE_DICTIONARY else {}
	var meta: Dictionary = d.get("meta", {}) if typeof(d.get("meta")) == TYPE_DICTIONARY else {}
	var sk := Skills.new()
	var xs = pl.get("skills", {})
	if typeof(xs) == TYPE_DICTIONARY:
		for k in xs.keys():
			sk.xp[k] = int(xs[k])
	if sk.xp.has("melee"):   # pre-0.2.4 saves
		sk.xp.erase("melee")
	return {"slot": n, "exists": true, "version": int(d.get("version", 0)),
		"name": str(meta.get("name", pl.get("char_name", "Adventurer"))),
		"total": int(meta.get("total", sk.total_level())), "combat": int(meta.get("combat", Combat.combat_level(sk))),
		"play_seconds": int(meta.get("play_seconds", 0)), "saved_unix": int(d.get("saved_unix", 0))}


func has_slot(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n)) or FileAccess.file_exists(slot_path(n) + ".bak")


func delete_slot(n: int) -> void:
	var keep := current_slot
	current_slot = n
	delete_save()
	current_slot = keep


# --------------------------------------------------- 0.3.2 boot watchdog --
## Set before a slot starts loading; cleared once gameplay frames render. If
## the app is killed / hangs / crashes while loading, the next start sees the
## mark and the menu offers recovery instead of hanging on the same save again.
func boot_begin(slot: int, mode: String) -> void:
	var f := FileAccess.open(BOOT_MARK, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"slot": slot, "mode": mode, "unix": int(Time.get_unix_time_from_system())}))
		f.close()


func boot_done() -> void:
	if FileAccess.file_exists(BOOT_MARK):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BOOT_MARK))


func boot_pending() -> Dictionary:
	if not FileAccess.file_exists(BOOT_MARK):
		return {}
	var f := FileAccess.open(BOOT_MARK, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {"slot": 1}


func delete_save() -> void:
	for p in [_path(), _path() + ".bak", _path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v < 2:
		data = migrate_bronze(data)
		data["version"] = 2
	if v < 3:
		data = migrate_combat_skills(data)
		data["version"] = 3
	if v < 4:
		data = migrate_map_markers(data)
		data["version"] = 4
	if v < 5:
		data = migrate_daynight(data)
		data["version"] = 5
	if v < 6:
		data = migrate_world_layout(data)
		data["version"] = 6
	if v < 7:
		data = migrate_walled_cities(data)
		data["version"] = 7
	if v < 8:
		data = migrate_adventurers_pk(data)
		data["version"] = 8
	if v > SAVE_VERSION:
		push_warning("SaveSystem: save from a newer build (v%d)" % v)
	return data


## v1 -> v2 (0.2.3): the copper metal tier became BRONZE. Every item / recipe
## id "copper_X" (except copper_ore and the copper_rock object) becomes
## "bronze_X" anywhere in the save: pack, bank vaults, equipment, ground
## items and death piles, AI stashes/gear/memos, market orders, references,
## collection boxes and shop stock (as values or dictionary keys).
static func migrate_bronze(data):
	var rx := RegEx.new()
	rx.compile("copper_(?!ore\\b|rock\\b)")
	return _ren(data, rx)


static func _ren(x, rx: RegEx):
	match typeof(x):
		TYPE_DICTIONARY:
			var out := {}
			for k in x.keys():
				out[_ren(k, rx)] = _ren(x[k], rx)
			return out
		TYPE_ARRAY:
			var arr := []
			for v in x:
				arr.append(_ren(v, rx))
			return arr
		TYPE_STRING:
			var s: String = x
			if s == "smelt_copper":
				return "smelt_bronze"
			return rx.sub(s, "bronze_", true) if s.contains("copper_") else s
	return x


## v2 -> v3 (0.2.4): Melee split into Attack, Strength and Defence. Every
## skill-XP dictionary (the player's and every AI agent's) copies its Melee XP
## into all three, so nobody loses access to gear they already wear. AI
## activities that named the Melee skill now name Attack.
static func migrate_combat_skills(data):
	match typeof(data):
		TYPE_DICTIONARY:
			var out := {}
			var is_xp: bool = data.has("melee") and data.has("vitality") and typeof(data["melee"]) in [TYPE_INT, TYPE_FLOAT]
			for k in data.keys():
				if is_xp and k == "melee":
					continue
				var v = data[k]
				if k == "skill" and typeof(v) == TYPE_STRING and v == "melee":
					v = "attack"
				out[k] = migrate_combat_skills(v)
			if is_xp:
				for s in ["attack", "strength", "defence"]:
					out[s] = maxi(int(out.get(s, 0)), int(data["melee"]))
			return out
		TYPE_ARRAY:
			var arr := []
			for v in data:
				arr.append(migrate_combat_skills(v))
			return arr
	return data


## v3 -> v4 (0.3.1): player gets an empty custom map-markers list + minimap toggle.
static func migrate_map_markers(data):
	if typeof(data) != TYPE_DICTIONARY:
		return data
	var p = data.get("player", {})
	if typeof(p) == TYPE_DICTIONARY and not p.has("map_markers"):
		p["map_markers"] = {"list": [], "minimap": true, "next_id": 1}
		data["player"] = p
	return data


## v4 -> v5 (0.3.1): seed day/night cycle offset (start at dawn-ish day).
static func migrate_daynight(data):
	if typeof(data) != TYPE_DICTIONARY:
		return data
	if not data.has("daynight"):
		data["daynight"] = {"offset_ticks": 0, "phase": "day"}
	return data


## v5 -> v6 (0.3.1 world layout): rocks moved into named mines, the Scorch,
## stone churches. The player gets an empty PK-zone memory (so the first
## Scorch crossing still warns), and old depleted-node timers are dropped (they
## were keyed to the old rock positions). A player standing on a tile that is
## now a wall/water is moved by main.relocate_if_walled on load.
static func migrate_world_layout(data):
	if typeof(data) != TYPE_DICTIONARY:
		return data
	var p = data.get("player", {})
	if typeof(p) == TYPE_DICTIONARY and not p.has("zone_seen"):
		p["zone_seen"] = {}
		data["player"] = p
	var w = data.get("world", {})
	if typeof(w) == TYPE_DICTIONARY and w.has("depleted"):
		w["depleted"] = {}
		data["world"] = w
	return data


## v6 -> v7 (0.3.1 walled cities): Fenhollow, Cinderholt and Saltmere were
## re-laid out inside walls with gates (new streets, a Cook House each). Saved
## tiles inside a city no longer mean anything, so the load step
## (main.apply_city_relayout) moves a player who was inside a city to that
## city's square and lifts ground piles off new walls. Market shelves keep
## their saved counts; the new Cook House shelves start at their data stock.
static func migrate_walled_cities(data):
	if typeof(data) != TYPE_DICTIONARY:
		return data
	if data.has("player") or data.has("world"):
		data["relayout_cities"] = true
	return data


## v7 -> v8 (0.3.1 AI track): Scorch PK state on the player (no skull, the
## rules card not yet shown) and the adventurer / gear-market blocks in the AI
## save. All additive: older AI agent records load as they are (tint and
## generation default), AdvBrain / GearEconomy start empty.
static func migrate_adventurers_pk(data):
	if typeof(data) != TYPE_DICTIONARY:
		return data
	if typeof(data.get("player")) == TYPE_DICTIONARY:
		var pl: Dictionary = data["player"]
		if not pl.has("skull_until"):
			pl["skull_until"] = -1
		if not pl.has("pk_warned"):
			pl["pk_warned"] = false
	if typeof(data.get("ai")) == TYPE_DICTIONARY:
		var ai: Dictionary = data["ai"]
		if not ai.has("adv"):
			ai["adv"] = {}
		if not ai.has("gear_econ"):
			ai["gear_econ"] = {}
	return data
