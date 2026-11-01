# TODO

## In short

- **Where it stands.** 1.2 is on mod.io (mod id 6495416) and tagged `v1.2`; the gallery shows "Not rebuilt". `main` reads `1.3-dev`. Test results are in [docs/design/findings.md](docs/design/findings.md).
- **Next.** Nothing planned for 1.3 yet. The checks below are optional; the ideas at the bottom are not planned.

## Release 1.0

- [x] Upload 1.0 ([docs/publishing.md](docs/publishing.md)): page public, gallery `1.jpg` to `5.jpg` in order, `mod.io_fileid.txt` committed.
- [x] Test the published copy with the staging link removed: `version 1.0 logLevel=summary`, files identical to `v1.0`, no load errors.
- [x] Tag `v1.0` (on `478003d`, the uploaded code) and publish the GitHub release.
- [x] 1.1: before a rebuild, ask the game whether it would collide (`api.engine.util.proposal.makeProposalData`); refuse at once with `reason=blocked` and log the game's messages, and in the tab grey the buy buttons as "Blocked" under a yellow warning at the top of the tab (greyed buttons show no tooltip). The window checks on opening, after each click and every 2 seconds while blocked and for 30 seconds after, so removing the obstacle clears it; the game script checks again on every buy (docs/design/findings.md).
- [x] 1.1 gallery: `2.jpg` has a fourth card, Berkeley Road Depot's blocked tab (`tools/gallery/road_depot_blocked.png`), and the new `6.jpg` is the tram building's blocked tab beside the house and garden the bulldozer highlights. At the upload, check that the dialog's gallery shows `6.jpg` after `5.jpg`.
- [x] Check that the page lists the console file too: both files show since the 1.1 upload.
- [x] 1.1.1: a collision only with the building's own entrance road counts as clear. Released (`v1.1.1` on `c194f37`); the published copy took a level on Peterlee Road Depot.
- [x] After 1.1.1: probe the base game's `ProposalViewer` with the real replace proposal. It agreed with the game everywhere the stand-in check did not, but each viewer previews the rebuild in the world (regrown greenery, a blue or red flash), so 1.2 tries the buy and places the viewer only after a refusal (docs/design/findings.md).

## Release 1.2

- [x] Test that "Not rebuilt" stays through a retry on a building the game still refuses (Berkeley Maintenance Building in "333" with the house standing), and goes once the house is bulldozed.
- [x] Gallery: `2.jpg` (its fourth card, now `tools/gallery/maintenance_not_rebuilt.png`) and `6.jpg` showed the 1.1 "Blocked" tab. Both are retaken from Berkeley Maintenance Building with "Not rebuilt" and the house in red.
- [x] Release 1.2 ([docs/publishing.md](docs/publishing.md)): published copy tested, `v1.2` on `c02773a`.
- [x] mod.io gallery: the update did not replace images under names mod.io already had, so the gallery is now `<n>-<name>.jpg` and a second update sent all six.
- [x] Optional: in "333", bulldoze only the buildings around Berkeley Road Depot (88894) and leave the road. The tab stayed blocked until the road was cut off, so the own-road rule does not clear that road; whether the game would refuse the rebuild is for the probe.

## Optional checks

- [ ] Roundhouse: add a stall to one with a vehicles level and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's.
- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.

## Ideas (not planned)

Other ways to handle a building the game will not rebuild (the facts are in [docs/design/findings.md](docs/design/findings.md)).

- **Force the rebuild.** Send it with `ignoreErrors` on, as the base game does for its own in-place replacements (landmark level-ups). What that does on a collision is unknown: first a one-off probe on a copy of the "333" save, forcing one rebuild of Berkeley Road Depot (88894), and a look at its surroundings. If it proves harmless for some kinds of collision (for example town buildings only), force those and show "Not rebuilt" for the rest; the proposal viewer reports the colliding entities.
- **Skip the rebuild.** Set pollution and noise with `makeEntitySetEmissionsCmd`, and upkeep with the debug `makeMaintenanceCostUpdateCmd`, without a rebuild. Not taken: pool and radius have no such command, and the next rebuild (a module edit, catenary) would undo the values, since the levels are stored in the building's params and those change only by a rebuild.
- **Point at what is in the way.** After a refusal the proposal viewer draws it in red. A click could also move the camera there, for a building in the way that is off screen.
