# Publishing on mod.io

## In short

- **Where it is.** Not on mod.io yet. The first upload will create the mod page.
- **How it gets there.** Only through the game's own uploader: Mod Hub, My Mods, the mod's dialog. The mod.io website refuses uploads for Transport Fever 3, and the page text changes only through the uploader. The uploader reads the name, summary, description and tags from [modinfo.json](../depot_retrofits_1/_metadata/modinfo.json) and the images from `depot_retrofits_1/_metadata/`.
- **The mod id file.** The first upload writes `depot_retrofits_1/_metadata/mod.io_fileid.txt` (the mod id). Commit it and never delete it: with it the dialog updates the existing mod, without it the next upload creates a second one.
- **What ships.** The whole `depot_retrofits_1/` folder except `_metadata/`: `mod.json`, `_content.json` and `content/`. The game loads only the files `_content.json` lists, so `python3 tools/check_content_list.py` must pass before an upload.
- **Images.** The layout of the Industry Upgrades listing: `0.jpg` is the cover, and `1.jpg` to `4.jpg` are the gallery, in file-name order. There is no `workshop_preview.jpg`. The cover shows on the mod's card only: opening the mod shows `1.jpg` first.
- **Version numbers.** mod.io labels every uploaded file "1.0", whatever the mod's number. The number that counts is `modVersion` in [mod.script.tl](../depot_retrofits_1/content/mod.script.tl), which the log prints at every load as `DEPOT_RETROFITS version <number>`, and the matching entry in [CHANGELOG.md](../CHANGELOG.md).
- **How sure.** The steps are the ones that worked for the sibling mod Best Before (four uploads, 17 to 30 Oct 2026; its [publishing.md](https://github.com/WuphonsReach/tf3-best-before-mod/blob/9fa081fc1c23ee79fcc4bac1b74a109db188c97d/docs/publishing.md)). None has been run for this mod.
- **Unknown.** Whether mod.io's page shows the gallery the way the game's dialog does (seen only in the dialog, from the staging copy), and whether the dialog writes a `workshop_preview.jpg` by itself when there is none.

## Releasing a version

1. **In the repo, on a release branch.**
   - The description in `modinfo.json` follows [user-guide.md](user-guide.md): change both together.
   - Run `python3 tools/check_content_list.py`, `python3 tools/check_repo.py --strict` (`settings.tl` ships `logLevel = "summary"`) and `tl check` on every script.
   - Set `modVersion` in `mod.script.tl` to the release number (between releases it reads the next number with `-dev`, for example `0.6-dev`).
   - In [CHANGELOG.md](../CHANGELOG.md), give the "not released" entry its number and date, and check its "Release note:" line, the one-liner for the uploader's Changelog field.
   - Redraw the cover with the new number if it shows one (`python3 tools/make_preview.py --version <number>`).
   - Merge the PR before uploading, so the upload is the code on `main`.
2. **Upload.** Start the game, open **Mod Hub**, then **My Mods**, and click the mod's card. In the dialog:
   - **Validation** should read "No Issues Found" (**Re-Validate** runs it again).
   - **Preview**: the cover. On the first upload click the slot (camera icon) and pick `0.jpg`; without a cover the card shows a "?".
   - **Gallery**: `1.jpg`, `2.jpg`, `3.jpg`, `4.jpg` in that order. See [Gallery](#gallery) before moving any.
   - Tick both **PC** and **Console** for the two files (Windows, Mac and Linux; Xbox Series X/S and PlayStation 5).
   - **Set Public** ticked. Unticked, the page is hidden from visitors.
   - **Update Metadata** ticked, so the page takes the name, summary, description and tags from `modinfo.json`.
   - **Changelog**: the version's "Release note" line. Left empty, the page shows "No release notes provided".
   - The button reads **Upload** ("A new mod will be created on mod.io") only the first time. After that it must read **Update** ("The existing mod on mod.io will be updated"); if it reads Upload, `mod.io_fileid.txt` is missing: stop and restore it.
3. **Press Upload or Update.** The dialog shows "Uploading... Please Wait" and a counter, then "Upload Successful". After the first upload, commit `mod.io_fileid.txt`.
4. **Check the page** (**Open Mod Page** in the dialog): text, images, files and their dates. The page is about a minute behind an upload, so reload it before judging the file list.
5. **Test the published copy.** Remove the `staging_area/depot_retrofits_1` link: with both present the game loads the staging copy and logs `Multiple (2) mods with same id found`, so such a run says nothing about the published file. Subscribe, load a save with the mod active, and check the log for `DEPOT_RETROFITS version <number>` and no `Error while loading game script`, and the downloaded `_content.json` (under `mod.io/common/10640/mods/<mod id>/`) for all files. A release counts as good only after this. Then unsubscribe and restore the link.
6. **Tag and release on GitHub.** Tag the merged commit `v<number>` and publish a GitHub release from it. Tags matching `v*.*` and releases cannot be changed once pushed, so check both first; a mistake means a new version. Best Before's release notes have these parts: a bold one-line pitch, What changed, Good to know (including that mod.io calls every upload "1.0"), links to the CHANGELOG and docs pinned to the tag, Checked (with the published-copy test), and Not done yet.
7. **Start the next version.** Set `modVersion` to the next number with `-dev` and open a "not released" entry at the top of the CHANGELOG.

## Gallery

- **The cover is not in the gallery.** `0.jpg` fills the dialog's Preview slot and the mod's card. The gallery under the large image holds `1.jpg` to `4.jpg`, and the large image opens on `1.jpg`, so a player who clicks the card sees the window cards next, not the cover again. Seen in the mod's dialog in the save's Mods tab and in My Mods, where the Preview slot holds the cover and the gallery `1.jpg` to `4.jpg` (staging copy, 31 Oct 2026). Best Before opens on its cover only because its `1.jpg` is a copy of the cover.
- **The order is the file names.** In Best Before's dialog the gallery showed its images sorted by name, and the page followed the dialog.
- **Moving a thumbnail swaps the files.** Each thumbnail in the dialog has a small < (Move Left), > (Move Right) and bin over its top right corner. Moving one swaps the two files' contents on disk and writes nothing else. Commit the files as the dialog leaves them, or the next upload goes back to the old order.
- **mod.io keeps old names.** A file uploaded under a name mod.io already holds is stored under a new name (`workshop_preview.1.jpg`) and the old one stays on its image server. Numbered files that never change name avoid that; to change an image, replace the file under the same number.
- **Thumbnails are cropped to 16:9**, so every image is 1920x1080. `1.jpg` is drawn by `tools/make_gallery.py` (its docstring has the command); `2.jpg` to `4.jpg` are game screenshots cropped to 16:9, so the shot must leave room above and below the window (a shot narrower than 16:9 loses the window's title or footer).

## Hub search and tiles

- **Search matches the name only.** In the Mod Hub, words that appear only in another mod's summary or description find nothing, so the name carries the search words: "depot", "retrofits".
- **Tiles show the whole 16:9 cover, uncropped.** mod.io's tile adds the author, the summary cut after about 130 characters, the first tag and the size.
- **Downloads ship without `_metadata`.** The hub builds its page from mod.io's own copy of the text.
