local _, OA = ...

-- Film slate: the console is a clapperboard. Clapper stripes across the top, then the slate's
-- cells: PRODUCTION (your stage name), SCENE (the page), TAKE (the timecode; click to roll). The
-- pages are a shot list, every setting sits in a ruled chalk cell (the picked choice boxed, like
-- a ticked option), and a film strip runs along the bottom with the status as edge codes.
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils
local base = Kit.SKINS.studio

-- Cells share their lines: rows and columns overlap by a pixel, so the grid reads as one board.
local skin = setmetatable({ gap = -1, colGap = -1, headingGap = 4, cols = { toggle = 2, slider = 2 } }, { __index = base })
Kit.SKINS.slate = skin

local STRIPES, BOARD, FILM, LIST = 24, 62, 30, 184
local PAD = 18
local INK = { 0.07, 0.07, 0.07, 1 }

local function Mono(parent, size, color)
    return Kit.Text(parent, size, color or C.text, nil, true)
end

function skin.Readout(parent, size)
    return Mono(parent, size, C.text)
end

-- A ruled cell: chalk lines on all four sides.
local function Cell(parent, width, height, button)
    local cell = CreateFrame(button and "Button" or "Frame", nil, parent)
    cell:SetSize(width, height)
    cell.edges = Kit.Border(cell, C.line)
    return cell
end

-- A small label in a cell's corner.
local function Tag(cell, text)
    local tag = Kit.Text(cell, 10, C.muted)
    tag:SetPoint("TOPLEFT", 9, -7)
    tag:SetText(text:upper())
    return tag
end

-- The chalk box around a picked choice (a ticked option on a slate).
local function Box(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.edges = Kit.Border(box, C.text)
    return box
end

---------------------------------------------------------------------------------------------- chrome

local function Board(face, api, onRefresh)
    local band = CreateFrame("Frame", nil, face)
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(STRIPES)
    local stripes = Kit.Band(band, "Stripes", C.text, "ARTWORK")
    stripes:SetAllPoints()
    api.Drag(band)
    local closeBox = CreateFrame("Button", nil, band)
    closeBox:SetSize(STRIPES, STRIPES)
    closeBox:SetPoint("RIGHT")
    local closeBg = Kit.Rect(closeBox, INK, "OVERLAY")
    closeBg:SetAllPoints()
    local x = Mono(closeBox, 14, C.text)
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    x:SetDrawLayer("OVERLAY", 2)
    closeBox:SetScript("OnClick", api.Close)

    local board = CreateFrame("Frame", nil, face)
    board:SetPoint("TOPLEFT", PAD, -STRIPES - 10)
    board:SetPoint("TOPRIGHT", -PAD, -STRIPES - 10)
    board:SetHeight(BOARD)
    local widths = { 250, 220, 170 }
    local cells, cx = {}, 0
    for i, w in ipairs(widths) do
        local cell = Cell(board, w, BOARD, i == 3)
        cell:SetPoint("TOPLEFT", cx, 0)
        cx = cx + w - 1
        cells[i] = cell
    end
    local rest = Cell(board, api.W - PAD * 2 - cx, BOARD)
    rest:SetPoint("TOPLEFT", cx, 0)

    Tag(cells[1], L["Production"])
    local production = Kit.Text(cells[1], 18, C.text)
    production:SetPoint("BOTTOMLEFT", 9, 10)
    production:SetPoint("RIGHT", cells[1], "RIGHT", -8, 0)
    Tag(cells[2], L["Scene"])
    local scene = Mono(cells[2], 16, C.text)
    scene:SetPoint("BOTTOMLEFT", 9, 12)
    Tag(cells[3], L["Take"])
    local take = Mono(cells[3], 18, C.red)
    take:SetPoint("BOTTOMLEFT", 9, 11)
    local takeDot = Kit.Shape(cells[3], "Dot", C.red, "ARTWORK")
    takeDot:SetSize(8, 8)
    takeDot:SetPoint("TOPRIGHT", -10, -9)
    local blink = Kit.Pulse(takeDot, 0.2, 1, 0.6)
    cells[3]:SetScript("OnClick", function() OA.Toggle() end)
    Kit.Tooltip(cells[3], L["Go live / end"], L["Click to go live or end the broadcast."])

    local layout = skin.Button(rest, { text = L["Layout"], width = 76, click = function() OA.Layout.Toggle() end })
    layout:SetPoint("BOTTOMRIGHT", -8, 9)
    local preview = skin.Button(rest, { text = L["Preview"], width = 76, click = function() OA.TogglePreview() end })
    preview:SetPoint("RIGHT", layout, "LEFT", -6, 0)
    Kit.Tooltip(preview, L["Preview"], L["Mask everything like live, to check your screen. No clock, no moments, no Shield."])

    local acc = 0
    local function Tick()
        local state = api.State()
        take:SetText(state == "live" and api.Clock() or Kit.Word(state))
    end
    board:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            Tick()
        end
    end)
    onRefresh(function()
        local state = api.State()
        production:SetText(OA.Names.MeAlias())
        local item = api.items[api.Current() or "broadcast"]
        scene:SetText(item and item.text:upper() or "")
        take:SetTextColor(unpack(state == "live" and C.red or (state == "preview" and C.amber or C.muted)))
        takeDot:SetVertexColor(unpack(state == "preview" and C.amber or C.red))
        takeDot:SetShown(state ~= "off")
        if state == "off" then
            blink:Stop()
        else
            blink:Play()
        end
        preview:SetLabel(state == "preview" and L["End"] or L["Preview"])
        preview:SetAlpha(state == "live" and 0.35 or 1)
        layout:SetLabel(OA.Layout.IsEditing() and L["Done"] or L["Layout"])
        Tick()
    end)
    return scene
end

-- The shot list: numbered, ruled; the picked shot chalked in.
local NAV_H = 27

local function ShotList(face, api, scene)
    local list = CreateFrame("Frame", nil, face)
    list:SetPoint("TOPLEFT", PAD, -STRIPES - BOARD - 22)
    list:SetPoint("BOTTOMLEFT", PAD, FILM + 10)
    list:SetWidth(LIST - PAD)
    local lit = Kit.Rect(list, C.text, "BORDER")
    lit:SetSize(LIST - PAD, NAV_H - 1)
    local y0 = 0
    local key = {}
    local function Place(y)
        y0 = y
        lit:SetPoint("TOPLEFT", 0, -y)
    end
    local rows = {}
    local n, y = 0, 0
    for _, section in ipairs(api.sections) do
        if section.title then
            local label = Mono(list, 9, C.faint)
            label:SetPoint("TOPLEFT", 2, -y - 6)
            label:SetText(section.title)
            y = y + 20
        end
        for _, item in ipairs(section.items) do
            n = n + 1
            local b = CreateFrame("Button", nil, list)
            b:SetSize(LIST - PAD, NAV_H)
            b:SetPoint("TOPLEFT", 0, -y)
            local rule = Kit.Rect(b, C.line, "BORDER")
            rule:SetPoint("BOTTOMLEFT")
            rule:SetPoint("BOTTOMRIGHT")
            rule:SetHeight(1)
            local number = Mono(b, 10, C.faint)
            number:SetPoint("LEFT", 6, 0)
            number:SetText(string.format("%02d", n))
            local text = Mono(b, 12, C.muted)
            text:SetPoint("LEFT", 34, 0)
            text:SetText(item.text:upper())
            b.number, b.text, b.y = number, text, y
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
            rows[item.key] = b
            y = y + NAV_H
        end
        y = y + 6
    end
    return function(pageKey, animate)
        for k, b in pairs(rows) do
            local on = k == pageKey
            b.text:SetTextColor(unpack(on and INK or C.muted))
            b.number:SetTextColor(unpack(on and INK or C.faint))
            if on then
                if animate then
                    Kit.Tween(key, y0, b.y, 0.28, Place, "quint")
                else
                    Place(b.y)
                end
            end
        end
        local item = api.items[pageKey]
        scene:SetText(item and item.text:upper() or "")
    end
end

-- The film strip: sprocket holes above and below, the status between them as edge codes.
local function Film(face, api, onRefresh)
    local strip = CreateFrame("Frame", nil, face)
    strip:SetPoint("BOTTOMLEFT", 1, 1)
    strip:SetPoint("BOTTOMRIGHT", -1, 1)
    strip:SetHeight(FILM)
    local bg = Kit.Rect(strip, INK, "BACKGROUND")
    bg:SetAllPoints()
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local holes = Kit.Band(strip, "Sprocket", C.line, "ARTWORK")
        holes:SetPoint(side .. "LEFT")
        holes:SetPoint(side .. "RIGHT")
        holes:SetHeight(8)
    end
    local segments = {}
    local x = 24
    for i, seg in ipairs(api.status) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(134, 12)
        b:SetPoint("LEFT", x, 0)
        local text = Mono(b, 9, C.amber)
        text:SetPoint("LEFT")
        b:SetScript("OnClick", function() api.Show(seg.page) end)
        segments[i] = { seg = seg, label = text }
        x = x + 138
    end
    local function Paint()
        for _, s in ipairs(segments) do
            local text, color = s.seg.text()
            s.label:SetText("\226\150\184 " .. text:upper())
            s.label:SetTextColor(unpack(color == C.off and C.faint or C.amber))
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
    local scene = Board(face, api, onRefresh)
    local select = ShotList(face, api, scene)
    Film(face, api, onRefresh)
    local area = CreateFrame("Frame", nil, face)
    area:SetPoint("TOPLEFT", LIST, -STRIPES - BOARD - 12)
    area:SetPoint("BOTTOMRIGHT", 0, FILM + 2)
    return { area = area, areaWidth = api.W - LIST, width = api.W - LIST - PAD * 2 - 8, pad = PAD, Select = select }
end

-- The page's header: what it does, in chalk (the scene's name is on the board above).
function skin.Page(shell, body, item)
    local desc = Kit.Text(body, 13, C.muted)
    desc:SetPoint("TOPLEFT", PAD, -12)
    desc:SetWidth(shell.width)
    desc:SetWordWrap(true)
    desc:SetSpacing(2)
    desc:SetText(item.desc)
    return 12 + math.max(desc:GetStringHeight(), 14) + 10
end

---------------------------------------------------------------------------------------------- controls

-- A small clapper and the group's name; a hint below.
function skin.Heading(parent, text, hint, width)
    local holder = CreateFrame("Frame", nil, parent)
    local mark = Kit.Band(holder, "Stripes", C.text, "ARTWORK")
    mark:SetSize(26, 10)
    mark:SetPoint("TOPLEFT", 0, -16)
    local head = Mono(holder, 12, C.text)
    head:SetPoint("LEFT", mark, "RIGHT", 8, 0)
    head:SetText(text:upper())
    local h = 34
    if hint then
        local fs = Kit.Text(holder, 12, C.muted)
        fs:SetPoint("TOPLEFT", 0, -34)
        fs:SetWidth(width)
        fs:SetWordWrap(true)
        fs:SetText(hint)
        h = 40 + fs:GetStringHeight()
    end
    holder:SetSize(width, h)
    return holder
end

-- ON or OFF, chalked big in the cell; the name in the corner, what it does under it.
function skin.Toggle(parent, spec, width)
    local cell = Cell(parent, width, 60, true)
    local name = Tag(cell, spec.title)
    name:SetPoint("RIGHT", cell, "RIGHT", -70, 0)
    local help = Kit.Text(cell, 10, C.faint)
    help:SetPoint("TOPLEFT", 9, -24)
    help:SetWidth(width - 86)
    help:SetWordWrap(true)
    help:SetMaxLines(2)
    help:SetText(spec.help or "")
    local value = Mono(cell, 18, C.text)
    value:SetPoint("RIGHT", -12, 0)
    local hover = Kit.Rect(cell, { 1, 1, 1, 0.04 }, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetAlpha(0)
    cell:SetScript("OnEnter", function() hover:SetAlpha(1) end)
    cell:SetScript("OnLeave", function() hover:SetAlpha(0) end)
    cell:SetScript("OnClick", function()
        spec.set(not spec.get())
        OA.UI.Refresh()
        PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end)
    local was
    function cell:Refresh(animate)
        local on = spec.get() and true or false
        value:SetText(on and L["ON"] or L["OFF"])
        value:SetTextColor(unpack(on and C.text or C.faint))
        name:SetTextColor(unpack(on and C.text or C.muted))
        if animate and was ~= nil and was ~= on then
            Kit.Tween(value, 0, 1, 0.25, function(p) value:SetAlpha(p) end)
        end
        was = on
    end
    cell:Refresh(false)
    return cell
end

function skin.Check(parent, spec, width)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, 24)
    local rule = Kit.Rect(row, C.line, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    local text = Kit.Text(row, 12, C.text)
    text:SetPoint("LEFT", 2, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -50, 0)
    text:SetText(spec.title)
    local value = Mono(row, 12, C.text)
    value:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnClick", function()
        spec.set(not spec.get())
        row:Refresh()
    end)
    function row:Refresh()
        local on = spec.get() and true or false
        value:SetText(on and L["ON"] or L["OFF"])
        value:SetTextColor(unpack(on and C.text or C.faint))
    end
    row:Refresh()
    return row
end

-- The options written across the cell; the picked one boxed.
function skin.Choice(parent, spec, width)
    local labeled = spec.label ~= nil
    local top = labeled and 26 or 6
    local hintH = 0
    local cell = Cell(parent, width, 10)
    if labeled then
        Tag(cell, spec.label)
        if spec.hint then
            local hint = Kit.Text(cell, 11, C.faint)
            hint:SetPoint("TOPLEFT", 9, -26)
            hint:SetWidth(width - 18)
            hint:SetWordWrap(true)
            hint:SetText(spec.hint)
            hintH = hint:GetStringHeight() + 6
        end
    end
    local box = Box(cell)
    local words = {}
    local x = labeled and 9 or 6
    local rowY = top + hintH
    for i, option in ipairs(spec.options) do
        local b = CreateFrame("Button", nil, cell)
        local text = Mono(b, 12, C.muted)
        text:SetPoint("CENTER")
        text:SetText(option.text:upper())
        local w = math.max(text:GetStringWidth(), #option.text * 7.2) + 16
        if not labeled then
            w = (width - 12) / #spec.options
            x = 6 + (i - 1) * w
        end
        b:SetSize(w, 24)
        b:SetPoint("TOPLEFT", x, -rowY)
        b:SetScript("OnClick", function()
            spec.set(option.value)
            OA.UI.Refresh()
            cell:Refresh(true)
        end)
        b:SetScript("OnEnter", function() text:SetTextColor(unpack(C.text)) end)
        b:SetScript("OnLeave", function() cell:Refresh(false) end)
        words[i] = { button = b, text = text, value = option.value }
        if labeled then
            x = x + w + 6
        end
    end
    cell:SetHeight(rowY + 24 + 8)
    local key = {}
    function cell:Refresh(animate)
        local current = spec.get()
        for _, word in ipairs(words) do
            local on = word.value == current
            word.text:SetTextColor(unpack(on and C.text or C.muted))
            if on then
                local target = word.button
                box:ClearAllPoints()
                box:SetAllPoints(target)
                if animate then
                    Kit.Tween(key, 0, 1, 0.2, function(p) box:SetAlpha(p) end)
                end
            end
        end
    end
    cell:Refresh(false)
    return cell
end

-- The value chalked big, a ruled scale with a chalk mark.
function skin.Slider(parent, spec, width)
    local min, max, step = spec.min, spec.max, spec.step
    local cell = Cell(parent, width, 64)
    Tag(cell, spec.label)
    local value = Mono(cell, 14, C.text)
    value:SetPoint("TOPRIGHT", -10, -7)
    value:SetJustifyH("RIGHT")
    local scale = CreateFrame("Button", nil, cell)
    scale:SetPoint("BOTTOMLEFT", 10, 8)
    scale:SetPoint("BOTTOMRIGHT", -10, 8)
    scale:SetHeight(24)
    local line = Kit.Rect(scale, C.line, "BORDER")
    line:SetPoint("LEFT", 0, -4)
    line:SetPoint("RIGHT", 0, -4)
    line:SetHeight(1)
    local fill = Kit.Rect(scale, C.text, "ARTWORK")
    fill:SetPoint("LEFT", 0, -4)
    fill:SetHeight(2)
    local scaleW = width - 20
    for i = 0, 10 do
        local tick = Kit.Rect(scale, C.line, "BORDER")
        tick:SetSize(1, i % 5 == 0 and 8 or 4)
        tick:SetPoint("BOTTOM", scale, "LEFT", scaleW * i / 10, -4)
    end
    local mark = Kit.Rect(scale, C.text, "OVERLAY")
    mark:SetSize(3, 16)
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
        mark:ClearAllPoints()
        mark:SetPoint("CENTER", scale, "LEFT", p * w, -4)
        fill:SetWidth(math.max(1, p * w))
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
        mark:SetColorTexture(unpack(C.red))
        Keys(enabled)
    end)
    scale:SetScript("OnLeave", function()
        mark:SetColorTexture(unpack(C.text))
        Keys(false)
    end)
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
    end)
    scale:SetScript("OnSizeChanged", function()
        Paint(Snap(spec.get() or min))
    end)
    function cell:Refresh()
        Paint(Snap(spec.get() or min))
    end
    function cell:SetEnabledLook(on)
        enabled = on
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    cell:Refresh()
    return cell
end

-- Text chalked into a cell.
local function Chalk(parent, width, get, set, live)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 24)
    box:SetAutoFocus(false)
    box:SetFontObject(Kit.Font(16))
    box:SetTextColor(unpack(C.text))
    box:SetTextInsets(0, 4, 0, 0)
    box:SetMaxLetters(48)
    local line = Kit.Rect(box, C.text, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetAlpha(0)
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
    box:SetScript("OnEditFocusGained", function() line:SetAlpha(0.6) end)
    box:SetScript("OnEditFocusLost", function(self)
        line:SetAlpha(0)
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
    return box
end

function skin.Input(parent, spec, width)
    local cell = Cell(parent, width, 10, true)
    local top = 8
    if spec.label then
        Tag(cell, spec.label)
        top = 24
        if spec.hint then
            local hint = Kit.Text(cell, 11, C.faint)
            hint:SetPoint("TOPLEFT", 9, -24)
            hint:SetWidth(width - 18)
            hint:SetWordWrap(true)
            hint:SetText(spec.hint)
            top = top + hint:GetStringHeight() + 4
        end
    end
    local action = spec.action
    local box = Chalk(cell, width - 18 - (action and 34 or 0), spec.get, spec.set, spec.live)
    box:SetPoint("TOPLEFT", 9, -top)
    if spec.max then
        box:SetMaxLetters(spec.max)
    end
    if action then
        local b = Kit.IconButton(cell, action.icon, 26, action.title, action.help, action.click)
        b:SetPoint("TOPRIGHT", -6, -top + 1)
    end
    cell:SetHeight(top + 24 + 8)
    cell:SetScript("OnClick", function() box:SetFocus() end)
    cell.box = box
    function cell:Refresh()
        box:Refresh()
    end
    function cell:SetEnabledLook(on)
        box:SetEnabled(on)
        self.oaAlpha = on and 1 or 0.35
        self:SetAlpha(self.oaAlpha)
    end
    return cell
end

-- Fields: cells side by side, each with its name in the corner.
function skin.Fields(parent, spec, width)
    local holder = CreateFrame("Frame", nil, parent)
    local y = 0
    if spec.label then
        local head = skin.Heading(holder, spec.label, spec.hint, width)
        head:SetPoint("TOPLEFT")
        y = head:GetHeight() + 4
    end
    local n = #spec.items
    local w = (width + (n - 1)) / n
    holder.inputs = {}
    local h = 0
    for i, item in ipairs(spec.items) do
        local cell = skin.Input(holder, { label = item.label, get = item.get, set = item.set, live = item.live }, w)
        cell:SetPoint("TOPLEFT", (i - 1) * (w - 1), -y)
        h = math.max(h, cell:GetHeight())
        holder.inputs[i] = cell
    end
    holder:SetSize(width, y + h)
    function holder:Refresh()
        for _, cell in ipairs(self.inputs) do
            cell:Refresh()
        end
    end
    return holder
end

-- A chalk-outlined word; the main ones chalked in. Space above it, as the cells touch.
function skin.Button(parent, spec)
    local b = CreateFrame("Button", nil, parent)
    local primary = spec.kind == "primary"
    local label = Mono(b, 12, primary and INK or C.text)
    label:SetPoint("CENTER")
    label:SetText(spec.text:upper())
    b:SetSize(spec.width or math.max(110, label:GetStringWidth() + 30), 30)
    local fill = Kit.Rect(b, C.text, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetAlpha(primary and 1 or 0)
    local edges = Kit.Border(b, C.text)
    b:SetScript("OnEnter", function()
        fill:SetAlpha(primary and 0.85 or 0.08)
    end)
    b:SetScript("OnLeave", function()
        fill:SetAlpha(primary and 1 or 0)
    end)
    if spec.click then
        b:SetScript("OnClick", spec.click)
    end
    if spec.tip then
        Kit.Tooltip(b, spec.text, spec.tip)
    end
    b.label, b.edges = label, edges
    function b:SetLabel(text)
        label:SetText(text:upper())
    end
    return b
end

-- Notes and other loose text sit a little apart from the cells.
function skin.Note(parent, text, width, big)
    local holder = CreateFrame("Frame", nil, parent)
    local fs = Kit.Text(holder, big and 13 or 12, big and C.muted or C.faint)
    fs:SetPoint("TOPLEFT", 0, -10)
    fs:SetWidth(width)
    fs:SetWordWrap(true)
    fs:SetSpacing(2)
    fs:SetText(text)
    holder:SetSize(width, math.max(1, fs:GetStringHeight()) + 14)
    holder.text = fs
    return holder
end

function skin.ListRow(parent, width, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    local rule = Kit.Rect(row, C.line, "BORDER")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    return row
end

---------------------------------------------------------------------------------------------- broadcast

-- The slate itself: its arm of stripes, ROLL / TAKE cells and the clap that starts the take.
function skin.Live(parent, width, api, onRefresh)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 120)
    local arm = Kit.Band(holder, "Stripes", C.text, "ARTWORK")
    arm:SetPoint("TOPLEFT", 0, -10)
    arm:SetPoint("TOPRIGHT", 0, -10)
    arm:SetHeight(18)
    local roll = Cell(holder, math.floor(width * 0.34), 80)
    roll:SetPoint("TOPLEFT", 0, -30)
    Tag(roll, L["Roll"])
    local masked = Mono(roll, 20, C.text)
    masked:SetPoint("BOTTOMLEFT", 9, 14)
    local take = Cell(holder, math.floor(width * 0.36), 80)
    take:SetPoint("TOPLEFT", roll, "TOPRIGHT", -1, 0)
    Tag(take, L["Take"])
    local clock = Mono(take, 26, C.red)
    clock:SetPoint("BOTTOMLEFT", 9, 12)
    local action = Cell(holder, width - roll:GetWidth() - take:GetWidth() + 2, 80)
    action:SetPoint("TOPLEFT", take, "TOPRIGHT", -1, 0)
    local go = skin.Button(action, { text = L["Clap: go live"], kind = "primary", width = action:GetWidth() - 20,
        click = function() OA.Toggle() end })
    go:SetPoint("TOP", 0, -10)
    local preview = skin.Button(action, { text = L["Rehearsal"], width = action:GetWidth() - 20, click = function() OA.TogglePreview() end })
    preview:SetPoint("TOP", go, "BOTTOM", 0, -6)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.25 then
            acc = 0
            if OA.live and not OA.rehearsal then
                clock:SetText(api.FormatTime(OA.Moments.Elapsed()))
            end
        end
    end)
    onRefresh(function()
        local state = api.State()
        clock:SetText(state == "live" and api.FormatTime(OA.Moments.Elapsed()) or Kit.Word(state))
        clock:SetTextColor(unpack(state == "live" and C.red or (state == "preview" and C.amber or C.muted)))
        masked:SetText(OA.live and string.format(L["%d masked"], OA.Names.Count()):upper() or L["REAL NAMES"])
        go:SetLabel(state == "live" and L["Cut: end"] or L["Clap: go live"])
        preview:SetLabel(state == "preview" and L["End rehearsal"] or L["Rehearsal"])
        preview:SetAlpha(state == "live" and 0.35 or 1)
    end)
    return holder
end

-- Who | what viewers see, a ruled row each.
function skin.Table(parent, width, rows, onRefresh)
    local H = 32
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, #rows * (H - 1) + 1)
    local split = math.floor(width * 0.34)
    for i, row in ipairs(rows) do
        local left = Cell(holder, split, H)
        left:SetPoint("TOPLEFT", 0, -(i - 1) * (H - 1))
        local who = Kit.Text(left, 12, C.muted)
        who:SetPoint("LEFT", 10, 0)
        who:SetText(row.text:upper())
        local right = Cell(holder, width - split + 1, H)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", -1, 0)
        local value = Kit.Text(right, 16, C.text)
        value:SetPoint("LEFT", 12, 0)
        value:SetPoint("RIGHT", -10, 0)
        onRefresh(function() value:SetText(row.value()) end)
    end
    return holder
end

---------------------------------------------------------------------------------------------- deck

local DECK_WORDS = { live = "TAKE", ui = "UI", camera = "CAM", orbit = "ORBIT", mark = "MARK", layout = "LAYOUT", console = "SLATE" }

-- A strip of clapper stripes, then words; TAKE goes red while rolling.
function skin.Deck(deck, specs)
    local frame = CreateFrame("Frame", nil, deck)
    frame:SetAllPoints()
    local bg = Kit.Rect(frame, { C.bg[1], C.bg[2], C.bg[3], 0.95 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(frame, C.line)
    local lead = Kit.Band(frame, "Stripes", C.text, "ARTWORK")
    local face = { frame = frame, tab = base.DeckTab(frame), buttons = {}, pad = 3, gap = 0, lead = 16 }
    for _, spec in ipairs(specs) do
        local b = CreateFrame("Button", nil, frame)
        local hl = Kit.Rect(b, C.hover, "BACKGROUND", 1)
        hl:SetAllPoints()
        hl:SetAlpha(0)
        local label = Mono(b, 12, C.text)
        label:SetPoint("CENTER")
        label:SetText(L[DECK_WORDS[spec.key] or spec.key:upper()])
        b.label = label
        b.w = math.max(label:GetStringWidth(), #label:GetText() * 7.2) + 18
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
    -- The stripes sit before the words: at the left, or on top when the Deck stands upright.
    function face.Arrange(vertical)
        lead:ClearAllPoints()
        lead:SetPoint("TOPLEFT", 1, -1)
        if vertical then
            lead:SetPoint("TOPRIGHT", -1, -1)
            lead:SetHeight(face.lead - 2)
        else
            lead:SetPoint("BOTTOMLEFT", 1, 1)
            lead:SetWidth(face.lead - 2)
        end
    end
    function face.Paint(state)
        for _, spec in ipairs(specs) do
            local b = face.buttons[spec.key]
            local on = state.on[spec.key]
            b.label:SetTextColor(unpack(on and (spec.key == "live" and (OA.rehearsal and C.amber or C.red) or C.text) or C.muted))
            b:SetAlpha(state.editing and 0.45 or 1)
        end
    end
    return face
end

function skin.PanelDecor(panel)
    local band = Kit.Band(panel, "Stripes", C.text, "OVERLAY")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(5)
end

---------------------------------------------------------------------------------------------- look page

function skin.Sketch(box, Col)
    local band = Kit.Band(box, "Stripes", Col("text"), "ARTWORK")
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(9)
    for i = 1, 3 do
        local cell = CreateFrame("Frame", nil, box)
        cell:SetSize(37, 16)
        cell:SetPoint("TOPLEFT", 4 + (i - 1) * 37, -14)
        Kit.Border(cell, Col("line"))
        local v = Kit.Rect(cell, i == 3 and Col("red") or Col("text"), "ARTWORK")
        v:SetSize(18, 3)
        v:SetPoint("BOTTOMLEFT", 4, 4)
    end
    for i = 1, 4 do
        local cell = CreateFrame("Frame", nil, box)
        cell:SetSize(56, 11)
        cell:SetPoint("TOPLEFT", 4 + ((i - 1) % 2) * 55, -34 - math.floor((i - 1) / 2) * 10)
        Kit.Border(cell, Col("line"))
    end
    local film = Kit.Rect(box, { 0.07, 0.07, 0.07, 1 }, "ARTWORK")
    film:SetPoint("BOTTOMLEFT", 1, 1)
    film:SetPoint("BOTTOMRIGHT", -1, 1)
    film:SetHeight(9)
    for i = 0, 13 do
        local hole = Kit.Rect(box, Col("line"), "OVERLAY")
        hole:SetSize(4, 2)
        hole:SetPoint("BOTTOMLEFT", 3 + i * 8.4, 2)
    end
end
