# AshFall 0.3.9.4 (versionCode 23)

## Side-view shield fixes
- Bleed-through root cause: the side shield sheets were already fully opaque
  (no semi-transparent pixels, no holes inside the outline). The "see-through"
  pixels were enclosed gaps BETWEEN the body and the shield in some walk frames
  (e.g. frame 1, x=11, y=14..17) where neither layer drew anything, so the
  ground showed through. tools/art/fix_side_shields_0394.py paints those gap
  pixels (and any enclosed non-opaque shield pixel) with the shield face colour
  per frame; protected_art.json re-hashed.
- Per-facing layer order (Actor.gear_layer_plan): shield is in the LEFT hand.
  - side, facing right: shield is the far hand -> drawn under the body.
  - side, facing left: shield is the near hand -> drawn over body/head;
    weapon (right hand, now far) drawn under the body.
  - up: shield under the body (unchanged); down: unchanged.
- Fixed child re-ordering so it is contiguous and index-safe.
- QA bot C19 templates composite per facing with the same order.
- Tests: patch0394_tests (opaque-inside-outline flood fill per frame, no enclosed
  body/shield gap, layer plan rules); patch0391 side test updated.
- Not used: art_handoff/shields_side (not marked Hudson-approved).
