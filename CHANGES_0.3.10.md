# AshFall 0.3.10 (versionCode 26) - stage 1: lore regions and biomes

Lore source: docs/specs/Lore_2026-10-21.md (Hudson's dated lore file, copied in).

## Regions (data/regions.json + src/world/world_regions.gd)
- Four regions: Cinder (north, Cinderholt; the Scorch is its northern half),
  Central Ashfen (Highfen, Oxley), Lower Ashfen (Fenhollow, Millbrook),
  the Mere Lands (Saltmere, Barrowby). Nearest anchor after a noise warp;
  a 26-tile soft border where the neighbouring region's ground/trees dither in.
- Ground per region: boreal grass + lots of rocky ground (Cinder), plain grass
  + some rocky (Central), lush grass + more marsh (Lower), tropical grass,
  wider beaches, marsh (Mere). Tree density: Mere/Lower forested, Central open.
- HUD: region title fades in on entry + chat line "You enter <region>."
  (Events.region_entered). Minimap and world map tinted by region.
- Towns and villages are NOT moved or redesigned (stage 2).

## Elevation + cliffs
- Terrace levels: Lower/Mere 0, Central 1, Cinder 2, plus local relief noise
  (Cinder most, Central many, Lower a few low bluffs, Mere few + sea cliffs
  behind some beaches).
- cliff_face (south edge: lip + rock face, shadow below) and cliff_lip
  (other edges) block player and AI pathing; cliff_shadow and cliff_stairs walk.
- Reachability: stairs wherever a road/town is within 3 tiles, where cliff runs
  cross a 24-tile gap grid, plus a per-cell flood fill that opens one stair
  into any pocket a basin or knoll would close. No trees/boulders spawn on a
  stair landing. Roads always override cliffs.
- Roads: a road whose A* wandered through a city rect corner is reconnected
  to its gate (keeps "gate to gate" valid).

## Ores by region (data/mines.json, replaces distance tiers)
- Lower: copper + tin (Fenhollow Pits, Fenhollow Hill Pits, new Millbrook Pits).
- Central: copper, tin, iron (new Highfen Quarry, Greyscar Quarry).
- Cinder: iron + dusk ore (Cinderholt Pits/Deeps/Ridge).
- Mere: coal (Saltmere, Eastmere x2, Barrowby, new Westmere).
- Scorch: richest - dusk ore + iron + coal.
- New: dusk_rock (Mining 30) -> dusk_ore; smelt_dusk_steel (dusk ore + coal,
  Smithing 30) -> dusk_steel_bar; forge_dusk_* anvil recipes for the existing
  dusk gear (Smithing 36-42). Dusk gear is still also sold in shops.

## Trees (Forestry)
- Tier 1 everywhere: Tree (old ash_tree, logs renamed "Logs"), new pine and dead trees.
- Oak 15 (alder_tree renamed; Lower + Central), Ash 30 (blackthorn_tree renamed;
  Lower), Spruce 45 (new, Cinder), Mahogany 60 (new, Mere). Object ids kept
  so saves, recipes and the AI economy stay valid.
- Magic mushrooms (Foraging 10): cyan, in damp forest/marsh of Lower + Mere.

## Placeholder art - see docs/ART_TODO_0.3.10.md

## Tools
- tools/gen_art_regions.py (placeholders), tools/render_region_map.py
  (region overview + reachability), export_world_map.gd dumps regions,
  main.gd screenshot --at=x,y.
- Tests: patch0310_tests (regions, borders, elevation order, cliff density
  order, cliffs block + stairs path, ground/trees/mushrooms, dusk steel,
  region HUD, placeholder flags); mine tests rewritten for regions.

## Music (Hudson's new alternative-metal tracks, 2026-10-22)
Converted from /Game/Game music mp3s to Ogg Vorbis 112 kbps 44.1 kHz stereo
(assets/music/), replacing the old files of the same slot. Title unchanged.
- ambient (day wilds, rotates): ambient.ogg = ambiant day 1, ambient_2.ogg = ambiant day 3
- ambient_night: ambiant night 2
- combat: combat 1
- fenhollow / highfen / saltmere / cinderholt: Fenhallow 2 / Highfen 2 / Saltmere 2 / Cinderholt 2
- scorch (new slot, inside the Scorch): Scorched 2
- guild (new slot, inside a building whose id has "guild" - the Guild of
  Knights hall in Highfen, arriving with the stage 2 Highfen set): Guild of Knights 2
- goblin (new slot, within 16 tiles of a goblin camp): Goblin village 1
- ruins (new slot, data/music_zones.json zones; empty until the ruined temple is placed): Mysterious Ruins 1
Music manager: same crossfade / fade mechanics; slots may hold <id>_N.ogg
variants that rotate each time the slot starts. main.gd music_area() picks the slot.
