local _, OA = ...

-- Where names get replaced or hidden on screen.
--
-- 1. Interface text: every FontString and Button text set from Lua goes through Scrub(). That
--    covers Blizzard's and other addons' frames alike: unit and raid frames, the character window,
--    friends, guild, communities, group finder, mail, scoreboard, popups.
-- 2. Names the game keeps secret (combat, instances) can't be read, so they can't be replaced:
--    those FontStrings are hidden instead, while they hold a secret player name.
-- 3. Overhead names: the game's own CVars, saved before going live and restored after; and, as
--    an option, a blank name font the game takes at login.
-- 4. Tooltips, nameplates and damage meters get their own handling below.
OA.Hide = {}

local Hide = OA.Hide
local Names = OA.Names
local Utils = OA.Utils
local L = OA.L
local IsSecret = Utils.IsSecret
local SafeBool = Names.SafeBool
local WORD, IsIndexWord = Names.WORD, Names.IsIndexWord

local function Where(key)
    return OA.live and OA.db.where[key] ~= false
end

-- The game can answer "is it forbidden / visible" with a secret boolean, which can't be tested:
-- a secret answer counts as forbidden and not visible.
local function Usable(obj)
    if obj.IsForbidden then
        local ok, forbidden = pcall(obj.IsForbidden, obj)
        if not ok or IsSecret(forbidden) or forbidden then
            return false
        end
    end
    return true
end

local function Visible(obj)
    local visible = obj:IsVisible()
    return not IsSecret(visible) and visible == true
end

---------------------------------------------------------------------------------------------- CVars

local CVARS = {
    me = { "UnitNameOwn" },
    others = { "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName", "UnitNamePlayerGuild",
        "UnitNamePlayerPVPTitle", "UnitNameGuildTitle" },
    pets = { "UnitNameFriendlyPetName", "UnitNameFriendlyGuardianName", "UnitNameFriendlyTotemName",
        "UnitNameFriendlyMinionName", "UnitNameEnemyPetName", "UnitNameEnemyGuardianName",
        "UnitNameEnemyTotemName", "UnitNameEnemyMinionName" },
    -- NPC names above heads: the game draws them itself, so they can only be switched off.
    npc = { "UnitNameNPC", "UnitNameHostleNPC", "UnitNameInteractiveNPC", "UnitNameNonCombatCreatureName",
        "UnitNameFriendlySpecialNPCName" },
}

local pendingCVars

-- Every "UnitName..." switch the game has about pets, guardians, totems, minions or companions goes
-- with the known ones (Midnight adds and renames some): looked up once, in the game's own list.
local PET_PARTS = { "Pet", "Guardian", "Totem", "Minion", "Companion" }
local petSwitchesFound = false

local function FindPetSwitches()
    if petSwitchesFound then
        return
    end
    petSwitchesFound = true
    local console = C_Console
    if not (console and console.GetAllCommands) then
        return
    end
    local ok, commands = pcall(console.GetAllCommands)
    if not ok or type(commands) ~= "table" then
        return
    end
    local known = {}
    for _, cvar in ipairs(CVARS.pets) do
        known[cvar] = true
    end
    for _, info in ipairs(commands) do
        local name = type(info) == "table" and info.command
        if type(name) == "string" and not IsSecret(name) and name:find("^UnitName") and not known[name] then
            for _, part in ipairs(PET_PARTS) do
                if name:find(part, 1, true) then
                    known[name] = true
                    CVARS.pets[#CVARS.pets + 1] = name
                    break
                end
            end
        end
    end
end

-- Names above players' heads. The game draws your target's name itself, whatever the switches
-- say, and addons can't change that text; but a player with a nameplate shows the plate instead,
-- and OnAir masks plates. So while live friendly players get name-only plates. The player name
-- switch stays off: it also brings back the other faction's names, which get no friendly plate.
-- Inside instances the game locks those plates (they'd show real names): switched off there.
local PLATE_NAMES = { nameplateShowFriendlyPlayers = "1", nameplateShowOnlyNameForFriendlyPlayerUnits = "1" }

local function InInstance()
    local ok, inside = pcall(IsInInstance)
    return ok and inside == true
end

-- Each switch OnAir sets while live, with its value.
local function CVarsWanted()
    FindPetSwitches()
    local wanted = {}
    if OA.db.where.nameplates == false then
        return wanted
    end
    for who, list in pairs(CVARS) do
        local on = OA.db.who[who] ~= false or (who == "others" and OA.db.who.crew ~= false)
        if who == "npc" then
            on = OA.db.npc.mode ~= "real"
        end
        if on then
            for _, cvar in ipairs(list) do
                wanted[cvar] = "0"
            end
        end
    end
    if OA.db.who.others ~= false or OA.db.who.crew ~= false then
        if InInstance() then
            wanted.nameplateShowFriendlyPlayers = "0"
        else
            for cvar, value in pairs(PLATE_NAMES) do
                wanted[cvar] = value
            end
        end
    end
    return wanted
end

-- The game's name switches set for live, only while live. Your own values are kept first (once,
-- in the saved variables, so a crash or a disconnect while live still gets them back on the next
-- login), and what OnAir set is noted, so putting them back can tell a later change of yours.
function Hide.ApplyCVars()
    if not OA.live then
        return
    end
    if InCombatLockdown() then
        pendingCVars = "apply"
        return
    end
    local db = OA.db
    db.savedCVars = db.savedCVars or {}
    db.cvarsSet = db.cvarsSet or {}
    for cvar, target in pairs(CVarsWanted()) do
        local value = C_CVar.GetCVar(cvar)
        if value ~= nil then
            if db.savedCVars[cvar] == nil then
                db.savedCVars[cvar] = value
            end
            if value ~= target then
                pcall(C_CVar.SetCVar, cvar, target)
            end
            db.cvarsSet[cvar] = target
        end
    end
end

-- Into or out of an instance while live: plates on or off (a moment later, after other addons
-- set their own nameplate switches for the new zone).
local zoneWatch = CreateFrame("Frame")
zoneWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneWatch:SetScript("OnEvent", function()
    if OA.live then
        C_Timer.After(0.5, function()
            if OA.live then
                Utils.Guard("name switches", Hide.ApplyCVars)()
            end
        end)
    end
end)

-- Your own values back. A switch that no longer holds what OnAir set was changed since (by you
-- or another addon, or the game never kept OnAir's change after a crash): that's the newer
-- choice, and it stays.
function Hide.RestoreCVars()
    if InCombatLockdown() then
        pendingCVars = "restore"
        return
    end
    local db = OA.db
    local set = db.cvarsSet or {}
    for cvar, value in pairs(db.savedCVars or {}) do
        if set[cvar] == nil or C_CVar.GetCVar(cvar) == set[cvar] then
            pcall(C_CVar.SetCVar, cvar, value)
        end
    end
    db.savedCVars = nil
    db.cvarsSet = nil
end

function Hide.OnCombatEnd()
    local todo = pendingCVars
    pendingCVars = nil
    if OA.live and Hide.Meters then
        Utils.Guard("meters", Hide.Meters)()
    end
    if todo == "apply" and OA.live then
        Hide.ApplyCVars()
    elseif todo == "restore" then
        Hide.RestoreCVars()
    end
end

---------------------------------------------------------------------------------------------- blank name font

-- Names above heads are drawn by the game, and no addon can change that text: only the font it's
-- drawn with, and only while you log in. The game reads its name fonts once then and keeps them
-- until you log out (a /reload doesn't read them again). With the blank name font on (an option,
-- off by default), OnAir hands the game a font without ink: no name shows above any head
-- (players, pets, NPCs, yours), live or not. Switching it either way shows after a logout. Each
-- alphabet has its own name font (a Cyrillic or Korean name is drawn with its own): all go.
local BLANK_FONT = Utils.MEDIA .. "OnAirBlank.ttf"
Hide.NAME_FONTS = { "UNIT_NAME_FONT", "UNIT_NAME_FONT_ROMAN", "UNIT_NAME_FONT_CYRILLIC",
    "UNIT_NAME_FONT_KOREAN", "UNIT_NAME_FONT_CHINESE" }

local blankThisLogin = false  -- the game gets the blank font at this login
local blankMissing = false    -- the option is on, but the client can't find the font file
local entered = false         -- the first PLAYER_ENTERING_WORLD came: the login is over

-- The client finds the file (SetFont raises when it can't). A name font the game can't load would
-- leave it with none, so then it keeps its own.
local function BlankFontLoads()
    local probe = UIParent:CreateFontString()
    return (pcall(probe.SetFont, probe, BLANK_FONT, 12, ""))
end

-- While you log in: OnAir's load, PLAYER_LOGIN and the first PLAYER_ENTERING_WORLD. The game reads
-- the fonts in there somewhere, and an addon loading later can set a name font of its own at the
-- same times (EllesmereUI's name font does), so the blank one goes in again each time.
function Hide.NameFontAtLogin()
    if entered or blankMissing then
        return
    end
    if not blankThisLogin then
        if not OA.db.blankNames then
            return
        end
        if not BlankFontLoads() then
            blankMissing = true
            Utils.Print(OA.L["The blank name font is missing, so names above heads still show. Reinstall OnAir."])
            return
        end
        blankThisLogin = true
    end
    for _, global in ipairs(Hide.NAME_FONTS) do
        _G[global] = BLANK_FONT
    end
end

-- The first PLAYER_ENTERING_WORLD. A real login remembers what the game got, in the saved
-- variables: after a /reload the game still has the fonts it read at the login.
function Hide.NameFontEntered(isInitialLogin)
    if entered then
        return
    end
    Hide.NameFontAtLogin()
    entered = true
    if isInitialLogin then
        OA.db.blankNamesNow = blankThisLogin or nil
    end
end

-- "on" or "off", or "on-next" / "off-next": switched since the login, and the game shows that
-- after the next logout.
function Hide.BlankFontState()
    local wanted, now = OA.db.blankNames == true, OA.db.blankNamesNow == true
    if wanted == now then
        return wanted and "on" or "off"
    end
    return wanted and "on-next" or "off-next"
end

---------------------------------------------------------------------------------------------- muting

-- A FontString hidden for one or more reasons ("secret", "pet", "tot"). Hidden through its alpha,
-- held at 0 even when its owner sets it again.
local reasons = {}
local hooked = {}

local function Hidden(fs)
    return reasons[fs] ~= nil and next(reasons[fs]) ~= nil
end

local function Mute(fs, reason, on)
    if type(fs) ~= "table" or not fs.SetAlpha then
        return
    end
    if not hooked[fs] then
        hooked[fs] = true
        hooksecurefunc(fs, "SetAlpha", function(self, alpha)
            if Hidden(self) and (IsSecret(alpha) or alpha ~= 0) then
                pcall(self.SetAlpha, self, 0)
            end
        end)
        -- Midnight's other way to show a region: also held at 0 while hidden.
        if fs.SetAlphaFromBoolean then
            hooksecurefunc(fs, "SetAlphaFromBoolean", function(self)
                if Hidden(self) then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
        end
    end
    local was = Hidden(fs)
    local set = reasons[fs]
    if on then
        set = set or {}
        reasons[fs] = set
        set[reason] = true
    elseif set then
        set[reason] = nil
    end
    local now = Hidden(fs)
    -- Every time, not only when it first gets hidden: its owner may have shown it another way.
    if now then
        pcall(fs.SetAlpha, fs, 0)
    elseif was then
        pcall(fs.SetAlpha, fs, 1)
    end
end
Hide.Mute = Mute

function Hide.UnmuteAll()
    local list = {}
    for fs in pairs(reasons) do
        list[#list + 1] = fs
    end
    for _, fs in ipairs(list) do
        if Hidden(fs) then
            reasons[fs] = nil
            fs:SetAlpha(1)
        end
        reasons[fs] = nil
    end
end

-- FontStrings that show a player's name: hidden while the name is secret.
local guard = setmetatable({}, { __mode = "k" })

-- FontStrings that show an NPC's name in "generic" mode: they always read their label (Enemy,
-- Boss, NPC). Set without reading the old text, so it works on secret names too.
local npcLabel = setmetatable({}, { __mode = "k" })

-- The generic name for an NPC unit.
function Hide.NpcLabel(unit)
    local npc = OA.db.npc
    local classification = SafeBool(UnitClassification, unit)
    if classification == "worldboss" or SafeBool(UnitLevel, unit) == -1 then
        return npc.boss
    end
    if SafeBool(UnitCanAttack, "player", unit) then
        return npc.enemy
    end
    return npc.friendly
end

---------------------------------------------------------------------------------------------- meters

-- In combat a damage meter's names are secret, so its name labels are found by where they sit:
--  EllesmereUI: its own list of rows (below); without it, EllesmereUIDMFrameN > row > fill > text
--   frame, where a player row's label is anchored to the rank text on its left (spell rows have
--   no rank).
--  Blizzard: an ancestor named DamageMeter*, the FontString kept under a "name"-like key.
local meterKind = setmetatable({}, { __mode = "k" })

-- Which meter a frame sits in (one walk up its parents): EllesmereUI's within 8 levels, Details!'s
-- bars within 4, Blizzard's within 10.
local function MeterOf(frame)
    for depth = 1, 10 do
        if not frame then
            return nil
        end
        local name = frame.GetName and frame:GetName()
        if name then
            if depth <= 8 and name:find("EllesmereUIDMFrame", 1, true) == 1 then
                return "eui"
            elseif depth <= 4 and name:find("DetailsBarra_", 1, true) == 1 then
                return "details"
            elseif name:find("DamageMeter", 1, true) == 1 then
                return "blizz"
            end
        end
        frame = frame:GetParent()
    end
    return nil
end

-- EllesmereUI's meter keeps a list of its own rows (each window's row pool and the pinned row of
-- your own): each row's name label, rank and amount, and the data the row shows (row._src). Read
-- from there, a name label is known whatever the layout, and so is who its row is. label -> its
-- row; a row's rank or amount -> false. A text it doesn't know yet looks the list up again, at most
-- once a frame (windows can be added).
local euiRows = setmetatable({}, { __mode = "k" })
local euiMappedAt

local function AddEuiRow(row)
    local label = type(row) == "table" and rawget(row, "label")
    if type(label) ~= "table" then
        return
    end
    euiRows[label] = row
    for _, key in ipairs({ "pos", "amount" }) do
        local other = rawget(row, key)
        if type(other) == "table" then
            euiRows[other] = false
        end
    end
end

local function EuiRow(fs)
    local row = euiRows[fs]
    if row == nil and euiMappedAt ~= GetTime() then
        euiMappedAt = GetTime()
        local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
        local dm = type(modules) == "table" and modules.EllesmereUIDamageMeters
        local windows = type(dm) == "table" and rawget(dm, "_windows")
        if type(windows) == "table" then
            for _, window in pairs(windows) do
                if type(window) == "table" then
                    local pool = rawget(window, "rowPool")
                    if type(pool) == "table" then
                        for _, r in ipairs(pool) do
                            AddEuiRow(r)
                        end
                    end
                    AddEuiRow(rawget(window, "stickyPlayer"))
                end
            end
        end
        row = euiRows[fs]
    end
    return row
end

local function Classify(fs)
    local row = EuiRow(fs)
    if row ~= nil then
        return row and "eui" or false
    end
    local holder = fs:GetParent()
    if not holder then
        return false
    end
    local meter = MeterOf(holder)
    if meter == "eui" then
        -- In one of its windows but not in its list yet (a window just added): once more, now.
        euiMappedAt = nil
        row = EuiRow(fs)
        if row ~= nil then
            return row and "eui" or false
        end
        -- (An EllesmereUI without its row list: the name is the second text, right of the rank.)
        local first, second = holder:GetRegions()
        if second ~= fs or not (first and first.GetObjectType and first:GetObjectType() == "FontString") then
            return false
        end
        for i = 1, fs:GetNumPoints() do
            local point, relative = fs:GetPoint(i)
            if point == "LEFT" and relative == first then
                return "eui"
            end
        end
        return false
    end
    -- Details!: each bar is a frame named DetailsBarra_<window>_<row>, its left text "lineText1".
    if meter == "details" then
        local parent = holder
        for _ = 1, 3 do
            if not parent then
                break
            end
            if parent.lineText1 == fs then
                return "details"
            end
            parent = parent:GetParent()
        end
        return false
    end
    if meter == "blizz" then
        local parent = holder
        for _ = 1, 3 do
            if not parent then
                break
            end
            for key, value in pairs(parent) do
                if value == fs and type(key) == "string" and key:lower():find("name") then
                    return "blizz"
                end
            end
            parent = parent:GetParent()
        end
    end
    return false
end

-- EllesmereUI paints the rows of its Enemy Damage Taken view red: those are mobs, keep them.
local function EnemyRow(fs)
    local fill = fs:GetParent() and fs:GetParent():GetParent()
    if not (fill and fill.GetStatusBarColor) then
        return false
    end
    local r, g, b = fill:GetStatusBarColor()
    if IsSecret(r) then
        return false
    end
    return math.abs(r - 0xDD / 255) < 0.01 and math.abs(g - 0x31 / 255) < 0.01 and math.abs(b - 0x31 / 255) < 0.01
end

---------------------------------------------------------------------------------------------- text hook

local busy = false

-- Words left as they were (no name OnAir knows yet) -> the labels holding them. When one of them
-- turns out to be a name, only those labels are looked at again: no sweeping the whole UI. Kept
-- to a size: past it the list starts over (labels set before that just aren't looked at again).
local waiting = {}
local waitingCount = 0
local WAITING_LIMIT = 6000
local WEAK = { __mode = "k" }
local waitedOn = setmetatable({}, WEAK)  -- label -> the text it was indexed with

local function Index(obj, word)
    local holders = waiting[word]
    if not holders then
        holders = setmetatable({}, WEAK)
        waiting[word] = holders
        waitingCount = waitingCount + 1
    end
    holders[obj] = true
end

local function Wait(obj, text)
    -- The same text again (most labels are set over and over): indexed already.
    if waitedOn[obj] == text then
        return
    end
    -- Full: start over before this label (so it's indexed whole).
    if waitingCount >= WAITING_LIMIT then
        wipe(waiting)
        wipe(waitedOn)
        waitingCount = 0
    end
    waitedOn[obj] = text
    for word in text:gmatch(WORD) do
        if IsIndexWord(word) then
            Index(obj, word)
            -- "Bob's", "Name-Realm": the name alone may be what gets learned.
            local letters = word:match("^[%a\128-\255]+")
            if letters ~= word and #letters >= 2 then
                Index(obj, letters)
            end
            local short = word:find("-", 1, true) and word:match("^(.-)%-")
            if short and short ~= letters and #short >= 2 then
                Index(obj, short)
            end
        end
    end
end

-- Sets text without our own hook seeing it. Protected so the hook can never stay switched off.
local function SetQuiet(obj, text)
    busy = true
    pcall(obj.SetText, obj, text)
    busy = false
end

-- Text OnAir shows on purpose (real names on the Custom page): never rewritten.
local exempt = setmetatable({}, { __mode = "k" })
function Hide.Exempt(obj)
    exempt[obj] = true
end

function Hide.IsExempt(obj)
    return exempt[obj] == true
end


-- Every text OnAir rewrote: what it said before and what OnAir put there. Much of the UI sets a
-- name only when it changes (meters, lists, frames), so nothing would bring the real one back:
-- when the broadcast ends, or a name or setting changes while live, the old text is put back
-- here (and masked again with the new settings) without a reload. Text its owner set again
-- since then is left alone.
local before = setmetatable({}, { __mode = "k" })
local wrote = setmetatable({}, { __mode = "k" })

local function Rewrite(obj, old, text)
    if wrote[obj] == nil then
        before[obj] = old
    end
    wrote[obj] = text
    SetQuiet(obj, text)
end

-- Its owner set new text: that's the text to put back from now on.
local function Reclaimed(obj, text)
    if wrote[obj] ~= nil and (IsSecret(text) or text ~= wrote[obj]) then
        before[obj], wrote[obj] = nil, nil
    end
end

local function PutBackOne(obj, text)
    if Usable(obj) then
        -- A label that once held hidden text may keep reporting it hidden after plain text was
        -- set; its owner setting new text would have dropped it from this list anyway.
        local now = obj:GetText()
        if IsSecret(now) or now == text then
            SetQuiet(obj, before[obj])
        end
    end
end

-- One at a time, protected: an object some addon swapped out since can't stop the rest.
local function PutBack()
    for obj, text in pairs(wrote) do
        pcall(PutBackOne, obj, text)
    end
    wipe(wrote)
    wipe(before)
end

-- Who a meter row stands for when its name is secret (combat). The row's own data says if it's you
-- (isLocalPlayer is never secret), and class + spec icon are never secret either: out of combat,
-- when names are readable, each player's class + spec is remembered with their name, so in combat
-- a row with a unique class + spec gets that name's alias (the alias of the moment: a reshuffle or
-- a new fixed alias shows at once). Two players alike: no guess.
local bySpec = {}

-- The data behind a meter row: EllesmereUI keeps it in bar._src, Blizzard on the entry itself.
local function RowSource(fs)
    local holder = fs:GetParent()
    for _ = 1, 5 do
        if not holder then
            return nil
        end
        local src = rawget(holder, "_src")
        if type(src) == "table" then
            return src
        end
        if rawget(holder, "classFilename") ~= nil or rawget(holder, "isLocalPlayer") ~= nil then
            return holder
        end
        holder = holder:GetParent()
    end
end

local function RowSourceOf(fs)
    if meterKind[fs] == "eui" then
        -- EllesmereUI's, through its row list (it attaches the data after the label: a frame later
        -- it's this redraw's). Without the list, none: the row's icons tell the rows apart.
        local row = euiRows[fs]
        local src = row and rawget(row, "_src")
        return type(src) == "table" and src or nil
    end
    return RowSource(fs)
end

local function SpecKey(src)
    local class, spec = src.classFilename, src.specIconID
    if class == nil or spec == nil or IsSecret(class) or IsSecret(spec) or class == "" then
        return nil
    end
    return class .. ":" .. tostring(spec)
end

-- Without its row list (an older EllesmereUI), a row's data is a plain table the label can't
-- reach. Its row icon (spec or class) and bar color are never secret, so they tell the rows apart:
-- label -> text frame -> bar, whose textures are the icon (and maybe a track).
-- (A meter redraws its rows many times a second in a fight: what's found per row is kept, and the
-- key is worked out again only when the row's icon changes.)
local rowTextures = setmetatable({}, WEAK)
local rowFill = setmetatable({}, WEAK)

local function RowTextures(fs)
    local list = rowTextures[fs]
    if list then
        return list, rowFill[fs]
    end
    local tf = fs:GetParent()
    local fill = tf and tf:GetParent()
    if not fill or fill:GetObjectType() ~= "StatusBar" then
        return nil
    end
    local skip = fill.GetStatusBarTexture and fill:GetStatusBarTexture()
    list = {}
    for _, region in ipairs({ fill:GetRegions() }) do
        if region ~= skip and region:GetObjectType() == "Texture" then
            list[#list + 1] = region
        end
    end
    rowTextures[fs], rowFill[fs] = list, fill
    return list, fill
end

local keySeen, keyOf = setmetatable({}, WEAK), setmetatable({}, WEAK)

-- What the key is made of, read cheaply (no strings built): each texture with its first texture
-- coordinates (class icons can share one sheet), and the bar color. Into one reused list.
local scratch = {}

local function ReadSignature(list, fill)
    local n = 0
    for i = 1, #list do
        local region = list[i]
        local ulx, uly = region:GetTexCoord()
        scratch[n + 1] = region:GetAtlas() or region:GetTexture()
        scratch[n + 2] = ulx
        scratch[n + 3] = uly
        n = n + 3
    end
    local r, g, b = fill:GetStatusBarColor()
    scratch[n + 1], scratch[n + 2], scratch[n + 3] = r, g, b
    return n + 3
end

local function BuildIconKey(list, fill)
    local parts = {}
    for _, region in ipairs(list) do
        local tex = region:GetAtlas() or region:GetTexture()
        if tex ~= nil then
            parts[#parts + 1] = tostring(tex)
            for _, v in ipairs({ region:GetTexCoord() }) do
                parts[#parts + 1] = string.format("%.2f", v)
            end
        end
    end
    if #parts == 0 then
        return nil
    end
    local r, g, b = fill:GetStatusBarColor()
    if r then
        parts[#parts + 1] = string.format("%.2f,%.2f,%.2f", r, g, b)
    end
    local key = table.concat(parts, ":")
    return not IsSecret(key) and key or nil
end

local function IconKey(fs)
    local list, fill = RowTextures(fs)
    if not list or not list[1] then
        return nil
    end
    local n = ReadSignature(list, fill)
    local seen = keySeen[fs]
    local same = seen ~= nil and seen.n == n
    for i = 1, n do
        local v = scratch[i]
        if IsSecret(v) then
            return nil
        end
        if same and seen[i] ~= v then
            same = false
        end
    end
    if not same then
        seen = seen or {}
        for i = 1, n do
            seen[i] = scratch[i]
        end
        seen.n = n
        keySeen[fs] = seen
        keyOf[fs] = BuildIconKey(list, fill) or false
    end
    return keyOf[fs] or nil
end

-- Your own spec's icon (looked up again every few seconds, not on every redraw).
local myIcon, myIconAt = nil, -10

local function MySpecIcon()
    local now = GetTime()
    if now - myIconAt > 5 then
        myIconAt = now
        local spec = GetSpecialization and GetSpecialization()
        myIcon = spec and select(4, GetSpecializationInfo(spec)) or nil
    end
    return myIcon
end

-- Your own spec's icon on the row: it's you (when OnAir hasn't learned otherwise).
local function MyIcon(fs)
    local list = RowTextures(fs)
    local icon = list and MySpecIcon()
    if not icon then
        return false
    end
    for _, region in ipairs(list) do
        local tex = region:GetTexture()
        if not IsSecret(tex) and tex == icon then
            return true
        end
    end
    return false
end

local function RowKey(fs)
    local src = RowSourceOf(fs)
    if src then
        return SpecKey(src)
    end
    -- A row from EllesmereUI's list before its data is attached: no key from its icons instead
    -- (keys from data and from icons never match each other).
    if euiRows[fs] then
        return nil
    end
    local ok, key = pcall(IconKey, fs)
    return ok and key or nil
end

local function RememberRow(fs, name)
    local key = RowKey(fs)
    if key then
        if bySpec[key] == nil or bySpec[key] == name then
            bySpec[key] = name
        else
            bySpec[key] = false
        end
    end
end

-- A meter fills a row's name before it attaches the row's data (EllesmereUI sets bar._src after
-- the label), so the row is looked at again a frame later, when the data is there. One list and
-- one frame for all rows: no timer per redraw. remember[fs] = the name it showed (plain);
-- recheck[fs] = what OnAir put there (secret name).
local remember, recheck, recheckText = setmetatable({}, WEAK), setmetatable({}, WEAK), setmetatable({}, WEAK)
local laterFrame = CreateFrame("Frame")
local RowAlias

local function RunLater()
    laterFrame:SetScript("OnUpdate", nil)
    if not OA.live then
        wipe(remember)
        wipe(recheck)
        wipe(recheckText)
        return
    end
    for fs, name in pairs(remember) do
        RememberRow(fs, name)
    end
    for fs, shown in pairs(recheck) do
        local alias = RowAlias(fs) or Names.Fill(OA.db.meterUnknown, 0)
        -- Only if the row still shows what OnAir put there (no newer name since).
        if wrote[fs] == shown and alias ~= shown then
            Rewrite(fs, recheckText[fs], alias)
        end
    end
    wipe(remember)
    wipe(recheck)
    wipe(recheckText)
end
local GuardedLater = Utils.Guard("meter row", RunLater)

local function Later()
    laterFrame:SetScript("OnUpdate", GuardedLater)
end

RowAlias = function(fs)
    local src = RowSourceOf(fs)
    if src then
        local own = src.isLocalPlayer
        if own ~= nil and not IsSecret(own) and own == true then
            return Names.MyAlias()
        end
    end
    local key = RowKey(fs)
    local known = key and bySpec[key]
    if known ~= nil then
        return known and Names.Scrub(known) or nil
    end
    local ok, mine = pcall(MyIcon, fs)
    return ok and mine and Names.MyAlias() or nil
end

-- A row whose name is secret: who it is from the row's data right away (a meter redraws its rows
-- all through a fight, and the data from the last redraw is almost always the same row), then
-- once more a frame later, when this redraw's data is attached.
local function SecretRow(fs, text)
    local shown = RowAlias(fs) or Names.Fill(OA.db.meterUnknown, 0)
    Rewrite(fs, text, shown)
    recheck[fs], recheckText[fs] = shown, text
    Later()
end

-- A meter's name label. Returns true when it was handled here.
local function MeterLabel(fs, kind, text)
    if kind == "eui" then
        if EnemyRow(fs) then
            return false
        end
        local plain = type(text) == "string" and not IsSecret(text)
        if plain then
            local out = Names.Scrub(text)
            if out ~= text then
                Rewrite(fs, text, out)
                remember[fs] = text
                Later()
            end
            -- A name OnAir learns only later (the group's roster after the row): fixed then.
            Wait(fs, out)
            return true
        end
        SecretRow(fs, text)
        return true
    end
    if kind == "blizz" or kind == "details" then
        if IsSecret(text) then
            SecretRow(fs, text)
            return true
        end
        if type(text) == "string" and text ~= "" and Where("interface") then
            local out = Names.Scrub(text)
            if out ~= text then
                Rewrite(fs, text, out)
                remember[fs] = text
                Later()
            end
            -- A name OnAir learns only later (the group's roster after the row): fixed then.
            Wait(fs, out)
            return true
        end
    end
    return false
end

local castTargets = setmetatable({}, { __mode = "k" })

local GROUP = { "player" }
for i = 1, 4 do
    GROUP[#GROUP + 1] = "party" .. i
end
for i = 1, 40 do
    GROUP[#GROUP + 1] = "raid" .. i
end

-- The alias of whoever the caster (the plate's unit) targets: you or a group member.
local function CasterTargetAlias(fs)
    local holder, plate = fs:GetParent(), nil
    for _ = 1, 3 do
        if not holder then
            break
        end
        if holder.castTarget == fs then
            plate = holder
            break
        end
        holder = holder:GetParent()
    end
    local unit = plate and (plate.unit or plate.namePlateUnitToken)
    if type(unit) ~= "string" or IsSecret(unit) then
        return nil
    end
    local target = unit .. "target"
    if not SafeBool(UnitExists, target) then
        return nil
    end
    if SafeBool(UnitIsUnit, target, "player") then
        return Names.MyAlias()
    end
    for i = 2, #GROUP do
        local member = GROUP[i]
        if SafeBool(UnitExists, member) and SafeBool(UnitIsUnit, target, member) then
            local person = Names.AddUnit(member)
            return person and person.alias or nil
        end
    end
    return nil
end

-- "always": a nameplate's cast target label (EllesmereUI, Plater). "secret": hidden only while it
-- holds a secret value - other cast target labels (EllesmereUI cast bars and Mythic+ target bars)
-- and DBM's big warnings, which carry hidden target names in instance combat.
local SECRET_FRAMES = { "DBMWarning", "DBMSpecialWarning", "DBMInfoFrame" }

local function IsCastTarget(fs)
    local name = fs.GetName and fs:GetName()
    local holder = fs:GetParent()
    for depth = 1, 3 do
        if not holder then
            break
        end
        if holder.castTarget == fs or holder.CastTarget == fs then
            return "always"
        end
        if holder.Target == fs or holder.target == fs then
            return "secret"
        end
        if depth == 1 then
            name = name or (holder.GetName and holder:GetName())
        end
        holder = holder:GetParent()
    end
    if type(name) == "string" then
        for _, prefix in ipairs(SECRET_FRAMES) do
            if name:find(prefix, 1, true) == 1 then
                return "secret"
            end
        end
    end
    return false
end

-- EllesmereUI's raid and party frames: their texts are slots you set up (name, health, level...),
-- and in instance combat the game sends names and numbers alike as secrets, so a name label can't
-- be told by its text. The button's own plan says which slots show the name (and its top name
-- bar): those are watched from their first text on, before any readable name was seen there.
-- Read from the module's registry, never written; a version without it finds nothing, and its
-- labels are learned from a readable name as before.
local euiButton = setmetatable({}, { __mode = "k" }) -- label -> its EllesmereUI button, or false

local function IsEuiNameLabel(fs)
    local button = euiButton[fs]
    if button == false then
        return false
    end
    local eui = _G.EllesmereUI
    local registry = type(eui) == "table" and eui._ModuleNS
    local ns = type(registry) == "table" and registry.EllesmereUIRaidFrames
    local buttons = type(ns) == "table" and ns._euiUnitButtons
    if type(buttons) ~= "table" or type(ns.GetFFD) ~= "function" then
        euiButton[fs] = false
        return false
    end
    if button == nil then
        button = false
        local holder = fs:GetParent()
        for _ = 1, 3 do
            if not holder then
                break
            end
            if buttons[holder] then
                button = holder
                break
            end
            holder = holder:GetParent()
        end
        euiButton[fs] = button
        if not button then
            return false
        end
    end
    local d = ns.GetFFD(button)
    if type(d) ~= "table" then
        return false
    end
    if d.topNameBarText == fs then
        return true
    end
    local slots, plan = d._tx, d._txL
    local names = type(plan) == "table" and plan.name
    if type(slots) ~= "table" or type(names) ~= "table" then
        return false
    end
    for _, slot in ipairs(names) do
        if type(slot) == "table" and slots[slot.i] == fs then
            return true
        end
    end
    return false
end

-- EllesmereUI's nameplate cast label (plate.castName, a few frames below the plate): it shows the
-- spell, and after a kick "Interrupted (Name)" while its plate is marked interrupted.
local INTERRUPTED = _G.INTERRUPTED or "Interrupted"
local castPlate = setmetatable({}, { __mode = "k" }) -- label -> its plate, or false

local function CastPlate(fs)
    local plate = castPlate[fs]
    if plate == nil then
        plate = false
        local holder = fs:GetParent()
        for _ = 1, 4 do
            if not holder then
                break
            end
            if rawget(holder, "castName") == fs then
                plate = holder
                break
            end
            holder = holder:GetParent()
        end
        castPlate[fs] = plate
    end
    return plate
end

local function ShowsInterrupter(fs)
    local plate = CastPlate(fs)
    return plate ~= false and rawget(plate, "_interrupted") == true
end

-- A line of the Guild & Communities window's chat (that window loads when it's first opened). A
-- message frame keeps its lines in a container of its own.
local function IsClubChat(fs)
    local window = _G.CommunitiesFrame
    local chat = window and window.Chat
    local lines = chat and chat.MessageFrame
    lines = lines and (lines.FontStringContainer or lines)
    return lines ~= nil and fs:GetParent() == lines
end

local function OnText(obj)
    if busy or not OA.live or exempt[obj] then
        return
    end
    -- Text boxes are left alone: changing their text can upset the box (focus, its own scripts),
    -- and you can't move while one holds the keyboard.
    if obj.GetObjectType and obj:GetObjectType() == "EditBox" then
        return
    end
    if not Usable(obj) then
        return
    end
    local text = obj:GetText()
    local secret = IsSecret(text)
    Reclaimed(obj, text)
    local label = npcLabel[obj]
    if label then
        if IsSecret(text) or text ~= label then
            Rewrite(obj, text, label)
        end
        return
    end
    -- A nameplate's cast target (EllesmereUI, Plater: a "castTarget" label next to the cast):
    -- always someone in your group or you, and plates come and go from pools, so it's hidden
    -- the moment it gets text, on any plate.
    if Where("nameplates") then
        local cast = castTargets[obj]
        if cast == nil then
            local ok, result = pcall(IsCastTarget, obj)
            cast = ok and result or false
            castTargets[obj] = cast
        end
        if cast == "always" then
            -- The game always gives the cast target's name as a secret: it can't be read. Who the
            -- caster targets can be asked, though: you or someone in your group shows as their
            -- alias (usually the spell's target too). Anyone else: hidden.
            local plain = type(text) == "string" and not IsSecret(text)
            if plain and text == "" then
                Mute(obj, "tot", false)
                return
            end
            local alias = plain and Names.Scrub(text) ~= text and Names.Scrub(text) or CasterTargetAlias(obj)
            if alias then
                Mute(obj, "tot", false)
                Rewrite(obj, text, alias)
            else
                Mute(obj, "tot", true)
            end
            return
        elseif cast == "secret" then
            Mute(obj, "secret", IsSecret(obj:GetText()))
        end
        -- EllesmereUI's cast bar after a kick: "Interrupted (Name)", the name being whoever
        -- interrupted. In instance combat that name is a secret and can't be swapped, so while the
        -- plate shows it, the label reads only "Interrupted".
        if secret and ShowsInterrupter(obj) then
            Rewrite(obj, text, INTERRUPTED)
            return
        end
    end
    if Where("meters") then
        local kind = meterKind[obj]
        if kind == nil then
            local ok, result = pcall(Classify, obj)
            kind = ok and result or false
            meterKind[obj] = kind
        end
        if kind and MeterLabel(obj, kind, text) then
            return
        end
    end
    if secret and not guard[obj] and IsEuiNameLabel(obj) then
        guard[obj] = true
    end
    if guard[obj] then
        Mute(obj, "secret", secret)
    end
    if type(text) == "string" and not secret then
        -- The message of the day: a switch of its own, whatever the others say.
        if Where("guildMotd") then
            local out = Names.HideMotd(text)
            if out then
                if out ~= text then
                    Rewrite(obj, text, out)
                end
                return
            end
        end
        -- The guild window's chat: its messages have a switch of their own (see Names.ScrubClubLine).
        if text:find("|K", 1, true) and IsClubChat(obj) then
            local out = Names.ScrubClubLine(text, Where("guildChat"), Where("interface"))
            if out ~= text then
                Rewrite(obj, text, out)
            end
            Wait(obj, out)
            return
        end
    end
    if not Where("interface") or type(text) ~= "string" or secret or text == "" then
        return
    end
    -- Numbers, timers, bars: no name in there (most of what the UI sets, many times a second).
    if not text:find("[%a\128-\255]") then
        return
    end
    -- A note on a friend or guild member: emptied (it's put back when the broadcast ends).
    if Names.IsNote(text) then
        Rewrite(obj, text, "")
        return
    end
    local out = Names.Scrub(text)
    if out ~= text then
        Rewrite(obj, text, out)
        -- It showed a player's name: any frame's, also other addons' (raid frames, meters). In
        -- combat in an instance the game sends it names as secrets, which can't be replaced, so
        -- from now on a secret here is hidden until readable text comes back. Not a nameplate's
        -- cast label: the name there was the interrupter's, and its secrets are spell names.
        if not CastPlate(obj) then
            guard[obj] = true
        end
    end
    Wait(obj, out)
end
local GuardedText = Utils.Guard("text", OnText)
Hide.OnText = GuardedText

-- The guild's message of the day. The game keeps it from addons in dungeons, raids, boss fights,
-- Mythic+ and PvP matches: reading it there (C_GuildInfo.GetMOTD) is a blocked action, which the
-- game reports even inside pcall. So OnAir keeps a copy: the game's GUILD_MOTD event brings each
-- new message, the Guild Info tab shows it, and the game is asked only while nothing is restricted.
local motdText -- the message as plain text; nil: none set
local motdKnown = false -- motdText is the message as it stands

-- True while the game restricts addons, so reading the message would be blocked.
local function Restricted()
    if InCombatLockdown() then
        return true
    end
    local chat = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if chat then
        local ok, locked = pcall(chat)
        if not ok or IsSecret(locked) or locked then
            return true
        end
    end
    local actions = C_RestrictedActions
    local kinds = Enum.AddOnRestrictionType
    local inactive = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive
    if actions and actions.GetAddOnRestrictionState and kinds and inactive then
        for _, kind in pairs(kinds) do
            if type(kind) == "number" then
                local ok, state = pcall(actions.GetAddOnRestrictionState, kind)
                if not ok or IsSecret(state) or state ~= inactive then
                    return true
                end
            end
        end
    end
    return false
end

-- A message seen as plain text is kept; false: a secret, so it can't be read here.
local function KeepMotd(text)
    if type(text) ~= "string" or IsSecret(text) then
        return false
    end
    motdText = text ~= "" and text or nil
    motdKnown = true
    return true
end

-- The guild's message of the day as plain text, or nil (none set). Until the game can be asked
-- again, the last one known.
local function GuildMotd()
    if not motdKnown and not Restricted() then
        local get = C_GuildInfo and C_GuildInfo.GetMOTD or _G.GetGuildRosterMOTD
        if type(get) ~= "function" then
            KeepMotd("")
        else
            local ok, text = pcall(get)
            if ok then
                KeepMotd(text)
            end
        end
    end
    return motdText
end
Hide.GuildMotd = GuildMotd

-- Each new message, from the game. In those places it comes as a secret: it's read later.
local motdWatch = CreateFrame("Frame")
motdWatch:RegisterEvent("GUILD_MOTD")
motdWatch:SetScript("OnEvent", Utils.Guard("guild message", function(_, _, text)
    if not KeepMotd(text) then
        motdKnown = false
    end
end))

-- The message of the day in the Guild Info tab: a SimpleHTML, not a label, so it has a hook of its
-- own. Its text can't be read back: what's put back is the kept copy of the message.
local boxChanged = false

local function MotdBox()
    local info = _G.CommunitiesFrameGuildDetailsFrameInfo
    local scroll = info and info.MOTDScrollFrame
    return scroll and scroll.MOTD
end

-- As the game sets it: `true` shows the text as it is, no markup.
local function SetBox(box, text)
    busy = true
    pcall(box.SetText, box, text, true)
    busy = false
end

-- What the box shows in place of the game's text; nil: that text as it is. Hidden, or with the switch
-- off, names swapped as everywhere else. An empty box stays empty.
local function BoxShows(text)
    if Where("guildMotd") then
        if IsSecret(text) or (type(text) == "string" and text ~= "") then
            return L["(hidden)"]
        end
    elseif Where("interface") and type(text) == "string" and not IsSecret(text) then
        local out = Names.Scrub(text)
        if out ~= text then
            return out
        end
    end
    return nil
end

local function OnBoxText(box, text)
    if busy or box ~= MotdBox() then
        return
    end
    -- The game puts the message as it stands in here (also where addons can't ask for it).
    KeepMotd(text)
    local out = BoxShows(text)
    if out then
        SetBox(box, out)
    end
    boxChanged = out ~= nil
end

-- Going live, the broadcast ending, a setting changing: the box as it should be now. A message
-- not known yet is hidden whatever it says, and isn't put back: the game sets the box again (its
-- next message, or the Guild Info tab shown again).
local function UpdateMotdBox()
    -- First, so the copy is there for tooltips before any window is opened.
    local real = GuildMotd()
    local box = MotdBox()
    if not box then
        return
    end
    local out
    if motdKnown then
        out = BoxShows(real)
    elseif Where("guildMotd") then
        out = L["(hidden)"]
    end
    if out then
        SetBox(box, out)
        boxChanged = true
    elseif boxChanged and motdKnown then
        boxChanged = false
        SetBox(box, real or "")
    end
end
local GuardedMotdBox = Utils.Guard("guild message", UpdateMotdBox)

-- For /onair check.
function Hide.MotdState()
    if not Where("guildMotd") then
        return L["switch off"]
    end
    local text = GuildMotd()
    if not motdKnown then
        return L["unknown for now (the game keeps it from addons in instances and fights)"]
    end
    if not text then
        return L["none set"]
    end
    if not MotdBox() then
        return L["Guild Info tab not opened yet"]
    end
    return boxChanged and L["hidden in the Guild Info tab"] or L["SHOWING in the Guild Info tab"]
end

local textHooked = false

local function HookText()
    if textHooked then
        return
    end
    textHooked = true
    local fsMeta = getmetatable(UIParent:CreateFontString()).__index
    hooksecurefunc(fsMeta, "SetText", GuardedText)
    hooksecurefunc(fsMeta, "SetFormattedText", GuardedText)
    local buttonMeta = getmetatable(CreateFrame("Button")).__index
    hooksecurefunc(buttonMeta, "SetText", GuardedText)
    hooksecurefunc(buttonMeta, "SetFormattedText", GuardedText)
    -- Protected: a game without this kind of frame can't stop the rest of going live.
    local ok, html = pcall(CreateFrame, "SimpleHTML")
    if ok and html then
        hooksecurefunc(getmetatable(html).__index, "SetText", Utils.Guard("guild message", OnBoxText))
    end
end

-- A new name came in: what's on screen may hold it already. Runs once per frame at most.
Hide.Rescrub = Utils.Debouncer(function()
    if not OA.live then
        return
    end
    if Hide.RefreshTooltip then
        Hide.RefreshTooltip()
    end
    -- Older text that holds a name learned only now (a guild message set before the roster
    -- arrived): exactly those labels, looked up by the word.
    for _, word in ipairs(Names.TakeNewWords()) do
        local holders = waiting[word]
        if holders then
            waiting[word] = nil
            waitingCount = waitingCount - 1
            for obj in pairs(holders) do
                if Usable(obj) then
                    GuardedText(obj)
                end
            end
        end
    end
    -- A note learned now (rosters are read a slice at a time): a label could hold it whole, and a
    -- note isn't a word to look up, so the screen is looked over again (a slice per frame).
    if Names.TakeNotesNew() then
        Hide.SweepUI()
    end
end, 0.05)

---------------------------------------------------------------------------------------------- tooltips

-- A unit whose name gives a player away: a player, or something a player controls (pets,
-- guardians, totems carry their owner's name or one the owner chose).
local function Owned(unit)
    if type(unit) ~= "string" or not SafeBool(UnitExists, unit) then
        return false
    end
    return SafeBool(UnitPlayerControlled, unit) == true and SafeBool(UnitIsPlayer, unit) ~= true
end

local function IsPlayer(unit)
    return type(unit) == "string" and SafeBool(UnitExists, unit) and SafeBool(UnitIsPlayer, unit) == true
end

local function ScrubTooltip(tooltip)
    if not OA.live or not tooltip or not Usable(tooltip) then
        return
    end
    -- The message of the day has a switch of its own (two of the guild window's tooltips show it).
    local names = Where("tooltips")
    local motd = Where("guildMotd") and GuildMotd()
    if not names and not motd then
        return
    end
    -- Every line it holds: also the unnamed tooltips some addons make (Premade Groups Filter).
    for _, fs in ipairs({ tooltip:GetRegions() }) do
        if fs.GetObjectType and fs:GetObjectType() == "FontString" then
            local text = fs:GetText()
            if type(text) == "string" and not IsSecret(text) and text ~= "" then
                local out = motd and Names.HideMotdText(text, motd) or text
                if names then
                    out = Names.Scrub(out)
                end
                if out ~= text then
                    SetQuiet(fs, out)
                end
            end
        end
    end
end

local function OnUnitTooltip(tooltip)
    if not OA.live or not tooltip.GetUnit then
        return
    end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if ok and type(unit) == "string" and not IsSecret(unit) then
        OA.Collect.Unit(unit)
        -- The "Targeting:" line some tooltips add.
        OA.Collect.Unit(unit .. "target")
        local mode = OA.db.npc.mode
        if mode ~= "real" and Where("tooltips") and SafeBool(UnitExists, unit)
            and not SafeBool(UnitPlayerControlled, unit) then
            local first = tooltip.GetName and _G[tooltip:GetName() .. "TextLeft1"]
            if first then
                SetQuiet(first, mode == "generic" and Hide.NpcLabel(unit) or "")
            end
        end
        -- A pet or minion: its name reads "<owner>'s Pet", and the owner on the line under it
        -- ("Jennie's Minion") is learned, so that line reads their alias. A stranger's pet name
        -- itself isn't learned as a word: a hunter's "Shadow" would eat every "Shadow Bolt".
        if Where("tooltips") and OA.db.who.pets ~= false and Owned(unit) then
            local name = tooltip.GetName and tooltip:GetName()
            local first = name and _G[name .. "TextLeft1"]
            local second = name and _G[name .. "TextLeft2"]
            if first then
                SetQuiet(first, Names.PetLabel(Names.OwnerIn(second and second:GetText())))
            end
        end
    end
    ScrubTooltip(tooltip)
end

function Hide.RefreshTooltip()
    if GameTooltip and GameTooltip:IsShown() then
        ScrubTooltip(GameTooltip)
    end
end

local tooltipHooked = false

local function HookTooltips()
    if tooltipHooked then
        return
    end
    tooltipHooked = true
    local scrub = Utils.Guard("tooltip", ScrubTooltip)
    local meta = getmetatable(GameTooltip).__index
    hooksecurefunc(meta, "Show", scrub)
    local TDP = TooltipDataProcessor
    if TDP and TDP.AddTooltipPostCall and Enum.TooltipDataType then
        TDP.AddTooltipPostCall(Enum.TooltipDataType.Unit, Utils.Guard("unit tooltip", OnUnitTooltip))
        if TDP.AllTypes then
            TDP.AddTooltipPostCall(TDP.AllTypes, scrub)
        end
    end
end

---------------------------------------------------------------------------------------------- units


-- One name FontString showing `unit`: guarded for a player, hidden for a pet, and for an NPC
-- whatever the NPC setting says (its real name, a generic label, or nothing).
local function NameFor(fs, unit, alwaysHide)
    if type(fs) ~= "table" then
        return
    end
    local player = IsPlayer(unit)
    local owned = Owned(unit)
    guard[fs] = player or nil
    Mute(fs, "pet", OA.db.who.pets ~= false and owned)
    Mute(fs, "tot", alwaysHide == true)
    local npc = not player and not owned and type(unit) == "string" and SafeBool(UnitExists, unit) == true
    local mode = npc and OA.db.npc.mode or "real"
    Mute(fs, "npc", mode == "hide")
    if mode == "generic" then
        npcLabel[fs] = Hide.NpcLabel(unit)
        Rewrite(fs, fs:GetText(), npcLabel[fs])
    else
        npcLabel[fs] = nil
    end
    local text = fs:GetText()
    Mute(fs, "secret", player and IsSecret(text))
    if player then
        GuardedText(fs)
    end
end

-- A unit frame's name labels (Blizzard's and EllesmereUI's keep them under these names).
local function UnitFrameNames(frame, unit, alwaysHide)
    if not frame then
        return
    end
    NameFor(frame.name, unit, alwaysHide)
    NameFor(frame.Name, unit, alwaysHide)
    NameFor(frame.NameText, unit, alwaysHide)
    local global = frame.GetName and frame:GetName()
    if global then
        NameFor(_G[global .. "Name"], unit, alwaysHide)
        NameFor(_G[global .. "TextName"], unit, alwaysHide)
    end
    local content = frame.TargetFrameContent
    if content and content.TargetFrameContentMain then
        NameFor(content.TargetFrameContentMain.Name, unit, alwaysHide)
    end
end

-- Target-of-target names are hidden outright (they move too fast to follow, and a boss's target
-- is always someone in your group).
local function TargetTargetNames()
    UnitFrameNames(_G.TargetFrameToT, "targettarget", true)
    UnitFrameNames(_G.EllesmereUIUnitFrames_TargetTarget, "targettarget", true)
end

local function FocusTargetNames()
    UnitFrameNames(_G.FocusFrameToT, "focustarget", true)
    UnitFrameNames(_G.EllesmereUIUnitFrames_FocusTarget, "focustarget", true)
end

local UNIT_GROUPS = {
    player = function()
        UnitFrameNames(_G.PlayerFrame, "player")
        NameFor(_G.PlayerName, "player")
        UnitFrameNames(_G.EllesmereUIUnitFrames_Player, "player")
    end,
    pet = function()
        UnitFrameNames(_G.PetFrame, "pet")
        NameFor(_G.PetName, "pet")
        UnitFrameNames(_G.EllesmereUIUnitFrames_Pet, "pet")
    end,
    target = function()
        UnitFrameNames(_G.TargetFrame, "target")
        UnitFrameNames(_G.EllesmereUIUnitFrames_Target, "target")
        TargetTargetNames()
    end,
    focus = function()
        UnitFrameNames(_G.FocusFrame, "focus")
        UnitFrameNames(_G.EllesmereUIUnitFrames_Focus, "focus")
        FocusTargetNames()
    end,
    targettarget = TargetTargetNames,
    focustarget = FocusTargetNames,
    group = function()
        local party = _G.PartyFrame
        if not party then
            return
        end
        if party.PartyMemberFramePool then
            for member in party.PartyMemberFramePool:EnumerateActive() do
                UnitFrameNames(member, member.unit)
            end
        end
        for i = 1, 4 do
            local member = party["MemberFrame" .. i]
            if member then
                UnitFrameNames(member, member.unit or ("party" .. i))
            end
        end
    end,
}
local UNIT_ORDER = { "player", "pet", "target", "focus", "group" }

-- All unit frames, or one group of them ("target" also does its target-of-target).
function Hide.UnitFrames(which)
    if not Where("interface") then
        return
    end
    if which then
        local fn = UNIT_GROUPS[which]
        if fn then
            fn()
        end
        return
    end
    for _, key in ipairs(UNIT_ORDER) do
        UNIT_GROUPS[key]()
    end
end

---------------------------------------------------------------------------------------------- nameplates

local function PlateNames(plate, unit)
    NameFor(plate.name, plate.unit or unit)
    -- Who a cast targets: always someone in your group or you.
    if plate.castTarget then
        GuardedText(plate.castTarget)
    end
end

-- Every EllesmereUI plate (going live).
local function EllesmerePlates()
    local ns = _G.EllesmereNameplates_NS
    if not ns then
        return
    end
    for _, list in ipairs({ ns.plates, ns.friendlyPlates }) do
        if type(list) == "table" then
            for unit, plate in pairs(list) do
                if type(plate) == "table" then
                    PlateNames(plate, unit)
                end
            end
        end
    end
end

-- Plates that just came (a city fills dozens in a moment): EllesmereUI keeps them by unit, so
-- only those are looked at, once, on the next frame (it builds its plate on the same event).
local platesDue = {}
local platesQueued = false

local function DuePlates()
    platesQueued = false
    local ns = _G.EllesmereNameplates_NS
    if ns then
        local hostile = type(ns.plates) == "table" and ns.plates or nil
        local friendly = type(ns.friendlyPlates) == "table" and ns.friendlyPlates or nil
        for unit in pairs(platesDue) do
            local plate = (hostile and hostile[unit]) or (friendly and friendly[unit])
            if type(plate) == "table" then
                PlateNames(plate, unit)
            end
        end
    end
    wipe(platesDue)
end
local GuardedDuePlates = Utils.Guard("plates", DuePlates)

function Hide.NamePlate(unit)
    if not Where("nameplates") then
        return
    end
    -- Learned before its name is looked at: the plate shows the alias from its first frame.
    OA.Collect.Unit(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate and Usable(plate) then
        if plate.UnitFrame then
            UnitFrameNames(plate.UnitFrame, unit)
        end
        -- Plater: its own unit frame (lower-case) and the name-only plate's text.
        local plater = plate.unitFrame
        if plater and plater ~= plate.UnitFrame then
            NameFor(plater.healthBar and plater.healthBar.unitName, unit)
            NameFor(plate.ActorNameSpecial, unit)
        end
    end
    platesDue[unit] = true
    if not platesQueued then
        platesQueued = true
        C_Timer.After(0, GuardedDuePlates)
    end
end

function Hide.AllNamePlates()
    if not Where("nameplates") then
        return
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        if plate.namePlateUnitToken then
            Hide.NamePlate(plate.namePlateUnitToken)
        end
    end
    EllesmerePlates()
end

---------------------------------------------------------------------------------------------- meters on screen

-- Meters already on screen: a row shows a name until it changes, so going live looks at every
-- label once (Blizzard's meter and EllesmereUI's; Details! redraws its bars by itself).
local function Sweep(frame, depth)
    if not frame or depth > 9 or not Usable(frame) then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            GuardedText(region)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        pcall(Sweep, child, depth + 1)
    end
end

-- EllesmereUI's meter sets a name only when it changes, and after a fight the label can keep a
-- name OnAir can't read back: asking it to set every name again is the only sure way to show the
-- right one (masked while live, the real one after).
local function RedrawMeterNames()
    local modules = _G.EllesmereUI and _G.EllesmereUI._ModuleNS
    local dm = type(modules) == "table" and modules.EllesmereUIDamageMeters
    if type(dm) == "table" and type(dm.RefreshNames) == "function" then
        pcall(dm.RefreshNames)
    end
end

function Hide.Meters()
    if not Where("meters") then
        return
    end
    RedrawMeterNames()
    Sweep(_G.DamageMeter, 1)
    for i = 1, 8 do
        Sweep(_G["EllesmereUIDMFrame" .. i], 1)
    end
end

-- The whole UI, once, closed windows too: much text is set before going live and never again
-- (the friends window's BattleTag is set at login; raid frames, other addons' frames), so it
-- would show real names until it changes. A few hundred frames per frame, so going live doesn't
-- hitch.
local queue = {}
local sweeper = CreateFrame("Frame")
local SWEEP_BUDGET = 4 -- milliseconds per frame

local function SweepFrame(frame)
    if not Usable(frame) then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            GuardedText(region)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        queue[#queue + 1] = child
    end
end

local function SweepStep()
    local start = Utils.Clock()
    repeat
        local frame = table.remove(queue)
        if not frame or not OA.live then
            wipe(queue)
            sweeper:SetScript("OnUpdate", nil)
            return
        end
        -- One frame at a time, protected: an odd frame can't stop the rest.
        pcall(SweepFrame, frame)
    until Utils.Clock() - start >= SWEEP_BUDGET
end

function Hide.SweepUI()
    if not OA.live then
        return
    end
    wipe(queue)
    queue[1] = UIParent
    sweeper:SetScript("OnUpdate", Utils.Guard("sweep", SweepStep))
end

-- A name or a setting changed while live: the old text back, then masked again.
function Hide.Redo()
    PutBack()
    GuardedMotdBox()
    if OA.live then
        Hide.Meters()
        Hide.SweepUI()
        if Hide.RefreshTooltip then
            Hide.RefreshTooltip()
        end
    end
end

---------------------------------------------------------------------------------------------- start

local hooksDone = false

local function HookFrames()
    if hooksDone then
        return
    end
    hooksDone = true
    if type(CompactUnitFrame_UpdateName) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateName", Utils.Guard("raid frames", function(frame)
            if OA.live and frame and frame.name and Usable(frame) then
                NameFor(frame.name, frame.displayedUnit or frame.unit)
            end
        end))
    end
    if PartyMemberFrameMixin and PartyMemberFrameMixin.Setup then
        hooksecurefunc(PartyMemberFrameMixin, "Setup", Utils.Guard("party frames", function(frame)
            if OA.live then
                UnitFrameNames(frame, frame.unit)
            end
        end))
    end
end

function Hide.Start()
    HookText()
    HookTooltips()
    HookFrames()
    Hide.ApplyCVars()
    Hide.UnitFrames()
    Hide.AllNamePlates()
    Utils.Guard("meters", Hide.Meters)()
    Hide.SweepUI()
    GuardedMotdBox()
    -- EllesmereUI frames can spawn after us, and its unit frames cache names: ask for a repaint.
    C_Timer.After(2, function()
        if OA.live then
            Hide.UnitFrames()
            Hide.AllNamePlates()
            Utils.Guard("meters", Hide.Meters)()
            if type(_G._EUF_RefreshUnitNames) == "function" then
                pcall(_G._EUF_RefreshUnitNames)
            end
        end
    end)
end

-- Off the air: everything OnAir rewrote shows its own text again, no reload needed.
function Hide.Stop()
    wipe(queue)
    sweeper:SetScript("OnUpdate", nil)
    wipe(npcLabel)
    wipe(waiting)
    wipe(waitedOn)
    wipe(platesDue)
    waitingCount = 0
    Utils.Guard("put back", PutBack)()
    GuardedMotdBox()
    RedrawMeterNames()
    Hide.RestoreCVars()
    Hide.UnmuteAll()
end

-- Units changed: refresh the frames that show them ("target", "focus", "targettarget", ...).
function Hide.OnUnitChanged(which)
    if OA.live then
        Hide.UnitFrames(which)
    end
end

-- For /onair check: what OnAir thinks of a label (to see why one wasn't hidden).
function Hide.Explain(obj)
    local parts = {}
    local cast = castTargets[obj]
    if cast ~= nil then
        parts[#parts + 1] = "cast=" .. tostring(cast)
    end
    if guard[obj] then
        parts[#parts + 1] = "watched"
    end
    for reason in pairs(reasons[obj] or {}) do
        parts[#parts + 1] = "muted:" .. reason
    end
    -- In EllesmereUI's meter row list: a row's name, or its rank or amount.
    if euiRows[obj] ~= nil then
        parts[#parts + 1] = "list=" .. (euiRows[obj] and "name" or "other")
    end
    if meterKind[obj] then
        parts[#parts + 1] = "meter=" .. tostring(meterKind[obj])
        -- What the row's data says (to see why a row isn't recognized).
        local src = RowSourceOf(obj)
        if not src then
            local key = RowKey(obj)
            parts[#parts + 1] = "icon=" .. (key and "yes" or "none")
            parts[#parts + 1] = "known=" .. (key and bySpec[key] and "yes" or "no")
            local ok, mine = pcall(MyIcon, obj)
            parts[#parts + 1] = "mine=" .. tostring(ok and mine)
        else
            local own = src.isLocalPlayer
            parts[#parts + 1] = "own=" .. (own == nil and "nil" or (IsSecret(own) and "secret" or tostring(own)))
            local class, spec = src.classFilename, src.specIconID
            parts[#parts + 1] = "class=" .. (class == nil and "nil" or (IsSecret(class) and "secret" or tostring(class)))
            parts[#parts + 1] = "spec=" .. (spec == nil and "nil" or (IsSecret(spec) and "secret" or tostring(spec)))
            local key = SpecKey(src)
            parts[#parts + 1] = "known=" .. (key and bySpec[key] and "yes" or "no")
            local keys = {}
            for k in pairs(src) do
                if type(k) == "string" and #keys < 12 then
                    keys[#keys + 1] = k
                end
            end
            parts[#parts + 1] = "fields=" .. table.concat(keys, ",")
        end
    end
    return #parts > 0 and table.concat(parts, " ") or "untouched"
end
