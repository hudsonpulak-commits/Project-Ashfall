# Saltmere (tropical port): stage 2 town art set, v1 for review

This set is drawn at the current game scale: 16 px tiles. It uses the AshFall palette plus tropical additions: sand `sa0-3`, turquoise water `tq0-4`, terracotta `tc0-2` and whitewash `wh`.
Every output goes through `grade()`, which applies a slightly lighter desaturation than Highfen's (about 24 %, about 7 % darker). Tropical colours stay muted but still read.

To build everything, run `python3 src/gen_saltmere.py && python3 src/preview.py`.
`src/townlib.py` is the shared Highfen v2 building and prop library, extended with:
- `wash` walls
- `bl` (blue) and `tc` (terracotta) roofs
- `crenel` and `flat` roofs for the fort

## Buildings: same layer rules as Highfen v2
All layers share **one canvas and one origin**:
- `<name>_floor.png`: the ground interior and furniture
- `<name>_walls.png`: the ground walls, with an 8 px doorway gap at `door_px`
- `<name>_upper1..N.png`: one per upper storey
- `<name>_roof.png`

Everything in `fade_group` (all the upper storeys and the roof) fades together while the player is inside.
For each building, `manifest.json` gives:
- `storeys`, `layers` and `fade_group`
- `footprint_origin_px`: the ground footprint starts at `[0, E]`, where E is the headroom for upper storeys and towers
- `door_px` and `door_tile`
- `roof_tiles`

| building | tiles | storeys | look |
|---|---|---|---|
| house_wash_round | 3×3 | 1 | Round whitewash house, blue roof |
| house_wash_l | 4×3 | 2 | L-shaped whitewash house, blue roof |
| house_terracotta_narrow | 2×4 | 2 | Narrow townhouse, terracotta roof |
| house_balcony | 5×3 | 2 | Stepped front with a rounded wing, blue roof |
| house_timber_corner | 4×3 | 1 | Notched timber house, terracotta roof |
| house_hillside | 3×4 | 2 | Stacked hillside house, blue roof |
| tavern_black_anchor | 6×4 | 2 | Timber facade with a round end wing, 2 chimneys. The hanging sign is `props/sign_black_anchor` |
| smithy | 4×3 | 1 | Stone forge with a lean-to and a chimney |
| harbourmaster | 4×4 | 2 | Whitewash office with a round lookout turret |
| warehouse | 7×4 | 1 | Long timber store full of barrels and chests |
| governor_mansion | 9×6 | 3 | Symmetrical wings, marble floor, red rug, terracotta roof |
| fort_bastion | 8×7 | 2 | Stone bastion with 4 round corner bastions and a flat crenellated top. Cannons and a flag are props placed on top |
| lighthouse | 2×2 | 4 | Whitewash tower plus a lantern drum |
| church | 4×6 | 2 | Cross plan with a bell tower |

## Terrain (`terrain/`)
- **Autotile strips** (16 frames × 16 px, frame index = mask N1|E2|S4|W8, where a bit means that neighbour is the same terrain):
  - `sand_to_water` (with a foam line)
  - `sand_to_grass`
  - `shallows_to_deep`
- **Base tiles:** `sand`, `grass_tropical`.
- **4-frame ripple strips** (64×16): `water_deep_4f`, `water_shallow_4f`.
- **`channel_winding_v`** (3×6 tiles): a winding water channel with sand banks.

## Paths (`paths/`)
Worn cobble and sand-path decals, each with:
- 3×3-tile quarter curves (`*_curve_ne` / `*_curve_sw`)
- S-bends (`*_sbend_v` 2×4, `*_sbend_h` 4×2)

## Docks (`docks/`)
- **`dock_planks_autotile`**: 16 frames, 16×20 px. The planks fill 16×16 and the bottom 4 px are pilings drawn on frames with an open south edge. It has edge beams, post caps on outer corners, and salt and moss stains.
- **Posts:** `dock_post` 6×16, `dock_ladder` 8×16, `mooring_post` 10×12.

## Props (`props/`, bottom-centre anchor)
- **Cargo:** barrel, barrel_stack, crate, crate_stack, crate_broken.
- **Harbour gear:** net_hanging, rope_coil, anchor, cannonballs, fish_rack.
- **Cannons:** cannon_side, cannon_front.
- **Town:** lamp_post, stall_fruit, stall_fish, stall_spice, cart, well, bench, debris, puddle.
- **Flags:** flag_pirate, flag_governor.
- **Signs:** sign_black_anchor (hanging, 20×18).
- **Plants:** palm_tall and palm_lean (24×40), palm_small (20×28), bush_tropical_a and bush_tropical_b.

## Ships (`ships/`, 3/4 side view, the bottom of the PNG is the waterline)
- **`ship_galleon`** (136×108): dark hull, gun ports, three masts of ragged black square sails, pirate flags.
- **`ship_sloop`** (80×72): fore-and-aft mainsail and jib, governor flag.
- **`rowboat_1-3`** (24×12): empty, with oars, and with cargo.

## Review files
- **`preview_saltmere_harbour_3x.png`** shows:
  - open sea along the south and a **winding channel** into the harbour basin, with no town wall
  - a plank quay with two piers, plus a jetty across the channel
  - the galleon moored at the quay, a sloop at the pier, another sloop and rowboats
  - a winding cobble harbour street, a hill lane and a market loop
  - sand paths to the beach, the lighthouse and the fort on the east headland (cannons and flag)
  - houses, the tavern (with its sign), the smithy, harbourmaster, warehouse, church and palms
  - the **governor's mansion (3 storeys) drawn cut away**, with its upper floors and roof hidden
- **`src/preview.py`** places buildings with an occupancy search. It **exits 1** if any building pixel (all layers, full height) overlaps a road, path or water pixel. The current result is 0 overlaps across 24 buildings.
- **`contact_sheet_3x.png`**: one labelled block per building (assembled, then each layer, with fade layers marked), followed by props, docks, ships, terrain and paths.

## v2 (tile-based rebuild; v1 files kept unchanged)
Run `src/gen_saltmere_v2.py` to build the assets, then `src/preview_v2.py` to build the preview. The preview exits 1 if a building touches a road, the water, a dock or the wall, or if a ship touches the land or the quay.
- **45° corner autotiles** (`tiles_v2/`, rules in `src/diagtiles.py`, also stored in manifest_v2.json under `diag_autotiles`)
  - Each 16x16 frame is indexed by which tile corners are inside the terrain: NW=1, NE=2, SE=4, SW=8.
  - Sample the shape on the (H+1)x(W+1) vertex grid. The frame for tile (y,x) is V[y,x] + 2·V[y,x+1] + 4·V[y+1,x+1] + 8·V[y+1,x].
  - 1 corner = an outer 45° diagonal (`diag_out_*`). 3 corners = an inner 45° diagonal (`diag_in_*`). 2 adjacent corners = a straight edge (`edge_*`). 2 opposite corners = a saddle.
  - A 45° run alternates `diag_out` and `diag_in` frames. A straight edge next to a diagonal frame is the straight-to-diagonal transition. This works in all four directions (NE/NW/SE/SW).
  - Sheets: `v2_diag_sand_shore` (with surf foam), `v2_diag_grass`, `v2_diag_cobble`, `v2_diag_sand_path`, and `v2_diag_wall_dark`. The wall sheet uses 16x28 frames: the 12 px stone face hangs into the row below, also on diagonals.
  - Single frames are cut out by name in `tiles_v2/named/`.
  - Layer order: water (`v2_water_*_4f`), then sand_shore, grass, sand_path, cobble, docks (`docks/dock_planks_autotile`, edge mask N1|E2|S4|W8), then wall rows depth-sorted with sprites.
- **Walls**
  - Round tower: `v2_wall_tower_round`.
  - Diagonal tower fits: `v2_wall_tower_fit_diag_ne/nw`.
  - Flush join stubs: `v2_wall_gate_join_w/e`.
- **Layered gatehouses** (`v2_gate_{front,back,side}_{floor,walls,roof}`)
  - `_floor` is the passage cobbles, drawn under characters.
  - `_walls` holds the towers and passage pillars, depth-sorted with characters.
  - `_roof` holds the arch, walkway and battlements. It is the fade group.
  - The passage tiles are listed as `roof_tiles` in the manifest.
  - Which gate to use: front = south gate (outer face), back = north gate (seen from inside the town), side = east/west gate in side profile, with the passage running E-W.
  - The wall runs straight for at least 5 tiles either side of a gate.
- **Buildings** (`buildings_v2/`): 24 unique house designs (v2_house_01..24), each with floor/interior, walls with a doorway gap, upper storeys and a roof. Civic set:
  - tavern, harbourmaster, governor (3 storeys), church
  - fort (3 storeys, crenellated, with towers), lighthouse (6 storeys)
  - 2 warehouses, smithy, rum house
- **Props** (`props_v2/`):
  - Plants: stiffer palms (tall, lean, short, cluster), banana, agave, fern, hibiscus, flowerbed.
  - 9 market stalls.
  - Crates, barrels, well, cart.

### v2 fix: docks join land
- The quay planks abut land directly. Across the dock span, land is filled or cut to the quay line; the shore and land autotiles are not drawn on dock tiles; and the top plank row uses the N-solid mask.
- Abutment overlays are in `tiles_v2/v2_dock_join.png`: a stone coping for cobble, a timber sill for sand roads, each with left/right end blocks.
- A cobble quay apron runs from the harbour road onto the planks, and the west end is a sand road with a timber sill.
- The fort now stands on a rock spit, so its sea wall closes the ring, with an extra sea tower.
- 45deg connectors rejoin the straight gate run to the ring.
- No wall tiles sit under the gate sprite, which fixes the wall row that drew over the N tower.
