local _, OA = ...

-- Where names get replaced or hidden on screen.
--
-- 1. Interface text: every FontString and Button text set from Lua goes through Scrub(). That
--    covers Blizzard's and other addons' frames alike: unit and raid frames, the character window,
--    friends, guild, communities, group finder, mail, scoreboard, popups.
-- 2. Names the game keeps secret (combat, instances) can't be read, so they can't be replaced:
--    those FontStrings are hidden instead, while they hold a secret player name.
-- 3. Overhead names: the game's own CVars, saved before going live and restored after.
-- 4. Tooltips, nameplates and damage meters get their own handling below.
OA.Hide = {}

local Hide = OA.Hide
local Names = OA.Names
local Utils = OA.Utils
local IsSecret = Utils.IsSecret
local SafeBool = Names.SafeBool

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

local function CVarsWanted()
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
                wanted[cvar] = true
            end
        end
    end
    return wanted
end

-- Overhead names off for what's hidden. The values from before are kept in the saved variables,
-- so a crash or a disconnect while live still restores them on the next login.
function Hide.ApplyCVars()
    if InCombatLockdown() then
        pendingCVars = "apply"
        return
    end
    local db = OA.db
    db.savedCVars = db.savedCVars or {}
    for cvar in pairs(CVarsWanted()) do
        local value = C_CVar.GetCVar(cvar)
        if value ~= nil then
            if db.savedCVars[cvar] == nil then
                db.savedCVars[cvar] = value
            end
            pcall(C_CVar.SetCVar, cvar, "0")
        end
    end
end

function Hide.RestoreCVars()
    if InCombatLockdown() then
        pendingCVars = "restore"
        return
    end
    local db = OA.db
    for cvar, value in pairs(db.savedCVars or {}) do
        pcall(C_CVar.SetCVar, cvar, value)
    end
    db.savedCVars = nil
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
            if Hidden(self) and alpha ~= 0 and not IsSecret(alpha) then
                pcall(self.SetAlpha, self, 0)
            end
        end)
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
    if now and not was then
        fs:SetAlpha(0)
    elseif was and not now then
        fs:SetAlpha(1)
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
--  EllesmereUI: EllesmereUIDMFrameN > row > fill > text frame, where a player row's label is
--   anchored to the rank text on its left (spell rows have no rank).
--  Blizzard: an ancestor named DamageMeter*, the FontString kept under a "name"-like key.
local meterKind = setmetatable({}, { __mode = "k" })

local function NamedAncestor(frame, prefix, depth)
    for _ = 1, depth do
        if not frame then
            return nil
        end
        local name = frame.GetName and frame:GetName()
        if name and name:find(prefix, 1, true) == 1 then
            return frame
        end
        frame = frame:GetParent()
    end
    return nil
end

local function Classify(fs)
    local holder = fs:GetParent()
    if not holder then
        return false
    end
    if NamedAncestor(holder, "EllesmereUIDMFrame", 8) then
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
    if NamedAncestor(holder, "DetailsBarra_", 4) then
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
    if NamedAncestor(holder, "DamageMeter", 10) then
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
local RING_SIZE = 600
local ring, ringPos = {}, 0

local function Remember(obj)
    ringPos = ringPos % RING_SIZE + 1
    ring[ringPos] = obj
end

-- Words left as they were (no name OnAir knows yet) -> the labels holding them. When one of them
-- turns out to be a name, only those labels are looked at again: no sweeping the whole UI.
local waiting = {}

local function Wait(obj, text)
    for word in text:gmatch("[%a\128-\255][%w\128-\255'%-]*") do
        local first = word:byte(1)
        -- Names start with a capital (or a letter outside plain ASCII).
        if #word >= 2 and (first >= 128 or (first >= 65 and first <= 90)) then
            local holders = waiting[word]
            if not holders then
                holders = setmetatable({}, { __mode = "k" })
                waiting[word] = holders
            end
            holders[obj] = true
            -- "Name-Realm": the name alone may be what gets learned.
            local short = word:match("^(.-)%-")
            if short and #short >= 2 then
                local list = waiting[short] or setmetatable({}, { __mode = "k" })
                waiting[short] = list
                list[obj] = true
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
        local now = obj:GetText()
        if not IsSecret(now) and now == text then
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
            end
            return true
        end
        Rewrite(fs, text, Names.Fill(OA.db.meterUnknown, 0))
        return true
    end
    if kind == "blizz" or kind == "details" then
        if IsSecret(text) then
            Rewrite(fs, text, Names.Fill(OA.db.meterUnknown, 0))
            return true
        end
        if type(text) == "string" and text ~= "" and Where("interface") then
            local out = Names.Scrub(text)
            if out ~= text then
                Rewrite(fs, text, out)
            end
            return true
        end
    end
    return false
end

local castTargets = setmetatable({}, { __mode = "k" })

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
            Mute(obj, "tot", true)
            return
        elseif cast == "secret" then
            Mute(obj, "secret", IsSecret(obj:GetText()))
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
    if guard[obj] then
        Mute(obj, "secret", IsSecret(text))
    end
    if not Where("interface") or type(text) ~= "string" or IsSecret(text) or text == "" then
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
        -- from now on a secret here is hidden until readable text comes back.
        guard[obj] = true
    end
    Wait(obj, out)
    Remember(obj)
end
local GuardedText = Utils.Guard("text", OnText)
Hide.OnText = GuardedText

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

end

-- A new name came in: what's on screen may hold it already. Runs once per frame at most.
Hide.Rescrub = Utils.Debouncer(function()
    if not OA.live then
        return
    end
    for i = 1, RING_SIZE do
        local obj = ring[i]
        if obj and Usable(obj) and Visible(obj) then
            GuardedText(obj)
        end
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
            for obj in pairs(holders) do
                if Usable(obj) then
                    GuardedText(obj)
                end
            end
        end
    end
end, 0.05)

---------------------------------------------------------------------------------------------- tooltips

local function ScrubTooltip(tooltip)
    if not Where("tooltips") or not tooltip or not Usable(tooltip) then
        return
    end
    -- Every line it holds: also the unnamed tooltips some addons make (Premade Groups Filter).
    for _, fs in ipairs({ tooltip:GetRegions() }) do
        if fs.GetObjectType and fs:GetObjectType() == "FontString" then
            local text = fs:GetText()
            if type(text) == "string" and not IsSecret(text) and text ~= "" then
                local out = Names.Scrub(text)
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

local function FrameNames(frame)
    if not frame then
        return {}
    end
    local list = { frame.name, frame.Name, frame.NameText }
    local global = frame.GetName and frame:GetName()
    if global then
        list[#list + 1] = _G[global .. "Name"]
        list[#list + 1] = _G[global .. "TextName"]
    end
    local content = frame.TargetFrameContent
    if content and content.TargetFrameContentMain then
        list[#list + 1] = content.TargetFrameContentMain.Name
    end
    return list
end

local function UnitFrameNames(frame, unit, alwaysHide)
    for _, fs in ipairs(FrameNames(frame)) do
        NameFor(fs, unit, alwaysHide)
    end
end

-- Target-of-target names are hidden outright (they move too fast to follow, and a boss's target
-- is always someone in your group).
function Hide.UnitFrames()
    if not Where("interface") then
        return
    end
    UnitFrameNames(_G.PlayerFrame, "player")
    NameFor(_G.PlayerName, "player")
    UnitFrameNames(_G.PetFrame, "pet")
    NameFor(_G.PetName, "pet")
    UnitFrameNames(_G.TargetFrame, "target")
    UnitFrameNames(_G.FocusFrame, "focus")
    UnitFrameNames(_G.TargetFrameToT, "targettarget", true)
    UnitFrameNames(_G.FocusFrameToT, "focustarget", true)
    -- EllesmereUI unit frames
    UnitFrameNames(_G.EllesmereUIUnitFrames_Player, "player")
    UnitFrameNames(_G.EllesmereUIUnitFrames_Pet, "pet")
    UnitFrameNames(_G.EllesmereUIUnitFrames_Target, "target")
    UnitFrameNames(_G.EllesmereUIUnitFrames_Focus, "focus")
    UnitFrameNames(_G.EllesmereUIUnitFrames_TargetTarget, "targettarget", true)
    UnitFrameNames(_G.EllesmereUIUnitFrames_FocusTarget, "focustarget", true)
    local party = _G.PartyFrame
    if party then
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
    end
end

---------------------------------------------------------------------------------------------- nameplates

local GuardedPlates

local function EllesmerePlates()
    local ns = _G.EllesmereNameplates_NS
    if not ns then
        return
    end
    for _, list in ipairs({ ns.plates, ns.friendlyPlates }) do
        if type(list) == "table" then
            for unit, plate in pairs(list) do
                if type(plate) == "table" then
                    NameFor(plate.name, plate.unit or unit)
                    -- Who a cast targets: always someone in your group or you.
                    Mute(plate.castTarget, "tot", true)
                end
            end
        end
    end
end

GuardedPlates = Utils.Guard("plates", EllesmerePlates)

function Hide.NamePlate(unit)
    if not Where("nameplates") then
        return
    end
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
    -- EllesmereUI builds its plate on the same event: look a frame later.
    C_Timer.After(0, GuardedPlates)
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

function Hide.Meters()
    if not Where("meters") then
        return
    end
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
local SWEEP_STEP = 300

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
    for _ = 1, SWEEP_STEP do
        local frame = table.remove(queue)
        if not frame or not OA.live then
            wipe(queue)
            sweeper:SetScript("OnUpdate", nil)
            return
        end
        -- One frame at a time, protected: an odd frame can't stop the rest.
        pcall(SweepFrame, frame)
    end
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
    Utils.Guard("put back", PutBack)()
    Hide.RestoreCVars()
    Hide.UnmuteAll()
end

-- Units changed: refresh the frames that show them.
function Hide.OnUnitChanged()
    if OA.live then
        Hide.UnitFrames()
    end
end
