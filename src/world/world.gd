class_name World
extends Node2D
## Owns the world: chunk data cache (for logic/pathing/AI), streamed chunk
## visuals around the camera focus, world-object state (depletion/respawn),
## and a y-sorted entity layer that actors are parented to.
##
## Rendering: one TileMapLayer per visible chunk using a TileSet built at
## runtime from data/sprites.json (so swapping a tile PNG needs no code).

signal object_changed(obj: WorldObject)
signal travelled(den_id: String, down: bool)   # 0.4.2 rat hole / den ladder

const CHUNK := WorldGen.CHUNK
const VIEW_RADIUS := 2          # chunks rendered around focus (5x5)
const UNLOAD_RADIUS := 3        # hysteresis so walking along a border doesn't thrash
const DATA_KEEP_RADIUS := 6     # chunk *data* kept around (AI/pathing)
const BUILDS_PER_FRAME := 2

var gen: WorldGen
var tile_px: int = 16
var chunks: Dictionary = {}          # Vector2i -> ChunkData
var chunk_views: Dictionary = {}     # Vector2i -> Node2D
var depleted: Dictionary = {}        # Vector2i -> respawn tick (authoritative)
var tick: int = 0

var ground_layer: Node2D
var entity_layer: Node2D             # y-sorted: objects + actors
var _tileset: TileSet
## batch_08_polish mood: the ground shader used to square every base tile (much darker
## ground than the art). With that fixed, the ground and its transition layers are dimmed
## together here (sprites, walls, roofs keep their painted values) to keep the old mood.
const GROUND_MOOD := Color(0.74, 0.73, 0.70)
## 0.4.3 overlay layers. Ground pieces (transitions, cliffs, shores, boardwalk,
## pilings, moat bank) go to the GROUND_OVL layers, which all take GROUND_MOOD
## like the base tiles; walls and building pieces keep their painted colours.
const OVL_NAMES := ["trans0", "trans1", "autotile", "joins", "corners", "walls", "g_autotile", "g_joins"]
const G_AUTOTILE := 6
const G_JOINS := 7
const GROUND_OVL := [0, 1, 6, 7]
const OVL_DRAW_ORDER := [0, 1, 6, 7, 2, 3, 4, 5]
var _overlay_src: Dictionary = {}
var _trans_var: Dictionary = {}       # transition id -> [[source, cols] v1, v2] (batch_08 wobble variants)    # "autotile/<id>" / "transitions/<id>" -> [source id, cols]
var _build_queue: Array = []
var _focus_chunk := Vector2i(999999, 999999)
var _animated: Array = []            # [Sprite2D, frames, fps]
var _anim_time := 0.0
var _mini_tex: Dictionary = {}       # Vector2i -> ImageTexture (minimap)
var ground: GroundItems              # items lying on tiles
var enemies: EnemyManager            # creature camps
var buildings_view: BuildingsView    # 0.3.0 roofs, signs, keepers, displays
var door_tiles: Dictionary = {}      # 0.3.19 Vector2i -> true, for worn paths
const AMBIENT := preload("res://src/world/ambient_life.gd")
var ambient                              # 0.3.20 smoke, birds, frogs, butterflies
var focus_tile := Vector2i.ZERO
var _sway_mat: ShaderMaterial
var _canopy_fade: Array = []         # foliage WorldObjects currently faded
const SWAY_SHADER := preload("res://assets/shaders/foliage_sway.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/ground_variation.gdshader")
const CANOPY_ALPHA := 0.4           # 0.3.19 tree crown when the player stands behind it


func setup(world_seed: int) -> void:
	tile_px = GameData.tile_size
	gen = WorldGen.new(world_seed)
	gen.perf_sink = perf_log
	_pf_seed = world_seed
	ground_layer = Node2D.new()
	ground_layer.name = "Ground"
	ground_layer.z_index = -10
	add_child(ground_layer)
	entity_layer = Node2D.new()
	entity_layer.name = "Entities"
	entity_layer.y_sort_enabled = true
	add_child(entity_layer)
	ground = GroundItems.new()
	ground.name = "GroundItems"
	add_child(ground)
	move_child(ground, entity_layer.get_index())
	enemies = EnemyManager.new()
	enemies.name = "Enemies"
	add_child(enemies)
	_tileset = _build_tileset()
	buildings_view = BuildingsView.new()
	buildings_view.name = "Buildings"
	add_child(buildings_view)
	buildings_view.setup(self)
	_build_wall_towers()
	ambient = AMBIENT.new()
	ambient.name = "AmbientLife"
	add_child(ambient)
	ambient.setup(self, WorldGen.GRASS_TILES, WorldGen.TileType.MARSH)
	_index_doors()


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	for i in WorldGen.TILE_NAMES.size():
		var tex := GameData.texture("tiles", WorldGen.TILE_NAMES[i])
		var src := TileSetAtlasSource.new()
		src.texture = tex
		# restyle (batch 02): 16x24 wall fronts / gates -- one tall tile whose
		# top 8 px overhang the wall-top cell to the north (bottom anchored)
		var tall := tex.get_height() > tile_px
		src.texture_region_size = Vector2i(tile_px, tex.get_height() if tall else tile_px)
		var cols := maxi(1, tex.get_width() / tile_px)
		for v in cols:
			src.create_tile(Vector2i(v, 0))
			if tall:
				src.get_tile_data(Vector2i(v, 0), 0).texture_origin = Vector2i(0, (tex.get_height() - tile_px) / 2)
		ts.add_source(src, i)
	# 0.3.9 autotile + transition overlay sheets (sources 100+ / 200+)
	_overlay_src.clear()
	var sid := 100
	for cat in ["autotile", "transitions"]:
		if cat == "transitions":
			sid = 200
		for id in GameData.sprites.get(cat, {}).keys():
			if str(id).begins_with("_"):
				continue
			var fs := GameData.frame_size(cat, id)
			if fs.y != tile_px:
				continue   # the fence sheet is drawn by object sprites, not the tile layer
			var tex := GameData.texture(cat, id)
			var src := TileSetAtlasSource.new()
			src.texture = tex
			src.texture_region_size = Vector2i(tile_px, tile_px)
			var cols := maxi(1, tex.get_width() / tile_px)
			var rows := maxi(1, tex.get_height() / tile_px)
			for r in rows:
				for cx in cols:
					src.create_tile(Vector2i(cx, r))
			ts.add_source(src, sid)
			_overlay_src[cat + "/" + id] = [sid, cols]
			sid += 1
	# batch_08_polish: 2 extra wobble variants per transition sheet (sources 400+), same frame layout
	_trans_var.clear()
	var vid := 400
	for id in GameData.sprites.get("transitions", {}).keys():
		if not _overlay_src.has("transitions/" + str(id)):
			continue
		for v in [1, 2]:
			var vp := "res://assets/sprites/transitions/variants/%s_v%d.png" % [id, v]
			if not ResourceLoader.exists(vp):
				continue
			var vt: Texture2D = load(vp)
			var vsrc := TileSetAtlasSource.new()
			vsrc.texture = vt
			vsrc.texture_region_size = Vector2i(tile_px, tile_px)
			var vc := maxi(1, vt.get_width() / tile_px)
			for r in maxi(1, vt.get_height() / tile_px):
				for cx in vc:
					vsrc.create_tile(Vector2i(cx, r))
			ts.add_source(vsrc, vid)
			_overlay_src["transitions/%s#%d" % [id, v]] = [vid, vc]
			var tva: Array = _trans_var.get(str(id), [])
			tva.append([vid, vc])
			_trans_var[str(id)] = tva
			vid += 1
	# restyle r5: thin unified walls -- one 16x28 atlas per material (16 top + 12 face drop,
	# drawn at the cell's top-left), frame picked by the 5x5 occupancy key via the shared LUT
	_wall_src.clear()
	var wid := 300
	for mat in WALL_ATLAS_MATS:
		var ap := "res://assets/sprites/tiles/walls_diag/%s_wall_atlas.png" % mat
		if not ResourceLoader.exists(ap):
			continue
		var at: Texture2D = load(ap)
		var asrc := TileSetAtlasSource.new()
		asrc.texture = at
		asrc.texture_region_size = Vector2i(tile_px, WALL_FRAME_H)
		var acols := at.get_width() / tile_px
		for r in at.get_height() / WALL_FRAME_H:
			for cx in acols:
				asrc.create_tile(Vector2i(cx, r))
				asrc.get_tile_data(Vector2i(cx, r), 0).texture_origin = Vector2i(0, -(WALL_FRAME_H - tile_px) / 2)
		ts.add_source(asrc, wid)
		_wall_src[mat] = [wid, acols]
		wid += 1
	return ts


## restyle r5 thin walls (batch_02 tiles/walls_diag, manifest r5).
const WALL_ATLAS_MATS := ["palisade", "basalt", "capital", "stone", "sandstone"]
const WALL_FRAME_H := 28
var _wall_src: Dictionary = {}     # mat -> [source id, cols]
static var _wall_lut: Dictionary = {}


static func wall_lut() -> Dictionary:
	if _wall_lut.is_empty():
		var f := FileAccess.open("res://assets/sprites/tiles/walls_diag/wall_atlas_lut.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				for k in d:
					_wall_lut[int(k)] = int(d[k])
	return _wall_lut


## 0.3.9 overlay cells for one tile: [[layer, source id, atlas coords], ...].
## layer 0/1 floor transitions, 2 wall caps / moat banks, 3 bridge joins.
## 4 moat inner corners (0.3.9.2).
## `nm` = Callable(Vector2i) -> tile name. Pure: unit-tested and used by _build_view.
## 0.3.9.2 moat inner corners NE, SE, SW, NW: [side a, side b, diagonal] as
## indexes into overlay_cells' neighbour list (N E S W NW NE SE SW).
const MOAT_CORNERS := [[0, 1, 5], [1, 2, 6], [2, 3, 7], [3, 0, 4]]


const BOARDWALK_JOINS := ["boardwalk", "planks", "bridge"]
const TRANS_ALIAS := {"ash_edge": "ash"}
## restyle batch 04: organic water edges. Not land: water, moat, decks over water, out of world.
const SHORE_NOT_LAND := ["water", "moat", "bridge", "boardwalk", "planks", ""]
const SHORE_ALIAS := {"ash_edge": "ash", "road_dirt": "path"}


## restyle batch 04: on a water cell, a bank frame from autotile/water_shore_<land> (same
## edge/corner bit rule as the floor transitions, bits where a neighbour is LAND),
## <land> = the most common land floor around it, else the generic water_shore. Layer 2.
func _add_shore(out: Array, nb: Array) -> void:
	var e := 0
	var cnt := {}
	for k in 8:
		var n: String = str(nb[k])
		if n in SHORE_NOT_LAND:
			continue
		if k < 4:
			e |= 1 << k
		var key: String = SHORE_ALIAS.get(n, n)
		cnt[key] = int(cnt.get(key, 0)) + 1
	if cnt.is_empty():
		return
	var c := 0
	var land := func(k): return not (str(nb[k]) in SHORE_NOT_LAND)
	if land.call(4) and not (e & 9): c |= 1
	if land.call(5) and not (e & 3): c |= 2
	if land.call(6) and not (e & 6): c |= 4
	if land.call(7) and not (e & 12): c |= 8
	var f := e | (c << 4)
	if f == 0:
		return
	var best := ""
	var bn := 0
	for k2 in cnt:
		if int(cnt[k2]) > bn or (int(cnt[k2]) == bn and str(k2) < best):
			best = k2
			bn = int(cnt[k2])
	var s: Array = _overlay_src.get("autotile/water_shore_" + best, [])
	if s.is_empty():
		s = _overlay_src.get("autotile/water_shore", [])
	if s.is_empty():
		return
	out.append([G_AUTOTILE, s[0], Vector2i(f % int(s[1]), f / int(s[1]))])


func overlay_cells(p: Vector2i, nm: Callable) -> Array:
	var out: Array = []
	var here: String = nm.call(p)
	var nb: Array = []
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		nb.append(nm.call(p + d))
	# restyle r5: thin wall frame on every wall cell and every cell next to one (gates draw their own sprite)
	if gen != null and not here.begins_with("gate_"):
		var wk: Array = gen.wall_key(p)
		if not wk.is_empty() and _wall_src.has(wk[0]):
			var fi: int = int(wall_lut().get(int(wk[1]), -1))
			if fi >= 0:
				var ws: Array = _wall_src[wk[0]]
				out.append([5, ws[0], Vector2i(fi % int(ws[1]), fi / int(ws[1]))])
	# restyle batch 04: ash_edge blends as ash (same art) -- the Scorch border is no longer a straight line
	var nbt: Array = nb.map(func(n): return TRANS_ALIAS.get(n, n))
	var ov := Autotile.overlays_for(TRANS_ALIAS.get(here, here), nbt)
	var tv := int(gen.hash01(p.x, p.y, 13) * 3) if gen != null and not ov.is_empty() else 0
	for i in ov.size():
		var s: Array = _overlay_src.get("transitions/" + str(ov[i]), [])
		if tv > 0:
			var va: Array = _trans_var.get(ov[i], [])
			if va.size() >= tv:
				s = va[tv - 1]
		if not s.is_empty():
			var f := Autotile.transition_frame(ov[i], nbt)
			out.append([i, s[0], Vector2i(f % int(s[1]), f / int(s[1]))])
	if Autotile.WALL_FAMILIES.has(here) and not Autotile.ART_WALLS.has(here) and not (gen != null and gen.is_thin_wall_cell(p)):
		var s: Array = _overlay_src.get("autotile/" + str(Autotile.WALL_FAMILIES[here]), [])
		if not s.is_empty():
			var f := Autotile.piece_at(p, func(q): var t: String = nm.call(q); return t == here or t in Autotile.WALL_JOIN_ALSO)
			out.append([2, s[0], Vector2i(f, 0)])
	elif here == "den_wall" or (here in DEN_FLOORS and nb[0] == "den_wall"):
		# 0.4.2 rat den walls: cap on the wall cell by the wall-neighbour mask (inner
		# corners by the open diagonal), face hanging into the open cell below
		var sd: Array = _overlay_src.get("autotile/den_wall16", [])
		if not sd.is_empty():
			if here == "den_wall":
				out.append([2, sd[0], Vector2i(_den_col(nb), 0)])
			else:
				var up := p + Vector2i(0, -1)
				var unb: Array = []
				for d2 in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
					unb.append(nm.call(up + d2))
				out.append([2, sd[0], Vector2i(_den_col(unb), 1)])
	elif here == "boardwalk":
		# restyle (batch 02): boardwalk deck autotile by the N1|E2|S4|W8 mask
		var sb: Array = _overlay_src.get("autotile/boardwalk16", [])
		if not sb.is_empty():
			var bm := 0
			for k in 4:
				if nb[k] in BOARDWALK_JOINS:
					bm |= 1 << k
			out.append([G_AUTOTILE, sb[0], Vector2i(bm, 0)])
	elif here == "water" and nb[0] == "boardwalk":
		_add_shore(out, nb)
		# pilings under the deck edge, in the water cell south of a boardwalk
		var sp: Array = _overlay_src.get("autotile/boardwalk_piling16", [])
		if not sp.is_empty():
			out.append([G_JOINS, sp[0], Vector2i(0, 0)])
	elif here == "water":
		_add_shore(out, nb)
	elif here == "moat":
		# restyle: moats get the same organic shore pass as natural water (replaces the
		# moat_border bank + inner-corner pieces); bridge joins stay on layer 3.
		_add_shore(out, nb)
		var s: Array = _overlay_src.get("autotile/moat_border", [])
		if not s.is_empty():
			for k in 4:
				if nb[k] == "bridge":
					out.append([G_JOINS, s[0], Vector2i(16 + k, 0)])
					break
	if gen != null and (here in CLIFF_NAMES or (nb.size() >= 4 and (str(nb[0]) in CLIFF_NAMES or str(nb[1]) in CLIFF_NAMES or str(nb[2]) in CLIFF_NAMES or str(nb[3]) in CLIFF_NAMES))):
		for pc in cliff_pieces(p, here, nb):
			var cs2: Array = _overlay_src.get("autotile/" + cliff_palette(p) + str(pc[0]), [])
			if not cs2.is_empty():
				var f2 := int(pc[1])
				out.append([G_JOINS if str(pc[0]) == "cliff_shadow" else G_AUTOTILE, cs2[0], Vector2i(f2 % int(cs2[1]), f2 / int(cs2[1]))])
	return out


## 0.3.11 the designer's cliff tiles (assets/sprites/cliffs/{normal,cinder},
## art_handoff/cliffs README + pick()): edge cells autotile by the N1|E2|S4|W8
## plateau mask, inner corners by the diagonals; south faces, south outer
## corners and stairs are 16x32 (frame 1 hangs into the cell below), the shadow
## lies 2 rows below. The Cinder region uses the cinder set.
const CLIFF_NAMES := ["cliff_face", "cliff_lip", "cliff_shadow", "cliff_stairs", "cliff_foot"]


## 0.4.2 den wall sheet column: 0-15 mask, 16-19 inner corners (mask 15 with an
## open diagonal), 20-23 45-degree diagonals: N+E / N+W outer corners with the
## opposite diagonal open (front, face below), E+S / S+W (back rim).
const DEN_FLOORS := ["den_floor", "den_mud", "den_sludge"]


static func _den_col(nb: Array) -> int:
	var dm := _den_mask(nb)
	if dm == 15:
		for k in [[5, 16], [6, 17], [7, 18], [4, 19]]:
			if nb[k[0]] != "den_wall":
				return k[1]
		return 15
	if nb.size() >= 8:
		match dm:
			3:
				if nb[7] != "den_wall": return 20
			9:
				if nb[6] != "den_wall": return 21
			6:
				if nb[4] != "den_wall": return 22
			12:
				if nb[5] != "den_wall": return 23
	return dm


static func _den_mask(nb: Array) -> int:
	var m := 0
	for k in 4:
		if nb[k] == "den_wall":
			m |= 1 << k
	return m


func cliff_palette(p: Vector2i) -> String:
	return "cinder_" if gen.region_map != null and gen.region_map.region_at(p) == "cinder" else ""


## The piece drawn on a south edge cell (face variants by cell hash).
func _south_piece(q: Vector2i) -> String:
	if gen.tile_at(q.x, q.y) == WorldGen.TileType.CLIFF_STAIRS:
		return "cliff_stairs"
	var m: int = gen.cliff_mask(q)
	if m & 2:
		return "cliff_corner_outer_se"
	if m & 8:
		return "cliff_corner_outer_sw"
	return ["cliff_face_s_a", "cliff_face_s_b", "cliff_face_s_c", "cliff_face_s_d"][posmod(q.x * 7 + q.y * 3, 4)]


func cliff_pieces(p: Vector2i, here: String, nb: Array) -> Array:
	var out: Array = []
	if here == "cliff_shadow":
		out.append(["cliff_shadow", 0])
	if here in ["cliff_face", "cliff_lip", "cliff_stairs"]:
		var m: int = gen.cliff_mask(p)
		if m & 4:
			out.append([_south_piece(p), 0])
			return out
		if here == "cliff_stairs":
			return out   # east / west / north ramps: open ground
		var v := "_b" if posmod(p.y * 5 + p.x * 3, 3) == 0 else ""
		if (m & 1) and (m & 2):
			out.append(["cliff_corner_outer_ne", 0])
		elif (m & 1) and (m & 8):
			out.append(["cliff_corner_outer_nw", 0])
		elif m & 1:
			out.append(["cliff_rim_n" + v, 0])
		elif m & 2:
			out.append(["cliff_rim_e" + v, 0])
		elif m & 8:
			out.append(["cliff_rim_w" + v, 0])
		else:
			var ic := _inner_corner(p)
			if ic != "":
				out.append([ic, 0])
		return out
	# the cell below a south edge: the overhang half of the 16x32 piece
	var up := p + Vector2i(0, -1)
	if nb.size() > 0 and str(nb[0]) in ["cliff_face", "cliff_stairs", "cliff_lip"] and (gen.cliff_mask(up) & 4):
		out.append([_south_piece(up), 1])
		return out
	# plateau cells whose only lower neighbour is diagonal: inner corner
	if not (here in CLIFF_NAMES) and gen.cliff_mask(p) == 0:
		var ic2 := _inner_corner(p)
		if ic2 != "":
			out.append([ic2, 0])
	return out


func _inner_corner(p: Vector2i) -> String:
	var l: int = gen.cliff_level(p)
	if gen.cliff_level(p + Vector2i(1, 1)) < l:
		return "cliff_corner_inner_se"
	if gen.cliff_level(p + Vector2i(-1, 1)) < l:
		return "cliff_corner_inner_sw"
	if gen.cliff_level(p + Vector2i(1, -1)) < l:
		return "cliff_corner_inner_ne"
	if gen.cliff_level(p + Vector2i(-1, -1)) < l:
		return "cliff_corner_inner_nw"
	return ""


## Cliff cells draw region ground underneath; the pieces above carry the look.
func cliff_base_tile(p: Vector2i, t: int) -> int:
	if t in [WorldGen.TileType.CLIFF_FACE, WorldGen.TileType.CLIFF_SHADOW, WorldGen.TileType.CLIFF_LIP, WorldGen.TileType.CLIFF_STAIRS, WorldGen.TileType.CLIFF_FOOT]:
		return gen.region_grass(p)
	return t


func variants_for(tile_type: int) -> int:
	var src := _tileset.get_source(tile_type) as TileSetAtlasSource
	return src.get_tiles_count() if src else 1


# ------------------------------------------------------------- coordinates --
static func chunk_of(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))


func tile_to_pos(p: Vector2i) -> Vector2:
	return Vector2(p.x * tile_px, p.y * tile_px)


## Bottom-centre of a tile: where y-sorted sprites stand.
func tile_foot(p: Vector2i) -> Vector2:
	return Vector2(p.x * tile_px + tile_px * 0.5, (p.y + 1) * tile_px)


func pos_to_tile(v: Vector2) -> Vector2i:
	return Vector2i(floori(v.x / tile_px), floori(v.y / tile_px))


# -------------------------------------------------------------------- data --
# ---- 0.3.16 chunk data prefetch on a worker thread --------------------------
## A second WorldGen (same seed, same data) lives on a worker thread and
## generates chunk data ahead of the player; the main thread only adopts the
## finished ChunkData (cheap). get_chunk() still generates synchronously when a
## chunk is needed before the worker got to it.
const PREFETCH_RADIUS := 4       # chunk data kept warm around the focus
const PREFETCH_AHEAD := 3        # extra chunks in the walking direction
var _pf_thread: Thread
var _pf_mutex := Mutex.new()
var _pf_sem := Semaphore.new()
var _pf_todo: Array = []         # Vector2i, nearest first (guarded by _pf_mutex)
var _pf_done: Array = []         # ChunkData (guarded by _pf_mutex)
var _pf_quit := false
var _pf_seed := 0
var _pf_last := Vector2i(999999, 999999)
var prefetch_enabled := true
var prefetch_adopted := 0


func _pf_start() -> void:
	if _pf_thread != null or not prefetch_enabled or OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	# 0.3.16 the worker's WorldGen is built here on the main thread (its setup touches
	# shared GameData/static caches); the thread only calls generate_chunk on it
	_pf_gen = WorldGen.new(_pf_seed)
	_pf_thread = Thread.new()
	_pf_thread.start(_pf_loop)
	if _focus_chunk.x != 999999:
		_pf_request(_focus_chunk, Vector2i.ZERO)


var _pf_ramps: Dictionary = {}
var _pf_gen: WorldGen = null


func _pf_loop() -> void:
	var wg: WorldGen = _pf_gen
	while true:
		_pf_sem.wait()
		_pf_mutex.lock()
		if _pf_quit:
			_pf_mutex.unlock()
			return
		var c = _pf_todo.pop_front() if not _pf_todo.is_empty() else null
		_pf_mutex.unlock()
		if c == null:
			continue
		var ch: ChunkData = wg.generate_chunk(c)
		# 0.3.16 hand over the cliff-ramp cell analyses (expensive; the view build needs them too)
		var rp: int = wg._ramp_period
		var cr: Vector2i = Vector2i(floori(float(c.x * CHUNK) / rp), floori(float(c.y * CHUNK) / rp))
		var ramps := {}
		for yy in range(cr.y - 1, cr.y + CHUNK / rp + 2):
			for xx in range(cr.x - 1, cr.x + CHUNK / rp + 2):
				var cc := Vector2i(xx, yy)
				wg._cell_hit(cc, Vector2i.ZERO)
				ramps[cc] = wg._cell_ramps.get(cc, {})
		_pf_mutex.lock()
		_pf_done.append(ch)
		_pf_ramps.merge(ramps, true)
		_pf_mutex.unlock()


func _pf_request(c: Vector2i, dir: Vector2i) -> void:
	if _pf_thread == null:
		return
	var want: Array = []
	for dy in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
		for dx in range(-PREFETCH_RADIUS, PREFETCH_RADIUS + 1):
			want.append(c + Vector2i(dx, dy))
	if dir != Vector2i.ZERO:
		for k in range(PREFETCH_RADIUS + 1, PREFETCH_RADIUS + 1 + PREFETCH_AHEAD):
			for s2 in range(-2, 3):
				want.append(c + dir * k + Vector2i(dir.y, dir.x) * s2)
	var aim := c + dir * 2
	want.sort_custom(func(a, b): return (a - aim).length_squared() < (b - aim).length_squared())
	_pf_mutex.lock()
	_pf_todo.clear()
	for q in want:
		if not chunks.has(q):
			_pf_todo.append(q)
	var n := _pf_todo.size()
	_pf_mutex.unlock()
	for i in n:
		_pf_sem.post()


func _pf_pending(c: Vector2i) -> bool:
	_pf_mutex.lock()
	var r := c in _pf_todo
	_pf_mutex.unlock()
	return r


func _all_pending() -> bool:
	for q in _build_queue:
		if chunks.has(q) or not _pf_pending(q):
			return false
	return true


func _pf_adopt() -> void:
	if _pf_thread == null:
		return
	_pf_mutex.lock()
	var done := _pf_done
	_pf_done = []
	var ramps := _pf_ramps
	_pf_ramps = {}
	_pf_mutex.unlock()
	if not ramps.is_empty():
		if gen._cell_ramps.size() > 3000:
			gen._cell_ramps.clear()
		gen._cell_ramps.merge(ramps, false)
	for ch in done:
		if chunks.has(ch.coord):
			continue
		for p in ch.objects.keys():
			if gen._town_meta.has(p):
				ch.objects[p].meta = gen._town_meta[p]
		_adopt_chunk(ch)
		prefetch_adopted += 1


func _adopt_chunk(ch: ChunkData) -> void:
	for p in ch.objects.keys():
		if depleted.has(p):
			ch.objects[p].depleted_until = int(depleted[p])
	chunks[ch.coord] = ch


func _exit_tree() -> void:
	if _pf_thread != null:
		_pf_mutex.lock()
		_pf_quit = true
		_pf_mutex.unlock()
		_pf_sem.post()
		_pf_thread.wait_to_finish()
		_pf_thread = null


func get_chunk(c: Vector2i) -> ChunkData:
	var ch: ChunkData = chunks.get(c)
	if ch == null:
		var _tg := Time.get_ticks_usec()
		ch = gen.generate_chunk(c)
		var _st := get_stack()
		var _who := ""
		for _k in range(1, mini(5, _st.size())):
			_who += "<" + str(_st[_k]["function"])
		perf_log.append(["syncgen" + _who, (Time.get_ticks_usec() - _tg) / 1000.0])
		for p in ch.objects.keys():
			if depleted.has(p):
				ch.objects[p].depleted_until = int(depleted[p])
		chunks[c] = ch
	return ch


func tile_type(p: Vector2i) -> int:
	var c := chunk_of(p)
	return get_chunk(c).tile_local(p.x - c.x * CHUNK, p.y - c.y * CHUNK)


func object_at(p: Vector2i) -> WorldObject:
	return get_chunk(chunk_of(p)).objects.get(p)


## 0.3.16 like object_at but never generates: null when the chunk's data isn't loaded.
func object_at_loaded(p: Vector2i) -> WorldObject:
	var ch: ChunkData = chunks.get(chunk_of(p))
	return ch.objects.get(p) if ch != null else null


func is_blocked(p: Vector2i) -> bool:
	var c := chunk_of(p)
	var ch := get_chunk(c)
	if ch.tile_local(p.x - c.x * CHUNK, p.y - c.y * CHUNK) in WorldGen.BLOCKING_TILES:
		return true
	var o: WorldObject = ch.objects.get(p)
	return o != null and o.blocks()


## Nearest walkable tile. outdoor = also skip building footprints (AI strolls,
## save relocation) so nobody idles inside a shop or on its doorway.
## Blocked by terrain itself (water, walls), not by an object standing there.
func is_tile_blocked(p: Vector2i) -> bool:
	return tile_type(p) in WorldGen.BLOCKING_TILES


func find_free_tile_near(p: Vector2i, max_r: int = 12, outdoor: bool = false) -> Vector2i:
	for r in max_r + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if not is_blocked(q) and not (outdoor and not gen.building_at(q).is_empty()):
					return q
	return p


## Nearest object of the given def ids within radius (Chebyshev), not depleted.
func find_nearest_object(from: Vector2i, def_ids: Array, radius: int = 30, allow_private: bool = false, loaded_only: bool = false) -> WorldObject:
	var best: WorldObject = null
	var best_d := 1 << 30
	var c0 := chunk_of(from - Vector2i(radius, radius))
	var c1 := chunk_of(from + Vector2i(radius, radius))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if loaded_only and not chunks.has(Vector2i(cx, cy)):
				continue   # 0.3.16 off-screen AI: never generate chunk data just to look
			for o in get_chunk(Vector2i(cx, cy)).objects.values():
				if not (o.def_id in def_ids) or o.is_depleted(tick):
					continue
				var d := maxi(absi(o.pos.x - from.x), absi(o.pos.y - from.y))
				if d <= radius and d < best_d and (allow_private or not gen.is_private(o.pos)):
					best_d = d
					best = o
	return best


## 0.3.1 PK helpers (data/pk_zones.json); the PK rules live with the AI/PK track.
## 0.3.1 churches: the nearest altar (by tiles) from `from`, optionally in one
## town. {"pos": altar tile, "approach": tile to stand on (door side),
## "building": id, "town": id, "door": door tile}; {} if none. AI players use
## this (walk to "approach", then interact with the altar object).
func nearest_altar(from: Vector2i, town: String = "") -> Dictionary:
	var best: Dictionary = {}
	var bd := 1 << 30
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		if not b.has("altar") or (town != "" and b["town"] != town):
			continue
		var a: Vector2i = b["altar"]
		var d := maxi(absi(a.x - from.x), absi(a.y - from.y))
		if d < bd:
			bd = d
			var door: Vector2i = b["doors"][0]
			var step := Vector2i(0, 1) if door.y > a.y else Vector2i(0, -1)
			best = {"pos": a, "approach": a + step, "building": id, "town": b["town"], "door": door}
	return best


## 0.4.2 travel objects: the surface rat hole drops the player into its den
## (arrival cell under the ladder); the den ladder brings them back up in front
## of the hole. Chunks at the far end load at once.
func travel(actor, obj: WorldObject, d: Dictionary) -> bool:
	var did := str(d.get("den", ""))
	if not gen.dens.has(did):
		return false
	var dd: Dictionary = gen.dens[did]
	var to: Vector2i
	var text := ""
	if bool(d.get("up", false)):
		to = gen.den_exit_tile(did)
		text = str(dd.get("leave_text", "You climb back up."))
	else:
		to = gen.den_arrival(did)
		text = str(dd.get("enter_text", "You climb down."))
	if to.x <= -99999:
		return false
	to = find_free_tile_near(to, 4)
	actor.place_at(to)
	actor.action = {}
	set_focus(to)   # views stream in nearest-first under the fade (no sync build: frame budget)
	_travel_fade()
	Events.say(text)
	travelled.emit(did, not bool(d.get("up", false)))
	return true


func _travel_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 1)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)
	add_child(layer)
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(r, "color:a", 0.0, 0.5)
	tw.tween_callback(layer.queue_free)


## 0.4.2 the den the tile lies in ("" = surface).
func den_at(p: Vector2i) -> String:
	return gen.den_at(p) if gen != null else ""


func is_pk(p: Vector2i) -> bool:
	return gen.is_pk(p)


func pk_zone_at(p: Vector2i) -> Dictionary:
	return gen.pk_zone_at(p)


## 0.3.1 AI routing: a gather node of `def_id` for someone at `from` whose
## home town is `home_town`. Nearby first (as before); otherwise the closest
## named mine (data/mines.json) that holds it, Scorch mines last.
func find_gather_node(from: Vector2i, def_id: String, home_town: String = "", radius: int = 30, loaded_only: bool = false) -> WorldObject:
	var o := find_nearest_object(from, [def_id], radius, false, loaded_only)
	if o != null:
		return o
	if bool(GameData.object_def(def_id).get("farm", false)):   # 0.3.1 village wheat fields
		var anchor0 := gen.town_center(home_town) if gen.towns.has(home_town) else from
		var f := gen.nearest_farm(anchor0, def_id)
		if f.is_empty():
			return null
		var r: Rect2i = f["rect"]
		return find_nearest_object(f["center"], [def_id], maxi(r.size.x, r.size.y), false, loaded_only)
	if not def_id.ends_with("_rock"):
		return null
	var anchor := gen.town_center(home_town) if gen.towns.has(home_town) else from
	var m := gen.nearest_mine(anchor, def_id, false)
	if m.is_empty():
		m = gen.nearest_mine(anchor, def_id, true)
	if m.is_empty():
		return null
	return find_nearest_object(m["c"], [def_id], int(ceil(float(m["radius"]))) + 1, false, loaded_only)


func deplete(o: WorldObject, ticks: int) -> void:
	o.depleted_until = tick + maxi(1, ticks)
	depleted[o.pos] = o.depleted_until
	_refresh_object_view(o)
	object_changed.emit(o)


var fires: Dictionary = {}   # 0.3.6 Vector2i -> tick the cooking fire burns out


## 0.3.6 a temporary cooking fire (a hearth station) that burns out by itself.
func add_fire(p: Vector2i, ticks: int) -> WorldObject:
	var o := WorldObject.new("cooking_fire", p)
	get_chunk(chunk_of(p)).objects[p] = o
	fires[p] = tick + maxi(1, ticks)
	var c := chunk_of(p)
	if chunk_views.has(c):
		_make_object_view(o)
		var objs: Array = chunk_views[c].get_meta("objects", [])
		objs.append(o)
	object_changed.emit(o)
	return o


func _expire_fires(t: int) -> void:
	for p in fires.keys():
		if int(fires[p]) > t:
			continue
		fires.erase(p)
		var ch := get_chunk(chunk_of(p))
		var o: WorldObject = ch.objects.get(p)
		if o and o.def_id == "cooking_fire":
			ch.objects.erase(p)
			if o.view and is_instance_valid(o.view):
				o.view.queue_free()
			o.view = null
			var c := chunk_of(p)
			if chunk_views.has(c):
				var objs: Array = chunk_views[c].get_meta("objects", [])
				objs.erase(o)
			object_changed.emit(o)


func on_tick(t: int) -> void:
	tick = t
	if not fires.is_empty():
		_expire_fires(t)
	if depleted.is_empty():
		return
	var done := []
	for p in depleted.keys():
		if int(depleted[p]) <= t:
			done.append(p)
	for p in done:
		depleted.erase(p)
		var c := chunk_of(p)
		if chunks.has(c):
			var o: WorldObject = chunks[c].objects.get(p)
			if o:
				o.depleted_until = 0
				_refresh_object_view(o)
				object_changed.emit(o)


# --------------------------------------------------------------- streaming --
func set_focus(p: Vector2i, immediate: bool = false) -> void:
	focus_tile = p
	var c := chunk_of(p)
	if c == _focus_chunk and not immediate:
		return
	var _tf := Time.get_ticks_usec()
	_set_focus_inner(c, immediate)
	perf_log.append(["focus", (Time.get_ticks_usec() - _tf) / 1000.0])


func _set_focus_inner(c: Vector2i, immediate: bool) -> void:
	_focus_chunk = c
	# queue missing views, nearest first
	var want: Array = []
	for dy in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var cc := c + Vector2i(dx, dy)
			if not chunk_views.has(cc) and not (cc in _build_queue):
				want.append(cc)
	want.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	_build_queue.append_array(want)
	# unload far views
	for cc in chunk_views.keys():
		if maxi(absi(cc.x - c.x), absi(cc.y - c.y)) > UNLOAD_RADIUS:
			_free_view(cc)
	# prune far data (keep depletion state in `depleted`)
	for cc in chunks.keys():
		if maxi(absi(cc.x - c.x), absi(cc.y - c.y)) > DATA_KEEP_RADIUS:
			chunks.erase(cc)
			_mini_tex.erase(cc)
	if not _job.is_empty() and maxi(absi(_job["c"].x - c.x), absi(_job["c"].y - c.y)) > VIEW_RADIUS:
		_abort_job()
	var dirv := Vector2i.ZERO
	if _pf_last.x != 999999:
		dirv = Vector2i(signi(c.x - _pf_last.x), signi(c.y - _pf_last.y))
	_pf_last = c
	_pf_request(c, dirv)
	if immediate:
		while not _job.is_empty():
			if _job_step(_job, 1e9):
				_job = {}
		while not _build_queue.is_empty():
			var cq: Vector2i = _build_queue.pop_front()
			if not chunk_views.has(cq):
				_build_view(cq)


func _process(delta: float) -> void:
	var d := (1.0 / 60.0) if Tick.fixed_step else delta   # 0.3.19 QA: one frame is one fixed slice
	if _pf_thread == null and _focus_chunk.x != 999999 and Tick.running:
		_pf_start()   # once the game is running, never during loading
	if not perf_on and perf_log.size() > 2000:
		perf_log.clear()   # only the QA perf scenario keeps the timings
	var _ta := Time.get_ticks_usec()
	_pf_adopt()
	perf_log.append(["adopt", (Time.get_ticks_usec() - _ta) / 1000.0])
	var t_end := Time.get_ticks_usec() + int(BUILD_BUDGET_MS * 1000.0)
	while Time.get_ticks_usec() < t_end:
		if _job.is_empty():
			if _build_queue.is_empty():
				break
			var cc: Vector2i = _build_queue.pop_front()
			if maxi(absi(cc.x - _focus_chunk.x), absi(cc.y - _focus_chunk.y)) > VIEW_RADIUS or chunk_views.has(cc):
				continue
			if not chunks.has(cc) and _pf_thread != null and _pf_pending(cc):
				_build_queue.push_back(cc)   # its data is still on the worker: build another one meanwhile
				if _build_queue.size() <= 1 or _all_pending():
					break
				continue
			_job = _job_new(cc)
		if _job_step(_job, (t_end - Time.get_ticks_usec()) / 1000.0):
			_job = {}
	_anim_time += d
	for a in _animated:
		var spr: Sprite2D = a[0]
		if is_instance_valid(spr):
			spr.frame = int(_anim_time * float(a[2])) % maxi(1, mini(int(a[1]), spr.hframes * spr.vframes))
	_update_canopies(d)
	if ambient != null:
		ambient.step(focus_tile, d)


var perf_on := false   # set by the QA perf scenario
var perf_log: Array = []   # 0.3.16 [what, ms] for the QA perf scenario
const BUILD_BUDGET_MS := 4.0   # 0.3.16 chunk views are built in slices within this per-frame budget
var _job: Dictionary = {}      # the chunk view being built (time-sliced)


func _build_view(c: Vector2i) -> void:
	var j := _job_new(c)
	while not _job_step(j, 1e9):
		pass


func _job_new(c: Vector2i) -> Dictionary:
	var _t0 := Time.get_ticks_usec()
	var ch := get_chunk(c)
	perf_log.append(["gen", (Time.get_ticks_usec() - _t0) / 1000.0])
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	var layer := TileMapLayer.new()
	layer.tile_set = _tileset
	layer.position = Vector2(c.x * CHUNK * tile_px, c.y * CHUNK * tile_px)
	# 0.3.16 in the tree (hidden) from the start, so the layers' internal updates are
	# spread over the frames that fill them instead of landing in one frame
	root.visible = false
	root.add_child(layer)
	layer.material = _ground_material(c, ch)
	layer.modulate = GROUND_MOOD
	ground_layer.add_child(root)
	return {"c": c, "ch": ch, "root": root, "layer": layer, "stage": 0, "row": 0, "names": {}, "ovl": [],
		"base": Vector2i(c.x * CHUNK, c.y * CHUNK), "objs": [], "oi": 0, "ol": []}


## Advance a build job until budget_ms is used up. True when the chunk is shown.
func _job_step(j: Dictionary, budget_ms: float) -> bool:
	var t_end := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var _t0 := Time.get_ticks_usec()
	var c: Vector2i = j["c"]
	var ch: ChunkData = j["ch"]
	var base: Vector2i = j["base"]
	while Time.get_ticks_usec() < t_end:
		var _ts := Time.get_ticks_usec()
		var _sg := int(j["stage"])
		_job_stage(j, c, ch, base)
		perf_log.append(["build:s%d" % _sg, (Time.get_ticks_usec() - _ts) / 1000.0])
		if int(j["stage"]) == 5:
			perf_log.append(["build", (Time.get_ticks_usec() - _t0) / 1000.0])
			return true
	perf_log.append(["build", (Time.get_ticks_usec() - _t0) / 1000.0])
	return false


func _job_stage(j: Dictionary, c: Vector2i, ch: ChunkData, base: Vector2i) -> void:
	if true:
		match int(j["stage"]):
			0:   # base tiles, one row per step
				var ly: int = j["row"]
				var layer: TileMapLayer = j["layer"]
				for lx in CHUNK:
					var t := ch.tile_local(lx, ly)
					var wx := base.x + lx
					var wy := base.y + ly
					t = cliff_base_tile(Vector2i(wx, wy), t)
					t = gen.wall_ground_tile(Vector2i(wx, wy), t)
					var nv := variants_for(t)
					var v := 0 if nv <= 1 else int(gen.hash01(wx, wy, 7) * nv) % nv
					layer.set_cell(Vector2i(lx, ly), t, Vector2i(v, 0))
				j["row"] = ly + 1
				if j["row"] >= CHUNK:
					j["stage"] = 1
					j["row"] = -1
			1:   # 0.3.9 overlay names of the chunk + a 1-tile rim, one row per step
				var ly2: int = j["row"]
				var names: Dictionary = j["names"]
				for lx in range(-1, CHUNK + 1):
					var inside := lx >= 0 and ly2 >= 0 and lx < CHUNK and ly2 < CHUNK
					var tt: int = ch.tile_local(lx, ly2) if inside else _rim_tile(base.x + lx, base.y + ly2)
					names[base + Vector2i(lx, ly2)] = WorldGen.TILE_NAMES[tt]
				j["row"] = ly2 + 1
				if j["row"] > CHUNK:
					j["stage"] = 2
					j["row"] = 0
					var ovl: Array = j["ovl"]
					for i in OVL_NAMES.size():
						var l := TileMapLayer.new()
						l.tile_set = _tileset
						l.position = (j["layer"] as TileMapLayer).position
						l.name = OVL_NAMES[i]
						if i in GROUND_OVL:
							l.modulate = GROUND_MOOD   # 0.4.3 every ground layer takes the same mood tint
						ovl.append(l)
					for i in OVL_DRAW_ORDER:
						(j["root"] as Node2D).add_child(ovl[i])
			2:   # overlays, one row per step
				var ly3: int = j["row"]
				var names2: Dictionary = j["names"]
				var nm := func(q: Vector2i) -> String: return names2.get(q, "")
				var ovl2: Array = j["ovl"]
				# 0.3.16 a third of a row per step (cliff lookups can be slow on first touch)
				var x0: int = int(j.get("col", 0))
				for lx in range(x0, mini(CHUNK, x0 + 8)):
					var _tc := Time.get_ticks_usec()
					for cell in overlay_cells(base + Vector2i(lx, ly3), nm):
						(ovl2[cell[0]] as TileMapLayer).set_cell(Vector2i(lx, ly3), cell[1], cell[2])
					var _dc := (Time.get_ticks_usec() - _tc) / 1000.0
					if _dc > 5.0:
						perf_log.append(["ovcell@%d,%d" % [base.x + lx, ly3 + base.y], _dc])
				j["col"] = x0 + 8
				if int(j["col"]) >= CHUNK:
					j["col"] = 0
					j["row"] = ly3 + 1
				if j["row"] >= CHUNK:
					j["stage"] = 3
			3:   # attach the layers
				var root: Node2D = j["root"]
				for l in j["ovl"]:
					if (l as TileMapLayer).get_used_cells().is_empty():
						l.free()
				root.visible = true
				chunk_views[c] = root
				j["ol"] = ch.objects.values()
				root.set_meta("objects", j["objs"])
				j["stage"] = 4
			4:   # object views, a few per step
				var ol: Array = j["ol"]
				var objs: Array = j["objs"]
				var k := 0
				while int(j["oi"]) < ol.size() and k < 16:
					var o: WorldObject = ol[int(j["oi"])]
					j["oi"] = int(j["oi"]) + 1
					k += 1
					if o.view == null or not is_instance_valid(o.view):
						_make_object_view(o)
					objs.append(o)
				if int(j["oi"]) >= ol.size():
					j["stage"] = 5


## 0.3.16 a neighbour tile for the overlay rim: from loaded (prefetched) chunk data when possible.
func _rim_tile(x: int, y: int) -> int:
	var p := Vector2i(x, y)
	var cc := chunk_of(p)
	var ch: ChunkData = chunks.get(cc)
	if ch != null:
		return ch.tile_local(x - cc.x * CHUNK, y - cc.y * CHUNK)
	return gen.tile_at(x, y)


func _abort_job() -> void:
	if _job.is_empty():
		return
	var j := _job
	_job = {}
	if chunk_views.has(j["c"]) and chunk_views[j["c"]] == j["root"]:
		_free_view(j["c"])
	elif is_instance_valid(j["root"]):
		j["root"].free()


func _free_view(c: Vector2i) -> void:
	var root: Node2D = chunk_views[c]
	for o in root.get_meta("objects", []):
		if o.view and is_instance_valid(o.view):
			o.view.queue_free()
		o.view = null
	root.queue_free()
	chunk_views.erase(c)
	_animated = _animated.filter(func(a): return is_instance_valid(a[0]) and not a[0].is_queued_for_deletion())


func _make_object_view(o: WorldObject) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.position = tile_foot(o.pos)
	o.view = spr
	if o.def().has("actor_sprite"):   # 0.3.7 quest givers use an actor sheet
		apply_keeper_sprite(spr, str(o.def()["actor_sprite"]))
	elif o.def().get("keeper", false):
		var b: Dictionary = gen.buildings.get(str(o.meta.get("building", "")), {})
		apply_keeper_sprite(spr, buildings_view.keeper_sprite(b) if not b.is_empty() else "keeper_general")
	elif GameData.sprite_def("objects", o.sprite_id(tick)).has("autotile"):
		apply_autotile_sprite(spr, o.pos, str(GameData.sprite_def("objects", o.sprite_id(tick))["autotile"]))
	else:
		_apply_sprite(spr, o.sprite_id(tick))
	_sync_foliage(spr, o)
	entity_layer.add_child(spr)


## 0.3.9 fences: piece from the same-group fences around, broken by tile hash.
func autotile_piece(p: Vector2i, group: String) -> Vector2i:
	var piece := Autotile.piece_at(p, func(q): return gen.autotile_group_at(q) == group)
	var d := GameData.sprite_def("autotile", group)
	var row := 0
	# 0.3.9.1 run ends: mostly a capped end post, sometimes (~30%) a broken end
	var chance := Autotile.END_BROKEN_CHANCE if piece in [1, 2, 4, 8] else Autotile.BROKEN_CHANCE
	if d.has("broken_row") and Autotile.is_broken(p, chance):
		row = int(d["broken_row"])
	var o := object_at(p) if chunks.has(chunk_of(p)) else null    # 0.3.16 repair props: broken until mended
	if o != null and d.has("broken_row") and o.def().has("repair_quest"):
		row = 0 if o.repaired() else int(d["broken_row"])
	return Vector2i(piece, row)


func apply_autotile_sprite(spr: Sprite2D, p: Vector2i, group: String) -> void:
	spr.visible = true
	spr.texture = GameData.texture("autotile", group)
	var fs := GameData.frame_size("autotile", group)
	var d := GameData.sprite_def("autotile", group)
	spr.hframes = maxi(1, int(d.get("frames", 1)))
	spr.vframes = maxi(1, int(d.get("rows", 1)))
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)
	spr.frame_coords = autotile_piece(p, group)
	spr.set_meta("autotile", group)


## Shopkeepers are drawn with an actor sheet (idle animation, faces right).
func apply_keeper_sprite(spr: Sprite2D, sid: String) -> void:
	spr.visible = true
	spr.texture = GameData.texture("actors", sid)
	var fs := GameData.frame_size("actors", sid)
	var frames := GameData.frame_count("actors", sid)
	spr.hframes = maxi(1, frames)
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)
	if frames > 1 and not spr.has_meta("animated"):
		spr.set_meta("animated", true)
		_animated.append([spr, frames, float(GameData.sprite_def("actors", sid).get("fps", 2))])


func _apply_sprite(spr: Sprite2D, sprite_id: String) -> void:
	if sprite_id == "":
		spr.visible = false
		return
	spr.visible = true
	spr.texture = GameData.texture("objects", sprite_id)
	var fs := GameData.frame_size("objects", sprite_id)
	var frames := GameData.frame_count("objects", sprite_id)
	spr.hframes = maxi(1, frames)
	spr.frame = 0
	spr.offset = Vector2(-fs.x / 2.0, -fs.y)
	if frames > 1 and not spr.has_meta("animated"):
		spr.set_meta("animated", true)
		var fps := float(GameData.sprite_def("objects", sprite_id).get("fps", 3))
		_animated.append([spr, frames, fps])


## 0.3.16 re-draw "repair_quest" props after a quest change (Can We Fix It?).
func refresh_repair_views() -> void:
	for c in chunk_views.keys():
		for o in chunk_views[c].get_meta("objects", []):
			if o.def().has("repair_quest") and o.view and is_instance_valid(o.view):
				if o.view.has_meta("autotile"):
					o.view.frame_coords = autotile_piece(o.pos, str(o.view.get_meta("autotile")))
				else:
					_apply_sprite(o.view, o.sprite_id(tick))


func _refresh_object_view(o: WorldObject) -> void:
	if o.view and is_instance_valid(o.view) and not o.view.has_meta("autotile"):
		_apply_sprite(o.view, o.sprite_id(tick))
		_sync_foliage(o.view, o)


# ------------------------------------------------- 0.3.19 scene polish --
func _index_doors() -> void:
	door_tiles.clear()
	for id in gen.building_order:
		for d in gen.buildings[id].get("doors", []):
			door_tiles[d] = true


## Worn-path weight for one tile. 0 away from roads and doors. Ragged at
## distance 2 so the band is not a hard rectangle. Grass and dirt only.
func wear_amount(p: Vector2i, tile_type: int = -1) -> float:
	var t := tile_type if tile_type >= 0 else gen.tile_at(p.x, p.y)
	if not (t in WorldGen.GRASS_TILES or t == WorldGen.TileType.DIRT):
		return 0.0
	var best := 0.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var dist := maxi(absi(dx), absi(dy))
			if dist == 0:
				continue
			var q := p + Vector2i(dx, dy)
			var road := gen.road_tiles.has(q) or int(gen._town_tiles.get(q, -1)) in WorldGen.ROAD_SURFACES
			if not road and not door_tiles.has(q):
				continue
			var w := 0.72 if dist == 1 else 0.38
			if dist == 2 and gen.hash01(p.x, p.y, 91) < 0.42:
				w = 0.0
			best = maxf(best, w)
	if best > 0.0:
		best *= 0.82 + 0.18 * gen.hash01(p.x, p.y, 92)
	return best


func _ground_material(c: Vector2i, ch: ChunkData) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	var img := Image.create(CHUNK, CHUNK, false, Image.FORMAT_RGBA8)
	var base := c * CHUNK
	for y in CHUNK:
		for x in CHUNK:
			var t := ch.tile_local(x, y)
			var vary := 1.0 if (t in WorldGen.GRASS_TILES or t == WorldGen.TileType.DIRT) else 0.0
			img.set_pixel(x, y, Color(wear_amount(base + Vector2i(x, y), t), vary, 0, 1))
	mat.set_shader_parameter("wear_tex", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("chunk_origin", Vector2(base) * float(tile_px))
	mat.set_shader_parameter("chunk_px", float(CHUNK * tile_px))
	mat.set_shader_parameter("tile_px", float(tile_px))
	return mat


static func foliage_sprite(sprite_id: String) -> bool:
	var s := sprite_id.to_lower()
	if s == "" or s.contains("stump") or s.contains("dead") or s.contains("burnt") or s.contains("log"):
		return false
	return s.contains("tree") or s.contains("palm") or s.contains("bush")


func _sway_material() -> ShaderMaterial:
	if _sway_mat == null:
		_sway_mat = ShaderMaterial.new()
		_sway_mat.shader = SWAY_SHADER
	return _sway_mat


func _sync_foliage(spr: Sprite2D, o: WorldObject) -> void:
	var sid := o.sprite_id(tick)
	if foliage_sprite(sid):
		spr.material = _sway_material()
	else:
		spr.material = null
		spr.modulate.a = 1.0


## Fade a tree/palm/bush crown while the player stands just north of it
## (the sprite draws over them). One call with a large dt finishes the fade.
func _update_canopies(dt: float) -> void:
	var pl = buildings_view.player if buildings_view != null else null
	var step := dt / 0.18
	var keep := []
	var seen := {}
	if pl != null and "tile" in pl:
		var origin: Vector2i = pl.tile
		var cc := chunk_of(origin)
		for cy in range(cc.y - 1, cc.y + 2):
			for cx in range(cc.x - 1, cc.x + 2):
				var root = chunk_views.get(Vector2i(cx, cy))
				if root == null:
					continue
				for o in root.get_meta("objects", []):
					if not (o is WorldObject) or o.view == null or not is_instance_valid(o.view):
						continue
					if not foliage_sprite(o.sprite_id(tick)):
						continue
					var dx: int = absi(int(o.pos.x) - origin.x)
					var dy: int = int(o.pos.y) - origin.y
					var cover: bool = dy >= 1 and dy <= 2 and dx <= 1
					var target: float = CANOPY_ALPHA if cover else 1.0
					if absf(o.view.modulate.a - target) > 0.001:
						o.view.modulate.a = move_toward(o.view.modulate.a, target, step)
					if o.view.modulate.a < 0.99:
						keep.append(o)
						seen[o.get_instance_id()] = true
	for o in _canopy_fade:
		if not is_instance_valid(o) or seen.has(o.get_instance_id()):
			continue
		if o.view and is_instance_valid(o.view) and o.view.modulate.a < 0.99:
			o.view.modulate.a = move_toward(o.view.modulate.a, 1.0, step)
			if o.view.modulate.a < 0.99:
				keep.append(o)
	_canopy_fade = keep


# ---------------------------------------------------------------- minimap --
func minimap_texture(c: Vector2i) -> ImageTexture:
	if _mini_tex.has(c):
		return _mini_tex[c]
	var ch := get_chunk(c)
	var img := Image.create(CHUNK, CHUNK, false, Image.FORMAT_RGBA8)
	for ly in CHUNK:
		for lx in CHUNK:
			img.set_pixel(lx, ly, region_tinted(c * CHUNK + Vector2i(lx, ly), ch.tile_local(lx, ly)))
	for o in ch.objects.values():
		var lp: Vector2i = o.pos - c * CHUNK
		var t: String = o.def().get("type", "")
		var col := Color(0.2, 0.35, 0.15)
		if t == "bank" or t == "exchange" or t == "station":
			col = Color(1.0, 0.85, 0.3)
		elif o.def().get("skill", "") == "mining":
			col = Color(0.55, 0.55, 0.6)
		elif o.def().get("skill", "") == "angling":
			col = Color(0.8, 0.95, 1.0)
		elif t == "shop" or t == "display":
			col = Color(1.0, 0.85, 0.3)
		elif t == "prop" or t == "scenery":
			continue
		img.set_pixel(lp.x, lp.y, col)
	# 0.3.0 building footprints: roof colour, door marked
	for id in gen.building_order:
		var b: Dictionary = gen.buildings[id]
		var r: Rect2i = b["rect"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var q := Vector2i(x, y) - c * CHUNK
				if q.x < 0 or q.y < 0 or q.x >= CHUNK or q.y >= CHUNK:
					continue
				var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
				var col2 := Color(str(b["roof"])).darkened(0.35 if edge else 0.0)
				if Vector2i(x, y) in b["doors"]:
					col2 = Color("#f8f0d8")
				img.set_pixel(q.x, q.y, col2)
	var tex := ImageTexture.create_from_image(img)
	_mini_tex[c] = tex
	return tex


## 0.3.10 minimap / map colour of a tile, tinted by its lore region on open ground.
const REGION_TINT := 0.22
var _tint_cache: Dictionary = {}

func region_tinted(p: Vector2i, t: int) -> Color:
	var col := GameData.tile_color(t)
	if not (t in WorldGen.GRASS_TILES or t in [WorldGen.TileType.DIRT, WorldGen.TileType.ROCKY, WorldGen.TileType.MARSH, WorldGen.TileType.SAND]):
		return col
	if gen.region_map == null or gen.in_town(p):
		return col
	var rid := gen.region_map.region_at(p)
	if not _tint_cache.has(rid):
		_tint_cache[rid] = Color(str(gen.region_map.def(rid).get("minimap_tint", "#ffffff")))
	return col.lerp(_tint_cache[rid], REGION_TINT)


# --------------------------------------------------------------- world map --
const MAP_STEP := 5                  # tiles per map pixel
var _map_tex: ImageTexture = null


## Whole-continent map (1 px = MAP_STEP tiles), roads and towns drawn on top.
## Built once per session from the seed (no chunk data needed).
func world_map_texture() -> ImageTexture:
	if _map_tex:
		return _map_tex
	var b := gen.bounds()
	var w := int(b.size.x / MAP_STEP)
	var h := int(b.size.y / MAP_STEP)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ocean := Color("#1d4a66")
	for py in h:
		for px in w:
			var x := b.position.x + px * MAP_STEP + MAP_STEP / 2
			var y := b.position.y + py * MAP_STEP + MAP_STEP / 2
			var t := gen.tile_at(x, y)
			var col := region_tinted(Vector2i(x, y), t)
			if t == WorldGen.TileType.WATER and gen.land_value(x, y) < WorldGen.OCEAN_LEVEL:
				col = ocean
			img.set_pixel(px, py, col)
	for p in gen.road_tiles.keys():
		var q: Vector2i = (p - b.position) / MAP_STEP
		if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
			img.set_pixel(q.x, q.y, Color("#e0c080"))
	for id in gen.towns.keys():
		var c: Vector2i = (gen.town_center(id) - b.position) / MAP_STEP
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q2 := c + Vector2i(dx, dy)
				if q2.x >= 0 and q2.y >= 0 and q2.x < w and q2.y < h:
					img.set_pixel(q2.x, q2.y, Color("#f8f0d8") if maxi(absi(dx), absi(dy)) < 2 else Color("#3a2a18"))
	# 0.3.0 building footprints (roof colour) over the town marker
	for bid in gen.building_order:
		var bd: Dictionary = gen.buildings[bid]
		var br: Rect2i = bd["rect"]
		for y in range(br.position.y, br.end.y, 2):
			for x in range(br.position.x, br.end.x, 2):
				var q3: Vector2i = (Vector2i(x, y) - b.position) / MAP_STEP
				if q3.x >= 0 and q3.y >= 0 and q3.x < w and q3.y < h:
					img.set_pixel(q3.x, q3.y, Color(str(bd["roof"])).darkened(0.2))
	_map_tex = ImageTexture.create_from_image(img)
	return _map_tex


func map_pixel(p: Vector2i) -> Vector2:
	var did := den_at(p)
	if did != "":
		p = gen.den_entrance(did)   # 0.4.2 below ground: shown at the rat hole on the surface map
	return Vector2(p - gen.bounds().position) / MAP_STEP


## 0.4.2 den layout map (1 px = 1 tile of the authored rows), for the map panel inset.
var _den_tex: Dictionary = {}


func den_map_texture(did: String) -> ImageTexture:
	if _den_tex.has(did):
		return _den_tex[did]
	var dd: Dictionary = gen.dens.get(did, {})
	var inner: Rect2i = dd.get("inner", Rect2i())
	var img := Image.create(maxi(1, inner.size.x), maxi(1, inner.size.y), false, Image.FORMAT_RGBA8)
	var wall := GameData.tile_color(WorldGen.TileType.DEN_WALL)
	var flo := GameData.tile_color(WorldGen.TileType.DEN_FLOOR).lightened(0.25)
	for y in inner.size.y:
		for x in inner.size.x:
			var t := gen.tile_at(inner.position.x + x, inner.position.y + y)
			img.set_pixel(x, y, wall if t == WorldGen.TileType.DEN_WALL else flo)
	var tex := ImageTexture.create_from_image(img)
	_den_tex[did] = tex
	return tex


# ------------------------------------------------------------------- save --
func to_save() -> Dictionary:
	var d := {}
	for p in depleted.keys():
		d["%d,%d" % [p.x, p.y]] = int(depleted[p]) - tick   # remaining ticks
	return {"seed": gen.world_seed, "depleted": d, "ground": ground.to_save(tick)}


func from_save(d: Dictionary, now_tick: int) -> void:
	depleted.clear()
	ground.from_save(d.get("ground", []), now_tick)
	var dep: Dictionary = d.get("depleted", {})
	for k in dep.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() == 2:
			depleted[Vector2i(int(parts[0]), int(parts[1]))] = now_tick + int(dep[k])
	for ch in chunks.values():
		for o in ch.objects.values():
			o.depleted_until = int(depleted.get(o.pos, 0))
			_refresh_object_view(o)


## restyle r7: wall towers are wall-atlas junction frames on thin-wall cells (y-sorted).
## 48x96 frames painted by the wall heightfield painter; the frame stores only the pixels
## that differ from the walls-only render for that exact 25-bit wall key.
const TOWER_FW := 48
const TOWER_FH := 96
const TOWER_FOOT := 76                 # ground under the drum centre (cell top 56 + 8 + drop 12)
const TOWER_CELL := Vector2(16, 56)    # wall cell top-left inside the frame
const TOWER_NB := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
static var _tower_lut: Dictionary = {}
static var _tower_mask_lut: Dictionary = {}


static func _load_int_lut(path: String, into: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			into[int(k)] = int(d[k])


## Frame index for a tower on wall cell key `key` (exact key, then 8-neighbour mask).
static func tower_frame(key: int) -> int:
	if _tower_lut.is_empty():
		_load_int_lut("res://assets/sprites/tiles/walls_diag/tower_atlas_lut.json", _tower_lut)
		_load_int_lut("res://assets/sprites/tiles/walls_diag/tower_mask_lut.json", _tower_mask_lut)
	if _tower_lut.has(key):
		return int(_tower_lut[key])
	var m := 0
	for i in 8:
		var d2: Vector2i = TOWER_NB[i]
		if key & (1 << ((d2.y + 2) * 5 + d2.x + 2)):
			m |= 1 << i
	return int(_tower_mask_lut.get(m, -1))


func _build_wall_towers() -> void:
	for p in gen.wall_tower_cells():
		var wk: Array = gen.wall_key(p)
		if wk.is_empty():
			continue
		var fi := tower_frame(int(wk[1]))
		if fi < 0:
			continue
		var tex: Texture2D = load("res://assets/sprites/tiles/walls_diag/%s_tower_atlas.png" % str(wk[0]))
		if tex == null:
			continue
		var at := AtlasTexture.new()
		at.atlas = tex
		var cols := tex.get_width() / TOWER_FW
		at.region = Rect2((fi % cols) * TOWER_FW, (fi / cols) * TOWER_FH, TOWER_FW, TOWER_FH)
		var s := Sprite2D.new()
		s.name = "WallTower_%d_%d" % [p.x, p.y]
		s.centered = false
		s.texture = at
		s.position = Vector2(p * tile_px) - TOWER_CELL + Vector2(0, TOWER_FOOT)
		s.offset = Vector2(0, -TOWER_FOOT)
		entity_layer.add_child(s)
