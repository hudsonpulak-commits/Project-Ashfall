# 0.3.11 (versionCode 27): Highfen redesign + designer cliffs

## Highfen (revised: tiled roads and walls, laid out after Hudson's reference)
- **Revision:** the painted roads and the smooth ring art are gone. Roads are road_stone and cobble tiles that bend, jog and step, with widths of 1–3 tiles. There are 2 irregular, stepped cobble ring roads and spoke streets from the 4 cardinal gates to a big cobble plaza at the centre.
- The city wall is a thick (2-tile) stepped oval of capital_wall tiles (autotiled), with gate_capital gates at N/S/E/W and 12 round wall towers (placeholder art).
- The plaza has a fountain at its centre (placeholder art). The palace stands on its north side, the church to the west and the Guild of Knights to the east, and the market stalls fill its south side.
- 17 houses pack the blocks between the rings, and 25 civilian houses circle the city outside the wall.
- Original 0.3.11 notes follow; the decal and ring-art parts below are superseded.
- Highfen is now a round walled city built from the designer's art in art_handoff/towns/highfen. The moat is gone; the wall (CITY_RING) blocks movement using the ring art's alpha. There are 4 gates (N/S/W/E), and the curved roads plus the plaza are painted as a ground decal.
- Inside the walls: the palace and throne room at the centre (a talk-only "hall"), the Guild of Knights (highfen_guild), the church, the bank, the general store, the cookhouse, the baker, the player shop (its 8 stands are on the market plaza) and the player townhouse (its stations and bank chest are in a walled work yard). There are about 6 houses inside the walls and 24 civilian houses outside them.
- Layered art buildings are walk-in. The plan comes from floor alpha. Walls are y-sorted, and the upper storeys plus the roof fade out while the player is inside. A long frame no longer makes a roof pop: the fade step is clamped to 1/30 s.
- tools/world/build_highfen_v2.py runs a road/building overlap check and a reachability check, and exits 1 if either fails. The last run found 0 overlaps and 0 reach failures.
- Guards, citizens and the hall greet lines are updated.

## Cliffs
- The designer cliff tiles (normal and cinder, 28 each) are autotiled with the N1|E2|S4|W8 mask plus diagonals. South faces are 16x32 and hang into the next row (CLIFF_FOOT), with the shadow 2 rows below.
- 2 rows must be clear below every south edge; otherwise that spot becomes stairs. Cinder region uses the cinder set.
- Diagonal cliff gaps are filled with a corner that never blocks a stair or road. Diagonal steps between two blocked tiles are forbidden.

## QA bot
- The moat checks are now city-wall checks. The townhouse stations are found through object meta (the yard). The _outside() helper never places an actor on another building's floor. An AI customer at a plaza stand counts as a customer (shop_spot accepts stand-adjacent street tiles for the player shop).
