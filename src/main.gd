extends Node2D
## Game root. Wires World, Player, AI players, Market, HUD and the Tick, and
## owns save/load. Simulation order each tick (deterministic):
##   world respawns -> player -> AI players -> market -> streaming/autosave
##
## Command-line (after `--`):  --fresh  --save-path=user://x.json
##   --selftest                 run headless tests, exit code = failures
##   --screenshot=/abs/out.png  [--ticks=N] [--panel=pack|skills|bank|menu|exchange|store|craft|report] [--zoom=N]
##   --away=SECONDS             pretend the save is this old (offline catch-up test)
##   --qa=walk|combat|shop|pshop|smithy [--qa-out=/abs/dir]  QA bot scenario (tools/qa_bot)
##   --soak=DAYS [--soak-out=/abs/dir] [--pshop=MULT]  (MULT: simulated player shops priced at ref x MULT)  headless economy soak test (CSV + JSON;
##        0.3.1: + adventurer progression, raider kills, PK coin flows, Scorch resets, AI level spread, gear-tier supply/prices: soak.json "adventurers")

const DEFAULT_SEED := 7331
const AUTOSAVE_TICKS := 50          # 30 s
const OFFLINE_CAP_SECONDS := 8 * 3600
const ZOOMS := [1, 2, 3, 4]         # integer zooms only: pixel-perfect
const BASE_VIEW := Vector2(360, 640) # minimum logical view (portrait)

const MENU_SCENE := "res://scenes/main_menu.tscn"
const OFFLINE_BUDGET_MS := 6000     # 0.3.2: wall-clock cap for the offline catch-up on the loading screen
const OFFLINE_CHUNK := 600          # ticks per loading-screen frame

static var force_fresh := false

var loading: LoadingScreen
var play_seconds := 0.0

var world: World
var player: Player
var camera: Camera2D
var hud: HUD
var fx_layer: Node2D
var hit_bubbles: HitBubbles
var tap_marker: Sprite2D
var zoom_index := 1
var args: Dictionary = {}


func _ready() -> void:
	args = _parse_args()
	_apply_pixel_scale()
	get_tree().root.size_changed.connect(_apply_pixel_scale)
	get_tree().quit_on_go_back = false   # 0.3.2: Android back is handled (_notification)
	if args.has("save-path"):
		SaveSystem.path_override = str(args["save-path"])
	if is_interactive():
		_boot_interactive()
		return
	var data: Dictionary = {}
	if not (args.has("fresh") or args.has("selftest") or force_fresh):
		data = SaveSystem.load_game()
	force_fresh = false
	_start(data)
	if args.has("selftest"):
		var SelfTest = load("res://src/tests/selftest.gd")
		var failures: int = await SelfTest.run(self)
		get_tree().quit(failures)
	elif args.has("screenshot"):
		_screenshot_mode()
	elif args.has("qa"):
		var scr: GDScript = load("res://tools/qa_bot/qa_driver.gd")   # tools/ is not exported
		if scr == null or not scr.can_instantiate():
			printerr("QA driver failed to load")
			get_tree().quit(2)
			return
		var drv: Node = scr.new()
		drv.set("main", self)
		add_child(drv)
	elif args.has("soak"):
		var Soak = load("res://src/tests/soak.gd")
		var failures: int = Soak.run(self, int(args["soak"]), str(args.get("soak-out", "user://soak")), not args.has("no-traders"), float(args.get("pshop", -1.0)))
		get_tree().quit(failures)


## 0.3.2: a player launch (from the main menu, or a device start). Test and
## tool modes keep the synchronous start above.
func is_interactive() -> bool:
	for k in ["selftest", "screenshot", "qa", "soak", "fresh", "save-path"]:
		if args.has(k):
			return false
	return true


## 0.3.2 boot: the loading screen renders FIRST, then the save is read and
## migrated (validated; a bad save goes back to the menu with a message), the
## world is built in stages and the offline catch-up runs in frame-sized chunks
## under a wall-clock budget. 0.3.1 did all of this inside _ready before the
## first frame: with an hours-old save the phone sat on the boot colour for
## minutes (offline catch-up up to 48 000 ticks on the main thread).
func _boot_interactive() -> void:
	force_fresh = false
	var req: Dictionary = SaveSystem.launch.duplicate()
	SaveSystem.launch = {}
	var slot := int(req.get("slot", SaveSystem.current_slot))
	var mode := str(req.get("mode", "continue"))
	SaveSystem.current_slot = slot
	Tick.running = false
	loading = LoadingScreen.new()
	add_child(loading)
	loading.set_progress(0.02, "Starting...")
	SaveSystem.boot_log("BOOT loading screen (slot %d, %s)" % [slot, mode])
	await _frames(2)
	SaveSystem.boot_begin(slot, mode)
	var data: Dictionary = {}
	if mode != "new":
		loading.set_progress(0.08, "Reading save...")
		await _frames(1)
		var r := SaveSystem.load_checked()
		if not bool(r.get("ok", false)):
			SaveSystem.boot_done()
			_back_to_menu_with_error("Slot %d could not be loaded (%s). The save was set aside as %s and the slot is free again." % [slot, str(r.get("error", "?")), str(r.get("backup", "")).get_file()])
			return
		data = r.get("data", {})
	var t0 := Time.get_ticks_msec()
	loading.set_progress(0.15, "Shaping the land...")
	await _frames(1)
	_start_world(data)
	loading.set_progress(0.45, "Raising the towns...")
	await _frames(1)
	_start_player(data)
	if mode == "new" and str(req.get("name", "")).strip_edges() != "":
		player.char_name = str(req["name"]).strip_edges().substr(0, 16)
	loading.set_progress(0.6, "Waking the townsfolk...")
	await _frames(1)
	_start_ai(data)
	loading.set_progress(0.75, "Opening the gates...")
	await _frames(1)
	_start_view()
	SaveSystem.boot_log("BOOT world ready in %d ms" % (Time.get_ticks_msec() - t0))
	if data.has("saved_unix"):
		var away := int(Time.get_unix_time_from_system()) - int(data.get("saved_unix", Time.get_unix_time_from_system()))
		if args.has("away"):
			away = int(args["away"])
		await _catch_up_async(clampi(away, 0, OFFLINE_CAP_SECONDS))
	else:
		_welcome_new()
	loading.set_progress(1.0, "Ready")
	await _frames(1)
	loading.queue_free()
	loading = null
	Tick.running = true
	await _frames(3)
	SaveSystem.boot_done()
	SaveSystem.boot_log("BOOT gameplay (slot %d) after %d ms" % [slot, Time.get_ticks_msec()])
	if mode == "new":
		save_game()   # the slot exists from the first second


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _back_to_menu_with_error(msg: String) -> void:
	SaveSystem.last_error = msg
	push_warning(msg)
	SaveSystem.boot_log("BOOT load failed: %s" % msg)
	Tick.running = false
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


## In-game Menu -> Main menu (saves first).
func to_main_menu() -> void:
	if player:
		save_game()
	Tick.running = false
	AIDirector.clear()
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _start(data: Dictionary) -> void:
	_start_world(data)
	_start_player(data)
	_start_ai(data)
	_start_view()
	if data.has("saved_unix") or args.has("away"):
		var away := int(Time.get_unix_time_from_system()) - int(data.get("saved_unix", Time.get_unix_time_from_system()))
		if args.has("away"):
			away = int(args["away"])
		_catch_up(clampi(away, 0, OFFLINE_CAP_SECONDS))
	else:
		_welcome_new()


func _welcome_new() -> void:
	Events.say("Welcome to Ashfen. Tap the ground to walk.")
	Events.say("Tap a tree, rock or pool to gather; bank at the chest.")


func _start_world(data: Dictionary) -> void:
	var wdata: Dictionary = data.get("world", {})
	var world_seed := int(wdata.get("seed", DEFAULT_SEED))
	Tick.tick_count = int(data.get("tick", 0))
	Market.reset_prices()
	Market.from_save(data.get("market", {}))

	world = World.new()
	world.name = "World"
	add_child(world)
	world.setup(world_seed)
	world.tick = Tick.tick_count



func _start_player(data: Dictionary) -> void:
	var wdata: Dictionary = data.get("world", {})
	player = Player.new()
	player.name = "Player"
	if data.has("player"):
		player.from_save(data["player"])
	else:
		player.place_at(world.gen.town_spawn())
		player.give_starter_kit()
		player.hp = player.max_hp()   # a new character starts at full HP (was the old 11 default)
	world.entity_layer.add_child(player)
	if bool(data.get("relayout_cities", false)):
		apply_city_relayout(world, player)
	relocate_if_walled(world, player)
	world.buildings_view.player = player
	world.buildings_view.refresh_all()
	DayNight.setup_world(world)
	DayNight.from_save(data.get("daynight", {}))
	DayNight.ensure_lights(world)
	world.set_focus(player.tile, true)
	world.from_save(wdata, Tick.tick_count)
	if bool(data.get("relayout_cities", false)):
		relocate_piles_if_walled(world)
	if data.has("player"):
		for tid in Market.player_shops.keys():
			var ps: PlayerShop = Market.player_shops[tid]
			if ps.owned and int(ps.unseen["qty"]) > 0:
				var u := ps.take_unseen()
				Events.say("Your %s shop sold %d item%s for %d marks while you were away (till: %d)." % [Market.town(tid).town_name, int(u["qty"]), "" if int(u["qty"]) == 1 else "s", int(u["coins"]), ps.till])
	world.enemies.spawn_all(world.entity_layer, world)


	play_seconds = float(data.get("meta", {}).get("play_seconds", 0)) if typeof(data.get("meta")) == TYPE_DICTIONARY else 0.0


func _start_ai(data: Dictionary) -> void:
	var world_seed := int(data.get("world", {}).get("seed", DEFAULT_SEED))
	AIDirector.clear()
	AIDirector.setup(world_seed ^ int(args.get("ai-seed", 0)))   # --ai-seed=N: soak variance runs (AI only; world unchanged)
	AIDirector.attach(world.entity_layer, world)
	AIDirector.spawn_population()
	AIDirector.from_save(data.get("ai", {}))
	Market.monitor.money_supply_provider = money_supply



func _start_view() -> void:
	fx_layer = Node2D.new()
	fx_layer.z_index = 50
	add_child(fx_layer)
	tap_marker = Sprite2D.new()
	tap_marker.texture = GameData.texture("ui", "tap_marker")
	tap_marker.visible = false
	fx_layer.add_child(tap_marker)
	hit_bubbles = HitBubbles.new()
	fx_layer.add_child(hit_bubbles)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_set_zoom(int(args.get("zoom", 2)))

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	hud = HUD.new()
	ui.add_child(hud)
	hud.setup(player, world)
	hud.minimap.others = AIDirector.agents
	hud.request_save.connect(func():
		save_game()
		Events.say("Game saved."))
	hud.request_reset.connect(_reset)
	hud.request_main_menu.connect(to_main_menu)
	hud.zoom_step.connect(func(d): _set_zoom(ZOOMS[clampi(zoom_index + d, 0, ZOOMS.size() - 1)]))
	hud.minimap_tapped.connect(func(t): player.handle_tap(world, t))

	Events.hitsplat.connect(_spawn_hitsplat)
	if not Tick.ticked.is_connected(_on_tick):
		Tick.ticked.connect(_on_tick)


## Pixel-perfect scaling: pick the largest INTEGER factor that keeps at least
## a 360x640 logical view, then let the view grow to fill the rest of the
## screen (no letterbox bars, no fractional pixels). 1080x2400 -> x3 (360x800).
func _apply_pixel_scale() -> void:
	var win := Vector2(get_tree().root.size)
	if win.x <= 0 or win.y <= 0:
		return
	var k := maxi(1, floori(minf(win.x / BASE_VIEW.x, win.y / BASE_VIEW.y)))
	get_tree().root.content_scale_factor = k


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			out[s.substr(0, i)] = s.substr(i + 1)
		else:
			out[s] = true
	return out


## Player coins (pack + bank) + AI coins + coins held by the Exchange.
func money_supply() -> int:
	var n := 0
	if player:
		n += player.inventory.count(GameData.currency) + player.vault_coins()
	return n + AIDirector.money_supply() + Market.coins_in_market()


## Offline catch-up: fast-forward the world for the time away (capped at 8 h)
## and show a "While you were away" report. (Tests / tools: one call.)
func _catch_up(away_seconds: int) -> void:
	var ticks := int(away_seconds / Tick.TICK_SECONDS)
	if ticks < 100:
		Events.say("Welcome back to Fenhollow.")
		return
	var snap := _catch_up_snapshot()
	var t0 := Time.get_ticks_msec()
	var rep := AIDirector.simulate_offline(ticks, Tick.tick_count, player.actor_id)
	Tick.tick_count = int(rep["end_tick"])
	world.tick = Tick.tick_count
	_catch_up_report(away_seconds, rep, snap, t0, ticks)


## 0.3.2 player boot: the same catch-up in loading-screen chunks, under a
## wall-clock budget (OFFLINE_BUDGET_MS). Whatever is left when the budget
## runs out is skipped (the clock still jumps to now), so a slow phone never
## sits for minutes; the report says how much was simulated.
func _catch_up_async(away_seconds: int) -> void:
	var ticks := int(away_seconds / Tick.TICK_SECONDS)
	if ticks < 100:
		Events.say("Welcome back to Fenhollow.")
		return
	var snap := _catch_up_snapshot()
	var t0 := Time.get_ticks_msec()
	var done := 0
	var total := {"ticks": 0, "end_tick": Tick.tick_count, "days": 0, "player": {"bought": {}, "sold": {}, "coins": 0}}
	var budget := int(args.get("catchup-budget-ms", OFFLINE_BUDGET_MS))
	while done < ticks:
		var n := mini(OFFLINE_CHUNK, ticks - done)
		var rep := AIDirector.simulate_offline(n, Tick.tick_count, player.actor_id)
		Tick.tick_count = int(rep["end_tick"])
		done += n
		total["days"] = int(total["days"]) + int(rep["days"])
		for k in ["bought", "sold"]:
			for item in rep["player"][k].keys():
				total["player"][k][item] = int(total["player"][k].get(item, 0)) + int(rep["player"][k][item])
		total["player"]["coins"] = int(total["player"]["coins"]) + int(rep["player"]["coins"])
		if loading:
			loading.set_progress(0.8 + 0.18 * float(done) / ticks, "While you were away... %d%%" % int(100.0 * done / ticks))
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > budget:
			break
	var skipped := ticks - done
	Tick.tick_count += skipped
	world.tick = Tick.tick_count
	total["ticks"] = done
	total["end_tick"] = Tick.tick_count
	if skipped > 0:
		SaveSystem.boot_log("OFFLINE catch-up budget: simulated %d of %d ticks, skipped %d" % [done, ticks, skipped])
	_catch_up_report(away_seconds, total, snap, t0, done)
	if skipped > 0:
		Events.say("The world caught up on %d%% of your time away (the rest passed quietly)." % int(100.0 * done / ticks))


func _catch_up_snapshot() -> Dictionary:
	var before := {}
	var tm := Market.town(player.current_town)
	for id in EconomyMonitor.BASKET:
		before[id] = tm.reference_price(id)
	return {"before": before, "trips": AIDirector.trip_log.size(), "notices": Market.notices.size(), "coins": AIDirector.money_supply()}


func _catch_up_report(away_seconds: int, rep: Dictionary, snap: Dictionary, t0: int, ticks: int) -> void:
	var tm := Market.town(player.current_town)
	var before: Dictionary = snap["before"]
	var trips_before := int(snap["trips"])
	var notices_before := int(snap["notices"])
	var coins_before := int(snap["coins"])
	var lines := []
	lines.append("You were away %dh %02dm (%d game days)." % [int(away_seconds / 3600.0), int(away_seconds / 60.0) % 60, int(rep["days"])])
	lines.append("Prices in %s:" % tm.town_name)
	var mine: Dictionary = rep["player"]
	for k in mine["sold"].keys():
		lines.append("Sold %d %s on the Exchange." % [int(mine["sold"][k]), GameData.item_name(k).to_lower()])
	for k in mine["bought"].keys():
		lines.append("Bought %d %s on the Exchange." % [int(mine["bought"][k]), GameData.item_name(k).to_lower()])
	if not mine["sold"].is_empty() or not mine["bought"].is_empty():
		lines.append("Collect at the Exchange board.")
	var movers := []
	for id in before.keys():
		var now_p := tm.reference_price(id)
		if now_p != int(before[id]):
			movers.append([absf(float(now_p) / before[id] - 1.0), id, int(before[id]), now_p])
	movers.sort_custom(func(a, b): return a[0] > b[0])
	for m in movers.slice(0, 4):
		lines.append("%s: %d -> %d" % [GameData.item_name(m[1]), m[2], m[3]])
	if movers.is_empty():
		lines.append("Prices held steady.")
	for i in range(notices_before, Market.notices.size()):
		lines.append(str(Market.notices[i]["text"]))
	lines.append("Travelling traders set out on %d trips." % maxi(0, AIDirector.trip_log.size() - trips_before))
	lines.append("Townsfolk coin: %d -> %d." % [coins_before, AIDirector.money_supply()])
	SaveSystem.boot_log("OFFLINE catch-up: %d ticks in %d ms" % [ticks, Time.get_ticks_msec() - t0])
	Events.report_ready.emit("While you were away", "\n".join(lines))


# -------------------------------------------------------------------- tick --
func _on_tick(t: int) -> void:
	play_seconds += Tick.TICK_SECONDS
	world.on_tick(t)
	player.on_tick(t, world)
	AIDirector.on_tick(t, world, player.tile)
	world.enemies.on_tick(t, [player] + AIDirector.agents, player.tile)
	world.ground.on_tick(t)
	Market.on_tick(t)
	world.set_focus(player.tile)
	if t % AUTOSAVE_TICKS == 0 and not (args.has("selftest") or args.has("screenshot") or args.has("soak") or args.has("qa")):
		save_game()


func _process(_dt: float) -> void:
	if camera and player:
		# 0.3.0 blur fix: main runs BEFORE its child actors each frame, so the camera
		# used last frame's player position: the avatar jittered 1 world px (3 screen
		# px) back and forth against the camera while walking. Place the sprite for
		# THIS frame first, then the camera from the same rounded value.
		player._update_visual_position()
		camera.position = (player.position - Vector2(0, GameData.tile_size / 2.0)).round()


# ------------------------------------------------------------------- input --
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			# the event's own position (not the OS cursor): exact for touch-emulated
			# clicks and for injected input (QA bot), same result for a real mouse
			var t := world.pos_to_tile(world.make_canvas_position_local(ev.position))
			_show_marker(t)
			player.handle_tap(world, t)
			get_viewport().set_input_as_handled()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(ZOOMS[clampi(zoom_index + 1, 0, ZOOMS.size() - 1)])
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(ZOOMS[clampi(zoom_index - 1, 0, ZOOMS.size() - 1)])
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var dirs := {KEY_W: Vector2i.UP, KEY_UP: Vector2i.UP, KEY_S: Vector2i.DOWN, KEY_DOWN: Vector2i.DOWN,
			KEY_A: Vector2i.LEFT, KEY_LEFT: Vector2i.LEFT, KEY_D: Vector2i.RIGHT, KEY_RIGHT: Vector2i.RIGHT}
		if dirs.has(ev.keycode):
			player.step_dir(world, dirs[ev.keycode])
		elif ev.keycode == KEY_I:
			hud.toggle_panel("pack")
		elif ev.keycode == KEY_K:
			hud.toggle_panel("skills")


func _set_zoom(z: int) -> void:
	zoom_index = maxi(0, ZOOMS.find(z))
	var zz: int = ZOOMS[zoom_index]
	camera.zoom = Vector2(zz, zz)


func _show_marker(t: Vector2i) -> void:
	tap_marker.position = world.tile_to_pos(t) + Vector2.ONE * GameData.tile_size / 2.0
	tap_marker.visible = true
	tap_marker.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(tap_marker, "modulate:a", 0.0, 0.6).set_delay(0.3)


func _spawn_hitsplat(target, t: Vector2i, amount: int) -> void:
	hit_bubbles.show_hit(target, t, amount)


# -------------------------------------------------------------------- save --
func build_save() -> Dictionary:
	return {
		"tick": Tick.tick_count,
		"world": world.to_save(),
		"player": player.to_save(),
		"ai": AIDirector.to_save(),
		"market": Market.to_save(),
		"daynight": DayNight.to_save(),
		"meta": {"name": player.char_name, "total": player.skills.total_level(), "combat": Combat.combat_level(player.skills),
			"play_seconds": int(play_seconds), "game_version": str(ProjectSettings.get_setting("application/config/version", ""))},
	}


func save_game() -> bool:
	return SaveSystem.save_game(build_save())


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if player and hud and loading == null and is_interactive():
			save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_interactive() and loading == null:
		# 0.3.2 Android back: close the open panel, else save and go to the main menu
		if hud and hud.current_panel != "":
			hud.show_panel("")
		else:
			to_main_menu()


func _reset() -> void:
	SaveSystem.delete_save()
	AIDirector.clear()
	Tick.tick_count = 0
	force_fresh = true
	SaveSystem.launch = {"mode": "new", "slot": SaveSystem.current_slot, "name": player.char_name if player else ""}
	get_tree().reload_current_scene()


# -------------------------------------------------------------- screenshot --
func _screenshot_mode() -> void:
	Tick.running = false
	if args.has("town"):
		var tid := str(args["town"])
		player.place_at(world.gen.town_spawn(tid) + Vector2i(0, 1))
		player.set_town(tid)
		world.set_focus(player.tile, true)
	if args.has("stand_shop"):
		var b: Dictionary = world.gen.building_for_shop(player.current_town, str(args["stand_shop"]))
		if not b.is_empty():
			player.place_at(b["stand"])
			world.set_focus(player.tile, true)
	var ticks := int(args.get("ticks", 0))
	for i in ticks:
		Tick.step()
	if args.has("fight"):
		# combat shot: walk into a goblin camp with some gear and start swinging
		var g: Enemy = world.enemies.nearest(Vector2i(48, 40), [str(args["fight"])], 300)
		for cs in Combat.COMBAT_SKILLS:
			player.skills.set_level(cs, int(args.get("melee", 6)))
		player.skills.set_level("vitality", 12)
		player.equipment = {"weapon": "bronze_sword", "head": "bronze_cap", "body": "bronze_scale_vest", "shield": "alder_buckler"}
		player.hp = player.max_hp()
		player.inventory.add("cooked_rat_meat", 3)
		player.place_at(world.find_free_tile_near(g.tile + Vector2i(-1, 0), 1))
		world.set_focus(player.tile, true)
		if args.has("pray"):
			player.skills.set_level("prayer", 8)
			player.prayer = {"id": "", "points": Prayer.max_points(8)}
			Prayer.activate(player.prayer, str(args["pray"]), 8)
		player.attack(g)
		var g2: Enemy = null
		var rival: AIPlayer = null
		if args.has("contest"):
			# an AI adventurer takes on a second goblin of the same camp
			g2 = world.enemies.nearest(g.tile, [g.kind], 8, func(e): return e != g)
			for a in AIDirector.records:
				if a.persona_id() == "adventurer" and g2 != null:
					a.pos = g2.tile + Vector2i(1, 1)
					if a.tier != 0:
						AIDirector._promote(a)
					rival = a.view
					rival.place_at(world.find_free_tile_near(g2.tile + Vector2i(1, 0), 1))
					for cs in Combat.COMBAT_SKILLS:
						rival.skills.set_level(cs, 8)
					rival.skills.set_level("vitality", 12)
					rival.hp = rival.max_hp()
					rival.think_cooldown = 1000
					rival.attack(g2)
					break
		for i in int(args.get("fight_ticks", 14)):
			Tick.step()
		if g2 != null and rival != null and not g2.dead:
			player.handle_tap(world, g2.tile)
	if args.has("chop"):
		var tree: WorldObject = world.find_nearest_object(player.tile, ["ash_tree"], 20)
		if tree:
			player.interact(world, tree)
			for i in 30:
				Tick.step()
	if args.has("gear"):
		# 0.2.4 equipment shot: a full same-tier armour set (+ weapon) and matching levels
		var m := str(args["gear"])
		var lv: int = int({"bronze": 1, "iron": 10, "steel": 20, "dusk": 30}.get(m, 1)) + 2
		for cs in Combat.COMBAT_SKILLS:
			player.skills.set_level(cs, lv)
		var pieces := {"bronze": ["bronze_cap", "bronze_scale_vest", "bronze_greaves", "alder_buckler"], "iron": ["iron_helm", "iron_hauberk", "iron_legguards", "iron_kite_shield"],
			"steel": ["steel_helm", "steel_brigandine", "steel_legplates", "steel_heater_shield"], "dusk": ["dusk_helm", "dusk_cuirass", "dusk_tassets", "dusk_tower_shield"]}
		for id in pieces.get(m, []) + ["%s_warhammer" % m]:
			player.inventory.add(id)
			player.equip_slot(player.inventory.find(id))
	if args.has("sprint"):
		# 0.2.4 HUD shot: sprint on, run a short way so energy is visibly draining
		player.set_sprint(true)
		player.walk_to(world, world.find_free_tile_near(player.tile + Vector2i(int(args.get("sprint_dx", 14)), 6), 3))
		for i in int(args.get("sprint_ticks", 10)):
			Tick.step()
	if args.has("panel"):
		var c: Vector2i = world.gen.town_spawn(player.current_town) - Vector2i(0, 0)
		match str(args["panel"]):
			"bank":
				var ch: WorldObject = world.find_nearest_object(c, ["bank_chest"], 14)
				player.place_at(ch.pos + Vector2i(0, 1))
				hud.show_panel("bank")
			"exchange":
				var eb: WorldObject = world.find_nearest_object(c, ["exchange_board"], 14)
				player.place_at(eb.pos + Vector2i(0, 1))
				hud.exchange_panel.view = str(args.get("view", "market"))
				hud._open_at("exchange")
				hud.exchange_panel.select(str(args.get("item", "iron_ore")))
			"store", "specialist":
				var shop := "general"
				if args["panel"] == "specialist":
					shop = str(args.get("shop", Market.town(player.current_town).specialists[0]))
				player.place_at(world.gen.building_for_shop(player.current_town, shop)["stand"])
				hud.store_panel.shop = shop
				hud._open_at("store")
			"craft":
				var anvil: WorldObject = world.find_nearest_object(c, ["anvil"], 12)
				player.place_at(anvil.pos + Vector2i(0, 1))
				player.inventory.add("bronze_bar", 4)
				player.inventory.add("plank", 2)
				Events.station_opened.emit("anvil", anvil.pos)
			"furnace":
				# 0.2.3 smelting shot: bronze / iron (40 % fail) / steel at the furnace
				var fur: WorldObject = world.find_nearest_object(c, ["furnace"], 30)
				player.place_at(world.find_free_tile_near(fur.pos + Vector2i(0, 1), 2))
				player.skills.set_level("smithing", 20)
				for id in ["copper_ore", "tin_ore", "iron_ore", "coal"]:
					player.inventory.add(id, 5)
				Events.station_opened.emit("furnace", fur.pos)
			_:
				hud.show_panel(str(args["panel"]))
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if args.has("strip"):
		await _walk_strip()
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(str(args["screenshot"]))
	print("SCREENSHOT %s %s %dx%d" % [args["screenshot"], "OK" if err == OK else "ERR %d" % err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)


## 0.2.5: --strip=N captures N consecutive frames (3 per tick, mid-tick
## interpolation included) of the player walking a real A* path diagonally,
## cropped around the avatar and laid side by side; prints the facing per frame.
func _walk_strip() -> void:
	var n := int(args.get("strip", 18))
	var dest: Vector2i = world.find_free_tile_near(player.tile + Vector2i(int(args.get("strip_dx", 13)), int(args.get("strip_dy", 9))), 3)
	player.walk_to(world, dest)
	if args.has("strip_zig"):
		# forced zigzag (the worst case for 0.2.4's per-step facing)
		player.path.clear()
		var o := player.tile
		for z in [[1, 1], [0, 2], [1, 3], [0, 4], [1, 5], [2, 6], [1, 7], [2, 8], [3, 9], [2, 10]]:
			player.path.append(o + Vector2i(z[0], z[1]))
	var steps := []
	var prev := player.tile
	for q in player.path:
		steps.append(q.x - prev.x)
		prev = q
	var zm := get_viewport().get_canvas_transform().get_scale().x
	var cw := int(22 * zm)
	var ch := int(32 * zm)
	var sc := maxi(1, int(round(6.0 / zm)))
	var strip := Image.create(n * cw * sc + (n - 1) * 2, ch * sc, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#17140e"))
	var faces := ""
	for i in n:
		var sub := i % 3
		if sub == 0 and i > 0:
			Tick.step()
		Tick._acc = Tick.TICK_SECONDS * sub / 3.0
		for k in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		var sp: Vector2 = get_viewport().get_canvas_transform() * player.global_position
		var r := Rect2i(int(sp.x) - cw / 2, int(sp.y - 28 * zm), cw, ch)
		r = r.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
		var crop := shot.get_region(r)
		crop.resize(crop.get_width() * sc, crop.get_height() * sc, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(i * (cw * sc + 2), 0))
		faces += "L" if player.facing.left else "R"
	var err := strip.save_png(str(args["screenshot"]))
	print("STRIP path step dx: %s" % str(steps))
	print("STRIP facing per frame: %s (flips %d)" % [faces, player.facing.flips])
	print("SCREENSHOT %s %s %dx%d" % [args["screenshot"], "OK" if err == OK else "ERR %d" % err, strip.get_width(), strip.get_height()])
	get_tree().quit(0 if err == OK else 1)


## 0.3.0: an old save may stand the player where a wall, counter or prop now is.
## 0.3.1: also water where a road used to run (roads now go round lakes) and
## the new mine rocks; far from any land (a long-gone road across a lake) ->
## the nearest walkable tile further out, else the town spawn.
## Save v7 (walled cities): a player saved inside a city is put on that city's
## square (the old streets are gone); outside the cities nothing moves.
static func apply_city_relayout(w, a) -> bool:
	var tid: String = w.gen.town_at(a.tile, 1)
	if tid == "" or not w.gen.towns.has(tid):
		return false
	a.place_at(w.gen.town_spawn(tid))
	if a.has_method("set_town"):
		a.set_town(tid)
	return true


## Save v7: ground piles that now sit on a city wall/building wall move to the
## nearest free tile so nothing is lost inside the new walls.
static func relocate_piles_if_walled(w) -> int:
	var moved := 0
	for pile in w.ground.piles:
		var q: Vector2i = pile["pos"]
		if w.is_blocked(q):
			pile["pos"] = w.find_free_tile_near(q, 16, true)
			moved += 1
	if moved > 0:
		w.ground.queue_redraw()
	return moved


static func relocate_if_walled(w, a) -> bool:
	if not w.is_blocked(a.tile):
		return false
	var q: Vector2i = w.find_free_tile_near(a.tile, 16, true)
	if w.is_blocked(q):
		q = w.find_free_tile_near(a.tile, 48, true)
	if w.is_blocked(q):
		q = w.gen.town_spawn()
	a.place_at(q)
	return true
