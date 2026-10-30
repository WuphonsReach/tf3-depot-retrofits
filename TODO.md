# TODO

## In short

- **Where it stands.** 0.5 is on `main`: levels are stored, applied and bought in the Retrofit tab, and the game script only handles buys. It has not been released.
- **Before a release.** The tab on the Roundhouse mod's depot, a decision on the rank gate, and the mod.io listing.
- **Unknown.** Whether the game's own rebuilds keep the level params.

## Before a release

- [ ] Open the Retrofit tab on the Roundhouse mod's depot, the one building type not yet seen in game (buildable from 1920; it is wrapped by the `depots/` folder rule, since it uses its own icon and its `constructionType` line is commented out).
- [ ] Find out whether the game's own rebuilds keep the level params: electrifying a rail depot, the construction upgrade tool, a param change in the build window.
- [ ] Decide the rank gate: fixed (max level = claimed rank), or an in-game setting that is on by default.
- [ ] Check which finance rows the level charges land in (booked as depot construction).
- [ ] Confirm that the upkeep tree leaves the vehicles' running cost (the accumulated costs in the upkeep footer) alone, as designed: on two like buildings servicing similar vehicles, one with upkeep levels, the accumulated costs should grow at the same rate.
- [ ] Release, following [docs/publishing.md](docs/publishing.md): the listing text in `_metadata/modinfo.json` (drop its "IN DEVELOPMENT" paragraph if it no longer applies), the CHANGELOG entry and `modVersion`, README status, the upload, a test of the published copy, then a `v*.*` tag and GitHub release (both immutable). After the first upload, commit `mod.io_fileid.txt` and note whether the gallery took `2.jpg` and `3.jpg`.

## Design

- [ ] Whether each tree gets its own cost basis. The upkeep tree pays back in about 13 years at the current ladder; 0.79 × the ladder gives 10 years, 1.18 × gives 15.
- [ ] Text sizes in the tab: everything is body size for now.
- [ ] The listing could say that buying a level lets the game reassign the building's vehicles, sometimes to another building in range.

## Small

- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
