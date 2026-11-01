# Spec

## In short

Depots and maintenance buildings get levels, bought one at a time in the building's own window. There are five level trees of 15 levels each, and a tree's highest level available is the company's claimed rank (the game has 15 ranks). Four trees (maintenance radius, vehicles maintained, pollution, noise) improve the building and raise its upkeep. Radius and vehicles levels cost 0.15 × the build price at level 1 and add 15% of the base upkeep each; noise costs 0.12 and adds 10%, pollution 0.08 and 5%, since those two do not change what the building does, and a town's rating spreads pollution over its whole area. In every tree, each level costs 15% more than the one before. The upkeep tree cuts the total upkeep, so it starts higher, at 0.25 × the build price, and a full upkeep tree pays for itself in about 12 game years on a building with the other four trees at 15. Version 1.0 stores, applies and sells levels by rebuilding the construction with new parameters (see [findings.md](findings.md) for what the tests showed).

## Trees

There are two kinds of tree:

- **Radius, vehicles, pollution and noise** improve the building, and each level raises its upkeep.
- **Upkeep** cuts the building's total upkeep, so it pays for itself over time. Its levels cost more.

Each tree has 15 levels, bought one at a time. Level *n* of a tree costs the tree's first-level share × the building's build price × 1.15^(*n*−1). Levels are paid in money only. A level's price does not depend on the building's other levels, so the order of purchase does not change what anything costs. All five trees at 15 cost about 36 × the build price.

## Radius, vehicles, pollution and noise

| Tree | Game value changed | Per level | At level 15 |
|---|---|---|---|
| Maintenance radius | the depot's catchment radius | +5% | +75% |
| Vehicles maintained | the depot's maintenance pool | +10%, or at least +1 vehicle | +150% or at least +15 vehicles |
| Pollution | the building's pollution, in both emission states | -5% | -75% |
| Noise | the building's noise, in both emission states | -5% | -75% |

Vehicles maintained at level *n* is the larger of the base pool × (1 + 0.1*n*), rounded, and the base pool + *n*. Pools below 10 grow by exactly one vehicle per level; larger pools grow by the 10% steps.

| Base pool | Levels 1 to 15 |
|---|---|
| 6 (rail depot) | 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 |
| 8 (water depot) | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 |
| 12 (road and tram depots, rail and water maintenance) | 13, 14, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 28, 29, 30 |
| 16 (road maintenance) | 18, 19, 21, 22, 24, 26, 27, 29, 30, 32, 34, 35, 37, 38, 40 |

### Price

The first-level share is 0.15 for radius and vehicles, 0.12 for noise and 0.08 for pollution:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Radius, vehicles (× build price) | 0.15 | 0.17 | 0.20 | 0.23 | 0.26 | 0.30 | 0.35 | 0.40 | 0.46 | 0.53 | 0.61 | 0.70 | 0.80 | 0.92 | 1.06 |
| Noise | 0.12 | 0.14 | 0.16 | 0.18 | 0.21 | 0.24 | 0.28 | 0.32 | 0.37 | 0.42 | 0.49 | 0.56 | 0.64 | 0.74 | 0.85 |
| Pollution | 0.08 | 0.09 | 0.11 | 0.12 | 0.14 | 0.16 | 0.19 | 0.21 | 0.24 | 0.28 | 0.32 | 0.37 | 0.43 | 0.49 | 0.57 |

A full radius or vehicles tree costs about 7.1 × the build price, a full noise tree 5.7 ×, a full pollution tree 3.8 ×, and all four about 24 ×.

Pollution and noise are cheaper because they do not change what the building does. A wider radius or a larger pool does: the building covers more vehicles, so fewer buildings are needed. Pollution is the cheapest: a town's pollution rating spreads the town's whole pollution over its area (at least 5 km²), so one building's cut barely moves it, and only many buildings together show a change (12 buildings at pollution 11 raised a town's rating by about 7 to 9 points; see [findings.md](findings.md)). Noise counts where people live and work, so a noise level near houses can matter on its own. Moving a building out of a town does not avoid this: its pollution only becomes another town's, and its vehicles tie it to where they run.

### Upkeep

Each level adds a share of the building's base upkeep, summed across the four trees: 15% for a radius or vehicles level, 10% for a noise level and 5% for a pollution level. With all 60 levels, the upkeep is 7.75 × the base.

## Upkeep

| Game value changed | Per level | At level 15 |
|---|---|---|
| the building's total upkeep, including what the other four trees add | -5% of the total | -75% |

The upkeep is (1 + 0.15 × (radius + vehicles levels) + 0.10 × noise levels + 0.05 × pollution levels) × (1 − 0.05 × upkeep levels) × the base, so a full upkeep tree leaves a quarter of the total. Upkeep levels add no upkeep of their own.

The upkeep tree cuts only the building's own upkeep, not the running cost of the vehicles it services (the accumulated costs the window's upkeep footer adds, which the game fills in itself; see [findings.md](findings.md)).

### Price

The first-level share is 0.25:

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| × build price | 0.25 | 0.29 | 0.33 | 0.38 | 0.44 | 0.50 | 0.58 | 0.67 | 0.76 | 0.88 | 1.01 | 1.16 | 1.34 | 1.54 | 1.77 |

A full upkeep tree costs about 11.9 × the build price.

### Payback

Every base building costs 6 × its yearly base upkeep to build ([findings.md](findings.md)), so a full upkeep tree costs about 71 × the base upkeep, wherever the building is. What it saves depends on how many levels the other four trees have:

| Other levels bought | Upkeep without the upkeep tree | Saved per year by a full upkeep tree | Payback of a full upkeep tree |
|---|---|---|---|
| All four trees at 15 | 7.75 × base | 5.8 × base | about 12 years |
| Radius and vehicles at 15 | 5.5 × base | 4.1 × base | about 17 years |
| Radius or vehicles alone at 15, or pollution and noise both at 15 | 3.25 × base | 2.4 × base | about 29 years |

The early levels pay back quickly and the late ones slowly: with the other trees full, level 1 saves 0.39 × base a year for 1.5 × base (4 years), level 15 the same 0.39 × base for 10.6 × base (27 years). The payback scales with the first-level share: 0.20 would give 10 years with the other trees full, 0.31 would give 15.

## Buying a level

- Levels are retrofits: they are bought for a building that already stands, including buildings placed before the mod was added. A newly placed depot or maintenance building starts at level 0 in every tree, and the build menu offers no way to place one with levels already set.
- Buying a level rebuilds the construction. The game then reassigns the vehicles the building maintained, and some may settle at another building. That is accepted: players rarely track which building maintains which vehicle, and the game reshuffles assignments in normal play too.

## Rank gate

A tree's maximum level equals the claimed company rank. It is fixed: there is no setting to turn it off. When the rank cannot be read, no level can be bought.

## How it is built (1.0)

- **Storing levels.** One construction param per tree, values 0 to 15, declared with an availability year of 9999. That keeps it out of the build menu even in a save that runs past the year 3000 (the game's date card goes up to 5000), and a rebuild stores it.
- **Price.** The build price is 6 × the upkeep the game charges for the building now, divided by what its current levels do to the upkeep, rounded to $100 (the game's whole-dollar upkeep leaves a few dollars of noise). That gives today's build price, with the game's upkeep factor and inflation included, without reading the depot scripts' base cost.
- **Charging.** The one-off price is booked as depot construction (journal entry, carrier from the depot) once the rebuild has landed; a rebuild that never lands is not charged. The extra upkeep is the building's own upkeep, raised in the rebuild, so it is charged with the normal upkeep.
- **Rank.** The rank the company window shows as reached (claimed), read through the base game's company progression script, or from the state it reads when that script cannot be loaded. Buying a level above it is refused, and so is every buy while neither read works.
- **Modular depots.** The levels scale what the modules add (pool, radius, upkeep), and an edit to the modules keeps the levels and recounts their upkeep, so the upkeep and the prices of further levels follow the building as it is now. Levels already bought are not repriced when the building grows or shrinks: buying small and adding modules afterwards skips the one-off price of the larger building. This is accepted, since the yearly upkeep the levels add grows with the modules.
- **Blocked.** The game refuses a rebuild that collides with what was built around the building since. The tab asks first and shows "Blocked" on every button, with a note in the Summary card, and asks again every 2 seconds while blocked, so the buttons come back once the way is clear; the buy is checked again when it is sent, and nothing is charged.
- **No effect.** A radius level adds 5% of the base radius. Where that is under 1 m (a base radius below 20 m, such as the Buffer Stop Depot mod's 1 m), the tab shows the radius now and a greyed "No effect" button instead of the next level.
- **Where the player buys.** A Retrofit tab in the building's window, next to its depot tab (as Industry Upgrades adds an Upgrades tab to industries): one card per tree with what the next level changes, the upkeep after it, and a buy button showing the price; the building's upkeep shows once, in the game's own upkeep footer.
