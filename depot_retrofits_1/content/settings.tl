-- Test switches, not in-game settings. Read when the game loads the mod's scripts, so restart the game after changing them.
--
-- logLevel: how much the mod writes to the game log (every line starts with DEPOT_RETROFITS). Any other value counts as "summary".
--   "summary"  shipped: the start-up lines, every error and fallback, constructions skipped for a reason, and one line per buy
--              with its outcome (sent, then charged, not landed or refused)
--   "full"     for testing: plus every construction and module wrapped, the wrapper's and the modules' before/after values,
--              the window's lines, and each buy's snapshots before and after 1 game hour, 1 day, 7 days and 30 days (pool,
--              radius, upkeep, emissions, the formulas' expected values, and pollution and noise in dB at the building)
-- tools/check_repo.py warns while logLevel is not "summary", and fails in CI.
return {
	logLevel = "summary",
}
