class_name EnemyManager
extends Node
## Spawns the enemy camps from data/enemies.json, ticks the ones near the
## player (others are reset at home: nobody is watching), and resolves kills:
## drops from data/drops.json land on the ground for the player, or straight
## into the AI killer's stash (the AI loots at once; it stands next to it).
## Coin drops are paid from the Guild's daily purse (Market.pay_bounty).

const ACTIVE_RADIUS := 64

var world = null
var enemies: Array = []           # Array[Enemy]
var kills: Dictionary = {}        # kind -> count (stats / soak)
var _occ: Dictionary = {}         # Vector2i -> Enemy (rebuilt each tick)


func spawn_all(parent: Node2D, w) -> void:
	world = w
	for e in enemies:
		e.queue_free()
	enemies.clear()
	var ci := 0
	for camp in GameData.camps:
		var at := Vector2i(int(camp["at"][0]), int(camp["at"][1]))
		at = world.find_free_tile_near(at, 10)
		var spread := int(camp.get("spread", 3))
		for i in int(camp.get("count", 3)):
			var p: Vector2i = world.find_free_tile_near(at + Vector2i((i % 3 - 1) * spread, (i / 3 - 1 + (i % 2)) * spread), 4)
			var e := Enemy.new()
			e.setup(str(camp["enemy"]), p, hash([ci, i, world.gen.world_seed]))
			e.manager = self
			e.name = "%s_%d_%d" % [camp["enemy"], ci, i]
			parent.add_child(e)
			enemies.append(e)
		ci += 1
	_spawn_greymaw(parent)
	_spawn_town_folk(parent)
	_spawn_pastures(parent)


## 0.4.0 Greymaw: one dormant enemy; DireWolf.manage wakes and rotates her.
func _spawn_greymaw(parent: Node2D) -> void:
	if not GameData.enemies.has("greymaw"):
		return
	var farms: Array = DireWolf.farm_tiles(world)
	var e := Enemy.new()
	e.setup("greymaw", farms[0] if not farms.is_empty() else Vector2i.ZERO, hash(["greymaw", world.gen.world_seed]))
	e.manager = self
	e.name = "greymaw"
	parent.add_child(e)
	e.dead = true
	e.visible = false
	e.respawn_at = 1 << 40
	enemies.append(e)


## 0.3.1 village pastures: cows (or whatever "enemy") inside the fence.
func _spawn_pastures(parent: Node2D) -> void:
	for pz in world.gen.pastures:
		var r: Rect2i = pz["rect"]
		for i in int(pz["count"]):
			var at := r.position + Vector2i(2 + (i * 3) % maxi(1, r.size.x - 4), 2 + (i / 2) * 2 % maxi(1, r.size.y - 4))
			at = world.find_free_tile_near(at, 2, true)
			var e := Enemy.new()
			e.setup(str(pz["enemy"]), at, hash([pz["id"], i, world.gen.world_seed]))
			e.manager = self
			e.name = "%s_%d" % [pz["id"], i]
			parent.add_child(e)
			enemies.append(e)


## 0.3.1 town guards (patrol loops) and citizens (wander) from data/town_npcs.json.
func _spawn_town_folk(parent: Node2D) -> void:
	var cfg: Dictionary = GameData.town_npcs.get("towns", {}).duplicate()
	for vid in world.gen.village_order:   # 0.3.1 village folk live in the village file
		if world.gen.villages[vid].has("citizens"):
			cfg[vid] = {"citizens": world.gen.villages[vid]["citizens"]}
	for tid in cfg.keys():
		var tdef: Dictionary = world.gen.towns.get(tid, world.gen.villages.get(tid, {}))
		if tdef.is_empty():
			continue
		var org: Array = tdef["origin"]
		var o := Vector2i(int(org[0]), int(org[1]))
		var td: Dictionary = cfg[tid]
		var gi := 0
		for gd in td.get("guards", []):
			var pts: Array = []
			for q in gd.get("patrol", []):
				pts.append(world.find_free_tile_near(o + Vector2i(int(q[0]), int(q[1])), 3, true))
			if pts.is_empty():
				continue
			var e := Enemy.new()
			e.setup(str(gd.get("enemy", "town_guard")), pts[0], hash([tid, "guard", gi, world.gen.world_seed]))
			e.patrol = pts
			e.town = tid
			e.manager = self
			e.name = "%s_guard_%d" % [tid, gi]
			parent.add_child(e)
			enemies.append(e)
			gi += 1
		var cz: Dictionary = td.get("citizens", {})
		if cz.is_empty():
			continue
		var a: Array = cz["area"]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([tid, "citizens", world.gen.world_seed])
		for i in int(cz.get("count", 4)):
			var at := o + Vector2i(int(a[0]) + rng.randi_range(0, int(a[2]) - 1), int(a[1]) + rng.randi_range(0, int(a[3]) - 1))
			at = world.find_free_tile_near(at, 4, true)
			var e2 := Enemy.new()
			e2.setup(str(cz.get("enemy", "citizen")), at, hash([tid, "citizen", i, world.gen.world_seed]))
			e2.town = tid
			e2.manager = self
			e2.name = "%s_citizen_%d" % [tid, i]
			parent.add_child(e2)
			enemies.append(e2)


func occupied(p: Vector2i, me: Enemy) -> bool:
	var o = _occ.get(p)
	return o != null and o != me


func on_tick(t: int, actors: Array, focus: Vector2i) -> void:
	_occ.clear()
	for e in enemies:
		if not e.dead:
			_occ[e.tile] = e
	for e in enemies:
		if e.def.get("rotates", false) and not DireWolf.manage(e, t, world, actors):
			continue
		if e.cheb(e.home, focus) > ACTIVE_RADIUS:
			if e.tile != e.home or e.hp < e.max_hp:
				e.reset_far()
			continue
		var before: Vector2i = e.tile
		e.tick(t, world, actors)
		if e.tile != before:
			_occ.erase(before)
			_occ[e.tile] = e


func enemy_at(p: Vector2i) -> Enemy:
	for e in enemies:
		if not e.dead and e.tile == p:
			return e
	return null


## Tap helper: enemy on the tile or drawn over it (tall sprites).
func enemy_near_tap(p: Vector2i) -> Enemy:
	var e := enemy_at(p)
	if e == null:
		e = enemy_at(p + Vector2i(0, 1))
	return e


func nearest(from: Vector2i, kinds: Array, radius: int, ok: Callable = Callable()) -> Enemy:
	var best: Enemy = null
	var bd := radius + 1
	for e in enemies:
		if e.dead or (not kinds.is_empty() and not (e.kind in kinds)):
			continue
		if ok.is_valid() and not bool(ok.call(e)):
			continue
		var d: int = e.cheb(e.tile, from)
		if d < bd:
			bd = d
			best = e
	return best


func on_killed(e: Enemy, killer: Actor, t: int) -> void:
	kills[e.kind] = int(kills.get(e.kind, 0)) + 1
	var extra: Array = []
	if e.kind == "greymaw":
		var ph: String = DireWolf.phase(killer) if killer is Player else "off"
		extra = DireWolf.extra_drops(ph == "hunt", ph == "free", e.rng)
	if killer is Player:    # 0.3.7 only the quest holder's own kills count
		QuestSystem.on_kill(killer, e.kind, e.tile)
	var drops := DropTable.roll(str(e.def.get("drops", e.kind)), e.rng) + extra
	for d in drops:
		var id: String = d[0]
		var q: int = d[1]
		if id == GameData.currency:
			q = Market.pay_bounty(q)
		if q <= 0:
			continue
		if killer is AIPlayer and (killer as AIPlayer).agent:
			var ag: AIAgent = (killer as AIPlayer).agent
			if id == GameData.currency:
				ag.coins += q
			else:
				ag.stash_add(id, q)
		elif world and world.ground:
			# private to the killer for a while, then anyone's (AI loot leftovers)
			world.ground.add(e.tile, id, q, t, -1, killer.actor_id if killer else "")
	if killer:
		killer.on_kill(e, t)
