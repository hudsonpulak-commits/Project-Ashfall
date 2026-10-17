# ASHFEN — Dire Wolf quest line
Handoff for Lead Game Developer. Same tier as Goblin Slayer. Either line can be done first. Neither requires the other.

## Who gives it
Warden Pye, Fenhollow east boardwalk. Not Wren, not Kell. Marker appears when the tutorial is finished and influence is at least 10. If the player is already on Kell's line, Pye still offers this one. One active step per line.

Same pack rule. If the reward will not fit, Pye says "Come back when you have space in your pack to receive the reward." Coins and influence wait. Next step only after the reward fits.

Each step pays 2 influence. Five steps, 10 influence. Tutorial (10) plus this line ends at 20. Tutorial plus both lines ends at 30. The cave threshold stays 20, so either line alone opens it.

AI ignore the gate. Ordinary wolves exist anyway. The dire wolf does not spawn until step 5 is active, then uses the respawn rule below.

## The farms and the wolf
Three village farms are already on the map: Millbrook wheat, Barrowby pasture, Oxley cows. The dire wolf has been hitting those, not the cities. It is not a normal wolf with more HP. It is a named enemy, Greymaw, combat level 34. Bigger sprite if one exists, otherwise the wolf sprite scaled up and a darker coat, swappable in `data/sprites.json`.

Greymaw max hit should be survivable in studded leather with the food from step 1, not in an empty pack. She does not aggro until attacked. Leash 16 from whichever farm tile she is on when the fight starts. Overhead level uses the existing nameplate colors. Single combat. Not the Scorch. Normal death rule.

She is not in a camp. She rotates. While step 5 is active she is at one of the three farms, picked at random when the step starts, and the journal marker points at that farm. If the player leaves the leash, she stays at that farm until killed. After turn-in she respawns every 10 minutes at a random one of the three farms, so the villages stay threatened and the pelt supply does not sit on one tile.

Ordinary wolves on the roads stay combat 12. They are not Greymaw.

## Ranger armour this line is feeding
Wolf pelt armour is level 20. Dire wolf pelt armour is level 30. Do not tan Greymaw's quest hide into either set.

Each ranger piece costs the hide plus 1 bar of the same tier. One bar, not a plate. Metal armour keeps its existing higher bar cost. Ranger is a small metal sink, not a way around the forge.

| Tier | Ranger piece | Level | Hide | Bar |
|---|---|---|---|---|
| 1 | leather | 1 | 1 cow leather | 1 bronze |
| 2 | studded leather | 10 | 1 leather | 1 iron |
| 3 | wolf pelt | 20 | 1 wolf pelt | 1 steel |
| 4 | dire wolf pelt | 30 | 1 dire pelt | 1 dusk |

Dire pelts come from two places: Greymaw, and the lesser dire wolves in low Scorch below. A quest hide does not tan.

A helm, body, and legs are three pieces, so a full ranger set is 3 bars and 3 hides. A metal set at the same tier must stay above 3 bars or the ranger set undercuts the forge. If a metal body is currently under 3 bars, raise the body, do not raise the ranger piece.

Make it at the tanning rack, or in the crafting window once that exists. The bar is consumed with the hide. No bar, no piece. A dire pelt only accepts a dusk bar and only makes the level-30 pattern. A wolf pelt cannot take a dusk bar. A dusk bar cannot upgrade a finished wolf pelt piece.

## The line

### 1. The Millbrook flock (2 influence)
Needs 10 influence, tutorial complete.
- Pye has had a runner from Millbrook. Two cows are gone and the fence is down.
- Go to Millbrook. Talk to the farmer at the pasture. Inspect the broken fence (one interact). Optional: two wolves, combat 12, at the field edge.
- Return to Pye with the farmer's account (quest item, a hide scrap).
- Reward: 150 marks, 2 influence, 15 cooked beef, a leather coif (level 1 ranger). First gear from this line is leather, not a sword.

### 2. Saltmere hides (2 influence)
The wolf is eating stock, so the harbour is short of hides. Reverse of Kell's city order.
- Take Pye's hide tally to Harbournaster Quill at the Saltmere piers.
- Quill keeps the tally and gives a pier token (quest item). One line: no wolf hides have come in for three days, and the carts from Cinderholt are late too.
- Return the token to Pye.
- Reward: 200 marks, 2 influence, a knife if crafting is in, otherwise 20 feathers and 30 bait.

### 3. Cinderholt carts (2 influence)
- Pye sends you to Smith Venn at the Cinderholt furnace, not Hest. A cart of iron ore never arrived; Venn thinks it was hit on the farm road.
- Venn wants 10 iron ore, or 200 marks if they cannot mine it yet. Either satisfies the step. No level-20 skill gate.
- He marks the stretch of road between Oxley and Barrowby.
- Return to Pye.
- Reward: 200 marks, 2 influence, a studded leather body (level 10 ranger). Sits in the pack if it cannot be worn yet. Does not replace Kell's iron helm.

### 4. Barrowby watch (2 influence)
- Go to Barrowby. The farmer there has sat up two nights.
- Kill 8 wolves on the Barrowby and Oxley fields. Road wolves from step 1 do not count. Wolves must be on the farm tiles or within 12 tiles of either village well.
- Talk to the Barrowby farmer again. He has seen a wolf that does not run, pale across the muzzle. That is the dire wolf. He does not ask you to fight it yet.
- Reward, paid by Pye on return: 250 marks, 2 influence, 8 wolf pelts. These are ordinary pelts for the level-20 set. Sellable.

### 5. Greymaw (2 influence)
- Pye names her and sends you to the marked farm. Kill Greymaw (combat 34).
- Always drops Greymaw's hide (quest item until turn-in: kept on death, no sell), 350 marks, 4 wolf pelts, 2 wolf meat. The 4 pelts are ordinary wolf pelts, not dire.
- Bring the hide to Pye. He keeps it for the bounty. It is not returned, and it does not tan. The payment is the reward.
- Rare extra on timer kills only, 1 in 8: 1 dire wolf pelt. Not on the quest kill, so the quest kill is not the farm. Dire pelt plus 1 dusk bar makes one level-30 ranger piece, and nothing weaker.
- Reward: 400 marks, 2 influence, a wolf pelt body (level 20 ranger), made from ordinary wolf, not dire. If wolf pelt armour is not in yet, pay 8 wolf pelts and 200 extra marks instead. Do not pay a dire piece, and do not fall back to a steel chainbody. This line stays on the ranger side.

## Totals
Influence: 10, same as Goblin Slayer.
Coins: 1,200 from Pye, plus 350 on Greymaw, 1,550 total. Slightly under Garr's 1,600.
Gear: leather coif, studded body, wolf pelt body (level 20). Supplies: beef, feathers, bait, ordinary wolf pelts. No dire pelt from the quest itself. No iron weapon, no steel med-helm. Both lines together are a melee set from Kell and a ranger set from Pye, with dire pelt armour still to be tanned from later Greymaw kills.

## Combat notes
Under combat 18, Pye warns and does not block. Overhead level shows red if she is 20 above the player. Farm NPCs do not help and do not aggro.

## Lesser dire wolves in low Scorch
Not Greymaw. A pack enemy, combat level 28, named on the overhead as Dire wolf. Almost her strength: about 90% of her max hit and HP, slower attacks, no special. They lose if the player is 10 or more combat levels above them and will not aggro. Leash 12 from their spawn.

Place them only in Scorch levels 3 to 8 (24 to 64 tiles north of y = -256). Not on the entrance line, not in the deep Scorch. Two or three packs of 2, spread out, not a camp on the road. The Scorch multi-combat rule applies, so they can be piled on, and they pile on inside their leash.

Drops, each kill:
- Always: 1 wolf bone, 1 wolf meat.
- 1 in 4: ordinary wolf pelt.
- 1 in 10: 1 dire wolf pelt.
- 1 in 20: 1 coal.

Greymaw stays the better farm (1 in 8 dire pelt, plus her marks). These are the supply that exists before anyone finishes Pye's line, and the supply for players who never hunt her again. No dusk bar on the drop. The bar still has to be smithed.

Killing a Scorch dire wolf does not advance Pye's quest. Killing Garr does not either. Farms stay single combat.
