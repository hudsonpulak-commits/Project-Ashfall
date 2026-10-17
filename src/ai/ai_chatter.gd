class_name AIChatter
extends RefCounted
## 0.3.3 AI immersion: overhead chat lines and event reactions for AI players.
## Only detailed-tier (on-screen) agents ever speak, so off-screen agents cost
## nothing. Lines, cooldowns and caps live in data/ai_chatter.json.
## Per-agent runtime state lives in AIAgent.chat (not saved).

static var player_ref = null          # Player registers itself (greet / strong-gear checks)
static var _pending: Array = []       # replies: [{"agent", "at", "cat"}]
static var enabled := true           # QA bot sprite scenarios mute chatter
static var said_total := 0            # QA/test counter
static var by_cat: Dictionary = {}    # category -> count (QA)


static func cfg() -> Dictionary:
	return GameData.ai_chatter.get("cfg", {})


static func c(key: String, def):
	return cfg().get(key, def)


## Pick a line for `cat`, persona-flavoured part of the time. "" if none.
static func line(agent: AIAgent, cat: String, fill: Dictionary = {}) -> String:
	var block: Dictionary = GameData.ai_chatter.get("lines", {}).get(cat, {})
	var pool: Array = block.get("any", [])
	var own: Array = block.get(agent.persona_id(), [])
	if not own.is_empty() and (pool.is_empty() or agent.rng.randf() < float(c("persona_share", 0.6))):
		pool = own
	if pool.is_empty():
		return ""
	var s: String = str(pool[agent.rng.randi() % pool.size()])
	for k in fill.keys():
		s = s.replace("{" + k + "}", str(fill[k]))
	return s


static func bubbles_shown(now: int) -> int:
	var n := 0
	for v in AIDirector.agents:
		if is_instance_valid(v) and v.bubble_until > now:
			n += 1
	return n


## Try to show a bubble. `force` skips the cooldown (big events) but never the
## on-screen cap. Returns true if something was said.
static func say(agent: AIAgent, cat: String, now: int, force: bool = false, fill: Dictionary = {}) -> bool:
	if not enabled or agent == null or agent.tier != 0 or agent.view == null or not is_instance_valid(agent.view):
		return false
	if not force and now < int(agent.chat.get("next", 0)):
		return false
	if bubbles_shown(now) >= int(c("max_on_screen", 3)):
		return false
	var s := line(agent, cat, fill)
	if s == "":
		return false
	agent.view.show_bubble(s, now + int(c("bubble_ticks", 7)))
	agent.chat["next"] = now + agent.rng.randi_range(int(c("cooldown_min_ticks", 34)), int(c("cooldown_max_ticks", 66)))
	agent.chat["last_cat"] = cat
	said_total += 1
	by_cat[cat] = int(by_cat.get(cat, 0)) + 1
	if cat != "reply" and cat != "death":
		_queue_reply(agent, now)
	return true


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _queue_reply(speaker: AIAgent, now: int) -> void:
	if speaker.rng.randf() >= float(c("reply_chance", 0.35)):
		return
	var r := int(c("reply_radius", 6))
	for v in AIDirector.agents:
		if is_instance_valid(v) and v.agent != speaker and _cheb(v.tile, speaker.view.tile) <= r and now >= int(v.agent.chat.get("next", 0)):
			_pending.append({"agent": v.agent, "at": now + int(c("reply_delay_ticks", 3))})
			return


## Called by AIDirector every tick (cheap: early-outs unless it's a check tick).
static func tick(now: int, player_tile: Vector2i) -> void:
	if not enabled:
		return
	for i in range(_pending.size() - 1, -1, -1):
		var p: Dictionary = _pending[i]
		if now >= int(p["at"]):
			_pending.remove_at(i)
			say(p["agent"], "reply", now, true)
	if now % int(c("check_every_ticks", 5)) != 0:
		return
	var gr := int(c("greet_radius", 4))
	for v in AIDirector.agents:
		if not is_instance_valid(v) or v.dead:
			continue
		var a: AIAgent = v.agent
		var chatty := float(GameData.ai_chatter.get("chattiness", {}).get(a.persona_id(), 1.0))
		# greet the player when they walk up (own, longer cooldown)
		if _cheb(v.tile, player_tile) <= gr and now >= int(a.chat.get("greet_next", 0)):
			a.chat["greet_next"] = now + int(c("greet_cooldown_ticks", 500))
			if a.rng.randf() < float(c("greet_chance", 0.7)) * chatty:
				var cat := "greet"
				if player_ref != null and is_instance_valid(player_ref) and Combat.combat_level(player_ref.skills) >= AIBrain.combat_level(a) + 10:
					cat = "greet_strong"
				if say(a, cat, now, true):
					v.face_toward(player_tile)
					continue
		if now < int(a.chat.get("next", 0)) or a.rng.randf() >= float(c("ambient_chance", 0.06)) * chatty:
			continue
		if a.rng.randf() < float(c("market_chance", 0.3)) and _market_line(a, now):
			continue
		say(a, activity_cat(v), now)


## Which chatter category fits what this body is doing right now.
static func activity_cat(v) -> String:
	var a: AIAgent = v.agent
	if v.hp < v.max_hp() * float(c("low_hp_share", 0.4)):
		return "low_hp"
	if AIBrain.is_trader(a):
		return "trading"
	var t: String = str(a.activity.get("type", "rest"))
	match t:
		"gather", "craft", "fight":
			return t
		"idle":
			return str(a.activity.get("mode", "idle"))
		"raid":
			return "fight"
	return "idle"


## Comment on a big daily move in something this persona trades.
static func _market_line(a: AIAgent, now: int) -> bool:
	var m = Market.town(a.town)
	if m == null:
		return false
	var mv := float(c("market_move", 0.2))
	for item in a.persona.get("sells", []) + a.persona.get("buys", []):
		if not m.tradeable(item):
			continue
		var ch: float = m.day_change(item)
		if absf(ch) >= mv:
			return say(a, "market_up" if ch > 0 else "market_down", now, false, {"item": GameData.item_name(item)})
	return false


# ------------------------------------------------------------ event hooks --
static func on_level(agent: AIAgent, skill_id: String, lvl: int, now: int) -> void:
	say(agent, "levelup", now, true, {"skill": GameData.skill_by_id.get(skill_id, {}).get("name", skill_id), "level": lvl})


## The player killed something: the closest on-screen AI within range reacts.
static func on_player_kill(tile: Vector2i, enemy_label: String, now: int) -> void:
	var best = null
	var bd := int(c("react_radius", 8)) + 1
	for v in AIDirector.agents:
		if is_instance_valid(v) and not v.dead and _cheb(v.tile, tile) < bd:
			bd = _cheb(v.tile, tile)
			best = v
	if best != null and say(best.agent, "player_kill", now, false, {"enemy": enemy_label.to_lower()}):
		best.face_toward(tile)


static func clear() -> void:
	_pending.clear()
