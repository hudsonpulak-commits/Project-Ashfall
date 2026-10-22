# AshFall cliffs (redraw of 0.3.10 placeholders cliff_face/lip/shadow/stairs)
Regenerate: `python3 src/gen_cliffs.py` (deterministic). Palettes: `normal/`, `cinder/` (same names).
## v2 (style ref refs/cliff_reference.png)
Faces = irregular rock columns/blocks with near-black crevices, top-left highlights; clumpy grass lip overhanging 1-3 px; moss tufts on face; ragged rubble base.
Added: cliff_top_dirt, cliff_face_s_d, cliff_rim_n_b/e_b/w_b (edge variants, chosen by cell hash), and 16x16 objects
cliff_outcrop_a, cliff_outcrop_b, cliff_boulder, prop_grass_tuft, prop_rocks, prop_pebbles (anchor bottom-centre, place on ground).
## Sizes / anchors
- 16x16: cliff_top, cliff_rim_n/e/w, cliff_corner_outer_ne/nw, cliff_corner_inner_ne/nw/se/sw, cliff_shadow (alpha overlay).
- 16x32: cliff_face_s_a/b/c, cliff_corner_outer_se/sw, cliff_stairs. Anchor = top-left of the plateau edge cell; the
  bottom 16 px overhang the cell to the south (that cell must be non-walkable / draw above ground, y-sorted by row).
  Face = ~3 px grass lip + ~26 px rock (lip jagged, bottom jagged).
- Sheets `cliffs_<pal>_sheet.png`: one 16x32 slot per tile, order in manifest.json (`sheet_order`); 16x16 tiles sit at slot top.
- Tiles are drawn ON the outermost plateau cells and include their own grass top; transparent outside the rim, so ground shows through.
## Selection (P = plateau cell, mask N1|E2|S4|W8 = neighbour is plateau; stairs count as plateau)
1. !S && !E -> outer_se; !S && !W -> outer_sw; !S -> face_s_(a|b|c) (vary by hash of cell)
2. !N && !E -> outer_ne; !N && !W -> outer_nw; !N -> rim_n; !E -> rim_e; !W -> rim_w
3. all 4 present: diagonal SE missing -> inner_se, SW -> inner_sw, NE -> inner_ne, NW -> inner_nw, else cliff_top
4. cliff_stairs replaces a face cell (walkable ramp). cliff_shadow goes 2 rows below every face/outer_s/stairs cell.
Reference implementation: `pick()` in src/gen_cliffs.py. Seams: lip/bottom/rim profiles are pinned at x/y=0 and 15, so
any face variant abuts any other, and rims tile vertically/horizontally.
## v3 changes
Wider (5-7 px) columns split into 6-9 px blocks; outcrops 16x32 and boulder 16x24 (anchor bottom-centre); bright tuft; Cinder embers ~0.6%;
outer SE/SW wrap with a shaded side; inner SE/SW have a shaded rock lip; labelled contact sheet (3x + 1x per tile).
## Constraints / known issues
- Min. 2 empty rows below a south edge (face overhang + shadow); 1-tile-wide plateau strips have no dedicated tile.
- Outcrops are still fairly narrow/egg-shaped at 16 px wide; prop_rocks is small.
- Cinder ash top is busy; Cinder dirt patch reads purple-ish.
