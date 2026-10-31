local _, OA = ...

-- Chat: message filters rewrite the sender and every known name inside the message before any
-- chat frame (Blizzard's or an addon's, like EllesmereUIChat) shows it. Filters are the game's
-- own hook for this: nothing is replaced, so nothing gets tainted.
OA.Chat = {}

local Chat = OA.Chat
local Names = OA.Names
local Utils = OA.Utils
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString
local SafeBool = Names.SafeBool

local EVENTS = {
    "SAY", "YELL", "EMOTE", "TEXT_EMOTE", "WHISPER", "WHISPER_INFORM", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
    "CHANNEL", "COMMUNITIES_CHANNEL", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "SYSTEM", "LOOT", "AFK",
    "DND", "CHANNEL_JOIN", "CHANNEL_LEAVE", "MONEY", "CURRENCY", "IGNORED", "SKILL", "TRADESKILLS",
    "OPENING", "PET_INFO", "COMBAT_FACTION_CHANGE", "BG_SYSTEM_NEUTRAL", "BG_SYSTEM_ALLIANCE",
    "BG_SYSTEM_HORDE", "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER", "MONSTER_EMOTE", "MONSTER_WHISPER",
    "MONSTER_SAY", "MONSTER_YELL", "MONSTER_PARTY", "PING", "VOICE_TEXT",
}
local BN_EVENTS = { "BN_WHISPER", "BN_WHISPER_INFORM", "BN_INLINE_TOAST_ALERT", "BN_INLINE_TOAST_BROADCAST" }
-- Senders that are NPCs: their names stay, only names inside the message change.
local NPC_SENDER = {
    CHAT_MSG_RAID_BOSS_EMOTE = true, CHAT_MSG_RAID_BOSS_WHISPER = true, CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_MONSTER_WHISPER = true, CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_PARTY = true,
}

local function Live()
    return OA.live and OA.db.where.chat ~= false
end

local function KindOf(author)
    local short = Ambiguate(author, "none")
    if SafeBool(UnitIsUnit, short, "player") then
        return "me"
    end
    if SafeBool(UnitInParty, short) or SafeBool(UnitInRaid, short) then
        return "crew"
    end
    return "other"
end

-- Players in "|Hplayer:Name|h[Name]|h" links are learned, so the visible [Name] becomes the alias.
-- The link's data keeps the real name (unseen), so clicking it still whispers the right player.
local function LearnLinks(msg)
    if not msg:find("|Hplayer:", 1, true) then
        return
    end
    for name in msg:gmatch("|Hplayer:([^:|]+)") do
        Names.AddFull(name, KindOf(name))
    end
end

local function ScrubMessage(msg)
    LearnLinks(msg)
    return Names.Scrub(msg)
end

local function Scrub(msg)
    if type(msg) ~= "string" or IsSecret(msg) then
        return msg
    end
    local ok, out = pcall(ScrubMessage, msg)
    return ok and out or msg
end

-- A chat filter that fails must not stop the message: on an error the message goes through as
-- it came, and the error is reported once.
local filterReported = false

local function Settle(ok, ...)
    if ok then
        return ...
    end
    if not filterReported then
        filterReported = true
        local handler = geterrorhandler and geterrorhandler()
        if handler then
            pcall(handler, "OnAir (chat filter): " .. tostring((...)))
        end
    end
    return false
end

local function SafeFilter(fn)
    return function(...)
        return Settle(pcall(fn, ...))
    end
end

-- Every chat window runs the filters for the same line: the answer is worked out once (and a
-- held whisper stored once) and given again to the next window. A line is its line ID (argument
-- 11) with the same message and sender, while live or not as before; hidden (secret) ones can't
-- be compared, so never kept.
local function PerLine(decide)
    local lastEvent, lastLine, lastRawMsg, lastRawAuthor, lastLive, lastHeld, lastMsg, lastAuthor
    return function(_, event, msg, author, ...)
        local lineID = select(9, ...)
        local live = OA.live == true
        local keep = type(lineID) == "number" and not IsSecret(lineID) and lineID > 0
            and not IsSecret(msg) and not IsSecret(author)
        if keep and lineID == lastLine and event == lastEvent and msg == lastRawMsg and author == lastRawAuthor
            and live == lastLive then
            if lastHeld then
                return true
            end
            if lastMsg == nil then
                return false
            end
            return false, lastMsg, lastAuthor, ...
        end
        local held, newMsg, newAuthor = decide(event, msg, author, ...)
        if keep then
            lastEvent, lastLine, lastRawMsg, lastRawAuthor, lastLive = event, lineID, msg, author, live
            lastHeld, lastMsg, lastAuthor = held, newMsg, newAuthor
        else
            lastLine = nil
        end
        if held then
            return true
        end
        if newMsg == nil then
            return false
        end
        return false, newMsg, newAuthor, ...
    end
end

-- Held back (true), or the message and sender to show (nil: as they came).
local function Decide(event, msg, author, ...)
    -- Shield first, while the sender is still the real name: strangers' whispers are held back.
    if OA.live and OA.Shield.HoldWhisper(event, msg, author, (select(10, ...))) then
        return true
    end
    if not Live() or IsSecret(author) or IsSecret(msg) then
        return false
    end
    if NPC_SENDER[event] and OA.db.npc.mode ~= "real" then
        author = event:find("BOSS") and OA.db.npc.boss or OA.db.npc.friendly
    elseif IsPlain(author) and not NPC_SENDER[event] then
        local person = Names.AddFull(author, KindOf(author))
        if person and person.alias then
            author = person.alias
        end
    end
    return false, Scrub(msg), author
end

-- Battle.net messages: the sender is a name token; the account ID (arg 13) leads to the alias.
local function DecideBN(_, msg, author, ...)
    if not Live() or IsSecret(msg) then
        return false
    end
    local accountID = select(11, ...)
    local alias
    if type(accountID) == "number" and not IsSecret(accountID) then
        alias = OA.Collect.BNetAccount(accountID)
    end
    if alias then
        author = alias
    elseif type(author) == "string" and not IsSecret(author) then
        author = Names.Scrub(author)
    end
    return false, Scrub(msg), author
end

-- The sender a message shows is the alias, so the game remembers the alias as who to reply to
-- (R, a click on the name, a whisper tab). When the chat box opens with an alias as its target,
-- the real one is put back: the whisper reaches them, and the header (scrubbed) still reads the
-- alias on screen.
local fixing = false

local function FixTarget(editBox)
    if fixing or not editBox or not editBox.GetAttribute then
        return
    end
    -- During encounters the game blocks chat sent by addons: leave the box alone then.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    local target = editBox:GetAttribute("tellTarget")
    if type(target) ~= "string" or IsSecret(target) then
        return
    end
    local real = Names.RealOf(target)
    if not real or real == target then
        return
    end
    fixing = true
    editBox:SetAttribute("tellTarget", real)
    local update = (ChatFrameUtil and ChatFrameUtil.UpdateHeader) or ChatEdit_UpdateHeader
    if type(update) == "function" then
        pcall(update, editBox)
    end
    fixing = false
end

-- The right-click menu on a sender's name carries the alias: Whisper, Invite and the rest are
-- pointed back at the real player before the menu's buttons can use it.
local MENUS = { "MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE", "MENU_UNIT_CHAT_ROSTER" }

local function FixMenu(_, _, contextData)
    if type(contextData) ~= "table" then
        return
    end
    local real = Names.RealOf(contextData.name)
    if not real or real:find("^|K") then
        return
    end
    if Utils.IS_FOREVER then
        contextData.name = real
    else
        local first, realm = Names.SplitFull(real)
        contextData.name = first
        contextData.server = realm or contextData.server
    end
    if contextData.chatTarget then
        contextData.chatTarget = real
    end
end

-- Chat bubbles draw the raw message, before our filters: names inside them are fixed a frame
-- later. Bubbles in instances are forbidden to addons and are left as they are.
local function BubbleString(outer)
    local child = outer:GetChildren()
    return child and child.String
end

local function ScrubBubbles()
    if not (Live() and C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then
        return
    end
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
    if not ok or type(list) ~= "table" then
        return
    end
    for _, outer in ipairs(list) do
        local found, fs = pcall(BubbleString, outer)
        if found and fs and fs.GetText then
            local text = fs:GetText()
            if type(text) == "string" and not IsSecret(text) then
                local out = Names.Scrub(text)
                if out ~= text then
                    fs:SetText(out)
                end
            end
        end
    end
end

local BUBBLE_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }
local bubbleFrame = CreateFrame("Frame")
local GuardedBubbles = Utils.Guard("chat bubbles", ScrubBubbles)
bubbleFrame:SetScript("OnEvent", function()
    C_Timer.After(0, GuardedBubbles)
    C_Timer.After(0.1, GuardedBubbles)
end)

local function AddFilter(event, fn)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, fn)
    else
        ChatFrame_AddMessageEventFilter(event, fn)
    end
end

local started = false

function Chat.Start()
    if started then
        return
    end
    started = true
    local filter, bnFilter = SafeFilter(PerLine(Decide)), SafeFilter(PerLine(DecideBN))
    for _, event in ipairs(EVENTS) do
        AddFilter("CHAT_MSG_" .. event, filter)
    end
    for _, event in ipairs(BN_EVENTS) do
        AddFilter("CHAT_MSG_" .. event, bnFilter)
    end
    local fixTarget = Utils.Guard("whisper target", FixTarget)
    if ChatFrameUtil and type(ChatFrameUtil.UpdateHeader) == "function" then
        hooksecurefunc(ChatFrameUtil, "UpdateHeader", fixTarget)
    end
    if type(ChatEdit_UpdateHeader) == "function" then
        hooksecurefunc("ChatEdit_UpdateHeader", fixTarget)
    end
    if Menu and Menu.ModifyMenu then
        local fixMenu = Utils.Guard("name menu", FixMenu)
        for _, tag in ipairs(MENUS) do
            pcall(Menu.ModifyMenu, tag, fixMenu)
        end
    end
    for _, event in ipairs(BUBBLE_EVENTS) do
        bubbleFrame:RegisterEvent(event)
    end
end

-- Empties every chat window, so lines from before going live (with real names) are gone.
-- EllesmereUIChat brings back its saved history a moment after login, so it runs twice then.
-- One frame: in combat some frames are locked (forbidden) and any call on them throws. True when
-- it was a chat window.
local function ClearOne(frame)
    local forbidden = frame.IsForbidden and frame:IsForbidden()
    if Utils.IsSecret(forbidden) or forbidden then
        return false
    end
    if frame:GetObjectType() == "ScrollingMessageFrame" and frame ~= UIErrorsFrame and frame.Clear then
        frame:Clear()
        return true
    end
    return false
end

-- Chat windows found so far (Blizzard's and other addons'): cleared at once. The rest of the UI
-- is looked over for more (tens of thousands of frames) a slice per frame.
local chatFrames = {}

local function Search()
    local frame = EnumerateFrames()
    local n = 0
    while frame do
        local ok, cleared = pcall(ClearOne, frame)
        if ok and cleared then
            chatFrames[frame] = true
        end
        n = n + 1
        if n % 200 == 0 then
            Utils.Pause()
        end
        frame = EnumerateFrames(frame)
    end
end

function Chat.ClearHistory()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            pcall(ClearOne, frame)
        end
    end
    for frame in pairs(chatFrames) do
        pcall(ClearOne, frame)
    end
    Utils.Job("clear chat", Search)
end

function Chat.OnGoLive(atLogin)
    Chat.Start()
    if OA.db.where.chat ~= false and OA.db.where.clearChat ~= false then
        Chat.ClearHistory()
        C_Timer.After(atLogin and 4 or 1, Chat.ClearHistory)
    end
end
