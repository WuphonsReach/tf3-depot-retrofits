# TODO

## In short

- **Where it stands.** 0.5 is on `main` and not released. The review fixes all passed in game (rank read, carrier from the depot, every buy charged once, buttons greyed out when money is short). Test results are in [docs/design/findings.md](docs/design/findings.md).
- **Before a release.** The Roundhouse checks, then the release itself.

## Before a release

- [ ] See the radius button show "No effect", greyed out, on a depot with a radius under 20 m (the Grimes Buffer Stop Depot mod's, 1 m), with the card showing the radius now and no upkeep after a level.
- [ ] Roundhouse: add a stall to a levelled one and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's. Also check whether the pollution and noise trees cut the chimney's emissions: the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep tree leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] Optional: the Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.
- [ ] Release, following [docs/publishing.md](docs/publishing.md): the listing text in `_metadata/modinfo.json`, the CHANGELOG entry and `modVersion`, README status, the upload, a test of the published copy, then a `v*.*` tag and GitHub release (both immutable). After the first upload, commit `mod.io_fileid.txt` and note whether the page's gallery shows `1.jpg` to `5.jpg` in order.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
