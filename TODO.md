# TODO

## In short

- **Where it stands.** 1.3 is on mod.io (mod id 6495416) and tagged `v1.3`. `main` reads `1.4-dev`. Test results are in [docs/design/findings.md](docs/design/findings.md) and [docs/compatibility.md](docs/compatibility.md); the finished items are in git history.
- **Next.** 1.4: the "<", ">" and ">|" buttons, on branch `2026-11-08-step-buttons`. Buying and removing work in game (102 buys and 19 removals over four sessions, each charged or refunded once; refused rebuilds charged nothing; [docs/design/findings.md](docs/design/findings.md)); four checks are left. The checks below are optional; "Later" and the ideas are not planned.

## Release 1.3

- [x] Release ([docs/publishing.md](docs/publishing.md)): published copy tested, `v1.3` on `fa989e1`.
- [ ] Reply to the mod.io comment about TRM: Industry Emissions.
- [ ] Next session with TRM: Industry Emissions after us: the `buy sent` lines read `wrapped=true` (our capture key found under TRM's wrapper), not `wrapped=unknown`.

## Release 1.4: the "<", ">" and ">|" buttons

- [ ] In-game test of the buttons, at `logLevel` `"full"`. Done: sessions of 2026-11-08, 2026-11-12 to 13, 2026-11-14 and 2026-11-15 (logs `local/logs/2026-11-09-0721-step-buttons-stdout.txt`, `2026-11-14-0139-`, `2026-11-14-1356-` and `2026-11-15-1055-step-buttons-stdout.txt`), results in [docs/design/findings.md](docs/design/findings.md). Left:
  - [x] The three buttons line up from card to card; "<" greyed at level 0.
  - [x] The buttons with the longest effect text on a rail depot: "-40% -> -45% of total" beside "Rank 9" fits, buttons lined up (2026-11-14, shots 07:05:28 and 07:40:39 EST).
  - [x] ">|" buys up to the rank in one rebuild, charged once at the sum of the single prices, the price the tab showed (`levelsBought=`; ranks 4, 5, 7, 8 and 13; road, tram and rail depots, road and water maintenance buildings), also from part way up (pollution 3 → 8, upkeep 3 → 13).
  - [ ] ">|" short of money stops where the money ends (needs a save with little money). With one level left it sends the same buy as ">" (the log cannot tell the two buttons apart).
  - [x] "<" removes the top level and refunds once 80% of that level's price today, the amount the tab showed (`buy refunded ... direction=down`; 19 removals, on tram and water maintenance buildings, two clicks in one second both landed, none lost or refused); the last removal's after-check (`removed=`) matches the formulas.
  - [ ] How the Finances tab shows a refund (no screenshot yet).
  - [ ] "<" on a level above the rank (needs a building levelled above the current rank).
  - [x] A refused rebuild for a buy with the new buttons, ">|" included: "Not rebuilt" and the blocker in red, nothing charged (9 refused, 7 replaced by a retry, 2 expired after 30 s); after clearing, ">|" to 13 landed and was charged once ("333": Berkeley Maintenance Building, Berkeley Road Depot).
  - [ ] A refused rebuild for a removal: "Not rebuilt" with the removal wording ("The level was kept and nothing was refunded"), and nothing refunded.
- [ ] Retake the gallery's `2-retrofit-tabs.jpg` (and `3-not-rebuilt.jpg`, which shows a card) with the new buttons (4 to 6 are retaken as `4-ship-depot-2.jpg`, `5-boathouse-2.jpg` and `6-rail-maintenance-2.jpg`, from the 2026-11-21 shots at 06:00:19, 05:59:33 and 06:01:40), under new file names, since mod.io keeps a picture under a name it already has. Sources (with an index) in `local/gallery/2026-11-15-step-buttons/`: for 2-retrofit-tabs.jpg a rail depot and a road maintenance building at rank 8, a road depot and a water maintenance building at rank 13; for 3-not-rebuilt.jpg Berkeley Maintenance Building with the house in red (2026-11-15 04:57:11).

## Screenshots still to take

For later gallery and info-card updates. Take them with the current prices (1.3-dev or later; the earlier ones are evicted from `local/gallery/2026-11-05-cards/`, which has only the "Not bought" note and one window crop). Take them with the TRM mods off, since TRM: Infrastructure Upkeep changes the upkeep figures. Take the full 4K shot, so the cards and the building both show; the window sits at about x 2870-3790. Shots with the "<", ">" and ">|" buttons are copied, with an index, to `local/gallery/2026-11-15-step-buttons/` (13 files, ranks 1, 8 and 13, no TRM); earlier shots show the 1.3 buy button.

- [x] "Not rebuilt" with the house in red, as in the gallery's 3-not-rebuilt.jpg but with the new buttons (Berkeley Maintenance Building in "333", 2026-11-15 04:57:11); Berkeley Road Depot with the tall building in red at 04:57:47.
- [ ] "Not bought: the buy could not be carried out" (the industry cross icon). Rare; needs a temporary refusal in the game script, as the noise test did for the money note.
- [ ] A mix of company ranks, each with a full tab and the Summary card showing the rank (the rank decides how many boxes are grey, how many dark, and which cards read "Rank N" in place of the price):
  - [ ] Low rank (1 to 4): few buyable boxes, most of the row dark, most cards greyed with "Rank N". Partly: rank 1 at level 0 (Socorro Maintenance Building, 2026-11-08 16:31), one box buyable and every card still priced; "Rank N" needs level 1 bought.
  - [x] Mid rank (5 to 9): some levels bought, some buyable, some dark (rank 8: Artesia Maintenance Building 07:40:10, Quemado Oil Refinery Train Depot 07:40:39, 2026-11-14).
  - [x] High rank (10 to 14): nearly all buyable; "Rank N" only at the last levels (rank 13, "Rank 14": Berkeley Road Depot, Berkeley Maintenance Building and Upton-upon-Severn Maintenance Building, 2026-11-15).
  - [x] Max rank (15): no dark boxes; one retrofit at level 15 reading "Highest level" with all 15 boxes white, the others partly bought (Cranbrook Boathouse, Peterlee Refinery West Ship Depot and its rail maintenance building, 2026-11-21 05:58 to 06:01).
  - [x] Mixed levels at one rank: the five retrofits at different levels (for example radius 12, vehicles 3, pollution 0, noise 7, upkeep 15), some at the rank's limit and some below it. Cranbrook Boathouse at rank 15, 2026-11-21 05:58:50 and 05:59:33: radius 2, vehicles 5, pollution 8, noise 1, upkeep 15. Also: the rail depot at 07:40:39 (upkeep at the limit, pollution 4, the rest 0) and the water maintenance building at 2026-11-15 05:05:58 (radius 3, vehicles 2, pollution 10, upkeep 13 at the limit, noise 0).
- [ ] The buy buttons greyed out for money, with the price still shown (balance below the next level).
- [ ] A ">|" tooltip ("Buy levels 4 to 9 for $X.") and a "<" tooltip (the refund and the upkeep after it).
- [ ] The money note at its start, with the yellow "Not bought: not enough money" note over the cards.
- [ ] One full Retrofit tab per building type at a mid level on the 1.3 prices (a different rank for each, from the mix above): road depot, tram depot, rail depot, ship depot, boathouse, road maintenance, rail maintenance. Pollution and noise cards matter most, since their prices changed. Have: rail depot and road maintenance (rank 8), road depot (rank 13), ship depot, boathouse and rail maintenance (rank 15, 2026-11-21; the boathouse also at level 0, 05:58:29); also a water maintenance building (rank 13), not on the list. Left: tram depot.
- [ ] A modular depot (Roundhouse) with stalls and levels, to show the vehicles card counting the modules.
- [x] The tab beside a level-0 building (no white boxes, every price at its level 1) as the "before" card (rail depot 07:05:22, maintenance building 07:39:51, 2026-11-14).

## Optional checks

- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

From the code review of 2026-11-03 (the charging and silent-refusal findings are fixed):

- [ ] Module upkeep: `relevelModule` in construction.script.tl rounds each module's added upkeep on its own instead of through `levels.levelledUpkeep`, so `MAINTENANCE_COST` is not `round(base x factor)` and `levels.baseUpkeep` cannot invert it. The tab's upkeep preview then falls back to the factor ratio (off by $1), and the game script's `upkeep` match too. Affects only depots whose module scripts add upkeep.
- [ ] `replacePending` (retrofits.script.tl) drops the building's pending buy uncharged even when the new buy is for another tree. If the earlier rebuild then lands and the game refuses the new one, the building keeps a level it never paid for; a replaced removal that lands later loses its level without the refund. Replace only a pending buy for the same tree and level (as noted in Station Retrofits' TODO too).
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
