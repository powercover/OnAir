local _, OA = ...

-- /onair check: finds leaks in the game itself, so they don't wait for someone to spot them.
--  1. Leaks: every text in the UI (closed windows too) that still holds a real name OnAir knows,
--     while live or in a preview.
--  2. Unknown players: everyone the game lets addons see (group, guild, friends and their
--     Battle.net characters, communities, group finder, who) that OnAir hasn't learned, so it
--     couldn't replace them; and names the game hides (secret), which can't be learned at all.
-- Names in the report are partly masked (Ke•••••s), so it's safe to run on stream.
OA.Check = {}

local Check = OA.Check
local Names = OA.Names
local Utils = OA.Utils
local L = OA.L
local IsSecret, IsPlain = Utils.IsSecret, Utils.IsPlainString

local MAX_LINES = 60

-- "Keraunos" -> "Ke•••••s": enough to tell who, not enough to read on stream.
local function Mask(text)
    local chars = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = ch
    end
    if #chars <= 3 then
        return (chars[1] or "") .. string.rep("\226\128\162", math.max(0, #chars - 1))
    end
    return chars[1] .. chars[2] .. string.rep("\226\128\162", #chars - 3) .. chars[#chars]
end

-- Where a text sits: its frame names up the tree (or the parent's key for unnamed ones).
local function Where(region)
    local ok, name = pcall(function() return region:GetDebugName() end)
    if ok and type(name) == "string" and name ~= "" and not IsSecret(name) then
        return name
    end
    local parts, frame = {}, region:GetParent()
    for _ = 1, 6 do
        if not frame then
            break
        end
        local n = frame.GetName and frame:GetName()
        if n then
            table.insert(parts, 1, n)
            break
        end
        table.insert(parts, 1, "?")
        frame = frame:GetParent()
    end
    return table.concat(parts, ".")
end

---------------------------------------------------------------------------------------------- leaks

-- What's actually drawn: no link targets (a chat link keeps the real name in its data on
-- purpose, so a click still reaches the player), colors, icons or Battle.net tokens.
local function Visible(text)
    return (text:gsub("|H.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""))
end

local function LeaksIn(text, aliasWords, phrases)
    text = Visible(text)
    local found = {}
    for word in text:gmatch("[^%s,%.:;!%?%(%)%[%]\"|<>/]+") do
        if Names.IsRealWord(word) and not aliasWords[word] then
            found[#found + 1] = word
        end
    end
    for _, phrase in ipairs(phrases) do
        if text:find(phrase, 1, true) then
            found[#found + 1] = phrase
        end
    end
    return found
end

local function ScanLeaks(report, secrets)
    local aliasWords, phrases = Names.AliasWords(), Names.Phrases()
    -- The UI, and the world frame too: nameplates hang off it, not the UI.
    local stack, seen, count = { UIParent, WorldFrame }, {}, 0
    while #stack > 0 do
        local frame = table.remove(stack)
        if not seen[frame] then
            seen[frame] = true
            pcall(function()
                local forbidden = frame.IsForbidden and frame:IsForbidden()
                if IsSecret(forbidden) or forbidden then
                    return
                end
                for _, region in ipairs({ frame:GetRegions() }) do
                    if region.GetObjectType and region:GetObjectType() == "FontString" and not OA.Hide.IsExempt(region) then
                        local text = region:GetText()
                        -- Hidden (secret) text on screen that OnAir left showing: could be a name.
                        if IsSecret(text) then
                            local shown = region:IsVisible()
                            local alpha = region.GetEffectiveAlpha and region:GetEffectiveAlpha() or region:GetAlpha() or 1
                            if not IsSecret(shown) and shown and not IsSecret(alpha) and type(alpha) == "number" and alpha > 0.05
                                and #secrets < MAX_LINES then
                                secrets[#secrets + 1] = "  " .. Where(region) .. "  [" .. OA.Hide.Explain(region) .. "]"
                            end
                        end
                        if type(text) == "string" and not IsSecret(text) and text ~= "" then
                            local found = LeaksIn(text, aliasWords, phrases)
                            if #found > 0 then
                                count = count + 1
                                if count <= MAX_LINES then
                                    local masked = {}
                                    for i, w in ipairs(found) do
                                        masked[i] = Mask(w)
                                    end
                                    local shown = region:IsVisible()
                                    report[#report + 1] = string.format("  %s  %s%s", table.concat(masked, ", "), Where(region),
                                        (not IsSecret(shown) and shown) and "" or "  (hidden now)")
                                end
                            end
                        end
                    end
                end
                for _, child in ipairs({ frame:GetChildren() }) do
                    stack[#stack + 1] = child
                end
            end)
        end
    end
    return count
end

---------------------------------------------------------------------------------------------- unknown players

local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
end

local function ScanPlayers(report)
    local missing, secret = {}, {}
    local function Look(name, source)
        if name == nil then
            return
        end
        if IsSecret(name) then
            secret[source] = (secret[source] or 0) + 1
            return
        end
        if IsPlain(name) and not Names.Knows(name) then
            missing[#missing + 1] = Mask(name) .. "  (" .. source .. ")"
        end
    end

    for i = 1, IsInRaid() and 40 or 4 do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            local first, realm = UnitName(unit)
            if not IsSecret(first) and IsPlain(realm) and not IsSecret(realm) then
                first = first .. "-" .. realm
            end
            Look(first, L["group"])
        end
    end
    if IsInGuild() and type(GetNumGuildMembers) == "function" then
        for i = 1, math.min(GetNumGuildMembers() or 0, 2000) do
            Look((Call(GetGuildRosterInfo, i)), L["guild"])
        end
    end
    local FL = C_FriendList
    if FL and FL.GetNumFriends then
        for i = 1, (Call(FL.GetNumFriends) or 0) do
            local info = Call(FL.GetFriendInfoByIndex, i)
            Look(info and info.name, L["friend"])
        end
    end
    local BN = C_BattleNet
    if BN and BN.GetFriendAccountInfo and type(BNGetNumFriends) == "function" then
        for i = 1, (Call(BNGetNumFriends) or 0) do
            local account = Call(BN.GetFriendAccountInfo, i)
            local game = account and account.gameAccountInfo
            -- Every game account, not just the one shown first: a friend can be on two at once.
            local numGames = BN.GetFriendNumGameAccounts and Call(BN.GetFriendNumGameAccounts, i) or 0
            if game then
                Look(game.characterName, L["Battle.net friend's character"])
            end
            for g = 1, numGames or 0 do
                local other = Call(BN.GetFriendGameAccountInfo, i, g)
                if other then
                    Look(other.characterName, L["Battle.net friend's character"])
                end
            end
            if account and IsPlain(account.battleTag) and not IsSecret(account.battleTag) then
                local tagKnown = false
                for _, phrase in ipairs(Names.Phrases()) do
                    if phrase == account.battleTag then
                        tagKnown = true
                    end
                end
                if not tagKnown then
                    missing[#missing + 1] = Mask(account.battleTag) .. "  (" .. L["BattleTag"] .. ")"
                end
            end
        end
    end
    local RA = C_RecentAllies
    if RA and RA.GetRecentAllies then
        for _, ally in ipairs(Call(RA.GetRecentAllies) or {}) do
            Look(OA.Collect.AllyName(ally), L["recent ally"])
        end
    end
    local LFG = C_LFGList
    if LFG and LFG.GetSearchResults then
        local _, results = Call(LFG.GetSearchResults)
        for _, id in ipairs(results or {}) do
            local info = Call(LFG.GetSearchResultInfo, id)
            if info then
                Look(info.leaderName, L["group finder"])
                if LFG.GetSearchResultPlayerInfo then
                    for m = 1, info.numMembers or 0 do
                        local player = Call(LFG.GetSearchResultPlayerInfo, id, m)
                        Look(type(player) == "table" and player.name or nil, L["group finder"])
                    end
                end
            end
        end
    end

    report[#report + 1] = ""
    report[#report + 1] = string.format(L["Players OnAir doesn't know: %d"], #missing)
    for i = 1, math.min(#missing, MAX_LINES) do
        report[#report + 1] = "  " .. missing[i]
    end
    for source, n in pairs(secret) do
        report[#report + 1] = string.format(L["  %d hidden by the game (%s): they can't be read, so they can't be replaced"], n, source)
    end
    return #missing
end

---------------------------------------------------------------------------------------------- run

-- /onair check 5: the same, a few seconds later (time to pull something and let it cast).
function Check.Later(seconds)
    Utils.Print(string.format(L["Checking in %d seconds."], seconds))
    C_Timer.After(seconds, function() Check.Run() end)
end

function Check.Run()
    -- Players first, before learning anything: who OnAir didn't know until now is the point.
    local players = {}
    local missing = ScanPlayers(players)
    OA.Collect.All()
    local report = {}
    local leaks = 0
    if OA.live then
        report[#report + 1] = L["Real names still on screen (or in closed windows):"]
        local secrets = {}
        leaks = ScanLeaks(report, secrets)
        if leaks == 0 then
            report[#report + 1] = L["  none"]
        elseif leaks > MAX_LINES then
            report[#report + 1] = string.format(L["  ... and %d more"], leaks - MAX_LINES)
        end
        -- EllesmereUI nameplates: what OnAir thinks of each cast target label (also between casts).
        local ns = _G.EllesmereNameplates_NS
        if ns and type(ns.plates) == "table" then
            report[#report + 1] = ""
            report[#report + 1] = L["Nameplate cast targets (EllesmereUI):"]
            local n = 0
            for _, plate in pairs(ns.plates) do
                local fs = type(plate) == "table" and plate.castTarget
                if fs and n < 12 then
                    n = n + 1
                    local text = fs:GetText()
                    local alpha = fs:GetAlpha()
                    report[#report + 1] = string.format("  alpha %s  text %s  [%s]",
                        IsSecret(alpha) and "secret" or tostring(alpha),
                        IsSecret(text) and "secret" or (text == nil and "none" or (text == "" and "empty" or Mask(text))),
                        OA.Hide.Explain(fs))
                end
            end
            if n == 0 then
                report[#report + 1] = L["  no plates now"]
            end
        end
        report[#report + 1] = ""
        report[#report + 1] = L["Hidden (secret) text still showing - may be a name the game hides from addons:"]
        if #secrets == 0 then
            report[#report + 1] = L["  none"]
        end
        for _, line in ipairs(secrets) do
            report[#report + 1] = line
        end
    else
        report[#report + 1] = L["Go live or start a preview to check the screen for real names."]
    end
    for _, line in ipairs(players) do
        report[#report + 1] = line
    end
    report[#report + 1] = ""
    report[#report + 1] = L["Names are partly masked. Send this to the developer if anything shows up."]
    OA.Moments.ShowExport(L["OnAir check"], table.concat(report, "\n"))
    Utils.Print(string.format(L["Check: %d leaks on screen, %d players unknown."], leaks, missing))
    return leaks, missing
end
