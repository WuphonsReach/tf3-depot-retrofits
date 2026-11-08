# TODO

## In short

- **Where it stands.** 1.2 is on mod.io (mod id 6495416) and tagged `v1.2`. `main` reads `1.3-dev`. Test results are in [docs/design/findings.md](docs/design/findings.md) and [docs/compatibility.md](docs/compatibility.md); the finished items are in git history.
- **Next.** Release 1.3 (cheaper pollution and noise levels, "Not bought" notes, no free levels, works with TRM: Industry Emissions in either order, prices in the game's money format): set `logLevel` back to `"summary"`, `modVersion` to `1.3`, date the changelog entry, then [docs/publishing.md](docs/publishing.md). The checks below are optional; "Later" and the ideas are not planned.

## Release 1.3

- [ ] Release ([docs/publishing.md](docs/publishing.md)), then reply to the mod.io comment about TRM: Industry Emissions.
- [ ] Pass the Station Retrofits handoff on (written 2026-11-07): its notes name our wrapper reference as one way to spot a building we wrap; now only the `depotRetrofits` capture key holds.
- [ ] Next session with TRM: Industry Emissions after us: the `buy sent` lines read `wrapped=true` (our capture key found under TRM's wrapper), not `wrapped=unknown`.
- [ ] Optional: reproduce the TRM bug on 1.2 (the published copy, TRM after Depot Retrofits, place a road depot, look for TRM's load error). The synthetic test shows it (`tools/test_wrapper_load.py`, "1.2 wrapper reference").

## Screenshots still to take

For later gallery and info-card updates. Take them with the current prices (1.3-dev or later; the earlier ones are evicted from `local/gallery/2026-11-05-cards/`, which has only the "Not bought" note and one window crop). Take them with the TRM mods off, since TRM: Infrastructure Upkeep changes the upkeep figures. Take the full 4K shot, so the cards and the building both show; the window sits at about x 2870-3790.

- [ ] "Not rebuilt" with the house in red, as in the gallery's 3-not-rebuilt.jpg but with the 1.3 prices (Berkeley Maintenance Building in "333", house standing).
- [ ] "Not bought: the buy could not be carried out" (the industry cross icon). Rare; needs a temporary refusal in the game script, as the noise test did for the money note.
- [ ] A mix of company ranks, each with a full tab and the Summary card showing the rank (the rank decides how many boxes are grey, how many dark, and which buttons read "Rank N"):
  - [ ] Low rank (1 to 4): few buyable boxes, most of the row dark, most buttons greyed as "Rank N".
  - [ ] Mid rank (5 to 9): some levels bought, some buyable, some dark.
  - [ ] High rank (10 to 14): nearly all buyable; the "Rank N" button only at the last levels.
  - [ ] Max rank (15): no dark boxes; one retrofit at level 15 reading "Highest level" with all 15 boxes white, the others partly bought.
  - [ ] Mixed levels at one rank: the five retrofits at different levels (for example radius 12, vehicles 3, pollution 0, noise 7, upkeep 15), some at the rank's limit and some below it.
- [ ] A buy button greyed out for money, with the price still shown (balance below the next level).
- [ ] The money note at its start, with the yellow "Not bought: not enough money" note over the cards.
- [ ] One full Retrofit tab per building type at a mid level on the 1.3 prices (a different rank for each, from the mix above): road depot, tram depot, rail depot, ship depot, boathouse, road maintenance, rail maintenance. Pollution and noise cards matter most, since their prices changed.
- [ ] A modular depot (Roundhouse) with stalls and levels, to show the vehicles card counting the modules.
- [ ] The tab beside a level-0 building (no white boxes, every price at its level 1) as the "before" card.

## Optional checks

- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

From the code review of 2026-11-03 (the charging and silent-refusal findings are fixed):

- [ ] Module upkeep: `relevelModule` in construction.script.tl rounds each module's added upkeep on its own instead of through `levels.levelledUpkeep`, so `MAINTENANCE_COST` is not `round(base x factor)` and `levels.baseUpkeep` cannot invert it. The tab's upkeep preview then falls back to the factor ratio (off by $1), and the game script's `upkeep` match too. Affects only depots whose module scripts add upkeep.
- [ ] Click numbers without `os.time`: the window then numbers clicks 1, 2, 3 from each session, so a refusal kept in the save from an earlier session can match a new click and show a stale "Not bought". `os.time` has been there in every test.
- [ ] Copied helpers: `firstDepot`, `constructionParams`, `clockNow`, `say`, the settings load and `wrapperRef`/`captureKey`/`buyEvent` are copied between scripts. The copies have started to differ (`constructionParams` copies the table in retrofits.script.tl and not in the window). Move them into a shared module (levels.tl is loaded everywhere).
- [ ] Window cost: `readTab` runs on every step of an open Retrofit tab and reads the rank, the charged upkeep, the maintained vehicle list (a fresh table each time), the balance and the footer scale. Read the slow-changing ones every N steps.

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.

## Ideas (not planned)

Other ways to handle a building the game will not rebuild (the facts are in [docs/design/findings.md](docs/design/findings.md)).

- **Force the rebuild.** Send it with `ignoreErrors` on, as the base game does for its own in-place replacements (landmark level-ups). What that does on a collision is unknown: first a one-off probe on a copy of the "333" save, forcing one rebuild of Berkeley Road Depot (88894), and a look at its surroundings. If it proves harmless for some kinds of collision (for example town buildings only), force those and show "Not rebuilt" for the rest; the proposal viewer reports the colliding entities.
- **Skip the rebuild.** Set pollution and noise with `makeEntitySetEmissionsCmd`, and upkeep with the debug `makeMaintenanceCostUpdateCmd`, without a rebuild. Not taken: pool and radius have no such command, and the next rebuild (a module edit, catenary) would undo the values, since the levels are stored in the building's params and those change only by a rebuild.
- **Point at what is in the way.** After a refusal the proposal viewer draws it in red. A click could also move the camera there, for a building in the way that is off screen.
