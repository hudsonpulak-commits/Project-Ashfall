extends Node
## Global event bus. Keeps UI decoupled from simulation code.

signal message(text: String, kind: String)          # chat/game log line
signal xp_gained(skill_id: String, amount: int)
signal level_up(skill_id: String, level: int)
signal inventory_changed()
signal bank_changed()
signal bank_opened()
signal exchange_opened()
signal action_changed(text: String)                 # "Chopping ash tree..." or ""
signal projectile(from: Object, to: Object, sprite: String)   # 0.3.3 arrow in flight (data/combat.json ranged)
signal quests_changed()   # 0.3.7
signal quest_dialog(giver_id: String)   # 0.3.7.1 open the NPC dialog
signal hitsplat(target: Object, world_tile: Vector2i, amount: int)
signal splat(target: Object, world_tile: Vector2i, amount: int, kind: String)   # restyle: "heal" (green) / "poison" (purple)   # target: Actor / Enemy / WorldObject
signal shop_opened(shop: String)
signal player_shop_opened(town: String, slot: int)   # 0.3.0 (slot -1 = counter: buy / manage)
signal town_changed(town: String)
signal map_requested()
signal station_opened(station: String, pos: Vector2i)
signal report_ready(title: String, body: String)
signal player_hp_changed(hp: int, max_hp: int)
signal region_entered(region_id: String)   # 0.3.10 lore region (data/regions.json)
signal zone_entered(zone_id: String, warning: String)   # 0.3.1 PK zone (data/pk_zones.json)
signal zone_left(zone_id: String)


func say(text: String, kind: String = "game") -> void:
	message.emit(text, kind)
