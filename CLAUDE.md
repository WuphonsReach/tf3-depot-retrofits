# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Transport Fever 3 script mod in development: depots and maintenance buildings get levels for maintenance radius, vehicles maintained, pollution, noise and upkeep, bought in the building's window. The spec is [docs/spec.md](docs/spec.md); the verified game facts and the open unknowns are in [docs/findings.md](docs/findings.md). Read findings before changing mechanics.

The repo is local only for now: no remote, work on `main`. The name avoids "Upgrades" (too close to another mod's "Industry Upgrades"); inside the mod the terms are "level" and "retrofit".

There is no build step and no unit tests. The code is Teal (`.tl`) that the game loads directly, and the only checks are the type checker and testing in the game. The user runs every in-game test.

## Commands

```bash
# Type check (needs gitignored tlconfig.lua copied from tlconfig.example.lua, with <tf3_install_folder> filled in)
export PATH="$HOME/.luarocks/bin:$PATH"; eval "$(luarocks path --local)"
tl check depot_retrofits_1/content/mod.script.tl
tl check depot_retrofits_1/content/construction.script.tl
tl check depot_retrofits_1/content/probe.script.tl

# Check that _content.json lists every file under content/ (the game cannot load a file the list leaves out)
python3 tools/check_content_list.py
```

Run `tl check` on each script you touch.

## Architecture (probe stage)

`depot_retrofits_1/` is the mod. For now it carries only probes; the level system gets built once the probes settle how levels are stored. Probe 0.2 (pool, radius, noise, pollution and upkeep scaling, control rebuild, test charges, vehicle tracing) is in git history at `fe37966`; its results are in docs/findings.md. The current probe is 0.3:

- **[mod.json](depot_retrofits_1/mod.json)** sets `runScript` to `mod.script@runFn`.
- **[mod.script.tl](depot_retrofits_1/content/mod.script.tl)**: `runFn` registers a `loadConstruction` modifier. For every non-industry construction that uses the base depot HUD icons or sits under a `depots/` folder, and is not an edge object (the base path signals use the same HUD icons), it replaces `updateScript` with the wrapper, keeps the original capture params at the top level, and stores the original script's absolute reference under `depotRetrofits`. It declares two of three level param variants: `depotRetrofitsFutureLevel` (values 0 to 15, `yearFrom` 3000) and `depotRetrofitsSingleLevel` (one value). The third, `depotRetrofitsUndeclaredLevel`, is not declared. It logs `wrap` and `skip` lines with the `fileName` the game passes.
- **[construction.script.tl](depot_retrofits_1/content/construction.script.tl)**: the wrapper `update` loads the original with base `::/scripts/util.tl` `useFn`, runs it, and logs which of the three variants it received, with the pool. It changes nothing. A missing original raises, since there is no result to return.
- **[probe.gs.lua](depot_retrofits_1/content/probe.gs.lua) and [probe.script.tl](depot_retrofits_1/content/probe.script.tl)**: the game script. A game day after the first load, it rebuilds the three busiest player buildings, each with one variant set to 6, and reads the stored params back before and at checks after 1 game hour, 1 day, 7 days and 1 month. It books two test charges ($12,345 depot construction, $23,456 infrastructure maintenance) and logs the finance table's rows before and after (`computeFinanceTable`, as in the Best Before probe). Depots placed during the run are logged with their stored params. The state carries a version; a state from an older probe is reset.

The param keys and the capture key are copied into each of the three scripts (no shared module, so no extra load); keep the copies equal.

## In-game test loop

- The mod folder is symlinked into the game's `staging_area/` folder, so edits show up without copying, but the game must be restarted to reload scripts and `mod.json`.
- The game log is `crash_dump/stdout.txt` beside that folder. It is overwritten at each launch and written live. Copy it to `local/logs/` (gitignored) before reading it. Log timestamps are UTC.
- Every line the mod writes starts with `DEPOT_RETROFITS` and carries `key=value` fields. Log the state before and after every action (entity ids, pool, radius, vehicles).
- After a change that adds a load or an API call, check the first log lines after the save loads for `Error while loading game script` before the user plays at speed: a broken load in the sibling mod raised an error every update and froze the game.
- Test on a copy of a manual save. Probes act directly when loaded, with a small cap on what they do.

## Conventions

- Wrap constructions; do not replace base game scripts. A replacement is last-wins and clashes with other mods.
- Put unverified API calls and optional loads under `pcall`, with a log line as the fallback. Reach base game files with the `::/` form; a leading `/` resolves inside the mod.
- Game scripts: module variables do not persist, so state lives in `state:get()`/`state:set()`. `sendCommand` cannot be called from `handleEvent` and cannot take a callback; send from `update`.
- The Industry Upgrades mod has no licence: its method may be reused, its code may not be copied.
- Cite base game facts by the source file inside the game's archives (for example `game_mechanics/emission/emissions.script.tl`), never by pasting code. Public docs carry no home paths or Steam ids.
- Keep the README short and put detail in `docs/`. Every doc opens with an "In short" section (key drivers, how it works, how sure, what is unknown), then detail, with test results and logs at the bottom. Docs state the current status only; history belongs in git.
- The mod ships no game files. `all_def.tl` and `tlconfig.example.lua` are for type checking only and point at the game's own type definitions.
