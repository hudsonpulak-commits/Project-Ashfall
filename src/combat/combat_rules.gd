class_name CombatRules
extends RefCounted
## Single-way combat by default; multi-combat only inside the tile rects of
## data/combat_zones.json (shipped empty). See docs/GDD.md 13.7.
##  - An actor in combat can only be attacked by the enemy it is fighting.
##  - An enemy in combat with one actor can't be attacked by another actor.
##  - "In combat" = within combat_ticks of the last swing dealt/taken (or of
##    an enemy aggroing onto you), and the foe is still alive.

static func combat_ticks() -> int:
	return int(GameData.combat_zones.get("combat_ticks", 8))


static func zones() -> Array:
	return GameData.combat_zones.get("zones", [])


static func zone_at(tile: Vector2i) -> Dictionary:
	for z in zones():
		var r: Array = z.get("rect", [0, 0, 0, 0])
		if Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(tile):
			return z
	return {}


## Multi-combat here? A data zone, or (0.3.1) any PK zone: the whole Scorch is multi.
static func is_multi(tile: Vector2i) -> bool:
	return not zone_at(tile).is_empty() or PkRules.is_pk(tile)


## Name for messages: an Enemy / WorldObject display_name(), an Actor's name.
static func label(x) -> String:
	if x == null or not is_instance_valid(x):
		return "?"
	if x is Actor:
		return str(x.display_name)
	return str(x.display_name())


static func _alive(x) -> bool:
	return x != null and is_instance_valid(x) and not x.dead


## The enemy an actor is engaged with right now, or null.
static func actor_foe(actor, t: int):
	var f = actor.combat_foe
	if _alive(f) and t - int(actor.last_combat_tick) < combat_ticks():
		return f
	return null


## The actor an enemy is engaged with right now, or null.
static func enemy_foe(enemy, t: int):
	var a = enemy.target
	if _alive(a) and t - int(enemy.last_combat_tick) < combat_ticks():
		return a
	return null


## May `enemy` aggro onto / swing at `actor`?
static func can_aggro(enemy, actor, t: int) -> bool:
	if is_multi(actor.tile):
		return true
	var f = actor_foe(actor, t)
	return f == null or f == enemy


## May `actor` attack `enemy`? "" = yes, else the reason shown to the player.
static func can_attack(actor, enemy, t: int) -> String:
	if enemy is Actor:
		return PkRules.can_pvp(actor, enemy, t)   # 0.3.1: other players only in PK zones (all multi)
	if bool(enemy.def.get("no_attack", false)):     # 0.3.16 quest animals (Clip Clop)
		return "You can't attack %s." % enemy.display_name()
	if is_multi(enemy.tile):
		return ""
	var ef = enemy_foe(enemy, t)
	if ef != null and ef != actor:
		return "Someone else is fighting that."
	var af = actor_foe(actor, t)
	if af != null and af != enemy and af.target == actor:
		return "You're already under attack."
	return ""


## Share of this enemy kind's camps that sit inside a multi zone (abstract sims).
static func camp_multi_share(kind: String) -> float:
	var n := 0
	var m := 0
	for c in GameData.camps:
		if str(c.get("enemy", "")) != kind:
			continue
		n += 1
		if is_multi(Vector2i(int(c["at"][0]), int(c["at"][1]))):
			m += 1
	return float(m) / n if n > 0 else 0.0


## Incoming-damage factor for abstract fights against this kind.
static func abstract_damage_mult(kind: String) -> float:
	return 1.0 + float(GameData.combat_zones.get("abstract_multi_damage", 0.5)) * camp_multi_share(kind)
