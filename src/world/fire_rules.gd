class_name FireRules
extends RefCounted
## 0.3.6 cooking fires (data/fire.json): flint + log -> a temporary hearth on
## the ground.

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/fire.json", FileAccess.READ)
		_cfg = JSON.parse_string(f.get_as_text()) if f else {}
	return _cfg


static func is_log(id: String) -> bool:
	return (cfg().get("logs", {}) as Dictionary).has(id)


## Burn time in ticks: ash 200 (2 min), +100 per higher tier.
static func burn_ticks(log_id: String) -> int:
	var l: Dictionary = cfg().get("logs", {}).get(log_id, {})
	return int(cfg().get("base_ticks", 200)) + int(cfg().get("per_tier_ticks", 100)) * (int(l.get("tier", 1)) - 1)


static func fire_xp(log_id: String) -> int:
	return int(cfg().get("logs", {}).get(log_id, {}).get("xp", 2))


## Best-tier log in the pack ("" = none).
static func best_log(inv: ItemContainer) -> String:
	var best := ""
	var bt := 0
	for s in inv.slots:
		if s != null and is_log(str(s["id"])):
			var t := int(cfg()["logs"][s["id"]].get("tier", 1))
			if t > bt:
				bt = t
				best = str(s["id"])
	return best


## Light a fire: needs flint + the log; 1 of each used; the fire goes on a free
## tile next to the actor. Returns "" or the reason it failed.
static func light(actor: Actor, world, log_id: String) -> String:
	if actor.inventory.count("flint") <= 0:
		return "You need flint."
	if log_id == "" or actor.inventory.count(log_id) <= 0:
		return "You need a log to burn."
	var spot := Vector2i(-99999, 0)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var q: Vector2i = actor.tile + d
		if not world.is_blocked(q) and world.object_at(q) == null and world.gen.building_at(q).is_empty():
			spot = q
			break
	if spot.x == -99999:
		return "There's no room to light a fire here."
	actor.inventory.remove("flint", 1)
	actor.inventory.remove(log_id, 1)
	world.add_fire(spot, burn_ticks(log_id))
	actor.skills.add_xp("forestry", fire_xp(log_id))
	return ""

