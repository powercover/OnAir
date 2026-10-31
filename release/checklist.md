# Releasing OnAir

Everything in this folder is for the project pages. None of it goes in the addon zip.

- `description.md`: the long description (paste it on both sites).
- `logo.png`: the project logo, 512 x 512 (`python tests/kit/make_media.py --page-logo` draws it again).

## 1. Build the zip

Commit first, so the zip matches a commit. Then:

```
python tests/kit/package.py
```

It writes `dist/OnAir-<version>.zip` with one folder inside, `OnAir`. It checks the TOC, the icon and
the changelog first, and says if a file isn't committed yet.

## 2. CurseForge (authors.curseforge.com)

1. Create a project: World of Warcraft, Addons.
2. Name: **OnAir**. If the address "onair" is taken, pick another one (the name can stay OnAir).
3. Summary: see below. Description: paste `description.md`.
4. Logo: `logo.png`. Category: Audio & Video (add Chat & Communication if you like).
5. License: All Rights Reserved (the same as `LICENSE.txt` and the TOC).
6. Upload a file: the zip from step 1.
   - Release type: Release.
   - Game versions: Retail **12.1.5** (and 12.1.7 if it's listed), WoW Forever **1.60.1**.
   - Changelog: the newest part of `CHANGELOG.md`.
7. CurseForge checks a new project by hand before it goes public. That can take a few days.

## 3. Wago (addons.wago.io)

1. In the developer dashboard, create an addon: the same name, summary, description and logo.
2. Upload the same zip. Supported patches: Retail **12.1.5** and **12.1.7**, Forever **1.60.1**.
   Stability: Stable.

## Summary (both sites)

> Streamer & recording mode: swaps player names for aliases in chat, nameplates, frames, tooltips,
> meters, friends, guild and group finder. Real names come back when you end. Retail and WoW Forever.

## Screenshots to take in the game

Take them while live, so no real names show.

1. The console (Broadcast page) while live.
2. Chat with aliases: party chat and a whisper.
3. A party or raid frame and a damage meter with aliases.
4. Friendly players' nameplates showing aliases.
5. The stream chat window over your chat.
6. The four looks (Look page), one shot each.
7. The Deck, and the Moments page with chapters.

## Each new version

1. Add a part for it at the top of `CHANGELOG.md` (`## 1.1.0`) and set `## Version` in `OnAir.toc`.
2. When the game updates, add its version to `## Interface` in `OnAir.toc` (12.1.5 is 120105,
   Forever 1.60.1 is 16001).
3. Commit, build the zip, upload it on both sites (or push a tag, below).

## Later: automatic uploads (optional)

`.github/workflows/release.yml` builds the zip and uploads it to both sites when you push a version
tag. It needs:

1. The OnAir folder on GitHub (a private repository is fine).
2. The project IDs in `OnAir.toc`: `## X-Curse-Project-ID: <number>` and `## X-Wago-ID: <id>`. Both
   sites show the ID on the project page. They aren't secret.
3. An API token from each site, saved in GitHub (Settings > Secrets and variables > Actions) as
   `CF_API_KEY` and `WAGO_API_TOKEN`. Make and save these yourself. Never paste a token in a chat.
4. Then each release is: `git tag 1.1.0`, then `git push origin 1.1.0`. The tag must be the TOC's
   version.
