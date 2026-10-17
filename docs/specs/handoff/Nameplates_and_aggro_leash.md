# ASHFEN — Nameplates and aggro leash
Handoff for Lead Game Developer. Two combat-readability rules. Data-driven numbers in JSON.

Context: combat level cap is 100. Tier 4 (dusk / cinder leather, level 30) is mid-game best until later tiers. Nameplates must still read clearly when levels run from 1 to 100.

## 1. Combat level above heads
Show combat level on every attackable actor: enemies, town guards, citizens that can be attacked, and AI players. Not on shop objects, drops, or passive scenery.

Formula already in game: `floor((Atk + Str + Def + Vit) / 4 + Prayer / 8)`. Display that integer, updated when gear or Prayer changes the level.

Label format: `Lv 14` centered above the sprite, under any existing name. AI players may show name plus level (`Bram  Lv 22`). Enemies show level only, unless they already have a unique name (warlord later).

Color versus the player's combat level:
- Green: their level is 10+ below the player (they will not aggro; safe).
- White: within 9 levels either way.
- Yellow: 10–19 above the player.
- Red: 20+ above the player.

Hide the label when the actor is off-screen or farther than the current draw distance. Do not hide it in combat. Toggle in the future settings menu (`show_levels`, default on). Font size stays readable in portrait on a phone; no extra health bar in this pass.

## 2. Leash — aggro dies away from spawn
Every enemy stores a home tile, set to the tile it spawned on. Guards use their gate post. AI players are not leashed (they roam by their own AI).

Drop aggro when the target is more than `leash_tiles` from that home tile. Suggested default: 12 tiles (about two screens of chase, not a map-wide hunt). Put `leash_tiles` per enemy type in the enemy JSON so a wolf can be 10 and a later boss can be 18.

On break:
- Clear target.
- Stop attacking.
- Walk back to the home tile.
- Do not regen to full on the way. Start regen only after they have stood on the home tile for 3 ticks (1.8 s). Prevents reset-kiting for free heals.
- If the player is still inside leash range when they arrive home, they may re-acquire. If the player left the radius, they idle.

Existing rule stays: enemies do not aggro at all if the player is 10+ combat levels above them. Leash does not override that.

Town guards keep their current behavior inside the walls. If a guard is pulled outside, the same leash applies from their post so they cannot be dragged into the woods.

## Not in this pass
No click-to-inspect panel, no weakness text, no aggro radius circle on the ground. Level color plus the leash is the readability fix.
