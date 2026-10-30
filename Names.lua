local _, OA = ...

-- The name engine. Every player OnAir learns about (from units, chat, rosters, lists) becomes a
-- person with an alias, and Scrub() rewrites any text so their names read as those aliases.
--
-- Who is who:
--   me     your characters        -> your stage name
--   crew   your party or raid     -> Crew settings (cast names or a template)
--   other  everyone else          -> Everyone else settings
--   friend Battle.net friends     -> Everyone else settings, keyed by account
--   pet    pets and minions with a name of their own -> "{owner}'s Pet"
-- Guild names and BattleTags are phrases: replaced as whole strings.
OA.Names = {}

local Names = OA.Names
local Utils = OA.Utils
local L = OA.L
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString

local RANK = { me = 4, crew = 3, friend = 2, pet = 2, other = 1 }
local WHO = { me = "me", crew = "crew", other = "others", friend = "friends", pet = "pets" }

local people = {}       -- key -> person
local words = {}        -- a name as it appears in text -> alias
local wordRank = {}     -- word -> rank of the person who holds it
local aliasStarts = {}  -- first word of an alias -> { alias, ... } (so aliases are never rewritten)
local phrases = {}      -- { text = , alias = } longest first
local phraseByText = {}
local tokens = {}       -- Battle.net |K..|k name token -> alias
local used = {}         -- alias -> true
local realOf = {}       -- alias -> who it stands for ("Name-Realm", or a Battle.net name token)
local cache, cacheSize = {}, 0
local customLower = {}

local function DB()
    return OA.db
end

local function WhoEnabled(kind)
    local db = DB()
    return db and db.who[WHO[kind] or kind] ~= false
end

local function Changed()
    wipe(cache)
    cacheSize = 0
    if Names.OnChanged then
        Names.OnChanged()
    end
end

local function SafeBool(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then
        return nil
    end
    return value
end
Names.SafeBool = SafeBool

---------------------------------------------------------------------------------------------- keys

local SEP = Utils.SurnameSeparator()

-- A person's key: "Name-Realm" on Retail, "First Surname" on Forever (or just the first name
-- while the second part isn't known).
local function MakeKey(first, second)
    if Utils.IS_FOREVER then
        if IsPlain(second) then
            return first .. SEP .. second
        end
        return first
    end
    local realm = IsPlain(second) and second or Utils.MyRealm()
    if realm then
        return first .. "-" .. realm
    end
    return first
end

Names.MakeKey = MakeKey

-- "Name-Realm" / "First Surname" / "Name" -> first, second.
local function SplitFull(full)
    if Utils.IS_FOREVER then
        local first, rest = full:match("^(.-)" .. SEP:gsub("%p", "%%%0") .. "(.+)$")
        if first and first ~= "" then
            return first, rest
        end
        return full, nil
    end
    local first, realm = full:match("^([^%-]+)%-(.+)$")
    if first then
        return first, realm
    end
    return full, nil
end
Names.SplitFull = SplitFull

---------------------------------------------------------------------------------------------- aliases

local ROLE_TEXT = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["DPS"] }

local function MeAlias()
    local db = DB()
    local me = db and db.me
    if type(me) == "string" and me ~= "" then
        return me
    end
    return L["The Star"]
end
Names.MeAlias = MeAlias

local function Fill(template, n, person)
    return (template:gsub("{(%a+)}", function(token)
        if token == "me" then
            return MeAlias()
        elseif token == "n" then
            return tostring(n)
        elseif token == "role" then
            return person and ROLE_TEXT[person.role] or L["Crew"]
        elseif token == "class" then
            return person and person.class or L["Adventurer"]
        elseif token == "owner" then
            local owner = person and person.owner and people[person.owner]
            return owner and owner.alias or L["Someone"]
        end
    end))
end
Names.Fill = Fill

local function Unique(alias)
    if not used[alias] then
        return alias
    end
    for i = 2, 999 do
        local candidate = alias .. " " .. i
        if not used[candidate] then
            return candidate
        end
    end
    return alias
end

local function FromCast(key)
    local list = OA.Cast.Get(DB().theme).cast
    local start = Utils.Hash(key) % #list
    for step = 0, #list - 1 do
        local pick = list[(start + step) % #list + 1]
        if not used[pick] then
            return pick
        end
    end
    return Unique(list[start + 1])
end

local function Generate(person)
    local db = DB()
    if person.kind == "pet" then
        return Unique(Fill(db.petTemplate, 0, person))
    end
    local group = person.kind == "crew" and db.crew or db.others
    if group.mode == "template" then
        local counter = person.kind == "crew" and "crew" or "others"
        db.counters[counter] = (db.counters[counter] or 0) + 1
        return Unique(Fill(group.template, db.counters[counter], person))
    end
    return FromCast(person.key)
end

local function CustomFor(person)
    local key = person.key:lower()
    return customLower[key] or customLower[person.first:lower()]
end

local function AliasFor(person)
    local db = DB()
    local custom = CustomFor(person)
    if custom then
        return custom
    end
    if person.kind == "me" then
        return MeAlias()
    end
    if person.forced then
        return person.forced
    end
    local assigned = db.assigned[person.key]
    if assigned and (RANK[db.assignedKind[person.key]] or 0) >= RANK[person.kind] then
        return assigned
    end
    if assigned then
        used[assigned] = nil
    end
    local alias = Generate(person)
    db.assigned[person.key] = alias
    db.assignedKind[person.key] = person.kind
    return alias
end

---------------------------------------------------------------------------------------------- words

local function AddAliasStart(alias)
    local first = alias:match("^[%a\128-\255]+")
    if not first then
        return
    end
    local list = aliasStarts[first]
    if not list then
        list = {}
        aliasStarts[first] = list
    end
    for _, existing in ipairs(list) do
        if existing == alias then
            return
        end
    end
    list[#list + 1] = alias
    table.sort(list, function(a, b) return #a > #b end)
end

local function PutWord(word, alias, rank)
    if not IsPlain(word) or #word < 2 then
        return false
    end
    if words[word] == alias then
        return false
    end
    if words[word] and (wordRank[word] or 0) > rank then
        return false
    end
    words[word] = alias
    wordRank[word] = rank
    return true
end

local function Publish(person)
    if not WhoEnabled(person.kind) then
        return false
    end
    local alias = AliasFor(person)
    person.alias = alias
    used[alias] = true
    AddAliasStart(alias)
    if person.kind ~= "pet" and (not realOf[alias] or person.kind ~= "friend") then
        realOf[alias] = person.key
    end
    local rank = RANK[person.kind]
    local changed = PutWord(person.key, alias, rank)
    if PutWord(person.first, alias, rank) then
        changed = true
    end
    if person.realmOnly then
        -- Retail names in text can carry the realm with or without its spaces.
        changed = PutWord(person.first .. "-" .. person.realmOnly, alias, rank) or changed
    end
    return changed
end

-- Learns a person, or updates what we know (a stranger who joins the group becomes crew).
function Names.Add(first, second, kind, info)
    if not IsPlain(first) then
        return nil
    end
    if IsSecret(second) then
        second = nil
    end
    if Utils.IS_FOREVER and not second then
        local f, s = SplitFull(first)
        first, second = f, s
    end
    local key = MakeKey(first, second)
    local db = DB()
    if db.myChars[key] then
        kind = "me"
    end
    local person = people[key]
    if person then
        if RANK[kind] <= RANK[person.kind] then
            return person
        end
        person.kind = kind
    else
        person = { key = key, first = first, kind = kind }
        people[key] = person
    end
    if info then
        person.class = info.class or person.class
        person.role = info.role or person.role
        person.owner = info.owner or person.owner
        person.forced = info.forced or person.forced
    end
    if Publish(person) then
        Changed()
    end
    return person
end

-- "Name-Realm" / "First Surname" / "Name" from chat and rosters.
function Names.AddFull(full, kind, info)
    if not IsPlain(full) then
        return nil
    end
    local first, second = SplitFull(full)
    return Names.Add(first, second, kind, info)
end

function Names.Get(key)
    return people[key]
end

function Names.AliasOfFull(full)
    if not IsPlain(full) then
        return nil
    end
    local person = Names.AddFull(full, "other")
    return person and person.alias
end

---------------------------------------------------------------------------------------------- units

local function UnitInfo(unit)
    local info = {}
    local ok, class = pcall(UnitClass, unit)
    if ok and IsPlain(class) then
        info.class = class
    end
    local role = SafeBool(UnitGroupRolesAssigned, unit)
    if role and role ~= "NONE" then
        info.role = role
    end
    return info
end

local function PetOwnerUnit(unit)
    if unit == "pet" then
        return "player"
    end
    local index = unit:match("^partypet(%d)$")
    if index then
        return "party" .. index
    end
    index = unit:match("^raidpet(%d+)$")
    if index then
        return "raid" .. index
    end
    return nil
end

-- A pet named by its owner. A pet still carrying its family's name ("Wolf") is left alone:
-- that word is also every wolf in the world.
local function AddPet(unit, ownerUnit)
    local ok, name = pcall(UnitName, unit)
    if not ok or not IsPlain(name) then
        return
    end
    local family = SafeBool(UnitCreatureFamily, unit)
    if family and family == name then
        return
    end
    local owner = Names.AddUnit(ownerUnit)
    if not owner then
        return
    end
    local key = "pet:" .. owner.key .. ":" .. name
    local person = people[key]
    if not person then
        person = { key = key, first = name, kind = "pet", owner = owner.key }
        people[key] = person
        if Publish(person) then
            Changed()
        end
    end
end

-- Learns the player behind a unit token. Returns the person.
function Names.AddUnit(unit)
    if type(unit) ~= "string" or not SafeBool(UnitExists, unit) then
        return nil
    end
    if not SafeBool(UnitIsPlayer, unit) then
        local ownerUnit = PetOwnerUnit(unit)
        if ownerUnit then
            AddPet(unit, ownerUnit)
        end
        return nil
    end
    local ok, first, second = pcall(UnitName, unit)
    if not ok or not IsPlain(first) then
        return nil
    end
    local kind = "other"
    if SafeBool(UnitIsUnit, unit, "player") then
        kind = "me"
    elseif SafeBool(UnitInParty, unit) or SafeBool(UnitInRaid, unit) then
        kind = "crew"
    end
    return Names.Add(first, second, kind, UnitInfo(unit))
end

function Names.IsHiddenKind(kind)
    return WhoEnabled(kind)
end

---------------------------------------------------------------------------------------------- phrases

local function SortPhrases()
    table.sort(phrases, function(a, b) return #a.text > #b.text end)
end

local function AddPhrase(text, alias)
    if not IsPlain(text) or #text < 3 then
        return
    end
    local existing = phraseByText[text]
    if existing then
        if existing.alias == alias then
            return
        end
        existing.alias = alias
    else
        existing = { text = text, alias = alias }
        phraseByText[text] = existing
        phrases[#phrases + 1] = existing
        SortPhrases()
    end
    AddAliasStart(alias)
    Changed()
end

-- Guild names: yours gets your guild alias, others a numbered one.
function Names.AddGuild(name, mine)
    if not IsPlain(name) or not WhoEnabled("guilds") then
        return
    end
    local db = DB()
    local alias
    if mine then
        alias = Fill(db.guildAlias, 0)
    else
        local key = "guild:" .. name
        alias = db.assigned[key]
        if not alias then
            db.counters.guilds = (db.counters.guilds or 0) + 1
            alias = Unique(Fill(db.otherGuild, db.counters.guilds))
            db.assigned[key] = alias
            db.assignedKind[key] = "other"
        end
        used[alias] = true
    end
    AddPhrase(name, alias)
end

-- A Battle.net friend: the account's name token, its BattleTag and the character it plays all
-- read as one alias.
function Names.AddBNet(accountID, token, battleTag, characterFull)
    if not WhoEnabled("friends") then
        return nil
    end
    local key = "bn:" .. tostring(accountID or token or battleTag)
    local person = people[key]
    if not person then
        person = { key = key, first = key, kind = "friend" }
        people[key] = person
        person.alias = AliasFor(person)
        used[person.alias] = true
        AddAliasStart(person.alias)
    end
    if type(token) == "string" and not IsSecret(token) then
        -- Whispers to the alias go to this account (Chat.lua swaps the target back).
        realOf[person.alias] = token
        if tokens[token] ~= person.alias then
            tokens[token] = person.alias
            Changed()
        end
    end
    if IsPlain(battleTag) then
        AddPhrase(battleTag, person.alias)
    end
    if IsPlain(characterFull) then
        Names.AddFull(characterFull, "friend", { forced = person.alias })
    end
    return person.alias
end

-- Your own BattleTag. The friends window draws it as the name plus a colored "#1234", so the
-- name and the number are replaced on their own too.
local ownTag
function Names.AddOwnBattleTag(tag)
    if not IsPlain(tag) or not WhoEnabled("me") then
        return
    end
    ownTag = tag
    local base, number = tag:match("^(.-)(#%d+)$")
    AddPhrase(tag, MeAlias())
    if base and #base >= 3 then
        AddPhrase(base, MeAlias())
        AddPhrase(number, "")
    end
end

-- Places to keep off screen (Shield: your zone and subzone while live). They read "Somewhere".
function Names.SetHiddenPlaces(list)
    for i = #phrases, 1, -1 do
        if phrases[i].place then
            phraseByText[phrases[i].text] = nil
            table.remove(phrases, i)
        end
    end
    local alias = L["Somewhere"]
    for _, text in ipairs(list) do
        if IsPlain(text) and #text >= 3 and not phraseByText[text] then
            local entry = { text = text, alias = alias, place = true }
            phraseByText[text] = entry
            phrases[#phrases + 1] = entry
        end
    end
    SortPhrases()
    AddAliasStart(alias)
    Changed()
end

-- Who an alias stands for, so a whisper to it reaches them. Nil for anything else.
function Names.RealOf(alias)
    if type(alias) ~= "string" or IsSecret(alias) then
        return nil
    end
    return realOf[alias]
end

-- A protected text token (|K..|k) that isn't a friend we know: group finder titles and comments,
-- voice chat names, a friend added while live. Its content can't be read, so it can't be judged:
-- it just reads "(hidden)".
local function TokenAlias(token)
    local alias = tokens[token]
    if alias then
        return alias
    end
    if not WhoEnabled("friends") then
        return nil
    end
    return L["(hidden)"]
end

-- Community names: like guild names, numbered.
function Names.AddCommunity(name)
    if not IsPlain(name) or not WhoEnabled("guilds") then
        return
    end
    local db = DB()
    local key = "club:" .. name
    local alias = db.assigned[key]
    if not alias then
        db.counters.clubs = (db.counters.clubs or 0) + 1
        alias = Unique(Fill(db.communityTemplate, db.counters.clubs))
        db.assigned[key] = alias
        db.assignedKind[key] = "other"
    end
    used[alias] = true
    AddPhrase(name, alias)
end

---------------------------------------------------------------------------------------------- scrub

local CACHE_LIMIT = 4000
local PH_OPEN, PH_CLOSE = "\001", "\002"

local function ReplacePhrases(s, held)
    for i = 1, #phrases do
        local p = phrases[i]
        if s:find(p.text, 1, true) then
            local parts, last = {}, 1
            while true do
                local a, b = s:find(p.text, last, true)
                if not a then
                    break
                end
                parts[#parts + 1] = s:sub(last, a - 1)
                held[#held + 1] = p.alias
                parts[#parts + 1] = PH_OPEN .. #held .. PH_CLOSE
                last = b + 1
            end
            parts[#parts + 1] = s:sub(last)
            s = table.concat(parts)
        end
    end
    return s
end

local function SkipEscape(s, a, len)
    local nx = s:sub(a + 1, a + 1)
    local close = (nx == "H" and "|h") or (nx == "T" and "|t") or (nx == "A" and "|a") or nil
    if close then
        local e = s:find(close, a + 2, true)
        return e and e + 2 or len + 1
    elseif nx == "c" then
        if s:sub(a + 2, a + 2) == "n" then
            local e = s:find(":", a + 3, true)
            return e and e + 1 or a + 2
        end
        return a + 10
    end
    return a + 2
end

local function ScrubRaw(s)
    local held = {}
    if #phrases > 0 then
        s = ReplacePhrases(s, held)
    end
    local len = #s
    local parts, last, i = nil, 1, 1
    while i <= len do
        local a = s:find("[|%a\128-\255]", i)
        if not a then
            break
        end
        local alias, stop
        if s:byte(a) == 124 then -- "|": an escape sequence
            if s:sub(a + 1, a + 1) == "K" then
                local e = s:find("|k", a + 2, true)
                if e then
                    alias = TokenAlias(s:sub(a, e + 1))
                    stop = e + 1
                end
                i = e and e + 2 or len + 1
            else
                i = SkipEscape(s, a, len)
            end
        else
            local _, e = s:find("^[%a\128-\255]+", a)
            local word = s:sub(a, e)
            local starts = aliasStarts[word]
            local kept
            if starts then
                for _, al in ipairs(starts) do
                    if s:sub(a, a + #al - 1) == al then
                        kept = a + #al
                        break
                    end
                end
            end
            if kept then
                i = kept
            else
                stop = e
                -- "Name-Realm"
                local _, re = s:find("^%-[%a\128-\255']+", e + 1)
                if re then
                    alias = words[s:sub(a, re)]
                    if alias or words[word] then
                        stop = re
                    end
                end
                -- "First Surname" (Forever)
                if not alias and Utils.IS_FOREVER then
                    local _, se = s:find("^ [%a\128-\255]+", e + 1)
                    if se then
                        alias = words[s:sub(a, se)]
                        if alias then
                            stop = se
                        end
                    end
                end
                alias = alias or words[word]
                i = stop + 1
            end
        end
        if alias then
            parts = parts or {}
            parts[#parts + 1] = s:sub(last, a - 1)
            parts[#parts + 1] = alias
            last = stop + 1
        end
    end
    if parts then
        parts[#parts + 1] = s:sub(last)
        s = table.concat(parts)
    end
    if #held > 0 then
        s = s:gsub(PH_OPEN .. "(%d+)" .. PH_CLOSE, function(n) return held[tonumber(n)] end)
    end
    return s
end

-- The text with every known name replaced. Secret values come back untouched (unreadable).
function Names.Scrub(text)
    if type(text) ~= "string" or IsSecret(text) or text == "" then
        return text
    end
    local hit = cache[text]
    if hit then
        return hit
    end
    local out = text
    if text:find("[%a\128-\255|]") then
        out = ScrubRaw(text)
    end
    if cacheSize >= CACHE_LIMIT then
        wipe(cache)
        cacheSize = 0
    end
    cache[text] = out
    cacheSize = cacheSize + 1
    return out
end

---------------------------------------------------------------------------------------------- settings

local function RebuildCustom()
    wipe(customLower)
    for real, alias in pairs(DB().custom) do
        if type(real) == "string" and type(alias) == "string" and alias ~= "" then
            customLower[Utils.Trim(real):lower()] = alias
        end
    end
end

-- After a settings change: aliases are worked out again for everyone we know.
-- `reshuffle` also forgets the remembered aliases, so everyone draws a new one.
function Names.Rebuild(reshuffle)
    local db = DB()
    if reshuffle then
        wipe(db.assigned)
        wipe(db.assignedKind)
        wipe(db.counters)
    end
    RebuildCustom()
    wipe(words)
    wipe(wordRank)
    wipe(aliasStarts)
    wipe(used)
    wipe(realOf)
    wipe(tokens)
    wipe(phrases)
    wipe(phraseByText)
    for _, alias in pairs(db.assigned) do
        used[alias] = true
    end
    local list = {}
    for _, person in pairs(people) do
        list[#list + 1] = person
    end
    -- Owners before their pets, the group before strangers.
    table.sort(list, function(a, b)
        if a.kind == "pet" ~= (b.kind == "pet") then
            return b.kind == "pet"
        end
        return RANK[a.kind] > RANK[b.kind]
    end)
    for _, person in ipairs(list) do
        if person.kind == "friend" and person.key:find("^bn:") then
            person.alias = AliasFor(person)
            used[person.alias] = true
        else
            Publish(person)
        end
    end
    if OA.Collect and OA.Collect.Guilds then
        OA.Collect.Guilds()
        OA.Collect.ClubNames()
    end
    if ownTag then
        Names.AddOwnBattleTag(ownTag)
    end
    if OA.Shield and OA.Shield.RefreshPlaces then
        OA.Shield.RefreshPlaces()
    end
    Changed()
end

function Names.Init()
    RebuildCustom()
    for _, alias in pairs(DB().assigned) do
        used[alias] = true
    end
end

-- For the console preview: alias of a made-up player of a kind, without remembering it.
function Names.Sample(kind, n, seed)
    local db = DB()
    if kind == "me" then
        return MeAlias()
    end
    local group = kind == "crew" and db.crew or db.others
    if group.mode == "template" then
        return Fill(group.template, n, { role = (n == 1 and "TANK") or (n == 2 and "HEALER") or "DAMAGER" })
    end
    local list = OA.Cast.Get(db.theme).cast
    return list[(Utils.Hash(seed or (kind .. n)) % #list) + 1]
end

function Names.Count()
    local n = 0
    for _ in pairs(people) do
        n = n + 1
    end
    return n
end
