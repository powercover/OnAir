local _, OA = ...

-- Moments: a timeline of the broadcast for whoever edits the video. Going live starts a clock at
-- 00:00 (with a short "clapper" flash on screen, so the footage shows the exact start), and the
-- big moments are marked on their own: bosses, keys, deaths, levels, achievements, epic loot,
-- PvP. A key binding adds your own. Each session exports as YouTube chapters or a marker list.
OA.Moments = {}

local Moments = OA.Moments
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Names = OA.Names
local Utils = OA.Utils
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString

local KEEP_SESSIONS = 10

-- What each kind of moment looks like, and whether it makes a YouTube chapter.
Moments.KINDS = {
    start = { icon = "Live", color = C.red, chapter = true },
    mark = { icon = "Flag", color = C.red, chapter = true },
    pull = { icon = "Group", color = C.text, chapter = true },
    kill = { icon = "Check", color = { 0.4, 0.86, 0.5, 1 } },
    wipe = { icon = "Close", color = C.muted },
    key = { icon = "Shuffle", color = C.text, chapter = true },
    keyEnd = { icon = "Check", color = { 0.4, 0.86, 0.5, 1 } },
    death = { icon = "Close", color = { 1, 0.45, 0.4, 1 } },
    level = { icon = "Me", color = { 1, 0.82, 0.3, 1 }, chapter = true },
    achievement = { icon = "Me", color = { 1, 0.82, 0.3, 1 } },
    loot = { icon = "Plus", color = { 0.64, 0.21, 0.93, 1 } },
    pvp = { icon = "Social", color = C.text, chapter = true },
}

-- Which automatic markers are on (settings), by group.
Moments.AUTO = {
    { key = "bosses", icon = "Group", text = L["Boss fights"], help = L["Pulls, kills and wipes."] },
    { key = "keys", icon = "Shuffle", text = L["Mythic+ keys"], help = L["Key started, in time or over."] },
    { key = "deaths", icon = "Close", text = L["Your deaths"], help = L["Every time you die."] },
    { key = "progress", icon = "Me", text = L["Levels & achievements"], help = L["Ding! and every achievement."] },
    { key = "loot", icon = "Plus", text = L["Epic loot"], help = L["Epic and better items you get."] },
    { key = "pvp", icon = "Social", text = L["PvP"], help = L["Battlegrounds, arenas and duels ending."] },
}

local function DB()
    return OA.db.moments
end

---------------------------------------------------------------------------------------------- sessions

function Moments.Sessions()
    return DB().sessions
end

function Moments.Current()
    local list = DB().sessions
    return list[#list]
end

-- Seconds since the clock started. The game timer is exact and survives a /reload; after the
-- game was restarted it no longer matches, and the wall clock takes over.
function Moments.Elapsed(session)
    session = session or Moments.Current()
    if not session then
        return 0
    end
    local now = GetTime()
    local wall = time() - session.started
    if session.gt and now >= session.gt and math.abs((now - session.gt) - wall) < 5 then
        return now - session.gt
    end
    return wall
end

function Moments.Format(seconds, forceHours)
    seconds = math.max(0, math.floor(seconds or 0))
    local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if h > 0 or forceHours then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

local flash

local function Flash()
    if not flash then
        flash = CreateFrame("Frame", nil, UIParent)
        flash:SetAllPoints(UIParent)
        flash:SetFrameStrata("FULLSCREEN_DIALOG")
        local white = flash:CreateTexture(nil, "BACKGROUND")
        white:SetAllPoints()
        white:SetColorTexture(1, 1, 1, 1)
        local clapper = Kit.Icon(flash, "Clapper", 96, { 0.05, 0.05, 0.06, 1 })
        clapper:SetPoint("CENTER", 0, 30)
        local text = Kit.Text(flash, 30, { 0.05, 0.05, 0.06, 1 })
        text:SetPoint("TOP", clapper, "BOTTOM", 0, -14)
        text:SetText("00:00  " .. L["ON AIR"])
        flash:Hide()
    end
    flash:Show()
    Kit.Tween(flash, 1, 0, 0.45, function(p)
        flash:SetAlpha(p)
        if p <= 0 then
            flash:Hide()
        end
    end)
end

-- A new session at 00:00. After a /reload while live, the running session carries on.
function Moments.Start(atLogin)
    local db = DB()
    local current = Moments.Current()
    if atLogin and current and not current.ended then
        return
    end
    if current and not current.ended then
        current.ended = time()
    end
    table.insert(db.sessions, { started = time(), gt = GetTime(), moments = {} })
    while #db.sessions > KEEP_SESSIONS do
        table.remove(db.sessions, 1)
    end
    Moments.Add("start", L["Broadcast starts"], true)
    if db.flash ~= false then
        Flash()
    end
end

-- Restart the clock now: when you started recording a bit later than going live.
function Moments.Restart()
    local session = Moments.Current()
    if session and OA.live then
        session.ended = time()
    end
    Moments.Start(false)
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

function Moments.Stop()
    local session = Moments.Current()
    if session and not session.ended then
        session.ended = time()
    end
end

---------------------------------------------------------------------------------------------- adding

local function Screenshot_()
    if type(Screenshot) == "function" then
        pcall(Screenshot)
    end
end

-- Adds a moment to the running session. Texts are stored with names already as aliases, so an
-- export is safe to show on stream too.
function Moments.Add(kind, text, quiet)
    if not OA.live and kind ~= "start" then
        return
    end
    local session = Moments.Current()
    if not session then
        return
    end
    if type(text) ~= "string" or IsSecret(text) then
        text = L["Moment"]
    end
    text = Names.Scrub(text)
    local t = Moments.Elapsed(session)
    table.insert(session.moments, { t = t, kind = kind, text = text })
    local db = DB()
    if not quiet then
        if db.screenshot then
            C_Timer.After(0.3, Screenshot_)
        end
        if db.note ~= false and OA.StreamChat and OA.StreamChat.Note then
            OA.StreamChat.Note(Moments.Format(t) .. "  " .. text)
        end
    end
    if OA.UI and OA.UI.RefreshMoments then
        OA.UI.RefreshMoments()
    end
end

function Moments.Mark(note)
    if not OA.live or OA.rehearsal then
        Utils.Print(L["Moments are marked while you're live."])
        return
    end
    Moments.Add("mark", IsPlain(note) and note or L["Marked"])
    PlaySound(SOUNDKIT and SOUNDKIT.UI_70_ARTIFACT_FORGE_TOAST_TRAITREFUNDED or 857)
end

---------------------------------------------------------------------------------------------- automatic

local function Auto(group)
    return OA.live and not OA.rehearsal and DB().auto[group] ~= false
end

-- Your own loot: the game's "You receive loot: %s." lines, as patterns.
local selfLoot
local function SelfLootPatterns()
    if selfLoot then
        return selfLoot
    end
    selfLoot = {}
    for _, name in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
        "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_CREATED_SELF" }) do
        local format = _G[name]
        if type(format) == "string" then
            -- Escape the pattern characters, then the format's %s / %d become captures.
            local pattern = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
            selfLoot[#selfLoot + 1] = "^" .. pattern
        end
    end
    return selfLoot
end

local function Quality(link)
    local q = link:match("|cnIQ(%d):")
    if q then
        return tonumber(q)
    end
    if C_Item and C_Item.GetItemQualityByID then
        local ok, quality = pcall(C_Item.GetItemQualityByID, link)
        if ok and type(quality) == "number" then
            return quality
        end
    end
    return nil
end

local function OnLoot(msg)
    if not Auto("loot") or type(msg) ~= "string" or IsSecret(msg) then
        return
    end
    local mine = false
    for _, pattern in ipairs(SelfLootPatterns()) do
        if msg:find(pattern) then
            mine = true
            break
        end
    end
    local link = mine and msg:match("|c.-|Hitem:.-|h.-|h|r")
    if link and (Quality(link) or 0) >= 4 then
        Moments.Add("loot", string.format(L["Loot: %s"], link))
    end
end

local pullStarted = {}

local HANDLERS = {
    ENCOUNTER_START = function(id, name)
        pullStarted[id] = GetTime()
        if Auto("bosses") then
            Moments.Add("pull", string.format(L["Pull: %s"], tostring(name)))
        end
    end,
    ENCOUNTER_END = function(id, name, _, _, success)
        if not Auto("bosses") then
            return
        end
        local took = pullStarted[id] and Moments.Format(GetTime() - pullStarted[id]) or "?"
        pullStarted[id] = nil
        if success == 1 or success == true then
            Moments.Add("kill", string.format(L["Killed: %s (%s)"], tostring(name), took))
        else
            Moments.Add("wipe", string.format(L["Wipe: %s (%s)"], tostring(name), took))
        end
    end,
    CHALLENGE_MODE_START = function(mapID)
        if not Auto("keys") or not C_ChallengeMode then
            return
        end
        local name = C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID) or L["Key"]
        local level = C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo() or 0
        Moments.Add("key", string.format(L["Key started: %s +%d"], tostring(name), tonumber(level) or 0))
    end,
    CHALLENGE_MODE_COMPLETED = function()
        if not Auto("keys") or not (C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo) then
            return
        end
        local info = C_ChallengeMode.GetChallengeCompletionInfo()
        if type(info) ~= "table" then
            return
        end
        local name = C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID) or L["Key"]
        local took = Moments.Format((info.time or 0) / 1000)
        if info.onTime then
            Moments.Add("keyEnd", string.format(L["Key in time: %s +%d, %s (+%d)"], tostring(name), info.level or 0,
                took, info.keystoneUpgradeLevels or 1))
        else
            Moments.Add("keyEnd", string.format(L["Key over time: %s +%d, %s"], tostring(name), info.level or 0, took))
        end
    end,
    PLAYER_DEAD = function()
        if Auto("deaths") then
            Moments.Add("death", L["You died"])
        end
    end,
    PLAYER_LEVEL_UP = function(level)
        if Auto("progress") then
            Moments.Add("level", string.format(L["Level %d!"], tonumber(level) or 0))
        end
    end,
    ACHIEVEMENT_EARNED = function(id)
        if Auto("progress") and type(GetAchievementInfo) == "function" then
            local _, name = GetAchievementInfo(id)
            Moments.Add("achievement", string.format(L["Achievement: %s"], tostring(name)))
        end
    end,
    CHAT_MSG_LOOT = OnLoot,
    PVP_MATCH_COMPLETE = function(winner)
        if not Auto("pvp") then
            return
        end
        local mine = type(GetBattlefieldArenaFaction) == "function" and GetBattlefieldArenaFaction()
        if type(winner) == "number" and type(mine) == "number" and not IsSecret(winner) then
            Moments.Add("pvp", winner == mine and L["PvP match won"] or L["PvP match lost"])
        else
            Moments.Add("pvp", L["PvP match finished"])
        end
    end,
    DUEL_FINISHED = function()
        if Auto("pvp") then
            Moments.Add("pvp", L["Duel finished"])
        end
    end,
}

local frame = CreateFrame("Frame")
for event, fn in pairs(HANDLERS) do
    HANDLERS[event] = Utils.Guard("moments " .. event, fn)
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    HANDLERS[event](...)
end)

---------------------------------------------------------------------------------------------- export

-- YouTube's rules: the first chapter at 00:00, at least three, each at least 10 seconds long.
function Moments.Chapters(session)
    local lines = {}
    local last = -100
    local hours = ((session.moments[#session.moments] or {}).t or 0) >= 3600
    for _, moment in ipairs(session.moments) do
        local kind = Moments.KINDS[moment.kind]
        if kind and kind.chapter then
            local t = #lines == 0 and 0 or moment.t
            if t - last >= 10 then
                lines[#lines + 1] = Moments.Format(t, hours) .. " " .. (#lines == 0 and L["Intro"] or moment.text)
                last = t
            end
        end
    end
    if #lines < 3 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L["(YouTube needs at least 3 chapters, 10 seconds apart.)"]
    end
    return table.concat(lines, "\n")
end

-- Every moment, for an editor: H:MM:SS, what, text.
function Moments.MarkerList(session)
    local lines = {}
    for _, moment in ipairs(session.moments) do
        lines[#lines + 1] = string.format("%s  %-12s %s", Moments.Format(moment.t, true), moment.kind, moment.text)
    end
    return table.concat(lines, "\n")
end

-- A window with the text selected, ready for Ctrl+C (addons can't write the clipboard).
local exportFrame

function Moments.ShowExport(title, text)
    if not exportFrame then
        local f = CreateFrame("Frame", "OnAirExport", UIParent)
        f:SetSize(520, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local bg = Kit.Rect(f, C.bg, "BACKGROUND")
        bg:SetAllPoints()
        Kit.Border(f)
        local stripe = Kit.Rect(f, C.red, "ARTWORK")
        stripe:SetPoint("TOPLEFT")
        stripe:SetPoint("TOPRIGHT")
        stripe:SetHeight(2)
        f.title = Kit.Text(f, 16, C.text)
        f.title:SetPoint("TOPLEFT", 18, -16)
        local hint = Kit.Text(f, 12, C.muted)
        hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
        hint:SetText(L["Selected: press Ctrl+C to copy."])
        local close = Kit.IconButton(f, "Close", 28, nil, nil, function() f:Hide() end)
        close:SetPoint("TOPRIGHT", -10, -10)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -60)
        scroll:SetPoint("BOTTOMRIGHT", -36, 18)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(Kit.Font(13))
        box:SetTextColor(unpack(C.text))
        box:SetWidth(450)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        box:SetScript("OnTextChanged", function(self, user)
            if user then
                self:SetText(f.text or "")
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(box)
        f.box = box
        tinsert(UISpecialFrames, "OnAirExport")
        exportFrame = f
    end
    exportFrame.title:SetText(title)
    exportFrame.text = text
    exportFrame.box:SetText(text)
    exportFrame:Show()
    exportFrame.box:SetFocus()
    exportFrame.box:HighlightText()
end

function Moments.OnGoLive(atLogin)
    Moments.Start(atLogin)
end

function Moments.OnEndLive()
    Moments.Stop()
end
