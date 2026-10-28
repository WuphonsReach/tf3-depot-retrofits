# Findings

## In short

- **Where the values come from.** A depot's maintenance pool, radius, noise, pollution and upkeep are all set by the construction's update script when the building is built. No game command changes them afterwards, so the mod wraps each depot construction's update script, reads level parameters, and rebuilds the construction to apply a level.
- **The method works, tested in game.** A rebuild keeps the construction and depot entity ids, keeps every vehicle's line, costs nothing, and applies all five values: pool, radius, noise, pollution (the emitter power follows the scaled values exactly) and upkeep. A game script can charge the level's price with a journal entry.
- **The cost of a rebuild: vehicles are reshuffled.** Every rebuild, even one that changes nothing, clears the maintenance link of every vehicle the building maintained. Within a game day the game assigns each vehicle again, by its own choice: in the test the maintenance buildings got all their vehicles back, the depot none of its 10 (they went to a nearer maintenance building and stayed there for the whole year). No command sets a vehicle's maintenance station, so the mod cannot put them back. Over the following months, the larger pool and radius draw vehicles in: the rebuilt maintenance building grew from 9 to 13 vehicles, the rebuilt depot later took 6 from a neighbour.
- **Pollution and noise.** The base game cannot green depots: the Industry Greenification tool only reaches industries. Depot emissions come from the same construction data, so the rebuild covers both trees. A larger pool also lowers emissions by itself, since the emission state follows vehicles in maintenance against the pool.
- **Unknown.** Whether loading a save regenerates constructions (a save-and-reload check is pending), and which finance rows the test charges landed in.

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

## Pollution tools in the base game

- The Industry Greenification tool (`gui/construction/tools/industry_greenify_tool.script.tl`, permit `ECO_INDUSTRY` at ranks 3, 6, 9, 12 and 15) cuts an industry's emissions by 80% (`emissionReductionPerEcoLevel` 0.8). Its handler stores any entity, but the emissions script only applies the eco factor to industries.
- The Cleaning Plant (rank 10, uses machines) removes 10,000 pollution at full output.
- A town's pollution rating averages samples over the town's whole area, so every depot inside the town border counts.

## Other mods

- **Industry Upgrades** (Stardorn) gives industries levels with the same method: a `loadConstruction` modifier wraps every industry's update script and declares hidden level params; buying a level rebuilds the construction from the game script. It has no licence, so this repo reuses the method only, never its code. It wraps only constructions marked as industries, so a depot wrapper does not overlap it.
- **Roundhouse** (a modular rail depot) builds one subconstruction with a `depot` table (pool 1, radius 800) and adds its modules into it.

## Unknowns

- Whether the game regenerates constructions when a save loads.
- Which finance rows the test charges landed in (the balance fell by exactly the amount; the rows were not checked).
- How the game picks the building a vehicle is assigned to.

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

The emitter power matched the scaled values at every check: for example the scaled depot at 6 of 24 read noise 25 and pollution 21.25, a quarter of the way from 20/20 to 40/25. A group of about five vehicles moved between the control and the scaled depot several times during the year; the depot's own 10 stayed at 262157 throughout.
