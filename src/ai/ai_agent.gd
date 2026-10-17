class_name AIAgent
extends RefCounted
## Persistent record for one AI player. This is the source of truth in every
## simulation tier; a detailed-tier AIPlayer node borrows it while on screen.

var id: String
var name: String
var persona: Dictionary = {}
var skills: Skills
var stash: Dictionary = {}        # bank: item -> qty
var tools: Dictionary = {}        # skill -> {"id", "dur"}
var coins: int = 0
var home := Vector2i.ZERO
var home_town: String = "fenhollow"
var town: String = "fenhollow"    # where the agent is (trades here); traders move
var trip: Dictionary = {}         # traders on the road: {"from", "to", "idx"}
var gear: Dictionary = {}         # armour slot -> {"id", "dur"} (weapon lives in tools.melee)
var pos := Vector2i.ZERO
var tier: int = 2                 # 0 detailed, 1 nearby-abstract, 2 world-abstract
var activity: Dictionary = {}     # {"type","skill","node","recipe","until"}
var frac: Dictionary = {}         # fractional production accumulators
var hunger: float = 0.0
var hp: float = -1.0              # -1 = full (set on first fight)
var prayer: Dictionary = {}       # Prayer buff state, shared with the on-screen body
var memo: Dictionary = {}         # "s:item"/"b:item" -> price multiplier (learned)
var my_orders: Dictionary = {}    # order id -> {"item", "buy"} (to detect fills)
var next_trade_tick: int = 0
var stats := {"earned": 0, "spent": 0, "made": 0, "gathered": 0, "trades": 0}
var rng := RandomNumberGenerator.new()
var view = null                   # AIPlayer when detailed
var skull_until: int = -1         # 0.3.1 PK: skulled until this tick (see PkRules)
var adv: Dictionary = {}          # 0.3.1 adventurer-class state (AdvBrain): bis, target, history
var tint: String = ""             # 0.3.1 own look ("" = the persona's tint); new players get their own
var gen: int = 1                  # 0.3.1 how many characters have held this population slot


func _init() -> void:
	skills = Skills.new()


func persona_id() -> String:
	return persona.get("id", "")


func focus() -> Array:
	return persona.get("focus", [])


func stash_count(item: String) -> int:
	return int(stash.get(item, 0))


## Stash plus whatever the on-screen body carries in its pack.
func held_count(item: String) -> int:
	var n := stash_count(item)
	if view != null and is_instance_valid(view):
		n += view.inventory.count(item)
	return n


func stash_add(item: String, q: int) -> void:
	if q == 0:
		return
	var n := stash_count(item) + q
	if n <= 0:
		stash.erase(item)
	else:
		stash[item] = n


func has_inputs(req: Dictionary, batches: int = 1) -> bool:
	for k in req.keys():
		if stash_count(k) < int(req[k]) * batches:
			return false
	return true


func tool_power(skill: String) -> float:
	var t: Dictionary = tools.get(skill, {})
	if t.is_empty():
		return 0.0
	return float(GameData.item(t["id"]).get("tool", {}).get("power", 0.0))


## Wear the tool for `skill` by n uses. Returns true if it broke.
func wear(skill: String, n: int) -> bool:
	var t: Dictionary = tools.get(skill, {})
	if t.is_empty() or n <= 0:
		return false
	t["dur"] = int(t["dur"]) - n
	if int(t["dur"]) <= 0:
		tools.erase(skill)
		return true
	return false


func gear_stat(stat: String) -> int:
	var n := 0
	for g in gear.values():
		n += int(GameData.item(g["id"]).get("gear", {}).get(stat, 0))
	var w: Dictionary = tools.get("melee", {})
	if not w.is_empty():
		n += int(GameData.item(w["id"]).get("gear", {}).get(stat, 0))
	return n


## Wear every armour piece by n; broken pieces are gone (an item sink).
func wear_gear(n: int) -> void:
	for slot in gear.keys():
		gear[slot]["dur"] = int(gear[slot]["dur"]) - n
		if int(gear[slot]["dur"]) <= 0:
			gear.erase(slot)


func give_tool(item_id: String, dur: int = -1) -> void:
	var gd: Dictionary = GameData.item(item_id).get("gear", {})
	if not gd.is_empty() and gd.get("slot", "") in ["head", "body", "legs", "shield"]:
		gear[gd["slot"]] = {"id": item_id, "dur": dur if dur >= 0 else int(gd.get("durability", 400))}
		return
	var tool: Dictionary = GameData.item(item_id).get("tool", {})
	if tool.is_empty():
		return
	tools[tool["skill"]] = {"id": item_id, "dur": dur if dur >= 0 else int(tool.get("durability", 100))}


func to_save() -> Dictionary:
	return {"id": id, "name": name, "persona": persona_id(), "xp": skills.to_save(), "stash": stash,
		"tools": tools, "coins": coins, "home": [home.x, home.y], "pos": [pos.x, pos.y],
		"activity": activity, "frac": frac, "hunger": hunger, "hp": hp, "prayer": prayer, "next_trade_tick": next_trade_tick,
		"stats": stats, "seed": rng.seed, "memo": memo, "my_orders": my_orders,
		"home_town": home_town, "town": town, "trip": trip, "gear": gear, "skull_until": skull_until, "adv": adv, "tint": tint, "gen": gen}


func from_save(d: Dictionary) -> void:
	id = d.get("id", id)
	name = d.get("name", name)
	for p in GameData.personas:
		if p["id"] == d.get("persona", ""):
			persona = p
	skills.from_save(d.get("xp", {}))
	stash.clear()
	for k in d.get("stash", {}).keys():
		stash[k] = int(d["stash"][k])
	tools.clear()
	for k in d.get("tools", {}).keys():
		tools[k] = {"id": str(d["tools"][k]["id"]), "dur": int(d["tools"][k]["dur"])}
	coins = int(d.get("coins", 0))
	var h: Array = d.get("home", [0, 0])
	home = Vector2i(int(h[0]), int(h[1]))
	var p2: Array = d.get("pos", [0, 0])
	pos = Vector2i(int(p2[0]), int(p2[1]))
	activity = d.get("activity", {})
	if activity.has("until"):
		activity["until"] = int(activity["until"])
	frac = d.get("frac", {})
	hunger = float(d.get("hunger", 0.0))
	hp = float(d.get("hp", -1.0))
	prayer = d.get("prayer", {})
	next_trade_tick = int(d.get("next_trade_tick", 0))
	stats = d.get("stats", stats)
	rng.seed = int(d.get("seed", hash(id)))
	memo = d.get("memo", {})
	home_town = str(d.get("home_town", home_town))
	town = str(d.get("town", home_town))
	trip = d.get("trip", {})
	if trip.has("idx"):
		trip["idx"] = int(trip["idx"])
	gear.clear()
	for k in d.get("gear", {}).keys():
		gear[k] = {"id": str(d["gear"][k]["id"]), "dur": int(d["gear"][k]["dur"])}
	skull_until = int(d.get("skull_until", -1))
	adv = d.get("adv", {})
	tint = str(d.get("tint", ""))
	gen = int(d.get("gen", 1))
	my_orders.clear()
	var mo: Dictionary = d.get("my_orders", {})
	for k in mo.keys():
		my_orders[int(k)] = mo[k]
