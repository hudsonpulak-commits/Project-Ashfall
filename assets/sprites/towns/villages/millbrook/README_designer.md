# Villages v1: Millbrook + farm/pasture kit + ruined churches + NPCs
Rebuild everything: `python3 src/gen_village.py && python3 src/churches_sheet.py && python3 src/preview_millbrook.py && python3 src/npcs.py && python3 ../../_rules/door_check.py .`
- buildings/<name>_{floor,walls,(upper1),roof,night}.png (same canvas). The roof of mb_rat_cellar is not used (it is an underground interior).
- tiles/: vl_diag_{road,meadow,bank,tilled} (45deg corner autotiles), vl_wheat_stages (6 stages), vl_fence_autotile(_broken) (N1|E2|S4|W8, 16x20), vl_fence_gate(_open), water.
- props/: farm, pasture, quest, graveyard and mill sails (mb_mill_sails_4f, 4x64x64).
- npcs/: odric_hunter{,_front,_back}.png (64x24, 4-frame walk, same layout as villager.png); quartermaster_hale{,_front,_back}.png (32x24, 2-frame walk, same layout as town_guard.png).
- Previews: preview_millbrook_scene_3x.png, churches_sheet_3x.png, npc_sheet_preview.png, interior_closeup_*_4x.png, layout/door_crops_2x.png

## Roof/mill revision (2026-10-23)
- Thatch (th..th5, varied wear) on all non-stone village buildings.
- Stone-walled buildings: mb_mill = conical weathered wood-shingle cap; mb_house_06 = muted clay tile; ruins: chapel = wood shingle, church = slate, shrine = clay tile, all holed with rafters showing.
- mb_mill: round stone tower (re-rounded after the rules grow step), cap sized to the tower, 88px sails centred on the cap apex/hub.
