local addonName, OA = ...

OA.Utils = {}

local Utils = OA.Utils

Utils.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
Utils.ICONS = Utils.MEDIA .. "Icons\\"

-- WoW Forever runs Midnight's engine but reports a 1.x interface number (16001). That number is
-- the one signal every Forever build gives the same way (WOW_PROJECT_ID can still say mainline).
local _, _, _, tocVersion = GetBuildInfo()
Utils.IS_FOREVER = type(tocVersion) == "number" and tocVersion < 20000

-- Values the game hides from addons in combat and in instances. Any Lua operation on them
-- (compare, concatenate, index) throws, so every name passes through here first.
function Utils.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

function Utils.IsPlainString(value)
    return type(value) == "string" and not Utils.IsSecret(value) and value ~= ""
end

-- A string hash (djb2), for picking the same cast name for the same player every session.
function Utils.Hash(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return h
end

function Utils.Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Calls fn once on the next frame, however many times this is asked for before then.
function Utils.Debouncer(fn, delay)
    local pending = false
    return function()
        if pending then
            return
        end
        pending = true
        C_Timer.After(delay or 0, function()
            pending = false
            fn()
        end)
    end
end

-- The player's realm, the way names carry it ("Name-Realm"). Retail only: Forever has no realms.
function Utils.MyRealm()
    if Utils.IS_FOREVER then
        return nil
    end
    local realm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if Utils.IsPlainString(realm) then
        return realm
    end
    return nil
end

-- The separator between a Forever first name and surname (a space).
function Utils.SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(sep) == "string" and sep ~= "" then
        return sep
    end
    return " "
end

-- Wraps a hook or handler so an error in it can never spam: each place reports its first error
-- once (to the error handler, so BugSack shows it) and stays quiet after that. Hooks run on every
-- text change in the game, so one bad case must not turn into thousands of errors.
local reported = {}

function Utils.Guard(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not reported[where] then
            reported[where] = true
            local handler = geterrorhandler and geterrorhandler()
            if handler then
                pcall(handler, "OnAir (" .. where .. "): " .. tostring(err))
            end
        end
        return ok
    end
end

function Utils.Print(text)
    print("|cffff3b30On|r|cffffffffAir|r  " .. tostring(text))
end
