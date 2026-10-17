# ASHFEN — Influence and the Fenhollow tutorial quests
Handoff for Lead Game Developer. Tutorial quest line. Cap is 100; tier 4 at level 30 is mid-game. These quests stop around level 10.

## Influence
A separate point total, shown on the quest journal. It is not coins and not XP.

- Only quests grant it. No buy, no trade, no Exchange.
- Spent nothing. It is a key, not a currency. Thresholds unlock quests and, later, areas.
- Death does not remove it. Scorch death does not remove it.
- Save it with the character.

Suggested thresholds, in `data/influence.json`:

| Total | Unlocks |
|---|---|
| 0 | Fenhollow tutorial line |
| 4 | Village errands (Millbrook, Barrowby, Oxley) |
| 7 | City work in Cinderholt and Saltmere |
| 10 | Scorch approach camps (not the deep Scorch) |
| 20 | First dungeon / goblin cave, when it exists |

Tutorial pays 1 influence per quest, 10 for the full line. Later quests pay more. The cave stays past the tutorial so it needs village and city work, not just Wren.

AI players ignore influence gates. They already have jobs, homes, and Scorch raiders. Gating them would stall the economy. The gate is for the player only.

Quest items are flagged quest-items: no sell, no drop on death, removed when the step completes. Rewards that are real gear are the player's to keep. Amounts stay small so ten quests do not flood Fenhollow with free bronze.

Every quest pays three things: influence, coins, and one low-level item or a stack of supplies. Coins are paid by Old Wren — a one-time faucet of 600 marks per new character, about four player-shop rents, not enough to skip smithing. Items are level 1 only. No iron, no steel, no food better than cooked rat or carp.

A new character starts with an empty pack and 0 marks. Nothing is equipped. The chain is how they get a hatchet, pickaxe, weapon, food, and rod. No shop purchase is required to finish it.

Reward hand-in is atomic. Influence, coins, and items are given together when the step is turned in. If the pack cannot hold the item reward, Wren does not complete the quest. He says: "Come back when you have space in your pack to receive the reward." Bank or drop something, talk to him again. Coins are not given early. The next quest is offered only after the reward has fitted.

Tools are rewarded on the quest before the one that needs them. Wren never asks for a hatchet, pickaxe, or rod the player has no way to own yet.

## Journal
One active starter quest at a time, in this order. Later chains can be parallel. Each step points at a map marker. Completion is checked by the game (item in pack, ore mined, bone buried), not by dialogue alone.

Talk is one line from the NPC plus the objective. No multi-page lore in this pass.

## The chain — Fenhollow tutorial
Giver: Old Wren, an old man who exists only in Fenhollow (north boardwalk; name swappable in NPC JSON if a starter NPC already exists). He gives every tutorial quest. No other NPC hands these out. Guards and the shopkeeper are talked to during a step; they do not offer the next one.

This is the tutorial line, not a side chain. On login with no quest started, Wren has a marker. Finishing a step does nothing until the player talks to him, has pack space, and takes the reward. He then offers the next tutorial quest himself. One active quest. Refusing is not a fail — talk to him again.

Each quest pays 1 influence. Ten quests, 10 influence. Coins and the level-1 item still pay on every step.

### 1. The palisade (1 influence)
Teaches movement, gates, talking. Needs no items.
- Walk the four gates. Each gate guard has a one-line check-in.
- Report back to Wren.
- Reward: 50 marks, 1 influence, a bronze hatchet, 10 cooked carp. First items they own.

### 2. A dry pack (1 influence)
Teaches foraging and the bank. Reeds need no tool.
- Pick 5 reeds outside the palisade.
- Bank them, withdraw them, hand them to the general-store keeper.
- Reward: 40 marks, 1 influence, a bronze pickaxe (used in quest 4).

### 3. Ash for the watch (1 influence)
Teaches forestry. Uses the hatchet from quest 1.
- Cut 8 ash logs at the Fenhollow trees (level 1).
- Bring them to the general store.
- Reward: 40 marks, 1 influence, 20 ash arrows and a spare bowstring. Fenhollow specialty. Vendor trash until ranged is in, then ammo.

### 4. Copper and tin (1 influence)
Teaches mining and the furnace. Uses the pickaxe from quest 2.
- Mine 3 copper and 3 tin at the near mine (~22 tiles out).
- Smelt 3 bronze bars at the blacksmith furnace.
- Keep the bars. They are for quest 5, not a hand-in.
- Reward: 50 marks, 1 influence, a bronze helm.

### 5. A blade of your own (1 influence)
Teaches the anvil. Uses the 3 bars from quest 4.
- Smith a bronze dagger (level 1 smithing) at the anvil. Make 1.
- Equip it. Wren does not take it.
- Reward: 60 marks, 1 influence, a bronze shortsword. They now have a dagger and a sword; either can fight rats.

### 6. Rats on the boardwalk (1 influence)
Teaches combat, food, death being non-fatal. Uses the dagger or shortsword, and the carp from quest 1.
- Kill 6 rats inside or just outside Fenhollow.
- Cook 3 of the meat at the cook house. Eat 1.
- Reward: 80 marks, 1 influence, 15 cooked rat meat. Wren speaks the death rule once: outside the Scorch you keep items and lose 10% coins. No forced death.

### 7. The altar (1 influence)
Teaches Prayer.
- Bury 3 bones (rat bones count).
- Refill at the Fenhollow church altar.
- Activate any one prayer buff and let Wren see it.
- Reward: 40 marks, 1 influence, a fishing rod and 20 bait (or 20 feathers if bait is not in yet). The rod is for quest 8.

### 8. Lines in the marsh (1 influence)
Teaches fishing. Uses the rod from quest 7.
- Catch 4 carp at the Fenhollow water.
- Cook 2 at the cook house.
- Reward: 50 marks, 1 influence, a leather body (level 1). Wearing it is optional.

### 9. The south road (1 influence)
Teaches the road out. The Exchange is not in Fenhollow.
- Walk the road marker toward the capital spur. Do not require entering the capital.
- Return to Wren.
- Reward: 70 marks, 1 influence, 15 bones.

### 10. Wren's blessing (1 influence)
Closes the chain.
- Bury 3 bones anywhere in Fenhollow.
- Report back. Wren offers nothing further here. Village errands opened at 4, city work at 7. Finishing this quest reaches 10 influence, which opens the Scorch approach. The Exchange is in the capital and is taught there, not here.
- Reward: 120 marks, 1 influence, 20 cooked carp.

Coin total: 600 marks. Influence total: 10. Item total, in the order they are earned: hatchet, carp, pickaxe, arrows, bowstring, helm, shortsword, rat meat, rod, bait, leather body, bones, more carp. Plus the dagger they smith and keep. All level 1. Selling the lot should pay less than doing the skills.

## After this chain
Do not build them yet. Names only, so the thresholds have a target:

- Village errands at 4: Millbrook wheat, Barrowby well, Oxley cows. Each pays 2 influence. Teach farming-adjacent foraging, not a new skill.
- City work at 7: Cinderholt furnace order, Saltmere pier catch. Each pays 2 influence.
- Scorch approach at 10: Wren warns you, you walk to the line, you leave. No kill required. Unlocks the approach camps.

## Not in this pass
No quest for ranged, fletching, or brewing until those skills are in. No influence shop. No fail state other than "not done yet".
