extends SceneTree
func _init():
	var gen := WorldGen.new(7331)
	var best := []
	for y in range(-200, 200):
		for x in range(-250, 250):
			if gen.tile_at(x, y) == WorldGen.TileType.CLIFF_FACE and gen.cliff_mask(Vector2i(x, y)) == 4:
				var n := 0
				for dx in range(-4, 5):
					n += int(gen.tile_at(x + dx, y) == WorldGen.TileType.CLIFF_FACE)
				var lips := 0
				for dy in range(-6, 1):
					for dx in range(-6, 7):
						lips += int(gen.tile_at(x + dx, y + dy) == WorldGen.TileType.CLIFF_LIP)
				if n >= 7 and lips >= 6 and gen.town_at(Vector2i(x, y), 10) == "":
					print("FACE ", x, ",", y, " lips ", lips)
					best.append(1)
					if best.size() > 5:
						quit()
						return
	quit()
