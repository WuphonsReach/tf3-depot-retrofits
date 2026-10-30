# User guide

## In short

- **What it does.** Depots and maintenance buildings get levels. A level widens the maintenance radius, adds vehicles maintained, or cuts pollution, noise or upkeep.
- **Where to buy.** Open the building's window and choose the Retrofit tab. Each level is bought on its own, for money.
- **What it costs.** Each level costs more than the one before. Every level except the upkeep levels also raises the building's upkeep.
- **Limit.** A tree's highest level is your company rank.
- **One catch.** Buying a level rebuilds the building. The game then reassigns the vehicles it maintained, and some may move to another building in range.
- **Status.** The mod is in development and not released yet.

## Which buildings

All road, tram, rail and water depots and maintenance buildings, including ones built before the mod was added. Depots from other mods get the tab too when they use the game's depot icons, are marked as a depot in their construction file, or sit in a `depots/` folder.

A newly placed building starts at level 0 in every tree. The build menu has no level options.

## Buying a level

The Retrofit tab sits next to the building's own tab. From top to bottom:

- **Summary**: your company rank, the building's radius, and its vehicles (maintained / maximum). If you have earned a higher rank but not claimed it yet, the Summary says so.
- **One card per tree**: the tree's icon and a row of 15 boxes, one per level: white for a level bought, grey for one you can buy at your rank, dark for one that needs a higher rank (hover over the boxes to see the levels bought and how many your rank allows, for example "Level 4/7 (max 15)"). Then the upkeep after the next level, what the next level changes (for example "400 m -> 420 m"), and a buy button with the price.
- **Upkeep footer**: the building's upkeep now, as in the building's own tab.

The upkeep figures, in the cards and in the footer, include a running cost for the vehicles the building is servicing, which goes up and down as vehicles come and go. Buying a level rebuilds the building and clears it, so right after a buy the footer can read a little below the figure the card showed. The upkeep tree does not cut this running cost.

The buy button shows "Rank N" and is greyed out when the next level needs a higher company rank. A tree at level 15 shows "Highest level".

Levels cannot be sold or lowered.

## The five trees

| Tree | Per level | At level 15 |
|---|---|---|
| Maintenance radius | +5% | +75% |
| Vehicles maintained | +10%, or at least +1 vehicle | +150% or at least +15 vehicles |
| Pollution | -5% | -75% |
| Noise | -5% | -75% |
| Upkeep | -5% of the total upkeep | -75% |

## What levels cost

Level prices follow the building's build price. Level 1 costs a tenth of it, and each level after that costs about a third more than the one before. Level 15 costs about 6.7 times the build price, and a full tree about 25 times.

Every tree has the same prices, and the order you buy in does not change them.

## Upkeep

Each level in the radius, vehicles, pollution or noise tree adds a quarter of the building's normal upkeep. With all four of those trees at 15, the upkeep is 16 times the normal upkeep.

The upkeep tree cuts the total by 5% per level, so a full upkeep tree leaves a quarter of it. On a building with the other four trees at 15, a full upkeep tree pays for itself in about 13 game years. The first upkeep levels pay back fastest.

## Good to know

- **Vehicles move after a buy.** The game reassigns the building's vehicles within a game day. Each one may come back or go to another building in range. Lines are not affected.
- **Levels are saved with the game.**
- **Not checked yet.** Whether the game's own rebuilds keep the levels (for example electrifying a rail depot), and what happens to leveled buildings when the mod is removed from a save.
