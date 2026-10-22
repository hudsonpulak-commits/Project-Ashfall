# Highfen (capital) – stage 2 town art set, v1 for review

Drawn at the current game scale: 16 px tiles, using the AshFall palette (`../../palette.hex`). Everything is made by `src/gen_highfen.py`, and the previews are made by `src/preview.py`.
Run `python3 src/gen_highfen.py && python3 src/preview.py`. Needs numpy, scipy and Pillow.

## Building layers (v2: multi-storey, walk-in, cut-away, no loading screens)
Every building is a stack of PNGs that all share **one canvas and one origin**, so they all go at the same x,y position.
- Canvas size is `px` in `manifest.json`.
- The ground footprint (`tiles` × 16 px) starts at `footprint_origin_px` = `[0, E]`.
- `E` is the headroom above the footprint for the upper storeys and towers: `(storeys-1)×14` px, plus 20 px if the building has towers.
- Tile logic (`roof_tiles`, `door_tile`) is measured from the footprint origin.

| layer file | contents | draw | cut-away |
|---|---|---|---|
| `<name>_floor.png` | Ground interior: floor (planks, flagstone or marble), furniture, door threshold | under actors | always shown |
| `<name>_walls.png` | Ground-storey wall tops, plus the ground front facade with windows. It has a **transparent 8 px doorway gap** at `door_px` | y-sorted with actors | always shown |
| `<name>_upper1.png` … `upperN.png` | One per storey above the ground. Each is that storey's front facade (its own window row), the floor-line beam and its side or top wall. Each one is the footprint shifted up 14 px × k | above actors | **fade_group** |
| `<name>_roof.png` | Roof over the top storey's plan, minus its facade band. Includes chimneys and tower drums or cones | above everything | **fade_group** |

**Fade rule:** while the player is in the doorway or inside, every file in `fade_group` (all the upper storeys and the roof) fades to alpha 0 together over `roof_fade_s`. Only floor and walls stay, which matches the current `buildings_view.gd` roof fade. The difference is that the upper storeys now fade together with the roof.

**Storeys:**
- 1 storey: cottage, longhouse, corner-tower house, smith, general store
- 2 storeys: L-shape, narrow tall, twin gable, crooked, stepped, baker, tavern, church
- 3 storeys plus 2 towers: Guild of Knights
- 4 storeys plus 4 towers: palace

Towers rise one extra drum height above the roof.

**Manifest fields per building:**
- `storeys`
- `layers`, in draw order
- `fade_group`
- `footprint_origin_px`
- `door_px` (the doorway centre x and facade top y on the canvas)
- `door_tile`
- `roof_tiles`

## Look (v2 dark pass)
- **Palette:** all output goes through `grade()` (about 36 % desaturated, about 8 % darker, slightly cool), so greens are muted, stone looks grimy and timber looks weathered.
- **Walls:** soot streaks under windows and eaves, moss at the bases, cracked plaster, patched panels, boarded or lit windows.
- **Roofs:** gently sagging shingle rows, a few missing shingles, a little moss, and calmer shingle contrast than v1.
- **Roads:** uneven worn cobble, a mud verge, puddles, cracks and weeds.
- **New props:** `crate_broken`, `debris`, `debris_b`, `puddle`, `mud_patch`.
- **City wall:** now has a 22 px dressed-stone face with block courses, soot and moss at the base, and crenellations. Gate towers stand at the south gate.

## Props (`props/`, transparent, bottom-centre anchor = feet/base at (w/2, h))
| Size | Props |
|---|---|
| 24×32 | tree_oak_a, tree_oak_b, tree_pine, tree_autumn, statue_knight |
| 16×16 | crate_broken, debris, debris_b, bush_a, bush_b, bush_flowers, barrel, crate, fence_straight, sign_inn, sign_bread, sign_post_road |
| 24×24 | crate_stack, well |
| 32×20 | cart |
| 16×32 | lamp_post, banner_pole |
| 32×16 | fence_curve |
| 16×12 | flowerbed_small |
| 32×12 | flowerbed_long |
| 16×10 / 24×12 | puddle / mud_patch (ground decals, may sit on roads) |
| 32×24 | stall_fruit, stall_cloth, stall_fish |

## Walls and roads
- `walls/city_wall_ring_full.png`: the complete circular wall (inner radius 17 tiles = 272 px, 12 px top, 22 px stone face) with a south gate and two gate towers. The ring centre is at `ring_center_px` in the manifest.
- `walls/city_wall_seg_000…315.png`: eight 45° octant pieces cut from that ring. `manifest.wall_segments[*].offset_from_ring_px` places each one relative to the full ring's top-left.
- `roads/`: four 3×3-tile quarter curves (road_curve_ne/nw/se/sw), two S-bends (2×4 and 4×2) and a 4×4 round plaza.
  - The roads are worn cobble with cracks, weeds and grassy edges.
  - They are decals laid over grass, so roads can bend freely and don't follow the grid.

## Review files
- **`preview_highfen_scene_3x.png`**: dense mock Highfen at 3×. It contains:
  - the round wall with its stone face, and a winding gate road
  - a plaza market (4 stalls, a well, a statue)
  - a loop lane around the palace, an outer ring road and winding tracks
  - 42 buildings, with props along every lane: lamps, barrels, crates, debris, puddles, mud
  - the **Guild of Knights drawn cut away**: its upper storeys and roof are hidden, so the floor, furniture and ground walls show
- Outside-the-wall houses reuse the house set, mirrored on the second use. A unique house per lot would need more house designs.
- **`src/preview.py`** places buildings with an occupancy search. It then runs a **collision check** and **exits 1** if any building pixel, across all its layers and its full drawn height, overlaps a road pixel. The current result is 0 overlaps.
- **`contact_sheet_3x.png`**: one labelled block per building (assembled, then each layer, with fade layers marked), followed by props, wall segments and roads. Labels don't overlap.

## v3 (tile-based walls/roads, reference layout)
- Run `src/gen_highfen_v3.py` to build the assets, then `src/preview_v3.py` to build the preview. The preview exits 1 if any building touches a road.
- `tiles_v3/`: dark-stone wall autotile (16 frames of 16x32: a 16 px walkway on top and a 16 px stone face below; mask N1|E2|S4|W8) with named straight/corner/end/tee cuts, `v3_wall_tower_round` (48x64), `v3_wall_gatehouse` (64x64, passage x20-44), the `v3_cobble_autotile` (16 frames), and cobble fills (plain/worn/cracked/mossy/puddle).
- `props_v3/`: large and small fountains (4 animation frames each), 5 market stalls, trees, hedge, garden bed, veg patch, crates, barrels, round well, cart, bench.
- `buildings_v3/`: 18 house designs (v3_house_01..18) plus richer narrow_tall and longhouse, bank, cookhouse, player house, temple, town hall and keep. Every building has floor (with furniture), walls (with a doorway gap), upper storeys and a roof; the upper storeys and roof form the fade group.
- Data for all of the above is in `manifest_v3.json`. The v2 files are unchanged.

## v3.1 (45° diagonals + layered gates)
Run `src/gen_highfen_v31.py` to build the tiles (it also adds a `v31` block to manifest_v3.json), then `src/preview_v31.py` to build `preview_highfen_v31_scene_3x.png` and `contact_sheet_v31_3x.png`.
- **45° corner autotiles** in `tiles_v31/`: `v31_diag_cobble` (16x16 frames) and `v31_diag_wall_dark` (16x28 frames). They follow the same corner rule as Saltmere v2 (NW1|NE2|SE4|SW8 on the vertex grid; see `src/diagtiles.py`). Named frames are in `tiles_v31/named/`.
- **Walls:** diagonal tower fits `v31_wall_tower_fit_diag_ne/nw` and join stubs `v31_wall_gate_join_w/e`.
- **Layered gates** `v31_gate_front/back/side`, each with `_floor`, `_walls` and `_roof`. The roof is the fade group, and the passage tiles are listed as `roof_tiles`. Use back for the N gate, front for the S gate and side for the E/W gates. The wall runs straight for at least 5 tiles either side of a gate and ends flush under the gate towers.
- **Preview:** the S gate is shown with its roof faded and the player standing in the passage. The town hall is shown cut away.
- The v3 tiles and the flat `v3_wall_gatehouse` are kept for reference. v3.1 supersedes them.

## Ground textures v3 (ground_textures_v3/)
These are drop-in replacements for road_stone, cobble and cobble_dark, in both tiles/ (64x16, 4 variants) and transitions/ (256x256, alpha kept). They are muted grey-brown, with about 62% of the old contrast, darker, and have grime in the mortar, dirt specks, moss in the cracks and a few worn stones. The plaza uses cobble; there is no separate plaza sprite. See before_after_3x.png. To regenerate, run src/gen_ground_v3.py.
