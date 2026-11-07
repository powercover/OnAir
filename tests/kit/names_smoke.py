"""The name engine on WoW's Lua (5.1, through lupa) with the game mocked: learning players and
rewriting text. Runs once as Retail and once as WoW Forever.

python tests/kit/names_smoke.py
"""
import os
import sys

from lupa.lua51 import LuaRuntime

ROOT = os.environ.get("ONAIR_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
FILES = ["Locales/Locales.lua", "Utils.lua", "Cast.lua", "Names.lua"]

MOCKS = r"""
TOC = ...
function GetBuildInfo() return "x", "1", "d", TOC end
function GetLocale() return "enUS" end
function GetNormalizedRealmName() return "Kazzak" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
ITEM_CREATED_BY = "|cff00ff00<Made by %s>|r"
ITEM_WRITTEN_BY = "Written by %s"
"""

DB = r"""
OA.db = { me = "The Star", theme = "film", crew = { mode = "template", template = "{me}'s Crew {n}" },
  others = { mode = "cast", template = "Extra #{n}" }, petTemplate = "{owner}'s Pet",
  guildAlias = "{me}'s Studio", otherGuild = "Studio {n}", communityTemplate = "Community {n}",
  who = { me = WHO, crew = WHO, others = WHO, friends = WHO, guilds = WHO, pets = WHO },
  custom = CUSTOM, assigned = {}, assignedKind = {}, counters = {}, myChars = {} }
OA.Names.Init()
"""

RETAIL = [
    # (lua setup, input, expected)
    ('OA.Names.Add("Bob", nil, "crew")', "Bob hits hard", "The Star's Crew 1 hits hard"),
    (None, "Bob-Kazzak says hi", "The Star's Crew 1 says hi"),
    (None, "|cffc41e3aBob|r died", "|cffc41e3aThe Star's Crew 1|r died"),
    (None, "|Hplayer:Bob-Kazzak:12|h[Bob]|h waves", "|Hplayer:Bob-Kazzak:12|h[The Star's Crew 1]|h waves"),
    (None, "Bobby is not Bob", "Bobby is not The Star's Crew 1"),
    (None, "Bob-Silvermoon too", "The Star's Crew 1 too"),
    ('OA.Names.Add("Star", "Kazzak", "other")', "The Star's Crew 1 and Star", None),
    ('OA.Names.Add("Me", nil, "me")', "Me and Bob", "The Star and The Star's Crew 1"),
    ('OA.Names.Add("Duo", nil, "other")', "Duo joined", "My Partner joined"),
    ('OA.Names.AddBNet(7, "|Kp12|k", "Zed#1234", nil)', "|Kp12|k (Zed#1234) online", None),
    ('OA.Names.AddGuild("Bob Squad", true)', "<Bob Squad>", "<The Star's Studio>"),
    # a one-word guild of someone else: only where the text is the guild itself
    ('OA.Names.AddGuild("Progress", false)', "Raider.IO Raid Progress", "Raider.IO Raid Progress"),
    (None, "<Progress>", "<Studio 1>"),
    (None, "Progress-TwistingNether", "Studio 1"),
    (None, "|cff40ff40<Progress>|r", "|cff40ff40<Studio 1>|r"),
    ('OA.Names.AddGuild("Night Watch Crew", false)', "joined Night Watch Crew today", "joined Studio 2 today"),
    ('OA.Names.AddCommunity("Mythic")', "Mythic+ Score", "Mythic+ Score"),
    ('OA.Names.AddGuild("Legacy", true)', "our Legacy raid", "our The Star's Studio raid"),
    (None, "|TInterface\\Icons\\Bob:14|t Bob", "|TInterface\\Icons\\Bob:14|t The Star's Crew 1"),
    (None, "12345 / 99%", "12345 / 99%"),
    ('OA.Names.AddOwnBattleTag("OnAir#0000")', "OnAir#0000", "The Star"),
    (None, "OnAir|cff416380#0000|r", "The Star|cff416380|r"),
    ('assert(OA.Names.RealOf("The Star\'s Crew 1") == "Bob-Kazzak")', "ok", "ok"),
    ('assert(OA.Names.RealOf("Steadicam") == "|Kp12|k")', "ok", "ok"),
    (None, "<Made by N\u00f8probl\u00eam>", None),
    (None, "|cff00ff00<Made by Crafty-Kazzak>|r", None),
    (None, "Written by Penpal", None),
]

FOREVER = [
    ('OA.Names.Add("Anna", "Smith", "crew")', "Anna Smith joined", "The Star's Crew 1 joined"),
    (None, "Anna is here", "The Star's Crew 1 is here"),
    ('OA.Names.AddFull("Tom Baker", "other")', "Tom Baker and Tom", None),
]


# Fixed aliases (the Custom page). Each scenario is a fresh engine: (what it shows, every group off?,
# the Custom page, steps). A step is as above; expected None: the text changed.
BOB_GIL = 'OA.Names.AddFull("Bob-Kazzak", "other"); OA.Names.AddFull("Gil-Kazzak", "other")'
FRIEND = 'OA.Names.AddBNet(7, "|Kp12|k", "Zed#1234", "Zedchar-Kazzak")'
AMY = 'OA.Names.AddBNet(8, "|Kp13|k", "Amy#5555", "Amychar-Kazzak")'


def all_of_zed(alias, setup=None):
    return [
        (setup, "|Kp12|k online", f"{alias} online"),
        (None, "Zed#1234 online", f"{alias} online"),
        (None, "Zed online", f"{alias} online"),
        (None, "Zedchar waves", f"{alias} waves"),
    ]


def amy_real():
    return [(None, text, text) for text in ("|Kp13|k online", "Amy#5555 online", "Amychar waves")]


FIXED_RETAIL = [
    ("1. one person, every group off", True, '{ ["Bob"] = "Partner" }', [
        (BOB_GIL, "Bob says hi", "Partner says hi"),
        (None, "Bob-Kazzak waves", "Partner waves"),
        (None, "Gil says hi", "Gil says hi"),
        # (a chat sender reads person.alias)
        ('assert(OA.Names.Get("Bob-Kazzak").alias == "Partner" and OA.Names.Get("Gil-Kazzak").alias == nil)', "ok", "ok"),
        ('assert(OA.Names.RealOf("Partner") == "Bob-Kazzak")', "ok", "ok"),
    ]),
    ("1. a group switched off while live gives its names back, not the fixed one", False, '{ ["Bob"] = "Partner" }', [
        (BOB_GIL, "Gil says hi", None),
        ("OA.db.who.others = false; OA.Names.Rebuild(false)", "Gil says hi", "Gil says hi"),
        (None, "Bob says hi", "Partner says hi"),
        ('assert(OA.Names.Get("Gil-Kazzak").alias == nil)', "ok", "ok"),
    ]),
    ("2. a BattleTag, every group off", True, '{ ["Zed#1234"] = "Duo" }',
        all_of_zed("Duo", FRIEND + "; " + AMY) + amy_real() + [
            ('assert(OA.Names.RealOf("Duo") == "|Kp12|k")', "ok", "ok"),
        ]),
    ("2. a BattleTag, every group on", False, '{ ["Zed#1234"] = "Duo" }',
        all_of_zed("Duo", FRIEND + "; " + AMY) + [(None, "Amy#5555 online", None), (None, "|Kp13|k online", None)]),
    ("2. a BattleTag without its number, in small letters", True, '{ ["zed"] = "Duo" }',
        all_of_zed("Duo", FRIEND + "; " + AMY) + amy_real()),
    ("2. a friend in your group", False, '{ ["Zed#1234"] = "Duo" }',
        all_of_zed("Duo", 'OA.Names.AddFull("Zedchar-Kazzak", "crew"); ' + FRIEND)),
    ("3. a friend's character, every group off", True, '{ ["Zedchar"] = "Duo" }',
        all_of_zed("Duo", FRIEND + "; " + AMY) + amy_real()),
    ("3. a friend's character, every group on", False, '{ ["Zedchar"] = "Duo" }', all_of_zed("Duo", FRIEND)),
    ("3. all of a friend's characters", False, '{ ["Zed#1234"] = "Duo" }', [
        (FRIEND + '; OA.Names.AddBNet(7, "|Kp12|k", "Zed#1234", "Zedalt-Kazzak")', "Zedalt waves", "Duo waves"),
        (None, "Zedchar waves", "Duo waves"),
    ]),
    ("4. a settings change keeps friends masked", False, "{}", all_of_zed("Steadicam", FRIEND + "; OA.Names.Rebuild(false)") + [
        ('assert(OA.Names.RealOf("Steadicam") == "|Kp12|k")', "ok", "ok"),
    ]),
    ("4. with a fixed alias too", True, '{ ["Zed#1234"] = "Duo" }', all_of_zed("Duo", FRIEND + "; OA.Names.Rebuild(false)")),
    ("4. a reshuffle: still one alias for one friend", False, "{}", [
        (FRIEND + '; OA.Names.Rebuild(true); local a = OA.Names.Scrub("|Kp12|k"); '
         'assert(a ~= "|Kp12|k" and OA.Names.Scrub("Zed#1234") == a and OA.Names.Scrub("Zedchar") == a)', "ok", "ok"),
    ]),
    ("4. the friends switch off and on while live", False, "{}",
        all_of_zed("Steadicam", FRIEND)
        + [("OA.db.who.friends = false; OA.Names.Rebuild(false)", "Zed#1234 online", "Zed#1234 online"),
           (None, "|Kp12|k online", "|Kp12|k online"), (None, "Zed online", "Zed online"), (None, "Zedchar waves", "Zedchar waves")]
        + all_of_zed("Steadicam", "OA.db.who.friends = true; OA.Names.Rebuild(false)")),
    ("4. friends seen while their switch was off", True, "{}",
        all_of_zed("Steadicam", FRIEND + "; OA.db.who.friends = true; OA.Names.Rebuild(false)")),
    ("1-3. a fixed alias taken off: the real names are back", True, '{ ["Zed#1234"] = "Duo", ["Bob"] = "Partner" }', [
        (FRIEND + "; " + BOB_GIL, "Zed#1234 online", "Duo online"),
        ('OA.db.custom["Zed#1234"], OA.db.custom["Bob"] = nil, nil; OA.Names.Rebuild(false)', "Zed#1234 online", "Zed#1234 online"),
        (None, "|Kp12|k online", "|Kp12|k online"),
        (None, "Zed online", "Zed online"),
        (None, "Zedchar waves", "Zedchar waves"),
        (None, "Bob says hi", "Bob says hi"),
        ('assert(OA.Names.Get("Bob-Kazzak").alias == nil and OA.Names.Get("Zedchar-Kazzak").alias == nil)', "ok", "ok"),
    ]),
    ("1-3. taken off a friend in your group: their own alias is back", False, '{ ["Zed#1234"] = "Duo" }', [
        ('OA.Names.AddFull("Zedchar-Kazzak", "crew"); ' + FRIEND, "Zedchar waves", "Duo waves"),
        ('OA.db.custom["Zed#1234"] = nil; OA.Names.Rebuild(false)', "Zedchar waves", "The Star's Crew 1 waves"),
    ]),
    ("5. someone OnAir hasn't met", True, '{ ["Bob"] = "Partner" }', [
        (None, "Bob says hi", "Partner says hi"),
        (None, "hi Bob", "hi Partner"),
        (None, "Bob-Silvermoon waves", "Partner waves"),
        (None, "Gil says hi", "Gil says hi"),
    ]),
    ("5. typed in small letters: the name, not the word", True, '{ ["bob"] = "Partner" }', [
        (None, "Bob says hi", "Partner says hi"),
        (None, "the boats bob", "the boats bob"),
    ]),
    ("5. typed with a realm", True, '{ ["Bob-Kazzak"] = "Partner" }', [
        (None, "Bob-Kazzak waves", "Partner waves"),
        (None, "Bob says hi", "Partner says hi"),
    ]),
    ("5. a BattleTag OnAir hasn't met", True, '{ ["Zed#1234"] = "Duo" }', [
        (None, "Zed#1234 online", "Duo online"),
        (None, "Zed online", "Duo online"),
    ]),
    ("6. a realm typed with its space", False, '{ ["Bob-Twisting Nether"] = "Partner" }', [
        ('OA.Names.AddFull("Bob-TwistingNether", "other")', "Bob-TwistingNether waves", "Partner waves"),
        ('assert(OA.Names.Get("Bob-TwistingNether").alias == "Partner")', "ok", "ok"),
    ]),
    ("6. a dash and an apostrophe in a realm", False, '{ ["Bob-Azjol-Nerub"] = "Partner", ["gil-amanthul"] = "Mate" }', [
        ('OA.Names.AddFull("Bob-AzjolNerub", "other"); OA.Names.AddFull("Gil-Aman\'Thul", "other"); '
         'assert(OA.Names.Get("Bob-AzjolNerub").alias == "Partner" and OA.Names.Get("Gil-Aman\'Thul").alias == "Mate")', "ok", "ok"),
    ]),
    ("6. the same name on another realm isn't them", False, '{ ["Bob-Kazzak"] = "Partner" }', [
        ('OA.Names.AddFull("Bob-Silvermoon", "other"); local a = OA.Names.Get("Bob-Silvermoon").alias; '
         'assert(a and a ~= "Partner")', "ok", "ok"),
        # (the bare name stays with the fixed one: it could be them)
        (None, "Bob says hi", "Partner says hi"),
    ]),
    ("nothing fixed, every group off: nothing changes", True, "{}", [
        (FRIEND + "; " + BOB_GIL, "Bob says hi", "Bob says hi"),
        (None, "|Kp12|k online", "|Kp12|k online"),
        (None, "Zed#1234 online", "Zed#1234 online"),
        (None, "Zed online", "Zed online"),
        (None, "Zedchar waves", "Zedchar waves"),
    ]),
]

FIXED_FOREVER = [
    ("1. one person, every group off", True, '{ ["Anna Smith"] = "Partner" }', [
        ('OA.Names.AddFull("Anna Smith", "other"); OA.Names.AddFull("Tom Baker", "other")', "Anna Smith joined", "Partner joined"),
        (None, "Anna is here", "Partner is here"),
        (None, "Tom Baker joined", "Tom Baker joined"),
    ]),
    ("5. someone OnAir hasn't met, typed in small letters", True, '{ ["anna smith"] = "Partner" }', [
        (None, "Anna Smith joined", "Partner joined"),
        (None, "Anna is here", "Partner is here"),
    ]),
    ("2. a BattleTag, every group off", True, '{ ["Zed#1234"] = "Duo" }', [
        ('OA.Names.AddBNet(7, "|Kp12|k", "Zed#1234", "Zed Char")', "Zed Char waves", "Duo waves"),
        (None, "|Kp12|k online", "Duo online"),
        (None, "Zed#1234 online", "Duo online"),
    ]),
]


# Forever: first names and surnames are both shared by many, and both can be everyday words.
ANNA_TOM = 'OA.Names.Add("Anna", "Smith", "other"); OA.Names.AddFull("Tom Baker", "other"); OA.Names.AddFull("Gil Jones", "other")'
ELLIPSIS = "\u2026"

FOREVER_NAMES = [
    ("a whole name, a first name", False, "{}", [
        (ANNA_TOM, "Anna Smith", "Stand-In"),
        (None, "Anna", "Stand-In"),
        (None, "Anna Smith joined", "Stand-In joined"),
    ]),
    ("a first name OnAir knows, with a surname it doesn't: the surname goes too", False, "{}", [
        (ANNA_TOM, "Anna Quill", "Stand-In"),
        (None, "|cffc41e3aAnna Quill|r", "|cffc41e3aStand-In|r"),
    ]),
    ("a name cut to fit", False, "{}", [
        (ANNA_TOM, "Anna Smi", "Stand-In"),
        (None, "Anna Smi" + ELLIPSIS, "Stand-In"),
    ]),
    ("a first name and a surname from different people, also inside a sentence", False, "{}", [
        (ANNA_TOM, "Anna Jones", "Stand-In"),
        (None, "hi Anna Jones!", "hi Stand-In!"),
    ]),
    ("an initial and a surname", False, "{}", [
        (ANNA_TOM, "A. Smith", "Stand-In"),
        (None, "|cffc41e3aA. Smith|r", "|cffc41e3aStand-In|r"),
    ]),
    ("a unit that carries the surname in its first value", False, "{}", [
        ('OA.Names.Add("Anna Smith", "Smith", "other"); assert(OA.Names.Get("Anna Smith"))', "Anna Smith", "Stand-In"),
        (None, "Anna", "Stand-In"),
    ]),
    ("every group off: only the fixed one, whole", True, '{ ["Anna Smith"] = "Partner" }', [
        (ANNA_TOM, "Anna Smith", "Partner"),
        (None, "A. Smith", "Partner"),
        (None, "Anna Quill", "Partner"),
        (None, "Tom Baker", "Tom Baker"),
        (None, "Tom", "Tom"),
        (None, "Baker", "Baker"),
        (None, "T. Baker", "T. Baker"),
    ]),
    ("a fixed alias taken off: its surname goes with it", True, '{ ["Anna Smith"] = "Partner" }', [
        (ANNA_TOM, "A. Smith", "Partner"),
        ('OA.db.custom["Anna Smith"] = nil; OA.Names.Rebuild(false)', "A. Smith", "A. Smith"),
        (None, "Anna Smith", "Anna Smith"),
        (None, "Anna", "Anna"),
    ]),
    # Surnames and first names that are everyday words: real ones seen in the game.
    ("a surname that's a game word stays that word", False, "{}", [
        ('OA.Names.AddFull("Anna Frost", "other"); OA.Names.AddFull("Gil Mage", "other"); OA.Names.AddFull("Tom Healer", "other")', "Frost", "Frost"),
        (None, "Mage", "Mage"),
        (None, "Healer", "Healer"),
        (None, "Frost Mage", "Frost Mage"),
        (None, "Arcane Mage", "Arcane Mage"),
        (None, "Frost Nova", "Frost Nova"),
        (None, "the Frost Mage attacks", "the Frost Mage attacks"),
        # (nobody got learned from those: "Frost" would then read as an alias everywhere)
        ('assert(OA.Names.Get("Frost Mage") == nil and OA.Names.Get("Arcane Mage") == nil)', "Frost", "Frost"),
    ]),
    ("a stranger with a surname OnAir knows isn't guessed", False, "{}", [
        (ANNA_TOM, "Zed Smith", "Zed Smith"),
        ('assert(OA.Names.Get("Zed Smith") == nil)', "ok", "ok"),
    ]),
    ("an alias stays as it is, also one of two words", False, '{ ["Anna Smith"] = "Set Dresser" }', [
        ('OA.Names.AddFull("Anna Smith", "other"); OA.Names.AddFull("Set Piece", "other")', "Set Dresser", "Set Dresser"),
        (None, "Set Piece", None),
    ]),
    ("free text with a surname OnAir has no way to know keeps it (/onair check shows it)", False, "{}", [
        (ANNA_TOM, "Anna Quill joined", "Stand-In Quill joined"),
        ('assert(OA.Names.HalfName("Stand-In Quill") == "Quill" and OA.Names.HalfName("Smith") == "Smith")', "ok", "ok"),
        ('assert(OA.Names.HalfName("Stand-In") == nil and OA.Names.HalfName("Frost Nova") == nil)', "ok", "ok"),
    ]),
]

RETAIL_NO_SURNAMES = [
    ("Retail has no surnames: none of this applies", False, '{ ["Bob"] = "Partner" }', [
        ('OA.Names.AddFull("Bob-Kazzak", "other")', "Bob Quill", "Partner Quill"),
        (None, "Kazzak", "Kazzak"),
        ('assert(OA.Names.HalfName("Partner Quill") == nil)', "ok", "ok"),
    ]),
]

# The guild window's chat: "[Sender]: message", where the message is a protected token. Whether it
# shows is its own switch, apart from the names in the line.
CLUB = 'OA.Names.AddFull("Bob-Kazzak", "other"); LINE = "07:41 [Bob]: |Kq9|k"; SCL = OA.Names.ScrubClubLine; '
GUILD_WINDOW = [
    ("hidden, names swapped", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'assert(SCL(LINE, true, true) == "07:41 [Partner]: (hidden)")', "ok", "ok"),
    ]),
    ("shown, names swapped", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'assert(SCL(LINE, false, true) == "07:41 [Partner]: |Kq9|k")', "ok", "ok"),
    ]),
    ("hidden, with every group off: the names stay real", True, "{}", [
        (CLUB + 'assert(SCL(LINE, true, true) == "07:41 [Bob]: (hidden)")', "ok", "ok"),
    ]),
    ("shown, with every group off: as the game sent it", True, "{}", [
        (CLUB + 'assert(SCL(LINE, false, true) == LINE)', "ok", "ok"),
    ]),
    ("Interface text off: the switch still works, the names aren't touched", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'assert(SCL(LINE, true, false) == "07:41 [Bob]: (hidden)" and SCL(LINE, false, false) == LINE)', "ok", "ok"),
    ]),
    ("an edited message, and one in a color", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'assert(SCL("[Bob]: |Kq9|k (edited)", true, true) == "[Partner]: (hidden) (edited)")', "ok", "ok"),
        ('assert(SCL("[Bob]: |cff40c040|Kq9|k|r", true, true) == "[Partner]: |cff40c040(hidden)|r")', "ok", "ok"),
    ]),
    ("a message in a color, every group off: still the message", True, "{}", [
        (CLUB + 'assert(SCL("[Bob]: |cff40c040|Kq9|k|r", true, true) == "[Bob]: |cff40c040(hidden)|r")', "ok", "ok"),
    ]),
    ("a sender who's a Battle.net friend: their alias, in both", False, "{}", [
        (FRIEND + '; SCL = OA.Names.ScrubClubLine', "ok", "ok"),
        ('assert(SCL("[|Kp12|k]: |Kq9|k", true, true) == "[Steadicam]: (hidden)")', "ok", "ok"),
        ('assert(SCL("[|Kp12|k]: |Kq9|k", false, true) == "[Steadicam]: |Kq9|k")', "ok", "ok"),
    ]),
    ("a line as the game writes it: a link, a class color, an edit mark", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'LINK = "|HplayerCommunity:Bob-Kazzak:1:2:3:4|h"', "ok", "ok"),
        ('assert(SCL("07:41 " .. LINK .. "[|cffc79c6eBob|r]|h: |Kq9|k", true, true) == "07:41 " .. LINK .. "[|cffc79c6ePartner|r]|h: (hidden)")', "ok", "ok"),
        ('assert(SCL(LINK .. "[Bob]|h: |Kq9|k |cff808080(edited)|r", true, true) == LINK .. "[Partner]|h: (hidden) |cff808080(edited)|r")', "ok", "ok"),
    ]),
    ("a line with no message token goes the usual way", False, '{ ["Bob"] = "Partner" }', [
        (CLUB + 'assert(SCL("Bob joined", true, true) == "Partner joined" and SCL("Tuesday, November 3", true, true) == "Tuesday, November 3")', "ok", "ok"),
    ]),
]

# The message of the day, worded as the game words it (GlobalStrings).
WORDS = ('COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT = [[Message of the Day: "%s"]]; GUILD_MOTD_TEMPLATE = [[Guild Message of the Day: "%s"]]; '
         'GUILD_NEWS_MOTD = "MotD: %s"; ')
HM = "HM = OA.Names.HideMotd; HT = OA.Names.HideMotdText; "
GUILD_MOTD = [
    ("each line: the message hidden, the words kept", False, "{}", [
        (WORDS + HM + 'assert(HM([[Message of the Day: "discord.gg/x"]]) == [[Message of the Day: "(hidden)"]])', "ok", "ok"),
        ('assert(HM([[Guild Message of the Day: "discord.gg/x"]]) == [[Guild Message of the Day: "(hidden)"]])', "ok", "ok"),
        ('assert(HM("MotD: discord.gg/x") == "MotD: (hidden)")', "ok", "ok"),
    ]),
    ("what's around a line", False, "{}", [
        (WORDS + HM + 'assert(HM([[12:34 Guild Message of the Day: "x"]]) == [[12:34 Guild Message of the Day: "(hidden)"]])', "ok", "ok"),
        ('assert(HM([[|cff40ff40Guild Message of the Day: "x"|r]]) == [[|cff40ff40Guild Message of the Day: "(hidden)"]])', "ok", "ok"),
        ('assert(HM([[Message of the Day: "say "hi" now"]]) == [[Message of the Day: "(hidden)"]])', "ok", "ok"),
    ]),
    ("hidden already: the same text again", False, "{}", [
        (WORDS + HM + 'for _, t in ipairs({ [[Message of the Day: "x"]], [[Guild Message of the Day: "x"]], "MotD: x" }) do assert(HM(HM(t)) == HM(t)) end', "ok", "ok"),
    ]),
    ("not a message of the day: headings, quotes, nothing after the words", False, "{}", [
        (WORDS + HM + 'for _, t in ipairs({ "Message of the Day", "Guild Message of the Day", "Guild MOTD", "MotD", "MotD: ", [[He said "hi"]], [[Message of the Day: "]] }) do assert(HM(t) == nil, t) end', "ok", "ok"),
    ]),
    ("the short words count only at a label's start", False, "{}", [
        (WORDS + HM + 'assert(HM("[Bob]: MotD: join") == nil and HM("12:34 MotD: join") == nil)', "ok", "ok"),
    ]),
    ("other languages", False, "{}", [
        (HM + 'GUILD_MOTD_TEMPLATE = [[Gildennachricht des Tages: "%1$s"]]; COMMUNITIES_MESSAGE_OF_THE_DAY_FORMAT = "Message du jour : « %s »"; GUILD_NEWS_MOTD = "今日信息：%s"', "ok", "ok"),
        ('assert(HM([[Gildennachricht des Tages: "x"]]) == [[Gildennachricht des Tages: "(hidden)"]])', "ok", "ok"),
        ('assert(HM("Message du jour : « x »") == "Message du jour : « (hidden) »")', "ok", "ok"),
        ('assert(HM("今日信息：x") == "今日信息：(hidden)")', "ok", "ok"),
    ]),
    ("a format that's only a quote and the message says nothing", False, "{}", [
        (HM + 'GUILD_MOTD_TEMPLATE = [["%s"]]; assert(HM([[He said "hi"]]) == nil)', "ok", "ok"),
    ]),
    ("a game without these strings", False, "{}", [
        (HM + 'assert(HM([[Message of the Day: "x"]]) == nil)', "ok", "ok"),
    ]),
    ("in a tooltip's line: the whole line, in quotes, inside", False, "{}", [
        (HM + 'assert(HT("discord.gg/x", "discord.gg/x") == "(hidden)")', "ok", "ok"),
        ('assert(HT([["discord.gg/x"]], "discord.gg/x") == [["(hidden)"]])', "ok", "ok"),
        ('assert(HT("see %d (x) here", "%d (x)") == "see (hidden) here")', "ok", "ok"),
        ('assert(HT("nothing here", "discord.gg/x") == "nothing here")', "ok", "ok"),
    ]),
    ("a short message counts only as the whole line", False, "{}", [
        (HM + 'assert(HT("hi", "hi") == "(hidden)" and HT("this", "hi") == "this")', "ok", "ok"),
    ]),
]

# A guild's or community's name with its switch off: whole, whatever words are in it.
KEEP = 'OA.db.who.guilds = false; OA.Names.AddFull("Bram-Kazzak", "other"); OA.Names.AddFull("Zed-Kazzak", "other"); '
GUILD_WHOLE = [
    ("the switch off: your guild's name stays whole, the player in it keeps an alias", False, "{}", [
        (KEEP + 'OA.Names.AddGuild("Lost Keys Bram", true)', "Lost Keys Bram", "Lost Keys Bram"),
        (None, "<Lost Keys Bram>", "<Lost Keys Bram>"),
        (None, "Bram", None),
        (None, "Bram joined", None),
    ]),
    ("another guild's name too", False, "{}", [
        (KEEP + 'OA.Names.AddGuild("Ten Past Zed", false)', "Ten Past Zed", "Ten Past Zed"),
        (None, "Zed", None),
    ]),
    ("a community's name too", False, "{}", [
        (KEEP + 'OA.Names.AddCommunity("The Bram Club")', "The Bram Club", "The Bram Club"),
        (None, "Bram", None),
    ]),
    ("one word alone could be that person: the alias stays", False, "{}", [
        (KEEP + 'OA.Names.AddGuild("Bram", true); OA.Names.AddGuild("Zed", false); OA.Names.AddCommunity("Zed")', "Bram", None),
        (None, "Zed", None),
    ]),
    ("kept names are no leaks for /onair check", False, "{}", [
        (KEEP + 'OA.Names.AddGuild("Lost Keys Bram", true); assert(#OA.Names.Phrases() == 0)', "ok", "ok"),
        ('assert(not OA.Names.WithoutKept("Lost Keys Bram joined"):find("Bram", 1, true))', "ok", "ok"),
        ('assert(OA.Names.WithoutKept("Bram joined") == "Bram joined")', "ok", "ok"),
    ]),
    ("the switch on: aliases as ever, and they do count for /onair check", False, "{}", [
        ('OA.Names.AddFull("Bram-Kazzak", "other"); OA.Names.AddGuild("Lost Keys Bram", true)', "Lost Keys Bram", "The Star's Studio"),
        ('assert(#OA.Names.Phrases() == 1)', "ok", "ok"),
        ('assert(OA.Names.WithoutKept("Lost Keys Bram joined") == "Lost Keys Bram joined")', "ok", "ok"),
    ]),
    ("no name: nothing happens", False, "{}", [
        (KEEP + 'OA.Names.AddGuild(nil); OA.Names.AddCommunity(nil)', "ok", "ok"),
    ]),
]
GUILD_WHOLE_FOREVER = [
    ("Forever, the switch off: a two-word guild isn't read as a person", False, "{}", [
        ('OA.db.who.guilds = false; OA.Names.AddFull("Bram Smith", "other"); OA.Names.AddGuild("Bram Club", true)', "Bram Club", "Bram Club"),
        ('OA.Names.AddGuild("Lost Keys Bram", false)', "Lost Keys Bram", "Lost Keys Bram"),
        (None, "Bram", None),
        (None, "Bram Jones", None),
    ]),
    ("Forever, the switch on: its alias, not the person's", False, "{}", [
        ('OA.Names.AddFull("Bram Smith", "other"); OA.Names.AddGuild("Bram Club", true)', "Bram Club", "The Star's Studio"),
    ]),
]


def engine(toc, everyone_off=False, custom='{ ["Duo"] = "My Partner" }'):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCKS, toc)
    oa = lua.eval("{}")
    for rel in FILES:
        src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        lua.execute(src, "OnAir", oa)
    lua.globals().OA = oa
    lua.execute(DB.replace("WHO", "false" if everyone_off else "true").replace("CUSTOM", custom))
    return lua


def run(toc, cases):
    lua = engine(toc)
    failures = 0
    for setup, text, expected in cases:
        if setup:
            lua.execute(setup)
        out = lua.eval("OA.Names.Scrub")(text)
        if expected is None:
            ok = out != text and "Star's Crew 1 and" in out if "Star" in text else out != text
        else:
            ok = out == expected
        mark = "ok  " if ok else "FAIL"
        print(f"  {mark} {text!r} -> {out!r}" + ("" if ok else f"  (wanted {expected!r})"))
        failures += 0 if ok else 1
    return failures


def run_fixed(toc, scenarios):
    failures = 0
    for title, everyone_off, custom, steps in scenarios:
        lua = engine(toc, everyone_off, custom)
        bad = 0
        for setup, text, expected in steps:
            if setup:
                try:
                    lua.execute(setup)
                except Exception as err:
                    print(f"    FAIL {str(err).splitlines()[0]}")
                    bad += 1
            out = lua.eval("OA.Names.Scrub")(text)
            ok = out != text if expected is None else out == expected
            if not ok:
                print(f"    FAIL {text!r} -> {out!r}  (wanted {'a change' if expected is None else repr(expected)})")
                bad += 1
        print(f"  {'ok  ' if bad == 0 else 'FAIL'} {title}")
        failures += bad
    return failures


if __name__ == "__main__":
    total = 0
    print("Retail")
    total += run(120100, RETAIL)
    print("Forever")
    total += run(16001, FOREVER)
    print("Fixed aliases, Retail")
    total += run_fixed(120100, FIXED_RETAIL)
    print("Fixed aliases, Forever")
    total += run_fixed(16001, FIXED_FOREVER)
    print("Forever names")
    total += run_fixed(16001, FOREVER_NAMES)
    total += run_fixed(120100, RETAIL_NO_SURNAMES)
    print("The guild window's chat")
    total += run_fixed(120100, GUILD_WINDOW)
    print("The message of the day, Retail")
    total += run_fixed(120100, GUILD_MOTD)
    print("The message of the day, Forever")
    total += run_fixed(16001, GUILD_MOTD)
    print("A guild's name with its switch off")
    total += run_fixed(120100, GUILD_WHOLE)
    total += run_fixed(16001, GUILD_WHOLE_FOREVER)
    print("names smoke:", "clean" if total == 0 else f"{total} failure(s)")
    sys.exit(1 if total else 0)
