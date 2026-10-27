# Depot Retrofits

A Transport Fever 3 script mod, in development: depots and maintenance buildings get levels that widen their maintenance radius, raise the number of vehicles they maintain, and cut their pollution.

## In short

- **Status.** Not playable yet. The repo holds the spec, the verified game facts, and a probe mod that tests the one thing the design depends on.
- **How it will work.** The mod wraps each depot construction's update script and reads hidden level parameters from the construction. Buying a level rebuilds the construction with the new level, and the wrapper scales the pool, the radius and the emissions. The game has no command that changes these values on a standing building, so a rebuild is the only route.
- **How sure.** The game facts are read from the game's own scripts. Another published mod uses the same rebuild method for industries.
- **Unknown.** Whether a rebuilt depot keeps its vehicles and their maintenance. The probe answers that before anything else is built.

## Notes

- [docs/spec.md](docs/spec.md): the level trees, prices, upkeep and rank gate, and the open points.
- [docs/findings.md](docs/findings.md): what is verified about depots in the base game and what a mod can change, with source files.

## Licence

MIT, see [LICENSE](LICENSE).
