class_name Enemy
extends Node2D
## A creature (data/enemies.json). Lives at a home spot inside its camp,
## wanders a little, aggroes on actors (player or AI) that come within its
## aggro radius, chases while it stays inside its leash radius, then walks
## home and heals. Dies -> drops (data/drops.json) -> respawns after a delay.

var kind := ""
var def: Dictionary = {}
var home := Vector2i.ZERO
var tile := Vector2i.ZERO
var prev_tile := Vector2i.ZERO
var hp := 1
var max_hp := 1
var target: Actor = null
var returning := false
var dead := false
var respawn_at := 0
var next_attack := 0
var last_combat_tick := -1000     # single-way combat (CombatRules)
var next_wander := 0
var wander_goal := Vector2i.ZERO
var rng := RandomNumberGenerator.new()
var manager = null                  # EnemyManager
var town := ""                      # 0.3.1 town guards / citizens: their town id
var patrol: Array = []              # 0.3.1 guards: world-tile waypoints walked in a loop
var patrol_i := 0
var _patrol_path: Array = []         # cached A* leg toward the current waypoint
var _patrol_wait := 0
var tint := Color.WHITE             # 0.3.1 colour variant (enemies.json "tints")

var _sprite: Sprite2D
var _anim_t := 0.0
var _bite_t := -1.0          # 0.3.17 seconds into a bite animation (-1 = none)
var _bite_dir := ""
var _shown_dir := "side"
var facing := Facing.new()            # 0.2.5: hysteresis facing (see src/actors/facing.gd)
var _tick_now := 0
var _last_move_t := -100000

var _lvl_label: Label = null    # 0.3.3 overhead "Name (lvl)"
var _lvl_t := 0.0
var _gossip: Label = null            # 0.3.20 lore lines when the player stands close
var _gossip_until := -1


func setup(k: String, at: Vector2i, seed_v: int) -> void:
	kind = k
	def = GameData.enemies.get(k, {})
	home = at
	tile = at
	prev_tile = at
	wander_goal = at
	rng.seed = seed_v
	max_hp = int(def.get("hp", 5))
	var hr: Array = def.get("hp_range", [])
	if hr.size() == 2:
		max_hp = rng.randi_range(int(hr[0]), int(hr[1]))
	hp = max_hp
	var tints: Array = def.get("tints", [])
	if not tints.is_empty():
		tint = Color(str(tints[rng.randi() % tints.size()]))


## 0.3.1 data flags (data/enemies.json): passive creatures never swing back;
## town folk may stand and fight inside towns; quick ones chase 2 tiles/tick.
func retaliates() -> bool:
	return bool(def.get("retaliate", true))


func town_ok() -> bool:
	return bool(def.get("town_ok", false))


func aggressive() -> bool:
	return int(def.get("aggro", 0)) > 0


func display_name() -> String:
	return str(def.get("name", kind))


func level() -> int:
	return int(def.get("level", 1))


## "Giant rat (level 1)": what you see when you tap / examine an enemy.
func display_name_level() -> String:
	return "%s (level %d)" % [display_name(), level()]


func _ready() -> void:
	var sid: String = def.get("sprite", kind)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = GameData.texture("actors", sid)
	var fs := GameData.frame_size("actors", sid)
	_sprite.hframes = maxi(1, GameData.frame_count("actors", sid))
	_sprite.offset = Vector2(-fs.x / 2.0, -fs.y)
	_sprite.modulate = tint
	var sc := float(def.get("scale", 1.0))     # 0.3.16 bosses drawn bigger (Rat Mother)
	_sprite.scale = Vector2(sc, sc)
	add_child(_sprite)
	if Overhead.enemy_shows(def):
		_lvl_label = Overhead.make(Overhead.level_color(level()))
		_lvl_label.text = "%s (%d)" % [display_name(), level()] if not def.has("follow_quest") else display_name()
		Overhead.place(_lvl_label, (fs.y - Actor.head_drop(sid)) * sc)
		Overhead.attach(_lvl_label, self)
	_update_pos()


func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func is_engaged() -> bool:
	return target != null and is_instance_valid(target)


# ------------------------------------------------------------------- tick --
func tick(t: int, world, actors: Array) -> void:
	_tick_now = t
	_tick_body(t, world, actors)
	if tile != prev_tile:
		_last_move_t = t
	if dead:
		return
	# 0.3.0 immediate: this tick's step direction; standing in a fight: the target
	if tile != prev_tile:
		facing.observe(tile.x - prev_tile.x, t, tile.y - prev_tile.y)
	elif is_engaged():
		facing.observe(target.tile.x - tile.x, t, target.tile.y - tile.y)


func _tick_body(t: int, world, actors: Array) -> void:
	prev_tile = tile
	if dead:
		if t >= respawn_at:
			_respawn()
		return
	_lore_gossip(t, actors)
	if def.has("follow_quest") and _follow_tick(t, world, actors):
		return
	var leash := int(def.get("leash", 7))
	var aggro := int(def.get("aggro", 3))
	if is_engaged() and (target.dead or cheb(target.tile, tile) > aggro + 8 or (world.gen.safe_at(target.tile) and not town_ok())):
		_give_up()
	if cheb(tile, home) > leash:
		_give_up()
	if is_engaged() and not CombatRules.can_aggro(self, target, t):
		_give_up()   # single-way: our target is busy with another enemy
	if is_engaged():
		if cheb(target.tile, tile) <= 1 and target.tile != tile:
			if t >= next_attack:
				_attack(t)
		else:
			for i in maxi(1, int(def.get("chase_steps", 1))):
				if cheb(target.tile, tile) <= 1:
					break
				var nxt := _step_toward(world, target.tile)
				if cheb(nxt, home) > leash:
					_give_up()
					break
				tile = nxt
		return
	if returning:
		tile = _step_toward(world, home)
		if cheb(tile, home) <= 1:
			returning = false
			hp = max_hp
		return
	if hp < max_hp and t % Combat.REGEN_TICKS == 0:
		hp += 1
		queue_redraw()
	# 0.3.1 guards walk their patrol loop (home follows, so the leash moves with them)
	if not patrol.is_empty():
		if t % 2 == 0:
			var wp: Vector2i = patrol[patrol_i % patrol.size()]
			if tile == wp or (manager and manager.occupied(wp, self) and cheb(tile, wp) <= 1):
				patrol_i = (patrol_i + 1) % patrol.size()
				wp = patrol[patrol_i]
			tile = _patrol_step(world, wp)
			home = tile
		return
	# idle: look for someone to bite
	if not aggressive():
		_idle_wander(t, world)
		return
	var best: Actor = null
	var bd := aggro + 1
	for a in actors:
		if a == null or not is_instance_valid(a) or a.dead:
			continue
		var d := cheb(a.tile, tile)
		if d < bd and cheb(a.tile, home) <= leash and not world.gen.safe_at(a.tile) and CombatRules.can_aggro(self, a, t) \
				and not ("skills" in a and Combat.too_strong_for_aggro(level(), a.skills)):
			bd = d
			best = a
	if best:
		target = best
		next_attack = maxi(next_attack, t + 1)
		last_combat_tick = t
		best.combat_foe = self      # aggro engages: no other enemy may pile on
		best.last_combat_tick = t
		return
	_idle_wander(t, world)


## 0.3.16 quest followers (Clip Clop): during the quest's "follow_stage" walk
## behind the quest holder (catching up if left far behind); once the quest
## is done, live at the home giver's site paddock. true = this tick handled.
func _follow_tick(t: int, world, actors: Array) -> bool:
	var qid := str(def["follow_quest"])
	var holder = null
	for a in actors:
		if a != null and is_instance_valid(a) and a is Player:
			holder = a
	if QuestSystem.done_ids.has(qid) or (holder != null and QuestSystem.state(holder, qid) == QuestSystem.COMPLETED):
		var pad := _home_paddock(world)
		if pad.x > -99999 and cheb(home, pad) > 3:
			home = pad
			tile = world.find_free_tile_near(pad, 3)
			prev_tile = tile
		return false
	if holder == null or not holder.quests.has(qid) or int(holder.quests[qid].get("stage", 0)) < int(def.get("follow_stage", 1)):
		return false
	var d := cheb(tile, holder.tile)
	if d > 16:      # left behind (travel, teleport, a reload): catch up
		tile = world.find_free_tile_near(holder.tile + Vector2i(-1, 1), 3)
		prev_tile = tile
	elif d > 1:
		for i in 2:
			if cheb(tile, holder.tile) <= 1:
				break
			var nx := _step_toward(world, holder.tile)
			if nx == tile or cheb(nx, holder.tile) >= cheb(tile, holder.tile):
				var path: Array = Pathfinder.find_path(world, tile, [holder.tile], holder.tile, 800)
				if path.size() > 1:
					nx = path[0]
			if nx == holder.tile:
				break
			tile = nx
	home = tile
	return true


func _home_paddock(world) -> Vector2i:
	var g: Dictionary = QuestSystem.cfg().get("givers", {}).get(str(def.get("home_giver", "")), {})
	if world == null or world.get("gen") == null or not g.has("site"):
		return Vector2i(-99999, -99999)
	return world.gen.site_point(str(g["site"]), "paddock")


## 0.3.20 Highfen townsfolk and Saltmere guards. The internal adventurer id
## "hero" is never spoken. Lines live in data/town_npcs.json "lore_talk".
func _lore_gossip(t: int, actors: Array) -> void:
	if _gossip != null and t >= _gossip_until:
		_gossip.visible = false
	if kind != "citizen" and kind != "town_guard":
		return
	if (t + absi(home.x * 3 + home.y)) % 48 != 0:
		return
	var pack: Dictionary = GameData.town_npcs.get("lore_talk", {}).get(town, {})
	var lines: Array = pack.get(kind, [])
	if lines.is_empty():
		return
	var near := false
	for a in actors:
		if a is Player and cheb((a as Player).tile, tile) <= 3:
			near = true
			break
	if not near:
		return
	var line: String = str(lines[absi(hash(str(t / 48) + town + kind)) % lines.size()])
	if _gossip == null:
		_gossip = Label.new()
		_gossip.add_theme_font_size_override("font_size", 8)
		_gossip.position = Vector2(-46, -28)
		add_child(_gossip)
	_gossip.text = line
	_gossip.visible = true
	_gossip_until = t + 10


func _idle_wander(t: int, world) -> void:
	# wander a little around home
	if t >= next_wander:
		var w := int(def.get("wander", 3))
		wander_goal = home + Vector2i(rng.randi_range(-w, w), rng.randi_range(-w, w))
		next_wander = t + rng.randi_range(6, 18)
	if tile != wander_goal and t % 2 == 0:
		tile = _step_toward(world, wander_goal)


func _give_up() -> void:
	target = null
	returning = true


## One patrol step along a cached A* path (greedy steps snag on stalls and
## houses). Waits briefly if someone stands in the way, then re-plans/skips.
func _patrol_step(world, wp: Vector2i) -> Vector2i:
	if tile == wp:
		return tile
	if _patrol_path.is_empty() or _patrol_path[-1] != wp or cheb(_patrol_path[0], tile) != 1:
		_patrol_path = Pathfinder.find_path(world, tile, [wp], wp, 2500)
		if _patrol_path.is_empty():
			patrol_i = (patrol_i + 1) % patrol.size()   # unreachable: next waypoint
			return _step_toward(world, wp)
	var nx: Vector2i = _patrol_path[0]
	if world.is_blocked(nx) or (manager and manager.occupied(nx, self)):
		_patrol_wait += 1
		if _patrol_wait <= 2:
			return tile   # give them a moment to move on
		# step around whoever stands there: any free neighbour that still
		# touches the following path tile
		var after: Vector2i = _patrol_path[1] if _patrol_path.size() > 1 else wp
		for d in Pathfinder.DIRS:
			var q: Vector2i = tile + d
			if q == nx or cheb(q, after) > 1 or world.is_blocked(q) or (manager and manager.occupied(q, self)):
				continue
			_patrol_wait = 0
			_patrol_path.pop_front()
			if _patrol_path.size() > 0 and _patrol_path[0] == q:
				_patrol_path.pop_front()
			return q
		if _patrol_wait > 8:
			_patrol_wait = 0
			_patrol_path = []
			patrol_i = (patrol_i + 1) % patrol.size()   # walled in: next waypoint
		return tile
	_patrol_wait = 0
	_patrol_path.pop_front()
	return nx


func _step_toward(world, goal: Vector2i) -> Vector2i:
	var best := tile
	var bd := cheb(tile, goal) * 10 + Vector2(tile - goal).length()
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var q := tile + Vector2i(dx, dy)
			if q == goal and target != null and q == target.tile:
				continue
			if world.is_blocked(q) or (manager and manager.occupied(q, self)):
				continue
			var d := cheb(q, goal) * 10 + Vector2(q - goal).length()
			if d < bd:
				bd = d
				best = q
	return best


func is_biting() -> bool:
	return _bite_t >= 0.0


func _attack(t: int) -> void:
	next_attack = t + int(def.get("attack_ticks", Combat.ATTACK_TICKS))
	last_combat_tick = t
	if _sprite and GameData.sprite_def("actors", def.get("sprite", kind)).has("bite_paths"):
		_bite_t = 0.0   # 0.3.17 play the wind-up + lunge bite strip
	var acc := Combat.enemy_accuracy(def, target.combat_def(), target.skills.level("defence")) * Prayer.mult(target.prayer, "def")
	var dmg := Combat.final_damage(Combat.swing(acc, int(def.get("max_hit", 1)), rng))   # 0.3.18 x0.5
	target.take_hit(dmg, self, t)


## Hit by an actor: retaliate, maybe die.
func take_hit(dmg: int, attacker: Actor, t: int) -> void:
	if dead:
		return
	hp -= dmg
	last_combat_tick = t
	Events.hitsplat.emit(self, tile, dmg)
	if dmg > 0 and attacker is Player:   # 0.3.13 sfx: humanoid (goblins, guards, citizens...) vs creature
		Sfx.npc_hit(bool(def.get("humanoid", false)))
	elif dmg == 0 and attacker is Player:   # 0.3.14 block/miss on an NPC: armour clang
		Sfx.armour_clang()
	queue_redraw()
	if attacker and not attacker.dead and retaliates() and (target == null or not is_instance_valid(target)):
		target = attacker
		returning = false
		next_attack = maxi(next_attack, t + 2)
	if hp <= 0:
		_die(attacker, t)


func _die(killer: Actor, t: int) -> void:
	dead = true
	target = null
	returning = false
	_play_death()
	visible = false
	respawn_at = t + int(def.get("respawn_ticks", 60))
	if manager:
		manager.on_killed(self, killer, t)


## 0.4.0 one-shot death strip (sprite "death_paths") left where it fell.
func _play_death() -> void:
	var sd := GameData.sprite_def("actors", def.get("sprite", kind))
	var dp: String = str(sd.get("death_paths", {}).get(facing.dir, ""))
	if dp == "" or _sprite == null or get_parent() == null:
		return
	var n := int(sd.get("death_frames", 4))
	var spr := Sprite2D.new()
	spr.texture = GameData._tex(dp)
	spr.hframes = maxi(1, n)
	spr.centered = false
	spr.offset = _sprite.offset
	spr.scale = scale
	spr.flip_h = _sprite.flip_h
	spr.position = position
	spr.z_index = z_index
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_parent().add_child(spr)
	var tw := spr.create_tween()
	var step := 1.0 / maxf(1.0, float(sd.get("death_fps", 6)))
	for i in n:
		tw.tween_callback(func(): spr.frame = i)
		tw.tween_interval(step)
	tw.tween_interval(0.6)
	tw.tween_property(spr, "modulate:a", 0.0, 0.5)
	tw.tween_callback(spr.queue_free)


func _respawn() -> void:
	dead = false
	hp = max_hp
	if not patrol.is_empty():
		home = patrol[0]
		patrol_i = 0
		_patrol_path = []
	tile = home
	prev_tile = home
	visible = true
	queue_redraw()


## Reset when the player is far away (no one is watching).
func reset_far() -> void:
	if dead:
		return
	target = null
	returning = false
	if not patrol.is_empty():
		home = patrol[0]
		patrol_i = 0
		_patrol_path = []
	tile = home
	prev_tile = home
	hp = max_hp


# ---------------------------------------------------------------- visuals --
func _process(delta: float) -> void:
	_update_pos()
	if _lvl_label:
		Overhead.clamp_on_screen(_lvl_label, self)
		_lvl_t -= delta
		if _lvl_t <= 0.0:
			_lvl_t = 1.0
			_lvl_label.add_theme_color_override("font_color", Overhead.level_color(level()))
	if _sprite:
		_anim_t += delta
		var sd := GameData.sprite_def("actors", def.get("sprite", kind))
		if _bite_t >= 0.0:
			_bite_t += delta
			var bn := int(sd.get("bite_frames", 2))
			var bf := int(_bite_t * float(sd.get("bite_fps", 6)))
			var bp: String = str(sd.get("bite_paths", {}).get(facing.dir, ""))
			if bf >= bn or bp == "":
				_bite_t = -1.0
				_shown_dir = ""   # restore the walk sheet below
				_sprite.hframes = maxi(1, GameData.frame_count("actors", def.get("sprite", kind)))
			else:
				if _bite_dir != facing.dir:
					_bite_dir = facing.dir
					_sprite.texture = GameData._tex(bp)
					_sprite.hframes = bn
				_shown_dir = "bite"
				_sprite.frame = clampi(bf, 0, bn - 1)
		if _bite_t < 0.0:
			_bite_dir = ""
			var moving := _tick_now - _last_move_t <= int(Facing.cfg().get("anim_grace_ticks", 2))
			# 0.4.0 optional idle strip (Greymaw, dire wolves) while standing still
			var ip: String = str(sd.get("idle_paths", {}).get(facing.dir, ""))
			var want := (facing.dir + "_idle") if (ip != "" and not moving and not is_engaged()) else facing.dir
			if want != _shown_dir:   # 0.3.9 front / back / side sheets
				_shown_dir = want
				if want.ends_with("_idle"):
					_sprite.texture = GameData._tex(ip)
					_sprite.hframes = maxi(1, int(sd.get("idle_frames", 2)))
				else:
					_sprite.texture = GameData.actor_texture(def.get("sprite", kind), facing.dir)
					_sprite.hframes = maxi(1, GameData.frame_count("actors", def.get("sprite", kind)))
			if _sprite.hframes > 1:
				if want.ends_with("_idle"):
					_sprite.frame = int(_anim_t * float(sd.get("idle_fps", 2))) % _sprite.hframes
				else:
					_sprite.frame = Facing.anim_frame(_anim_t, float(sd.get("fps", 4)), _sprite.hframes) if (moving or is_engaged()) else 0
		_sprite.flip_h = facing.left and bool(sd.get("flip", true)) and facing.dir == "side"


func _update_pos() -> void:
	var tp := float(GameData.tile_size)
	var a := Vector2((prev_tile.x + 0.5) * tp, (prev_tile.y + 1) * tp)
	var b := Vector2((tile.x + 0.5) * tp, (tile.y + 1) * tp)
	position = a.lerp(b, Tick.alpha()).round()


func _draw() -> void:
	if dead or hp >= max_hp:
		return
	var _hs: String = str(def.get("sprite", kind))
	var h := float(GameData.frame_size("actors", _hs).y - Actor.head_drop(_hs)) * float(def.get("scale", 1.0))
	var w := 12.0
	var top := -h - 3.0
	draw_rect(Rect2(-w / 2.0, top, w, 2), Color("#a8281e"))
	draw_rect(Rect2(-w / 2.0, top, w * clampf(float(hp) / max_hp, 0.0, 1.0), 2), Color("#3ac83a"))
