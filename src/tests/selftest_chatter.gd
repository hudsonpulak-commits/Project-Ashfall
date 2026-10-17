extends RefCounted
## 0.3.3 AI chatter / idle behaviour checks. Returns [[ok, label], ...].

static func run(main, world, p) -> Array:
	var out: Array = []
	var L: Dictionary = GameData.ai_chatter.get("lines", {})
	var cats_ok := true
	for k in ["gather", "craft", "fight", "bank", "trading", "idle", "low_hp", "levelup", "death", "greet", "player_kill", "market_up", "market_down", "reply"]:
		cats_ok = cats_ok and L.has(k) and L[k].get("any", []).size() >= 3
	out.append([cats_ok, "chatter: every category has >= 3 generic lines"])
	p.place_at(world.gen.town_spawn("fenhollow") + Vector2i(0, 1))
	p.set_town("fenhollow")
	world.set_focus(p.tile, true)
	AIDirector._update_tiers(p.tile)
	var max_seen := 0
	var said0 := AIChatter.said_total
	var offscreen_spoke := false
	for i in 600:
		Tick.step()
		max_seen = maxi(max_seen, AIChatter.bubbles_shown(Market.tick))
	for a in AIDirector.records:
		if a.tier != 0 and int(a.chat.get("greet_next", 0)) > Market.tick + 1000:
			offscreen_spoke = true
	out.append([AIChatter.said_total > said0, "chatter: on-screen AIs talk in town (%d lines in 600 ticks)" % (AIChatter.said_total - said0)])
	out.append([max_seen <= int(AIChatter.c("max_on_screen", 3)), "chatter: never more than %d bubbles on screen (max %d)" % [int(AIChatter.c("max_on_screen", 3)), max_seen]])
	out.append([not offscreen_spoke, "chatter: off-screen agents hold no chat state"])
	var v = null
	for x in AIDirector.agents:
		if is_instance_valid(x) and not x.dead:
			v = x
			break
	out.append([v != null, "chatter: an AI is on screen in Fenhollow"])
	if v == null:
		return out
	# rate limit: a second normal line inside the cooldown is refused
	v.agent.chat.clear()
	v.bubble_until = -1
	for x in AIDirector.agents:
		if is_instance_valid(x):
			x.bubble_until = -1
	var t := Market.tick
	var first := AIChatter.say(v.agent, "idle", t)
	var second := AIChatter.say(v.agent, "idle", t + 1)
	out.append([first and not second and v.bubble_text() != "", "chatter: per-agent cooldown holds a second line"])
	# off-screen agents can't speak
	var far: AIAgent = null
	for a in AIDirector.records:
		if a.tier != 0:
			far = a
			break
	out.append([far == null or not AIChatter.say(far, "idle", t, true), "chatter: off-screen agents never speak"])
	# templating
	var s := AIChatter.line(v.agent, "levelup", {"skill": "Forestry", "level": 7})
	out.append([not s.contains("{") and (s.contains("7") or s.contains("Forestry")), "chatter: level-up line filled (%s)" % s])
	# greeting when the player walks up
	for x in AIDirector.agents:
		if is_instance_valid(x):
			x.bubble_until = -1
	var g0 := int(AIChatter.by_cat.get("greet", 0)) + int(AIChatter.by_cat.get("greet_strong", 0))
	for tries in 12:
		v.agent.chat.clear()
		for x in AIDirector.agents:
			if is_instance_valid(x):
				x.bubble_until = -1
		AIChatter.tick(10 * (Market.tick / 10 + 1 + tries) , v.tile + Vector2i(1, 0))
		if int(AIChatter.by_cat.get("greet", 0)) + int(AIChatter.by_cat.get("greet_strong", 0)) > g0:
			break
	out.append([int(AIChatter.by_cat.get("greet", 0)) + int(AIChatter.by_cat.get("greet_strong", 0)) > g0, "chatter: AI greets the player who walks up"])
	# reaction to the player killing something nearby
	for x in AIDirector.agents:
		if is_instance_valid(x):
			x.bubble_until = -1
			x.agent.chat.clear()
	var k0 := int(AIChatter.by_cat.get("player_kill", 0))
	AIChatter.on_player_kill(v.tile + Vector2i(2, 0), "Rat", Market.tick)
	out.append([int(AIChatter.by_cat.get("player_kill", 0)) > k0, "chatter: nearby AI reacts to the player's kill"])
	# idle behaviours
	var sat: bool = v._idle_think(Market.tick, world, {"type": "idle", "mode": "sit"})
	out.append([sat and v.think_cooldown >= 20, "idle: AI sits for a while"])
	var ab := AIAgent.new()
	ab.persona = GameData.personas[0]
	var picked_idle := false
	for i in 40:
		if AIBrain.choose(ab, Market.tick).get("type", "") == "idle":
			picked_idle = true
	out.append([not picked_idle, "idle: abstract agents never roll idle (economy unchanged)"])
	return out
