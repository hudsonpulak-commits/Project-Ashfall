class_name PkRules
extends RefCounted
## 0.3.1 PK (player-killing) rules for the PK zones of data/pk_zones.json
## ("the Scorch"); tuning in data/pk.json. See docs/GDD.md "PK zone".
##  - Anyone may attack anyone inside (player <-> AI, AI <-> AI), both must
##    stand in a PK zone. Every PK zone is multi-combat (CombatRules.is_multi).
##  - First strike: attacking someone who has not attacked you (within the
##    skull window) skulls you for skull_minutes.
##  - Death inside: keep the keep_items most valuable item units (0 when
##    skulled); everything else drops for the killer (private for
##    killer_private_ticks, then public). Coins are never kept; the healer
##    keeps the normal 10 % of carried coin.
## Kept decoupled from the world track: zones come from data/pk_zones.json
## (or GameData.pk_zones if the world track adds it); World never has to know.

static var _cfg: Dictionary = {}
static var _zones: Array = []          # raw zone dicts
static var _rects: Array = []          # Array[Rect2i], parallel to _zones
static var _loaded := false


static func _read(rel: String) -> Dictionary:
	var f := FileAccess.open("res://data/" + rel, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cfg = _read("pk.json")
	var src: Dictionary = {}
	if "pk_zones" in GameData and typeof(GameData.get("pk_zones")) == TYPE_DICTIONARY and not (GameData.get("pk_zones") as Dictionary).is_empty():
		src = GameData.get("pk_zones")
	else:
		src = _read("pk_zones.json")
	set_zones(src.get("zones", []))


static func reload() -> void:
	_loaded = false
	_load()


## Replace the zone list (tests; the world track's data).
static func set_zones(zs: Array) -> void:
	_loaded = true
	if _cfg.is_empty():
		_cfg = _read("pk.json")
	_zones = zs.duplicate()
	_rects.clear()
	for z in _zones:
		var r: Array = z.get("rect", [0, 0, 0, 0])
		_rects.append(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))


static func cfg() -> Dictionary:
	_load()
	return _cfg


static func ai_cfg() -> Dictionary:
	return cfg().get("ai", {})


static func zones() -> Array:
	_load()
	return _zones


static func zone_at(tile: Vector2i) -> Dictionary:
	_load()
	for i in _rects.size():
		if (_rects[i] as Rect2i).has_point(tile):
			return _zones[i]
	return {}


static func is_pk(tile: Vector2i) -> bool:
	_load()
	for r in _rects:
		if (r as Rect2i).has_point(tile):
			return true
	return false


## A random land tile inside a PK zone, in its southern `band` rows (where
## people come in from the towns), or the zone centre.
static func random_spot(rng: RandomNumberGenerator, world = null, band: int = 70) -> Vector2i:
	_load()
	if _rects.is_empty():
		return Vector2i.ZERO
	var r: Rect2i = _rects[rng.randi() % _rects.size()]
	var y0 := maxi(r.position.y, r.end.y - band)
	for i in 40:
		var p := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(y0, r.end.y - 1))
		if world == null:
			if _on_land(p):
				return p
		elif world.gen.land_value(p.x, p.y) > WorldGen.BEACH_LEVEL + 0.05 and not world.is_blocked(p):
			return p
	for i in 40:
		var q := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if (world == null and _on_land(q)) or (world != null and not world.is_blocked(q) and world.gen.land_value(q.x, q.y) > WorldGen.BEACH_LEVEL):
			return q
	return Vector2i(r.get_center().x, r.end.y - 5)


## Rough continent test without a World (data/world.json circle).
static func _on_land(p: Vector2i) -> bool:
	var c: Dictionary = GameData.world.get("continent", {})
	var ctr: Array = c.get("center", [180, -10])
	return Vector2(p).distance_to(Vector2(float(ctr[0]), float(ctr[1]))) < float(c.get("radius", 330)) * 0.92


static func skull_ticks() -> int:
	return int(cfg().get("skull_minutes", 10)) * int(cfg().get("ticks_per_minute", 100))


static func keep_count(skulled: bool) -> int:
	return 0 if skulled else int(cfg().get("keep_items", 3))


static func coin_fee() -> float:
	return float(cfg().get("coin_fee", 0.10))


# ------------------------------------------------------------ who may hit --
## "" = `att` may attack actor `vic` now, else the reason (shown to the player).
static func can_pvp(att, vic, _t: int) -> String:
	if att == vic or vic == null or not is_instance_valid(vic) or vic.dead:
		return "You can't attack that."
	if not is_pk(att.tile):
		return "You can only attack other players in the Scorch."
	if not is_pk(vic.tile):
		return "They're not in the Scorch."
	return ""


## Bookkeeping for a PvP swing (call before the hit lands): the first strike
## on someone who has not attacked you skulls you. Returns true if it skulled.
static func on_pvp_swing(att, vic, t: int) -> bool:
	var st := skull_ticks()
	var hit_me: int = int(att.pvp_aggr.get(vic.actor_id, -1000000))
	if t - hit_me < st:
		return false                       # retaliation: never skulls
	var before: int = int(vic.pvp_aggr.get(att.actor_id, -1000000))
	vic.pvp_aggr[att.actor_id] = t
	if t - before < st:
		return false                       # still the same fight
	var was: bool = att.is_skulled(t)
	att.set_skull(t + st)
	return not was


# --------------------------------------------------------- PvP formulas --
## Fighter stats for PvP / duel estimates: levels, gear bonuses, weapon,
## HP now, max HP and the HP its food can heal.
static func actor_stats(a) -> Dictionary:
	var w: String = a.weapon_id()
	var s := {"attack": a.skills.level("attack"), "strength": a.skills.level("strength"), "defence": a.skills.level("defence"),
		"atk": a.combat_atk(), "str": a.combat_str(), "def": a.combat_def(), "power": a.weapon_power(), "weapon": w,
		"hp": float(a.hp), "max_hp": float(a.max_hp()), "heal": 0.0, "prayer": a.prayer}
	if a is AIPlayer and a.agent:
		s["heal"] = food_heal(a.agent)
	else:
		for sl in a.inventory.slots:
			if sl != null:
				s["heal"] = float(s["heal"]) + float(GameData.item(sl["id"]).get("heals", 0)) * int(sl["qty"])
	return s


static func agent_stats(agent: AIAgent) -> Dictionary:
	var s := AIBrain.fight_stats(agent)
	var mh := float(AIBrain.agent_max_hp(agent))
	s["hp"] = mh if agent.hp < 0.0 else agent.hp
	s["max_hp"] = mh
	s["heal"] = food_heal(agent)
	s["prayer"] = agent.prayer
	return s


## Healing an adventurer-class AI carries into the zone (its first carry_food foods).
static func food_heal(agent: AIAgent) -> float:
	var left := int(ai_cfg().get("carry_food", 8))
	var h := 0.0
	for f in AIBrain.FOODS:
		var n := mini(left, agent.stash_count(f))
		h += n * float(GameData.item(f).get("heals", 3))
		left -= n
	return h


static func accuracy(att: Dictionary, vic: Dictionary) -> float:
	var p: Dictionary = cfg().get("pvp", {})
	var brk := Combat.armour_break(str(att.get("weapon", "")))
	var acc := float(p.get("base_acc", 0.55)) + (int(att.get("attack", 1)) + int(att.get("atk", 0))) * float(p.get("atk_per", 0.01)) \
		- (int(vic.get("defence", 1)) * float(p.get("def_level_per", 0.008)) + int(vic.get("def", 0)) * float(p.get("def_gear_per", 0.006))) * (1.0 - brk)
	acc = clampf(acc, float(p.get("min_acc", 0.1)), float(p.get("max_acc", 0.9)))
	acc *= Prayer.mult(att.get("prayer", {}), "acc") * Prayer.mult(vic.get("prayer", {}), "def")
	return clampf(acc, 0.02, 0.95)


static func max_hit(att: Dictionary) -> int:
	return Combat.actor_max_hit(int(att.get("strength", 1)), float(att.get("power", 0.0)), int(att.get("str", 0)))


## Expected damage per tick `att` deals to `vic`.
static func dps(att: Dictionary, vic: Dictionary) -> float:
	return accuracy(att, vic) * (1.0 + max_hit(att)) / 2.0 * Prayer.mult(att.get("prayer", {}), "dmg") / float(Combat.weapon_ticks(str(att.get("weapon", ""))))


## Chance the side `a` (one or more fighters ganging up on b[0]) wins
## against `b` (the defenders; b[0] is the one being attacked, all of b
## hit back at a[0]). Logistic in the ratio of times-to-kill.
static func win_p(a: Array, b: Array) -> float:
	if a.is_empty() or b.is_empty():
		return 0.5
	var da := 0.0
	for x in a:
		da += dps(x, b[0])
	var db := 0.0
	for y in b:
		db += dps(y, a[0])
	var t_a := (float(b[0]["hp"]) + float(b[0].get("heal", 0.0))) / maxf(0.001, da)
	var t_b := (float(a[0]["hp"]) + float(a[0].get("heal", 0.0))) / maxf(0.001, db)
	var k := float(ai_cfg().get("duel_k", 3.0))
	return 1.0 / (1.0 + pow(t_a / maxf(0.001, t_b), k))


# --------------------------------------------------------------- deaths --
static func unit_value(id: String) -> int:
	return GameData.item_value(id)


## Indices of the `n` most valuable units in `ids` (coins never kept; ties
## keep the earlier unit).
static func kept_indices(ids: Array, n: int) -> Array:
	var order := []
	for i in ids.size():
		if str(ids[i]) != GameData.currency:
			order.append(i)
	order.sort_custom(func(x, y): return unit_value(ids[x]) > unit_value(ids[y]) or (unit_value(ids[x]) == unit_value(ids[y]) and x < y))
	return order.slice(0, maxi(0, n))


## What an AI has at risk in a PK zone: worn armour, its weapon and tools,
## carried food and carried coin. [{"id", "src"}], coins.
static func agent_risk(agent: AIAgent) -> Dictionary:
	var units := []
	for sk in agent.tools.keys():       # weapon + gathering tools in hand
		units.append({"id": str(agent.tools[sk]["id"]), "src": "tool:" + str(sk)})
	for slot in agent.gear.keys():
		units.append({"id": str(agent.gear[slot]["id"]), "src": "gear:" + slot})
	var left := int(ai_cfg().get("carry_food", 8))
	for f in AIBrain.FOODS:
		for i in mini(left, agent.stash_count(f)):
			units.append({"id": f, "src": "stash"})
		left -= mini(left, agent.stash_count(f))
	var coins := mini(agent.coins, int(ai_cfg().get("carry_coins", 40)) + int(agent.coins * float(ai_cfg().get("carry_coin_share", 0.05))))
	return {"units": units, "coins": coins}


## Remove lost units from the agent. Returns [lost ids], coins dropped (after fee).
static func strip_agent(agent: AIAgent, risk: Dictionary, skulled: bool) -> Dictionary:
	var units: Array = risk["units"]
	var ids := []
	for u in units:
		ids.append(u["id"])
	var keep := kept_indices(ids, keep_count(skulled))
	var lost := []
	var kept := []
	for i in units.size():
		var u: Dictionary = units[i]
		if i in keep:
			kept.append(u["id"])
			continue
		lost.append(u["id"])
		var src: String = u["src"]
		if src.begins_with("tool:"):
			agent.tools.erase(src.substr(5))
		elif src.begins_with("gear:"):
			agent.gear.erase(src.substr(5))
		else:
			agent.stash_add(u["id"], -1)
	var carried := int(risk["coins"])
	var fee := int(ceil(carried * coin_fee()))
	agent.coins -= carried
	Market.record_sink(fee)
	tally("coin_dropped", carried)
	tally("coin_fee", fee)
	tally("items_dropped", lost.size())
	return {"lost": lost, "kept": kept, "coins": carried - fee, "fee": fee}


## The value of what an agent would drop (for raider target choice: the
## units beyond the kept ones + carried coin).
static func drop_value(agent: AIAgent, skulled: bool) -> float:
	var risk := agent_risk(agent)
	var ids := []
	for u in risk["units"]:
		ids.append(u["id"])
	var keep := kept_indices(ids, keep_count(skulled))
	var v := float(risk["coins"])
	for i in ids.size():
		if not i in keep:
			v += unit_value(ids[i])
	return v


## Same for an actor on screen (player: pack + worn; AI: its agent's kit + pack).
static func actor_drop_value(a, t: int) -> float:
	if a is AIPlayer and a.agent:
		var v := drop_value(a.agent, a.is_skulled(t))
		for sl in a.inventory.slots:
			if sl != null and not GameData.item(sl["id"]).has("tool"):
				v += (1.0 if sl["id"] == GameData.currency else float(unit_value(sl["id"]))) * int(sl["qty"])
		return v
	var ids := []
	var coins := 0
	for sl in a.inventory.slots:
		if sl == null:
			continue
		if sl["id"] == GameData.currency:
			coins += int(sl["qty"])
			continue
		for i in int(sl["qty"]):
			ids.append(sl["id"])
	if "equipment" in a:
		for slot in a.equipment.keys():
			ids.append(a.equipment[slot])
	var keep := kept_indices(ids, keep_count(a.is_skulled(t)))
	var v2 := float(coins)
	for i in ids.size():
		if not i in keep:
			v2 += unit_value(ids[i])
	return v2


## Hand loot straight to an AI killer (abstract deaths, no pile).
static func give_agent(agent: AIAgent, ids: Array, coins: int) -> void:
	for id in ids:
		agent.stash_add(id, 1)
	agent.coins += coins
	tally("coin_looted", coins)
	tally("items_looted", ids.size())
	var v := coins
	for id in ids:
		v += unit_value(id)
	agent.stats["pk_loot"] = int(agent.stats.get("pk_loot", 0)) + v


## Drop a death pile: grouped by id, private to `owner` for `private` ticks.
static func drop_pile(ground, pos: Vector2i, ids: Array, coins: int, owner: String, private: int, t: int) -> void:
	if ground == null:
		return
	var by := {}
	for id in ids:
		by[id] = int(by.get(id, 0)) + 1
	if coins > 0:
		by[GameData.currency] = int(by.get(GameData.currency, 0)) + coins
	var ttl := int(cfg().get("death_pile_ttl", 3000))
	for id in by.keys():
		ground.add(pos, id, int(by[id]), t, ttl, owner, private)


static func pile_owner_and_private(killer, victim_id: String) -> Array:
	if killer != null and is_instance_valid(killer) and killer is Actor:
		return [killer.actor_id, int(cfg().get("killer_private_ticks", 100))]
	return [victim_id, int(cfg().get("npc_kill_private_ticks", 300))]


static func record_kill(killer_agent: AIAgent, victim_agent: AIAgent) -> void:
	if killer_agent:
		killer_agent.stats["pk_kills"] = int(killer_agent.stats.get("pk_kills", 0)) + 1
	if victim_agent:
		victim_agent.stats["pk_deaths"] = int(victim_agent.stats.get("pk_deaths", 0)) + 1
	pk_log_total["kills"] = int(pk_log_total.get("kills", 0)) + 1


## Session-wide PK counters (soak / QA reporting).
static var pk_log_total: Dictionary = {}
static var pk_log: Array = []


static func tally(key: String, n: int) -> void:
	pk_log_total[key] = int(pk_log_total.get(key, 0)) + n


static func log_event(d: Dictionary) -> void:
	pk_log.append(d)
	while pk_log.size() > 300:
		pk_log.pop_front()
