"""The whole addon on WoW's Lua (5.1) against a mocked frame API, driven like a player: load,
log in, open the console and every page, flip every switch, go live, fire the events and hooks
(text, chat, tooltips, nameplates, menus), end the broadcast. Any Lua error fails the run.
Runs as Retail and as WoW Forever.

python tests/kit/ui_smoke.py
"""
import os
import re
import sys

from lupa.lua51 import LuaRuntime

ROOT = os.environ.get("ONAIR_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))

MOCK = r"""
local TOC = ...
local function noop() end
local Widget = {}
local metas = {}

local function NewObject(kind, name, parent)
  local o = { _kind = kind, _shown = true, _points = {}, _regions = {}, _children = {}, _attr = {},
              _parent = parent, _name = name, _w = 100, _h = 20, _alpha = 1 }
  setmetatable(o, metas[kind] or metas.Frame)
  if name then _G[name] = o end
  if parent and parent._children then table.insert(parent._children, o) end
  return o
end

local base = {}
function base:GetObjectType() return self._kind end
function base:GetName() return self._name end
function base:GetParent() return self._parent end
function base:SetParent(p) self._parent = p end
function base:IsForbidden() return false end
function base:Show() self._shown = true; if self._scripts and self._scripts.OnShow then self._scripts.OnShow(self) end end
function base:Hide() self._shown = false end
function base:SetShown(v) if v then self:Show() else self:Hide() end end
function base:IsShown() return self._shown end
function base:IsVisible() return self._shown end
function base:SetText(t) self._text = t end
function base:SetFormattedText(f, ...) self._text = string.format(f, ...) end
function base:GetText() return self._text end
function base:SetPoint(p, a, b, c, d) table.insert(self._points, { p, type(a) == "table" and a or self._parent }) end
function base:ClearAllPoints() self._points = {} end
function base:GetPoint(i) local pt = self._points[i or 1]; if pt then return pt[1], pt[2], pt[1], 0, 0 end end
function base:GetNumPoints() return #self._points end
function base:GetWidth() return self._w end
function base:GetHeight() return self._h end
function base:SetSize(w, h) self._w, self._h = w, h end
function base:SetWidth(w) self._w = w end
function base:SetHeight(h) self._h = h end
function base:GetStringHeight() return 14 end
function base:GetStringWidth() return 40 end
function base:GetFrameLevel() return self._level or 1 end
function base:SetFrameLevel(l) self._level = l end
function base:GetLeft() return 10 end
function base:GetBottom() return 10 end
function base:GetAlpha() return self._alpha end
function base:SetAlpha(a) self._alpha = a end
function base:GetEffectiveScale() return 1 end
function base:GetCenter() return 500, 400 end
function base:SetScript(k, fn) self._scripts = self._scripts or {}; self._scripts[k] = fn end
function base:GetScript(k) return self._scripts and self._scripts[k] end
function base:HookScript(k, fn) local old = self:GetScript(k); self:SetScript(k, function(...) if old then old(...) end fn(...) end) end
function base:CreateTexture() local t = NewObject("Texture", nil, self); table.insert(self._regions, t); return t end
function base:CreateFontString() local t = NewObject("FontString", nil, self); table.insert(self._regions, t); return t end
function base:GetRegions() return unpack(self._regions) end
function base:GetChildren() return unpack(self._children) end
function base:CreateAnimationGroup() return NewObject("AnimationGroup", nil, self) end
function base:CreateAnimation() return NewObject("Animation", nil, self) end
function base:IsPlaying() return false end
function base:GetVerticalScrollRange() return 120 end
function base:GetVerticalScroll() return 0 end
function base:GetStatusBarColor() return 0.5, 0.5, 0.5 end
function base:SetAttribute(k, v) self._attr[k] = v end
function base:GetAttribute(k) return self._attr[k] end
function base:HasFocus() return false end
function base:NumLines() return self._lines or 0 end
function base:GetUnit() return "Bob", "mouseover" end
function base:AddMessage(text) self._lines = self._lines or {}; table.insert(self._lines, text) end
function base:Clear() self._lines = {} end
function base:Click(button) local fn = self:GetScript("OnClick"); if fn then fn(self, button or "LeftButton") end end

local VERBS = { "Set", "Get", "Is", "Enable", "Disable", "Register", "Unregister", "Clear", "Play", "Stop",
  "Start", "Raise", "Lower", "Add", "Insert", "Scroll", "Can", "Has", "Highlight" }
local permissive = { __index = function(t, k)
  local v = rawget(base, k); if v then return v end
  if type(k) == "string" then
    for _, verb in ipairs(VERBS) do if k:sub(1, #verb) == verb then return noop end end
  end
  return nil
end }
for _, kind in ipairs({ "Frame", "Button", "Texture", "FontString", "EditBox", "ScrollFrame", "StatusBar",
  "AnimationGroup", "Animation", "GameTooltip", "ScrollingMessageFrame" }) do
  local index = setmetatable({}, permissive)
  metas[kind] = { __index = index }
end

function CreateFrame(kind, name, parent) return NewObject(kind, name, parent) end
function CreateFont(name) return NewObject("Font", name) end
UIParent = NewObject("Frame", "UIParent")
Minimap = NewObject("Frame", "Minimap")
GameTooltip = NewObject("GameTooltip", "GameTooltip")
UIErrorsFrame = NewObject("Frame", "UIErrorsFrame")
ChatFrame1 = NewObject("ScrollingMessageFrame", "ChatFrame1")
PlayerFrame = NewObject("Frame", "PlayerFrame"); PlayerFrame.name = PlayerFrame:CreateFontString()
TargetFrame = NewObject("Frame", "TargetFrame")
TargetFrame.TargetFrameContent = { TargetFrameContentMain = { Name = TargetFrame:CreateFontString() } }
TargetFrameToT = NewObject("Frame", "TargetFrameToT"); TargetFrameToT.name = TargetFrameToT:CreateFontString()
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
SOUNDKIT = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
Enum = { TooltipDataType = { Unit = 2 }, ClubType = { Guild = 2 } }

local hookLog = {}
function hooksecurefunc(a, b, c)
  local tbl, name, fn = a, b, c
  if type(a) == "string" then tbl, name, fn = _G, a, b end
  local orig = tbl[name] or noop
  tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
  hookLog[#hookLog + 1] = name
end

function GetBuildInfo() return "x", "1", "d", TOC end
function GetLocale() return "enUS" end
function GetNormalizedRealmName() return "Kazzak" end
function GetTime() return 100 end
function GetCursorPosition() return 600, 400 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) table.insert(t, v) end
function issecretvalue(v) return type(v) == "table" and v.__secret == true end
GUARDED = {}
function geterrorhandler() return function(msg) GUARDED[#GUARDED + 1] = tostring(msg) end end
function InCombatLockdown() return false end
function IsInRaid() return false end
function IsInGuild() return true end
function GetGuildInfo(unit) if unit == "player" then return "Bob Squad" end return "Other Guild" end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i) return ({ "Carl-Kazzak", "Dana-Draenor" })[i] end
function GetInboxNumItems() return 1 end
function GetInboxHeaderInfo() return nil, nil, "Mailer-Kazzak" end
function GetNumBattlefieldScores() return 0 end
function BNGetNumFriends() return 1 end
function BNGetInfo() return 1, "Nimbus#2468" end
function PlaySound() end
function ReloadUI() end
function StaticPopup_Show() end
function GameTooltip_Hide() end
function EnumerateFrames(f) if not f then return ChatFrame1 end end
function Ambiguate(n) return (n:gsub("%-.*", "")) end
function GetMinimapShape() return "ROUND" end
WorldFrame = NewObject("Frame", "WorldFrame")
UI_SHOWN = true
function SetUIVisibility(v) UI_SHOWN = v; if v then UIParent:Show() else UIParent:Hide() end end
function UnitClassification(u) return units[u] and units[u].class or "normal" end
function UnitLevel(u) return units[u] and units[u].boss and -1 or 70 end
function UnitCanAttack(_, u) return units[u] and units[u].hostile or false end
function IsShiftKeyDown() return false end
time = os.time
date = os.date
function GetZoneText() return "Stormwind City" end
function GetSubZoneText() return "Trade District" end
function GetRealZoneText() return "Stormwind City" end
function GetMinimapZoneText() return "Trade District" end
DECLINED = 0
function DeclineGroup() DECLINED = DECLINED + 1 end
function CancelDuel() DECLINED = DECLINED + 1 end
function CancelTrade() DECLINED = DECLINED + 1 end
function StaticPopup_Hide() end
function IsGuildMember() return false end
function UnitGUID() return "guid" end
SHOTS = 0
function Screenshot() SHOTS = SHOTS + 1 end
SENT = {}
function SendChatMessage(text, kind, _, target) table.insert(SENT, target) end
function GetAchievementInfo(id) return id, "Big Achievement" end
function GetBattlefieldArenaFaction() return 0 end
LOOT_ITEM_SELF = "You receive loot: %s."
CHAT_MONSTER_SAY_GET = "%s says: "
DEFAULT_CHAT_FRAME = ChatFrame1
C_ChallengeMode = { GetMapUIInfo = function() return "The Dungeon" end, GetActiveKeystoneInfo = function() return 12 end,
  GetChallengeCompletionInfo = function() return { mapChallengeModeID = 1, level = 12, time = 1800000, onTime = true, keystoneUpgradeLevels = 2 } end }

units = {
  player = { name = "Me", realm = nil, player = true, me = true },
  party1 = { name = "Bob", realm = nil, player = true, party = true },
  target = { name = "Bob", realm = nil, player = true, party = true },
  mouseover = { name = "Stranger", realm = "Draenor", player = true },
  nameplate1 = { name = "Wolfie", controlled = true },
  targettarget = { name = "Boss", npc = true },
  nameplate2 = { name = "Angry Ogre", hostile = true },
  nameplate3 = { name = "Ragnaros", hostile = true, boss = true },
}
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] and units[u].player or false end
function UnitName(u) local d = units[u]; if d then return d.name, d.realm end end
function UnitIsUnit(a, b) return a == b or (a == "Me" and b == "player") end
function UnitInParty(u) return u == "Bob" or (units[u] and units[u].party) or false end
function UnitInRaid() return nil end
function UnitClass(u) return units[u] and units[u].player and "Warrior" or nil end
function UnitGroupRolesAssigned() return "TANK" end
function UnitPlayerControlled(u) return units[u] and (units[u].player or units[u].controlled) or false end
function UnitCreatureFamily() return "Wolf" end

C_Timer = { After = function(_, fn) fn() end, NewTimer = function(_, fn) return { Cancel = noop } end }
CVAR_DEFAULTS = { cameraDistanceMaxZoomFactor = "1.9", cameraFov = "90", test_cameraOverShoulder = "0",
  cameraYawSmoothSpeed = "180", cameraZoomSpeed = "20", cameraSmoothStyle = "0" }
C_CVar = { _v = {}, GetCVar = function(k) return C_CVar._v[k] or CVAR_DEFAULTS[k] or "1" end,
  SetCVar = function(k, v) C_CVar._v[k] = tostring(v) end, GetCVarDefault = function(k) return CVAR_DEFAULTS[k] or "1" end }
ORBIT = 0
function MoveViewLeftStart(speed) ORBIT = speed end
function MoveViewLeftStop() ORBIT = 0 end
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1", UnitFrame = { name = UIParent:CreateFontString() } } } end,
  GetNamePlateForUnit = function() return { UnitFrame = { name = UIParent:CreateFontString() } } end }
C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = "Pal-Kazzak" } end,
  IsFriend = function() return false end, GetFriendInfo = function(n) if n == "Pal-Kazzak" or n == "Pal" then return { name = "Pal" } end end,
  GetNumIgnores = function() return 0 end, GetNumWhoResults = function() return 0 end }
C_BattleNet = { GetFriendAccountInfo = function() return { bnetAccountID = 7, accountName = "|Kp7|k", battleTag = "Zed#1111",
  gameAccountInfo = { characterName = "Zedchar", realmName = "Kazzak" } } end,
  GetAccountInfoByID = function() return { bnetAccountID = 7, accountName = "|Kp7|k", battleTag = "Zed#1111" } end }
C_Club = { GetSubscribedClubs = function() return { { clubId = 1, name = "Cozy Club", clubType = 1 } } end,
  GetClubMembers = function() return { 1 } end, GetMemberInfo = function() return { name = "Clubber-Kazzak" } end }
C_GuildInfo = { GuildRoster = noop }
C_LFGList = { GetSearchResults = function() return 0, {} end, GetApplicants = function() return {} end }
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
C_ChatBubbles = { GetAllChatBubbles = function() return {} end }
local menus = {}
Menu = { ModifyMenu = function(tag, fn) menus[tag] = fn end }
MENUS_MOCK = menus
local filters = {}
ChatFrameUtil = { AddMessageEventFilter = function(e, fn) filters[e] = fn end, UpdateHeader = noop }
FILTERS = filters
TooltipDataProcessor = { AllTypes = "ALL", _calls = {}, AddTooltipPostCall = function(t, fn) TooltipDataProcessor._calls[t] = fn end }
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
"""

DRIVE = r"""
local OA = ...
local function fire(event, ...)
  for _, f in ipairs(FRAMES) do
    if f._events and f._events[event] and f._scripts and f._scripts.OnEvent then
      f._scripts.OnEvent(f, event, ...)
    end
  end
end
fire("ADDON_LOADED", "OnAir")
fire("PLAYER_LOGIN")
local UI = OA.UI
UI.ShowConsole()
for _, key in ipairs({ "broadcast", "names", "hide", "custom", "about" }) do UI.ShowPage(key, true) end

-- flip every switch and segment twice, click every button
local function walk(o, seen)
  if type(o) ~= "table" or seen[o] then return end
  seen[o] = true
  if o._kind == "Button" and o._scripts and o._scripts.OnClick then
    o._scripts.OnClick(o, "LeftButton")
    if o._scripts.OnClick then o._scripts.OnClick(o, "LeftButton") end
  end
  if o._kind == "EditBox" and o._scripts then
    o._text = "Typed Name"
    if o._scripts.OnTextChanged then o._scripts.OnTextChanged(o, true) end
    if o._scripts.OnEnterPressed then o._scripts.OnEnterPressed(o) end
    if o._scripts.OnEditFocusGained then o._scripts.OnEditFocusGained(o) end
    if o._scripts.OnEditFocusLost then o._scripts.OnEditFocusLost(o) end
  end
  if o._scripts then
    for _, k in ipairs({ "OnEnter", "OnLeave", "OnMouseWheel", "OnDragStart", "OnDragStop" }) do
      if o._scripts[k] then o._scripts[k](o, 1) end
    end
    -- Cards toggle on a click anywhere on them: press once, then once more, to leave them as found.
    if o._kind == "Frame" and o._scripts.OnMouseUp then
      o._scripts.OnMouseUp(o, "LeftButton"); o._scripts.OnMouseUp(o, "LeftButton")
    end
  end
  for _, c in ipairs(o._children or {}) do walk(c, seen) end
end
walk(OnAirConsole, {})
walk(OnAirMinimapButton, {})
walk(OnAirBadge, {})
-- the walk typed into every field and clicked every choice: back to known settings
OA.db.npc = { mode = "real", enemy = "Enemy", friendly = "NPC", boss = "Boss" }

OA.GoLive()
assert(OA.live, "should be live")
fire("PLAYER_TARGET_CHANGED"); fire("GROUP_ROSTER_UPDATE"); fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
fire("UPDATE_MOUSEOVER_UNIT"); fire("FRIENDLIST_UPDATE"); fire("GUILD_ROSTER_UPDATE"); fire("CLUB_MEMBERS_UPDATED")
fire("MAIL_INBOX_UPDATE"); fire("PARTY_INVITE_REQUEST", "Inviter-Kazzak"); fire("UNIT_TARGET", "target")

-- the global text hook
local fs = UIParent:CreateFontString()
fs:SetText("Bob and Stranger-Draenor and |Kp7|k")
RESULT_TEXT = fs:GetText()
local secret = { __secret = true }
fs:SetText(secret)
local b = CreateFrame("Button"); b:SetText("Carl")
RESULT_BUTTON = b:GetText()

-- chat
local f = FILTERS["CHAT_MSG_WHISPER"]
local _, msg, author = f(ChatFrame1, "CHAT_MSG_WHISPER", "hi from |Hplayer:Bob-Kazzak:1|h[Bob]|h", "Bob-Kazzak", "", "", "", "", 0, 0, "", 0, 1, "guid")
RESULT_CHAT = author .. " | " .. msg
local ok2 = FILTERS["CHAT_MSG_BN_WHISPER"](ChatFrame1, "CHAT_MSG_BN_WHISPER", "yo", "|Kp7|k", "", "", "", "", 0, 0, "", 0, 1, "", 7)
local box = CreateFrame("EditBox"); box:SetAttribute("tellTarget", author)
ChatFrameUtil.UpdateHeader(box)
RESULT_TELL = box:GetAttribute("tellTarget")
local ctx = { name = author, chatTarget = author }
MENUS_MOCK["MENU_UNIT_FRIEND"](nil, nil, ctx)
RESULT_MENU = tostring(ctx.name) .. "/" .. tostring(ctx.server)

-- tooltips
GameTooltip._lines = 0
GameTooltip:Show()
TooltipDataProcessor._calls[2](GameTooltip)
TooltipDataProcessor._calls.ALL(GameTooltip)

UI.ShowConsole(); UI.Refresh()
SlashCmdList.ONAIR("reshuffle")
SlashCmdList.ONAIR("")
OnAir_OnAddonCompartmentClick(nil, "RightButton")
OnAir_OnBinding("toggle")
assert(not OA.live, "binding should end the broadcast")
OA.GoLive(); OA.EndLive()
assert(C_CVar._v.UnitNameOwn == "1", "cvars restored")

-- camera: a preset, then live-only mode, then off: every CVar back where it was
local cam = OA.db.camera
cam.mode = "off"; OA.Camera.Update()
C_CVar._v = {}
cam.mode = "always"; OA.Camera.UsePreset("cinematic")
assert(C_CVar.GetCVar("cameraDistanceMaxZoomFactor") == "2.6", "zoom applied")
assert(C_CVar.GetCVar("cameraFov") == "75", "fov applied")
assert(C_CVar.GetCVar("CameraKeepCharacterCentered") == "0", "centering off for the shoulder offset")
OA.Camera.Set("fov", 60)
assert(C_CVar.GetCVar("cameraFov") == "60", "slider applied")
OA.Camera.ToggleOrbit(); assert(ORBIT > 0, "orbiting"); OA.Camera.ToggleOrbit(); assert(ORBIT == 0, "orbit stopped")
cam.mode = "live"; OA.Camera.Update()
assert(C_CVar.GetCVar("cameraFov") == "90", "live mode, not live: restored")
OA.GoLive(); assert(C_CVar.GetCVar("cameraFov") == "60", "live mode, live: applied")
OA.EndLive(); assert(C_CVar.GetCVar("cameraFov") == "90", "broadcast over: restored")
assert(C_CVar.GetCVar("cameraDistanceMaxZoomFactor") == "1.9", "zoom restored")
assert(OA.db.camera.saved == nil, "nothing left saved")
UI.ShowPage("camera", true); walk(OnAirConsole, {})

-- stream chat: only the picked kinds of lines, names aliased
OA.GoLive()
local smf
for _, c in ipairs(OnAirStreamChat._children) do if c._kind == "ScrollingMessageFrame" then smf = c end end
assert(OnAirStreamChat:IsShown(), "stream chat shown while live")
fire("CHAT_MSG_MONSTER_SAY", "Hello Bob, welcome.", "Innkeeper", "", "", "", "", 0, 0, "", 0, 1, "")
fire("CHAT_MSG_LOOT", "Bob receives loot: [Cloth].", "", "", "", "", "", 0, 0, "", 0, 1, "")
fire("CHAT_MSG_PARTY", "secret plan", "Bob-Kazzak", "", "", "", "", 0, 0, "", 0, 1, "")
STREAM_LINES = table.concat(smf._lines, " || ")
OA.EndLive()
assert(not OnAirStreamChat:IsShown(), "stream chat hidden after the broadcast")
UI.ShowPage("stream", true); walk(OnAirConsole, {})

-- moments: a session at 00:00, automatic markers, a manual one, exports
OA.db.moments.screenshot = true
OA.GoLive()
local session = OA.Moments.Current()
assert(session and session.moments[1].kind == "start", "session starts with a start moment")
fire("ENCOUNTER_START", 1, "Big Boss")
fire("ENCOUNTER_END", 1, "Big Boss", 0, 0, 1)
fire("CHALLENGE_MODE_START", 1)
fire("CHALLENGE_MODE_COMPLETED")
fire("ACHIEVEMENT_EARNED", 99)
fire("PLAYER_LEVEL_UP", 42)
fire("PLAYER_DEAD")
fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ4:|Hitem:1::|h[Epic Sword]|h|r.", "", "", "", "", "", 0, 0, "", 0, 1, "")
fire("CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2::|h[Grey Rock]|h|r.", "", "", "", "", "", 0, 0, "", 0, 1, "")
OA.Moments.Mark("Funny moment with Bob")
local kinds = {}
for _, m in ipairs(session.moments) do kinds[#kinds + 1] = m.kind .. ":" .. m.text end
MOMENTS = table.concat(kinds, " | ")
CHAPTERS = OA.Moments.Chapters(session)
MARKERS = OA.Moments.MarkerList(session)
assert(SHOTS > 0, "screenshots taken")
UI.ShowPage("moments", true); walk(OnAirConsole, {})

-- shield: a stranger's whisper is held, a friend's goes through; invites declined; zones hidden
OA.db.shield.reply = true
DECLINED = 0
OA.db.shield.zones = true
OA.Shield.Apply()
local held = FILTERS["CHAT_MSG_WHISPER"](ChatFrame1, "CHAT_MSG_WHISPER", "where are you?", "Sniper-Kazzak", "", "", "", "", 0, 0, "", 0, 1, "guid1")
local friend = FILTERS["CHAT_MSG_WHISPER"](ChatFrame1, "CHAT_MSG_WHISPER", "hey", "Pal-Kazzak", "", "", "", "", 0, 0, "", 0, 1, "guid2")
SHIELD_HELD, SHIELD_FRIEND = held, friend
fire("PARTY_INVITE_REQUEST", "Sniper-Kazzak", false, false, false, false, false, "guid1")
fire("DUEL_REQUESTED", "Sniper-Kazzak")
SHIELD_DECLINED = DECLINED
SHIELD_REPLY = SENT[1]
local zfs = UIParent:CreateFontString(); zfs:SetText("Welcome to Stormwind City, Trade District")
ZONE_TEXT = zfs:GetText()
HELD_BEFORE_END = OA.Shield.HeldCount()
OA.EndLive()
HELD_AFTER_END = OA.Shield.HeldCount()
UI.ShowPage("shield", true); walk(OnAirConsole, {})

-- preview: masked like live, but no session, no Shield
local before = OA.Moments.Current()
OA.TogglePreview()
assert(OA.live and OA.rehearsal, "preview is on")
assert(OA.Moments.Current() == before, "a preview starts no session")
local pfs = UIParent:CreateFontString(); pfs:SetText("Bob is here")
PREVIEW_TEXT = pfs:GetText()
OA.GoLive()
assert(OA.live and not OA.rehearsal, "from preview straight to live")
assert(OA.Moments.Current() ~= before, "going live from preview starts the session")
OA.EndLive()

-- NPC names: generic labels, then hidden
OA.db.npc = { mode = "generic", enemy = "Enemy", friendly = "NPC", boss = "Boss" }
OA.GoLive()
local plate = { UnitFrame = { name = UIParent:CreateFontString() } }
C_NamePlate.GetNamePlateForUnit = function() return plate end
plate.UnitFrame.name:SetText("Angry Ogre")
OA.Hide.NamePlate("nameplate2")
NPC_GENERIC = plate.UnitFrame.name:GetText()
plate.UnitFrame.name:SetText("Angry Ogre")
NPC_AFTER_RESET = plate.UnitFrame.name:GetText()
OA.Hide.NamePlate("nameplate3")
NPC_BOSS = plate.UnitFrame.name:GetText()
OA.db.npc.mode = "hide"
OA.Hide.NamePlate("nameplate2")
NPC_HIDDEN_ALPHA = plate.UnitFrame.name:GetAlpha()
NPC_CVAR = C_CVar.GetCVar("UnitNameNPC")
OA.EndLive()
OA.db.npc.mode = "real"

-- the Deck: every button, layout mode on and off, hiding the UI keeps the Deck
OA.db.deck.show = "always"
OA.Deck.Refresh()
walk(OnAirDeck, {})
OA.Deck.ToggleUI()
DECK_UI_HIDDEN = (UI_SHOWN == false)
DECK_STAYS = OnAirDeck:IsShown() and OnAirDeck:GetParent() == WorldFrame
OA.Deck.ToggleUI()
OA.Layout.Start(); LAYOUT_ON = OA.Layout.IsEditing(); walk(OnAirLayoutBar, {}); OA.Layout.Stop()
OA.Deck.AfterDrag()
UI.ShowPage("deck", true); walk(OnAirConsole, {})
UI.ShowPage("names", true); walk(OnAirConsole, {})

-- slider keys
for _, f in ipairs(FRAMES) do
  if f._scripts and f._scripts.OnKeyDown then
    f._scripts.OnEnter(f); f._scripts.OnKeyDown(f, "RIGHT"); f._scripts.OnKeyDown(f, "A"); f._scripts.OnLeave(f)
  end
end
UI.HideConsole()
"""


def run(toc):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK, toc)
    # Track every frame so events can be fired at the ones that registered them.
    lua.execute(r"""
    FRAMES = {}
    local create = CreateFrame
    function CreateFrame(kind, name, parent)
      local f = create(kind, name, parent)
      f._events = {}
      f.RegisterEvent = function(self, e) self._events[e] = true end
      f.RegisterUnitEvent = function(self, e) self._events[e] = true end
      table.insert(FRAMES, f)
      return f
    end
    """)
    oa = lua.eval("{}")
    toc_text = open(os.path.join(ROOT, "OnAir.toc"), encoding="utf-8").read()
    files = [l.strip().replace("\\", "/") for l in toc_text.splitlines() if l.strip().endswith(".lua")]
    for rel in files:
        lua.execute(open(os.path.join(ROOT, rel), encoding="utf-8").read(), "OnAir", oa)
    lua.execute(DRIVE, oa)
    g = lua.globals()
    guarded = [g.GUARDED[i] for i in range(1, len(g.GUARDED) + 1)]
    if guarded:
        raise RuntimeError("errors caught by the guard: " + " || ".join(guarded))
    return {k: g[k] for k in ("RESULT_TEXT", "RESULT_BUTTON", "RESULT_CHAT", "RESULT_TELL", "RESULT_MENU", "STREAM_LINES",
                              "MOMENTS", "CHAPTERS", "MARKERS", "SHIELD_HELD", "SHIELD_FRIEND", "SHIELD_DECLINED",
                              "SHIELD_REPLY", "ZONE_TEXT", "HELD_BEFORE_END", "HELD_AFTER_END", "PREVIEW_TEXT",
                              "NPC_GENERIC", "NPC_AFTER_RESET", "NPC_BOSS", "NPC_HIDDEN_ALPHA", "NPC_CVAR",
                              "DECK_UI_HIDDEN", "DECK_STAYS", "LAYOUT_ON")}


if __name__ == "__main__":
    failures = 0
    for label, toc in (("Retail", 120100), ("Forever", 16001)):
        try:
            results = run(toc)
            print(label)
            for k, v in results.items():
                print(f"  {k}: {v!r}")
            if label == "Retail":
                checks = [
                    ("Bob" not in results["RESULT_TEXT"] and "Stranger" not in results["RESULT_TEXT"]
                     and "|K" not in results["RESULT_TEXT"], "text hook scrubbed"),
                    (results["RESULT_BUTTON"] != "Carl", "button text scrubbed"),
                    (not results["RESULT_CHAT"].startswith("Bob") and "[Bob]" not in results["RESULT_CHAT"], "chat scrubbed"),
                    (results["RESULT_TELL"] == "Bob-Kazzak", "reply goes to the real player"),
                    (results["RESULT_MENU"] == "Bob/Kazzak", "menu points at the real player"),
                    ("Innkeeper" in results["STREAM_LINES"] and "Bob" not in results["STREAM_LINES"]
                     and "secret plan" not in results["STREAM_LINES"] and "Cloth" in results["STREAM_LINES"],
                     "stream chat: NPC talk and loot, names aliased, party chat left out"),
                    (all(k in results["MOMENTS"] for k in ("pull:", "kill:", "key:", "keyEnd:", "achievement:", "level:",
                                                           "death:", "loot:", "mark:")) and "Grey Rock" not in results["MOMENTS"]
                     and "Bob" not in results["MOMENTS"], "moments: every kind marked, grey loot skipped, names aliased"),
                    (results["CHAPTERS"].startswith("00:00 "), "chapters start at 00:00"),
                    (results["SHIELD_HELD"] is True and results["SHIELD_FRIEND"] is not True, "stranger whisper held, friend's through"),
                    (results["SHIELD_DECLINED"] == 2, "stranger invite and duel declined"),
                    (results["SHIELD_REPLY"] == "Sniper-Kazzak", "auto-reply sent to the stranger"),
                    ("Stormwind" not in results["ZONE_TEXT"] and "Trade District" not in results["ZONE_TEXT"], "zone names hidden"),
                    (results["HELD_BEFORE_END"] == 1 and results["HELD_AFTER_END"] == 0, "held whispers shown after the broadcast"),
                    ("Bob" not in results["PREVIEW_TEXT"], "preview masks names"),
                    (results["NPC_GENERIC"] == "Enemy" and results["NPC_AFTER_RESET"] == "Enemy", "NPC generic label sticks"),
                    (results["NPC_BOSS"] == "Boss", "bosses read Boss"),
                    (results["NPC_HIDDEN_ALPHA"] == 0 and results["NPC_CVAR"] == "0", "NPC names hidden (plates and overhead)"),
                    (results["DECK_UI_HIDDEN"] and results["DECK_STAYS"], "Deck stays with the UI hidden"),
                    (results["LAYOUT_ON"], "edit layout runs"),
                ]
                for ok, what in checks:
                    print(f"  {'ok  ' if ok else 'FAIL'} {what}")
                    failures += 0 if ok else 1
        except Exception as e:  # noqa: BLE001
            print(label, "ERROR:", e)
            failures += 1
    print("ui smoke:", "clean" if failures == 0 else f"{failures} failure(s)")
    sys.exit(1 if failures else 0)
