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
-- A fixed alias (Custom page) goes for whoever it names, whatever the "Whose names" switches say.
OA.Names = {}

local Names = OA.Names
local Utils = OA.Utils
local L = OA.L
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString

local RANK = { me = 4, crew = 3, friend = 2, pet = 2, other = 1 }
-- A name on the Custom page: above everyone, whoever it turns out to be.
local FIXED_RANK = 5
local WHO ={ me = "me", crew = "crew", other = "others", friend = "friends", pet = "pets" }

local people = {}       -- key -> person
local peopleCount = 0
local words = {}        -- a name as it appears in text -> alias
local wordRank = {}     -- word -> rank of the person who holds it
local aliasStarts = {}  -- first word of an alias -> { alias, ... } (so aliases are never rewritten)
local phrases = {}      -- { text = , alias = } longest first
local phraseByText = {}
local tokens = {}       -- Battle.net |K..|k name token -> alias
local used = {}         -- alias -> true
local realOf = {}       -- alias -> who it stands for ("Name-Realm", or a Battle.net name token)
local cache, cacheSize = {}, 0
local cacheStale = false
local customLower = {}
local surnames = {}     -- Forever: a surname seen on someone -> their alias

local function DB()
    return OA.db
end

local function WhoEnabled(kind)
    local db = DB()
    return db and db.who[WHO[kind] or kind] ~= false
end

-- Names learned since the last look (Hide fixes the text that holds them, nothing more).
local newWords = {}

function Names.TakeNewWords()
    local list = newWords
    newWords = {}
    return list
end

-- How text is cut into words for that: a run starting with a letter ("Bob's", "Name-Realm"), and
-- only the ones that can be a name (a capital, or a letter outside plain ASCII). Hide indexes the
-- labels on screen the same way.
local WORD = "[%a\128-\255][%w\128-\255'%-]*"
Names.WORD = WORD

local function IndexWord(word)
    local first = word:byte(1)
    return #word >= 2 and (first >= 128 or (first >= 65 and first <= 90))
end
Names.IsIndexWord = IndexWord

-- A guild, community, BattleTag or place learned while live: its words count as new too, so text
-- already on screen that holds it is looked at again.
local function NewWordsOf(text)
    if not OA.live then
        return
    end
    for word in text:gmatch(WORD) do
        if IndexWord(word) then
            newWords[#newWords + 1] = word
        end
    end
end

-- Words starting the same (first 3 bytes), for a name cut short with "..." (see Shortened).
local byStart = {}

local function IndexStart(word)
    if #word >= 3 then
        local head = word:sub(1, 3)
        local list = byStart[head]
        if not list then
            list = {}
            byStart[head] = list
        end
        list[#list + 1] = word
    end
end

-- Something a text could be scrubbed with changed. The cache is emptied on the next scrub, not
-- here: going live or reading a guild learns hundreds of names in a row.
local function Changed()
    cacheStale = true
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

-- Asked once it's known (before login the game may not have it yet).
local myRealm
local function MyRealm()
    if not myRealm then
        myRealm = Utils.MyRealm()
    end
    return myRealm
end

-- A person's key: "Name-Realm" on Retail, "First Surname" on Forever (or just the first name
-- while the second part isn't known).
local function MakeKey(first, second)
    if Utils.IS_FOREVER then
        if IsPlain(second) then
            return first .. SEP .. second
        end
        return first
    end
    local realm = IsPlain(second) and second or MyRealm()
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
            if person and person.ownerAlias then
                return person.ownerAlias
            end
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

-- How a name on the Custom page is looked up: small letters, and a realm without its spaces, dashes
-- and apostrophes however it was typed ("Bob-Twisting Nether" is the game's "Bob-TwistingNether").
local function FixedKey(name)
    local first, realm = name:match("^([^%-]+)%-(.+)$")
    if first and not Utils.IS_FOREVER then
        return (first .. "-" .. realm:gsub("[%s'%-]", "")):lower()
    end
    return name:lower()
end

local function CustomFor(person)
    if not next(customLower) then
        return nil
    end
    return customLower[FixedKey(person.key)] or customLower[person.first:lower()]
end

-- What the character you play now is called: its fixed alias (Custom page) if it has one, else your
-- stage name, the same as wherever its name is swapped. For what names you without your name in it:
-- your damage meter row while names are secret, a cast aimed at you.
function Names.MyAlias()
    local ok, first, second = pcall(UnitName, "player")
    if ok and IsPlain(first) then
        local key = MakeKey(first, IsPlain(second) and second or nil)
        local custom = customLower[FixedKey(key)] or customLower[first:lower()]
        if custom then
            return custom
        end
    end
    return MeAlias()
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
    if words[word] == nil then
        IndexStart(word)
        -- For Hide's late fix (text shown before the name was known); only while live.
        if OA.live then
            newWords[#newWords + 1] = word
        end
    end
    words[word] = alias
    wordRank[word] = rank
    return true
end

local function Publish(person)
    -- Their group is off and nothing fixes an alias for them: they read as themselves (also a sender
    -- in chat, who'd keep the alias from before the switch went off).
    if not WhoEnabled(person.kind) and not person.fixed and not CustomFor(person) then
        person.alias = nil
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
    if Utils.IS_FOREVER and person.kind ~= "pet" then
        local surname = person.key:sub(#person.first + #SEP + 1)
        if surname ~= "" then
            surnames[surname] = alias
        end
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
    elseif Utils.IS_FOREVER and IsPlain(second) then
        -- Some units carry the surname in the first value too: ("Anna Smith", "Smith").
        local tail = SEP .. second
        if first:sub(-#tail) == tail then
            first = first:sub(1, -#tail - 1)
        end
    end
    if second and not Utils.IS_FOREVER then
        Names.AddRealm(second)
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
        peopleCount = peopleCount + 1
    end
    if info then
        person.class = info.class or person.class
        person.role = info.role or person.role
        person.owner = info.owner or person.owner
        person.forced = info.forced or person.forced
        person.fixed = info.fixed or person.fixed
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

-- For /onair check: is this a word OnAir replaces (a real name)?
function Names.IsRealWord(word)
    return IsPlain(word) and words[word] ~= nil
end

-- Every word that appears in some alias ("Star" in "The Star"): those aren't leaks.
function Names.AliasWords()
    local set = {}
    for alias in pairs(used) do
        for w in alias:gmatch("[^%s]+") do
            set[w] = true
        end
    end
    return set
end

-- Notes on friends, guild members and contacts: anything goes in them (real names too). A label
-- whose whole text is a note is emptied while live; a note is never matched inside other text,
-- so a short note like "tank" doesn't eat that word everywhere.
local notes = {}
local notesNew = false   -- a note learned while live (Hide looks the screen over again)
local noteSeen = {}      -- raw note text -> true (rosters are read again and again)
local noteCache, noteCacheSize = {}, 0
local NOTE_CACHE_LIMIT = 2000

local function NoteKey(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Names.AddNote(text)
    if not IsPlain(text) or noteSeen[text] then
        return
    end
    noteSeen[text] = true
    local key = NoteKey(text)
    if key ~= "" and not notes[key] then
        notes[key] = true
        wipe(noteCache)
        noteCacheSize = 0
        if OA.live then
            notesNew = true
            if Names.OnChanged then
                Names.OnChanged()
            end
        end
    end
end

function Names.TakeNotesNew()
    local new = notesNew
    notesNew = false
    return new
end

-- Asked for every text the UI sets while live, so the answer for a text is kept.
function Names.IsNote(text)
    if not IsPlain(text) or not next(notes) then
        return false
    end
    local hit = noteCache[text]
    if hit ~= nil then
        return hit
    end
    local key = NoteKey(text)
    -- Also "Note: ..." and the like: a short label in front of the note.
    local found = notes[key] == true or notes[key:match("^[^:]+:%s*(.+)$") or ""] == true
    if noteCacheSize >= NOTE_CACHE_LIMIT then
        wipe(noteCache)
        noteCacheSize = 0
    end
    noteCache[text] = found
    noteCacheSize = noteCacheSize + 1
    return found
end

-- Multi-word names (guilds, BattleTags, communities) for /onair check.
function Names.Phrases()
    local list = {}
    for _, phrase in ipairs(phrases) do
        -- A name kept on purpose (see KeepWhole) is no leak.
        if phrase.alias ~= phrase.text then
            list[#list + 1] = phrase.text
        end
    end
    return list
end

-- Does OnAir know this player ("Name-Realm" or "Name") without learning it now?
function Names.Knows(full)
    if not IsPlain(full) then
        return false
    end
    local first, second = SplitFull(full)
    return people[MakeKey(first, second)] ~= nil or words[full] ~= nil or (IsPlain(first) and words[first] ~= nil)
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
        peopleCount = peopleCount + 1
        if Publish(person) then
            Changed()
        end
    end
end

-- "Jennie's Minion": the owner line under a pet's name (its tooltip), in the game's own words for
-- every language. The owner part is taken whole: it can be the real name or, when the line was
-- masked first, the owner's alias already.
local ownerPatterns
local OWNER_TITLES = { "UNITNAME_TITLE_PET", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_CHARM",
    "UNITNAME_TITLE_COMPANION", "UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_SQUIRE", "UNITNAME_TITLE_OPPONENT" }

local function OwnerPatterns()
    if ownerPatterns then
        return ownerPatterns
    end
    ownerPatterns = {}
    local formats = {}
    for _, global in ipairs(OWNER_TITLES) do
        formats[#formats + 1] = _G[global]
    end
    for i = 1, 30 do
        formats[#formats + 1] = _G["UNITNAME_SUMMON_TITLE" .. i]
    end
    for _, format in ipairs(formats) do
        if type(format) == "string" and format:find("%s", 1, true) then
            local plain = format:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local pattern = plain:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", function() return "(.-)" end)
            ownerPatterns[#ownerPatterns + 1] = "^<?" .. pattern .. ">?$"
        end
    end
    return ownerPatterns
end

-- The owner a pet's line names ("Jennie's Minion" -> "Jennie"), or nil.
function Names.OwnerIn(text)
    if not IsPlain(text) then
        return nil
    end
    local line = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _, pattern in ipairs(OwnerPatterns()) do
        local owner = line:match(pattern)
        if owner then
            return owner
        end
    end
    return nil
end

-- What a pet reads as when its own name isn't learned (a stranger's demon): "{owner}'s Pet", the
-- owner by their alias (learned here when it's their real name).
function Names.PetLabel(owner)
    local alias
    if IsPlain(owner) then
        if used[owner] then
            alias = owner
        else
            local person = Names.AddFull(owner, "other")
            alias = person and person.alias
        end
    end
    return Fill(DB().petTemplate, 0, { kind = "pet", ownerAlias = alias })
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
    -- Known already, as this kind or more, with the class read: only the group role can change.
    local realm = second
    if IsSecret(realm) then
        realm = nil
    end
    local known = people[MakeKey(first, realm)]
    if known and known.class and RANK[kind] <= RANK[known.kind] then
        local role = SafeBool(UnitGroupRolesAssigned, unit)
        if role and role ~= "NONE" then
            known.role = role
        end
        return known
    end
    return Names.Add(first, second, kind, UnitInfo(unit))
end

function Names.IsHiddenKind(kind)
    return WhoEnabled(kind)
end

---------------------------------------------------------------------------------------------- phrases

-- Sorted (longest first) and split the next time a text is scrubbed, not on every new phrase.
-- BattleTags (most phrases: one per friend) are looked up by their "#1234" in the text instead of
-- being searched for one by one.
local phrasesStale = false
local tagPhrases = {}    -- "#1234" -> { phrase, ... } longest first
local otherPhrases = {}  -- guilds, communities, places: longest first

local function SortPhrases()
    phrasesStale = true
end

local function Longer(a, b)
    return #a.text > #b.text
end

local function SplitPhrases()
    phrasesStale = false
    table.sort(phrases, Longer)
    wipe(tagPhrases)
    wipe(otherPhrases)
    for _, p in ipairs(phrases) do
        local tag = p.text:match("#%d+$")
        if tag then
            local list = tagPhrases[tag]
            if not list then
                list = {}
                tagPhrases[tag] = list
            end
            list[#list + 1] = p
        else
            otherPhrases[#otherPhrases + 1] = p
        end
    end
end

-- One-word names of other guilds and of communities ("Progress", "Legacy") are everyday words
-- too: those are replaced only where the whole text is the name (a guild line, "<Progress>",
-- "Progress-Realm"), never inside other text ("Raider.IO Raid Progress").
local wholeNames = {}   -- name -> alias

local function AddPhrase(text, alias, wholeOnly)
    if not IsPlain(text) or #text < 3 then
        return
    end
    if wholeOnly and not text:find("%s") then
        if wholeNames[text] == alias then
            return
        end
        wholeNames[text] = alias
        AddAliasStart(alias)
        NewWordsOf(text)
        Changed()
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
    NewWordsOf(text)
    Changed()
end

-- A guild or community with its switch off stays as it is: a word in its name can be someone's name
-- ("Ten Past Zed"), and their alias doesn't belong in there. One word alone goes the usual way: it
-- could just as well be that person, and a real name must not show because of it.
local function KeepWhole(name)
    if name:find("%s") then
        AddPhrase(name, name)
    end
end

-- Guild names: yours gets your guild alias, others a numbered one.
function Names.AddGuild(name, mine)
    if not IsPlain(name) then
        return
    end
    if not WhoEnabled("guilds") then
        KeepWhole(name)
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
    -- Your own guild is replaced everywhere; one-word names of other guilds only on their own.
    AddPhrase(name, alias, not mine)
end

-- Battle.net friends, by account. What's known of each is kept, also while their switch is off: a
-- settings change works them out again from here (the game's lists are read only when the game
-- says they changed).
local friends = {}

-- A friend's fixed alias (Custom page): typed as their BattleTag, with or without its "#1234", or
-- as a character they were seen on.
local function FixedForFriend(person)
    if not next(customLower) then
        return nil
    end
    if person.battleTag then
        local tag = person.battleTag:lower()
        local fixed = customLower[tag] or customLower[tag:match("^(.-)#%d+$") or tag]
        if fixed then
            return fixed
        end
    end
    for full in pairs(person.chars) do
        local fixed = customLower[FixedKey(full)] or customLower[(SplitFull(full)):lower()]
        if fixed then
            return fixed
        end
    end
    return nil
end

-- A friend's character reads as their account. One OnAir knows as more than a friend (in your
-- group) keeps its own alias, unless the friend's alias is fixed.
local function ForceCharacter(full, alias, fixed)
    local person = Names.AddFull(full, "friend", { forced = alias, fixed = fixed })
    if person and (fixed or person.kind == "friend") and (person.forced ~= alias or person.fixed ~= fixed) then
        person.forced, person.fixed = alias, fixed
        if Publish(person) then
            Changed()
        end
    end
end

-- The account's name token, its BattleTag and every character it was seen on all read as one alias.
local function PublishFriend(person)
    local fixed = FixedForFriend(person)
    if not fixed and not WhoEnabled("friends") then
        person.alias = nil
        return nil
    end
    if not people[person.key] then
        people[person.key] = person
        peopleCount = peopleCount + 1
    end
    local alias = fixed or AliasFor(person)
    person.alias = alias
    used[alias] = true
    AddAliasStart(alias)
    if person.token then
        -- Whispers to the alias go to this account (Chat.lua swaps the target back).
        realOf[alias] = person.token
        if tokens[person.token] ~= alias then
            tokens[person.token] = alias
            Changed()
        end
    end
    if person.battleTag then
        AddPhrase(person.battleTag, alias)
        -- The name without "#1234" too, as a whole word: EllesmereUI's friends tooltip and others
        -- show the BattleTag cut short ("DarkStriker (Character)").
        local short = person.battleTag:match("^(.-)#%d+$")
        if short and PutWord(short, alias, fixed and FIXED_RANK or RANK.friend) then
            Changed()
        end
    end
    for full in pairs(person.chars) do
        ForceCharacter(full, alias, fixed and true or nil)
    end
    return alias
end

function Names.AddBNet(accountID, token, battleTag, characterFull)
    local key = "bn:" .. tostring(accountID or token or battleTag)
    local person = friends[key]
    if not person then
        person = { key = key, first = key, kind = "friend", chars = {} }
        friends[key] = person
    end
    if type(token) == "string" and not IsSecret(token) then
        person.token = token
    end
    if IsPlain(battleTag) then
        person.battleTag = battleTag
    end
    if IsPlain(characterFull) then
        person.chars[characterFull] = true
    end
    return PublishFriend(person)
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
local placesNow = ""

function Names.SetHiddenPlaces(list)
    -- Zone events come often (every subzone): only a real change rebuilds anything.
    local sig = table.concat(list, "\001")
    if sig == placesNow then
        return
    end
    placesNow = sig
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
            NewWordsOf(text)
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
    if not IsPlain(name) then
        return
    end
    if not WhoEnabled("guilds") then
        KeepWhole(name)
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
    AddPhrase(name, alias, true)
end

---------------------------------------------------------------------------------------------- scrub

local CACHE_LIMIT = 4000
local PH_OPEN, PH_CLOSE = "\001", "\002"

local function ReplaceOne(s, p, held)
    if not s:find(p.text, 1, true) then
        return s
    end
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
    return table.concat(parts)
end

local function ReplacePhrases(s, held)
    if phrasesStale then
        SplitPhrases()
    end
    if next(tagPhrases) and s:find("#", 1, true) then
        for tag in s:gmatch("#%d+") do
            local list = tagPhrases[tag]
            if list then
                for i = 1, #list do
                    s = ReplaceOne(s, list[i], held)
                end
            end
        end
    end
    for i = 1, #otherPhrases do
        s = ReplaceOne(s, otherPhrases[i], held)
    end
    return s
end

-- For /onair check: text without the names kept on purpose (a player's name inside one is no leak).
function Names.WithoutKept(text)
    for _, phrase in ipairs(phrases) do
        if phrase.alias == phrase.text then
            text = ReplaceOne(text, phrase, {})
        end
    end
    return text
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

-- Lines that carry a stranger's name OnAir may never have seen: the crafter of an item
-- ("<Made by %s>"), a gift's sender, a letter's writer. Built from the game's own text (so every
-- language works), without color codes; the name in them is learned on the spot.
local creatorPatterns
local creatorHeads = {}  -- the plain text before the name ("<Made by "), looked for first
local CREATOR_FORMATS = { "ITEM_CREATED_BY", "ITEM_WRAPPED_BY", "ITEM_WRITTEN_BY", "ITEM_SIGNED_BY" }

local function CreatorPatterns()
    if creatorPatterns then
        return creatorPatterns
    end
    creatorPatterns = {}
    for _, global in ipairs(CREATOR_FORMATS) do
        local format = _G[global]
        if type(format) == "string" and format:find("%%s") then
            format = format:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local pattern = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%s", "(.-)")
            if pattern:sub(-4) == "(.-)" then
                pattern = pattern:sub(1, -5) .. "(.+)$"
            end
            creatorPatterns[#creatorPatterns + 1] = pattern
            creatorHeads[#creatorPatterns] = format:match("^(.-)%%s") or ""
        end
    end
    return creatorPatterns
end

local function LearnCreators(s)
    for i, pattern in ipairs(CreatorPatterns()) do
        local head = creatorHeads[i]
        local name = (head == "" or s:find(head, 1, true)) and s:match(pattern)
        if name then
            name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if IsPlain(name) and #name > 1 and not used[name] then
                Names.AddFull(name, "other")
            end
        end
    end
end

-- A text that is only a one-word guild or community name (see wholeNames): the name (and a
-- "-Realm" after it) replaced in place, colors and brackets kept. Nil for anything else.
local function WholeName(text)
    if not next(wholeNames) or #text > 80 then
        return nil
    end
    local core = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    core = core:match("^%s*<?%s*(.-)%s*>?%s*$") or core
    local name = core
    local alias = wholeNames[name]
    if not alias then
        name = core:match("^(.-)%-[^%-%s]+$")
        alias = name and wholeNames[name]
    end
    if not alias then
        return nil
    end
    local first, last = text:find(name, 1, true)
    if not first then
        return nil
    end
    local _, realmEnd = text:find("^%-[^%-%s|>]+", last + 1)
    return text:sub(1, first - 1) .. alias .. text:sub((realmEnd or last) + 1)
end

local function ScrubRaw(s)
    LearnCreators(s)
    local held = {}
    if phrases[1] then
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
                        elseif words[word] and surnames[s:sub(e + 2, se)] then
                            -- A first name and a surname OnAir knows, on different people: both are
                            -- shared by many, so this is one more, and the surname goes too.
                            alias, stop = words[word], se
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
-- Realms OnAir has seen (yours, the connected ones, every learned player's). A "Name-Realm" or
-- "Name (Realm)" with one of these is a player, even one OnAir never met: a Raider.IO search, an
-- auction seller, a "sent by" line. It's learned on the spot and replaced like any other.
local realms = {}
local realmSeen = {}

local function RealmKey(realm)
    return (realm:gsub("[%s'%-]", "")):lower()
end

function Names.AddRealm(realm)
    if not IsPlain(realm) or realmSeen[realm] then
        return
    end
    realmSeen[realm] = true
    if #realm >= 3 then
        realms[RealmKey(realm)] = true
    end
end

local function Capital(word)
    local b = word:byte(1)
    return b and ((b >= 65 and b <= 90) or b >= 195)
end

local function LearnStrangers(text)
    if Utils.IS_FOREVER or not next(realms) then
        return
    end
    if text:find("-", 1, true) then
        for name, realm in text:gmatch("([%a\128-\255][%a\128-\255]+)%-([%a\128-\255][%a\128-\255']+)") do
            if Capital(name) and realms[RealmKey(realm)] and not words[name .. "-" .. realm] then
                Names.Add(name, realm, "other")
            end
        end
    end
    if text:find(" (", 1, true) then
        for name, realm in text:gmatch("([%a\128-\255][%a\128-\255]+) %(([%a\128-\255][%a\128-\255' ]+)%)") do
            if Capital(name) and realms[RealmKey(realm)] and not words[name] then
                Names.Add(name, (realm:gsub("%s", "")), "other")
            end
        end
    end
end

-- "Thrallbro…": a known name cut short to fit (WhisperMessenger, EllesmereUI) reads as its alias.
local ELLIPSIS = "\226\128\166"
local EMPTY = {}

local function Shortened(s)
    return (s:gsub("([%a\128-\255][%w\128-\255]+)" .. ELLIPSIS, function(prefix)
        if #prefix >= 3 and Capital(prefix) and not words[prefix] then
            for _, word in ipairs(byStart[prefix:sub(1, 3)] or EMPTY) do
                if #word > #prefix and word:sub(1, #prefix) == prefix and words[word] then
                    return words[word]
                end
            end
        end
    end))
end

-- Forever: a label that holds only a player's name, in forms the words alone can't catch:
--   "Anna Quill", "Anna Qui"  a first name OnAir knows, with a surname it doesn't, or cut short:
--                             without this it would read "Alias Quill"
--   "A. Smith"                an initial and a surname OnAir has seen (EllesmereUI's Abbreviated)
-- A surname alone ("Smith", EllesmereUI's Last Name) or a stranger with a known surname ("Zed Smith")
-- is left alone on purpose: surnames are everyday words too. A label reading "Frost" or "Frost Mage"
-- is a spec, and learning that as a player would make "Frost" read as an alias in every spell.
local function ForeverLabel(text)
    if not Utils.IS_FOREVER or #text > 80 then
        return nil
    end
    local core = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    core = core:match("^%s*(.-)%s*$")
    if used[core] or words[core] or phraseByText[core] then
        return nil
    end
    local first = core:match("^([%a\128-\255]+) [%a\128-\255]+$")
    local alias = first and words[first] or surnames[core:match("^[%a\128-\255]+%. ([%a\128-\255]+)$") or ""]
    if not alias then
        return nil
    end
    local a, b = text:find(core, 1, true)
    return a and (text:sub(1, a - 1) .. alias .. text:sub(b + 1)) or nil
end

-- For /onair check on Forever: half of a name on screen, which the words can't show: an alias and
-- one more word ("Stand-In Smith"), or a surname OnAir knows on its own.
function Names.HalfName(text)
    if not Utils.IS_FOREVER then
        return nil
    end
    local core = text:match("^%s*(.-)%s*$")
    if surnames[core] then
        return core
    end
    for _, alias in ipairs(aliasStarts[core:match("^[%a\128-\255]+") or ""] or EMPTY) do
        if core:sub(1, #alias) == alias then
            local rest = core:sub(#alias + 1):match("^ ([%a\128-\255]+)$")
            if rest then
                return rest
            end
        end
    end
    return nil
end

function Names.Scrub(text)
    if type(text) ~= "string" or IsSecret(text) or text == "" then
        return text
    end
    if cacheStale then
        wipe(cache)
        cacheSize = 0
        cacheStale = false
    end
    local hit = cache[text]
    if hit then
        return hit
    end
    -- Numbers, timers, percentages: no name in there, and not worth a place in the cache.
    if not text:find("[%a\128-\255|]") then
        return text
    end
    LearnStrangers(text)
    if cacheStale then
        wipe(cache)
        cacheSize = 0
        cacheStale = false
    end
    local out = WholeName(text) or ForeverLabel(text) or ScrubRaw(text)
    if out:find(ELLIPSIS, 1, true) then
        out = Shortened(out)
    end
    if cacheSize >= CACHE_LIMIT then
        wipe(cache)
        cacheSize = 0
    end
    cache[text] = out
    cacheSize = cacheSize + 1
    return out
end

-- A line of the Guild & Communities window's chat: "[Sender]: message". The game gives the message
-- as a protected token: it can't be read, so no name in it can be swapped. Whether it shows has a
-- switch of its own, apart from the names in the line (`names`: "Interface text" is on). Other
-- tokens go as everywhere (see TokenAlias).
function Names.ScrubClubLine(text, hide, names)
    local a, b
    local from = 1
    while true do
        local s, e = text:find("|K.-|k", from)
        if not s then
            break
        end
        a, b, from = s, e, e + 1
    end
    -- The message is the last token, right after the ": " (maybe with a color in between).
    local head = a and text:sub(1, a - 1)
    if not head or not (head:find(": $") or head:find(": |c%x%x%x%x%x%x%x%x$")) then
        return names and Names.Scrub(text) or text
    end
    local tail = text:sub(b + 1)
    if names then
        head, tail = Names.Scrub(head), Names.Scrub(tail)
    end
    return head .. (hide and L["(hidden)"] or text:sub(a, b)) .. tail
end

-- The lines that give the message of the day, worded as the game words them in each language: the
-- Guild & Communities window's chat (a community's too), every chat window (maybe after a timestamp),
-- and the Guild News tab, whose words are short ("MotD: ") so they count only at a label's very start.
-- Its headings ("Message of the Day") have no message after them.
local MOTD_LINES = {
    { "COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT" },
    { "GUILD_MOTD_TEMPLATE" },
    { "GUILD_NEWS_MOTD", atStart = true },
}
local motdLines

local function MotdLines()
    if not motdLines then
        motdLines = {}
        for _, spec in ipairs(MOTD_LINES) do
            local format = _G[spec[1]]
            local words, after
            if type(format) == "string" then
                words, after = format:match("^(.-)%%[%d%$]*s(.*)$")
            end
            -- A format that's only a quote and the message says nothing: it would match any quote.
            if words and #words >= 4 then
                motdLines[#motdLines + 1] = { words = words, after = after, atStart = spec.atStart }
            end
        end
    end
    return motdLines
end

-- Such a line with its message hidden; nil for any other text.
function Names.HideMotd(text)
    for _, line in ipairs(MotdLines()) do
        local a, b = text:find(line.words, 1, true)
        if a and b < #text and (a == 1 or not line.atStart) then
            return text:sub(1, b) .. L["(hidden)"] .. line.after
        end
    end
    return nil
end

-- Text with the guild's message of the day in it (a tooltip's line): that part hidden. A short
-- message counts only as the whole text: "hi" is in many words.
function Names.HideMotdText(text, motd)
    if text == motd then
        return L["(hidden)"]
    end
    if #motd >= 6 then
        local a, b = text:find(motd, 1, true)
        if a then
            return text:sub(1, a - 1) .. L["(hidden)"] .. text:sub(b + 1)
        end
    end
    return text
end

---------------------------------------------------------------------------------------------- settings

local function RebuildCustom()
    wipe(customLower)
    for real, alias in pairs(DB().custom) do
        if type(real) == "string" and type(alias) == "string" and alias ~= "" then
            customLower[FixedKey(Utils.Trim(real))] = alias
        end
    end
end

local function Capitalized(word)
    return word:sub(1, 1):upper() .. word:sub(2):lower()
end

-- A fixed alias works from the moment it's added, also for someone OnAir hasn't met yet: the name
-- on the Custom page goes out right away. Typed in small letters it's still a name (the game writes
-- a capital); "bob" itself stays a word. A realm isn't needed: "Bob-Anywhere" reads through "Bob".
local function PublishFixed()
    for real, alias in pairs(DB().custom) do
        if type(real) == "string" and type(alias) == "string" and alias ~= "" then
            local name = Utils.Trim(real)
            local first, second
            if name:find("#%d+$") then
                AddPhrase(name, alias)
                first = name:match("^(.-)#%d+$")
            else
                first, second = SplitFull(name)
            end
            used[alias] = true
            AddAliasStart(alias)
            PutWord(Capitalized(first), alias, FIXED_RANK)
            if IndexWord(first) then
                PutWord(first, alias, FIXED_RANK)
            end
            if second and Utils.IS_FOREVER then
                surnames[Capitalized(second)] = alias
            end
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
    wipe(surnames)
    wipe(aliasStarts)
    wipe(used)
    wipe(realOf)
    wipe(tokens)
    wipe(phrases)
    wipe(phraseByText)
    wipe(wholeNames)
    wipe(byStart)
    placesNow = ""
    SortPhrases()
    for _, alias in pairs(db.assigned) do
        used[alias] = true
    end
    PublishFixed()
    local list = {}
    for _, person in pairs(people) do
        -- A fixed alias carried from a friend's account: worked out again below, from the account.
        if person.fixed then
            person.forced, person.fixed = nil, nil
        end
        if not friends[person.key] then
            list[#list + 1] = person
        end
    end
    for _, person in pairs(friends) do
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
        if friends[person.key] then
            PublishFriend(person)
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
    if not Utils.IS_FOREVER then
        Names.AddRealm(GetRealmName and GetRealmName())
        Names.AddRealm(GetNormalizedRealmName and GetNormalizedRealmName())
        if type(GetAutoCompleteRealms) == "function" then
            local ok, list = pcall(GetAutoCompleteRealms)
            for _, realm in ipairs(ok and type(list) == "table" and list or {}) do
                Names.AddRealm(realm)
            end
        end
    end
    for _, alias in pairs(DB().assigned) do
        used[alias] = true
    end
    PublishFixed()
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
    return peopleCount
end
