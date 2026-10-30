local _, OA = ...

-- Teaches the name engine every player the UI can show: the group, units you look at, chat
-- authors (Chat.lua), and the social lists. Each list is read when the game says it changed, so
-- names are known before (or right after) a window draws them; Hide.lua re-scrubs what's on screen
-- whenever a new name comes in.
OA.Collect = {}

local Collect = OA.Collect
local Names = OA.Names
local Utils = OA.Utils
local IsPlain = Utils.IsPlainString

local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
    return nil
end

function Collect.Group()
    Names.AddUnit("player")
    Names.AddUnit("pet")
    if IsInRaid() then
        for i = 1, 40 do
            Names.AddUnit("raid" .. i)
            Names.AddUnit("raidpet" .. i)
        end
    else
        for i = 1, 4 do
            Names.AddUnit("party" .. i)
            Names.AddUnit("partypet" .. i)
        end
    end
end

local function GuildOf(unit)
    local name = Call(GetGuildInfo, unit)
    if IsPlain(name) then
        Names.AddGuild(name, false)
    end
end

-- A unit you look at: its player (or pet) and its guild.
function Collect.Unit(unit)
    local person = Names.AddUnit(unit)
    if person then
        GuildOf(unit)
    end
    return person
end

function Collect.Guilds()
    local mine = IsInGuild() and Call(GetGuildInfo, "player")
    if IsPlain(mine) then
        Names.AddGuild(mine, true)
    end
end

function Collect.GuildRoster()
    Collect.Guilds()
    if not IsInGuild() or type(GetNumGuildMembers) ~= "function" then
        return
    end
    local total = GetNumGuildMembers() or 0
    for i = 1, math.min(total, 2000) do
        local name = Call(GetGuildRosterInfo, i)
        Names.AddFull(name, "other")
    end
end

function Collect.Friends()
    local FL = C_FriendList
    if FL and FL.GetNumFriends then
        for i = 1, (Call(FL.GetNumFriends) or 0) do
            local info = Call(FL.GetFriendInfoByIndex, i)
            if info then
                Names.AddFull(info.name, "other")
            end
        end
    end
    if FL and FL.GetNumIgnores then
        for i = 1, (Call(FL.GetNumIgnores) or 0) do
            Names.AddFull(Call(FL.GetIgnoreName, i), "other")
        end
    end
    local BN = C_BattleNet
    if BN and BN.GetFriendAccountInfo and type(BNGetNumFriends) == "function" then
        for i = 1, (Call(BNGetNumFriends) or 0) do
            local account = Call(BN.GetFriendAccountInfo, i)
            if account then
                local game = account.gameAccountInfo
                local character
                if game and IsPlain(game.characterName) then
                    character = game.characterName
                    if IsPlain(game.realmName) and not Utils.IS_FOREVER then
                        character = character .. "-" .. game.realmName:gsub("%s", "")
                    end
                end
                Names.AddBNet(account.bnetAccountID, account.accountName, account.battleTag, character)
            end
        end
    end
end

-- Your own BattleTag (the friends window shows it at the top).
function Collect.Self()
    if type(BNGetInfo) == "function" then
        local _, battleTag = Call(BNGetInfo)
        Names.AddOwnBattleTag(battleTag)
    end
end

function Collect.BNetAccount(accountID)
    local BN = C_BattleNet
    local account = BN and BN.GetAccountInfoByID and Call(BN.GetAccountInfoByID, accountID)
    if not account then
        return nil
    end
    local game = account.gameAccountInfo
    local character = game and IsPlain(game.characterName) and game.characterName or nil
    return Names.AddBNet(account.bnetAccountID or accountID, account.accountName, account.battleTag, character)
end

function Collect.Clubs()
    local Club = C_Club
    if not (Club and Club.GetSubscribedClubs) then
        return
    end
    local guildType = Enum.ClubType and Enum.ClubType.Guild
    for _, club in ipairs(Call(Club.GetSubscribedClubs) or {}) do
        if club.clubType ~= guildType then
            Names.AddCommunity(club.name)
        end
        local members = Call(Club.GetClubMembers, club.clubId) or {}
        for i = 1, math.min(#members, 2000) do
            local info = Call(Club.GetMemberInfo, club.clubId, members[i])
            if info and not info.isSelf then
                Names.AddFull(info.name, "other")
            end
        end
    end
end

-- Only the communities' own names (after a settings change rebuilt the aliases).
function Collect.ClubNames()
    local Club = C_Club
    if not (Club and Club.GetSubscribedClubs) then
        return
    end
    local guildType = Enum.ClubType and Enum.ClubType.Guild
    for _, club in ipairs(Call(Club.GetSubscribedClubs) or {}) do
        if club.clubType ~= guildType then
            Names.AddCommunity(club.name)
        end
    end
end

function Collect.Who()
    local FL = C_FriendList
    if not (FL and FL.GetNumWhoResults) then
        return
    end
    for i = 1, (Call(FL.GetNumWhoResults) or 0) do
        local info = Call(FL.GetWhoInfo, i)
        if info then
            Names.AddFull(info.fullName, "other")
            if IsPlain(info.fullGuildName) then
                Names.AddGuild(info.fullGuildName, false)
            end
        end
    end
end

function Collect.LFG()
    local LFG = C_LFGList
    if not (LFG and LFG.GetSearchResults) then
        return
    end
    local _, results = Call(LFG.GetSearchResults)
    for _, id in ipairs(results or {}) do
        local info = Call(LFG.GetSearchResultInfo, id)
        if info then
            Names.AddFull(info.leaderName, "other")
        end
    end
    Collect.Applicants()
end

function Collect.Applicants()
    local LFG = C_LFGList
    if not (LFG and LFG.GetApplicants) then
        return
    end
    for _, id in ipairs(Call(LFG.GetApplicants) or {}) do
        local info = Call(LFG.GetApplicantInfo, id)
        for i = 1, (info and info.numMembers or 0) do
            Names.AddFull((Call(LFG.GetApplicantMemberInfo, id, i)), "other")
        end
    end
end

function Collect.Mail()
    if type(GetInboxNumItems) ~= "function" then
        return
    end
    for i = 1, (Call(GetInboxNumItems) or 0) do
        local _, _, sender = Call(GetInboxHeaderInfo, i)
        Names.AddFull(sender, "other")
    end
end

function Collect.Scoreboard()
    local PvP = C_PvP
    if not (PvP and PvP.GetScoreInfo) or type(GetNumBattlefieldScores) ~= "function" then
        return
    end
    for i = 1, (Call(GetNumBattlefieldScores) or 0) do
        local info = Call(PvP.GetScoreInfo, i)
        if info then
            Names.AddFull(info.name, "other")
        end
    end
end

function Collect.Arena()
    for i = 1, 5 do
        Collect.Unit("arena" .. i)
    end
end

-- Everything at once: when going live.
function Collect.All()
    Collect.Self()
    Collect.Group()
    for _, unit in ipairs({ "target", "focus", "targettarget", "focustarget", "mouseover" }) do
        Collect.Unit(unit)
    end
    Collect.GuildRoster()
    Collect.Friends()
    Collect.Clubs()
    Collect.Mail()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        if plate.namePlateUnitToken then
            Collect.Unit(plate.namePlateUnitToken)
        end
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        Call(C_GuildInfo.GuildRoster)
    end
end

local HANDLERS = {
    GROUP_ROSTER_UPDATE = Collect.Group,
    UNIT_PET = Collect.Group,
    PLAYER_TARGET_CHANGED = function() Collect.Unit("target"); Collect.Unit("targettarget") end,
    PLAYER_FOCUS_CHANGED = function() Collect.Unit("focus"); Collect.Unit("focustarget") end,
    UPDATE_MOUSEOVER_UNIT = function() Collect.Unit("mouseover") end,
    UNIT_TARGET = function() Collect.Unit("targettarget"); Collect.Unit("focustarget") end,
    NAME_PLATE_UNIT_ADDED = function(unit) Collect.Unit(unit) end,
    ARENA_OPPONENT_UPDATE = Collect.Arena,
    GUILD_ROSTER_UPDATE = Collect.GuildRoster,
    PLAYER_GUILD_UPDATE = Collect.Guilds,
    FRIENDLIST_UPDATE = Collect.Friends,
    BN_FRIEND_LIST_SIZE_CHANGED = Collect.Friends,
    BN_FRIEND_INFO_CHANGED = Collect.Friends,
    BN_FRIEND_ACCOUNT_ONLINE = Collect.Friends,
    CLUB_MEMBERS_UPDATED = Collect.Clubs,
    CLUB_MEMBER_ADDED = Collect.Clubs,
    WHO_LIST_UPDATE = Collect.Who,
    LFG_LIST_SEARCH_RESULTS_RECEIVED = Collect.LFG,
    LFG_LIST_APPLICANT_LIST_UPDATED = Collect.Applicants,
    LFG_LIST_APPLICANT_UPDATED = Collect.Applicants,
    MAIL_INBOX_UPDATE = Collect.Mail,
    UPDATE_BATTLEFIELD_SCORE = Collect.Scoreboard,
    TRADE_SHOW = function() Collect.Unit("npc") end,
    INSPECT_READY = function() Collect.Unit("target") end,
    DUEL_REQUESTED = function(name) Names.AddFull(name, "other") end,
    PARTY_INVITE_REQUEST = function(name) Names.AddFull(name, "other") end,
}

for event, fn in pairs(HANDLERS) do
    HANDLERS[event] = Utils.Guard("collect " .. event, fn)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    if OA.live then
        HANDLERS[event](...)
    end
end)

function Collect.Init()
    for event in pairs(HANDLERS) do
        if C_EventUtils == nil or C_EventUtils.IsEventValid == nil or C_EventUtils.IsEventValid(event) then
            if event == "UNIT_TARGET" then
                frame:RegisterUnitEvent(event, "target", "focus")
            else
                pcall(frame.RegisterEvent, frame, event)
            end
        end
    end
end
