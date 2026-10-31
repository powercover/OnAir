# OnAir

## 0.1.0

- First build: streamer & recording mode for Retail and WoW Forever.
- Aliases for you, your crew, everyone else, Battle.net friends, guilds and pets: cast names from four
  themes, or your own templates ({me}, {n}, {role}, {class}, {owner}), and fixed aliases.
- Hides names in chat, nameplates and overhead names, tooltips, damage meters (Blizzard and EllesmereUI)
  and all interface text.
- The console (/onair), a minimap button, a go-live banner and key bindings.
  Left-click goes live or ends, right-click opens the console.
- Stream chat: a clean chat window over yours while live, showing only what you pick (NPC talk, boss
  emotes and loot by default), names already aliased.
- Camera: presets (Cinematic, Over the shoulder, Wide), zoom distance, field of view, shoulder offset,
  tilt, head movement, smoother follow and zoom, and a slow orbit. Off, always, or only while live;
  your own camera settings come back afterwards.
- Right-click menus on aliased names still reach the real player; replies (R) too.
- Chat bubbles, community names and hidden group finder text are covered.
- Moments: a clock from 00:00 when you go live (with a clapper flash), automatic markers for bosses,
  keys, deaths, levels, achievements, epic loot and PvP, a Mark moment key, screenshots, and exports
  as YouTube chapters or a marker list. The last 10 sessions are kept.
- Shield: holds whispers from strangers (shown after the broadcast) with an optional auto-reply,
  declines invites, duels and trades from strangers, and can hide your zone, zone banners and minimap.
- NPC names: real, generic (Enemy / NPC / Boss, your own words) or hidden, on nameplates, target frames,
  tooltips and chat; names above heads switch off with them.
- The Deck: a small control bar that stays with the UI hidden (Alt+Z): go live, hide the UI, camera
  presets, orbit, mark, edit layout, console. Sticks to edges and corners; stays, fades or tucks away.
- Edit layout: a grid over the screen to place the stream chat and the Deck. Pieces stick to lines
  while you drag: any side or the middle onto the center lines, the screen edges, the other pieces and
  (optionally) the game's own frames, lit as you go; sides onto the grid. Snapping Free, Guides or
  Grid, grid 16 / 32 / 64 px, Shift drags freely. Its own Layout page; opening and closing animate.
  Deck buttons are locked while editing.
- Skins (console > Look), each its own console, controls and Deck, switching right away (no reload):
  - Viewfinder (default): a camera screen. REC readout and shot info on top, corner brackets and
    thirds lines, the pages as a camera menu with colored tabs, every setting a menu row (ON / OFF,
    < choice >, tick scales), a help line at the bottom, a Deck of words (REC UI CAM ORBIT ...).
  - Vision mixer: PROGRAM / PREVIEW keys and a timecode display, the pages as a bus of keys, lit
    tiles with a tally strip, vertical faders, small displays for text, a Deck of labeled keys.
  - Film slate: clapper stripes, PRODUCTION / SCENE / TAKE cells, a numbered shot list, settings in
    ruled chalk cells (the picked choice boxed), a film strip with the status as edge codes.
  - Studio: the plain console with tiles and switches.
  The banner, the go-live slate, the stream chat's title bar and edit layout follow the skin. On a
  viewfinder the thirds lines are snap guides too.
- No reloads: ending the broadcast puts every real name back right away (the reload prompt is gone),
  and changing a name or a Hide setting while live re-masks what's on screen.
- Going live masks what's already on screen too (open windows, raid frames, other addons' frames,
  damage meter rows), not only text that changes afterwards.
- /onair check: looks for leaks in the game itself. Real names still on screen (closed windows too)
  while live or in a preview, and players the game shows that OnAir hasn't learned (or that the game
  hides). Names in the report are partly masked.
- Also covered: Battle.net friends' characters when the Battle.net app is their main account, group
  finder members (Premade Groups Filter, Raider.IO), unnamed addon tooltips, your BattleTag in the
  friends window, and other addons' raid frames and meters in instance combat.
- An audit of the installed addons' code (EllesmereUI, DBM, Raider.IO, Premade Groups Filter, M+ logs,
  MPlusCoach, AlterEgo, PrioWarband, Syndicator, Narcissus, WhisperMessenger, Leatrix and more) and
  the fixes from it:
  - Names only other addons keep are learned when going live: your alts, past key groups, whisper
    contacts from past sessions, names in EllesmereUI's saved chat.
  - A "Name-Realm" or "Name (Realm)" with a known realm is a player even if OnAir never met them
    (Raider.IO searches, DBM "sent by", auction sellers).
  - Names cut short with "..." read as their alias.
  - Hidden while secret in instance combat: cast bar targets, Mythic+ target bars, DBM's big warnings.
  - Nameplate cast targets on plates made later from a pool; whisper senders even when a whisper
    addon takes the line; the target of whoever you mouse over; recent allies.
- OnAir Mono: OnAir's own pixel font for timecodes and camera text (Latin letters with accents).
- Deck quick panels: rest the mouse on a button for a second for its settings on the fly: clock,
  preview and stream chat; camera mode, preset, zoom, field of view, shoulder; orbit direction, speed
  and auto-stop; recent moments and Mark now; snapping, lock and how the Deck hides.
- Lock positions: the stream chat and the Deck can't be dragged (edit layout still moves them). The
  Deck has no grip strip any more: drag it from anywhere.
- The Deck shows you're on air (glowing live button, red stripe); the separate ON AIR badge is gone.
- Going live shows a short ON AIR slate with a thin red frame instead of a white flash.
- Orbit either way round. On the Deck: left click orbits left, right click right, the same click again
  or a middle click stops. Optionally stops when you move or turn the camera with the mouse.
- Preview: everything masked like live, without the clock, moments or Shield.
- New console: pages grouped as Live / Privacy / Production, page headers, a status strip, smoother
  motion (pages glide in, cards appear in turn, a stretching rail marker, springy switches).
- Sliders: drag or use the arrow keys; the mouse wheel scrolls the page instead.
