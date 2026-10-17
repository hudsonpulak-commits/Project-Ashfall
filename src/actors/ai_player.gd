class_name AIPlayer
extends Actor
## Detailed-tier view of an AI player: a full Actor (same rules as the human)
## bound to an AIAgent record while the agent is near the player. Decisions
## come from AIBrain; the bank chest is the agent's stash.

var agent: AIAgent
var think_cooldown: int = 0
var _label: Label
var _trip_base := -1                 # road index where the current path slice starts
var _trip_len := 0
var _bubble: Label = null             # 0.3.3 overhead chat bubble (AIChatter)
var bubble_until := -1
var _bubble_x := 0.0


func bind(a: AIAgent, world) -> void:
	agent = a
	actor_id = a.id
	display_name = a.name
	sprite_id = "npc"
	tint = Color(a.tint if a.tint != "" else str(a.persona.get("tint", "#ffffff")))
	skills = a.skills            # shared object: XP earned here is the record's XP
	rng.seed = a.rng.randi()
	inventory.clear()
	sync_from_agent()
	hp = int(ceil(a.hp)) if a.hp >= 0.0 else max_hp()
	hp = clampi(hp, 1, max_hp())
	_world_ref = world
	prayer = a.prayer                # same Dictionary: buffs carry across tiers
	place_at(world.find_free_tile_near(a.pos, 12))
	if not skills.leveled.is_connected(_on_level):
		skills.leveled.connect(_on_level)


## Pack -> record (tools to agent.tools, everything else to the stash).
func unbind() -> void:
	if skills.leveled.is_connected(_on_level):
		skills.leveled.disconnect(_on_level)
	sync_to_agent()
	agent.hp = float(hp)
	for i in inventory.size():
		var s = inventory.slots[i]
		if s == null or GameData.item(s["id"]).has("tool"):
			continue
		_stash_slot(i)
	agent.pos = tile
	agent.view = null


func sync_to_agent() -> void:
	agent.tools.clear()
	for s in inventory.slots:
		if s == null:
			continue
		var t: Dictionary = GameData.item(s["id"]).get("tool", {})
		if t.is_empty():
			continue
		var cur: Dictionary = agent.tools.get(t["skill"], {})
		if cur.is_empty() or float(t.get("power", 0)) > agent.tool_power(t["skill"]):
			agent.tools[t["skill"]] = {"id": s["id"], "dur": int(s.get("dur", t.get("durability", 100)))}


func sync_from_agent() -> void:
	# drop pack tools the record no longer owns (sold/upgraded), add new ones
	for i in inventory.size():
		var s = inventory.slots[i]
		if s == null:
			continue
		var t: Dictionary = GameData.item(s["id"]).get("tool", {})
		if t.is_empty():
			continue
		var owned: Dictionary = agent.tools.get(t["skill"], {})
		if owned.is_empty() or owned["id"] != s["id"]:
			inventory.remove_at(i)
	for skill in agent.tools.keys():
		var tl: Dictionary = agent.tools[skill]
		if inventory.count(tl["id"]) == 0:
			inventory.add(tl["id"], 1, int(tl["dur"]))


func _stash_slot(i: int) -> void:
	var s = inventory.slots[i]
	if s["id"] == GameData.currency:
		agent.coins += int(s["qty"])
	else:
		agent.stash_add(s["id"], int(s["qty"]))
	inventory.remove_at(i)


func _ready() -> void:
	super._ready()
	var trader: bool = agent != null and str(agent.persona.get("id", "")) == "trader"
	_label = Overhead.make(Color(0.7, 0.9, 1.0) if trader else Color(1, 1, 0.75))
	_label.text = Overhead.ai_text(display_name, skills) + (" (trader)" if trader else "")
	Overhead.place(_label, 24.0)
	Overhead.attach(_label, self)
	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 8)
	_bubble.add_theme_color_override("font_color", Color("#1a1410"))
	_bubble.add_theme_stylebox_override("normal", UIStyle.box(Color("#f4ecd0"), Color("#1a1410"), 1, 2))
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_bubble.z_index = 5
	add_child(_bubble)
	_refresh_gear_visual()


# ------------------------------------------------------------ chatter --
## 0.3.3: show a speech bubble until tick `until` (AIChatter decides what/when).
func show_bubble(text: String, until: int) -> void:
	if _bubble == null:
		return
	_bubble.text = text
	_bubble.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble.size = Vector2.ZERO
	_bubble.reset_size()
	var w := _bubble.get_minimum_size().x
	if w > 90.0:            # long lines wrap into a narrower, taller bubble
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.custom_minimum_size = Vector2(90, 0)
		_bubble.size = Vector2(90, 0)
		_bubble.reset_size()
		w = 90.0
	else:
		_bubble.custom_minimum_size = Vector2.ZERO
	var h := _bubble.get_combined_minimum_size().y
	var x := -w / 2.0
	_bubble_x = x
	_bubble.position = Vector2(x, -36 - h)
	_bubble.visible = true
	bubble_until = until


func bubble_text() -> String:
	return _bubble.text if _bubble != null and _bubble.visible else ""


func face_toward(p: Vector2i) -> void:
	if last_steps == 0 and action.get("kind", "") != "fight":
		facing.observe(p.x - tile.x)


func _on_level(skill_id: String, lvl: int) -> void:
	AIChatter.on_level(agent, skill_id, lvl, Market.tick)


# ------------------------------------------------------------------ combat --
func combat_atk() -> int:
	return agent.gear_stat("atk") if agent else 0


func combat_str() -> int:
	return agent.gear_stat("str") if agent else 0


func combat_def() -> int:
	return agent.gear_stat("def") if agent else 0


## AI rotates styles to train Attack and Strength evenly.
func current_style() -> String:
	return AIBrain.ai_style(agent) if agent else super.current_style()


func armour_ids() -> Array:
	var out := []
	if agent:
		for g in agent.gear.values():
			out.append(g["id"])
	return out


# ------------------------------------------------------------- 0.3.1 PK --
func is_skulled(t: int) -> bool:
	return agent != null and t < agent.skull_until


func set_skull(until: int) -> void:
	if agent:
		agent.skull_until = maxi(agent.skull_until, until)
	queue_redraw()


func on_pvp_kill(victim, t: int) -> void:
	super.on_pvp_kill(victim, t)
	if victim is AIPlayer:
		agent.stats["pk_kills"] = int(agent.stats.get("pk_kills", 0)) + 1    # (the victim side was recorded at its death)
	else:
		PkRules.record_kill(agent, null)
	think_cooldown = 0


## Attacked by another player / AI in the Scorch: fight back if we'd win
## (raiders and opportunists are bolder), else run south out of the zone.
func _pvp_react(attacker, t: int) -> void:
	if attacker == null or not is_instance_valid(attacker) or not (attacker is Actor) or attacker.dead:
		return
	if action.get("kind", "") == "fight" and action.get("enemy") == attacker:
		return
	var mine := [PkRules.actor_stats(self)]
	var theirs := [PkRules.actor_stats(attacker)]
	var p := PkRules.win_p(mine, theirs)
	var bold := 0.35 if AdvBrain.is_adv(agent) and AdvBrain.sub(agent) in ["raider", "opportunist"] else (0.5 if AdvBrain.is_adv(agent) or AIBrain.is_fighter(agent) else 0.8)
	if p >= bold:
		attack(attacker)
		set_status("Fighting back")
	else:
		_flee(t)


func _flee(t: int) -> void:
	agent.stats["fled"] = int(agent.stats.get("fled", 0)) + 1
	agent.activity = {"type": "rest", "until": t + 200}
	action = {}
	path.clear()
	auto_retaliate = false
	set_status("Fleeing")
	if _world_ref:
		walk_to(_world_ref, _world_ref.gen.town_spawn(agent.home_town if not agent.trip.has("to") else agent.trip["to"]))


## Hurt: eat from the stash (a packed lunch) below half HP; with no food
## left and under 35 % HP, run home and rest instead.
func on_damaged(t: int) -> void:
	agent.hp = float(hp)
	if last_attacker is Actor and PkRules.is_pk(tile) and hp > 0:
		# 0.3.1 PvP: losing badly -> run; a fresh attack -> decide fight or flight
		var foe_now = last_attacker
		if action.get("kind", "") == "fight" and action.get("enemy") == foe_now:
			if hp < max_hp() * float(PkRules.ai_cfg().get("flee_below", 0.35)) and PkRules.win_p([PkRules.actor_stats(self)], [PkRules.actor_stats(foe_now)]) < 0.4:
				AIBrain.heal(agent)
				hp = int(ceil(agent.hp))
				if hp < max_hp() * float(PkRules.ai_cfg().get("flee_below", 0.35)):
					_flee(t)
					return
		else:
			_pvp_react(foe_now, t)
	if hp > 0 and hp < max_hp() * float(AIChatter.c("low_hp_share", 0.4)):
		AIChatter.say(agent, "low_hp", t)
	if hp < max_hp() * AIBrain.EAT_AT:
		AIBrain.heal(agent)
		hp = int(ceil(agent.hp))
		next_attack = maxi(next_attack, t + Combat.EAT_DELAY)
	if hp < max_hp() * (0.45 if AdvBrain.is_adv(agent) else AIBrain.FLEE_AT) and hp > 0:
		agent.stats["fled"] = int(agent.stats.get("fled", 0)) + 1
		agent.activity = {"type": "rest", "until": t + 200}
		action = {}
		path.clear()
		auto_retaliate = false
		if _world_ref:
			walk_to(_world_ref, _world_ref.gen.town_spawn(agent.home_town if not agent.trip.has("to") else agent.trip["to"]))


func die(t: int) -> void:
	AIChatter.say(agent, "death", t, true)
	if PkRules.is_pk(tile):
		_pk_die(t)
		return
	AIBrain.on_death(agent, t)
	hp = max_hp()
	action = {}
	path.clear()
	agent.trip = {}
	if _world_ref:
		place_at(_world_ref.find_free_tile_near(_world_ref.gen.town_spawn(agent.town), 4))
	agent.pos = tile


## 0.3.1 death in a PK zone: what we carry (pack loot, weapon and tools,
## worn armour, food, carried coin) minus the 3 most valuable units (none if
## skulled) drops where we fell, private to the killer for a while.
func _pk_die(t: int) -> void:
	var killer = last_attacker
	var risk := PkRules.agent_risk(agent)
	for i in inventory.size():
		var sl = inventory.slots[i]
		if sl == null or GameData.item(sl["id"]).has("tool"):
			continue
		if sl["id"] == GameData.currency:
			risk["coins"] = int(risk["coins"]) + int(sl["qty"])
			agent.coins += int(sl["qty"])
			inventory.remove_at(i)
			continue
		for k in int(sl["qty"]):
			risk["units"].append({"id": sl["id"], "src": "stash"})
		_stash_slot(i)
	var skulled := is_skulled(t)
	var drop := PkRules.strip_agent(agent, risk, skulled)
	var spot := tile
	var own: Array = PkRules.pile_owner_and_private(killer, actor_id)
	if _world_ref and _world_ref.ground:
		PkRules.drop_pile(_world_ref.ground, spot, drop["lost"], int(drop["coins"]), own[0], own[1], t)
	if killer is Actor:
		PkRules.record_kill(null, agent)      # victim side + total (the AI killer adds its own count in on_pvp_kill)
	else:
		agent.stats["pk_npc_deaths"] = int(agent.stats.get("pk_npc_deaths", 0)) + 1
	PkRules.log_event({"tick": t, "kind": "ai_death", "victim": agent.id, "killer": CombatRules.label(killer) if killer != null and is_instance_valid(killer) else "?",
		"kept": drop["kept"], "lost": drop["lost"].size(), "coins": int(drop["coins"]), "skulled": skulled, "owner": own[0], "pos": [spot.x, spot.y]})
	last_pk_drop = drop
	quit_name = display_name
	AdvBrain.pk_respawn(agent, t)      # 0.3.1: an AI killed in the Scorch quits; a new level-1 player takes the slot
	refresh_identity()
	hp = max_hp()
	action = {}
	path.clear()
	if _world_ref:
		place_at(_world_ref.find_free_tile_near(_world_ref.gen.town_spawn(agent.town), 4))
	agent.pos = tile
	_refresh_gear_visual()
	queue_redraw()


var last_pk_drop: Dictionary = {}
var quit_name := ""      # the name of the character that just quit (kill messages after the reset)


## 0.3.1: the record now belongs to a new player (Scorch death): new id, name, look.
func refresh_identity() -> void:
	actor_id = agent.id
	display_name = agent.name
	tint = Color(agent.tint if agent.tint != "" else str(agent.persona.get("tint", "#ffffff")))
	if _sprite:
		_sprite.modulate = tint
	if _label:
		_label.text = Overhead.ai_text(display_name, skills)
	inventory.clear()
	sync_from_agent()
	pvp_aggr.clear()
	last_attacker = null


func on_kill(enemy, t: int) -> void:
	super.on_kill(enemy, t)
	agent.stats["kills"] = int(agent.stats.get("kills", 0)) + 1


func set_label_visible(v: bool) -> void:
	if _label:
		_label.visible = v


## Single-way combat: someone else has that enemy; pick another next tick.
func combat_blocked(_why: String) -> void:
	think_cooldown = 0


func on_crafted(_r: Dictionary) -> void:
	agent.stats["made"] = int(agent.stats.get("made", 0)) + 1


## The bank chest: deposit loot to the stash, withdraw inputs for crafting.
func on_bank(_world, _obj) -> void:
	if agent.rng.randf() < 0.3:
		AIChatter.say(agent, "bank", Market.tick)
	for i in inventory.size():
		var s = inventory.slots[i]
		if s != null and not GameData.item(s["id"]).has("tool"):
			_stash_slot(i)
	if agent.activity.get("type", "") == "craft":
		var r := Interactions.recipe_by_id(agent.activity.get("recipe", ""))
		if r.is_empty():
			return
		var per := 0
		for k in r["in"].keys():
			per += int(r["in"][k])
		var batches := int(inventory.free_slots() / maxi(1, per))
		for k in r["in"].keys():
			batches = mini(batches, int(agent.stash_count(k) / int(r["in"][k])))
		for k in r["in"].keys():
			var q := batches * int(r["in"][k])
			var got := inventory.add(k, q)
			agent.stash_add(k, -got)


func on_tick(t: int, world) -> void:
	_world_ref = world
	super.on_tick(t, world)
	agent.hp = float(hp)
	if t % 10 == 3:
		_refresh_gear_visual()
		if _label and not _label.text.ends_with("(trader)"):
			_label.text = Overhead.ai_text(display_name, skills)
	if bubble_until >= 0 and t >= bubble_until:
		bubble_until = -1
		_bubble.visible = false
	if agent.skull_until >= 0 and t == agent.skull_until:
		queue_redraw()
	if not in_combat(t):
		auto_retaliate = true
	if _trip_base >= 0 and agent.trip.has("to"):
		agent.trip["idx"] = _trip_base + (_trip_len - path.size())
		agent.pos = tile
	if _visit_tick(t, world):
		return
	if _loot_tick(t, world):
		return
	if not path.is_empty() or not action.is_empty():
		return
	if think_cooldown > 0:
		think_cooldown -= 1
		return
	_think(t, world)


## Leftovers: walk over to public ground piles nearby and take them.
## Returns true while busy looting. Never mid-fight, never traders on a trip.
func _loot_tick(t: int, world) -> bool:
	if action.get("kind", "") == "loot":
		if path.is_empty():
			if tile == action["pos"] and world.ground:
				world.ground.loot_to_agent(agent, tile)
			action = {}
			set_status("")
			think_cooldown = 0
		return true
	if world.ground == null or world.ground.piles.is_empty() or dead:
		return false
	if t % int(GroundItems.rule("ai_loot_check_ticks", 5)) != 0 or in_combat(t) or action.get("kind", "") == "fight":
		return false
	if agent.trip.has("to"):
		return false
	var found: Array = world.ground.lootable_near(agent, tile, int(GroundItems.rule("ai_loot_radius", 10)), actor_id)
	if found.is_empty():
		return false
	found.sort_custom(func(a, b): return _cheb(a["pos"], tile) < _cheb(b["pos"], tile))
	var p: Dictionary = found[0]
	var pos: Vector2i = p["pos"]
	if tile != pos and not walk_to(world, pos):
		return false
	world.ground.claim(p, actor_id)
	action = {"kind": "loot", "pos": pos}
	set_status("Looting")
	return true


func _go_bank(world) -> bool:
	var chest: WorldObject = world.find_nearest_object(tile, ["bank_chest"], 80)
	return chest != null and interact(world, chest)


## Travelling traders follow the road tile by tile (no pathfinding needed).
func _travel_think(world) -> void:
	_trip_base = -1
	if not agent.trip.has("to"):
		# in town: mill about near the Exchange board
		var board: WorldObject = world.find_nearest_object(world.gen.town_center(agent.town), ["exchange_board"], 20)
		var anchor: Vector2i = board.pos if board else tile
		walk_to(world, world.find_free_tile_near(anchor + Vector2i(rng.randi_range(-4, 4), rng.randi_range(1, 4)), 12, true))
		think_cooldown = rng.randi_range(4, 12)
		return
	var road: Array = world.gen.road_between(agent.trip["from"], agent.trip["to"])
	var idx := clampi(int(agent.trip.get("idx", 0)), 0, road.size() - 1)
	var at: Vector2i = road[idx]
	if tile != at:
		var d := (at - tile).abs()
		if maxi(d.x, d.y) > 30 or not walk_to(world, at):
			place_at(world.find_free_tile_near(at, 3))
		return
	path = road.slice(idx + 1, idx + 61)
	_trip_base = idx
	_trip_len = path.size()


func _think(t: int, world) -> void:
	if AIBrain.is_trader(agent):
		_travel_think(world)
		return
	var a := agent.activity
	if a.is_empty() or t >= int(a.get("until", 0)):
		agent.activity = AIBrain.choose(agent, t)
		a = agent.activity
	match a.get("type", "rest"):
		"gather":
			if inventory.free_slots() == 0:
				if _go_bank(world):
					return
			var node: WorldObject = world.find_gather_node(tile, a["node"], agent.home_town)   # 0.3.1: walks to the named mine
			if node == null:
				node = world.find_nearest_object(agent.home, [a["node"]], 40)
			if node and not node.is_depleted(t) and interact(world, node):
				return
			if node and _walk_leg(world, node.pos):
				return     # 0.3.1: far mine (beyond one A* search): walk there in legs
		"craft":
			var r := Interactions.recipe_by_id(a.get("recipe", ""))
			if not r.is_empty():
				if inventory.has_all(r["in"]):
					var ids := []
					for oid in GameData.objects.keys():
						if GameData.objects[oid].get("station", "") == r["station"]:
							ids.append(oid)
					var st: WorldObject = world.find_nearest_object(tile, ids, 80)
					if st and start_recipe(world, st, r["id"], -1):
						return
					if st == null:   # 0.3.1 village querns: walk out to the nearest one
						var best := Vector2i.ZERO
						var bd := INF
						for q in world.gen.station_sites(str(r["station"])):
							if Vector2(q - tile).length() < bd:
								bd = Vector2(q - tile).length()
								best = q
						if bd < INF and _walk_leg(world, best):
							return
				elif agent.has_inputs(r["in"]) and _go_bank(world):
					return
			a["until"] = t   # nothing to make: rethink next time
			if inventory.free_slots() < 6 and _go_bank(world):
				return
		"pray":
			AIBrain.simulate(agent, 10, t)
		"fight":
			var free_foe := func(e): return CombatRules.can_attack(self, e, t) == ""
			var kind: String = str(a.get("kind", AIBrain.quarry(agent)))
			var foe = world.enemies.nearest(tile, [kind], 120, free_foe) if world.enemies else null   # 0.3.1: camps sit further out
			if foe == null and kind == "cow":   # 0.3.1 village pastures lie between the cities: walk there
				var pz: Dictionary = world.gen.nearest_pasture(tile, kind)
				if not pz.is_empty() and _walk_leg(world, pz["gate"]):
					return
			if AdvBrain.is_adv(agent) and hp < max_hp() * 0.6 and AIBrain.food_count(agent) == 0 and not in_combat(t):
				agent.activity = {"type": "rest", "until": t + 200}     # 0.3.1: no food, hurt -> rest up first
				set_status("Resting")
				think_cooldown = 5
				return
			# settlement creatures (guards, citizens) are fair game for adventurers only if they never start fights
			if foe != null and (not world.gen.safe_at(foe.tile) or (AdvBrain.is_adv(agent) and int(foe.def.get("aggro", 0)) == 0)):
				Prayer.ai_pick(prayer, skills.level("prayer"), float(hp) / max_hp(), func(): return AIBrain.bury_one(agent))
				attack(foe)
				return
			if AdvBrain.is_adv(agent) and a.has("camp"):
				if _walk_toward(world, Vector2i(int(a["camp"][0]), int(a["camp"][1]))):
					return
		"idle":
			if _idle_think(t, world, a):
				return
		"raid":
			if _raid_think(t, world):
				return
			var dummy: WorldObject = world.find_nearest_object(tile, ["training_dummy"], 60)
			if dummy and interact(world, dummy):
				return
	# rest / fallback: stroll near home or the plaza
	var anchor := agent.home if (agent.home - tile).length() < 60 else tile
	walk_to(world, world.find_free_tile_near(anchor + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6)), 12, true))
	think_cooldown = rng.randi_range(3, 10)


## 0.3.1: head towards a far goal one A*-sized leg at a time.
func _walk_leg(world, goal: Vector2i, leg: int = 32) -> bool:
	var d := goal - tile
	if maxi(absi(d.x), absi(d.y)) <= 2:
		return false
	var f := minf(1.0, float(leg) / maxf(1.0, Vector2(d).length()))
	var aim := world.find_free_tile_near(tile + Vector2i(Vector2(d) * f), 6, true) as Vector2i
	return aim != tile and walk_to(world, aim)


func to_save() -> Dictionary:
	return {}


## Long walks in hops (A* has a node budget): up to 30 tiles toward `goal`.
## Returns false once there (within 6 tiles) or if no hop could be found.
func _walk_toward(world, goal: Vector2i) -> bool:
	if _cheb(goal, tile) <= 6:
		return false
	var d := goal - tile
	var hop := tile + Vector2i(clampi(d.x, -30, 30), clampi(d.y, -30, 30))
	if walk_to(world, world.find_free_tile_near(hop, 6, true)):
		set_status("Travelling")
		return true
	return false


## 0.3.1 raider on screen: get into the Scorch, pick the best weak / rich
## looking target near (the player too), maybe joining a fellow raider's
## fight (multi-combat), else prowl around the raid spot.
func _raid_think(t: int, world) -> bool:
	var a := agent.activity
	var spot := Vector2i(int(a.get("spot", [tile.x, tile.y])[0]), int(a.get("spot", [tile.x, tile.y])[1]))
	if not PkRules.is_pk(tile):
		if _walk_toward(world, spot):
			return true
		return false
	var tgt = pick_pvp_target(t)
	if tgt != null:
		Prayer.ai_pick(prayer, skills.level("prayer"), float(hp) / max_hp(), func(): return AIBrain.bury_one(agent))
		attack(tgt)
		set_status("Hunting %s" % CombatRules.label(tgt))
		return true
	var r := 8
	walk_to(world, world.find_free_tile_near(spot + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r)), 8, true))
	set_status("Prowling")
	think_cooldown = rng.randi_range(2, 6)
	return true


## Best PvP target in reach: in a PK zone, not another raider, worth the
## risk: (drop value + 10) x odds, odds >= min_win_p counting raiders
## already on it (they gang up). null = none.
func pick_pvp_target(t: int):
	var ac := PkRules.ai_cfg()
	var radius := int(ac.get("hunt_radius", 14))
	var best = null
	var best_s := 0.0
	var me := PkRules.actor_stats(self)
	for o in get_tree().get_nodes_in_group("actors") if is_inside_tree() else []:
		if o == self or not is_instance_valid(o) or o.dead or _cheb(o.tile, tile) > radius:
			continue
		if PkRules.can_pvp(self, o, t) != "":
			continue
		if o is AIPlayer and o.agent and AdvBrain.is_raider(o.agent):
			continue
		var side := [me]
		for o2 in get_tree().get_nodes_in_group("actors"):
			if o2 is AIPlayer and o2 != self and o2.agent and AdvBrain.is_raider(o2.agent) and o2.action.get("kind", "") == "fight" and o2.action.get("enemy") == o:
				side.append(PkRules.actor_stats(o2))
		var p := PkRules.win_p(side, [PkRules.actor_stats(o)])
		if p < float(ac.get("min_win_p", 0.6)):
			continue
		var sc := (PkRules.actor_drop_value(o, t) + 10.0) * p
		if sc > best_s:
			best_s = sc
			best = o
	return best


# ------------------------------------------------- 0.3.1 visible gear --
## What the agent wears (Actor draws the layers; see Actor._refresh_gear_visual).
func gear_worn() -> Dictionary:
	var out := {}
	if agent == null:
		return out
	for slot in GEAR_DRAW_ORDER:
		var id := AdvBrain.current(agent, slot)
		if id != "":
			out[slot] = id
	return out


# ------------------------------------------------- 0.3.0 cosmetic shop visits --
## AIBrain calls this when this agent just bought from a shop while detailed
## (near you): walk in through the door to the counter (or to a stocked stand
## in your shop), linger a few ticks, walk back out. Purely visual: the trade
## already happened in AIBrain. Only taken when the agent is idle, so it never
## costs production (an earlier version interrupted work and shifted the soak).
func visit_shop(shop: String) -> void:
	if _world_ref == null or dead or agent == null or agent.trip.has("to") or not action.is_empty():
		return   # only when idle: a visit must never interrupt gathering / crafting / fighting (economy-neutral)
	var b: Dictionary = _world_ref.gen.building_for_shop(Market.shop_town() if shop == "player" else agent.town, shop)
	if b.is_empty() or _cheb(b["stand"], tile) > 40:
		return
	var spot := shop_spot(b)
	if spot == Vector2i(1 << 20, 0) or not walk_to(_world_ref, spot):
		return
	var vt: Array = GameData.buildings_cfg.get("visit_ticks", [5, 9])
	action = {"kind": "visit", "building": b["id"], "spot": spot, "linger": rng.randi_range(int(vt[0]), int(vt[1])), "until": -1}
	set_status("Shopping")


## Where to stand: next to a stocked stand (player shop) or the counter front,
## reachable from the counter front (never behind the counter), never the
## doorway, never on someone.
func shop_spot(b: Dictionary) -> Vector2i:
	var taken := {}
	for a in get_tree().get_nodes_in_group("actors") if is_inside_tree() else []:
		if a != self and "tile" in a:
			taken[a.tile] = true
			for st in a.path.slice(-1):
				taken[st] = true
	var wants: Array = []
	if b["kind"] == "player":
		var ps := Market.player_shop(b["town"])
		for i in ps.stocked():
			wants.append(b["displays"][i])
	wants.append(b["stand"])
	for w in wants:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i.ZERO]:
			var q: Vector2i = w + d
			if q == w and w != b["stand"]:
				continue
			if not taken.has(q) and not _world_ref.is_blocked(q) and _world_ref.gen.is_inside(q, b) and not (q in b["doors"]) \
					and (q == b["stand"] or not Pathfinder.find_path(_world_ref, b["stand"], [q], q, 300).is_empty()):
				return q   # customer side only (tiles boxed in behind the counter are skipped)
	return Vector2i(1 << 20, 0)


## Visit / leave state machine; also steps off a doorway or out of a shop
## whenever idle there, so no AI ever parks in a door.
func _visit_tick(t: int, world) -> bool:
	var k: String = action.get("kind", "")
	if k == "visit":
		if not path.is_empty():
			return true
		if int(action["until"]) < 0:
			action["until"] = t + int(action["linger"])
		if t < int(action["until"]) and tile == action["spot"]:
			return true
		_leave_building(world, world.gen.buildings.get(action["building"], {}))
		return true
	if k == "leave":
		if path.is_empty():
			action = {}
			set_status("")
			think_cooldown = 0
		return true
	if path.is_empty() and action.is_empty():
		var b: Dictionary = world.gen.building_at(tile)
		if not b.is_empty():
			_leave_building(world, b)
			return true
	return false


func _leave_building(world, b: Dictionary) -> void:
	if b.is_empty():
		action = {}
		return
	var door: Vector2i = b["doors"][0]
	var outward := Vector2i(0, 1) if door.y == int(b["facade_y"]) and door.y == (b["rect"] as Rect2i).end.y - 1 else Vector2i(0, -1)
	var out_t: Vector2i = world.find_free_tile_near(door + outward * 3, 4, true)
	walk_to(world, out_t)
	action = {"kind": "leave"}
	set_status("")


## 0.3.3 idle variety (AIBrain.choose "idle"): walk to the town well, sit a
## while, or stand near another AI and watch it work. True while handled.
func _idle_think(t: int, world, a: Dictionary) -> bool:
	match str(a.get("mode", "")):
		"well":
			var well: WorldObject = world.find_nearest_object(tile, ["well"], 40)
			if well == null:
				return false
			if _cheb(well.pos, tile) > 1:
				if walk_to(world, world.find_free_tile_near(well.pos, 2, true)):
					set_status("Fetching water")
					return true
				return false
			face_toward(well.pos)
			think_cooldown = rng.randi_range(15, 30)
			return true
		"sit":
			set_status("Sitting")
			think_cooldown = rng.randi_range(20, 40)
			return true
		"watch":
			var best = null
			for v in AIDirector.agents:
				if is_instance_valid(v) and v != self and not v.action.is_empty() and _cheb(v.tile, tile) <= 15:
					best = v
					break
			if best == null:
				return false
			a["watching"] = best.agent.name
			if _cheb(best.tile, tile) > 3:
				return walk_to(world, world.find_free_tile_near(best.tile + Vector2i(rng.randi_range(-2, 2), 2), 2, true))
			face_toward(best.tile)
			if rng.randf() < 0.4:
				AIChatter.say(agent, "watch", t, false, {"name": best.agent.name})
			think_cooldown = rng.randi_range(10, 20)
			return true
	return false


## Keep a showing bubble on screen when its speaker stands near an edge.
## Runs only while a bubble is visible (on-screen agents only).
func _process(delta: float) -> void:
	super._process(delta)
	Overhead.clamp_on_screen(_label, self)
	if _bubble == null or not _bubble.visible:
		return
	var xf := get_global_transform_with_canvas()
	var vw := get_viewport_rect().size.x
	var sc := maxf(0.01, xf.get_scale().x)
	var w := _bubble.size.x
	var x := _bubble_x
	var vr := get_viewport_rect().size
	var off := xf.origin.x < 0.0 or xf.origin.x > vr.x or xf.origin.y < 0.0 or xf.origin.y > vr.y
	_bubble.modulate.a = 0.0 if off else 1.0   # speaker off screen: no floating orphan bubble
	var left := xf.origin.x + x * sc
	if left < 2.0:
		x += (2.0 - left) / sc
	elif left + w * sc > vw - 2.0:
		x -= (left + w * sc - vw + 2.0) / sc
	_bubble.position.x = x
