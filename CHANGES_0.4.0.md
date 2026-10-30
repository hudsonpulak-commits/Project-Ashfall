# AshFall 0.4.0 (versionCode 38)

## Ranged
- Archery is now shown as **Ranged** (internal id `archery` kept for save compatibility).
- Line of sight with no range limit (combat.json range 99, effectively the whole screen).
- Ammo, including dusk arrows. Ranger armour boosts Ranged: ranged_atk = bow atk + gear rng; ranged_str = bow str + rng×2.
- Ranger tiers (need Crafting to make, Ranged to wear): leather 1, studded 10, wolf pelt 20, dire pelt 30. Defence XP on hit: leather, studded and wolf pelt 0.5; dire pelt 1. Plate and chain are unchanged.

## Fletching (replaces Joinery)
- Use a knife on a log to open the window, then pick a quantity (1/5/10/All): arrow shafts, headless arrows, arrowheads, unstrung bows.
- Joinery XP moves to Fletching (save v11 migration). Old joinery recipes move to Crafting.

## Tanning and Crafting
- Tanning rack and vat: hides → leather, tanned wolf and dire pelts.
- Crafting with a needle and thread makes ranger armour.
- A Crafting Supply in every city (Fenhollow, Saltmere, Cinderholt, Highfen), with a spinning wheel, tanning rack and vat. The wheel spins reed → simple string and flax → superior string.
- Flax is a new Foraging crop that grows wild on grassland.

## Quest: Night of 1000 Howls, part 2
- Warden Pye in Fenhollow gives it. It needs part 1 (wolf_pelts) done, and old saves are told about it on load.
- 11 stages through Millbrook, Barrowby, Saltmere (Quill) and Cinderholt (Venn: deliver items or pay 200 marks), ending with the hunt for **Greymaw**, the named dire wolf, at a farm. Afterwards she roams the farms on a timer.
- Rewards: 400 marks, influence and the wolf pelt body. New dire wolf packs in the low Scorch.

## World and art
- 125 new sprites. Greymaw and dire wolf each have walk, idle, attack and death strips.
- Elijah's tomb has a 32×40 headstone with a night glow and a path, so it is easier to find.
- World map labels no longer collide, and the map version comes from project.godot.

## Tests
- New patch040 tests. The selftest passes 1288/1288.
