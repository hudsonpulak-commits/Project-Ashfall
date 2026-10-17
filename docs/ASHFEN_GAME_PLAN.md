# ASHFEN — Full Game Plan & Roadmap
*(Paste this into Grok to keep brainstorming. When ideas are final, bring the decisions back to Lead Game Developer to build.)*

## 1. Vision
- Original top-down, tile-based skilling RPG for **Android** (phone, portrait). Inspired by the *feel* of classic MMO skilling RPGs, not a copy.
- **Single-player that feels like an MMO:** ~52 AI players who level, trade, fight, die and get replaced by "new players".
- **Organic supply/demand economy** with regulations (price floors/ceilings, 2% Exchange tax, coin sinks).
- **Pixel art.** Current art is AI placeholder; Hudson will hand-draw final art. Every sprite is swappable through `data/sprites.json` without code changes (see `docs/ART_GUIDE.md`).
- Engine: Godot 4.7, GDScript, 600 ms game tick. All content is data-driven JSON (`data/*.json`).

## 2. Current state (v0.3.2 — in Dropbox /Game)
**World:** One continent surrounded by ocean, 3 walled cities, 3 villages, roads gate-to-gate around lakes.
- **Fenhollow (0,0):** marsh town, wooden palisade, boardwalks, thatch. Specialty shops: helmets, swords & daggers, archery.
- **Cinderholt (330,-200):** forge city, basalt walls & towers, cobbled grid. Specialty: body armour, shields, battle axes.
- **Saltmere (300,170):** harbour town, sandstone walls, plaster/blue roofs, piers. Specialty: leggings, maces & warhammers.
- Every city: bank chest, general store, blacksmith (furnace + anvil inside), stone church (altar refills Prayer), cook house (oven + cheaper finite food), player shop for sale, Exchange board, gates with 2 guards each.
- **Villages:** Millbrook, Barrowby, Oxley — cottages, well, quern, hearth, wheat field, cow pasture.
- **Mines by distance:** copper+tin near each city (~22 tiles) → iron (~68) → coal (~115) → richest ore in the Scorch.
- **Enemies by distance from town:** chickens → rats → wolves → goblins → cinder brutes (Scorch only). Guards and citizens in towns (passive).
- **The Scorch:** northern map (y ≤ -256), charred-earth biome, PvP + multi-combat everywhere.
- Day/night: 10 min day, 5 min night, dusk/dawn fades, torches and lit windows.

**Systems already built:**
- Walk-in buildings with roof cut-away; shopkeepers behind counters.
- Player shop: 1,500 marks per town, 8 display stands, AI buy more for good deals and full, varied shelves; till collected at the counter.
- Combat: one-on-one except in multi-combat zones. Attack (accuracy), Strength (max hit), Defence (blocking). Combat level = floor((Atk+Str+Def+Vit)/4 + Prayer/8). Enemies don't aggro if you're 10+ combat levels above them.
- Gear tiers: bronze 1 / iron 10 / steel 20 / dusk 30. Visible gear layers on the player and AI.
- Prayer: one timed buff at a time, **30 s per Prayer level** (just changed), refilled by burying bones or the church altar.
- Sprint with an energy bar; HP / Prayer / Energy bars by the minimap.
- Map markers (8 icons, 8 colours, labels), main menu with 3 save slots, loading screen.
- Drops are private for 1 min, then AI can loot them.
- **Death:** normal = keep items, 10% coin fee. **Scorch:** keep your 3 most valuable items, the rest drops to the killer; whoever attacks first is skulled for 10 min and keeps nothing.

**AI players:**
- 40 economy AI (woodsman, prospector, angler, farmer, smith, cook, trader, acolyte…), each with a home town, focus skills and buy/sell lists.
- 12 adventurers: 6 heroes (PvE, chase best-in-slot gear), 4 raiders (hunt in the Scorch), 2 opportunists.
- Same skills/XP/level requirements as the player. AI that die in the Scorch quit and are replaced by a level-1 "new player"; their bank is sold off as an estate sale.
- Smiths make less when gear doesn't sell; an armourer buys surplus gear for scrap (anti-glut).

**Skills now (max level 60, content stops at ~15–32):**

| Skill | Content |
|---|---|
| Forestry | ash 1, alder 12, blackthorn 25 |
| Mining | copper/tin 1, iron 12, coal 20 |
| Angling | carp 1, eel 15 |
| Foraging | reeds/wheat 1, fenroot 5 |
| Smithing | bronze 1–9, iron 12–20, steel 20+, dusk ~30 |
| Joinery | plank 1, rod 4, shortbow 5, buckler 6, longbow 15 |
| Cooking | rat/chicken/carp/flour 1, bread 3, beef 5, eel 15 |
| Brewing | EMPTY |
| Attack / Strength / Defence | gear requirements up to 30 |
| Vitality | HP |
| Prayer | 6 buffs |

## 3. Decided for v0.4 (designed, not built yet)
1. **Angling → Fishing** (rename; saves and AI carried over).
2. **New Ranged combat skill:** bows + arrows (ammo slot, arrows consumed). No range limit, but needs line of sight: blocked by walls/buildings, can shoot over plants, rocks and fences. Walks to get a clear shot.
3. **Joinery → Fletching (ranged gear only).** Knife on a log, anywhere, opens the crafting window.
   - Log → unstrung bow; + string → usable bow (short/long per log tier).
   - Log → arrow shafts (ash 10, alder 15, blackthorn 20).
   - Shafts + feathers → headless arrows; + arrowheads (bronze/iron/steel/dusk, smithed at the anvil) → arrows.
4. **New Crafting skill:** takes over planks, rods, buckler etc. from Joinery. Needle + thread in your pack lets you sew leather into armour anywhere.
   - Old Joinery XP carries over to both Fletching and Crafting.
5. **Tanning rack** (villages + cities, small fee): cowhide → leather; wolf pelt → wolf leather.
6. **Ranger armour tiers** parallel to metal: leather 1, studded leather (leather + iron) 10, wolf pelt 20, tier 30 TBD. Ranger armour boosts Ranged; metal armour boosts melee accuracy. Wearing the wrong type for your style gives a small penalty.
7. **Crafting Supply store** in each city with a spinning wheel: reeds → simple string (most crafting/fletching); flax (new Foraging crop) → superior string (higher-level gear).
8. **Crafting window for ALL production:** pick the item + quantity (1/5/10/All/custom) before making anything. Smithing still at the anvil, cooking at a range/oven, etc.

## 4. Open questions to brainstorm
- **Level 30 ranger armour material?** (A new creature hide: Scorch beast, boar, bear, fen drake?)
- **Brewing:** what herbs/ingredients, which potions (stat boosts, Prayer restore, energy, antipoison?), and where do you brew?
- **Content for levels 33–60** in every skill: new ores, trees, fish, foods, a tier above dusk, harder monsters/bosses.
- **Fishing:** more spots and fish, tools (rod, net, harpoon), bait.
- **Foraging:** more plants (herbs for Brewing, flax, mushrooms), seasonal or night-only spawns?
- **Magic skill?** Runes/staves, or leave it out to keep the game grounded.
- **Other skill ideas:** Farming (plant & grow crops), Thieving (pickpocket citizens, stalls), Agility (shortcuts, energy regen), Construction (furnish your player shop / a house), Hunting/Trapping (pelts, feathers).
- **Quests/NPC stories:** small quests from villagers, guards, priests?
- **Bosses / dungeons:** a goblin warlord, a Scorch dragon, caves under the mines?
- **Player shop decor:** displays/décor that raise attractiveness.
- **Marking the world map:** which other areas become multi-combat zones?
- **Economy:** new coin sinks (repairs, tolls, housing), bank interest?
- **Pets, mounts, boats** (sail to islands)?
- **Settings menu:** sound, music, UI scale, left-handed layout.
- **Sound & music.**

## 5. Proposed roadmap
| Version | Theme | Contents |
|---|---|---|
| **0.4** | Ranged & Crafting | Everything in section 3 + crafting window + Prayer 30 s/level (done) |
| **0.5** | Brewing & Foraging | Herbs, flax, potions/tonics, more Foraging plants, more Fishing spots & fish |
| **0.6** | Levels 30–60 | New ore/bar tier, new tree, new fish, tier-5 gear (melee + ranger), harder camps, a first boss |
| **0.7** | Quests & NPCs | Short villager quests, guard/priest storylines, quest journal |
| **0.8** | World expansion | Dungeons/caves, islands by boat, new multi-combat zones from Hudson's map |
| **0.9** | Polish | Settings, sound & music, tutorial, balance pass, performance on low-end phones |
| **1.0** | Hudson's art | Swap all placeholder sprites for hand-drawn art; Play Store prep |

## 6. Rules to keep (house rules for design)
- Data-driven: every number and sprite lives in JSON so it can be tuned without code.
- Single combat by default; Hudson decides multi-combat zones.
- The AI follow the same rules as the player.
- Every change must keep the economy simulation healthy (no runaway inflation/deflation).
- Every build is tested in the real game and booted from the actual phone build before release, plus glitch checks; Hudson's bug reports become new automated checks.

## 7. How to hand ideas back
When you've decided on features in Grok, send a list to Lead Game Developer like this:
"0.4 final: [feature] — [exact numbers/levels/items]", and include answers to any open questions. Short bullet lists build fastest and cheapest.
