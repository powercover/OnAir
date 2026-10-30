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
                SetQuiet(fs, out)
            end
            return true
        end
        SetQuiet(fs, Names.Fill(OA.db.meterUnknown, 0))
        return true
    end
    if (kind == "blizz" or kind == "details") and IsSecret(text) then
        SetQuiet(fs, Names.Fill(OA.db.meterUnknown, 0))
        return true
    end
    return false
end

local function OnText(obj)
    if busy or not OA.live or exempt[obj] then
        return
    end
    if obj.IsForbidden and obj:IsForbidden() then
        return
    end
    local text = obj:GetText()
    local label = npcLabel[obj]
    if label then
        if IsSecret(text) or text ~= label then
            SetQuiet(obj, label)
        end
        return
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
    local out = Names.Scrub(text)
    if out ~= text then
        SetQuiet(obj, out)
    end
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
        if obj and not (obj.IsForbidden and obj:IsForbidden()) and obj:IsVisible() then
            GuardedText(obj)
        end
    end
    if Hide.RefreshTooltip then
        Hide.RefreshTooltip()
    end
end, 0.05)

---------------------------------------------------------------------------------------------- tooltips

local function ScrubTooltip(tooltip)
    if not Where("tooltips") or not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then
        return
    end
    local name = tooltip.GetName and tooltip:GetName()
    if not name then
        return
    end
    for i = 1, tooltip:NumLines() or 0 do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G[name .. side .. i]
            if fs then
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
end

local function OnUnitTooltip(tooltip)
    if not OA.live or not tooltip.GetUnit then
        return
    end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if ok and type(unit) == "string" and not IsSecret(unit) then
        OA.Collect.Unit(unit)
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
        SetQuiet(fs, npcLabel[fs])
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
    if plate and not (plate.IsForbidden and plate:IsForbidden()) then
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

---------------------------------------------------------------------------------------------- start

local hooksDone = false

local function HookFrames()
    if hooksDone then
        return
    end
    hooksDone = true
    if type(CompactUnitFrame_UpdateName) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateName", Utils.Guard("raid frames", function(frame)
            if OA.live and frame and frame.name and not (frame.IsForbidden and frame:IsForbidden()) then
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
    -- EllesmereUI frames can spawn after us, and its unit frames cache names: ask for a repaint.
    C_Timer.After(2, function()
        if OA.live then
            Hide.UnitFrames()
            Hide.AllNamePlates()
            if type(_G._EUF_RefreshUnitNames) == "function" then
                pcall(_G._EUF_RefreshUnitNames)
            end
        end
    end)
end

function Hide.Stop()
    Hide.RestoreCVars()
    Hide.UnmuteAll()
end

-- Units changed: refresh the frames that show them.
function Hide.OnUnitChanged()
    if OA.live then
        Hide.UnitFrames()
    end
end
