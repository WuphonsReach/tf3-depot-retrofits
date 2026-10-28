# Findings

## In short

- **Where the values come from.** A depot's maintenance pool, radius, noise, pollution and upkeep are all set by the construction's update script when the building is built. No game command changes them afterwards, so the mod wraps each depot construction's update script, reads level parameters, and rebuilds the construction to apply a level.
- **The method works, tested in game.** A rebuild keeps the construction and depot entity ids, keeps every vehicle's line, costs nothing, and applies all five values: pool, radius, noise, pollution (the emitter power follows the scaled values exactly) and upkeep. A game script can charge the level's price with a journal entry.
- **The cost of a rebuild: vehicles are reshuffled.** Every rebuild, even one that changes nothing, clears the maintenance link of every vehicle the building maintained. Within a game day the game assigns each vehicle again, by its own choice: in the test the maintenance buildings got all their vehicles back, the depot none of its 10 (they went to a nearer maintenance building and stayed there for the whole year). No command sets a vehicle's maintenance station, so the mod cannot put them back. Over the following months, the larger pool and radius draw vehicles in: the rebuilt maintenance building grew from 9 to 13 vehicles, the rebuilt depot later took 6 from a neighbour.
- **Pollution and noise.** The base game cannot green depots: the Industry Greenification tool only reaches industries. Depot emissions come from the same construction data, so the rebuild covers both trees. A larger pool also lowers emissions by itself, since the emission state follows vehicles in maintenance against the pool.
- **Saved with the game.** Loading a save does not rerun the construction scripts: the rebuilt buildings came back with their scaled values and level params, and the wrapper was not called.
- **Keeping levels out of the build menu.** A level param declared with an availability year far in the future (`yearFrom` 3000) does not show in the build menu and is not passed when a depot is placed, yet a rebuild stores it and passes it to the update script. A param that is not declared at all behaves the same way. A declared param with a single value still shows in the menu. The mod declares 9999, since a long game can pass 3000; at 9999 the build menu showed no level options either, and a building placed by hand started at level 0 (probe 0.4).
- **Levels at scale (probe 0.4).** 18 of the save's 24 buildings were given levels by rebuilding them (all five trees, levels 0 to 15); pool, radius, upkeep and stored levels matched the formulas for all 18 at every check up to a game month, and the emitter power followed the scaled emission states.
- **Where the levels card goes.** Every vehicle depot, depot or maintenance building, opens the base maintenance station window, which shows the cards registered for its extension point. A mod adds a card with a `react-plugin` resource; no window script is replaced. It shows on road, rail and water depots and road maintenance buildings, levelled or not, once the card finds the construction from the depot itself: the window's own `constructionEntity` left it hidden. Buying from it is not yet tested.
- **Reading the rank.** The base `company_progression_util.tl` gives the claimed rank (`level`) and the earned rank (`potentialLevel`); the company window reads it the same way. It works from a game script (read rank 2, Mechanic, as the company window showed).
- **Two upkeep figures.** The depot list and `calcMaintenanceForSubconstruction` give the same yearly upkeep ($37,500 for a road depot); the figure at the foot of the building window is a little higher on most buildings and rose while the game ran ($38,148, later $38,310, for the same depot). The card prices from the first. What the window adds is Open.
- **Unknown.** Whether the game's own rebuilds of a construction (for example electrifying a rail depot) keep the level params; which finance rows the test charges show under.

## Depot values in the base game

Source: each depot's update script in `base/content/depots/{road,rail,water}.zip`, for example `rail/rail_depot.script.lua` and `road/road_maint_station.script.lua`. The values sit in the subconstruction's `depot` table (`maintenancePool`, `catchmentArea.radius`), its `metadata.emissions` (two states, idle and full), and the result's `cost` and `maintenanceCost`.

| Building | Pollution idle → full | Noise idle → full | Pool | Radius | Upkeep per year | Build cost |
|---|---|---|---|---|---|---|
| Rail depot | 100 → 120 | 50 → 100 | 6 | 800 | 100k | 6 × upkeep |
| Road depot | 80 → 100 | 40 → 80 | 12 | 400 | 30k | 6 × upkeep |
| Tram depot | 80 → 100 | 40 → 80 | 12 | 400 | 60k | 6 × upkeep |
| Water depot | 80 → 100 | 40 → 80 | 8 | 1000 | 100k | 6 × upkeep |
| Road maintenance | 40 → 80 | 20 → 40 | 16 | 600 (the script's capture params can override it) | 10k | 60k |
| Rail maintenance | 50 → 100 | 20 → 40 | 12 | 800 | 40k | 240k |
| Water maintenance | 50 → 100 | 20 → 40 | 12 | 1400 | 40k | 240k |

The rail depot's upkeep and cost are multiplied by its template's year coefficient (1, 3 or 9 by era, in `rail/rail_depot.con.lua`). For scale, processing industries reach 250 to 750 pollution and mines 10 to 30.

## How the game uses them at run time

- The `VEHICLE_DEPOT` component on the depot entity holds `maintenancePool`, `catchmentArea` and pool usage statistics (`api/tealdef/api/engine.d.tl`, record `VehicleDepot`). Ordinary depots and maintenance buildings both carry it; a maintenance building is a depot with no in or out nodes (`gui/entity_window/maintenance_station/maintenance_station.tl` in `gui.zip`).
- The depot entity is a subconstruction of the construction. The game finds the construction with `streetConnectorSystem.getConstructionEntityForSubconstruction` or `getConstructionEntityForDepot`, and the `CONSTRUCTION` component lists its `depots` (`api/tealdef/api/engine/system.d.tl`, `engine.d.tl`).
- The maintenance window shows pool usage as the count from `transportVehicleSystem.getVehiclesForMaintenanceStation(depot)` against `maintenancePool` (`gui/entity_window/entity_window_util.tl`). Each vehicle's `TRANSPORT_VEHICLE` component also names its `maintenanceStation`.
- Emissions: `game_mechanics/emission/emissions.script.tl` sets every emitter every few updates. For a depot, the emission state slides between the two `metadata.emissions` entries with vehicles in maintenance against the pool. The eco factor is applied only to industries; depots, stations and warehouses always get 1.
- Upkeep: the construction entity's `MAINTENANCE_COST` component holds the script's `maintenanceCost`. `api.engine.util.maintenance.calcMaintenanceForSubconstruction(depot)` returns the figure actually charged, 1.25 times that in the test save (probably its maintenance difficulty setting).
- Maintenance assignment, seen in game: a vehicle's `maintenanceStation` names no existing station while it has none (probably the empty id). The game fills it within about a day, and the link then mostly stays; some vehicles lose it now and then in normal play and are assigned again, sometimes to another building.

## What a mod can and cannot change

- `api/tealdef/api/cmd.d.tl` has no command that changes a depot's pool or radius. The only maintenance command there sets a maintenance cost, and it is marked debug.
- `api.engine.util.proposal.createProposalReplaceConstruction(entity, params)` builds a proposal that replaces a construction with new parameters (`api/tealdef/api/engine/util.d.tl`). A game script sends it with `api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false)` from `update`, without a callback.
- A mod's `runFn` can register `addModifier("loadConstruction", fn)` and change any construction definition as it loads. The base game does this itself (`base/base_mod.lua` in `base.zip`).
- Construction params are 1-based: the catenary param's `defaultIndex = 2` means "Yes", and `rail/rail_depot.script.lua` tests `params.catenary == 2` (`scripts/construction/param_util.tl` in `scripts.zip`). A param can be declared with `postConstructionModifiable = false` (`api/tealdef/api/type.d.tl`, record `ConstructionScriptParam`).
- Depot `.con` files name their update script relative to their own folder (`"rail_depot.script@updateFn"`). `scripts/util.tl` `useFn` loads a script function from an absolute `file@function` reference.
- A construction script can be Teal: the base heliport's module update script is a `.script.tl` file that returns a table (`stations/air/heliport/modules.script.tl`).
- Telling a depot construction apart: every base depot and maintenance `.con` names `configureDepotHudIconsFn` with a `depotType` in its templates. The Roundhouse mod's depot does not, but its files sit under `depots/`. The base path signals (`infrastructure/signal/signal_path_a.con.lua`, `signal_path_c.con.lua`) name the same HUD script; they are edge objects (`edgeObject`), which the depots are not.
- The update script also sets the building's upkeep (`result.maintenanceCost`), so the wrapper can scale it in the same rebuild.
- Charging money: a game script books a journal entry with `api.cmd.makeJournalBookAssetCmd(player, entry, position)`, the way the base marketing tool charges for a campaign (`gui/construction/tools/marketing_campaign_tool.script.tl`). The categories are in `scripts/journal.d.tl` (base tealdef): type `CONSTRUCTION` with subcategory `DEPOT`, type `MAINTENANCE` with `INFRASTRUCTURE`, and so on.
- No command sets a vehicle's maintenance station (`api/tealdef/api/cmd.d.tl`).

## The building window

- Clicking a depot or a maintenance building opens `MaintenanceStationWindowContent` for its `VEHICLE_DEPOT` entity (`gui/entity_window/make_entity_window.tl` in `gui.zip`). A construction with one such subconstruction opens it directly; one with several gets a tab per subconstruction.
- That window collects cards from `MaintenanceStationEowExtensionPoint` (`gui/entity_window/maintenance_station/maintenance_station_eow.script.tl`). The base cards are registered by resources of type `react-plugin ::MaintenanceStationEowExtensionPoint` with a `filePath`, an optional `condition` and an `order` (pool 20, balance 30, statistics 40, vehicles 50; for example `maintenance_station_balance.res.lua`). The card function receives the depot entity, the ownership state and the construction entity (nil while the construction cannot be modified).
- The other route is a construction's own `entityWindowScript`, as the Cleaning Plant uses (`game_mechanics/emission/pollution_cleanup_facility_hud.script.tl`): it replaces the whole window and adds custom tabs. Industry Upgrades uses the plugin route for industries.
- A GUI script sends an event to game scripts with `api.cmd.makeScriptingSendEventCmd("", id, name, param)`; a game script receives it in `handleEvent` once it has called `state:subscribeToEvent(name)`. The company window's rank claim works this way (`game_mechanics/company/company.tl` and `company_growth.script.tl`).
- Widgets: `builtin.Button` takes `content` and `onClick`; any widget's `meta.enabled` greys it out (`scripts/builtin.d.tl`, `scripts/react.d.tl` in base tealdef).

## Company rank

- `company_progression_util.getCompanyProgressionState(player)` (`game_mechanics/company/company_progression_util.tl`) reads the state of `company_progression.gs`: `level` is the rank claimed in the company window, `potentialLevel` the rank earned. Rank rewards count from `level`.

## Pollution tools in the base game

- The Industry Greenification tool (`gui/construction/tools/industry_greenify_tool.script.tl`, permit `ECO_INDUSTRY` at ranks 3, 6, 9, 12 and 15) cuts an industry's emissions by 80% (`emissionReductionPerEcoLevel` 0.8). Its handler stores any entity, but the emissions script only applies the eco factor to industries.
- The Cleaning Plant (rank 10, uses machines) removes 10,000 pollution at full output.
- A town's pollution rating averages samples over the town's whole area, so every depot inside the town border counts.

## Other mods

- **Industry Upgrades** (Stardorn) gives industries levels with the same method: a `loadConstruction` modifier wraps every industry's update script and declares hidden level params; buying a level rebuilds the construction from the game script. It has no licence, so this repo reuses the method only, never its code. It wraps only constructions marked as industries, so a depot wrapper does not overlap it.
- **Roundhouse** (a modular rail depot) builds one subconstruction with a `depot` table (pool 1, radius 800) and adds its modules into it.

## Unknowns

- Which finance rows the test charges landed in (the balance fell by exactly the amount; the rows were not checked).
- How the game picks the building a vehicle is assigned to.
- Whether a rebuild the game itself starts (a construction upgrade tool, a post-construction param change) keeps a param hidden by `yearFrom` or an undeclared one.

## Test results

Both probes ran on the same 1900 save, with 24 player depots and 90 vehicles; the second ran on a fresh load of the save, not on top of the first.

**Probe 0.1** (pool and radius only) rebuilt the busiest road depot and road maintenance building. The `loadConstruction` modifier received `::/depots/...con.lua` names (for example `::/depots/road/road_depot/road_depot.con.lua`) and the relative update script references resolved against them; all seven base depot and maintenance constructions and the Roundhouse were wrapped. The construction's params read back as `modules`, `seed` and `year`; the update script receives those plus `state` and `upgrade`. Same outcome as below: ids kept, values applied, all vehicles unlinked, reassigned within a day (depot 0 of 10 back, maintenance building 4 of 9).

**Probe 0.2** (described in the repo's CLAUDE.md) rebuilt three buildings: the busiest road depot and road maintenance building with all five probe values (pool x2, radius x1.5, noise x0.5, pollution x0.25, upkeep x2), and the next busiest road maintenance building as a control, with nothing changed. Then it booked two $1,000 test charges; the balance fell by $2,000. It checked 11 times, up to a game year later.

| | Depot, scaled | Maintenance, scaled | Maintenance, control |
|---|---|---|---|
| Construction and depot ids | unchanged | unchanged | unchanged |
| Pool | 12 → 24 | 16 → 32 | 16 |
| Radius | 400 → 600 | 600 → 900 | 600 |
| Upkeep (script → charged) | 30k → 60k (charged 37.5k → 75k) | 10k → 20k (12.5k → 25k) | 10k (12.5k) |
| Emissions, noise/pollution idle → full | 40/80 → 80/100 became 20/20 → 40/25 | 20/40 → 40/80 became 10/10 → 20/20 | unchanged |
| Money charged for the rebuild | none | none | none |
| Vehicles maintained before | 10 | 9 | 9 |
| About one game hour later | 0; all 10 unlinked | 0; all 9 unlinked | 0; all 9 unlinked |
| 1 day | 0; all 10 at maintenance building 262157 (6/16 before, now full) | 10: all 9 back plus 1 | 9: all 9 back |
| 7 days | 0 | 11 | 7 (5 of the 9) |
| 1 month | 1 | 12 | 5 |
| 2 months | 6 (5 of them from the control) | 13 | 3 |
| 6 months | 0 | 12 | 11 |
| 1 year | 6 (5 from the control) | 13 (8 of the 9) | 2 (none of the 9) |
| Lines kept | all 10 | all 9 | all 9 |

After the year, the game was saved, quit and the autosave loaded again: the three buildings still had the same pool, radius, upkeep, emitter power and level params, and no wrapper call was logged during the load.

The emitter power matched the scaled values at every check: for example the scaled depot at 6 of 24 read noise 25 and pollution 21.25, a quarter of the way from 20/20 to 40/25. A group of about five vehicles moved between the control and the scaled depot several times during the year; the depot's own 10 stayed at 262157 throughout.

**Probe 0.3** (params; on a fresh load of the same save) rebuilt the three busiest buildings, each with one variant of a level param set to 6, and booked two test charges.

| Variant | In the build menu | Passed when a depot is placed | After the rebuild |
|---|---|---|---|
| Declared, `yearFrom` 3000, values 0 to 15 | no | no | stored as 6, passed to the update script, unchanged after 7 days |
| Declared, one value | yes, a box showing 0, for every depot type | 1 | stored as 6, passed, unchanged |
| Not declared | no | no | stored as 6, passed, unchanged |

The build menu was checked for the road, tram, road maintenance, rail, rail maintenance, water and water maintenance buildings. When a depot is placed, the params also carry `constructOpt56` and `constructOpt78`; after a rebuild they carry `upgrade`.

A road maintenance building placed by hand during the run was stored without the future-year param (level 0) and with the single-value param at 1. Within days it took vehicles from the full maintenance building next to it (that one went from 16/16 to 14/16, the new one to 7/16), with no rebuild involved: the game moves vehicles to a new building on its own.

The test charges ($12,345 as depot construction, $23,456 as infrastructure maintenance) lowered the balance by exactly $35,801. The construction charge appeared in the finance table's construction rows (key 2/2/6, which also holds the player's other construction this year); the maintenance charge is not among the investment rows the probe logs.

**Probe 0.4** (levels; on a fresh load of the same save, 27 January 1900, company rank 2). A game day after the load the probe gave levels to 18 of the 24 player buildings and left 6 as controls. The 4 checks (1 game hour, 1 day, 7 days, 1 month) all read 18 of 18 matching the formulas: pool, radius, script upkeep (`MAINTENANCE_COST`) and stored levels. The charged upkeep stayed 1.25 times the script value throughout, for example the water depot at 4/8/12/0/1 (radius/vehicles/pollution/noise/upkeep): 100k to 665k script, 831,250 charged, as the depot list showed. Examples at the month check:

| Building | Levels | Pool | Radius | Upkeep charged | Noise / pollution power (vehicles in use) |
|---|---|---|---|---|---|
| Road maintenance, all 15 | 15/15/15/15/15 | 16 → 40 | 600 → 1050 | 12,500 → 12,500 | 21.25/42.5 (1 of 16) → 5.25/10.5 (2 of 40) |
| Road depot, all but upkeep 15 | 15/15/15/15/0 | 12 → 30 | 400 → 700 | 37,500 → 600,000 | 43.3/81.7 (1 of 12) → 10.7/20.3 (2 of 30) |
| Rail maintenance | 0/10/7/15/7 | 12 → 24 | 800 | 50,000 → 292,500 | 20/50 → 5/32.5 (idle) |
| Control, road depot | none | 12 | 400 | 37,500 | 73.3/96.7 (10 of 12), unchanged |

The build menu for road depots and a maintenance building showed only height, rotation and underground; a road maintenance building placed by hand ($75,000) was listed at 0/16 vehicles and $12,500, so at level 0. The Retrofit card did not appear in the windows of a road depot, two road maintenance buildings and a rail depot, and the log had no line from the card's script.

After a fix (the card looks the construction up from the depot), a second fresh load showed the Retrofit card in the windows of a road depot, two road maintenance buildings (one levelled, one control), a road maintenance building placed during the run, the rail depot and the ship depot. Each showed rank 2, the stored levels and the prices the formulas give: $22,500 for any first level on the road depot, $7,500 on road maintenance, $75,000 on the rail and ship depots; on the levelled maintenance building (3/4/1/5/13) pollution level 2 cost $10,125 and the trees already at or above rank 2 showed the rank they need. No level was bought in that run.

