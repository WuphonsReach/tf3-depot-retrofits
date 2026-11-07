---
name: review-test-session
description: Review what the user did in an in-game test session from the game log and the screenshots. Use when the user says they tested, bought, loaded a mod order, took screenshots, or points to "the latest image index" or log.
---

# Reviewing a test session

1. Read `local/machine.md` (the `machine` skill): game log location, screenshot folders, which branch the game loads.
2. Copy `crash_dump/stdout.txt` to `local/logs/YYYY-MM-DD-HHMM-<slug>-stdout.txt` and read the copy. The log is overwritten at each launch, so an earlier launch's log may already be gone: say so rather than guessing. Log times are UTC; screenshot names are local time (UTC-5 from 1 Nov 2026).
3. Count the evidence before concluding: `grep -c 'DEPOT_RETROFITS buy'` (ours) against `STATION_RETROFITS` (the sibling mod's lines use the same shape), `Error while loading`, the mod order in the "Active mods" list, the `version` line (logLevel).
4. Screenshots: use the index in `../tf3-save-format` (`.claude/skills/screenshot-index/SKILL.md`: `python3 -I tools/screenshot_index.py --work local/screenshots find TERM`, `local/screenshots/INDEX.md`, run `ocr` first when shots are new). Its labels are often guesses. Shots from the last two hours sit at the top of `~/Pictures/Screenshots`, older ones in `tf3/YYYY-MM-DD/`. Open a few as scratchpad copies (`magick X.png -resize 1600x`), never whole 4K frames in bulk.
5. Tell the user which feature each session exercised and what the log and pictures prove, and what they do not. Check the staging branch (step 1) before saying a feature "did not work".
