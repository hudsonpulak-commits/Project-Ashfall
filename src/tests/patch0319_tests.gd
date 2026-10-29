class_name Patch0319Tests
extends RefCounted
## 0.3.19 custom bank tabs in the HUD, sprite-clip audit, tree sway, canopy and
## roof fade, ground colour variation and worn paths.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(main, world: World, p: Player) -> void:
	print("  -- 0.3.19 bank tabs + scene polish")
	check(str(ProjectSettings.get_setting("application/config/version")).begins_with("0.3."), "0.3.19 scene polish still ships on the 0.3 line")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(preset.contains("version/code="), "Android export still carries a versionCode")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	check(a.randi() == b.randi() and a.randf() == b.randf(), "a seeded RNG repeats (selftest stays deterministic)")
	_bank_ui(main, world, p)
	_clip()
	_foliage(world, p)
	_ground(world)
	_roof_behind(world, p)
	_armour_fits(p)


static func _bank_ui(main, world: World, p: Player) -> void:
	var hud = main.hud
	var keep_tile: Vector2i = p.tile
	var keep_bank: Array = p.bank.slots.duplicate(true)
	var keep_tabs: Dictionary = BankTabs.to_save(p)
	var keep_arrange: bool = hud.bank_arrange
	var chest: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow"), ["bank_chest"], 40)
	p.bank.clear()
	p.bank_tabs = []
	p.bank_tab_of = {}
	p.bank.add("iron_ore", 4)
	p.bank.add("coal", 2)
	p.place_at(chest.pos)
	hud.bank_tab = BankTabs.ALL
	hud.bank_arrange = true
	hud._bank_sel = -1
	hud.show_panel("bank")
	check(hud.BANK_TABS_ON and hud.bank_tab_scroll.visible and hud.bank_tab_row.get_node_or_null("BankTabAdd") != null,
		"custom bank tabs are shown (All, Main, and New)")
	(hud.bank_tab_row.get_node("BankTabAdd") as Button).pressed.emit()
	check(p.bank_tabs.size() == 1 and hud.bank_tab == 1, "New creates a tab and opens it")
	var ed := hud.bank_edit_row.get_node_or_null("BankTabName") as LineEdit
	check(ed != null, "Arrange on a custom tab offers a name field")
	if ed:
		ed.text = "Ores"
		hud._sync_bank_tab_name()
	check(p.bank_tabs[0]["name"] == "Ores", "typing renames the tab without an enter key")
	# file coal (slot 1) onto the new tab, then swap the two stacks with Arrange
	hud.bank_tab = BankTabs.ALL
	hud._bank_sel = -1
	hud._refresh_bank()
	hud._on_bank_tap(1)
	check(hud._bank_sel == 1, "Arrange still picks a stack (gold selection)")
	hud._on_bank_tab(1)
	check(BankTabs.tab_of(p, "coal") == 1 and BankTabs.tab_of(p, "iron_ore") == 0 and hud._bank_sel == -1,
		"tapping a tab files the picked item there")
	hud.bank_tab = BankTabs.ALL
	hud._refresh_bank()
	hud._on_bank_tap(0)
	hud._on_bank_tap(1)
	check(p.bank.slots[0]["id"] == "coal" and p.bank.slots[1]["id"] == "iron_ore", "Arrange still swaps stacks while tabs are on")
	hud.bank_tab = 1
	hud._bank_sel = p.bank.find("coal")
	hud._refresh_bank()
	(hud.bank_edit_row.get_node("BankTabIcon") as Button).pressed.emit()
	check(str(p.bank_tabs[0]["icon"]) == "coal", "Icon uses the picked item")
	var q := Player.new()
	q.from_save(p.to_save())
	check(q.bank_tabs.size() == 1 and q.bank_tabs[0]["name"] == "Ores" and q.bank_tabs[0]["icon"] == "coal" and BankTabs.tab_of(q, "coal") == 1 and q.bank.slots[0]["id"] == "coal",
		"tabs, names, icons and the swapped order survive save/load")
	q.free()
	hud.bank_tab = 1
	hud._refresh_bank()
	(hud.bank_edit_row.get_node("BankTabDelete") as Button).pressed.emit()
	check(p.bank_tabs.is_empty() and BankTabs.tab_of(p, "coal") == 0 and BankTabs.tab_of(p, "iron_ore") == 0 and hud.bank_tab == 0,
		"deleting a tab returns its items to Main")
	hud.show_panel("")
	hud.bank_arrange = keep_arrange
	p.bank.slots = keep_bank
	p.bank.changed.emit()
	BankTabs.from_save(p, keep_tabs)
	p.place_at(keep_tile)


static func _clip() -> void:
	var cut := Image.create(8, 10, false, Image.FORMAT_RGBA8)
	cut.fill(Color(0, 0, 0, 0))
	for y in 8:
		cut.set_pixel(0, y, Color(0.2, 0.6, 0.2, 1))
	var clear := Image.create(8, 10, false, Image.FORMAT_RGBA8)
	clear.fill(Color(0, 0, 0, 0))
	clear.set_pixel(3, 4, Color(0.2, 0.6, 0.2, 1))
	check(SpriteAudit.border_hit(cut) and SpriteAudit.edge_run(cut, "L") > 0.7 and not SpriteAudit.border_hit(clear),
		"the clip audit flags a sliced edge and accepts a sprite with a clear margin")
	var bad := SpriteAudit.clipped_foliage()
	check(bad.is_empty(), "no foliage sprite is cut off at the frame (palms included) %s" % str(bad))


static func _foliage(world: World, p: Player) -> void:
	var keep: Vector2i = p.tile
	var tree: WorldObject = world.find_nearest_object(world.gen.town_spawn("fenhollow"), ["ash_tree"], 40)
	if tree:
		world.set_focus(tree.pos, true)
		tree = world.object_at(tree.pos)
	check(tree != null and tree.view != null and tree.view.material is ShaderMaterial, "trees use the wind sway shader")
	if tree and tree.view:
		var mat := tree.view.material as ShaderMaterial
		check(mat.shader != null and str(mat.shader.resource_path).ends_with("foliage_sway.gdshader"), "trees share one sway shader, phased from each sprite's position")
		p.place_at(tree.pos + Vector2i(0, -1))
		world._update_canopies(1.0)
		check(tree.view.modulate.a <= 0.45, "the canopy fades when you stand behind the tree (alpha %.2f)" % tree.view.modulate.a)
		p.place_at(tree.pos + Vector2i(0, 3))
		world._update_canopies(1.0)
		check(tree.view.modulate.a >= 0.95, "the canopy comes back when you stand in front of the tree")
	p.place_at(keep)
	world.set_focus(keep, true)


static func _ground(world: World) -> void:
	var shaded := false
	for c in world.chunk_views.keys():
		var layer := (world.chunk_views[c] as Node2D).get_child(0)
		if layer is TileMapLayer and layer.material is ShaderMaterial:
			shaded = true
			break
	check(shaded, "ground tiles use the colour-variation shader")
	var near := Vector2i(1 << 20, 0)
	var ragged := false
	for road in world.gen.road_tiles.keys():
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = road + d
			var t := world.gen.tile_at(q.x, q.y)
			if (t in WorldGen.GRASS_TILES or t == WorldGen.TileType.DIRT) and not world.gen.road_tiles.has(q):
				near = q
				break
		if near.x != 1 << 20:
			for d2 in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(2, 1), Vector2i(-2, 1), Vector2i(1, 2)]:
				if world.wear_amount(road + d2) == 0.0:
					ragged = true
			break
	var far := Vector2i(1 << 20, 0)
	var origin := world.gen.town_spawn("fenhollow")
	for r in range(12, 70):
		for d in [Vector2i(r, r), Vector2i(-r, r), Vector2i(r, -r), Vector2i(-r, 0)]:
			var q2: Vector2i = origin + d
			if world.gen.tile_at(q2.x, q2.y) in WorldGen.GRASS_TILES and world.wear_amount(q2) == 0.0:
				far = q2
				break
		if far.x != 1 << 20:
			break
	check(near.x != 1 << 20 and world.wear_amount(near) > 0.45 and far.x != 1 << 20 and world.wear_amount(far) == 0.0 and ragged,
		"worn paths darken grass beside roads and doors, ragged rather than a hard band (near %.2f)" % world.wear_amount(near))


static func _roof_behind(world: World, p: Player) -> void:
	var bid := ""
	var north := Vector2i.ZERO
	for id in world.gen.building_order:
		var b: Dictionary = world.gen.buildings[id]
		if not b.has("art"):
			continue
		var r: Rect2i = b["rect"]
		for x in range(r.position.x, r.end.x):
			var t := Vector2i(x, r.position.y - 1)
			var host: Dictionary = world.gen.building_at(t)
			if host.is_empty() or not world.gen.is_inside(t, host):
				bid = id
				north = t
				break
		if bid != "":
			break
	check(bid != "", "an art building has a tile just north of its roof")
	if bid == "":
		return
	var keep: Vector2i = p.tile
	var bv: BuildingsView = world.buildings_view
	p.place_at(north)
	bv.step(5.0)
	check(is_equal_approx(bv.roof_alpha(bid), 0.4), "the roof fades to 0.4 when you stand behind it (alpha %.2f)" % bv.roof_alpha(bid))
	var inside: Vector2i = world.gen.buildings[bid]["stand"]
	p.place_at(inside)
	bv.step(5.0)
	check(bv.roof_alpha(bid) <= 0.001, "standing under the roof still cuts it away")
	p.place_at(north + Vector2i(0, -8))
	bv.step(5.0)
	check(bv.roof_alpha(bid) >= 0.999, "the roof returns once you walk clear of it")
	p.place_at(keep)
	bv.step(5.0)


## 0.3.19 plate favours block, chain favours hit chance, same power. Old saves
## keep the ids they already had, and those ids are the plate fit.
static func _armour_fits(p: Player) -> void:
	var plates: Array = []
	var chains: Array = []
	var ranger_ok := true
	for id in GameData.items.keys():
		var g: Dictionary = GameData.items[id].get("gear", {})
		var fit := str(g.get("fit", ""))
		if fit == "plate":
			plates.append(id)
		elif fit == "chain":
			chains.append(id)
		var sid := str(id)
		if sid.contains("leather") or sid.contains("pelt") or sid == "cowhide":
			ranger_ok = ranger_ok and fit == ""
	ranger_ok = ranger_ok and not GameData.item("alder_buckler").get("gear", {}).has("fit") and int(GameData.item("alder_buckler")["gear"]["def"]) == 3 and int(GameData.item("alder_buckler")["gear"].get("atk", 0)) == 0
	check(plates.size() == 15 and chains.size() == 15, "every melee armour piece (bronze, iron, steel, dusk, including metal shields) has a plate and a chain (%d/%d)" % [plates.size(), chains.size()])
	var paired := true
	var balance := true
	var smith_ok := true
	var xp_ok := true
	for pid in plates:
		var pg: Dictionary = GameData.item(pid)["gear"]
		var mate := ""
		for cid in chains:
			var cg: Dictionary = GameData.item(cid)["gear"]
			if str(cg["slot"]) == str(pg["slot"]) and int(cg["tier"]) == int(pg["tier"]):
				if mate != "":
					paired = false
				mate = cid
		if mate == "":
			paired = false
			continue
		var cg2: Dictionary = GameData.item(mate)["gear"]
		var p_atk := int(pg["atk"])
		var p_def := int(pg["def"])
		var c_atk := int(cg2["atk"])
		var c_def := int(cg2["def"])
		balance = balance and p_atk + p_def == c_atk + c_def and p_def > c_def and c_atk > p_atk and p_atk >= 1 and c_def >= 1
		balance = balance and int(pg["level"]) == int(cg2["level"]) and int(pg["tier"]) == int(cg2["tier"]) and int(GameData.item(pid)["value"]) == int(GameData.item(mate)["value"])
		xp_ok = xp_ok and is_equal_approx(Combat.armour_hit_xp([pid]), Combat.armour_hit_xp([mate])) and is_equal_approx(Combat.armour_hit_xp([pid]), Combat.tier_hit_xp(int(pg["tier"])))
		var pr := _recipe_for(str(pid))
		var cr := _recipe_for(mate)
		smith_ok = smith_ok and pr.get("station", "") == "anvil" and cr.get("station", "") == "anvil" and int(pr.get("level", -1)) == int(cr.get("level", -2)) and pr.get("in", {}) == cr.get("in", {})
	check(paired and balance, "plate blocks more and chain hits more, with the same power, value, tier and Defence level")
	check(smith_ok, "plate and chain are smithed at the anvil from the same bars at the same smithing level")
	check(xp_ok and is_equal_approx(Combat.tier_hit_xp(1), 0.5) and is_equal_approx(Combat.tier_hit_xp(2), 1.0) and is_equal_approx(Combat.tier_hit_xp(3), 2.0) and is_equal_approx(Combat.tier_hit_xp(4), 3.0),
		"Defence XP per piece is unchanged for both fits (bronze 0.5, iron 1, steel 2, dusk 3)")
	check(ranger_ok, "leather, wolf pelt and the alder buckler are unchanged")
	var gob: Dictionary = GameData.enemies["goblin"]
	var helm_p: Dictionary = GameData.item("iron_helm")["gear"]
	var helm_c: Dictionary = GameData.item("iron_chain_coif")["gear"]
	check(Combat.actor_accuracy(20, int(helm_c["atk"]), int(gob["defence"])) > Combat.actor_accuracy(20, int(helm_p["atk"]), int(gob["defence"])),
		"chain raises hit chance (iron coif atk %d vs plate helm atk %d)" % [int(helm_c["atk"]), int(helm_p["atk"])])
	check(Combat.enemy_accuracy(gob, int(helm_p["def"]), 20) < Combat.enemy_accuracy(gob, int(helm_c["def"]), 20),
		"plate raises block chance (iron helm def %d vs chain coif def %d)" % [int(helm_p["def"]), int(helm_c["def"])])
	var keep_eq: Dictionary = p.equipment.duplicate()
	var keep_def := p.skills.level("defence")
	p.skills.set_level("defence", 30)
	p.equipment.erase("head")
	p.inventory.add("iron_chain_coif")
	p.inventory.add("iron_helm")
	var wore_c := p.equip_slot(p.inventory.find("iron_chain_coif")) == ""
	var c_hit := p.combat_atk()
	var c_blk := p.combat_def()
	p.unequip("head")
	var wore_p := p.equip_slot(p.inventory.find("iron_helm")) == ""
	var p_hit := p.combat_atk()
	var p_blk := p.combat_def()
	check(wore_c and wore_p and c_hit > p_hit and p_blk > c_blk and c_hit + c_blk == p_hit + p_blk,
		"wearing chain raises hit chance, wearing plate raises block, and the totals match")
	var plate_tip := Combat.gear_note("iron_helm")
	var chain_tip := Combat.gear_note("iron_chain_coif")
	check(plate_tip.contains("Plate:") and plate_tip.contains("% block") and chain_tip.contains("Chain:") and chain_tip.contains("% hit") and Combat.equip_stat_line(p_hit, p_blk).contains("hit") and Combat.equip_stat_line(p_hit, p_blk).contains("block"),
		"the item line and the equipment stats show the hit and block bonuses")
	var old := {"version": 8, "player": {"tile": [3, 3], "equipment": {"head": "bronze_cap", "body": "iron_hauberk"}, "inventory": [{"id": "steel_helm", "qty": 1}]}, "world": {"seed": 7331}}
	var mig: Dictionary = SaveSystem._migrate(old)
	var q := Player.new()
	q.from_save(mig["player"])
	check(int(mig["version"]) == SaveSystem.SAVE_VERSION and q.equipment.get("head", "") == "bronze_cap" and q.equipment.get("body", "") == "iron_hauberk" and q.inventory.count("steel_helm") == 1
		and str(GameData.item(q.equipment["head"])["gear"]["fit"]) == "plate" and str(GameData.item(q.equipment["body"])["gear"]["fit"]) == "plate" and str(GameData.item("steel_helm")["gear"]["fit"]) == "plate",
		"an old save loads, and the armour it already had is plate")
	q.free()
	p.unequip("head")
	p.inventory.remove("iron_helm", 1)
	p.inventory.remove("iron_chain_coif", 1)
	p.equipment = keep_eq
	p.skills.set_level("defence", keep_def)


static func _recipe_for(item_id: String) -> Dictionary:
	for r in GameData.recipes:
		if (r as Dictionary).get("out", {}).has(item_id):
			return r
	return {}
