class_name Interactions
extends RefCounted
## Rules for every object interaction, applied identically to the player and
## AI players. Tuning numbers live in data/objects.json and data/recipes.json.

const LEVEL_BONUS_PER_LEVEL := 0.012
const DUMMY_ATTACK_TICKS := 3


static func perform(actor: Actor, world, t: int) -> void:
	if actor.action.get("kind", "") == "pack_craft":   # 0.4.0 knife / needle in the pack
		_station(actor, null, {"station": str(actor.action.get("station", ""))})
		return
	var obj: WorldObject = world.object_at(actor.action.get("pos", Vector2i(1 << 20, 0)))
	if obj == null:
		actor.stop()
		return
	var standing_on: bool = (not obj.blocks()) and actor.tile == obj.pos
	# 0.3.0 counters/keepers are served from the tile in front of the counter
	var at_stand: bool = obj.meta.has("stand") and actor.tile == obj.meta["stand"]
	if obj.meta.has("stand") and not at_stand:
		actor.stop()
		return
	if not at_stand and not actor.is_adjacent_to(obj.pos) and not standing_on:
		actor.stop()
		return
	var d := obj.def()
	if d.get("type", "") in ["station", "bank"] and world.gen.is_private(obj.pos) and not (actor is Player and actor.house_owned):
		actor.stop()
		if actor is Player:
			actor.say("This is the townhouse's %s. Buy the house from the estate clerk to use it." % str(d.get("name", "bench")).to_lower())
		return
	match d.get("type", ""):
		"gather":
			_gather(actor, world, obj, d, t)
		"dummy":
			_dummy(actor, obj, d)
		"station":
			_station(actor, obj, d)
		"bank":
			actor.action = {}
			actor.on_bank(world, obj)
		"quest":    # 0.3.7
			actor.action = {}
			if actor is Player:
				QuestSystem.talk(actor, obj)
		"exchange":
			actor.action = {}
			actor.on_exchange(world, obj)
		"shop":
			actor.action = {}
			actor.on_shop(world, obj)
		"display":
			actor.action = {}
			actor.on_display(world, obj)
		"altar":
			_altar(actor, obj)
		"travel":   # 0.4.2 rat hole <-> den ladder
			actor.stop()
			if actor is Player:
				world.travel(actor, obj, d)
		"prop":
			actor.stop()
		_:
			actor.stop()


## 0.3.6 trees need a hatchet, ores a pickaxe: in the pack or wielded.
const TOOL_NEEDED := {"forestry": "You need a hatchet.", "mining": "You need a pickaxe."}


static func has_gather_tool(actor: Actor, skill: String) -> bool:
	if not TOOL_NEEDED.has(skill):
		return true
	if actor.inventory.best_tool_index(skill) >= 0:
		return true
	var w := actor.weapon_id()
	return w != "" and str(GameData.item(w).get("tool", {}).get("skill", "")) == skill


static func gather_chance(actor: Actor, d: Dictionary) -> float:
	var skill: String = d["skill"]
	var lvl := actor.skills.level(skill)
	var power := 0.0
	var ti := actor.inventory.best_tool_index(skill)
	if ti >= 0:
		power = float(GameData.item(actor.inventory.slots[ti]["id"])["tool"].get("power", 0.0))
	return clampf((float(d.get("chance", 0.3)) + LEVEL_BONUS_PER_LEVEL * (lvl - int(d.get("level", 1))) + power) * Market.gather_mult
		* Prayer.mult(actor.prayer, "gather"), 0.05, 0.95)


static func _gather(actor: Actor, world, obj: WorldObject, d: Dictionary, t: int) -> void:
	var skill: String = d["skill"]
	var sname: String = GameData.skill_by_id.get(skill, {}).get("name", skill)
	if obj.is_depleted(t):
		actor.say("There's nothing left here right now.")
		actor.stop()
		return
	if actor.skills.level(skill) < int(d.get("level", 1)):
		actor.say("You need %s level %d for that." % [sname, int(d.get("level", 1))])
		actor.stop()
		return
	if not has_gather_tool(actor, skill):
		actor.say(str(TOOL_NEEDED.get(skill, "You need a tool for that.")))
		actor.stop()
		return
	var item_id: String = d["yield"]
	var xp := int(d.get("xp", 0))
	if actor.inventory.room_for(item_id) <= 0:
		actor.say("Your pack is full.")
		actor.stop()
		return
	actor.set_status("%s %s..." % [str(d.get("doing", "working")).capitalize(), obj.display_name().to_lower()])
	# one attempt every `attempt_ticks` ticks (swing/cast cadence)
	var cd := int(actor.action.get("cooldown", 0))
	if cd > 0:
		actor.action["cooldown"] = cd - 1
		return
	actor.action["cooldown"] = int(d.get("attempt_ticks", 3)) - 1
	if actor is Player:   # 0.3.13 sfx: every swing / chop
		if skill == "mining":
			Sfx.play("pickaxe_swing")
		elif skill == "forestry":
			Sfx.play("axe_chop")
	if actor.rng.randf() >= gather_chance(actor, d):
		return
	var alt: Dictionary = d.get("alt_yield", {})
	if not alt.is_empty() and actor.skills.level(skill) >= int(alt.get("level", 99)) and actor.rng.randf() < float(alt.get("chance", 0.0)):
		item_id = alt["item"]
		xp = int(alt.get("xp", xp))
	actor.inventory.add(item_id, 1)
	if actor is Player and skill == "mining":
		Sfx.play("ore_obtained")   # 0.3.13 sfx
	actor.skills.add_xp(skill, xp)
	actor.say("You get: %s." % GameData.item_name(item_id))
	var ti := actor.inventory.best_tool_index(skill)
	if ti >= 0:
		var tool_id: String = actor.inventory.slots[ti]["id"]
		if actor.inventory.wear_tool(ti):
			actor.say("Your %s breaks!" % GameData.item_name(tool_id).to_lower())
	if actor.rng.randf() < float(d.get("deplete", 0.0)):
		world.deplete(obj, int(d.get("respawn", 10)))
		actor.stop()
	elif actor.inventory.room_for(item_id) <= 0 and actor.inventory.room_for(d["yield"]) <= 0:
		actor.say("Your pack is full.")
		actor.stop()


const DUMMY_XP_MULT := 3


static func _dummy(actor: Actor, obj: WorldObject, d: Dictionary) -> void:
	actor.set_status("Training on the dummy...")
	var cd := int(actor.action.get("cooldown", 0))
	if cd > 0:
		actor.action["cooldown"] = cd - 1
		return
	actor.action["cooldown"] = DUMMY_ATTACK_TICKS - 1
	# the dummy has no defence or gear bonus: Attack sets the hit chance,
	# Strength + weapon power the max hit; XP follows the chosen style
	var hit_chance := clampf(0.55 + actor.skills.level("attack") * 0.01, 0.0, 0.95)
	var dmg := 0
	if actor.rng.randf() < hit_chance:
		dmg = actor.rng.randi_range(1, Combat.actor_max_hit(actor.skills.level("strength"), actor.weapon_power(), 0))
	actor.on_hitsplat(obj, dmg)
	if dmg > 0:
		# 0.3.5 the dummy is worth 3x the normal hit XP
		for _i in DUMMY_XP_MULT:
			Combat.award_hit_xp(actor.skills, actor.current_style(), dmg)
		obj.hp -= dmg
	# 0.3.5 the dummy swings back every time: always blocked (0 splat, no
	# damage) and the block trains Defence
	var blk := Combat.award_defence_xp(actor.skills, 0, 1.0, actor.rng)
	actor.action["dummy_blocks"] = int(actor.action.get("dummy_blocks", 0)) + 1
	actor.action["dummy_def_xp"] = int(actor.action.get("dummy_def_xp", 0)) + blk
	if actor is Player:
		Events.hitsplat.emit(actor, actor.tile, 0)
	if obj.hp <= 0:
		obj.hp = int(d.get("hp", 10))
		var stipend := Market.pay_bounty(int(round(int(d.get("stipend", 0)) * Market.stipend_mult)))
		if stipend > 0:
			actor.inventory.add(GameData.currency, stipend)
			actor.say("The dummy is knocked flat and reset. +%d marks training stipend." % stipend)
		else:
			actor.say("The dummy is knocked flat and reset. The Guild's stipend purse is empty until tomorrow.")


static func recipe_by_id(id: String) -> Dictionary:
	for r in GameData.recipes:
		if r["id"] == id:
			return r
	return {}


static func can_make(actor: Actor, r: Dictionary) -> bool:
	return actor.skills.level(r["skill"]) >= int(r.get("level", 1)) and actor.inventory.has_all(r["in"]) and has_tools(actor, r)


## 0.4.0 recipes with "tools" (knife, needle) need them in the pack (not used up).
static func has_tools(actor: Actor, r: Dictionary) -> bool:
	for tl in r.get("tools", []):
		if actor.inventory.count(str(tl)) <= 0:
			return false
	return true


## 0.4.0 stations worked from the pack, not a world object.
const PACK_STATIONS := {"knife": "fletching", "needle": "crafting"}


static func _station(actor: Actor, obj: WorldObject, d: Dictionary) -> void:
	var station: String = d.get("station", "")
	var recipe: Dictionary = {}
	var want: String = actor.action.get("recipe", "")
	if want != "":
		recipe = recipe_by_id(want)
		if recipe.is_empty() or not can_make(actor, recipe):
			if not recipe.is_empty() and not has_tools(actor, recipe):
				actor.say("You need a %s for that." % GameData.item_name(str(recipe["tools"][0])).to_lower())
			elif not recipe.is_empty() and actor.skills.level(recipe["skill"]) < int(recipe.get("level", 1)):
				actor.say("You need %s level %d for that." % [GameData.skill_by_id[recipe["skill"]]["name"], int(recipe["level"])])
			else:
				actor.say("You don't have the materials to continue.")
			actor.stop()
			return
	else:
		var options: Array = []
		for r in GameData.recipes_for_station(station):
			if can_make(actor, r):
				options.append(r)
		if options.size() > 1 and actor.wants_recipe_choice() and obj != null:
			actor.action = {}
			actor.on_station_menu(station, obj)
			return
		if not options.is_empty():
			recipe = options[0]
			actor.action["recipe"] = recipe["id"]
	if recipe.is_empty():
		var hint := ""
		for r in GameData.recipes_for_station(station):
			if actor.inventory.has_all(r["in"]):
				hint = " (needs %s level %d)" % [GameData.skill_by_id[r["skill"]]["name"], int(r["level"])]
				break
		actor.say("You have nothing to use at the %s%s." % [obj.display_name().to_lower() if obj else station, hint])
		if actor.wants_recipe_choice() and obj != null:
			actor.on_station_menu(station, obj)
		actor.stop()
		return
	var out_id: String = recipe["out"].keys()[0]
	actor.set_status("Making %s..." % GameData.item_name(out_id).to_lower())
	actor.action["progress"] = int(actor.action.get("progress", 0)) + 1
	if actor is Player:   # 0.3.13 sfx: anvil strike each tick, furnace loop while smelting
		if station == "anvil":
			Sfx.play("anvil_strike")
		elif station == "furnace":
			Sfx.furnace_tick()
		elif station in ["knife", "tanning", "needle", "spinning"]:
			Sfx.play("axe_chop")
	if int(actor.action["progress"]) < int(recipe.get("ticks", 3)):
		return
	actor.action["progress"] = 0
	for id in recipe["in"].keys():
		actor.inventory.remove(id, int(recipe["in"][id]))
	var fail: Dictionary = recipe.get("fail", {})
	if not fail.is_empty():
		if actor.rng.randf() < fail_chance(recipe, actor.skills.level(recipe["skill"])):
			if fail.has("item"):
				actor.inventory.add(fail["item"], 1)
			actor.skills.add_xp(recipe["skill"], fail_xp(recipe))
			actor.say(str(fail.get("message", "Oops, you ruin it: %s." % GameData.item_name(str(fail.get("item", ""))).to_lower())))
			_count_attempt(actor)   # a failed attempt still counts toward "make N"
			return
	for id in recipe["out"].keys():
		actor.inventory.add(id, int(recipe["out"][id]))
	actor.skills.add_xp(recipe["skill"], int(recipe["xp"]))
	actor.say("You make: %s." % GameData.item_name(out_id))
	actor.on_crafted(recipe)
	_count_attempt(actor)


static func _count_attempt(actor: Actor) -> void:
	var left := int(actor.action.get("count", -1))
	if left > 0:
		actor.action["count"] = left - 1
		if left - 1 == 0:
			actor.stop()


## Recipe failure chance at a skill level. "chance" = flat rate (e.g. iron
## smelting 40 %); otherwise base - per_level x levels over, floored at min.
static func fail_chance(recipe: Dictionary, level: int) -> float:
	var fail: Dictionary = recipe.get("fail", {})
	if fail.is_empty():
		return 0.0
	if fail.has("chance"):
		return clampf(float(fail["chance"]), 0.0, 1.0)
	var over := level - int(recipe.get("level", 1))
	return maxf(float(fail.get("min", 0.0)), float(fail.get("base", 0.0)) - float(fail.get("per_level", 0.0)) * over)


## XP for a failed attempt: fail.xp if given, else a quarter of the recipe XP.
static func fail_xp(recipe: Dictionary) -> int:
	var fail: Dictionary = recipe.get("fail", {})
	return int(fail["xp"]) if fail.has("xp") else int(int(recipe.get("xp", 0)) / 4.0)


## 0.3.1 church altar: kneel for kneel_ticks (data/churches.json), then the
## Prayer points refill to max. No XP: Prayer XP still comes from burying bones.
## Same rule for the player and AI players (World.nearest_altar finds one).
static func _altar(actor: Actor, obj: WorldObject) -> void:
	var cfg: Dictionary = GameData.churches
	var need := maxi(1, int(cfg.get("kneel_ticks", 2)))
	var n := int(actor.action.get("progress", 0)) + 1
	actor.action["progress"] = n
	actor.action["kneel"] = true
	actor.set_status("Praying at the altar...")
	if n < need:
		return
	var lvl: int = actor.skills.level("prayer")
	var was_full := Prayer.points(actor.prayer, lvl) >= Prayer.max_points(lvl) - 0.001
	actor.prayer["points"] = Prayer.max_points(lvl)
	actor.action = {}
	actor.set_status("")
	actor.say(str(cfg.get("full_line" if was_full else "pray_line", "Your prayer is restored.")))
	if actor.has_method("on_prayed"):
		actor.on_prayed(obj)
