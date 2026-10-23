# Art gaps 0.3.14

## Cinderholt / Northern Guard camp
- No armoured Northern soldier sprite: northern_soldier reuses town_guard with a darker steel tint.
- No spiked barricade / cheval-de-frise prop in the handoff (lore asks for spiked fences and barriers); palisade + gate only.
- Camp fits 3 of the tent variants (ng_tent_01/02 unused for space next to the training yard).

## Resized sets (sprite bot: fenhollow_v2, saltmere_v4, highfen_v5, cinderholt_v2) - integrated 0.3.14
The old under-5x5 audit list is superseded: every walk-in art building in the 4 art towns is now >= 5x5 (selftest patch0314 "every art building ... at least 5x5"). Only exception: v3_elijah_tomb (4x4, a monument, not walk-in).
- Saltmere: the v3 harbour entrance arch is NOT resized (still the v3 art over the north road). v3_smithy_large and v3_elijah_tomb are still v3 (not in saltmere_v4).
- Saltmere: one designer-layout house sits inside the old fort ring; we use our own layout (no fort, no walls), so nothing fort-related came back.
- Saltmere v4 generator reads highfen/tiles_v3 (wall tower/gatehouse only); the Saltmere build uses only saltmere v4 tiles_v2 (Saltmere has no walls).
- Highfen v5: a few house designs repeat (pool of 28 designs for 36 homes); repeats are alternated with horizontal flips. No roof-colour variants (a tint would need per-design roof masks; not done cleanly) - more house variants welcome.
- Highfen v5: the bigger buildings do not all fit between the plaza and the inner ring road: the tavern, general store and player shop now stand just outside the wall by the ring road. A slightly smaller variant (<= 6x5) of those three would let them move back inside.
- Northern Guard camp: ng_tent_02 and ng_tent_04 not placed (no room in the camp at the v2 sizes).
- Night: *_night.png layers used for every v2 building (ADD blend, driven by the day/night light level); the old overlay is gone.
- Fenhollow boardwalk: the fixed fh_boardwalk_autotile.png + fh_boardwalk_blob47.png are used; the code corner patch is removed.

## Fenhollow shoreline / transition (0.3.14 steering)
Done with existing art: noisy inland shoreline via fh_diag_marsh_bank, dithered pixel fade into world grass,
ragged mud-landing aprons (fh_diag_mud_path) at all 76 boardwalk/land joins, fh_stilts as landing posts,
denser fh_reeds_a/b/c on banks, fh_mud_fill clumps thinning grass toward the palisade.
Missing for sprite bot:
- cattail prop (reeds_a/b/c stand in)
- mooring post / stake props (fh_stilts stands in)
- grass<->mud ragged edge autotile (currently pixel-dithered mud fill)
- world-grass<->marsh blend tiles for the town rect edge (currently dithered alpha)
- world road-end blend: the world-side 3-wide path stub outside the west gate is a world tile and stays square
