
## 0.3.16 (versionCode 33): sprite-bot art integrated

- **Millbrook rebuilt from villages/v1** (`tools/world/build_millbrook_v1.py`, sources copied into `assets/sprites/towns/villages/millbrook/`; the hand-off folder is untouched). The village is now an 84x60 designer layout at origin [143,-146] (the old site sat between two lakes): 18 walk-in buildings (inn, windmill with turning 4-frame sails, rat barn, granary, cowshed, two farmhouses, ruined chapel, ten cottages), each with floor / walls with door gap / upper+roof fade layers and its own `_night` window layer (no legacy window overlay). Brightened worn dirt roads, a meadow ground decal with a noise-faded natural edge, millpond, 5 fenced wheat farms and a cow pasture, wells/quern/hearth, bounty board, signs, sacks and scattered props.
- Odric the Hunter and Quartermaster Hale use their v1 NPC sprites.
- Old Mabel stands by the rat barn door; the giant-rat nest, the Rat hole (rat_den site) and the Rat Mother moved just south of the village, below the barn. The Goblin Warlord camp moved to the hills north of Millbrook (quest text updated); two slime camps moved to stay by the village. All through data (quests.json / enemies.json).
- **Rat Mother**: real 48x48 underground v1.1 sheet (4-frame walk, 4 facings) with the fungal glow layer composited in; no more scaled/tinted giant rat. Bite strips exported for later.
- **Rat hole** uses `den_entrance_3x2_trans.png`.
- Underground v1.1 tiles, den, rat_mother and overworld art copied to `assets/sprites/underground/` ready for 0.3.17 (the underworld plane and the den interior are not built yet).
- Engine: BuildingsView fade layers support `frames`/`fps`; quest sites block road routing (a rerouted road crossed Garrow's paddock); village tests measure from the village rect; lower region anchor added for the new site.
- QA: new `millbrook` scenario (gate, green, mill, inn interior, rat barn, fields, night, Rat Mother, den entrance).

### Map Tester fixes (2026-10-23 report)

- Fenhollow: the barrel at 11,-29 is gone; the pocket near 6,-36 is reachable (pathfinding test).
- Cinderholt: the crates at 296,-185 are gone; the sealed pocket near 296,-200 opens (pathfinding test).
- The old orange cottage night-window overlay is retired everywhere (`DayNight.window_tiles` only lights stained glass); the six unlayered cottages in Barrowby (149,135 / 164,135 / 164,127) and Oxley (277,-26 / 292,-26 / 292,-18) no longer get it.
- Night layers for the Saltmere blacksmith (319,150) and Elijah's Tomb (262,128); the tomb stays 4x4 (approved exception).
- Lone diagonal-only cliff stubs (no orthogonal cliff neighbour, exactly one diagonal one) become ground; 360,41 fixed; a scan test covers cliff_lip.

### Movement smoothness

- Chunk data is generated on a worker thread (own WorldGen), prefetched in a radius of 4 chunks plus 3 ahead in the walking direction; it also hands over the cliff-ramp cell analyses.
- Chunk views are built time-sliced (4 ms/frame: tile rows, overlay thirds-of-rows, objects 16 at a time), filled in the tree while hidden, aborted if left behind.
- Nothing generates far chunks on the main thread any more: roof hiding, shop displays, keepers, quest-giver labels and off-screen AI placement (gather/activity/adventurer spots) only look at loaded chunks.
- AI views get a per-tick time budget (rotating order), so a town full of NPCs doesn't path all at once.
- QA: new `perf` scenario sprints Fenhollow → Highfen → Millbrook → Highfen → Oxley (581 tiles, 18 chunks) and gates (C36) on per-frame game work ≤ 33 ms; wall frame times are reported too.
