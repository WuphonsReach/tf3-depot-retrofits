# Changelog

Newest first. The number in the title is `modVersion` at the top of [mod.script.tl](depot_retrofits_1/content/mod.script.tl), which the game log prints at every load as `DEPOT_RETROFITS version <number>` (between releases it reads the next number with "-dev", for example `1.1-dev`). Each entry's last line is the one-liner for the Changelog field of the in-game uploader ([how to release](docs/publishing.md#releasing-a-version)). mod.io labels every uploaded file "1.0", whatever the number here is, so the number in this file and in the log is the one that tells builds apart.

## 1.1 (not released)

- **A building the game cannot rebuild shows "Blocked".** Buying a level rebuilds the building, and the game refuses a rebuild when something built since stands in the way, such as a town building on the lot next door. In 1.0 the click then did nothing, and nothing was charged. The tab now asks the game first: the buy buttons read "Blocked", greyed out, and a yellow warning at the top of the tab says to clear what is in the way. The tab checks again every 2 seconds while blocked, paused or not, so the buttons come back by themselves once the way is clear, and for 30 seconds after that, so they grey out again if the town builds on the cleared lot. The buy is checked again when it is sent.

Release note: `Buildings the game cannot rebuild now show "Blocked" in the Retrofit tab instead of ignoring the click.`

## 1.0 (2026-10-31)

The first version meant for players.

- **Levels for depots and maintenance buildings.** Five retrofits of 15 levels each: maintenance radius (+5% a level), vehicles maintained (+10% a level, at least +1 vehicle), pollution (-5%), noise (-5%) and upkeep (-5% of the total). The highest level a retrofit can reach is the company rank you have claimed.
- **A Retrofit tab in the building's window**, next to the building's own tab. It has a Summary card (rank, radius, vehicles), one card per retrofit with a row of 15 boxes for the levels, and a buy button with the price, greyed out when the rank or the money is not enough, or with "No effect" when a radius level would add less than 1 m. The upkeep after the next level matches the window's upkeep footer to the dollar, apart from the vehicles' running cost, which a rebuild resets.
- **Buying a level rebuilds the building** with the new level and charges the price once the rebuild is done. Levels are saved with the game. The game then reassigns the building's vehicles within a game day, sometimes to another building in range.
- **Which buildings.** All road, tram, rail and water depots and maintenance buildings, including ones built before the mod was added, and depots from other mods that use the game's depot icons, are marked as a depot, or sit in a `depots/` folder. On a depot built from modules (the Roundhouse mod's), the levels also cover what the modules add: their vehicles and their upkeep. The game's own rebuilds (electrifying, the catenary tool, module edits) keep the levels.

Release note: `First release: depots and maintenance buildings get levels for radius, vehicles, pollution, noise and upkeep, bought in the building's Retrofit tab.`
