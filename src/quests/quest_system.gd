class_name QuestSystem
extends RefCounted
## 0.3.7 data-driven quests (data/quests.json). Player state per quest id:
## {"stage": int, "count": int, "done": bool}; absent = not started.

static var _cfg: Dictionary = {}
static var _giver_tiles: Dictionary = {}   # giver id -> Vector2i (found once per world)

const NOT_STARTED := "not_started"
const IN_PROGRESS := "in_progress"
const READY := "ready"           # current stage is "talk to the giver"
const COMPLETED := "completed"


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/quests.json", FileAccess.READ)
		_cfg = JSON.parse_string(f.get_as_text()) if f else {"quests": [], "givers": {}}
	return _cfg


static func quests() -> Array:
	return cfg().get("quests", [])


static func quest(id: String) -> Dictionary:
	for q in quests():
		if q["id"] == id:
			return q
	return {}


static func state(p, id: String) -> String:
	var s: Dictionary = p.quests.get(id, {})
	if s.is_empty():
		return NOT_STARTED
	if bool(s.get("done", false)):
		return COMPLETED
	var st := stage(id, int(s.get("stage", 0)))
	match str(st.get("type", "")):
		"talk":
			return READY
		"gather":      # 0.3.15 ready to hand in once the pack holds every item
			return READY if has_items(p, st) else IN_PROGRESS
	return IN_PROGRESS


## 0.3.15 "gather" stage: {"items": {id: n}, "labels": {id: "Wolf pelts"}, "source": [enemy kinds]}.
## Counts what is in the pack (not the bank); handing in removes it.
static func has_items(p, st: Dictionary) -> bool:
	for it in st.get("items", {}).keys():
		if p.inventory.count(it) < int(st["items"][it]):
			return false
	return true


static func gather_text(p, st: Dictionary) -> String:
	var bits := []
	for it in st.get("items", {}).keys():
		var lbl := str(st.get("labels", {}).get(it, GameData.item_name(it)))
		bits.append("%s %d/%d" % [lbl, mini(p.inventory.count(it), int(st["items"][it])), int(st["items"][it])])
	return ", ".join(bits)


static func stage(id: String, i: int) -> Dictionary:
	var stages: Array = quest(id).get("stages", [])
	return stages[i] if i >= 0 and i < stages.size() else {}


static func current_stage(p, id: String) -> Dictionary:
	var s: Dictionary = p.quests.get(id, {})
	if s.is_empty() or bool(s.get("done", false)):
		return {}
	return stage(id, int(s.get("stage", 0)))


## Journal line, e.g. "Goblins 3/5".
static func progress_text(p, id: String) -> String:
	match state(p, id):
		NOT_STARTED:
			return "Not started: talk to %s" % giver_name(str(quest(id).get("giver", "")))
		COMPLETED:
			return "Completed"
	var st := current_stage(p, id)
	if str(st.get("type", "")) == "kill":
		return "%s: %s %d/%d" % [str(st.get("text", "")), str(st.get("label", st.get("enemy", ""))), int(p.quests[id].get("count", 0)), int(st.get("count", 1))]
	if str(st.get("type", "")) == "gather":
		return "%s: %s" % [str(st.get("text", "")), gather_text(p, st)]
	return str(st.get("text", ""))


static func giver_name(gid: String) -> String:
	return str(cfg().get("givers", {}).get(gid, {}).get("name", gid))


## Overhead / map symbol for a giver: "?" a quest to start, "!" one to turn in.
static func giver_marker(p, gid: String) -> String:
	var mark := ""
	for q in quests():
		if str(q.get("giver", "")) != gid:
			continue
		var s := state(p, q["id"])
		if s == READY:
			return "!"
		if s == NOT_STARTED:
			mark = "?"
	return mark


static func giver_tile(world, gid: String) -> Vector2i:
	if _giver_tiles.has(gid) and world.object_at(_giver_tiles[gid]) != null:
		return _giver_tiles[gid]
	var g: Dictionary = cfg().get("givers", {}).get(gid, {})
	if g.has("near"):     # 0.3.15 placed by WorldGen._place_quest_givers
		var sp: Vector2i = world.gen.giver_spot(gid)
		if sp.x > -99999:
			_giver_tiles[gid] = sp
		return sp
	var o = world.find_nearest_object(world.gen.town_center(str(g.get("town", ""))), [str(g.get("object", "quest_giver"))], 40)
	if o == null:
		return Vector2i(-99999, -99999)
	_giver_tiles[gid] = o.pos
	return o.pos


## Talking to a quest giver (Interactions "quest"): opens the dialog panel.
static func talk(p, obj) -> void:
	var gid := str(obj.def().get("giver", ""))
	if Events.has_signal("quest_dialog"):
		Events.quest_dialog.emit(gid)


static func _advance(p, id: String) -> void:
	var s: Dictionary = p.quests[id]
	var cur := stage(id, int(s["stage"]))
	if str(cur.get("type", "")) == "gather":
		if not has_items(p, cur):
			return
		for it in cur.get("items", {}).keys():
			p.inventory.remove(it, int(cur["items"][it]))
		Events.inventory_changed.emit()
	s["stage"] = int(s["stage"]) + 1
	s["count"] = 0
	if stage(id, int(s["stage"])).is_empty():
		s["done"] = true
		_reward(p, id)
	_changed()


static func _reward(p, id: String) -> void:
	var r: Dictionary = quest(id).get("rewards", {})
	var inf := int(r.get("influence", 0))
	p.influence += inf
	var bits := ["+%d Influence" % inf]
	if int(r.get("marks", 0)) > 0:
		p.inventory.add(GameData.currency, int(r["marks"]))
		bits.append("%d marks" % int(r["marks"]))
	for it in r.get("items", {}).keys():
		var n := int(r["items"][it])
		if p.inventory.room_for(it) >= n:
			p.inventory.add(it, n)
		elif p.get("world_ref") != null and p.world_ref.get("ground") != null:
			p.world_ref.ground.add(p.tile, it, n, Tick.tick_count, -1, p.actor_id)
		bits.append("%s x%d" % [GameData.item_name(it), n])
	for sk in r.get("xp", {}).keys():      # 0.3.15
		p.skills.add_xp(sk, int(r["xp"][sk]))
		bits.append("%d %s XP" % [int(r["xp"][sk]), str(sk).capitalize()])
	Events.say("Quest complete: %s! %s" % [quest(id)["name"], ", ".join(bits)], "level")
	Events.inventory_changed.emit()


## A kill by the player (only the quest holder's own kills count).
static func on_kill(p, kind: String) -> void:
	for id in p.quests.keys():
		var st := current_stage(p, id)
		if str(st.get("type", "")) != "kill" or str(st.get("enemy", "")) != kind:
			continue
		var s: Dictionary = p.quests[id]
		s["count"] = mini(int(s.get("count", 0)) + 1, int(st.get("count", 1)))
		Events.say("%s: %s" % [quest(id)["name"], progress_text(p, id)])
		if int(s["count"]) >= int(st.get("count", 1)):
			_advance(p, id)
		else:
			_changed()


## 0.3.7.1 the current objective, ALWAYS during an active quest:
## {"tile", "kind": "enemy" | "area" | "npc"}. Kill stage: the nearest live
## target (any distance); none alive -> its nearest spawn area. {} = none.
static func objective(p, world) -> Dictionary:
	for q in quests():
		var id: String = q["id"]
		var s := state(p, id)
		if s == READY:
			return {"tile": giver_tile(world, str(q.get("giver", ""))), "kind": "npc"}
		if s != IN_PROGRESS:
			continue
		var kind := _target_kind(current_stage(p, id))
		var best = null
		var bd := 1 << 30
		for e in world.enemies.enemies:
			if e.dead or e.kind != kind:
				continue
			var d: int = maxi(absi(e.tile.x - p.tile.x), absi(e.tile.y - p.tile.y))
			if d < bd:
				bd = d
				best = e.tile
		if best != null:
			return {"tile": best, "kind": "enemy"}
		var a = spawn_area(kind, p.tile)
		if a != null:
			return {"tile": a, "kind": "area"}
	return {}


static func objective_tile(p, world) -> Variant:
	var o := objective(p, world)
	return o.get("tile") if not o.is_empty() else null


## Nearest camp ("at" in data/enemies.json camps) of an enemy kind.
static func spawn_area(kind: String, from: Vector2i) -> Variant:
	var best = null
	var bd := 1 << 30
	for c in _camps():
		if str(c.get("enemy", "")) != kind:
			continue
		var t := Vector2i(int(c["at"][0]), int(c["at"][1]))
		var d: int = maxi(absi(t.x - from.x), absi(t.y - from.y))
		if d < bd:
			bd = d
			best = t
	return best


static var _camp_cache: Array = []


static func _camps() -> Array:
	if _camp_cache.is_empty():
		var f := FileAccess.open("res://data/enemies.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else {}
		_camp_cache = d.get("camps", []) if d is Dictionary else []
	return _camp_cache


## Map / minimap objective area during a kill stage: the target's camp.
static func objective_area(p, world) -> Variant:
	for q in quests():
		var id: String = q["id"]
		if state(p, id) != IN_PROGRESS:
			continue
		var a = spawn_area(_target_kind(current_stage(p, id)), p.tile)
		if a != null:
			return a
	return null


## Kill stage: its enemy; gather stage: the first "source" enemy (0.3.15).
static func _target_kind(st: Dictionary) -> String:
	if st.has("enemy"):
		return str(st["enemy"])
	var src: Array = st.get("source", [])
	return str(src[0]) if not src.is_empty() else ""


# ---------------------------------------------------------------- dialog --
## 0.3.7.1 data-driven dialog (quests.json "dialog"): node by state —
## "offer" (not started), "in_progress", "stage_<i>" (a talk stage),
## "completed". Each node: text (+ {progress}), choices [{label, action}].
## Actions: accept, decline, advance, close.
static func dialog(p, gid: String) -> Dictionary:
	for q in quests():
		if str(q.get("giver", "")) != gid:
			continue
		var id: String = q["id"]
		var dl: Dictionary = q.get("dialog", {})
		var key := ""
		match state(p, id):
			NOT_STARTED: key = "offer"
			IN_PROGRESS: key = "in_progress"
			READY: key = "stage_%d" % int(p.quests[id].get("stage", 0))
			COMPLETED: key = "completed"
		if state(p, id) == COMPLETED and _later_from(gid, id):
			continue     # a later quest from the same giver may be on offer (0.3.15: per giver)
		var node: Dictionary = dl.get(key, {})
		return {"quest": id, "name": giver_name(gid), "node": key,
			"text": str(node.get("text", "")).replace("{progress}", progress_text(p, id)),
			"choices": node.get("choices", [{"label": "Goodbye", "action": "close"}])}
	return {"quest": "", "name": giver_name(gid), "node": "", "text": "Good day.", "choices": [{"label": "Goodbye", "action": "close"}]}


static func _later_from(gid: String, id: String) -> bool:
	var seen := false
	for q in quests():
		if q["id"] == id:
			seen = true
		elif seen and str(q.get("giver", "")) == gid:
			return true
	return false


## A dialog choice. Returns the reply line ("" = none). Never auto-starts.
static func choose(p, quest_id: String, action: String) -> String:
	var q := quest(quest_id)
	var reply := ""
	for node in q.get("dialog", {}).values():
		for c in node.get("choices", []):
			if str(c.get("action", "")) == action and c.has("reply"):
				reply = str(c["reply"])
	match action:
		"accept":
			if state(p, quest_id) == NOT_STARTED:
				p.quests[quest_id] = {"stage": 0, "count": 0, "done": false}
				Events.say("Quest started: %s" % q["name"], "level")
				_changed()
		"advance":
			if state(p, quest_id) == READY:
				_advance(p, quest_id)
			else:
				reply = ""
		_:
			pass
	if reply != "":
		p.say("%s: %s" % [giver_name(str(q.get("giver", ""))), reply])
	return reply


static func _changed() -> void:
	if Events.has_signal("quests_changed"):
		Events.quests_changed.emit()
