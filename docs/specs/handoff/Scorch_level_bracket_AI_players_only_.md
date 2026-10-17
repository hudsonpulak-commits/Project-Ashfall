# ASHFEN — Scorch level bracket (AI players only)
Handoff for Lead Game Developer.

The Scorch stays PvP and multi-combat everywhere north of the line (y ≤ -256). Depth into the Scorch sets how far apart two combat levels may be before an AI player can be attacked. This is not a gear tier. Tier 4 (level 30) is still mid-game; combat cap is 100.

## Rule
On a Scorch tile of level N, a player or AI player may attack an AI player only if the combat levels differ by at most N.

- Scorch level 1: only ±1.
- Scorch level 10: ±10.
- Same check for AI attacking the player, and AI attacking AI. They follow the same rule.

Does not apply to monsters or NPC humans (guards, citizens, shopkeepers, later bosses). Those keep current combat rules, including "no aggro if the player is 10+ combat levels above them" and the leash.

Out-of-bracket click: no swing, short message ("Too large a level gap for this part of the Scorch"). No skull from a refused hit.

## How N is calculated
Home edge of the Scorch is y = -256 (already the biome line). Depth is how far north of that line the actor is standing.

```
depth_tiles = max(0, -256 - y)
scorch_level = clamp(1 + floor(depth_tiles / tiles_per_level), 1, scorch_level_cap)
```

Defaults, in `data/world.json` so they can change without code:

- `tiles_per_level`: 8. Level 1 is the first 8 rows north of the line. Level 10 starts 72 tiles in. Level 30 starts 232 tiles in.
- `scorch_level_cap`: 40 for now. Deep enough that a level 1 and a level 41 cannot meet, not so deep that the whole cap of 100 is open on the current map.

The tile you are standing on is the one that counts, not the target's tile. Chasing someone south into a shallower band can make the next hit illegal. Standing still on the border uses your tile.

## UI
While in the Scorch, show `Scorch 7 (±7)` near the minimap. That is the local bracket.

Nameplates from the level-over-head pass stay. In the Scorch, dim an AI player's level label if they are outside your current bracket, so a legal target is obvious before the click. Monsters are never dimmed for this rule.

## Unchanged
- Skull: whoever lands the first legal hit on another player or AI player is skulled for 10 minutes and keeps nothing on death.
- Scorch death: keep your 3 most valuable items, the rest goes to the killer.
- Single combat outside the Scorch. This bracket does not exist on the continent south of y = -256.
- Monsters and NPC humans ignore N entirely.

## Low Scorch monsters added with this
Dire wolves, combat 28, Scorch levels 3 to 8 only. Not the farm dire wolf Greymaw (combat 34). Drops and leash are in the dire wolf quest handoff. They do not use the player bracket. Any combat level may attack them.
