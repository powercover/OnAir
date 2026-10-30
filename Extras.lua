local _, OA = ...

-- What lives outside the console: the minimap button and the go-live banner. (The Deck shows
-- you're on air; it replaced the old ON AIR badge.)
OA.UI = OA.UI or {}

local UI = OA.UI
local Kit = OA.Kit
local C = Kit.C
local L = OA.L
local Utils = OA.Utils

---------------------------------------------------------------------------------------------- tooltip

function UI.ShowLauncherTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("On|cffff3b30Air|r", 1, 1, 1)
    if OA.live then
        GameTooltip:AddLine(L["ON AIR: names are hidden"], 1, 0.23, 0.19)
    else
        GameTooltip:AddLine(L["Off the air: real names showing"], 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Left-click"], OA.live and L["End broadcast"] or L["Go live"], 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Right-click"], L["Console"], 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:Show()
end

---------------------------------------------------------------------------------------------- minimap

-- Placed like LibDBIcon places buttons (just outside the edge, following square minimaps), so
-- minimap button addons such as EllesmereUI's pick it up like any other.
local EDGE_OFFSET = 5
local FALLBACK_RADIUS = 80
local SHAPES = {
    ROUND = { true, true, true, true }, SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local mini

local function OnMinimap()
    return mini and mini:GetParent() == Minimap
end

local function PlaceMinimap()
    if not OnMinimap() then
        return
    end
    local rad = math.rad(OA.db.minimap.angle or 200)
    local x, y = math.cos(rad), math.sin(rad)
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    local w = width and width > 0 and width / 2 + EDGE_OFFSET or FALLBACK_RADIUS
    local h = height and height > 0 and height / 2 + EDGE_OFFSET or FALLBACK_RADIUS
    local quarter = 1
    if x < 0 then
        quarter = quarter + 1
    end
    if y > 0 then
        quarter = quarter + 2
    end
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    if (SHAPES[shape] or SHAPES.ROUND)[quarter] then
        x, y = x * w, y * h
    else
        x = math.max(-w, math.min(x * (math.sqrt(2 * w * w) - 10), w))
        y = math.max(-h, math.min(y * (math.sqrt(2 * h * h) - 10), h))
    end
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local miniPulse, miniDot, miniWaves

local function BuildMinimap()
    mini = CreateFrame("Button", "OnAirMinimapButton", Minimap)
    mini:SetSize(32, 32)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("AnyUp")
    mini:RegisterForDrag("LeftButton")
    local base = mini:CreateTexture(nil, "ARTWORK", nil, 0)
    base:SetTexture(Utils.MEDIA .. "MinimapIcon")
    base:SetAllPoints()
    base:SetVertexColor(1, 1, 1, 0)
    mini.icon = base
    -- The icon's dark disc without the waves: drawn from the dot texture, under them.
    local disc = mini:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(Utils.MEDIA .. "Dot")
    disc:SetVertexColor(0.07, 0.075, 0.086, 1)
    disc:SetAllPoints(base)
    miniWaves = mini:CreateTexture(nil, "ARTWORK", nil, 1)
    miniWaves:SetTexture(Utils.MEDIA .. "MinimapWaves")
    miniWaves:SetAllPoints(base)
    miniDot = mini:CreateTexture(nil, "ARTWORK", nil, 2)
    miniDot:SetTexture(Utils.MEDIA .. "MinimapDot")
    miniDot:SetAllPoints(base)
    local glow = mini:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(Utils.MEDIA .. "Glow")
    glow:SetVertexColor(unpack(C.red))
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", base, "TOPLEFT", -6, 6)
    glow:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", 6, -6)
    glow:SetAlpha(0)
    miniPulse = Kit.Pulse(glow, 0, 0.8, 0.9)

    mini:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            UI.ToggleConsole()
        else
            OA.Toggle()
            UI.ShowLauncherTooltip(self)
        end
    end)
    mini:SetScript("OnEnter", UI.ShowLauncherTooltip)
    mini:SetScript("OnLeave", GameTooltip_Hide)
    mini:SetScript("OnDragStart", function(self)
        if not OnMinimap() then
            return
        end
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            OA.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimap()
        end)
    end)
    mini:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    Minimap:HookScript("OnSizeChanged", PlaceMinimap)
    PlaceMinimap()
end

---------------------------------------------------------------------------------------------- banner

local banner

local function BuildBanner()
    banner = CreateFrame("Frame", nil, UIParent)
    banner:SetSize(340, 54)
    banner:SetFrameStrata("FULLSCREEN_DIALOG")
    banner:SetPoint("TOP", 0, -90)
    local bg = Kit.Rect(banner, { C.bg[1], C.bg[2], C.bg[3], 0.95 }, "BACKGROUND")
    bg:SetAllPoints()
    banner.edges = Kit.Border(banner, C.redDeep)
    banner.stripe = Kit.Rect(banner, C.red, "ARTWORK")
    banner.stripe:SetPoint("TOPLEFT")
    banner.stripe:SetPoint("BOTTOMLEFT")
    banner.stripe:SetWidth(3)
    local look = Kit.Theme()
    if look.stripes then
        local band = Kit.Band(banner, "Stripes", C.text, "ARTWORK")
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(5)
    end
    if look.corners then
        Kit.Corners(banner, 10, 2, C.text, 0)
    end
    banner.dot = Kit.Shape(banner, "Dot", C.red, "ARTWORK")
    banner.dot:SetSize(12, 12)
    banner.dot:SetPoint("LEFT", 22, 0)
    banner.title = Kit.Text(banner, 20, C.text)
    banner.title:SetPoint("LEFT", 44, 8)
    banner.sub = Kit.Text(banner, 12, C.muted)
    banner.sub:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -3)
    banner:Hide()
end

local bannerTimer

-- Slides in, waits, slides out.
function UI.Toast(live)
    -- Going live with the slate on: the slate says it already.
    if live == true and OA.Moments.SlateShowing() then
        return
    end
    if not banner then
        BuildBanner()
    end
    local preview = live == "preview"
    local color = preview and C.amber or (live and C.red or C.off)
    banner.stripe:SetColorTexture(unpack(color))
    banner.dot:SetVertexColor(unpack(color))
    Kit.SetBorderColor(banner.edges, live and C.redDeep or C.line)
    if preview then
        banner.title:SetText(Kit.Word("preview"))
        banner.sub:SetText(L["Masked like live. Nothing is recorded or marked."])
    else
        banner.title:SetText(Kit.Word(live and "live" or "off"))
        banner.sub:SetText(live and L["Names are hidden. Have a good show."] or L["Real names are back."])
    end
    banner:Show()
    Kit.Tween(banner, 0, 1, 0.3, function(p)
        banner:SetAlpha(p)
        banner:SetPoint("TOP", 0, -70 - 20 * p)
    end)
    if bannerTimer then
        bannerTimer:Cancel()
    end
    bannerTimer = C_Timer.NewTimer(2.2, function()
        Kit.Tween(banner, 1, 0, 0.4, function(p)
            banner:SetAlpha(p)
            if p <= 0 then
                banner:Hide()
            end
        end)
    end)
    PlaySound(live and (SOUNDKIT and SOUNDKIT.UI_PROFESSIONS_WINDOW_OPEN or 158) or (SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE or 851))
end

---------------------------------------------------------------------------------------------- state

function UI.UpdateExtras()
    if not OA.db then
        return
    end
    if mini then
        mini:SetShown(OA.db.minimap.show ~= false)
        if OA.live then
            miniDot:SetVertexColor(unpack(C.red))
            miniWaves:SetVertexColor(1, 1, 1, 1)
            miniPulse:Play()
        else
            miniDot:SetVertexColor(unpack(C.muted))
            miniWaves:SetVertexColor(unpack(C.muted))
            miniPulse:Stop()
        end
    end
    if OA.Deck and mini then
        OA.Deck.Refresh()
    end
end

function UI.InitExtras()
    BuildMinimap()
    OA.Layout.Register("stream", OA.StreamChat.Frame(), L["Stream chat"], {
        show = function(on) OA.StreamChat.SetPlacing(on) end,
        save = function() OA.StreamChat.SavePosition() end,
    })
    OA.Layout.Register("deck", OA.Deck.Frame(), L["Deck"], {
        show = function() OA.Deck.Refresh() end,
        snap = function() end, -- the Deck docks to edges and saves by itself
    })
    UI.UpdateExtras()
    OA.Deck.Refresh()
end
