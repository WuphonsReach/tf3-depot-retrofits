# TODO

## In short

- **Where it stands.** 0.5 is on `main`: levels are stored, applied and bought in the Retrofit tab, and the game script only handles buys. It has not been released.
- **Before a release.** A decision on the rank gate, and the mod.io listing.

## Before a release

- [x] Open the Retrofit tab on the Roundhouse mod's depot (works; its stalls' vehicles and upkeep were not levelled, see docs/design/findings.md).
- [x] Test the modular depot changes on the Roundhouse (TF3 calls `loadModule`; stalls are re-levelled, upkeep covers them; see docs/design/findings.md).
- [ ] Optional: a Roundhouse with 10 or more stalls at a high vehicles level, where +10% of the whole pool beats +1 a level.
- [x] Find out whether the game's own rebuilds keep the level params: electrifying a rail depot, the catenary tool on a tram depot and module edits on the Roundhouse do; base depots have no param that can be changed after building.
- [ ] Decide the rank gate: fixed (max level = claimed rank), or an in-game setting that is on by default.
- [ ] Check which finance rows the level charges land in (booked as depot construction).
- [ ] Confirm that the upkeep tree leaves the vehicles' running cost (the accumulated costs in the upkeep footer) alone, as designed: on two like buildings servicing similar vehicles, one with upkeep levels, the accumulated costs should grow at the same rate.
- [ ] Release, following [docs/publishing.md](docs/publishing.md): the listing text in `_metadata/modinfo.json` (drop its "IN DEVELOPMENT" paragraph if it no longer applies), the CHANGELOG entry and `modVersion`, README status, the upload, a test of the published copy, then a `v*.*` tag and GitHub release (both immutable). After the first upload, commit `mod.io_fileid.txt` and note whether the gallery took `2.jpg` and `3.jpg`.

## Design

- [ ] Whether each tree gets its own cost basis. The upkeep tree pays back in about 13 years at the current ladder; 0.79 × the ladder gives 10 years, 1.18 × gives 15.
- [ ] Text sizes in the tab: everything is body size for now.
- [ ] The listing could say that buying a level lets the game reassign the building's vehicles, sometimes to another building in range.

## Small

- [ ] Check in game that the tab's upkeep figures now match the footer after every buy (they were $4 off after 2 of 10 buys at a scale of 4; the fix works from the whole-dollar upkeep before the levels, and replays all 66 logged buys exactly).
- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
