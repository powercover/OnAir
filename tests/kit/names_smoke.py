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
"""

DB = r"""
OA.db = { me = "The Star", theme = "film", crew = { mode = "template", template = "{me}'s Crew {n}" },
  others = { mode = "cast", template = "Extra #{n}" }, petTemplate = "{owner}'s Pet",
  guildAlias = "{me}'s Studio", otherGuild = "Studio {n}",
  who = { me = true, crew = true, others = true, friends = true, guilds = true, pets = true },
  custom = { ["Duo"] = "My Partner" }, assigned = {}, assignedKind = {}, counters = {}, myChars = {} }
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
    (None, "|TInterface\\Icons\\Bob:14|t Bob", "|TInterface\\Icons\\Bob:14|t The Star's Crew 1"),
    (None, "12345 / 99%", "12345 / 99%"),
    ('OA.Names.AddOwnBattleTag("Nimbus#2468")', "Nimbus#2468", "The Star"),
    (None, "Nimbus|cff416380#2468|r", "The Star|cff416380|r"),
    ('assert(OA.Names.RealOf("The Star\'s Crew 1") == "Bob-Kazzak")', "ok", "ok"),
    ('assert(OA.Names.RealOf("Steadicam") == "|Kp12|k")', "ok", "ok"),
]

FOREVER = [
    ('OA.Names.Add("Anna", "Smith", "crew")', "Anna Smith joined", "The Star's Crew 1 joined"),
    (None, "Anna is here", "The Star's Crew 1 is here"),
    ('OA.Names.AddFull("Tom Baker", "other")', "Tom Baker and Tom", None),
]


def run(toc, cases):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCKS, toc)
    oa = lua.eval("{}")
    for rel in FILES:
        src = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        lua.execute(src, "OnAir", oa)
    lua.globals().OA = oa
    lua.execute(DB)
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


if __name__ == "__main__":
    total = 0
    print("Retail")
    total += run(120100, RETAIL)
    print("Forever")
    total += run(16001, FOREVER)
    print("names smoke:", "clean" if total == 0 else f"{total} failure(s)")
    sys.exit(1 if total else 0)
