local _, OA = ...

-- Edit layout: a grid over the screen, and everything OnAir puts on it (the stream chat, the
-- Deck) unlocked and outlined so it can be dragged into place. While you drag, a piece sticks to
-- lines: any side or its middle onto a guide (the screen's center lines and edges, the other
-- pieces, the game's own frames if wanted), its sides onto the grid. Snapping is Free, Guides or
-- Grid; Shift drags freely. Done (or Esc) puts the console back.
OA.Layout = {}

local Layout = OA.Layout
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local RANGE = 12     -- how close (in UI pixels) an anchor is pulled onto a guide
local GRID_RANGE = 8 -- ... and a side onto a grid line
local STEP = 4       -- in Grid mode, off the lines, positions round to this
local GRID_ALPHA = 0.07
local SHADE_ALPHA = 0.35
Layout.GRID_SIZES = { 16, 32, 64 }

-- The game's own frames a piece can line up with (when they're on screen).
local UI_FRAMES = {
    "MinimapCluster", "PlayerFrame", "TargetFrame", "FocusFrame", "ChatFrame1", "ObjectiveTrackerFrame",
    "BuffFrame", "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MicroMenuContainer", "BagsBar", "PartyFrame",
    "CompactRaidFrameContainer", "PlayerCastingBarFrame", "OnAirConsole",
    "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target", "EllesmereUIUnitFrames_Focus",
}

local editing = false
local movers = {}
local grid, bar, shade
local lines = { count = 0 } -- grid lines: { tex, distance from the center }
local centerX, centerY
local guideX, guideY
local drag                 -- the piece being dragged: frame and where the drag began
local consoleWasOpen = false
local stale = false        -- the skin changed since the grid was built

Kit.OnSkin(function() stale = true end)

local function Options()
    local db = OA.db
    db.layout = db.layout or {}
    local o = db.layout
    -- Guides is the default; a choice of your own (picked) stays.
    if not o.picked or (o.snap ~= "free" and o.snap ~= "guides" and o.snap ~= "grid") then
        o.snap = "guides"
    end
    o.grid = tonumber(o.grid) or 32
    if o.ui == nil then
        o.ui = true
    end
    return o
end
Layout.Options = Options

function Layout.IsEditing()
    return editing
end

-- Locked: the pieces stay put (no dragging) outside edit layout.
function Layout.Locked()
    return OA.db ~= nil and OA.db.layout ~= nil and OA.db.layout.locked == true
end

-- A piece of the layout. opts.show(on) makes it visible for editing (and puts it back after);
-- opts.save() stores where it was dropped; opts.snap (optional) replaces the plain snap.
function Layout.Register(key, frame, label, opts)
    movers[key] = { frame = frame, label = label, opts = opts or {} }
end

---------------------------------------------------------------------------------------------- the grid

-- (Re)draws the grid lines for the current size, out from the center so the center lines sit
-- exactly in the middle. Lines are kept and reused when the size changes.
local function DrawGrid()
    local o = Options()
    local size = o.grid
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = w / 2, h / 2
    local alpha = o.snap == "grid" and GRID_ALPHA or GRID_ALPHA * 0.5
    local n = 0
    local function Line(vertical, offset)
        n = n + 1
        local line = lines[n]
        if not line then
            line = { tex = grid:CreateTexture(nil, "ARTWORK") }
            lines[n] = line
        end
        local t = line.tex
        t:ClearAllPoints()
        t:SetColorTexture(C.text[1], C.text[2], C.text[3], alpha)
        if vertical then
            t:SetWidth(1)
            t:SetPoint("TOP", grid, "TOPLEFT", cx + offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOMLEFT", cx + offset, 0)
        else
            t:SetHeight(1)
            t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, cy + offset)
            t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, cy + offset)
        end
        t:Show()
        line.distance = math.abs(offset) / math.max(cx, cy)
    end
    for x = size, cx, size do
        Line(true, x)
        Line(true, -x)
    end
    for y = size, cy, size do
        Line(false, y)
        Line(false, -y)
    end
    for i = n + 1, #lines do
        lines[i].tex:Hide()
    end
    lines.count = n
end

local function BuildGrid()
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    local cx, cy = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    shade = Kit.Rect(grid, { 0, 0, 0, SHADE_ALPHA }, "BACKGROUND")
    shade:SetAllPoints()
    -- The center lines grow out from the middle when the grid opens.
    centerX = grid:CreateTexture(nil, "ARTWORK", nil, 1)
    centerX:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.45)
    centerX:SetWidth(1)
    centerX:SetPoint("CENTER", grid, "BOTTOMLEFT", cx, cy)
    centerY = grid:CreateTexture(nil, "ARTWORK", nil, 1)
    centerY:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.45)
    centerY:SetHeight(1)
    centerY:SetPoint("CENTER", grid, "BOTTOMLEFT", cx, cy)
    -- The guides that light up where a dragged piece sticks.
    guideX = grid:CreateTexture(nil, "OVERLAY")
    guideX:SetWidth(2)
    guideX:Hide()
    guideY = grid:CreateTexture(nil, "OVERLAY")
    guideY:SetHeight(2)
    guideY:Hide()
    -- The theme's touches: viewfinder brackets on the screen's corners and its thirds lines, the
    -- slate's clapper stripes along the top, the vision mixer's wipe.
    local look = Kit.Theme()
    if look.corners then
        grid.corners = Kit.Corners(grid, 80, 3, C.accent, 24, "ARTWORK")
    end
    if look.thirds then
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        for i = 1, 2 do
            local v = grid:CreateTexture(nil, "ARTWORK", nil, 1)
            v:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
            v:SetWidth(1)
            v:SetPoint("TOP", grid, "TOPLEFT", w * i / 3, 0)
            v:SetPoint("BOTTOM", grid, "BOTTOMLEFT", w * i / 3, 0)
            local hz = grid:CreateTexture(nil, "ARTWORK", nil, 1)
            hz:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.3)
            hz:SetHeight(1)
            hz:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, h * i / 3)
            hz:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, h * i / 3)
        end
    end
    if look.stripes then
        grid.band = Kit.Band(grid, "Stripes", C.text, "ARTWORK")
        grid.band:SetPoint("LEFT")
        grid.band:SetPoint("RIGHT")
        grid.band:SetHeight(14)
        grid.band:SetAlpha(0.8)
    end
    if look.keys then
        grid.wipe = grid:CreateTexture(nil, "ARTWORK", nil, 2)
        grid.wipe:SetColorTexture(1, 1, 1, 0.12)
        grid.wipe:SetWidth(160)
        grid.wipe:SetPoint("TOP")
        grid.wipe:SetPoint("BOTTOM")
    end
    DrawGrid()
    grid:Hide()
end

---------------------------------------------------------------------------------------------- the bar

local function BuildBar()
    bar = CreateFrame("Frame", "OnAirLayoutBar", UIParent)
    bar:SetSize(724, 44)
    bar:SetPoint("TOP", 0, -14)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:EnableMouse(true)
    local bg = Kit.Rect(bar, C.bg, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(bar, C.redDeep)
    local dot = Kit.Shape(bar, "Dot", C.red, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 14, 0)
    local text = Kit.Text(bar, 13, C.text)
    text:SetPoint("LEFT", 30, 0)
    text:SetText(L["EDIT LAYOUT"])

    local snap = Kit.Segmented(bar, {
        { value = "free", text = L["Free"] },
        { value = "guides", text = L["Guides"] },
        { value = "grid", text = L["Grid"] },
    }, 200, function() return Options().snap end, function(v) Layout.SetOption("snap", v) end)
    snap:SetPoint("LEFT", 140, 0)
    local sizes = {}
    for _, size in ipairs(Layout.GRID_SIZES) do
        sizes[#sizes + 1] = { value = size, text = tostring(size) }
    end
    local size = Kit.Segmented(bar, sizes, 120, function() return Options().grid end,
        function(v) Layout.SetOption("grid", v) end)
    size:SetPoint("LEFT", snap, "RIGHT", 10, 0)
    local ui = Kit.Switch(bar, function() return Options().ui end, function(v) Layout.SetOption("ui", v) end)
    ui:SetPoint("LEFT", size, "RIGHT", 16, 0)
    local uiText = Kit.Text(bar, 12, C.muted)
    uiText:SetPoint("LEFT", ui, "RIGHT", 8, 0)
    uiText:SetText(L["Game frames"])

    local done = Kit.Button(bar, L["Done"], 80, 28, "primary", function()
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
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
        GameTooltip:SetText(L["Edit layout"], 1, 1, 1)
        GameTooltip:AddLine(L["Free: no snapping. Guides: sides and middles stick to the center lines, the screen edges and the other pieces. Grid: the grid too. Game frames: line up with your unit frames, minimap, chat... Hold Shift to drag freely."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function bar.Refresh()
        snap:Refresh(true)
        size:Refresh(true)
        ui:Refresh(true)
        size:SetAlpha(Options().snap == "grid" and 1 or 0.45)
    end
    bar.Refresh()
    bar:Hide()
end

function Layout.SetOption(key, value)
    local o = Options()
    o[key] = value
    if key == "snap" then
        o.picked = true
    end
    if grid then
        DrawGrid()
        for i = 1, lines.count do
            lines[i].tex:SetAlpha(1)
        end
    end
    if bar then
        bar.Refresh()
    end
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
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

---------------------------------------------------------------------------------------------- snapping

-- A frame's box in UIParent's units: left, bottom, width, height (and the scale to get back).
local function Box(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then
        return nil
    end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * k, bottom * k, frame:GetWidth() * k, frame:GetHeight() * k, k
end

local function AddBox(list, frame, vertical, kind)
    local left, bottom, w, h = Box(frame)
    if left then
        local start, length = left, w
        if vertical then
            start, length = bottom, h
        end
        list[#list + 1] = { start, kind }
        list[#list + 1] = { start + length / 2, kind }
        list[#list + 1] = { start + length, kind }
    end
end

-- The guides on one axis: the screen's center line ("center") and edges ("edge"), the sides and
-- middles of the other visible pieces ("piece") and, if wanted, of the game's frames ("ui").
local function Guides(frame, vertical)
    local size = vertical and UIParent:GetHeight() or UIParent:GetWidth()
    local list = { { size / 2, "center" }, { 0, "edge" }, { size, "edge" } }
    if Kit.Theme().thirds then
        list[#list + 1] = { size / 3, "thirds" }
        list[#list + 1] = { size * 2 / 3, "thirds" }
    end
    for _, mover in pairs(movers) do
        local other = mover.frame
        if other ~= frame and other:IsVisible() then
            AddBox(list, other, vertical, "piece")
        end
    end
    if Options().ui then
        for _, name in ipairs(UI_FRAMES) do
            local other = _G[name]
            if type(other) == "table" and other ~= frame and type(other.IsVisible) == "function" then
                pcall(function()
                    if not other:IsForbidden() and other:IsVisible() then
                        AddBox(list, other, vertical, "ui")
                    end
                end)
            end
        end
    end
    return list
end

-- One axis: the closest guide any anchor reaches wins; only with no guide in reach, a side goes
-- onto the closest grid line (gridSize given). Returns the new start, the line and its kind.
local function Axis(start, size, center, guides, gridSize)
    local best, line, kind, dist = start, nil, nil, RANGE
    if gridSize then
        best = math.floor(start / STEP + 0.5) * STEP
    end
    for _, offset in ipairs({ 0, size / 2, size }) do
        local anchor = start + offset
        for _, guide in ipairs(guides) do
            local d = math.abs(anchor - guide[1])
            if d < dist then
                best, line, kind, dist = guide[1] - offset, guide[1], guide[2], d
            end
        end
    end
    if gridSize and not line then
        dist = GRID_RANGE
        for _, offset in ipairs({ 0, size }) do
            local anchor = start + offset
            local gridLine = center + math.floor((anchor - center) / gridSize + 0.5) * gridSize
            local d = math.abs(anchor - gridLine)
            if d < dist then
                best, line, kind, dist = gridLine - offset, gridLine, "grid", d
            end
        end
    end
    return best, line, kind
end

-- Snaps a box (UI units). Returns left and bottom in the frame's own units (ready for SetPoint),
-- then the lines it snapped to (UI units, or nil) and their kinds.
local function SnapBox(frame, left, bottom, w, h, k)
    local o = Options()
    if o.snap == "free" or IsShiftKeyDown() then
        return left / k, bottom / k
    end
    local gridSize = o.snap == "grid" and o.grid or nil
    local x, gx, kx = Axis(left, w, UIParent:GetWidth() / 2, Guides(frame, false), gridSize)
    local y, gy, ky = Axis(bottom, h, UIParent:GetHeight() / 2, Guides(frame, true), gridSize)
    return x / k, y / k, gx, gy, kx, ky
end

-- Where a frame would snap from where it is now.
function Layout.SnapPosition(frame)
    local left, bottom, w, h, k = Box(frame)
    if not left then
        return nil
    end
    return SnapBox(frame, left, bottom, w, h, k)
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
    center = C.red, -- (the theme's own tables: they're painted at login, after this file loads)
    piece = { C.amber[1], C.amber[2], C.amber[3], 0.9 },
    ui = { 0.35, 0.72, 1, 0.9 },
    thirds = C.accent,
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

---------------------------------------------------------------------------------------------- dragging

local function Cursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

-- Every frame of a drag: follow the cursor, stick to the lines, light them.
local function Follow()
    if not drag then
        return
    end
    local cx, cy = Cursor()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local left = math.max(0, math.min(drag.left + cx - drag.cx, sw - drag.w))
    local bottom = math.max(0, math.min(drag.bottom + cy - drag.cy, sh - drag.h))
    local x, y, gx, gy, kx, ky = SnapBox(drag.frame, left, bottom, drag.w, drag.h, drag.k)
    drag.frame:ClearAllPoints()
    drag.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    Guide(guideX, gx, kx, true)
    Guide(guideY, gy, ky, false)
end

-- The frame edit layout is dragging right now (pieces leave their position alone meanwhile).
function Layout.Dragging()
    return drag and drag.frame
end

local function EndDrag()
    drag = nil
    if grid then
        grid:SetScript("OnUpdate", nil)
        guideX:Hide()
        guideY:Hide()
    end
end

-- A piece's drag began (pieces call this from their OnDragStart, after StartMoving). In edit
-- layout OnAir moves it instead of the game, so it can stick to lines while you drag.
function Layout.DragStart(key)
    local mover = movers[key]
    if not (editing and mover) then
        return
    end
    local frame = mover.frame
    frame:StopMovingOrSizing()
    local left, bottom, w, h, k = Box(frame)
    if not left then
        return
    end
    local cx, cy = Cursor()
    drag = { frame = frame, left = left, bottom = bottom, w = w, h = h, k = k, cx = cx, cy = cy }
    grid:SetScript("OnUpdate", Utils.Guard("layout drag", Follow))
end

---------------------------------------------------------------------------------------------- open / close

-- Opening: the shade fades in, the center lines grow out of the middle, the grid ripples out
-- after them, the bar drops in from the top and the outlines pop in one after another.
local function AnimateIn()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    grid:SetAlpha(1)
    Kit.Tween(grid, 0, 1, 0.45, function(p)
        shade:SetAlpha(p)
        centerX:SetHeight(math.max(1, h * p))
        centerY:SetWidth(math.max(1, w * p))
        if grid.corners then
            grid.corners.Place(24 - 90 * (1 - p))
        end
        if grid.band then
            grid.band:ClearAllPoints()
            grid.band:SetPoint("TOPLEFT", 0, 14 * (1 - p))
            grid.band:SetPoint("TOPRIGHT", 0, 14 * (1 - p))
        end
        if grid.wipe then
            grid.wipe:SetPoint("LEFT", grid, "LEFT", -160 + (w + 160) * p, 0)
            grid.wipe:SetAlpha(p < 1 and 1 or 0)
        end
    end, "quint")
    for i = 1, lines.count do
        local line = lines[i]
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
    -- A new skin since the last time: the grid, the bar and the outlines are drawn again.
    if grid and stale then
        grid:Hide()
        bar:SetScript("OnHide", nil)
        bar:Hide()
        grid, bar, shade = nil, nil, nil
        lines = { count = 0 }
        for _, mover in pairs(movers) do
            if mover.outline then
                mover.outline:Hide()
                mover.outline = nil
            end
        end
    end
    stale = false
    -- Build first: the new bar hides itself at the end, and its OnHide (Esc) would end an edit
    -- layout that had already begun.
    if not grid then
        BuildGrid()
        BuildBar()
    end
    editing = true
    DrawGrid()
    bar.Refresh()
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
    EndDrag()
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

-- Called by a piece when a drag ends: snap it (its own way or to the lines), then save.
function Layout.Dropped(key)
    local mover = movers[key]
    if mover and drag and drag.frame == mover.frame then
        Follow()
        EndDrag()
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
