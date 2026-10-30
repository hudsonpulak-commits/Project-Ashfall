class_name Skills
extends RefCounted
## Skill XP container shared by the player and AI players.
## Levels are always derived from XP (single source of truth).

signal xp_gained(skill_id: String, amount: int)
signal leveled(skill_id: String, new_level: int)

var xp: Dictionary = {}   # skill_id -> int


func _init() -> void:
	for s in GameData.skills:
		xp[s["id"]] = 0
	# Vitality starts at level 10 so early fights aren't instant deaths.
	if xp.has("vitality"):
		xp["vitality"] = GameData.xp_for_level(10)


func level(skill_id: String) -> int:
	return GameData.level_for_xp(int(xp.get(skill_id, 0)))


## Debug/test helper: set a skill to the start of a level.
func set_level(skill_id: String, lvl: int) -> void:
	xp[skill_id] = GameData.xp_for_level(lvl)


func total_level() -> int:
	var t := 0
	for id in xp.keys():
		t += level(id)
	return t


func add_xp(skill_id: String, amount: int) -> void:
	if amount <= 0 or not xp.has(skill_id):
		return
	var before := level(skill_id)
	xp[skill_id] = mini(int(xp[skill_id]) + amount, GameData.xp_for_level(GameData.max_level) * 4)
	xp_gained.emit(skill_id, amount)
	var after := level(skill_id)
	if after > before:
		leveled.emit(skill_id, after)


## 0..1 progress through the current level.
func progress(skill_id: String) -> float:
	var l := level(skill_id)
	if l >= GameData.max_level:
		return 1.0
	var a := GameData.xp_for_level(l)
	var b := GameData.xp_for_level(l + 1)
	return clampf(float(int(xp[skill_id]) - a) / float(maxi(1, b - a)), 0.0, 1.0)


func to_save() -> Dictionary:
	return xp.duplicate()


func from_save(d: Dictionary) -> void:
	for k in d.keys():
		if xp.has(k):
			xp[k] = int(d[k])
	# pre-0.2.4 records (belt and braces; SaveSystem migrates files too):
	# Melee XP carries into each of Attack, Strength and Defence
	if d.has("melee"):
		for s in ["attack", "strength", "defence"]:
			if not d.has(s):
				xp[s] = int(d["melee"])
	# 0.4.0 Joinery became Fletching
	if d.has("joinery") and not d.has("fletching"):
		xp["fletching"] = int(d["joinery"])
