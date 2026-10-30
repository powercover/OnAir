local _, OA = ...

-- The Deck: a small control bar for recording. Go live, hide the game's UI (the Deck stays: it
-- hangs off the world frame, not the UI), camera presets, orbit, mark a moment, edit the layout,
-- the console. Drag it anywhere; near an edge it sticks flush to it (vertical on the sides), near
-- two edges into the corner. It can stay put, fade after a moment, or tuck into its edge, leaving
-- a small tab with an arrow.
OA.Deck = {}

local Deck = OA.Deck
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local SIZE = 30      -- one button
local GRIP = 10      -- the drag strip
local SNAP = 40      -- how close to an edge counts as "at" it
local TAB = 14       -- what stays on screen when tucked

local deck, grip, tab, buttons
local tucked = 0     -- 0 = out, 1 = tucked away
local alphaNow = 1
local idle = 0

local function DB()
    return OA.db.deck
end

local function Vertical()
    local edge = DB().edge
    return edge == "LEFT" or edge == "RIGHT"
end

-- The Deck lives on the world frame, so it matches the UI's scale by itself.
local function SyncScale()
    if not deck then
        return
    end
    local ui = UIParent:GetEffectiveScale()
    local world = WorldFrame:GetEffectiveScale()
    if ui and world and world > 0 then
        deck:SetScale((DB().scale or 1) * ui / world)
    end
end

---------------------------------------------------------------------------------------------- buttons

local CAMERA_CYCLE = { "cinematic", "shoulder", "wide", "default" }

local function CameraNext()
    local cam = OA.db.camera
    local index = 0
    for i, key in ipairs(CAMERA_CYCLE) do
        if key == cam.preset then
            index = i
        end
    end
    if cam.mode == "off" then
        cam.mode = "always"
    end
    OA.Camera.UsePreset(CAMERA_CYCLE[index % #CAMERA_CYCLE + 1])
end

function Deck.ToggleUI()
    if InCombatLockdown() then
        Utils.Print(L["The game doesn't let addons hide the UI in combat. Use Alt+Z."])
        return
    end
    if type(SetUIVisibility) == "function" then
        pcall(SetUIVisibility, not UIParent:IsShown())
    end
    Deck.Refresh()
end

Deck.BUTTONS = {
    { key = "live", icon = "Live", text = L["Go live / end"],
        tip = function() return OA.live and L["Left: end the broadcast. Right: preview."] or L["Left: go live. Right: preview."] end,
        on = function() return OA.live end,
        click = function(button) if button == "RightButton" then OA.TogglePreview() else OA.Toggle() end end },
    { key = "ui", icon = "Hide", text = L["Hide the UI"],
        tip = function() return L["Hides the game's UI. The Deck stays."] end,
        on = function() return not UIParent:IsShown() end,
        click = function() Deck.ToggleUI() end },
    { key = "camera", icon = "Camera", text = L["Camera"],
        tip = function()
            local cam = OA.db.camera
            return string.format(L["Now: %s. Left: next preset. Right: camera off."],
                cam.mode == "off" and L["Off"] or cam.preset)
        end,
        on = function() return OA.Camera.Active() end,
        click = function(button)
            if button == "RightButton" then
                OA.db.camera.mode = "off"
                OA.Camera.Update()
            else
                CameraNext()
            end
        end },
    { key = "orbit", icon = "Orbit", text = L["Orbit"],
        tip = function() return L["Left: orbit left. Right: orbit right. The same click again or a middle click stops it."] end,
        on = function() return OA.Camera.IsOrbiting() end,
        click = function(button)
            if button == "MiddleButton" then
                OA.Camera.StopOrbit()
            else
                OA.Camera.ToggleOrbit(button == "RightButton" and "right" or "left")
            end
        end },
    { key = "mark", icon = "Flag", text = L["Mark a moment"],
        tip = function() return L["Adds a moment at the current timecode."] end,
        on = function() return false end,
        click = function() OA.Moments.Mark() end },
    { key = "layout", icon = "Group", text = L["Edit layout"],
        tip = function() return L["Move the badge, stream chat and Deck on a grid."] end,
        on = function() return OA.Layout and OA.Layout.IsEditing() end,
        click = function() OA.Layout.Toggle() end },
    { key = "console", icon = "Names", text = L["Console"],
        tip = function() return L["Opens the OnAir console (and the UI, if hidden)."] end,
        on = function() return false end,
        click = function()
            if not UIParent:IsShown() and not InCombatLockdown() and type(SetUIVisibility) == "function" then
                pcall(SetUIVisibility, true)
            end
            OA.UI.ToggleConsole()
        end },
}

local function Shown(spec)
    return DB().buttons[spec.key] ~= false
end

---------------------------------------------------------------------------------------------- placing

-- Screen size in the Deck's own units.
local function Screen()
    local ratio = WorldFrame:GetEffectiveScale() / deck:GetEffectiveScale()
    return WorldFrame:GetWidth() * ratio, WorldFrame:GetHeight() * ratio
end

local function Place()
    local db = DB()
    local pos = db.pos
    deck:ClearAllPoints()
    if not pos then
        deck:SetPoint("TOP", WorldFrame, "TOP", 0, -8)
        return
    end
    local w, h = deck:GetWidth(), deck:GetHeight()
    local x, y = pos.x or 0, pos.y or 0
    -- Tucked: slide out of the screen along the docked edge.
    local hide = tucked
    if hide > 0 and db.edge then
        local depth = (Vertical() and w or h) - TAB
        if db.edge == "LEFT" then
            x = x - depth * hide
        elseif db.edge == "RIGHT" then
            x = x + depth * hide
        elseif db.edge == "TOP" then
            y = y + depth * hide
        else
            y = y - depth * hide
        end
    end
    deck:SetPoint(pos.point or "BOTTOMLEFT", WorldFrame, pos.point or "BOTTOMLEFT", x, y)
end

local function Layout()
    local list = {}
    for _, spec in ipairs(Deck.BUTTONS) do
        local b = buttons[spec.key]
        if Shown(spec) then
            list[#list + 1] = b
            b:Show()
        else
            b:Hide()
        end
    end
    local vertical = Vertical()
    local length = GRIP + #list * SIZE + 4
    if vertical then
        deck:SetSize(SIZE + 6, length)
    else
        deck:SetSize(length, SIZE + 6)
    end
    grip:ClearAllPoints()
    if vertical then
        grip:SetPoint("TOPLEFT", 3, -2)
        grip:SetPoint("TOPRIGHT", -3, -2)
        grip:SetHeight(GRIP - 2)
    else
        grip:SetPoint("TOPLEFT", 2, -3)
        grip:SetPoint("BOTTOMLEFT", 2, 3)
        grip:SetWidth(GRIP - 2)
    end
    for i, b in ipairs(list) do
        b:ClearAllPoints()
        if vertical then
            b:SetPoint("TOP", deck, "TOP", 0, -(GRIP + (i - 1) * SIZE))
        else
            b:SetPoint("LEFT", deck, "LEFT", GRIP + (i - 1) * SIZE + 1, 0)
        end
    end
    -- The tab sits on the inner side of the docked edge, where the Deck peeks out when tucked.
    tab:ClearAllPoints()
    local edge = DB().edge
    if edge == "LEFT" then
        tab:SetPoint("TOPRIGHT")
        tab:SetPoint("BOTTOMRIGHT")
        tab:SetWidth(TAB)
        tab.arrow:SetRotation(math.rad(90))
    elseif edge == "RIGHT" then
        tab:SetPoint("TOPLEFT")
        tab:SetPoint("BOTTOMLEFT")
        tab:SetWidth(TAB)
        tab.arrow:SetRotation(math.rad(-90))
    elseif edge == "TOP" then
        tab:SetPoint("BOTTOMLEFT")
        tab:SetPoint("BOTTOMRIGHT")
        tab:SetHeight(TAB)
        tab.arrow:SetRotation(0)
    else
        tab:SetPoint("TOPLEFT")
        tab:SetPoint("TOPRIGHT")
        tab:SetHeight(TAB)
        tab.arrow:SetRotation(math.rad(180))
    end
    Place()
end

-- After a drag: stick to an edge or a corner when close, else stay where dropped.
local function Snap()
    local db = DB()
    -- In edit layout, the grid and the center lines count too (along the docked edge).
    local gridX, gridY
    if OA.Layout and OA.Layout.IsEditing() then
        gridX, gridY = OA.Layout.SnapPosition(deck)
    end
    local sw, sh = Screen()
    local w, h = deck:GetWidth(), deck:GetHeight()
    local left, bottom = deck:GetLeft() or 0, deck:GetBottom() or 0
    local right, top = left + w, bottom + h
    local dLeft, dRight, dBottom, dTop = left, sw - right, bottom, sh - top
    local nearX = math.min(dLeft, dRight) < SNAP
    local nearY = math.min(dBottom, dTop) < SNAP
    local edge
    if nearX and (not nearY or math.min(dLeft, dRight) <= math.min(dBottom, dTop)) then
        edge = dLeft <= dRight and "LEFT" or "RIGHT"
    elseif nearY then
        edge = dBottom <= dTop and "BOTTOM" or "TOP"
    end
    local wasVertical = Vertical()
    db.edge = edge
    if Vertical() ~= wasVertical then
        Layout()
        w, h = deck:GetWidth(), deck:GetHeight()
    end
    local x = math.max(0, math.min(gridX or left, sw - w))
    local y = math.max(0, math.min(gridY or bottom, sh - h))
    if nearX then
        x = dLeft <= dRight and 0 or sw - w
    end
    if nearY then
        y = dBottom <= dTop and 0 or sh - h
    end
    db.pos = { point = "BOTTOMLEFT", x = x, y = y }
    tucked = 0
    Layout()
end

---------------------------------------------------------------------------------------------- hiding

local function SetTucked(target)
    if math.abs(tucked - target) < 0.001 then
        return
    end
    Kit.Tween(tab, tucked, target, 0.25, function(p)
        tucked = p
        Place()
        tab:SetAlpha(p)
    end)
end

local function SetAlphaTo(target)
    if math.abs(alphaNow - target) < 0.001 then
        return
    end
    Kit.Tween(deck, alphaNow, target, target < alphaNow and 0.6 or 0.15, function(p)
        alphaNow = p
        deck:SetAlpha(p)
    end)
end

local function Watch(_, elapsed)
    local db = DB()
    if OA.Layout and OA.Layout.IsEditing() then
        SetAlphaTo(1)
        SetTucked(0)
        return
    end
    if deck:IsMouseOver(8, -8, -8, 8) then
        idle = 0
        SetAlphaTo(1)
        SetTucked(0)
        return
    end
    idle = idle + elapsed
    if idle < (db.delay or 2) then
        return
    end
    if db.hide == "tuck" and db.edge then
        SetTucked(1)
    elseif db.hide == "fade" or db.hide == "tuck" then
        SetAlphaTo(db.fadeTo or 0.2)
    end
end

---------------------------------------------------------------------------------------------- build

local function Paint()
    for _, spec in ipairs(Deck.BUTTONS) do
        local b = buttons[spec.key]
        local ok, on = pcall(spec.on)
        b.icon:SetVertexColor(unpack(ok and on and C.red or C.text))
    end
end

local function Build()
    deck = CreateFrame("Frame", "OnAirDeck", WorldFrame)
    deck:SetFrameStrata("DIALOG")
    deck:SetClampedToScreen(false)
    deck:SetMovable(true)
    deck:EnableMouse(true)
    deck:RegisterForDrag("LeftButton")
    local bg = Kit.Rect(deck, { 0.05, 0.055, 0.063, 0.94 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(deck, C.line)
    local stripe = Kit.Rect(deck, C.red, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("TOPRIGHT")
    stripe:SetHeight(1)

    grip = CreateFrame("Frame", nil, deck)
    for i = 1, 3 do
        local dot = Kit.Shape(grip, "Dot", C.faint, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", grip, "CENTER", 0, (i - 2) * 6)
        grip["dot" .. i] = dot
    end

    tab = CreateFrame("Frame", nil, deck)
    local tabBg = Kit.Rect(tab, C.raised, "ARTWORK")
    tabBg:SetAllPoints()
    tab.arrow = Kit.Icon(tab, "Chevron", 10, C.text)
    tab.arrow:SetPoint("CENTER")
    local tabDot = Kit.Shape(tab, "Dot", C.red, "OVERLAY")
    tabDot:SetSize(5, 5)
    tabDot:SetPoint("CENTER", tab.arrow, "CENTER", 0, 0)
    tabDot:SetAlpha(0.8)
    tab:SetAlpha(0)

    local function StartDrag()
        if not (OA.Layout and OA.Layout.IsEditing()) and DB().locked then
            return
        end
        deck:StartMoving()
        OA.Layout.DragStart("deck")
    end
    local function StopDrag()
        deck:StopMovingOrSizing()
        Snap()
        OA.Layout.Dropped("deck")
    end
    deck:SetScript("OnDragStart", StartDrag)
    deck:SetScript("OnDragStop", StopDrag)

    buttons = {}
    for _, spec in ipairs(Deck.BUTTONS) do
        local b = CreateFrame("Button", nil, deck)
        b:SetSize(SIZE, SIZE)
        b:RegisterForClicks("AnyUp")
        b:RegisterForDrag("LeftButton")
        local hl = Kit.Rect(b, C.hover, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetAlpha(0)
        b.icon = Kit.Icon(b, spec.icon, 16, C.text)
        b.icon:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            hl:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(spec.text, 1, 1, 1)
            GameTooltip:AddLine(spec.tip(), nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            hl:SetAlpha(0)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(_, mouse)
            spec.click(mouse)
            Paint()
        end)
        b:SetScript("OnDragStart", StartDrag)
        b:SetScript("OnDragStop", StopDrag)
        buttons[spec.key] = b
    end
    deck:SetScript("OnUpdate", Utils.Guard("deck", Watch))
    deck:SetScript("OnEvent", SyncScale)
    deck:RegisterEvent("UI_SCALE_CHANGED")
    deck:RegisterEvent("DISPLAY_SIZE_CHANGED")
    SyncScale()
    Layout()
end

function Deck.Refresh()
    local db = DB()
    local show = db.show == "always" or (db.show == "live" and OA.live)
        or (OA.Layout and OA.Layout.IsEditing())
    if show and not deck then
        Build()
    end
    if not deck then
        return
    end
    deck:SetShown(show and true or false)
    if show then
        SyncScale()
        Layout()
        Paint()
        if db.hide == "never" then
            alphaNow = 1
            deck:SetAlpha(1)
        end
    end
end

function Deck.ResetPosition()
    DB().pos = nil
    DB().edge = nil
    tucked = 0
    Deck.Refresh()
end

function Deck.Frame()
    if not deck then
        Build()
    end
    return deck
end

function Deck.AfterDrag()
    Snap()
end
