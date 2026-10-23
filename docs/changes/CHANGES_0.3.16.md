# Ashfall 0.3.16 (versionCode 32)

The remaining four lore side quests, each +5 Influence, all in data/quests.json.

| Quest | Giver (placement) | Steps | Rewards |
|---|---|---|---|
| We Need Steel! | Brannoc the smith, Cinderholt anvils | gather 5 iron ore + 10 coal -> Guard steel; deliver to Sgt Voss at the Northern Guard camp | +5 Inf, 300 marks, 1500 Smithing XP |
| Can We Fix It? | Farmer Garrow, Garrow farm SW of Cinderholt (site garrow_farm) | hand in 8 planks; broken fences + damaged wall are drawn mended after | +5 Inf, 150 marks, 700 Joinery XP |
| Finding Clip Clop | Wenna Tamsin, Tamsin farm E of Fenhollow (site tamsin_farm) | kill 3 wolves at the wolf den (site wolf_den); Clip Clop follows you home; he then stays in the paddock | +5 Inf, 150 marks, 500 Defence XP |
| A Dead Rat is a Good Rat | Old Mabel, Millbrook (town data, movable by data edit) | kill 6 giant rats, report, kill the Rat Mother by the rat-den entrance (site rat_den), report | +5 Inf, 120 marks, 500 Strength XP, 4 cooked rat meat |

Engine additions: multi-stage quests with a stage NPC (dialog_npc), "give" items, escort/follower stage, repair_quest props (world_object repaired sprite, fence autotile), quest sites (data stamps), no_attack enemies, follower AI (enemy.gd), quest "encounter" data that pins a boss camp to a site point (plane "surface"; 0.3.17 moves the Rat Mother underground with a data edit).

New placeholders: farm wall (intact/damaged), wolf den (also used as rat hole), Clip Clop = tinted cow, Rat Mother = scaled tinted giant rat.

Known gaps: QA puts ore/coal/planks in the pack directly (not mined/bought); these items don't stack; wolves count for Clip Clop wherever killed.
