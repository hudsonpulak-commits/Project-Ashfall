# AshFall 0.3.9 (versionCode 19)

## Fences and walls: autotiling
- New `src/world/autotile.gd`: piece = N1|E2|S4|W8 (post, end caps, straights, corners, T-junctions, 4-way) plus 45-degree '/' and '\' diagonals when nothing joins orthogonally.
- Rural fences (pen fences, road fences) draw from `autotile/fence_rural` (18 pieces x 2 rows); about 15% are broken/deteriorated, picked deterministically by a seed-independent tile hash. City walls get autotiled wall-top caps (`autotile/wall_<family>`) and never break.
- Millbrook's paddock gets a divider fence (T joint at the rim, end cap with a gap), so T pieces appear in the world.

## Floor transitions
- Priority-based blob overlay: where unlike floors meet (grass, dirt, path, dirt/stone road, sand, ash, marsh, planks/floor/boardwalk/stone floor, cobble...), the higher-priority floor spills onto its neighbour with edge + corner frames (256-frame sheets in `assets/sprites/transitions/`). Up to 2 overlays per tile; water, walls and the moat never blend.
- Performance: overlay cells are computed once when a chunk view is built, into at most 4 extra batched TileMapLayers per chunk (empty layers freed).

## Four-way facing
- Facing now has a direction: moving mostly up shows the back sheet, down the front, left/right the side (mirrored for left). Applies to the player, AI players, NPCs/guards and enemies. Gear layers switch sheets with the body.
- Every actor and gear sheet has `_front` / `_back` placeholder sheets with the same walk frames (`dir_paths` in sprites.json).

## Roads
- Road fences run parallel to their road (vertical roads -> vertical lines, horizontal -> horizontal) and use the corner/T/4-way/broken pieces. They still block walking, arrows still fly over, and they keep 4 tiles clear of road junctions.

## Highfen moat
- The moat border autotiles (straight, corner, T, 4-way banks) with stone bridge-join piers next to the bridges.

## Title screen
- Hudson's title art is in the data-driven slot `ui/title_bg` (`assets/ui/title_bg.png`, 941x1672, quantized to 256 colours: 2.3 MB -> 0.9 MB, pixel look kept), cover-scaled with the aspect kept. The menu's own "AshFall" label is hidden (the art carries the logo) and the buttons sit low over the dark foreground. Without the file the old menu background and label come back. The name stays AshFall.

## Art
- All new art is swappable placeholder pixel art made by `tools/art/placeholders_039.py` and registered in data/sprites.json and tools/art/aseprite_manifest.json.

## Tests
- Unit: new `src/tests/patch039_tests.gd` (mask -> piece, diagonals, broken share, transition frames and priorities, moat/wall overlay cells, pen corner, road fences parallel + junction gaps, facing up/down/left/right, player body + gear switch to the back sheet, title slot).
- QA: new `autotile` scenario + C31 checks (frames: fence_corner_t, road_fence_vertical, road_fence_horizontal, transitions, moat_corner, player_walk_up_back). Ghost/facing checks now know the front/back sheets; the PK finish step moves both fighters into the Scorch when they start on its edge.
