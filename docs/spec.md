# Spec

## In short

Depots and maintenance buildings get levels, bought one at a time in the building's own window. There are three level trees: maintenance radius, vehicles maintained, and pollution. Each tree has 15 levels, and a tree's highest level available is the company's current rank (the game has 15 ranks). Levels cost money and raise the building's upkeep. Nothing is built yet: the design rests on rebuilding the construction with new parameters, and the first in-game probe checks that a rebuild keeps the building's vehicles (see [findings.md](findings.md)).

Open points are listed at the bottom.

## Level trees

| Tree | Game value changed | Per level | At level 15 |
|---|---|---|---|
| Maintenance radius | the depot's catchment radius | +5% | +75% |
| Vehicles maintained | the depot's maintenance pool | +10%, rounded to the nearest vehicle | +150% |
| Pollution | the building's noise and pollution, in both emission states | -5% | -75% |

Example, vehicles maintained for a rail depot with a pool of 6, levels 1 to 15: 7, 7, 8, 8, 9, 10, 10, 11, 11, 12, 13, 13, 14, 14, 15.

## Cost

Each tree has its own price ladder. Level *n* costs 0.20 × the building's build price × 1.5^(*n*−1):

| Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| × build price | 0.20 | 0.30 | 0.45 | 0.68 | 1.01 | 1.52 | 2.28 | 3.42 | 5.13 | 7.69 | 11.5 | 17.3 | 25.9 | 38.9 | 58.4 |

A full tree costs about 175 × the build price, and all three trees about 524 ×. Levels are paid in money only.

## Upkeep

Each level bought adds 25% of the building's base upkeep, added up across trees. All 45 levels make the upkeep 12.25 × the base.

## Rank gate

A tree's maximum level equals the company rank.

## Open points

- The top of the price ladder is steep (level 15 alone costs about 58 × the build price). Not yet decided whether to soften it.
- Whether the rank gate is an in-game setting. The proposal is a setting that is on by default.
- Which rank counts: the proposal is the rank the company window shows.
- How to read the build price actually paid. The depot scripts give a base cost, and the game raises it with the year.
- How the one-off price is charged: a journal entry, category not decided.
- How the extra upkeep is charged: a journal entry, or the building's own upkeep raised in the rebuild.
