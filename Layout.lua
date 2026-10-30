local _, OA = ...

-- Edit layout: a grid over the screen, and everything OnAir puts on it (the ON AIR badge, the
-- stream chat, the Deck) unlocked and outlined so it can be dragged into place. Drops snap to the
-- grid. Done (or Esc) puts the console back.
OA.Layout = {}

local Layout = OA.Layout
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local GRID = 32
local SNAP = 8

local editing = false
local movers = {}
local grid, bar
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
    local function Line(vertical, offset, color, alpha)
        local t = grid:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(color[1], color[2], color[3], alpha)
        if vertical then
            t:SetWidth(1)
            t:SetPoint("TOP", grid, "TOPLEFT", cx + offset, 0)
            t:SetPoint("BOTTOM", grid, "BOTTOMLEFT", cx + offset, 0)
        else
            t:SetHeight(1)
            t:SetPoint("LEFT", grid, "BOTTOMLEFT", 0, cy + offset)
            t:SetPoint("RIGHT", grid, "BOTTOMRIGHT", 0, cy + offset)
        end
    end
    local shade = Kit.Rect(grid, { 0, 0, 0, 0.35 }, "BACKGROUND")
    shade:SetAllPoints()
    for x = GRID, cx, GRID do
        Line(true, x, { 1, 1, 1 }, 0.07)
        Line(true, -x, { 1, 1, 1 }, 0.07)
    end
    for y = GRID, cy, GRID do
        Line(false, y, { 1, 1, 1 }, 0.07)
        Line(false, -y, { 1, 1, 1 }, 0.07)
    end
    Line(true, 0, C.red, 0.45)
    Line(false, 0, C.red, 0.45)
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
        Layout.Stop()
    end)
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

-- Round a frame's spot onto the grid (in UIParent's coordinates).
local function GridSnap(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left then
        return
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = math.floor(left * scale / SNAP + 0.5) * SNAP
    local y = math.floor(bottom * scale / SNAP + 0.5) * SNAP
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end
Layout.GridSnap = GridSnap

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
    if consoleWasOpen then
        console:Hide()
    end
    grid:Show()
    grid:SetAlpha(0)
    Kit.Tween(grid, 0, 1, 0.25, function(p) grid:SetAlpha(p) end)
    bar:Show()
    for _, mover in pairs(movers) do
        if mover.opts.show then
            mover.opts.show(true)
        end
        Outline(mover):Show()
    end
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

function Layout.Stop()
    if not editing then
        return
    end
    editing = false
    grid:Hide()
    bar:Hide()
    for _, mover in pairs(movers) do
        if mover.outline then
            mover.outline:Hide()
        end
        if mover.opts.show then
            mover.opts.show(false)
        end
    end
    if consoleWasOpen and OA.UI then
        OA.UI.ShowConsole()
    end
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

function Layout.Toggle()
    if editing then
        Layout.Stop()
    else
        Layout.Start()
    end
end

-- Called by a piece when a drag ends: snap it (its own way or to the grid), then save.
function Layout.Dropped(key)
    local mover = movers[key]
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
