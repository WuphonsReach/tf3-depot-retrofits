# TODO

## In short

- **Where it stands.** 1.0 is on mod.io (mod id 6495416, uploaded 31 Oct 2026). The review fixes all passed in game (rank read, carrier from the depot, every buy charged once, buttons greyed out when money is short). Test results are in [docs/design/findings.md](docs/design/findings.md).
- **Next.** 1.1: check a rebuild before sending it, and show "Blocked" when the game would refuse it. The checks below are optional.

## Release 1.0

- [x] Upload 1.0 ([docs/publishing.md](docs/publishing.md)): page public, gallery `1.jpg` to `5.jpg` in order, `mod.io_fileid.txt` committed.
- [x] Test the published copy with the staging link removed: `version 1.0 logLevel=summary`, files identical to `v1.0`, no load errors.
- [x] Tag `v1.0` (on `478003d`, the uploaded code) and publish the GitHub release.
- [ ] 1.1: before a rebuild, ask the game whether it would collide (`api.engine.util.proposal.makeProposalData`); refuse at once with `reason=blocked` and log the game's messages, and in the tab grey the buy buttons as "Blocked" with a line in the Summary card (greyed buttons show no tooltip). The window checks on opening and every couple of seconds while open, so removing the obstacle clears it; the game script checks again on every buy (docs/design/findings.md).
- [ ] Check that the page lists the console file too.

## Optional checks

- [ ] Roundhouse: add a stall to one with a vehicles level and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's.
- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
