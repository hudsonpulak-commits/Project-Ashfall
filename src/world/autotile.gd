class_name Autotile
extends RefCounted
## 0.3.9 autotiling: fences, city walls, the moat border and floor transitions.
## Pieces: N=1 E=2 S=4 W=8 -> 0..15 (0 post/tower, 1/2/4/8 end caps, 5/10
## straights, 3/6/12/9 corners, 7/14/13/11 T-junctions, 15 4-way), plus 16 '/'
## and 17 '\' 45-degree diagonals (only when nothing joins orthogonally).
## Art: data/sprites.json "autotile" / "transitions" (swap the PNGs freely).

const N := 1
const E := 2
const S := 4
const W := 8
const DIAG_SLASH := 16      # '/'  NE <-> SW
const DIAG_BACK := 17       # '\'  NW <-> SE
const PIECES := 18
const DIRS4 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BROKEN_CHANCE := 0.15
const END_BROKEN_CHANCE := 0.3
## City wall top tiles -> their cap sheet (data/sprites.json autotile wall_<family>).
## 0.3.11 v3.1 walls drawn by town art (Highfen's dark 45-degree wall), no tile caps
const ART_WALLS := {"capital_wall": true}
const WALL_FAMILIES := {"stone_wall": "wall_stone_wall", "palisade": "wall_palisade", "basalt_wall": "wall_basalt_wall", "sandstone_wall": "wall_sandstone_wall", "capital_wall": "wall_capital_wall"}
const WALL_JOIN_ALSO := ["gate_wood", "gate_basalt", "gate_sand", "gate_capital"]

## Piece names for tests / QA.
static func piece_name(i: int) -> String:
	match i:
		0: return "post"
		1, 2, 4, 8: return "end"
		5, 10: return "straight_v" if i == 5 else "straight_h"
		3, 6, 12, 9: return "corner"
		7, 14, 13, 11: return "t"
		15: return "cross"
		DIAG_SLASH: return "diag_slash"
		DIAG_BACK: return "diag_back"
	return "?"


## Piece index from a connection test `joins(p) -> bool`.
static func piece_at(p: Vector2i, joins: Callable) -> int:
	var m := 0
	for k in 4:
		if joins.call(p + DIRS4[k]):
			m |= 1 << k
	if m != 0:
		return m
	return piece_from_diag(joins.call(p + Vector2i(1, -1)), joins.call(p + Vector2i(-1, -1)), joins.call(p + Vector2i(1, 1)), joins.call(p + Vector2i(-1, 1)))


static func piece_from_diag(ne: bool, nw: bool, se: bool, sw: bool) -> int:
	if ne or sw:
		return DIAG_SLASH
	if nw or se:
		return DIAG_BACK
	return 0


## Deterministic deterioration (rural fences only; city walls never break).
static func is_broken(p: Vector2i, chance: float = BROKEN_CHANCE) -> bool:
	return WorldGen.hash01_static(p.x, p.y, 97) < chance


static var _prio: Dictionary = {}

static func priority(tile_name: String) -> int:
	if _prio.is_empty():
		_prio = GameData.sprites.get("transitions", {}).get("_rules", {}).get("priority", {}).duplicate()
		_prio["_loaded"] = -1
	return int(_prio.get(tile_name, -1))


## Blend frame for overlaying floor `u` onto a tile whose 8 neighbours are
## `nb` (names, order N E S W NW NE SE SW). edges N1 E2 S4 W8, corners NW1 NE2 SE4 SW8 (<<4).
static func transition_frame(u: String, nb: Array) -> int:
	var e := 0
	for k in 4:
		if nb[k] == u:
			e |= 1 << k
	var c := 0
	# a corner only where neither side next to it already has the edge
	if nb[4] == u and not (e & (N | W)): c |= 1
	if nb[5] == u and not (e & (N | E)): c |= 2
	if nb[6] == u and not (e & (S | E)): c |= 4
	if nb[7] == u and not (e & (S | W)): c |= 8
	return e | (c << 4)


## Up to 2 higher-priority floors around a tile, highest last (drawn on top).
static func overlays_for(here: String, nb: Array) -> Array:
	var ph := priority(here)
	if ph < 0:
		return []
	var cands := {}
	for n in nb:
		var pn := priority(n)
		if pn > ph and n != here:
			cands[n] = pn
	var keys := cands.keys()
	keys.sort_custom(func(a, b): return cands[a] < cands[b] or (cands[a] == cands[b] and a < b))
	return keys.slice(maxi(0, keys.size() - 2))
