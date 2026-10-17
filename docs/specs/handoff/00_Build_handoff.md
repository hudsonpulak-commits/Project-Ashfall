# ASHFEN — Build handoff
For Lead Game Developer. Cap is 100. Tier 4 (dusk / dire wolf pelt, level 30) is mid-game. All numbers in JSON. AI follow the same rules as the player except where noted.

## 1. Combat readability
Show combat level above every attackable actor: `Lv 14`. AI players may show name plus level. Color versus the player: green if 10+ below (they will not aggro), white within 9, yellow if 10–19 above, red if 20+ above. Toggle later. Default on.

Leash: each enemy stores its spawn tile. Drop aggro past 12 tiles from home, walk back, start regen only after standing on home for 3 ticks. AI players are not leashed. Guards leash to their gate post. Existing rule stays: no aggro if the player is 10+ combat levels above them.

## 2. Monsters
| Monster | Combat | Where |
|---|---|---|
| Chicken | 2 | Village fields |
| Rat | 5 | Town boardwalks, alleys, cottages |
| Goblin | 10 | Mid wilds, 60–90 tiles out, and the goblin camp |
| Wolf | 12 | Roads and farm edges |
| Guard | 25 | Gate posts. Passive unless attacked. Not the strongest thing on the map |
| Dire wolf | 28 | Low Scorch only, levels 3–8 (24–64 tiles north of y = -256). Packs of 2 |
| Giant | 30 | Iron-mine cave, ~68 tiles out. Do not leave the cave |
| Garr the Red | 32 | Goblin camp only |
| Greymaw | 34 | One of the three farms, quest then 10 min timer |
| Cinder brute | 40 | Deep Scorch, past level 8 |

All wolves drop wolf meat, not beef. Beef comes from cows.

Scorch is PvP and multi-combat everywhere north of y = -256. Depth sets the AI-player attack bracket only. Scorch level N means you may attack an AI player only if combat levels differ by at most N. Symmetric. Does not apply to monsters or NPC humans. Default 8 tiles per level, cap 40. Show `Scorch 7 (±7)` by the minimap. Dim an AI player's level if they are outside your bracket.

Giant cave: tunnel is single combat. Back chamber is the only multi-combat room outside the Scorch. Opens at 20 influence. Giants drop 1 giant bone (bury for 20 Prayer XP), iron ore 1/3, coal 1/8, steel bar 1/16.

## 3. Gear
Metal armour has two cuts. Plate is Defence. Chain is Attack, and the Attack is smaller than plate's Defence so chain never outscales plate. Ranger is one set, Ranged only. Wrong-style penalty is −8% accuracy.

Weapons: daggers accurate and weak, swords middle, axes and warhammers hit harder. Two-hand weapons block the shield slot. Garr's blade is an iron sword with 16 Attack and 13 Strength.

Shields: buckler (small, Attack) and kite (large, Defence). Buckler costs 1 bar. Kite costs 2. Both sold only at the Cinderholt shield store. Exchange can still list them.

Ranger piece = 1 hide + 1 bar of the same tier. Full set is 3 bars and 3 hides. Metal sets must cost more than 3 bars.

| Tier | Level | Melee | Ranger | Bar |
|---|---|---|---|---|
| 1 | 1 | bronze | leather | bronze |
| 2 | 10 | iron | studded leather | iron |
| 3 | 20 | steel | wolf pelt | steel |
| 4 | 30 | dusk | dire wolf pelt | dusk |

Dire pelt only takes a dusk bar and only makes the level-30 pattern. A wolf pelt cannot be upgraded.

Exact Attack / Strength / Defence numbers are in `ASHFEN_gear_stats.md`.

## 4. Drops that matter
- Ordinary wolves: wolf meat, wolf bone, wolf pelt.
- Dire wolves (Scorch, combat 28): wolf bone, wolf meat, wolf pelt 1/4, dire pelt 1/10, coal 1/20.
- Greymaw: quest hide (does not tan), 350 marks, 4 wolf pelts, 2 wolf meat. Timer kills: dire pelt 1/8.
- Giants: giant bone, 20 Prayer XP.

## 5. Quests and influence
Influence is a key, not a coin. Quests only. Not spent, not traded, not lost on death. AI ignore influence gates.

| Total | Unlocks |
|---|---|
| 0 | Tutorial |
| 4 | Village errands |
| 7 | City work |
| 10 | Scorch approach, Kell, Pye, Exchange errand |
| 20 | Giant cave |

Reward hand-in is atomic. If the pack cannot hold the items, the NPC says "Come back when you have space in your pack to receive the reward." Coins and influence wait. Next step only after the reward fits.

**Tutorial — Old Wren, Fenhollow only.** New character starts with an empty pack, nothing equipped, 0 marks. Wren gives every step. 1 influence each. Tools arrive on the quest before the one that needs them. Full chain in `ASHFEN_starter_quests.md`. Ends at 10 influence and 600 marks. No Exchange step. Exchange is taught in the capital.

**Goblin Slayer — Sergeant Kell, Fenhollow north gate.** Needs tutorial done and 10 influence. 5 steps, 2 influence each. Travels to Cinderholt then Saltmere, then the goblin camp (~80 tiles on the Fenhollow–Cinderholt road). Ends on Garr the Red, combat 32. Rewards are the melee kit: iron helm, iron longsword, steel med-helm, Garr's blade. Does not require Pye.

**Dire Wolf — Warden Pye, Fenhollow east boardwalk.** Same gate as Kell. Either line first. 5 steps, 2 influence each. Farms at Millbrook, Barrowby, Oxley. Ends on Greymaw, combat 34. Rewards are the ranger kit: leather coif, studded body, wolf pelt body. Greymaw's quest hide does not tan. Dire pelt is from later kills and from Scorch dire wolves.

Doing either line reaches 20 influence and opens the cave. Doing both is not required.

## 6. Capital
One capital at the map center (placeholder name Highfen). Elegant: pale stone, market square, exchange hall, paved streets, gardens. Focal point. Bank, church altar, cook house, player-store row, player-house row, guards at 25. No specialty weapon store. Roads spur in from the three towns.

**Exchange.** One board, in the capital hall only. It is the player trading market. Players and AI post offers. The board has no stock of its own. Any item can be looked up, sold, or bought if someone has listed it. Floor and ceiling on every item. 2% tax on the seller. Cancel returns goods or coins. No haggle. Most convenient. Not always cheapest.

**Town stores.** Always in stock, only their select goods, spread across the map. Fixed price near the Exchange mid. Never empty.

| Place | Stores |
|---|---|
| Fenhollow | Bank, general store, blacksmith, church, cook house, tanning rack. Specialty: helmets, swords and daggers, archery |
| Cinderholt | Same services. Specialty: body armour, shields (bucklers and kites), battle axes |
| Saltmere | Same services. Specialty: leggings, maces and warhammers |
| Capital | Bank, altar, cook house, Exchange hall, player-store row, player-house row. No specialty weapon store |
| Villages | No stores. Well, quern, hearth, field, pasture, tanning rack |

**Player stores.** Capital only. One plot, 1,500 marks rent, weekly upkeep, 8 stands, till at the counter. Owner sets the price. Undersell the Exchange mid to pull customers. Over the mid and buyers use the hall. AI prefer 5–15% under the mid and buy more from a full varied shelf. A store sale is not an Exchange trade and pays no Exchange tax.

**Player houses.** Capital only. One per character. Bought once.
- Bank chest. Same bank as the town chests.
- Bed. Refills Energy and Prayer to full, instantly. Does not heal HP. Does not pass time. 60 second cooldown.
- Crafting station and smithing station, bought after the house. Same recipes, same costs, no XP bonus. The bonus is not walking to a town.

One store and one house. They do not stack. AI can run a store. AI do not buy houses.

## 7. Item XP (per action)
Prayer bury: bones 5, wolf bone 7, dire wolf bone 12, giant bone 20. Altar gives no XP.

Forestry: ash 8, alder 18, blackthorn 32.
Mining: copper/tin 6, iron 16, coal 24, dusk ore 40.
Fishing: carp 8, eel 22.
Cooking: rat 5, chicken 6, carp 8, bread 10, beef 12, wolf 14, eel 22. Burn is 0.
Smithing bars: bronze 8, iron 18, steel 28, dusk 42. A finished item at that tier: 12, 28, 45, 70. Body pays the same as a dagger.
Crafting: tan 8, leather piece 14, studded 28, wolf pelt piece 45, dire piece 70.
Fletching and full price ranges are in `ASHFEN_item_xp.md` and `ASHFEN_item_list.md`.

Combat skills get XP from hits, not from items.

## 8. Do not build yet
Brewing potions, combat magic, Construction beyond the two house stations, boats, a second Exchange, a giant boss, a second dire wolf, ranged and fletching quests until those skills are in.

## 9. Suggested build order
1. Nameplates, leash, Scorch bracket.
2. Plate / chain, buckler / kite, ranger bar costs, wolf meat.
3. Wren tutorial.
4. Remove town Exchange boards. Capital hall as the only Exchange.
5. Player store and house in the capital, with bank chest, bed, station upgrades.
6. Kell and Pye lines, goblin camp, Greymaw, Scorch dire wolves.
7. Giant cave at 20 influence.
