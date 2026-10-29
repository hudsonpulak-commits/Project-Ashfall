class_name SpriteAudit
extends RefCounted
## 0.3.19 catches cut-off sprites: an opaque run along the outer column or the
## top row means the art was sliced by its frame (the Saltmere palm bug).
## The bottom rows are the feet anchor and are allowed to touch the frame.


const ALPHA := 0.15


static func _opaque(img: Image, x: int, y: int) -> bool:
	return img.get_pixel(x, y).a > ALPHA


## Longest contiguous opaque run on one edge, as a fraction of that edge.
## `edge` is "L", "R" or "T". The bottom two rows are the trunk/feet.
static func edge_run(img: Image, edge: String) -> float:
	if img == null or img.is_empty():
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 3:
		return 0.0
	var flags: Array = []
	if edge == "T":
		for x in w:
			flags.append(_opaque(img, x, 0))
	else:
		var x := 0 if edge == "L" else w - 1
		for y in h - 2:
			flags.append(_opaque(img, x, y))
	return _longest(flags) / float(maxi(1, flags.size()))


static func worst_run(img: Image) -> float:
	return maxf(edge_run(img, "L"), maxf(edge_run(img, "R"), edge_run(img, "T")))


static func _longest(flags: Array) -> int:
	var best := 0
	var cur := 0
	for f in flags:
		cur = cur + 1 if f else 0
		best = maxi(best, cur)
	return best


## True when any outer pixel (the full border, including the feet) is opaque.
## Used by the synthetic check so a one-pixel clip is caught.
static func border_hit(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if (x == 0 or y == 0 or x == w - 1 or y == h - 1) and _opaque(img, x, y):
				return true
	return false


static func _is_foliage(id: String) -> bool:
	var s := id.to_lower()
	if s.begins_with("_") or s.contains("stump") or s.contains("dead") or s.contains("log"):
		return false
	return s.contains("tree") or s.contains("palm") or s.contains("bush")


## Foliage sprite ids whose frame cuts the art. `limit` is the worst-run
## fraction that still counts as intact (palms use a tighter limit).
static func clipped_foliage(limit: float = 0.62, palm_limit: float = 0.34) -> Array:
	var bad := []
	for id in GameData.sprites.get("objects", {}).keys():
		var sid := str(id)
		if not _is_foliage(sid):
			continue
		var img := _load(sid)
		if img == null:
			bad.append(sid + " (unreadable)")
			continue
		var run := worst_run(img)
		var cap := palm_limit if sid.to_lower().contains("palm") else limit
		if run >= cap:
			bad.append("%s (edge run %.2f)" % [sid, run])
	return bad


static func _load(id: String) -> Image:
	var tex := GameData.texture("objects", id)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return img
