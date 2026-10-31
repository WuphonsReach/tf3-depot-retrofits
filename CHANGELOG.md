# Changelog

Newest first. The number in the title is `modVersion` at the top of [mod.script.tl](depot_retrofits_1/content/mod.script.tl), which the game log prints at every load as `DEPOT_RETROFITS version <number>` (between releases it reads the next number with "-dev", for example `0.6-dev`). Each entry's last line is the one-liner for the Changelog field of the in-game uploader ([how to release](docs/publishing.md#releasing-a-version)). mod.io labels every uploaded file "1.0", whatever the number here is, so the number in this file and in the log is the one that tells builds apart.

## 0.5 (not released)

The first version meant for players.

- **Levels for depots and maintenance buildings.** Five retrofits of 15 levels each: maintenance radius (+5% a level), vehicles maintained (+10% a level, at least +1 vehicle), pollution (-5%), noise (-5%) and upkeep (-5% of the total). The highest level a retrofit can reach is the company rank you have claimed.
- **A Retrofit tab in the building's window**, next to the building's own tab. It has a Summary card (rank, radius, vehicles), one card per retrofit with a row of 15 boxes for the levels, and a buy button with the price. The upkeep after the next level matches the window's upkeep footer to the dollar, apart from the vehicles' running cost, which a rebuild resets.
- **Buying a level rebuilds the building** with the new level and charges the price once the rebuild is done. Levels are saved with the game. The game then reassigns the building's vehicles within a game day, sometimes to another building in range.
- **Which buildings.** All road, tram, rail and water depots and maintenance buildings, including ones built before the mod was added, and depots from other mods that use the game's depot icons, are marked as a depot, or sit in a `depots/` folder. On a depot built from modules (the Roundhouse mod's), the levels also cover what the modules add: their vehicles and their upkeep. The game's own rebuilds (electrifying, the catenary tool, module edits) keep the levels.

Release note: `First release: depots and maintenance buildings get levels for radius, vehicles, pollution, noise and upkeep, bought in the building's Retrofit tab.`
