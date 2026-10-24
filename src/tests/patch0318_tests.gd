class_name Patch0318Tests
extends RefCounted
## 0.3.18 global damage x0.5 (min 1 on a hit) and the armour hit-XP bonus by tier.

static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(_main, _world, p) -> void:
	print("  -- 0.3.18 damage halved + armour XP")
	check(str(ProjectSettings.get_setting("application/config/version")) == "0.3.18", "version is 0.3.18")
	check(Combat.final_damage(0) == 0 and Combat.final_damage(1) == 1 and Combat.final_damage(2) == 1 and Combat.final_damage(4) == 2 and Combat.final_damage(10) == 5 and Combat.final_damage(9) == 5,
		"0.3.18 damage x0.5 at the final step, a hit never below 1, a miss stays 0")
	check(Combat.tier_hit_xp(1) == 0.5 and Combat.tier_hit_xp(2) == 1.0 and Combat.tier_hit_xp(3) == 2.0 and Combat.tier_hit_xp(4) == 3.0 and Combat.tier_hit_xp(5) == 4.0,
		"0.3.18 armour hit XP per piece: bronze 0.5, iron 1, steel 2, dusk 3, +1 per tier above")
	check(Combat.armour_hit_xp(["bronze_cap", "bronze_scale_vest", "bronze_greaves", "alder_buckler"]) == 2.0 and Combat.armour_hit_xp(["steel_helm", "iron_hauberk", "bronze_arrows"]) == 3.0,
		"0.3.18 the bonus sums over worn pieces (ammo excluded)")
	var keep_xp: Dictionary = p.skills.xp.duplicate()
	var keep_hp: int = p.hp
	var keep_gear: Dictionary = p.equipment.duplicate(true)
	p.equipment["head"] = "steel_helm"
	p.equipment["body"] = "iron_hauberk"
	p.equipment["legs"] = "bronze_greaves"
	var sum := 0.0
	var n := 40
	var e = _world.enemies.nearest(p.tile, [], 4000)
	var x0 := float(p.skills.xp["defence"])
	for i in n:
		p.hp = 999
		p.last_armour_bonus = 0.0
		p.take_hit(1, e, Tick.tick_count)
		sum += p.last_armour_bonus
	var gained := float(p.skills.xp["defence"]) - x0
	var base := Combat.defence_xp(1) * p.set_mult() * n
	var want := Combat.armour_hit_xp(p.armour_ids()) * n
	check(e != null and absf(sum - want) < 0.01 and gained >= base + want - n and gained <= base + want + n, "0.3.18 a hit on the player adds the armour bonus to Defence XP (worn %s: bonus %.2f/hit, gained %d vs base %d)" % [str(p.armour_ids()), want / n, int(gained), int(base)])
	check(absf(want / n - 3.5) < 0.01, "0.3.18 steel helm + iron body + bronze legs = +3.5 per hit")
	p.equipment = keep_gear
	p.skills.xp = keep_xp
	p.hp = keep_hp
