# Fenhollow (AshFall stage 2): marsh town set, v1

The tiles are 16 px, in the same dark layered style as Highfen v3.1 and Saltmere v2, with a greener, more desaturated marsh grade (`townlib_fh.grade`).
To regenerate: `python3 src/gen_fenhollow.py && python3 src/preview.py` (the preview exits 1 if a building touches a path, boardwalk, water or palisade).

## Layout
- **buildings/**: 20 unique layered buildings, each with `<n>_floor` (furniture), `<n>_walls` (doorway gap), `<n>_upperN` and `<n>_roof`.
  - The upper storeys and roof are the fade group (see `manifest.json` `fade_group` and `roof_tiles`).
  - Civic: church, bank, general_store, smithy, cookhouse (oven), player_shop, kell_lodge, guard_post. Houses: fh_house_01..12.
  - Roofs are thatch (`th`) and reed (`rk`); the bank is a flat stone roof.
- **tiles/**:
  - Ground:
    - `fh_diag_marsh_bank`: marsh grass over water, with a reed and wet-mud edge.
    - `fh_diag_mud_path`: 1-2 shades brighter than the wattle and timber walls.
    - Both are 45deg corner autotiles: frame = NW1|NE2|SE4|SW8.
    - `fh_water_deep/shallow_4f`, plus fills.
  - Palisade:
    - `fh_diag_palisade`: 16x30 frames, a stake top plus a 14 px log face. It covers the straight, corner and 45deg cases.
    - `fh_palisade_watchtower`: 48x80.
  - Boardwalk: `fh_boardwalk_autotile`, 16x20 frames with edge mask N1|E2|S4|W8. It covers ends, straights, bends, tees and the cross, with posts below the open edges.
  - Wooden layered gates:
    - Views: `fh_gate_front` (S gate), `fh_gate_back` (N gate) and `fh_gate_side` (E/W gates).
    - Layers: `_floor` (passage), `_walls` (towers and pillars) and `_roof` (the fade group).
  - `named/`: every autotile frame as a separate file.
- **props/**: reeds a/b/c, fish trap, rope coil, lantern pole, barrel, crates, drying rack, rowboat, stilts, 4 shop signs, the town sign, cart and mud puddle.
- **preview_fenhollow_scene_3x.png**: the whole palisaded town.
  - The S gate roof is cut away, with the player in the passage.
  - Guards stand at every gate.
  - Kell (a red-tinted citizen placeholder) stands at his lodge door; the lodge is cut away. It is by the S gate, where new players start.
- **contact_sheet_3x.png**: every layer, gate, tile, named frame and prop.

## Palisade continuity
The ring is a 4-connected band at least 2 vertices thick. Gate runs are straight right up to each passage, and the E/W runs are tied back onto the ring with connectors. Saddle frames (5 and 10) are removed, so only edge, full and inside/outside 45deg corner frames occur. Watchtowers snap onto full wall tiles. The exact rule is under `palisade.continuity_rule` in manifest.json.

## Door clearance and spur paths (v1.2)
- Each building needs about 44 px (roughly 2.75 tiles) of dry ground in front of its door: no water, no boardwalk, no wall, and no other building within ±8 px. That ground must also link to a road over dry land. Buildings that fail this are moved.
- Every door gets a narrow mud spur, drawn after the building-clearance check. The route is found with a BFS over dry land on a 4 px grid that avoids buildings, aiming for the nearest main road. It is then loosened into a jittered polyline and rendered with corner autotiles, so diagonals come out at 45°.
- Palisade ring: a 1-tile log band from the boundary of the ellipse plus a 1-vertex outer dilation, then de-saddled so there are no gaps.
