class_name Combat
extends RefCounted
## Combat rules shared by the player, tier-0 AI players (real fights) and the
## abstract AI simulation (expected values). Tick-based: an actor swings every
## weapon-class attack_ticks (dagger 3, warhammer 5, others 4), enemies every
## their own attack_ticks; a swing hits with an accuracy chance for 1..max_hit.
## 0.2.4: three combat skills (data/combat.json):
##   actor accuracy = 0.55 + (Attack + gear atk) * 1%
##                    - enemy defence * (1 - armour_break) * 2%           (10-95 %)
##   actor max hit  = 1 + Strength / 6 + weapon power + gear str / 4
##   enemy accuracy = enemy accuracy - gear def * 1% - Defence * 0.5%       (5-95 %)
##   enemy max hit  = from data/enemies.json
## XP: damage dealt x damage_xp goes to the style's skill (Accurate -> Attack,
## Aggressive -> Strength), x vitality_xp to Vitality. Every enemy swing at you
## gives Defence XP (block / hit), x the full-armour-set bonus.
## Max HP = 10 + Vitality level. Out of combat everyone regains 1 HP / 30 ticks.

const ATTACK_TICKS := 4
const REGEN_TICKS := 30
const EAT_DELAY := 2
const SEARCH_TICKS := 30         # abstract fights: finding the next creature, looting, resting
const COMBAT_SKILLS := ["attack", "strength", "defence"]
const ARMOUR_SLOTS := ["head", "body", "legs", "shield"]


static func cfg() -> Dictionary:
	return GameData.combat


## 0.3.3 combat level, shared by the player, AI players and the aggro rule:
## floor((Attack + Strength + Defence + Vitality + Archery) / 5 + Prayer / 8), min 1.
static func combat_level(skills: Skills) -> int:
	if skills == null:
		return 1
	var base := (skills.level("attack") + skills.level("strength") + skills.level("defence") + skills.level("vitality") + skills.level("archery")) / 5.0
	return maxi(1, int(floor(base + skills.level("prayer") / 8.0)))


## 0.3.1: enemies don't START fights with anyone aggro_level_gap+ combat levels above them.
static func too_strong_for_aggro(enemy_level: int, skills: Skills) -> bool:
	return combat_level(skills) >= enemy_level + int(cfg().get("aggro_level_gap", 10))


static func max_hp(skills: Skills) -> int:
	return 10 + skills.level("vitality")


# ------------------------------------------------------- weapon classes --
static func weapon_class(item_id: String) -> String:
	var gd: Dictionary = GameData.item(item_id).get("gear", {}) if item_id != "" else {}
	return str(gd.get("class", "")) if gd.get("slot", "") == "weapon" else ""


static func class_def(item_id: String) -> Dictionary:
	return cfg().get("classes", {}).get(weapon_class(item_id), {})


## Skill needed to use a gear piece: weapon class skill, Defence for armour.
static func req_skill(item_id: String) -> String:
	var gd: Dictionary = GameData.item(item_id).get("gear", {})
	if gd.is_empty():
		return ""
	if gd.get("slot", "") == "weapon":
		return str(class_def(item_id).get("skill", "attack"))
	if gd.get("slot", "") in ARMOUR_SLOTS:
		return str(cfg().get("armour_skill", "defence"))
	return ""


## "" if these skills may use the item, else the refusal message.
static func equip_error(skills: Skills, item_id: String) -> String:
	var s := req_skill(item_id)
	if s == "":
		return ""
	var need := int(GameData.item(item_id)["gear"].get("level", 1))
	if skills.level(s) < need:
		return "You need %s level %d to use that." % [GameData.skill_by_id[s]["name"], need]
	return ""


static func default_style(weapon_id: String) -> String:
	return str(class_def(weapon_id).get("style", "accurate")) if weapon_id != "" else "accurate"


static func style_skill(style: String) -> String:
	return str(cfg().get("styles", {}).get(style, {}).get("skill", "attack"))


static func style_label(style: String) -> String:
	return str(cfg().get("styles", {}).get(style, {}).get("label", style.capitalize()))


static func weapon_ticks(weapon_id: String) -> int:
	return int(class_def(weapon_id).get("attack_ticks", ATTACK_TICKS)) if weapon_id != "" else ATTACK_TICKS


## Crush weapons ("armour breakers") ignore this share of enemy defence.
static func armour_break(weapon_id: String) -> float:
	return float(class_def(weapon_id).get("armour_break", 0.0)) if weapon_id != "" else 0.0


# ------------------------------------------------------------ set bonus --
## Full armour set (helm + body + legs + shield) all of one tier ->
## {"tier", "mult", "name"}; anything else -> tier 0, mult 1.0.
static func set_bonus(armour_ids: Array) -> Dictionary:
	var sb: Dictionary = cfg().get("set_bonus", {})
	var need: Array = sb.get("slots", ARMOUR_SLOTS)
	var by_slot := {}
	for id in armour_ids:
		var gd: Dictionary = GameData.item(str(id)).get("gear", {})
		if gd.get("slot", "") in need:
			by_slot[gd["slot"]] = int(gd.get("tier", 0))
	var tier := -1
	for slot in need:
		if not by_slot.has(slot) or (tier >= 0 and int(by_slot[slot]) != tier):
			return {"tier": 0, "mult": 1.0, "name": ""}
		tier = int(by_slot[slot])
	var key := str(tier)
	return {"tier": tier, "mult": float(sb.get("mult", {}).get(key, 1.0)), "name": str(sb.get("names", {}).get(key, "tier %d" % tier))}


# ----------------------------------------------------------------- XP --
## Fractional XP rounded stochastically (keeps the expected value exact).
static func roll_xp(amount: float, rng: RandomNumberGenerator) -> int:
	var n := int(floor(amount))
	return n + (1 if rng.randf() < amount - n else 0)


## Defence XP for one enemy swing at you, before the set bonus.
static func defence_xp(dmg: int) -> float:
	var d: Dictionary = cfg().get("defence_xp", {})
	if dmg <= 0:
		return float(d.get("block", 2.0))
	return float(d.get("hit_base", 2.0)) + float(d.get("hit_per_damage", 1.0)) * dmg


static func award_defence_xp(skills: Skills, dmg: int, set_mult: float, rng: RandomNumberGenerator) -> int:
	var n := roll_xp(defence_xp(dmg) * set_mult, rng)
	skills.add_xp("defence", n)
	return n


## Damage dealt: the style's skill (Attack / Strength) plus Vitality.
static func award_hit_xp(skills: Skills, style: String, dmg: int) -> void:
	if dmg <= 0:
		return
	skills.add_xp(style_skill(style), int(round(dmg * float(cfg().get("damage_xp", 4.0)))))
	skills.add_xp("vitality", int(round(dmg * float(cfg().get("vitality_xp", 1.4)))))


# ------------------------------------------------------------- formulas --
static func actor_accuracy(attack: int, atk: int, enemy_def: int, brk: float = 0.0) -> float:
	return clampf(0.55 + (attack + atk) * 0.01 - enemy_def * (1.0 - brk) * 0.02, 0.1, 0.95)


static func actor_max_hit(strength: int, power: float, str_bonus: int) -> int:
	return 1 + int(strength / 6.0) + int(power) + int(str_bonus / 4.0)


static func enemy_accuracy(e: Dictionary, def_bonus: int, defence_lvl: int = 0) -> float:
	return clampf(float(e.get("accuracy", 0.5)) - def_bonus * 0.01 - defence_lvl * float(cfg().get("defence_level_acc", 0.005)), 0.05, 0.95)


## One swing: returns damage (0 = miss).
static func swing(acc: float, max_hit: int, rng: RandomNumberGenerator) -> int:
	if rng.randf() >= acc:
		return 0
	return rng.randi_range(1, maxi(1, max_hit))


## Expected fight against enemy `e` (abstract sim). `s` holds the fighter:
## attack/strength/defence levels, gear atk/str/def, weapon power, weapon id
## and set_mult. Returns ticks per kill, damage taken, enemy swings and the
## expected Defence XP per kill.
static func expected_fight(e: Dictionary, s: Dictionary, acc_mult: float = 1.0, dmg_mult: float = 1.0, def_mult: float = 1.0) -> Dictionary:
	var w := str(s.get("weapon", ""))
	var acc := minf(0.95, actor_accuracy(int(s.get("attack", 1)), int(s.get("atk", 0)), int(e.get("defence", 0)), armour_break(w)) * acc_mult)
	var mh := actor_max_hit(int(s.get("strength", 1)), float(s.get("power", 0.0)), int(s.get("str", 0)))
	var dps := acc * (1.0 + mh) / 2.0 * dmg_mult / weapon_ticks(w)
	var swing_ticks := float(e.get("hp", 5)) / maxf(0.01, dps)
	var ticks := swing_ticks + SEARCH_TICKS
	var e_acc := enemy_accuracy(e, int(s.get("def", 0)), int(s.get("defence", 1))) * def_mult
	var e_max := float(e.get("max_hit", 1))
	var swings := swing_ticks / float(e.get("attack_ticks", ATTACK_TICKS))
	var taken := e_acc * (1.0 + e_max) / 2.0 * swings
	var dx: Dictionary = cfg().get("defence_xp", {})
	var per_swing := (1.0 - e_acc) * float(dx.get("block", 2.0)) + e_acc * (float(dx.get("hit_base", 2.0)) + float(dx.get("hit_per_damage", 1.0)) * (1.0 + e_max) / 2.0)
	return {"ticks": ticks, "damage": taken, "swings": swings, "def_xp": per_swing * swings * float(s.get("set_mult", 1.0))}


# ------------------------------------------------------------ 0.3.3 archery --
static func rcfg() -> Dictionary:
	return cfg().get("ranged", {})


static func is_ranged(weapon_id: String) -> bool:
	return weapon_id != "" and str(class_def(weapon_id).get("style", "")) == "ranged"


static func ranged_range() -> int:
	return int(rcfg().get("range", 5))


static func is_arrow(item_id: String) -> bool:
	return item_id.ends_with("_arrows") and GameData.item(item_id).get("gear", {}).get("slot", "") == "ammo"


## Best arrows in the pack this skill set may shoot ("" = out of arrows).
static func best_arrow(inv: ItemContainer, skills: Skills) -> String:
	var best := ""
	var bt := -1
	for s in inv.slots:
		if s == null or not is_arrow(str(s["id"])):
			continue
		var gd: Dictionary = GameData.item(s["id"])["gear"]
		if skills.level("archery") < int(gd.get("level", 1)):
			continue
		if int(gd.get("tier", 1)) > bt:
			bt = int(gd.get("tier", 1))
			best = str(s["id"])
	return best


static func arrow_power(arrow_id: String) -> int:
	if arrow_id == "":
		return 0
	return int(GameData.item(arrow_id).get("gear", {}).get("tier", 1)) * int(rcfg().get("arrow_tier_power", 1))


## Line of sight: wall / building tiles block; plants, rocks, fences, logs, water and the moat don't.
static func line_of_sight(world, a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, n):
		var p := Vector2i(roundi(lerpf(a.x, b.x, float(i) / n)), roundi(lerpf(a.y, b.y, float(i) / n)))
		var tt: int = world.tile_type(p)
		if tt in WorldGen.BLOCKING_TILES and not (tt in WorldGen.SHOOT_OVER_TILES):
			return false
	return true
