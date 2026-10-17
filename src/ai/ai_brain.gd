class_name AIBrain
extends RefCounted
## Decision making for AI players, shared by every simulation tier.
##  * choose(): utility = expected marks/tick x persona weight x glut x noise,
##    using the agent's LOCAL town prices, so regional supply and demand steer
##    what agents do.
##  * simulate(): abstract production for agents that are not on screen.
##  * trade(): local order-book behaviour (collect, reprice, buy needs and gear,
##    sell surplus, dump to the store floor).
##  * trader_*(): travelling traders buy where an item is cheap, walk the road
##    to a town where it is dear and sell there (arbitrage with travel time).

const EFF_GATHER := 0.3         # abstract: walking/banking/chatting overhead
const EFF_CRAFT := 0.6
const RESERVATION := 0.06       # marks/tick below which an agent would rather rest
const ACTIVITY_MIN := 300
const ACTIVITY_MAX := 900
const FOCUS_WEIGHTS := [1.0, 0.85]
const OTHER_WEIGHT := 0.35
const KILL_TICKS := 30.0
const FOODS := ["cooked_eel", "cooked_beef", "bread", "cooked_carp", "cooked_rat_meat", "cooked_chicken"]
const FLEE_AT := 0.35            # share of max HP: no food left -> run
const EAT_AT := 0.5
const DEATH_COIN_FEE := 0.10     # same penalty as the player: the healer keeps 10 % of coin
const PRAY_UTILITY := 0.3        # acolytes value burying bones like paid work
const FUELS := ["ash_log", "alder_log", "blackthorn_log"]
const DAILY_FOOD := 3
const DAILY_FUEL := 3
const INN_COST := 6
const DUMP_AT := 120
const DUMP_KEEP := 60
const MULT_MIN := 0.88
const MULT_MAX := 1.12
const UPKEEP_FLAT := 8
const UPKEEP_RATE := 0.02
const UPKEEP_FREE := 400
const SESSION_HOURS := 8
const GLUT_AT := 40
const GLUT_VALUE := 500.0     # marks of one item in the stash before production slows
const ARMOUR_SLOTS := ["head", "body", "legs", "shield"]
# travelling traders
const TRADER_MIN_ROI := 0.25
const TRADER_MIN_NET := 2
const TRADER_CARRY := 30        # non-stackable units per trip (stackables x10)
const TRADER_BUDGET := 0.5      # share of coins risked per trip
const TRADER_WAIT := 900        # ticks to wait in town for cargo to sell before moving on


static func mk(agent: AIAgent) -> TownMarket:
	return Market.town(agent.town)


const PRICE_HEALTH := 0.85


static func value(agent: AIAgent, item: String) -> float:
	var m := mk(agent)
	if m.tradeable(item):
		return float(m.reference_price(item))
	return float(GameData.item_value(item))


static func weight(agent: AIAgent, skill: String) -> float:
	var f := agent.focus()
	var i := f.find(skill)
	if i >= 0 and i < FOCUS_WEIGHTS.size():
		return FOCUS_WEIGHTS[i]
	return OTHER_WEIGHT


## Agents play ~8 game hours a day; persona picks when, +-2 h per agent.
static func is_active_hour(agent: AIAgent, hour: int) -> bool:
	var start := 8
	match agent.persona.get("schedule", "day"):
		"dawn":
			start = 4
		"evening":
			start = 14
		"night":
			start = 20
		"any":
			return true
	start += posmod(int(hash(agent.id)), 5) - 2
	return posmod(hour - start, 24) < SESSION_HOURS


static func gather_rate(agent: AIAgent, d: Dictionary) -> float:
	var skill: String = d["skill"]
	var lvl := agent.skills.level(skill)
	var c := clampf((float(d.get("chance", 0.3)) + Interactions.LEVEL_BONUS_PER_LEVEL * (lvl - int(d.get("level", 1)))
		+ agent.tool_power(skill)) * Market.gather_mult * Prayer.mult(agent.prayer, "gather"), 0.05, 0.95)
	return c / float(d.get("attempt_ticks", 3)) * MineTravel.factor_def(agent.home_town, d)   # 0.3.1 far mines cost walking


static func gather_value(agent: AIAgent, d: Dictionary) -> float:
	var v := value(agent, d["yield"])
	var alt: Dictionary = d.get("alt_yield", {})
	if not alt.is_empty() and agent.skills.level(d["skill"]) >= int(alt.get("level", 99)):
		var ac := float(alt.get("chance", 0.0))
		v = v * (1.0 - ac) + value(agent, alt["item"]) * ac
	return v


## Unsold stock piling up -> the next unit is worth less to this agent.
## Discourage producing more of what already piles up in the stash
## (by count and by value, so cheap stackables can't flood the market).
static func glut(agent: AIAgent, item: String) -> float:
	var n := agent.stash_count(item)
	var r := minf(float(GLUT_AT) / maxf(1.0, n), GLUT_VALUE / maxf(1.0, n * float(GameData.item_value(item))))
	if r >= 1.0:
		return 1.0
	return r * r if r > 0.25 else 0.0


## Supply response: producers back off an item trading well under its base
## value locally (1.0 at >= PRICE_HEALTH x base, falling cubically below).
static func price_health(agent: AIAgent, item: String) -> float:
	var base := float(GameData.item_value(item))
	if base <= 0.0 or not mk(agent).tradeable(item):
		return 1.0
	var r := clampf(value(agent, item) / (base * PRICE_HEALTH), 0.0, 1.0)
	return r * r * r


static func fail_p(agent: AIAgent, r: Dictionary) -> float:
	return Interactions.fail_chance(r, agent.skills.level(r["skill"]))


static func recipe_margin(agent: AIAgent, r: Dictionary) -> float:
	var out_id: String = r["out"].keys()[0]
	var m := value(agent, out_id) * int(r["out"][out_id]) * (1.0 - fail_p(agent, r))
	for k in r["in"].keys():
		m -= value(agent, k) * int(r["in"][k])
	return m


## 0.3.1 regional supply: a town's duty prospector (personas min_per_town)
## favours whichever of its pit_duty_ores it has dug least so far (that it can
## mine), so every town's copper, tin and coal all see use.
static func duty_ore(agent: AIAgent) -> String:
	if not agent.memo.has("duty:pits"):
		return ""
	var best := ""
	var bn := 1 << 30
	for ore in agent.persona.get("pit_duty_ores", []):
		var lvl_ok := false
		for oid in GameData.objects.keys():
			var d: Dictionary = GameData.objects[oid]
			if str(d.get("yield", "")) == ore and str(d.get("skill", "")) == "mining" and agent.skills.level("mining") >= int(d.get("level", 1)):
				lvl_ok = true
		var n := int(agent.stats.get("g:" + str(ore), 0))
		if lvl_ok and n < bn:
			bn = n
			best = str(ore)
	return best


## Which enemy an AI fighter hunts: goblins once it can handle them. The
## activity may pin another quarry (0.3.1: cows in the village pastures).
static func quarry(agent: AIAgent) -> String:
	var q := str(agent.activity.get("quarry", "")) if agent.activity else ""
	if q != "":
		return q
	return "goblin" if combat_level(agent) >= 8 and agent.gear_stat("def") + agent.skills.level("vitality") >= 8 else "giant_rat"


## 0.3.1 what a fighter weighs up: its usual camp quarry, plus the village
## cows (herding / hunting for beef and hides; the pastures cost a walk).
static func quarries(agent: AIAgent) -> Array:
	var base := "goblin" if combat_level(agent) >= 8 and agent.gear_stat("def") + agent.skills.level("vitality") >= 8 else "giant_rat"
	var out := [base]
	var share := float(agent.persona.get("herd_share", 1.0))
	var herder: bool = float(agent.memo["herder"]) > 0.0 if agent.memo.has("herder") else posmod(int(hash(agent.id + "|herd")), 100) < int(share * 100.0)
	if GameData.enemies.has("cow") and not GameData.villages.is_empty() and herder:
		out.append("cow")   # herders: personas.json herd_share of the fighters
	return out


## Walking cost of a quarry (village cows sit between the cities).
static func quarry_travel(agent: AIAgent, kind: String) -> float:
	return MineTravel.farm_factor(agent.home_town) if kind == "cow" else 1.0


## Fighters train Attack, Strength and Defence (persona focus).
static func is_fighter(agent: AIAgent) -> bool:
	return agent.focus().has("attack")


## 0.3.1: the shared combat level (Combat.combat_level: Attack, Strength,
## Defence, Vitality, Prayer). Decides the quarry and the aggro rule.
static func combat_level(agent: AIAgent) -> int:
	return Combat.combat_level(agent.skills)


## Mean of Attack and Strength (the offence side of a fighter): kill speed.
static func offence_level(agent: AIAgent) -> int:
	return int((agent.skills.level("attack") + agent.skills.level("strength")) / 2.0)


## Style rotation: train whichever of Attack / Strength is behind.
static func ai_style(agent: AIAgent) -> String:
	return "accurate" if agent.skills.level("attack") <= agent.skills.level("strength") else "aggressive"


static func armour_ids(agent: AIAgent) -> Array:
	var out := []
	for g in agent.gear.values():
		out.append(g["id"])
	return out


## The agent as a fighter (Combat.expected_fight input); optionally with
## another weapon in hand (to compare upgrades).
static func fight_stats(agent: AIAgent, weapon_override: String = "") -> Dictionary:
	var w: Dictionary = agent.tools.get("melee", {})
	var wid: String = weapon_override if weapon_override != "" else (str(w["id"]) if not w.is_empty() else "")
	var st := {"attack": agent.skills.level("attack"), "strength": agent.skills.level("strength"), "defence": agent.skills.level("defence"),
		"atk": 0, "str": 0, "def": 0, "power": 0.0, "weapon": wid, "set_mult": Combat.set_bonus(armour_ids(agent))["mult"]}
	for g in agent.gear.values():
		var gd: Dictionary = GameData.item(g["id"]).get("gear", {})
		for k in ["atk", "str", "def"]:
			st[k] += int(gd.get(k, 0))
	if wid != "":
		var wi := GameData.item(wid)
		for k in ["atk", "str", "def"]:
			st[k] += int(wi.get("gear", {}).get(k, 0))
		st["power"] = float(wi.get("tool", {}).get("power", 0))
	return st


## Weapon quality for this agent: goblin kills per 1000 ticks with it.
static func weapon_score(agent: AIAgent, weapon_id: String) -> float:
	var fn := Combat.expected_fight(GameData.enemies.get("goblin", {}), fight_stats(agent, weapon_id))
	return 1000.0 / maxf(1.0, float(fn["ticks"]) - Combat.SEARCH_TICKS)


## Expected fight; `cover` = share of the fight a prayer buff is active.
static func fight_numbers(agent: AIAgent, kind: String, now: int = -1, cover: float = 0.0) -> Dictionary:
	var e: Dictionary = GameData.enemies.get(kind, {})
	var mults := {"acc": 1.0, "dmg": 1.0, "def": 1.0}
	if now >= 0 and Prayer.is_active(agent.prayer):
		for k in mults.keys():
			mults[k] = 1.0 + (Prayer.mult(agent.prayer, k) - 1.0) * cover
	# one enemy at a time (single-way); camps in multi zones hit harder
	var fn := Combat.expected_fight(e, fight_stats(agent), mults["acc"], mults["dmg"], mults["def"])
	fn["damage"] = float(fn["damage"]) * CombatRules.abstract_damage_mult(kind)
	return fn


static func agent_max_hp(agent: AIAgent) -> int:
	return Combat.max_hp(agent.skills)


## Eat stash food until HP is back above half. Returns false if none left.
static func heal(agent: AIAgent) -> bool:
	var mh := agent_max_hp(agent)
	while agent.hp < mh * EAT_AT:
		var ate := false
		for f in FOODS:
			if agent.stash_count(f) > 0:
				agent.stash_add(f, -1)
				agent.hp = minf(mh, agent.hp + float(GameData.item(f).get("heals", 3)))
				ate = true
				break
		if not ate:
			return false
	return true


## Death (abstract or detailed): the healer keeps 10 % of coin (sink), the
## agent wakes at full HP in its home town and rests a while.
static func on_death(agent: AIAgent, now: int) -> void:
	var fee := int(ceil(agent.coins * DEATH_COIN_FEE))
	agent.coins -= fee
	Market.record_sink(fee)
	agent.hp = agent_max_hp(agent)
	agent.stats["deaths"] = int(agent.stats.get("deaths", 0)) + 1
	if not is_trader(agent):
		agent.town = agent.home_town
	agent.activity = {"type": "rest", "until": now + 300}


static func kill_rate(agent: AIAgent) -> float:
	var r := (1.0 + offence_level(agent) / 30.0 + agent.gear_stat("atk") / 30.0 + agent.tool_power("melee") * 0.05) / KILL_TICKS
	return r if food_count(agent) > 0 else r * 0.5


static func food_count(agent: AIAgent) -> int:
	var n := 0
	for f in FOODS:
		n += agent.stash_count(f)
	return n


static func focus_recipes(agent: AIAgent) -> Array:
	var out := []
	for r in GameData.recipes:
		if agent.focus().has(r["skill"]) and agent.skills.level(r["skill"]) >= int(r.get("level", 1)):
			out.append(r)
	out.sort_custom(func(a, b): return recipe_margin(agent, a) / float(a.get("ticks", 3)) > recipe_margin(agent, b) / float(b.get("ticks", 3)))
	return out


static func is_trader(agent: AIAgent) -> bool:
	return agent.persona_id() == "trader"


## Returns the best activity dict for this agent right now.
static func choose(agent: AIAgent, now: int) -> Dictionary:
	if AdvBrain.is_adv(agent):
		return AdvBrain.choose(agent, now)   # 0.3.1 adventurer-class AI
	var best := {"type": "rest"}
	var best_u := 0.0
	if is_trader(agent) or not is_active_hour(agent, Market.game_hour()):
		best["until"] = now + Market.TICKS_PER_GAME_HOUR
		return best
	var duty := duty_ore(agent)
	var duty_mult := float(agent.persona.get("pit_duty", 1.0))
	if duty != "":
		# 0.3.1 catch-up: when the duty ore lags far behind the ore this
		# prospector digs most (< 1/3 of it), it goes to that pit half the time
		var most := 0
		for k in agent.stats.keys():   # every ore it digs (iron included)
			if str(k).begins_with("g:") and (str(k).ends_with("_ore") or str(k) == "g:coal"):
				most = maxi(most, int(agent.stats[k]))
		if int(agent.stats.get("g:" + duty, 0)) * 3 < most and agent.rng.randf() < 0.5:
			duty_mult = 1000.0
	for oid in GameData.objects.keys():
		var d: Dictionary = GameData.objects[oid]
		if d.get("type", "") != "gather" or agent.skills.level(d["skill"]) < int(d.get("level", 1)):
			continue
		var u := gather_rate(agent, d) * EFF_GATHER * gather_value(agent, d) * weight(agent, d["skill"]) * glut(agent, d["yield"]) * price_health(agent, d["yield"])
		if str(d["yield"]) == duty:
			u *= duty_mult   # 0.3.1 each town's pits see use
		u *= agent.rng.randf_range(0.85, 1.15)
		if u > best_u:
			best_u = u
			best = {"type": "gather", "skill": d["skill"], "node": oid}
	for r in GameData.recipes:
		if agent.skills.level(r["skill"]) < int(r.get("level", 1)) or not agent.has_inputs(r["in"]):
			continue
		var mg := recipe_margin(agent, r)
		var u2 := (mg + (int(r["xp"]) * 0.02 if mg > 0.0 else 0.0)) / float(r.get("ticks", 3)) * EFF_CRAFT * weight(agent, r["skill"]) * glut(agent, r["out"].keys()[0]) * price_health(agent, r["out"].keys()[0])
		u2 *= GearEconomy.production_factor(agent, r["out"].keys()[0])   # 0.3.1: demand-aware smithing
		u2 *= agent.rng.randf_range(0.85, 1.15)
		if u2 > best_u:
			best_u = u2
			best = {"type": "craft", "skill": r["skill"], "recipe": r["id"]}
	if agent.focus().has("prayer") and agent.stash_count("bones") > 0 and PRAY_UTILITY > best_u:
		best_u = PRAY_UTILITY
		best = {"type": "pray", "skill": "prayer"}
	if is_fighter(agent):
		for kind in quarries(agent):
			var fn := fight_numbers(agent, kind)
			var loot := DropTable.expected_value(str(GameData.enemies[kind].get("drops", kind)),
				func(id): return (minf(1.0, Market.bounty_left / 20.0) if id == GameData.currency else value(agent, id) * glut(agent, id)))
			var u3 := loot / float(fn["ticks"]) * weight(agent, "attack") * quarry_travel(agent, kind) * agent.rng.randf_range(0.85, 1.15)
			if food_count(agent) == 0 and float(fn["damage"]) * 4.0 > agent_max_hp(agent):
				u3 *= 0.3   # risky without food
			if u3 > best_u:
				best_u = u3
				best = {"type": "fight", "skill": "attack", "quarry": kind}
	if best_u < RESERVATION:
		best = {"type": "rest"}
	best["until"] = now + agent.rng.randi_range(ACTIVITY_MIN, ACTIVITY_MAX)
	return best


static func _take(agent: AIAgent, key: String, amount: float) -> int:
	var acc := float(agent.frac.get(key, 0.0)) + amount
	var n := int(floor(acc))
	agent.frac[key] = acc - n
	return n


## Abstract simulation of `ticks` ticks of the agent's current activity.
static func simulate(agent: AIAgent, ticks: int, now: int) -> void:
	var a := agent.activity
	if agent.hp >= 0.0 and a.get("type", "rest") != "fight":
		agent.hp = minf(agent_max_hp(agent), agent.hp + float(ticks) / Combat.REGEN_TICKS)
	if agent.view == null and a.get("type", "rest") != "fight":
		Prayer.tick(agent.prayer, agent.skills.level("prayer"), ticks)
	match a.get("type", "rest"):
		"gather":
			var d: Dictionary = GameData.object_def(a["node"])
			if d.is_empty():
				a["until"] = now
				return
			var n := _take(agent, "g", gather_rate(agent, d) * EFF_GATHER * ticks)
			var alt: Dictionary = d.get("alt_yield", {})
			for i in n:
				var item: String = d["yield"]
				var xp := int(d.get("xp", 0))
				if not alt.is_empty() and agent.skills.level(d["skill"]) >= int(alt.get("level", 99)) and agent.rng.randf() < float(alt.get("chance", 0)):
					item = alt["item"]
					xp = int(alt.get("xp", xp))
				agent.stash_add(item, 1)
				agent.skills.add_xp(d["skill"], xp)
				agent.stats["g:" + item] = int(agent.stats.get("g:" + item, 0)) + 1   # 0.3.1 per-item supply (soak)
			agent.stats["gathered"] = int(agent.stats.get("gathered", 0)) + n
			if agent.wear(d["skill"], n):
				a["until"] = now
		"craft":
			var r := Interactions.recipe_by_id(a.get("recipe", ""))
			if r.is_empty():
				a["until"] = now
				return
			var n := _take(agent, "c", float(ticks) / float(r.get("ticks", 3)) * EFF_CRAFT)
			var fp := fail_p(agent, r)
			for i in n:
				if not agent.has_inputs(r["in"]):
					a["until"] = now
					break
				for k in r["in"].keys():
					agent.stash_add(k, -int(r["in"][k]))
				if fp > 0.0 and agent.rng.randf() < fp:
					if r["fail"].has("item"):
						agent.stash_add(r["fail"]["item"], 1)
					agent.skills.add_xp(r["skill"], Interactions.fail_xp(r))
				else:
					for k in r["out"].keys():
						agent.stash_add(k, int(r["out"][k]))
						agent.stats["m:" + k] = int(agent.stats.get("m:" + k, 0)) + int(r["out"][k])   # 0.3.1 per-item output (soak)
					agent.skills.add_xp(r["skill"], int(r["xp"]))
					agent.stats["made"] = int(agent.stats.get("made", 0)) + 1
		"pray":
			var nb := mini(agent.stash_count("bones"), _take(agent, "p", ticks / 3.0))
			for i in nb:
				bury_one(agent)
			if agent.stash_count("bones") == 0:
				a["until"] = now
		"fight":
			var kind: String = str(a.get("kind", quarry(agent)))   # 0.3.1: adventurers name their target
			var e: Dictionary = GameData.enemies.get(kind, {})
			if e.is_empty():
				a["until"] = now
				return
			if now < int(a.get("arrive", 0)):
				return       # still walking to the camp
			if agent.hp < 0.0:
				agent.hp = agent_max_hp(agent)
			# pray before engaging (abstract: the buff covers part of this chunk)
			var plv := agent.skills.level("prayer")
			Prayer.ai_pick(agent.prayer, plv, agent.hp / agent_max_hp(agent), func(): return bury_one(agent))
			var cover := clampf(float(Prayer.ticks_left(agent.prayer, plv)) / maxf(1.0, ticks), 0.0, 1.0)
			var fn := fight_numbers(agent, kind, now, cover)
			if agent.view == null:
				Prayer.tick(agent.prayer, plv, ticks)
			var n := _take(agent, "k", ticks / float(fn["ticks"]))
			for i in n:
				agent.hp -= float(fn["damage"]) * agent.rng.randf_range(0.5, 1.5)
				if agent.hp <= 0.0 and not heal(agent):
					if PkRules.is_pk(agent.pos):
						AdvBrain.npc_pk_death(agent, now)   # 0.3.1: keep-3 rule in the Scorch
					else:
						on_death(agent, now)
					return
				for d in DropTable.roll(str(e.get("drops", kind)), agent.rng):
					if d[0] == GameData.currency:
						var c := Market.pay_bounty(int(d[1]))
						agent.coins += c
						agent.stats["earned"] = int(agent.stats.get("earned", 0)) + c
					elif AdvBrain.loot_wanted(agent, d[0], int(d[1])):
						agent.stash_add(d[0], int(d[1]))
				agent.stats["kills"] = int(agent.stats.get("kills", 0)) + 1
				agent.stats["k:" + kind] = int(agent.stats.get("k:" + kind, 0)) + 1   # 0.3.1 per-kind kills (soak)
				if AdvBrain.is_adv(agent):    # 0.3.1: regen while finding the next one, like a player
					agent.hp = minf(agent_max_hp(agent), agent.hp + float(Combat.SEARCH_TICKS) / Combat.REGEN_TICKS)
				Combat.award_hit_xp(agent.skills, ai_style(agent), int(e.get("hp", 5)))   # damage dealt = its HP
				agent.skills.add_xp("defence", Combat.roll_xp(float(fn["def_xp"]), agent.rng))
				if not heal(agent) and agent.hp < agent_max_hp(agent) * (0.5 if AdvBrain.is_adv(agent) else FLEE_AT):   # 0.3.1: adventurers rest up early
					agent.stats["fled"] = int(agent.stats.get("fled", 0)) + 1
					agent.activity = {"type": "rest", "until": now + 200}
					return
			agent.wear_gear(n * GearEconomy.wear_mult())          # 0.3.1: gear wears out (data/gear_economy.json)
			if agent.wear("melee", n * GearEconomy.wear_mult()):
				a["until"] = now
			if AdvBrain.is_adv(agent):
				AdvBrain.after_fight(agent)


# --------------------------------------------------------------- trading --
static func _mult(agent: AIAgent, key: String, def: float) -> float:
	return float(agent.memo.get(key, def))


static func _nudge(agent: AIAgent, key: String, def: float, by: float) -> void:
	agent.memo[key] = clampf(_mult(agent, key, def) + by, MULT_MIN, MULT_MAX)


static func sell_default(agent: AIAgent) -> float:
	return 1.0 + 0.02 + 0.04 * float(agent.persona.get("patience", 0.5)) - 0.03 * float(agent.persona.get("risk", 0.3))


static func buy_default(agent: AIAgent) -> float:
	return 0.98 - 0.04 * float(agent.persona.get("patience", 0.5)) + 0.03 * float(agent.persona.get("risk", 0.3))


static func collect(agent: AIAgent) -> void:
	var box := mk(agent).collect(agent.id)
	agent.coins += int(box.get("coins", 0))
	var items: Dictionary = box.get("items", {})
	for k in items.keys():
		agent.stash_add(k, int(items[k]))


## Before leaving town: pull every order resting here and take the escrow
## (unsold cargo, unspent coin) along, so nothing is stranded in this town's box.
static func close_out(agent: AIAgent) -> void:
	var m := mk(agent)
	for id in agent.my_orders.keys().duplicate():
		if str(agent.my_orders[id].get("town", agent.town)) == agent.town:
			m.cancel_order(id, true)
			agent.my_orders.erase(id)
	collect(agent)


## Equip anything useful sitting in the stash (tools, weapons, armour).
static func equip_from_stash(agent: AIAgent) -> void:
	if is_trader(agent):
		return
	for k in agent.stash.keys().duplicate():
		var it := GameData.item(k)
		var gd: Dictionary = it.get("gear", {})
		if not gd.is_empty() and Combat.equip_error(agent.skills, k) != "":
			continue
		if gd.get("slot", "") in ARMOUR_SLOTS:
			var cur: Dictionary = agent.gear.get(gd["slot"], {})
			var cur_def := int(GameData.item(cur["id"]).get("gear", {}).get("def", 0)) if not cur.is_empty() else -1
			if int(gd.get("def", 0)) > cur_def:
				agent.stash_add(k, -1)
				if not cur.is_empty():
					agent.stash_add(cur["id"], 1)
				agent.give_tool(k)
		elif it.has("tool"):
			var skill: String = it["tool"]["skill"]
			var better := float(it["tool"].get("power", 0)) > agent.tool_power(skill)
			if skill == "melee":
				if gd.get("style", "melee") != "melee":
					continue
				var cur_w: Dictionary = agent.tools.get("melee", {})
				better = cur_w.is_empty() or weapon_score(agent, k) > weapon_score(agent, str(cur_w["id"])) * 1.01
			if better:
				var cur2: Dictionary = agent.tools.get(skill, {})
				agent.stash_add(k, -1)
				if not cur2.is_empty():
					agent.stash_add(cur2["id"], 1)
				agent.give_tool(k)


static func keep_list(agent: AIAgent) -> Dictionary:
	var keep := {}
	for r in focus_recipes(agent).slice(0, 2):
		for k in r["in"].keys():
			keep[k] = maxi(int(keep.get(k, 0)), int(r["in"][k]) * 20)
	keep["cooked_carp"] = maxi(int(keep.get("cooked_carp", 0)), 12 if is_fighter(agent) else 6)
	if AdvBrain.is_adv(agent):
		keep.merge(AdvBrain.keep_list(agent), true)    # 0.3.1: food for the fight; bones are buried, not bought
	elif agent.focus().has("prayer"):
		keep["bones"] = 30
	keep["ash_log"] = maxi(int(keep.get("ash_log", 0)), 6)
	return keep


static func _price(m: TownMarket, item: String, mult: float) -> int:
	var band := m.price_band(item)
	return clampi(int(round(m.reference_price(item) * mult)), band.x, band.y)


static func _has_open(agent: AIAgent, item: String, buy: bool) -> bool:
	for id in agent.my_orders.keys():
		var o: Dictionary = agent.my_orders[id]
		if o["item"] == item and bool(o["buy"]) == buy and str(o.get("town", agent.town)) == agent.town:
			return true
	return false


static func place_buy(agent: AIAgent, item: String, qty: int, price: int) -> bool:
	if qty <= 0 or price <= 0 or agent.coins < qty * price:
		return false
	var m := mk(agent)
	agent.coins -= qty * price
	var res := m.place_order(agent.id, item, qty, price, true)
	if not res["ok"]:
		agent.coins += qty * price
		return false
	if m.orders.has(res["id"]):
		agent.my_orders[res["id"]] = {"item": item, "buy": true, "town": agent.town}
	agent.stats["trades"] = int(agent.stats.get("trades", 0)) + 1
	return true


static func place_sell(agent: AIAgent, item: String, qty: int, price: int) -> bool:
	qty = mini(qty, agent.stash_count(item))
	if qty <= 0:
		return false
	var m := mk(agent)
	agent.stash_add(item, -qty)
	var res := m.place_order(agent.id, item, qty, price, false)
	if not res["ok"]:
		agent.stash_add(item, qty)
		return false
	if m.orders.has(res["id"]):
		agent.my_orders[res["id"]] = {"item": item, "buy": false, "town": agent.town}
	agent.stats["trades"] = int(agent.stats.get("trades", 0)) + 1
	return true


## Fill-detection and repricing of this agent's orders in its current town.
static func _review_orders(agent: AIAgent, now: int, window: int) -> void:
	for id in agent.my_orders.keys().duplicate():
		var mine: Dictionary = agent.my_orders[id]
		var tm := Market.town(str(mine.get("town", agent.town)))
		var key: String = ("b:" if mine["buy"] else "s:") + str(mine["item"])
		if not tm.orders.has(id):
			_nudge(agent, key, buy_default(agent) if mine["buy"] else sell_default(agent), -0.015 if mine["buy"] else 0.015)
			agent.my_orders.erase(id)
			continue
		if tm.town_id != agent.town:
			# a trader left town: pull the order (escrow waits in that town's box)
			if tm.cancel_order(id, true):
				agent.my_orders.erase(id)
			continue
		var o: Dictionary = tm.orders[id]
		if now - int(o["tick"]) > window and tm.cancel_order(id):
			agent.my_orders.erase(id)
			_nudge(agent, key, buy_default(agent) if mine["buy"] else sell_default(agent), 0.03 if mine["buy"] else -0.03)


## Buy the best affordable item for a tool skill or gear slot, locally:
## Exchange ask, else this town's shop (general or specialist), else bid.
static func _buy_upgrade(agent: AIAgent, candidates: Array, current_power: float, stat: String) -> void:
	var m := mk(agent)
	var best := ""
	var best_p := current_power
	for id in candidates:
		var it := GameData.item(id)
		var p := float(it.get("gear", {}).get(stat, it.get("tool", {}).get("power", 0))) if stat != "" else float(it.get("tool", {}).get("power", 0))
		if stat == "weapon":
			p = weapon_score(agent, id)
		if Combat.equip_error(agent.skills, id) != "":
			continue
		if p > best_p and m.reference_price(id) * 2 <= agent.coins:
			best_p = p
			best = id
	if best == "" or _has_open(agent, best, true):
		return
	var ask := m.best_ask(best)
	var band := m.price_band(best)
	var shop := ""
	for s in ["general"] + m.specialists:
		if best in m.shop_items(s) and (m.shelf(s, best) < 0 or m.shelf(s, best) > 0):
			shop = s
	var shop_p := m.shop_price(shop, best) if shop != "" else 1 << 30
	if ask > 0 and ask <= band.y and ask <= shop_p:
		place_buy(agent, best, 1, ask)
	elif shop != "" and agent.coins >= shop_p:
		var cost := m.shop_sell_to(shop, best, 1)
		if cost > 0:
			agent.coins -= cost
			agent.give_tool(best)
			note_shop_visit(agent, shop)
	else:
		place_buy(agent, best, 1, _price(m, best, _mult(agent, "b:" + best, buy_default(agent))))


static func trade(agent: AIAgent, now: int) -> void:
	if is_trader(agent):
		return
	var m := mk(agent)
	collect(agent)
	var patience := float(agent.persona.get("patience", 0.5))
	_review_orders(agent, now, int(300 + patience * 900))
	collect(agent)
	equip_from_stash(agent)
	shop_browse(agent, now)
	var keep := keep_list(agent)
	# 1. tools and gear
	for s in agent.focus():
		if s in ["forestry", "mining", "angling"]:
			var cands := []
			for id in GameData.items.keys():
				if GameData.item(id).get("tool", {}).get("skill", "") == s:
					cands.append(id)
			_buy_upgrade(agent, cands, agent.tool_power(s), "")
	AdvBrain.visit_altar(agent)          # 0.3.1: refill Prayer at the town church altar (if the world has one)
	if AdvBrain.is_adv(agent):
		AdvBrain.gear_trade(agent, now)    # 0.3.1 best-in-slot upgrades (any source / commission)
	elif is_fighter(agent):
		var weapons := []
		for id in GameData.items.keys():
			if GameData.item(id).get("gear", {}).get("slot", "") == "weapon" and GameData.item(id).get("gear", {}).get("style", "") == "melee":
				weapons.append(id)
		var w: Dictionary = agent.tools.get("melee", {})
		_buy_upgrade(agent, weapons, weapon_score(agent, str(w["id"])) * 1.05 if not w.is_empty() else -1.0, "weapon")
		var slot: String = ARMOUR_SLOTS[agent.rng.randi() % ARMOUR_SLOTS.size()]
		var pieces := []
		for id in GameData.items.keys():
			if GameData.item(id).get("gear", {}).get("slot", "") == slot:
				pieces.append(id)
		var cur: Dictionary = agent.gear.get(slot, {})
		_buy_upgrade(agent, pieces, float(GameData.item(cur["id"]).get("gear", {}).get("def", 0)) if not cur.is_empty() else -1.0, "def")
	# 2. inputs / food / fuel
	var budget := int(agent.coins * 0.4)
	for k in keep.keys():
		var have_n := agent.held_count(k)
		if have_n * 4 >= int(keep[k]) or _has_open(agent, k, true) or not m.tradeable(k):
			continue
		var p := _price(m, k, _mult(agent, "b:" + k, buy_default(agent)))
		var ask := m.best_ask(k)
		if ask > 0 and ask <= p * 1.03:
			p = clampi(ask, m.price_band(k).x, m.price_band(k).y)
		var q := mini(int(keep[k]) - have_n, int(budget / maxf(1.0, p)))
		if q > 0 and place_buy(agent, k, q, p):
			budget -= q * p
	# 3. surplus (0.3.1: glutted wearables go to the armourer for scrap first)
	GearEconomy.scrap_surplus(agent)
	var lots := []
	for k in agent.stash.keys():
		var s := agent.stash_count(k) - int(keep.get(k, 0))
		if s > 0:
			lots.append([k, s, s * value(agent, k)])
	lots.sort_custom(func(a, b): return a[2] > b[2])
	for lot in lots:
		var item: String = lot[0]
		var surplus: int = lot[1]
		if not m.tradeable(item):
			if GameData.item_value(item) <= 0:
				agent.stash.erase(item)
			continue
		if agent.stash_count(item) >= DUMP_AT:
			var res := m.npc_buy_from(agent.id, item, agent.stash_count(item) - DUMP_KEEP)
			agent.stash_add(item, -int(res["qty"]))
			agent.coins += int(res["paid"])
			surplus -= int(res["qty"])
		if surplus < (1 if value(agent, item) >= 30 else 3) or _has_open(agent, item, false):
			continue
		if m.open_count(agent.id) >= Market.MAX_OPEN_ORDERS_PER_TRADER - 1:
			break
		var p := _price(m, item, _mult(agent, "s:" + item, sell_default(agent)))
		var bid := m.best_bid(item)
		if bid > 0 and bid >= int(p * 0.97):
			p = bid
		p = maxi(p, m.npc_buy_price(item))
		if p > m.price_band(item).y:
			continue
		place_sell(agent, item, mini(surplus, 60), p)
	if agent.persona_id() == "smith":
		AdvBrain.smith_fill(agent, now)     # 0.3.1 commissioned gear


# ------------------------------------------------------- travelling traders --
## Cheapest way to buy one unit of `item` in town m right now: [price, source, available].
## 0.3.0: an owned, stocked player shop is a source too ("player", stand index in [3]).
static func buy_quote(m: TownMarket, item: String, include_player: bool = true) -> Array:
	var best := [1 << 30, "", 0, -1]
	var ask := m.best_ask(item)
	if ask > 0 and not m.is_halted(item):
		best = [ask, "exchange", m.depth(item, false), -1]
	for s in ["general"] + m.specialists:
		if item in m.shop_items(s):
			var shelf := m.shelf(s, item)
			if shelf != 0:
				var p := m.shop_price(s, item)
				if p < int(best[0]):
					best = [p, s, shelf if shelf > 0 else 50, -1]
	if include_player:
		var ps := Market.open_player_shop(m.town_id)
		if ps != null:
			for i in ps.stocked():
				var sl: Dictionary = ps.slots[i]
				if str(sl["item"]) == item and int(sl["price"]) < int(best[0]):
					best = [int(sl["price"]), "player", int(sl["qty"]), i]
	return best


## What a unit should fetch in town m (conservative).
static func sell_estimate(m: TownMarket, item: String) -> float:
	var bid := float(m.best_bid(item))
	var est := maxf(bid, float(m.reference_price(item)) * (0.97 if bid > 0.0 else 0.9))
	return est * (1.0 - Market.TAX_RATE)


## Best arbitrage from the trader's town: {item, to, unit, qty, source, net} or {}.
static func plan_trip(agent: AIAgent) -> Dictionary:
	var here := mk(agent)
	var best := {}
	var best_score := 0.0
	var budget := int(agent.coins * TRADER_BUDGET)
	for item in here.reference.keys():
		if not here.tradeable(item):
			continue
		var q := buy_quote(here, item)
		var unit: int = q[0]
		if unit <= 0 or unit > budget or str(q[1]) == "":
			continue
		for to in Market.town_ids:
			if to == agent.town:
				continue
			var there := Market.town(to)
			var net := sell_estimate(there, item) - unit
			if net < TRADER_MIN_NET or net / unit < TRADER_MIN_ROI:
				continue
			var cap := TRADER_CARRY * (10 if GameData.is_stackable(item) else 1)
			var demand := maxi(8, int(there.prev_day_vol.get(item, 0) / 2) + there.depth(item, true))
			var qty := mini(mini(int(budget / unit), int(q[2])), mini(cap, demand))
			var crowd := 0
			for other in AIDirector.records:
				if other != agent and other.trip.get("to", "") == to and other.stash_count(item) > 0:
					crowd += 1
			var score := net * qty * agent.rng.randf_range(0.9, 1.1) / (1.0 + crowd)
			if qty > 0 and score > best_score:
				best_score = score
				best = {"item": item, "to": to, "unit": unit, "qty": qty, "source": q[1], "net": net}
	return best


## A trader in town: collect, sell cargo, or plan and buy for the next trip.
## Returns the destination town if the trader should set off now, else "".
static func trader_trade(agent: AIAgent, now: int) -> String:
	var m := mk(agent)
	collect(agent)
	_review_orders(agent, now, 400)
	collect(agent)
	# 1. sell cargo here
	var selling := false
	for item in agent.stash.keys().duplicate():
		if not m.tradeable(item):
			agent.stash.erase(item)
			continue
		var cost := float(agent.memo.get("c:" + item, m.reference_price(item)))
		if _has_open(agent, item, false):
			selling = true
			continue
		var band := m.price_band(item)
		var bid := m.best_bid(item)
		var mult := _mult(agent, "s:" + item, 1.04)
		var p := clampi(int(ceil(maxf(cost * 1.03, m.reference_price(item) * mult))), band.x, band.y)
		if bid >= int(cost * 1.02) and bid >= band.x:
			p = bid
		if place_sell(agent, item, agent.stash_count(item), p):
			selling = true
	if selling:
		if agent.trip.is_empty() or int(agent.trip.get("arrived", now)) + TRADER_WAIT > now:
			if agent.trip.is_empty():
				agent.trip = {"arrived": now}
			return ""
		# waited long enough: cut losses. Hit the bids, sell the rest to the
		# general store (its daily purse permitting), carry only what is left.
		for id in agent.my_orders.keys().duplicate():
			if Market.town(str(agent.my_orders[id].get("town", agent.town))).cancel_order(id, true):
				agent.my_orders.erase(id)
		collect(agent)
		for item in agent.stash.keys().duplicate():
			var bid := m.best_bid(item)
			if bid > 0 and m.tradeable(item):
				place_sell(agent, item, agent.stash_count(item), maxi(bid, m.price_band(item).x))
		for id in agent.my_orders.keys().duplicate():
			if m.cancel_order(id, true):
				agent.my_orders.erase(id)
		collect(agent)
		for item in agent.stash.keys().duplicate():
			var res := m.npc_buy_from(agent.id, item, agent.stash_count(item), "general")
			if int(res["qty"]) > 0:
				agent.stash_add(item, -int(res["qty"]))
				agent.coins += int(res["paid"])
		agent.stats["liquidations"] = int(agent.stats.get("liquidations", 0)) + 1
		if not agent.stash.is_empty():
			var best_to := ""
			var best_v := -1.0
			for to in Market.town_ids:
				if to == agent.town:
					continue
				var v := 0.0
				for item in agent.stash.keys():
					v += sell_estimate(Market.town(to), item) * agent.stash_count(item)
				if v > best_v:
					best_v = v
					best_to = to
			return best_to
	# 2. plan a new trip
	var plan := plan_trip(agent)
	if plan.is_empty():
		agent.trip = {}
		return ""
	var item: String = plan["item"]
	var qty: int = plan["qty"]
	var spent := 0
	var c0 := agent.coins
	var had := agent.stash_count(item)
	if plan["source"] == "exchange":
		var limit := mini(m.price_band(item).y, int(plan["unit"] * 1.03) + 1)
		if place_buy(agent, item, qty, limit):
			# take what filled now; the unfilled rest is cancelled (escrow back)
			for id in agent.my_orders.keys().duplicate():
				if agent.my_orders[id]["item"] == item and m.cancel_order(id, true):
					agent.my_orders.erase(id)
			collect(agent)
			spent = c0 - agent.coins
	elif plan["source"] == "player":
		# 0.3.0 buying cheap stock off your stands to resell elsewhere (realistic, allowed)
		var ps := Market.player_shop(agent.town)
		var q := buy_quote(m, item)
		if str(q[1]) == "player":
			var n := mini(qty, int(agent.coins / maxi(1, int(q[0]))))
			var cost := ps.ai_buy(agent.id, int(q[3]), n) if n > 0 else 0
			if cost > 0:
				agent.coins -= cost
				agent.stash_add(item, cost / maxi(1, int(q[0])))
				spent = cost
				note_shop_visit(agent, "player")
	else:
		var cost := m.shop_cost(plan["source"], item, qty)
		if cost <= agent.coins and m.shop_sell_to(plan["source"], item, qty) > 0:
			agent.coins -= cost
			agent.stash_add(item, qty)
			spent = cost
	var got := agent.stash_count(item) - had
	if got <= 0:
		return ""
	agent.memo["c:" + item] = float(spent) / maxf(1.0, got) if spent > 0 else float(plan["unit"])
	agent.stats["trips"] = int(agent.stats.get("trips", 0)) + 1
	agent.stats["carried"] = int(agent.stats.get("carried", 0)) + got
	return plan["to"]


static func daily_needs(agent: AIAgent) -> int:
	if AdvBrain.is_adv(agent) and not bool(AdvBrain.cfg().get("pays_inn", false)):
		return 0      # adventurers live like players: no inn bill, they eat what they carry in fights
	var spent := 0
	for need in [[FOODS, DAILY_FOOD], [FUELS, DAILY_FUEL]]:
		var left: int = need[1]
		for item in need[0]:
			var take := mini(left, agent.stash_count(item))
			agent.stash_add(item, -take)
			left -= take
		var cost := mini(left * INN_COST, agent.coins)
		agent.coins -= cost
		spent += cost
	return spent


## Fighters bury bones beyond what they keep to sell (Prayer XP, a goods sink).
## Bury one bone from the stash: Prayer XP + restores prayer points.
static func bury_one(agent: AIAgent) -> bool:
	if agent.stash_count("bones") <= 0:
		return false
	var it := GameData.item("bones")
	agent.stash_add("bones", -1)
	agent.skills.add_xp("prayer", int(it.get("bury_xp", 5)))
	Prayer.restore(agent.prayer, agent.skills.level("prayer"), float(it.get("prayer_restore", 0.2)))
	return true


static func bury_surplus(agent: AIAgent) -> void:
	if not is_fighter(agent):
		return
	var extra := agent.stash_count("bones") - 40
	if extra > 0:
		agent.stash_add("bones", -extra)
		agent.skills.add_xp("prayer", extra * int(GameData.item("bones").get("bury_xp", 5)))


static func upkeep(agent: AIAgent) -> int:
	if AdvBrain.is_adv(agent) and not bool(AdvBrain.cfg().get("pays_inn", false)):
		return 0      # adventurers are players: no living costs (their sinks are food, gear, wear, PK fees)
	var cost := UPKEEP_FLAT + int(maxi(0, agent.coins - UPKEEP_FREE) * UPKEEP_RATE)
	cost = mini(cost, agent.coins)
	agent.coins -= cost
	return cost


# ------------------------------------------------------- 0.3.0 player shops --
## How many of `item` this agent wants right now (0 = none): tool / weapon /
## armour upgrades it can use, or keep-list goods (food, fuel, inputs). With a
## bargain (deal >= 1 / bargain_at) it tops keep-list goods right up.
static func shop_want(agent: AIAgent, item: String, bargain: bool) -> int:
	var it := GameData.item(item)
	var tool: Dictionary = it.get("tool", {})
	var gear: Dictionary = it.get("gear", {})
	if not gear.is_empty() and Combat.equip_error(agent.skills, item) != "":
		return 0
	if not tool.is_empty() and str(tool.get("skill", "")) in agent.focus() and str(tool.get("skill", "")) != "melee":
		return 1 if float(tool.get("power", 0)) > agent.tool_power(str(tool["skill"])) else 0
	if not gear.is_empty():
		if not is_fighter(agent):
			return 0
		var slot := str(gear.get("slot", ""))
		if slot == "weapon":
			if str(gear.get("style", "")) != "melee":
				return 0
			var w: Dictionary = agent.tools.get("melee", {})
			var cur := weapon_score(agent, str(w["id"])) * 1.05 if not w.is_empty() else -1.0
			return 1 if weapon_score(agent, item) > cur else 0
		if slot in ARMOUR_SLOTS:
			var c: Dictionary = agent.gear.get(slot, {})
			var cur_def := float(GameData.item(c["id"]).get("gear", {}).get("def", 0)) if not c.is_empty() else -1.0
			return 1 if float(gear.get("def", 0)) > cur_def else 0
		return 0
	var keep := keep_list(agent)
	if not keep.has(item):
		return 0
	var have := agent.held_count(item)
	if have * 4 >= int(keep[item]) and not bargain:
		return 0
	return maxi(0, int(keep[item]) - have)


## A look around your shop at the agent's normal trading cadence (every tier,
## so it also sells while you're away). Needs + budget + a daily lot cap bound
## demand; the price (deal) and the shop's attractiveness set the odds.
static func shop_browse(agent: AIAgent, _now: int) -> void:
	var ps := Market.open_player_shop(agent.town)
	if ps == null:
		return
	var c := PlayerShop.ai_cfg()
	var budget := int(agent.coins * float(c.get("budget_frac", 0.4)))
	for i in ps.stocked():
		if ps.lots_left(agent.id) <= 0 or budget <= 0:
			return
		var sl = ps.slots[i]
		if sl == null:
			continue
		var item: String = sl["item"]
		var price := int(sl["price"])
		var d := ps.deal(item, price)
		var want := shop_want(agent, item, d >= 1.0 / float(c.get("bargain_at", 0.85)))
		var q := mini(mini(want, int(sl["qty"])), int(budget / maxi(1, price)))
		if q <= 0:
			continue
		if agent.rng.randf() >= ps.buy_chance(item, price):
			continue
		var cost := ps.ai_buy(agent.id, i, q)
		if cost <= 0:
			continue
		agent.coins -= cost
		budget -= cost
		if PlayerShop.is_unit_item(item):
			agent.give_tool(item, int(sl.get("dur", -1)))
		else:
			agent.stash_add(item, q)
		note_shop_visit(agent, "player")


## Cosmetic: a detailed-tier agent near you walks into the shop it just used.
static func note_shop_visit(agent: AIAgent, shop: String) -> void:
	if agent.view != null and is_instance_valid(agent.view) and agent.view.has_method("visit_shop"):
		agent.view.visit_shop(shop)
