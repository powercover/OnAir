local _, OA = ...

-- Stream chat: OnAir's own chat window for the broadcast. While live it sits on top of your chat
-- and shows only what you pick (NPC talk, boss emotes and loot by default), every name already
-- swapped for its alias. It reads the chat events on its own frame, outside Blizzard's chat code,
-- so your real chat underneath keeps working and nothing gets tainted.
OA.StreamChat = {}

local Stream = OA.StreamChat
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Names = OA.Names
local Utils = OA.Utils
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString

Stream.GROUPS = {
    { key = "npc", icon = "Chat", text = L["NPC talk"], help = L["What NPCs say, yell and whisper."],
        events = { "MONSTER_SAY", "MONSTER_YELL", "MONSTER_WHISPER", "MONSTER_PARTY" } },
    { key = "emotes", icon = "Overhead", text = L["NPC & boss emotes"], help = L["Boss warnings and NPC emotes."],
        events = { "MONSTER_EMOTE", "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER" } },
    { key = "loot", icon = "Plus", text = L["Loot & money"], help = L["Loot drops, gold and currency."],
        events = { "LOOT", "MONEY", "CURRENCY" } },
    { key = "progress", icon = "Me", text = L["Progress"], help = L["XP, reputation, skills, achievements."],
        events = { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "TRADESKILLS", "ACHIEVEMENT" } },
    { key = "system", icon = "About", text = L["System messages"], help = L["Yellow game messages."],
        events = { "SYSTEM" } },
    { key = "group", icon = "Group", text = L["Party & raid"], help = L["Your group's chat, with aliases."],
        events = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
    { key = "say", icon = "Social", text = L["Say & yell"], help = L["Players around you, with aliases."],
        events = { "SAY", "YELL", "EMOTE", "TEXT_EMOTE" } },
    { key = "guild", icon = "Guild", text = L["Guild"], help = L["Guild and officer chat, with aliases."],
        events = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT" } },
    { key = "whispers", icon = "BNet", text = L["Whispers"], help = L["Whispers and Battle.net, with aliases."],
        events = { "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" } },
}

-- Messages whose text already holds the sender ("%s" in the text, or a full sentence).
local WHOLE = {
    MONSTER_EMOTE = true, RAID_BOSS_EMOTE = true, RAID_BOSS_WHISPER = true, TEXT_EMOTE = true,
    ACHIEVEMENT = true, GUILD_ACHIEVEMENT = true, LOOT = true, MONEY = true, CURRENCY = true,
    COMBAT_XP_GAIN = true, COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true, SKILL = true,
    TRADESKILLS = true, SYSTEM = true,
}
local NPC = { MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_WHISPER = true, MONSTER_PARTY = true,
    MONSTER_EMOTE = true, RAID_BOSS_EMOTE = true, RAID_BOSS_WHISPER = true }

local function DB()
    return OA.db.stream
end

local window, smf, header

local function Color(chatType)
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if info and info.r then
        return info.r, info.g, info.b
    end
    return 1, 1, 1
end

-- The sender as viewers should see it: NPCs keep their name, players get their alias.
local function Sender(chatType, author, ...)
    if not IsPlain(author) then
        return IsSecret(author) and L["Someone"] or ""
    end
    if NPC[chatType] then
        if OA.db.npc.mode ~= "real" then
            return chatType:find("BOSS") and OA.db.npc.boss or OA.db.npc.friendly
        end
        return author
    end
    if chatType:find("^BN_") then
        local accountID = select(11, ...)
        if type(accountID) == "number" and not IsSecret(accountID) then
            return OA.Collect.BNetAccount(accountID) or L["Friend"]
        end
        return Names.Scrub(author)
    end
    local person = Names.AddFull(author, "other")
    return person and person.alias or Names.Scrub(author)
end

local function Line(chatType, msg, author, ...)
    -- Hidden (secret) lines can't be checked for names: left out (see OnEvent).
    if type(msg) ~= "string" or IsSecret(msg) then
        return nil
    end
    local sender = Sender(chatType, author, ...)
    msg = Names.Scrub(msg)
    if WHOLE[chatType] then
        if msg:find("%%s") then
            local ok, out = pcall(string.format, msg, sender)
            if ok then
                return out
            end
        end
        return msg
    end
    if chatType == "EMOTE" then
        return sender .. " " .. msg
    end
    local format = _G["CHAT_" .. chatType .. "_GET"]
    if type(format) == "string" then
        local ok, out = pcall(string.format, format, sender)
        if ok then
            return out .. msg
        end
    end
    return sender .. ": " .. msg
end

---------------------------------------------------------------------------------------------- window

local function SavePosition()
    if not window then
        return
    end
    local point, _, relPoint, x, y = window:GetPoint()
    DB().pos = { point = point, relPoint = relPoint, x = x, y = y, w = window:GetWidth(), h = window:GetHeight() }
end

-- Where your chat is: the stream chat covers it the first time.
local function DefaultPlace()
    local chat = _G.ChatFrame1
    local left, bottom = chat and chat:GetLeft(), chat and chat:GetBottom()
    if left and bottom then
        window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - 6, bottom - 34)
        window:SetSize(math.max(320, chat:GetWidth() + 12), math.max(160, chat:GetHeight() + 64))
    else
        window:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 40)
        window:SetSize(430, 200)
    end
end

function Stream.ApplyLook()
    if not window then
        return
    end
    local db = DB()
    window.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], db.opacity or 0.92)
    smf:SetFontObject(Kit.Font(db.fontSize or 14, "OUTLINE"))
    -- After the font: a font object brings its own alignment (centered), and lines start on the left.
    smf:SetJustifyH("LEFT")
    smf:SetFading(db.fade ~= false)
    smf:SetTimeVisible(db.fadeAfter or 60)
    header:SetShown(db.header ~= false)
    smf:SetPoint("TOPLEFT", 10, db.header ~= false and -28 or -8)
end

-- The title bar: the skin's mark, a live dot and the title; drag it to move the window.
local function BuildHeader()
    header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(22)
    -- The theme's mark: a red stripe, the slate's clapper stripes, or viewfinder brackets.
    local look = Kit.Theme()
    local stripe = look.stripes and Kit.Band(header, "Stripes", C.text, "ARTWORK") or Kit.Rect(header, C.red, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(look.stripes and 4 or 2)
    if look.corners then
        stripe:Hide()
        local over = CreateFrame("Frame", nil, window)
        over:SetAllPoints()
        over:SetFrameLevel(window:GetFrameLevel() + 20)
        Kit.Corners(over, 10, 2, { C.text[1], C.text[2], C.text[3], 0.7 }, 3)
        header.over = over
    end
    local glow = Kit.Shape(header, "Glow", C.red, "BORDER")
    glow:SetSize(30, 30)
    glow:SetPoint("CENTER", header, "LEFT", 14, -1)
    glow:SetBlendMode("ADD")
    header.pulse = Kit.Pulse(glow, 0.2, 0.9, 0.9)
    local dot = Kit.Shape(header, "Dot", C.red, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", header, "LEFT", 14, -1)
    local title = Kit.Text(header, 11, C.muted)
    title:SetPoint("LEFT", 26, -1)
    title:SetText(Kit.Word("live") .. "  " .. L["CHAT"])
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not OA.Layout.IsEditing() and OA.Layout.Locked() then
            return
        end
        window:StartMoving()
        OA.Layout.DragStart("stream")
    end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        OA.Layout.Dropped("stream")
    end)
end

-- A new skin: the title bar is drawn again, the border recolored. The lines stay.
Kit.OnSkin(function()
    if not window then
        return
    end
    header:Hide()
    if header.over then
        header.over:Hide()
    end
    BuildHeader()
    Kit.SetBorderColor(window.edges, C.line)
    Stream.ApplyLook()
    Stream.Update()
end)

local function Build()
    window = CreateFrame("Frame", "OnAirStreamChat", UIParent)
    -- High in the chat's own layer, so it covers chat windows (Blizzard's and addons').
    window:SetFrameStrata("MEDIUM")
    window:SetFrameLevel(120)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    if window.SetResizeBounds then
        window:SetResizeBounds(240, 100, 1200, 800)
    end
    local pos = DB().pos
    if pos and pos.point then
        window:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        window:SetSize(pos.w or 430, pos.h or 200)
    else
        DefaultPlace()
    end
    window.bg = Kit.Rect(window, C.bg, "BACKGROUND")
    window.bg:SetAllPoints()
    window.edges = Kit.Border(window, C.line)
    window:EnableMouse(true)
    BuildHeader()

    smf = CreateFrame("ScrollingMessageFrame", nil, window)
    smf:SetPoint("BOTTOMRIGHT", -10, 8)
    smf:SetMaxLines(250)
    smf:SetIndentedWordWrap(true)
    smf:SetHyperlinksEnabled(true)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    smf:SetScript("OnHyperlinkClick", function(_, link, text, button)
        if type(SetItemRef) == "function" then
            pcall(SetItemRef, link, text, button)
        end
    end)

    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    local gripTex = Kit.Icon(grip, "Chevron", 12, C.faint)
    gripTex:SetPoint("CENTER")
    gripTex:SetRotation(math.rad(45))
    grip:SetScript("OnMouseDown", function()
        if OA.Layout.IsEditing() or not OA.Layout.Locked() then
            window:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        SavePosition()
    end)

    Stream.ApplyLook()
    window:Hide()
end

---------------------------------------------------------------------------------------------- events

local listener = CreateFrame("Frame")
local wanted = {}

local function OnEvent(_, event, msg, author, ...)
    local chatType = event:sub(10)
    if not window or not window:IsShown() or not wanted[chatType] then
        return
    end
    -- In instance combat some lines come hidden from addons (a boss yell naming a player): they
    -- can't be checked for names, so the stream chat leaves them out.
    if Utils.IsSecret(msg) or Utils.IsSecret(author) then
        return
    end
    local line = Line(chatType, msg, author, ...)
    if line == nil or Utils.IsSecret(line) or line == "" then
        return
    end
    pcall(smf.AddMessage, smf, line, Color(chatType))
end
listener:SetScript("OnEvent", Utils.Guard("stream chat", OnEvent))

function Stream.RegisterEvents()
    listener:UnregisterAllEvents()
    wipe(wanted)
    local groups = DB().groups
    for _, group in ipairs(Stream.GROUPS) do
        if groups[group.key] then
            for _, chatType in ipairs(group.events) do
                wanted[chatType] = true
                pcall(listener.RegisterEvent, listener, "CHAT_MSG_" .. chatType)
            end
        end
    end
end

---------------------------------------------------------------------------------------------- state

local placing = false

function Stream.IsPlacing()
    return placing
end

-- Shows the window outside a broadcast so it can be moved and sized, with a few sample lines.
function Stream.TogglePlacing()
    placing = not placing
    if placing then
        if not window then
            Build()
        end
        window:Show()
        smf:Clear()
        smf:AddMessage(L["Drag the top bar to move, the corner to resize."], 1, 1, 1)
        smf:AddMessage(string.format(L["%s says: Welcome, %s!"], L["Innkeeper Allison"], Names.MeAlias()), Color("MONSTER_SAY"))
        smf:AddMessage(L["You receive loot: [Linen Cloth]x2."], Color("LOOT"))
    end
    Stream.Update()
end

Stream.SavePosition = SavePosition

function Stream.Frame()
    if not window then
        Build()
    end
    return window
end

-- Shown for Edit layout (or the Place button) outside a broadcast, with sample lines.
function Stream.SetPlacing(on)
    if (on and true or false) ~= placing then
        Stream.TogglePlacing()
    end
end

function Stream.Update()
    local db = DB()
    local show = (OA.live and db.enabled) or placing
    if show and not window then
        Build()
    end
    if not window then
        return
    end
    Stream.RegisterEvents()
    Stream.ApplyLook()
    if show then
        if not window:IsShown() then
            window:Show()
            window:SetAlpha(0)
            Kit.Tween(window, 0, 1, 0.25, function(p) window:SetAlpha(p) end)
        end
        if OA.live then
            header.pulse:Play()
        else
            header.pulse:Stop()
        end
    else
        header.pulse:Stop()
        window:Hide()
    end
end

function Stream.OnGoLive()
    placing = false
    if window then
        smf:Clear()
    end
    Stream.Update()
end

-- OnAir's own line in the stream chat: a red dot, then the text (a moment, a declined invite).
local DOT = "|T" .. Utils.MEDIA .. "Dot:8:8:0:0:64:64:0:64:0:64:255:59:48|t "

function Stream.Note(text)
    if window and window:IsShown() and OA.live and type(text) == "string" then
        pcall(smf.AddMessage, smf, DOT .. text, 0.85, 0.86, 0.88)
    end
end

function Stream.ResetPosition()
    DB().pos = nil
    if window then
        window:ClearAllPoints()
        DefaultPlace()
        SavePosition()
    end
end
