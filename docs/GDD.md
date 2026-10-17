# Ashfen: Game Design Document (Milestones 1–2)

Owner: Hudson · Engine: Godot 4.7.2 (GDScript, 2D, Compatibility renderer) · Target: **Android first** (iOS deferred)

Ashfen is an original top-down, tile-based skilling RPG. It should feel like a busy MMO, but it is single-player: everyone else in the world is an AI player who gathers, crafts, banks and trades in the same economy you do. It is inspired by the *feel* of classic tile MMOs (tap-to-walk, 0.6 s ticks, gathering nodes, a bank, a market). It borrows no names, art, data or numbers from any existing game. All names, art, formulas and balance numbers in this document and in `data/` are original.

---

## 1. Pillars

1. **A world that lives without you.** AI players have names, jobs, schedules and stashes. They take trees before you get there, flood the market with ore after a mining boom, and buy your fish when food is scarce.
2. **An honest economy.** Prices come from real supply and demand (an order book), not a lookup table. Regulations stop it spiralling: bands, tax, sinks, circuit breakers and an inflation monitor.
3. **Short, satisfying sessions on a phone.** Tap, gather, bank, sell, level up. The game is fully playable one-handed in portrait, with sessions of 2–10 minutes and progress always saved.
4. **Readable pixel art.** Every sprite is a swappable PNG. The owner hand-draws the final art (see `docs/ART_GUIDE.md`).

## 2. Core loop

```
 gather (Forestry / Mining / Angling / Foraging)
    │  raw items, tools wear down
    ▼
 process (Smithing / Joinery / Cooking / Brewing) at town stations
    │  higher-value goods; some fail → junk (sink)
    ▼
 bank ──► sell on the Exchange / to NPC shops (tax = coin sink)
    │                                   ▲
    ▼                                   │ AI players buy & sell too
 buy better tools / food ──► reach better nodes & regions ──► (repeat)
                 │
                 └─► combat (Attack / Strength / Defence / Vitality) uses food + smithed weapons
```

Moment to moment: **tap a node → the character walks (one tile per tick) → works the node on a tick cadence → XP and items → the pack fills (24 slots) → walk to the bank chest.** Within a session you set short goals ("next hatchet tier"). Across sessions you chase levels, regions and market wealth.

## 3. Skills (13: Prayer added in M2, see §13.8; Melee split into Attack / Strength / Defence in 0.2.4, see §13.12)

The level cap is **60**. XP to reach level L = `floor(100 × (1.085^(L−1) − 1) / 0.085)`. That gives L2 = 100, L10 = 1,275, L20 = 4,366, L30 = 11,356, L40 = 27,159, L50 = 62,891 and L60 = 143,679. Early levels arrive every few minutes and late levels take hours. Data lives in `data/skills.json`.

| Skill | Type | What you do | Feeds |
|---|---|---|---|
| Forestry | Gathering | Fell ash → alder → blackthorn | Joinery (planks, handles, rods); fuel (M3) |
| Mining | Gathering | Copper, tin, iron, coal outcrops | Smithing |
| Angling | Gathering | Fish rippling pools (carp, fen eel) | Cooking |
| Foraging | Gathering | Reed beds, fenroot patches (later fungi) | Brewing, Joinery (reed fibre) |
| Smithing | Production | Smelt bronze / iron / steel bars at the furnace; forge tools, weapons and armour at the anvil | Every gatherer (tools wear out), every fighter |
| Joinery | Production | Workbench: planks, rods, handles, bows (M3) | Angling (rods), Smithing (handles), building (later) |
| Cooking | Production | Hearth: cook fish/stews; failures char | Vitality / combat sustain |
| Brewing | Production | Tonics from fen herbs (M2) | Temporary skill and combat boosts (a consumable sink) |
| Attack | Combat | Accuracy (how often you hit). Wield daggers, swords, battle axes. Trains in the Accurate style | Creature drops |
| Strength | Combat | Max hit. Wield maces, warhammers ("armour breakers"). Trains in the Aggressive style | Creature drops |
| Defence | Combat | Enemies hit you less often. Wear armour. Small XP whenever an enemy swings at you, x a full-set bonus | Survival |
| Vitality | Combat | Health pool; trains with all combat | Survival in harder regions |

**Interdependence by design:** gatherers need tools (made by Smithing) and tools wear out, so demand never stops. Smiths need ore and coal. Combat needs food (Cooking ← Angling) and weapons (Smithing). Joinery makes rods (Angling) and later handles. No skill is self-sufficient, so the market always has reasons to trade.

**Gathering rule (shared by player and AI):** one attempt every `attempt_ticks` ticks (Forestry/Mining 3, Angling 4, Foraging 2). Success chance = `clamp(node.chance + 0.012 × (level − node.level) + tool.power, 0.05, 0.95)`. On success you gain the item, XP and 1 tool wear. Then, with probability `node.deplete`, the node depletes for `respawn` ticks (trees become stumps, rocks become empty).

## 4. First region: the Ashfen marshes, and Fenhollow (starter town)

> **M2:** the infinite map is replaced by one bounded continent with three towns. See §13.1. The Fenhollow layout below still applies.

The world is an infinite seeded map streamed in 24×24-tile chunks. The **Ashfen marshes** around the origin hold grassland, fen pools, marsh, dirt outcrops and winding roads on a coarse grid. A dry ring keeps the town from flooding. Node quality rises with distance from town: alder trees appear past 20 tiles and blackthorn past 60; iron past 25 tiles and coal past 45. This pushes players outward as they level.

**Fenhollow** is an authored 24×24 overlay (`data/towns/fenhollow.json`) centred on the spawn (0,0):

```
...a....a...=.a.....a...
.a.......l..=.....a....a
..f.a.......=......l....
..~~~~......=...........
.~~~~~~,....=....:::::..
.~~~~~~,....=....:c:c:..
.~~~~~f,....=....::i::..
..~~~~,,....=....:c:k:..
...,,,......=....:::::..
............=...........
......############......
......#B##E##H#F##......
======############======
......##W#########......
......#########D##......
......############......
............=...........
..a.........=.....mmm...
.....l......=....mrmgm..
............=....mgmrm..
.a....a.....=.....mmm...
............=.a.........
...a........=......a....
.......a....=..........a
```
Legend: `.` grass · `=` road · `#` cobble plaza · `~` pool · `,` sand · `:` dirt · `m` marsh · `a` ash tree · `l` alder · `c` copper · `t` tin · `i` iron · `k` coal · `f` fishing pool · `r` reed bed · `g` fenroot · `B` bank chest · `E` Exchange board · `H` hearth · `F` furnace · `W` workbench · `D` training dummy.

- **Plaza (centre):** bank chest, Exchange board, hearth, furnace, workbench and training dummy. Every first-hour activity is within about 10 tiles.
- **North-west:** Fenhollow pool (fishing), with a sand shore.
- **North-east:** the quarry outcrop (copper ×2, tin, iron, coal; iron and coal are gated by level).
- **South-east:** the reed marsh (reed beds, fenroot).
- **Edges:** scattered ash and alder trees; roads leave the plaza in all 4 directions.

Planned M2–M3 additions: an NPC general store and a smithy (anvil) on the plaza, an AI players' "commons" (where idle agents gather), and a notice board for player and AI contracts. The second region, **Cinderholt** (a burnt forest with blackthorn and coal), comes in M4.

## 5. Items: first slice with base values

Base value is the **anchor** for the reference price and for NPC shop floor/ceiling prices. It is not a fixed price. The full list is in `data/items.json`.

| Id | Name | Category | Base value (marks) | Stacks | Source / use |
|---|---|---|---|---|---|
| `marks` | Marks | currency | 1 | yes | currency; dummy stipend, sales |
| `ash_log` | Ash log | resource | 4 | no | Forestry 1 (ash tree) |
| `alder_log` | Alder log | resource | 11 | no | Forestry 12 |
| `blackthorn_log` | Blackthorn log | resource | 27 | no | Forestry 25 |
| `copper_ore` | Copper ore | resource | 6 | no | Mining 1 |
| `tin_ore` | Tin ore | resource | 6 | no | Mining 1 (tin rocks beside the copper) |
| `iron_ore` | Iron ore | resource | 17 | no | Mining 12 |
| `coal` | Coal | resource | 22 | no | Mining 20 |
| `raw_carp` | Raw carp | resource | 5 | no | Angling 1 |
| `raw_eel` | Raw fen eel | resource | 14 | no | Angling 15 (same pools) |
| `reed_fibre` | Reed fibre | resource | 3 | yes | Foraging 1 (reed bed) |
| `fenroot` | Fenroot | resource | 9 | no | Foraging 5 |
| `bronze_bar` | Bronze bar | material | 16 | no | Smithing 1: 1 copper ore + 1 tin ore |
| `iron_bar` | Iron bar | material | 34 | no | Smithing 12: 1 iron ore, **40 % flat fail** (ore lost) |
| `steel_bar` | Steel bar | material | 50 | no | Smithing 20: 1 iron ore + 1 coal |
| `plank` | Ash plank | material | 9 | no | Joinery 1: ash log |
| `cooked_carp` | Cooked carp | food | 9 | no | Cooking 1; heals 4 |
| `cooked_eel` | Cooked fen eel | food | 24 | no | Cooking 15; heals 9 |
| `charred_fish` | Charred fish | junk | 0 | no | failed cook (junk sink) |
| `marsh_tonic` | Marsh tonic | consumable | 35 | no | Brewing (M2) |
| `bronze_hatchet` | Bronze hatchet | tool | 48 | no | starter / Smithing 3; 220 uses |
| `iron_hatchet` | Iron hatchet | tool | 100 | no | Smithing 15; 480 uses |
| `bronze_pick` | Bronze pick | tool | 48 | no | starter / Smithing 4; 220 uses |
| `iron_pick` | Iron pick | tool | 100 | no | Smithing 16; 480 uses |
| `reed_rod` | Reed rod | tool | 25 | no | starter / Joinery 4: plank + 6 fibre; 180 uses |
| `bronze_sword` | Bronze sword | weapon | 62 | no | starter / Smithing 6 |
| `iron_sword` | Iron sword | weapon | 130 | no | Smithing 18 |
| `steel_sword` | Steel sword | weapon | 195 | no | Smithing 27 (full gear table: §13.11) |

## 6. AI players

### 6.1 Personas (archetypes)
Defined in `data/personas.json`: **Woodsman, Prospector, Angler, Smith, Cook, Merchant, Adventurer.** Each has:
- `focus` skills (what they train), `sells` / `buys` lists (market intent), `risk` (willingness to cross the price band or hold stock), `patience` (how long an order sits before it is repriced), `schedule` (day / dawn / evening / night / any) and a tint for their placeholder sprite.
- A generated original name (`name_parts`), persistent skills, inventory, bank and coin.

### 6.2 Goals and brain (M2 design)
AI players use a **utility brain** that is re-evaluated whenever they go idle. It chooses between `gather(skill)`, `process(recipe)`, `bank`, `sell(item)`, `buy(item)`, `upgrade_tool`, `eat/rest`, `socialise/idle` and `wander`. Utility = persona weight × need (an empty pack, a broken tool, low food) × market signal (price vs reference) × schedule factor. Long-term goals ("reach Mining 20", "save 500 marks for an iron pick") add a bias. Each agent's RNG is seeded, so behaviour is reproducible from a save.

**M1 prototype (implemented):** 4 agents (Woodsman / Prospector / Angler / Forager-style focus) use the same `Actor` code as the player. They find the nearest node for their skill, gather until the pack is full, walk to the bank chest, deposit and repeat. Otherwise they wander. In tests they gain about 5,000 XP between them in 500 ticks and never stand on blocked tiles.

### 6.3 How they gather, craft, buy and sell
- **Gather/craft:** same rules, odds and tool wear as the player, using `Interactions`.
- **Sell:** when the bank holds more than `persona.stock_target` of a `sells` item, the agent posts a limit sell order at `reference × (1 + markup)`. The markup comes from risk and recent fills. If the order stays unfilled past `patience`, it is repriced toward the bid.
- **Buy:** when they need inputs or tools, they post a bid at `reference × (1 − discount)` inside the band. If the bid goes stale and the need is urgent, they cross the spread or buy from the NPC shop at the ceiling price.
- **Merchant persona:** a market maker that quotes both sides around the reference with a spread of at least 2 × tax. It is limited by anti-manipulation rules (§7.5) and adds liquidity without cornering.

### 6.4 Simulation tiers and the phone performance budget
| Tier | Who | Simulation | Budget |
|---|---|---|---|
| **Detailed** | Agents within about 48 tiles of the player (max 12) | Full `Actor`: pathing, per-tick actions, visible sprites | ≤ 1.0 ms/tick total on a mid-range phone |
| **Nearby-abstract** | Agents in loaded chunk data but off-screen (max ~40) | Activity state machine updated every 10 ticks. No pathing; teleport between work sites; yields from expected rates | ≤ 0.3 ms/tick |
| **World-abstract** | Everyone else (target population 150–300) | Per-agent record (skills, stash, coin, intent) updated once per **game hour** (150 ticks) using expected-value production plus market orders | ≤ 2 ms per batch, spread across frames |

Promotion and demotion happen at the tier boundary. An agent's state is a plain dictionary, so moving it between tiers is just "spawn/despawn a view". Total frame budget on a 2020-era mid-range Android phone: 16.6 ms frame (60 fps target, 30 fps floor). Simulation work stays under 3 ms per frame. Rendering: 5×5 chunk TileMapLayers plus at most a few hundred sprites. Pathfinding is node-budgeted A* (4,000 expansions max). Measured chunk data generation is about 1.3 ms per chunk on the build box (desktop); views stream at no more than 2 chunks per frame.

## 7. Economy

> **M2:** the single Exchange became one market per town, with regional prices, specialist shops and travelling traders. Where §13 and §7 disagree, §13 (as built) wins.

### 7.1 The Fenhollow Exchange (central order book)
- One continuous **limit order book per item**, holding price-time priority bids and asks. Matching runs on the tick (`Market.on_tick`). The player and all AI players use the same API (`Market.place_order(trader, item, qty, limit, is_buy)`).
- A trade executes at the resting order's price. Proceeds go to the seller's **Exchange account** (collected at any bank chest or Exchange board).
- **Reference price** = volume-weighted average price (VWAP) of the previous game day (24 real minutes = 2,400 ticks), smoothed with an EMA (α = 0.3). It falls back to base value if the item had no trades.

### 7.2 NPC shops: floor and ceiling liquidity
- NPC shops **buy any item at 45 % of reference** (the floor) and **sell staples at 160 % of reference** (the ceiling). Staples are tools, basic food and starter materials; the stock is unlimited but expensive.
- This bounds prices: the market can't collapse below what an NPC pays, or spike above what an NPC charges for staples. Inside those bounds, players and agents set the price.

### 7.3 Price discovery
Supply comes from gathering rates × the active agent population per skill. Demand comes from recipes consuming inputs, tool wear, food eaten in combat, and agents' upgrade goals. If too many agents mine copper, the asks pile up, the price falls and copper-focused agents' utility for mining drops (some switch to Smithing to exploit cheap ore). That is organic rebalancing with no scripted prices.

### 7.4 Regulations (anti-chaos)
| Rule | Value (tunable in `autoload/market.gd`) | Purpose |
|---|---|---|
| Daily price band | Orders must be within **±12 %** of today's reference | Stops runaway spikes and crashes |
| Circuit breaker | A **25 %** intraday move from the open halts the item for **300 ticks** (3 min) | Lets agents re-evaluate; prevents cascades |
| Transaction tax | **2 %** of seller proceeds on sales of 50 marks or more (destroyed) | Main coin sink; makes wash-trading unprofitable |
| Order limits | **8** open orders per trader; orders expire after 1 game day | Bounds memory/CPU; stops book stuffing |
| Volume cap | One trader may be at most **25 %** of an item's daily volume | Anti-cornering |
| NPC floor/ceiling | 45 % / 160 % of reference | Hard bounds on price |

### 7.5 Sinks and faucets (keeping inflation in check)
- **Faucets (coin in):** NPC shop buy-backs, the training-dummy stipend (2 marks), and quest/contract rewards (M3).
- **Sinks (coin/items out):** exchange tax, NPC shop purchases, tool **durability** (bronze 220 uses; it breaks and is destroyed), food eaten, failed crafts (charred fish has 0 value), Brewing consumables, and later repair fees and bank expansions.
- **Inflation monitor** (M2, runs once per game day): tracks total coin supply M, coin velocity, and a price index (a basket of 10 staple items, weighted by volume). If the index rises more than 3 % per day for 3 days, it lowers the NPC buy factor (45 % down to 40 %), trims the dummy stipend and nudges drop rates down 5 %. If it falls more than 3 % per day, it reverses those steps. Every adjustment is bounded (±20 % from defaults), logged, and visible on the Exchange board as "Guild notices". Tool durability is never changed silently.

### 7.6 Anti-manipulation (applies to AI and player)
Rules include the volume cap, a max order count, minimum order lifetime (5 ticks) to stop spoofing, the tax floor (which makes self-trading lose money), and per-agent "reputation". Agents that trip the limits lose market priority for a day.

## 8. Offline / "the world keeps living"
- On load, the game computes `away = now − saved_unix`, **capped at 8 hours**, and fast-forwards:
  - **Depletion timers** are saved as *remaining ticks*, so nodes are exactly as you left them, minus the elapsed time (implemented).
  - **World-abstract AI** runs `away / 150 ticks` batched game-hour steps: production, consumption, order placement and matching (M2; `AIDirector.simulate_offline` hook exists).
  - **Market** settles the elapsed game days with VWAP/EMA reference updates and expires stale orders (M2; `Market.simulate_offline` hook exists).
  - **The player does not progress offline** (no idle XP). This keeps the game honest and keeps the economy the only thing that moved. A "While you were away" summary shows the biggest price moves and what your open orders did.
- Clock tampering: if `now < saved_unix`, offline time is 0. Fast-forward never exceeds the cap.

## 9. Save format
`user://ashfen_save.json` (JSON). It is written atomically (`.tmp` → rename) with the previous file kept as `.bak`, and falls back to `.bak` if the main file is unreadable. Saves happen every 50 ticks (30 s), on app pause/focus-out (Android) and on quit.
```json
{
  "version": 1, "saved_unix": 1791500000, "tick": 1234,
  "world":  { "seed": 7331, "depleted": { "-6,8": 12 } },
  "player": { "id": "player", "tile": [0,0], "skills": {"forestry": 1520, "...": 0},
              "inventory": [ {"id":"bronze_hatchet","qty":1,"dur":203}, null, ... ],
              "bank": [ {"id":"ash_log","qty":57}, ... ] },
  "ai":     { "agents": [ { "id":"ai_0", "name":"Teo Moss", "persona":"woodsman", "tile":[..], "skills":{..}, "inventory":[..], "bank":[..] } ] },
  "market": { "reference": { "ash_log": 4, "...": 0 } }
}
```
The map itself is never saved; it regenerates from `seed`. Only changes are stored. `SaveSystem._migrate()` is where versioned upgrades go.

## 10. Technical architecture (as built in M1)
```
autoload/  GameData (JSON + sprite mapping + XP curve) · Tick (0.6 s heartbeat) · Events (bus)
           SaveSystem · Market (stub + regulation constants) · AIDirector (prototype agents)
src/world/ WorldGen (seeded tiles/objects, town overlay) · ChunkData · World (streaming, TileMapLayer
           per chunk, depletion/respawn, minimap) · Pathfinder (A*, budgeted) · Interactions (rules)
src/actors/ Actor (shared by player & AI) · Player · AIPlayer
src/skills/ Skills   src/inventory/ ItemContainer   src/ui/ HUD, Minimap, ItemSlot, UIStyle
src/tests/  selftest.gd (44 headless checks)   data/ *.json   assets/sprites/<category>/*.png
```
Simulation order per tick: world respawns → player → AI → market → chunk streaming → autosave. State changes only happen on ticks; visuals interpolate.

## 11. Roadmap to a shippable Android release
| Milestone | Scope | Exit criteria |
|---|---|---|
| **M1 (this)** | Godot port, data-driven content, 10 skills defined (9 live: Forestry, Mining, Angling, Foraging, Smithing (smelting), Joinery, Cooking, Melee + Vitality via the dummy; Brewing is data-only), bank, minimap, save/load, prototype AI, Web + Android debug builds | APK and Web build run; 44/44 selftests pass |
| **M2: Living continent (done, see §13)** | Real Exchange order book plus regulations, NPC general store and smithy (anvil recipes for tools/weapons), AI utility brain plus 3 sim tiers, ~40 named agents, offline catch-up, "while you were away" report, Exchange UI (buy/sell/orders), first creature (marsh rat) with aggro | Prices move organically; a 7-day soak test shows the price index within ±15 %; 60 fps on a mid-range phone with 12 detailed agents |
| **M3: Depth** | Brewing, more Joinery, contracts/notice board, combat zone, equipment slots, run toggle, audio/SFX, settings, tutorial, owner's first hand-drawn art pass | A new player can learn the game unaided in 10 minutes |
| **M4: Second region** | Cinderholt, tier-3 materials, travel, more personas, bank expansion sink, achievements | 10–15 h of content |
| **M5: Release candidate** | Release keystore, Gradle build → **AAB** (installs the NDK r28b and CMake listed in `docs/BUILD.md`), Play Console internal testing, crash reporting (opt-in), privacy policy (no data collected), store listing, performance pass on low-end devices (2 GB RAM) | Internal-testing track live, then a closed beta |
| **Later** | iOS port. Needs a **Mac with Xcode** and an **Apple Developer Program account ($99/yr)**. Godot exports an Xcode project; nothing in the code is Android-specific except the safe-area handling, which already uses Godot's cross-platform API | n/a |

## 12. Originality guardrails
- No Jagex or RuneScape names, assets, data, formulas or numbers. Skill names, items, town, region, currency ("marks"), XP curve, gather formula and all balance values are original to Ashfen.
- All art is either generated by `tools/gen_art.py` (original procedural pixel art) or hand-drawn by the owner.
- "Inspired by classic tile-based MMOs" is fine for marketing. Avoid naming other games on the store page.


---

## 13. Milestone 2: as built (supersedes §4, §6 and §7 where they differ)

### 13.1 The continent
- One **bounded, seeded continent** (centre (180, −10), radius 330 tiles; `data/world.json`). Land value = `1 − d/R + coast noise × 0.45`, plus a boost near towns. Below 0.10 is **ocean** (impassable water), and below 0.15 is beach. Inland lakes come from noise. Chunk streaming (24×24) is unchanged. Anything outside the bounds is always water.
- **Regions** bias the biome and resource mix: hills around Cinderholt (ore and coal), marsh around Fenhollow (reeds, fenroot, fen pools), and forest and coast around Saltmere (alder and blackthorn, fish).
- **Roads** link every pair of towns. They are 8-connected wobbling rasters of path tiles (`WorldGen.road_between`). The closest town pair is 344 tiles apart, about 3.5 real minutes on foot at 1 tile per tick.
- **World map:** the Map tab replaced the Bank tab. It shows the continent, roads, labelled towns, trader dots and your blinking position. "To <Town>" buttons walk you there along the roads.

### 13.2 Towns and shops
| Town | Centre | Region | Specialist shops (approved 3/3/2 split) |
|---|---|---|---|
| **Fenhollow** | (0, 0) | marsh | Helmets (Crestwright's Helms), Swords (Edgewell Blades), Archery (Fletch & Stave) |
| **Cinderholt** | (330, −200) | hills / mining | Body armour (The Mailhouse), Shields (Bossmaker's Shields), Battle axes (Cleft & Haft) |
| **Saltmere** | (300, 170) | coast | Leggings (Greave & Gusset), Maces (Flange & Knob) |

Every town has a **bank chest** with its own vault (goods never teleport between towns), a **General Store**, an Exchange board, a furnace, a hearth, a workbench, an anvil and a training dummy. The bank opens only by walking to a chest.
- **General Store:** sells basic goods (tools, rod, cooked carp, planks, bronze bars, tin ore, bronze arrows) at the local reference × 1.6. It buys almost anything at the floor (local reference × `npc_buy_factor`, default 0.45), up to 25 of each item per day and within the town's **daily purse** (default 600 marks; see §13.4).
- **Specialists:** each sells its line in four metal tiers (bronze / iron / steel / dusk; archery: ash / alder / blackthorn bows plus bronze / iron / steel arrows). Price = local reference × 1.15 × (1 + 0.6 × (1 − shelf/max)), so scarcity raises prices. Shelves hold max 8/5/4/3 per tier and restock one item every 200 ticks. A specialist buys only its own line, at base × 0.55, and that stock goes back on the shelf.
- **Gear lines** (`data/items.json`, `gear` block: slot, line, tier, atk/str/def, level 1/10/20/30 since 0.2.3; the level is in Attack, Strength or Defence by class since 0.2.4, §13.12). Weapons double as melee tools. Bronze, iron and steel pieces are forgeable at the anvil (22 recipes). Bows are carved at the workbench. Dusk pieces are shop-only.

### 13.3 Regional economy (per-town markets)
Each town runs its own **TownMarket**: a limit order book (price-time priority, trades at the resting price, escrow up front, per-town collection box), its own reference prices (start = base × the town's `price_bias`), its own shop stock, and its own regulations:

| Rule (per town) | Value |
|---|---|
| Daily band | ±12 % of the town's reference |
| Circuit breaker | a move > max(8 %, 2 marks) within 300 ticks halts that item in that town for 300 ticks |
| Tax (sink) | 2 % of gross on sales ≥ 50 marks |
| NPC floor / ceiling | General Store buys at 0.45 × reference (25 per item per day, purse-limited); sells staples at 1.6 × reference |
| Orders | max 8 open per trader per town; TTL 1 game day; min lifetime 5 ticks; self-trade rejected |
| Day close | reference = EMA (α 0.3) toward the day's VWAP (or book mid), clamped to 0.25–4 × base |

One game day = 2,400 ticks (24 real minutes) and one game hour = 100 ticks. The hub (`autoload/market.gd`) owns the global tunables, the Guild purse, the econ history and the monitor.

### 13.4 Faucets, sinks and the monitor
- **Faucets (coin in), all capped per day:** store buy-backs (each town's purse, default 600, monitor range 300–900) and the **Guild purse** (450/day × `bounty_mult`). The Guild purse pays training-dummy stipends and coin drops from goblins. Nothing else creates coin.
- **Sinks:** exchange tax, shop purchases, AI upkeep (8 + 2 % of coin above 400 per day), AI inn costs when they lack food or fuel (6 marks per missing unit), the death fee (10 % of carried coin), tool and gear wear, failed crafts, food eaten, and bones buried.
- **EconomyMonitor** (daily; basket index averaged across towns). It looks at the average daily change of the index (d_idx) and of the money supply (d_money) over the last 3 days:
  - **cool:** d_idx > 2 %, or d_money > 4 % with d_idx ≥ 0. Lowers the buy factor, purse, bounty and stipend, and nudges gathering up.
  - **glut:** d_idx < −1 % and d_money > 1.5 %. Goods are piling up while coin still grows, so it shrinks the purse and slows gathering. Since 0.2.1 it no longer cuts the buy factor, because lowering the floor in a slump made the slump deeper.
  - **warm:** d_idx < −2 % and money not growing fast. Takes the opposite steps.
  - Otherwise every tunable relaxes 10 % toward its default.
  - Every step is bounded and posted as a Guild notice. The Exchange "Guild" view also shows a by-town price table.
  - **Per-item floor support (0.2.1)**, checked daily for every traded good in every town (`EconomyMonitor._item_floors`):
    - Below **0.8 × base** locally, that town's store floor for the good rises by **+0.05 × base** a day, up to **+0.30**. The floor is then (buy factor + boost) × base, about 0.75 × base at most.
    - Above **0.95 × base** the boost steps back down.
    - The store buys the surplus as town consumption (a goods sink). It pays from the same capped daily store purse, so the coin faucet stays bounded. AI sellers never ask below the store floor, so the support lifts asks in that town.
    - Boosts are saved per town (`floor_boost`). This fixed the 14-day slide: before, the index reached −14 % and raw eel's cross-town spread 2.5×.

### 13.5 AI population (40 agents, 3 tiers)
| Persona | n | Focus |
|---|---|---|
| Woodsman | 3 | Forestry, Joinery |
| Prospector | 5 | Mining, Smithing |
| Angler | 4 | Angling, Cooking |
| Forager | 3 | Foraging, Joinery |
| Smith | 5 | Smithing |
| Cook | 4 | Cooking |
| Adventurer | 7 | Attack, Strength, Defence, Vitality (rotate Accurate/Aggressive) |
| **Acolyte** | 3 | Prayer (buys bones and buries them) |
| **Trader** | 6 | Arbitrage between towns |

- **Tiers:** detailed (≤ 48 tiles from you, max 12 on-screen bodies, demoted beyond 56), nearby-abstract (≤ 160 tiles, stepped every 10 ticks) and world-abstract (stepped every 100 ticks). Every tier trades every 50–90 ticks, using its town's local prices.
- **Brain:** utility = marks per tick at local prices × persona weight × glut factor × noise. Agents rest below a reservation wage of 0.06 marks per tick and keep 8-game-hour sessions. Each day they need 3 food and 3 fuel or pay the inn. They learn their own buy and sell multipliers.


**Supply response (late M2 tuning).** Gather and craft utility are multiplied by `price_health` = min(1, local price / (0.85 x base))^3. Producers back off an item that trades well under its base value. A recipe whose margin is 0 or less no longer earns an XP bonus, so XP alone can't keep a value-destroying chain running. Woodsmen went from 4 to 3 and Smiths from 4 to 5 (still 40 agents). Before these changes, sawn planks fell about 1 mark a day to the NPC floor (0.48x base). A control run with AI sawing disabled swung planks into shortage instead (13-15 marks), which showed that woodsman over-supply was the driver.

### 13.6 Travelling traders
- **Plan:** in town, a trader scores every item it can buy here (Exchange ask or shop) against each other town. Net = the destination's conservative sell estimate (best bid, or reference × 0.9 with no bids, minus tax) − unit cost. The trip must clear ROI ≥ 25 % and net ≥ 2. Quantity is limited by budget (50 % of coin), carry capacity (30 items, ×10 for stackables) and the destination's demand. Lanes other traders are already working are discounted.
- **Travel:** the trader physically walks the road at 1 tile per tick. Near you it is a visible body labelled "(trader)". Offscreen it advances abstractly along the same road. Before leaving town it pulls all its local orders and takes the escrow along.
- **Sell:** at the destination it lists the cargo at the higher of cost + 3 % and its learned markup over the local reference (or takes a bid at ≥ cost + 2 %). After 900 ticks it cuts losses: it hits the bids, sells the rest to the General Store (within the purse), and carries only what is left elsewhere.
- **Effect** (soak test, §13.10): traders narrow cross-town gaps but don't erase them. Shortages and gluts in one town pull goods from the others.

### 13.7 Enemies and combat
- **Camps** (`data/enemies.json`): 15 camps (9 giant-rat and 6 goblin), 53 creatures, spread across the continent and outside towns. Each creature has a **home** tile, wanders within 3 tiles, **aggroes** on the player or any AI body within its aggro radius (rat 3, goblin 4), and chases while it stays within its **leash** (rat 7, goblin 8). Past the leash it gives up, walks home and heals to full. It never follows anyone into a town. On death it respawns at home after 60 ticks (rat) or 90 ticks (goblin). Camps more than 64 tiles from you are frozen at home.
- **Stats:** giant rat 4 HP, max hit 1, 40 % accuracy, defence 0. Goblin 9 HP, max hit 2, 50 % accuracy, defence 2. Both swing every 4 ticks.
- **Tick combat** (`src/combat/combat.gd`, shared by the player and AI; numbers in `data/combat.json`). Enemies swing every 4 ticks; you swing every 4 ticks (dagger 3, warhammer 5):
  - **Your accuracy** = 0.55 + (Attack + gear atk) × 1 % − enemy defence × (1 − armour break) × 2 %, clamped to 10–95 %. Maces and warhammers ignore 50 % of enemy defence.
  - **Your max hit** = 1 + Strength/6 + weapon power + gear str/4.
  - **Enemy accuracy** = its accuracy − your gear defence × 1 % − your Defence level × 0.5 % (5–95 %).
  - **Damage** is 1..max hit on a hit, and 0 shows as a blue miss splat.
  - **XP:** 4 per damage to your style's skill (Accurate → Attack, Aggressive → Strength) and Vitality 1.4 per damage. Defence: 2 per enemy swing that misses you, 2 + 1 per damage when it hits, × the full-set bonus (§13.12).
  - **HP:** max HP = 10 + Vitality. Out of combat you regain 1 HP every 30 ticks.
  - **Feedback:** hitsplats and HP bars over both sides.
  - **Damage bubbles (0.2.2):** each actor, enemy or dummy shows at most **one** bubble. A new hit removes the old bubble at once and shows the new value in the same spot, so bubbles never stack. Misses (0, blue) follow the same rule. A bubble follows its target as it moves and fades after `lifetime_s` (0.6 s; the last `fade_s` 0.2 s fades out). Tunables are in `data/fx.json`; the code is `src/ui/hit_bubbles.gd`.
  - **Retaliation:** an idle actor that is hit fights back, and an enemy that is hit targets its attacker.
- **Eat to heal:** tap food in the pack, then Eat. Cooked carp heals 4, cooked eel more, and cooked rat meat 3. Eating delays your next swing by 2 ticks.
- **Equipment** (new for the player): tap gear, then Equip. Slots are head, body, legs, shield and weapon. You need the item's level in its skill: Attack for daggers, swords and battle axes; Strength for maces and warhammers; Defence for armour (§13.12). With no weapon equipped, the best melee tool in your pack is used, so the M1 behaviour still works. Bows don't add melee power yet; ranged combat is a later milestone.
- **Death penalty (decided):** you wake at the **nearest town** with full HP.
  - Worn equipment and everything banked are always kept.
  - The town healer keeps **10 % of the coins you carried** (a sink).
  - Everything else from your pack is left in a **private pile** where you fell. Only you can see and pick it up, and it lasts **30 minutes (3,000 ticks)**.
  - Rationale: dying costs a walk back and a little coin, never your progress. That's fair on a phone, where an interruption can kill you.
- **Single-way combat (0.2.1, default everywhere)** (`src/combat/combat_rules.gd`):
  - An actor (you or an AI) that is **in combat** can only be attacked by the enemy it is fighting. Other enemies won't aggro onto it until it is free.
  - An enemy in combat with one actor can't be attacked by anyone else. Tapping it says *"Someone else is fighting that."*, and an AI picks another target.
  - While an enemy is on you, you can't open on a second one (*"You're already under attack."*).
  - **In combat** = within **8 ticks** (`combat_ticks`) of the last swing dealt or taken, or of an enemy aggroing onto you, while that foe is alive. A kill frees you at once.
  - Offscreen (abstract) fights are one enemy at a time.
- **Multi-combat zones** (`data/combat_zones.json`, shipped **empty**). Inside a zone both single-way rules are lifted: several enemies may attack one actor, and several actors may attack one enemy. While you stand in one, the HUD shows a crossed-swords icon with the zone's name.
  - **To add a zone,** append `{"id": "goblin_warrens", "name": "Goblin Warrens", "rect": [x, y, w, h]}` to `zones`. The rect is world tile coordinates: top-left corner plus width and height. The coordinates on the HUD (second line, after the day and hour) show your current tile.
  - Abstract fights against a kind whose camps lie inside multi zones take **+50 %** incoming damage (`abstract_multi_damage` × the share of that kind's camps in zones).
- **AI fighters:** detailed adventurers hunt real camps near you; they eat from their stash below 50 % HP, flee home below 35 % with no food, and can die. Abstract adventurers use the same numbers in expectation (`Combat.expected_fight`, +30 ticks per kill for searching/looting): damage taken, food eaten, flee or die. AI death = the same 10 % coin fee, respawn in the home town, then a rest.

### 13.8 Drops, ground items and Prayer
- **Drop tables** (`data/drops.json`): `always` entries always drop. Then one roll: a weighted `rare` entry with probability `rare.chance`, otherwise a weighted `common` entry with probability `common.chance`, otherwise nothing. Quantity is `n` or `[min, max]`. Coin drops are paid from the Guild purse.
  - **Giant rat:** Bones (always), Raw rat meat (65 %).
  - **Goblin:** Bones (always). Common (55 %): 2–8 marks, 1–3 copper ore, 1–3 tin ore, a bronze bar, ash logs or rat meat. Rare (3 %): a bronze sword, mace, battle-axe or cap.
- **Ground items** (rules in `data/drops.json` → `ground`):
  - Your kill drops, and items you drop, are **private to you for 100 ticks (60 s)** (`private_ticks`). Then they turn **public**, and anyone may take them.
  - Every drop despawns **500 ticks** after it fell (`drop_ttl`), whether private or public.
  - Tap the tile to walk over and pick everything up. AI killers loot at once, straight into their stash.
  - Ground items and death piles are saved, including how long each stays private.
- **AI looting of leftovers (0.2.1):**
  - Every 5 ticks, a detailed (on-screen) AI that isn't in combat or on a trading trip looks for public piles within **10 tiles** worth at least **3 marks** (market value × qty; coins count 1 each). It claims one, walks over and takes the pile into its stash or purse. Junk (burnt meat) is skipped.
  - Nearby abstract (tier-1) agents claim a public pile within 10 tiles with a **5 %** chance per 10-tick check.
  - Looted goods enter the regional economy like any other stash goods.
  - **Death piles are never public** and are never taken by AI. Only their owner can see them, for 30 minutes.
- **Raw rat meat** cooks at Cooking 1 into **Cooked rat meat** (heals 3), with a 45 % base burn chance falling 3 % per level, to a minimum of 5 % (burnt meat is junk).
- **Prayer** (new skill): tap Bones, then **Bury**: +5 Prayer XP and restores 20% of your prayer points (`prayer_restore` on the item, so bigger bones can restore more later). AI adventurers keep 40 bones to sell and bury the rest each day. Acolytes buy bones on the Exchange and bury them, which creates real demand for bones. Bones and meat are sellable everywhere.

**Churches (0.3.1)** (`data/churches.json`): every town has one walk-in stone church (grey stone walls and floor, slate roof, pews, candles, stained glass, a priest). Tap the altar (**Pray at**): you walk in, kneel for 2 ticks, and your prayer points refill to max. It gives no XP; Prayer XP still comes only from burying bones. The priest greets you as you enter and talks when tapped (no shop). AI players use the same rule (`Interactions`), and `World.nearest_altar(from, town)` gives them the altar and its approach tile.

**Combat level (0.3.1)** (`Combat.combat_level`): floor((Attack + Strength + Defence + Vitality) / 4 + Prayer / 8), at least 1. A new character is Combat 3. The HUD shows `Total N  Combat N` (Total = total level); the Skills panel header shows both. Enemies do not START a fight with anyone (player or AI) whose combat level is `aggro_level_gap` (data/combat.json, 10) or more above the enemy's level, everywhere including the Scorch; an enemy you attack still fights back. Tapping an enemy names its level ("You attack the Giant rat (level 1).").

**Walled cities (0.3.1)** (`data/towns/<city>.json` laid out by `tools/layout_walled_cities.py`, `building_style` per city): Fenhollow (timber halls, boardwalks, wooden palisade), Cinderholt (basalt blocks on a grid, dark cobbles) and Saltmere (plaster harbour, sandstone wall). Each city is walled with four 3-tile gates (N/S/E/W) and two stationary, non-aggressive guards per gate; the whole walled area and the gates are a safe zone. Roads run gate to gate (A* starts and ends at the outside tile of the facing gates, walled cities and village footprints are impassable to the road), and a short path/pier approach is stamped outside every gate. Every city has a **Cook House** (oven = hearth station, free to use; finite cooked-food shelf at ~80% of the general-store price, `shop.json` `cookhouse`). At night every facade style (timber, stone, basalt, plaster) gets lit windows and a torch burns on the wall either side of every gate. Save v7: a player saved inside a city is moved to its square on load and ground piles on new walls move to a free tile.

**Villages, wheat and cows (0.3.1)** (`data/villages.json`, `data/towns/<village>.json` with kind `village`, laid out by `tools/layout_villages.py`): Millbrook (Fenhollow–Cinderholt road), Barrowby (Fenhollow–Saltmere) and Oxley (Cinderholt–Saltmere). Each has three walk-in cottages (a villager talks, no shop), a well, a quern, a cooking hearth, villagers, and a path to the road. The village core is a safe zone like a town, but villages are not cities: distance bands, home towns, travel, markets and respawn use the three cities only. Beside each village: a fenced **wheat field** (tap a stalk, **Foraging** 1, one sheaf then stubble, regrows after 40 ticks) and a fenced **cow pasture** (4 cows: level 2, 8 HP, passive, kick back for at most 1, respawn; always drop bones, raw beef and a cowhide). Chain (Cooking, no new skill): 2 wheat -> flour at the quern (Cooking 1), flour -> bread on a hearth (Cooking 3, heals 4), raw beef -> cooked beef (Cooking 5, heals 5). Cowhide sells (12 base; leather Crafting later); general stores stock bread. AI: a **Farmer** persona (Foraging + Cooking, one per city) works the fields; a share of adventurers (`herd_share`) also hunt the pasture cows; both pay a walking cost to reach the villages.

**Prayer buffs and prayer points** (`data/prayers.json`, `src/combat/prayer.gd`)
- **Pool:** max prayer points = Prayer level x `ticks_per_level` (10). A full pool runs a 1-point-per-tick buff for level x 10 ticks, so 6 s per level (L1 = 6 s, L10 = 1 min). Shown on the HUD as `Prayer cur/max` next to HP.
- **Drain:** an active buff drains its `drain` points every tick (data, per buff): tier 1 = 1.0, tier 2 = 1.2, tier 3 = 1.5. When points hit 0 the buff ends. You can't start a buff with 0 points (under 1 point).
- **One at a time:** start it from Skills, then Prayers (big buttons). Tap the active buff again to stop it and save the rest of your points. While it runs, a HUD icon shows its name and the seconds left at the current drain.
- **Restore:** burying bones (above). Slow passive regen is the chosen second option: with no buff active you regain 1 point every `regen_ticks` (10) ticks, which is 6 s. Draining while active and regenerating while idle never happen together. There is no shrine/altar in M2.
- **Buffs** (original names; def = enemies' accuracy against you x (1 - v); dmg/acc/gather = x (1 + v)):

| Buff | Level | Effect | Drain/tick |
|---|---|---|---|
| Stillwater Ward | 1 | def 5% | 1.0 |
| Ember Grip | 4 | damage +5% | 1.0 |
| Keen Sight | 7 | accuracy +5% | 1.0 |
| Reedsong | 10 | gathering +10% | 1.0 |
| Oakbark Ward | 13 | def 10% | 1.2 |
| Forgefire Grip | 16 | damage +10% | 1.2 |
| Hawk Sight | 19 | accuracy +10% | 1.2 |
| Ironroot Ward | 24 | def 15% | 1.5 |
| Stormbrand | 28 | damage +15% | 1.5 |
| Dawnstar Sight | 32 | accuracy +15% | 1.5 |

- **AI:** before engaging, an AI fighter with no active buff first buries stashed bones (up to 5) while it is under 60% points. If it then has at least 30% points, it picks its best unlocked buff: defence when under 60% HP, else damage, then accuracy. Visible (tier 0) AI tick their pool like the player. Abstract fights scale the buff's effect by the share of the session the remaining points cover, then drain them. Idle abstract agents regenerate. Acolytes' and adventurers' daily burials also restore points.

### 13.9 Offline catch-up
When you return after time away (capped at 8 hours), every agent runs its abstract tier for the elapsed ticks: production, trading, travel, fights and day closes. The "While you were away" report shows price moves in your current town, your filled orders, trader trips and the change in townsfolk coin.

### 13.10 Soak test
`godot --headless --path . -- --fresh --soak=N [--no-traders] [--soak-out=DIR]` runs N game days and logs per-town reference prices for 10 key items each day. It writes `soak.csv` (global), `soak_towns.csv` (per town) and `soak.json`. `tools/soak_chart.py RUN [CONTROL]` draws the chart and compares a run against a no-traders control run. Pass criteria:
- the price index stays within ±15 %;
- money supply ends within ±30 %;
- basket prices stay within 0.5–2 × base;
- the Exchanges trade every day;
- there are no negative balances;
- traders make ≥ 10 trips;
- the max cross-town spread stays ≤ 2.0× (bounded) and the mean spread stays ≥ 1.02× (persisting);
- the chart script additionally checks that the average spread is lower with traders than without.

**Results (0.2.1):**

| Run | Worst index drift | Money supply | Max spread | Mean spread | Trader trips |
|---|---|---|---|---|---|
| 7 days, traders on | 7.5 % | −10.9 % | 1.70× | 1.30× | 137 |
| 7 days, traders off | 4.3 % | −12.1 % | 3.00× | 1.56× | — |
| 14 days, traders on | 11.4 % | −0.8 % | 1.67× (alder log) | 1.28× | 239 |

All three runs pass. The 14-day run failed before per-item floor support: its index drifted −14.0 % and raw eel's spread hit 2.67×. By day 12 many raw goods and copper tools sit at the maximum floor boost in at least one town. Structural over-supply remains, and the floors are the backstop.

**Results (0.2.3, after the bronze / iron-fail / steel change):**

| Run | Worst index drift | Money supply | Max spread | Mean spread | Trader trips |
|---|---|---|---|---|---|
| 7 days, traders on | 5.0 % | −11.5 % | 1.78× (raw eel) | 1.28× | 125 |
| 7 days, traders off | 4.0 % | −19.1 % | 3.00× | 1.45× | — |
| 14 days, traders on | 7.1 % | −10.5 % | 1.38× (bronze bar) | 1.21× | 262 |

All three pass, and arbitrage narrows the gaps (average mean spread 1.25× with traders vs 1.32× without). On day 14 the new goods sit at these multiples of base across the three towns: tin ore 0.67–0.83, bronze bar 0.81–1.12, iron bar 1.06–1.24, steel bar 1.04–1.14 and coal 0.50–0.64 (coal now feeds steel only, so it runs cheap). Smiths and prospectors smelt all three bars and forge steel pieces.

**Results (0.2.4, combat skills + daggers/warhammers):**

| Run | Worst index drift | Money supply | Max spread (final day) | Mean spread | Trader trips |
|---|---|---|---|---|---|
| 7 days, traders on | 3.5 % | −12.3 % | 1.89× (raw eel) | 1.30× | 133 |
| 7 days, traders off | 2.8 % | −16.6 % | 2.67× | 1.43× | — |
| 14 days, traders on | 5.9 % | −6.5 % | 1.83× (plank) | 1.31× | 257 |

All three pass, and arbitrage narrows the gaps (average mean spread 1.24× and 1.29× with traders vs 1.31× without). The first 0.2.4 run gave warhammers 4 bars + 1 plank. It passed only at the limit: plank spread 2.00× on day 14, and 2.17× (integer town prices) on days 12–13. The extra plank demand landed in the smithing town. Warhammers became 4 bars with no plank. The spread check only looks at the final day; in the integer per-town CSV, raw eel touches about 2.1× on days 8–12 of the 14-day run, which is a thin market to watch.


### 13.11 Metals rework (0.2.3): bronze, iron fail, steel
**Bars (furnace, `data/recipes.json`):**

| Bar | Inputs | Smithing | XP | Fail | Base value |
|---|---|---|---|---|---|
| Bronze bar | 1 copper ore + 1 tin ore | 1 | 14 | none | 16 (inputs 6 + 6) |
| Iron bar | 1 iron ore | 12 | 40 | **40 % flat**: ore lost, 0 XP, "The iron ore is too impure and you fail to refine it." | 34 (expected ore cost 17 / 0.6 ≈ 28) |
| Steel bar | 1 iron ore + 1 coal | 20 | 55 | none | 50 (inputs 17 + 22) |

- The fail rate is data: `"fail": {"chance": 0.4, "xp": 0, "message": "..."}`. A `chance` key means a flat rate that does not shrink with level. The older `{item, base, per_level, min}` form (charred fish at the hearth) still works. The furnace menu shows "40% fail" on the iron row. A failed attempt counts toward "Make N". AI agents use the same rate in both the detailed and abstract tiers, and price recipes by expected output (`AIBrain.recipe_margin`).
- **Interpretation:** "steel takes 1 iron and 1 coal" is read as 1 iron **ore** + 1 coal (as specified), so steel never risks the 40 % loss and is the reliable route for iron ore once you reach Smithing 20.

**Ores and rocks:** tin ore (base 6) comes from new **tin rocks** (Mining 1). In town maps they are legend `t` beside the copper (Fenhollow quarry, Cinderholt); in the wilds, about 45 % of the copper spots on dirt become tin. Iron rocks (Mining 12) and coal rocks (Mining 20) already existed and are unchanged. The spec suggested coal at about Mining 30, but coal stays at Mining 20 so the steel bar (Smithing 20) is reachable on the same timeline and the soak-tuned supply is undisturbed. Prospectors mine copper, tin, iron and coal; smiths buy tin and smelt all three bars. Goblins' common drop gains 1–3 tin ore. The General Store stocks tin ore.

**Gear tiers** (every metal specialist line, `data/shop.json` `lines` index = tier − 1; shelves max 8/5/4/3):

| Tier | Metal | Melee level | Weapons atk/str (sword · mace · battle-axe) | Armour def (helm · body · legs · shield) | Durability (weapon / armour) | Source |
|---|---|---|---|---|---|---|
| 1 | Bronze (was copper) | 1 | 4/2 · 3/3 · 2/4 | 2 · 5 · 3 · 3 (alder buckler) | 300 / 400 | anvil, Smithing 3–9 |
| 2 | Iron | 10 | 8/4 · 6/6 · 5/8 | 4 · 9 · 6 · 6 | 600 / 800 | anvil, Smithing 15–24 |
| 3 | **Steel (new)** | **20** | 11/5 · 8/8 · 7/10 | 5 · 11 · 8 · 8 | 800 / 1100 | anvil, Smithing 27–32 |
| 4 | Dusksteel | **30** (was 25) | 14/7 · 11/10 · 9/13 | 7 · 14 · 10 · 10 | 1000 / 1400 | shop only |

Steel pieces: `steel_sword` 195, `steel_mace` 205, `steel_battleaxe` 215, `steel_helm` 195, `steel_brigandine` 260, `steel_legplates` 225, `steel_heater_shield` 220 and `steel_arrows` 10 (str 3, archery shop). Anvil recipes: sword 3 bars (Smithing 27); mace and battle-axe 3 bars + 1 plank (28); helm 3 bars (28); heater shield 3 bars + 2 planks (29); legplates 3 bars + 2 planks (30); brigandine 4 bars (32). Dusk moved from Melee 25 to 30 so the 1 / 10 / 20 / 30 ladder stays evenly spaced. Iron gear values were lowered (for example, sword 170 → 130, hauberk → 180, hatchet and pick 130 → 100) because the iron bar dropped from 48 to 34. Every piece is still worth more than its bars at expected cost. Steel tools were not added (the request covered gear tiers); bronze and iron hatchets and picks remain.

**Save migration:** `SAVE_VERSION` 2. Loading a v1 save renames every `copper_X` id except `copper_ore` and `copper_rock` to `bronze_X` throughout the save tree, as values and dictionary keys. That covers the pack, bank vaults, equipment, ground items and death piles, AI stashes, gear, price memos, market orders and references, and shop stock. It also renames `smelt_copper` to `smelt_bronze` and `forge_copper_*` to `forge_bronze_*`.


### 13.12 Combat skills (0.2.4): Attack, Strength, Defence
The single Melee skill is replaced by three. Vitality stays as HP. The rules live in `data/combat.json`.

| Skill | Effect | Gear it unlocks (bronze 1, iron 10, steel 20, dusk 30) | XP |
|---|---|---|---|
| Attack | +1 % accuracy per level | daggers (stab), swords, battle axes (slash); bows (unchanged, ranged comes later) | 4 per damage on the **Accurate** style |
| Strength | max hit +1 per 6 levels | maces, warhammers (crush, "armour breakers") | 4 per damage on the **Aggressive** style |
| Defence | enemies' hit chance −0.5 % per level | helm, body, legs, shield | 2 per enemy swing that misses, 2 + 1 per damage when it hits, × set bonus |

- **Gear bonuses still apply alongside the skills:** gear atk adds to accuracy, gear str to max hit, gear def lowers enemy accuracy by 1 % per point. Prayer buffs map acc → Attack, dmg → Strength, def → Defence (descriptions now say so; the effects are unchanged).
- **Combat style:** two big buttons at the top of the Skills panel: **Accurate (Attack XP)** and **Aggressive (Strength XP)**. Equipping a weapon sets its default (stab/slash → Accurate, crush → Aggressive). You can switch at any time; the choice is saved. The training dummy follows the same rule. Defence trains only by being attacked, so the dummy never gives it.
- **Armour set bonus:** a full set (helm + body + legs + shield) all of one tier multiplies Defence XP: bronze ×1.25 (the alder buckler is the tier-1 shield), iron ×1.5, steel ×1.75, dusk ×2.0. Mixed tiers or a missing piece give no bonus. The pack panel shows a line under the worn gear, for example "Full steel set: Defence XP x1.75". Fractional XP is rounded stochastically, so the average is exact.
- **New weapon lines** (placeholder art; forged at the anvil for bronze/iron/steel, dusk shop-only):

| Weapon | Tier 1–4 atk / str / power | Swing | Bars (anvil) | Smithing (XP) | Values |
|---|---|---|---|---|---|
| Dagger (stab, Attack) | 6/1/1 · 11/2/2 · 15/3/3 · 19/4/4 | every 3 ticks | 2 bars | 2 (36) · 14 (100) · 26 (155) | 42 · 90 · 130 · 440 |
| Warhammer (crush, Strength) | 0/6/4 · 2/11/7 · 4/14/9 · 6/18/11 | every 5 ticks | 4 bars (metal haft, no plank) | 8 (70) · 23 (200) · 31 (300) | 85 · 175 · 255 · 640 |

  Durability: dagger 250/500/700/900 and warhammer 350/700/900/1100. Daggers sell at the swords shop (Edgewell Blades, now "Swords & daggers"), and warhammers at Flange & Knob ("Maces & warhammers"). Shop rows pair the classes by tier. Expected damage per tick against a goblin at matching levels stays within the existing sword-to-battle-axe range: daggers are fast and accurate with low max hits; warhammers are slow and inaccurate but hit hardest per swing.
- **Battle axes and warhammers are not two-handed** (yet), so a shield still fits with them.
- **AI:** adventurers focus Attack, Strength, Defence and Vitality. They start with Strength and Defence near their Attack level (−4..+2) and Vitality 10–18, plus a bronze (or, if their levels allow, iron) weapon they can wield. They rotate style by training whichever of Attack and Strength is behind. Gear purchases and stash equips respect the new requirements. Weapons are chosen by expected goblin kill speed for that agent, not raw strength bonus. Abstract fights use all three levels (`Combat.expected_fight` returns ticks, damage, enemy swings and expected Defence XP per kill), and the AI Defence XP rule is the same as the player's. In soaks, adventurers reach Attack and Strength 18–48 and Defence 10–24 after 7 days, and Attack and Strength 24–58 and Defence 10–25 after 14 days. Under 0.2.3 several hit Melee 60 (the cap) within a week. Defence lags by design: it only trains when they are swung at, so a strong fighter that rarely gets hit stays low (one stayed at Defence 10).
- **Save migration (`SAVE_VERSION` 3):** every skill-XP dictionary (the player's and each AI agent's) copies its Melee XP into Attack, Strength and Defence, so nobody loses access to gear they wear. AI activities naming Melee now name Attack. The AI weapon slot (`tools.melee`, an internal key, not a skill) is kept. `Skills.from_save` applies the same rule as a fallback.

### 13.13 Sprint, energy and the HUD bars (0.2.4)
- **Sprint (player only):** tap the **Energy** bar beside the minimap (84×30 px touch target) to toggle it. While it's on and energy > 0 you move **2 tiles per tick** along any path, including road travel and chasing a creature. Each tick of sprint movement costs **0.5** energy (max 100, so 200 ticks ≈ 2 min of running). At 0 sprint switches itself off ("You're out of energy and slow to a walk."). You can't start it again below 1 energy. Standing still with sprint on costs nothing.
- **Regen per tick:** **0.15** while walking or busy (gathering, crafting, fighting), **0.4** when fully idle (no path, no action). All values are in `data/player.json`. Energy and the toggle are saved; old saves start full.
- **AI players never sprint,** so travel times and the economy are unchanged.
- **HUD:** three labelled bars sit stacked between the info text and the minimap: **HP** (red) `cur/max`, **Prayer** (blue) `cur/max` and **Energy** (green; yellow with a bright frame and ">> Run" while sprinting) `cur/max`. They update every frame (HP on hit, eat and regen; Prayer on drain, bury and regen). The HP/Prayer text line was removed from the top-left info; the info now reads title, day/time + coordinates, total level + marks. The active prayer buff and the multi-combat notice still show there. The layout fits 360 px portrait and leaves the minimap zoom buttons clear.

### 13.14 Playtest fixes (0.2.5): facing, walk cycle, sprint tap
- **Avatar flashing left/right while walking.** There were two causes. (1) **Art:** the 2-frame `player`/`npc` walk cycle swapped which arm and leg was lowered on a front-facing figure, so frame 2 was frame 1 mirrored. At the hard-coded 6 fps, every walking tick read as the avatar flipping left and right. (2) **Code:** facing (`flip_h`) was set from every single path step, so any zigzag (A* weaving, chasing) mirrored the sprite step by step. **Fixes:**
  - The person art is now a 4-frame cycle (stand, far leg up, stand, near leg up) with a three-quarter head facing right. No frame is a mirror of another, so mirroring now actually means "faces left".
  - **Facing hysteresis** (`src/actors/facing.gd`, tunables `data/fx.json` `facing`) for the player, AI players and enemies. Facing follows the net intent once per tick: the walk destination, or the target while fighting. Single steps are ignored. Straight up/down never flips. A 2+ tile reversal turns at once. A 1-tile reversal has to persist 2 ticks. There are never two turns within 3 ticks.
  - The walk cycle uses the sprite's data `fps` and `frames` (player/npc 5 fps x 4 frames, rat 6, goblin 4) on a continuous clock with a 2-tick grace, so short pauses don't snap to frame 0. A sprint tick (2 tiles) is interpolated through its middle tile.
  - `sprites.json` actor `"flip": false` opts art out of mirroring.
  - Proof: `screenshots/v025_walk_strip.png` (real A* diagonal) and `v025_walk_strip_zigzag.png` (forced zigzag with 4 leftward steps): 15 frames, 3 per tick, all facing right, 0 flips.
- **Energy tap toggled sprint on and straight back off.** Cause: `StatBar._gui_input` acted on both `InputEventScreenTouch` presses and left-mouse presses. On Android, `pointing/emulate_mouse_from_touch` is on, so each tap arrives as a touch and as an emulated mouse click, and that toggled twice. **Fix:** only one source counts (the real or emulated mouse press while emulation is on, else the touch press). Releases and the duplicate source are consumed (`accept_event`, so nothing reaches the world tap handler). Taps closer than 250 ms are ignored (`data/fx.json` `tap.debounce_ms`). **Audit:** every other HUD control (Pack / Skills / Map / Menu, minimap zoom, Accurate / Aggressive, prayers, shop, bank, craft) is a `Button` using the `pressed` signal, which reacts only to the mouse press, so each fires once. The minimap and world tap handlers are mouse-only. No other control had the pattern.
- Selftest: zigzag never flips, sustained reversal flips once, vertical never flips, jitter never flips, min-flip spacing, fight facing follows the target, data fps / frames, idle grace, `flip:false`, no mirror-pair frames in any actor sheet, sprint glide, and the Android tap sequence (touch press, emulated mouse press, touch release, mouse release). One tap = 1 toggle, two taps = 2, and with emulation off a touch+mouse pair still = 1.


### 13.15 Walk-in buildings (0.3.0)

The market-stall props are gone. Every shop is a walk-in building on the town
grid (`data/buildings.json` for shop data, `tools/layout_towns.py` for the
layout, which writes `data/towns/*.json`): blocking walls (`wall`,
`wall_front` on the door side), a `floor`, a 1-tile `doorway`, a blocking
counter, a keeper behind it, props (shelves, barrels, racks) and a hanging
sign. Seamless: no scene change, no loading.

* **Towns expanded** from 24x24 to 46x38 around the same spawn, so roads,
  camps and the dry ring are unchanged. The old resource quadrants moved to
  the corners unchanged; the plaza (bank, Exchange, hearth, workbench, dummy)
  is in the middle; four shop slots (two north with doors facing south, two
  south with doors facing north) and the empty player shop in the west band.
  Fenhollow: Fenhollow Provisions, Crestwright's Helms, Blacksmith (Edgewell
  Blades), Fletch & Stave. Cinderholt: Cinderholt Supply, The Mailhouse,
  Bossmaker's Shields, Blacksmith (Cleft & Haft). Saltmere: Saltmere
  Chandlery, Greave & Gusset, Blacksmith (Flange & Knob).
* **Roof cut-away.** Each building has a roof (tinted per town, name on the
  ridge). It fades out over 0.2 s while you stand in the doorway or inside
  that building, and back in when you leave. Only that building's roof
  changes. While a roof shows, the actors and objects under it are hidden.
  The facade row is never roofed, so the door and sign stay visible.
* **Keepers.** Tapping the keeper or the counter walks you through the door
  to the counter front. The keeper greets you (three original lines per shop,
  chat plus a speech bubble, 20 s cooldown), then the shop panel opens.
  Keepers idle-animate (breathe, blink), face the customer, and use their
  own non-mirrored, right-facing sheets.
* **AI customers.** When a detailed AI near you buys from a shop it walks in
  to the counter (or beside a stocked stand), lingers 5-9 ticks and leaves.
  It never stops in a doorway, and only does this when idle, so the economy
  is unchanged.
* **Pathing.** A* blocks walls, counters and props; a tap inside a building
  paths through the door. The minimap and world map draw the footprints and
  doors.
* **Old saves.** A player whose saved tile is now inside a wall or prop is
  moved to the nearest free outdoor tile.
* Every panel has a close button (X).

### 13.16 Blacksmith (0.3.0)

Each town's furnace and anvil moved off the plaza into a 9x9 walk-in
**Blacksmith**, combined with the town's weapon-smith shop (Fenhollow
swords, Cinderholt axes, Saltmere maces). The west side has the counter and
the smith (the shop keeper). The east side is the forge: anvil, furnace,
bellows, quench barrel, weapon rack and coal crate. The smith calls out
when you walk in. The stations work exactly as before: tap the furnace or
anvil inside. AI smiths path in through the door to use them. The roof
reads "Blacksmith"; the sign is an anvil.

### 13.17 Player shop (0.3.0)

Every town has one empty building with a For-sale sign and an estate agent
(Tamsin Deed). Only the player can buy it, for 1,500 marks (a coin sink;
`data/player_shop.json`). Once owned, the roof and sign read "Your Shop"
("<name>'s Shop" once players can name themselves) and the keeper becomes
your assistant, Pip.

* **Stands.** 8 display stands. Put items from your pack on a stand (1 gear
  piece or tool, or up to 50 of a stackable) at a price you set. The panel
  shows the local reference price, the Exchange bid/ask, the cheapest
  alternative in town and a deal label (Bargain / Good deal / Fair / Pricey /
  Overpriced). Stocked items are drawn on the stands. You can take items
  back, reprice, and see a sales log. The price is at least 1 and at most
  5x the going rate (anti-manipulation).
* **Who buys.** AI agents look in at their normal trading cadence (every tier,
  so it also sells while you are away). They buy what they need: food, fuel,
  inputs on their keep list, tool and weapon/armour upgrades they can use,
  and traders' arbitrage. Each look compares your price with the best local
  alternative:
  `deal = min(alternative, 1.25 x ref) / price` and
  `chance = 0.30 x deal^3 x attractiveness`. The chance is x0.15 if you are
  dearer than the alternative, 0 above 1.6x ref, and capped at 0.95.
  Attractiveness (0.6-1.4) rewards full stands, variety and items the town
  trades (a decor hook is in the data). Demand is bounded by needs, 40% of
  the agent's coins and 3 lots per agent per day.
* **Proceeds.** The buyer pays your price; the 2% Exchange tax (on sales of
  50+ marks) is taken and the rest goes to the till. You collect it at the
  counter, or turn on auto-bank (that town's vault). On walking in you see
  "Sold 12 items for 340 marks while you were away".
* **Rules.** You cannot buy from your own shop; traders may resell your
  stock elsewhere; the shop and stands are saved. Old saves load with every
  shop unowned.
* **Soak** (7 game days, a shop in every town restocked daily at ref x mult;
  `--soak=7 --pshop=<mult>`). Units sold per day, all 3 towns:

  | price | units/day | per town | marks/day (after tax) |
  |---|---|---|---|
  | 0.8x ref | 491 | 164 | 4,306 |
  | 1.0x ref | 298 | 99 | 2,969 |
  | 1.3x ref | 225 | 75 | 2,760 |

  At 1.0x over 14 days: 278 units/day. Money supply stays within bounds in
  every run (the collected till counts as your coins).

### 13.18 Walking (0.3.0 rework)

* **Facing** is decided in one place (`Actor._update_facing`) from this
  tick's horizontal movement. It flips on the first frame of a direction
  change and is kept on pure vertical moves.
* **Blur root cause.** `main._process` ran before its child actors, so the
  camera followed last frame's player position. The avatar jittered 1 world
  px (3 screen px) against the camera every frame while walking. Now the
  player's visual position is updated first and the camera uses the same
  rounded value; positions are whole world pixels.
* **8-direction movement.** Diagonal steps cost 1.414 (octile A*). No corner
  cutting past walls or water, or between two blocked tiles; one object
  (tree, rock) may be passed diagonally. Paths are string-pulled into
  straight grid lines, and the sprite moves along the exact straight line
  (no up/over staircase). Sprint takes 2 steps per tick along the same line.
* **Reversals.** Each tick's movement starts from where the sprite is drawn,
  so turning around mid-step never drifts 1 px the old way while already
  facing the new way.

### 13.19 QA bot (0.3.0)

`tools/qa_bot/run.sh` plays the real game with real rendering and touch
input, captures every frame and checks facing, ghosting, diagonals, jitter,
taps, hit bubbles, roofs, shops, the player shop and the Blacksmith. See
docs/QA_BOT.md. `scripts/release.sh` stages the APK only when the selftest
and the QA bot pass.
