class_name MapMarkers
extends RefCounted
## 0.3.1 custom player map markers. Pure data: add / edit / delete / clear,
## serialize into the player save. Icons and colours come from data/map_markers.json
## and sprites.json (ui/marker_<id>). Cap is tunable (default 50).

var markers: Array = []          # [{id, x, y, icon, colour, label}]
var show_on_minimap := true
var _next_id := 1


static func cfg() -> Dictionary:
	return GameData.map_markers_cfg


static func icons() -> Array:
	return cfg().get("icons", ["pin"])


static func colours() -> Array:
	return cfg().get("colours", ["#e05050"])


static func max_count() -> int:
	return int(cfg().get("max", 50))


static func default_icon() -> String:
	return str(cfg().get("default_icon", "pin"))


static func default_colour() -> String:
	return str(cfg().get("default_colour", "#e05050"))


static func label_max() -> int:
	return int(cfg().get("label_max", 16))


func count() -> int:
	return markers.size()


func is_full() -> bool:
	return markers.size() >= max_count()


func get_by_id(id: int) -> Dictionary:
	for m in markers:
		if int(m["id"]) == id:
			return m
	return {}


func find_near(tile: Vector2i, radius_tiles: float = 3.0) -> Dictionary:
	var best := {}
	var best_d := radius_tiles
	for m in markers:
		var d := Vector2(tile.x - int(m["x"]), tile.y - int(m["y"])).length()
		if d <= best_d:
			best_d = d
			best = m
	return best


## Add a marker at tile. Returns the new marker, or {} if full / invalid icon.
func add(tile: Vector2i, icon: String = "", colour: String = "", label: String = "") -> Dictionary:
	if is_full():
		return {}
	var ic := icon if icon != "" else default_icon()
	if not icons().has(ic):
		ic = default_icon()
	var col := colour if colour != "" else default_colour()
	if not colours().has(col):
		col = default_colour()
	var lab := label.strip_edges().left(label_max())
	var m := {
		"id": _next_id,
		"x": tile.x,
		"y": tile.y,
		"icon": ic,
		"colour": col,
		"label": lab,
	}
	_next_id += 1
	markers.append(m)
	return m


func update(id: int, fields: Dictionary) -> bool:
	var m := get_by_id(id)
	if m.is_empty():
		return false
	if fields.has("icon"):
		var ic := str(fields["icon"])
		if icons().has(ic):
			m["icon"] = ic
	if fields.has("colour"):
		var col := str(fields["colour"])
		if colours().has(col):
			m["colour"] = col
	if fields.has("label"):
		m["label"] = str(fields["label"]).strip_edges().left(label_max())
	if fields.has("x") and fields.has("y"):
		m["x"] = int(fields["x"])
		m["y"] = int(fields["y"])
	return true


func remove(id: int) -> bool:
	for i in markers.size():
		if int(markers[i]["id"]) == id:
			markers.remove_at(i)
			return true
	return false


func clear_all() -> int:
	var n := markers.size()
	markers.clear()
	return n


func tile_of(m: Dictionary) -> Vector2i:
	return Vector2i(int(m.get("x", 0)), int(m.get("y", 0)))


func to_save() -> Dictionary:
	var arr := []
	for m in markers:
		arr.append({
			"id": int(m["id"]),
			"x": int(m["x"]),
			"y": int(m["y"]),
			"icon": str(m["icon"]),
			"colour": str(m["colour"]),
			"label": str(m.get("label", "")),
		})
	return {"list": arr, "minimap": show_on_minimap, "next_id": _next_id}


func from_save(d: Dictionary) -> void:
	markers.clear()
	show_on_minimap = bool(d.get("minimap", cfg().get("minimap_show_default", true)))
	_next_id = maxi(1, int(d.get("next_id", 1)))
	for raw in d.get("list", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var ic := str(raw.get("icon", default_icon()))
		if not icons().has(ic):
			ic = default_icon()
		var col := str(raw.get("colour", default_colour()))
		if not colours().has(col):
			col = default_colour()
		var mid := int(raw.get("id", _next_id))
		markers.append({
			"id": mid,
			"x": int(raw.get("x", 0)),
			"y": int(raw.get("y", 0)),
			"icon": ic,
			"colour": col,
			"label": str(raw.get("label", "")).strip_edges().left(label_max()),
		})
		_next_id = maxi(_next_id, mid + 1)
