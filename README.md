# Ashfen

An original top-down, tile-based skilling RPG for Android: an MMO-feel world where every other "player" is an AI and the economy is driven by supply and demand. Built with Godot 4.7.2 (GDScript, 2D, GL Compatibility).

- Design: [`docs/GDD.md`](docs/GDD.md)
- Build/toolchain: [`docs/BUILD.md`](docs/BUILD.md)
- Art drop-in guide: [`docs/ART_GUIDE.md`](docs/ART_GUIDE.md)

```bash
./scripts/test.sh            # headless gameplay tests (1199 checks)
./scripts/build_web.sh       # -> build/web/
./scripts/build_android.sh   # -> build/android/ashfen-debug.apk
./scripts/build_android_release.sh  # -> small release APK (custom template), signed with the debug keystore
godot --headless --path . -- --fresh --soak=7 [--no-traders] --soak-out=$PWD/build/soak7t   # economy soak test
python3 tools/soak_chart.py build/soak7t build/soak7n   # chart + arbitrage comparison
./scripts/screenshots_m2.sh  # -> screenshots/m2_*.png (towns, world map, shops, goblin combat, prayer)
```

**Controls:** tap the ground to walk; tap trees, rocks, pools, reeds, the dummy, hearth, furnace, workbench, anvil, shops, bank chest or Exchange board to use them. Tap a creature to attack it. Tap items lying on the ground to pick them up. In the pack, tap an item to Eat, Bury, Equip or Drop it, and tap a worn piece to take it off. Skills > Prayers starts or stops a prayer buff, which drains prayer points (the Prayer bar beside the minimap). Skills also has the combat style buttons (Accurate = Attack XP, Aggressive = Strength XP). Tap the Energy bar beside the minimap to sprint (2 tiles per tick while energy lasts). Burying bones refills them. The Map tab shows the continent, and its "To <Town>" buttons walk you along the roads. Tap the minimap to walk there. On desktop: WASD/arrow keys to step, `I` for the pack, `K` for skills, and the mouse wheel to zoom.

Original game. All names, art and numbers are original; not affiliated with any other game or company.
