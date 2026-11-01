# TODO

## In short

- **Where it stands.** 1.0 is on mod.io (mod id 6495416, uploaded 31 Oct 2026). The review fixes all passed in game (rank read, carrier from the depot, every buy charged once, buttons greyed out when money is short). Test results are in [docs/design/findings.md](docs/design/findings.md).
- **Next.** 1.1 (on a branch): a rebuild is checked before it is sent, and the tab shows "Blocked" when the game would refuse it. The first in-game test found the check failing on every call (`makeProposalData` takes a `SimpleProposal`), so every rebuild went out unchecked as in 1.0; fixed and tested (both blocked buildings in "333" show "Blocked", a clear building buys as before). The yellow warning tested well. A town can build on a cleared lot again within days at 1x, so a tab that turns clear now keeps checking for 30 seconds; to test, then release. The checks below are optional; the ideas at the bottom are not planned.

## Release 1.0

- [x] Upload 1.0 ([docs/publishing.md](docs/publishing.md)): page public, gallery `1.jpg` to `5.jpg` in order, `mod.io_fileid.txt` committed.
- [x] Test the published copy with the staging link removed: `version 1.0 logLevel=summary`, files identical to `v1.0`, no load errors.
- [x] Tag `v1.0` (on `478003d`, the uploaded code) and publish the GitHub release.
- [ ] 1.1: before a rebuild, ask the game whether it would collide (`api.engine.util.proposal.makeProposalData`); refuse at once with `reason=blocked` and log the game's messages, and in the tab grey the buy buttons as "Blocked" under a yellow warning at the top of the tab (greyed buttons show no tooltip). The window checks on opening, after each click and every 2 seconds while blocked and for 30 seconds after, so removing the obstacle clears it; the game script checks again on every buy (docs/design/findings.md).
- [ ] Check that the page lists the console file too.

## Optional checks

- [ ] Roundhouse: add a stall to one with a vehicles level and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's.
- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.

## Ideas (not planned)

Other ways to handle a building the game will not rebuild, kept for if the "Blocked" check falls short (the facts are in [docs/design/findings.md](docs/design/findings.md)).

- **Force the rebuild.** Send it with `ignoreErrors` on, as the base game does for its own in-place replacements (landmark level-ups). What that does on a collision is unknown: first a one-off probe on a copy of the "333" save, forcing one rebuild of Berkeley Road Depot (88894), and a look at its surroundings. If it proves harmless for some kinds of collision (for example town buildings only), force those and show "Blocked" for the rest; the check logs the colliding entities.
- **Skip the rebuild.** Set pollution and noise with `makeEntitySetEmissionsCmd`, and upkeep with the debug `makeMaintenanceCostUpdateCmd`, without a rebuild. Not taken: pool and radius have no such command, and the next rebuild (a module edit, catenary) would undo the values, since the levels are stored in the building's params and those change only by a rebuild.
- **Point at what is in the way.** The check logs the colliding entities (for Berkeley Road Depot, 80088 and 110793). The warning could name them or a click could move the camera there, so the player knows what to clear.
