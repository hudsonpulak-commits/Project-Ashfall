class_name Pathfinder
extends RefCounted
## Tile A* with 8-way movement (no corner cutting) and a node budget so a
## bad tap can never stall a frame. Works on any object exposing
## is_blocked(Vector2i) -> bool (the World), so AI players share it.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const DIAG := 1.4142


static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return (dx + dy) + (DIAG - 2.0) * mini(dx, dy)


## Path from start to any tile in `goals` (excluding start). Returns [] if none.
## `aim` is used for the heuristic (e.g. the object's tile when goals are its neighbours).
static func find_path(world, start: Vector2i, goals: Array, aim: Vector2i, max_nodes: int = 12000) -> Array:
	var _t := Time.get_ticks_usec()
	var r := _find_path(world, start, goals, aim, max_nodes)
	var ms := (Time.get_ticks_usec() - _t) / 1000.0
	if ms > 3.0 and "perf_log" in world:
		world.perf_log.append(["path", ms])
	return r


static func _find_path(world, start: Vector2i, goals: Array, aim: Vector2i, max_nodes: int = 12000) -> Array:
	# 0.3.14 12000 (was 4000): the bigger v2 towns need more search round a wall to the nearest gate
	var goal_set := {}
	for g in goals:
		if not world.is_blocked(g):
			goal_set[g] = true
	if goal_set.is_empty():
		return []
	if goal_set.has(start):
		return []
	var open_heap: Array = []   # [f, counter, Vector2i]
	var g_cost := {start: 0.0}
	var came := {}
	var closed := {}
	var counter := 0
	_push(open_heap, [_h(start, aim), counter, start])
	var expanded := 0
	while not open_heap.is_empty() and expanded < max_nodes:
		var cur: Vector2i = _pop(open_heap)[2]
		if closed.has(cur):
			continue
		if goal_set.has(cur):
			var path: Array = []
			var c := cur
			while c != start:
				path.append(c)
				c = came[c]
			path.reverse()
			return path
		closed[cur] = true
		expanded += 1
		for d in DIRS:
			var n: Vector2i = cur + d
			if closed.has(n) or world.is_blocked(n):
				continue
			if d.x != 0 and d.y != 0 and not diag_ok(world, cur, d):
				continue
			var cost: float = g_cost[cur] + (DIAG if (d.x != 0 and d.y != 0) else 1.0)
			if cost < g_cost.get(n, INF):
				g_cost[n] = cost
				came[n] = cur
				counter += 1
				_push(open_heap, [cost + _h(n, aim), counter, n])
	return []


## 0.3.0 corner rule: a diagonal step may slip past ONE blocking object (a
## tree, a rock: the sprites just overlap) but never past a wall/water corner,
## and never between two blocked tiles. (0.2.x forbade it next to any object,
## so every tree corner turned a diagonal into an up-then-over pair.)
static func diag_ok(world, cur: Vector2i, d: Vector2i) -> bool:
	var a := Vector2i(cur.x + d.x, cur.y)
	var b := Vector2i(cur.x, cur.y + d.y)
	var ba: bool = world.is_blocked(a)
	var bb: bool = world.is_blocked(b)
	if ba and bb:
		return false
	if not world.has_method("is_tile_blocked"):
		return not (ba or bb)
	return not ((ba and world.is_tile_blocked(a)) or (bb and world.is_tile_blocked(b)))


## The evenly spread grid line from a to b (excluding a): n = max(|dx|,|dy|)
## steps, each diagonal or straight, distributed like Bresenham.
static func grid_line(a: Vector2i, b: Vector2i) -> Array:
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	var out: Array = []
	for k in range(1, n + 1):
		var f := float(k) / n
		out.append(a + Vector2i(roundi(d.x * f), roundi(d.y * f)))
	return out


static func line_walkable(world, a: Vector2i, b: Vector2i) -> bool:
	var prev := a
	for q in grid_line(a, b):
		var step: Vector2i = q - prev
		if world.is_blocked(q) or (step.x != 0 and step.y != 0 and not diag_ok(world, prev, step)):
			return false
		prev = q
	return true


## 0.3.0 string pulling: replace the A* tile chain by straight grid lines
## between the farthest mutually visible waypoints. Same or fewer steps, and
## each straight run spreads its diagonal/straight steps evenly instead of
## "8 diagonals, then 4 sideways". Returns {"tiles": [...], "lines": [[from, to, k, n], ...]}.
static func straighten(world, start: Vector2i, raw: Array, lookahead: int = 48) -> Dictionary:
	var tiles: Array = []
	var lines: Array = []
	var anchor := start
	var i := 0
	while i < raw.size():
		var j := mini(raw.size() - 1, i + lookahead)
		while j > i and not line_walkable(world, anchor, raw[j]):
			j -= 1
		var to: Vector2i = raw[j]
		var seg := grid_line(anchor, to) if j > i or line_walkable(world, anchor, to) else [to]
		for k in seg.size():
			tiles.append(seg[k])
			lines.append([anchor, to, k + 1, seg.size()])
		anchor = to
		i = j + 1
	return {"tiles": tiles, "lines": lines}


## Tiles from which `target` can be interacted with (8 neighbours).
static func interaction_tiles(target: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		out.append(target + d)
	return out


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _less(heap[i], heap[p]):
			var t = heap[i]
			heap[i] = heap[p]
			heap[p] = t
			i = p
		else:
			break


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and _less(heap[l], heap[m]):
				m = l
			if r < n and _less(heap[r], heap[m]):
				m = r
			if m == i:
				break
			var t = heap[i]
			heap[i] = heap[m]
			heap[m] = t
			i = m
	return top
