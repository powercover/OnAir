local _, OA = ...

-- The building blocks: colors, fonts, shapes, tweens and the studio's widgets. Flat shapes, thin
-- lines, the game's Arial Narrow; every widget is built from color textures and the white shapes in
-- Media/ (tinted), so there are no Blizzard templates to fight. The skins (Skin*.lua) build their
-- own consoles and controls from these: a camera viewfinder (the default), a vision mixer, a film
-- slate, or the plain studio console.
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
    accent = { 1, 0.231, 0.188, 1 },  -- what's picked: rail item, switch, slider fill
    accentInk = { 1, 1, 1, 1 },       -- text on the accent
    knob = { 1, 1, 1, 1 },            -- switch and slider knobs
    tally = { 0.4, 0.86, 0.5, 1 },    -- the "preview" / standby green
}
Kit.C = C

---------------------------------------------------------------------------------------------- themes

-- Each skin's colors: a palette (any key of C), the words for live / preview / off the air, and
-- flags for the touches other parts add (the go-live slate, the edit-layout grid, the banner).
-- The skin itself (its console, controls and Deck) is in Skin<Name>.lua.
Kit.THEMES = {
    { key = "viewfinder", words = { live = "REC", preview = "PREVIEW", off = "STBY" },
        corners = true, thirds = true,
        palette = {
            bg = { 0.078, 0.082, 0.09, 0.98 }, rail = { 0.067, 0.071, 0.078, 1 },
            card = { 0.106, 0.11, 0.122, 1 }, raised = { 0.145, 0.149, 0.161, 1 },
            hover = { 0.18, 0.184, 0.196, 1 }, line = { 0.23, 0.231, 0.247, 1 },
            text = { 0.914, 0.902, 0.875, 1 }, muted = { 0.604, 0.588, 0.553, 1 },
            faint = { 0.38, 0.37, 0.35, 1 }, off = { 0.3, 0.3, 0.3, 1 },
            accent = { 1, 0.69, 0.125, 1 }, accentInk = { 0.078, 0.082, 0.09, 1 },
            knob = { 0.078, 0.082, 0.09, 1 }, tally = { 0.31, 0.765, 0.969, 1 },
        } },
    { key = "mixer", words = { live = "PROGRAM", preview = "PREVIEW", off = "OFF AIR" },
        keys = true,
        palette = {
            bg = { 0.114, 0.122, 0.141, 0.98 }, rail = { 0.09, 0.098, 0.114, 1 },
            card = { 0.165, 0.173, 0.2, 1 }, raised = { 0.2, 0.208, 0.239, 1 },
            hover = { 0.24, 0.25, 0.282, 1 }, line = { 0.255, 0.267, 0.306, 1 },
            text = { 0.847, 0.859, 0.886, 1 }, muted = { 0.541, 0.561, 0.604, 1 },
            faint = { 0.36, 0.38, 0.42, 1 },
            accent = { 1, 0.231, 0.188, 1 }, tally = { 0.545, 0.886, 0.561, 1 },
            knob = { 0.79, 0.8, 0.83, 1 },
        } },
    { key = "slate", words = { live = "TAKE", preview = "REHEARSAL", off = "CUT" },
        stripes = true,
        palette = {
            bg = { 0.102, 0.102, 0.102, 0.98 }, rail = { 0.078, 0.078, 0.078, 1 },
            card = { 0.125, 0.125, 0.12, 1 }, raised = { 0.165, 0.16, 0.153, 1 },
            hover = { 0.2, 0.196, 0.188, 1 }, line = { 0.42, 0.4, 0.36, 1 },
            text = { 0.937, 0.914, 0.863, 1 }, muted = { 0.659, 0.635, 0.58, 1 },
            faint = { 0.45, 0.43, 0.39, 1 }, red = { 1, 0.353, 0.306, 1 },
            accent = { 0.937, 0.914, 0.863, 1 }, accentInk = { 0.102, 0.102, 0.102, 1 },
            knob = { 0.102, 0.102, 0.102, 1 },
        } },
    { key = "studio", words = { live = "ON AIR", preview = "PREVIEW", off = "OFF AIR" },
        palette = {} },
}

local theme = Kit.THEMES[1]

-- The base colors (what a theme leaves alone keeps these), for previews of the other themes.
local BASE = {}
for name, color in pairs(C) do
    BASE[name] = { color[1], color[2], color[3], color[4] }
end

-- A color of any theme (for its preview card).
function Kit.ThemeColor(t, name)
    return t.palette[name] or BASE[name]
end

function Kit.Theme()
    return theme
end

-- Paints the palette into C (the same tables, so colors captured earlier follow).
function Kit.ApplyTheme(key)
    for _, t in ipairs(Kit.THEMES) do
        if t.key == key then
            theme = t
        end
    end
    for name, base in pairs(BASE) do
        local color = theme.palette[name] or base
        local target = C[name]
        for i = 1, 4 do
            target[i] = color[i] or 1
        end
    end
end

---------------------------------------------------------------------------------------------- skins

-- Skin<Name>.lua files add themselves here: Kit.SKINS[key] = { Shell = ..., Toggle = ..., ... }.
Kit.SKINS = {}

-- The active skin (the studio one fills in anything a skin leaves out).
function Kit.Skin()
    return Kit.SKINS[theme.key] or Kit.SKINS.studio
end

-- Parts that drew themselves in the old skin's colors redo it when the skin changes.
local skinListeners = {}

function Kit.OnSkin(fn)
    skinListeners[#skinListeners + 1] = fn
end

function Kit.SetSkin(key)
    Kit.ApplyTheme(key)
    for i, fn in ipairs(skinListeners) do
        Utils.Guard("skin " .. i, fn)(key)
    end
end

-- "live", "preview" or "off" in the theme's words (REC / PREVIEW / STBY on a viewfinder).
function Kit.Word(state)
    return OA.L[theme.words[state] or ""]
end

-- Viewfinder brackets on a frame's corners. Returns the textures (to move them, e.g. fly in).
function Kit.Corners(frame, length, thick, color, inset, layer)
    local list = {}
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local sx = corner:find("LEFT") and 1 or -1
        local sy = corner:find("TOP") and -1 or 1
        local h = frame:CreateTexture(nil, layer or "OVERLAY")
        h:SetColorTexture(unpack(color))
        h:SetSize(length, thick)
        local v = frame:CreateTexture(nil, layer or "OVERLAY")
        v:SetColorTexture(unpack(color))
        v:SetSize(thick, length)
        local bracket = { h = h, v = v, corner = corner, sx = sx, sy = sy }
        function bracket.Place(off)
            h:ClearAllPoints()
            v:ClearAllPoints()
            h:SetPoint(corner, frame, corner, sx * off, sy * off)
            v:SetPoint(corner, frame, corner, sx * off, sy * off)
        end
        bracket.Place(inset or 0)
        list[#list + 1] = bracket
    end
    function list.Place(off)
        for _, b in ipairs(list) do
            b.Place(off)
        end
    end
    function list.SetAlpha(a)
        for _, b in ipairs(list) do
            b.h:SetAlpha(a)
            b.v:SetAlpha(a)
        end
    end
    return list
end

-- A tiled band: the slate's diagonal clapper stripes or a film strip's sprocket holes.
function Kit.Band(parent, file, color, layer)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    tex:SetTexture(Utils.MEDIA .. file, "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    tex:SetVertexColor(unpack(color or C.text))
    return tex
end

-- Arial Narrow has no Cyrillic or East Asian letters: those clients use their standard font.
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT
Kit.FONT = FONT

-- OnAir Mono: OnAir's own pixel font (made by tests/kit/make_font.py: Latin letters, digits,
-- the marks a readout needs) for timecodes and camera-screen text. Other alphabets keep theirs.
local MONO = LATIN[GetLocale()] and Utils.MEDIA .. "OnAirMono.ttf" or STANDARD_TEXT_FONT

local fonts = {}
local function MakeFont(file, tag, size, flags)
    local key = tag .. size .. (flags or "")
    if not fonts[key] then
        local font = CreateFont("OnAirFont" .. key:gsub("%W", ""))
        font:SetFont(file, size, flags or "")
        font:SetShadowOffset(0, 0)
        fonts[key] = font
    end
    return fonts[key]
end

function Kit.Font(size, flags)
    return MakeFont(FONT, "", size, flags)
end

function Kit.Mono(size, flags)
    return MakeFont(MONO, "Mono", size, flags)
end

function Kit.Text(parent, size, color, layer, mono)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(mono and Kit.Mono(size) or Kit.Font(size))
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
    function b:SetLabel(text)
        label:SetText(text)
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
        local r, g, b, a = Mix(C.off, C.accent, p)
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
    local underline = Kit.Rect(bar, C.accent, "ARTWORK")
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
    local focusLine = Kit.Rect(box, C.accent, "ARTWORK")
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
    local fill = Kit.Rect(track, C.accent, "BORDER")
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
