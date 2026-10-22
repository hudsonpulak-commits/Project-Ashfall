# 0.3.10 placeholder art for the designer to redraw

All of these are recolours made by `tools/gen_art_regions.py` from existing
sprites. They are flagged `"note": "0.3.10 PLACEHOLDER ..."` in
data/sprites.json and listed in assets/sprites/placeholders.json, so
`tools/art_status.py` shows them as placeholders until replaced. Same sizes
and layouts as the files they came from, so drop-in replacements work.

## Ground tiles (64x16 strips of 4 variants) + transition sheets (256x256)
- tiles/grass_lush.png + transitions/grass_lush.png - Lower Ashfen (fertile, deep green)
- tiles/grass_boreal.png + transitions/grass_boreal.png - Cinder (cold, grey-blue green)
- tiles/grass_tropic.png + transitions/grass_tropic.png - the Mere Lands (warm, yellow green)
- tiles/rocky.png + transitions/rocky.png - stony ground (Cinder, Central Ashfen)

## Cliffs (layered, 64x16 strips)
- tiles/cliff_face.png - south-facing edge of a higher terrace: lip (top 4 px) + rock face. Blocks.
- tiles/cliff_lip.png - east/west/north edge of a higher terrace (rim stone). Blocks.
- tiles/cliff_shadow.png - the ground just below a face (cast shadow). Walkable.
- tiles/cliff_stairs.png - ramps / stone stairs through a cliff line. Walkable.
  Ideal redraw: a 2-tile-tall face, corner pieces, and stairs drawn per direction.

## Trees (16x24 objects)
- objects/tree_pine.png (Forestry 1) - recolour of tree_ash
- objects/tree_dead.png (Forestry 1) - recolour of burnt_tree
- objects/tree_spruce.png (Forestry 45, Cinder) - recolour of tree_alder
- objects/tree_mahogany.png (Forestry 60, Mere Lands) - recolour of tree_blackthorn
- objects/tree_alder.png is now the OAK tree (Forestry 15) - redraw as oak
- objects/tree_blackthorn.png is now the ASH tree (Forestry 30) - redraw as ash
- objects/tree_ash.png is now the plain "Tree" (Forestry 1)

## Other
- objects/magic_mushroom.png + items/magic_mushroom.png - cyan glowing mushrooms (recolour of fenroot)
- objects/rock_dusk.png + items/dusk_ore.png - dusk ore (recolour of iron)
- items/dusk_steel_bar.png - recolour of steel_bar
- items/spruce_log.png, items/mahogany_log.png - recolours of alder / blackthorn logs
