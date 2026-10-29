# 0.3.20 (versionCode 37)

Lore geography and the first story props. Plate and chain armour from 0.3.19 are unchanged.

## Villages

Millbrook, Barrowby, and Oxley moved as units (buildings, NPCs, farms, pastures, quest givers, map markers). Roads were rebuilt.

- Millbrook sits on the road north of Highfen toward Cinderholt. Origin (180, -152), plaza (213, -125). Its road runs to Highfen. The Goblin Warlord camp and the rat nest moved with it.
- Barrowby is the southernmost village, between Highfen and Saltmere. Origin (228, 62), plaza (240, 69). Its road runs to Saltmere. The new site is lake and cliff, so the village yard (and the gap out to the fields) is filled with grass. Authored walls stay.
- Oxley is the quiet village east of Highfen. Origin (310, -8), plaza (322, -2). Its road runs to Highfen.
- An old save whose player is standing inside a village footprint that moved, and not inside that village's new footprint, is placed on the new plaza. Bank and player-shop data are left alone. Save version 10.

## Lore

- The quest id stays `wolf_pelts`. The display name is Night of 1000 Howls. The Dire Wolf (part 2) is not in this build.
- Elijah's tomb outside Saltmere has fresh flowers and candles.
- A raided trader cart sits beside the Fenhollow–Highfen road. Burnt cottages stand by the Cinder Brute camps. Cyan magic mushrooms grow by the rat den. The Northern Guard camp has a supply wagon and a spiked barrier. Each church has a scaffold plank (one prop, not a stack of the plank item).
- Lay keepers say the head priest is up north, holding the Scorch Line with Prayer. Highfen townsfolk talk about newborn Prince Elijah, the twins Avery and Sophia, little Princess Kylie, and Queen Jessica. Brannoc and Voss blame the ore shortage on Cindervill falling to the Scorch. Saltmere guards remember Elijah as the old trainer.
- Player-facing text does not call the player a hero or a chosen one, and does not name the Ash Demon. The internal adventurer id `hero` still shows as Adventurer.

## Scene

Crates, barrels, fence sections, flowers, and signposts are scattered through towns and villages, off the roads. Houses put up a small chimney puff. Birds flee when you walk up to them. Frogs sit in the Fenhollow marsh. Butterflies cross the meadows. None of them can be fought.

## Checks

- Selftest: PASS 1230/1230
- Boot QA on the Android pack (official Linux release template): PASS 12/12
- QA bot: PASS 219/219
- Worst game-work frame on the perf sprint: 25.9 ms (gate 33 ms). Under software GL the process peak was 54.2 ms and the wall-clock frame peak was 54.5 ms. The gate is the game-work time.

Lore source copied to `docs/specs/AshFall_Official_Lore_2026-10-29.md`. The 21 October briefing still applies where that file is silent.
