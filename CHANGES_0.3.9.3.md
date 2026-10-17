# AshFall 0.3.9.3 (versionCode 22) - side-view shield fix

- Bug: walking left/right, the shield looked transparent or invisible.
- Root cause (art, not engine): the 0.3.9.2 designer side sheets `assets/sprites/actors/gear/shield*.png` (all 20: round/buckler/heater/kite/tower x 4 tiers) had the body silhouette cut out of the shield - the back view's "only the edge peeks out" mask had been applied to the side view as well. The engine draws the shield layer over the body from the side (z-order and modulate were correct; no gear_item_* shield overrides exist), so what showed was a hollow ring outline with the body visible through it.
- Fix: `tools/art/fix_side_shields_0393.py` fills each row between the shield's outer edges with its face colour (existing pixels kept). Side shields are now solid in front of the body; front sheets untouched; back sheets untouched (still hidden under the body except the outer edge). protected_art.json re-hashed.
- Test: patch0393_tests - for every shield sprite, every side frame has 40+ opaque px, 12+ over the body and no holes.
