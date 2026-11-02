local _, OA = ...

-- Camera tools for recording: zoom further out, a narrower field of view, the action camera's
-- shoulder offset and tilt, slower and smoother follow and zoom, and a slow orbit.
-- They run Always, Only while live, or Off. Before the first change the camera's own values are
-- saved, and they come back when the camera mode turns off (or the broadcast ends in "live" mode),
-- also after a crash, on the next login. Zoom speed is apart: no preset changes it, and it stays
-- on with the camera off too, until it goes back to the game default.
OA.Camera = {}

local Camera = OA.Camera
local L = OA.L

-- Each setting: its CVar(s), range, and how the slider shows it. `cvars` maps the value onto
-- every CVar it drives. `own`: yours alone, not part of the presets, and on with the camera off.
Camera.SETTINGS = {
    { key = "zoom", cvar = "cameraDistanceMaxZoomFactor", min = 1, max = 2.6, step = 0.1,
        label = L["Max zoom distance"], format = function(v) return string.format(L["%d yards"], v * 15) end },
    { key = "fov", cvar = "cameraFov", min = 50, max = 90, step = 1,
        label = L["Field of view"], format = function(v) return string.format("%d\194\176", v) end },
    { key = "shoulder", cvar = "test_cameraOverShoulder", min = -2, max = 2, step = 0.1,
        label = L["Shoulder offset"], format = function(v)
            if math.abs(v) < 0.05 then
                return L["Centered"]
            end
            return string.format(v > 0 and L["%.1f right"] or L["%.1f left"], math.abs(v))
        end },
    { key = "tilt", cvar = "test_cameraDynamicPitchBaseFovPad", min = 0, max = 1, step = 0.05,
        label = L["Camera tilt"], format = function(v)
            return v <= 0 and L["Off"] or string.format("%d%%", v * 100)
        end },
    { key = "head", cvar = "test_cameraHeadMovementStrength", min = 0, max = 2, step = 0.1,
        label = L["Head movement"], format = function(v)
            return v <= 0 and L["Off"] or string.format("%.1f", v)
        end },
    { key = "follow", cvar = "cameraYawSmoothSpeed", min = 30, max = 360, step = 10,
        label = L["Follow speed"], format = function(v) return string.format(L["%d (lower is smoother)"], v) end },
    { key = "zoomSpeed", cvar = "cameraZoomSpeed", min = 2, max = 50, step = 1, own = true,
        label = L["Zoom speed"], format = function(v) return string.format(L["%d (lower is smoother)"], v) end },
}

local byKey = {}
for _, setting in ipairs(Camera.SETTINGS) do
    byKey[setting.key] = setting
end

Camera.STYLES = {
    { value = 0, text = L["Never follow"] },
    { value = 4, text = L["Smart"] },
    { value = 2, text = L["Always follow"] },
}

Camera.PRESETS = {
    { key = "default", text = L["Default"], values = {} },
    { key = "cinematic", text = L["Cinematic"], values = { zoom = 2.6, fov = 75, shoulder = 0.6, tilt = 0.35,
        head = 0, follow = 90, style = 4 } },
    { key = "shoulder", text = L["Over the shoulder"], values = { zoom = 1.4, fov = 85, shoulder = 1.2, tilt = 0.25,
        head = 0, follow = 150, style = 4 } },
    { key = "wide", text = L["Wide"], values = { zoom = 2.6, fov = 90, shoulder = 0, tilt = 0, head = 0,
        follow = 180 } },
}

local function DB()
    return OA.db.camera
end

local function Refresh()
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
    if OA.Deck and OA.Deck.Refresh then
        OA.Deck.Refresh()
    end
end

function Camera.Exists(cvar)
    return C_CVar.GetCVar(cvar) ~= nil
end

local function Default(cvar)
    local value = C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(cvar)
    return tonumber(value)
end

-- The value a setting has now: yours, or the game's default.
function Camera.Get(key)
    local db = DB()
    if key == "style" then
        return db.style or Default("cameraSmoothStyle") or 0
    end
    local setting = byKey[key]
    local value = db[key]
    if value == nil then
        value = Default(setting.cvar) or setting.min
    end
    return value
end

-- A camera setting changed while the camera is off turns it on (Always), so the change shows.
function Camera.On()
    local db = DB()
    if db.mode == "off" then
        db.mode = "always"
        Refresh()
    end
end

function Camera.Set(key, value)
    local db = DB()
    db[key] = value
    -- Your own settings aren't part of a preset and work with the camera off. The rest make the
    -- preset Custom and turn the camera on.
    if not byKey[key].own then
        db.preset = "custom"
        Camera.On()
    end
    Camera.Update()
end

function Camera.UsePreset(key)
    local db = DB()
    for _, preset in ipairs(Camera.PRESETS) do
        if preset.key == key then
            for _, setting in ipairs(Camera.SETTINGS) do
                if not setting.own then
                    db[setting.key] = preset.values[setting.key]
                end
            end
            db.style = preset.values.style
            db.preset = key
        end
    end
    Camera.Update()
end

-- Back to the game's defaults: the Default preset, and your own settings too.
function Camera.Reset()
    local db = DB()
    for _, setting in ipairs(Camera.SETTINGS) do
        if setting.own then
            db[setting.key] = nil
        end
    end
    Camera.UsePreset("default")
end

-- CVar -> value, for what's set now. With the camera off, only your own settings.
local function Wanted(active)
    local db = DB()
    local wanted = {}
    for _, setting in ipairs(Camera.SETTINGS) do
        if db[setting.key] ~= nil and (active or setting.own) then
            wanted[setting.cvar] = db[setting.key]
        end
    end
    if not active then
        return wanted
    end
    if db.style ~= nil then
        wanted.cameraSmoothStyle = db.style
    end
    local tilt = db.tilt
    if tilt ~= nil then
        wanted.test_cameraDynamicPitch = tilt > 0 and 1 or 0
    end
    if db.focus ~= nil then
        wanted.test_cameraTargetFocusEnemyEnable = db.focus and 1 or 0
    end
    -- The action camera only moves the view while the game isn't keeping you centered.
    if (db.shoulder and db.shoulder ~= 0) or (db.head and db.head > 0) or (tilt and tilt > 0) then
        wanted.CameraKeepCharacterCentered = 0
        if db.head and db.head > 0 then
            wanted.CameraReduceUnexpectedMovement = 0
        end
    end
    return wanted
end

-- The game asks "use experimental features?" the first time an action camera CVar changes.
-- Choosing the camera here is that choice.
local quieted = false
local function QuietExperimentalPopup()
    if not quieted and UIParent and UIParent.UnregisterEvent then
        quieted = true
        pcall(UIParent.UnregisterEvent, UIParent, "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    end
end

local pending
local applied -- the camera was on at the last update

local function Apply(active)
    local db = DB()
    db.saved = db.saved or {}
    local wanted = Wanted(active)
    -- Not wanted anymore (moved back to the game default, or the camera turned off): give back
    -- the value from before.
    for cvar, value in pairs(db.saved) do
        if wanted[cvar] == nil then
            pcall(C_CVar.SetCVar, cvar, value)
            db.saved[cvar] = nil
        end
    end
    for cvar, value in pairs(wanted) do
        local current = C_CVar.GetCVar(cvar)
        if current ~= nil then
            if db.saved[cvar] == nil then
                db.saved[cvar] = current
            end
            if cvar:find("^test_") then
                QuietExperimentalPopup()
            end
            pcall(C_CVar.SetCVar, cvar, tostring(value))
        end
    end
    if next(db.saved) == nil then
        db.saved = nil
    end
end

function Camera.Active()
    local mode = DB().mode
    return mode == "always" or (mode == "live" and OA.live)
end

-- Puts the camera where the settings and the live state say. Waits for combat to end.
function Camera.Update()
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local active = Camera.Active()
    -- The camera turning off ends an orbit. One started with it off keeps going.
    if applied and not active then
        Camera.StopOrbit()
    end
    applied = active
    Apply(active)
end

function Camera.OnCombatEnd()
    if pending then
        Camera.Update()
    end
end

---------------------------------------------------------------------------------------------- orbit

-- A slow turn around your character, for intros and outros, either way round. Stops on its own
-- when combat starts and, if set, when you start moving or take the camera with the mouse.
local orbiting -- nil, "left" or "right"
local watcher
local grace = 0

local MOVE = {
    left = { start = "MoveViewLeftStart", stop = "MoveViewLeftStop" },
    right = { start = "MoveViewRightStart", stop = "MoveViewRightStop" },
}

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then
        pcall(fn, ...)
        return true
    end
end

function Camera.IsOrbiting()
    return orbiting ~= nil
end

function Camera.OrbitDirection()
    return orbiting or DB().orbitDir or "left"
end

-- Mouse on the world with a button held: the player is turning the camera themselves.
local function MouseOnCamera()
    if type(IsMouselooking) == "function" and IsMouselooking() then
        return true
    end
    if type(IsMouseButtonDown) ~= "function" or not IsMouseButtonDown("LeftButton") then
        return false
    end
    local focus
    if type(GetMouseFoci) == "function" then
        focus = GetMouseFoci()[1]
    elseif type(GetMouseFocus) == "function" then
        focus = GetMouseFocus()
    end
    return focus == nil or focus == WorldFrame
end

local function Watch(_, elapsed)
    if grace > 0 then
        grace = grace - elapsed
        return
    end
    local stop = DB().orbitStop or {}
    if stop.mouse and MouseOnCamera() then
        Camera.StopOrbit()
    end
end

local function OnEvent()
    if (DB().orbitStop or {}).move and grace <= 0 then
        Camera.StopOrbit()
    end
end

local function Watcher(on)
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", OA.Utils.Guard("orbit stop", OnEvent))
    end
    if on then
        grace = 0.3
        watcher:SetScript("OnUpdate", OA.Utils.Guard("orbit watch", Watch))
        watcher:RegisterEvent("PLAYER_STARTED_MOVING")
        watcher:RegisterEvent("PLAYER_STARTED_TURNING")
    else
        watcher:SetScript("OnUpdate", nil)
        watcher:UnregisterAllEvents()
    end
end

function Camera.StopOrbit()
    if orbiting then
        Call(MOVE[orbiting].stop)
        orbiting = nil
        Watcher(false)
        Refresh()
    end
end

-- Starts turning one way ("left", "right"; nil: the saved direction). Switching way round just
-- turns the other way.
function Camera.StartOrbit(dir)
    dir = MOVE[dir] and dir or DB().orbitDir or "left"
    if orbiting == dir then
        return
    end
    if orbiting then
        Call(MOVE[orbiting].stop)
    end
    if not Call(MOVE[dir].start, DB().orbitSpeed or 0.1) then
        orbiting = nil
        return
    end
    orbiting = dir
    Watcher(true)
    Refresh()
end

-- The same way again stops it; the other way switches over.
function Camera.ToggleOrbit(dir)
    if orbiting and (dir == nil or dir == orbiting) then
        Camera.StopOrbit()
    else
        Camera.StartOrbit(dir)
    end
end

function Camera.SetOrbitDirection(dir)
    DB().orbitDir = dir
    if orbiting and orbiting ~= dir then
        Camera.StartOrbit(dir)
    end
end

function Camera.SetOrbitSpeed(speed)
    DB().orbitSpeed = speed
    DB().orbitSpeedSet = true
    if orbiting then
        Call(MOVE[orbiting].stop)
        Call(MOVE[orbiting].start, speed)
    end
end

function Camera.Init()
    -- The old default (5%) moves up to the new one (10%), unless you picked a speed yourself.
    local db = DB()
    if db.orbitSpeed == 0.05 and not db.orbitSpeedSet then
        db.orbitSpeed = 0.1
    end
    -- Before 1.0.1 each preset brought its own zoom speed (8, 15, 20). One that came with a
    -- preset isn't yours: it goes back to the game default, once.
    if not db.zoomSpeedOwn then
        db.zoomSpeedOwn = true
        local speed = db.zoomSpeed
        if db.preset ~= "custom" or speed == 8 or speed == 15 or speed == 20 then
            db.zoomSpeed = nil
        end
    end
    -- Left applied by a session that ended without restoring (a crash): mode off means put back.
    if DB().saved and not Camera.Active() then
        Apply(false)
    end
    Camera.Update()
end

function Camera.Format(key, value)
    local setting = byKey[key]
    return setting and setting.format(value) or tostring(value)
end
