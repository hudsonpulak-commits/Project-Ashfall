class_name GroundItems
extends Node2D
## Items lying on tiles (kill drops, dropped items, death piles).
## Pile: {pos, id, qty, until, owner, public_at, claim, claim_until}
##  - owner "" = anyone. Otherwise only the owner sees / takes it until
##    public_at; public_at == -1 means never public (death piles).
##  - Rules (private window, TTLs, AI looting) live in data/drops.json "ground".
## Public piles get looted by nearby AI players (see AIPlayer / AIDirector).

const DROP_TTL := 500            # fallback; data/drops.json ground.drop_ttl
const DEATH_TTL := 3000          # fallback; data/drops.json ground.death_ttl

var piles: Array = []
var viewer := "player"
var now := 0                     # last tick seen (visibility of private piles)
var looted := {}                 # stats: "ai" / "abstract" -> items taken
var _dirty := true


static func rule(key: String, fallback: float) -> float:
	return float(GameData.ground_rules.get(key, fallback))


static func drop_ttl() -> int:
	return int(rule("drop_ttl", DROP_TTL))


static func death_ttl() -> int:
	return int(rule("death_ttl", DEATH_TTL))


static func private_ticks() -> int:
	return int(rule("private_ticks", 100))


func _ready() -> void:
	z_index = -5


## owner "" = public at once. private_for: ticks until it turns public
## (-1 = never: death piles; -2 = use the data default).
func add(pos: Vector2i, id: String, qty: int, t: int, ttl: int = -1, owner: String = "", private_for: int = -2) -> void:
	if qty <= 0:
		return
	now = maxi(now, t)
	if ttl < 0:
		ttl = drop_ttl()
	if private_for == -2:
		private_for = private_ticks()
	var pub := 0 if owner == "" else (-1 if private_for < 0 else t + private_for)
	for p in piles:
		if p["pos"] == pos and p["id"] == id and p["owner"] == owner and (int(p["public_at"]) < 0) == (pub < 0) and GameData.is_stackable(id):
			p["qty"] = int(p["qty"]) + qty
			p["until"] = maxi(int(p["until"]), t + ttl)
			if pub > 0:
				p["public_at"] = maxi(int(p["public_at"]), pub)
			queue_redraw()
			return
	piles.append({"pos": pos, "id": id, "qty": qty, "until": t + ttl, "owner": owner, "public_at": pub, "claim": "", "claim_until": 0})
	queue_redraw()


func is_public(p: Dictionary) -> bool:
	return p["owner"] == "" or (int(p["public_at"]) >= 0 and now >= int(p["public_at"]))


func visible_to(p: Dictionary, who: String) -> bool:
	return p["owner"] == who or is_public(p)


func at(pos: Vector2i, who: String = "player") -> Array:
	var out: Array = []
	for p in piles:
		if p["pos"] == pos and visible_to(p, who):
			out.append(p)
	return out


## Moves what fits from the tile into the actor's pack. Returns items moved.
func pick_up(actor: Actor, pos: Vector2i) -> int:
	var moved := 0
	for p in at(pos, actor.actor_id):
		var got := actor.inventory.add(p["id"], int(p["qty"]))
		p["qty"] = int(p["qty"]) - got
		moved += got
	piles = piles.filter(func(p): return int(p["qty"]) > 0)
	queue_redraw()
	return moved


## Worth of a pile to an AI (market value x qty; coins 1 each).
static func pile_value(agent: AIAgent, p: Dictionary) -> float:
	if p["id"] == GameData.currency:
		return float(p["qty"])
	return AIBrain.value(agent, p["id"]) * int(p["qty"])


## Public, unclaimed (or claimed by `who`) piles near `from` worth looting.
## Death piles are never public, so they never show up here.
func lootable_near(agent: AIAgent, from: Vector2i, radius: int, who: String) -> Array:
	var out: Array = []
	var min_v := rule("ai_loot_min_value", 3)
	for p in piles:
		# 0.3.1: an AI also loots piles private to itself (its PK kills)
		if not (is_public(p) or p["owner"] == who) or (p["claim"] != "" and p["claim"] != who and now < int(p["claim_until"])):
			continue
		var d: Vector2i = (p["pos"] - from).abs()
		if maxi(d.x, d.y) > radius:
			continue
		if pile_value(agent, p) >= min_v:
			out.append(p)
	return out


func claim(p: Dictionary, who: String, ticks: int = 40) -> void:
	p["claim"] = who
	p["claim_until"] = now + ticks


## An AI takes every public pile on the tile worth looting: coins to its
## purse, items to its stash. Returns the number of items taken.
func loot_to_agent(agent: AIAgent, pos: Vector2i, kind: String = "ai") -> int:
	var n := 0
	var min_v := rule("ai_loot_min_value", 3)
	for p in piles:
		if p["pos"] != pos or not (is_public(p) or p["owner"] == agent.id) or pile_value(agent, p) < min_v:
			continue
		if p["id"] == GameData.currency:
			agent.coins += int(p["qty"])
		else:
			agent.stash_add(p["id"], int(p["qty"]))
		n += int(p["qty"])
		p["qty"] = 0
	if n > 0:
		piles = piles.filter(func(p): return int(p["qty"]) > 0)
		looted[kind] = int(looted.get(kind, 0)) + n
		agent.stats["looted"] = int(agent.stats.get("looted", 0)) + n
		queue_redraw()
	return n


func on_tick(t: int) -> void:
	var was := now
	now = t
	if t % 10 != 0:
		return
	var n := piles.size()
	piles = piles.filter(func(p): return int(p["until"]) > t)
	var flipped := false
	for p in piles:
		var pa := int(p["public_at"])
		if pa > was - 10 and pa <= t:
			flipped = true
	if piles.size() != n or flipped:
		queue_redraw()


func _draw() -> void:
	var ts := float(GameData.tile_size)
	var seen := {}
	for p in piles:
		if not visible_to(p, viewer):
			continue
		var k: Vector2i = p["pos"]
		var n := int(seen.get(k, 0))
		seen[k] = n + 1
		if n > 2:
			continue
		var tex := GameData.texture("items", p["id"])
		if tex:
			var off := Vector2(2 + n * 2, 2 - n * 2)
			draw_texture_rect(tex, Rect2(Vector2(k) * ts + off, Vector2(12, 12)), false)


func to_save(t: int) -> Array:
	var out: Array = []
	for p in piles:
		var pa := int(p["public_at"])
		out.append({"pos": [p["pos"].x, p["pos"].y], "id": p["id"], "qty": p["qty"], "left": int(p["until"]) - t,
			"owner": p["owner"], "public_in": (pa - t) if pa > 0 else pa})
	return out


func from_save(arr: Array, t: int) -> void:
	piles.clear()
	now = t
	for d in arr:
		var owner := str(d.get("owner", ""))
		# old saves: owned piles were death piles (never public)
		var pin := int(d.get("public_in", 0 if owner == "" else -1))
		var pa := pin if pin <= 0 else t + pin
		if owner != "" and pin == 0:
			pa = t
		piles.append({"pos": Vector2i(int(d["pos"][0]), int(d["pos"][1])), "id": str(d["id"]), "qty": int(d["qty"]),
			"until": t + int(d.get("left", DROP_TTL)), "owner": owner, "public_at": pa, "claim": "", "claim_until": 0})
	queue_redraw()
