class_name DropTable
extends RefCounted
## Data-driven drop tables (data/drops.json):
##   {"always": [{"item", "qty"}],
##    "common": {"chance": p, "entries": [{"item", "qty", "weight"}]},
##    "rare":   {"chance": p, "entries": [...]}}
## One roll per kill: rare (with its chance) beats common (with its chance),
## else nothing. "qty" is n or [min, max]. Always-drops always come.


static func table(id: String) -> Dictionary:
	return GameData.drop_tables.get(id, {})


static func _qty(e: Dictionary, rng: RandomNumberGenerator) -> int:
	var q = e.get("qty", 1)
	if q is Array:
		return rng.randi_range(int(q[0]), int(q[1]))
	return int(q)


static func _pick(group: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var entries: Array = group.get("entries", [])
	var total := 0.0
	for e in entries:
		total += float(e.get("weight", 1))
	if total <= 0.0:
		return {}
	var r := rng.randf() * total
	for e in entries:
		r -= float(e.get("weight", 1))
		if r <= 0.0:
			return e
	return entries[-1]


## Returns [[item_id, qty], ...] for one kill.
static func roll(id: String, rng: RandomNumberGenerator) -> Array:
	var t := table(id)
	var out: Array = []
	for e in t.get("always", []):
		out.append([str(e["item"]), _qty(e, rng)])
	var rare: Dictionary = t.get("rare", {})
	var common: Dictionary = t.get("common", {})
	var e2 := {}
	if rng.randf() < float(rare.get("chance", 0.0)):
		e2 = _pick(rare, rng)
	elif rng.randf() < float(common.get("chance", 0.0)):
		e2 = _pick(common, rng)
	if not e2.is_empty():
		out.append([str(e2["item"]), _qty(e2, rng)])
	return out


## Expected marks per kill, valuing items with `valuer(item) -> float`
## (used by the AI to compare fighting with other work).
static func expected_value(id: String, valuer: Callable) -> float:
	var t := table(id)
	var v := 0.0
	for e in t.get("always", []):
		v += _mean_qty(e) * float(valuer.call(str(e["item"])))
	var rare: Dictionary = t.get("rare", {})
	var common: Dictionary = t.get("common", {})
	var p_rare := float(rare.get("chance", 0.0))
	var p_common := (1.0 - p_rare) * float(common.get("chance", 0.0))
	for pair in [[rare, p_rare], [common, p_common]]:
		var g: Dictionary = pair[0]
		var total := 0.0
		for e in g.get("entries", []):
			total += float(e.get("weight", 1))
		for e in g.get("entries", []):
			v += float(pair[1]) * float(e.get("weight", 1)) / maxf(1.0, total) * _mean_qty(e) * float(valuer.call(str(e["item"])))
	return v


static func _mean_qty(e: Dictionary) -> float:
	var q = e.get("qty", 1)
	if q is Array:
		return (float(q[0]) + float(q[1])) / 2.0
	return float(q)


## Problems with the drop data (unknown items, bad chances). Empty = valid.
static func validate() -> Array:
	var errs: Array = []
	for id in GameData.drop_tables.keys():
		var t: Dictionary = GameData.drop_tables[id]
		for e in t.get("always", []):
			if not GameData.items.has(e["item"]) and e["item"] != GameData.currency:
				errs.append("%s: unknown item %s" % [id, e["item"]])
		for g in ["common", "rare"]:
			var grp: Dictionary = t.get(g, {})
			var c := float(grp.get("chance", 0.0))
			if c < 0.0 or c > 1.0:
				errs.append("%s.%s: chance %f" % [id, g, c])
			for e in grp.get("entries", []):
				if not GameData.items.has(e["item"]) and e["item"] != GameData.currency:
					errs.append("%s.%s: unknown item %s" % [id, g, e["item"]])
	for eid in GameData.enemies.keys():
		if not GameData.drop_tables.has(GameData.enemies[eid].get("drops", "")):
			errs.append("enemy %s: no drop table" % eid)
	return errs
