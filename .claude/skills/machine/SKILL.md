---
name: machine
description: Read local/machine.md for where things are on this machine (game install, user data, staging symlink, game log, screenshot folders, sibling repos and what each does). Use before searching the disk, and whenever a task names the game folder, a log, a save, a screenshot, a mod.io mod or a sibling repo.
---

# Where things are on this machine

`local/machine.md` (gitignored, so it can hold paths) answers: where Transport Fever 3 is installed, where its user data, `staging_area/`, saves and `crash_dump/stdout.txt` are, where screenshots live, how the mod is linked into the game, and what each sibling repo under the projects folder is for (`tf3-save-format` with its skills, `tf3-save-mapper`, `tf3-save-editor`, `tf3-map-making`, `tf3-station-retrofits`, `tf3-best-before-mod`).

1. Read it first. Do not run `find /` or guess paths: it is slow (the commands time out) and the answer is there.
2. The fuller copy is `../tf3-station-retrofits/local/machine.md` (saves used for tests, map overlays, dense-station saves). If `local/machine.md` is missing, copy its general part from there.
3. When you learn a path or fact that is not in it, add it, keeping the file short.
4. The game loads whatever branch this checkout has out (the staging symlink points at it). A change on another branch or worktree is not in the game: check `git branch --show-current` and the symlink before blaming a missing feature on the code.
5. Keep home paths, Steam ids and the like out of anything committed: `machine.md` is the one place for them.
