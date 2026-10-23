class_name AdvBrain
extends RefCounted
## 0.3.1 adventurer-class AI players (data/adventurers.json + the personas
## with "class": "adventurer"): they play like a real player.
##  * Train Attack / Strength / Defence / Vitality / Prayer with the same
##    combat formulas (AIBrain.simulate / Actor fights), eat, pray, bank
##    (their stash is the bank), bury bones as they go.
##  * Target choice is generic over data/enemies.json: every enemy kind with
##    camps is scored by XP and loot per tick for THIS agent (Combat.expected_fight),
##    minus food, with travel time, and must be safe for its HP + food and level.
##    New creatures (world track: chickens, wolves, guards, citizens, Scorch
##    camps) are picked up automatically.
##  * Best-in-slot by stats and level requirements per slot; buys the best
##    affordable upgrade from the Exchange, the town shops or your player shop,
##    or commissions a smith in town (paid on delivery).
##  * Sub-types: hero ("Adventurer", PvE, goes north only when strong),
##    raider (PKs in the Scorch: weak / rich-looking targets, gangs up, flees
##    when losing), opportunist (Scorch camps for loot, fights back).
## Abstract PK (agents off screen) is resolved here; on-screen fights are real
## Actor fights (src/actors/ai_player.gd + src/combat/pk_rules.gd).

static var _cfg: Dictionary = {}
static var world = null                 # World (AIDirector.attach)
static var player_ref = null            # Player (main), for raider drift / tests
static var commissions: Array = []      # {"id","buyer","town","item","price","until","tick"}
static var _next_cid := 1
static var counters: Dictionary = {}    # session stats (soak/QA): buys by source, commissions, raids...
static var _cands: Dictionary = {}      # slot -> [item ids] (cache)

const SUBS := ["hero", "raider", "opportunist"]


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open("res://data/adventurers.json", FileAccess.READ)
		if f:
			var p = JSON.parse_string(f.get_as_text())
			if typeof(p) == TYPE_DICTIONARY:
				_cfg = p
	return _cfg


static func reset() -> void:
	commissions.clear()
	_next_cid = 1
	counters.clear()
	_cands.clear()
	estates.clear()
	resets.clear()
	resets_total = 0


static func count(key: String, n: int = 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n


static func is_adv(agent) -> bool:
	return agent != null and str(agent.persona.get("class", "")) == "adventurer"


static func sub(agent) -> String:
	return agent.persona_id()


static func is_raider(agent) -> bool:
	return is_adv(agent) and sub(agent) == "raider"


static func _by_sub(key: String, s: String, def):
	var d = cfg().get(key, {})
	if typeof(d) == TYPE_DICTIONARY:
		return d.get(s, def)
	return d if d != null else def


static func persona_by_id(id: String) -> Dictionary:
	for p in GameData.personas:
		if p["id"] == id:
			return p
	return {}


static func town_pos(tid: String) -> Vector2i:
	if world != null and world is Node and "gen" in world:
		return world.gen.town_center(tid)
	var t: Dictionary = GameData.towns.get(tid, {})
	var s: Array = t.get("spawn", [0, 0])
	return Vector2i(int(s[0]), int(s[1]))


static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# ------------------------------------------------------------------ spawn --
## The adventurer-class population (ids adv_0..), after the 40.
static func spawn_all(director, taken: Dictionary, rng: RandomNumberGenerator) -> void:
	var pop: Dictionary = cfg().get("population", {})
	var i := 0
	for s in SUBS:
		var persona := persona_by_id(s)
		if persona.is_empty():
			continue
		for k in int(pop.get(s, 0)):
			var a := AIAgent.new()
			a.id = "adv_%d" % i
			i += 1
			a.name = director.make_name(taken)
			a.persona = persona
			a.rng.seed = rng.randi()
			a.home_town = director._pick_town(persona.get("home_weights", {}), Market.town_ids)
			a.town = a.home_town
			a.home = town_pos(a.home_town) + Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
			a.pos = a.home
			roll(a, rng)
			a.next_trade_tick = rng.randi_range(1, 60)
			director.records.append(a)


static func roll(a: AIAgent, rng: RandomNumberGenerator) -> void:
	var s := sub(a)
	var range_lv: Array = _by_sub("start", s, [1, 5])
	var lv := rng.randi_range(int(range_lv[0]), int(range_lv[1]))
	for sk in a.skills.xp.keys():
		a.skills.xp[sk] = GameData.xp_for_level(rng.randi_range(1, 4))
	for sk in ["attack", "strength", "defence"]:
		a.skills.xp[sk] = GameData.xp_for_level(clampi(lv + rng.randi_range(-2, 2), 1, GameData.max_level))
	a.skills.xp["vitality"] = GameData.xp_for_level(clampi(maxi(10, lv + rng.randi_range(-1, 3)), 10, GameData.max_level))
	a.skills.xp["prayer"] = GameData.xp_for_level(clampi(int(lv / 2.0) + rng.randi_range(0, 3), 1, GameData.max_level))
	var cr: Array = _by_sub("start_coins", s, [200, 400])
	a.coins = rng.randi_range(int(cr[0]), int(cr[1]))
	var set_name: String = str(_by_sub("start_gear", s, "bronze"))
	var sets: Dictionary = cfg().get("tier_sets", {})
	for tier in [set_name, "bronze"]:
		var pieces: Dictionary = sets.get(tier, {})
		for slot in pieces.keys():
			if current(a, slot) != "":
				continue
			var id: String = pieces[slot]
			if Combat.equip_error(a.skills, id) != "":
				continue
			if slot != "weapon" and s == "hero" and rng.randf() < 0.5:
				continue            # fresh heroes own a weapon and a few pieces, not a set
			a.give_tool(id)
	a.stash_add("cooked_carp", rng.randi_range(8, 14))
	if s != "hero":
		a.stash_add("cooked_eel", rng.randi_range(4, 8))
	a.stash_add("ash_log", rng.randi_range(2, 6))
	a.hp = float(Combat.max_hp(a.skills))
	a.adv = {"start_cb": cb_level(a)}


## Overall fighting level: the mean of Attack, Strength, Defence and Vitality.
## Combat level: the one shared formula (Combat.combat_level, shown in the HUD and on names).
static func cb_level(agent) -> int:
	return Combat.combat_level(agent.skills)


static func is_active_hour(agent: AIAgent, hour: int) -> bool:
	var start := posmod(int(hash(agent.id)), 24)
	return posmod(hour - start, 24) < int(cfg().get("session_hours", 14))


# ---------------------------------------------------------------- targets --
static func camps_of(kind: String) -> Array:
	var out := []
	for c in GameData.camps:
		if str(c.get("enemy", "")) == kind:
			out.append(Vector2i(int(c["at"][0]), int(c["at"][1])))
	return out


## Expected numbers for this agent against one enemy kind.
static func evaluate(agent: AIAgent, kind: String) -> Dictionary:
	var e: Dictionary = GameData.enemies.get(kind, {})
	if e.is_empty():
		return {}
	var fn := AIBrain.fight_numbers(agent, kind)
	var ticks := maxf(1.0, float(fn["ticks"]))
	var dmg := float(fn["damage"])
	var mh := float(AIBrain.agent_max_hp(agent))
	var heal := PkRules.food_heal(agent)
	var lvl := int(e.get("level", 1))
	# safe: one unlucky kill (1.5x the mean damage) can't take a fed-up fighter below half
	# HP; food on hand stretches that (the abstract fight eats as it goes)
	var safe := dmg <= float(cfg().get("safe_damage_share", 0.3)) * mh + float(cfg().get("safe_food_share", 0.5)) * minf(heal, mh) \
		and lvl <= cb_level(agent) + int(cfg().get("level_margin", 6))
	var cc: Dictionary = GameData.combat
	var xp := float(e.get("hp", 5)) * (float(cc.get("damage_xp", 4.0)) + float(cc.get("vitality_xp", 1.4))) + float(fn["def_xp"])
	var loot := DropTable.expected_value(str(e.get("drops", kind)),
		func(id): return (minf(1.0, Market.bounty_left / 20.0) if id == GameData.currency else AIBrain.value(agent, id)))
	var food_p := AIBrain.value(agent, "cooked_carp") / 4.0     # marks per HP healed
	# food only pays for damage beyond what natural regeneration covers
	var eat_rate := maxf(0.0, dmg - float(Combat.SEARCH_TICKS) / Combat.REGEN_TICKS) / ticks   # regen between kills
	return {"kind": kind, "ticks": ticks, "dmg": dmg, "safe": safe, "level": lvl, "xp_rate": xp / ticks, "loot_rate": loot / ticks,
		"cost_rate": eat_rate * food_p, "aggro": int(e.get("aggro", 0))}


## Every (kind, camp) scored for this agent; best first. Only safe ones.
static func rank_targets(agent: AIAgent, now: int = -1) -> Array:
	var s := sub(agent)
	var xw := float(_by_sub("xp_weight", s, 1.0))
	var lw := float(_by_sub("loot_weight", s, 0.5))
	var pk_min := int(_by_sub("scorch_min_level", s, 99))
	var cb := cb_level(agent)
	var xv := float(cfg().get("xp_value", 0.12))      # marks one XP is worth to a player
	var from: Vector2i = agent.pos
	var out := []
	var raiders := 0
	for r in AIDirector.records:
		if is_raider(r) and r.activity.get("type", "") == "raid":
			raiders += 1
	for kind in GameData.enemies.keys():
		if bool(GameData.enemies[kind].get("no_attack", false)):
			continue           # quest animals (Clip Clop) aren't prey
		var ev := evaluate(agent, kind)
		if ev.is_empty() or not bool(ev["safe"]):
			continue
		var base := xw * float(ev["xp_rate"]) * xv + lw * float(ev["loot_rate"]) - float(ev["cost_rate"])
		for camp in camps_of(kind):
			var pk := PkRules.is_pk(camp)
			if pk and (cb < pk_min or now < int(agent.adv.get("avoid_pk_until", -1))):
				continue           # too weak, or just killed there: stay out a while
			var u := base
			if pk:
				u = xw * float(ev["xp_rate"]) * xv + lw * float(ev["loot_rate"]) * float(cfg().get("scorch_loot_bonus", 1.35)) - float(ev["cost_rate"])
				if s != "raider":
					u *= maxf(0.3, 1.0 - 0.08 * raiders)
			var dist := float(cheb(from, camp))
			u *= 600.0 / (600.0 + 2.0 * dist / float(cfg().get("travel_tiles_per_tick", 1.0)))
			out.append({"kind": kind, "camp": camp, "pk": pk, "u": u, "ev": ev, "dist": dist})
	out.sort_custom(func(a, b): return float(a["u"]) > float(b["u"]))
	return out


static func choose(agent: AIAgent, now: int) -> Dictionary:
	var dur := agent.rng.randi_range(AIBrain.ACTIVITY_MIN, AIBrain.ACTIVITY_MAX)
	if not is_active_hour(agent, Market.game_hour()):
		return {"type": "rest", "until": now + Market.TICKS_PER_GAME_HOUR}
	if agent.hp >= 0.0 and agent.hp < AIBrain.agent_max_hp(agent) * 0.5 and AIBrain.food_count(agent) == 0:
		return {"type": "rest", "until": now + 200}    # hurt and no food: heal up in town first
	agent.adv["bis"] = bis(agent)
	if is_raider(agent) and cb_level(agent) >= int(cfg().get("raid_min_level", 12)) and not agent.tools.get("melee", {}).is_empty() \
			and agent.rng.randf() < float(cfg().get("raid_share", 0.65)) and not PkRules.zones().is_empty():
		var spot := PkRules.random_spot(agent.rng, world)
		var d := cheb(agent.pos, spot)
		agent.adv["target"] = "raid"
		count("raids_started")
		return {"type": "raid", "skill": "attack", "spot": [spot.x, spot.y], "arrive": now + d, "until": now + d + dur}
	var ranked := rank_targets(agent, now)
	if ranked.is_empty():
		# nothing safe at all: train on the weakest creature there is
		var weakest := ""
		var lo := 1 << 30
		for kind in GameData.enemies.keys():
			if int(GameData.enemies[kind].get("level", 1)) < lo and not camps_of(kind).is_empty():
				lo = int(GameData.enemies[kind].get("level", 1))
				weakest = kind
		if weakest == "":
			return {"type": "rest", "until": now + dur}
		ranked = [{"kind": weakest, "camp": camps_of(weakest)[0], "pk": PkRules.is_pk(camps_of(weakest)[0]), "dist": float(cheb(agent.pos, camps_of(weakest)[0]))}]
	# a little noise between near-equal options (players differ)
	var pick: Dictionary = ranked[0]
	if ranked.size() > 1 and agent.rng.randf() < 0.2 and float(ranked[1]["u"]) > float(ranked[0]["u"]) * 0.85:
		pick = ranked[1]
	var camp: Vector2i = pick["camp"]
	agent.adv["target"] = pick["kind"]
	agent.adv["target_pk"] = bool(pick["pk"])
	var hist: Dictionary = agent.adv.get("targets", {})
	hist[pick["kind"]] = int(hist.get(pick["kind"], 0)) + 1
	agent.adv["targets"] = hist
	return {"type": "fight", "skill": "attack", "kind": pick["kind"], "camp": [camp.x, camp.y], "pk": bool(pick["pk"]),
		"arrive": now + int(pick["dist"]), "until": now + int(pick["dist"]) + dur}


## Where an adventurer stands for its activity (every tier): the camp / raid spot.
static func place(agent: AIAgent) -> bool:
	if not is_adv(agent):
		return false
	var a := agent.activity
	var key := "camp" if a.has("camp") else ("spot" if a.has("spot") else "")
	if key == "":
		agent.pos = agent.home
		return true
	var p := Vector2i(int(a[key][0]), int(a[key][1]))
	if world != null:
		var q := p + Vector2i(agent.rng.randi_range(-3, 3), agent.rng.randi_range(-3, 3))
		# 0.3.16 off-screen camps: don't generate chunk data just to pick a free tile
		if not ("chunks" in world) or world.chunks.has(World.chunk_of(q)):
			p = world.find_free_tile_near(q, 6)
	agent.pos = p
	return true


## What an adventurer keeps stocked (AIBrain.keep_list): fighting food (eel
## too for Scorch-goers), logs for the fire; no bones (it buries its own).
static func keep_list(agent: AIAgent) -> Dictionary:
	var own := agent.stash_count("cooked_rat_meat") + agent.stash_count("cooked_eel")
	var k := {"cooked_carp": maxi(0, int(cfg().get("food_keep", 14)) - own)}
	if sub(agent) != "hero" or cb_level(agent) >= int(_by_sub("scorch_min_level", "hero", 28)):
		k["cooked_eel"] = 6
	return k


## 0.3.1 churches (world track): World.nearest_altar(tile) -> altar or null.
## An adventurer or acolyte in town with a church tops its Prayer up at the
## altar (no XP; XP still comes from bones). Guarded: no-op until the world
## track's hook exists.
static func altar_near(agent: AIAgent):
	if world == null or not is_instance_valid(world) or not world.has_method("nearest_altar"):
		return null
	var c: Vector2i = town_pos(agent.town)
	var alt = world.call("nearest_altar", c, agent.town) if _altar_takes_town() else world.call("nearest_altar", c)
	if alt == null or (alt is Dictionary and (alt as Dictionary).is_empty()):
		return null
	var at: Vector2i = c
	if alt is Vector2i:
		at = alt
	elif alt is Dictionary:
		at = alt.get("pos", c)
	elif alt is Object and "pos" in alt:
		at = alt.pos
	return alt if cheb(at, c) <= 60 else null


## World.nearest_altar(from, town) (world track) vs a one-argument hook.
static func _altar_takes_town() -> bool:
	for m in world.get_method_list():
		if str(m.get("name", "")) == "nearest_altar":
			return (m.get("args", []) as Array).size() >= 2
	return false


static func visit_altar(agent: AIAgent) -> bool:
	if not (is_adv(agent) or agent.persona_id() == "acolyte" or AIBrain.is_fighter(agent)) or agent.trip.has("to"):
		return false
	var plv := agent.skills.level("prayer")
	if Prayer.points(agent.prayer, plv) >= Prayer.max_points(plv) * 0.8:
		return false
	if altar_near(agent) == null:
		return false
	Prayer.restore(agent.prayer, plv, 1.0)
	count("altar_visits")
	return true


## After an abstract fight chunk: bury the bones (Prayer XP), like a player does.
## Like a player past the early levels, an adventurer leaves low-value drops
## lying (ore, logs, cheap bars) once its level makes them not worth the bank
## space: keep a drop if it's food, bones, or worth >= loot_min_value_per_cb x
## combat level (data/adventurers.json). Non-adventurers keep everything.
static func loot_wanted(agent: AIAgent, item: String, qty: int) -> bool:
	if not is_adv(agent) or item in AIBrain.FOODS or item == "bones" or item.begins_with("raw_"):
		return true
	var v := float(AIBrain.value(agent, item)) * qty
	if v >= float(cfg().get("loot_min_value_per_cb", 0.0)) * cb_level(agent):
		return true
	count("loot_left", qty)
	return false


static func after_fight(agent: AIAgent) -> void:
	var guard := 0
	while agent.stash_count("bones") > 0 and guard < 200:
		AIBrain.bury_one(agent)
		guard += 1
	# cook what it caught for its own lunch (the cheapest food there is)
	for r in GameData.recipes:
		if str(r.get("skill", "")) != "cooking" or agent.skills.level("cooking") < int(r.get("level", 1)) or r["in"].size() != 1:
			continue
		var out_id: String = r["out"].keys()[0]
		if not out_id in AIBrain.FOODS:
			continue
		var fp := AIBrain.fail_p(agent, r)
		var raw: String = r["in"].keys()[0]
		while agent.stash_count(raw) > 0 and guard < 400:
			guard += 1
			agent.stash_add(raw, -1)
			if agent.rng.randf() < fp:
				agent.skills.add_xp("cooking", Interactions.fail_xp(r))
			else:
				agent.stash_add(out_id, 1)
				agent.skills.add_xp("cooking", int(r.get("xp", 0)))


# ------------------------------------------------------------------- gear --
static func slot_of(id: String) -> String:
	var gd: Dictionary = GameData.item(id).get("gear", {})
	var slot := str(gd.get("slot", ""))
	if slot == "weapon" and str(gd.get("style", "")) != "melee":
		return ""
	return slot if slot in cfg().get("slots", []) else ""


static func current(agent: AIAgent, slot: String) -> String:
	if slot == "weapon":
		var w: Dictionary = agent.tools.get("melee", {})
		return str(w["id"]) if not w.is_empty() else ""
	var g: Dictionary = agent.gear.get(slot, {})
	return str(g["id"]) if not g.is_empty() else ""


static func score(agent: AIAgent, id: String, slot: String) -> float:
	if id == "":
		return -1.0
	if slot == "weapon":
		return AIBrain.weapon_score(agent, id)
	var gd: Dictionary = GameData.item(id).get("gear", {})
	return float(gd.get("def", 0)) + 0.1 * float(gd.get("tier", 0))


static func candidates(slot: String) -> Array:
	if not _cands.has(slot):
		var out := []
		for id in GameData.items.keys():
			if slot_of(id) == slot:
				out.append(id)
		_cands[slot] = out
	return _cands[slot]


## Best-in-slot this agent may wear now (stats + level requirements; price ignored).
static func bis(agent: AIAgent) -> Dictionary:
	var out := {}
	for slot in cfg().get("slots", []):
		var best := ""
		var bs := -1.0
		for id in candidates(slot):
			if Combat.equip_error(agent.skills, id) != "":
				continue
			var sc := score(agent, id, slot)
			if sc > bs:
				bs = sc
				best = id
		out[slot] = best
	return out


## Highest gear tier the agent wears (0 = none) and the mean over the 5 slots.
static func gear_tier(agent: AIAgent) -> Dictionary:
	var hi := 0
	var sum := 0.0
	for slot in cfg().get("slots", []):
		var id := current(agent, slot)
		var t := int(GameData.item(id).get("gear", {}).get("tier", 0)) if id != "" else 0
		hi = maxi(hi, t)
		sum += t
	return {"max": hi, "mean": sum / maxf(1.0, cfg().get("slots", []).size())}


## Buy one now from the Exchange at up to `limit`: place, take what filled,
## cancel the rest. Returns units got.
static func buy_now(agent: AIAgent, item: String, qty: int, limit: int) -> int:
	var m := AIBrain.mk(agent)
	var had := agent.stash_count(item)
	if not AIBrain.place_buy(agent, item, qty, limit):
		return 0
	for oid in agent.my_orders.keys().duplicate():
		var o: Dictionary = agent.my_orders[oid]
		if str(o["item"]) == item and bool(o["buy"]) and str(o.get("town", agent.town)) == agent.town:
			if not m.orders.has(oid) or m.cancel_order(oid, true):
				agent.my_orders.erase(oid)
	AIBrain.collect(agent)
	return agent.stash_count(item) - had


## Buy one unit of `id` from quote q ([price, source, avail, stand]). Into the stash.
static func buy_from(agent: AIAgent, id: String, q: Array) -> bool:
	var m := AIBrain.mk(agent)
	var src := str(q[1])
	var price := int(q[0])
	if price > agent.coins:
		return false
	match src:
		"exchange":
			if buy_now(agent, id, 1, price) <= 0:
				return false
		"player":
			var ps := Market.player_shop(agent.town)
			var cost := ps.ai_buy(agent.id, int(q[3]), 1)
			if cost <= 0:
				return false
			agent.coins -= cost
			agent.stash_add(id, 1)
			AIBrain.note_shop_visit(agent, "player")
		"":
			return false
		_:
			var cost2 := m.shop_sell_to(src, id, 1)
			if cost2 <= 0:
				return false
			agent.coins -= cost2
			agent.stash_add(id, 1)
			AIBrain.note_shop_visit(agent, src)
	count("buy_" + src)
	var log: Array = agent.adv.get("buys", [])
	log.append([id, src, price])
	agent.adv["buys"] = log.slice(maxi(0, log.size() - 12))
	return true


## The trading-round gear step: for each slot, the best affordable upgrade
## from any source in town; if the best upgrade isn't for sale anywhere here,
## commission a smith. Then wear what's best.
static func gear_trade(agent: AIAgent, now: int) -> void:
	AIBrain.equip_from_stash(agent)
	# shopping round at most every gear_check_ticks unless levels / coin moved a lot
	var key := cb_level(agent) * 1000 + int(log(maxf(1.0, agent.coins)) * 4.0)
	if now < int(agent.adv.get("gear_next", 0)) and key == int(agent.adv.get("gear_key", -1)):
		return
	agent.adv["gear_next"] = now + int(cfg().get("gear_check_ticks", 400))
	agent.adv["gear_key"] = key
	var m := AIBrain.mk(agent)
	var budget := int(agent.coins * float(cfg().get("gear_budget_share", 0.7)))
	for slot in cfg().get("slots", []):
		var cur := current(agent, slot)
		var cur_s := score(agent, cur, slot)
		var opts := []
		for id in candidates(slot):
			if Combat.equip_error(agent.skills, id) != "" or agent.stash_count(id) > 0:
				continue
			var sc := score(agent, id, slot)
			if sc > cur_s * 1.02 + 0.001:
				opts.append([sc, id])
		if opts.is_empty():
			continue
		opts.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		var bought := false
		for o in opts:
			var q := AIBrain.buy_quote(m, o[1])
			if str(q[1]) == "" or int(q[0]) > budget:
				continue
			if buy_from(agent, o[1], q):
				budget -= int(q[0])
				bought = true
				break
		if bought or has_commission(agent.id, slot):
			continue
		for o in opts:
			var r := recipe_for(o[1])
			var price := int(ceil(m.reference_price(o[1]) * float(cfg().get("commission_premium", 1.2))))
			if not r.is_empty() and price <= budget and str(AIBrain.buy_quote(m, o[1])[1]) == "":
				post_commission(agent, o[1], price, now)
				break
	AIBrain.equip_from_stash(agent)


static func recipe_for(item: String) -> Dictionary:
	for r in GameData.recipes:
		if r["out"].has(item):
			return r
	return {}


static func has_commission(buyer: String, slot: String) -> bool:
	for c in commissions:
		if c["buyer"] == buyer and slot_of(c["item"]) == slot:
			return true
	return false


static func post_commission(agent: AIAgent, item: String, price: int, now: int) -> void:
	commissions.append({"id": _next_cid, "buyer": agent.id, "town": agent.town, "item": item, "price": price,
		"until": now + int(cfg().get("commission_ticks", 1200)), "tick": now})
	_next_cid += 1
	count("commissions_posted")


static func find_agent(id: String) -> AIAgent:
	for a in AIDirector.records:
		if a.id == id:
			return a
	return null


## A smith in town works through the commission board: it forges an ordered
## piece it has the level for (from its stash, buying missing bars if that
## still leaves a profit) and is paid on delivery (coins move agent to agent).
static func smith_fill(smith: AIAgent, now: int) -> void:
	var m := AIBrain.mk(smith)
	for c in commissions.duplicate():
		if now > int(c["until"]):
			commissions.erase(c)
			count("commissions_expired")
			continue
		if str(c["town"]) != smith.town or str(c["buyer"]) == smith.id:
			continue
		var r := recipe_for(c["item"])
		var stocked := bool(GearEconomy.cfg().get("commission_from_stock", true)) and smith.stash_count(c["item"]) > 0
		if r.is_empty() or (smith.skills.level(r["skill"]) < int(r.get("level", 1)) and not stocked):
			continue
		var buyer := find_agent(c["buyer"])
		if buyer == null or buyer.coins < int(c["price"]):
			commissions.erase(c)
			continue
		var from_stock := stocked
		if from_stock:
			smith.stash_add(c["item"], -1)          # 0.3.1: sell finished stock before forging more
			count("commissions_from_stock")
		elif not smith.has_inputs(r["in"]):
			var spend := 0
			for k in r["in"].keys():
				var need := int(r["in"][k]) - smith.stash_count(k)
				if need <= 0:
					continue
				var q := AIBrain.buy_quote(m, k, false)
				if str(q[1]) == "" or int(q[0]) * need + spend > int(int(c["price"]) * 0.85) or int(q[0]) * need > smith.coins:
					break
				if str(q[1]) == "exchange":
					buy_now(smith, k, need, int(q[0]))
				else:
					var cost := m.shop_cost(q[1], k, need)
					if cost <= smith.coins and m.shop_sell_to(q[1], k, need) > 0:
						smith.coins -= cost
						smith.stash_add(k, need)
				spend += int(q[0]) * need
			if not smith.has_inputs(r["in"]):
				continue
		if not from_stock:
			for k in r["in"].keys():
				smith.stash_add(k, -int(r["in"][k]))
			smith.skills.add_xp(r["skill"], int(r.get("xp", 0)))
			smith.stats["made"] = int(smith.stats.get("made", 0)) + 1
		smith.stats["commissions"] = int(smith.stats.get("commissions", 0)) + 1
		buyer.coins -= int(c["price"])
		smith.coins += int(c["price"])
		buyer.stash_add(c["item"], 1)
		AIBrain.equip_from_stash(buyer)
		commissions.erase(c)
		count("commissions_filled")
		var log: Array = buyer.adv.get("buys", [])
		log.append([c["item"], "commission:" + smith.id, int(c["price"])])
		buyer.adv["buys"] = log.slice(maxi(0, log.size() - 12))


# ------------------------------------------------------- abstract PK -----
static func _skulled(a: AIAgent, t: int) -> bool:
	return t < a.skull_until


## Off-screen Scorch encounters (every 50 ticks): raiders on a raid pick the
## best weak / rich-looking target among agents in the zone (not other
## raiders), maybe with a gang; the target may run; the fight resolves by the
## duel odds; the loser dies under the PK death rules and the winner takes
## the drop. On-screen (tier 0) agents fight for real instead.
static func raid_tick(t: int, records: Array) -> void:
	var ac := PkRules.ai_cfg()
	var raiders := []
	var pool := []
	for a in records:
		if a.tier == 0 or a.trip.has("to") or not PkRules.is_pk(a.pos):
			continue
		if t < int(a.activity.get("arrive", 0)) or a.activity.get("type", "rest") == "rest":
			continue
		if is_raider(a):
			if a.activity.get("type", "") == "raid":
				raiders.append(a)
		else:
			pool.append(a)
	if raiders.is_empty():
		return
	var busy := {}
	for r in raiders:
		if busy.has(r.id) or r.rng.randf() >= float(ac.get("raid_encounter_chance", 0.35)):
			continue
		var best: AIAgent = null
		var best_s := 0.0
		var rs := PkRules.agent_stats(r)
		for v in pool:
			if busy.has(v.id):
				continue
			var p := PkRules.win_p([rs], [PkRules.agent_stats(v)])
			if p < float(ac.get("min_win_p", 0.6)):
				continue
			var sc := (PkRules.drop_value(v, _skulled(v, t)) + 10.0) * p
			if sc > best_s:
				best_s = sc
				best = v
		if best == null:
			continue
		var gang: Array = [r]
		for r2 in raiders:
			if r2 != r and not busy.has(r2.id) and cheb(r2.pos, r.pos) < 60 and r2.rng.randf() < float(ac.get("gang_join_chance", 0.5)):
				gang.append(r2)
		for g in gang:
			busy[g.id] = true
		busy[best.id] = true
		resolve(gang, best, t)


## One abstract PvP fight: `gang` attacked `victim`.
static func resolve(gang: Array, victim: AIAgent, t: int) -> Dictionary:
	var ac := PkRules.ai_cfg()
	var gs := []
	for g in gang:
		gs.append(PkRules.agent_stats(g))
	var vs := PkRules.agent_stats(victim)
	var p := PkRules.win_p(gs, [vs])
	var st := PkRules.skull_ticks()
	for g in gang:
		if not _skulled(g, t):
			g.skull_until = t + st          # they struck first
	count("pk_fights")
	var fc: Dictionary = ac.get("flee_chance", {})
	var flee := float(fc.get(sub(victim) if is_adv(victim) else "default", fc.get("default", 0.7)))
	var res := {"tick": t, "kind": "abstract", "gang": gang.map(func(g): return g.id), "victim": victim.id, "p": snappedf(p, 0.01)}
	# the victim sees it's losing and runs for the edge of the zone
	if p > 0.5 and victim.rng.randf() < flee * p:
		victim.hp = maxf(1.0, float(vs["hp"]) - PkRules.dps(gs[0], vs) * 6.0)
		victim.activity = {"type": "rest", "until": t + 300}
		victim.pos = victim.home
		victim.stats["pk_escapes"] = int(victim.stats.get("pk_escapes", 0)) + 1
		count("pk_escapes")
		res["result"] = "escaped"
		PkRules.log_event(res)
		return res
	var gang_wins: bool = (gang[0] as AIAgent).rng.randf() < p
	var winner: AIAgent = gang[0] if gang_wins else victim
	var loser: AIAgent = victim if gang_wins else gang[0]
	# the winner is hurt in proportion to how close it was
	var w_hp := float(PkRules.agent_stats(winner)["hp"])
	winner.hp = maxf(1.0, w_hp * clampf(0.35 + 0.6 * absf(p - 0.5) * 2.0, 0.3, 0.95))
	var won_vs: float = float(vs["max_hp"]) if gang_wins else float(gs[0]["max_hp"])
	Combat.award_hit_xp(winner.skills, AIBrain.ai_style(winner), int(won_vs))
	winner.skills.add_xp("defence", int(won_vs))
	PkRules.record_kill(winner, loser)        # before the loser's slot goes to a new player
	var loser_id := loser.id
	var drop := pk_death(loser, t)
	PkRules.give_agent(winner, drop["lost"], int(drop["coins"]))
	AIBrain.equip_from_stash(winner)
	if gang_wins:
		count("raider_kills")
		for g in gang.slice(1):
			g.stats["pk_assists"] = int(g.stats.get("pk_assists", 0)) + 1
	else:
		count("raider_deaths")
		for g in gang.slice(1):
			g.activity = {"type": "rest", "until": t + 200}    # the gang scatters
			g.pos = g.home
	res["result"] = "gang_won" if gang_wins else "victim_won"
	res["winner"] = winner.id
	res["loser"] = loser_id
	res["value"] = int(drop["coins"]) + drop["lost"].reduce(func(acc, id): return acc + PkRules.unit_value(id), 0)
	res["kept"] = drop["kept"]
	PkRules.log_event(res)
	return res


## Abstract PK death: keep-3 (0 if skulled), the rest is the killer's.
## Respawn in the home town at full HP, rest a while. Returns the drop.
static func pk_death(loser: AIAgent, t: int) -> Dictionary:
	var drop := PkRules.strip_agent(loser, PkRules.agent_risk(loser), _skulled(loser, t))
	pk_respawn(loser, t)
	return drop


## After a PK-zone death (carried items already stripped): the character
## quits and a new level-1 player takes the slot (reincarnate). With
## new_players off (data/pk.json ai.new_players = false) the old behaviour:
## back in the home town at full HP, unskulled, staying out a while.
static func pk_respawn(loser: AIAgent, t: int) -> void:
	if bool(PkRules.ai_cfg().get("new_players", true)):
		reincarnate(loser, t)
		return
	loser.hp = float(AIBrain.agent_max_hp(loser))
	loser.stats["deaths"] = int(loser.stats.get("deaths", 0)) + 1
	loser.town = loser.home_town
	loser.trip = {}
	loser.activity = {"type": "rest", "until": t + 300}
	loser.pos = loser.home
	loser.skull_until = -1
	loser.prayer.erase("id")
	if not is_raider(loser):
		loser.adv["avoid_pk_until"] = t + int(cfg().get("pk_death_cooldown", 2400))


# ------------------------------------------------- 0.3.1 new players ------
## Session log of characters that quit after a Scorch death (soak / QA).
static var resets: Array = []
static var resets_total := 0
## Estate sales in progress: {"id": "estate:<old id>", "town", "left": {item: qty}, "until", "coins", "sold"}
static var estates: Array = []


## The AI killed in the Scorch quits; a NEW player takes its population slot:
## new id / name / look, persona re-rolled within its class, home re-rolled by
## the persona's home weights, every skill at a new player's level, the
## starter kit and ~25 marks. What the old character still owned (its bank,
## the kept items, open orders) goes to an estate sale on the Exchange whose
## proceeds vanish (a sink); its coin vanishes too (a sink).
static func reincarnate(a: AIAgent, t: int) -> void:
	var old := {"id": a.id, "name": a.name, "persona": a.persona_id(), "cb": cb_level(a), "total": a.skills.total_level(), "tick": t,
		"coins": a.coins, "gen": a.gen}
	# 1. settle the old character: pull its orders + boxes (every town), drop its commissions
	for tid in Market.town_ids:
		var m: TownMarket = Market.town(tid)
		for o in m.open_orders_of(a.id):
			m.cancel_order(int(o["id"]), true)
		var box := m.collect(a.id)
		a.coins += int(box.get("coins", 0))
		var bi: Dictionary = box.get("items", {})
		for k in bi.keys():
			a.stash_add(k, int(bi[k]))
	a.my_orders.clear()
	for c in commissions.duplicate():
		if str(c["buyer"]) == a.id:
			commissions.erase(c)
	# 2. estate sale: bank + whatever it kept (tools, worn gear)
	var left := {}
	for k in a.stash.keys():
		if int(a.stash[k]) > 0:
			left[k] = int(left.get(k, 0)) + int(a.stash[k])
	for sk in a.tools.keys():
		left[a.tools[sk]["id"]] = int(left.get(a.tools[sk]["id"], 0)) + 1
	for sl in a.gear.keys():
		left[a.gear[sl]["id"]] = int(left.get(a.gear[sl]["id"], 0)) + 1
	var units := 0
	for k in left.keys():
		units += int(left[k])
	if not left.is_empty():
		estates.append({"id": "estate:" + a.id, "town": a.town if a.town in Market.town_ids else a.home_town, "left": left,
			"until": t + int(PkRules.ai_cfg().get("estate_ticks", 7200)), "coins": 0, "sold": 0, "units": units})
	Market.record_sink(a.coins)                 # the old character's purse leaves the game
	count("reset_coins_sunk", a.coins)
	count("estate_units", units)
	# 3. the new player
	var cls := str(a.persona.get("class", ""))
	if cls == "adventurer":
		# class weights (population), plus a pull toward sub-types that are now short, so a
		# sub-type that dies a lot in the Scorch (opportunists) is not slowly bred out
		var pop: Dictionary = cfg().get("population", {})
		var have := {}
		for o in AIDirector.records:
			if o != a and is_adv(o):
				have[sub(o)] = int(have.get(sub(o), 0)) + 1
		var w := {}
		var tot := 0
		for k in SUBS:
			w[k] = int(pop.get(k, 0)) + int(cfg().get("reroll_refill_weight", 4)) * maxi(0, int(pop.get(k, 0)) - int(have.get(k, 0)))
			tot += int(w[k])
		var r := a.rng.randi_range(1, maxi(1, tot))
		for k in SUBS:
			r -= int(w[k])
			if r <= 0:
				var pp := persona_by_id(k)
				if not pp.is_empty():
					a.persona = pp
				break
	var base := a.id.split("~")[0]
	a.gen += 1
	a.id = "%s~%d" % [base, a.gen]
	var taken := {}
	for r2 in AIDirector.records:
		taken[r2.name] = true
	a.name = AIDirector.make_name(taken)
	var col := Color(str(a.persona.get("tint", "#ffffff")))
	col = Color.from_hsv(fposmod(col.h + a.rng.randf_range(-0.08, 0.08), 1.0), clampf(col.s * a.rng.randf_range(0.7, 1.3), 0.0, 1.0), clampf(col.v * a.rng.randf_range(0.85, 1.1), 0.3, 1.0))
	a.tint = col.to_html(false)
	a.home_town = AIDirector._pick_town(a.persona.get("home_weights", {}), Market.town_ids)
	a.town = a.home_town
	a.home = town_pos(a.home_town) + Vector2i(a.rng.randi_range(-12, 12), a.rng.randi_range(-12, 12))
	a.pos = a.home
	var fresh := Skills.new()
	for sk in fresh.xp.keys():
		a.skills.xp[sk] = int(fresh.xp[sk])
	a.stash.clear()
	a.tools.clear()
	a.gear.clear()
	for id in PkRules.ai_cfg().get("starter_kit", ["bronze_hatchet", "bronze_pick", "reed_rod", "bronze_sword"]):
		if GameData.items.has(id):
			a.give_tool(id)
	a.coins = int(PkRules.ai_cfg().get("starter_coins", 25))
	Market.record_faucet(a.coins)
	a.memo.clear()
	a.frac.clear()
	a.hunger = 0.0
	a.stats = {"earned": 0, "spent": 0, "made": 0, "gathered": 0, "trades": 0}
	a.adv = {"start_cb": cb_level(a), "born": t} if is_adv(a) else {}
	a.hp = float(AIBrain.agent_max_hp(a))
	a.trip = {}
	a.activity = {"type": "rest", "until": t + 300}
	a.skull_until = -1
	a.prayer.clear()
	a.next_trade_tick = t + 20
	resets_total += 1
	count("resets")
	old["new_id"] = a.id
	old["new_name"] = a.name
	old["new_persona"] = a.persona_id()
	resets.append(old)
	while resets.size() > 200:
		resets.pop_front()
	PkRules.log_event({"tick": t, "kind": "new_player", "old": old["name"], "new": a.name, "persona": a.persona_id(), "estate_units": units})


## Every 100 ticks: list estate goods on the Exchange (a little under the
## reference price), sweep sale proceeds out of the game (sink), relist what
## expired. After `until` whatever is left is given up (destroyed).
static func estate_tick(t: int) -> void:
	for e in estates.duplicate():
		var m: TownMarket = Market.town(str(e["town"]))
		if m == null:
			estates.erase(e)
			continue
		var box := m.collect(str(e["id"]))
		var c := int(box.get("coins", 0))
		if c > 0:
			Market.record_sink(c)
			e["coins"] = int(e["coins"]) + c
			count("estate_coins_sunk", c)
		var back: Dictionary = box.get("items", {})
		var left: Dictionary = e["left"]
		for k in back.keys():
			left[k] = int(left.get(k, 0)) + int(back[k])
		if t >= int(e["until"]):
			for o in m.open_orders_of(str(e["id"])):
				m.cancel_order(int(o["id"]), true)
			var box2 := m.collect(str(e["id"]))
			if int(box2.get("coins", 0)) > 0:
				Market.record_sink(int(box2["coins"]))
			var gone := 0
			for k in left.keys():
				gone += int(left[k])
			for k in box2.get("items", {}).keys():
				gone += int(box2["items"][k])
			count("estate_units_unsold", gone)
			estates.erase(e)
			continue
		for k in left.keys().duplicate():
			var q := int(left[k])
			if q <= 0:
				left.erase(k)
				continue
			if not m.tradeable(k):
				left.erase(k)
				count("estate_units_untradeable", q)
				continue
			if GearEconomy.is_wearable(k) and GearEconomy.is_surplus_market(m, k):
				left.erase(k)                       # 0.3.1: glutted gear is scrapped, not dumped on the Exchange
				count("estate_units_scrapped", q)
				continue
			if m.open_count(str(e["id"])) >= TownMarket.MAX_OPEN_ORDERS_PER_TRADER:
				break
			var band := m.price_band(k)
			var price := clampi(int(round(m.reference_price(k) * float(PkRules.ai_cfg().get("estate_price", 0.9)))), band.x, band.y)
			var qq := mini(q, mini(TownMarket.MAX_ORDER_QTY, maxi(1, m.daily_cap(k) - int(m.trader_day_vol.get(str(e["id"]) + "|" + k, 0)))))
			var res := m.place_order(str(e["id"]), k, qq, price, false)
			if bool(res.get("ok", false)):
				left[k] = q - qq
				e["sold"] = int(e["sold"]) + qq
				if int(left[k]) <= 0:
					left.erase(k)
		if left.is_empty() and m.open_count(str(e["id"])) == 0 and m.pending(str(e["id"])).get("coins", 0) == 0:
			estates.erase(e)


## A creature killed an agent inside a PK zone (abstract): the keep-3 rule
## still applies; nobody is there to take the drop, so it is lost (a sink).
static func npc_pk_death(agent: AIAgent, t: int) -> void:
	var drop := pk_death(agent, t)
	count("pk_npc_deaths")
	count("pk_npc_items_lost", drop["lost"].size())


## Tier-1 raiders on a raid drift toward you when you are in the Scorch
## (so they get on screen and hunt you for real).
static func drift(a: AIAgent, player_tile: Vector2i, t: int) -> void:
	if not is_raider(a) or a.activity.get("type", "") != "raid" or not PkRules.is_pk(player_tile) or t < int(a.activity.get("arrive", 0)):
		return
	if cheb(a.pos, player_tile) > 160 or a.rng.randf() >= float(PkRules.ai_cfg().get("drift_to_player", 0.25)):
		return
	var d := player_tile - a.pos
	var step := Vector2i(clampi(d.x, -10, 10), clampi(d.y, -10, 10))
	var np := a.pos + step
	if PkRules.is_pk(np):
		a.pos = np


# ------------------------------------------------------------------- save --
static func to_save() -> Dictionary:
	return {"commissions": commissions.duplicate(true), "next_cid": _next_cid, "estates": estates.duplicate(true), "resets_total": resets_total,
		"resets": resets.slice(maxi(0, resets.size() - 50))}


static func from_save(d: Dictionary) -> void:
	commissions.clear()
	for c in d.get("commissions", []):
		var c2: Dictionary = c.duplicate()
		for k in ["id", "price", "until", "tick"]:
			c2[k] = int(c2.get(k, 0))
		commissions.append(c2)
	_next_cid = int(d.get("next_cid", commissions.size() + 1))
	estates.clear()
	for e in d.get("estates", []):
		var e2: Dictionary = e.duplicate(true)
		for k in ["until", "coins", "sold", "units"]:
			e2[k] = int(e2.get(k, 0))
		var l2 := {}
		for k in e2.get("left", {}).keys():
			l2[k] = int(e2["left"][k])
		e2["left"] = l2
		estates.append(e2)
	resets_total = int(d.get("resets_total", 0))
	resets = d.get("resets", []).duplicate(true)


# ---------------------------------------------------------------- reports --
## One line per adventurer (soak / debug).
static func snapshot(agent: AIAgent) -> Dictionary:
	var gear := {}
	for slot in cfg().get("slots", []):
		gear[slot] = current(agent, slot)
	var gt := gear_tier(agent)
	return {"id": agent.id, "name": agent.name, "sub": sub(agent), "cb": cb_level(agent),
		"attack": agent.skills.level("attack"), "strength": agent.skills.level("strength"), "defence": agent.skills.level("defence"),
		"vitality": agent.skills.level("vitality"), "prayer": agent.skills.level("prayer"), "coins": agent.coins,
		"gear": gear, "tier_max": gt["max"], "tier_mean": snappedf(float(gt["mean"]), 0.01), "target": str(agent.adv.get("target", "")),
		"kills": int(agent.stats.get("kills", 0)), "deaths": int(agent.stats.get("deaths", 0)),
		"pk_kills": int(agent.stats.get("pk_kills", 0)), "pk_deaths": int(agent.stats.get("pk_deaths", 0)), "pk_loot": int(agent.stats.get("pk_loot", 0))}
