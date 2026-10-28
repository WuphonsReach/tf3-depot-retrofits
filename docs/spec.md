# Spec

## In short

Depots and maintenance buildings get levels, bought one at a time in the building's own window. There are five level trees: maintenance radius, vehicles maintained, pollution, noise, and upkeep. Each tree has 15 levels, and a tree's highest level available is the company's current rank (the game has 15 ranks). Levels cost money. The first four trees raise the building's upkeep; the upkeep tree cuts it, and a full upkeep tree pays for itself in about 13 game years on a building with every other tree at 15. It is being built inside probe 0.4: levels are stored, applied and bought for real, on rebuilding the construction with new parameters (see [findings.md](findings.md) for what the probes showed).

Open points are listed at the bottom.

## Level trees

| Tree | Game value changed | Per level | At level 15 |
|---|---|---|---|
| Maintenance radius | the depot's catchment radius | +5% | +75% |
| Vehicles maintained | the depot's maintenance pool | +10%, rounded to the nearest vehicle, and at least +1 vehicle | +150%, or +15 vehicles if that is more |
| Pollution | the building's pollution, in both emission states | -5% | -75% |
| Noise | the building's noise, in both emission states | -5% | -75% |
| Upkeep | the building's total upkeep, including what the other trees add | -5% of the total | -75% |

Vehicles maintained at level *n* is the larger of the base pool × (1 + 0.1*n*), rounded, and the base pool + *n*. Pools below 10 grow by exactly one vehicle per level; larger pools grow by the 10% steps.

| Base pool | Levels 1 to 15 |
|---|---|
| 6 (rail depot) | 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 |
| 8 (water depot) | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 |
| 12 (road and tram depots, rail and water maintenance) | 13, 14, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 28, 29, 30 |
| 16 (road maintenance) | 18, 19, 21, 22, 24, 26, 27, 29, 30, 32, 34, 35, 37, 38, 40 |

## Cost

Each tree has its own price ladder, the same for all five trees. Level *n* costs 0.10 × the building's build price × 1.35^(*n*−1):

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| × build price | 0.10 | 0.14 | 0.18 | 0.25 | 0.33 | 0.45 | 0.61 | 0.82 | 1.10 | 1.49 | 2.01 | 2.71 | 3.66 | 4.95 | 6.68 |

The first ten levels of a tree cost about 5.5 × the build price, a full tree about 25 ×, and all five trees about 127 ×. Levels are paid in money only. A level's price does not depend on the building's other levels, so the order of purchase does not change what anything costs. The cost basis may later differ by tree, depending on how much each tree is worth to the player.

## Upkeep

Each level bought in the radius, vehicles, pollution or noise tree adds 25% of the building's base upkeep, added up across trees. Upkeep levels add nothing. With all 60 of those levels, the upkeep is 16 × the base.

Each upkeep level then takes 5% of that total off: the upkeep is (1 + 0.25 × other levels) × (1 − 0.05 × upkeep levels) × the base. A full upkeep tree leaves a quarter of the total.

Payback of the upkeep tree. Every base building costs 6 × its yearly base upkeep to build ([findings.md](findings.md)), so a full upkeep tree (25.5 × the build price) costs about 153 × the base upkeep, wherever the building is.

| Other levels bought | Upkeep without the upkeep tree | Saved per year by a full upkeep tree | Payback of a full upkeep tree |
|---|---|---|---|
| 60 (all four trees at 15) | 16 × base | 12 × base | about 13 years |
| 30 | 8.5 × base | 6.4 × base | about 24 years |
| 15 | 4.75 × base | 3.6 × base | about 43 years |

The early levels pay back quickly and the late ones slowly: with the other trees full, level 1 saves 0.8 × base a year for 0.6 × base, level 15 the same 0.8 × base for 40 × base.

## Buying a level

- Levels are retrofits: they are bought for a building that already stands, including buildings placed before the mod was added. A newly placed depot or maintenance building starts at level 0 in every tree, and the build menu offers no way to place one with levels already set.
- Buying a level rebuilds the construction. The game then reassigns the vehicles the building maintained, and some may settle at another building. That is accepted: players rarely track which building maintains which vehicle, and the game reshuffles assignments in normal play too.

## Rank gate

A tree's maximum level equals the company rank.

## How it is built (0.5)

- **Storing levels.** One construction param per tree, values 0 to 15, declared with an availability year of 9999. That keeps it out of the build menu even in a save that runs past the year 3000 (the game's date card goes up to 5000), and a rebuild stores it.
- **Price.** The build price is 6 × the upkeep the game charges for the building now, divided by what its current levels do to the upkeep. That gives today's build price, with the game's upkeep factor and inflation included, without reading the depot scripts' base cost.
- **Charging.** The one-off price is booked as depot construction (journal entry, carrier from the building type). The extra upkeep is the building's own upkeep, raised in the rebuild, so it is charged with the normal upkeep.
- **Rank.** The rank the company window shows as reached (claimed). Buying a level above it is refused.
- **Where the player buys.** A Retrofit tab in the building's window, next to its depot tab (as Industry Upgrades adds an Upgrades tab to industries): one card per tree with the value now and after the next level, the upkeep it brings, and a buy button showing the price.

## Open points

- Whether the game's own rebuilds of a construction (for example electrifying a rail depot) keep the level params.
- Whether each tree gets its own cost basis. The upkeep tree's payback scales with its price: 0.79 × the ladder gives 10 years at full levels, 1.18 × gives 15.
- Whether the rank gate is an in-game setting. The proposal is a setting that is on by default.
