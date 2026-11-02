local _, OA = ...

-- Teaches the name engine every player the UI can show: the group, units you look at, chat
-- authors (Chat.lua), and the social lists. Each list is read when the game says it changed, so
-- names are known before (or right after) a window draws them; Hide.lua re-scrubs what's on screen
-- whenever a new name comes in. Big lists (a guild, communities, friends) are read a slice per
-- frame (Utils.Job), and again at most every few seconds however often the game says they changed.
OA.Collect = {}

local Collect = OA.Collect
local Names = OA.Names
local Utils = OA.Utils
local IsPlain = Utils.IsPlainString
local Pause = Utils.Pause

-- When each list was last read, and which ones wait to be read again (see Soon below). A read that
-- found nobody doesn't count: right after login the lists are still empty, and the real one must
-- not wait out the gap.
local lastRun, queued = {}, {}

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

-- A count from the game, for a loop: 0 when it's missing or a secret. In instances the game hides
-- some (a group finder listing's member count in a Mythic+ key), and a loop can't run to a secret.
local function Count(n)
    if type(n) ~= "number" or Utils.IsSecret(n) then
        return 0
    end
    return n
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
    local total = Count(GetNumGuildMembers())
    if total == 0 then
        lastRun.guild = nil
    end
    for i = 1, math.min(total, 2000) do
        local name, _, _, _, _, _, publicNote, officerNote = Call(GetGuildRosterInfo, i)
        Names.AddNote(publicNote)
        Names.AddNote(officerNote)
        Names.AddFull(name, "other")
        Pause()
    end
end

-- A friend's game account: its WoW character as "Name-Realm" (or "First Surname"), if any.
local function Character(game)
    if not game or not IsPlain(game.characterName) then
        return nil
    end
    local character = game.characterName
    if IsPlain(game.realmName) and not Utils.IS_FOREVER then
        character = character .. "-" .. game.realmName:gsub("%s", "")
    end
    return character
end

-- WoW friends and the ignore list.
function Collect.WoWFriends()
    local FL = C_FriendList
    if FL and FL.GetNumFriends then
        local count = Count(Call(FL.GetNumFriends))
        if count == 0 then
            lastRun["wow friends"] = nil
        end
        for i = 1, count do
            local info = Call(FL.GetFriendInfoByIndex, i)
            if info then
                Names.AddFull(info.name, "other")
                Names.AddNote(info.notes)
            end
            Pause()
        end
    end
    if FL and FL.GetNumIgnores then
        for i = 1, Count(Call(FL.GetNumIgnores)) do
            Names.AddFull(Call(FL.GetIgnoreName, i), "other")
        end
    end
end

-- One Battle.net friend, by their place in the list.
function Collect.Friend(i)
    local BN = C_BattleNet
    if not (BN and BN.GetFriendAccountInfo) then
        return
    end
    local account = Call(BN.GetFriendAccountInfo, i)
    if not account then
        return
    end
    Names.AddBNet(account.bnetAccountID, account.accountName, account.battleTag, Character(account.gameAccountInfo))
    Names.AddNote(account.note)
    -- Every game account, not only the "main" one: with the Battle.net app open, the app can be
    -- the main one and the WoW character would never be learned.
    for g = 1, Count(BN.GetFriendNumGameAccounts and Call(BN.GetFriendNumGameAccounts, i)) do
        local character = Character(Call(BN.GetFriendGameAccountInfo, i, g))
        if character then
            Names.AddBNet(account.bnetAccountID, account.accountName, account.battleTag, character)
        end
    end
end

function Collect.BNFriends()
    if type(BNGetNumFriends) ~= "function" then
        return
    end
    local count = Count(Call(BNGetNumFriends))
    if count == 0 then
        lastRun["bn friends"] = nil
    end
    for i = 1, count do
        Collect.Friend(i)
        Pause()
    end
end

function Collect.Friends()
    Collect.WoWFriends()
    Collect.BNFriends()
end

-- Recent allies (the friends window's Recent tab): people you raided with, whispered, grouped with.
local function AllyName(ally)
    local data = type(ally) == "table" and (ally.characterData or ally) or nil
    if not data then
        return nil
    end
    if IsPlain(data.fullName) then
        return data.fullName
    end
    if IsPlain(data.name) and IsPlain(data.realmName) and not Utils.IS_FOREVER then
        return data.name .. "-" .. data.realmName:gsub("%s", "")
    end
    return data.name
end
Collect.AllyName = AllyName

function Collect.RecentAllies()
    local RA = C_RecentAllies
    if not (RA and RA.GetRecentAllies) then
        return
    end
    for _, ally in ipairs(Call(RA.GetRecentAllies) or {}) do
        Names.AddFull(AllyName(ally), "other")
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
    return Names.AddBNet(account.bnetAccountID or accountID, account.accountName, account.battleTag,
        Character(account.gameAccountInfo))
end

-- One member of a community.
function Collect.Member(clubId, memberId)
    local info = C_Club and Call(C_Club.GetMemberInfo, clubId, memberId)
    if info then
        Names.AddNote(info.memberNote)
        Names.AddNote(info.officerNote)
        if not info.isSelf then
            Names.AddFull(info.name, "other")
        end
    end
end

function Collect.ClubMembers(clubId)
    local members = C_Club and Call(C_Club.GetClubMembers, clubId) or {}
    for i = 1, math.min(#members, 2000) do
        Collect.Member(clubId, members[i])
        Pause()
    end
end

-- The guild is a community too, but its members are the guild roster (read on its own): only
-- the other communities are read here.
local function IsGuildClub(clubId)
    local guild = C_Club and C_Club.GetGuildClubId and Call(C_Club.GetGuildClubId)
    return guild ~= nil and guild == clubId
end

function Collect.Clubs()
    local Club = C_Club
    if not (Club and Club.GetSubscribedClubs) then
        return
    end
    local guildType = Enum.ClubType and Enum.ClubType.Guild
    local clubs = Call(Club.GetSubscribedClubs) or {}
    if not clubs[1] then
        lastRun.clubs = nil
    end
    for _, club in ipairs(clubs) do
        if club.clubType ~= guildType then
            Names.AddCommunity(club.name)
            Collect.ClubMembers(club.clubId)
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
    for i = 1, Count(Call(FL.GetNumWhoResults)) do
        local info = Call(FL.GetWhoInfo, i)
        if info then
            Names.AddFull(info.fullName, "other")
            if IsPlain(info.fullGuildName) then
                Names.AddGuild(info.fullGuildName, false)
            end
        end
    end
end

-- A group finder listing: its leader and, where the game tells, every member (addons like
-- Premade Groups Filter and Raider.IO show them all).
local function LearnListing(id)
    local LFG = C_LFGList
    local info = Call(LFG.GetSearchResultInfo, id)
    if not info then
        return
    end
    Names.AddFull(info.leaderName, "other")
    if LFG.GetSearchResultPlayerInfo then
        for i = 1, Count(info.numMembers) do
            local player = Call(LFG.GetSearchResultPlayerInfo, id, i)
            if type(player) == "table" then
                Names.AddFull(player.name, "other")
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
        LearnListing(id)
    end
    Collect.Applicants()
end

function Collect.Listing(id)
    if C_LFGList and C_LFGList.GetSearchResultInfo and id then
        LearnListing(id)
    end
end

function Collect.Applicants()
    local LFG = C_LFGList
    if not (LFG and LFG.GetApplicants) then
        return
    end
    for _, id in ipairs(Call(LFG.GetApplicants) or {}) do
        local info = Call(LFG.GetApplicantInfo, id)
        for i = 1, Count(info and info.numMembers) do
            Names.AddFull((Call(LFG.GetApplicantMemberInfo, id, i)), "other")
        end
    end
end

function Collect.Mail()
    if type(GetInboxNumItems) ~= "function" then
        return
    end
    for i = 1, Count(Call(GetInboxNumItems)) do
        local _, _, sender = Call(GetInboxHeaderInfo, i)
        Names.AddFull(sender, "other")
    end
end

function Collect.Scoreboard()
    local PvP = C_PvP
    if not (PvP and PvP.GetScoreInfo) or type(GetNumBattlefieldScores) ~= "function" then
        return
    end
    for i = 1, Count(Call(GetNumBattlefieldScores)) do
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

local function Read(name, fn)
    lastRun[name] = GetTime()
    Utils.Job(name, fn)
end

-- Everything: when going live. Who is on screen right now (the group, units, plates) at once.
function Collect.All()
    Collect.Self()
    Collect.Group()
    for _, unit in ipairs({ "target", "focus", "targettarget", "focustarget", "mouseover" }) do
        Collect.Unit(unit)
    end
    Collect.Guilds()
    Collect.ClubNames()
    Collect.Mail()
    -- Group finder listings already on screen (and applicants): no new event comes for them.
    Collect.LFG()
    Collect.RecentAllies()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        if plate.namePlateUnitToken then
            Collect.Unit(plate.namePlateUnitToken)
        end
    end
    -- The long lists, a slice per frame, one after the other (each on its own: one failing can't
    -- stop the rest): friends first (their window shows BattleTags), then the guild, the
    -- communities, and names only other addons' saved data holds.
    Read("wow friends", Collect.WoWFriends)
    Read("bn friends", Collect.BNFriends)
    Read("guild", Collect.GuildRoster)
    Read("clubs", Collect.Clubs)
    Utils.Job("archives", OA.Archives.Read)
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        Call(C_GuildInfo.GuildRoster)
    end
end

-- A list the game says changed: read again, but at most every `gap` seconds (a big guild sends
-- its event every few seconds while people log in and out), and a slice per frame.
local function Soon(name, gap, fn, arg)
    if queued[name] then
        return
    end
    local wait = (lastRun[name] or -math.huge) + gap - GetTime()
    if wait <= 0 then
        lastRun[name] = GetTime()
        Utils.Job(name, fn, arg)
        return
    end
    queued[name] = true
    C_Timer.After(wait, function()
        queued[name] = nil
        lastRun[name] = GetTime()
        if OA.live then
            Utils.Job(name, fn, arg)
        end
    end)
end

local function ClubChanged(clubId)
    -- A community joined since going live: its name too.
    Collect.ClubNames()
    if clubId ~= nil and not Utils.IsSecret(clubId) and not IsGuildClub(clubId) then
        Soon("club " .. tostring(clubId), 30, Collect.ClubMembers, clubId)
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
    GUILD_ROSTER_UPDATE = function() Soon("guild", 20, Collect.GuildRoster) end,
    PLAYER_GUILD_UPDATE = Collect.Guilds,
    FRIENDLIST_UPDATE = function() Soon("wow friends", 5, Collect.WoWFriends) end,
    BN_FRIEND_LIST_SIZE_CHANGED = function() Soon("bn friends", 5, Collect.BNFriends) end,
    -- A friend's status changed: the game says which one (the whole list only when it doesn't).
    BN_FRIEND_INFO_CHANGED = function(index)
        if type(index) == "number" and not Utils.IsSecret(index) then
            Collect.Friend(index)
        else
            Soon("bn friends", 5, Collect.BNFriends)
        end
    end,
    -- A friend came online: read them whole (every game account) when the list can say where.
    BN_FRIEND_ACCOUNT_ONLINE = function(id)
        if type(id) ~= "number" or Utils.IsSecret(id) then
            return
        end
        local index = type(BNGetFriendIndex) == "function" and Call(BNGetFriendIndex, id)
        if type(index) == "number" and not Utils.IsSecret(index) then
            Collect.Friend(index)
        else
            Collect.BNetAccount(id)
        end
    end,
    CLUB_ADDED = ClubChanged,
    INITIAL_CLUBS_LOADED = function()
        Collect.ClubNames()
        Soon("clubs", 30, Collect.Clubs)
    end,
    CLUB_MEMBERS_UPDATED = ClubChanged,
    CLUB_MEMBER_ADDED = function(clubId, memberId) Collect.Member(clubId, memberId) end,
    WHO_LIST_UPDATE = Collect.Who,
    -- Whisper senders, from the event itself: a whisper addon may take the line out of chat
    -- before OnAir's chat filter ever sees it.
    CHAT_MSG_WHISPER = function(_, author) Names.AddFull(author, "other") end,
    CHAT_MSG_BN_WHISPER = function(...)
        local id = select(13, ...)
        if id then
            Collect.BNetAccount(id)
        end
    end,
    RECENT_ALLIES_CACHE_UPDATE = Collect.RecentAllies,
    RECENT_ALLY_DATA_UPDATED = Collect.RecentAllies,
    RECENT_ALLIES_DATA_READY = Collect.RecentAllies,
    LFG_LIST_SEARCH_RESULTS_RECEIVED = Collect.LFG,
    LFG_LIST_SEARCH_RESULT_UPDATED = function(id) Collect.Listing(id) end,
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
