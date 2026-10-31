# OnAir

### The broadcast studio inside World of Warcraft.

**Go live without giving anyone away.** OnAir turns every player name in your interface into an alias, gives you the tools a stream or a video needs, and puts everything back the moment you end. No reload.

> **What OnAir is, and isn't.** OnAir is a streamer mode: it hides real names on your screen and adds tools for streaming and recording. It doesn't record or stream video itself. Keep using OBS, Streamlabs, NVIDIA or AMD. OnAir gets the game ready for the camera.

For **Retail** and **WoW Forever**. One addon, no libraries.

---

## Why OnAir

- **Aliases, not blanks.** Your viewers can still follow the action. Every player gets an alias, and the same player keeps the same alias every session.
- **Everywhere at once.** Chat, nameplates, unit and raid frames, tooltips, damage meters, and the friends, guild, group finder and mail windows. Other addons' text too.
- **Works with your addons.** Tested with popular UI and quality-of-life addons (see below). OnAir swaps names in the text any addon shows, so it doesn't need a list of supported addons.
- **Even in combat.** Where the game hides names from addons (combat, dungeons), OnAir covers that text instead.
- **Back to normal in one click.** End the broadcast and every real name returns at once. The game settings OnAir changed come back as you had them.
- **It checks itself.** `/onair check` looks for any real name still on your screen.
- **Made for creators.** Timestamps, screenshots and YouTube chapters, a clean stream chat, a shield against stream snipers, and a cinematic camera.
- **Light.** No libraries. Big jobs are spread over many frames, and long lists are read only now and then.

---

## Every name, an alias

- **You**: your stage name, on every character you play.
- **Your party and raid**: cast names from a theme (Film set, Pirate crew, Royal court, Critters), or your own template with `{me}`, `{n}`, `{role}` and `{class}`.
- **Everyone else**: strangers, guildmates, friends, people in lists and chat.
- **Battle.net friends**: real names and BattleTags.
- **Guilds and communities**: yours reads "The Star's Studio", others "Studio 1", "Studio 2"...
- **Pets and minions**: "Owner's Pet", with the owner's alias.
- **NPCs**, if you like: a generic label (Enemy, NPC, Boss) or nothing.

Give a player a fixed alias on the Custom page, like your duo partner. Try **Preview** before you go live: everything is masked like live, so you can check your screen first.

## Moments: one key for every highlight

- Going live starts a clock at **00:00**, and a short ON AIR slate on screen marks the same 00:00 in your video, so the timecodes line up.
- **Boss pulls, kills and wipes, Mythic+ keys, deaths, levels, achievements, epic loot and PvP** mark themselves.
- Your **Mark** key adds your own moment. Turn on **Screenshot each moment** and every moment saves a screenshot too.
- **Tip:** bind the same key to *Save Replay* in OBS. One press gives you a clip and its timecode.
- Export a session as **YouTube chapters** or a **marker list** for your video editor. Names in moments are already aliases, so they're safe to show.

## Shield: keep stream snipers out

While you're live, whispers from strangers wait until you end (with an auto-reply if you like), and their invites, duels and trades are declined. Your zone, zone banners and minimap can stay hidden. Friends, your guild, your group and the players on your Custom page always get through.

## Stream chat

A clean chat window over yours while live. It shows only what you pick (NPC talk, boss emotes, loot by default), with names already swapped. Your real chat keeps running underneath.

## Camera

Cinematic presets, zoom, field of view, shoulder offset, tilt, smoother follow and a slow orbit (left or right, stopping when you move if you like). Use it always or only while live. Your own camera settings come back after.

## The Deck and four looks

The **Deck** is a small control bar that stays on screen when you hide the UI (Alt+Z): go live, hide the UI, camera, orbit, mark, edit layout. Rest the mouse on a button for quick settings. It tucks away to a small handle that still shows if you're on air.

Pick a look: a **camera viewfinder**, a **vision mixer**, a **film slate** or a clean **studio** console. The console, the Deck, the stream chat and the go-live moment all follow.

## Names above heads

The game draws names above heads itself, and addons can't change that text. While live, OnAir shows friendly players as name-only nameplates, which read their aliases.

For full cover, turn on **Blank name font** (Hide page): no name above any head, players or NPCs, live or not. The game reads this font only when you log in, so it needs a logout to switch on or off. Friendly NPC nameplates bring NPC names back.

## Works with your addons

OnAir doesn't patch addons one by one. It swaps names in the text itself, wherever it shows, so other addons' windows, frames and tooltips are covered too.

It was built and tested alongside popular UI and quality-of-life addons, and checked against their code:

- **EllesmereUI**: unit frames, nameplates, damage meters (also in combat), friends and chat.
- **Deadly Boss Mods**: warnings and "sent by" lines.
- **Raider.IO** and **Premade Groups Filter**: group finder lists and searches.
- **Leatrix Plus**, **Narcissus**, **Syndicator**, **WhisperMessenger**, **AlterEgo**: names they show or keep from earlier sessions.

Names that only other addons remember (your alts, past key groups, whisper contacts) are learned when you go live, so they're covered from the first second. Found a name that slips through? `/onair check` shows where it is.

## What the game doesn't allow

- In combat and in dungeons the game hides some names from addons. OnAir can't swap those, so it hides that text instead.
- Blizzard's friendly nameplates inside dungeons and raids can't be changed by any addon.
- The combat log tab isn't changed.

## Commands

| Command | What it does |
| --- | --- |
| `/onair` | Open the console |
| `/onair live`, `/onair off` | Go live, end the broadcast |
| `/onair preview` | Preview on or off |
| `/onair mark [note]` | Mark a moment |
| `/onair check` | Look for real names still on screen |
| `/onair reshuffle` | Everyone draws a new alias |

Key bindings: Options > Keybindings > OnAir. The minimap button: left-click goes live or ends, right-click opens the console.

## Your data

Everything OnAir learns stays in your own saved variables, on your computer.
