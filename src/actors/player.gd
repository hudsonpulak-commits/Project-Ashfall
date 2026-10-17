class_name Player
extends Actor
## The human player. Same rules as AI players; adds messages, UI events and
## tap/keyboard orders.


func _init() -> void:
	super._init()
	actor_id = "player"
	display_name = "You"
	sprite_id = "player"
	skills.xp_gained.connect(func(s, a): Events.xp_gained.emit(s, a))
	skills.leveled.connect(_on_level)
	inventory.changed.connect(func(): Events.inventory_changed.emit())
	set_town("fenhollow")
	status_changed.connect(func(t): Events.action_changed.emit(t))
	energy = max_energy()


# ------------------------------------------------------------- equipment --
const SLOTS := ["head", "body", "legs", "shield", "weapon"]
const DEATH_COIN_FEE := 0.10       # share of carried coin the town healer keeps (sink)
var equipment: Dictionary = {}      # slot -> item id
var deaths := 0
var energy := 100.0                 # sprint stamina (data/player.json)
var sprint := false                 # sprint toggle (tap the Energy bar)
var world_ref = null
var zone_seen: Dictionary = {}       # 0.3.1 PK zones already warned about (first-crossing banner)
var map_markers := MapMarkers.new()   # 0.3.1 custom world-map pins


## 0.3.1: worn gear is drawn as layers on the player sprite (Actor._refresh_gear_visual).
func gear_worn() -> Dictionary:
	return equipment


func _gear_sum(stat: String) -> int:
	var n := 0
	for slot in equipment.keys():
		n += int(GameData.item(equipment[slot]).get("gear", {}).get(stat, 0))
	return n


func combat_atk() -> int:
	return _gear_sum("atk")


func combat_str() -> int:
	return _gear_sum("str")


func combat_def() -> int:
	return _gear_sum("def")


func weapon_id() -> String:
	var w: String = equipment.get("weapon", "")
	return w if w != "" else super.weapon_id()


func weapon_power() -> float:
	var w: String = equipment.get("weapon", "")
	if w != "" and GameData.item(w).get("gear", {}).get("style", "melee") != "melee":
		return 0.0     # bows: ranged combat is a later milestone
	return super.weapon_power()


func armour_ids() -> Array:
	var out := []
	for slot in Combat.ARMOUR_SLOTS:
		if equipment.has(slot):
			out.append(equipment[slot])
	return out


## Accurate (Attack XP) or Aggressive (Strength XP); the player can switch any time.
func set_style(style: String) -> void:
	combat_style = style


## Equip the gear in pack slot i (the worn piece goes back to the pack).
func equip_slot(i: int) -> String:
	var s = inventory.slots[i]
	if s == null:
		return ""
	var id: String = s["id"]
	var gd: Dictionary = GameData.item(id).get("gear", {})
	if gd.is_empty() or not (gd.get("slot", "") in SLOTS):
		return "You can't wear that."
	var why := Combat.equip_error(skills, id)
	if why != "":
		return why
	var slot: String = gd["slot"]
	if slot == "weapon":
		combat_style = Combat.default_style(id)   # style follows the new weapon (switchable)
	inventory.remove_at(i)
	if equipment.has(slot):
		inventory.add(equipment[slot])
	equipment[slot] = id
	Events.inventory_changed.emit()
	return ""


func unequip(slot: String) -> String:
	if not equipment.has(slot):
		return ""
	if inventory.room_for(equipment[slot]) <= 0:
		return "Your pack is full."
	inventory.add(equipment[slot])
	equipment.erase(slot)
	Events.inventory_changed.emit()
	return ""


func bury_slot(i: int) -> int:
	var s = inventory.slots[i]
	if s == null:
		return 0
	var xp := int(GameData.item(s["id"]).get("bury_xp", 0))
	if xp <= 0:
		return 0
	var share := float(GameData.item(s["id"]).get("prayer_restore", 0.0))
	inventory.remove_at(i)
	skills.add_xp("prayer", xp)
	Prayer.restore(prayer, skills.level("prayer"), share)
	return xp


func drop_slot(i: int, t: int) -> void:
	var s = inventory.slots[i]
	if s == null or world_ref == null:
		return
	world_ref.ground.add(tile, s["id"], int(s["qty"]), t, -1, actor_id)
	inventory.remove_at(i)


## Death: respawn at the nearest town with full HP. Worn equipment is kept.
## The town healer keeps 10 % of the coin you carried (a sink); everything
## else in your pack is left in a pile where you fell, visible only to you,
## for 30 minutes (3000 ticks). Banked items are never at risk.
func die(t: int) -> void:
	if PkRules.is_pk(tile):
		_pk_die(t)
		return
	deaths += 1
	var w = world_ref
	var town: String = w.gen.nearest_town(tile) if w else current_town
	var fee := 0
	if w:
		for i in inventory.size():
			var s = inventory.slots[i]
			if s == null:
				continue
			var q := int(s["qty"])
			if s["id"] == GameData.currency:
				fee = int(ceil(q * DEATH_COIN_FEE))
				q -= fee
			w.ground.add(tile, s["id"], q, t, GroundItems.death_ttl(), actor_id, -1)
		inventory.clear()
		Market.record_sink(fee)
	action = {}
	path.clear()
	cancel_travel()
	hp = max_hp()
	var spot := tile
	if w:
		place_at(w.find_free_tile_near(w.gen.town_spawn(town), 4))
		set_town(town)
	say("Oh dear, you are dead! You wake in %s. Your pack lies where you fell (%d, %d) for 30 minutes%s." % [
		w.gen.town_name(town) if w else town, spot.x, spot.y, ("; the healer took %d marks" % fee) if fee > 0 else ""])
	Events.player_hp_changed.emit(hp, max_hp())


# ------------------------------------------------------------- 0.3.1 PK --
var char_name := "Adventurer"     # 0.3.2: the name chosen on New Game (save slot list)
var pk_warned := false             # the first-crossing warning was shown
var _was_pk := false


## Death in a PK zone: keep the 3 most valuable item units (worn or packed;
## none while skulled); everything else, plus carried coin after the healer's
## 10 %, drops in a pile private to the killer for a while, then public.
func _pk_die(t: int) -> void:
	deaths += 1
	var w = world_ref
	var killer = last_attacker
	var skulled := is_skulled(t)
	var units := []
	var coins := 0
	for i in inventory.size():
		var sl = inventory.slots[i]
		if sl == null:
			continue
		if sl["id"] == GameData.currency:
			coins += int(sl["qty"])
			continue
		for k in int(sl["qty"]):
			units.append({"id": sl["id"], "slot": "", "dur": int(sl.get("dur", -1))})
	for slot in SLOTS:
		if equipment.has(slot):
			units.append({"id": equipment[slot], "slot": slot, "dur": -1})
	var ids := []
	for u in units:
		ids.append(u["id"])
	var keep := PkRules.kept_indices(ids, PkRules.keep_count(skulled))
	var lost := []
	var kept_names := []
	inventory.clear()
	equipment.clear()
	for i in units.size():
		var u: Dictionary = units[i]
		if i in keep:
			kept_names.append(GameData.item_name(u["id"]).to_lower())
			if u["slot"] != "":
				equipment[u["slot"]] = u["id"]
			else:
				inventory.add(u["id"], 1, int(u["dur"]))
		else:
			lost.append(u["id"])
	var fee := int(ceil(coins * PkRules.coin_fee()))
	Market.record_sink(fee)
	PkRules.tally("coin_dropped", coins)
	PkRules.tally("coin_fee", fee)
	PkRules.tally("items_dropped", lost.size())
	var spot := tile
	var own: Array = PkRules.pile_owner_and_private(killer, actor_id)
	if w:
		PkRules.drop_pile(w.ground, spot, lost, coins - fee, own[0], own[1], t)
	var kname := CombatRules.label(killer) if killer != null and is_instance_valid(killer) else "something"
	PkRules.log_event({"tick": t, "kind": "player_death", "killer": kname, "kept": kept_names.duplicate(), "lost": lost.size(), "coins": coins - fee, "skulled": skulled, "pos": [spot.x, spot.y]})
	pk_last_death = {"tick": t, "kept": keep.map(func(i): return ids[i]), "lost": lost.duplicate(), "coins": coins - fee, "fee": fee, "owner": own[0], "skulled": skulled, "pos": [spot.x, spot.y]}
	action = {}
	path.clear()
	cancel_travel()
	hp = max_hp()
	prayer.erase("id")
	var town: String = w.gen.nearest_town(spot) if w else current_town
	if w:
		place_at(w.find_free_tile_near(w.gen.town_spawn(town), 4))
		set_town(town)
	Events.inventory_changed.emit()
	var kept_txt := ("You kept: %s." % ", ".join(kept_names)) if not kept_names.is_empty() else ("You were skulled, so you kept nothing." if skulled else "You had nothing worth keeping.")
	say("You were killed by %s in the Scorch. %s Everything else lies where you fell (%d, %d)%s." % [kname, kept_txt, spot.x, spot.y,
		("; the healer took %d marks" % fee) if fee > 0 else ""])
	Events.player_hp_changed.emit(hp, max_hp())


var pk_last_death: Dictionary = {}   # QA / tests: what the last PK death kept and dropped


func on_pvp_kill(victim, t: int) -> void:
	super.on_pvp_kill(victim, t)
	var nm: String = victim.quit_name if victim is AIPlayer and victim.quit_name != "" else CombatRules.label(victim)
	say("You have defeated %s." % nm)


func set_skull(until: int) -> void:
	var was := is_skulled(Tick.tick_count)
	super.set_skull(until)
	if not was:
		Events.say("You attacked first: you are skulled for %d minutes and will keep nothing if you die." % int(PkRules.cfg().get("skull_minutes", 10)), "warn")


## Entering a PK zone the first time: the rules card (chat + banner: ZoneBanner).
func _pk_tick() -> void:
	var now_pk := PkRules.is_pk(tile)
	if now_pk == _was_pk:
		return
	_was_pk = now_pk
	if now_pk:
		# chat lines + the banner/skull row come from ZoneBanner (world track); this adds the rules card once
		if not pk_warned and bool(PkRules.cfg().get("warn_once", true)):
			pk_warned = true
			Events.report_ready.emit(str(PkRules.cfg().get("warning_title", "The Scorch")), str(PkRules.cfg().get("warning_text", "")))


## The AI player drawn on / just below the tapped tile (they are 1.5 tiles tall).
func ai_near_tap(p: Vector2i):
	for a in AIDirector.agents:
		if is_instance_valid(a) and not a.dead and a.tile == p:
			return a
	for a in AIDirector.agents:
		if is_instance_valid(a) and not a.dead and a.tile == p + Vector2i(0, 1):
			return a
	return null


func take_hit(dmg: int, attacker, t: int) -> void:
	super.take_hit(dmg, attacker, t)
	Events.player_hp_changed.emit(hp, max_hp())


func on_kill(enemy, t: int) -> void:
	super.on_kill(enemy, t)
	say("You defeat the %s." % CombatRules.label(enemy).to_lower())


## Each town's bank chest opens that town's own vault (goods don't teleport).
var vaults: Dictionary = {}       # town id -> ItemContainer
var current_town: String = ""


func set_town(id: String) -> void:
	if id == "" or id == current_town:
		return
	if not vaults.has(id):
		var v := ItemContainer.new(400, true)
		v.changed.connect(func(): if bank == v: Events.bank_changed.emit())
		vaults[id] = v
	current_town = id
	bank = vaults[id]
	Events.bank_changed.emit()
	Events.town_changed.emit(id)


func on_tick(t: int, world) -> void:
	world_ref = world
	var hp0 := hp
	super.on_tick(t, world)
	_energy_tick()
	if hp != hp0:
		Events.player_hp_changed.emit(hp, max_hp())
	if action.get("kind", "") == "pickup" and path.is_empty():
		if tile == action["pos"]:
			var n: int = world.ground.pick_up(self, tile)
			say("You pick up %d item%s." % [n, "" if n == 1 else "s"] if n > 0 else "There's nothing here you can carry.")
		action = {}
	_travel_step(world)
	var here: String = world.gen.town_at(tile, 8)
	if here != "":
		set_town(here)
	_shop_tick(world, t)
	_pk_tick()


# ------------------------------------------------------ 0.3.0 buildings --
var _in_building := ""
var _greeted: Dictionary = {}     # building id -> msec of the last greeting


## Entering your own shop reports what sold since you last looked; auto-bank
## moves the till into that town's vault.
func _shop_tick(world, t: int) -> void:
	var b: Dictionary = world.gen.building_at(tile)
	var bid: String = b["id"] if not b.is_empty() and world.gen.is_inside(tile, b) else ""
	if bid != _in_building:
		_in_building = bid
		if bid != "" and b["kind"] in ["smithy", "church", "house", "cookhouse"] and str(action.get("kind", "")) != "shop":
			smith_greet(world, b)
		elif bid != "" and b["kind"] == "player":
			var ps := Market.player_shop(b["town"])
			if ps.owned and int(ps.unseen["qty"]) > 0:
				var u := ps.take_unseen()
				say("Sold %d item%s for %d marks while you were away. Till: %d marks." % [int(u["qty"]), "" if int(u["qty"]) == 1 else "s", int(u["coins"]), ps.till])
	if t % 25 == 0:
		for town_id in Market.player_shops.keys():
			var ps: PlayerShop = Market.player_shops[town_id]
			if ps.owned and ps.auto_bank and ps.till > 0:
				if not vaults.has(town_id):
					var cur := current_town
					set_town(town_id)
					set_town(cur)
				var got: int = vaults[town_id].add(GameData.currency, ps.till)
				ps.till -= got
				PlayerShop.version += 1


## 0.3.0 Blacksmith: the smith calls out when you walk in (not when you came
## straight for the counter: the counter greeting covers that).
func smith_greet(world, b: Dictionary) -> String:
	var key := str(b["id"]) + ":enter"
	var now := Time.get_ticks_msec()
	if now - int(_greeted.get(key, -1000000)) < int(float(GameData.buildings_cfg.get("greet_cooldown_s", 20)) * 1000.0):
		return ""
	_greeted[key] = now
	var lines: Array = GameData.buildings_cfg.get("smithy", {}).get("enter_greet", [])
	if b["kind"] == "church":
		lines = GameData.churches.get("enter_greet", [])
	elif b["kind"] == "house":
		lines = GameData.villages_cfg.get("enter_greet", [])
	elif b["kind"] == "cookhouse":
		lines = GameData.buildings_cfg.get("cookhouse", {}).get("enter_greet", [])
	if lines.is_empty():
		return ""
	var line: String = lines[randi() % lines.size()]
	if world and world.buildings_view:
		world.buildings_view.keeper_say(b, line)
	return line


## A keeper line (data/buildings.json), at most every greet_cooldown_s per shop.
func greet(world, b: Dictionary) -> String:
	var now := Time.get_ticks_msec()
	if now - int(_greeted.get(b["id"], -1000000)) < int(float(GameData.buildings_cfg.get("greet_cooldown_s", 20)) * 1000.0):
		return ""
	_greeted[b["id"]] = now
	var lines: Array = GameData.buildings_cfg.get("shops", {}).get(b["shop"], {}).get("greet", [])
	if b["kind"] == "player" and Market.player_shop(b["town"]).owned:
		lines = GameData.buildings_cfg.get("owned_greet", [])
	if b["kind"] == "church":
		lines = GameData.churches.get("greet", [])
	elif b["kind"] == "house":
		lines = GameData.villages_cfg.get("greet", [])
	if lines.is_empty():
		return ""
	var line := str(lines[absi(hash([b["id"], Tick.tick_count])) % lines.size()])
	if world.buildings_view:
		world.buildings_view.keeper_say(b, line)
	return line


# ------------------------------------------------------------ energy --
static func energy_cfg() -> Dictionary:
	return GameData.player_cfg.get("energy", {})


func max_energy() -> float:
	return float(energy_cfg().get("max", 100.0))


func sprint_steps() -> int:
	return int(energy_cfg().get("sprint_tiles_per_tick", 2)) - 1 if sprint and energy > 0.0 else 0


## Toggle sprint. Returns the message to show.
func set_sprint(on: bool) -> String:
	if on and energy < float(energy_cfg().get("min_to_start", 1)):
		sprint = false
		return "You're too tired to run."
	sprint = on
	return "Sprint on." if on else "Sprint off."


## Per tick: sprint-moving drains; otherwise regen (slow while walking or
## busy, faster when fully idle). Clamped to 0..max.
func _energy_tick() -> void:
	var c := energy_cfg()
	if dead:
		return
	if sprint and last_steps > 0:
		energy -= float(c.get("sprint_drain", 0.5))
	elif last_steps > 0 or not action.is_empty() or not path.is_empty():
		energy += float(c.get("regen_active", 0.15))
	else:
		energy += float(c.get("regen_idle", 0.4))
	energy = clampf(energy, 0.0, max_energy())
	if sprint and energy <= 0.0:
		sprint = false
		say("You're out of energy and slow to a walk.")


func vault_coins() -> int:
	var n := 0
	for v in vaults.values():
		n += v.count(GameData.currency)
	return n


func to_save() -> Dictionary:
	var d := super.to_save()
	var vs := {}
	for k in vaults.keys():
		vs[k] = vaults[k].to_save()
	d["vaults"] = vs
	d["town"] = current_town
	d["equipment"] = equipment.duplicate()
	d["deaths"] = deaths
	d["combat_style"] = combat_style
	d["energy"] = energy
	d["sprint"] = sprint
	d["zone_seen"] = zone_seen.duplicate()
	d["char_name"] = char_name
	d["map_markers"] = map_markers.to_save()
	d["skull_until"] = skull_until
	d["pk_warned"] = pk_warned
	return d


func from_save(d: Dictionary) -> void:
	super.from_save(d)   # legacy "bank" lands in the current (Fenhollow) vault
	char_name = str(d.get("char_name", "Adventurer"))
	for k in d.get("vaults", {}).keys():
		var keep := current_town
		set_town(k)
		vaults[k].from_save(d["vaults"][k])
		set_town(keep)
	if d.has("town"):
		set_town(str(d["town"]))
	equipment = d.get("equipment", {}).duplicate()
	deaths = int(d.get("deaths", 0))
	combat_style = str(d.get("combat_style", ""))
	energy = clampf(float(d.get("energy", max_energy())), 0.0, max_energy())   # old saves start full
	sprint = bool(d.get("sprint", false)) and energy > 0.0
	zone_seen = (d.get("zone_seen", {}) as Dictionary).duplicate()
	map_markers.from_save(d.get("map_markers", {}))
	skull_until = int(d.get("skull_until", -1))
	pk_warned = bool(d.get("pk_warned", false))
	_was_pk = PkRules.is_pk(tile)


func give_starter_kit() -> void:
	inventory.clear()
	inventory.add("bronze_hatchet")
	inventory.add("bronze_pick")
	inventory.add("reed_rod")
	inventory.add("bronze_sword")
	inventory.add(GameData.currency, 25)


func _on_level(skill_id: String, lvl: int) -> void:
	Events.level_up.emit(skill_id, lvl)
	Events.say("%s level %d!" % [GameData.skill_by_id[skill_id]["name"], lvl], "level")


func say(text: String) -> void:
	Events.say(text)


func on_bank(_world, _obj) -> void:
	Events.bank_opened.emit()


func on_exchange(_world, _obj) -> void:
	Events.exchange_opened.emit()


func on_shop(world, obj) -> void:
	var b: Dictionary = world.gen.buildings.get(str(obj.meta.get("building", "")), {}) if world else {}
	if not b.is_empty():
		var line := greet(world, b)
		if b["kind"] in ["church", "house"]:   # 0.3.1 the priest / villagers talk; no shop panel
			if line != "":
				say("%s: %s" % [b["keeper"], line])
			return
		if b["kind"] == "player":
			Events.player_shop_opened.emit(str(b["town"]), -1)
			return
	Events.shop_opened.emit(obj.shop_id())


func on_display(world, obj) -> void:
	var town := str(obj.meta.get("town", current_town))
	if not Market.player_shop(town).owned:
		say("An empty display stand. Buy the shop at the counter to stock it.")
		return
	Events.player_shop_opened.emit(town, int(obj.meta.get("slot", 0)))


func wants_recipe_choice() -> bool:
	return true


func on_station_menu(station: String, obj) -> void:
	Events.station_opened.emit(station, obj.pos)


func on_hitsplat(obj, dmg: int) -> void:
	Events.hitsplat.emit(obj, obj.pos, dmg)


## Tap on a tile: interact with an object there, else walk.
# ------------------------------------------------------------ road travel --
var travel_route: Array = []
var travel_idx := -1
var travel_to := ""


## Walk to a town along the road network: path to the nearest point of a road
## that ends at `dest`, then follow it tile by tile, then into the town square.
func start_travel(world, dest: String) -> bool:
	var best: Array = []
	var best_i := -1
	var best_d := 1 << 30
	for from in world.gen.towns.keys():
		if from == dest:
			continue
		var road: Array = world.gen.road_between(from, dest)
		for i in range(0, road.size(), 2):
			var d: int = maxi(absi(road[i].x - tile.x), absi(road[i].y - tile.y))
			if d < best_d:
				best_d = d
				best = road
				best_i = i
	if best.is_empty() or best_d > 60:
		say("Get onto a road first (the map shows them).")
		return false
	travel_route = best
	travel_idx = best_i
	travel_to = dest
	if not walk_to(world, best[best_i]):
		travel_route = []
		say("You can't reach the road from here.")
		return false
	say("You set off for %s." % world.gen.town_name(dest))
	return true


func _travel_step(world) -> void:
	if travel_route.is_empty() or not path.is_empty() or not action.is_empty():
		return
	if travel_idx >= 0 and tile == travel_route[travel_idx]:
		path = travel_route.slice(travel_idx + 1)
		travel_idx = -1
		if path.is_empty():
			travel_idx = -2
		return
	# end of the road (or interrupted): finish into the town square
	var dest := travel_to
	travel_route = []
	travel_to = ""
	if travel_idx == -1 or travel_idx == -2:
		walk_to(world, world.gen.town_spawn(dest))


func cancel_travel() -> void:
	travel_route = []
	travel_idx = -1
	travel_to = ""


func combat_blocked(why: String) -> void:
	say(why)


func handle_tap(world, p: Vector2i) -> void:
	cancel_travel()
	world_ref = world
	var foe = world.enemies.enemy_near_tap(p) if world.enemies else null
	if foe != null:
		var why := CombatRules.can_attack(self, foe, Tick.tick_count)
		if why != "":
			say("%s %s" % [foe.display_name_level(), why])
			return
		attack(foe)
		say("You attack the %s (level %d)." % [foe.display_name().to_lower(), foe.level()])
		return
	# 0.3.1: in a PK zone, tapping an AI player attacks them
	var rival = ai_near_tap(p)
	if rival != null and (PkRules.is_pk(tile) or PkRules.is_pk(rival.tile)):
		var why2 := PkRules.can_pvp(self, rival, Tick.tick_count)
		if why2 != "":
			say(why2)
			return
		attack(rival)
		say("You attack %s." % rival.display_name)
		return
	if world.ground and not world.ground.at(p, actor_id).is_empty():
		if tile == p or walk_to(world, p):
			action = {"kind": "pickup", "pos": p}
		return
	var bt: Dictionary = world.gen.building_at(p)
	if not bt.is_empty() and p == (bt["keeper_at"] as Vector2i) + Vector2i(0, -1):
		p = bt["keeper_at"]    # tapped the keeper's head (it overhangs the tile above)
	var obj: WorldObject = world.object_at(p)
	if obj != null and obj.def().get("type", "") == "scenery" and not obj.blocks():
		obj = null    # 0.3.1 decor you can stand on (embers, charred stumps): just walk there
	if obj != null and not obj.def().is_empty():
		var d := obj.def()
		if interact(world, obj):
			var t: String = d.get("type", "")
			if t == "gather":
				say("%s the %s." % [d.get("verb", "Use"), obj.display_name().to_lower()])
			elif t == "bank":
				say("You head to the bank chest.")
		else:
			say("You can't reach that.")
		return
	if not walk_to(world, p):
		say("You can't walk there.")


## One-tile keyboard step (desktop convenience).
func step_dir(world, dir: Vector2i) -> void:
	var n := tile + dir
	if not world.is_blocked(n):
		action = {}
		set_status("")
		path = [n]
