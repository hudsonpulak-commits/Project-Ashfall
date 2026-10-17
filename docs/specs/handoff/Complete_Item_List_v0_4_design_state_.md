# ASHFEN — Complete Item List (v0.4 design state)
Handoff for Lead Game Developer and economy tuning.  
Max level 100. Tier 4 (dusk / dire wolf pelt, level 30) is mid-game. All numbers live in JSON.  
Prices are suggested Exchange ranges (marks). Shops can sit inside or at the edges of these. AI and players move prices inside the range. 2% Exchange tax applies on sales.

Legend for skill column:  
- **Material** = gathered or dropped, used by a skill  
- **Product** = made by a skill  
- **Both** = can be used further or is a finished good

## 1. Raw materials — Forestry
| Item | Skill | Type | Other uses | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Ash logs | Forestry 1 | Material | Fletching, Crafting, fuel | 2 | 6 | 1 | 4 |
| Alder logs | Forestry 12 | Material | Fletching, Crafting | 8 | 18 | 5 | 14 |
| Blackthorn logs | Forestry 25 | Material | Fletching, Crafting | 20 | 45 | 14 | 35 |

## 2. Raw materials — Mining
| Item | Skill | Type | Other uses | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Copper ore | Mining 1 | Material | Smithing (bronze) | 3 | 8 | 2 | 6 |
| Tin ore | Mining 1 | Material | Smithing (bronze) | 3 | 8 | 2 | 6 |
| Iron ore | Mining 12 | Material | Smithing (iron/steel) | 12 | 28 | 8 | 22 |
| Coal | Mining 20 | Material | Smithing (steel+), fuel | 18 | 40 | 12 | 32 |
| Dusk ore | Mining ~30 | Material | Smithing (dusk) | 40 | 90 | 28 | 70 |

## 3. Processed — Smithing bars
| Item | Skill | Type | Other uses | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Bronze bar | Smithing 1 | Product | Melee gear, ranger tier 1, arrowheads | 8 | 16 | 6 | 12 |
| Iron bar | Smithing 12 | Product | Melee gear, ranger tier 2, arrowheads | 30 | 60 | 22 | 48 |
| Steel bar | Smithing 20 | Product | Melee gear, ranger tier 3, arrowheads | 70 | 140 | 50 | 110 |
| Dusk bar | Smithing 30 | Product | Melee gear, ranger tier 4, arrowheads | 160 | 320 | 120 | 250 |

## 4. Raw materials — Foraging & hides
| Item | Skill | Type | Other uses | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Reeds | Foraging 1 | Material | Simple string, thatch | 1 | 4 | 1 | 3 |
| Wheat | Foraging 1 | Material | Flour, bread | 2 | 6 | 1 | 4 |
| Fenroot | Foraging 5 | Material | Cooking, Brewing later | 4 | 10 | 2 | 8 |
| Flax | Foraging ~15 | Material | Superior string | 6 | 14 | 4 | 11 |
| Cowhide | Foraging / cows | Material | Leather (Crafting) | 5 | 12 | 3 | 9 |
| Wolf pelt | Wolves (drop) | Material | Wolf pelt armour (tier 3) | 25 | 55 | 18 | 42 |
| Dire wolf pelt | Dire wolves / Greymaw | Material | Dire armour (tier 4) | 80 | 180 | 60 | 140 |

## 5. Processed — Crafting & Fletching intermediates
| Item | Skill | Type | Other uses | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Leather | Crafting (tan) | Product | Ranger armour, other crafting | 10 | 22 | 7 | 16 |
| Simple string | Crafting (reeds) | Product | Bows, other | 2 | 6 | 1 | 4 |
| Superior string | Crafting (flax) | Product | Higher bows | 8 | 18 | 5 | 14 |
| Plank | Crafting | Product | Construction later, basic | 4 | 10 | 2 | 7 |
| Arrow shaft (ash) | Fletching 1 | Product | Arrows | 1 | 4 | 1 | 3 |
| Arrow shaft (alder) | Fletching 12 | Product | Arrows | 4 | 10 | 2 | 7 |
| Arrow shaft (blackthorn) | Fletching 25 | Product | Arrows | 10 | 24 | 7 | 18 |
| Headless arrow | Fletching | Product | Finished arrows | 2 | 6 | 1 | 4 |
| Bronze arrowheads | Smithing | Product | Bronze arrows | 3 | 8 | 2 | 6 |
| Iron arrowheads | Smithing | Product | Iron arrows | 10 | 22 | 7 | 16 |
| Steel arrowheads | Smithing | Product | Steel arrows | 22 | 48 | 16 | 36 |
| Dusk arrowheads | Smithing | Product | Dusk arrows | 50 | 110 | 36 | 85 |

## 6. Melee weapons (Smithing products)
All require the matching Attack level. Visible on character.

| Item | Tier / Level | Type | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|
| Bronze dagger | 1 | Product | 15 | 35 | 10 | 26 |
| Bronze sword / shortsword | 1 | Product | 25 | 55 | 18 | 40 |
| Bronze mace | 1 | Product | 25 | 55 | 18 | 40 |
| Iron dagger | 10 | Product | 60 | 130 | 45 | 100 |
| Iron sword / longsword | 10 | Product | 100 | 220 | 75 | 170 |
| Iron battleaxe | 10 | Product | 110 | 240 | 80 | 180 |
| Steel dagger | 20 | Product | 180 | 380 | 130 | 290 |
| Steel sword | 20 | Product | 280 | 580 | 200 | 440 |
| Steel battleaxe / warhammer | 20 | Product | 300 | 620 | 220 | 470 |
| Dusk dagger | 30 | Product | 450 | 950 | 330 | 720 |
| Dusk sword | 30 | Product | 700 | 1450 | 500 | 1100 |
| Dusk battleaxe | 30 | Product | 750 | 1550 | 540 | 1180 |
| Garr's blade | Unique (iron+) | Product / drop | 200 | 450 | 150 | 340 |

## 7. Melee armour (Smithing products)
Defence level required. Metal armour boosts melee accuracy.

| Item | Tier / Level | Type | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|
| Bronze helm | 1 | Product | 20 | 45 | 14 | 34 |
| Bronze body | 1 | Product | 40 | 90 | 30 | 68 |
| Bronze legs | 1 | Product | 30 | 65 | 22 | 48 |
| Bronze shield / buckler | 1 | Product | 25 | 55 | 18 | 40 |
| Iron helm | 10 | Product | 80 | 170 | 60 | 130 |
| Iron body | 10 | Product | 160 | 340 | 120 | 260 |
| Iron legs | 10 | Product | 120 | 250 | 90 | 190 |
| Iron shield | 10 | Product | 100 | 210 | 75 | 160 |
| Steel helm | 20 | Product | 220 | 460 | 160 | 350 |
| Steel body | 20 | Product | 450 | 950 | 330 | 720 |
| Steel legs | 20 | Product | 340 | 720 | 250 | 550 |
| Steel shield | 20 | Product | 280 | 580 | 200 | 440 |
| Dusk helm | 30 | Product | 550 | 1150 | 400 | 880 |
| Dusk body | 30 | Product | 1100 | 2300 | 800 | 1750 |
| Dusk legs | 30 | Product | 850 | 1800 | 620 | 1350 |
| Dusk shield | 30 | Product | 700 | 1450 | 500 | 1100 |

## 8. Ranger armour (Crafting products)
Each piece = 1 hide/leather + 1 bar of matching tier. Boosts Ranged. Penalty if used for melee.

| Item | Tier / Level | Materials | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|
| Leather coif / body / legs | 1 | Leather + bronze bar | 30 | 65 | 22 | 48 |
| Studded leather body | 10 | Leather + iron bar | 90 | 190 | 65 | 145 |
| Wolf pelt coif / body / legs | 20 | Wolf pelt + steel bar | 200 | 420 | 145 | 320 |
| Dire wolf pelt coif / body / legs | 30 | Dire pelt + dusk bar | 500 | 1050 | 360 | 800 |

## 9. Ranged weapons & ammo (Fletching products)
| Item | Skill / Level | Type | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|
| Shortbow (ash) | Fletching 5 | Product | 20 | 45 | 14 | 34 |
| Longbow (alder) | Fletching 15 | Product | 60 | 130 | 45 | 100 |
| Longbow (blackthorn) | Fletching 25 | Product | 140 | 300 | 100 | 230 |
| Bronze arrows | Fletching | Product (stack) | 4 | 10 | 2 | 7 |
| Iron arrows | Fletching | Product (stack) | 12 | 28 | 8 | 21 |
| Steel arrows | Fletching | Product (stack) | 28 | 60 | 20 | 45 |
| Dusk arrows | Fletching | Product (stack) | 60 | 130 | 45 | 100 |

## 10. Food (Cooking products)
| Item | Skill | Type | Heals / notes | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Raw rat meat | Drop | Material | Cooking | 1 | 4 | 1 | 3 |
| Cooked rat | Cooking 1 | Product | Low heal | 3 | 8 | 2 | 6 |
| Raw chicken | Drop | Material | Cooking | 2 | 6 | 1 | 4 |
| Cooked chicken | Cooking 1 | Product | Low heal | 5 | 12 | 3 | 9 |
| Raw carp | Fishing 1 | Material | Cooking | 3 | 8 | 2 | 6 |
| Cooked carp | Cooking 1 | Product | Low-mid heal | 6 | 14 | 4 | 11 |
| Raw eel | Fishing 15 | Material | Cooking | 10 | 22 | 7 | 16 |
| Cooked eel | Cooking 15 | Product | Mid heal | 18 | 40 | 13 | 30 |
| Raw beef | Cows | Material | Cooking | 6 | 14 | 4 | 11 |
| Cooked beef | Cooking 5 | Product | Mid heal | 12 | 28 | 8 | 21 |
| Wolf meat | All wolves | Material | Cooking | 5 | 12 | 3 | 9 |
| Cooked wolf | Cooking ~8 | Product | Mid heal | 10 | 24 | 7 | 18 |
| Flour | Cooking / mill | Product | Bread | 3 | 8 | 2 | 6 |
| Bread | Cooking 3 | Product | Mid heal | 8 | 18 | 5 | 14 |

## 11. Bones & Prayer
| Item | Source | Type | Use | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Bones (rat/chicken/etc.) | Common drops | Material | Bury for low Prayer XP | 1 | 5 | 1 | 3 |
| Wolf bone | Wolves | Material | Bury for medium Prayer XP | 4 | 10 | 2 | 7 |
| Giant bone | Giants | Material | Bury for 20 Prayer XP | 25 | 55 | 18 | 42 |

## 12. Tools
| Item | Skill | Type | Use | Low buy | High buy | Low sell | High sell |
|---|---|---|---|---|---|---|---|
| Bronze hatchet | Smithing | Product | Forestry | 15 | 35 | 10 | 26 |
| Bronze pickaxe | Smithing | Product | Mining | 15 | 35 | 10 | 26 |
| Fishing rod | Crafting / Fletching | Product | Fishing | 10 | 25 | 7 | 18 |
| Knife | Smithing | Product | Fletching / Crafting anywhere | 8 | 20 | 5 | 15 |
| Needle + thread | Crafting | Product | Leather armour anywhere | 5 | 14 | 3 | 10 |

## 13. Quest & unique items
These are not normally traded. Listed for completeness.

| Item | Source | Notes |
|---|---|---|
| Patrol token, basalt tally, pier token, hide scrap, Greymaw's hide, Garr's blade (pre-turn-in) | Quests | Quest items: no sell, kept on death, removed or converted on turn-in |
| Garr's blade (post-turn-in) | Quest | Becomes normal tradeable iron+ sword |

## Economy notes
- Price floors and ceilings should be set in JSON around the low/high columns above.
- AI smiths, cooks, and traders use these ranges. Surplus gear is scrapped by the armourer.
- Dire pelts and dusk bars are the main mid-game sinks/faucets. Keep their ranges wide so the Scorch and Greymaw matter.
- Food and bones are high-volume, low-margin. Weapons and armour are lower-volume, higher-margin.
- All ranges are starting points. Tune after the AI economy has run for a few in-game days.

## Not yet in the game (do not add prices until designed)
Brewing potions, higher-tier ores/trees/fish beyond dusk/blackthorn, magic items, construction furniture, boats.
