local _, OA = ...

-- The look: a dark broadcast console with one red "live" accent. Flat shapes, thin lines, the
-- game's Arial Narrow for a tight studio-label feel. Every widget is built from color textures and
-- the white shapes in Media/ (tinted), so there are no Blizzard templates to fight.
OA.Kit = {}

local Kit = OA.Kit
local Utils = OA.Utils

local C = {
    bg = { 0.051, 0.055, 0.063, 0.98 },
    rail = { 0.067, 0.071, 0.082, 1 },
    card = { 0.086, 0.094, 0.106, 1 },
    raised = { 0.122, 0.13, 0.145, 1 },
    hover = { 0.155, 0.165, 0.184, 1 },
    line = { 0.165, 0.176, 0.196, 1 },
    text = { 0.93, 0.93, 0.94, 1 },
    muted = { 0.56, 0.58, 0.62, 1 },
    faint = { 0.34, 0.36, 0.40, 1 },
    red = { 1, 0.231, 0.188, 1 },
    redDeep = { 0.55, 0.09, 0.07, 1 },
    off = { 0.27, 0.29, 0.32, 1 },
    amber = { 1, 0.69, 0.2, 1 },
    green = { 0.4, 0.86, 0.5, 1 },
}
Kit.C = C

-- Arial Narrow has no Cyrillic or East Asian letters: those clients use their standard font.
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT
Kit.FONT = FONT

local fonts = {}
function Kit.Font(size, flags)
    local key = size .. (flags or "")
    if not fonts[key] then
        local font = CreateFont("OnAirFont" .. key:gsub("%W", ""))
        font:SetFont(FONT, size, flags or "")
        font:SetShadowOffset(0, 0)
        fonts[key] = font
    end
    return fonts[key]
end

function Kit.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(Kit.Font(size))
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function Kit.Rect(parent, color, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    tex:SetColorTexture(unpack(color))
    return tex
end

function Kit.Shape(parent, file, color, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(Utils.MEDIA .. file)
    tex:SetVertexColor(unpack(color or C.text))
    return tex
end

function Kit.Icon(parent, name, size, color)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(Utils.ICONS .. name)
    tex:SetSize(size, size)
    tex:SetVertexColor(unpack(color or C.text))
    return tex
end

-- A 1px border around a frame.
function Kit.Border(frame, color)
    local c = color or C.line
    local edges = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(c))
        t:SetPoint(spec[1])
        t:SetPoint(spec[2])
        if spec[3] then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
        edges[i] = t
    end
    return edges
end

function Kit.SetBorderColor(edges, color)
    for _, t in ipairs(edges) do
        t:SetColorTexture(unpack(color))
    end
end

---------------------------------------------------------------------------------------------- tweens

-- One driver for every animation: tweens run on an OnUpdate that stops when nothing moves.
local tweens = {}
local driver = CreateFrame("Frame")

-- Easing curves. "out" (cubic) is the default; "quint" is a quick start and a long soft landing
-- (pages, the rail); "back" overshoots a little and settles (knobs, popping in).
local EASE = {
    out = function(t)
        local inv = 1 - t
        return 1 - inv * inv * inv
    end,
    quint = function(t)
        local inv = 1 - t
        return 1 - inv * inv * inv * inv * inv
    end,
    back = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        local u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    end,
    linear = function(t)
        return t
    end,
}

local function Value(tw)
    local p = math.min(1, tw.t / tw.duration)
    return tw.from + (tw.to - tw.from) * tw.ease(p), p
end

local function Drive(_, elapsed)
    -- Over a copy of the keys: an apply may start other tweens.
    local keys = {}
    for key in pairs(tweens) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        local tw = tweens[key]
        if tw then
            if tw.wait > 0 then
                tw.wait = tw.wait - elapsed
            else
                tw.t = tw.t + elapsed
                local value, p = Value(tw)
                if p >= 1 then
                    tweens[key] = nil
                    value = tw.to
                end
                tw.apply(value)
            end
        end
    end
    if not next(tweens) then
        driver:SetScript("OnUpdate", nil)
    end
end

-- Moves a value from where it is now to `to`. Same key: the old tween is replaced, so the value
-- glides on from wherever it got to. `ease` picks the curve, `delay` waits first (staggering).
function Kit.Tween(key, from, to, duration, apply, ease, delay)
    local current = tweens[key]
    if current and current.wait <= 0 then
        from = (Value(current))
    end
    tweens[key] = { from = from, to = to, duration = duration or 0.18, t = 0, apply = apply,
        ease = EASE[ease or "out"] or EASE.out, wait = delay or 0 }
    driver:SetScript("OnUpdate", Drive)
end

local function Mix(a, b, p)
    return a[1] + (b[1] - a[1]) * p, a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * p
end
Kit.Mix = Mix

-- A looping pulse on a texture's alpha (the live lamp).
function Kit.Pulse(tex, low, high, duration)
    local group = tex:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(low)
    fade:SetToAlpha(high)
    fade:SetDuration(duration or 0.9)
    fade:SetSmoothing("IN_OUT")
    return group
end

---------------------------------------------------------------------------------------------- widgets

local function Tooltip(frame, title, body)
    if not title then
        return
    end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then
            GameTooltip:AddLine(body, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end
Kit.Tooltip = Tooltip

-- Buttons. kind: "primary" (red), "ghost" (outlined), "plain" (flat).
function Kit.Button(parent, text, width, height, kind, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 28)
    local base = kind == "primary" and C.red or (kind == "ghost" and C.card or C.raised)
    local hot = kind == "primary" and { 1, 0.36, 0.31, 1 } or C.hover
    local bg = Kit.Rect(b, base, "BACKGROUND")
    bg:SetAllPoints()
    b.bg = bg
    b.edges = Kit.Border(b, kind == "primary" and C.red or C.line)
    local label = Kit.Text(b, 13, kind == "primary" and { 1, 1, 1, 1 } or C.text)
    label:SetPoint("CENTER")
    label:SetText(text)
    b.label = label
    b.base, b.hot = base, hot
    local key = {}
    b:SetScript("OnEnter", function()
        Kit.Tween(key, 0, 1, 0.12, function(p) bg:SetColorTexture(Mix(b.base, b.hot, p)) end)
    end)
    b:SetScript("OnLeave", function()
        Kit.Tween(key, 1, 0, 0.2, function(p) bg:SetColorTexture(Mix(b.base, b.hot, p)) end)
    end)
    b:SetScript("OnMouseDown", function() label:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function() label:SetPoint("CENTER", 0, 0) end)
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    function b:SetColors(newBase, newHot)
        self.base, self.hot = newBase, newHot
        bg:SetColorTexture(unpack(newBase))
    end
    return b
end

function Kit.IconButton(parent, icon, size, title, body, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local tex = Kit.Icon(b, icon, math.floor(size * 0.62), C.muted)
    tex:SetPoint("CENTER")
    b.icon = tex
    local hl = Kit.Rect(b, C.hover, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetAlpha(0)
    b:SetScript("OnEnter", function()
        hl:SetAlpha(1)
        tex:SetVertexColor(unpack(C.text))
    end)
    b:SetScript("OnLeave", function()
        hl:SetAlpha(0)
        tex:SetVertexColor(unpack(C.muted))
    end)
    Tooltip(b, title, body)
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    return b
end

-- An on/off switch: a pill whose knob slides, the track turning red when on.
function Kit.Switch(parent, get, set)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(36, 20)
    local left = Kit.Shape(s, "Dot", C.off, "BACKGROUND")
    left:SetSize(20, 20)
    left:SetPoint("LEFT")
    local right = Kit.Shape(s, "Dot", C.off, "BACKGROUND")
    right:SetSize(20, 20)
    right:SetPoint("RIGHT")
    local mid = Kit.Rect(s, C.off, "BACKGROUND")
    mid:SetPoint("TOPLEFT", 10, 0)
    mid:SetPoint("BOTTOMRIGHT", -10, 0)
    local knob = Kit.Shape(s, "Dot", { 1, 1, 1, 1 }, "ARTWORK")
    knob:SetSize(14, 14)
    local key = {}
    local function Paint(p)
        local r, g, b, a = Mix(C.off, C.red, p)
        left:SetVertexColor(r, g, b, a)
        right:SetVertexColor(r, g, b, a)
        mid:SetColorTexture(r, g, b, a)
        knob:SetPoint("LEFT", 3 + p * 16, 0)
    end
    local state = get() and 1 or 0
    Paint(state)
    function s:Refresh(animate)
        local target = get() and 1 or 0
        if animate then
            Kit.Tween(key, state, target, 0.28, Paint, "back")
        else
            Paint(target)
        end
        state = target
    end
    s:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh(true)
        PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end)
    return s
end

-- A row of choices with a highlight that slides to the picked one.
function Kit.Segmented(parent, options, width, get, set)
    local bar = CreateFrame("Frame", nil, parent)
    local h = 26
    bar:SetSize(width, h)
    local bg = Kit.Rect(bar, C.card, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(bar)
    local segW = width / #options
    local pill = Kit.Rect(bar, C.raised, "BORDER")
    pill:SetSize(segW - 4, h - 4)
    local underline = Kit.Rect(bar, C.red, "ARTWORK")
    underline:SetSize(segW - 4, 2)
    underline:SetPoint("BOTTOMLEFT", pill, "BOTTOMLEFT")
    local buttons = {}
    local key = {}
    local x = 0
    local function Place(px)
        x = px
        pill:SetPoint("LEFT", 2 + px, 0)
    end
    local function Index()
        local value = get()
        for i, option in ipairs(options) do
            if option.value == value then
                return i
            end
        end
        return 1
    end
    function bar:Refresh(animate)
        local index = Index()
        local target = (index - 1) * segW
        if animate then
            Kit.Tween(key, x, target, 0.3, Place, "quint")
        else
            Place(target)
        end
        for i, b in ipairs(buttons) do
            b.label:SetTextColor(unpack(i == index and C.text or C.muted))
        end
    end
    for i, option in ipairs(options) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(segW, h)
        b:SetPoint("LEFT", (i - 1) * segW, 0)
        local label = Kit.Text(b, 12, C.muted)
        label:SetPoint("CENTER")
        label:SetText(option.text)
        b.label = label
        b:SetScript("OnClick", function()
            set(option.value)
            bar:Refresh(true)
        end)
        buttons[i] = b
    end
    bar:Refresh(false)
    return bar
end

-- A text field. `set` runs on Enter, on leaving the field, and (with live = true) on each key.
function Kit.Input(parent, width, get, set, live)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 28)
    box:SetAutoFocus(false)
    box:SetFontObject(Kit.Font(13))
    box:SetTextColor(unpack(C.text))
    box:SetTextInsets(9, 9, 0, 0)
    box:SetMaxLetters(48)
    local bg = Kit.Rect(box, C.card, "BACKGROUND")
    bg:SetAllPoints()
    local edges = Kit.Border(box)
    local focusLine = Kit.Rect(box, C.red, "ARTWORK")
    focusLine:SetPoint("BOTTOMLEFT")
    focusLine:SetPoint("BOTTOMRIGHT")
    focusLine:SetHeight(1)
    focusLine:SetAlpha(0)
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
        Kit.Tween(focusLine, focusLine:GetAlpha(), 1, 0.15, function(a) focusLine:SetAlpha(a) end)
        Kit.SetBorderColor(edges, C.faint)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        Kit.Tween(focusLine, focusLine:GetAlpha(), 0, 0.2, function(a) focusLine:SetAlpha(a) end)
        Kit.SetBorderColor(edges, C.line)
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
    function box:SetEnabledLook(enabled)
        self:SetEnabled(enabled)
        self.oaAlpha = enabled and 1 or 0.4
        self:SetAlpha(self.oaAlpha)
    end
    return box
end

-- A slider: label on the left, value on the right, a thin track with a red fill and a knob.
-- Drag it, click the track, or use the mouse wheel (one step per notch). `set` runs as it moves.
function Kit.Slider(parent, width, label, min, max, step, get, set, format)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, 40)
    local name = Kit.Text(s, 13, C.text)
    name:SetPoint("TOPLEFT")
    name:SetText(label)
    local value = Kit.Text(s, 13, C.muted)
    value:SetPoint("TOPRIGHT")
    value:SetJustifyH("RIGHT")
    local track = CreateFrame("Button", nil, s)
    track:SetPoint("BOTTOMLEFT", 0, 4)
    track:SetPoint("BOTTOMRIGHT", 0, 4)
    track:SetHeight(16)
    local rail = Kit.Rect(track, C.raised, "BACKGROUND")
    rail:SetPoint("LEFT")
    rail:SetPoint("RIGHT")
    rail:SetHeight(3)
    local fill = Kit.Rect(track, C.red, "BORDER")
    fill:SetPoint("LEFT")
    fill:SetHeight(3)
    local knob = Kit.Shape(track, "Dot", { 1, 1, 1, 1 }, "ARTWORK")
    knob:SetSize(12, 12)
    local enabled = true

    local function Snap(v)
        v = math.max(min, math.min(max, v))
        return math.floor((v - min) / step + 0.5) * step + min
    end
    local function Paint(v)
        local p = (v - min) / (max - min)
        local w = track:GetWidth()
        if not w or w <= 0 then
            w = width
        end
        fill:SetWidth(math.max(1, p * w))
        knob:SetPoint("CENTER", track, "LEFT", p * w, 0)
        value:SetText(format and format(v) or tostring(v))
    end
    local function Apply(v)
        v = Snap(v)
        set(v)
        Paint(v)
    end
    local function FromCursor()
        local left = track:GetLeft()
        local w = track:GetWidth()
        if not left or not w or w <= 0 then
            return
        end
        local x = GetCursorPosition() / track:GetEffectiveScale()
        Apply(min + (max - min) * ((x - left) / w))
    end
    track:SetScript("OnMouseDown", function(self)
        if not enabled then
            return
        end
        FromCursor()
        self:SetScript("OnUpdate", FromCursor)
    end)
    track:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    -- The mouse wheel is left to the page (scrolling past a slider never changes it). While the
    -- pointer is on the slider, the arrow keys step it (Shift: five steps). Keyboard capture is
    -- off in combat, where the game doesn't allow it.
    local function Keys(on)
        if InCombatLockdown() then
            on = false
        end
        track:EnableKeyboard(on)
        if on and track.SetPropagateKeyboardInput then
            track:SetPropagateKeyboardInput(true)
        end
    end
    track:SetScript("OnEnter", function()
        Kit.Tween(knob, knob:GetWidth(), 16, 0.12, function(v) knob:SetSize(v, v) end)
        value:SetTextColor(unpack(C.text))
        Keys(enabled)
    end)
    track:SetScript("OnLeave", function()
        Kit.Tween(knob, knob:GetWidth(), 12, 0.16, function(v) knob:SetSize(v, v) end)
        value:SetTextColor(unpack(C.muted))
        Keys(false)
    end)
    track:SetScript("OnKeyDown", function(self, key)
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
        Apply((get() or min) + delta * step * (IsShiftKeyDown() and 5 or 1))
    end)
    track:SetScript("OnSizeChanged", function()
        Paint(Snap(get() or min))
    end)
    function s:Refresh()
        Paint(Snap(get() or min))
    end
    function s:SetEnabledLook(on)
        enabled = on
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    s:Refresh()
    return s
end

-- A small uppercase label above a group of controls.
function Kit.Heading(parent, text)
    local fs = Kit.Text(parent, 11, C.muted)
    fs:SetText(text:upper())
    return fs
end

-- A vertical scroll area: content goes in `scroll.child` (fixed width, grows as needed).
function Kit.Scroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 10)
    scroll:SetScrollChild(child)
    scroll.child = child
    local thumb = Kit.Rect(scroll, C.raised, "OVERLAY")
    thumb:SetWidth(3)
    thumb:Hide()
    local function Thumb()
        local range = scroll:GetVerticalScrollRange()
        local h = scroll:GetHeight()
        if range <= 0 or h <= 0 then
            thumb:Hide()
            return
        end
        local size = math.max(24, h * h / (h + range))
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -(h - size) * (scroll:GetVerticalScroll() / range))
        thumb:Show()
    end
    scroll:EnableMouseWheel(true)
    local key = {}
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local target = math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48))
        Kit.Tween(key, self:GetVerticalScroll(), target, 0.18, function(v)
            self:SetVerticalScroll(v)
            Thumb()
        end)
    end)
    scroll:SetScript("OnScrollRangeChanged", Thumb)
    scroll:SetScript("OnSizeChanged", Thumb)
    function scroll:SetContentHeight(h)
        child:SetHeight(h)
        Thumb()
    end
    return scroll
end
