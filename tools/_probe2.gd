extends Node
## ASCII probe: godot --headless --path . -s tools/_probe.gd -- x0 y0 w h
func _ready():
	var a := OS.get_cmdline_user_args()
	var x0 := int(a[0]); var y0 := int(a[1]); var w := int(a[2]); var h := int(a[3])
	var gen := WorldGen.new(int(a[4]) if a.size() > 4 else 7331)
	var ch := {0: ".", 1: "=", 2: "~", 3: ":", 4: ","}
	for y in range(y0, y0 + h, 2):
		var s := "%5d " % y
		for x in range(x0, x0 + w, 2):
			var t := gen.tile_at(x, y)
			var o := gen.object_at(x, y, t)
			var c: String = ch.get(t, WorldGen.TILE_NAMES[t].substr(0, 1).to_upper() if t < WorldGen.TILE_NAMES.size() else "?")
			if gen.is_cliff(x, y): c = "^"
			if o != "": c = "T" if "tree" in o else ("f" if "fence" in o else "o")
			if gen.town_at(Vector2i(x, y), 0) != "" or gen.village_at(Vector2i(x, y), 0) != "": c = "H" if t > 7 else c.to_upper()
			s += c
		print(s)
	get_tree().quit()
