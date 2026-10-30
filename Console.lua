local _, OA = ...

-- The console: OnAir's own window (/onair, the minimap button, the Deck, a key binding).
--  top:    logo, the tally light with the timecode, Preview, Edit layout, close
--  left:   the rail, pages grouped as LIVE / PRIVACY / PRODUCTION
--  right:  the page: a header (section, title, what it does, a big faint icon), then cards
--  bottom: a status strip, one segment per system; click one to open its page
OA.UI = OA.UI or {}

local UI = OA.UI
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Names = OA.Names
local Utils = OA.Utils

local W, H = 880, 620
local HEADER, STATUS, RAIL = 56, 30, 196
local PAD = 28
local INNER = W - RAIL - PAD * 2 - 8

local console
local refreshers = {}
local pages, navs = {}, {}
local current

local function OnRefresh(fn)
    refreshers[#refreshers + 1] = fn
end

function UI.Refresh()
    if UI.UpdateExtras then
        UI.UpdateExtras()
    end
    if not console then
        return
    end
    for _, fn in ipairs(refreshers) do
        fn()
    end
end

local function Save(fn)
    return function(...)
        fn(...)
        OA.NamesChanged(false)
    end
end

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
end

---------------------------------------------------------------------------------------------- pages

local SECTIONS = {
    { title = L["LIVE"], items = {
        { key = "broadcast", icon = "Live", text = L["Broadcast"],
            desc = L["Go live, check what viewers see, and pick what shows on screen."] },
        { key = "stream", icon = "Chat", text = L["Stream chat"],
            desc = L["While live, a clean chat window covers yours and shows only what you pick, every name already an alias. Your real chat keeps running underneath."] },
        { key = "moments", icon = "Flag", text = L["Moments"],
            desc = L["Going live starts a clock at 00:00. Start your recording at the same time: a short clapper flash marks 00:00 in the video, so these timecodes match it exactly."] },
    } },
    { title = L["PRIVACY"], items = {
        { key = "names", icon = "Names", text = L["Names"],
            desc = L["Your stage name, what everyone else is called, and NPC names."] },
        { key = "hide", icon = "Hide", text = L["Hide"],
            desc = L["Whose names are swapped, and where."] },
        { key = "custom", icon = "Custom", text = L["Custom"],
            desc = L["Give a player the same alias always, e.g. your duo partner. This page holds real names: they stay masked unless you reveal them."] },
        { key = "shield", icon = "Shield", text = L["Shield"],
            desc = L["Against stream snipers and griefers, while live. Friends, Battle.net friends, your guild, your group and the players on the Custom page always get through."] },
    } },
    { title = L["PRODUCTION"], items = {
        { key = "camera", icon = "Camera", text = L["Camera"],
            desc = L["Cinematic camera for recording: zoom, field of view, shoulder offset, smoother motion, orbit."] },
        { key = "deck", icon = "Group", text = L["Deck"],
            desc = L["A small control bar that stays on screen even with the UI hidden (Alt+Z). Drag it to any edge or corner."] },
    } },
    { items = {
        { key = "about", icon = "About", text = L["About"],
            desc = L["Streamer & recording mode for World of Warcraft."] },
    } },
}

local ITEMS = {}
for _, section in ipairs(SECTIONS) do
    for _, item in ipairs(section.items) do
        item.section = section.title
        ITEMS[item.key] = item
    end
end

---------------------------------------------------------------------------------------------- top bar

local function BuildHeader(frame)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER)
    local bg = Kit.Rect(header, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    local line = Kit.Rect(header, C.line, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(Utils.MEDIA .. "Logo")
    logo:SetSize(28, 28)
    logo:SetPoint("LEFT", 18, 0)
    local title = Kit.Text(header, 20, C.text)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 1)
    title:SetText("On|cffff3b30Air|r")
    local sub = Kit.Text(header, 10, C.faint)
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText((Utils.IS_FOREVER and L["WOW FOREVER"] or L["RETAIL"]) .. "  v" .. OA.VERSION)

    -- The tally light with the running timecode: grey off the air, amber in a preview, red live.
    local tally = CreateFrame("Button", nil, header)
    tally:SetSize(200, 30)
    tally:SetPoint("CENTER", header, "CENTER", 40, 0)
    local tallyBg = Kit.Rect(tally, C.bg, "BACKGROUND")
    tallyBg:SetAllPoints()
    local tallyEdges = Kit.Border(tally)
    local glow = Kit.Shape(tally, "Glow", C.red, "BORDER")
    glow:SetSize(44, 44)
    glow:SetPoint("CENTER", tally, "LEFT", 17, 0)
    glow:SetBlendMode("ADD")
    local pulse = Kit.Pulse(glow, 0.25, 0.95, 0.8)
    local dot = Kit.Shape(tally, "Dot", C.off, "ARTWORK")
    dot:SetSize(10, 10)
    dot:SetPoint("CENTER", tally, "LEFT", 17, 0)
    local tallyText = Kit.Text(tally, 13, C.muted)
    tallyText:SetPoint("LEFT", 32, 0)
    local tallyTime = Kit.Text(tally, 15, C.text)
    tallyTime:SetPoint("RIGHT", -12, 0)
    tally:SetScript("OnClick", function() OA.Toggle() end)
    Kit.Tooltip(tally, L["Go live / end"], L["Click to go live or end the broadcast."])
    local acc = 0
    tally:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            tallyTime:SetText((OA.live and not OA.rehearsal) and FormatTime(OA.Moments.Elapsed()) or "--:--:--")
        end
    end)

    local close = Kit.IconButton(header, "Close", 30, nil, nil, function()
        UI.HideConsole()
    end)
    close:SetPoint("RIGHT", -12, 0)
    local layout = Kit.Button(header, L["Edit layout"], 104, 28, "ghost", function()
        OA.Layout.Toggle()
    end)
    layout:SetPoint("RIGHT", close, "LEFT", -8, 0)
    local preview = Kit.Button(header, L["Preview"], 96, 28, "ghost", function()
        OA.TogglePreview()
    end)
    preview:SetPoint("RIGHT", layout, "LEFT", -8, 0)
    Kit.Tooltip(preview, L["Preview"], L["Mask everything like live, to check your screen. No clock, no moments, no Shield."])

    OnRefresh(function()
        if OA.live and OA.rehearsal then
            dot:SetVertexColor(unpack(C.amber))
            glow:SetVertexColor(unpack(C.amber))
            glow:Show()
            pulse:Play()
            tallyText:SetText(L["PREVIEW"])
            tallyText:SetTextColor(unpack(C.amber))
            Kit.SetBorderColor(tallyEdges, C.line)
        elseif OA.live then
            dot:SetVertexColor(unpack(C.red))
            glow:SetVertexColor(unpack(C.red))
            glow:Show()
            pulse:Play()
            tallyText:SetText(L["ON AIR"])
            tallyText:SetTextColor(unpack(C.text))
            Kit.SetBorderColor(tallyEdges, C.redDeep)
        else
            dot:SetVertexColor(unpack(C.off))
            pulse:Stop()
            glow:Hide()
            tallyText:SetText(L["OFF AIR"])
            tallyText:SetTextColor(unpack(C.muted))
            Kit.SetBorderColor(tallyEdges, C.line)
        end
        preview.label:SetText((OA.live and OA.rehearsal) and L["End preview"] or L["Preview"])
        preview:SetAlpha((OA.live and not OA.rehearsal) and 0.35 or 1)
        layout.label:SetText(OA.Layout.IsEditing() and L["Done"] or L["Edit layout"])
    end)

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        OA.db.window = { point = point, relPoint = relPoint, x = x, y = y }
    end)
end

---------------------------------------------------------------------------------------------- rail

local NAV_H = 34
local SECTION_H = 30

local function BuildRail(frame)
    local rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", 0, -HEADER)
    rail:SetPoint("BOTTOMLEFT", 0, STATUS)
    rail:SetWidth(RAIL)
    local bg = Kit.Rect(rail, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    local edge = Kit.Rect(rail, C.line, "BORDER")
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)

    -- The marker stretches as it moves: its leading edge goes first, the trailing edge follows.
    local marker = Kit.Rect(rail, C.red, "OVERLAY")
    marker:SetWidth(3)
    local markerBg = Kit.Rect(rail, C.card, "BORDER")
    markerBg:SetWidth(RAIL - 1)
    local top, bottom = 0, NAV_H
    local edgeTop, edgeBottom = {}, {}
    local function Paint()
        marker:SetPoint("TOPLEFT", 0, -top - 5)
        marker:SetHeight(math.max(4, bottom - top - 10))
        markerBg:SetPoint("TOPLEFT", 0, -top)
        markerBg:SetHeight(math.max(1, bottom - top))
    end
    rail.Move = function(y, animate)
        if not animate then
            top, bottom = y, y + NAV_H
            Paint()
            return
        end
        local down = y > top
        Kit.Tween(edgeTop, top, y, down and 0.38 or 0.22, function(v) top = v; Paint() end, "quint")
        Kit.Tween(edgeBottom, bottom, y + NAV_H, down and 0.22 or 0.38, function(v) bottom = v; Paint() end, "quint")
    end

    local function Item(item, y)
        local b = CreateFrame("Button", nil, rail)
        b:SetSize(RAIL - 1, NAV_H)
        b:SetPoint("TOPLEFT", 0, -y)
        local icon = Kit.Icon(b, item.icon, 16, C.muted)
        icon:SetPoint("LEFT", 24, 0)
        local text = Kit.Text(b, 14, C.muted)
        text:SetPoint("LEFT", icon, "RIGHT", 12, 0)
        text:SetText(item.text)
        b.icon, b.text, b.y = icon, text, y
        b:SetScript("OnEnter", function(self)
            if current ~= item.key then
                self.text:SetTextColor(unpack(C.text))
            end
        end)
        b:SetScript("OnLeave", function(self)
            if current ~= item.key then
                self.text:SetTextColor(unpack(C.muted))
            end
        end)
        b:SetScript("OnClick", function()
            UI.ShowPage(item.key, true)
        end)
        navs[item.key] = b
    end

    local y = 10
    for _, section in ipairs(SECTIONS) do
        if section.title then
            local label = Kit.Text(rail, 10, C.faint)
            label:SetPoint("TOPLEFT", 24, -y - 14)
            label:SetText(section.title)
            y = y + SECTION_H
            for _, item in ipairs(section.items) do
                Item(item, y)
                y = y + NAV_H
            end
        else
            -- The last group sits at the bottom of the rail.
            local bottom = H - HEADER - STATUS - 12 - #section.items * NAV_H
            for i, item in ipairs(section.items) do
                Item(item, bottom + (i - 1) * NAV_H)
            end
        end
    end
    console.rail = rail
end

local function Stagger(page)
    local kids = { page.body:GetChildren() }
    for i = 1, math.min(#kids, 40) do
        local kid = kids[i]
        local target = kid.oaAlpha or 1
        kid:SetAlpha(0)
        Kit.Tween(kid, 0, target, 0.32, function(a) kid:SetAlpha(a) end, "out", 0.05 + i * 0.022)
    end
end

function UI.ShowPage(key, animate)
    if not pages[key] then
        key = "broadcast"
    end
    local old = pages[current]
    current = key
    for k, page in pairs(pages) do
        if k == key then
            page:Show()
        elseif animate and page == old and old:IsShown() then
            Kit.Tween(old, old:GetAlpha(), 0, 0.1, function(a)
                old:SetAlpha(a)
                if a <= 0 and current ~= k then
                    old:Hide()
                end
            end)
        else
            page:Hide()
        end
    end
    for k, b in pairs(navs) do
        local on = k == key
        b.text:SetTextColor(unpack(on and C.text or C.muted))
        b.icon:SetVertexColor(unpack(on and C.red or C.muted))
        if on then
            console.rail.Move(b.y, animate)
        end
    end
    local page = pages[key]
    if animate then
        page:SetAlpha(0)
        Kit.Tween(page, 0, 1, 0.36, function(p)
            page:SetAlpha(p)
            page:SetPoint("TOPLEFT", RAIL + 28 * (1 - p), -HEADER)
        end, "quint", 0.06)
        Stagger(page)
    else
        page:SetAlpha(1)
        page:SetPoint("TOPLEFT", RAIL, -HEADER)
    end
    if page.OnShow then
        page.OnShow()
    end
end

---------------------------------------------------------------------------------------------- status strip

local function BuildStatus(frame)
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("BOTTOMLEFT")
    strip:SetPoint("BOTTOMRIGHT")
    strip:SetHeight(STATUS)
    local bg = Kit.Rect(strip, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    local line = Kit.Rect(strip, C.line, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)

    local segments = {
        { page = "broadcast", text = function()
            if OA.live and OA.rehearsal then
                return L["PREVIEW"], C.amber
            elseif OA.live then
                return L["LIVE"] .. "  " .. FormatTime(OA.Moments.Elapsed()), C.red
            end
            return L["OFF AIR"], C.off
        end },
        { page = "names", text = function()
            return string.format(L["%d masked"], Names.Count()), OA.live and C.red or C.off
        end },
        { page = "stream", text = function()
            local on = OA.db.stream.enabled
            return L["STREAM CHAT"] .. " " .. (on and L["on"] or L["off"]), on and C.green or C.off
        end },
        { page = "moments", text = function()
            local session = OA.Moments.Current()
            local n = session and #session.moments or 0
            return string.format(L["%d moments"], n), n > 0 and C.text or C.off
        end },
        { page = "shield", text = function()
            local held = OA.Shield.HeldCount()
            if held > 0 then
                return string.format(L["SHIELD  %d held"], held), C.amber
            end
            return L["SHIELD"] .. " " .. (OA.db.shield.whispers and L["on"] or L["off"]), OA.db.shield.whispers and C.green or C.off
        end },
        { page = "camera", text = function()
            local cam = OA.db.camera
            local on = OA.Camera.Active()
            return L["CAM"] .. " " .. (on and cam.preset or L["off"]), on and C.green or C.off
        end },
    }
    local x = 12
    for _, seg in ipairs(segments) do
        local b = CreateFrame("Button", nil, strip)
        b:SetHeight(STATUS)
        b:SetPoint("LEFT", x, 0)
        local dot = Kit.Shape(b, "Dot", C.off, "ARTWORK")
        dot:SetSize(6, 6)
        dot:SetPoint("LEFT", 6, 0)
        local text = Kit.Text(b, 11, C.muted)
        text:SetPoint("LEFT", dot, "RIGHT", 7, 0)
        b:SetWidth(118)
        b:SetScript("OnClick", function() UI.ShowPage(seg.page, true) end)
        b:SetScript("OnEnter", function() text:SetTextColor(unpack(C.text)) end)
        b:SetScript("OnLeave", function() text:SetTextColor(unpack(C.muted)) end)
        seg.dot, seg.label = dot, text
        x = x + 122
    end
    local function Paint()
        for _, seg in ipairs(segments) do
            local text, color = seg.text()
            seg.label:SetText(text:upper())
            seg.dot:SetVertexColor(unpack(color))
        end
    end
    local acc = 0
    strip:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.5 then
            acc = 0
            Paint()
        end
    end)
    OnRefresh(Paint)
end

---------------------------------------------------------------------------------------------- page helpers

-- A page: its header (section, title, what it does, a big faint icon), then the content.
local HERO_H = 96

local function NewPage(key)
    local item = ITEMS[key]
    local page = CreateFrame("Frame", nil, console)
    page:SetPoint("TOPLEFT", RAIL, -HEADER)
    page:SetPoint("BOTTOMRIGHT", 0, STATUS)
    local scroll = Kit.Scroll(page, W - RAIL - 8)
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    page.body = scroll.child
    page.scroll = scroll

    local body = page.body
    local watermark = Kit.Icon(body, item.icon, 128, C.red)
    watermark:SetPoint("TOPRIGHT", -PAD + 8, -10)
    watermark:SetAlpha(0.06)
    local kicker = Kit.Text(body, 10, C.red)
    kicker:SetPoint("TOPLEFT", PAD, -PAD + 4)
    kicker:SetText(item.section or "ONAIR")
    local title = Kit.Text(body, 26, C.text)
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
    title:SetText(item.text)
    local desc = Kit.Text(body, 13, C.muted)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(INNER - 110)
    desc:SetWordWrap(true)
    desc:SetSpacing(2)
    desc:SetText(item.desc)
    page.heroBottom = PAD + 4 + 10 + 6 + 30 + 8 + math.max(desc:GetStringHeight(), 16)
    local rule = Kit.Rect(body, C.line, "BORDER")
    rule:SetPoint("TOPLEFT", PAD, -page.heroBottom - 14)
    rule:SetSize(INNER, 1)
    page.heroBottom = page.heroBottom + 30

    page:Hide()
    pages[key] = page
    return page
end

-- Lays controls out top to bottom inside a page, below its header.
local function Flow(page)
    local y = -(page.heroBottom or HERO_H)
    local flow = {}
    function flow.Add(region, height, gap, x)
        region:SetPoint("TOPLEFT", page.body, "TOPLEFT", PAD + (x or 0), y)
        y = y - height - (gap or 12)
        return region
    end
    function flow.Space(h)
        y = y - h
    end
    function flow.Y()
        return -y
    end
    function flow.Heading(text, hint)
        local heading = Kit.Heading(page.body, text)
        flow.Add(heading, 12, hint and 4 or 10)
        if hint then
            local fs = Kit.Text(page.body, 12, C.faint)
            fs:SetWidth(INNER)
            fs:SetWordWrap(true)
            fs:SetText(hint)
            flow.Add(fs, fs:GetStringHeight(), 10)
        end
        return heading
    end
    function flow.Finish()
        page.scroll:SetContentHeight(-y + PAD)
    end
    return flow
end

-- A card: icon, title, a line of help and a switch. On: a red edge on the left and a red icon.
local TILE_W, TILE_H = (INNER - 12) / 2, 64

local function Tile(parent, icon, title, help, get, set)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(TILE_W, TILE_H)
    local bg = Kit.Rect(tile, C.card, "BACKGROUND")
    bg:SetAllPoints()
    local edges = Kit.Border(tile)
    local sheen = Kit.Rect(tile, { 1, 1, 1, 0.035 }, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    local accent = Kit.Rect(tile, C.red, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(2)
    local badge = Kit.Rect(tile, C.raised, "BORDER")
    badge:SetSize(36, 36)
    badge:SetPoint("LEFT", 14, 0)
    local glyph = Kit.Icon(tile, icon, 20, C.muted)
    glyph:SetPoint("CENTER", badge)
    local name = Kit.Text(tile, 14, C.text)
    name:SetPoint("TOPLEFT", badge, "TOPRIGHT", 12, -1)
    name:SetText(title)
    local sub = Kit.Text(tile, 11, C.muted)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", tile, "RIGHT", -60, 0)
    sub:SetWordWrap(true)
    sub:SetMaxLines(2)
    sub:SetText(help)
    local switch = Kit.Switch(tile, get, function(value)
        set(value)
        UI.Refresh()
    end)
    switch:SetPoint("RIGHT", -14, 0)
    local lit = get() and 1 or 0
    local function Paint(animate)
        local on = get() and 1 or 0
        glyph:SetVertexColor(unpack(on == 1 and C.red or C.faint))
        Kit.SetBorderColor(edges, on == 1 and C.line or C.card)
        name:SetTextColor(unpack(on == 1 and C.text or C.muted))
        if animate then
            Kit.Tween(accent, lit, on, 0.2, function(p) accent:SetAlpha(p) end)
        else
            accent:SetAlpha(on)
        end
        lit = on
    end
    tile:EnableMouse(true)
    local hover = {}
    tile:SetScript("OnEnter", function()
        Kit.Tween(hover, 0, 1, 0.14, function(p) bg:SetColorTexture(Kit.Mix(C.card, C.raised, p)) end)
    end)
    tile:SetScript("OnLeave", function()
        Kit.Tween(hover, 1, 0, 0.3, function(p) bg:SetColorTexture(Kit.Mix(C.card, C.raised, p)) end)
    end)
    tile:SetScript("OnMouseUp", function()
        switch:Click()
    end)
    OnRefresh(function()
        switch:Refresh(true)
        Paint(true)
    end)
    Paint(false)
    return tile
end

-- A row of three short text fields with small labels above (aliases, labels).
local function Fields(body, flow, specs)
    local w = (INNER - 12) / #specs
    local first
    for i, spec in ipairs(specs) do
        local box = Kit.Input(body, w - 4, spec.get, spec.set)
        if i == 1 then
            flow.Add(box, 28, 22, 0)
            first = box
        else
            box:SetPoint("LEFT", first, "LEFT", (i - 1) * (w + 2), 0)
        end
        local label = Kit.Text(body, 10, C.faint)
        label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 4)
        label:SetText(spec.label:upper())
        spec.box = box
    end
    return specs
end

---------------------------------------------------------------------------------------------- broadcast page

local function BuildBroadcast()
    local page = NewPage("broadcast")
    local flow = Flow(page)
    local body = page.body

    flow.Heading(L["Go live"])
    -- The big button, with a glow that breathes while live.
    local holder = CreateFrame("Frame", nil, body)
    holder:SetSize(INNER, 76)
    flow.Add(holder, 76, 18)
    local glow = Kit.Shape(holder, "Glow", C.red, "BACKGROUND")
    glow:SetSize(360, 150)
    glow:SetPoint("CENTER", holder, "LEFT", 140, 0)
    glow:SetBlendMode("ADD")
    local breathe = Kit.Pulse(glow, 0.15, 0.55, 1.4)
    local go = Kit.Button(holder, L["GO LIVE"], 280, 64, "primary", function()
        OA.Toggle()
    end)
    go:SetPoint("LEFT")
    go.label:SetFontObject(Kit.Font(22))
    local timer = Kit.Text(holder, 26, C.text)
    timer:SetPoint("LEFT", go, "RIGHT", 24, 8)
    local timerSub = Kit.Text(holder, 11, C.muted)
    timerSub:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -4)
    local ticker = CreateFrame("Frame", nil, holder)
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.25 then
            return
        end
        acc = 0
        if OA.live then
            timer:SetText(FormatTime(OA.Moments.Elapsed()))
        end
    end)

    flow.Heading(L["What viewers see"], L["Real names are never shown here, so it's safe to open the console on stream."])
    local card = CreateFrame("Frame", nil, body)
    local ROWS = {
        { icon = "Me", text = L["You"], alias = function() return Names.MeAlias() end },
        { icon = "Group", text = L["Party member"], alias = function() return Names.Sample("crew", 1, "crew:a") end },
        { icon = "Group", text = L["Party member"], alias = function() return Names.Sample("crew", 2, "crew:b") end },
        { icon = "Social", text = L["Stranger"], alias = function() return Names.Sample("others", 1, "other:a") end },
        { icon = "Guild", text = L["Your guild"], alias = function() return Names.Fill(OA.db.guildAlias, 0) end },
        { icon = "Pet", text = L["Your pet"], alias = function()
            return (OA.db.petTemplate:gsub("{owner}", Names.MeAlias()))
        end },
    }
    local ROW_H = 34
    card:SetSize(INNER, #ROWS * ROW_H + 12)
    flow.Add(card, #ROWS * ROW_H + 12, 18)
    local cardBg = Kit.Rect(card, C.card, "BACKGROUND")
    cardBg:SetAllPoints()
    Kit.Border(card)
    for i, row in ipairs(ROWS) do
        local y = -6 - (i - 1) * ROW_H
        local icon = Kit.Icon(card, row.icon, 16, C.faint)
        icon:SetPoint("TOPLEFT", 16, y - 9)
        local who = Kit.Text(card, 13, C.muted)
        who:SetPoint("LEFT", icon, "RIGHT", 12, 0)
        who:SetText(row.text)
        local arrow = Kit.Icon(card, "Chevron", 12, C.faint)
        arrow:SetRotation(math.rad(90))
        arrow:SetPoint("LEFT", card, "TOPLEFT", 190, y - 17)
        local alias = Kit.Text(card, 15, C.text)
        alias:SetPoint("LEFT", arrow, "RIGHT", 16, 0)
        alias:SetPoint("RIGHT", card, "RIGHT", -16, 0)
        if i < #ROWS then
            local sep = Kit.Rect(card, C.bg, "BORDER")
            sep:SetPoint("TOPLEFT", 12, y - ROW_H + 1)
            sep:SetPoint("TOPRIGHT", -12, y - ROW_H + 1)
            sep:SetHeight(1)
        end
        OnRefresh(function()
            alias:SetText(row.alias())
        end)
    end

    flow.Heading(L["On screen"])
    local t1 = Tile(body, "Live", L["ON AIR badge"], L["Red badge while live. Drag it; click to end, right-click for the console."],
        function() return OA.db.badge end, function(v) OA.db.badge = v end)
    local t2 = Tile(body, "Overhead", L["Go-live banner"], L["A short banner when you go live or end."],
        function() return OA.db.toast end, function(v) OA.db.toast = v end)
    flow.Add(t1, 0, 0)
    t2:SetPoint("TOPLEFT", t1, "TOPRIGHT", 12, 0)
    flow.Space(TILE_H + 12)
    local t3 = Tile(body, "World", L["Minimap button"], L["Left-click: go live or end. Right-click: console."],
        function() return OA.db.minimap.show end, function(v) OA.db.minimap.show = v end)
    flow.Add(t3, TILE_H, 18)

    flow.Finish()

    OnRefresh(function()
        if OA.live then
            go.label:SetText(L["END BROADCAST"])
            go:SetColors(C.redDeep, { 0.68, 0.12, 0.09, 1 })
            breathe:Play()
            glow:Show()
            timer:SetText(FormatTime(OA.Moments.Elapsed()))
            timer:SetTextColor(unpack(C.text))
            timerSub:SetText(string.format(L["ON AIR  -  %d players masked"], Names.Count()))
        else
            go.label:SetText(L["GO LIVE"])
            go:SetColors(C.red, { 1, 0.36, 0.31, 1 })
            breathe:Stop()
            glow:Hide()
            timer:SetText("00:00:00")
            timer:SetTextColor(unpack(C.faint))
            timerSub:SetText(L["OFF AIR  -  real names showing"])
        end
    end)
end

---------------------------------------------------------------------------------------------- names page

local MODES = {
    { value = "cast", text = L["Cast names"] },
    { value = "template", text = L["Template"] },
}

local function TokenHint()
    return L["Tokens: {me} your stage name, {n} a number, {role} tank/healer/DPS, {class} their class."]
end

local function GroupControls(page, flow, group, title, hint)
    flow.Heading(title, hint)
    local seg = Kit.Segmented(page.body, MODES, 260, function() return group.mode end, Save(function(v) group.mode = v end))
    flow.Add(seg, 26, 10)
    local input = Kit.Input(page.body, INNER, function() return group.template end,
        Save(function(v) if v ~= "" then group.template = v end end))
    flow.Add(input, 28, 22)
    OnRefresh(function()
        seg:Refresh(true)
        input:Refresh()
        input:SetEnabledLook(group.mode == "template")
    end)
end

local function BuildNames()
    local page = NewPage("names")
    local flow = Flow(page)
    local body = page.body
    local db = OA.db

    flow.Heading(L["Your stage name"], L["Replaces your name everywhere: frames, chat, meters, tooltips."])
    local me = Kit.Input(body, INNER - 76, function() return db.me end, Save(function(v)
        if v ~= "" then db.me = v end
    end))
    flow.Add(me, 28, 22)
    local dice = Kit.IconButton(body, "Dice", 30, L["Suggest a name"], L["A random stage name from the theme."], function()
        db.me = OA.Cast.SuggestStage(db.theme, db.me)
        OA.NamesChanged(false)
    end)
    dice:SetPoint("LEFT", me, "RIGHT", 8, 0)
    OnRefresh(function() me:Refresh() end)

    local themes = {}
    for _, theme in ipairs(OA.Cast.THEMES) do
        themes[#themes + 1] = { value = theme.key, text = theme.name }
    end
    flow.Heading(L["Theme"], L["Where cast names come from."])
    local themeSeg = Kit.Segmented(body, themes, INNER, function() return db.theme end, function(v)
        db.theme = v
        OA.NamesChanged(true)
    end)
    flow.Add(themeSeg, 26, 22)
    OnRefresh(function() themeSeg:Refresh(true) end)

    GroupControls(page, flow, db.crew, L["Crew: party & raid"], TokenHint())
    GroupControls(page, flow, db.others, L["Everyone else"], L["Strangers, guildmates, friends, people in lists and chat."])

    flow.Heading(L["Guild & pets"], L["Your guild's name, other guilds ({n} counts them), and pets ({owner} is their owner's alias)."])
    local guild = Kit.Input(body, (INNER - 12) / 3, function() return db.guildAlias end,
        Save(function(v) if v ~= "" then db.guildAlias = v end end))
    flow.Add(guild, 28, 22)
    local other = Kit.Input(body, (INNER - 12) / 3, function() return db.otherGuild end,
        Save(function(v) if v ~= "" then db.otherGuild = v end end))
    other:SetPoint("LEFT", guild, "RIGHT", 6, 0)
    local pet = Kit.Input(body, (INNER - 12) / 3, function() return db.petTemplate end,
        Save(function(v) if v ~= "" then db.petTemplate = v end end))
    pet:SetPoint("LEFT", other, "RIGHT", 6, 0)
    OnRefresh(function()
        guild:Refresh()
        other:Refresh()
        pet:Refresh()
    end)

    flow.Heading(L["NPC names"], L["Real names, a generic label, or nothing: on nameplates, target frames, tooltips and chat. Names above heads are drawn by the game, so Generic and Hidden switch those off (also with the UI hidden)."])
    local npc = db.npc
    local function NpcChanged()
        if OA.live then
            OA.Hide.RestoreCVars()
            OA.Hide.ApplyCVars()
            OA.Hide.AllNamePlates()
            OA.Hide.UnitFrames()
        end
        UI.Refresh()
    end
    local npcMode = Kit.Segmented(body, {
        { value = "real", text = L["Real names"] },
        { value = "generic", text = L["Generic"] },
        { value = "hide", text = L["Hidden"] },
    }, 360, function() return npc.mode end, function(v)
        npc.mode = v
        NpcChanged()
    end)
    flow.Add(npcMode, 26, 30)
    local labels = Fields(body, flow, {
        { label = L["Enemies"], get = function() return npc.enemy end, set = function(v) if v ~= "" then npc.enemy = v; NpcChanged() end end },
        { label = L["Friendly NPCs"], get = function() return npc.friendly end, set = function(v) if v ~= "" then npc.friendly = v; NpcChanged() end end },
        { label = L["Bosses"], get = function() return npc.boss end, set = function(v) if v ~= "" then npc.boss = v; NpcChanged() end end },
    })
    OnRefresh(function()
        npcMode:Refresh(true)
        for _, spec in ipairs(labels) do
            spec.box:Refresh()
            spec.box:SetEnabledLook(npc.mode == "generic")
        end
    end)

    flow.Heading(L["Start over"], L["Everyone draws a new alias. Names you set on the Custom page stay."])
    local shuffle = Kit.Button(body, L["Reshuffle everyone"], 200, 30, "ghost", function()
        OA.NamesChanged(true)
        Utils.Print(L["Everyone drew a new name."])
    end)
    flow.Add(shuffle, 30, 12)
    flow.Finish()
end

---------------------------------------------------------------------------------------------- hide page

local function BuildHide()
    local page = NewPage("hide")
    local flow = Flow(page)
    local body = page.body
    local db = OA.db

    local function Grid(specs, getRoot)
        for i, spec in ipairs(specs) do
            local tile = Tile(body, spec[1], spec[2], spec[3], function() return getRoot()[spec[4]] ~= false end,
                function(v)
                    getRoot()[spec[4]] = v
                    OA.NamesChanged(false)
                    if OA.live and spec[5] then
                        spec[5]()
                    end
                end)
            if i % 2 == 1 then
                flow.Add(tile, 0, 0)
                if i == #specs then
                    flow.Space(TILE_H + 12)
                end
                specs.lastLeft = tile
            else
                tile:SetPoint("TOPLEFT", specs.lastLeft, "TOPRIGHT", 12, 0)
                flow.Space(TILE_H + 12)
            end
        end
        flow.Space(14)
    end

    local function CVars()
        OA.Hide.RestoreCVars()
        OA.Hide.ApplyCVars()
    end

    flow.Heading(L["Whose names"])
    Grid({
        { "Me", L["Your name"], L["Every character you play."], "me", CVars },
        { "Group", L["Party & raid"], L["Your crew while grouped."], "crew" },
        { "Social", L["Everyone else"], L["Strangers, guild, lists."], "others", CVars },
        { "BNet", L["Battle.net friends"], L["Real names and BattleTags."], "friends" },
        { "Guild", L["Guild names"], L["Yours and everyone's."], "guilds" },
        { "Pet", L["Pets & minions"], L["They carry their owner's name."], "pets", CVars },
    }, function() return db.who end)

    flow.Heading(L["Where"])
    Grid({
        { "Chat", L["Chat"], L["Senders, names in messages, whispers."], "chat" },
        { "Trash", L["Clear chat on go live"], L["Wipes old lines with real names."], "clearChat" },
        { "Nameplate", L["Nameplates & overhead"], L["Plates and names above heads."], "nameplates", CVars },
        { "Tooltip", L["Tooltips"], L["Unit tooltips, guild lines, lists."], "tooltips" },
        { "Meter", L["Damage meters"], L["Blizzard's and EllesmereUI's, also in combat."], "meters" },
        { "UnitFrame", L["Interface text"], L["Unit & raid frames, character, friends, guild, LFG, mail."], "interface" },
    }, function() return db.where end)

    local note = Kit.Text(body, 12, C.faint)
    note:SetWidth(INNER)
    note:SetWordWrap(true)
    note:SetText(L["Changes apply right away. Turning something off brings real names back in new text; a reload brings them back everywhere."])
    flow.Add(note, note:GetStringHeight(), 12)
    flow.Finish()
end

---------------------------------------------------------------------------------------------- stream chat page

local function BuildStream()
    local page = NewPage("stream")
    local flow = Flow(page)
    local body = page.body
    local Stream = OA.StreamChat
    local db = OA.db.stream

    local on = Tile(body, "Chat", L["Use stream chat while live"], L["Off: your normal chat stays in view (names still hidden)."],
        function() return db.enabled end, function(v)
            db.enabled = v
            Stream.Update()
        end)
    flow.Add(on, TILE_H, 22)

    flow.Heading(L["Show in stream chat"])
    local lastLeft
    for i, group in ipairs(Stream.GROUPS) do
        local tile = Tile(body, group.icon, group.text, group.help,
            function() return db.groups[group.key] == true end,
            function(v)
                db.groups[group.key] = v or nil
                Stream.Update()
            end)
        if i % 2 == 1 then
            flow.Add(tile, 0, 0)
            lastLeft = tile
            if i == #Stream.GROUPS then
                flow.Space(TILE_H + 12)
            end
        else
            tile:SetPoint("TOPLEFT", lastLeft, "TOPRIGHT", 12, 0)
            flow.Space(TILE_H + 12)
        end
    end
    flow.Space(10)

    flow.Heading(L["Look"])
    local colW = (INNER - 28) / 2
    local size = Kit.Slider(body, colW, L["Text size"], 10, 22, 1, function() return db.fontSize end, function(v)
        db.fontSize = v
        Stream.ApplyLook()
    end)
    flow.Add(size, 40, 16)
    local opacity = Kit.Slider(body, colW, L["Background"], 0, 1, 0.05, function() return db.opacity end, function(v)
        db.opacity = v
        Stream.ApplyLook()
    end, function(v) return string.format("%d%%", v * 100) end)
    opacity:SetPoint("LEFT", size, "RIGHT", 28, 0)
    local fade = Tile(body, "Trash", L["Fade old lines"], L["Lines fade out after a minute."],
        function() return db.fade ~= false end, function(v)
            db.fade = v
            Stream.ApplyLook()
        end)
    flow.Add(fade, 0, 0)
    local headerTile = Tile(body, "Live", L["ON AIR bar"], L["The thin red bar on top (drag it to move)."],
        function() return db.header ~= false end, function(v)
            db.header = v
            Stream.ApplyLook()
        end)
    headerTile:SetPoint("TOPLEFT", fade, "TOPRIGHT", 12, 0)
    flow.Space(TILE_H + 22)

    local place = Kit.Button(body, L["Place the window"], 180, 30, "ghost", function()
        Stream.TogglePlacing()
        UI.Refresh()
    end)
    flow.Add(place, 30, 12)
    local reset = Kit.Button(body, L["Back over my chat"], 170, 30, "ghost", function()
        Stream.ResetPosition()
    end)
    reset:SetPoint("LEFT", place, "RIGHT", 10, 0)
    flow.Finish()

    OnRefresh(function()
        size:Refresh()
        opacity:Refresh()
        place.label:SetText(Stream.IsPlacing() and L["Done placing"] or L["Place the window"])
    end)
end

---------------------------------------------------------------------------------------------- moments page

local function BuildMoments()
    local page = NewPage("moments")
    local flow = Flow(page)
    local body = page.body
    local Moments = OA.Moments
    local db = OA.db.moments
    local shown -- the session on screen (index); nil = the latest

    flow.Heading(L["Session clock"])
    local clockRow = CreateFrame("Frame", nil, body)
    clockRow:SetSize(INNER, 56)
    flow.Add(clockRow, 56, 14)
    local clock = Kit.Text(clockRow, 34, C.text)
    clock:SetPoint("LEFT")
    local mark = Kit.Button(clockRow, L["Mark moment"], 150, 34, "primary", function()
        Moments.Mark()
    end)
    mark:SetPoint("LEFT", 190, 0)
    local restart = Kit.Button(clockRow, L["Restart clock"], 130, 34, "ghost", function()
        Moments.Restart()
    end)
    restart:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    local ticker = CreateFrame("Frame", nil, clockRow)
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            clock:SetText(OA.live and Moments.Format(Moments.Elapsed(), true) or "-:--:--")
            clock:SetTextColor(unpack(OA.live and C.text or C.faint))
        end
    end)
    local tip = Kit.Text(body, 12, C.faint)
    tip:SetWidth(INNER)
    tip:SetWordWrap(true)
    tip:SetText(L["Tip: bind the same key to OnAir > Mark a moment and to OBS's replay buffer (Save replay). One press gives you a clip and a timecode."])
    flow.Add(tip, tip:GetStringHeight(), 22)

    -- Session picker: older sessions stay for exporting later.
    local picker = CreateFrame("Frame", nil, body)
    picker:SetSize(INNER, 30)
    flow.Add(picker, 30, 10)
    local prev = Kit.IconButton(picker, "Chevron", 28, L["Older session"])
    prev.icon:SetRotation(math.rad(-90))
    prev:SetPoint("LEFT")
    local sessionText = Kit.Text(picker, 13, C.text)
    sessionText:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    local nextB = Kit.IconButton(picker, "Chevron", 28, L["Newer session"])
    nextB.icon:SetRotation(math.rad(90))
    nextB:SetPoint("LEFT", 270, 0)
    local list = Kit.Button(picker, L["Marker list"], 120, 28, "ghost")
    list:SetPoint("RIGHT")
    local chapters = Kit.Button(picker, L["YouTube chapters"], 140, 28, "ghost")
    chapters:SetPoint("RIGHT", list, "LEFT", -8, 0)

    local listFrame = CreateFrame("Frame", nil, body)
    listFrame:SetSize(INNER, 10)
    flow.Add(listFrame, 10, 0)
    local empty = Kit.Text(listFrame, 13, C.faint)
    empty:SetPoint("TOPLEFT", 4, -6)
    empty:SetText(L["No moments yet. Go live, and they show up here as they happen."])
    local rows = {}
    local ROW_H = 26
    local MAX_ROWS = 60

    -- Below the list: the automatic markers.
    local after = CreateFrame("Frame", nil, body)
    after:SetSize(INNER, 10)
    local heading = Kit.Heading(after, L["Mark automatically"])
    heading:SetPoint("TOPLEFT", 0, -16)
    local lastLeft
    for i, group in ipairs(Moments.AUTO) do
        local tile = Tile(after, group.icon, group.text, group.help,
            function() return db.auto[group.key] ~= false end,
            function(v) db.auto[group.key] = v end)
        local row = math.floor((i - 1) / 2)
        if i % 2 == 1 then
            tile:SetPoint("TOPLEFT", 0, -40 - row * (TILE_H + 12))
            lastLeft = tile
        else
            tile:SetPoint("TOPLEFT", lastLeft, "TOPRIGHT", 12, 0)
        end
    end
    local extrasY = -40 - math.ceil(#Moments.AUTO / 2) * (TILE_H + 12) - 10
    local shot = Tile(after, "Camera", L["Screenshot each moment"], L["Saved in your Screenshots folder: thumbnails."],
        function() return db.screenshot == true end, function(v) db.screenshot = v end)
    shot:SetPoint("TOPLEFT", 0, extrasY)
    local flashTile = Tile(after, "Clapper", L["Clapper flash at 00:00"], L["A short white flash when you go live."],
        function() return db.flash ~= false end, function(v) db.flash = v end)
    flashTile:SetPoint("TOPLEFT", shot, "TOPRIGHT", 12, 0)
    local noteTile = Tile(after, "Chat", L["Moments in stream chat"], L["A line with the timecode as it happens."],
        function() return db.note ~= false end, function(v) db.note = v end)
    noteTile:SetPoint("TOPLEFT", 0, extrasY - TILE_H - 12)
    local afterH = -extrasY + (TILE_H + 12) * 2 + 10
    local listTop = 0

    local function Session()
        local sessions = Moments.Sessions()
        local index = shown or #sessions
        return sessions[index], index, #sessions
    end

    local function Render()
        local session, index, total = Session()
        if session then
            sessionText:SetText(string.format(L["Session %d of %d  -  %s"], index, total, date("%d %b %H:%M", session.started)))
        else
            sessionText:SetText(L["No sessions yet"])
        end
        prev:SetEnabled(index > 1)
        prev:SetAlpha(index > 1 and 1 or 0.3)
        nextB:SetEnabled(index < total)
        nextB:SetAlpha(index < total and 1 or 0.3)
        local moments = session and session.moments or {}
        local first = math.max(1, #moments - MAX_ROWS + 1)
        local n = 0
        for i = #moments, first, -1 do
            n = n + 1
            local moment = moments[i]
            local row = rows[n]
            if not row then
                row = CreateFrame("Frame", nil, listFrame)
                row:SetSize(INNER, ROW_H - 2)
                row:SetPoint("TOPLEFT", 0, -(n - 1) * ROW_H)
                local bg = Kit.Rect(row, n % 2 == 0 and C.bg or C.card, "BACKGROUND")
                bg:SetAllPoints()
                row.time = Kit.Text(row, 13, C.muted)
                row.time:SetPoint("LEFT", 10, 0)
                row.icon = Kit.Icon(row, "Flag", 14, C.text)
                row.icon:SetPoint("LEFT", 82, 0)
                row.text = Kit.Text(row, 13, C.text)
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
                row.text:SetPoint("RIGHT", -10, 0)
                rows[n] = row
            end
            local kind = Moments.KINDS[moment.kind] or Moments.KINDS.mark
            row.time:SetText(Moments.Format(moment.t, true))
            row.icon:SetTexture(Utils.ICONS .. kind.icon)
            row.icon:SetVertexColor(unpack(kind.color))
            row.text:SetText(moment.text)
            row:Show()
        end
        for i = n + 1, #rows do
            rows[i]:Hide()
        end
        empty:SetShown(n == 0)
        local h = math.max(30, n * ROW_H)
        listFrame:SetHeight(h)
        after:ClearAllPoints()
        after:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 0, -10)
        page.scroll:SetContentHeight(listTop + h + 10 + afterH + PAD)
    end
    UI.RefreshMoments = function()
        if console and console:IsShown() and current == "moments" then
            Render()
        end
    end

    prev:SetScript("OnClick", function()
        local _, index = Session()
        shown = math.max(1, index - 1)
        Render()
    end)
    nextB:SetScript("OnClick", function()
        local _, index, total = Session()
        shown = (index + 1 >= total) and nil or index + 1
        Render()
    end)
    chapters:SetScript("OnClick", function()
        local session = Session()
        if session then
            Moments.ShowExport(L["YouTube chapters"], Moments.Chapters(session))
        end
    end)
    list:SetScript("OnClick", function()
        local session = Session()
        if session then
            Moments.ShowExport(L["Marker list"], Moments.MarkerList(session))
        end
    end)

    flow.Finish()
    listTop = page.scroll.child:GetHeight() - PAD
    OnRefresh(function()
        Render()
        mark.oaAlpha = (OA.live and not OA.rehearsal) and 1 or 0.4
        mark:SetAlpha(mark.oaAlpha)
    end)
end

---------------------------------------------------------------------------------------------- shield page

local function BuildShield()
    local page = NewPage("shield")
    local flow = Flow(page)
    local body = page.body
    local db = OA.db.shield


    local function Pair(left, right)
        flow.Add(left, 0, 0)
        if right then
            right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
        end
        flow.Space(TILE_H + 12)
    end
    local function T(icon, title, help, key, after)
        return Tile(body, icon, title, help, function() return db[key] == true end, function(v)
            db[key] = v
            if after then
                after()
            end
        end)
    end
    local function Apply()
        OA.Shield.Apply()
    end

    flow.Heading(L["Strangers"])
    Pair(T("BNet", L["Hold stranger whispers"], L["Shown in chat when the broadcast ends."], "whispers"),
        T("Chat", L["Polite auto-reply"], L["Once per player per 15 minutes."], "reply"))
    Pair(T("Group", L["Decline group invites"], L["From players you don't know."], "invites"),
        T("Social", L["Decline duels"], L["From players you don't know."], "duels"))
    Pair(T("Plus", L["Decline trades"], L["From players you don't know."], "trades"))

    flow.Heading(L["Auto-reply text"])
    local reply = Kit.Input(body, INNER, function() return db.replyText end, function(v)
        if v ~= "" then
            db.replyText = v
        end
    end)
    reply:SetMaxLetters(240)
    flow.Add(reply, 28, 22)

    flow.Heading(L["Location"])
    Pair(T("World", L["Hide zone names"], L["Your zone reads Somewhere in all text."], "zones", Apply),
        T("Overhead", L["Hide zone banners"], L["The big zone name when you enter."], "banners", Apply))
    Pair(T("Nameplate", L["Hide the minimap"], L["Its map shows where you are."], "minimap", Apply))

    local held = Kit.Text(body, 13, C.muted)
    flow.Add(held, 16, 14)
    local note = Kit.Text(body, 12, C.faint)
    note:SetWidth(INNER)
    note:SetWordWrap(true)
    note:SetText(L["An addon can't delay your stream: set a stream delay in OBS too. Auto-replies wait outside boss encounters, when the game blocks addon chat."])
    flow.Add(note, note:GetStringHeight(), 12)
    flow.Finish()

    OnRefresh(function()
        reply:Refresh()
        local count = OA.Shield.HeldCount()
        held:SetText(count > 0 and string.format(L["%d whispers held so far."], count) or L["No whispers held."])
    end)
end

---------------------------------------------------------------------------------------------- camera page

local function BuildCamera()
    local page = NewPage("camera")
    local flow = Flow(page)
    local body = page.body
    local Camera = OA.Camera
    local cam = OA.db.camera

    flow.Heading(L["When"], L["Off leaves your camera alone. Always works without going live. While live switches with the broadcast. Your own camera settings come back when it turns off."])
    local modes = Kit.Segmented(body, {
        { value = "off", text = L["Off"] },
        { value = "always", text = L["Always"] },
        { value = "live", text = L["Only while live"] },
    }, 360, function() return cam.mode end, function(v)
        cam.mode = v
        Camera.Update()
        UI.Refresh()
    end)
    flow.Add(modes, 26, 22)

    flow.Heading(L["Presets"])
    local presetOptions = {}
    for _, preset in ipairs(Camera.PRESETS) do
        presetOptions[#presetOptions + 1] = { value = preset.key, text = preset.text }
    end
    presetOptions[#presetOptions + 1] = { value = "custom", text = L["Custom"] }
    local presets = Kit.Segmented(body, presetOptions, INNER, function() return cam.preset end, function(v)
        if v ~= "custom" then
            Camera.UsePreset(v)
        end
        UI.Refresh()
    end)
    flow.Add(presets, 26, 24)

    flow.Heading(L["Fine tune"])
    local colW = (INNER - 28) / 2
    local sliders = {}
    for i, setting in ipairs(Camera.SETTINGS) do
        local slider = Kit.Slider(body, colW, setting.label, setting.min, setting.max, setting.step,
            function() return Camera.Get(setting.key) end,
            function(v) Camera.Set(setting.key, v) end,
            setting.format)
        if i % 2 == 1 then
            flow.Add(slider, 40, 16)
            sliders.left = slider
        else
            slider:SetPoint("LEFT", sliders.left, "RIGHT", 28, 0)
        end
        slider.cvar = setting.cvar
        sliders[#sliders + 1] = slider
    end
    flow.Space(6)

    flow.Heading(L["Follow style"], L["How the camera swings behind you while you move."])
    local style = Kit.Segmented(body, Camera.STYLES, 360, function() return Camera.Get("style") end, function(v)
        cam.style = v
        cam.preset = "custom"
        Camera.Update()
        UI.Refresh()
    end)
    flow.Add(style, 26, 18)

    local focus = Tile(body, "Overhead", L["Target focus"], L["The camera turns toward the enemy you target."],
        function() return cam.focus == true end, function(v)
            cam.focus = v
            cam.preset = "custom"
            Camera.Update()
        end)
    flow.Add(focus, TILE_H, 24)

    flow.Heading(L["Orbit"], L["A slow turn around your character for intros and outros. Stops when combat starts. Key binding: OnAir > Camera orbit."])
    local orbit = Kit.Button(body, L["Start orbit"], 150, 30, "ghost", function()
        Camera.ToggleOrbit()
    end)
    flow.Add(orbit, 40, 14)
    local orbitSpeed = Kit.Slider(body, INNER - 180, L["Orbit speed"], 0.01, 0.3, 0.01,
        function() return cam.orbitSpeed or 0.05 end,
        function(v) Camera.SetOrbitSpeed(v) end,
        function(v) return string.format("%d%%", v * 100) end)
    orbitSpeed:SetPoint("LEFT", orbit, "RIGHT", 30, 4)

    local reset = Kit.Button(body, L["Back to game defaults"], 200, 30, "ghost", function()
        Camera.UsePreset("default")
        UI.Refresh()
    end)
    flow.Add(reset, 30, 16)

    local note = Kit.Text(body, 12, C.faint)
    note:SetWidth(INNER)
    note:SetWordWrap(true)
    note:SetText(L["The game caps the field of view at 90 (its normal value), so it can only get narrower, for a film look. Shoulder offset, tilt and head movement are the game's action camera."])
    flow.Add(note, note:GetStringHeight(), 12)
    flow.Finish()

    OnRefresh(function()
        modes:Refresh(true)
        presets:Refresh(true)
        style:Refresh(true)
        for _, slider in ipairs(sliders) do
            slider:Refresh()
            slider:SetEnabledLook(Camera.Exists(slider.cvar))
        end
        orbitSpeed:Refresh()
        orbit.label:SetText(Camera.IsOrbiting() and L["Stop orbit"] or L["Start orbit"])
        local live = cam.mode ~= "off"
        presets:SetAlpha(live and 1 or 0.6)
    end)
end

---------------------------------------------------------------------------------------------- custom page

local function Mask(text)
    return text:sub(1, 1) .. string.rep("*", math.max(2, math.min(6, #text - 1)))
end

local function BuildCustom()
    local page = NewPage("custom")
    local flow = Flow(page)
    local body = page.body
    local db = OA.db
    local reveal = false

    flow.Heading(L["Add a fixed alias"])
    local realBox, aliasBox
    local pendingReal, pendingAlias = "", ""
    realBox = Kit.Input(body, 200, function() return pendingReal end, function(v) pendingReal = v end, true)
    flow.Add(realBox, 28, 14)
    local realHint = Kit.Text(body, 11, C.faint)
    realHint:SetPoint("BOTTOMLEFT", realBox, "TOPLEFT", 0, 4)
    realHint:SetText(L["Real name"])
    aliasBox = Kit.Input(body, 200, function() return pendingAlias end, function(v) pendingAlias = v end, true)
    aliasBox:SetPoint("LEFT", realBox, "RIGHT", 10, 0)
    local aliasHint = Kit.Text(body, 11, C.faint)
    aliasHint:SetPoint("BOTTOMLEFT", aliasBox, "TOPLEFT", 0, 4)
    aliasHint:SetText(L["Alias"])
    local add = Kit.Button(body, L["Add"], 90, 28, "primary", function()
        if pendingReal ~= "" and pendingAlias ~= "" then
            db.custom[pendingReal] = pendingAlias
            pendingReal, pendingAlias = "", ""
            realBox:SetText("")
            aliasBox:SetText("")
            realBox:ClearFocus()
            aliasBox:ClearFocus()
            OA.NamesChanged(false)
        end
    end)
    add:SetPoint("LEFT", aliasBox, "RIGHT", 10, 0)

    local revealRow = CreateFrame("Frame", nil, body)
    revealRow:SetSize(INNER, 22)
    flow.Add(revealRow, 22, 12)
    local revealSwitch = Kit.Switch(revealRow, function() return reveal end, function(v)
        reveal = v
        UI.Refresh()
    end)
    revealSwitch:SetPoint("LEFT")
    local revealText = Kit.Text(revealRow, 12, C.muted)
    revealText:SetPoint("LEFT", revealSwitch, "RIGHT", 10, 0)
    revealText:SetText(L["Reveal real names"])

    local list = CreateFrame("Frame", nil, body)
    list:SetSize(INNER, 10)
    flow.Add(list, 10, 0)
    local rows = {}
    local ROW_H = 32
    OnRefresh(function()
        local keys = {}
        for real in pairs(db.custom) do
            keys[#keys + 1] = real
        end
        table.sort(keys, function(a, b) return a:lower() < b:lower() end)
        for i, real in ipairs(keys) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, list)
                row:SetSize(INNER, ROW_H - 2)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
                local bg = Kit.Rect(row, C.card, "BACKGROUND")
                bg:SetAllPoints()
                row.real = Kit.Text(row, 13, C.muted)
                OA.Hide.Exempt(row.real)
                row.real:SetPoint("LEFT", 14, 0)
                row.real:SetWidth(180)
                local arrow = Kit.Icon(row, "Chevron", 12, C.faint)
                arrow:SetRotation(math.rad(90))
                arrow:SetPoint("LEFT", 200, 0)
                row.alias = Kit.Text(row, 14, C.text)
                row.alias:SetPoint("LEFT", arrow, "RIGHT", 14, 0)
                row.remove = Kit.IconButton(row, "Trash", 26, L["Remove"])
                row.remove:SetPoint("RIGHT", -6, 0)
                rows[i] = row
            end
            row.real:SetText(reveal and real or Mask(real))
            row.alias:SetText(db.custom[real])
            row.remove:SetScript("OnClick", function()
                db.custom[real] = nil
                OA.NamesChanged(false)
            end)
            row:Show()
        end
        for i = #keys + 1, #rows do
            rows[i]:Hide()
        end
        local h = math.max(10, #keys * ROW_H)
        list:SetHeight(h)
        page.scroll:SetContentHeight(PAD * 2 + 200 + h)
        revealSwitch:Refresh(true)
    end)
    flow.Finish()
end

---------------------------------------------------------------------------------------------- about page

local function BuildAbout()
    local page = NewPage("about")
    local flow = Flow(page)
    local body = page.body

    local logo = body:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(Utils.MEDIA .. "Logo")
    logo:SetSize(72, 72)
    flow.Add(logo, 72, 14)
    local name = Kit.Text(body, 26, C.text)
    name:SetPoint("LEFT", logo, "RIGHT", 18, 10)
    name:SetText("On|cffff3b30Air|r")
    local tag = Kit.Text(body, 13, C.muted)
    tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    tag:SetText(L["Streamer & recording mode for World of Warcraft."])

    local function Paragraph(title, text)
        flow.Heading(title)
        local fs = Kit.Text(body, 13, C.muted)
        fs:SetWidth(INNER)
        fs:SetWordWrap(true)
        fs:SetSpacing(3)
        fs:SetText(text)
        flow.Add(fs, fs:GetStringHeight(), 20)
    end

    Paragraph(L["Commands"], L["/onair  open this console\n/onair live  go live\n/onair off  end the broadcast\n/onair mark [note]  mark a moment\n/onair orbit  camera orbit on / off\n/onair camera  the camera page\n/onair preview  preview on / off\n/onair layout  edit the layout\n/onair reshuffle  everyone draws a new name\nKey bindings: Esc > Options > Keybindings > OnAir"])
    Paragraph(L["How it works"], L["OnAir learns every player your UI can show (group, targets, nameplates, chat, friends, guild, communities, group finder, mail) and swaps their names for aliases in all text, including other addons'. Names you see stay the same every session."])
    Paragraph(L["What the game doesn't allow"], L["In combat and in instances the game hides some names from addons. OnAir can't read those, so it hides that text instead (nameplates, meters, unit frames). Blizzard's friendly nameplates inside dungeons can't be touched by any addon: use overhead names off, or EllesmereUI's friendly plates. The combat log tab is not changed."])
    flow.Finish()
end

---------------------------------------------------------------------------------------------- window

---------------------------------------------------------------------------------------------- deck page

local function BuildDeck()
    local page = NewPage("deck")
    local flow = Flow(page)
    local body = page.body
    local Deck = OA.Deck
    local db = OA.db.deck

    flow.Heading(L["Show the Deck"])
    local show = Kit.Segmented(body, {
        { value = "always", text = L["Always"] },
        { value = "live", text = L["Only while live"] },
        { value = "never", text = L["Never"] },
    }, 360, function() return db.show end, function(v)
        db.show = v
        Deck.Refresh()
    end)
    flow.Add(show, 26, 22)

    flow.Heading(L["When you're not using it"], L["Tuck works when the Deck sits on an edge: it slides away and leaves a small tab with an arrow."])
    local hide = Kit.Segmented(body, {
        { value = "never", text = L["Stay"] },
        { value = "fade", text = L["Fade"] },
        { value = "tuck", text = L["Tuck into the edge"] },
    }, 360, function() return db.hide end, function(v)
        db.hide = v
        Deck.Refresh()
    end)
    flow.Add(hide, 26, 22)

    local colW = (INNER - 28) / 2
    local fade = Kit.Slider(body, colW, L["Faded to"], 0, 1, 0.05, function() return db.fadeTo end,
        function(v) db.fadeTo = v end,
        function(v) return v <= 0 and L["Invisible"] or string.format("%d%%", v * 100) end)
    flow.Add(fade, 40, 16)
    local delay = Kit.Slider(body, colW, L["After"], 1, 6, 0.5, function() return db.delay end,
        function(v) db.delay = v end,
        function(v) return string.format(L["%.1f s"], v) end)
    delay:SetPoint("LEFT", fade, "RIGHT", 28, 0)
    local size = Kit.Slider(body, colW, L["Size"], 0.7, 1.6, 0.05, function() return db.scale end,
        function(v)
            db.scale = v
            Deck.Refresh()
        end,
        function(v) return string.format("%d%%", v * 100) end)
    flow.Add(size, 40, 22)

    flow.Heading(L["Buttons"])
    local lastLeft
    for i, spec in ipairs(Deck.BUTTONS) do
        local tile = Tile(body, spec.icon, spec.text, spec.tip(),
            function() return db.buttons[spec.key] ~= false end,
            function(v)
                db.buttons[spec.key] = v and nil or false
                Deck.Refresh()
            end)
        if i % 2 == 1 then
            flow.Add(tile, 0, 0)
            lastLeft = tile
            if i == #Deck.BUTTONS then
                flow.Space(TILE_H + 12)
            end
        else
            tile:SetPoint("TOPLEFT", lastLeft, "TOPRIGHT", 12, 0)
            flow.Space(TILE_H + 12)
        end
    end
    flow.Space(10)

    local edit = Kit.Button(body, L["Edit layout"], 140, 30, "ghost", function()
        OA.Layout.Toggle()
    end)
    flow.Add(edit, 30, 12)
    local reset = Kit.Button(body, L["Back to the top"], 150, 30, "ghost", function()
        Deck.ResetPosition()
    end)
    reset:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    local note = Kit.Text(body, 12, C.faint)
    note:SetWidth(INNER)
    note:SetWordWrap(true)
    note:SetText(L["Key binding: OnAir > Hide / show the UI. The game doesn't let addons hide the UI in combat: Alt+Z still works there."])
    flow.Add(note, note:GetStringHeight(), 12)
    flow.Finish()

    OnRefresh(function()
        show:Refresh(true)
        hide:Refresh(true)
        fade:Refresh()
        delay:Refresh()
        size:Refresh()
    end)
end

local function Build()
    console = CreateFrame("Frame", "OnAirConsole", UIParent)
    console:SetSize(W, H)
    console:SetFrameStrata("HIGH")
    console:SetToplevel(true)
    console:SetClampedToScreen(true)
    console:SetMovable(true)
    console:EnableMouse(true)
    local pos = OA.db.window
    if pos and pos.point then
        console:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        console:SetPoint("CENTER")
    end
    local bg = Kit.Rect(console, C.bg, "BACKGROUND", -8)
    bg:SetAllPoints()
    Kit.Border(console, C.line)
    -- A thin red line on top: the studio's "recording" stripe.
    local stripe = Kit.Rect(console, C.red, "OVERLAY")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(2)
    tinsert(UISpecialFrames, "OnAirConsole")

    BuildHeader(console)
    BuildRail(console)
    BuildStatus(console)
    BuildBroadcast()
    BuildStream()
    BuildMoments()
    BuildNames()
    BuildHide()
    BuildCustom()
    BuildShield()
    BuildCamera()
    BuildDeck()
    BuildAbout()
    console:Hide()
end

-- Opens with a soft rise and a slight pop; closes with a quick fade.
function UI.ShowConsole()
    if not console then
        Build()
    end
    UI.ShowPage(current or "broadcast", false)
    UI.Refresh()
    console:Show()
    console:SetAlpha(0)
    Kit.Tween(console, 0, 1, 0.34, function(p)
        console:SetAlpha(math.min(1, p))
        console:SetScale(0.96 + 0.04 * p)
    end, "back")
    local page = pages[current]
    if page then
        page:SetAlpha(1)
    end
    PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN or 839)
end

function UI.HideConsole()
    if console and console:IsShown() then
        Kit.Tween(console, console:GetAlpha(), 0, 0.14, function(p)
            console:SetAlpha(p)
            console:SetScale(0.98 + 0.02 * p)
            if p <= 0 then
                console:Hide()
                console:SetScale(1)
            end
        end)
        PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE or 840)
    end
end

function UI.ToggleConsole()
    if console and console:IsShown() and console:GetAlpha() > 0.5 then
        UI.HideConsole()
    else
        UI.ShowConsole()
    end
end

function UI.OnLiveChanged()
    UI.Refresh()
end

function UI.Init()
    if UI.InitExtras then
        UI.InitExtras()
    end
end
