# AshFall 0.3.5 (versionCode 13)
- Music: changing area (ambient <-> town themes) now fades the old track out over 1.5 s before the new one starts. Combat still cuts in instantly.
- Fenhollow, Cinderholt, Saltmere: the plaza hearth ("oven") is removed. Cook in the Cook House; villages keep their hearths.
- New stone bank building in each city replaces the open plaza bank chest. It has a door, a counter with a Banker (tap to open the bank) and two bank chests inside. The minimap shows its walls. AIs bank there. Old saves standing (or with AIs) inside the new walls are moved out.
- Archery range is now 10 tiles (Chebyshev), still with line of sight.
- Training dummy gives 3x XP. It swings back every attack, always blocked (0 hitsplat, no damage), and each block gives Defence XP.
- Tests: unit tests (Patch035Tests, music fade). New QA scenario "bank" (C21 bank/plaza/AI banking, C22 archery at 9-10 tiles, C23 dummy block).
