# OnAir

## 1.0.1

- Mythic+ keys: fixed an error from the group finder (in a key, the game hides some numbers from
  addons).
- EllesmereUI nameplates: an interrupted cast reads "Interrupted", never the real name of the player
  who kicked it.
- Shield: "Hide the minimap" hides its icons too (quests, mail, flight points), also with
  EllesmereUI's minimap. In combat the game doesn't let addons hide it, so it hides when combat ends.
  /onair check shows where it stands.
- Shield page: the text no longer overlaps.
- Camera: zoom speed is now yours. Switching presets keeps it, and it works with the camera off. A
  zoom speed that came with a preset goes back to the game's once. Changing any other camera setting
  while the camera is off turns it on.
- YouTube chapters: a moment less than 10 seconds after the chapter before is left out (YouTube's
  rule), and the window now says which. That note is no longer part of the text you copy.

## 1.0.0

The first release.

- Streamer & recording mode for Retail and WoW Forever: player names in your interface become aliases,
  and ending the broadcast puts every real name back at once (no reload).
- Whose names: you (your stage name, on every character), your party and raid, everyone else,
  Battle.net friends (real names and BattleTags), guilds and communities, pets and minions. Cast names
  from four themes, your own templates ({me}, {n}, {role}, {class}, {owner}), or a fixed alias for a
  player. The same player keeps the same alias every session.
- Where: chat (senders, names inside messages, whispers), nameplates, unit and raid frames, tooltips,
  damage meters (Blizzard's and EllesmereUI's, also in combat), the character, friends, guild, group
  finder and mail windows, and other addons' frames and text.
- NPC names: real, a generic label (Enemy / NPC / Boss, in your own words) or hidden.
- Names above heads: while live, friendly players get name-only plates that show their alias. An
  optional blank name font takes every name off every head (it needs a logout to switch).
- Going live: the console (/onair), the minimap button, the Deck and key bindings. A preview first if
  you like; old chat lines can be wiped when you go live.
- Stream chat: a clean chat window over yours while live, only the lines you pick, names swapped.
- Moments: a clock from 00:00, markers by themselves (bosses, keys, deaths, levels, achievements, epic
  loot, PvP), a Mark key, and exports as YouTube chapters or a marker list.
- Shield: while live, whispers from strangers wait until you end (with an auto-reply if you like), and
  their invites, duels and trades are declined. Can hide your zone, zone banners and minimap.
- Camera: presets, zoom, field of view, shoulder offset, tilt, smoother follow and a slow orbit; always
  or only while live, with your own camera settings back after.
- The Deck: a small control bar that stays with the UI hidden (Alt+Z), with quick settings on hover.
  It can tuck away to a small handle.
- Four looks: Viewfinder, Vision mixer, Film slate and Studio. The console, the Deck, the stream chat
  and the go-live moment all follow.
- Edit layout: place the stream chat and the Deck on a grid, with snapping.
- /onair check: looks for real names still on screen.
- No libraries. The game settings OnAir changes while live come back as you had them.
