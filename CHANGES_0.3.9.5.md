# AshFall 0.3.9.5 (versionCode 24)

## Full-face helmets in every facing
- Hudson: helmets read as full-face from the front but open-faced from the side.
- Designer redo (Hudson-approved per the designer): new full-face side helmets
  head_1..4.png (closed visor + eye slit in the helmet's colours).
- tools/art/fix_full_face_helmets_0395.py: per frame, paints any part of the
  body's head (player/npc: face, hair, ears, eyes, mouth, neck skin) a helmet
  leaves uncovered as a closed faceplate. A no-op on the designer's sheets (0 px).
- patch0395_tests: no body skin-tone pixel in the head rows of any helmet
  composite (player + npc, down/left/right/up, every frame); helmets alpha
  0/255 only; no enclosed helmet/body gap; head layer always over the body.

## Same tier = same colours in every facing
- Cause: not code. Gear layers have no tint and gear_<slot>_<tier> maps to the
  right files; the side sheets (0.3.9.2 designer art) and the front/back sheets
  (0.3.9.1 generator) simply used different tier palettes (T1 gold vs bronze,
  T2 light grey vs dark iron, T3 teal vs steel/white, T4 purple vs dusk/red).
- Designer redo: all 112 front/back gear sheets (head/body/legs, shields,
  weapons) redrawn in the side sheets' tier palettes. Side body/legs/weapon
  sheets unchanged.
- patch0395_tests: per tier and armour piece the dominant hue matches across
  side/front/back (or all greys), and every front/back armour colour is one of
  that tier's side colours.

## Side shield behind the body
- Facing right (shield in the far/left hand, behind the body) the shield layer
  is drawn 1 px forward (Actor.gear_layer_offset); facing left/front/back: no
  offset. QA bot templates follow.
- The shift opened 1-px holes between body and shield edge on some frames
  (round f2, heater, kite f1/f2, tower): closed with the shield's outline ink by
  tools/art/fix_shield_offset_gaps_0395.py (48 px over 16 sheets; bucklers 0).
- Tests: in-game offset (+1 facing right, 0 facing left), every shield still
  peeks out 6+ px behind the body, no enclosed gap with the offset.
