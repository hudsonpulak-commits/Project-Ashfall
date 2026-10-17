extends Node
## AIDirector — owns the ~40 AI "players" and runs them in three tiers:
##   0 detailed   : within DETAILED_RADIUS_TILES of the player (max MAX_DETAILED)
##                  -> a full AIPlayer Actor on the map, same rules as the human
##   1 nearby     : within NEARBY_RADIUS -> abstract AIBrain step every 10 ticks,
##                  positioned at real work sites so promotion looks right
##   2 world      : everyone else -> abstract step every 100 ticks
## Every tier trades on the Exchange through the same AIBrain.trade().
## AIAgent records are the source of truth and are what gets saved.

const DETAILED_RADIUS_TILES := 48
const DEMOTE_RADIUS_TILES := 56       # hysteresis
const MAX_DETAILED := 12
const NEARBY_RADIUS := 160
const POPULATION := 40
const NEAR_TOWN_SHARE := 0.65
const SAVE_VERSION := 2

var records: Array = []               # Array[AIAgent]
var agents: Array = []                # Array[AIPlayer] currently detailed (minimap)
var tier_counts := [0, 0, 0]
var _rng := RandomNumberGenerator.new()
var _parent: Node = null
var _world = null
var _upkeep_today := 0
var traders_enabled := true           # soak control run: --no-traders
var trip_log: Array = []              # recent trader trips (for the soak report)
var trips_total := 0


func _ready() -> void:
	Market.day_closed.connect(_on_day_closed)


func setup(world_seed: int) -> void:
	_rng.seed = world_seed ^ 0x5eed


func attach(parent: Node, world) -> void:
	_parent = parent
	_world = world
	AdvBrain.world = world


func make_name(taken: Dictionary = {}) -> String:
	var f: Array = GameData.name_parts.get("first", ["Wren"])
	var l: Array = GameData.name_parts.get("last", ["Marsh"])
	for i in 50:
		var n := "%s %s" % [f[_rng.randi() % f.size()], l[_rng.randi() % l.size()]]
		if not taken.has(n):
			taken[n] = true
			return n
	return "Wanderer %d" % taken.size()


func spawn_population(count: int = POPULATION) -> void:
	var pool := []
	for p in GameData.personas:
		for i in int(p.get("count", 1)):
			pool.append(p)
	var taken := {}
	var ids: Array = Market.town_ids
	var seen := {}   # persona id -> instances so far (0.3.1 min_per_town)
	for i in count:
		var a := AIAgent.new()
		a.id = "ai_%d" % i
		a.name = make_name(taken)
		a.persona = pool[i % pool.size()]
		a.rng.seed = _rng.randi()
		a.home_town = _pick_town(a.persona.get("home_weights", {}), ids)
		# 0.3.1 every town keeps its own miners: the first min_per_town x towns
		# of a persona go round-robin (named mines sit by each town; the rest
		# follow home_weights)
		var pid := str(a.persona.get("id", ""))
		var k := int(seen.get(pid, 0))
		seen[pid] = k + 1
		if a.persona.has("herd_share"):   # 0.3.1 every 1/herd_share-th fighter also herds the village cows
			var hs := float(a.persona["herd_share"])
			a.memo["herder"] = 1.0 if floori((k + 1) * hs) > floori(k * hs) else 0.0
		if k < int(a.persona.get("min_per_town", 0)) * ids.size():
			a.home_town = ids[k % ids.size()]
			if a.persona.has("pit_duty"):
				a.memo["duty:pits"] = 1.0   # 0.3.1 this town's own copper/tin digger
		a.town = a.home_town
		var c: Vector2i = _world.gen.town_center(a.home_town) if _world else Vector2i.ZERO
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(10, 45)
		a.home = c + Vector2i(int(cos(ang) * r), int(sin(ang) * r))
		a.pos = c if AIBrain.is_trader(a) else a.home
		_roll_stats(a)
		a.next_trade_tick = _rng.randi_range(1, 60)
		records.append(a)
	# 0.3.1: adventurer-class AI (adv_0..), on top of the 40
	AdvBrain.spawn_all(self, taken, _rng)


func _pick_town(weights: Dictionary, ids: Array) -> String:
	var total := 0.0
	for id in ids:
		total += float(weights.get(id, 0.0))
	if total <= 0.0:
		return ids[_rng.randi() % ids.size()]
	var r := _rng.randf() * total
	for id in ids:
		r -= float(weights.get(id, 0.0))
		if r <= 0.0:
			return id
	return ids[-1]


func _roll_stats(a: AIAgent) -> void:
	var f := a.focus()
	for s in a.skills.xp.keys():
		var lvl := _rng.randi_range(1, 5)
		if f.size() > 0 and s == f[0]:
			lvl = _rng.randi_range(5, 30)
		elif f.size() > 1 and s == f[1]:
			lvl = _rng.randi_range(1, 18)
		if s == "vitality":
			lvl = maxi(10, lvl)
		a.skills.xp[s] = GameData.xp_for_level(lvl)
	if AIBrain.is_fighter(a):
		# fighters train all three combat skills: Strength / Defence near Attack, Vitality 10-18
		var base := a.skills.level("attack")
		for s2 in ["strength", "defence"]:
			a.skills.xp[s2] = GameData.xp_for_level(clampi(base + _rng.randi_range(-4, 2), 1, 30))
		a.skills.xp["vitality"] = GameData.xp_for_level(_rng.randi_range(10, 18))
	a.coins = _rng.randi_range(600, 1600) * (2 if AIBrain.is_trader(a) else 1)
	for s in f:
		if s in ["forestry", "mining", "angling"]:
			var iron := a.skills.level(s) >= 15 and _rng.randf() < 0.5
			var tool := ""
			for id in GameData.items.keys():
				var t: Dictionary = GameData.item(id).get("tool", {})
				if t.get("skill", "") == s and id.begins_with("iron_") == iron:
					tool = id
			if tool != "":
				a.give_tool(tool)
	for item in a.persona.get("sells", []):
		if Market.tradeable(item) and _rng.randf() < 0.6:
			a.stash_add(item, _rng.randi_range(2, 20))
	if AIBrain.is_fighter(a):
		# a starting weapon it can wield: bronze, or iron once Attack / Strength allow
		var opts := []
		for id in ["iron_sword", "iron_battleaxe", "iron_mace", "bronze_sword", "bronze_battleaxe", "bronze_mace", "bronze_dagger"]:
			if Combat.equip_error(a.skills, id) == "" and (opts.is_empty() or id.begins_with("bronze_") or _rng.randf() < 0.5):
				opts.append(id)
		if not opts.is_empty():
			a.give_tool(opts[_rng.randi() % opts.size()])
		for slot_items in [["bronze_cap"], ["bronze_scale_vest"], ["bronze_greaves"], ["alder_buckler"]]:
			if _rng.randf() < 0.5:
				a.give_tool(slot_items[0])
	a.stash_add("cooked_carp", _rng.randi_range(2, 6) + (6 if AIBrain.is_fighter(a) else 0))
	a.stash_add("ash_log", _rng.randi_range(2, 6))


func money_supply() -> int:
	var n := 0
	for a in records:
		n += a.coins
		if a.view:
			n += a.view.inventory.count(GameData.currency)
	return n


# -------------------------------------------------------------------- tick --
func on_tick(t: int, world, player_tile: Vector2i) -> void:
	if t % 10 == 0:
		_update_tiers(player_tile)
	if t % 3 == 0:
		_declutter_labels(player_tile)
	for i in records.size():
		var a: AIAgent = records[i]
		match a.tier:
			0:
				if a.view:
					a.view.on_tick(t, world)
					if a.trip.has("to") and int(a.trip.get("idx", 0)) >= _road(a).size() - 1:
						_arrive(a, t)
			1:
				if (t + i) % 10 == 0:
					_abstract_step(a, 10, t)
					AdvBrain.drift(a, player_tile, t)
			_:
				if (t + i * 7) % 100 == 0:
					_abstract_step(a, 100, t)
		if t >= a.next_trade_tick:
			_trade(a, t)
	if t % 10 == 5 and world != null and world.ground != null and not world.ground.piles.is_empty():
		_abstract_loot(world, t)
	if t % 50 == 25:
		AdvBrain.raid_tick(t, records)    # 0.3.1 off-screen Scorch PK
	if t % 100 == 50:
		AdvBrain.estate_tick(t)           # 0.3.1 estate sales of characters who quit


## Nearby abstract (tier-1) agents sometimes claim public piles close to them.
func _abstract_loot(world, _t: int) -> void:
	var g: GroundItems = world.ground
	var radius := int(GroundItems.rule("ai_loot_radius", 10))
	var chance := GroundItems.rule("abstract_claim_chance", 0.05)
	for a in records:
		if a.tier != 0 and not a.trip.has("to"):
			# 0.3.1: a killer that left the screen still collects the pile private to it (its PK kill)
			for q in g.piles:
				if q["owner"] == a.id and maxi(absi(q["pos"].x - a.pos.x), absi(q["pos"].y - a.pos.y)) <= radius * 3:
					g.loot_to_agent(a, q["pos"], "abstract")
					break
		if a.tier != 1 or a.trip.has("to") or a.activity.get("type", "") == "fight":
			continue
		var found := g.lootable_near(a, a.pos, radius, a.id)
		if not found.is_empty() and a.rng.randf() < chance:
			g.loot_to_agent(a, found[0]["pos"], "abstract")

## Show at most one name label per small screen area (closest to the player wins).
func _declutter_labels(player_tile: Vector2i) -> void:
	var views: Array = []
	for a in records:
		if a.tier == 0 and a.view:
			views.append(a.view)
	views.sort_custom(func(x, y): return (x.tile - player_tile).length_squared() < (y.tile - player_tile).length_squared())
	var shown: Array = []
	for v in views:
		var ok := true
		for q in shown:
			if absi(q.x - v.tile.x) < 5 and absi(q.y - v.tile.y) < 2:
				ok = false
				break
		v.set_label_visible(ok)
		if ok:
			shown.append(v.tile)


func _road(a: AIAgent) -> Array:
	if _world == null or not a.trip.has("to"):
		return []
	return _world.gen.road_between(a.trip["from"], a.trip["to"])


## Traders walk the road at one tile per tick (the same speed as any actor).
func _travel(a: AIAgent, ticks: int, t: int) -> void:
	var road := _road(a)
	if road.is_empty():
		a.trip = {}
		return
	a.trip["idx"] = int(a.trip.get("idx", 0)) + ticks
	a.pos = road[mini(int(a.trip["idx"]), road.size() - 1)]
	if int(a.trip["idx"]) >= road.size() - 1:
		_arrive(a, t)


func _depart(a: AIAgent, to: String, t: int) -> void:
	if _world == null or _world.gen.road_between(a.town, to).is_empty():
		return
	AIBrain.close_out(a)
	a.trip = {"from": a.town, "to": to, "idx": 0, "start": t}
	a.activity = {"type": "travel", "to": to}
	trips_total += 1
	trip_log.append({"tick": t, "agent": a.id, "from": a.town, "to": to, "cargo": a.stash.duplicate()})
	while trip_log.size() > 200:
		trip_log.pop_front()


func _arrive(a: AIAgent, t: int) -> void:
	a.town = a.trip["to"]
	a.trip = {"arrived": t}
	a.activity = {"type": "market", "until": t + 100}
	if a.view == null and _world:
		a.pos = _world.gen.town_center(a.town)
	a.next_trade_tick = t


func _abstract_step(a: AIAgent, ticks: int, t: int) -> void:
	if AIBrain.is_trader(a):
		if a.trip.has("to"):
			_travel(a, ticks, t)
		return
	if a.activity.is_empty() or t >= int(a.activity.get("until", 0)):
		a.activity = AIBrain.choose(a, t)
		_place_for_activity(a)
	AIBrain.simulate(a, ticks, t)


## Nearby agents stand at a real work site so they appear in a sensible spot.
func _place_for_activity(a: AIAgent) -> void:
	if AdvBrain.place(a):
		return     # 0.3.1 adventurers stand at their camp / raid spot in every tier
	if a.tier != 1 or _world == null:
		a.pos = a.home
		return
	var target = null
	match a.activity.get("type", "rest"):
		"gather":
			target = _world.find_gather_node(a.home, a.activity["node"], a.home_town, 40)   # 0.3.1 named mines
		"craft":
			var r := Interactions.recipe_by_id(a.activity.get("recipe", ""))
			var ids := []
			for oid in GameData.objects.keys():
				if not r.is_empty() and GameData.objects[oid].get("station", "") == r["station"]:
					ids.append(oid)
			target = _world.find_nearest_object(_world.gen.town_center(a.town), ids, 40)
		"fight":
			target = _world.find_nearest_object(_world.gen.town_center(a.town), ["training_dummy"], 40)
	a.pos = target.pos if target else a.home


func _trade(a: AIAgent, t: int) -> void:
	if a.view:
		a.view.sync_to_agent()
	if AIBrain.is_trader(a):
		if traders_enabled and not a.trip.has("to"):
			var dest := AIBrain.trader_trade(a, t)
			if dest != "":
				_depart(a, dest, t)
	else:
		AIBrain.trade(a, t)
	if a.view:
		a.view.sync_from_agent()
	a.next_trade_tick = t + 50 + a.rng.randi_range(0, 40)


func _update_tiers(player_tile: Vector2i) -> void:
	var cand := []
	for a in records:
		var p: Vector2i = a.view.tile if a.view else a.pos
		var d := maxi(absi(p.x - player_tile.x), absi(p.y - player_tile.y))
		var limit := DEMOTE_RADIUS_TILES if a.tier == 0 else DETAILED_RADIUS_TILES
		if d <= limit:
			cand.append([d, a])
		elif a.tier == 0:
			_demote(a)
		if a.tier != 0:
			a.tier = 1 if d <= NEARBY_RADIUS else 2
	cand.sort_custom(func(x, y): return x[0] < y[0])
	for i in cand.size():
		var a: AIAgent = cand[i][1]
		if i < MAX_DETAILED:
			if a.tier != 0:
				_promote(a)
		elif a.tier == 0:
			_demote(a)
			a.tier = 1
	tier_counts = [0, 0, 0]
	for a in records:
		tier_counts[a.tier] += 1


func _promote(a: AIAgent) -> void:
	if _parent == null or _world == null:
		return
	var v := AIPlayer.new()
	v.bind(a, _world)
	a.view = v
	a.tier = 0
	_parent.add_child(v)
	agents.append(v)


func _demote(a: AIAgent) -> void:
	if a.view:
		var v: AIPlayer = a.view
		v.unbind()
		agents.erase(v)
		v.queue_free()
	a.tier = 1


func _on_day_closed(_day: int) -> void:
	var total := 0
	for a in records:
		if a.view:
			a.view.sync_to_agent()
		total += AIBrain.upkeep(a) + AIBrain.daily_needs(a)
		AIBrain.bury_surplus(a)
	_upkeep_today = total
	if total > 0:
		Market.record_sink(total)


# ---------------------------------------------------------- offline catch-up --
## Fast-forward `ticks` ticks starting after tick `t0`: abstract steps for every
## agent (100-tick granularity), Exchange housekeeping and day rollovers.
## Returns a summary for the "While you were away" report.
func simulate_offline(ticks: int, t0: int, player_id: String = "player") -> Dictionary:
	for a in records:
		if a.tier == 0:
			_demote(a)
		a.tier = 2
	var mine := {"bought": {}, "sold": {}, "coins": 0}
	var on_trade := func(_town: String, item: String, q: int, price: int, buyer: String, seller: String) -> void:
		if buyer == player_id:
			mine["bought"][item] = int(mine["bought"].get(item, 0)) + q
		if seller == player_id:
			mine["sold"][item] = int(mine["sold"].get(item, 0)) + q
			mine["coins"] = int(mine["coins"]) + q * price
	Market.trade_executed.connect(on_trade)
	var days := {"n": 0}
	var day_cb := func(_d: int) -> void: days["n"] += 1
	Market.day_closed.connect(day_cb)
	var end := t0 + ticks
	var t := t0
	while t < end:
		t += 1
		if t % 50 == 0:
			Market.on_tick(t)
		if t % 100 == 0:
			for a in records:
				_abstract_step(a, 100, t)
		if t % 100 == 50:
			for a in records:
				if t >= a.next_trade_tick:
					_trade(a, t)
		if t % 50 == 25:
			AdvBrain.raid_tick(t, records)
		if t % 100 == 50:
			AdvBrain.estate_tick(t)
	Market.trade_executed.disconnect(on_trade)
	Market.day_closed.disconnect(day_cb)
	return {"ticks": ticks, "end_tick": end, "days": int(days["n"]), "player": mine}


# -------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	var out := []
	for a in records:
		if a.view:
			a.view.sync_to_agent()
			# pack contents stay with the view; save them into the stash copy
			var copy: Dictionary = a.to_save()
			var st: Dictionary = copy["stash"].duplicate()
			for s in a.view.inventory.slots:
				if s != null and not GameData.item(s["id"]).has("tool"):
					if s["id"] == GameData.currency:
						copy["coins"] = int(copy["coins"]) + int(s["qty"])
					else:
						st[s["id"]] = int(st.get(s["id"], 0)) + int(s["qty"])
			copy["stash"] = st
			copy["pos"] = [a.view.tile.x, a.view.tile.y]
			out.append(copy)
		else:
			out.append(a.to_save())
	return {"version": SAVE_VERSION, "agents": out, "adv": AdvBrain.to_save(), "gear_econ": GearEconomy.to_save()}


func from_save(d: Dictionary) -> void:
	if int(d.get("version", 1)) < SAVE_VERSION:
		return   # M1 saves: keep the freshly spawned population
	var by_id := {}
	for a in records:
		by_id[a.id] = a
	for s in d.get("agents", []):
		var a: AIAgent = by_id.get(str(s.get("id", "")), null)
		if a:
			a.from_save(s)
	AdvBrain.from_save(d.get("adv", {}))
	GearEconomy.from_save(d.get("gear_econ", {}))


func clear() -> void:
	for a in records:
		if a.view and is_instance_valid(a.view):
			a.view.queue_free()
		a.view = null
	agents.clear()
	records.clear()
	AdvBrain.reset()
	GearEconomy.reset()
