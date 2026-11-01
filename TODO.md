# TODO

## In short

- **Where it stands.** 1.0 is on mod.io (mod id 6495416, uploaded 31 Oct 2026). The review fixes all passed in game (rank read, carrier from the depot, every buy charged once, buttons greyed out when money is short). Test results are in [docs/design/findings.md](docs/design/findings.md).
- **Next.** 1.1 (on a branch): a rebuild is checked before it is sent, and the tab shows "Blocked" when the game would refuse it. The first in-game test found the check failing on every call (`makeProposalData` takes a `SimpleProposal`), so every rebuild went out unchecked as in 1.0; fixed and tested (both blocked buildings in "333" show "Blocked", a clear building buys as before). The yellow warning tested well. A tab that turns clear keeps checking for 30 seconds, every 2 real seconds; tested. Berkeley Road Depot in "333" can only take levels with its road cut off, then built again. The gallery shows the warning (`2.jpg`, `6.jpg`). A radius level adds at least 10 m: the Buffer Stop Depot's radius went 1 m, 11 m, 21 m and on; tested. 1.1 is released (tagged `v1.1`). Its published copy showed a false "Blocked" on a road depot whose only collision was its own entrance road; 1.1.1 (on a branch) counts that as clear, tested in game. Left: the 1.1.1 release. The checks below are optional; the ideas at the bottom are not planned.

## Release 1.0

- [x] Upload 1.0 ([docs/publishing.md](docs/publishing.md)): page public, gallery `1.jpg` to `5.jpg` in order, `mod.io_fileid.txt` committed.
- [x] Test the published copy with the staging link removed: `version 1.0 logLevel=summary`, files identical to `v1.0`, no load errors.
- [x] Tag `v1.0` (on `478003d`, the uploaded code) and publish the GitHub release.
- [x] 1.1: before a rebuild, ask the game whether it would collide (`api.engine.util.proposal.makeProposalData`); refuse at once with `reason=blocked` and log the game's messages, and in the tab grey the buy buttons as "Blocked" under a yellow warning at the top of the tab (greyed buttons show no tooltip). The window checks on opening, after each click and every 2 seconds while blocked and for 30 seconds after, so removing the obstacle clears it; the game script checks again on every buy (docs/design/findings.md).
- [x] 1.1 gallery: `2.jpg` has a fourth card, Berkeley Road Depot's blocked tab (`tools/gallery/road_depot_blocked.png`), and the new `6.jpg` is the tram building's blocked tab beside the house and garden the bulldozer highlights. At the upload, check that the dialog's gallery shows `6.jpg` after `5.jpg`.
- [x] Check that the page lists the console file too: both files show since the 1.1 upload.
- [ ] 1.1.1: a collision only with the building's own entrance road counts as clear. Release it ([docs/publishing.md](docs/publishing.md)).
- [ ] After 1.1.1: probe the base game's `ProposalViewer` (`gui/entity_window/bridge_and_tunnel.tl`) in the window with the real replace proposal, logging only, on Peterlee Road Depot (clear expected), the "333" tram building with its neighbour standing (Collision expected) and Berkeley Road Depot with the block cleared but its road connected. If it agrees with the game, it replaces the stand-in check, the own-road rule and most of the timers; if not, the game script's check becomes advisory (send anyway; an unlanded rebuild is never charged). No more exceptions in the meantime.
- [ ] Optional: in "333", bulldoze only the buildings around Berkeley Road Depot (88894) and leave the road; if the tab turns clear, its road 80088 was the same false alarm.

## Optional checks

- [ ] Roundhouse: add a stall to one with a vehicles level and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's.
- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.

## Ideas (not planned)

Other ways to handle a building the game will not rebuild, kept in case the "Blocked" check falls short (the facts are in [docs/design/findings.md](docs/design/findings.md)).

- **Force the rebuild.** Send it with `ignoreErrors` on, as the base game does for its own in-place replacements (landmark level-ups). What that does on a collision is unknown: first a one-off probe on a copy of the "333" save, forcing one rebuild of Berkeley Road Depot (88894), and a look at its surroundings. If it proves harmless for some kinds of collision (for example town buildings only), force those and show "Blocked" for the rest; the check logs the colliding entities.
- **Skip the rebuild.** Set pollution and noise with `makeEntitySetEmissionsCmd`, and upkeep with the debug `makeMaintenanceCostUpdateCmd`, without a rebuild. Not taken: pool and radius have no such command, and the next rebuild (a module edit, catenary) would undo the values, since the levels are stored in the building's params and those change only by a rebuild.
- **Point at what is in the way.** The check logs the colliding entities (for Berkeley Road Depot, 80088 and 110793). The warning could name them or a click could move the camera there, so the player knows what to clear.
