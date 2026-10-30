# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Transport Fever 3 script mod in development: depots and maintenance buildings get levels for maintenance radius, vehicles maintained, pollution, noise and upkeep, bought in the building's window. The player-facing guide is [docs/user-guide.md](docs/user-guide.md). The design docs are in `docs/design/`: the spec is [docs/design/spec.md](docs/design/spec.md); the verified game facts and the open unknowns are in [docs/design/findings.md](docs/design/findings.md). Read findings before changing mechanics.

The repo is public on GitHub ([WuphonsReach/tf3-depot-retrofits](https://github.com/WuphonsReach/tf3-depot-retrofits), MIT); the mod is not on mod.io yet. `main` takes changes only through a pull request (see "CI and repo rules"): branch from `origin/main` as `<YYYY-MM-DD>-<slug>`, and push or open a PR only when the user asks. The name avoids "Upgrades" (too close to another mod's "Industry Upgrades"); inside the mod the terms are "level" and "retrofit".

There is no build step and no unit tests. The code is Teal (`.tl`) that the game loads directly, and the only checks are the type checker, the CI checks below and testing in the game. The user runs every in-game test.

## Commands

```bash
# Type check (needs gitignored tlconfig.lua copied from tlconfig.example.lua, with <tf3_install_folder> filled in)
export PATH="$HOME/.luarocks/bin:$PATH"; eval "$(luarocks path --local)"
tl check depot_retrofits_1/content/levels.tl
tl check depot_retrofits_1/content/mod.script.tl
tl check depot_retrofits_1/content/construction.script.tl
tl check depot_retrofits_1/content/retrofits.script.tl
tl check depot_retrofits_1/content/retrofit_window.script.tl

# Check that _content.json lists every file under content/ (the game cannot load a file the list leaves out)
python3 tools/check_content_list.py

# Redraw the mod's cover (depot_retrofits_1/_metadata/0.jpg, the uploader's Preview slot, 1920x1080; needs rsvg-convert and the Lato font)
python3 tools/make_preview.py [--version 0.5] [--keep-svg local/preview/cover.svg]   # the version goes in the upper right corner, kept clear for it

# Redraw the gallery's 1.jpg: hand-cropped screenshots of the building window, laid as a pile of cards on the cover's background
python3 tools/make_gallery.py depot_retrofits_1/_metadata/1.jpg CARD.png[:angle[:dy[:slot]]] ...   # the docstring has the command for the current image
# 2.jpg and 3.jpg are game screenshots cropped to 16:9 and scaled to 1920x1080 (the listing's thumbnails are cropped to 16:9). The layout is Industry Upgrades': 0 is the cover, 1 to N the gallery in file-name order, no workshop_preview.jpg (docs/publishing.md)
```

Run `tl check` on each script you touch.

## CI and repo rules

`.github/workflows/checks.yml` runs on every PR and every push to `main`: a `python-checks` job (`check_content_list.py`, `py_compile` of `tools/`) and a `teal-syntax` job (`tl gen` on each `.tl` file under `content/`, which fails on syntax errors only). CI cannot run `tl check` because the game's type definitions are not in the repo, so the type check stays a local step. Actions are pinned to full commit SHAs with the version in a trailing comment (`uses: actions/checkout@<sha> # v7.0.1`), at the latest release when added or bumped; look the SHA up with `gh api repos/<owner>/<action>/git/ref/tags/<tag>` and never use a floating tag like `@v4`.

The rulesets match Best Before's and have no bypass actors, so they bind the owner too:

- `main` and `pr-checks`: changes reach `main` only through a PR, and `pr-checks` requires the status checks `python-checks` and `teal-syntax`. The job names in `checks.yml` are the check names the ruleset matches: renaming a job means updating the ruleset (Settings > Rules) in the same change, or every PR will wait for a check that never reports.
- `trunks`: `main` cannot be deleted or force-pushed.
- `version-tags`: tags matching `v*.*` cannot be moved or deleted once pushed. Releases are immutable too, so check a tag and its release before publishing; a mistake means a new version, not a fix in place.

Releases follow [docs/publishing.md](docs/publishing.md): upload only through the game's Mod Hub dialog, test the published copy with the staging link removed, then tag. Keep `modVersion` in `mod.script.tl` and the top entry of [CHANGELOG.md](CHANGELOG.md) in step (between releases `modVersion` reads the next number with `-dev`). After the first upload `_metadata/mod.io_fileid.txt` holds the mod id: commit it and never delete it, or the next upload creates a second mod. Images use Industry Upgrades' layout: `0.jpg` the cover, `1.jpg` onward the gallery in file-name order, no `workshop_preview.jpg`; moving a thumbnail in the dialog swaps the files on disk, so commit them as the dialog leaves them.

## Architecture (0.5)

`depot_retrofits_1/` is the mod. Levels are stored, applied and bought in the building's window; the game script only handles buys. The probes are in git history (0.2, value scaling, at `fe37966`; 0.3, param variants, at `3adf8c6`; 0.4, random levels across a save, at `449de35`); their results are in docs/design/findings.md.

- **[levels.tl](depot_retrofits_1/content/levels.tl)**: the five trees, their param keys and the formulas of docs/design/spec.md (pool, radius, emissions, upkeep, build price, level price). Pure functions; every script loads it with `ug_require` under `pcall`. Its type is [types/depot_retrofits.d.tl](types/depot_retrofits.d.tl), which the mod does not ship.
- **[mod.json](depot_retrofits_1/mod.json)** sets `runScript` to `mod.script@runFn`.
- **[_metadata/modinfo.json](depot_retrofits_1/_metadata/modinfo.json)**: the name, summary, description, tags and url that the in-game mod list shows and the game's uploader sends to mod.io. The description follows [docs/user-guide.md](docs/user-guide.md): change both together.
- **[mod.script.tl](depot_retrofits_1/content/mod.script.tl)**: `runFn` registers a `loadConstruction` modifier. For every non-industry construction that uses the base depot HUD icons, declares a depot `constructionType` (`STREET_DEPOT`, `RAIL_DEPOT`, `WATER_DEPOT`) or sits under a `depots/` folder, and is not an edge object (the base path signals use the same HUD icons), it replaces `updateScript` with the wrapper, keeps the original capture params at the top level, and stores the original script's absolute reference under `depotRetrofits`. It declares one param per tree (values 0 to 15, `yearFrom` 9999, so never in the build menu) and sets the window script. A `loadModule` modifier (under `pcall`) wraps the update script of every module under a `depots/` folder the same way.
- **[construction.script.tl](depot_retrofits_1/content/construction.script.tl)**: the wrapper `update` loads the original with base `::/scripts/util.tl` `useFn`, runs it, and applies the levels to pool, radius, both emission states and upkeep; the upkeep factor also covers the modules' upkeep (their `metadata.maintenanceCost` in `params.modules`, which the game adds afterwards). `updateModule` wraps a module's update script, which the game runs after the construction's, and re-levels what the module added to the pool, radius or upkeep. A missing original raises, since there is no result to return.
- **[retrofits.gs.lua](depot_retrofits_1/content/retrofits.gs.lua) and [retrofits.script.tl](depot_retrofits_1/content/retrofits.script.tl)**: the game script. It handles the Retrofit tab's buy event: `handleEvent` queues it, `update` checks it (wrapped, level not stale, below 15, within the claimed rank, enough money), rebuilds with the new level, books the price as depot construction, and logs the building before and after 1 game hour and 1 day with the formulas' expected values. It logs the company rank on load. The state carries a version; a state from an older version is reset.
- **[retrofit_window.script.tl](depot_retrofits_1/content/retrofit_window.script.tl)**: the building window. mod.script.tl names it as each wrapped construction's `entityWindowScript` (only where the construction has none). It returns the base construction window with the depot's own tab plus a Retrofit tab, as the base Cleaning Plant adds its tab: a Summary card (rank, radius, vehicles), one card per tree (the tree's stock icon and a row of 15 drawn level boxes, upkeep after the next level, what the level changes, and a buy button with the stock shopping cart and the price), and the game's own upkeep footer (`MaintenanceBar`) below the scrolling cards.

The wrapper reference, capture key and buy event name are copied into the scripts that use them (keep the copies equal); the param keys live in levels.tl only.

## In-game test loop

- The mod folder is symlinked into the game's `staging_area/` folder, so edits show up without copying, but the game must be restarted to reload scripts and `mod.json`.
- The game log is `crash_dump/stdout.txt` beside that folder. It is overwritten at each launch and written live. Copy it to `local/logs/` (gitignored) before reading it. Log timestamps are UTC.
- Every line the mod writes starts with `DEPOT_RETROFITS` and carries `key=value` fields. Log the state before and after every action (entity ids, pool, radius, vehicles).
- After a change that adds a load or an API call, check the first log lines after the save loads for `Error while loading game script` before the user plays at speed: a broken load in the sibling mod raised an error every update and froze the game.
- Test on a copy of a manual save. A probe (a test build of the game script) acts directly when loaded, with a small cap on what it does.

## Conventions

- Wrap constructions; do not replace base game scripts. A replacement is last-wins and clashes with other mods.
- Put unverified API calls and optional loads under `pcall`, with a log line as the fallback. Reach base game files with the `::/` form; a leading `/` resolves inside the mod.
- Game scripts: module variables do not persist, so state lives in `state:get()`/`state:set()`. `sendCommand` cannot be called from `handleEvent` and cannot take a callback; send from `update`.
- The Industry Upgrades mod has no licence: its method may be reused, its code may not be copied.
- Cite base game facts by the source file inside the game's archives (for example `game_mechanics/emission/emissions.script.tl`), never by pasting code. Public docs carry no home paths or Steam ids.
- Keep the README short and put detail in `docs/`. Every doc opens with an "In short" section (key drivers, how it works, how sure, what is unknown), then detail, with test results and logs at the bottom. Docs state the current status only; history belongs in git. Player-facing docs (the user guide, the mod.io listing) use the simplest wording that is still exact.
- The mod ships no game files. `all_def.tl` and `tlconfig.example.lua` are for type checking only and point at the game's own type definitions.
