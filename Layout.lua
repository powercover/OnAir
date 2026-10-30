local _, OA = ...

-- Edit layout: a grid over the screen, and everything OnAir puts on it (the ON AIR badge, the
-- stream chat, the Deck) unlocked and outlined so it can be dragged into place. Drops snap: any
-- side or the middle of a piece onto a guide (the screen's center lines and edges, the sides and
-- middles of the other pieces), its sides onto the grid. Shift drops freely. Done (or Esc) puts
-- the console back.
OA.Layout = {}

local Layout = OA.Layout
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local GRID = 32
local RANGE = 12     -- how close (in UI pixels) an anchor is pulled onto a guide
local GRID_RANGE = 8 -- ... and a side onto a grid line
local STEP = 4       -- off the lines, positions round to this
local GRID_ALPHA = 0.07
local SHADE_ALPHA = 0.35

local editing = false
local movers = {}
local grid, bar, shade
local lines = {}     -- grid lines: { tex, distance from the center }
local centerX, centerY
local guideX, guideY
local dragging
local consoleWasOpen = false

function Layout.IsEditing()
    return editing
end

-- A piece of the layout. opts.show(on) makes it visible for editing (and puts it back after);
-- opts.save() stores where it was dropped; opts.snap (optional) replaces the grid snap.
function Layout.Register(key, frame, label, opts)
    movers[key] = { frame = frame, label = label, opts = opts or {} }
end

local function BuildGrid()
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = w / 2, h / 2
    -- Lines out from the center, so the center lines sit exactly in the middle.
    local function Line(vertical, offset)
        local t = grid:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, GRID_ALPHA)
        if vertical then
            t:SetWidth(1)
            t:SetPoint("TOP", grid, "TOPLEFT", cx + offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOMLEFT", cx + offset, 0)
        else
            t:SetHeight(1)
            t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, cy + offset)
            t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, cy + offset)
        end
        lines[#lines + 1] = { tex = t, distance = math.abs(offset) / math.max(cx, cy) }
    end
    shade = Kit.Rect(grid, { 0, 0, 0, SHADE_ALPHA }, "BACKGROUND")
    shade:SetAllPoints()
    for x = GRID, cx, GRID do
        Line(true, x)
        Line(true, -x)
    end
    for y = GRID, cy, GRID do
        Line(false, y)
        Line(false, -y)
    end
    -- The center lines grow out from the middle when the grid opens.
    centerX = grid:CreateTexture(nil, "ARTWORK")
    centerX:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.45)
    centerX:SetWidth(1)
    centerX:SetPoint("CENTER", grid, "BOTTOMLEFT", cx, cy)
    centerY = grid:CreateTexture(nil, "ARTWORK")
    centerY:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.45)
    centerY:SetHeight(1)
    centerY:SetPoint("CENTER", grid, "BOTTOMLEFT", cx, cy)
    -- The guides that light up where a dragged piece will snap.
    guideX = grid:CreateTexture(nil, "OVERLAY")
    guideX:SetWidth(2)
    guideX:Hide()
    guideY = grid:CreateTexture(nil, "OVERLAY")
    guideY:SetHeight(2)
    guideY:Hide()
    grid:Hide()
end

local function BuildBar()
    bar = CreateFrame("Frame", "OnAirLayoutBar", UIParent)
    bar:SetSize(420, 40)
    bar:SetPoint("TOP", 0, -14)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    local bg = Kit.Rect(bar, C.bg, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(bar, C.redDeep)
    local dot = Kit.Shape(bar, "Dot", C.red, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 14, 0)
    local text = Kit.Text(bar, 13, C.text)
    text:SetPoint("LEFT", 30, 0)
    text:SetText(L["EDIT LAYOUT  -  drag things to move them"])
    local done = Kit.Button(bar, L["Done"], 80, 26, "primary", function()
        Layout.Stop(true)
    end)
    done:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    done:SetPoint("RIGHT", -8, 0)
    tinsert(UISpecialFrames, "OnAirLayoutBar")
    bar:SetScript("OnHide", function()
        if editing then
            Layout.Stop()
        end
    end)
    bar:Hide()
end

local function Outline(mover)
    if mover.outline then
        return mover.outline
    end
    local o = CreateFrame("Frame", nil, mover.frame)
    o:SetAllPoints()
    o:SetFrameLevel(mover.frame:GetFrameLevel() + 30)
    local fill = Kit.Rect(o, { 1, 0.23, 0.19, 0.08 }, "BACKGROUND")
    fill:SetAllPoints()
    Kit.Border(o, C.red)
    local tag = CreateFrame("Frame", nil, o)
    tag:SetSize(10, 18)
    tag:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 2)
    local tagBg = Kit.Rect(tag, C.red, "BACKGROUND")
    tagBg:SetAllPoints()
    local tagText = Kit.Text(tag, 11, { 1, 1, 1, 1 })
    tagText:SetPoint("LEFT", 6, 0)
    tagText:SetText(mover.label:upper())
    tag:SetWidth(tagText:GetStringWidth() + 12)
    mover.outline = o
    return o
end

-- A frame's box in UIParent's units: left, bottom, width, height (and the scale to get back).
local function Box(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then
        return nil
    end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, bottom * k, frame:GetWidth() * k, frame:GetHeight() * k, k
end

-- The guides on one axis: the screen's center line ("center") and edges ("edge"), and the
-- sides and middles of the other visible pieces ("piece").
local function Guides(frame, vertical)
    local size = vertical and UIParent:GetHeight() or UIParent:GetWidth()
    local list = { { size / 2, "center" }, { 0, "edge" }, { size, "edge" } }
    for _, mover in pairs(movers) do
        local other = mover.frame
        if other ~= frame and other:IsVisible() then
            local left, bottom, w, h = Box(other)
            if left then
                local start, length = left, w
                if vertical then
                    start, length = bottom, h
                end
                list[#list + 1] = { start, "piece" }
                list[#list + 1] = { start + length / 2, "piece" }
                list[#list + 1] = { start + length, "piece" }
            end
        end
    end
    return list
end

-- One axis: the closest of (any anchor onto a guide) and (a side onto a grid line) wins;
-- otherwise the position rounds to STEP. Returns the new start, the line and its kind.
local function Axis(start, size, center, guides)
    local best, line, kind, dist = math.floor(start / STEP + 0.5) * STEP, nil, nil, RANGE
    for _, offset in ipairs({ 0, size / 2, size }) do
        local anchor = start + offset
        for _, guide in ipairs(guides) do
            local d = math.abs(anchor - guide[1])
            if d < dist then
                best, line, kind, dist = guide[1] - offset, guide[1], guide[2], d
            end
        end
    end
    dist = math.min(dist, GRID_RANGE)
    for _, offset in ipairs({ 0, size }) do
        local anchor = start + offset
        local gridLine = center + math.floor((anchor - center) / GRID + 0.5) * GRID
        local d = math.abs(anchor - gridLine)
        if d < dist then
            best, line, kind, dist = gridLine - offset, gridLine, "grid", d
        end
    end
    return best, line, kind
end

-- Where a frame would snap. Returns left and bottom in the frame's own units (ready for
-- SetPoint), then the lines it snapped to (UI units, or nil) and their kinds.
function Layout.SnapPosition(frame)
    local left, bottom, w, h, k = Box(frame)
    if not left then
        return nil
    end
    if IsShiftKeyDown() then
        return left / k, bottom / k
    end
    local x, gx, kx = Axis(left, w, UIParent:GetWidth() / 2, Guides(frame, false))
    local y, gy, ky = Axis(bottom, h, UIParent:GetHeight() / 2, Guides(frame, true))
    return x / k, y / k, gx, gy, kx, ky
end

local function GridSnap(frame)
    local x, y = Layout.SnapPosition(frame)
    if x then
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", frame:GetParent() or UIParent, "BOTTOMLEFT", x, y)
    end
end
Layout.GridSnap = GridSnap

local GUIDE_COLORS = {
    center = { C.red[1], C.red[2], C.red[3], 1 },
    piece = { C.amber[1], C.amber[2], C.amber[3], 0.9 },
    edge = { 1, 1, 1, 0.55 },
    grid = { 1, 1, 1, 0.55 },
}

local function Guide(tex, at, kind, vertical)
    if not at then
        tex:Hide()
        return
    end
    local color = GUIDE_COLORS[kind] or GUIDE_COLORS.grid
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:ClearAllPoints()
    if vertical then
        tex:SetPoint("TOP", grid, "TOPLEFT", at, 0)
        tex:SetPoint("BOTTOM", grid, "BOTTOMLEFT", at, 0)
    else
        tex:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, at)
        tex:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, at)
    end
    tex:Show()
end

-- While something is dragged: light the lines it would snap to.
local function ShowGuides()
    if not dragging then
        guideX:Hide()
        guideY:Hide()
        return
    end
    local _, _, gx, gy, kx, ky = Layout.SnapPosition(dragging)
    Guide(guideX, gx, kx, true)
    Guide(guideY, gy, ky, false)
end

-- A piece's drag began (pieces call this from their OnDragStart).
function Layout.DragStart(key)
    local mover = movers[key]
    if editing and mover then
        dragging = mover.frame
        grid:SetScript("OnUpdate", Utils.Guard("layout guides", ShowGuides))
    end
end

-- Opening: the shade fades in, the center lines grow out of the middle, the grid ripples out
-- after them, the bar drops in from the top and the outlines pop in one after another.
local function AnimateIn()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    grid:SetAlpha(1)
    Kit.Tween(grid, 0, 1, 0.45, function(p)
        shade:SetAlpha(p)
        centerX:SetHeight(math.max(1, h * p))
        centerY:SetWidth(math.max(1, w * p))
    end, "quint")
    for _, line in ipairs(lines) do
        line.tex:SetAlpha(0)
        Kit.Tween(line.tex, 0, 1, 0.3, function(p) line.tex:SetAlpha(p) end, "out", 0.05 + line.distance * 0.35)
    end
    bar:Show()
    bar:SetAlpha(0)
    Kit.Tween(bar, 0, 1, 0.38, function(p)
        bar:SetAlpha(math.min(1, p))
        bar:ClearAllPoints()
        bar:SetPoint("TOP", 0, -14 + 40 * (1 - p))
    end, "back", 0.08)
    local i = 0
    for _, mover in pairs(movers) do
        local o = Outline(mover)
        o:Show()
        o:SetAlpha(0)
        Kit.Tween(o, 0, 1, 0.25, function(p) o:SetAlpha(p) end, "out", 0.15 + i * 0.06)
        i = i + 1
    end
end

-- Closing: the bar lifts away, the outlines fade, the grid folds back into its center lines.
-- Everything hides once it's gone (unless edit layout opened again meanwhile).
local function AnimateOut()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if grid and grid:IsShown() then
        Kit.Tween(grid, grid:GetAlpha(), 0, 0.28, function(p)
            grid:SetAlpha(p)
            centerX:SetHeight(math.max(1, h * p))
            centerY:SetWidth(math.max(1, w * p))
            if p <= 0 and not editing then
                grid:Hide()
            end
        end)
    end
    if bar and bar:IsShown() then
        Kit.Tween(bar, bar:GetAlpha(), 0, 0.2, function(p)
            bar:SetAlpha(p)
            bar:ClearAllPoints()
            bar:SetPoint("TOP", 0, -14 + 30 * (1 - p))
            if p <= 0 and not editing then
                bar:Hide()
            end
        end)
    end
    for _, mover in pairs(movers) do
        local o = mover.outline
        if o and o:IsShown() then
            Kit.Tween(o, o:GetAlpha(), 0, 0.16, function(p)
                o:SetAlpha(p)
                if p <= 0 and not editing then
                    o:Hide()
                end
            end)
        end
    end
end

function Layout.Start()
    if editing or InCombatLockdown() then
        if InCombatLockdown() then
            Utils.Print(L["Edit layout waits until combat ends."])
        end
        return
    end
    editing = true
    if not grid then
        BuildGrid()
        BuildBar()
    end
    local console = _G.OnAirConsole
    consoleWasOpen = console and console:IsShown() or false
    if consoleWasOpen and OA.UI then
        OA.UI.HideConsole()
    end
    grid:Show()
    for _, mover in pairs(movers) do
        if mover.opts.show then
            Utils.Guard("layout " .. mover.label, mover.opts.show)(true)
        end
    end
    AnimateIn()
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

-- Leaves edit layout. Each step runs on its own, so one piece failing can't keep the grid on
-- screen (the failure is reported once). `force` cleans up even when we think we're not editing.
function Layout.Stop(force)
    if not editing and not force then
        return
    end
    local was = editing
    editing = false
    dragging = nil
    if grid then
        grid:SetScript("OnUpdate", nil)
        guideX:Hide()
        guideY:Hide()
    end
    Utils.Guard("layout close", AnimateOut)()
    for key, mover in pairs(movers) do
        if mover.opts.show then
            Utils.Guard("layout " .. key, mover.opts.show)(false)
        end
    end
    if was and consoleWasOpen and OA.UI then
        consoleWasOpen = false
        Utils.Guard("layout console", OA.UI.ShowConsole)()
    end
    if OA.UI and OA.UI.Refresh then
        Utils.Guard("layout refresh", OA.UI.Refresh)()
    end
end

function Layout.Toggle()
    if editing then
        Layout.Stop()
    else
        Layout.Start()
    end
end

-- Called by a piece when a drag ends: snap it (its own way or to the guides), then save.
function Layout.Dropped(key)
    local mover = movers[key]
    if mover and dragging == mover.frame then
        dragging = nil
        if grid then
            grid:SetScript("OnUpdate", nil)
            ShowGuides()
        end
    end
    if not mover then
        return
    end
    if mover.opts.snap then
        mover.opts.snap()
    elseif editing then
        GridSnap(mover.frame)
    end
    if mover.opts.save then
        mover.opts.save()
    end
end
