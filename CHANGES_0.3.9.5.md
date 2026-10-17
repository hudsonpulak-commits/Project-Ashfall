# AshFall 0.3.9.5 (versionCode 24)

## Full-face helmets in every facing
- Hudson: helmets read as full-face from the front but open-faced from the side.
- tools/art/fix_full_face_helmets_0395.py paints, per frame, every part of the
  body's head (player.png and npc.png for that facing: face, hair, ears, eyes,
  mouth in rows 0-10, plus neck skin on row 11) that the helmet did not cover
  into the helmet sheet as a closed faceplate: the helmet's own plate colour,
  ink where the plate meets the silhouette edge, and a dark eye slit on the
  body's eye row. Idempotent; protected_art.json re-hashed.
- Sheets changed: head_1..4 side (biggest change: the visor), head_1_front (the
  leather cap was open-faced from the front too), and small neck/chin fills on
  head_2..4_front and head_1..4_back.
- All helmet sheets alpha 0/255 only; no enclosed gap against the body.
- Tests: patch0395_tests (no body skin in the head rows of any helmet composite,
  player + npc, down/left/right/up, every frame; opacity; no gaps; head layer
  always over the body).
