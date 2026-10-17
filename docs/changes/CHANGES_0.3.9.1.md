# AshFall 0.3.9.1 (versionCode 20) - graphical fixes (Hudson's GRAPHICAL_FIXES.md)

## 1. Creatures: one head, one rear
- Audit: the 0.3.9 front/back sheets mirrored half of the side frame, so creatures got 2 heads (front) or 2 rears (back), and guards got 2 spears. All 82 directional sheets were redrawn by `tools/art/placeholders_0391.py` (side sheets untouched):
  - creatures (cow, wolf, rat, chicken): front = head-on (body narrowed, ONE centred head), back = rear view (body narrowed, tail stub, no head); symmetric blobs (slime) keep their one view;
  - goblins / warlord / cinder brute: a centred face on the front, eyes removed on the back.
- Flip logic re-checked: only the side sheet mirrors (for left); front/back are never mirrored.

## 2. Clean human fronts
- Player, AI players and human NPCs: the body and legs come from the side frame (walk frames kept, nothing doubled); the head is rebuilt symmetric: hair fringe, face, 2 symmetric eyes and a mouth. Hats/helmets stay; the back shows hair or the helmet.

## 3. Shields behind the body from the back
- Shield back sheets keep only the outer edge that peeks out beside the body, and the shield layer is drawn under the body while facing away (over it from the front/side). The town guard's baked-in shield is hidden the same way on its back sheet.

## 4. Fences: runs of 3+, clear ends
- Road-fence generation removes any 4-connected run shorter than 3 tiles (`road_rules.decor.fence_min_run`), so there are no lone posts or lone diagonals; pastures and fields were already long runs.
- Every run ends clearly: a stout capped end post (most ends) or a broken end (snapped stump with the last rail sagging to the ground, ~30% of rural ends). New, clearly readable end pieces in `autotile/fence_rural`.

## Validators / tests
- Unit (`src/tests/patch0391_tests.gd`): no front/back frame equals a mirrored half of the side frame (colour compare), creatures are narrower head-on/from behind, human fronts have 2 symmetric eyes, shield back sheets only show the edge, the shield layer sits under the body when facing away, every fence is a run of 3+ with no posts/diagonals, every run endpoint is an end piece (post or broken).
- QA: new `gfx` scenario + C32 checks (frames: cow_right/left/down/up, player_front_shield, player_back_shield, fence_end_post, fence_end_broken).
