# TODO

## In short

- **Where it stands.** 0.5 is on `main`: levels are stored, applied and bought in the Retrofit tab, and the game script only handles buys. It has not been released.
- **Before a release.** An in-game test of the rest of the review fixes (the carrier on a tram depot, the greyed button when money is short), the Roundhouse checks (the module wrapper's recorded base pool, the chimney's emissions), then the release itself.

## Before a release

- [x] Open the Retrofit tab on the Roundhouse mod's depot (works; see docs/design/findings.md).
- [x] Test the modular depot changes on the Roundhouse (TF3 calls `loadModule`; stalls are re-levelled, upkeep covers them; see docs/design/findings.md).
- [x] A Roundhouse with 10 or more stalls at a high vehicles level, where +10% of the whole pool beats +1 a level (28 stalls: pool 29 → 61 at vehicles 11).
- [ ] Optional: the Modern Railway Depot mod's depot (modular, its modules are wrapped); in a save before 2015, turn on its "Available from 1900" setting.
- [x] Find out whether the game's own rebuilds keep the level params: electrifying a rail depot, the catenary tool on a tram depot and module edits on the Roundhouse do; base depots have no param that can be changed after building.
- [x] Decide the rank gate: fixed (max level = claimed rank), no setting.
- [ ] Test the rest of the review fixes in game (the rank read, the new module's load and the carrier from the depot passed: WATER on ship depots, water maintenance and the Boathouse 241705, RAIL on rail ones, 41 more buys all charged; docs/design/findings.md). Still to see: TRAM with `carrierSource=depot` on a tram depot's `buy sent` line; a buy button greys out, price still shown, with "Not enough money" when the balance is below the price (a fresh company, or a loan paid back).
- [ ] Roundhouse: add a stall to a levelled one and check the `module` line's `baseSource` (`recorded` means the game hands the modules the wrapper's own table; `inverted` is the fallback) and that the pool is the formula's. Also check that the chimney's pollution or noise is cut by those trees: the wrapper only scales the depot subconstruction's emissions.
- [x] Test the uncharged-buy fix: 74 quick clicks on three buildings, 38 buys all charged once at the shown price, no `notLanded` (the old version gave 2 free levels in 144); since then 142 and 33 more buys on the "333" save, all charged once.
- [x] Check which finance rows the level charges land in: Investments > Infrastructure, to the dollar; no row there or under the carriers shows the carrier (docs/design/findings.md).
- [ ] Confirm that the upkeep tree leaves the vehicles' running cost (the accumulated costs in the upkeep footer) alone, as designed: on two like buildings servicing similar vehicles, one with upkeep levels, the accumulated costs should grow at the same rate.
- [x] Retake the gallery `_metadata/1.jpg` to `3.jpg`, and add `4.jpg`: the old images showed the old price ladder (the upkeep tree priced like the others), and 2.jpg an old buy tooltip. Use buildings at level 0, with only upkeep levels, or bought once since the 15% upkeep step; buildings levelled before it show prices 25% to 43% too high until rebuilt (docs/design/findings.md). Full 4K screenshots will do: crop the window for `tools/make_gallery.py` (same angles and slots as its docstring), and crop 2.jpg and 3.jpg to 16:9 at 1920x1080.
- [x] Retake the gallery images that show a pollution or noise price or upkeep: pollution levels now start at 0.08 × the build price and add 5% of the base upkeep each, noise levels 0.12 × and 10%. Use buildings with no pollution or noise levels bought before the change; buildings that have them show wrong figures until rebuilt (docs/design/findings.md). All four images retaken; every price shown matches the formula.
- [ ] Release, following [docs/publishing.md](docs/publishing.md): the listing text in `_metadata/modinfo.json`, the CHANGELOG entry and `modVersion`, README status, the upload, a test of the published copy, then a `v*.*` tag and GitHub release (both immutable). After the first upload, commit `mod.io_fileid.txt` and note whether the page's gallery shows `1.jpg` to `5.jpg` in order.

## Design

- [x] Decide the upkeep tree's first-level share: 0.25 (pays back in about 12 years with the other trees full).
- [ ] Text sizes in the tab: everything is body size for now.
- [x] The listing says that buying a level lets the game reassign the building's vehicles, some or all of them to another building in range.

## Small

- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
