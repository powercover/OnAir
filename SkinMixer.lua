local _, OA = ...

-- Vision mixer: the console is a broadcast desk. PROGRAM and PREVIEW keys and a timecode display
-- on top, the pages as a bus of source keys (the picked one lit green, like a preview bus),
-- settings as lit tiles with a tally strip, sliders as vertical faders with a cap, text as
-- small displays. The Deck is a row of labeled keys.
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils
local base = Kit.SKINS.studio

local skin = setmetatable({ gap = 12, colGap = 10, headingGap = 10, cols = { toggle = 4, slider = 5 } }, { __index = base })
Kit.SKINS.mixer = skin

local TOP, BUS, BOTTOM = 58, 52, 30
local PAD = 20
local DISPLAY = { 0.055, 0.059, 0.071, 1 } -- the desk's little black displays

local function Mono(parent, size, color)
    return Kit.Text(parent, size, color or C.text, nil, true)
end

function skin.Readout(parent, size)
    return Mono(parent, size, C.text)
end

-- A key: a raised square button with a label; lit in a color, or dark.
local function Key(parent, text, width, height, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local face = Kit.Rect(b, C.card, "BACKGROUND")
    face:SetAllPoints()
    local top = Kit.Rect(b, { 1, 1, 1, 0.06 }, "BORDER")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    local shade = Kit.Rect(b, { 0, 0, 0, 0.35 }, "BORDER")
    shade:SetPoint("BOTTOMLEFT")
    shade:SetPoint("BOTTOMRIGHT")
    shade:SetHeight(2)
    local label = Kit.Text(b, size or 11, C.text)
    label:SetPoint("CENTER")
    label:SetText(text)
    b.face, b.label = face, label
    local lit, hover = nil, false
    function b:Light(color, ink)
        lit = color
        face:SetColorTexture(unpack(color or (hover and C.hover or C.card)))
        label:SetTextColor(unpack(ink or (color and DISPLAY) or C.text))
    end
    b:SetScript("OnEnter", function()
        hover = true
        if not lit then
            face:SetColorTexture(unpack(C.hover))
        end
    end)
    b:SetScript("OnLeave", function()
        hover = false
        if not lit then
            face:SetColorTexture(unpack(C.card))
        end
    end)
    b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)
    function b:SetLabel(t)
        label:SetText(t)
    end
    return b
end

-- A small black display with mono text.
local function Display(parent, width, height, size, color)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(width, height)
    local bg = Kit.Rect(d, DISPLAY, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(d, { 0, 0, 0, 1 })
    d.text = Mono(d, size, color or C.red)
    d.text:SetPoint("CENTER")
    return d
end

---------------------------------------------------------------------------------------------- chrome

local function Header(face, api, onRefresh)
    local bar = CreateFrame("Frame", nil, face)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(TOP)
    local bg = Kit.Rect(bar, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    api.Drag(bar)

    local program = Key(bar, L["PROGRAM"], 110, 32, 12)
    program:SetPoint("LEFT", PAD, 0)
    program:SetScript("OnClick", function() OA.Toggle() end)
    Kit.Tooltip(program, L["Go live / end"], L["Click to go live or end the broadcast."])
    local preview = Key(bar, L["PREVIEW"], 110, 32, 12)
    preview:SetPoint("LEFT", program, "RIGHT", 8, 0)
    preview:SetScript("OnClick", function() OA.TogglePreview() end)
    Kit.Tooltip(preview, L["Preview"], L["Mask everything like live, to check your screen. No clock, no moments, no Shield."])

    local logo = Kit.Text(bar, 16, C.muted)
    logo:SetPoint("LEFT", preview, "RIGHT", 22, 0)
    logo:SetText("On|cffff3b30Air|r")

    local close = Key(bar, "\195\151", 32, 32, 16)
    close:SetPoint("RIGHT", -PAD, 0)
    close:SetScript("OnClick", api.Close)
    local layout = Key(bar, L["LAYOUT"], 86, 32, 11)
    layout:SetPoint("RIGHT", close, "LEFT", -8, 0)
    layout:SetScript("OnClick", function() OA.Layout.Toggle() end)

    local clock = Display(bar, 150, 32, 18, C.red)
    clock:SetPoint("RIGHT", layout, "LEFT", -18, 0)
    local acc = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            clock.text:SetText(api.Clock())
        end
    end)

    onRefresh(function()
        local state = api.State()
        program:Light(state == "live" and C.red or nil, state == "live" and { 0.16, 0.03, 0.02, 1 } or nil)
        preview:Light(state == "preview" and C.tally or nil)
        program:SetLabel(state == "live" and L["ON AIR"] or L["PROGRAM"])
        preview:SetAlpha(state == "live" and 0.4 or 1)
        clock.text:SetTextColor(unpack(state == "live" and C.red or C.faint))
        clock.text:SetText(api.Clock())
        layout:SetLabel(OA.Layout.IsEditing() and L["DONE"] or L["LAYOUT"])
    end)
end

-- The bus: one key per page, grouped, the group's name over it. The picked one is lit green.
local function Bus(face, api)
    local bus = CreateFrame("Frame", nil, face)
    bus:SetPoint("TOPLEFT", 0, -TOP)
    bus:SetPoint("TOPRIGHT", 0, -TOP)
    bus:SetHeight(BUS)
    local line = Kit.Rect(bus, C.line, "BORDER")
    line:SetPoint("BOTTOMLEFT", PAD, 0)
    line:SetPoint("BOTTOMRIGHT", -PAD, 0)
    line:SetHeight(1)
    local count, groups = 0, 0
    for _, section in ipairs(api.sections) do
        count = count + #section.items
        groups = groups + 1
    end
    local GAP, GROUP_GAP = 4, 12
    local keyW = (api.W - PAD * 2 - (count - groups) * GAP - (groups - 1) * GROUP_GAP) / count
    local keys = {}
    local x = PAD
    for _, section in ipairs(api.sections) do
        if section.title then
            local label = Kit.Text(bus, 9, C.faint)
            label:SetPoint("TOPLEFT", x, -4)
            label:SetText(section.title)
        end
        for i, item in ipairs(section.items) do
            local key = Key(bus, item.text:upper(), keyW, 26, 10)
            key:SetPoint("TOPLEFT", x, -17)
            key:SetScript("OnClick", function() api.Show(item.key) end)
            keys[item.key] = key
            x = x + keyW + (i < #section.items and GAP or 0)
        end
        x = x + GROUP_GAP
    end
    return function(pageKey)
        for k, key in pairs(keys) do
            key:Light(k == pageKey and C.tally or nil)
        end
    end
end

-- The strip at the bottom: one LED per system.
local function Meters(face, api, onRefresh)
    local strip = CreateFrame("Frame", nil, face)
    strip:SetPoint("BOTTOMLEFT")
    strip:SetPoint("BOTTOMRIGHT")
    strip:SetHeight(BOTTOM)
    local bg = Kit.Rect(strip, C.rail, "BACKGROUND")
    bg:SetAllPoints()
    local segments = {}
    local x = PAD
    for i, seg in ipairs(api.status) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(132, BOTTOM)
        b:SetPoint("LEFT", x, 0)
        local led = Kit.Rect(b, C.off, "ARTWORK")
        led:SetSize(8, 8)
        led:SetPoint("LEFT")
        local text = Mono(b, 10, C.muted)
        text:SetPoint("LEFT", led, "RIGHT", 7, 0)
        b:SetScript("OnClick", function() api.Show(seg.page) end)
        segments[i] = { seg = seg, led = led, label = text }
        x = x + 138
    end
    local function Paint()
        for _, s in ipairs(segments) do
            local text, color = s.seg.text()
            s.label:SetText(text:upper())
            s.led:SetColorTexture(unpack(color))
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
    Header(face, api, onRefresh)
    local select = Bus(face, api)
    Meters(face, api, onRefresh)
    local area = CreateFrame("Frame", nil, face)
    area:SetPoint("TOPLEFT", 0, -TOP - BUS)
    area:SetPoint("BOTTOMRIGHT", 0, BOTTOM)
    return { area = area, areaWidth = api.W, width = api.W - PAD * 2 - 8, pad = PAD, Select = select }
end

function skin.Page(shell, body, item)
    local title = Kit.Text(body, 20, C.text)
    title:SetPoint("TOPLEFT", PAD, -16)
    title:SetText(item.text)
    local desc = Kit.Text(body, 12, C.muted)
    desc:SetPoint("TOPLEFT", PAD, -44)
    desc:SetWidth(shell.width)
    desc:SetWordWrap(true)
    desc:SetText(item.desc)
    return 44 + math.max(desc:GetStringHeight(), 14) + 18
end

---------------------------------------------------------------------------------------------- controls

function skin.Heading(parent, text, hint, width)
    local holder = CreateFrame("Frame", nil, parent)
    local head = Kit.Text(holder, 11, C.muted)
    head:SetPoint("TOPLEFT", 0, -4)
    head:SetText(text:upper())
    local line = Kit.Rect(holder, C.line, "BORDER")
    line:SetPoint("LEFT", head, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", holder, "RIGHT")
    line:SetHeight(1)
    local h = 18
    if hint then
        local fs = Kit.Text(holder, 12, C.faint)
        fs:SetPoint("TOPLEFT", 0, -22)
        fs:SetWidth(width)
        fs:SetWordWrap(true)
        fs:SetText(hint)
        h = 24 + fs:GetStringHeight()
    end
    holder:SetSize(width, h)
    return holder
end

-- A tile: a tally strip on top (green when on), the name and what it does.
function skin.Toggle(parent, spec, width)
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(width, 72)
    local bg = Kit.Rect(tile, C.card, "BACKGROUND")
    bg:SetAllPoints()
    local tally = Kit.Rect(tile, C.off, "ARTWORK")
    tally:SetPoint("TOPLEFT")
    tally:SetPoint("TOPRIGHT")
    tally:SetHeight(3)
    local name = Kit.Text(tile, 13, C.text)
    name:SetPoint("TOPLEFT", 10, -12)
    name:SetPoint("RIGHT", tile, "RIGHT", -26, 0)
    name:SetText(spec.title)
    local led = Kit.Shape(tile, "Dot", C.off, "ARTWORK")
    led:SetSize(7, 7)
    led:SetPoint("TOPRIGHT", -10, -14)
    local help = Kit.Text(tile, 10, C.muted)
    help:SetPoint("TOPLEFT", 10, -32)
    help:SetWidth(width - 20)
    help:SetWordWrap(true)
    help:SetMaxLines(3)
    help:SetText(spec.help or "")
    tile:SetScript("OnEnter", function() bg:SetColorTexture(unpack(C.raised)) end)
    tile:SetScript("OnLeave", function() bg:SetColorTexture(unpack(C.card)) end)
    tile:SetScript("OnClick", function()
        spec.set(not spec.get())
        OA.UI.Refresh()
        PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end)
    local lit
    function tile:Refresh(animate)
        local on = spec.get() and 1 or 0
        local function Paint(p)
            tally:SetColorTexture(Kit.Mix(C.off, C.tally, p))
            led:SetVertexColor(Kit.Mix(C.off, C.tally, p))
        end
        if animate and lit and lit ~= on then
            Kit.Tween(tally, lit, on, 0.25, Paint)
        else
            Paint(on)
        end
        name:SetTextColor(unpack(on == 1 and C.text or C.muted))
        lit = on
    end
    tile:Refresh(false)
    return tile
end

function skin.Check(parent, spec, width)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 24)
    local text = Kit.Text(row, 12, C.text)
    text:SetPoint("LEFT")
    text:SetPoint("RIGHT", row, "RIGHT", -56, 0)
    text:SetText(spec.title)
    local key = Key(row, "", 48, 22, 10)
    key:SetPoint("RIGHT")
    key:SetScript("OnClick", function()
        spec.set(not spec.get())
        row:Refresh()
    end)
    function row:Refresh()
        local on = spec.get() and true or false
        key:SetLabel(on and L["ON"] or L["OFF"])
        key:Light(on and C.tally or nil)
    end
    row:Refresh()
    return row
end

-- A row of keys, the picked one lit.
function skin.Choice(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 8
    end
    local n = #spec.options
    local w = math.min(140, (width - (n - 1) * 4) / n)
    if not spec.label then
        w = (width - (n - 1) * 4) / n
    end
    local keys = {}
    for i, option in ipairs(spec.options) do
        local key = Key(holder, option.text, w, 28, 11)
        key:SetPoint("TOPLEFT", (i - 1) * (w + 4), -y)
        key:SetScript("OnClick", function()
            spec.set(option.value)
            OA.UI.Refresh()
            holder:Refresh()
        end)
        keys[i] = key
    end
    holder:SetSize(width, y + 28)
    function holder:Refresh()
        local current = spec.get()
        for i, option in ipairs(spec.options) do
            keys[i]:Light(option.value == current and C.tally or nil)
        end
    end
    holder:Refresh()
    return holder
end

-- A fader: a slot, a cap you drag up and down, the value in a little display over it. Narrow
-- places (the Deck's panels) get a horizontal one.
function skin.Slider(parent, spec, width)
    local min, max, step = spec.min, spec.max, spec.step
    local vertical = width <= 200
    local s = CreateFrame("Frame", nil, parent)
    local value = Display(s, vertical and width - 8 or 110, 20, 10, C.tally)
    local label = Kit.Text(s, 11, C.muted)
    label:SetText(spec.label)
    local slot = CreateFrame("Button", nil, s)
    local SLOT = 96
    if vertical then
        s:SetSize(width, 170)
        value:SetPoint("TOP", 0, 0)
        slot:SetSize(28, SLOT + 12)
        slot:SetPoint("TOP", value, "BOTTOM", 0, -8)
        label:SetPoint("TOP", slot, "BOTTOM", 0, -6)
        label:SetWidth(width - 6)
        label:SetJustifyH("CENTER")
        label:SetWordWrap(true)
        label:SetMaxLines(2)
    else
        s:SetSize(width, 46)
        label:SetPoint("TOPLEFT")
        value:SetPoint("TOPRIGHT")
        slot:SetPoint("BOTTOMLEFT", 0, 0)
        slot:SetPoint("BOTTOMRIGHT", 0, 0)
        slot:SetHeight(18)
    end
    local track = Kit.Rect(slot, DISPLAY, "BACKGROUND")
    if vertical then
        track:SetSize(6, SLOT)
        track:SetPoint("CENTER")
        for i = 0, 10 do
            local tick = Kit.Rect(slot, C.faint, "BORDER")
            tick:SetSize(i % 5 == 0 and 8 or 4, 1)
            tick:SetPoint("RIGHT", slot, "CENTER", -8, -SLOT / 2 + SLOT * i / 10)
        end
    else
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(4)
    end
    local cap = Kit.Rect(slot, C.knob, "ARTWORK")
    cap:SetSize(vertical and 28 or 12, vertical and 12 or 18)
    local mark = Kit.Rect(slot, DISPLAY, "OVERLAY")
    if vertical then
        mark:SetSize(20, 1)
    else
        mark:SetSize(1, 12)
    end
    mark:SetPoint("CENTER", cap)
    local enabled = true
    local function Snap(v)
        v = math.max(min, math.min(max, v))
        return math.floor((v - min) / step + 0.5) * step + min
    end
    local function Paint(v)
        local p = (v - min) / (max - min)
        cap:ClearAllPoints()
        if vertical then
            cap:SetPoint("CENTER", slot, "CENTER", 0, -SLOT / 2 + SLOT * p)
        else
            local w = slot:GetWidth()
            if not w or w <= 0 then
                w = width
            end
            cap:SetPoint("CENTER", slot, "LEFT", 6 + (w - 12) * p, 0)
        end
        value.text:SetText(spec.format and spec.format(v) or tostring(v))
    end
    local function Apply(v)
        v = Snap(v)
        spec.set(v)
        Paint(v)
    end
    local function FromCursor()
        local scale = slot:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        if vertical then
            local bottom = slot:GetBottom()
            if not bottom then
                return
            end
            local y = cy / scale - bottom - (slot:GetHeight() - SLOT) / 2
            Apply(min + (max - min) * (y / SLOT))
        else
            local left, w = slot:GetLeft(), slot:GetWidth()
            if not left or not w or w <= 12 then
                return
            end
            Apply(min + (max - min) * ((cx / scale - left - 6) / (w - 12)))
        end
    end
    slot:SetScript("OnMouseDown", function(self)
        if enabled then
            FromCursor()
            self:SetScript("OnUpdate", FromCursor)
        end
    end)
    slot:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    local function Keys(on)
        if InCombatLockdown() then
            on = false
        end
        slot:EnableKeyboard(on)
        if on and slot.SetPropagateKeyboardInput then
            slot:SetPropagateKeyboardInput(true)
        end
    end
    slot:SetScript("OnEnter", function()
        cap:SetColorTexture(unpack(C.text))
        Keys(enabled)
    end)
    slot:SetScript("OnLeave", function()
        cap:SetColorTexture(unpack(C.knob))
        Keys(false)
    end)
    slot:SetScript("OnKeyDown", function(self, key)
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
    end)
    function s:Refresh()
        Paint(Snap(spec.get() or min))
    end
    function s:SetEnabledLook(on)
        enabled = on
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    s:Refresh()
    return s
end

-- A text field: a little display, the text in green.
local function Field(parent, width, get, set, live)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 28)
    box:SetAutoFocus(false)
    box:SetFontObject(Kit.Font(14))
    box:SetTextColor(unpack(C.tally))
    box:SetTextInsets(9, 9, 0, 0)
    box:SetMaxLetters(48)
    local bg = Kit.Rect(box, DISPLAY, "BACKGROUND")
    bg:SetAllPoints()
    local edges = Kit.Border(box, { 0, 0, 0, 1 })
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
    box:SetScript("OnEditFocusGained", function() Kit.SetBorderColor(edges, C.tally) end)
    box:SetScript("OnEditFocusLost", function(self)
        Kit.SetBorderColor(edges, { 0, 0, 0, 1 })
        Commit(self)
    end)
    if live then
        box:SetScript("OnTextChanged", function(self, user)
            if user then
                Commit(self)
            end
        end)
    end
    box.box = box
    function box:Refresh()
        if not self:HasFocus() then
            self:SetText(get() or "")
            self:SetCursorPosition(0)
        end
    end
    function box:SetEnabledLook(on)
        self:SetEnabled(on)
        self.oaAlpha = on and 1 or 0.4
        self:SetAlpha(self.oaAlpha)
    end
    return box
end

function skin.Input(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 8
    end
    local action = spec.action
    local box = Field(holder, action and width - 40 or width, spec.get, spec.set, spec.live)
    box:SetPoint("TOPLEFT", 0, -y)
    if spec.max then
        box:SetMaxLetters(spec.max)
    end
    if action then
        local b = Key(holder, "", 32, 28)
        b:SetPoint("LEFT", box, "RIGHT", 8, 0)
        local icon = Kit.Icon(b, action.icon, 16, C.text)
        icon:SetPoint("CENTER")
        b:SetScript("OnClick", action.click)
        Kit.Tooltip(b, action.title, action.help)
    end
    holder:SetSize(width, y + 28)
    holder.box = box
    function holder:Refresh()
        box:Refresh()
    end
    function holder:SetEnabledLook(on)
        box:SetEnabledLook(on)
    end
    return holder
end

function skin.Fields(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 8
    end
    local n = #spec.items
    local w = (width - (n - 1) * 10) / n
    holder.inputs = {}
    for i, item in ipairs(spec.items) do
        local label = Kit.Text(holder, 10, C.faint)
        label:SetPoint("TOPLEFT", (i - 1) * (w + 10), -y)
        label:SetText(item.label:upper())
        local box = Field(holder, w, item.get, item.set, item.live)
        box:SetPoint("TOPLEFT", (i - 1) * (w + 10), -y - 15)
        holder.inputs[i] = box
    end
    holder:SetSize(width, y + 15 + 28)
    function holder:Refresh()
        for _, box in ipairs(self.inputs) do
            box:Refresh()
        end
    end
    return holder
end

function skin.Button(parent, spec)
    local b = Key(parent, spec.text, spec.width or 150, 30, 12)
    if spec.kind == "primary" then
        b:Light(C.red, { 1, 1, 1, 1 })
    end
    if spec.click then
        b:SetScript("OnClick", spec.click)
    end
    if spec.tip then
        Kit.Tooltip(b, spec.text, spec.tip)
    end
    return b
end

function skin.ListRow(parent, width, height, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    local bg = Kit.Rect(row, index % 2 == 0 and DISPLAY or C.card, "BACKGROUND")
    bg:SetAllPoints()
    return row
end

---------------------------------------------------------------------------------------------- broadcast

-- Program and Preview as big keys, the timecode in a big display, a level meter of masked names.
function skin.Live(parent, width, api, onRefresh)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 96)
    local program = Key(holder, L["GO LIVE"], 200, 60, 18)
    program:SetPoint("TOPLEFT")
    program:SetScript("OnClick", function() OA.Toggle() end)
    local preview = Key(holder, L["PREVIEW"], 130, 60, 14)
    preview:SetPoint("LEFT", program, "RIGHT", 10, 0)
    preview:SetScript("OnClick", function() OA.TogglePreview() end)
    local clock = Display(holder, 220, 60, 30, C.red)
    clock:SetPoint("LEFT", preview, "RIGHT", 18, 0)
    local sub = Kit.Text(holder, 11, C.muted)
    sub:SetPoint("TOPLEFT", program, "BOTTOMLEFT", 0, -10)
    -- Masked names as a meter: one bar per few names.
    local bars = {}
    for i = 1, 10 do
        local bar = Kit.Rect(holder, C.off, "ARTWORK")
        bar:SetSize(8, 8 + i * 4)
        bar:SetPoint("BOTTOMLEFT", clock, "BOTTOMRIGHT", 18 + (i - 1) * 11, 0)
        bars[i] = bar
    end
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            clock.text:SetText(OA.live and api.FormatTime(OA.Moments.Elapsed()) or "00:00:00")
        end
    end)
    onRefresh(function()
        local state = api.State()
        program:Light(OA.live and not OA.rehearsal and C.red or C.raised, OA.live and not OA.rehearsal and { 1, 1, 1, 1 } or C.text)
        program:SetLabel(OA.live and not OA.rehearsal and L["END"] or L["GO LIVE"])
        preview:Light(state == "preview" and C.tally or nil)
        preview:SetAlpha(state == "live" and 0.4 or 1)
        clock.text:SetText(OA.live and api.FormatTime(OA.Moments.Elapsed()) or "00:00:00")
        clock.text:SetTextColor(unpack(OA.live and C.red or C.faint))
        local count = OA.live and OA.Names.Count() or 0
        for i, bar in ipairs(bars) do
            local on = count >= i * 3 or (i == 1 and count > 0)
            local color = i > 8 and C.red or (i > 6 and C.amber or C.tally)
            bar:SetColorTexture(unpack(on and color or C.off))
        end
        sub:SetText(OA.live and string.format(L["%s  -  %d players masked"], Kit.Word(state), OA.Names.Count())
            or string.format(L["%s  -  real names showing"], Kit.Word("off")))
    end)
    return holder
end

-- A black display listing who -> what viewers see.
function skin.Table(parent, width, rows, onRefresh)
    local H = 28
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, #rows * H + 12)
    local bg = Kit.Rect(box, DISPLAY, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(box, { 0, 0, 0, 1 })
    for i, row in ipairs(rows) do
        local y = -6 - (i - 1) * H
        local icon = Kit.Icon(box, row.icon, 14, C.faint)
        icon:SetPoint("TOPLEFT", 14, y - 7)
        local who = Kit.Text(box, 12, C.muted)
        who:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        who:SetText(row.text)
        local value = Kit.Text(box, 14, C.tally)
        value:SetPoint("LEFT", box, "TOPLEFT", 200, y - 14)
        value:SetPoint("RIGHT", box, "RIGHT", -14, 0)
        onRefresh(function() value:SetText(row.value()) end)
    end
    return box
end

---------------------------------------------------------------------------------------------- deck

local DECK_WORDS = { live = "ON AIR", ui = "UI", camera = "CAM", orbit = "ORBIT", mark = "MARK", layout = "LAYOUT", console = "DESK" }

-- Labeled keys on a dark strip; ON AIR lights red, a running camera or orbit amber.
function skin.Deck(deck, specs)
    local frame = CreateFrame("Frame", nil, deck)
    frame:SetAllPoints()
    local bg = Kit.Rect(frame, { C.bg[1], C.bg[2], C.bg[3], 0.95 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(frame, C.line)
    local face = { frame = frame, tab = base.DeckTab(frame), buttons = {}, pad = 5, gap = 4, lead = 0 }
    for _, spec in ipairs(specs) do
        local word = L[DECK_WORDS[spec.key] or spec.key:upper()]
        local b = Key(frame, word, 10, 24, 10)
        b.w = math.max(34, b.label:GetStringWidth() + 18)
        function b.SetHover() end
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
        return b.w, 24
    end
    function face.Paint(state)
        for _, spec in ipairs(specs) do
            local b = face.buttons[spec.key]
            local on = state.on[spec.key]
            if spec.key == "live" then
                local color = OA.live and (OA.rehearsal and C.tally or C.red) or nil
                b:Light(color, color and (OA.rehearsal and DISPLAY or { 1, 1, 1, 1 }) or nil)
            else
                b:Light(nil)
                b.label:SetTextColor(unpack(on and C.amber or C.text))
            end
            b:SetAlpha(state.editing and 0.45 or 1)
        end
    end
    return face
end

---------------------------------------------------------------------------------------------- look page

function skin.Sketch(box, Col)
    local keyA = Kit.Rect(box, Col("red"), "ARTWORK")
    keyA:SetSize(22, 8)
    keyA:SetPoint("TOPLEFT", 6, -6)
    local keyB = Kit.Rect(box, Col("tally"), "ARTWORK")
    keyB:SetSize(22, 8)
    keyB:SetPoint("LEFT", keyA, "RIGHT", 3, 0)
    local lcd = Kit.Rect(box, { 0.055, 0.059, 0.071, 1 }, "ARTWORK")
    lcd:SetSize(34, 8)
    lcd:SetPoint("TOPRIGHT", -6, -6)
    for i = 1, 8 do
        local key = Kit.Rect(box, i == 3 and Col("tally") or Col("card"), "ARTWORK")
        key:SetSize(11, 6)
        key:SetPoint("TOPLEFT", 6 + (i - 1) * 13.5, -19)
    end
    for i = 1, 4 do
        local tile = Kit.Rect(box, Col("card"), "ARTWORK")
        tile:SetSize(24, 14)
        tile:SetPoint("TOPLEFT", 6 + (i - 1) * 27, -30)
        local lit = Kit.Rect(box, i % 2 == 1 and Col("tally") or Col("off"), "OVERLAY")
        lit:SetSize(24, 2)
        lit:SetPoint("TOPLEFT", tile, "TOPLEFT")
    end
    for i = 1, 5 do
        local slot = Kit.Rect(box, { 0.055, 0.059, 0.071, 1 }, "ARTWORK")
        slot:SetSize(2, 18)
        slot:SetPoint("TOPLEFT", 14 + (i - 1) * 20, -50)
        local cap = Kit.Rect(box, Col("knob"), "OVERLAY")
        cap:SetSize(10, 4)
        cap:SetPoint("CENTER", slot, "CENTER", 0, (i % 3 - 1) * 5)
    end
end
