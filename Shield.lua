local _, OA = ...

-- Shield: anti-snipe and anti-grief while live. Whispers from strangers are held (shown in chat
-- once the broadcast ends) with an optional polite reply; group invites, duels and trades from
-- strangers are declined; your location can be kept off screen. Friends, Battle.net friends,
-- your guild, your group and everyone on the Custom page are trusted and get through.
OA.Shield = {}

local Shield = OA.Shield
local L = OA.L
local Names = OA.Names
local Utils = OA.Utils
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString
local SafeBool = Names.SafeBool

local REPLY_COOLDOWN = 15 * 60

local function DB()
    return OA.db.shield
end

local function On(key)
    return OA.live and not OA.rehearsal and DB()[key] ~= false
end

-- Someone you know. Unknowable (secret) counts as known: never block what can't be checked.
function Shield.Trusted(name, guid)
    if IsSecret(name) or IsSecret(guid) then
        return true
    end
    if not IsPlain(name) then
        return true
    end
    local short = Ambiguate(name, "none")
    if SafeBool(UnitIsUnit, short, "player") or SafeBool(UnitInParty, short) or SafeBool(UnitInRaid, short) then
        return true
    end
    local custom = OA.db.custom
    if custom[name] or custom[short] or custom[(Names.SplitFull(name))] then
        return true
    end
    if IsPlain(guid) then
        if C_FriendList and C_FriendList.IsFriend and SafeBool(C_FriendList.IsFriend, guid) then
            return true
        end
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
            local ok, account = pcall(C_BattleNet.GetGameAccountInfoByGUID, guid)
            if ok and account then
                return true
            end
        end
        if type(IsGuildMember) == "function" and SafeBool(IsGuildMember, guid) then
            return true
        end
    end
    if C_FriendList and C_FriendList.GetFriendInfo then
        local ok, info = pcall(C_FriendList.GetFriendInfo, name)
        if ok and info then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------------------------- whispers

local replied = {}

local function Send(text, target)
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if type(send) == "function" then
        pcall(send, text, "WHISPER", nil, target)
    end
end

-- Called by the chat filter (Chat.lua) before names are swapped: true holds the whisper back.
function Shield.HoldWhisper(event, msg, author, guid)
    if event ~= "CHAT_MSG_WHISPER" or not On("whispers") or Shield.Trusted(author, guid) then
        return false
    end
    local db = DB()
    if not IsSecret(msg) and type(msg) == "string" then
        table.insert(db.held, { from = author, msg = msg, at = time() })
        while #db.held > 200 do
            table.remove(db.held, 1)
        end
    end
    if db.reply and IsPlain(db.replyText) and IsPlain(author) then
        local last = replied[author]
        if not last or GetTime() - last > REPLY_COOLDOWN then
            replied[author] = GetTime()
            -- Later, outside the chat code that delivered the whisper.
            C_Timer.After(0.5, function()
                Send(db.replyText, author)
            end)
        end
    end
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
    return true
end

function Shield.HeldCount()
    return #DB().held
end

-- After the broadcast: the held whispers, with real names, in your chat.
function Shield.ShowHeld()
    local held = DB().held
    if #held == 0 then
        return
    end
    Utils.Print(string.format(L["%d whispers came in while you were live:"], #held))
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    for _, w in ipairs(held) do
        local line = string.format("|cff8a8f98%s|r |cffff80ff%s:|r %s", date("%H:%M", w.at), w.from, w.msg)
        if frame and frame.AddMessage then
            pcall(frame.AddMessage, frame, line)
        end
    end
    wipe(held)
end

---------------------------------------------------------------------------------------------- requests

local function Declined(what)
    if OA.StreamChat and OA.StreamChat.Note then
        OA.StreamChat.Note(what)
    end
end

local HANDLERS = {
    PARTY_INVITE_REQUEST = function(name, _, _, _, _, _, guid)
        if On("invites") and not Shield.Trusted(name, guid) then
            pcall(DeclineGroup)
            StaticPopup_Hide("PARTY_INVITE")
            Declined(L["Declined a group invite from a stranger."])
        end
    end,
    DUEL_REQUESTED = function(name)
        if On("duels") and not Shield.Trusted(name) then
            pcall(CancelDuel)
            StaticPopup_Hide("DUEL_REQUESTED")
            Declined(L["Declined a duel from a stranger."])
        end
    end,
    TRADE_REQUEST = function(name)
        if On("trades") and not Shield.Trusted(name) then
            pcall(CancelTrade)
            StaticPopup_Hide("TRADE")
            Declined(L["Declined a trade from a stranger."])
        end
    end,
    TRADE_SHOW = function()
        if On("trades") then
            local ok, name, realm = pcall(UnitName, "npc")
            local guid = UnitGUID and UnitGUID("npc")
            if ok and IsPlain(name) then
                local full = IsPlain(realm) and (name .. "-" .. realm) or name
                if not Shield.Trusted(full, guid) then
                    pcall(CancelTrade)
                    Declined(L["Declined a trade from a stranger."])
                end
            end
        end
    end,
}

---------------------------------------------------------------------------------------------- location

-- Your zone and subzone names read "Somewhere" in every text while live (the minimap, its addons,
-- quest text, chat), the big zone banners are hidden, and the minimap can be too.
local BANNERS = { "ZoneTextString", "SubZoneTextString", "PVPInfoTextString", "PVPArenaTextString" }

function Shield.RefreshPlaces()
    local places = {}
    if OA.live and DB().zones then
        for _, fn in ipairs({ GetZoneText, GetSubZoneText, GetRealZoneText, GetMinimapZoneText }) do
            if type(fn) == "function" then
                local ok, text = pcall(fn)
                if ok and IsPlain(text) then
                    places[#places + 1] = text
                end
            end
        end
    end
    Names.SetHiddenPlaces(places)
end

function Shield.Apply()
    local live = OA.live
    local db = DB()
    for _, name in ipairs(BANNERS) do
        OA.Hide.Mute(_G[name], "snipe", live and db.banners ~= false)
    end
    OA.Hide.Mute(_G.Minimap, "snipe", live and db.minimap == true)
    Shield.RefreshPlaces()
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    HANDLERS[event] = Shield.RefreshPlaces
end

local frame = CreateFrame("Frame")
for event, fn in pairs(HANDLERS) do
    HANDLERS[event] = Utils.Guard("shield " .. event, fn)
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...)
    if OA.live then
        HANDLERS[event](...)
    end
end)

function Shield.OnGoLive()
    wipe(replied)
    Shield.Apply()
end

function Shield.OnEndLive()
    Shield.Apply()
    Shield.ShowHeld()
end

-- At login, off the air: whispers held before a reload or a crash.
function Shield.Init()
    if not OA.live then
        C_Timer.After(5, Shield.ShowHeld)
    end
end
