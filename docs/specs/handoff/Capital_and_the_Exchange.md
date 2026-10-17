# ASHFEN — Capital and the Exchange
Handoff for Lead Game Developer. Replaces the Exchange board in every city.

## The city
One capital, name pending (placeholder: Highfen). It sits at the map center, between Fenhollow, Cinderholt, and Saltmere, on the roads that already join the three towns. It is the focal point. The three towns stay specialist: Fenhollow swords and archery, Cinderholt bodies and shields, Saltmere legs and maces. The capital does not copy those stores.

Look: elegant, not thatch and not basalt-fortress. Pale stone, a market square, a tall exchange hall, paved streets, gardens, lit windows at night. Bigger than a town, smaller than a second continent. Bank, church altar, cook house, the player-store row, the player-house row, gates and guards (combat 25, same as the towns). No specialty weapon store. People come here to trade and to live, not to buy a sword off a counter.

## Player stores and houses
Player stores and player houses exist only in the capital. Fenhollow, Cinderholt, and Saltmere do not sell a store plot and do not have a house row. The old 1,500 mark shop in each town is gone.

Store: one plot in the market row, rented from the capital clerk. 8 display stands, till collected at the counter. Rent is 1,500 marks, paid to the capital, weekly upkeep after that so an empty store is a coin sink. A store sale is not an Exchange trade and pays no Exchange tax.

Pricing: a store can undersell the Exchange to pull customers. Buyers, including AI, compare the store price to the current Exchange mid for that item. A store at or under the mid gets more foot traffic. A store over the mid is ignored unless the Exchange has no offer. The undercut is the owner's choice. There is no forced discount. A full, varied shelf at a small undercut sells more than eight of the same sword. AI buyers prefer 5–15% under the mid.

AI-run stores follow the same rule. They price under the mid when they can still profit, and they stop restocking a line that is not selling.

## Where you buy
Three places. None is always cheapest.

**Exchange.** The player trading market. Any item, one hall, if a player or AI has posted it. Most convenient. Price is whatever the offers are inside the floor and ceiling. Cheap when the board is flooded. Empty when no one has listed it. It is not a store. It has no stock of its own.

**Town stores.** Always in stock. Only their select goods. Fenhollow: swords, daggers, archery. Cinderholt: bodies, shields, bucklers and kites. Saltmere: legs, maces, warhammers. General stores: tools, basic food, a few supplies. Fixed price near the Exchange mid. Never empty, never bargains. The cost is the walk. The towns are spread out, and none sells another town's specialty.

**Player stores.** Owner sets the price. Undersell the mid to take the sale. Over the mid and buyers walk to the hall instead.

Balance: the Exchange wins on convenience. Town stores win on certainty and on being the only counter when the board is bare. Player stores win on price when an owner chooses to take less.

House: one plot in the house row, bought once from the same clerk. It is not a store. Display stands do not work in it.

What a house has:
- A bank access chest. Same bank as the town chests. Items deposited here are in the bank, not a private stash.
- A bed. Sleeping in it refills Energy and Prayer to full, instantly. It does not heal HP and it does not pass time. One use, then a short cooldown so it is not a combat reset in the middle of a fight. Suggested cooldown: 60 seconds, in JSON.
- Add-on slots for a crafting station and a smithing station (anvil plus furnace). Bought from the clerk after the house, not included in the purchase. Crafting station lets you tan, string, and sew in the house. Smithing station lets you smelt and smith in the house. Both use the same recipes and the same bar and hide costs as the town stations. No XP bonus. The bonus is not walking to Cinderholt.

A house does not replace the Exchange, the town specialty stores, or the cook house. It replaces the walk for banking, prayer refill, energy refill, and, once the stations are in, smelting and crafting.

Construction, when it exists, furnishes the house and can add the station slots if they are not already a clerk purchase. Until then the clerk sells the two stations as upgrades.

A character may own one store and one house. They do not stack. AI who run a store use the capital row too, so the market looks lived in. AI do not buy houses. Houses are player-only in this pass.

## The Exchange
One board, in the capital exchange hall. It is only the player trading market. Players and AI post offers. The board never stocks an item itself. There is no Exchange in Fenhollow, Cinderholt, or Saltmere.

Rules:
- Offers inside the item floor and ceiling.
- 2% tax on the seller when a sale completes.
- Cancel returns the items or the held coins.
- Instant fill takes the listed price. No haggle.
- A store sale is not an Exchange trade and pays no Exchange tax.

What changes from the old town boards:
- One price on the board for the whole map. The profit in hauling is reaching the capital, not arbitrage between three boards.
- AI smiths carry surplus to the capital to post it. Town stores still sell their specialty at the fixed store price, always in stock.
- The Exchange is not tuned to be the cheap option. It is tuned to be the complete option.

## Roads
Gate-to-gate roads already exist. Add spurs from each town road into the capital square so a walker from Fenhollow, Cinderholt, or Saltmere reaches the hall without cutting swamp. The capital is the hub. The Scorch line, farms, and mines do not move.

## Tutorial
Wren's chain ends without an Exchange step. The Exchange is taught on the first capital visit, after the tutorial, as its own one-step errand from a clerk at the hall:

- Walk to the capital hall.
- Sell any 5 logs, ore, or raw fish at the guide price or lower.
- Buy any 1 item from a standing NPC offer (the hall keeps a few clerk offers so a solo player cannot get stuck).
- Reward: 1 influence, 70 marks. This errand sits at 10 influence, with Kell and Pye. It does not block them.

## Not in this pass
No capital-only ore. No throne quest. No second Exchange. Name and exact tile can wait for the map pass.
