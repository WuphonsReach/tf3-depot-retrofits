# Findings

## In short

- **Where the values come from.** A depot's maintenance pool, its maintenance radius and its emissions are all set by the construction's update script when the building is built. No game command changes the pool or the radius afterwards, so the only way to change them is to rebuild the construction with new parameters. The plan is to wrap each depot construction's update script, read hidden level parameters, and scale the values.
- **How sure.** The values and the missing commands come straight from the game's scripts and type definitions, so they are certain. The rebuild method is the one another published mod already uses for industries, so it is likely to work for depots.
- **What a rebuild keeps.** The first probe rebuilt a road depot and a road maintenance building in a live save. Both kept their construction and depot entity ids and took the new pool and radius, and the rebuild cost nothing. But every vehicle maintained there lost its maintenance link, and within a game day the game had sent them to other buildings: the depot kept none of its 10, the maintenance building 4 of its 9. Whether the vehicles drift back to the larger buildings over the following months is the open question; the probe's later checks are still running.
- **Pollution.** The base game cannot green depots: the Industry Greenification tool only reaches industries. Depot emissions come from the same construction data, so the rebuild also covers the pollution tree.

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

## What a mod can and cannot change

- `api/tealdef/api/cmd.d.tl` has no command that changes a depot's pool or radius. The only maintenance command there sets a maintenance cost, and it is marked debug.
- `api.engine.util.proposal.createProposalReplaceConstruction(entity, params)` builds a proposal that replaces a construction with new parameters (`api/tealdef/api/engine/util.d.tl`). A game script sends it with `api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false)` from `update`, without a callback.
- A mod's `runFn` can register `addModifier("loadConstruction", fn)` and change any construction definition as it loads. The base game does this itself (`base/base_mod.lua` in `base.zip`).
- Construction params are 1-based: the catenary param's `defaultIndex = 2` means "Yes", and `rail/rail_depot.script.lua` tests `params.catenary == 2` (`scripts/construction/param_util.tl` in `scripts.zip`). A param can be declared with `postConstructionModifiable = false` (`api/tealdef/api/type.d.tl`, record `ConstructionScriptParam`).
- Depot `.con` files name their update script relative to their own folder (`"rail_depot.script@updateFn"`). `scripts/util.tl` `useFn` loads a script function from an absolute `file@function` reference.
- A construction script can be Teal: the base heliport's module update script is a `.script.tl` file that returns a table (`stations/air/heliport/modules.script.tl`).
- Telling a depot construction apart: every base depot and maintenance `.con` names `configureDepotHudIconsFn` with a `depotType` in its templates. The Roundhouse mod's depot does not, but its files sit under `depots/`. The base path signals (`infrastructure/signal/signal_path_a.con.lua`, `signal_path_c.con.lua`) name the same HUD script; they are edge objects (`edgeObject`), which the depots are not.
- The update script also sets the building's upkeep (`result.maintenanceCost`), so the wrapper can scale it in the same rebuild.

## Pollution tools in the base game

- The Industry Greenification tool (`gui/construction/tools/industry_greenify_tool.script.tl`, permit `ECO_INDUSTRY` at ranks 3, 6, 9, 12 and 15) cuts an industry's emissions by 80% (`emissionReductionPerEcoLevel` 0.8). Its handler stores any entity, but the emissions script only applies the eco factor to industries.
- The Cleaning Plant (rank 10, uses machines) removes 10,000 pollution at full output.
- A town's pollution rating averages samples over the town's whole area, so every depot inside the town border counts.

## Other mods

- **Industry Upgrades** (Stardorn) gives industries levels with the same method: a `loadConstruction` modifier wraps every industry's update script and declares hidden level params; buying a level rebuilds the construction from the game script. It has no licence, so this repo reuses the method only, never its code. It wraps only constructions marked as industries, so a depot wrapper does not overlap it.
- **Roundhouse** (a modular rail depot) builds one subconstruction with a `depot` table (pool 1, radius 800) and adds its modules into it.

## Unknowns

- Whether vehicles that lost their maintenance link after a rebuild come back to the rebuilt building, and how the game picks the building it sends them to.
- Whether a rebuild keeps line assignments (not logged by the first probe).
- Whether the game regenerates constructions when a save loads.
- Whether a raised pool is filled by more vehicles over the following weeks, and whether a larger radius picks up vehicles from further away.

## Test results

**First probe, partial** (`depot_retrofits_1/` 0.1-probe, described in the repo's CLAUDE.md; a 1900 save with 24 player depots and 90 vehicles). The probe rebuilt the busiest road depot and road maintenance building with a doubled pool and a 1.5 times wider radius.

- The `loadConstruction` modifier received `::/depots/...con.lua` names (for example `::/depots/road/road_depot/road_depot.con.lua`) and the relative update script references resolved against them. All seven base depot and maintenance constructions and the Roundhouse were wrapped; the two path signals were wrapped too, by mistake (fixed since: edge objects are skipped).
- The construction's params read back as `modules`, `seed` and `year`; the update script receives those plus `state` and `upgrade`.

| | Road depot | Road maintenance |
|---|---|---|
| Construction and depot ids after the rebuild | unchanged | unchanged |
| Pool | 12 → 24 | 16 → 32 |
| Radius | 400 → 600 | 600 → 900 |
| Money charged for the rebuild | none | none |
| Vehicles maintained before | 10 | 9 |
| About one game hour later | 0; all 10 name a station entity that no longer exists | 0; all 9 the same |
| One game day later | 0; all 10 assigned to other buildings | 5: 4 of the 9, plus 1 other vehicle |

The checks at 7 days, 1 month and 2 months are pending.
