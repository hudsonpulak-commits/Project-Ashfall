# ASHFEN — Weapon and armour stats
Handoff for Lead Game Developer. Cap is 100. Tier 4 is mid-game. All numbers in JSON.

Combat uses the existing three ratings: Attack (accuracy), Strength (max hit), Defence (blocking). Ranged is the accuracy stat for bows. A piece only adds the stats listed. Empty slots add nothing.

Metal armour comes in two cuts at every tier. Plate favours Defence. Chain favours Attack, and the Attack it gives is smaller than the Defence plate gives, so plate is the safer buy and chain is the aggressive one. Ranger armour is unchanged: one set, Ranged only.

Wrong-style penalty: metal worn while using a bow, or ranger worn while using a melee weapon, is −8% accuracy. The penalty is on the style you are using, not a stat on the piece.

## Weapons
Attack and Strength are the only weapon stats. Defence on a weapon is 0.

| Weapon | Level | Attack | Strength |
|---|---|---|---|
| Bronze dagger | 1 | 4 | 3 |
| Bronze sword | 1 | 6 | 5 |
| Bronze mace | 1 | 5 | 6 |
| Iron dagger | 10 | 10 | 7 |
| Iron sword | 10 | 14 | 11 |
| Iron battleaxe | 10 | 12 | 15 |
| Steel dagger | 20 | 18 | 13 |
| Steel sword | 20 | 24 | 19 |
| Steel battleaxe / warhammer | 20 | 20 | 26 |
| Dusk dagger | 30 | 28 | 20 |
| Dusk sword | 30 | 36 | 28 |
| Dusk battleaxe | 30 | 30 | 38 |
| Garr's blade | 10 | 16 | 13 |

Daggers are accurate and weak. Axes and warhammers hit harder and miss more. Swords sit in the middle. A shield is worn with a one-hand weapon. Battleaxes and warhammers are two-hand: no shield slot.

## Shields
Two cuts at every metal tier. A kite is the defence shield. A buckler is the small round attack shield, and the Attack it gives is smaller than the Defence the kite gives, same rule as chain versus plate.

| Shield | Level | Attack | Defence |
|---|---|---|---|
| Bronze buckler | 1 | 3 | 1 |
| Bronze kite | 1 | 0 | 6 |
| Iron buckler | 10 | 6 | 2 |
| Iron kite | 10 | 0 | 13 |
| Steel buckler | 20 | 10 | 3 |
| Steel kite | 20 | 0 | 21 |
| Dusk buckler | 30 | 15 | 5 |
| Dusk kite | 30 | 0 | 30 |

A kite is slightly stronger than the old single shield, because it is now the dedicated defence option. A buckler never outscales the kite at the same tier. One-hand weapons only. Two-hand weapons still block the shield slot.

Smithing: a buckler costs 1 bar. A kite costs 2 bars. The extra bar is the defence tax, so kites do not flood the Exchange the way a 1-bar shield would. Both cuts are sold only at the shield shop in Cinderholt. Fenhollow does not stock bucklers. The Exchange can still list either if a player or AI posts one.

## Melee armour — plate (defence)
Helm, body, legs. Plate body is the big defence piece. Pair it with a kite.

| Piece | Level | Attack | Defence |
|---|---|---|---|
| Bronze plate helm | 1 | 0 | 4 |
| Bronze plate body | 1 | 0 | 8 |
| Bronze plate legs | 1 | 0 | 6 |
| Iron plate helm | 10 | 0 | 9 |
| Iron plate body | 10 | 0 | 18 |
| Iron plate legs | 10 | 0 | 13 |
| Steel plate helm | 20 | 0 | 15 |
| Steel plate body | 20 | 0 | 30 |
| Steel plate legs | 20 | 0 | 22 |
| Dusk plate helm | 30 | 0 | 22 |
| Dusk plate body | 30 | 0 | 44 |
| Dusk plate legs | 30 | 0 | 32 |

Full bronze plate, no shield: 18 Defence. With a bronze kite: 24. Full dusk plate, no shield: 98 Defence. With a dusk kite: 128.

## Melee armour — chain (attack)
Chain has no shield of its own. Pair it with a buckler. A chain user can still wear a kite, and they pay for that: the kite is pure Defence, the chain is mostly Attack.

| Piece | Level | Attack | Defence |
|---|---|---|---|
| Bronze chain helm | 1 | 2 | 1 |
| Bronze chain body | 1 | 4 | 2 |
| Bronze chain legs | 1 | 3 | 1 |
| Iron chain helm | 10 | 5 | 2 |
| Iron chain body | 10 | 9 | 4 |
| Iron chain legs | 10 | 6 | 3 |
| Steel chain helm | 20 | 8 | 3 |
| Steel chain body | 20 | 14 | 6 |
| Steel chain legs | 20 | 10 | 4 |
| Dusk chain helm | 30 | 12 | 5 |
| Dusk chain body | 30 | 20 | 8 |
| Dusk chain legs | 30 | 14 | 6 |

Full bronze chain: 9 Attack, 4 Defence. With a bronze buckler: 12 Attack, 5 Defence. Full dusk chain: 46 Attack, 19 Defence. With a dusk buckler: 61 Attack, 24 Defence. Attack on chain plus buckler stays under Defence on plate plus kite at the same tier. Chain never outscales plate.

Smithing: chain costs the same bars as plate at that tier. The cut is a recipe flag, not a cheaper set. AI smiths make both. If chain stops selling, they make less of it, same as any other gear.

## Ranger armour (unchanged)
One set. No plate or chain split. Each piece is 1 hide + 1 bar of the matching tier, as already specced. Stats are Ranged only.

| Piece | Level | Ranged |
|---|---|---|
| Leather coif / body / legs | 1 | 3 / 6 / 4 |
| Studded coif / body / legs | 10 | 6 / 12 / 8 |
| Wolf pelt coif / body / legs | 20 | 10 / 20 / 14 |
| Dire wolf pelt coif / body / legs | 30 | 15 / 30 / 20 |

A ranger helm is the coif. There is no ranger shield. A metal buckler or kite can be worn with a bow and takes the wrong-style penalty.

## Slot rules
Head, body, legs, weapon, shield, ammo. Chain and plate can be mixed. A dusk plate body with a bronze chain helm is legal and just adds the two stat lines. The wrong-style penalty checks the majority of armour slots: if two or more of head, body, legs are metal, melee is the style those slots support. If two or more are ranger, Ranged is. A 1-and-1 mix with a one-hand weapon and shield counts the shield as metal.

## Not in this pass
No Strength on armour. No Prayer bonus on metal. No third cut (leather-and-mail, trimmed). Repair cost can key off tier later. It does not change these stats.
