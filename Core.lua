local addonName, OA = ...

-- Settings, going live and off the air, events and commands. Loads last (see the TOC).
OA.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
OA.live = false

local L = OA.L
local Utils = OA.Utils
local Names = OA.Names

local DEFAULTS = {
    version = 1,
    live = false,
    me = L["The Star"],
    theme = "film",
    crew = { mode = "cast", template = L["{me}'s Crew {n}"] },
    others = { mode = "cast", template = L["Extra #{n}"] },
    petTemplate = L["{owner}'s Pet"],
    guildAlias = L["{me}'s Studio"],
    otherGuild = L["Studio {n}"],
    communityTemplate = L["Community {n}"],
    -- A meter row whose name the game keeps secret (combat): we can't tell who it is.
    meterUnknown = L["Crew Member"],
    -- NPC names: "real", "generic" (the labels below) or "hide".
    npc = { mode = "real", enemy = L["Enemy"], friendly = L["NPC"], boss = L["Boss"] },
    who = { me = true, crew = true, others = true, friends = true, guilds = true, pets = true },
    where = { chat = true, clearChat = true, nameplates = true, tooltips = true, meters = true, interface = true },
    -- No names above heads at all: the game takes a blank name font at login (see Hide.lua).
    blankNames = false,
    custom = {},
    assigned = {},
    assignedKind = {},
    counters = {},
    myChars = {},
    toast = true,
    minimap = { show = true, angle = 200 },
    -- Camera values left nil mean "the game's default".
    look = "viewfinder",
    layout = { snap = "guides", grid = 32, ui = true, locked = false },
    camera = { mode = "off", preset = "default", orbitSpeed = 0.1, orbitDir = "left",
        orbitStop = { move = true, mouse = true } },
    moments = { sessions = {}, auto = {}, flash = true, note = true, screenshot = false },
    shield = { whispers = true, reply = false, replyText = L["I'm live right now, so whispers are off. I'll read yours after the stream!"],
        invites = true, duels = true, trades = true, zones = false, banners = true, minimap = false, held = {} },
    deck = { show = "always", hide = "fade", fadeTo = 0.25, delay = 2, scale = 1, buttons = {} },
    stream = { enabled = true, groups = { npc = true, emotes = true, loot = true }, opacity = 0.92,
        fontSize = 14, fade = true, header = true },
    window = {},
}

local function Merge(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            Merge(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function InitDB()
    OnAirDB = type(OnAirDB) == "table" and OnAirDB or {}
    Merge(OnAirDB, DEFAULTS)
    OA.db = OnAirDB
    OA.Kit.ApplyTheme(OA.db.look)
end

-- Your character is always "me", on every character you log in with.
local function RememberMe()
    local first, second = UnitName("player")
    if Utils.IsPlainString(first) then
        OA.db.myChars[Names.MakeKey(first, second)] = true
    end
end

---------------------------------------------------------------------------------------------- live

local function Notify()
    if OA.UI and OA.UI.OnLiveChanged then
        OA.UI.OnLiveChanged()
    end
end

-- Preview ("rehearsal"): everything is masked like live, so you can check your screen, but no
-- clock, no moments, no Shield, no chat wipe, and it isn't remembered as live.
local function Start(atLogin, rehearsal)
    OA.live = true
    OA.rehearsal = rehearsal and true or false
    OA.db.live = not rehearsal
    -- Each part on its own: one failing (a frame locked in combat) can't stop the rest.
    Utils.Guard("go live: names", OA.Collect.All)()
    Utils.Guard("go live: hide", OA.Hide.Start)()
    if not rehearsal then
        Utils.Guard("go live: chat", OA.Chat.OnGoLive)(atLogin)
        Utils.Guard("go live: moments", OA.Moments.OnGoLive)(atLogin)
        Utils.Guard("go live: shield", OA.Shield.OnGoLive)()
    else
        Utils.Guard("go live: chat", OA.Chat.Start)()
    end
    Utils.Guard("go live: camera", OA.Camera.Update)()
    Utils.Guard("go live: stream chat", OA.StreamChat.OnGoLive)()
    Notify()
end

function OA.GoLive()
    if OA.live and OA.rehearsal then
        -- From a preview straight to the real broadcast: the masking is already running.
        OA.rehearsal = false
        OA.db.live = true
        OA.Chat.OnGoLive(false)
        OA.Moments.OnGoLive(false)
        OA.Shield.OnGoLive()
        Notify()
        if OA.db.toast and OA.UI and OA.UI.Toast then
            OA.UI.Toast(true)
        end
        return
    end
    if OA.live then
        return
    end
    Start(false)
    if OA.db.toast and OA.UI and OA.UI.Toast then
        OA.UI.Toast(true)
    end
end

function OA.EndLive()
    if not OA.live then
        return
    end
    local rehearsal = OA.rehearsal
    OA.live = false
    OA.rehearsal = false
    OA.db.live = false
    if not rehearsal then
        OA.Moments.OnEndLive()
    end
    OA.Hide.Stop()
    if not rehearsal then
        OA.Shield.OnEndLive()
    end
    OA.Camera.Update()
    OA.StreamChat.Update()
    Notify()
    if OA.db.toast and OA.UI and OA.UI.Toast then
        OA.UI.Toast(false)
    end
end

function OA.Toggle()
    if OA.live then
        OA.EndLive()
    else
        OA.GoLive()
    end
end

-- Preview on and off. From a preview, Go live switches straight to the real broadcast.
function OA.TogglePreview()
    if OA.live and OA.rehearsal then
        OA.EndLive()
    elseif not OA.live then
        Start(false, true)
        if OA.UI and OA.UI.Toast then
            OA.UI.Toast("preview")
        end
    end
end

-- Settings that change who gets which alias: everyone known is worked out again.
function OA.NamesChanged(reshuffle)
    Names.Rebuild(reshuffle)
    if OA.live then
        OA.Hide.Redo()
    end
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

---------------------------------------------------------------------------------------------- events

local frame = CreateFrame("Frame")

local HANDLERS = {
    ADDON_LOADED = function(name)
        if name ~= addonName then
            return
        end
        InitDB()
        Names.Init()
        Names.OnChanged = OA.Hide.Rescrub
        OA.Collect.Init()
        Utils.Guard("name font", OA.Hide.NameFontAtLogin)()
    end,
    PLAYER_LOGIN = function()
        Utils.Guard("name font", OA.Hide.NameFontAtLogin)()
        RememberMe()
        OA.Camera.Init()
        if OA.UI and OA.UI.Init then
            OA.UI.Init()
        end
        if OA.db.live then
            Start(true)
            Utils.Print(L["You're on the air: names are hidden. /onair to open the console."])
        elseif OA.db.savedCVars then
            -- Went off the air in a way that never restored them (a crash): do it now.
            OA.Hide.RestoreCVars()
        end
        OA.Shield.Init()
    end,
    PLAYER_ENTERING_WORLD = function(isInitialLogin)
        OA.Hide.NameFontEntered(isInitialLogin)
    end,
    PLAYER_REGEN_ENABLED = function()
        OA.Hide.OnCombatEnd()
        OA.Camera.OnCombatEnd()
        OA.Shield.OnCombatEnd()
    end,
    PLAYER_REGEN_DISABLED = function()
        OA.Camera.StopOrbit()
    end,
    NAME_PLATE_UNIT_ADDED = function(unit)
        if OA.live then
            OA.Hide.NamePlate(unit)
        end
    end,
    -- Only the frames that show what changed (UNIT_TARGET comes all through a fight).
    PLAYER_TARGET_CHANGED = function() OA.Hide.OnUnitChanged("target") end,
    PLAYER_FOCUS_CHANGED = function() OA.Hide.OnUnitChanged("focus") end,
    UNIT_TARGET = function(unit) OA.Hide.OnUnitChanged(unit == "focus" and "focustarget" or "targettarget") end,
    GROUP_ROSTER_UPDATE = function() OA.Hide.OnUnitChanged("group") end,
    UNIT_PET = function() OA.Hide.OnUnitChanged("pet") end,
}

for event, fn in pairs(HANDLERS) do
    HANDLERS[event] = Utils.Guard(event, fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    HANDLERS[event](...)
end)
for event in pairs(HANDLERS) do
    if event == "UNIT_TARGET" then
        frame:RegisterUnitEvent(event, "target", "focus")
    elseif event == "UNIT_PET" then
        frame:RegisterUnitEvent(event, "player")
    else
        frame:RegisterEvent(event)
    end
end

---------------------------------------------------------------------------------------------- commands

SLASH_ONAIR1 = "/onair"
SLASH_ONAIR2 = "/oa"
SlashCmdList.ONAIR = function(input)
    local command = Utils.Trim((input or ""):lower())
    if command == "live" or command == "on" then
        OA.GoLive()
    elseif command == "off" or command == "end" then
        OA.EndLive()
    elseif command == "preview" then
        OA.TogglePreview()
    elseif command == "layout" then
        OA.Layout.Toggle()
    elseif command == "toggle" then
        OA.Toggle()
    elseif command == "mark" or command:find("^mark ") then
        OA.Moments.Mark(Utils.Trim(input:sub(6)))
    elseif command == "orbit" then
        OA.Camera.ToggleOrbit()
    elseif command == "camera" then
        OA.UI.ShowConsole()
        OA.UI.ShowPage("camera", true)
    elseif command == "check" then
        OA.Check.Run()
    elseif command:find("^check %d+$") then
        OA.Check.Later(math.min(30, tonumber(command:match("%d+"))))
    elseif command == "reshuffle" then
        OA.NamesChanged(true)
        Utils.Print(L["Everyone drew a new name."])
    else
        OA.UI.ToggleConsole()
    end
end

BINDING_HEADER_ONAIR = "OnAir"
BINDING_NAME_ONAIR_TOGGLE = L["Go live / end broadcast"]
BINDING_NAME_ONAIR_CONSOLE = L["Open the console"]
BINDING_NAME_ONAIR_ORBIT = L["Camera orbit on / off"]
BINDING_NAME_ONAIR_MARK = L["Mark a moment"]
BINDING_NAME_ONAIR_UI = L["Hide / show the UI (keeps the Deck)"]

function OnAir_OnBinding(what)
    if what == "toggle" then
        OA.Toggle()
    elseif what == "ui" then
        OA.Deck.ToggleUI()
    elseif what == "mark" then
        OA.Moments.Mark()
    elseif what == "orbit" then
        OA.Camera.ToggleOrbit()
    else
        OA.UI.ToggleConsole()
    end
end

-- Same clicks everywhere: left goes live or ends, right opens the console.
function OnAir_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        OA.UI.ToggleConsole()
    else
        OA.Toggle()
    end
end

function OnAir_OnAddonCompartmentEnter(_, menuButton)
    OA.UI.ShowLauncherTooltip(menuButton)
end

function OnAir_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
