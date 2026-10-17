class_name ChunkData
extends RefCounted
## Tiles + objects for one CHUNK x CHUNK area. Pure data (AI and pathfinding
## use it even when the chunk isn't rendered).

var coord: Vector2i
var tiles := PackedByteArray()
var objects: Dictionary = {}     # Vector2i (world tile) -> WorldObject
var last_used_frame: int = 0


func _init(c: Vector2i) -> void:
	coord = c
	tiles.resize(WorldGen.CHUNK * WorldGen.CHUNK)


func tile_local(lx: int, ly: int) -> int:
	return tiles[ly * WorldGen.CHUNK + lx]
