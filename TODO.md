# TODO

## In short

- **Where it stands.** 0.5 is on `main`: levels are stored, applied and bought in the Retrofit tab, and the game script only handles buys. It has not been released.
- **Before a release.** One in-game check of the $100 price rounding, the tab on the building types not yet opened, a decision on the rank gate, and the mod.io listing.
- **Unknown.** Whether the game's own rebuilds keep the level params.

## Before a release

- [ ] Run the build price's $100 rounding in game. Buy an upkeep level on a road maintenance building; the next level in any tree should read $10,125, not $10,124. It is checked offline against logged figures only.
- [ ] Open the Retrofit tab on the building types not yet seen in game: tram depot, rail maintenance, water maintenance, and the Roundhouse mod's depot.
- [ ] Find out whether the game's own rebuilds keep the level params: electrifying a rail depot, the construction upgrade tool, a param change in the build window.
- [ ] Decide the rank gate: fixed (max level = claimed rank), or an in-game setting that is on by default.
- [ ] Check which finance rows the level charges land in (booked as depot construction).
- [ ] Release: mod.io listing (screenshots; the text is in `_metadata/modinfo.json`; drop its "IN DEVELOPMENT" paragraph), version text in `mod.script.tl`, README status, a `v*.*` tag (tags and releases are immutable).

## Design

- [ ] Whether each tree gets its own cost basis. The upkeep tree pays back in about 13 years at the current ladder; 0.79 × the ladder gives 10 years, 1.18 × gives 15.
- [ ] Text sizes in the tab: everything is body size for now.
- [ ] The buy button's tooltip runs past the window's left edge: shorten it or split it.
- [ ] Optional stock icons in front of the noise, pollution and vehicle values (`symbol_noise`, `symbol_pollution`, `symbol_tools`). The game has no radius icon.
- [ ] The listing could say that buying a level lets the game reassign the building's vehicles, sometimes to another building in range.

## Small

- [ ] "gameScript loaded" is logged once per Lua state, about 14 lines per load.
