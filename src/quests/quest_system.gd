class_name QuestSystem
extends RefCounted
## 0.3.7 data-driven quests (data/quests.json). Player state per quest id:
## {"stage": int, "count": int, "done": bool}; absent = not started.

static var _cfg: Dictionary = {}
static var _giver_tiles: Dictionary = {}   # giver id -> Vector2i (found once per world)
static var done_ids: Dictionary = {}      # 0.3.16 completed quest ids (repair props read this)

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
			return READY if has_items(p, st) or has_alt_items(p, st) else IN_PROGRESS
		"escort":      # 0.3.16 ready once the follower stands near the npc
			return READY if escort_arrived(p, id, st) else IN_PROGRESS
	return IN_PROGRESS


## 0.3.16 who to talk to for the current stage: its "npc", else the quest giver.
static func stage_npc(id: String, st: Dictionary) -> String:
	return str(st.get("npc", quest(id).get("giver", "")))


const ESCORT_NEAR := 4


static func follower(world, kind: String):
	if world == null or world.get("enemies") == null:
		return null
	for e in world.enemies.enemies:
		if e.kind == kind and not e.dead:
			return e
	return null


static func escort_arrived(p, id: String, st: Dictionary) -> bool:
	var w = p.get("world_ref")
	var f = follower(w, str(st.get("follower", "")))
	if f == null:
		return false
	var gt := giver_tile(w, stage_npc(id, st))
	return gt.x > -99999 and maxi(absi(f.tile.x - gt.x), absi(f.tile.y - gt.y)) <= ESCORT_NEAR


## 0.3.16 sync done_ids from the player's quests (load / new game).
static func sync(p) -> void:
	done_ids.clear()
	for id in p.quests.keys():
		if bool(p.quests[id].get("done", false)):
			done_ids[id] = true


## 0.3.15 "gather" stage: {"items": {id: n}, "labels": {id: "Wolf pelts"}, "source": [enemy kinds]}.
## Counts what is in the pack (not the bank); handing in removes it.
static func has_items(p, st: Dictionary) -> bool:
	for it in st.get("items", {}).keys():
		if p.inventory.count(it) < int(st["items"][it]):
			return false
	return true


## 0.4.0 a gather stage may take "alt_items" instead (Smith Venn: ore or marks).
static func has_alt_items(p, st: Dictionary) -> bool:
	if not st.has("alt_items"):
		return false
	for it in st["alt_items"].keys():
		if p.inventory.count(it) < int(st["alt_items"][it]):
			return false
	return true


## 0.4.0 quests with "requires" are offered only once those quests are done.
static func available(p, id: String) -> bool:
	for r in quest(id).get("requires", []):
		if state(p, str(r)) != COMPLETED:
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
	if str(st.get("type", "")) == "escort" and state(p, id) == READY:
		return "%s: home!" % str(st.get("text", ""))
	return str(st.get("text", ""))


## 0.3.17 journal details: where a giver stands ("Fenhollow", "near the wolf den").
static func giver_place(gid: String, gen = null) -> String:
	var g: Dictionary = cfg().get("givers", {}).get(gid, {})
	var t := str(g.get("town", ""))
	if t != "":
		return gen.town_name(t) if gen != null and gen.has_method("town_name") else t.capitalize()
	if g.has("near"):
		return "near the " + str(g["near"]).replace("_", " ")
	return "somewhere in Ashfen"


## 0.3.17 journal status word for the collapsed list.
static func status_word(p, id: String) -> String:
	return {NOT_STARTED: "not started", IN_PROGRESS: "active", READY: "ready to hand in", COMPLETED: "complete"}.get(state(p, id), "active")


## 0.3.17 the expanded journal entry: giver + place, objective/progress, who to return to.
static func detail_lines(p, id: String, gen = null) -> Array:
	var q := quest(id)
	var gid := str(q.get("giver", ""))
	var out: Array = ["Given by: %s (%s)" % [giver_name(gid), giver_place(gid, gen)]]
	out.append("Objective: " + progress_text(p, id))
	var st := state(p, id)
	if st == COMPLETED:
		out.append("Done.")
	elif st == NOT_STARTED:
		out.append("Talk to %s to start." % giver_name(gid))
	else:
		var who := stage_npc(id, current_stage(p, id))
		out.append("Return to: %s (%s)" % [giver_name(who), giver_place(who, gen)])
	return out


static func giver_name(gid: String) -> String:
	return str(cfg().get("givers", {}).get(gid, {}).get("name", gid))


## Overhead / map symbol for a giver: "?" a quest to start, "!" one to turn in.
static func giver_marker(p, gid: String) -> String:
	var mark := ""
	for q in quests():
		var s := state(p, q["id"])
		if s == READY and stage_npc(q["id"], current_stage(p, q["id"])) == gid:
			return "!"
		if str(q.get("giver", "")) == gid and s == NOT_STARTED and available(p, q["id"]):
			mark = "?"
	return mark


static func giver_tile(world, gid: String) -> Vector2i:
	if _giver_tiles.has(gid):
		var gt: Vector2i = _giver_tiles[gid]
		# 0.3.16 a cached giver in an unloaded chunk is trusted (checking would generate it)
		if (world.has_method("object_at_loaded") and world.chunks.get(World.chunk_of(gt)) == null) or world.object_at(gt) != null:
			return gt
	var g: Dictionary = cfg().get("givers", {}).get(gid, {})
	if g.has("near") and world.get("gen") != null:     # 0.3.15 placed by WorldGen._place_quest_givers
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


static func _advance(p, id: String, alt: bool = false) -> void:
	var s: Dictionary = p.quests[id]
	var cur := stage(id, int(s["stage"]))
	if str(cur.get("type", "")) == "gather":
		var use: Dictionary = cur.get("alt_items", {}) if alt else cur.get("items", {})
		if (alt and not has_alt_items(p, cur)) or (not alt and not has_items(p, cur)):
			return
		for it in use.keys():
			p.inventory.remove(it, int(use[it]))
		Events.inventory_changed.emit()
	if int(cur.get("influence", 0)) > 0:      # 0.4.0 per-step influence (Pye's line)
		p.influence += int(cur["influence"])
		Events.say("+%d Influence" % int(cur["influence"]))
	for it in cur.get("give", {}).keys():      # 0.3.16 e.g. the smith's finished goods
		var n := int(cur["give"][it])
		if p.inventory.room_for(it) >= n:
			p.inventory.add(it, n)
		elif p.get("world_ref") != null and p.world_ref.get("ground") != null:
			p.world_ref.ground.add(p.tile, it, n, Tick.tick_count, -1, p.actor_id)
		Events.say("You receive: %s." % GameData.item_name(it))
		Events.inventory_changed.emit()
	s["stage"] = int(s["stage"]) + 1
	s["count"] = 0
	if stage(id, int(s["stage"])).is_empty():
		s["done"] = true
		_reward(p, id)
	_changed()


static func _reward(p, id: String) -> void:
	var r: Dictionary = quest(id).get("rewards", {})
	done_ids[id] = true
	if quest(id).has("complete_notice"):     # 0.4.0 e.g. Odric points at Warden Pye
		Events.say(str(quest(id)["complete_notice"]), "level")
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
static func on_kill(p, kind: String, at: Vector2i = Vector2i(1 << 20, 0)) -> void:
	for id in p.quests.keys():
		var st := current_stage(p, id)
		if str(st.get("type", "")) != "kill" or str(st.get("enemy", "")) != kind:
			continue
		if not kill_in_area(p, st, at):
			continue
		var s: Dictionary = p.quests[id]
		s["count"] = mini(int(s.get("count", 0)) + 1, int(st.get("count", 1)))
		Events.say("%s: %s" % [quest(id)["name"], progress_text(p, id)])
		if int(s["count"]) >= int(st.get("count", 1)):
			_advance(p, id)
		else:
			_changed()


## 0.3.17 a kill stage with "near" (object id) + "radius" only counts kills close to it.
static func kill_in_area(p, st: Dictionary, at: Vector2i) -> bool:
	if st.has("near_towns"):     # 0.4.0 kills on / around these villages' fields
		var w0 = p.get("world_ref") if p != null else null
		if w0 == null or at.x >= (1 << 20):
			return false
		for tid in st["near_towns"]:
			var c: Vector2i = w0.gen.town_center(str(tid))
			if maxi(absi(c.x - at.x), absi(c.y - at.y)) <= int(st.get("radius", 20)):
				return true
		return false
	if not st.has("near"):
		return true
	var w = p.get("world_ref") if p != null else null
	if w == null or at.x >= (1 << 20):
		return false
	return w.find_nearest_object(at, [str(st["near"])], int(st.get("radius", 15))) != null


## 0.3.7.1 the current objective, ALWAYS during an active quest:
## {"tile", "kind": "enemy" | "area" | "npc"}. Kill stage: the nearest live
## target (any distance); none alive -> its nearest spawn area. {} = none.
static func objective(p, world) -> Dictionary:
	for q in quests():
		var id: String = q["id"]
		var s := state(p, id)
		if s == READY:
			return {"tile": giver_tile(world, stage_npc(id, current_stage(p, id))), "kind": "npc"}
		if s != IN_PROGRESS:
			continue
		var cst := current_stage(p, id)
		if str(cst.get("type", "")) == "escort" or (str(cst.get("type", "")) == "gather" and cst.has("npc") and has_items(p, cst)):
			return {"tile": giver_tile(world, stage_npc(id, cst)), "kind": "npc"}
		var kind := _target_kind(cst)
		if kind == "":
			continue
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
		var cd := str(c.get("den", ""))
		if cd != "" and den_of(from) != cd:
			t = den_hole(cd)   # 0.4.2 a den camp seen from outside: point at its way down
		var d: int = maxi(absi(t.x - from.x), absi(t.y - from.y))
		if d < bd:
			bd = d
			best = t
	return best


static var _camp_cache: Array = []


static func _camps() -> Array:
	# 0.4.2 GameData.camps: quest encounters already applied, den camps included
	return GameData.camps


## 0.4.2 den id of a tile from data/underworld.json (no WorldGen needed); "" = surface.
static func den_of(t: Vector2i) -> String:
	var dens: Dictionary = GameData.underworld.get("dens", {})
	for did in dens.keys():
		var dd: Dictionary = dens[did]
		var rows: Array = dd.get("rows", [])
		if rows.is_empty():
			continue
		var pad := int(dd.get("pad", 16))
		var r := Rect2i(Vector2i(int(dd["origin"][0]) - pad, int(dd["origin"][1]) - pad), Vector2i(str(rows[0]).length() + pad * 2, rows.size() + pad * 2))
		if r.has_point(t):
			return did
	return ""


## 0.4.2 the surface tile of a den's entrance (its quest site origin + entrance_at).
static func den_hole(did: String) -> Vector2i:
	var dd: Dictionary = GameData.underworld.get("dens", {}).get(did, {})
	var sd: Dictionary = cfg().get("sites", {}).get(str(dd.get("surface_site", "")), {})
	if sd.is_empty():
		return Vector2i(-99999, -99999)
	var a: Array = dd.get("entrance_at", [1, 1])
	return Vector2i(int(sd["origin"][0]) + int(a[0]), int(sd["origin"][1]) + int(a[1]))


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
	for q in quests():      # 0.3.16 a stage to be finished at THIS npc (deliveries) comes first
		var qid: String = q["id"]
		if str(q.get("giver", "")) == gid or state(p, qid) != READY:
			continue
		var cs := current_stage(p, qid)
		if stage_npc(qid, cs) != gid:
			continue
		var k := "stage_%d" % int(p.quests[qid].get("stage", 0))
		var nd: Dictionary = q.get("dialog_npc", {}).get(gid, {}).get(k, {})
		return {"quest": qid, "name": giver_name(gid), "node": k,
			"text": str(nd.get("text", "")).replace("{progress}", progress_text(p, qid)),
			"choices": nd.get("choices", [{"label": "Goodbye", "action": "close"}])}
	for q in quests():
		if str(q.get("giver", "")) != gid:
			continue
		var id: String = q["id"]
		if state(p, id) == NOT_STARTED and not available(p, id):
			continue
		var dl: Dictionary = q.get("dialog", {})
		var key := ""
		match state(p, id):
			NOT_STARTED: key = "offer"
			IN_PROGRESS: key = "in_progress"
			READY:
				key = "stage_%d" % int(p.quests[id].get("stage", 0))
				if stage_npc(id, current_stage(p, id)) != gid and not dl.has(key):
					key = "in_progress"     # 0.3.16 ready at another npc (a delivery)
			COMPLETED: key = "completed"
		if state(p, id) == COMPLETED and _later_from(gid, id):
			continue     # a later quest from the same giver may be on offer (0.3.15: per giver)
		var node: Dictionary = dl.get(key, {})
		return {"quest": id, "name": giver_name(gid), "node": key,
			"text": str(node.get("text", "")).replace("{progress}", progress_text(p, id)),
			"choices": node.get("choices", [{"label": "Goodbye", "action": "close"}])}
	return {"quest": "", "name": giver_name(gid), "node": "", "text": str(cfg().get("givers", {}).get(gid, {}).get("idle", "Good day.")), "choices": [{"label": "Goodbye", "action": "close"}]}


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
	# 0.3.16 the reply comes from the node on screen (offer, or this stage's turn-in)
	var key := "offer" if state(p, quest_id) == NOT_STARTED else "stage_%d" % int(p.quests[quest_id].get("stage", 0))
	var nodes: Array = []
	if q.get("dialog", {}).has(key):
		nodes.append(q["dialog"][key])
	for g in q.get("dialog_npc", {}).values():
		if g.has(key):
			nodes.append(g[key])
	for node in nodes:
		for c in node.get("choices", []):
			if str(c.get("action", "")) == action and c.has("reply"):
				reply = str(c["reply"])
	match action:
		"accept":
			if state(p, quest_id) == NOT_STARTED and available(p, quest_id):
				p.quests[quest_id] = {"stage": 0, "count": 0, "done": false}
				Events.say("Quest started: %s" % q["name"], "level")
				_changed()
		"advance":
			if state(p, quest_id) == READY:
				_advance(p, quest_id)
			else:
				reply = ""
		"advance_alt":     # 0.4.0 the alternative payment (Venn: 200 marks)
			if state(p, quest_id) == READY and has_alt_items(p, current_stage(p, quest_id)):
				_advance(p, quest_id, true)
		_:
			pass
	if reply != "":
		p.say("%s: %s" % [giver_name(str(q.get("giver", ""))), reply])
	return reply


static func _changed() -> void:
	if Events.has_signal("quests_changed"):
		Events.quests_changed.emit()
