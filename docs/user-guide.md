# User guide

## In short

- **What it does.** Depots and maintenance buildings get levels. A level widens the maintenance radius, raises the number of vehicles maintained, or cuts pollution, noise or upkeep.
- **Where to buy.** Open the building's window and choose the Retrofit tab. Each level is bought on its own, for money.
- **What it costs.** Each level costs more than the one before. Every level except the upkeep levels also raises the building's upkeep.
- **Limit.** A retrofit's highest level is your company rank.
- **One catch.** Buying a level rebuilds the building. The game then reassigns the vehicles it maintained; some or all of them may go to another building in range.
- **Status.** Version 1.1.1: the tab shows "Blocked" when the game cannot rebuild the building.

## Which buildings

All road, tram, rail and water depots and maintenance buildings, including ones built before the mod was added. Depots from other mods get the tab too when they use the game's depot icons, are marked as a depot in their construction file, or sit in a `depots/` folder.

On a depot built from modules, such as the Roundhouse mod's, the levels also cover what the modules add: their vehicles and their upkeep.

A newly placed building starts at level 0 in every retrofit. The build menu has no level options.

## Buying a level

The Retrofit tab sits next to the building's own tab. From top to bottom:

- **Summary**: your company rank, the building's radius, and its vehicles (maintained / maximum). If you have earned a higher rank but not claimed it yet, the Summary says so.
- **One card per retrofit**: the retrofit's icon and a row of 15 boxes, one per level. White is a level bought, grey a level you can buy at your rank, dark a level that needs a higher rank; hover over the boxes to see the levels bought and how many your rank allows, for example "Level 4/7 (max 15)". Then the upkeep after the next level, what the next level changes (for example "400 m -> 420 m"), and a buy button with the price.
- **Upkeep footer**: the building's upkeep now, as in the building's own tab.

The upkeep figures, in the cards and in the footer, include a running cost for the vehicles the building maintains, which goes up and down as vehicles come and go. Buying a level rebuilds the building and resets that cost to zero, so right after a buy the footer can read a little below the figure the card showed. The upkeep retrofit does not cut this running cost.

The buy button shows "Rank N" and is greyed out when the next level needs a higher company rank. It is also greyed out, with the price still shown, when you do not have enough money for the level. When the game cannot rebuild the building, because something built after it stands in the way (a town building on the lot next door, or the road in front of it), every buy button shows "Blocked" and is greyed out, and a yellow warning at the top of the tab says so. Pause the game and clear what is in the way; with the window still open, the buttons should come back after a few seconds. Buy while still paused, so the town cannot build there again first. If you removed a road, build it again once the levels are bought, so the building is connected again. If the town builds there again within 30 seconds of the buttons coming back, the warning comes back by itself; after that, the next click on a buy button shows it. A retrofit at level 15 shows "Highest level".

Levels cannot be sold or lowered.

## The five retrofits

Each building has five retrofits, each with 15 levels:

| Retrofit | Per level | At level 15 |
|---|---|---|
| Maintenance radius | +5%, or at least +10 m | +75% or at least +150 m |
| Vehicles maintained | +10%, or at least +1 vehicle | +150% or at least +15 vehicles |
| Pollution | -5% | -75% |
| Noise | -5% | -75% |
| Upkeep | -5% of the total upkeep | -75% |

## What levels cost

Level prices follow the building's build price: what it would cost to build today. In the radius and vehicles retrofits, level 1 costs 15% of it, and each level after that costs 15% more than the one before. Level 15 costs about the build price, and all 15 levels about 7 times it.

The noise retrofit costs a little less (level 1 at 12% of the build price, all 15 levels about 6 times it), and the pollution retrofit about half (level 1 at 8%, all 15 levels about 4 times it). They make the town happier but do not change what the building does, unlike a wider radius or more vehicles, which can mean fewer buildings. A town's pollution rating counts its whole area, so it takes many levelled buildings to show a change.

The upkeep retrofit costs more, since it pays for itself: level 1 costs 25% of the build price, level 15 about 1.8 times it, and all 15 levels about 12 times it.

The order you buy in does not change any price.

## Upkeep

Each level in the radius or vehicles retrofit adds 15% of the building's normal upkeep, each noise level 10% and each pollution level 5%. With all four of those retrofits at 15, the upkeep is about 8 times the normal upkeep.

The upkeep retrofit cuts the total by 5% per level, so level 15 leaves a quarter of it. On a building with the other four retrofits at 15, a full upkeep retrofit pays for itself in about 12 game years. The first upkeep levels pay back fastest.

## Good to know

- **Vehicles move after a buy.** The game reassigns the building's vehicles within a game day. Each one may come back or go to another building in range. Lines are not affected.
- **The pollution map moves only a little.** Pollution and noise levels lower only what the building itself gives off. Vehicles keep their own pollution and noise, which still add to the area. The pollution overlay map uses a decibel scale and averages over a few minutes of play, so at the full 75% reduction the pollution map shows only 2 to 3 steps less next to the building, out of its 12. Hover over the change line on the Pollution or Noise card for a reminder.
- **The town window shows the effect best.** The Pollution Rating graph at the bottom of a town's pollution card follows the whole town's pollution; hover over a point to see its value. Expect a real but small change: stations and tracks often give off most of a town's pollution, and the mod does not change them. In a test, pollution level 11 on all 12 depots and maintenance buildings inside a town's borders raised the town's rating from about 41% to 50% over the next two years. The town stayed at Mediocre, and as its industries grew the rating slipped back to 47%. At today's prices those 132 levels cost about $23 million and add about $1.1 million a year to the 12 buildings' upkeep. In a smaller town, pollution level 9 on three buildings raised the rating from about 80% to 88%. The list of pollution sources above the graph shows depots and maintenance buildings on their own rows, but as shares of the town's total: they jump whenever an industry starts or stops producing, even when the depots do not change.

  ![The town's Pollution Rating graph from the 12-building test. Top: a point from before the levels were bought, at 41%, on a line that stayed flat for 20 years. Middle: 1976, at 50%. Bottom: 1978, back to 47%.](images/town-pollution-graph.png)
- **Levels are saved with the game.**
- **The game's own rebuilds keep the levels**, for example electrifying a rail depot, using the catenary tool on a tram depot, or adding or removing Roundhouse stalls.
- **Not checked yet.** What happens to levelled buildings when the mod is removed from a save. Keep a backup of any save you play with the mod.
