# TODO

## In short

- **Where it stands.** 1.0 is on mod.io (mod id 6495416, uploaded 31 Oct 2026). The review fixes all passed in game (rank read, carrier from the depot, every buy charged once, buttons greyed out when money is short). Test results are in [docs/design/findings.md](docs/design/findings.md).
- **To finish the release.** Test the published copy, then tag `v1.0`. The checks below it are optional.

## Before a release

- [x] Upload 1.0 ([docs/publishing.md](docs/publishing.md)): page public, gallery `1.jpg` to `5.jpg` in order, `mod.io_fileid.txt` committed.
- [ ] Test the published copy with the staging link removed (`version 1.0`, no load errors, the downloaded `_content.json`).
- [ ] Tag `v1.0` and publish the GitHub release (both immutable).
- [ ] Check that the page lists the console file too.

## Optional checks

- [ ] Roundhouse: add a stall to one with a vehicles level and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's.
- [ ] Roundhouse: check whether the pollution and noise retrofits cut the chimney's emissions; the wrapper only scales the depot subconstruction's.
- [ ] Confirm that the upkeep retrofit leaves the accumulated costs in the upkeep footer alone: on two like buildings servicing similar vehicles, one with upkeep levels, they should grow at the same rate.
- [ ] The Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.

## Later

- [ ] Text sizes in the tab: everything is body size for now.
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
