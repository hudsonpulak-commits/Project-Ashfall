class_name Prayer
extends RefCounted
## Prayer buffs (data/prayers.json), shared by the player and AI players.
## State is a Dictionary owned by the actor / AI record:
##   {"id": active buff id or "", "points": prayer points left (float)}
## Max points = Prayer level x ticks_per_level. An active buff drains its
## "drain" points per tick and ends at 0. One buff at a time. Burying bones
## restores points (item "prayer_restore" share of max). With no buff active
## the pool regains 1 point every regen_ticks ticks.


static func cfg() -> Dictionary:
	return GameData.prayers


static func buffs() -> Array:
	return cfg().get("buffs", [])


static func buff(id: String) -> Dictionary:
	for b in buffs():
		if b["id"] == id:
			return b
	return {}


static func max_points(level: int) -> float:
	return float(maxi(1, level) * int(cfg().get("ticks_per_level", 10)))


static func points(state: Dictionary, level: int) -> float:
	return minf(float(state.get("points", max_points(level))), max_points(level))


## Ticks a buff lasts from a full pool (level x ticks_per_level for drain 1).
static func duration_ticks(level: int, id: String = "") -> int:
	var drain := float(buff(id).get("drain", 1.0)) if id != "" else 1.0
	return int(floor(max_points(level) / maxf(0.01, drain)))


static func is_active(state: Dictionary) -> bool:
	return str(state.get("id", "")) != ""


## Ticks left on the active buff at its drain rate.
static func ticks_left(state: Dictionary, level: int) -> int:
	if not is_active(state):
		return 0
	return int(ceil(points(state, level) / maxf(0.01, float(buff(str(state["id"])).get("drain", 1.0)))))


## Returns "" on success, else why it can't start.
static func activate(state: Dictionary, id: String, level: int) -> String:
	var b := buff(id)
	if b.is_empty():
		return "Unknown prayer."
	if level < int(b["level"]):
		return "You need Prayer level %d for %s." % [int(b["level"]), b["name"]]
	if is_active(state):
		return "%s is still active." % buff(str(state["id"])).get("name", "A prayer")
	if points(state, level) < 1.0:
		return "You have no prayer points left. Bury bones to restore them."
	state["points"] = points(state, level)
	state["id"] = id
	return ""


static func deactivate(state: Dictionary) -> void:
	state["id"] = ""


## Advance n ticks: drain the active buff, else regenerate slowly.
static func tick(state: Dictionary, level: int, n: int = 1) -> void:
	var p := points(state, level)
	if is_active(state):
		p -= float(buff(str(state["id"])).get("drain", 1.0)) * n
		if p <= 0.0:
			p = 0.0
			state["id"] = ""
	else:
		p = minf(max_points(level), p + float(n) / float(cfg().get("regen_ticks", 10)))
	state["points"] = p


## Bury-style restore: share of max points.
static func restore(state: Dictionary, level: int, share: float) -> void:
	state["points"] = minf(max_points(level), points(state, level) + share * max_points(level))


## Multiplier for an effect ("def", "dmg", "acc", "gather") right now.
## def returns the factor applied to ENEMY accuracy (below 1 is good).
static func mult(state: Dictionary, effect: String) -> float:
	if not is_active(state):
		return 1.0
	var b := buff(str(state["id"]))
	if b.get("effect", "") != effect:
		return 1.0
	var v := float(b.get("value", 0.0))
	return 1.0 - v if effect == "def" else 1.0 + v


## Best unlocked buff of a kind (highest level).
static func best(level: int, effect: String) -> String:
	var out := ""
	var lv := -1
	for b in buffs():
		if b["effect"] == effect and int(b["level"]) <= level and int(b["level"]) > lv:
			lv = int(b["level"])
			out = b["id"]
	return out


## AI before engaging: top up by burying bones (via `bury`, a Callable that
## buries one bone and returns true, or an invalid Callable), then pick
## defence when hurt, otherwise damage, then accuracy. Returns the id or "".
static func ai_pick(state: Dictionary, level: int, hp_frac: float, bury: Callable = Callable()) -> String:
	if is_active(state):
		return ""
	if bury.is_valid():
		var guard := 0
		while points(state, level) < max_points(level) * 0.6 and guard < 5 and bool(bury.call()):
			guard += 1
	if points(state, level) < max_points(level) * 0.3:
		return ""
	var order := ["def", "dmg", "acc"] if hp_frac < 0.6 else ["dmg", "acc", "def"]
	for eff in order:
		var id := best(level, eff)
		if id != "" and activate(state, id, level) == "":
			return id
	return ""


## Stochastic rounding so small damage multipliers still matter on average.
static func scale_damage(dmg: int, m: float, rng: RandomNumberGenerator) -> int:
	if dmg <= 0 or m == 1.0:
		return dmg
	var f := dmg * m
	var n := int(floor(f))
	if rng.randf() < f - n:
		n += 1
	return n
