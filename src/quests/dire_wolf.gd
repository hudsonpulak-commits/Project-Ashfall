class_name DireWolf
extends RefCounted
## 0.4.0 Night of 1000 Howls part 2 (quest id dire_wolf, giver Warden Pye).
## Greymaw is one named enemy that rotates between the three village farms.
## She does not exist (hidden, no ticks) until step 5 (stage index 9) is active;
## then she waits at the farm picked when that step started. After the turn-in
## she respawns every respawn_ticks (10 min) at a random one of the three farms.

const QUEST := "dire_wolf"
const HUNT_STAGE := 9
const FARMS := ["millbrook_wheat", "barrowby_pasture", "oxley_pasture"]


## "off" (not yet), "hunt" (step 5 active), "free" (line finished: timer spawns).
static func phase(p) -> String:
	if p == null:
		return "off"
	var s: Dictionary = p.quests.get(QUEST, {})
	if s.is_empty():
		return "off"
	if bool(s.get("done", false)):
		return "free"
	return "hunt" if int(s.get("stage", 0)) == HUNT_STAGE else "off"


## World tiles where she stands: just outside each farm's fence.
static func farm_tiles(world) -> Array:
	var out: Array = []
	for fid in FARMS:
		var r := Rect2i()
		for f in world.gen.farms + world.gen.pastures:
			if str(f["id"]) == fid:
				r = f["rect"]
		if r.size == Vector2i.ZERO:
			continue
		var t := Vector2i(r.position.x + r.size.x / 2, r.end.y + 2)
		out.append(world.find_free_tile_near(t, 6))
	return out


## The farm index for the active hunt (picked once, kept in the save).
static func hunt_farm(p, world) -> int:
	var s: Dictionary = p.quests[QUEST]
	if not s.has("farm"):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		s["farm"] = rng.randi_range(0, maxi(0, farm_tiles(world).size() - 1))
	return int(s["farm"])


static func _player(actors: Array):
	for a in actors:
		if a is Player:
			return a
	return null


## Called by EnemyManager each tick before Greymaw's own tick.
## Returns false when she is dormant (skip her tick).
static func manage(e, t: int, world, actors: Array) -> bool:
	var p = _player(actors)
	var ph: String = phase(p)
	var farms: Array = farm_tiles(world) if e.get_meta("farms", []).is_empty() else e.get_meta("farms")
	e.set_meta("farms", farms)
	if farms.is_empty():
		return false
	if ph == "off":
		if not e.dead:
			e.dead = true
			e.visible = false
			e.target = null
		e.respawn_at = 1 << 40
		e.set_meta("hunt_spawned", false)
		return false
	if ph == "hunt":
		if e.dead and not bool(e.get_meta("hunt_spawned", false)):
			e.home = farms[hunt_farm(p, world) % farms.size()]
			e._respawn()
			e.set_meta("hunt_spawned", true)
		return not e.dead
	# free: the timer
	if e.dead:
		if e.respawn_at > t + int(e.def.get("respawn_ticks", 1000)):
			e.respawn_at = t + int(e.def.get("respawn_ticks", 1000))
		if t >= e.respawn_at:
			e.home = farms[e.rng.randi_range(0, farms.size() - 1)]
			e._respawn()
		return not e.dead
	return true


## Extra drops: 4 wolf pelts always; the quest hide on the hunt kill; on timer
## kills a 1 in 8 dire wolf pelt. `hunt` = phase before the kill was counted.
static func extra_drops(hunt: bool, free: bool, rng: RandomNumberGenerator) -> Array:
	var d: Array = [["wolf_pelt", 1], ["wolf_pelt", 1], ["wolf_pelt", 1], ["wolf_pelt", 1]]
	if hunt:
		d.append(["greymaw_hide", 1])
	elif free and rng.randi_range(1, 8) == 1:
		d.append(["dire_wolf_pelt", 1])
	return d
