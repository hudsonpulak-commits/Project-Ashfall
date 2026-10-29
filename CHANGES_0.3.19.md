# 0.3.19 (versionCode 36)

- Custom bank tabs are on. Create a tab with +, rename it by typing (no enter key needed), set its icon from the picked item, and delete it. In Arrange, tap an item and then a tab to file it; tap a slot to move or swap as before. Tabs, names, icons and filing are saved.
- Sprite-clip selftest: a sliced frame edge fails the run, including palms on the side they lean.
- Trees, palms and bushes sway slightly in the wind. The trunk stays put, the motion stays on whole pixels, and each sprite's phase comes from its position so one shared material is enough.
- A tree crown fades while you stand behind it. A tall roof fades to 40% on the tile just north of the building, and still fades out completely while you are inside.
- Ground tiles pick up a soft world-space colour variation. Grass beside roads and doors wears toward dirt, with a ragged edge so it does not read as a rectangle. Ash, stone and water are left as painted.
- Scorch nights stay readable: the zone night floor is lifted so the ash field does not drop out under the night tint. The QA night shot dismisses the entry report first, because that panel was swallowing the walk tap and the camera never reached the border.
- Selftest and the QA bot use a seeded RNG. QA waits (except the perf measurement) advance on a fixed 1/60 s step so a slow frame cannot expire a timeout early.
- Melee armour (bronze, iron, steel, dusk, including the metal shields) comes in Plate and Chain. Plate keeps the old defence and adds a smaller hit bonus. Chain swaps those numbers, so both have the same power. Both are smithed at the anvil from the same bars at the same smithing level, and need the same Defence level. Helmet, body and leg shops sell both; chain shields are anvil-only. An old save's armour is the plate piece (same item id). The tooltip and the worn-gear line show +hit% and +block%. Defence XP per piece is unchanged. Leather, wolf pelts and the alder buckler are unchanged.
