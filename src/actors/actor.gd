class_name Actor
extends Node2D
## Anything that walks the tile grid and does skilling: the player AND the AI
## players share this class, so AI gets exactly the same rules (pathing,
## gathering odds, inventory limits, tool wear) as the human.

signal status_changed(text: String)

var actor_id: String = "actor"
var display_name: String = "Someone"
var tile := Vector2i.ZERO
var prev_tile := Vector2i.ZERO
var path: Array = []                  # Array[Vector2i]
var action: Dictionary = {}           # {} = idle. {"pos": Vector2i, "kind": String, ...}
var skills: Skills
var inventory: ItemContainer
var bank: ItemContainer
var rng := RandomNumberGenerator.new()
var sprite_id: String = "player"
var tint := Color.WHITE

# --- combat (see src/combat/combat.gd)
var hp := 11
var dead := false
var next_attack := 0
var last_combat_tick := -1000
var combat_foe = null                # Enemy we are engaged with (CombatRules)
var auto_retaliate := true
var prayer: Dictionary = {}           # Prayer buff state (see src/combat/prayer.gd)
var combat_style := ""                # "accurate" / "aggressive"; "" = follow the weapon class default
var last_steps := 0                   # tiles moved this tick (sprint = 2)
# --- 0.3.1 PK (see src/combat/pk_rules.gd)
var skull_until := -1                 # tick the skull wears off (-1 = never skulled)
var pvp_aggr: Dictionary = {}         # actor id -> tick they first struck us (skull / retaliation)
var last_attacker = null              # who hit us last (Actor or Enemy): the killer on death

var _sprite: Sprite2D
var _layers: Dictionary = {}          # 0.3.1 visible gear: slot -> Sprite2D over the body
var _layer_key := ""
var _world_ref = null
var _anim_t := 0.0
var _pose := ""          # restyle: "attack" / "shoot" while a one-shot pose plays
var _pose_t := 0.0
var _pose_shown := ""
var facing := Facing.new()            # 0.3.0: immediate facing from this tick's movement
var _tick_now := 0
var _last_move_t := -100000           # last tick we moved (anim grace)
var path_line: Array = []             # 0.3.0 parallel to path: [from, to, k, n, tile] straight-line info
var _vis_last := Vector2.INF          # where the sprite stood at the end of last tick (world px)
var _vis_pts: Array = []              # this tick's sprite waypoints (1 + steps) on the straight line


var _shown_dir := "side"


func _init() -> void:
	skills = Skills.new()
	inventory = ItemContainer.new(24, false)
	bank = ItemContainer.new(400, true)


func _ready() -> void:
	add_to_group("actors")
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = GameData.texture("actors", sprite_id)
	var fs := GameData.frame_size("actors", sprite_id)
	_sprite.hframes = maxi(1, GameData.frame_count("actors", sprite_id))
	_sprite.offset = Vector2(-fs.x / 2.0, -fs.y)
	_sprite.modulate = tint
	add_child(_sprite)
	_update_visual_position()


func max_hp() -> int:
	return Combat.max_hp(skills)


func place_at(p: Vector2i) -> void:
	tile = p
	prev_tile = p
	path.clear()
	path_line.clear()
	_vis_last = foot_px(p)
	_vis_pts = [_vis_last]
	_update_visual_position()


func say(_text: String) -> void:
	pass   # player overrides; AI is silent (M2: overhead chat bubbles)


func set_status(text: String) -> void:
	status_changed.emit(text)


func is_adjacent_to(p: Vector2i) -> bool:
	var d := (p - tile).abs()
	return maxi(d.x, d.y) == 1


# ------------------------------------------------------------------ orders --
func walk_to(world, dest: Vector2i) -> bool:
	action = {}
	set_status("")
	var goals: Array = [dest]
	if world.is_blocked(dest):
		# tapped water/a rock: aim for the closest walkable ring around it
		goals = []
		for r in range(1, 6):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) == r and not world.is_blocked(dest + Vector2i(dx, dy)):
						goals.append(dest + Vector2i(dx, dy))
			if not goals.is_empty():
				break
	set_path(world, Pathfinder.find_path(world, tile, goals, dest))
	return not path.is_empty() or tile == dest


## Use an A* path, straightened into evenly spread straight grid lines.
func set_path(world, raw: Array) -> void:
	var st := Pathfinder.straighten(world, tile, raw)
	path = st["tiles"]
	path_line = []
	for i in path.size():
		path_line.append(st["lines"][i] + [path[i]])


func interact(world, obj: WorldObject) -> bool:
	action = {"pos": obj.pos, "kind": obj.def().get("type", ""), "progress": 0, "cooldown": 0}
	if obj.meta.has("stand"):
		# 0.3.0 shop counter / keeper: walk (through the door) to the tile in front of the counter
		var st: Vector2i = obj.meta["stand"]
		if tile == st:
			path.clear()
			return true
		set_path(world, Pathfinder.find_path(world, tile, [st], st))
		if path.is_empty():
			action = {}
			return false
		return true
	if is_adjacent_to(obj.pos) or (not obj.blocks() and tile == obj.pos):
		path.clear()
		return true
	var goals: Array = Pathfinder.interaction_tiles(obj.pos)
	if not obj.blocks():
		goals.append(obj.pos)
	set_path(world, Pathfinder.find_path(world, tile, goals, obj.pos))
	if path.is_empty():
		action = {}
		return false
	return true


func stop() -> void:
	path.clear()
	path_line.clear()
	action = {}
	set_status("")


# ------------------------------------------------- interaction callbacks --
## Default (AI) behaviour: bank everything except tools and coin.
func on_bank(_world, _obj) -> void:
	deposit_all(true)


func on_exchange(_world, _obj) -> void:
	pass


func on_shop(_world, _obj) -> void:
	pass


func on_display(_world, _obj) -> void:
	pass


## Player returns true (opens a recipe menu); AI picks automatically.
func wants_recipe_choice() -> bool:
	return false


func on_station_menu(_station: String, _obj) -> void:
	pass


func on_crafted(_recipe: Dictionary) -> void:
	pass


## Start crafting a specific recipe at the station on `pos` (count -1 = all).
func start_recipe(world, obj, recipe_id: String, count: int = -1) -> bool:
	if not interact(world, obj):
		return false
	action["recipe"] = recipe_id
	action["count"] = count
	return true


## 0.4.0 Fletching (knife) / Crafting (needle) worked from the pack, in place.
func start_pack_recipe(station: String, recipe_id: String, count: int = -1) -> bool:
	var r := Interactions.recipe_by_id(recipe_id)
	if r.is_empty() or str(r.get("station", "")) != station:
		return false
	path.clear()
	action = {"kind": "pack_craft", "station": station, "recipe": recipe_id, "count": count, "progress": 0, "cooldown": 0}
	return true


func on_hitsplat(_obj, _dmg: int) -> void:
	pass


## Moves every pack item into the bank. Returns the number of items moved.
func deposit_all(keep_tools: bool = false) -> int:
	var moved := 0
	for i in inventory.size():
		var s = inventory.slots[i]
		if s == null:
			continue
		if keep_tools and (GameData.item(s["id"]).has("tool") or s["id"] == GameData.currency):
			continue
		moved += deposit_slot(i)
	return moved


func deposit_slot(i: int) -> int:
	var s = inventory.slots[i]
	if s == null:
		return 0
	var n := bank.add(s["id"], int(s["qty"]), int(s.get("dur", -1)))
	if n > 0:
		inventory.remove_at(i)
	return n


## Withdraw up to qty of item id from the bank (bank slot index).
func withdraw(bank_index: int, qty: int) -> int:
	var s = bank.slots[bank_index]
	if s == null:
		return 0
	var id: String = s["id"]
	var n := mini(qty, mini(int(s["qty"]), inventory.room_for(id)))
	if n <= 0:
		return 0
	var got := inventory.add(id, n, int(s.get("dur", -1)))
	if got > 0:
		if int(s["qty"]) <= got:
			bank.remove_at(bank_index)
		else:
			s["qty"] = int(s["qty"]) - got
			bank.changed.emit()
	return got


# ------------------------------------------------------------------ combat --
## Gear bonuses; Player reads its equipment, AIPlayer its agent's gear.
func combat_atk() -> int:
	return 0


func combat_str() -> int:
	return 0


func combat_def() -> int:
	return 0


## 0.4.0 Ranged uses the bow plus ranger gear ("rng"); melee armour atk/str
## don't help a bow. AI keeps its abstract gear stats.
func ranged_atk() -> int:
	return combat_atk()


func ranged_str() -> int:
	return combat_str()


## The weapon this actor fights with: the strongest melee weapon in the pack
## it has the level to use ("" = bare hands). Player overrides (worn weapon).
func weapon_id() -> String:
	var best := ""
	var best_p := -1.0
	for s in inventory.slots:
		if s == null:
			continue
		var it := GameData.item(s["id"])
		if it.get("tool", {}).get("skill", "") != "melee":
			continue
		var bow := Combat.is_ranged(s["id"])
		if not bow and it.get("gear", {}).get("style", "melee") != "melee":
			continue
		if Combat.equip_error(skills, s["id"]) != "":
			continue
		# 0.3.3: a bow counts only with arrows to shoot; it wins ties over melee
		if bow and ammo_arrow() == "":
			continue
		var p := float(it["tool"].get("power", 0)) + (0.5 if bow else 0.0)
		if p > best_p:
			best_p = p
			best = s["id"]
	return best


## 0.3.6 the arrows this actor fires. AI archers: best usable stack in the pack;
## the Player overrides this with its equipped ammo slot only.
func ammo_arrow() -> String:
	return Combat.best_arrow(inventory, skills)


func use_ammo(arrow: String) -> void:
	inventory.remove(arrow, 1)


func weapon_power() -> float:
	var w := weapon_id()
	return float(GameData.item(w).get("tool", {}).get("power", 0)) if w != "" else 0.0


## 0.3.3: one bow shot at e (in range, line of sight checked by the caller).
## Uses one arrow; false = out of arrows (the attack stops).
func _shoot(e, t: int, world) -> bool:
	var arrow := ammo_arrow()
	if arrow == "":
		return false
	use_ammo(arrow)
	start_pose("shoot")
	if self is Player:
		Events.inventory_changed.emit()
	var w := weapon_id()
	var acc := 0.0
	if e is Actor:
		PkRules.on_pvp_swing(self, e, t)
		acc = PkRules.accuracy(PkRules.actor_stats(self), PkRules.actor_stats(e))
	else:
		acc = minf(0.95, Combat.actor_accuracy(skills.level("archery"), ranged_atk(), int(e.def.get("defence", 0)), Combat.armour_break(w)) * Prayer.mult(prayer, "acc"))
	var mh := Combat.actor_max_hit(skills.level("archery"), weapon_power(), ranged_str()) + Combat.arrow_power(arrow)
	var dmg := Combat.swing(acc, mh, rng)
	dmg = Combat.final_damage(Prayer.scale_damage(dmg, Prayer.mult(prayer, "dmg"), rng))   # 0.3.18 x0.5
	Events.projectile.emit(self, e, str(Combat.rcfg().get("projectile_sprite", "arrow")))
	Combat.award_hit_xp(skills, "ranged", dmg)
	if world != null and world.get("ground") != null and rng.randf() < float(Combat.rcfg().get("arrow_drop_chance", 0.5)):
		world.ground.add(e.tile, arrow, 1, t, -1, actor_id)
	e.take_hit(dmg, self, t)
	return true


## Style in use: the chosen one, else the weapon class default.
func current_style() -> String:
	return combat_style if combat_style != "" else Combat.default_style(weapon_id())


## Worn armour ids (for the full-set Defence XP bonus).
func armour_ids() -> Array:
	return []


func set_mult() -> float:
	return float(Combat.set_bonus(armour_ids())["mult"])


func in_combat(t: int) -> bool:
	return t - last_combat_tick < CombatRules.combat_ticks()


func attack(enemy) -> void:
	path.clear()
	action = {"kind": "fight", "enemy": enemy, "goal": Vector2i(999999, 999999)}
	set_status("Fighting: %s" % (enemy.display_name_level() if enemy.has_method("display_name_level") else CombatRules.label(enemy)))


# ------------------------------------------------------------- 0.3.1 PK --
func is_skulled(t: int) -> bool:
	return t < skull_until


func set_skull(until: int) -> void:
	skull_until = maxi(skull_until, until)
	queue_redraw()


## We killed another player / AI player (PK zone).
func on_pvp_kill(_victim, _t: int) -> void:
	action = {}
	path.clear()
	set_status("")


var last_armour_bonus := 0.0   # 0.3.18 tests / QA


## An enemy hit us (dmg 0 = a miss, still shown).
func take_hit(dmg: int, attacker, t: int) -> void:
	if dead:
		return
	hp -= dmg
	last_combat_tick = t
	if dmg > 0 and attacker is Player and not (self is Player):   # 0.3.13 sfx: AI players are humanoid
		Sfx.npc_hit(true)
	elif dmg == 0 and attacker != null and (attacker is Player or self is Player):   # 0.3.14 block/miss on the player or an AI player: armour clang
		Sfx.armour_clang()
	if attacker != null:
		last_attacker = attacker
		combat_foe = attacker
		var bonus := Combat.armour_hit_xp(armour_ids()) if self is Player and dmg > 0 else 0.0   # 0.3.18 armour XP bonus
		var dx := Combat.award_defence_xp(skills, dmg, set_mult(), rng, bonus)   # block or hit: small Defence XP
		if bonus > 0.0 and self is Player:
			last_armour_bonus = bonus
			Events.say("+%d Defence XP (armour +%s)" % [dx, str(snappedf(bonus, 0.01))])
	Events.hitsplat.emit(self, tile, dmg)
	queue_redraw()
	on_damaged(t)
	if hp <= 0:
		hp = 0
		die(t)
		if attacker is Actor and is_instance_valid(attacker):
			attacker.on_pvp_kill(self, t)
		last_attacker = null
		return
	if auto_retaliate and action.is_empty() and path.is_empty() and attacker != null:
		attack(attacker)


## Hook: single-way combat refused our attack (player: show the message).
func combat_blocked(_why: String) -> void:
	pass


## Hook: AI decides to eat / flee here.
func on_damaged(_t: int) -> void:
	pass


## Hook: Player respawns in town with a death pile; AIPlayer reports to its record.
func die(_t: int) -> void:
	hp = max_hp()


func on_kill(_enemy, _t: int) -> void:
	action = {}
	path.clear()
	set_status("")


## Eat the food in pack slot i. Returns HP healed (-1 = not food).
func eat_slot(i: int, t: int) -> int:
	var s = inventory.slots[i]
	if s == null:
		return -1
	var it := GameData.item(s["id"])
	var heals := int(it.get("heals", 0))
	if heals <= 0:
		return -1
	if int(s.get("qty", 1)) > 1:
		inventory.remove(s["id"], 1)
	else:
		inventory.remove_at(i)
	var before := hp
	hp = mini(max_hp(), hp + heals)
	next_attack = maxi(next_attack, t + Combat.EAT_DELAY)
	queue_redraw()
	return hp - before


func food_slot() -> int:
	for i in inventory.size():
		var s = inventory.slots[i]
		if s != null and int(GameData.item(s["id"]).get("heals", 0)) > 0:
			return i
	return -1


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _fight_tick(t: int, world) -> void:
	var e = action.get("enemy")
	if e == null or not is_instance_valid(e) or e.dead:
		action = {}
		path.clear()
		set_status("")
		return
	var why := CombatRules.can_attack(self, e, t)
	if why != "":
		action = {}
		path.clear()
		set_status("")
		combat_blocked(why)
		return
	var d := _cheb(e.tile, tile)
	var wpn := weapon_id()
	if Combat.is_ranged(wpn) and d >= 1 and d <= Combat.ranged_range() and Combat.line_of_sight(world, tile, e.tile):
		path.clear()     # archers stand and shoot
		if t >= next_attack:
			next_attack = t + Combat.weapon_ticks(wpn)
			last_combat_tick = t
			combat_foe = e
			if not _shoot(e, t, world):
				action = {}
				set_status("")
				combat_blocked("Out of arrows!")
		return
	if d == 1 and not Combat.is_ranged(wpn):
		path.clear()
		if t >= next_attack:
			var w := weapon_id()
			next_attack = t + Combat.weapon_ticks(w)
			last_combat_tick = t
			combat_foe = e
			start_pose("attack")
			var acc := 0.0
			if e is Actor:
				# 0.3.1 PvP (PK zones only): skull bookkeeping, then the PvP accuracy formula
				PkRules.on_pvp_swing(self, e, t)
				acc = PkRules.accuracy(PkRules.actor_stats(self), PkRules.actor_stats(e))
			else:
				acc = minf(0.95, Combat.actor_accuracy(skills.level("attack"), combat_atk(), int(e.def.get("defence", 0)), Combat.armour_break(w)) * Prayer.mult(prayer, "acc"))
			var dmg := Combat.swing(acc, Combat.actor_max_hit(skills.level("strength"), weapon_power(), combat_str()), rng)
			dmg = Combat.final_damage(Prayer.scale_damage(dmg, Prayer.mult(prayer, "dmg"), rng))   # 0.3.18 x0.5
			Combat.award_hit_xp(skills, current_style(), dmg)
			e.take_hit(dmg, self, t)
		return
	if d > 40:
		action = {}
		path.clear()
		set_status("")
		return
	if action.get("goal") != e.tile or path.is_empty():
		action["goal"] = e.tile
		set_path(world, Pathfinder.find_path(world, tile, Pathfinder.interaction_tiles(e.tile), e.tile, 800))
		if path.is_empty() and d != 0:
			action = {}
			set_status("")
			return
	if d == 0:
		var side: Vector2i = world.find_free_tile_near(tile + Vector2i(1, 0), 2)
		path = [side]
	_step_path(world, true)


# -------------------------------------------------------------------- tick --
func on_tick(t: int, world) -> void:
	prev_tile = tile
	last_steps = 0
	_tick_now = t
	if skull_until >= 0 and t == skull_until:
		queue_redraw()     # skull wears off
	if _vis_last == Vector2.INF:
		_vis_last = foot_px(tile)
	# Start this tick's trail where the sprite is actually drawn, not at the
	# logical end of the last step: the last frame of a tick is usually a
	# little short of it, and "finishing" that step on a reversal moved the
	# sprite 1 px the old way while already facing the new way (QA C1).
	if is_inside_tree() and position.distance_to(_vis_last) <= float(GameData.tile_size):
		_vis_pts = [position]
	else:
		_vis_pts = [_vis_last]
	_tick_body(t, world)
	if last_steps > 0:
		_last_move_t = t
	elif (_vis_pts.back() as Vector2) != foot_px(tile):
		_vis_pts.append(foot_px(tile))      # stopped off the line's tile centre: settle onto it
	_vis_last = _vis_pts.back()
	_update_facing()


## THE one place facing is decided: the x of this tick's movement, at once;
## vertical keeps; standing in a fight faces the target.
func _update_facing() -> void:
	if dead:
		return
	if last_steps > 0:
		facing.observe((_vis_pts.back() as Vector2).x - (_vis_pts[0] as Vector2).x, 0, (_vis_pts.back() as Vector2).y - (_vis_pts[0] as Vector2).y)
		return
	if action.get("kind", "") == "fight":
		var e = action.get("enemy")
		if e != null and is_instance_valid(e) and not e.dead:
			facing.observe(e.tile.x - tile.x, 0, e.tile.y - tile.y)


func foot_px(p: Vector2i) -> Vector2:
	var tp := float(GameData.tile_size)
	return Vector2((p.x + 0.5) * tp, (p.y + 1) * tp)


## Target of the current fight, else the end of the path, else null.
func _intent_tile():
	if action.get("kind", "") == "fight":
		var e = action.get("enemy")
		if e != null and is_instance_valid(e) and not e.dead:
			return e.tile
		return null
	if not path.is_empty():
		return path.back()
	return null


func _tick_body(t: int, world) -> void:
	if dead:
		return
	Prayer.tick(prayer, skills.level("prayer"))
	if hp < max_hp() and not in_combat(t) and t % Combat.REGEN_TICKS == 0:
		hp += 1
		queue_redraw()
	if action.get("kind", "") == "fight":
		_fight_tick(t, world)
		return
	if not path.is_empty():
		_step_path(world)
		return
	if not action.is_empty() and not (action.get("kind", "") in ["pickup", "loot", "visit", "leave"]):
		Interactions.perform(self, world, t)


## Walk along the path: 1 tile per tick, + sprint_steps() extra (player
## sprint). chase = fight pursuit (a blocked step is skipped, not fatal).
func _step_path(world, chase: bool = false) -> void:
	for i in 1 + sprint_steps():
		if path.is_empty():
			return
		var nxt: Vector2i = path[0]
		if world.is_blocked(nxt):
			if chase:
				path.pop_front()
			else:
				path.clear()   # something appeared in the way; give up this leg
			return
		var line = path_line.pop_front() if not path_line.is_empty() else null
		if line != null and line[4] != nxt:
			path_line.clear()
			line = null
		tile = nxt
		path.pop_front()
		last_steps += 1
		if line != null:
			# the exact point on the straight line: a diagonal run is a straight, steady glide
			_vis_pts.append(foot_px(line[0]).lerp(foot_px(line[1]), float(line[2]) / float(line[3])))
		else:
			_vis_pts.append(foot_px(tile))


## Extra tiles per tick (Player: sprint). AI players never sprint.
func sprint_steps() -> int:
	return 0


# ---------------------------------------------------------------- visuals --
func _process(delta: float) -> void:
	_update_visual_position()
	if _sprite:
		_anim_t += delta   # continuous clock: the cycle never restarts per tick
		var kneel := bool(action.get("kneel", false)) and path.is_empty()
		if _pose != "":
			_pose_t += delta
			var pd := pose_def(sprite_id, _pose)
			var nf := maxi(1, int(pd.get("frames", 4)))
			if _pose_t * float(pd.get("fps", 8)) >= float(nf):
				_pose = ""
		if _pose != _pose_shown:
			_pose_shown = _pose
			_apply_pose_look(_sprite, sprite_id)
			_shown_dir = facing.dir
			_layer_key = ""
		if _pose != "":
			var pd2 := pose_def(sprite_id, _pose)
			_sprite.frame = mini(_sprite.hframes - 1, int(_pose_t * float(pd2.get("fps", 8))))
		elif _sprite.hframes > 1:
			_sprite.frame = 0 if kneel else (Facing.anim_frame(_anim_t, anim_fps(), _sprite.hframes) if is_animating() else 0)
		_sprite.scale.y = 0.8 if kneel else 1.0   # 0.3.1 kneeling at an altar (scales toward the feet)
		if facing.dir != _shown_dir:
			_shown_dir = facing.dir
			_apply_pose_look(_sprite, sprite_id)
			_layer_key = ""   # gear layers follow the facing too
		var fl: bool = facing.left and can_flip() and facing.dir == "side"
		if fl != _sprite.flip_h:
			_layer_key = ""   # 0.3.9.4 left/right swap which hand is near: re-order the gear layers
		_sprite.flip_h = fl
		_refresh_gear_visual()
		_sync_gear_layers()


## restyle: how much lower (px) the overhead UI sits than on the old 16x24 body.
func body_height_delta() -> int:
	return maxi(0, 24 - GameData.frame_size("actors", sprite_id).y)


## restyle (batch 01): one-shot attack / shoot poses (32x32 frames, offset -8,-8
## from the 16x16 walk frame). "" when no pose plays now.
func start_pose(kind: String) -> void:
	var key := kind + "_paths"
	if not GameData.sprite_def("actors", sprite_id).has(key):
		return
	_pose = kind
	_pose_t = 0.0


func current_pose() -> String:
	return _pose


static func pose_def(sid: String, kind: String) -> Dictionary:
	if kind == "":
		return {}
	return GameData.sprite_def("actors", sid).get(kind + "_paths", {})


## Texture, hframes and offset for a sprite id in the current pose (or walk).
func _apply_pose_look(spr: Sprite2D, sid: String) -> void:
	var pd := pose_def(sid, _pose)
	if pd.is_empty():
		spr.texture = GameData.actor_texture(sid, facing.dir)
		var fs := GameData.frame_size("actors", sid)
		spr.hframes = maxi(1, GameData.frame_count("actors", sid))
		spr.offset = Vector2(-fs.x / 2.0, -fs.y)
		return
	var wf := GameData.frame_size("actors", sid)
	var pf: Array = pd.get("frame_size", [32, 32])
	var po: Array = pd.get("offset", [-8, -8])
	var tex: Texture2D = load(str(pd.get(facing.dir, pd.get("side", ""))))
	spr.texture = tex
	spr.hframes = maxi(1, int(pd.get("frames", 4)))
	spr.offset = Vector2(-wf.x / 2.0 + float(po[0]), -wf.y + float(po[1]))
	if tex == null or int(pf[0]) <= 0:
		_apply_pose_look_walk(spr, sid)


func _apply_pose_look_walk(spr: Sprite2D, sid: String) -> void:
	var fs := GameData.frame_size("actors", sid)
	spr.texture = GameData.actor_texture(sid, facing.dir)
	spr.hframes = maxi(1, GameData.frame_count("actors", sid))
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)


## Walk cycle speed from data/sprites.json "fps".
func anim_fps() -> float:
	return float(GameData.sprite_def("actors", sprite_id).get("fps", 4))


## Art may opt out of mirroring (sprites.json actor "flip": false).
func can_flip() -> bool:
	return bool(GameData.sprite_def("actors", sprite_id).get("flip", true))


## Moving (with a short grace so a 1-tick pause doesn't pop to frame 0) or busy.
func is_animating() -> bool:
	return _tick_now - _last_move_t <= int(Facing.cfg().get("anim_grace_ticks", 2)) or not action.is_empty()


func _draw() -> void:
	if dead:
		return
	if is_skulled(_tick_now if _tick_now > 0 else Tick.tick_count):
		var sk := GameData.texture("ui", "skull")
		if sk:
			draw_texture_rect(sk, Rect2(-4, -38 + body_height_delta(), 8, 8), false)
	if hp >= max_hp():
		return
	var top := -27.0 + float(body_height_delta())   # restyle: 8 px lower on 16x16 bodies
	draw_rect(Rect2(-6, top, 12, 2), Color("#a8281e"))
	draw_rect(Rect2(-6, top, 12.0 * clampf(float(hp) / max_hp(), 0.0, 1.0), 2), Color("#3ac83a"))


func _update_visual_position() -> void:
	position = trail_position(Tick.alpha())


## Sprite position: along this tick's waypoints (1 segment walking, 2 when
## sprinting), each on the straight line of the path, at a constant pace.
## Rounded to whole world pixels (pixel art; the camera rounds the same way).
func trail_position(alpha: float) -> Vector2:
	var pts: Array = _vis_pts if _vis_pts.size() >= 1 else [foot_px(tile)]
	if pts.size() == 1:
		return (pts[0] as Vector2).round()
	var segs := pts.size() - 1
	var f := clampf(alpha, 0.0, 1.0) * segs
	var i := mini(int(f), segs - 1)
	return (pts[i] as Vector2).lerp(pts[i + 1], f - i).round()


# -------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	return {
		"id": actor_id, "name": display_name,
		"tile": [tile.x, tile.y],
		"skills": skills.to_save(), "hp": hp, "prayer": prayer.duplicate(),
		"inventory": inventory.to_save(),
		"bank": bank.to_save(),
	}


func from_save(d: Dictionary) -> void:
	if d.has("name"):
		display_name = str(d["name"])
	var tl: Array = d.get("tile", [tile.x, tile.y])
	place_at(Vector2i(int(tl[0]), int(tl[1])))
	skills.from_save(d.get("skills", {}))
	hp = clampi(int(d.get("hp", max_hp())), 1, max_hp())
	prayer = d.get("prayer", {}).duplicate()
	inventory.from_save(d.get("inventory", []))
	bank.from_save(d.get("bank", []))


# ------------------------------------------------- 0.3.1 visible gear --
const GEAR_DRAW_ORDER := ["legs", "body", "head", "shield", "weapon"]


## slot -> item id of what this actor wears (Player: equipment; AIPlayer: its agent).
func gear_worn() -> Dictionary:
	return {}


## Sprite id drawn for a worn item (data/sprites.json "actors"), most specific first:
##   gear_item_<item id>               one item's own art (hand-drawn swaps)
##   gear_<slot>_<class>_<tier>        silhouette per weapon/shield type and tier
##   gear_<slot>_<tier>                generic per slot and tier
## "" = no art: nothing is drawn for that slot.
static func gear_sprite_for(item_id: String, slot: String) -> String:
	var own := "gear_item_" + item_id
	if not GameData.sprite_def("actors", own).is_empty():
		return own
	var gd: Dictionary = GameData.item(item_id).get("gear", {})
	var tier := int(gd.get("tier", 0))
	var cls := str(gd.get("class", ""))
	# the item's gear "class" (sword, bow...), else any word of its id that names a
	# silhouette (iron_kite_shield -> kite, alder_buckler -> buckler)
	var classes: Array = [cls] if cls != "" else Array(item_id.split("_"))
	for c in classes:
		var sid := "gear_%s_%s_%d" % [slot, c, tier]
		if not GameData.sprite_def("actors", sid).is_empty():
			return sid
	var gen := "gear_%s_%d" % [slot, tier]
	return gen if not GameData.sprite_def("actors", gen).is_empty() else ""


## Rebuild the overlay sprites when what is worn changed (cheap key check, run
## every frame, so an equip/unequip shows on the very next frame).
func _refresh_gear_visual() -> void:
	if _sprite == null:
		return
	var worn := gear_worn()
	var key := ""
	var want := {}
	for slot in GEAR_DRAW_ORDER:
		if not worn.has(slot):
			continue
		var sid := gear_sprite_for(str(worn[slot]), slot)
		if sid == "":
			continue
		want[slot] = sid
		key += sid + ";"
	key += _pose + facing.dir
	if key == _layer_key:
		return
	_layer_key = key
	for slot in _layers.keys():
		_layers[slot].visible = false
	for slot in GEAR_DRAW_ORDER:
		if not want.has(slot):
			continue
		var spr: Sprite2D = _layers.get(slot)
		if spr == null:
			spr = Sprite2D.new()
			spr.centered = false
			spr.name = "gear_" + slot
			add_child(spr)
			_layers[slot] = spr
		var sid: String = want[slot]
		_apply_pose_look(spr, sid)
		spr.set_meta("sprite_id", sid)
		spr.visible = true
	_order_gear_layers()
	_sync_gear_layers()


## 0.3.9.4 per-facing gear layer order. The shield is in the LEFT hand, the
## weapon in the RIGHT; the side sheets face right and are mirrored for left.
##   down: legs < body < head < shield < weapon, all over the body
##   up:   the shield under the body (held in front, hidden by the back)
##   side, facing right: the left hand is the far side -> shield under the body
##   side, facing left:  the shield is the near side -> drawn over everything;
##                       the weapon (right hand) is far -> under the body
static func gear_layer_plan(dir: String, left: bool) -> Dictionary:
	var under: Array = []
	if dir == "up" or (dir == "side" and not left):
		under = ["shield"]
	elif dir == "side" and left:
		under = ["weapon"]
	var over: Array = GEAR_DRAW_ORDER.filter(func(s): return not s in under)
	if dir == "side" and left:
		over = ["legs", "body", "head", "shield"]
	return {"under": under, "over": over}


## 0.3.9.5 facing right the side shield is behind the body (far hand): nudge it
## 1 px forward (+x, the facing direction) so more of it peeks out in front of
## the chest. Facing left (shield over the body), front and back: no offset.
static func gear_layer_offset(slot: String, dir: String, left: bool) -> Vector2:
	if slot == "shield" and dir == "side" and not left:
		return Vector2(1, 0)
	return Vector2.ZERO


func _order_gear_layers() -> void:
	var plan := gear_layer_plan(facing.dir, _sprite.flip_h)
	var seq: Array = []
	for slot in plan["under"]:
		if _layers.has(slot):
			seq.append(_layers[slot])
	seq.append(_sprite)
	for slot in plan["over"]:
		if _layers.has(slot):
			seq.append(_layers[slot])
	var base := _sprite.get_index()
	for n in seq:
		base = mini(base, n.get_index())
	for i in seq.size():   # under... < body < over..., contiguous from the lowest slot
		move_child(seq[i], base + i)


## Same frame and mirroring as the body, set in the same _process as the body
## frame, so layers never lag a frame behind (no ghosting / flicker).
func _sync_gear_layers() -> void:
	for slot in _layers.keys():
		var spr: Sprite2D = _layers[slot]
		if spr.visible:
			spr.frame = mini(_sprite.frame, spr.hframes - 1)
			spr.flip_h = _sprite.flip_h
			spr.position = _sprite.position + gear_layer_offset(str(slot), facing.dir, _sprite.flip_h)


## Sprite ids of the gear layers showing now, draw order (tests / QA).
func gear_layer_ids() -> Array:
	var ids := []
	for slot in GEAR_DRAW_ORDER:
		if _layers.has(slot) and _layers[slot].visible:
			ids.append(str(_layers[slot].get_meta("sprite_id", "")))
	return ids
