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
- Side shield art: replaced the flat 0.3.9.3/0.3.9.4 stopgap with the designer's
  redrawn side sheets (art_handoff/shields_side, 20 files; approval relayed via the
  parent agent). Opaque inside every outline (alpha 0/255 only). The only adjustment:
  shield_kite_1..4 frame 2 had 4 pixels enclosed between the body and the shield
  ((10,11),(10,19),(11,20),(11,21)), filled with the face colour by
  fix_side_shields_0394.py. The other 16 sheets are byte-identical to the handoff.
  No per-facing offset needed: anchored on the near hand, the shield draws over the
  body facing left and peeks out in front of the chest from behind facing right.
