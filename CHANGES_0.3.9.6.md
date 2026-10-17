# AshFall 0.3.9.6 (versionCode 25)

Designer's "0.3.9.7 texture pass" (Hudson-approved per the designer), shipped as 0.3.9.6.

## Art (copied from art_handoff/textures_0397, protected_art re-hashed)
- tiles: road_stone, cobble, cobble_dark, moat, moat_edge, capital_wall,
  capital_front, gate_capital, capital_bldg_wall, capital_bldg_front
- transitions: road_stone, cobble, cobble_dark (256x256, same 16x16 layout)
- autotile: moat_border (20 pieces), moat_border_corners, wall_capital_wall
- cobble is shared: Fenhollow, Cinderholt and Saltmere streets change with it
  (nothing else in Saltmere touched).

## Engine checks
- Variant strips: road_stone and cobble_dark are now 64x16 strips of 4.
  World._build_tileset already makes one atlas tile per 16 px of strip width
  and _build_view picks the variant with gen.hash01(x, y, 7) once per chunk
  build: deterministic per cell, stable, no flicker. Transitions are separate
  256-frame sheets (layout unchanged); the minimap uses minimap_color, not the
  texture. No code change needed; the alt_exact_size files are not used.
- Moat: bridge joins (layer 3) and inner corners (layer 4) are now
  see-through; they draw over the layer-2 bank piece, which is fully opaque
  in all 16 masks, over the opaque moat base tile - no hole to the void, one
  join per tile. Inner-corner rules unchanged (patch0392 still passes).
- Minimap colours = texture average: road_stone #857d7d, cobble #8e8382,
  cobble_dark #3f363a, moat #1e3b4b.
- patch0396_tests covers the above.

## Title video (main menu)
- res://assets/ui/title_loop.ogv: Hudson's title loop (720x1280 h264, 15.04 s)
  made seamless and converted to Ogg Theora 540x960, 24 fps, no audio,
  q9, keyframe every 5 s: 337 frames = 14.04 s. Seam: the last 1 s (source
  frames 337-360) is crossfaded into the first 1 s (frames 0-23) with weights
  k/23, overlap dropped, so the loop ends on source frame 23 and restarts on
  source frame 24. Frame N-1 -> frame 0 mean abs diff (lossless 540x960):
  1.04 vs 3.35 for the original wrap, in line with neighbouring frames
  (0.76-1.15). No ping-pong.
- Engine: the size-optimised export template had module_theora disabled; it
  is enabled now (Android template +29 KB) and both custom templates were
  rebuilt.
- MainMenu: a muted, looping, autoplay VideoStreamPlayer, cover-fitted
  (aspect kept, centred, clipped) over the static title art and under the
  menu. The still (assets/ui/title_bg.png, unchanged) is the poster while the
  stream opens and the fallback when the file / Theora / stream is missing or
  no frame arrives within 4 s. Started deferred after the menu is built (boot
  time unchanged); stopped and freed before the game scene loads and on
  _exit_tree (no playback in gameplay). Title text stays hidden (the video
  carries the AshFall logo).
- Menu layout: Continue on top, then New Game / Load Game / Settings / Quit in
  two columns, so the menu sits on the dark river at the bottom of the video,
  clear of the bridge and the city; the panel keeps its dark backing.
- patch0396_video_tests: player present with loop/autoplay/expand/muted,
  layering over the still, cover-fit maths, stop+free, fallback on a missing
  stream.
