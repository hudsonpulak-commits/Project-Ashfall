# 0.3.14 (versionCode 30)
- Cinderholt redesign (designer ch_ set, tools/world/build_cinderholt_v1.py): basalt wall ring with towers, N/S/E/W gates, brightened ash + cobble roads (lum 59.9/62.6 vs buildings 44.1), organic street plan, 30+ walk-in buildings with fading roofs, forge district, props.
- Northern Guard camp (ng_ set) on the plateau just north of Cinderholt (Lore_2026-10-21), reached by cliff stairs; palisade with W gate, command tent, barracks, tents, watchtower, training yard, campfire, wagons, racks, banners, torches. New enemies northern_guard (lv30) and northern_soldier (lv35, heavier armour).
- Cinder cliff ridge, straight, no diagonal gaps. Town shifted 12 tiles south to stay clear of the Scorch; Cinderholt Pits moved to (342,-141); nearby chicken/slime/wolf camps nudged to keep their bands.
- Wall-ring QA for town + camp (ray walk, flood sealed/open per gate, diag gaps); patch0314_tests.
- Night: the legacy glowing window overlay is no longer drawn on any layered-art building (Highfen, Saltmere, Fenhollow, Cinderholt, camp); only the art's own windows.
- Screenshot flag --night.
- SFX: armour_clang hook on every 0-damage hit (block/miss) involving the player (player hit, or player/AI-player hitting an NPC), playing Hudson's sword_ting (assets/audio/sfx/armour_clang.ogg).
- Fenhollow: organic shoreline all round the town (no water at the rect edge, noisy marsh bank), dithered fade into world grass, mud landings with posts and reeds at boardwalk ends, grass thinning to mud by the palisade.
