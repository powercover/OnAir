local _, OA = ...

-- Viewfinder: the console is a camera screen. A REC readout and the shot info run along the top,
-- corner brackets and faint thirds lines frame it, the pages are a camera menu with colored tabs
-- (the picked one lit amber), and every setting is a menu row: a label, dotted leaders and its
-- value (ON / OFF, < CHOICE >, a tick scale with a marker). The line at the bottom says what the
-- row under the mouse does. Text is OnAir Mono, a pixel font, like a camera's screen.
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils
local base = Kit.SKINS.studio

local skin = setmetatable({ gap = 2, colGap = 10, headingGap = 4, cols = { toggle = 1, slider = 1 } }, { __index = base })
Kit.SKINS.viewfinder = skin

local TOP, BOTTOM, RAIL = 44, 30, 180
local PAD = 22
local ROW_H = 30

-- The menu's tab colors, one per group (LIVE, PRIVACY, PRODUCTION, the rest).
local TABS = { { 1, 0.231, 0.188, 1 }, { 1, 0.69, 0.125, 1 }, { 0.31, 0.765, 0.969, 1 }, { 0.482, 0.847, 0.561, 1 } }

local function Mono(parent, size, color, layer)
    return Kit.Text(parent, size, color or C.text, layer, true)
end

-- A mono string's width: the font knows; before it's drawn, count (6 pixels of 10 per letter).
local function Width(fs, size)
    local w = fs:GetStringWidth()
    local text = fs:GetText() or ""
    return math.max(w or 0, #text * size * 0.6)
end

local function Dots(parent, color, layer)
    local t = Kit.Band(parent, "Dots", color or C.line, layer or "BORDER")
    t:SetHeight(1)
    return t
end

-- The line at the bottom: what the row under the mouse does (set by the shell).
local hint
local function Hint(text)
    if hint then
        hint(text)
    end
end

function skin.Label(parent, size, color)
    return Kit.Text(parent, size, color)
end

function skin.Readout(parent, size)
    return Mono(parent, size, C.text)
end

---------------------------------------------------------------------------------------------- small parts

-- A word you click: mono text, amber on hover, brackets when it's a real button.
local function TextButton(parent, text, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    local label = Mono(b, size, C.muted)
    label:SetPoint("CENTER")
    label:SetText(text)
    b:SetSize(Width(label, size) + 16, size + 12)
    b.label = label
    b:SetScript("OnEnter", function() label:SetTextColor(unpack(C.accent)) end)
    b:SetScript("OnLeave", function() label:SetTextColor(unpack(C.muted)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A menu row: a dotted rule under it, a cursor bar and a lighter band under the mouse.
local function Row(parent, width, height, help)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local band = Kit.Rect(row, C.hover, "BACKGROUND")
    band:SetAllPoints()
    band:SetAlpha(0)
    local cursor = Kit.Rect(row, C.accent, "ARTWORK")
    cursor:SetPoint("TOPLEFT", 0, -4)
    cursor:SetPoint("BOTTOMLEFT", 0, 4)
    cursor:SetWidth(2)
    cursor:SetAlpha(0)
    local rule = Dots(row)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    local key = {}
    row:SetScript("OnEnter", function()
        Kit.Tween(key, band:GetAlpha(), 1, 0.12, function(a) band:SetAlpha(a); cursor:SetAlpha(a) end)
        Hint(help)
    end)
    row:SetScript("OnLeave", function()
        Kit.Tween(key, band:GetAlpha(), 0, 0.2, function(a) band:SetAlpha(a); cursor:SetAlpha(a) end)
        Hint(nil)
    end)
    function row:SetEnabledLook(on)
        self:SetEnabled(on)
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    return row
end

-- A text field drawn as a value: amber text on a dotted line (solid while typing).
local function Edit(parent, width, get, set, live)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetFontObject(Kit.Font(14))
    box:SetTextColor(unpack(C.accent))
    box:SetTextInsets(4, 4, 0, 0)
    box:SetMaxLetters(48)
    local line = Dots(box, C.accent)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetAlpha(0.6)
    local solid = Kit.Rect(box, C.accent, "ARTWORK")
    solid:SetPoint("BOTTOMLEFT")
    solid:SetPoint("BOTTOMRIGHT")
    solid:SetHeight(1)
    solid:SetAlpha(0)
    box:SetText(get() or "")
    box:SetCursorPosition(0)
    local function Commit(self)
        set(Utils.Trim(self:GetText() or ""))
    end
    box:SetScript("OnEnterPressed", function(self)
        Commit(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(get() or "")
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function()
        Kit.Tween(solid, solid:GetAlpha(), 1, 0.15, function(a) solid:SetAlpha(a) end)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        Kit.Tween(solid, solid:GetAlpha(), 0, 0.2, function(a) solid:SetAlpha(a) end)
        Commit(self)
    end)
    if live then
        box:SetScript("OnTextChanged", function(self, user)
            if user then
                Commit(self)
            end
        end)
    end
    function box:Refresh()
        if not self:HasFocus() then
            self:SetText(get() or "")
            self:SetCursorPosition(0)
        end
    end
    function box:SetEnabledLook(on)
        self:SetEnabled(on)
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    return box
end

---------------------------------------------------------------------------------------------- chrome

local function TopBar(face, api, onRefresh, corners)
    local bar = CreateFrame("Frame", nil, face)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TOP)
    local rule = Dots(bar)
    rule:SetPoint("BOTTOMLEFT", 14, 0)
    rule:SetPoint("BOTTOMRIGHT", -14, 0)
    api.Drag(bar)

    -- The REC readout: click it to go live or end.
    local rec = CreateFrame("Button", nil, bar)
    rec:SetSize(230, 26)
    rec:SetPoint("LEFT", 28, 0)
    local dot = Kit.Shape(rec, "Dot", C.red, "ARTWORK")
    dot:SetSize(10, 10)
    dot:SetPoint("LEFT")
    local blink = Kit.Pulse(dot, 0.25, 1, 0.6)
    local word = Mono(rec, 15, C.red)
    word:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    local clock = Mono(rec, 15, C.text)
    clock:SetPoint("LEFT", word, "RIGHT", 12, 0)
    rec:SetScript("OnClick", function() OA.Toggle() end)
    Kit.Tooltip(rec, L["Go live / end"], L["Click to go live or end the broadcast."])

    local close = TextButton(bar, "\195\151", 15, api.Close)
    close:SetPoint("RIGHT", -24, 0)
    local layout = TextButton(bar, L["LAYOUT"], 12, function() OA.Layout.Toggle() end)
    layout:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local preview = TextButton(bar, L["PREVIEW"], 12, function() OA.TogglePreview() end)
    preview:SetPoint("RIGHT", layout, "LEFT", -4, 0)
    Kit.Tooltip(preview, L["Preview"], L["Mask everything like live, to check your screen. No clock, no moments, no Shield."])

    -- The shot info: what's masked, the Shield, the camera, like a camera's settings line.
    local info = Mono(bar, 11, C.muted)
    info:SetPoint("LEFT", rec, "RIGHT", 10, 0)
    info:SetPoint("RIGHT", preview, "LEFT", -16, 0)
    info:SetJustifyH("CENTER")

    local acc = 0
    local function Tick()
        clock:SetText(api.Clock())
        local parts = {}
        for _, i in ipairs({ 2, 5, 6 }) do
            if api.status[i] then
                parts[#parts + 1] = (api.status[i].text())
            end
        end
        info:SetText(table.concat(parts, "  \194\183  "):upper())
    end
    bar:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.5 then
            acc = 0
            Tick()
        end
    end)
    onRefresh(function()
        local state = api.State()
        local color = state == "live" and C.red or (state == "preview" and C.amber or C.tally)
        word:SetText(Kit.Word(state))
        word:SetTextColor(unpack(color))
        dot:SetTexture(Utils.MEDIA .. (state == "off" and "Ring" or "Dot"))
        dot:SetVertexColor(unpack(color))
        if state == "off" then
            blink:Stop()
        else
            blink:Play()
        end
        -- The brackets turn red while recording.
        local bracket = state == "live" and C.red or (state == "preview" and C.amber or C.text)
        for _, b in ipairs(corners) do
            b.h:SetColorTexture(unpack(bracket))
            b.v:SetColorTexture(unpack(bracket))
        end
        preview.label:SetText(state == "preview" and L["END PREVIEW"] or L["PREVIEW"])
        preview:SetAlpha(state == "live" and 0.35 or 1)
        layout.label:SetText(OA.Layout.IsEditing() and L["DONE"] or L["LAYOUT"])
        Tick()
    end)
end

local NAV_H = 28
local SECTION_H = 26

local function Menu(face, api)
    local rail = CreateFrame("Frame", nil, face)
    rail:SetPoint("TOPLEFT", 0, -TOP)
    rail:SetPoint("BOTTOMLEFT", 0, BOTTOM)
    rail:SetWidth(RAIL)
    local edge = Dots(rail, C.line)
    edge:SetHeight(0)
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT", 0, -10)
    edge:SetPoint("BOTTOMRIGHT", 0, 10)

    -- The lit row: the camera menu's cursor, gliding to the picked page.
    local lit = Kit.Rect(rail, C.accent, "BORDER")
    lit:SetSize(RAIL - 30, NAV_H - 4)
    local y0 = 0
    local key = {}
    local function Place(y)
        y0 = y
        lit:SetPoint("TOPLEFT", 16, -y - 2)
    end

    local navs = {}
    local function Item(item, y, color)
        local b = CreateFrame("Button", nil, rail)
        b:SetSize(RAIL - 30, NAV_H)
        b:SetPoint("TOPLEFT", 16, -y)
        local tab = Kit.Rect(b, color, "ARTWORK")
        tab:SetSize(3, 12)
        tab:SetPoint("LEFT", 8, 0)
        local text = Mono(b, 12, C.muted)
        text:SetPoint("LEFT", 20, 0)
        text:SetText(item.text:upper())
        b.tab, b.text, b.y, b.color = tab, text, y, color
        b:SetScript("OnEnter", function(self)
            if api.Current() ~= item.key then
                self.text:SetTextColor(unpack(C.text))
            end
            Hint(item.desc)
        end)
        b:SetScript("OnLeave", function(self)
            if api.Current() ~= item.key then
                self.text:SetTextColor(unpack(C.muted))
            end
            Hint(nil)
        end)
        b:SetScript("OnClick", function() api.Show(item.key) end)
        navs[item.key] = b
    end

    local y = 14
    for index, section in ipairs(api.sections) do
        local color = TABS[index] or TABS[#TABS]
        if section.title then
            local label = Mono(rail, 10, C.faint)
            label:SetPoint("TOPLEFT", 24, -y - 10)
            label:SetText(section.title)
            y = y + SECTION_H
            for _, item in ipairs(section.items) do
                Item(item, y, color)
                y = y + NAV_H
            end
            y = y + 6
        else
            local bottomY = api.H - TOP - BOTTOM - 14 - #section.items * NAV_H
            for i, item in ipairs(section.items) do
                Item(item, bottomY + (i - 1) * NAV_H, color)
            end
        end
    end

    return function(pageKey, animate)
        for k, b in pairs(navs) do
            local on = k == pageKey
            b.text:SetTextColor(unpack(on and C.accentInk or C.muted))
            b.tab:SetColorTexture(unpack(on and C.accentInk or b.color))
            if on then
                if animate then
                    Kit.Tween(key, y0, b.y, 0.3, Place, "quint")
                else
                    Place(b.y)
                end
            end
        end
    end
end

-- The bottom line: the systems' status, or what the row under the mouse does.
local function InfoLine(face, api, onRefresh)
    local line = CreateFrame("Frame", nil, face)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(BOTTOM)
    local rule = Dots(line)
    rule:SetPoint("TOPLEFT", 14, 0)
    rule:SetPoint("TOPRIGHT", -14, 0)
    local status = CreateFrame("Frame", nil, line)
    status:SetAllPoints()
    local segments = {}
    local x = 30
    for i, seg in ipairs(api.status) do
        local b = CreateFrame("Button", nil, status)
        b:SetHeight(BOTTOM)
        b:SetPoint("LEFT", x, 0)
        local dot = Kit.Shape(b, "Dot", C.off, "ARTWORK")
        dot:SetSize(5, 5)
        dot:SetPoint("LEFT")
        local text = Mono(b, 10, C.muted)
        text:SetPoint("LEFT", dot, "RIGHT", 6, 0)
        b:SetWidth(128)
        b:SetScript("OnClick", function() api.Show(seg.page) end)
        b:SetScript("OnEnter", function() text:SetTextColor(unpack(C.text)) end)
        b:SetScript("OnLeave", function() text:SetTextColor(unpack(C.muted)) end)
        segments[i] = { seg = seg, dot = dot, label = text }
        x = x + 136
    end
    local help = Kit.Text(line, 12, C.text)
    help:SetPoint("LEFT", 30, 0)
    help:SetPoint("RIGHT", -30, 0)
    help:Hide()
    hint = function(text)
        help:SetText(text or "")
        help:SetShown(text ~= nil and text ~= "")
        status:SetShown(not help:IsShown())
    end
    local function Paint()
        for _, s in ipairs(segments) do
            local text, color = s.seg.text()
            s.label:SetText(text:upper())
            s.dot:SetVertexColor(unpack(color))
        end
    end
    local acc = 0
    line:SetScript("OnUpdate", function(_, elapsed)
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
    -- The rule of thirds, faintly, like a camera's grid.
    for i = 1, 2 do
        local v = Kit.Rect(face, { 1, 1, 1, 0.03 }, "BACKGROUND", -7)
        v:SetWidth(1)
        v:SetPoint("TOP", face, "TOPLEFT", api.W * i / 3, -TOP)
        v:SetPoint("BOTTOM", face, "BOTTOMLEFT", api.W * i / 3, BOTTOM)
        local h = Kit.Rect(face, { 1, 1, 1, 0.03 }, "BACKGROUND", -7)
        h:SetHeight(1)
        local y = BOTTOM + (api.H - TOP - BOTTOM) * i / 3
        h:SetPoint("LEFT", face, "BOTTOMLEFT", 0, y)
        h:SetPoint("RIGHT", face, "BOTTOMRIGHT", 0, y)
    end
    local over = CreateFrame("Frame", nil, face)
    over:SetAllPoints()
    over:SetFrameLevel(face:GetFrameLevel() + 50)
    local corners = Kit.Corners(over, 18, 2, C.text, 8)
    TopBar(face, api, onRefresh, corners)
    local select = Menu(face, api)
    InfoLine(face, api, onRefresh)
    local area = CreateFrame("Frame", nil, face)
    area:SetPoint("TOPLEFT", RAIL, -TOP)
    area:SetPoint("BOTTOMRIGHT", 0, BOTTOM)
    return { area = area, areaWidth = api.W - RAIL, width = api.W - RAIL - PAD * 2 - 8, pad = PAD, Select = select }
end

-- The page's header: its tab color, the title, its number in the menu, what it does.
function skin.Page(shell, body, item, api)
    local index, total, color = 0, 0, TABS[1]
    for s, section in ipairs(api.sections) do
        for _, it in ipairs(section.items) do
            total = total + 1
            if it == item then
                index, color = total, TABS[s] or TABS[#TABS]
            end
        end
    end
    local tab = Kit.Rect(body, color, "ARTWORK")
    tab:SetSize(3, 16)
    tab:SetPoint("TOPLEFT", PAD, -PAD)
    local title = Mono(body, 18, C.text)
    title:SetPoint("LEFT", tab, "RIGHT", 10, 0)
    title:SetText(item.text:upper())
    local number = Mono(body, 11, C.faint)
    number:SetPoint("TOPRIGHT", body, "TOPLEFT", PAD + shell.width, -PAD - 3)
    number:SetText(string.format("%02d/%02d", index, total))
    local desc = Kit.Text(body, 12, C.muted)
    desc:SetPoint("TOPLEFT", PAD, -PAD - 28)
    desc:SetWidth(shell.width)
    desc:SetWordWrap(true)
    desc:SetSpacing(2)
    desc:SetText(item.desc)
    local bottom = PAD + 28 + math.max(desc:GetStringHeight(), 14)
    local rule = Dots(body, C.faint)
    rule:SetPoint("TOPLEFT", PAD, -bottom - 12)
    rule:SetWidth(shell.width)
    return bottom + 22
end

---------------------------------------------------------------------------------------------- controls

-- A group's name in amber with a dotted rule after it; a hint below.
function skin.Heading(parent, text, hint, width)
    local holder = CreateFrame("Frame", nil, parent)
    local head = Mono(holder, 11, C.accent)
    head:SetPoint("TOPLEFT", 0, -10)
    head:SetText(text:upper())
    local rule = Dots(holder, C.faint)
    rule:SetPoint("LEFT", head, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
    local h = 26
    if hint then
        local fs = Kit.Text(holder, 12, C.faint)
        fs:SetPoint("TOPLEFT", 0, -28)
        fs:SetWidth(width)
        fs:SetWordWrap(true)
        fs:SetText(hint)
        h = 32 + fs:GetStringHeight()
    end
    holder:SetSize(width, h)
    return holder
end

-- ON / OFF on the right, a small square lit or empty.
local function OnOff(fs, on)
    fs:SetText(on and ("\226\150\160 " .. L["ON"]) or ("\226\150\161 " .. L["OFF"]))
    fs:SetTextColor(unpack(on and C.accent or C.faint))
end

function skin.Toggle(parent, spec, width)
    local row = Row(parent, width, ROW_H, spec.help)
    local icon = Kit.Icon(row, spec.icon or "Live", 14, C.faint)
    icon:SetPoint("LEFT", 10, 0)
    local label = Mono(row, 12, C.text)
    label:SetPoint("LEFT", 32, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -90, 0)
    label:SetText(spec.title)
    local value = Mono(row, 12, C.accent)
    value:SetPoint("RIGHT", -8, 0)
    value:SetJustifyH("RIGHT")
    local was
    row:SetScript("OnClick", function()
        spec.set(not spec.get())
        OA.UI.Refresh()
        PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end)
    function row:Refresh(animate)
        local on = spec.get() and true or false
        OnOff(value, on)
        icon:SetVertexColor(unpack(on and C.accent or C.faint))
        label:SetTextColor(unpack(on and C.text or C.muted))
        if animate and was ~= nil and was ~= on then
            Kit.Tween(value, 0.2, 1, 0.25, function(a) value:SetAlpha(a) end)
        end
        was = on
    end
    row:Refresh(false)
    return row
end

function skin.Check(parent, spec, width)
    local row = Row(parent, width, 22)
    local label = Mono(row, 11, C.text)
    label:SetPoint("LEFT", 6, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -64, 0)
    label:SetText(spec.title)
    local value = Mono(row, 11, C.accent)
    value:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function()
        spec.set(not spec.get())
        row:Refresh(true)
    end)
    function row:Refresh()
        OnOff(value, spec.get() and true or false)
    end
    row:Refresh()
    return row
end

-- < VALUE >: a click steps to the next choice, a right click back.
function skin.Choice(parent, spec, width)
    local options = spec.options
    local row = Row(parent, width, spec.label and ROW_H or 24, spec.hint)
    local label
    if spec.label then
        label = Mono(row, 12, C.text)
        label:SetPoint("LEFT", 10, 0)
        label:SetText(spec.label)
    end
    local right = Mono(row, 12, C.accent)
    right:SetText("\226\150\184")
    right:SetPoint("RIGHT", -6, 0)
    local value = Mono(row, 12, C.accent)
    value:SetPoint("RIGHT", right, "LEFT", -8, 0)
    local left = Mono(row, 12, C.accent)
    left:SetText("\226\151\130")
    left:SetPoint("RIGHT", value, "LEFT", -8, 0)
    local count = Mono(row, 9, C.faint)
    count:SetPoint("RIGHT", left, "LEFT", -10, 0)
    local function Index()
        local current = spec.get()
        for i, option in ipairs(options) do
            if option.value == current then
                return i
            end
        end
        return 1
    end
    row:SetScript("OnClick", function(_, button)
        local i = Index()
        local step = button == "RightButton" and -1 or 1
        local nextOption = options[(i - 1 + step) % #options + 1]
        spec.set(nextOption.value)
        OA.UI.Refresh()
        row:Refresh(true)
        PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end)
    local shown
    function row:Refresh(animate)
        local i = Index()
        value:SetText(tostring(options[i].text):upper())
        count:SetText(string.format("%d/%d", i, #options))
        if animate and shown and shown ~= i then
            Kit.Tween(value, 0, 1, 0.2, function(p)
                value:SetAlpha(p)
                value:SetPoint("RIGHT", right, "LEFT", -8 - 6 * (1 - p), 0)
            end)
        end
        shown = i
    end
    row:Refresh(false)
    return row
end

-- A tick scale with a marker under it; the ticks up to the value light up. Drag along it, click
-- it, or rest the mouse on it and use the arrow keys (Shift: five steps).
function skin.Slider(parent, spec, width)
    local min, max, step = spec.min, spec.max, spec.step
    local narrow = width < 320
    local row = Row(parent, width, narrow and 46 or 36)
    local label = Mono(row, 12, C.text)
    label:SetText(spec.label)
    local value = Mono(row, 12, C.accent)
    value:SetJustifyH("RIGHT")
    local scale = CreateFrame("Button", nil, row)
    if narrow then
        label:SetPoint("TOPLEFT", 6, -6)
        value:SetPoint("TOPRIGHT", -6, -6)
        scale:SetPoint("BOTTOMLEFT", 8, 4)
        scale:SetPoint("BOTTOMRIGHT", -8, 4)
    else
        label:SetPoint("LEFT", 10, 0)
        value:SetPoint("RIGHT", -8, 0)
        scale:SetPoint("TOPLEFT", row, "TOPLEFT", math.floor(width * 0.36), -4)
        scale:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -190, 4)
    end
    scale:SetHeight(24)
    local scaleW = narrow and (width - 16) or (width - math.floor(width * 0.36) - 190)
    local TICKS = 20
    local ticks = {}
    for i = 0, TICKS do
        local t = Kit.Rect(scale, C.faint, "ARTWORK")
        t:SetSize(1, i % 5 == 0 and 9 or 5)
        t:SetPoint("BOTTOM", scale, "BOTTOMLEFT", scaleW * i / TICKS, 10)
        ticks[i] = t
    end
    local marker = Mono(scale, 10, C.accent)
    marker:SetText("\226\150\178")
    local enabled = true
    local function Snap(v)
        v = math.max(min, math.min(max, v))
        return math.floor((v - min) / step + 0.5) * step + min
    end
    local function Paint(v)
        local p = (v - min) / (max - min)
        local w = scale:GetWidth()
        if not w or w <= 0 then
            w = scaleW
        end
        marker:ClearAllPoints()
        marker:SetPoint("TOP", scale, "BOTTOMLEFT", p * w, 10)
        for i = 0, TICKS do
            ticks[i]:SetColorTexture(unpack(i / TICKS <= p + 0.0001 and C.accent or C.faint))
        end
        value:SetText(spec.format and spec.format(v) or tostring(v))
    end
    local function Apply(v)
        v = Snap(v)
        spec.set(v)
        Paint(v)
    end
    local function FromCursor()
        local left, w = scale:GetLeft(), scale:GetWidth()
        if not left or not w or w <= 0 then
            return
        end
        local x = GetCursorPosition() / scale:GetEffectiveScale()
        Apply(min + (max - min) * ((x - left) / w))
    end
    scale:SetScript("OnMouseDown", function(self)
        if enabled then
            FromCursor()
            self:SetScript("OnUpdate", FromCursor)
        end
    end)
    scale:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    local function Keys(on)
        if InCombatLockdown() then
            on = false
        end
        scale:EnableKeyboard(on)
        if on and scale.SetPropagateKeyboardInput then
            scale:SetPropagateKeyboardInput(true)
        end
    end
    scale:SetScript("OnEnter", function()
        row:GetScript("OnEnter")(row)
        Keys(enabled)
    end)
    scale:SetScript("OnLeave", function()
        row:GetScript("OnLeave")(row)
        Keys(false)
    end)
    -- Hidden under the mouse (console closed, skin switched, panel gone): let go of the keyboard.
    scale:SetScript("OnHide", function() Keys(false) end)
    scale:SetScript("OnKeyDown", function(self, key)
        local delta = (key == "RIGHT" or key == "UP") and 1 or ((key == "LEFT" or key == "DOWN") and -1 or 0)
        local canStop = not InCombatLockdown() and self.SetPropagateKeyboardInput
        if delta == 0 or not enabled then
            if canStop then
                self:SetPropagateKeyboardInput(true)
            end
            return
        end
        if canStop then
            self:SetPropagateKeyboardInput(false)
        end
        Apply((spec.get() or min) + delta * step * (IsShiftKeyDown() and 5 or 1))
        -- Only this key press is kept from the game: the next ones go through again.
        if canStop then
            C_Timer.After(0, function()
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(true)
                end
            end)
        end
    end)
    scale:SetScript("OnSizeChanged", function()
        Paint(Snap(spec.get() or min))
    end)
    function row:Refresh()
        Paint(Snap(spec.get() or min))
    end
    function row:SetEnabledLook(on)
        enabled = on
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    row:Refresh()
    return row
end

-- A label, then the text itself in amber on a dotted line.
function skin.Input(parent, spec, width)
    local row = Row(parent, width, ROW_H, spec.hint)
    local x = 6
    if spec.label then
        local label = Mono(row, 12, C.text)
        label:SetPoint("LEFT", 10, 0)
        label:SetText(spec.label)
        x = math.floor(width * 0.4)
    else
        local prompt = Mono(row, 12, C.faint)
        prompt:SetPoint("LEFT", 8, 0)
        prompt:SetText("\226\150\184")
        x = 24
    end
    local action = spec.action
    local box = Edit(row, width - x - (action and 40 or 8), spec.get, spec.set, spec.live)
    box:SetPoint("LEFT", x, 0)
    if spec.max then
        box:SetMaxLetters(spec.max)
    end
    if action then
        local b = Kit.IconButton(row, action.icon, 26, action.title, action.help, action.click)
        b:SetPoint("RIGHT", -4, 0)
    end
    row:SetScript("OnClick", function() box:SetFocus() end)
    row.box = box
    function row:Refresh()
        box:Refresh()
    end
    function row:SetEnabledLook(on)
        box:SetEnabledLook(on)
        self:SetEnabled(on)
    end
    return row
end

-- Short fields: one menu row each.
function skin.Fields(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 4
    end
    holder.inputs = {}
    for i, item in ipairs(spec.items) do
        local row = skin.Input(holder, { label = item.label, get = item.get, set = item.set, live = item.live }, width)
        row:SetPoint("TOPLEFT", 0, -y)
        y = y + ROW_H + 2
        holder.inputs[i] = row
    end
    holder:SetSize(width, y)
    function holder:Refresh()
        for _, row in ipairs(self.inputs) do
            row:Refresh()
        end
    end
    return holder
end

-- [ TEXT ]: brackets around a word; the main ones filled amber.
function skin.Button(parent, spec)
    local b = CreateFrame("Button", nil, parent)
    local primary = spec.kind == "primary"
    local label = Mono(b, 12, primary and C.accentInk or C.text)
    label:SetPoint("CENTER")
    label:SetText(spec.text:upper())
    b:SetSize(spec.width or math.max(120, Width(label, 12) + 36), 28)
    local fill = Kit.Rect(b, primary and C.accent or C.hover, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetAlpha(primary and 1 or 0)
    local corners = Kit.Corners(b, 6, 1, primary and C.accent or C.muted, 0)
    local key = {}
    b:SetScript("OnEnter", function()
        if primary then
            Kit.Tween(key, 0, 1, 0.12, function(p) fill:SetColorTexture(Kit.Mix(C.accent, C.text, p * 0.35)) end)
        else
            Kit.Tween(key, fill:GetAlpha(), 1, 0.12, function(a) fill:SetAlpha(a) end)
            corners.Place(-2)
        end
    end)
    b:SetScript("OnLeave", function()
        if primary then
            Kit.Tween(key, 1, 0, 0.2, function(p) fill:SetColorTexture(Kit.Mix(C.accent, C.text, p * 0.35)) end)
        else
            Kit.Tween(key, fill:GetAlpha(), 0, 0.2, function(a) fill:SetAlpha(a) end)
            corners.Place(0)
        end
    end)
    if spec.click then
        b:SetScript("OnClick", spec.click)
    end
    if spec.tip then
        Kit.Tooltip(b, spec.text, spec.tip)
    end
    b.label = label
    function b:SetLabel(text)
        label:SetText(text:upper())
    end
    return b
end

function skin.ListRow(parent, width, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    local rule = Dots(row)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    return row
end

---------------------------------------------------------------------------------------------- broadcast

-- The monitor: framed by brackets, the big REC readout, and the record button.
function skin.Live(parent, width, api, onRefresh)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 112)
    local bg = Kit.Rect(holder, { 0, 0, 0, 0.25 }, "BACKGROUND")
    bg:SetAllPoints()
    local corners = Kit.Corners(holder, 14, 2, C.text, 0)
    local dot = Kit.Shape(holder, "Dot", C.red, "ARTWORK")
    dot:SetSize(16, 16)
    dot:SetPoint("TOPLEFT", 22, -26)
    local blink = Kit.Pulse(dot, 0.2, 1, 0.6)
    local word = Mono(holder, 28, C.red)
    word:SetPoint("LEFT", dot, "RIGHT", 12, 0)
    local clock = Mono(holder, 28, C.text)
    clock:SetPoint("LEFT", word, "RIGHT", 18, 0)
    local sub = Mono(holder, 11, C.muted)
    sub:SetPoint("TOPLEFT", 24, -66)
    local go = skin.Button(holder, { text = L["Start rec"], kind = "primary", width = 190, click = function() OA.Toggle() end })
    go:SetPoint("TOPRIGHT", -20, -20)
    local preview = skin.Button(holder, { text = L["Preview"], width = 190, click = function() OA.TogglePreview() end })
    preview:SetPoint("TOPRIGHT", go, "BOTTOMRIGHT", 0, -8)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            clock:SetText(OA.live and api.FormatTime(OA.Moments.Elapsed()) or "00:00:00")
        end
    end)
    onRefresh(function()
        local state = api.State()
        local color = state == "live" and C.red or (state == "preview" and C.amber or C.tally)
        word:SetText(Kit.Word(state))
        word:SetTextColor(unpack(color))
        dot:SetTexture(Utils.MEDIA .. (state == "off" and "Ring" or "Dot"))
        dot:SetVertexColor(unpack(color))
        if state == "off" then
            blink:Stop()
        else
            blink:Play()
        end
        clock:SetText(OA.live and api.FormatTime(OA.Moments.Elapsed()) or "00:00:00")
        clock:SetTextColor(unpack(OA.live and C.text or C.faint))
        for _, b in ipairs(corners) do
            b.h:SetColorTexture(unpack(state == "off" and C.text or color))
            b.v:SetColorTexture(unpack(state == "off" and C.text or color))
        end
        sub:SetText((OA.live and string.format(L["%d masked"], OA.Names.Count()) or L["Real names showing"]):upper())
        go:SetLabel(OA.live and L["Stop"] or L["Start rec"])
        preview:SetLabel(state == "preview" and L["End preview"] or L["Preview"])
        preview:SetAlpha(state == "live" and 0.35 or 1)
    end)
    return holder
end

-- Who ........ what viewers see.
function skin.Table(parent, width, rows, onRefresh)
    local H = 30
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, #rows * H)
    for i, row in ipairs(rows) do
        local r = skin.ListRow(holder, width, H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * H)
        local icon = Kit.Icon(r, row.icon, 14, C.faint)
        icon:SetPoint("LEFT", 8, 0)
        local who = Mono(r, 12, C.muted)
        who:SetPoint("LEFT", 32, 0)
        who:SetText(row.text)
        local arrow = Mono(r, 12, C.accent)
        arrow:SetPoint("RIGHT", -6, 0)
        arrow:SetText("\226\150\184")
        local value = Kit.Text(r, 14, C.accent)
        value:SetPoint("RIGHT", arrow, "LEFT", -8, 0)
        value:SetJustifyH("RIGHT")
        local leader = Dots(r, C.faint, "ARTWORK")
        leader:SetPoint("LEFT", who, "RIGHT", 8, -3)
        leader:SetPoint("RIGHT", value, "LEFT", -8, -3)
        onRefresh(function() value:SetText(row.value()) end)
    end
    return holder
end

---------------------------------------------------------------------------------------------- deck

local DECK_WORDS = { live = "REC", ui = "UI", camera = "CAM", orbit = "ORBIT", mark = "MARK", layout = "GRID", console = "MENU" }

-- Words, not icons: REC  UI  CAM  ORBIT  MARK  GRID  MENU, inside viewfinder brackets.
function skin.Deck(deck, specs)
    local SIZE = 12
    local frame = CreateFrame("Frame", nil, deck)
    frame:SetAllPoints()
    local bg = Kit.Rect(frame, { C.bg[1], C.bg[2], C.bg[3], 0.94 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(frame, C.line)
    local over = CreateFrame("Frame", nil, frame)
    over:SetAllPoints()
    over:SetFrameLevel(frame:GetFrameLevel() + 20)
    local corners = Kit.Corners(over, 7, 2, C.text, -1)
    local face = { frame = frame, tab = base.DeckTab(frame), buttons = {}, pad = 3, gap = 0, lead = 0 }
    for _, spec in ipairs(specs) do
        local b = CreateFrame("Button", nil, frame)
        local hl = Kit.Rect(b, C.hover, "BACKGROUND", 1)
        hl:SetAllPoints()
        hl:SetAlpha(0)
        local label = Mono(b, SIZE, C.text)
        label:SetText(L[DECK_WORDS[spec.key] or spec.key:upper()])
        if spec.key == "live" then
            b.dot = Kit.Shape(b, "Dot", C.red, "ARTWORK")
            b.dot:SetSize(7, 7)
            b.dot:SetPoint("LEFT", 8, 0)
            b.blink = Kit.Pulse(b.dot, 0.2, 1, 0.6)
            label:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
            b.w = Width(label, SIZE) + 30
        else
            label:SetPoint("CENTER")
            b.w = Width(label, SIZE) + 18
        end
        b.label = label
        function b.SetHover(on)
            hl:SetAlpha(on and 1 or 0)
        end
        face.buttons[spec.key] = b
    end
    function face.Size(b, vertical)
        if vertical then
            local w = 0
            for _, other in pairs(face.buttons) do
                w = math.max(w, other.w)
            end
            return w, 24
        end
        return b.w, 26
    end
    function face.Paint(state)
        for _, spec in ipairs(specs) do
            local b = face.buttons[spec.key]
            local on = state.on[spec.key]
            local color = on and (spec.key == "live" and C.red or C.accent) or C.text
            b.label:SetTextColor(unpack(color))
            b:SetAlpha(state.editing and 0.45 or 1)
        end
        local live = face.buttons.live
        if live then
            local color = OA.live and (OA.rehearsal and C.amber or C.red) or C.faint
            live.dot:SetTexture(Utils.MEDIA .. (OA.live and "Dot" or "Ring"))
            live.dot:SetVertexColor(unpack(color))
            live.label:SetText((OA.live and OA.rehearsal) and Kit.Word("preview") or L["REC"])
            live.label:SetTextColor(unpack(OA.live and color or C.text))
            if OA.live then
                live.blink:Play()
            else
                live.blink:Stop()
            end
        end
        local bracket = OA.live and (OA.rehearsal and C.amber or C.red) or C.text
        for _, b in ipairs(corners) do
            b.h:SetColorTexture(unpack(bracket))
            b.v:SetColorTexture(unpack(bracket))
        end
    end
    return face
end

function skin.PanelDecor(panel)
    local over = CreateFrame("Frame", nil, panel)
    over:SetAllPoints()
    over:SetFrameLevel(panel:GetFrameLevel() + 10)
    Kit.Corners(over, 8, 2, C.accent, -1)
end

---------------------------------------------------------------------------------------------- look page

function skin.Sketch(box, Col)
    Kit.Corners(box, 7, 1, Col("text"), 3)
    local dot = Kit.Shape(box, "Dot", Col("red"), "OVERLAY")
    dot:SetSize(4, 4)
    dot:SetPoint("TOPLEFT", 8, -7)
    local osd = Kit.Rect(box, Col("muted", 0.7), "ARTWORK")
    osd:SetSize(30, 2)
    osd:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    local colors = { Col("red"), Col("accent"), Col("tally"), Col("green") }
    for i = 1, 4 do
        local lit = i == 2
        local row = Kit.Rect(box, lit and Col("accent") or Col("raised", 0.5), "ARTWORK")
        row:SetSize(30, 6)
        row:SetPoint("TOPLEFT", 8, -16 - (i - 1) * 11)
        local tab = Kit.Rect(box, lit and Col("bg") or colors[i], "OVERLAY")
        tab:SetSize(1, 4)
        tab:SetPoint("LEFT", row, "LEFT", 2, 0)
    end
    for i = 1, 3 do
        local line = Kit.Rect(box, Col("line"), "ARTWORK")
        line:SetSize(66, 1)
        line:SetPoint("TOPLEFT", 46, -24 - (i - 1) * 12)
        local value = Kit.Rect(box, Col("accent"), "ARTWORK")
        value:SetSize(14, 3)
        value:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 0, 2)
    end
    for i = 0, 10 do
        local tick = Kit.Rect(box, i <= 6 and Col("accent") or Col("faint"), "ARTWORK")
        tick:SetSize(1, i % 5 == 0 and 5 or 3)
        tick:SetPoint("BOTTOMLEFT", 46 + i * 6, 10)
    end
end
