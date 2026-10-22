# AshFall 0.3.12 (versionCode 28): Saltmere v2

Saltmere is rebuilt as an open harbour town using the designer's v2 set (tiles_v2, buildings_v2, props_v2, manifest_v2).

## Town
- There is no fort and no walls. The former gate guards now walk 10 patrol beats, and 5 citizens wander the town. The west and north entrances are open roads.
- White houses with blue roofs (26 houses from the 12 blue-roof designs). The civic buildings are walk-in, and their upper storeys and roof fade when you walk in.
- Every shop, the bank, the church, the NPCs and the quest givers are kept, with the same ids and names:
  - The Blacksmith (maces) is in the v2 warehouse_a, because v2_smithy is too small inside.
  - The Salt Warehouse uses the v2_smithy art.
  - Saltmere Light, kept by Old Wick, stands on the spit.
- Cobble main street, plaza market, harbour street and cross streets. Winding sand lanes round the bay and up the coast.
- The ground decal is brighter than the buildings. Mere biome: palms, beach and tropical grass.

## Harbour
- A plank quay with 3 piers, nets, crates and mooring posts. A sheltered basin with a galleon, sloops and rowboats, and 6 fishing spots.
- The channel is open to the sea and at least 4 tiles wide (6 at its narrowest). A selftest floods the basin out to the ocean.

## World and engine
- Towns can set `cliff_clear`. Saltmere uses 1, so the sea cliffs just south stay intact. `dry_center` keeps the old land centre.
- Gate torches are skipped for towns with `walls: "none"`.
- The chicken camps were moved north out of the new town rect.
- A spot for Elijah's tomb is reserved west of town at (272,160). Nothing is placed there yet.

## Tests
- New `Patch0312Tests`:
  - no walls and no fort;
  - at least 30 art buildings and all roles present;
  - the basin floods to the sea, and the channel is at least 4 wide;
  - every open door is reachable from the spawn (the test skips buildings with no doors instead of crashing);
  - the roof fades;
  - 10 patrols.
- The gate-related world tests exempt open towns.
- Generator: `tools/world/build_saltmere_v2.py`. It checks reachability, road and tile overlap, ship placement and the channel.
