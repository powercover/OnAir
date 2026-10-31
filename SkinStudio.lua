local _, OA = ...

-- Studio: the plain dark broadcast console. Header with the tally light, a rail of pages on the
-- left, cards with switches, a status strip at the bottom; one red light.
--
-- A skin is a table in Kit.SKINS with:
--   Shell(face, api, onRefresh)   the console's chrome inside `face` (the window). Returns
--                                 { area = where pages go, areaWidth, width = content width,
--                                   pad = content's left edge, Select(key, animate) }.
--   Page(shell, body, item, api)  a page's header in `body`; returns where the content starts.
--   Heading, Toggle, Choice, Slider, Input, Fields, Button, Note: one control each, built
--                                 from a spec (see Console.lua); each returns a frame of its height
--                                 with Refresh() (and SetEnabledLook(on) where it applies).
--   Check(parent, spec, width)    a compact switch row (the Deck's quick panels).
--   Live, Table, ListRow, Label, Readout: the go-live block, a name list, list rows, text.
--   Deck(deck, specs)             the Deck's face: its buttons and background (see Deck.lua).
--   Sketch(box, Col)              a tiny picture of the skin for the Look page.
--   gap, colGap, headingGap, cols = { toggle = n, slider = n }: spacing and how many side by side.
-- Anything a skin leaves out comes from this one.
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local skin = { gap = 12, colGap = 12, headingGap = 10, cols = { toggle = 2, slider = 2 } }
Kit.SKINS.studio = skin

local HEADER, STATUS, RAIL = 56, 30, 196
local PAD = 28

function skin.Label(parent, size, color)
    return Kit.Text(parent, size, color)
end

function skin.Readout(parent, size)
    return Kit.Text(parent, size, C.text)
end

---------------------------------------------------------------------------------------------- chrome

local function Header(face, api, onRefresh)
    local header = CreateFrame("Frame", nil, face)
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
            tallyTime:SetText(api.Clock())
        end
    end)

    local close = Kit.IconButton(header, "Close", 30, nil, nil, api.Close)
    close:SetPoint("RIGHT", -12, 0)
    local layout = Kit.Button(header, L["Edit layout"], 104, 28, "ghost", function() OA.Layout.Toggle() end)
    layout:SetPoint("RIGHT", close, "LEFT", -8, 0)
    local preview = Kit.Button(header, L["Preview"], 96, 28, "ghost", function() OA.TogglePreview() end)
    preview:SetPoint("RIGHT", layout, "LEFT", -8, 0)
    Kit.Tooltip(preview, L["Preview"], L["Mask everything like live, to check your screen. No clock, no moments, no Shield."])

    onRefresh(function()
        local state = api.State()
        if state == "off" then
            dot:SetVertexColor(unpack(C.off))
            pulse:Stop()
            glow:Hide()
            tallyText:SetTextColor(unpack(C.muted))
            Kit.SetBorderColor(tallyEdges, C.line)
        else
            local color = state == "preview" and C.amber or C.red
            dot:SetVertexColor(unpack(color))
            glow:SetVertexColor(unpack(color))
            glow:Show()
            pulse:Play()
            tallyText:SetTextColor(unpack(state == "preview" and C.amber or C.text))
            Kit.SetBorderColor(tallyEdges, state == "live" and C.redDeep or C.line)
        end
        tallyText:SetText(Kit.Word(state))
        preview.label:SetText(state == "preview" and L["End preview"] or L["Preview"])
        preview:SetAlpha(state == "live" and 0.35 or 1)
        layout.label:SetText(OA.Layout.IsEditing() and L["Done"] or L["Edit layout"])
    end)
    api.Drag(header)
end

local NAV_H = 34
local SECTION_H = 30

local function Rail(face, api)
    local rail = CreateFrame("Frame", nil, face)
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
    local marker = Kit.Rect(rail, C.accent, "OVERLAY")
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
    local function Move(y, animate)
        if not animate then
            top, bottom = y, y + NAV_H
            Paint()
            return
        end
        local down = y > top
        Kit.Tween(edgeTop, top, y, down and 0.38 or 0.22, function(v) top = v; Paint() end, "quint")
        Kit.Tween(edgeBottom, bottom, y + NAV_H, down and 0.22 or 0.38, function(v) bottom = v; Paint() end, "quint")
    end

    local navs = {}
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
            if api.Current() ~= item.key then
                self.text:SetTextColor(unpack(C.text))
            end
        end)
        b:SetScript("OnLeave", function(self)
            if api.Current() ~= item.key then
                self.text:SetTextColor(unpack(C.muted))
            end
        end)
        b:SetScript("OnClick", function() api.Show(item.key) end)
        navs[item.key] = b
    end

    local y = 10
    for _, section in ipairs(api.sections) do
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
            local bottomY = api.H - HEADER - STATUS - 12 - #section.items * NAV_H
            for i, item in ipairs(section.items) do
                Item(item, bottomY + (i - 1) * NAV_H)
            end
        end
    end

    return function(key, animate)
        for k, b in pairs(navs) do
            local on = k == key
            b.text:SetTextColor(unpack(on and C.text or C.muted))
            b.icon:SetVertexColor(unpack(on and C.accent or C.muted))
            if on then
                Move(b.y, animate)
            end
        end
    end
end

local function Status(face, api, onRefresh)
    local strip = CreateFrame("Frame", nil, face)
    strip:SetPoint("BOTTOMLEFT")
    strip:SetPoint("BOTTOMRIGHT")
    strip:SetHeight(STATUS)
    local bg = Kit.Rect(strip, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    local line = Kit.Rect(strip, C.line, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    local x = 12
    local segments = {}
    for i, seg in ipairs(api.status) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(118, STATUS)
        b:SetPoint("LEFT", x, 0)
        local dot = Kit.Shape(b, "Dot", C.off, "ARTWORK")
        dot:SetSize(6, 6)
        dot:SetPoint("LEFT", 6, 0)
        local text = Kit.Text(b, 11, C.muted)
        text:SetPoint("LEFT", dot, "RIGHT", 7, 0)
        b:SetScript("OnClick", function() api.Show(seg.page) end)
        b:SetScript("OnEnter", function() text:SetTextColor(unpack(C.text)) end)
        b:SetScript("OnLeave", function() text:SetTextColor(unpack(C.muted)) end)
        segments[i] = { seg = seg, dot = dot, label = text }
        x = x + 122
    end
    local function Paint()
        for _, s in ipairs(segments) do
            local text, color = s.seg.text()
            s.label:SetText(text:upper())
            s.dot:SetVertexColor(unpack(color))
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
    onRefresh(Paint)
end

function skin.Shell(face, api, onRefresh)
    local bg = Kit.Rect(face, C.bg, "BACKGROUND", -8)
    bg:SetAllPoints()
    Kit.Border(face, C.line)
    -- A thin red line on top: the studio's "recording" stripe.
    local stripe = Kit.Rect(face, C.red, "OVERLAY")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(2)
    Header(face, api, onRefresh)
    local select = Rail(face, api)
    Status(face, api, onRefresh)
    local area = CreateFrame("Frame", nil, face)
    area:SetPoint("TOPLEFT", RAIL, -HEADER)
    area:SetPoint("BOTTOMRIGHT", 0, STATUS)
    return { area = area, areaWidth = api.W - RAIL, width = api.W - RAIL - PAD * 2 - 8, pad = PAD, Select = select }
end

-- The page's header: section, title, what it does, a big faint icon, a rule.
function skin.Page(shell, body, item)
    local watermark = Kit.Icon(body, item.icon, 128, C.accent)
    watermark:SetPoint("TOPRIGHT", -PAD + 8, -10)
    watermark:SetAlpha(0.06)
    local kicker = Kit.Text(body, 10, C.accent)
    kicker:SetPoint("TOPLEFT", PAD, -PAD + 4)
    kicker:SetText(item.section or "ONAIR")
    local title = Kit.Text(body, 26, C.text)
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
    title:SetText(item.text)
    local desc = Kit.Text(body, 13, C.muted)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(shell.width - 110)
    desc:SetWordWrap(true)
    desc:SetSpacing(2)
    desc:SetText(item.desc)
    local bottom = PAD + 4 + 10 + 6 + 30 + 8 + math.max(desc:GetStringHeight(), 16)
    local rule = Kit.Rect(body, C.line, "BORDER")
    rule:SetPoint("TOPLEFT", PAD, -bottom - 14)
    rule:SetSize(shell.width, 1)
    return bottom + 30
end

---------------------------------------------------------------------------------------------- controls

-- A frame holding wrapped text; returns it with its height set.
local function TextBlock(parent, text, width, size, color, gap)
    local holder = CreateFrame("Frame", nil, parent)
    local fs = Kit.Text(holder, size, color)
    fs:SetPoint("TOPLEFT")
    fs:SetWidth(width)
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    fs:SetText(text)
    holder:SetSize(width, math.max(1, fs:GetStringHeight()) + (gap or 0))
    holder.text = fs
    return holder
end
skin.TextBlock = TextBlock

-- A label (uppercase) with an optional hint under it, as one frame.
function skin.Heading(parent, text, hint, width)
    local holder = CreateFrame("Frame", nil, parent)
    local head = Kit.Heading(holder, text)
    head:SetPoint("TOPLEFT")
    local h = 12
    if hint then
        local fs = Kit.Text(holder, 12, C.faint)
        fs:SetPoint("TOPLEFT", 0, -16)
        fs:SetWidth(width)
        fs:SetWordWrap(true)
        fs:SetText(hint)
        h = 16 + fs:GetStringHeight()
    end
    holder:SetSize(width, h)
    return holder
end

-- A card: icon, title, a line of help and a switch. On: a lit edge on the left and a lit icon.
local TILE_H = 64

function skin.Toggle(parent, spec, width)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(width, TILE_H)
    local bg = Kit.Rect(tile, C.card, "BACKGROUND")
    bg:SetAllPoints()
    local edges = Kit.Border(tile)
    local sheen = Kit.Rect(tile, { 1, 1, 1, 0.035 }, "BORDER")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(1)
    local accent = Kit.Rect(tile, C.accent, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(2)
    local badge = Kit.Rect(tile, C.raised, "BORDER")
    badge:SetSize(36, 36)
    badge:SetPoint("LEFT", 14, 0)
    local glyph = Kit.Icon(tile, spec.icon or "Live", 20, C.muted)
    glyph:SetPoint("CENTER", badge)
    local name = Kit.Text(tile, 14, C.text)
    name:SetPoint("TOPLEFT", badge, "TOPRIGHT", 12, -1)
    name:SetPoint("RIGHT", tile, "RIGHT", -60, 0)
    name:SetText(spec.title)
    local sub = Kit.Text(tile, 11, C.muted)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", tile, "RIGHT", -60, 0)
    sub:SetWordWrap(true)
    sub:SetMaxLines(2)
    sub:SetText(spec.help or "")
    local switch = Kit.Switch(tile, spec.get, function(value)
        spec.set(value)
        OA.UI.Refresh()
    end)
    switch:SetPoint("RIGHT", -14, 0)
    local lit = spec.get() and 1 or 0
    local function Paint(animate)
        local on = spec.get() and 1 or 0
        glyph:SetVertexColor(unpack(on == 1 and C.accent or C.faint))
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
    function tile:Refresh(animate)
        switch:Refresh(animate)
        Paint(animate)
    end
    Paint(false)
    return tile
end

-- A label and a switch on one line (the Deck's quick panels).
function skin.Check(parent, spec, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 20)
    local text = Kit.Text(row, 12, C.text)
    text:SetPoint("LEFT")
    text:SetText(spec.title)
    local switch = Kit.Switch(row, spec.get, spec.set)
    switch:SetPoint("RIGHT")
    function row:Refresh(animate)
        switch:Refresh(animate)
    end
    return row
end

-- A heading (with its hint) over a row of choices.
local function Labeled(parent, spec, width, control, controlH)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 10
    end
    control:SetParent(holder)
    control:SetPoint("TOPLEFT", 0, -y)
    holder:SetSize(width, y + controlH)
    return holder
end

function skin.Choice(parent, spec, width)
    local w = spec.label and math.min(width, math.max(240, #spec.options * 120)) or width
    local seg = Kit.Segmented(parent, spec.options, w, spec.get, function(v)
        spec.set(v)
        OA.UI.Refresh()
    end)
    if not spec.label then
        return seg
    end
    local holder = Labeled(parent, spec, width, seg, 26)
    function holder:Refresh(animate)
        seg:Refresh(animate)
    end
    return holder
end

function skin.Slider(parent, spec, width)
    return Kit.Slider(parent, width, spec.label, spec.min, spec.max, spec.step, spec.get, spec.set, spec.format)
end

function skin.Input(parent, spec, width)
    local action = spec.action
    local box = Kit.Input(parent, action and width - 38 or width, spec.get, spec.set, spec.live)
    if spec.max then
        box:SetMaxLetters(spec.max)
    end
    local holder = spec.label and Labeled(parent, spec, width, box, 28) or CreateFrame("Frame", nil, parent)
    if not spec.label then
        holder:SetSize(width, 28)
        box:SetParent(holder)
        box:SetPoint("TOPLEFT")
    end
    if action then
        local b = Kit.IconButton(holder, action.icon, 30, action.title, action.help, action.click)
        b:SetPoint("LEFT", box, "RIGHT", 8, 0)
    end
    holder.box = box
    function holder:Refresh()
        box:Refresh()
    end
    function holder:SetEnabledLook(on)
        box:SetEnabledLook(on)
    end
    return holder
end

-- Short fields side by side, a small label over each.
function skin.Fields(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 10
    end
    local n = #spec.items
    local w = (width - (n - 1) * 8) / n
    holder.inputs = {}
    for i, item in ipairs(spec.items) do
        local label = Kit.Text(holder, 10, C.faint)
        label:SetPoint("TOPLEFT", (i - 1) * (w + 8), -y)
        label:SetText(item.label:upper())
        local box = Kit.Input(holder, w, item.get, item.set, item.live)
        box:SetPoint("TOPLEFT", (i - 1) * (w + 8), -y - 16)
        box.box = box
        holder.inputs[i] = box
    end
    holder:SetSize(width, y + 16 + 28)
    function holder:Refresh()
        for _, box in ipairs(self.inputs) do
            box:Refresh()
        end
    end
    return holder
end

function skin.Button(parent, spec)
    local b = Kit.Button(parent, spec.text, spec.width or 170, 30, spec.kind == "primary" and "primary" or "ghost", spec.click)
    if spec.tip then
        Kit.Tooltip(b, spec.text, spec.tip)
    end
    return b
end

function skin.Note(parent, text, width, big)
    return TextBlock(parent, text, width, big and 13 or 12, big and C.muted or C.faint)
end

function skin.ListRow(parent, width, height, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    local bg = Kit.Rect(row, index % 2 == 0 and C.bg or C.card, "BACKGROUND")
    bg:SetAllPoints()
    return row
end

---------------------------------------------------------------------------------------------- broadcast

-- The big button, with a glow that breathes while live, and the clock beside it.
function skin.Live(parent, width, api, onRefresh)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 76)
    local glow = Kit.Shape(holder, "Glow", C.red, "BACKGROUND")
    glow:SetSize(360, 150)
    glow:SetPoint("CENTER", holder, "LEFT", 140, 0)
    glow:SetBlendMode("ADD")
    local breathe = Kit.Pulse(glow, 0.15, 0.55, 1.4)
    local go = Kit.Button(holder, L["GO LIVE"], 280, 64, "primary", function() OA.Toggle() end)
    go:SetPoint("LEFT")
    go.label:SetFontObject(Kit.Font(22))
    local timer = Kit.Text(holder, 26, C.text)
    timer:SetPoint("LEFT", go, "RIGHT", 24, 8)
    local timerSub = Kit.Text(holder, 11, C.muted)
    timerSub:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -4)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            if OA.live then
                timer:SetText(api.FormatTime(OA.Moments.Elapsed()))
            end
        end
    end)
    onRefresh(function()
        if OA.live then
            go.label:SetText(L["END BROADCAST"])
            go:SetColors(C.redDeep, { 0.68, 0.12, 0.09, 1 })
            breathe:Play()
            glow:Show()
            timer:SetText(api.FormatTime(OA.Moments.Elapsed()))
            timer:SetTextColor(unpack(C.text))
            timerSub:SetText(string.format(L["%s  -  %d players masked"], Kit.Word(api.State()), OA.Names.Count()))
        else
            go.label:SetText(L["GO LIVE"])
            go:SetColors(C.red, { 1, 0.36, 0.31, 1 })
            breathe:Stop()
            glow:Hide()
            timer:SetText("00:00:00")
            timer:SetTextColor(unpack(C.faint))
            timerSub:SetText(string.format(L["%s  -  real names showing"], Kit.Word("off")))
        end
    end)
    return holder
end

-- Who -> what viewers see, one row each.
function skin.Table(parent, width, rows, onRefresh)
    local ROW_H = 34
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, #rows * ROW_H + 12)
    local cardBg = Kit.Rect(card, C.card, "BACKGROUND")
    cardBg:SetAllPoints()
    Kit.Border(card)
    for i, row in ipairs(rows) do
        local y = -6 - (i - 1) * ROW_H
        local icon = Kit.Icon(card, row.icon, 16, C.faint)
        icon:SetPoint("TOPLEFT", 16, y - 9)
        local who = Kit.Text(card, 13, C.muted)
        who:SetPoint("LEFT", icon, "RIGHT", 12, 0)
        who:SetText(row.text)
        local arrow = Kit.Icon(card, "Chevron", 12, C.faint)
        arrow:SetRotation(math.rad(90))
        arrow:SetPoint("LEFT", card, "TOPLEFT", 190, y - 17)
        local value = Kit.Text(card, 15, C.text)
        value:SetPoint("LEFT", arrow, "RIGHT", 16, 0)
        value:SetPoint("RIGHT", card, "RIGHT", -16, 0)
        if i < #rows then
            local sep = Kit.Rect(card, C.bg, "BORDER")
            sep:SetPoint("TOPLEFT", 12, y - ROW_H + 1)
            sep:SetPoint("TOPRIGHT", -12, y - ROW_H + 1)
            sep:SetHeight(1)
        end
        onRefresh(function() value:SetText(row.value()) end)
    end
    return card
end

---------------------------------------------------------------------------------------------- deck

-- The handle a tucked Deck leaves on screen: an arrow and, if wanted, the broadcast's state (a
-- dot and its word). The Deck lays it out.
function skin.DeckTab(frame)
    local tab = CreateFrame("Frame", nil, frame)
    local bg = Kit.Rect(tab, { C.bg[1], C.bg[2], C.bg[3], 0.94 }, "BACKGROUND")
    bg:SetAllPoints()
    tab.edges = Kit.Border(tab, C.line)
    tab.arrow = Kit.Icon(tab, "Chevron", 10, C.text)
    tab.dot = Kit.Shape(tab, "Dot", C.red, "OVERLAY")
    tab.dot:SetSize(6, 6)
    tab.word = Kit.Text(tab, 10, C.text)
    tab:SetAlpha(0)
    return tab
end

-- Icon buttons on a dark strip; on air the live button glows and the top line turns red.
function skin.Deck(deck, specs)
    local SIZE = 30
    local frame = CreateFrame("Frame", nil, deck)
    frame:SetAllPoints()
    local bg = Kit.Rect(frame, { C.bg[1], C.bg[2], C.bg[3], 0.94 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(frame, C.line)
    local stripe = Kit.Rect(frame, C.red, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(1)
    local face = { frame = frame, tab = skin.DeckTab(frame), buttons = {}, pad = 3, gap = 0, lead = 0 }
    for _, spec in ipairs(specs) do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(SIZE, SIZE)
        local hl = Kit.Rect(b, C.hover, "BACKGROUND", 1)
        hl:SetAllPoints()
        hl:SetAlpha(0)
        b.icon = Kit.Icon(b, spec.icon, 16, C.text)
        b.icon:SetPoint("CENTER")
        function b.SetHover(on)
            hl:SetAlpha(on and 1 or 0)
        end
        face.buttons[spec.key] = b
    end
    local glow = Kit.Shape(face.buttons.live, "Glow", C.red, "BORDER")
    glow:SetSize(SIZE + 10, SIZE + 10)
    glow:SetPoint("CENTER")
    glow:SetBlendMode("ADD")
    local pulse = Kit.Pulse(glow, 0.15, 0.7, 0.9)
    glow:Hide()
    function face.Size()
        return SIZE, SIZE
    end
    function face.Paint(state)
        for _, spec in ipairs(specs) do
            local b = face.buttons[spec.key]
            local on = state.on[spec.key]
            b.icon:SetVertexColor(unpack(on and (spec.key == "live" and C.red or C.accent) or C.text))
            b.icon:SetAlpha(state.editing and 0.45 or 1)
        end
        stripe:SetHeight(OA.live and 2 or 1)
        stripe:SetAlpha(OA.live and 1 or 0.5)
        if OA.live then
            glow:Show()
            pulse:Play()
        else
            pulse:Stop()
            glow:Hide()
        end
    end
    return face
end

---------------------------------------------------------------------------------------------- look page

function skin.Sketch(box, Col)
    local rail = Kit.Rect(box, Col("rail"), "BORDER")
    rail:SetPoint("TOPLEFT", 1, -10)
    rail:SetPoint("BOTTOMLEFT", 1, 1)
    rail:SetWidth(34)
    local top = Kit.Rect(box, Col("red"), "OVERLAY")
    top:SetPoint("TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", -1, -1)
    top:SetHeight(1)
    for i = 1, 4 do
        local row = Kit.Rect(box, i == 2 and Col("card") or Col("raised", 0.6), "ARTWORK")
        row:SetSize(i == 2 and 32 or 22, 6)
        row:SetPoint("TOPLEFT", i == 2 and 2 or 6, -14 - (i - 1) * 12)
    end
    local mark = Kit.Rect(box, Col("red"), "OVERLAY")
    mark:SetSize(2, 6)
    mark:SetPoint("TOPLEFT", 2, -26)
    for i = 1, 4 do
        local tile = Kit.Rect(box, Col("card"), "ARTWORK")
        tile:SetSize(36, 20)
        tile:SetPoint("TOPLEFT", 40 + ((i - 1) % 2) * 40, -16 - math.floor((i - 1) / 2) * 26)
        local lit = Kit.Rect(box, Col("red"), "OVERLAY")
        lit:SetSize(2, 20)
        lit:SetPoint("TOPLEFT", tile, "TOPLEFT")
    end
end
