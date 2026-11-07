# Compatibility with other mods

## In short

- **One known incompatibility: TRM: Industry Emissions**, when it loads after Depot Retrofits and its "Transport Building Emissions" setting is "Rebalanced" (the default). New base depots and maintenance buildings can then not be placed; existing ones keep working. Reported on the mod.io page on 2026-11-06; the cause is read from its code, not yet reproduced here.
- **Workaround:** load Depot Retrofits after TRM: Industry Emissions, or set that setting to "Base Game". With Depot Retrofits last, both mods apply: the levels and TRM's halving multiply.
- **Fix planned on our side** (TODO.md, "Compatibility"): make the wrapper loadable the way TRM loads a script, so either order works. Depot Retrofits takes no dependency on TRM.
- **Expected to stack, from reading their code (not tested):** Station, Warehouse & Capacity Tuner and Noise & Pollution Tuner multiply the values a depot has, so their factors and the levels multiply. TRM: Infrastructure Upkeep leaves depots alone.
- **Tested in game:** the Roundhouse, Modern Railway Depot and Boathouse mods' depots (docs/design/findings.md, "Other mods").

## Known incompatibilities

### TRM: Industry Emissions

- **The mod.** [TRM: Industry Emissions](https://mod.io/g/transportfever3/m/trm-industry-emissions) (EloudaLightstar, `trm_building_emissions_1`, part of the "Transport Rework Mod" series), read in the version updated 2026-10-27. It replaces the base emissions game script with its own copy, and with "Transport Building Emissions" at "Rebalanced" its `loadConstruction` modifier wraps the update script of the base transport buildings it lists by `.con` file name: the four depots and the three maintenance buildings at a factor of 0.5, plus airports, helipads, street and water stations and warehouses. Depots from other mods are not listed, so they are not affected.
- **What goes wrong.** Its modifier works out the path of the script it wraps by adding `.lua` to the reference it finds in `updateScript`, loads that file with `ug_require` and expects it to define the global `data()`, as the base game's `.lua` scripts do (its `mod.script.tl`, `originalScriptPath`, and `game_mechanics/building_emissions/building_build.script.lua`, `loadOriginal`). When it runs after Depot Retrofits, the reference it finds is our wrapper's, `depot_retrofits_1::/construction.script@update`. That file is `construction.script.tl` and returns its table instead of defining `data()`, so TRM's load fails. The game runs the update script for every placement preview, so the building cannot be placed. Built buildings are not rebuilt and keep working until something rebuilds them (a level buy, a module edit, catenary).
- **The other order works.** When Depot Retrofits runs second, it wraps TRM's wrapper and loads it with base `util.useFn`, which handles both kinds of script. TRM passes the capture params on unchanged (it only adds its own `be*` keys), so our wrapper finds its `depotRetrofits` entry, runs TRM's script, and scales the result. The two reductions multiply: pollution level 15 with TRM gives 0.25 × 0.5 of the base. TRM marks each list it scaled with its factor (`beScale`) so that its emissions script can undo the factor later. Whether that script keeps our share of the reduction on built buildings is not checked.
- **Workarounds.** Load Depot Retrofits after TRM: Industry Emissions, or set TRM's "Transport Building Emissions" to "Base Game" (the reporter found both).
- **Status.** Cause read from TRM's code; not yet reproduced here. Fix planned (TODO.md).

## Overlapping mods, expected to stack (read from their code, not tested)

- **Station, Warehouse & Capacity Tuner** (`edgar_swc_tuner_1`) multiplies the pool and radius it finds on depots (airports and heliports too) in a `loadScript` wrapper. Our wrapper loads the original with `util.useFn`, which goes through `loadScript`, so its wrapper sits inside ours and the factors multiply.
- **Noise & Pollution Tuner** (`edgar_noise_pollution_1`) multiplies the emissions the base emissions script sends for depots by a global factor, in its game script. The levels apply first, then its factor.
- **TRM: Infrastructure Upkeep** (`trm_upkeep_rebalance_1`) skips everything under `depots/` when it changes upkeep.
- **CRH EMU Maintenance Depot** is wrapped (it sits under `depots/`). The vehicles, radius and upkeep levels apply to the whole building, but its only emissions are on a warehouse part, and the wrapper scales emissions only on parts with a depot, so its pollution and noise levels do nothing.

## Declaring an incompatibility

- A mod's `mod.json` can list `incompatibilities` (`api/tealdef/api/type/mod.d.tl`, `ModIncompatibility`: a mod reference), and `dependencies` can be `optional` and `loadBefore`. No mod among about 700 subscribed ones uses `incompatibilities`, so how the game shows it is not seen.
- Depot Retrofits declares neither for TRM. An incompatibility would also flag the order that works and the "Base Game" setting. A dependency is not wanted. Whether the uploader would send a `mod.json` dependency to mod.io is not checked.
