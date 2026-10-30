local _, OA = ...

-- The Deck: a small control bar for recording. Go live, hide the game's UI (the Deck stays: it
-- hangs off the world frame, not the UI), camera presets, orbit, mark a moment, edit the layout,
-- the console. Drag it anywhere; near an edge it sticks flush to it (vertical on the sides), near
-- two edges into the corner. It can stay put, fade after a moment, or tuck into its edge, leaving
-- a small tab with an arrow. Rest the mouse on a button for a second and a small panel opens
-- with the settings worth changing mid-recording (orbit speed, camera preset, ...).
OA.Deck = {}

local Deck = OA.Deck
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

local SNAP = 40      -- how close to an edge counts as "at" it
local TAB = 14       -- what stays on screen when tucked

local deck, face, tab, buttons
local faces = {}     -- skin key -> the Deck's face in that skin
local tucked = 0     -- 0 = out, 1 = tucked away
local alphaNow = 1
local idle = 0
local PanelWatch -- the quick panels' watcher (below)

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
    { key = "layout", icon = "Layout", text = L["Edit layout"],
        tip = function() return L["Move the stream chat and the Deck on a grid."] end,
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
    if OA.Layout and OA.Layout.Dragging() == deck then
        return
    end
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
    -- The face sizes each button (icons are square, a label is as wide as its word); the
    -- buttons sit in a line along the Deck, centered across it.
    local vertical = Vertical()
    local along, across = face.lead + face.pad, 0
    local sizes = {}
    for i, b in ipairs(list) do
        local w, h = face.Size(b, vertical)
        b:SetSize(w, h)
        sizes[i] = vertical and h or w
        across = math.max(across, vertical and w or h)
    end
    local x = along
    for i, b in ipairs(list) do
        b:ClearAllPoints()
        if vertical then
            b:SetPoint("TOP", deck, "TOP", 0, -x)
        else
            b:SetPoint("LEFT", deck, "LEFT", x, 0)
        end
        x = x + sizes[i] + (i < #list and face.gap or 0)
    end
    local length = x + face.pad
    if vertical then
        deck:SetSize(across + face.pad * 2, length)
    else
        deck:SetSize(length, across + face.pad * 2)
    end
    if face.Arrange then
        face.Arrange(vertical)
    end
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
    -- (In edit layout the Deck already stuck to the guides while it was dragged.)
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
    local x = math.max(0, math.min(left, sw - w))
    local y = math.max(0, math.min(bottom, sh - h))
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
    PanelWatch(elapsed)
    if OA.Layout and OA.Layout.IsEditing() then
        SetAlphaTo(1)
        SetTucked(0)
        return
    end
    if deck:IsMouseOver(8, -8, -8, 8) or Deck.PanelOpen() then
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

---------------------------------------------------------------------------------------------- quick panels

-- Rest the mouse on a button for a second: a small panel opens beside it with what's worth
-- changing on the fly. It stays while the mouse is on the button or the panel; moving to another
-- button with a panel switches over at once. Not in edit layout.
local PANEL_W = 250
local HOVER_DELAY = 1
local LINGER = 0.35

local panel, panelKey
local hoverKey, hoverTime, away, tick = nil, 0, 0, 0
local contents = {}

-- A little vertical stack for a panel's controls.
local function Stack(frame)
    local y = -34
    local stack = {}
    function stack.Add(widget, height, gap)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
        y = y - (height or widget:GetHeight()) - (gap or 10)
        return widget
    end
    function stack.Height()
        return -y + 2
    end
    return stack
end

local W = PANEL_W - 24

-- The panel's controls, drawn by the active skin.
local function Check(frame, stack, title, get, set)
    return stack.Add(Kit.Skin().Check(frame, { title = title, get = get, set = set }, W), nil, 8)
end

local function Choice(frame, stack, options, get, set)
    return stack.Add(Kit.Skin().Choice(frame, { options = options, get = get, set = set }, W), nil, 12)
end

local function Slider(frame, stack, spec)
    return stack.Add(Kit.Skin().Slider(frame, spec, W), nil, 8)
end

local function Button(frame, stack, text, kind, click)
    return stack.Add(Kit.Skin().Button(frame, { text = text, kind = kind, width = W, click = click }), nil, 10)
end

local SHORT_PRESETS = {
    { value = "default", text = L["Default"] },
    { value = "cinematic", text = L["Cinema"] },
    { value = "shoulder", text = L["Shoulder"] },
    { value = "wide", text = L["Wide"] },
}

local PANELS = {}

PANELS.live = function(frame, stack, onRefresh)
    local skin = Kit.Skin()
    local clock = stack.Add(skin.Readout(frame, 22), 24, 2)
    local sub = stack.Add(skin.Label(frame, 12, C.muted), 14, 12)
    local preview = Check(frame, stack, L["Preview"],
        function() return OA.live and OA.rehearsal end,
        function() OA.TogglePreview() end)
    local chat = Check(frame, stack, L["Stream chat"],
        function() return OA.db.stream.enabled ~= false end,
        function(v)
            OA.db.stream.enabled = v
            OA.StreamChat.Update()
        end)
    onRefresh(function()
        if OA.live then
            clock:SetText(OA.Moments.Format(OA.Moments.Elapsed()))
            clock:SetTextColor(unpack(OA.rehearsal and C.amber or C.red))
            sub:SetText(string.format(L["%s  -  %d masked"], Kit.Word(OA.rehearsal and "preview" or "live"), OA.Names.Count()))
        else
            clock:SetText("00:00")
            clock:SetTextColor(unpack(C.faint))
            sub:SetText(Kit.Word("off"))
        end
        preview:Refresh(true)
        chat:Refresh(true)
        -- No preview while really live: end the broadcast first.
        preview:SetAlpha((OA.live and not OA.rehearsal) and 0.4 or 1)
    end)
end

PANELS.camera = function(frame, stack, onRefresh)
    local Camera = OA.Camera
    local cam = OA.db.camera
    local mode = Choice(frame, stack, {
        { value = "off", text = L["Off"] },
        { value = "always", text = L["Always"] },
        { value = "live", text = L["While live"] },
    }, function() return cam.mode end, function(v)
        cam.mode = v
        Camera.Update()
    end)
    local preset = Choice(frame, stack, SHORT_PRESETS, function() return cam.preset end, function(v)
        if cam.mode == "off" then
            cam.mode = "always"
        end
        Camera.UsePreset(v)
    end)
    local sliders = {}
    for _, key in ipairs({ "zoom", "fov", "shoulder" }) do
        for _, setting in ipairs(Camera.SETTINGS) do
            if setting.key == key then
                sliders[#sliders + 1] = Slider(frame, stack, { label = setting.label, min = setting.min, max = setting.max,
                    step = setting.step, format = setting.format,
                    get = function() return Camera.Get(key) end,
                    set = function(v) Camera.Set(key, v) end })
            end
        end
    end
    onRefresh(function()
        mode:Refresh(true)
        preset:Refresh(true)
        for _, slider in ipairs(sliders) do
            slider:Refresh()
        end
    end)
end

PANELS.orbit = function(frame, stack, onRefresh)
    local Camera = OA.Camera
    local cam = OA.db.camera
    local dir = Choice(frame, stack, {
        { value = "left", text = L["Turn left"] },
        { value = "right", text = L["Turn right"] },
    }, function() return Camera.OrbitDirection() end, function(v)
        Camera.SetOrbitDirection(v)
    end)
    local speed = Slider(frame, stack, { label = L["Orbit speed"], min = 0.01, max = 1, step = 0.01,
        get = function() return cam.orbitSpeed or 0.1 end,
        set = function(v) Camera.SetOrbitSpeed(v) end,
        format = function(v) return string.format("%d%%", v * 100) end })
    cam.orbitStop = cam.orbitStop or { move = true, mouse = true }
    local move = Check(frame, stack, L["Stop when I move"],
        function() return cam.orbitStop.move == true end, function(v) cam.orbitStop.move = v end)
    local mouse = Check(frame, stack, L["Stop when I grab the camera"],
        function() return cam.orbitStop.mouse == true end, function(v) cam.orbitStop.mouse = v end)
    local go = Button(frame, stack, L["Start orbit"], nil, function() Camera.ToggleOrbit() end)
    onRefresh(function()
        dir:Refresh(true)
        speed:Refresh()
        move:Refresh(true)
        mouse:Refresh(true)
        go:SetLabel(Camera.IsOrbiting() and L["Stop orbit"] or L["Start orbit"])
    end)
end

PANELS.mark = function(frame, stack, onRefresh)
    local skin = Kit.Skin()
    local head = stack.Add(skin.Label(frame, 12, C.muted), 14, 8)
    local lines = {}
    for i = 1, 3 do
        local line = skin.Label(frame, 12, C.text)
        line:SetWidth(W)
        lines[i] = stack.Add(line, 14, 4)
    end
    local mark = Button(frame, stack, L["Mark now"], "primary", function() OA.Moments.Mark() end)
    local db = OA.db.moments
    local shot = Check(frame, stack, L["Screenshot with each moment"],
        function() return db.screenshot == true end, function(v) db.screenshot = v end)
    onRefresh(function()
        local session = OA.Moments.Current()
        local list = (OA.live and session and session.moments) or {}
        head:SetText(OA.live and string.format(L["%d moments"], #list) or L["Moments are marked while you're live."])
        for i = 1, 3 do
            local m = list[#list - i + 1]
            lines[i]:SetText(m and (OA.Moments.Format(m.t) .. "  " .. m.text) or "")
        end
        mark:SetAlpha((OA.live and not OA.rehearsal) and 1 or 0.4)
        shot:Refresh(true)
    end)
end

PANELS.layout = function(frame, stack, onRefresh)
    local Layout = OA.Layout
    local snap = Choice(frame, stack, {
        { value = "free", text = L["Free"] },
        { value = "guides", text = L["Guides"] },
        { value = "grid", text = L["Grid"] },
    }, function() return Layout.Options().snap end, function(v) Layout.SetOption("snap", v) end)
    local lock = Check(frame, stack, L["Lock positions"],
        function() return Layout.Locked() end, function(v) Layout.SetOption("locked", v) end)
    local label = stack.Add(Kit.Skin().Label(frame, 12, C.muted), 14, 6)
    label:SetText(L["The Deck when idle"])
    local db = DB()
    local hide = Choice(frame, stack, {
        { value = "never", text = L["Stay"] },
        { value = "fade", text = L["Fade"] },
        { value = "tuck", text = L["Tuck"] },
    }, function() return db.hide end, function(v)
        db.hide = v
        Deck.Refresh()
    end)
    onRefresh(function()
        snap:Refresh(true)
        lock:Refresh(true)
        hide:Refresh(true)
    end)
end

local function BuildPanel()
    local skin = Kit.Skin()
    panel = CreateFrame("Frame", "OnAirDeckPanel", deck)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(deck:GetFrameLevel() + 40)
    panel:SetWidth(PANEL_W)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    local bg = Kit.Rect(panel, { C.bg[1], C.bg[2], C.bg[3], 0.97 }, "BACKGROUND")
    bg:SetAllPoints()
    Kit.Border(panel, C.line)
    local accent = Kit.Rect(panel, C.accent, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(1)
    panel.icon = Kit.Icon(panel, "Orbit", 14, C.accent)
    panel.icon:SetPoint("TOPLEFT", 12, -11)
    panel.title = skin.Label(panel, 12, C.text)
    panel.title:SetPoint("LEFT", panel.icon, "RIGHT", 8, 0)
    if skin.PanelDecor then
        skin.PanelDecor(panel)
    end
    panel:Hide()
end

local function Content(key)
    if contents[key] then
        return contents[key]
    end
    local frame = CreateFrame("Frame", nil, panel)
    frame:SetAllPoints()
    local stack = Stack(frame)
    local list = {}
    PANELS[key](frame, stack, function(fn) list[#list + 1] = fn end)
    local content = { frame = frame, height = stack.Height(), refresh = list }
    contents[key] = content
    return content
end

-- A new skin draws new panels (the old ones stay hidden).
function Deck.ResetPanels()
    if panel then
        panel:Hide()
    end
    panel, panelKey, contents = nil, nil, {}
end

local function RefreshPanel()
    local content = panelKey and contents[panelKey]
    if content then
        for _, fn in ipairs(content.refresh) do
            Utils.Guard("deck panel " .. panelKey, fn)()
        end
    end
end

-- Beside the button, away from the docked edge (over or under it on a horizontal Deck).
local function Anchor(button)
    panel:ClearAllPoints()
    local edge = DB().edge
    if edge == "LEFT" then
        panel:SetPoint("TOPLEFT", button, "TOPRIGHT", 10, 0)
    elseif edge == "RIGHT" then
        panel:SetPoint("TOPRIGHT", button, "TOPLEFT", -10, 0)
    else
        local _, y = deck:GetCenter()
        local _, sh = Screen()
        if (y or 0) > sh / 2 then
            panel:SetPoint("TOP", button, "BOTTOM", 0, -10)
        else
            panel:SetPoint("BOTTOM", button, "TOP", 0, 10)
        end
    end
end

local function SpecOf(key)
    for _, spec in ipairs(Deck.BUTTONS) do
        if spec.key == key then
            return spec
        end
    end
end

local function ShowPanel(key)
    if not panel then
        BuildPanel()
    end
    local content = Content(key)
    for k, c in pairs(contents) do
        c.frame:SetShown(k == key)
    end
    local spec = SpecOf(key)
    panelKey = key
    panel.title:SetText(spec.text:upper())
    panel.icon:SetTexture(Utils.ICONS .. spec.icon)
    panel:SetHeight(content.height)
    Anchor(buttons[key])
    RefreshPanel()
    GameTooltip:Hide()
    away, tick = 0, 0
    if not panel:IsShown() then
        panel:Show()
    end
    Kit.Tween(panel, panel:GetAlpha(), 1, 0.22, function(p) panel:SetAlpha(p) end, "quint")
end

local function HidePanel()
    if panel and panelKey then
        panelKey = nil
        Kit.Tween(panel, panel:GetAlpha(), 0, 0.15, function(p)
            panel:SetAlpha(p)
            if p <= 0 and not panelKey then
                panel:Hide()
            end
        end)
    end
end
Deck.HidePanel = HidePanel

function Deck.PanelOpen()
    return panel ~= nil and panelKey ~= nil
end

-- Called from the Deck's watcher, every frame.
PanelWatch = function(elapsed)
    if OA.Layout.IsEditing() or DB().panels == false then
        HidePanel()
        return
    end
    if hoverKey and PANELS[hoverKey] then
        if Deck.PanelOpen() then
            if panelKey ~= hoverKey then
                ShowPanel(hoverKey)
            end
        else
            hoverTime = hoverTime + elapsed
            if hoverTime >= HOVER_DELAY then
                ShowPanel(hoverKey)
            end
        end
    end
    if Deck.PanelOpen() then
        if panel:IsMouseOver() or buttons[panelKey]:IsMouseOver() then
            away = 0
        else
            away = away + elapsed
            if away >= LINGER then
                HidePanel()
            end
        end
        tick = tick + elapsed
        if tick >= 0.25 then
            tick = 0
            RefreshPanel()
        end
    end
end

local function Hovered(key)
    hoverKey, hoverTime = key, 0
end

-- For the console's Deck page.
Deck.PANELS = PANELS

---------------------------------------------------------------------------------------------- build

-- What the face paints: on air, the Deck says so (it took over from the old ON AIR badge); in
-- edit layout the buttons dim: they're locked.
local function Paint()
    local state = { on = {}, editing = OA.Layout and OA.Layout.IsEditing() }
    for _, spec in ipairs(Deck.BUTTONS) do
        local ok, on = pcall(spec.on)
        state.on[spec.key] = ok and on and true or false
    end
    face.Paint(state)
end

local function StartDrag()
    if not OA.Layout.IsEditing() and OA.Layout.Locked() then
        return
    end
    deck:StartMoving()
    OA.Layout.DragStart("deck")
end

local function StopDrag()
    deck:StopMovingOrSizing()
    OA.Layout.Dropped("deck")
    Snap()
end

-- The active skin's face (built the first time), wired to the Deck's clicks, hover and drag.
local function UseFace()
    local key = Kit.Theme().key
    if not faces[key] then
        local new = Kit.Skin().Deck(deck, Deck.BUTTONS)
        for _, spec in ipairs(Deck.BUTTONS) do
            local b = new.buttons[spec.key]
            b:RegisterForClicks("AnyUp")
            b:RegisterForDrag("LeftButton")
            b:SetScript("OnEnter", function(self)
                local editing = OA.Layout and OA.Layout.IsEditing()
                b.SetHover(not editing)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(spec.text, 1, 1, 1)
                GameTooltip:AddLine(editing and L["Edit layout: drag to move the Deck. Buttons work again after Done."]
                    or spec.tip(), nil, nil, nil, true)
                GameTooltip:Show()
                Hovered(spec.key)
            end)
            b:SetScript("OnLeave", function()
                b.SetHover(false)
                GameTooltip:Hide()
                Hovered(nil)
            end)
            b:SetScript("OnClick", function(_, mouse)
                -- In edit layout the Deck is something you move, not press.
                if OA.Layout and OA.Layout.IsEditing() then
                    return
                end
                spec.click(mouse)
                Paint()
            end)
            b:SetScript("OnDragStart", StartDrag)
            b:SetScript("OnDragStop", StopDrag)
        end
        faces[key] = new
    end
    if face and face ~= faces[key] then
        face.frame:Hide()
        face.tab:SetAlpha(0)
    end
    face = faces[key]
    face.frame:Show()
    tab, buttons = face.tab, face.buttons
    tab:SetAlpha(tucked)
end

local function Build()
    deck = CreateFrame("Frame", "OnAirDeck", WorldFrame)
    deck:SetFrameStrata("DIALOG")
    deck:SetClampedToScreen(false)
    deck:SetMovable(true)
    deck:EnableMouse(true)
    deck:RegisterForDrag("LeftButton")
    deck:SetScript("OnDragStart", StartDrag)
    deck:SetScript("OnDragStop", StopDrag)
    UseFace()
    deck:SetScript("OnUpdate", Utils.Guard("deck", Watch))
    deck:SetScript("OnEvent", SyncScale)
    deck:RegisterEvent("UI_SCALE_CHANGED")
    deck:RegisterEvent("DISPLAY_SIZE_CHANGED")
    SyncScale()
    Layout()
end

-- Another skin: a new face, and the quick panels redrawn in it.
Kit.OnSkin(function()
    Deck.ResetPanels()
    if deck then
        UseFace()
        Deck.Refresh()
    end
end)

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
