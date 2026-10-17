class_name WorldObject
extends RefCounted
## A placed interactable (tree, rock, station...). Definition comes from
## data/objects.json; this holds per-instance runtime state only.

var def_id: String
var pos: Vector2i
var depleted_until: int = 0     # tick at which it respawns (0 = available)
var hp: int = 0                 # training dummy
var view: Node2D = null         # set by World when rendered
var meta: Dictionary = {}       # 0.3.0 per-instance data from the town file (shop, building, stand, slot)


func _init(p_def: String, p_pos: Vector2i) -> void:
	def_id = p_def
	pos = p_pos
	hp = int(def().get("hp", 0))


func def() -> Dictionary:
	return GameData.object_def(def_id)


func display_name() -> String:
	return str(meta.get("name", def().get("name", def_id)))


## Shop this object trades for (counter / keeper meta, else the def).
func shop_id() -> String:
	return str(meta.get("shop", def().get("shop", "general")))


func blocks() -> bool:
	return bool(def().get("blocks", true))


func is_depleted(tick: int) -> bool:
	return depleted_until > tick


func sprite_id(tick: int) -> String:
	var d := def()
	if is_depleted(tick):
		return d.get("depleted_sprite", "")
	return d.get("sprite", "")
