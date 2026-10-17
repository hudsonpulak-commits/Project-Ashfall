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
