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
- v4 guild, cookhouse (Hob's bakery), player shop, smithy (new: Highfen Forge, anvil only; smithing stays in Fenhollow) and general store, replacing guild_knights, v3_cookhouse, shop_smith and shop_general per manifest_v4.
- v4 knight statue on the plaza, banners flanking civic doors, v4 lamp posts on road verges, v4 trees for fill.
- Player-house yard stations now placed on a checkerboard so none is boxed in.
- Wall ring QA: 1496 samples, 0 gaps, 4 gates. Reachability: 0 fails.
- Test change: patch0311 "relocated inside the city wall" radius widened from 17 to 26 tiles. The larger v4 buildings fill the band freed by the dropped ring road; 26 is still inside the wall.

Selftest: 927/927.
