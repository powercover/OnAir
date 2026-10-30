local _, OA = ...

-- Camera tools for recording: zoom further out, a narrower field of view, the action camera's
-- shoulder offset and tilt, slower and smoother follow and zoom, and a slow orbit.
-- They run Always, Only while live, or Off. Before the first change the camera's own values are
-- saved, and they come back when the camera mode turns off (or the broadcast ends in "live" mode),
-- also after a crash, on the next login.
OA.Camera = {}

local Camera = OA.Camera
local L = OA.L

-- Each setting: its CVar(s), range, and how the slider shows it. `cvars` maps the value onto
-- every CVar it drives.
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
    { key = "zoomSpeed", cvar = "cameraZoomSpeed", min = 2, max = 50, step = 1,
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
        head = 0, follow = 90, zoomSpeed = 8, style = 4 } },
    { key = "shoulder", text = L["Over the shoulder"], values = { zoom = 1.4, fov = 85, shoulder = 1.2, tilt = 0.25,
        head = 0, follow = 150, zoomSpeed = 15, style = 4 } },
    { key = "wide", text = L["Wide"], values = { zoom = 2.6, fov = 90, shoulder = 0, tilt = 0, head = 0,
        follow = 180, zoomSpeed = 20 } },
}

local function DB()
    return OA.db.camera
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

function Camera.Set(key, value)
    DB()[key] = value
    DB().preset = "custom"
    Camera.Update()
end

function Camera.UsePreset(key)
    local db = DB()
    for _, preset in ipairs(Camera.PRESETS) do
        if preset.key == key then
            for _, setting in ipairs(Camera.SETTINGS) do
                db[setting.key] = preset.values[setting.key]
            end
            db.style = preset.values.style
            db.preset = key
        end
    end
    Camera.Update()
end

-- CVar -> value, for what's set now.
local function Wanted()
    local db = DB()
    local wanted = {}
    for _, setting in ipairs(Camera.SETTINGS) do
        if db[setting.key] ~= nil then
            wanted[setting.cvar] = db[setting.key]
        end
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

local function Apply()
    local db = DB()
    db.saved = db.saved or {}
    local wanted = Wanted()
    -- A setting moved back to the game default: give back the value from before.
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
end

local function Restore()
    local db = DB()
    for cvar, value in pairs(db.saved or {}) do
        pcall(C_CVar.SetCVar, cvar, value)
    end
    db.saved = nil
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
    if Camera.Active() then
        Apply()
    else
        Camera.StopOrbit()
        Restore()
    end
end

function Camera.OnCombatEnd()
    if pending then
        Camera.Update()
    end
end

---------------------------------------------------------------------------------------------- orbit

local orbiting = false

function Camera.IsOrbiting()
    return orbiting
end

function Camera.StopOrbit()
    if orbiting then
        orbiting = false
        pcall(MoveViewLeftStop)
        if OA.UI and OA.UI.Refresh then
            OA.UI.Refresh()
        end
    end
end

-- A slow turn around your character, for intros and outros. Stops on its own when combat starts.
function Camera.ToggleOrbit()
    if orbiting then
        Camera.StopOrbit()
        return
    end
    if type(MoveViewLeftStart) ~= "function" then
        return
    end
    orbiting = true
    pcall(MoveViewLeftStart, DB().orbitSpeed or 0.05)
    if OA.UI and OA.UI.Refresh then
        OA.UI.Refresh()
    end
end

function Camera.SetOrbitSpeed(speed)
    DB().orbitSpeed = speed
    if orbiting then
        pcall(MoveViewLeftStop)
        pcall(MoveViewLeftStart, speed)
    end
end

function Camera.Init()
    -- Left applied by a session that ended without restoring (a crash): mode off means put back.
    if DB().saved and not Camera.Active() then
        Restore()
    end
    Camera.Update()
end

function Camera.Format(key, value)
    local setting = byKey[key]
    return setting and setting.format(value) or tostring(value)
end
