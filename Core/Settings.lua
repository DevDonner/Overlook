-- Saved settings: defaults, loading and clamping. Pure Lua, so the offline tests cover it.
local _, ns = ...

local Settings = {}
ns.Settings = Settings

Settings.VERSION = 2
Settings.SIZE_MIN, Settings.SIZE_MAX = 120, 600
Settings.FAR_MIN, Settings.FAR_MAX = 500, 3200

-- x/y (the frame's centre offset from the screen centre) start unset: the first login places the
-- frame where the native minimap was.
Settings.DEFAULTS = {
    size = 200,           -- px, square
    locked = false,       -- hides the resize grip; Alt+drag still moves it
    maxFarZoom = 2000,    -- yd radius; setting goes up to 3,200
    rotate = false,
    clustering = false,
    smoothZoom = true,    -- tween far-zoom steps
    routes = true,        -- Questie's NPC routes on the far map
    partyDots = true,     -- party and raid members on the far map
    trackingButton = true, -- the minimap icons (tracking) button under the bottom-left corner
}

function Settings.ClampSize(n)
    n = tonumber(n) or Settings.DEFAULTS.size
    return math.max(Settings.SIZE_MIN, math.min(Settings.SIZE_MAX, math.floor(n + 0.5)))
end

function Settings.ClampMaxFar(n)
    n = tonumber(n) or Settings.DEFAULTS.maxFarZoom
    return math.max(Settings.FAR_MIN, math.min(Settings.FAR_MAX, math.floor(n + 0.5)))
end

-- Fills missing keys with defaults and clamps values. Reuses the saved table so the game writes
-- back the same object.
function Settings.Load(saved)
    local db = type(saved) == "table" and saved or {}
    -- v1 saved locked = true as an unused default; v2 makes the lock real, so start unlocked.
    if (tonumber(db.version) or 0) < 2 and db.locked == true then db.locked = false end
    for k, v in pairs(Settings.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.size = Settings.ClampSize(db.size)
    db.maxFarZoom = Settings.ClampMaxFar(db.maxFarZoom)
    -- Per-category icon preferences (IconPrefs). Not in DEFAULTS: a table default would be shared.
    if type(db.icons) ~= "table" then db.icons = {} end
    -- LibDBIcon's saved state for the minimap button ({ hide, minimapPos }); same reason.
    if type(db.minimapButton) ~= "table" then db.minimapButton = {} end
    if type(db.x) ~= "number" or type(db.y) ~= "number" then
        db.x, db.y = nil, nil
    end
    db.version = Settings.VERSION
    return db
end
