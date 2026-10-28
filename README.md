# Depot Retrofits

A Transport Fever 3 script mod, in development: depots and maintenance buildings get levels that widen their maintenance radius, raise the number of vehicles they maintain, cut their pollution and noise, and cut their upkeep.

## In short

- **Status.** Not released yet. The mod (0.5) stores, applies and sells levels in a Retrofit tab in each depot's window; the tab's layout is still being reworked. The repo also holds the spec and the verified game facts.
- **How it will work.** The mod wraps each depot construction's update script and reads hidden level parameters from the construction. Buying a level rebuilds the construction with the new level, and the wrapper scales the pool, the radius and the emissions. The game has no command that changes these values on a standing building, so a rebuild is the only route.
- **How sure.** The game facts are read from the game's own scripts. Another published mod uses the same rebuild method for industries.
- **Tested.** In game, a rebuild keeps the building and its vehicles' lines and applies all five values. Levels given to 18 buildings matched the formulas for a game month, and buying a level in the Retrofit tab charged the shown price and applied it. The catch: every rebuild unlinks the vehicles the building maintains, and the game reassigns them within a day, not always to the same building. See [docs/design/findings.md](docs/design/findings.md).

## Notes

- [docs/user-guide.md](docs/user-guide.md): how to buy levels, what they do and what they cost.
- [docs/design/spec.md](docs/design/spec.md): the level trees, prices, upkeep and rank gate, and the open points.
- [docs/design/findings.md](docs/design/findings.md): what is verified about depots in the base game and what a mod can change, with source files.
- [TODO.md](TODO.md): what is left before a release.

## Licence

MIT, see [LICENSE](LICENSE).
