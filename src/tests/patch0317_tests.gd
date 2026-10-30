class_name Patch0317Tests
extends RefCounted
## 0.3.17 pack / bank organizing (move, swap, persistence) and custom bank tabs.


static func check(cond: bool, what: String) -> void:
	WorldTests.check(cond, what)


static func run(_main, _world, p) -> void:
	_map0317(_world)
	_journal0317(_main, p)
	print("  -- 0.3.17 organizing + bank tabs")
	check((str(ProjectSettings.get_setting("application/config/version")).begins_with("0.3.") or str(ProjectSettings.get_setting("application/config/version")).begins_with("0.4.")), "version is 0.3.x")
	var keep_inv: Array = p.inventory.slots.duplicate(true)
	var keep_bank: Array = p.bank.slots.duplicate(true)
	var keep_tabs: Dictionary = BankTabs.to_save(p)
	var inv: ItemContainer = p.inventory
	inv.clear()
	inv.add("copper_ore", 2)
	inv.add("bronze_hatchet", 1, 7)
	# move to an empty slot
	check(inv.move_slot(0, 10) and inv.slots[0] == null and inv.slots[10]["id"] == "copper_ore", "pack: move an item to an empty slot")
	# swap two items
	check(inv.move_slot(10, 2) and inv.slots[10]["id"] == "bronze_hatchet" and int(inv.slots[10]["dur"]) == 7 and inv.slots[2]["id"] == "copper_ore", "pack: tapping another item swaps them (tool keeps its wear)")
	check(not inv.move_slot(5, 6) and not inv.move_slot(2, 2), "pack: moving nothing / onto itself does nothing")
	check(inv.count("copper_ore") == 2 and inv.count("bronze_hatchet") == 1, "pack: counts unchanged by moving")
	# bank
	var bank: ItemContainer = p.bank
	bank.clear()
	bank.add("iron_ore", 5)
	bank.add("coal", 3)
	bank.add("raw_carp", 4)
	check(bank.move_slot(0, 2) and bank.slots[0]["id"] == "raw_carp" and bank.slots[2]["id"] == "iron_ore", "bank: swap two stacks")
	check(bank.move_slot(1, 7) and bank.slots[7]["id"] == "coal" and bank.slots[1] == null, "bank: move a stack to an empty slot")
	# tabs
	p.bank_tabs = []
	p.bank_tab_of = {}
	var t1 := BankTabs.add(p, "Ores")
	var t2 := BankTabs.add(p, "Fishing")
	BankTabs.set_icon(p, t1, "iron_ore")
	BankTabs.assign(p, "iron_ore", t1)
	BankTabs.assign(p, "coal", t1)
	BankTabs.assign(p, "raw_carp", t2)
	check(t1 == 1 and t2 == 2 and BankTabs.indices(p, bank, t1) == [2, 7] and BankTabs.indices(p, bank, t2) == [0], "tabs: items filed under Ores / Fishing")
	check(BankTabs.indices(p, bank, BankTabs.ALL).size() == 3 and BankTabs.indices(p, bank, 0).is_empty(), "tabs: All shows everything, Main only unfiled items")
	BankTabs.rename(p, t2, "Smithing")
	check(p.bank_tabs[1]["name"] == "Smithing" and p.bank_tabs[0]["icon"] == "iron_ore", "tabs: rename + item icon")
	var n := 2
	while BankTabs.add(p) > 0:
		n += 1
	check(n == BankTabs.MAX and p.bank_tabs.size() == 8, "tabs: at most 8 custom tabs")
	# save / load: pack positions, bank positions, tabs
	var q := Player.new()
	q.from_save(p.to_save())
	check(q.inventory.slots[10] != null and q.inventory.slots[10]["id"] == "bronze_hatchet" and q.inventory.slots[2]["id"] == "copper_ore" and q.inventory.slots[0] == null, "save/load keeps pack slot positions")
	check(q.bank.slots[7] != null and q.bank.slots[7]["id"] == "coal" and q.bank.slots[0]["id"] == "raw_carp", "save/load keeps bank slot positions")
	check(q.bank_tabs.size() == 8 and q.bank_tabs[0]["name"] == "Ores" and q.bank_tabs[0]["icon"] == "iron_ore" and BankTabs.tab_of(q, "coal") == 1 and BankTabs.tab_of(q, "raw_carp") == 2, "save/load keeps tabs, names, icons and filing")
	q.free()
	# delete: items return to Main, later tabs shift down
	BankTabs.assign(p, "raw_carp", 3)
	BankTabs.remove(p, t1)
	check(BankTabs.tab_of(p, "iron_ore") == 0 and BankTabs.tab_of(p, "coal") == 0 and BankTabs.tab_of(p, "raw_carp") == 2 and p.bank_tabs.size() == 7 and p.bank_tabs[0]["name"] == "Smithing", "tabs: deleting a tab returns its items to Main; later tabs shift")
	var old := Player.new()
	var d: Dictionary = p.to_save()
	d.erase("bank_tabs")
	old.from_save(d)
	check(old.bank_tabs.is_empty() and old.bank_tab_of.is_empty(), "an older save loads with no tabs")
	old.free()
	inv.slots = keep_inv
	bank.slots = keep_bank
	BankTabs.from_save(p, keep_tabs)
	inv.changed.emit()


## 0.3.17 no tree / cliff on or beside roads; stairs single, on straight cliff.
static func _map0317(world) -> void:
	var gen = world.gen
	var T := WorldGen.TileType
	var cliffs := [T.CLIFF_FACE, T.CLIFF_LIP, T.CLIFF_FOOT, T.CLIFF_STAIRS, T.CLIFF_SHADOW]
	var bad_tree: Array = []
	var bad_cliff: Array = []
	var nroad := 0
	var keys: Array = gen.road_tiles.keys()
	for town in gen._town_tiles.keys():
		if gen._town_tiles[town] in WorldGen.ROAD_SURFACES:
			keys.append(town)
	for i in range(0, keys.size(), 3):
		var r: Vector2i = keys[i]
		nroad += 1
		if gen.tile_at(r.x, r.y) in cliffs:
			bad_cliff.append(r)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q: Vector2i = r + Vector2i(dx, dy)
				var o: String = gen.object_at(q.x, q.y, gen.tile_at(q.x, q.y))
				if WorldGen.is_tree_id(o):
					bad_tree.append([q, o])
	check(nroad > 500 and bad_tree.is_empty(), "0.3.17 no tree on or next to a road tile (%d road tiles sampled, %s)" % [nroad, str(bad_tree.slice(0, 4))])
	check(bad_cliff.is_empty(), "0.3.17 no cliff on a road tile (%s)" % str(bad_cliff.slice(0, 4)))
	var stairs := 0
	var bad_adj: Array = []
	var bad_line: Array = []
	for y in range(-200, 200):
		for x in range(-200, 500):
			if gen.tile_at(x, y) != T.CLIFF_STAIRS:
				continue
			stairs += 1
			var p := Vector2i(x, y)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				if gen.tile_at(x + d.x, y + d.y) == T.CLIFF_STAIRS:
					bad_adj.append(p)
					break
			var e: int = gen._cliff_edge(p)
			var st := Vector2i(1, 0) if e != 0 else Vector2i(0, 1)
			var walls := [T.CLIFF_FACE, T.CLIFF_LIP]
			if not (gen.tile_at(x + st.x, y + st.y) in walls and gen.tile_at(x - st.x, y - st.y) in walls and gen._cliff_edge(p + st) == e and gen._cliff_edge(p - st) == e):
				bad_line.append(p)
	check(stairs > 20 and bad_adj.is_empty(), "0.3.17 every cliff stair stands alone (%d stairs, %d touching another: %s)" % [stairs, bad_adj.size(), str(bad_adj.slice(0, 4))])
	check(stairs > 20 and bad_line.is_empty(), "0.3.17 every stair has straight cliff on both sides along the line (%d bad: %s)" % [bad_line.size(), str(bad_line.slice(0, 4))])


## 0.3.17 journal: names + status only; one tap expands details, a second collapses.
static func _journal0317(main, p) -> void:
	var hud = main.hud
	var id := "kell_goblins" if not QuestSystem.quest("kell_goblins").is_empty() else str(QuestSystem.quests()[0]["id"])
	hud.quest_open = ""
	hud.refresh_quests()
	var b: Button = hud.quest_rows.get(id)
	check(b != null and hud.quest_box.get_node_or_null("QuestDetail") == null and not b.text.contains("Objective"), "0.3.17 journal collapsed: name + status only (%s)" % (b.text if b else "?"))
	b.pressed.emit()
	var d = hud.quest_box.get_node_or_null("QuestDetail")
	var txt: String = d.text if d else ""
	check(txt.contains("Given by: ") and txt.contains("(") and txt.contains("Objective: ") and (txt.contains("Return to: ") or txt.contains("Talk to ") or txt.contains("Done.")), "0.3.17 tap expands giver + place, objective, return-to (%s)" % txt.replace("\n", " | "))
	(hud.quest_rows.get(id) as Button).pressed.emit()
	check(hud.quest_box.get_node_or_null("QuestDetail") == null and hud.quest_open == "", "0.3.17 tap again collapses")
