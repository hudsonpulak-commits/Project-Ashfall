# AshFall 0.3.13 (versionCode 29): Fenhollow v1

Fenhollow is rebuilt as a marsh town from the designer's Fenhollow v1 set (art_handoff/towns/fenhollow, copied to assets/sprites/towns/fenhollow). The generator is tools/world/build_fenhollow_v1.py.

## Town
- The town is 74x60 tiles (it was smaller). It uses the designer's own preview layout and seeds, centred on the old town centre.
- **Palisade.** A continuous wooden palisade rings the town, with 4 wooden gatehouses (N, S, E, W) and watchtowers on the ring. The gatehouse roofs fade when you walk under them. The cliffs and the diagonal-gap rule are kept.
- **Streets and boardwalks.**
  - Winding mud lanes with no grid; the mud is a shade or two brighter than the buildings.
  - Raised boardwalks cross the creek and the pools.
  - Doorway spurs connect every door to a lane.
- **Buildings.** There are 17 buildings from 16 designer designs, and every one is walk-in, with the upper storeys and roof fading as you enter. The roles below keep their old ids, names and keepers:

  | Role | Design |
  |---|---|
  | Church | fh_church |
  | Kell's lodge | fh_kell_lodge |
  | Guard post | fh_guard_post |
  | Bank | fh_bank, 2 chests |
  | General store | fh_general_store |
  | Blacksmith (swords) | a flipped fh_kell_lodge forge hall, with furnace and anvil |
  | Cook house | fh_cookhouse |
  | Player shop | fh_player_shop |
  | Helmets | fh_smithy |
  | Archery | fh_house_12 |
  | Homes | 7 houses |

- **Props.** About 240 designer props: reeds, barrels, crates, drying racks, fish traps, carts, rope coils, lantern poles, stilts, rowboats and mud puddles. There are also 5 reed beds, 4 fishing spots, ash and alder trees, the exchange board, a workbench, a training dummy, shop signs and the town sign.
- **New players** start beside Kell, outside his lodge by the south gate.
- **Guards and citizens.** 2 guards stand at each gate and 4 patrol inside. 6 citizens wander the town.

## World
- The 2 chicken camps and 2 slime camps that fell inside the larger town were moved outside the palisade (data/enemies.json).

## Engine
- Art buildings take an `inset_x` canvas offset (buildings_view.gd). Fenhollow's plans use an invisible 1-tile collision rim, which gives the interiors room.

## QA
- New src/tests/patch0313_tests.gd:
  - **Palisade ring walk:** a collision flood is sealed with the gates shut and opens through each of the 4 gates. The generator's visual ring walk casts 1315 rays, with 0 gaps.
  - Gate roof fades.
  - Roles and designs.
  - Every open door is reachable from the spawn.
  - Roof fades inside buildings.
  - The spawn is beside Kell.
  - The gate passages are safe.
- **Older tests adapted to the inset ring:**
  - perimeter and gate sampling in the walled-city tests;
  - the gateway-rat test now runs at Cinderholt;
  - the Highfen roof count is limited to Highfen;
  - the LOS wall test accepts art walls;
  - the hatchet test uses an ash tree;
  - the furnace and hearth tests allow 80 ticks for the longer walks.
- Selftest result: 907/907.

## Saltmere v3 (tools/world/build_saltmere_v3.py)
- Designer Saltmere v3 swapped in (copied to assets/sprites/towns/saltmere; art_handoff untouched).
- Quay corner pieces (nw/ne/sw/se), knee-brace inner pieces where piers leave the quay, ladder pier tips.
- 14 sm3_* dock props on the quay and pier fingers; v3 town sign by the west road.
- Harbour entrance arch over the north road (walk-through passage, pillars block, roof fades).
- Elijah's tomb (saltmere_elijah_tomb).
- The smith moves out of the warehouse into v3_smithy_large (furnace + anvil fully indoors). The warehouse is now just the Salt Warehouse.
- v3 galleon, sloops and the larger 40x20 rowboats.

## Highfen v4 (tools/world/build_highfen_v4.py)
- Street plan per preview_v4: outer ring road dropped; the 60/120-degree spokes replaced by inner spokes at 30/150/210/330.
- v4 guild, cookhouse (Hob's bakery), player shop, smithy (new: Highfen Forge, a working forge with a furnace and anvil) and general store, replacing guild_knights, v3_cookhouse, shop_smith and shop_general per manifest_v4.
- v4 knight statue on the plaza, banners flanking civic doors, wall banners on the inner city wall beside each gate, v4 lamp posts on road verges, v4 trees for fill.
- Player-house yard stations now placed on a checkerboard so none is boxed in.
- Wall ring QA: 1496 samples, 0 gaps, 4 gates. Reachability: 0 fails.
- Test change: patch0311 "relocated inside the city wall" radius widened from 17 to 26 tiles. The larger v4 buildings fill the band freed by the dropped ring road; 26 is still inside the wall.

Selftest: 939/939 (also fixed 3 latent SCRIPT ERRORs the release gate rejects: no-counter shop tap, gate-standing Fenhollow guards, no-keeper first house).

## QA fixes (0.3.13)
- Fenhollow buildings: a tile now counts as walk-in floor only when at least 160 of its 256 px are drawn floor (it was 24). Before this, the top row of the forge hall, which is mostly outside the drawn floor, could be walked on. The furnace, anvil and keeper stood above the back wall, and the wall drew over the player's head.
- QA bot: the walk and gear legs now run on a properly clear patch. The old search found no clear patch within radius 70 of the dense Fenhollow spawn, so the legs ran through crates and racks.

## Bridge / boardwalk corner holes (0.3.13)
- Cause: `assets/sprites/towns/fenhollow/tiles/fh_boardwalk_autotile.png` — every one of its 16 frames has a 2x2
  transparent rounded corner. On wide (2+ tile) decks the four corners meet at every tile seam and leave a 4x4 hole.
- Fix (builder-time, the art file is untouched): `build_fenhollow_v1.py render_ground` fills a corner from the board
  2 px inward when both sides join and the diagonal tile is boardwalk too (L-bends keep their inner notch).
  300 corners filled across 153 boardwalk tiles; ring QA still 0 gaps.
- Audited clean: tiles/bridge.png, tiles/planks.png, tiles/boardwalk.png, transitions/boardwalk.png, transitions/planks.png,
  autotile/moat_border(.png/_corners.png), saltmere docks/dock_planks_autotile.png, v2_dock_join.png, v3_pier_end_s.png.

## Sound effects (0.3.13)
- New autoload `Sfx` on its own "SFX" bus with its own volume (Settings > Sound effects volume, user://settings.cfg
  [audio] sfx). Music player and fades unchanged.
- mining_tick: each pickaxe swing; mining_ting_rock: ore obtained; axe_solid: each woodcutting (forestry) chop;
  damage_hit: only when the player takes >0 damage; anvil_ting_high: each anvil smithing strike;
  furnace_low: looped while smelting at a furnace (stops ~1.5 s after smelting stops).
- Hooks `Sfx.npc_hit(humanoid)` -> npc_hit_humanoid / npc_hit_creature: no-ops until those .ogg files are added.
