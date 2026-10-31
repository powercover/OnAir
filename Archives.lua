local _, OA = ...

-- Names other addons keep in their saved data: OnAir can only replace names it knows, and many
-- show up only there (your alts in AlterEgo, PrioWarband, Syndicator, Narcissus; past key groups
-- in EllesmereUI and MPlusCoach; whisper contacts from past sessions in WhisperMessenger; chat
-- lines EllesmereUI saved before you went live). Read once when going live.
--
-- Only records that are clearly characters count: a name next to a realm, a "Name-Realm" string,
-- a BattleTag, a player link. Loose words (profile names, font names) are never taken, so normal
-- text never gets replaced.
OA.Archives = {}

local Archives = OA.Archives
local Names = OA.Names
local Utils = OA.Utils
local IsPlain = Utils.IsPlainString

local NAME_KEYS = { name = true, fullName = true, playerName = true, senderName = true, characterName = true,
    charName = true, displayName = true, unitName = true, gameAccountName = true }
local REALM_KEYS = { realm = true, realmName = true, server = true, normalizedRealm = true }
local TAG_KEYS = { battleTag = true, bnetTag = true }
local NOTE_KEYS = { note = true, notes = true, nickname = true }

-- "Name-Realm": a capital (or a letter beyond ASCII), no spaces, one hyphen.
local function NameRealm(s)
    return IsPlain(s) and s:find("^[A-Z\195-\244][^%s%-]+%-[%a\195-\244][^%s%-]+$") ~= nil
end

local function Learn(full, kind)
    if kind == "me" then
        local first, second = Names.SplitFull(full)
        OA.db.myChars[Names.MakeKey(first, second)] = true
    end
    Names.AddFull(full, kind)
end

-- Walks a saved table (depth and size limited) for character records.
local function Walk(t, kind, depth, seen, budget)
    budget.left = budget.left - 1
    if budget.left < 0 then
        return
    end
    local name, realm
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "string" then
            if NAME_KEYS[k] then
                name = v
            elseif REALM_KEYS[k] then
                realm = v
            elseif TAG_KEYS[k] and IsPlain(v) and v:find("#%d+$") then
                Names.AddBNet(nil, nil, v, nil)
            elseif NOTE_KEYS[k] and kind ~= "me" then
                Names.AddNote(v)
            end
            for linked in v:gmatch("|Hplayer:([^:|]+)") do
                Names.AddFull(linked, kind == "me" and "other" or kind)
            end
        elseif tv == "table" then
            -- Tables keyed by "Name-Realm" (one per character).
            if type(k) == "string" and NameRealm(k) then
                Learn(k, kind)
            end
            if depth > 0 and not seen[v] then
                seen[v] = true
                Walk(v, kind, depth - 1, seen, budget)
            end
        end
    end
    if IsPlain(name) then
        if IsPlain(realm) and not Utils.IS_FOREVER and not name:find("-", 1, true) then
            Learn(name .. "-" .. realm:gsub("[%s']", ""), kind)
        elseif NameRealm(name) then
            Learn(name, kind)
        end
    end
end

local function Read(global, kind)
    local t = _G[global]
    if type(t) == "table" then
        Walk(t, kind, 9, { [t] = true }, { left = 40000 })
    end
end

-- Your alts: these read as your stage name.
local MINE = { "AlterEgoDB", "PrioWarbandDB", "NarciCharacterProfiles", "NarciBarberShopDB" }
-- Other people: past groups, whisper contacts, saved chat.
local OTHERS = { "EllesmereUIMythicRunsDB", "MPlusCoachGlobalDB", "MPlusCoachDB", "WhisperMessengerDB",
    "WhisperMessengerCharacterDB", "EllesmereUIChatScrollDB" }

function Archives.Read()
    -- Every character of yours OnAir has seen, also the ones you're not playing now.
    for key in pairs(OA.db.myChars) do
        Names.AddFull(key, "me")
    end
    for _, global in ipairs(MINE) do
        Utils.Guard("archive " .. global, Read)(global, "me")
    end
    local api = _G.Syndicator and _G.Syndicator.API
    if api then
        Utils.Guard("archive Syndicator", function()
            for _, full in ipairs(api.GetAllCharacters() or {}) do
                if NameRealm(full) then
                    Learn(full, "me")
                end
            end
            for _, guild in ipairs(api.GetAllGuilds() or {}) do
                local name = type(guild) == "string" and guild:match("^(.+)%-[^%-]+$")
                if name then
                    Names.AddGuild(name, true)
                end
            end
        end)()
    end
    for _, global in ipairs(OTHERS) do
        Utils.Guard("archive " .. global, Read)(global, "other")
    end
end
