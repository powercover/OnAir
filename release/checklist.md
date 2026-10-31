# Releasing OnAir

Everything in this folder is for the project pages. None of it goes in the addon zip.

- `description.md`: the long description, in Markdown, with an `IMAGE_...` placeholder for each
  gallery image. `description-curseforge.md` and `description-wago.md` are the same text with each
  site's image addresses, ready to paste (`python tests/kit/make_descriptions.py` writes them; the
  addresses are in that script).
- `logo.gif`: the project logo, animated: 400 x 400, a 6-second loop of the lamp switching off and
  back on, with a gleam across the glass. CurseForge plays a GIF logo (Better Great Vault's does).
  The first frame is the lit lamp, so a site that shows one frame still shows the logo. `logo.png`
  is the same logo, still, 512 x 512 (`python tests/kit/make_media.py --page-logo` draws both).
- `gallery/`: the images for both sites' galleries, 1920 x 1080 (`python tests/kit/make_gallery.py`
  draws them again, from OnAir's own windows), and `00-how-it-works.gif`, an 8-second loop of
  OnAir's own widgets going live and back: the Deck's handle, the ON AIR slate, the stream chat with
  a marked moment, the "Real names are back" banner (`python tests/kit/make_animation.py`).
- `shots/`: your screenshots from the game, for gallery cards of their own (see below).

## 1. Build the zip

Only for a check on your own computer or an upload by hand: the release workflow builds its own
zip. Commit first, so the zip matches a commit. Then:

```
python tests/kit/package.py
```

It writes `dist/OnAir-<version>.zip` with one folder inside, `OnAir`. It checks the TOC, the icon and
the changelog first, and says if a file isn't committed yet.

## 2. CurseForge (authors.curseforge.com)

1. Create a project: World of Warcraft, Addons.
2. Name: **OnAir**. If the address "onair" is taken, pick another one (the name can stay OnAir).
3. Summary: see below. Description: paste `description-curseforge.md` as it is, in the editor's
   Markdown mode.
4. Logo: `logo.gif`. Category: Audio & Video (add Chat & Communication if you like).
5. Images: upload everything in `gallery/`, in the order of `IMAGES` in
   `tests/kit/make_descriptions.py` (`01-go-live` first: it's the cover). The descriptions show
   them by their addresses: after uploading a new image, put its address in that script and run it.
6. License: All Rights Reserved (the same as `LICENSE.txt` and the TOC).
7. No file to upload: pushing the version tag does it (see "Automatic uploads" below). Note the
   project ID on the project page.
8. CurseForge checks a new project by hand before it goes public. That can take a few days.

## 3. Wago (addons.wago.io)

1. In the developer dashboard, create an addon: the same name and summary, and
   `description-wago.md` as the description. Logo: `logo.gif` (if Wago won't take a GIF,
   `logo.png`).
2. Add the same gallery images, in the same order.
3. No file to upload here either: the tag does it. Note the addon's ID (8 letters and digits,
   under its name on the dashboard).

## Summary (both sites)

> Streamer mode for WoW: every player name becomes an alias, everywhere. Plus one-key timestamps,
> screenshots, YouTube chapters and a shield against stream snipers.

## Screenshots from the game

The gallery shows OnAir's own windows. Cards with the game itself sell it best. Take these while live
(so every name is an alias), in a busy place: a city, a dungeon group, a raid.

| File name in `shots/` | What to show |
| --- | --- |
| `chat` | Chat with aliases: party chat and a whisper. |
| `nameplates` | Friendly players' nameplates showing aliases. |
| `meters` | A damage meter in combat, with aliases. |
| `frames` | Party or raid frames with aliases. |
| `stream-chat` | The stream chat window over your chat. |

Save them as png or jpg under those names, then run `python tests/kit/make_gallery.py`. Each one
becomes a `shot-...` card in `gallery/`, with the same headline style. Upload those too.

## Each new version

1. Add a part for it at the top of `CHANGELOG.md` (`## 1.1.0`) and set `## Version` in `OnAir.toc`.
2. When the game updates, add its version to `## Interface` in `OnAir.toc` (12.1.5 is 120105,
   Forever 1.60.1 is 16001).
3. Commit, then push a version tag (below).

## Automatic uploads

`.github/workflows/release.yml` (BigWigs' packager, the same as Better Great Vault's) builds the
zip and uploads it to both sites and to the GitHub release when a version tag is pushed. The game
versions come from the TOC's `## Interface` line (16001 makes it a WoW Forever file too), the notes
from `CHANGELOG.md`. It needs:

1. The repository: `powercover/OnAir` on GitHub (public).
2. The project IDs in `OnAir.toc`: `## X-Curse-Project-ID: <number>` and `## X-Wago-ID: <id>`.
   They aren't secret.
3. An API token from each site, saved in the repository's secrets as `CF_API_KEY` and
   `WAGO_API_TOKEN` (Settings > Secrets and variables > Actions, or `gh secret set CF_API_KEY -R
   powercover/OnAir`, which asks for the value). Set these yourself. Never paste a token in a chat.
4. Then each release is: `git tag 1.1.0`, then `git push origin 1.1.0`. The tag must be the TOC's
   version.
