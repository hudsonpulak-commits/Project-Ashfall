# AshFall 0.3.6 (versionCode 14)
- Ammo slot: new "ammo" equipment slot (Pack > Worn shows e.g. "Bronze x5"). Equipping arrows moves the whole stack in. Bows fire only from the ammo slot; arrows left in the pack are not used ("Out of arrows!"). Old saves auto-equip the best pack arrows on load. AI archers still use the arrows in their pack.
- Tools to gather: trees need a hatchet and ores a pickaxe, either in the pack or wielded. Without one you get "You need a hatchet." / "You need a pickaxe." and gather nothing. New players and AIs start with both, and the general store sells them.
- Food: cooked foods heal more by tier (rat meat/chicken 4, carp 5, bread 6, beef 8, eel 14). No Cooking-level scaling.
- Flint (general store): Pack > Light on flint or a log lights a cooking fire on the ground. Uses 1 flint + 1 log and gives Forestry XP (ash 2, alder 3, blackthorn 4). The fire works as a hearth and burns 2/3/4 min by log tier, then goes out. Data in data/fire.json.
- Enemies: every HP ×1.5 (rounded up). Giant rat is level 5, goblin 8, town guard 30, with stats raised to match. Wolf goes to level 6 so the distance difficulty order still holds.
- Music: night in the wilds plays the new night ambient (ambient_night.ogg, 56 kbps mono). Day and night ambient fade over 1.5 s. Town and combat tracks are unchanged.
- Tests: Patch036Tests unit tests. New QA scenario "v036": C24 ammo, C25 tools, C26 fire, C27 food, C28 night music.
