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
-- The same first errors, for /onair check (Lua errors may be turned off in the game).
Utils.errors = {}

local function Report(where, err)
    if reported[where] then
        return
    end
    reported[where] = true
    Utils.errors[#Utils.errors + 1] = where .. ": " .. tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        pcall(handler, "OnAir (" .. where .. "): " .. tostring(err))
    end
end
Utils.Report = Report

function Utils.Guard(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            Report(where, err)
        end
        return ok
    end
end

-- Milliseconds, precise (for keeping work inside a frame's budget).
Utils.Clock = type(debugprofilestop) == "function" and debugprofilestop or function()
    return GetTime() * 1000
end

-- Long work (a big guild, communities, other addons' saved data, the whole UI at go-live) runs a
-- slice at a time: a few milliseconds per frame, so it never stalls the game. A job calls
-- Utils.Pause() between steps; the first slice runs at once. Starting a job that is still
-- running starts it over.
local SLICE = 3
local Clock = Utils.Clock
local jobs, jobOrder = {}, {}
local current, sliceStart = nil, 0
local frameStamp, frameUsed = nil, 0
local jobFrame

-- One budget per frame for all jobs, however many times this runs in it (each new job starts its
-- first slice at once, and going live starts several).
local function RunJobs()
    local now = GetTime()
    if now ~= frameStamp then
        frameStamp, frameUsed = now, 0
    end
    if frameUsed >= SLICE then
        return
    end
    sliceStart = Clock() - frameUsed
    while jobOrder[1] do
        local name = jobOrder[1]
        local co = jobs[name]
        current = co
        local ok, err = coroutine.resume(co)
        current = nil
        if not ok then
            Report("job " .. name, err)
        end
        if coroutine.status(co) == "dead" then
            if jobs[name] == co then
                jobs[name] = nil
                table.remove(jobOrder, 1)
            end
        end
        if Clock() - sliceStart >= SLICE then
            frameUsed = Clock() - sliceStart
            return
        end
    end
    frameUsed = Clock() - sliceStart
    jobFrame:SetScript("OnUpdate", nil)
end

function Utils.Job(name, fn, arg)
    if not jobs[name] then
        jobOrder[#jobOrder + 1] = name
    end
    jobs[name] = coroutine.create(function() fn(arg) end)
    jobFrame = jobFrame or CreateFrame("Frame")
    jobFrame:SetScript("OnUpdate", RunJobs)
    -- Not from inside a job (it is running already): the next frame picks the new one up.
    if current == nil then
        RunJobs()
    end
end

-- Inside a job: once this frame's slice is used up, the rest waits for the next frame. Anywhere
-- else (or in someone else's coroutine) it does nothing.
function Utils.Pause()
    if current ~= nil and coroutine.running() == current and Clock() - sliceStart >= SLICE then
        coroutine.yield()
    end
end

function Utils.JobsRunning()
    return jobOrder[1] ~= nil
end

function Utils.Print(text)
    print("|cffff3b30On|r|cffffffffAir|r  " .. tostring(text))
end
