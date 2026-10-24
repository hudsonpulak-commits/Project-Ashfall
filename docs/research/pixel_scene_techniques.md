# Pixel Scene Techniques — layering & lived-in scenes (research, 2026-10-23)

Context: Godot 4.7 Android, top-down OSRS-like. Cost = cheap (<1 h, no new art) / medium (some art or system) / heavy.
Respect existing rules: buildings >=5x5, natural terrain transitions, no trees/cliffs on roads, single cliff stairs w/ straight cliff both sides, no orange night-window overlay, cliffs >=3 tiles from water.

## A. Layering sprites

| Technique | How-to | Godot 4 hint | Cost |
|---|---|---|---|
| Y-sort by feet | Sort draw order by the object's ground contact, not sprite centre. | `y_sort_enabled` on the world Node2D + prop layer; set sprite `offset` so origin = base/feet; TileData `y_sort_origin` for tall tiles. | cheap |
| Split tall props into base + canopy | Trunk/wall base y-sorts; canopy/roof drawn on a higher layer so it overlaps whatever stands behind it. | Canopy/roof as separate TileMapLayer or Sprite2D with higher `z_index`, not y-sorted. | medium |
| Occluder fade | When player is behind a tree/roof, fade it to ~40% alpha (or dither). Only if `prop.y > player.y` and rects overlap. | Area2D on canopy → tween `modulate.a`; or shader with `instance uniform` prop pos + global player pos. Roof: fade whole roof layer when player inside building Area2D. | cheap–medium |
| Player silhouette through occluders | Draw outline of player when hidden. | Second sprite copy, `z_index` high, shader draws only where alpha of occluder >0 (needs BackBufferCopy) — prefer fade instead on mobile. | medium |
| Separate shadow layer | Short, soft, consistent-direction blob/cast shadows grounding props; keep inside 1 tile to avoid conflicts. | Shadow TileMapLayer under props (z between ground and props), 1 colour at ~30% alpha, `light_mask` off. | cheap |
| Cut-off avoidance | Sprites must fit their frame/region; leaning sprites need padding on lean side; atlas region must include full bounds. | Audit: script that checks every atlas region's alpha on outer pixel columns (non-zero edge = likely clipped). Shader sway needs margin (`margin_scale`). | cheap |
| Full blob autotile (47) | Use edge+corner matching so diagonals & inner corners look intentional. | TileSet terrain set "Match Corners and Sides"; multiple interior variants with probability weights. | medium (art) |
| Decoration layer | Grass tufts/flowers/pebbles on a separate layer over ground, rules by terrain. | Script pass: iterate ground layer `get_used_cells`, read terrain via `get_cell_tile_data`, `set_cell` on deco layer with seeded RNG & density per terrain; exclude roads. | cheap |
| Break the grid | Mix flat negative space with textured patches; variants; rotate/flip; world-space noise tint. | Tile `flip_h`/transpose alternatives; canvas_item shader on ground layer tinting by world-space NoiseTexture2D (±10–18%). | cheap |
| Off-grid props | Nudge props by a few px (seeded) so rows of trees don't align. | Per-instance random offset ±3px from a hash of cell coords (deterministic). | cheap |
| Staggered forests | Simple symmetric canopies overlapping in staggered rows read as solid forest; save unique asymmetric trees for focal points. | Placement rule: odd rows offset half a tile. | cheap |

## B. Lived-in / dynamic scenes

| Technique | How-to | Godot 4 hint | Cost |
|---|---|---|---|
| Foliage sway | Top moves most, base anchored; desync per instance; pixel-quantised UV so it stays crisp. | canvas_item shader, `sin(TIME*speed + phase)*(1-UV.y)`, `instance uniform float phase` from position hash; multiply by vertex COLOR so CanvasModulate still works. | cheap |
| Hand-animated rustle | Slynyrd: 4 frames, 0.2 s/frame, leaf clusters move 1px in sequence. | AnimatedSprite2D, random start frame. | medium (art) |
| Water | Shoreline foam/ripple bands 2–4 frames; occasional sparkle. | Animated tiles in TileSet (Animation columns), random frame offset per tile. | cheap–medium |
| Smoke/chimney, fire | Few-pixel puffs rising & fading. | GPUParticles2D (or CPUParticles2D on low-end) with small pixel texture, amount ≤8, `local_coords` false. | cheap |
| Critters | Birds that fly off when player approaches, butterflies near flowers, fireflies at night, fish ripples. | Tiny state machine (idle/flee) + VisibleOnScreenEnabler2D so off-screen ones cost nothing. | medium |
| Falling leaves / dust motes | 2x2 px particles drifting with wind. | CPUParticles2D attached to camera, very low count. | cheap |
| NPC schedules | Time → activity table (work, eat, wander to well, sleep) with random jitter; player events override. Far cheaper and better than pure random walk. (Game AI Pro ch.36) | JSON schedule per NPC like quests.json; evaluate only on hour change; nav to named markers. | medium |
| Idle micro-behaviours | Look around, sit, chat in pairs, blacksmith hammer + spark, sweep. | Extra 2–4 frame idles + random timer. | medium (art) |
| Environmental storytelling | Props that imply events: broken cart by wolf den, bones at rat den, laundry lines, half-chopped log + axe, crates at quartermaster. "What happened here?" (Smith/Worch GDC). | Hand-placed prop sets per location, data in map gen. | cheap–medium |
| Clutter clusters | Place props in groups of 2–5 near walls/doors/fences, not evenly scattered; leave negative space. | Scatter rule: anchor to building door/side cells, Poisson-disc min distance. | cheap |
| Wear & paths | Worn dirt near doors, wells, gates; desire-line paths between buildings; grass thinning at road edges. | Deco pass: lower grass density + dirt-transition tiles within 1–2 tiles of doors/roads. | cheap |
| Day/night tint | Gradual CanvasModulate (white → warm dusk → cool blue night); small PointLight2D on torches/fires. | AnimationPlayer or code lerp on CanvasModulate; lights `energy`=0 by day. Keep window glow subtle/non-orange per rule. | cheap (tint) / medium (lights, mobile cost) |
| Weather | Rain particles + darker tint + puddle ripples. | Camera-attached particles. | medium |
| Ambient sound cues | Positional loops: forge clang, river, birds by day/crickets by night, chickens. | AudioStreamPlayer2D with `max_distance`, randomised pitch 0.9–1.1. | cheap (if SFX exist) |
| Parallax/cloud shadows | Large soft cloud shadows drifting over ground. | One big low-alpha texture on CanvasLayer scrolling slowly, pixel-snapped. | cheap |

## AshFall cheap wins (prioritised)
1. **Sprite-clipping audit script** — flag any atlas region with opaque pixels on its edge columns/rows (would have caught the palm bug); add to selftest. *cheap, no art.*
2. **Foliage sway shader** on trees/palms/bushes with per-instance phase; preserve vertex COLOR for day/night. Give lean-side margin. *cheap.*
3. **Canopy/roof fade** when player is behind a tree or inside a 5x5+ building (Area2D + tween alpha to 0.4). *cheap.*
4. **Deterministic deco + off-grid jitter pass**: grass tufts/flowers/pebbles by terrain, ±2–3 px prop offsets, excluding road cells (respect no-trees-on-roads). *cheap.*
5. **World-space noise tint** on ground layer to hide tile repetition. *cheap, one shader.*
6. **Wear near doors/wells/gates**: dirt-transition patches and thinned grass using existing transition tiles. *cheap.*
7. **Chimney smoke + few critters** (birds flee on approach, fireflies at night) via tiny particles, culled off-screen. *cheap–medium.*
8. **Story prop sets** at quest locations (wolf den bones/torn cart, rat den gnawed sacks, Garrow's broken fence, Wenna's empty stable). *cheap–medium, small art.*

Later (medium): NPC schedule JSON, 47-tile blob terrain, positional ambient SFX, torch PointLight2D (watch mobile perf gate C36).

## Sources
- Godot Y-Sort recipe: https://kidscancode.org/godot_recipes/4.x/2d/using_ysort/index.html
- Godot TileMaps docs: https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html
- Roof hiding discussion: https://forum.godotengine.org/t/the-problem-with-roofs-and-more/104006
- Occluder transparency (behind-only): https://forum.godotengine.org/t/how-can-i-make-a-transparency-shader-apply-only-when-the-player-is-behind-a-tree-or-wall-and-not-when-in-front-of-it/112494
- Occlusion cutout/dither fade demo: https://github.com/dmlary/godot-occlusion-cutout-demo
- Slynyrd Pixelblog 20 Top Down Tiles: https://www.slynyrd.com/blog/2019/8/27/pixelblog-20-top-down-tiles
- Slynyrd Pixelblog 21 Top Down Objects (shadows, staggered trees): https://www.slynyrd.com/blog/2019/9/18/pixelblog-21-top-down-objects
- Slynyrd Pixelblog 33 Wind Effects: https://www.slynyrd.com/blog/2021/7/16/pixelblog-33-wind-effects
- Slynyrd Pixelblog 23 Parallax (pixel-perfect motion): https://www.slynyrd.com/blog/2019/11/12/pixelblog-23-parallax-scrolling
- Godot 4 autotile/noise tint: https://tilewise.ai/blog/godot-4-autotile-terrain-setup
- Scatter2D addon: https://github.com/alex9978/scatter2d
- Pixel-perfect sway shader: https://godotshaders.com/shader/2d-pixel-perfect-wind-sway-effect/
- Sway shader preserving modulate: https://godotshaders.com/shader/wind-sway-for-foliage-and-flags/
- 2D day/night in Godot 4: https://www.youtube.com/watch?v=9T_s9QPBO9k
- Game AI Pro ch.36 Background NPC schedules: http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter36_Breathing_Life_into_Your_Background_Characters.pdf
- GDC "Stop Fighting! Systems for Non-Combat AI": https://www.gdcvault.com/play/1025833/Stop-Fighting-Systems-for-Non
- GDC "What Happened Here? Environmental Storytelling": https://www.gdcvault.com/play/1012647/what-happened-here-environmental
