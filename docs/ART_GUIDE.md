# Ashfen: art guide (drop-in pixel art)

Every image in the game is a PNG under `assets/sprites/<category>/`. The game finds sprites **only** through one mapping file: `data/sprites.json`. That means you can replace art without touching code:

1. **Same name, same size:** overwrite `assets/sprites/objects/tree_ash.png` with your own 16×24 PNG, then open the project in Godot (or run any script in `scripts/`). Godot re-imports it and it appears in-game.
2. **New file:** point the entry's `path` in `data/sprites.json` at it, e.g. `"tree_ash": {"path": "res://assets/sprites/objects/my_ash_v2.png", ...}`.
3. If a mapped file is missing, the game draws a **magenta/black checker** (`ui/missing.png`) so gaps are obvious. `scripts/test.sh` also fails the check "every mapped sprite PNG exists".

Check your progress at any time:
```bash
python3 tools/art_status.py            # placeholder / HAND-MADE / MISSING for every sprite
python3 tools/art_status.py --markdown # same, as a table
```
`tools/gen_art.py` (the placeholder generator) **never overwrites a PNG you've changed**. It compares each file against the hashes in `assets/sprites/placeholders.json` and keeps anything that differs. Only `--force` overwrites.

## Global rules
- **Grid:** 1 tile = **16×16 px**. The world is drawn at integer zoom (1×–4×, default 2×) and the whole screen uses an integer scale factor. Pixels are always square and crisp.
- **Filtering:** the project default texture filter is **Nearest** (`rendering/textures/canvas_textures/default_texture_filter=0`). You don't need to change import settings. Keep Godot's default 2D import (Lossless, no mipmaps).
- **No anti-aliasing:** hard pixel edges only. Use no soft brushes, no sub-pixel rotation, no resampled scaling, and no partial alpha except for the ground shadow and water ripples.
- **Format:** PNG, RGBA 8-bit, transparent background, sRGB. No colour profile is needed.
- **Light:** comes from the top-left. Shade the bottom-right.
- **Outline:** optional 1 px darker-hue outline (not pure black) on objects and actors. Tiles have no outline.
- **Ground shadow:** objects and actors include a small ellipse shadow at their feet (black at about 27 % alpha, rows 21–23 of a 24-px-tall sprite).

## Palette guidance
Aim for a **limited palette of 32–48 colours**, shared across the whole game (Aseprite: *Palette → Save*, and keep it as `assets/palette.gpl`). The placeholders use these anchor hues, so matching them keeps the minimap and the UI coherent:

| Use | Hex |
|---|---|
| Grass / dark grass | `#4a7a3a` / `#3c6a30` |
| Leaves highlight | `#5f9a46`, `#9ad070` |
| Path / dirt | `#9a7c4c` / `#6e5236` |
| Water / shallows highlight | `#2e6a8c` / `#5a8aa0` |
| Sand | `#cdb878` |
| Cobble / stone | `#80827a`, `#6e7078`, `#8d9098` |
| Wood (trunks, chest) | `#5a3b22`, `#7a4e24`, `#a8784a` |
| Copper / iron / coal (ore, rocks) | `#c8783c` / `#9a5a48` / `#1e1e22` |
| Tin ore / rock | `#c4c8cc` / `#d0d4d8` |
| Metal tiers: bronze / iron / steel / dusksteel | `#b08a3c` / `#8a8e96` / `#6a7a8a` / `#5a4a7a` |
| Gold (marks, trims) | `#e8c050`, `#b88a2a` |
| UI dark / border / highlight | `#17140e` / `#7a6232` / `#d8b468` |

If you change a ground tile's main colour, also update its `minimap_color` in `data/sprites.json`. The minimap uses one pixel per tile.

## Categories, sizes and anchors

| Category | Folder | Frame size | Anchor (where the tile is) | Notes |
|---|---|---|---|---|
| Ground tiles | `tiles/` | **16×16** | fills the tile | **Variants:** a horizontal strip; width = 16 × N. The game picks a variant per tile with a stable hash, so a 64×16 file = 4 variants. Add more variants by widening the strip, with no code change |
| World objects | `objects/` | **16×24** (16×32 allowed; update `frame_size`) | **bottom-centre**: the bottom 16 px sit on the object's tile and the top 8 px overhang the tile above | Depleted states are separate sprites (`stump`, `rock_empty`), referenced by `depleted_sprite` in `data/objects.json` |
| Actors (player, AI players) | `actors/` | **16×24** | bottom-centre (feet on the tile's bottom edge) | Animation frames are a horizontal strip (see below). `npc.png` is drawn in **white/light grey clothing** because it is tinted per AI persona (`tintable: true`) |
| Item icons | `items/` | **16×16** | n/a | Shown at 2× in the pack/bank (32×32 on screen). The file name = the item id from `data/items.json` |
| UI | `ui/` | 16×16 | n/a | `tap_marker` (tap feedback), `missing` (fallback) |
| App icon (source) | `app/icon_64.png` | 64×64 | n/a | `tools/gen_art.py` scales it by integer factors to `icon.png` (256) and `assets/app_icon_main_192.png`. The Android adaptive icons are `assets/app_icon_fg_432.png` and `assets/app_icon_bg_432.png`; keep the important art inside the centre 264 px circle |

## Animation frame layout
- Frames go **left to right in a single row**, with no padding, spacing or trimming. Each frame is exactly `frame_size`.
- Set `"frames"` (count) and `"fps"` in the sprite's `data/sprites.json` entry.
- **Actors now:** 2 frames (`0` = idle/stand, `1` = step/work). The game alternates them while walking or working and flips horizontally for left-facing movement, so draw them **facing right/forward**.
- **Actors planned (M3):** 4 rows = directions **down, left, right, up**, each row with the same frame count (e.g. 4 walk frames). A `rows` field will be added to the mapping. Single-row sheets will keep working.
- **Animated objects:** e.g. `objects/fishing_spot.png` = 2 frames at 3 fps (32×24).

**Aseprite export:** *File → Export Sprite Sheet* → Layout: **Horizontal Strip**, Borders: padding 0, **Trim off**, Output: PNG to the exact path above, with JSON data off (not needed). For single images, *File → Export As* at 100 % scale. **Never export upscaled.**

## Naming
- `snake_case`, ASCII, no spaces: `tree_alder.png`, `rock_iron.png`, `cooked_eel.png`.
- Item icons **must** match item ids. Object/actor/tile names match their `data/sprites.json` keys.
- To add a new object: draw `objects/<name>.png`, add an entry under `"objects"` in `data/sprites.json`, then reference it as `"sprite": "<name>"` in `data/objects.json`.

## Fonts (optional)
The UI uses Godot's default font. To use a pixel font, drop it at `assets/fonts/ui_font.ttf` (or `.otf` / `.fnt`) and it is picked up automatically (`src/ui/ui_style.gd`). Good choices are any OFL-licensed pixel font at native size 8 or 16. Check the licence first.

## Placeholder inventory (replace one by one)
All 119 sprites below are **placeholders**: original procedural pixel art generated by `tools/gen_art.py` (Python/Pillow), not drawn at runtime. Re-run `python3 tools/art_status.py --markdown` to refresh this table.

M2 added:
- **Objects:** the anvil, the General Store stall (`store_stall`) and eight specialist stalls (`shop_<line>`, 16x24). Each has a coloured awning and a small sign showing its line.
- **Item icons:** every gear piece (helmets, body, legs, shields, swords, battle axes, maces and bows in three tiers, plus copper and iron arrows), and the combat drops (bones, raw and cooked rat meat, burnt meat).
- **Enemies** (`actors`, 2-frame strips): `giant_rat` (16x16 per frame, a 32x16 strip) and `goblin` (16x24 per frame, a 32x24 strip, same layout as the player).

0.2.3 (bronze / steel):
- The copper metal tier is now **bronze**: `bronze_bar`, `bronze_hatchet`, `bronze_pick`, `bronze_sword`, `bronze_cap`, `bronze_scale_vest`, `bronze_greaves`, `bronze_battleaxe`, `bronze_mace` and `bronze_arrows` (bronze palette `#b08a3c`). The old `copper_*` item PNGs are deleted; `copper_ore` and `rock_copper` stay.
- **New:** `tin_ore` icon and `rock_tin` object (16x24, same frame layout as the other rocks). There is also a **steel tier** (palette `#6a7a8a` / `#a8b8c8` / `#3a4450`): `steel_bar`, `steel_helm`, `steel_brigandine`, `steel_legplates`, `steel_heater_shield`, `steel_sword`, `steel_battleaxe`, `steel_mace` and `steel_arrows`.
- Gear icons now come in four metal tiers (bronze, iron, steel, dusksteel). Dusksteel keeps its red crest and gem details.

0.2.4 (combat skills):
- **New weapon lines:** `bronze_dagger`, `iron_dagger`, `steel_dagger`, `dusk_dagger` (short blade, small guard, wrapped grip) and `bronze_warhammer`, `iron_warhammer`, `steel_warhammer`, `dusk_warhammer` (long haft, square head, back spike). They use the same four metal palettes; dusk adds a red gem. 16x16 icons from `tools/gen_art.py` (`dagger()`, `warhammer()`).
- The HP / Prayer / Energy bars beside the minimap are drawn in code (`src/ui/stat_bar.gd`), not sprites.

0.2.5 (facing and animation):
- **Actor art faces RIGHT.** The game mirrors it (`flip_h`) to face left. Set `"flip": false` on an actor in `data/sprites.json` for art that must never be mirrored (text, a one-sided weapon, a symmetric front view).
- **Walk frames must not be mirror images of each other.** The 0.2.4 `player`/`npc` cycle swapped which arm and leg was low on a front-facing figure, so frame 2 was frame 1 mirrored and walking looked like the avatar flipping left and right. The selftest now fails if any frame of `player`, `npc`, `goblin` or `giant_rat` is within 12 px of a mirrored frame.
- `player` and `npc` are now **4 frames, 64x24** (stand, far leg lifted, stand, near leg lifted), with a three-quarter head facing right (eyes and nose right, hair tuft at the back). Frame 0 is the idle pose.
- The walk cycle runs at the sprite's `fps` with `frames` frames from data, on a continuous clock with a 2-tick grace (`data/fx.json` `facing.anim_grace_ticks`) so short pauses don't pop to frame 0.

Enemies are registered in `data/sprites.json` under `actors`, and `data/enemies.json` names the sprite id per enemy. To replace one, drop a PNG with the same frame size and frame count at the mapped path. The removed M1 placeholders `marsh_rat`, `marsh_rat_tail` and `rat_pelt` no longer exist.

| Category | Id | File | Size (px) | Status |
|---|---|---|---|---|
| tiles | grass | tiles/grass.png | 64x16 | placeholder |
| tiles | path | tiles/path.png | 64x16 | placeholder |
| tiles | water | tiles/water.png | 64x16 | placeholder |
| tiles | sand | tiles/sand.png | 64x16 | placeholder |
| tiles | dirt | tiles/dirt.png | 64x16 | placeholder |
| tiles | cobble | tiles/cobble.png | 64x16 | placeholder |
| tiles | planks | tiles/planks.png | 64x16 | placeholder |
| tiles | marsh | tiles/marsh.png | 64x16 | placeholder |
| objects | tree_ash | objects/tree_ash.png | 16x24 | placeholder |
| objects | tree_alder | objects/tree_alder.png | 16x24 | placeholder |
| objects | tree_blackthorn | objects/tree_blackthorn.png | 16x24 | placeholder |
| objects | stump | objects/stump.png | 16x24 | placeholder |
| objects | rock_copper | objects/rock_copper.png | 16x24 | placeholder |
| objects | rock_iron | objects/rock_iron.png | 16x24 | placeholder |
| objects | rock_coal | objects/rock_coal.png | 16x24 | placeholder |
| objects | rock_empty | objects/rock_empty.png | 16x24 | placeholder |
| objects | reed_bed | objects/reed_bed.png | 16x24 | placeholder |
| objects | fenroot_patch | objects/fenroot_patch.png | 16x24 | placeholder |
| objects | dummy | objects/dummy.png | 16x24 | placeholder |
| objects | bank_chest | objects/bank_chest.png | 16x24 | placeholder |
| objects | exchange_board | objects/exchange_board.png | 16x24 | placeholder |
| objects | hearth | objects/hearth.png | 16x24 | placeholder |
| objects | furnace | objects/furnace.png | 16x24 | placeholder |
| objects | workbench | objects/workbench.png | 16x24 | placeholder |
| objects | fishing_spot | objects/fishing_spot.png | 32x24 | placeholder |
| objects | anvil | objects/anvil.png | 16x24 | placeholder |
| objects | store_stall | objects/store_stall.png | 16x24 | placeholder |
| objects | shop_helmets | objects/shop_helmets.png | 16x24 | placeholder |
| objects | shop_body | objects/shop_body.png | 16x24 | placeholder |
| objects | shop_legs | objects/shop_legs.png | 16x24 | placeholder |
| objects | shop_shields | objects/shop_shields.png | 16x24 | placeholder |
| objects | shop_swords | objects/shop_swords.png | 16x24 | placeholder |
| objects | shop_axes | objects/shop_axes.png | 16x24 | placeholder |
| objects | shop_maces | objects/shop_maces.png | 16x24 | placeholder |
| objects | shop_archery | objects/shop_archery.png | 16x24 | placeholder |
| objects | rock_tin | objects/rock_tin.png | 16x24 | placeholder |
| actors | player | actors/player.png | 64x24 | placeholder |
| actors | npc | actors/npc.png | 64x24 | placeholder |
| actors | giant_rat | actors/giant_rat.png | 32x16 | placeholder |
| actors | goblin | actors/goblin.png | 32x24 | placeholder |
| items | marks | items/marks.png | 16x16 | placeholder |
| items | ash_log | items/ash_log.png | 16x16 | placeholder |
| items | alder_log | items/alder_log.png | 16x16 | placeholder |
| items | blackthorn_log | items/blackthorn_log.png | 16x16 | placeholder |
| items | copper_ore | items/copper_ore.png | 16x16 | placeholder |
| items | tin_ore | items/tin_ore.png | 16x16 | placeholder |
| items | iron_ore | items/iron_ore.png | 16x16 | placeholder |
| items | coal | items/coal.png | 16x16 | placeholder |
| items | raw_carp | items/raw_carp.png | 16x16 | placeholder |
| items | raw_eel | items/raw_eel.png | 16x16 | placeholder |
| items | reed_fibre | items/reed_fibre.png | 16x16 | placeholder |
| items | fenroot | items/fenroot.png | 16x16 | placeholder |
| items | bronze_bar | items/bronze_bar.png | 16x16 | placeholder |
| items | iron_bar | items/iron_bar.png | 16x16 | placeholder |
| items | steel_bar | items/steel_bar.png | 16x16 | placeholder |
| items | plank | items/plank.png | 16x16 | placeholder |
| items | cooked_carp | items/cooked_carp.png | 16x16 | placeholder |
| items | cooked_eel | items/cooked_eel.png | 16x16 | placeholder |
| items | charred_fish | items/charred_fish.png | 16x16 | placeholder |
| items | marsh_tonic | items/marsh_tonic.png | 16x16 | placeholder |
| items | bronze_hatchet | items/bronze_hatchet.png | 16x16 | placeholder |
| items | iron_hatchet | items/iron_hatchet.png | 16x16 | placeholder |
| items | bronze_pick | items/bronze_pick.png | 16x16 | placeholder |
| items | iron_pick | items/iron_pick.png | 16x16 | placeholder |
| items | reed_rod | items/reed_rod.png | 16x16 | placeholder |
| items | bronze_sword | items/bronze_sword.png | 16x16 | placeholder |
| items | iron_sword | items/iron_sword.png | 16x16 | placeholder |
| items | unknown | items/unknown.png | 16x16 | placeholder |
| items | bronze_cap | items/bronze_cap.png | 16x16 | placeholder |
| items | iron_helm | items/iron_helm.png | 16x16 | placeholder |
| items | dusk_helm | items/dusk_helm.png | 16x16 | placeholder |
| items | bronze_scale_vest | items/bronze_scale_vest.png | 16x16 | placeholder |
| items | iron_hauberk | items/iron_hauberk.png | 16x16 | placeholder |
| items | dusk_cuirass | items/dusk_cuirass.png | 16x16 | placeholder |
| items | bronze_greaves | items/bronze_greaves.png | 16x16 | placeholder |
| items | iron_legguards | items/iron_legguards.png | 16x16 | placeholder |
| items | dusk_tassets | items/dusk_tassets.png | 16x16 | placeholder |
| items | alder_buckler | items/alder_buckler.png | 16x16 | placeholder |
| items | iron_kite_shield | items/iron_kite_shield.png | 16x16 | placeholder |
| items | dusk_tower_shield | items/dusk_tower_shield.png | 16x16 | placeholder |
| items | dusk_sword | items/dusk_sword.png | 16x16 | placeholder |
| items | bronze_battleaxe | items/bronze_battleaxe.png | 16x16 | placeholder |
| items | iron_battleaxe | items/iron_battleaxe.png | 16x16 | placeholder |
| items | dusk_battleaxe | items/dusk_battleaxe.png | 16x16 | placeholder |
| items | bronze_mace | items/bronze_mace.png | 16x16 | placeholder |
| items | iron_mace | items/iron_mace.png | 16x16 | placeholder |
| items | dusk_mace | items/dusk_mace.png | 16x16 | placeholder |
| items | ash_shortbow | items/ash_shortbow.png | 16x16 | placeholder |
| items | alder_longbow | items/alder_longbow.png | 16x16 | placeholder |
| items | blackthorn_warbow | items/blackthorn_warbow.png | 16x16 | placeholder |
| items | bronze_arrows | items/bronze_arrows.png | 16x16 | placeholder |
| items | iron_arrows | items/iron_arrows.png | 16x16 | placeholder |
| items | bones | items/bones.png | 16x16 | placeholder |
| items | raw_rat_meat | items/raw_rat_meat.png | 16x16 | placeholder |
| items | cooked_rat_meat | items/cooked_rat_meat.png | 16x16 | placeholder |
| items | burnt_meat | items/burnt_meat.png | 16x16 | placeholder |
| items | steel_sword | items/steel_sword.png | 16x16 | placeholder |
| items | steel_mace | items/steel_mace.png | 16x16 | placeholder |
| items | steel_battleaxe | items/steel_battleaxe.png | 16x16 | placeholder |
| items | steel_helm | items/steel_helm.png | 16x16 | placeholder |
| items | steel_brigandine | items/steel_brigandine.png | 16x16 | placeholder |
| items | steel_legplates | items/steel_legplates.png | 16x16 | placeholder |
| items | steel_heater_shield | items/steel_heater_shield.png | 16x16 | placeholder |
| items | steel_arrows | items/steel_arrows.png | 16x16 | placeholder |
| items | bronze_dagger | items/bronze_dagger.png | 16x16 | placeholder |
| items | bronze_warhammer | items/bronze_warhammer.png | 16x16 | placeholder |
| items | iron_dagger | items/iron_dagger.png | 16x16 | placeholder |
| items | iron_warhammer | items/iron_warhammer.png | 16x16 | placeholder |
| items | steel_dagger | items/steel_dagger.png | 16x16 | placeholder |
| items | steel_warhammer | items/steel_warhammer.png | 16x16 | placeholder |
| items | dusk_dagger | items/dusk_dagger.png | 16x16 | placeholder |
| items | dusk_warhammer | items/dusk_warhammer.png | 16x16 | placeholder |
| ui | tap_marker | ui/tap_marker.png | 16x16 | placeholder |
| ui | missing | ui/missing.png | 16x16 | placeholder |
| ui | prayer_def | ui/prayer_def.png | 16x16 | placeholder |
| ui | prayer_dmg | ui/prayer_dmg.png | 16x16 | placeholder |
| ui | prayer_acc | ui/prayer_acc.png | 16x16 | placeholder |
| ui | prayer_gather | ui/prayer_gather.png | 16x16 | placeholder |
| ui | multi_combat | ui/multi_combat.png | 16x16 | placeholder |

0/95 sprites hand-made, 0 missing


## Buildings (0.3.0)

Walk-in buildings are made of 16x16 tiles plus a few 16x24 objects. All are
placeholders from `tools/gen_art.py`; replace any PNG and the generator keeps
your file (sha in `assets/sprites/placeholders.json`).

| file | size | notes |
|---|---|---|
| tiles/wall.png | 16x16 x variants | stone wall seen from above (side/back walls) |
| tiles/wall_front.png | 16x16 x variants | the door-side facade: plaster and timber, some variants with a window or lantern |
| tiles/floor.png | 16x16 x variants | wooden boards |
| tiles/doorway.png | 16x16 x variants | open door: dark threshold, door leaf swung in, frame posts |
| buildings/roof.png | 48x48 | 3x3 nine-patch of 16 px pieces (corners, edges, middle). Draw it **light and neutral**: the game tints it per town (`roof` in data/towns/*.json) and fades it out when the player walks in. The middle row is the ridge, where the building name is drawn |
| buildings/sign_<shop>.png | 16x16 | hanging board with the shop's icon: general, helmets, body, legs, shields, swords, axes, maces, archery, smithy (anvil), forsale (key), player (coins and star) |
| objects/counter.png | 16x24 | one counter segment (counters are 3-5 segments wide) |
| objects/display_stand.png | 16x24 | player-shop stand; the game draws the stocked item's 16x16 icon on top (centre 18 px above the foot) |
| objects/shelf_goods, barrel, crate, sacks, helm_stand, armour_stand, shield_rack, weapon_rack, axe_rack, bow_rack | 16x24 | shop props (they block movement) |
| objects/bellows, quench_barrel, coal_crate | 16x24 | Blacksmith forge props |
| actors/keeper_<shop>.png | 4 frames of 16x24 | general, helmets, body, legs, shields, swords, axes, maces, archery, estate (estate agent), player (your assistant). 3/4 view **facing right**, idle cycle: stand, breathe, stand, blink. Frames must not be mirror images of each other (the game mirrors the whole sprite to face left). Each keeper should be recognisable: apron colour of the shop, hair, and a hat, hood or band by trade. Tintable: keep the apron mid-tone |

Layout rules: the facade row (the wall with the door) is never roofed, so
the door, facade and sign stay visible. Keep roof edges readable at 1x.

## World layout placeholders (0.3.1)

Drawn by `tools/gen_art_world.py` (rerun it to regenerate; it also updates `assets/sprites/placeholders.json`). Replace any of them by dropping a PNG with the same size and frame count at the path mapped in `data/sprites.json`:

| Sprite | Path | Size / frames | Notes |
|---|---|---|---|
| tiles `ash`, `ash_edge` | `tiles/ash.png`, `tiles/ash_edge.png` | 16x16 | The Scorch ground; `ash_edge` is the charred boundary row (glowing cracks) along the zone rect's southern edge (`edge_tiles` in `data/pk_zones.json`). |
| tile `bridge` | `tiles/bridge.png` | 16x16 | Wooden planks for road crossings over lakes. |
| objects `burnt_tree`, `charred_stump`, `embers` | `objects/*.png` | tree 16x32, stump 16x16, embers 16x16 x2 frames | Scorch decor; only `burnt_tree` blocks. Spawn chances: `decor` in `data/pk_zones.json`. |
| actors `chicken`, `wolf`, `town_guard`, `citizen`, `cinder_brute` | `actors/*.png` | chicken 16x16, wolf 24x16, others 16x24; 2 frames | `citizen` is drawn light/neutral: the game tints it per spawn (`tints` in `data/enemies.json`). |
| items `feather`, `raw_chicken`, `cooked_chicken`, `wolf_pelt` | `items/*.png` | 16x16 | |
| ui `pk_skull` | `ui/pk_skull.png` | 16x16 | HUD skull row + the Scorch entry banner. |
| tiles `stone_wall`, `stone_front`, `stone_floor` | `tiles/*.png` | 16x16 x4 variants | 0.3.1 stone church: wall tops, facade (variant 2 has a lancet slit), flagstone floor. Buildings with `"style": "stone"` (data/churches.json) use these instead of the timber `wall` / `wall_front` / `floor`. |
| objects `altar`, `pew`, `candle_stand`, `stained_glass` | `objects/*.png` | 16x24 (candles x2 frames); stained_glass 16x16 | Church interior; stained glass sits on wall tiles (north wall inside, facade outside). |
| actor `priest` | `actors/priest.png` | 16x24 x4 idle frames | The church keeper (like the shopkeepers). |
| building `sign_church` | `buildings/sign_church.png` | 16x16 | Facade sign beside the church door. The church roof is the normal roof nine-patch tinted slate grey (`roof` in data/churches.json). |

## Visible gear layers (0.3.1): player and AI players

Everything worn in the **head, body, legs, shield and weapon** slots is drawn as a separate overlay sprite on top of the body sprite. The player and every AI player use the same system (`Actor._refresh_gear_visual`). Equipping or unequipping changes the picture on the very next frame (QA check C19).

**Layer sheet format.** It is the same as the body sheet (`actors/player.png` / `actors/npc.png`):

| Property | Value |
|---|---|
| Frame size | **16×24** px (`"frame_size": [16, 24]`) |
| Frames | **4** in one row, a **64×24** strip, no padding: 0 stand (idle), 1 far leg lifted, 2 stand, 3 near leg lifted. Frame *n* of a layer is always drawn over frame *n* of the body. If a layer has fewer frames, the game uses its last frame. |
| Anchor | **bottom-centre**, exactly like the body. Pixel (8, 24) is the actor's feet. Draw each piece in the place it sits on the body frame below it; the canvas is the full 16×24 frame, transparent everywhere else. |
| Facing | Draw **facing right** (the body's three-quarter view). The game mirrors the body and all its layers together (`flip_h`) to face left, so never draw a left-facing copy. |
| fps | Ignored for layers: they follow the body's walk clock. Use `"fps": 5`, the same as the body. |
| Colours | No tint is applied to layers. Paint the final colours, using the metal tier anchors above: bronze `#b08a3c`, iron `#8a8e96`, steel `#6a7a8a`, dusk `#5a4a7a`. Wood (bucklers, bows) uses the wood ramp. |

Body geometry the placeholder layers are drawn against (frame-local px, x right / y down):
- Head: x5–10, y4–9 (hair y3–4). Helmets cover y1–7.
- Torso: x4–11, y10–17.
- Legs: x5–6 (far leg, lifts 1 px on f1) and x9–10 (near leg, lifts on f3), y17–21.
- Near arm (weapon hand): x12, y11–15. The hand is at y14, +1 on f1 and −1 on f3; weapons swing with it.
- Far arm (shield): x3, y11–14.

**Draw order.** From back to front: body sprite < **legs < body armour < head < shield < weapon**. The whole stack is mirrored for left-facing, so the order is correct both ways. The weapon is in the near (right) hand and the shield is on the far arm. If a shield should look like it is behind the torso, paint the overlapping pixels transparent.

**Which sprite is used.** The ids are in `data/sprites.json` → `actors`. The first match wins:
1. `gear_item_<item id>`: art for **one item**, e.g. `gear_item_dusk_sword`. This is the slot for your hand-drawn pieces. Add an entry and that item uses it.
2. `gear_<slot>_<class>_<tier>`: the silhouette per type and tier. Weapons use the item's gear `class`: `sword`, `dagger`, `mace`, `warhammer`, `battleaxe`, `bow`. Shields use a word from the item id: `buckler`, `kite`, `heater`, `tower`. Example: `gear_weapon_bow_2`, `gear_shield_kite_2`.
3. `gear_<slot>_<tier>`: the generic piece per slot and tier, e.g. `gear_head_3`. `gear_weapon_<tier>` is the sword.

If no match is found, nothing is drawn for that slot. Tiers are 1 bronze/ash, 2 iron/alder, 3 steel/blackthorn and 4 dusk.

Example entry, for hand-drawn art for one helmet:
```json
"gear_item_steel_helm": {"path": "res://assets/sprites/actors/gear/my_steel_helm.png", "frame_size": [16, 24], "frames": 4, "fps": 5, "anchor": "bottom", "flip": true}
```

The placeholders live in `assets/sprites/actors/gear/*.png` and are made by `tools/gen_art_adv.py`. Like `gen_art.py`, it never overwrites a PNG you have changed. To check your art in the game, run `QA_KEEP_FRAMES=1 tools/qa_bot/run.sh gear`. It puts every tier set on, facing right and left, into `evidence/v031_gear_player.png`, and checks that the rendered sprite matches body + layers on every frame (C19). It also runs C1 facing and C2 ghosting with gear on.

## 0.3.9.2 designer art (short note)
- Every actor, gear, tile, object, item, UI and transition PNG is now hand-drawn designer art (batches 1+2), plus the app icons and Hudson's exact title image (`assets/ui/title_bg.png`, lossless). All are listed with sha256 in `tools/art/protected_art.json`; `tools/art/art_guard.py` (imported by every generator) refuses to overwrite them, even with `--force`. They are no longer in `assets/sprites/placeholders.json`.
- Hands: profile near hand at (8,15), (11,14), (8,15), (5,14) per walk frame; front/back hands at x=3 and x=12. Gear sheets must follow these.
- Palette: 38 colours (designer handoff `palette.hex`).
- Moat inner corners: `autotile/moat_border_corners` (NE, SE, SW, NW), drawn when both side neighbours are moat and the diagonal is land.
- Back-facing shields are drawn under the body; only the outer edge (x <= 5) may show.
