# Findings

## In short

- **Where the values come from.** A depot's maintenance pool, its maintenance radius and its emissions are all set by the construction's update script when the building is built. No game command changes the pool or the radius afterwards, so the only way to change them is to rebuild the construction with new parameters. The plan is to wrap each depot construction's update script, read hidden level parameters, and scale the values.
- **How sure.** The values and the missing commands come straight from the game's scripts and type definitions, so they are certain. The rebuild method is the one another published mod already uses for industries, so it is likely to work for depots.
- **The big unknown.** Does a rebuild keep the depot's vehicles, their maintenance assignment and the depot's entity id? The whole design depends on it, and the probe mod (`depot_retrofits_1/`) tests it.
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
- Telling a depot construction apart: every base depot and maintenance `.con` names `configureDepotHudIconsFn` with a `depotType` in its templates. The Roundhouse mod's depot does not, but its files sit under `depots/`.

## Pollution tools in the base game

- The Industry Greenification tool (`gui/construction/tools/industry_greenify_tool.script.tl`, permit `ECO_INDUSTRY` at ranks 3, 6, 9, 12 and 15) cuts an industry's emissions by 80% (`emissionReductionPerEcoLevel` 0.8). Its handler stores any entity, but the emissions script only applies the eco factor to industries.
- The Cleaning Plant (rank 10, uses machines) removes 10,000 pollution at full output.
- A town's pollution rating averages samples over the town's whole area, so every depot inside the town border counts.

## Other mods

- **Industry Upgrades** (Stardorn) gives industries levels with the same method: a `loadConstruction` modifier wraps every industry's update script and declares hidden level params; buying a level rebuilds the construction from the game script. It has no licence, so this repo reuses the method only, never its code. It wraps only constructions marked as industries, so a depot wrapper does not overlap it.
- **Roundhouse** (a modular rail depot) builds one subconstruction with a `depot` table (pool 1, radius 800) and adds its modules into it.

## Unknowns

- Whether a rebuild keeps the depot's vehicles, their maintenance assignment and line assignments, and whether the construction and depot entity ids survive.
- What `fileName` the `loadConstruction` modifier receives for a depot `.con`, and whether a relative update script resolves correctly against it.
- Whether the game regenerates constructions when a save loads.
- Whether a raised pool is filled by more vehicles over the following weeks, and whether a larger radius picks up vehicles from further away.

## Test results

None yet. The first probe (`depot_retrofits_1/`, described in the repo's CLAUDE.md) rebuilds the busiest depot and maintenance building in a test save with a doubled pool and a 1.5 times wider radius, and logs whether the entities and the maintained vehicles survive.
