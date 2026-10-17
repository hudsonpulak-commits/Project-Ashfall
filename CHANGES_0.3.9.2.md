# AshFall 0.3.9.2 (versionCode 21) - designer sprite overhaul

- Designer art batches 1 + 2 copied in unchanged (batch 2 wins where both have a file): 495 PNGs covering all humans/NPCs/creatures (side/front/back), the 168 gear overlays, fences, floors, transitions, wall caps, tiles, objects, buildings, items, UI/fx, plus new app icons (icon.png, main 192, adaptive fg/bg 432).
- Source: the designer's regenerated handoff (Dropbox "AshFall - ashfall_art_handoff_2026-10-16.zip"), because the originally approved files were lost in the box reset.
- Title: assets/ui/title_bg.png is Hudson's exact image (byte-identical, 2,395,221 bytes); the menu still hides its own AshFall label.
- Moat inner corners: new overlay layer 4 in world.gd (MOAT_CORNERS) with autotile/moat_border_corners (NE/SE/SW/NW).
- Art protection: tools/art/protected_art.json (496 files, sha256) + tools/art/art_guard.py imported by every generator; protected files removed from placeholders.json.
- Tests: patch0392_tests (moat corners in 4 directions and none in open moat / next to a bridge / along a straight bank; creature + goblin front/back frames are whole: at most 1 px on the frame edge, at least half the side width; protected list). The 0.3.9.1 back-shield test now checks only what is visible past the body (outer edge x <= 5).
- QA thresholds for the darker art: Scorch night luminance > 25 (was 30), gate torch warm pixels >= 3 (was > 6).
- Not done: bow draw pose (proposal), Saltmere port (cancelled).
