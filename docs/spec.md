# Spec

## In short

Depots and maintenance buildings get levels, bought one at a time in the building's own window. There are three level trees: maintenance radius, vehicles maintained, and pollution. Each tree has 15 levels, and a tree's highest level available is the company's current rank (the game has 15 ranks). Levels cost money and raise the building's upkeep. Nothing is built yet: the design rests on rebuilding the construction with new parameters, and the first in-game probe checks that a rebuild keeps the building's vehicles (see [findings.md](findings.md)).

Open points are listed at the bottom.

## Level trees

| Tree | Game value changed | Per level | At level 15 |
|---|---|---|---|
| Maintenance radius | the depot's catchment radius | +5% | +75% |
| Vehicles maintained | the depot's maintenance pool | +10%, rounded to the nearest vehicle, and at least +1 vehicle | +150%, or +15 vehicles if that is more |
| Pollution | the building's noise and pollution, in both emission states | -5% | -75% |

Vehicles maintained at level *n* is the larger of the base pool × (1 + 0.1*n*), rounded, and the base pool + *n*. Pools below 10 grow by exactly one vehicle per level; larger pools grow by the 10% steps.

| Base pool | Levels 1 to 15 |
|---|---|
| 6 (rail depot) | 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 |
| 8 (water depot) | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 |
| 12 (road and tram depots, rail and water maintenance) | 13, 14, 16, 17, 18, 19, 20, 22, 23, 24, 25, 26, 28, 29, 30 |
| 16 (road maintenance) | 18, 19, 21, 22, 24, 26, 27, 29, 30, 32, 34, 35, 37, 38, 40 |

## Cost

Each tree has its own price ladder. Level *n* costs 1/15 (0.0667) × the building's build price × 1.5^(*n*−1):

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| × build price | 0.067 | 0.10 | 0.15 | 0.23 | 0.34 | 0.51 | 0.76 | 1.14 | 1.71 | 2.56 | 3.84 | 5.77 | 8.65 | 13.0 | 19.5 |

The first ten levels of a tree cost about 7.6 × the build price, a full tree about 58 ×, and all three trees about 175 ×. Levels are paid in money only. The cost basis may later differ by tree, depending on how much each tree is worth to the player.

## Upkeep

Each level bought adds 25% of the building's base upkeep, added up across trees. All 45 levels make the upkeep 12.25 × the base.

## Rank gate

A tree's maximum level equals the company rank.

## Open points

- Whether each tree gets its own cost basis, and whether the 1.5 × step between levels stays: the step sets the shape, and level 15 alone is a third of a tree's total.
- Whether the rank gate is an in-game setting. The proposal is a setting that is on by default.
- Which rank counts: the proposal is the rank the company window shows.
- How to read the build price actually paid. The depot scripts give a base cost, and the game raises it with the year.
- How the one-off price is charged: a journal entry, category not decided.
- How the extra upkeep is charged: a journal entry, or the building's own upkeep raised in the rebuild.
