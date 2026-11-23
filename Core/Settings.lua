-- Saved settings: defaults, loading and clamping. Pure Lua, so the offline tests cover it.
local _, ns = ...

local Settings = {}
ns.Settings = Settings

Settings.VERSION = 4
Settings.SIZE_MIN, Settings.SIZE_MAX = 120, 800
Settings.FAR_MIN, Settings.FAR_MAX = 500, 6400

-- x/y (the frame's centre offset from the screen centre) start unset: the first login places the
-- frame where the native minimap was.
Settings.DEFAULTS = {
    size = 200,           -- px, square
    locked = false,       -- hides the resize grip; Alt+drag still moves it
    maxFarZoom = 2000,    -- yd radius; setting goes up to 6,400
    rotate = false,       -- the game's rotating minimap, at normal zoom (Shell.SetRotate)
    clustering = false,
    smoothZoom = true,    -- tween far-zoom steps
    routes = true,        -- Questie's NPC routes on the far map
    routeWidth = 1.5,     -- px, far-map route lines
    routeAlpha = 1,       -- opacity of the far-map route lines (times Questie's own)
    partyDots = true,     -- party and raid members on the far map
    nativeIcons = false,  -- the game's own quest and town icons (Questie draws them instead)
    arrowScale = 1,       -- player arrow size on the far map (1 = the native arrow's size)
    questAreas = true,    -- the game's blue quest areas on the far map
    questAreaFill = 0.25, -- their fill opacity (several quests' areas merge into one shape)
    questAreaBorder = 0.5, -- their border opacity
    questAreaTracked = false, -- only quests on the objective tracker
    -- Bars: zone name above the map, coordinates / far radius / clock below it.
    topBar = true,
    topBarInside = false, -- over the map's top edge instead of above it
    topBarZone = false,   -- the zone after the subzone
    topBarPvP = true,     -- colour the name by PvP status
    bottomBar = true,
    bottomBarInside = false,
    barCoords = true,
    coordDecimals = 1,
    barZoom = true,       -- the far view's radius, while zoomed out
    barClock = true,
    clock24 = true,
    clockServer = false,  -- the realm's time instead of this computer's
    replaceOthers = true, -- switch off other clocks / coordinates / zone text our bars replace
    barFont = 11,         -- px
    barAlpha = 0.8,       -- background opacity
    hideZoneHeader = true, -- the game's zone name above the minimap, while the top bar shows
    hideGameButtons = true, -- the game's calendar, tracking and addon-compartment buttons above it
    -- Mouse and mounting.
    recenterMiddle = true, -- middle-click recenters
    recenterDouble = true, -- double-click on the far map recenters
    rightClickPing = true, -- right-click on the far map pings, where the native map reaches
    mountZoom = true,      -- zoom out on mounting, recenter on dismounting
    mountRadius = 800,     -- yd, the mounted view
}

-- Numeric settings: min, max, and whether they're whole numbers. Load clamps every one of them,
-- and the settings window uses the same ranges for its sliders.
Settings.RANGES = {
    size = { Settings.SIZE_MIN, Settings.SIZE_MAX, true },
    maxFarZoom = { Settings.FAR_MIN, Settings.FAR_MAX, true },
    routeWidth = { 0.5, 6 },
    routeAlpha = { 0.1, 1 },
    arrowScale = { 0.4, 2 },
    questAreaFill = { 0, 1 },
    questAreaBorder = { 0, 1 },
    coordDecimals = { 0, 2, true },
    barFont = { 8, 18, true },
    barAlpha = { 0, 1 },
    mountRadius = { 300, Settings.FAR_MAX, true },
}

-- Clamps a value for a numeric setting; anything that isn't a number gets the default.
function Settings.Clamp(key, n)
    local r = Settings.RANGES[key]
    n = tonumber(n) or Settings.DEFAULTS[key]
    if not r then return n end
    if r[3] then n = math.floor(n + 0.5) end
    return math.max(r[1], math.min(r[2], n))
end

function Settings.ClampSize(n) return Settings.Clamp("size", n) end
function Settings.ClampMaxFar(n) return Settings.Clamp("maxFarZoom", n) end

-- Fills missing keys with defaults and clamps values. Reuses the saved table so the game writes
-- back the same object.
function Settings.Load(saved)
    local db = type(saved) == "table" and saved or {}
    -- v1 saved locked = true as an unused default; v2 makes the lock real, so start unlocked.
    if (tonumber(db.version) or 0) < 2 and db.locked == true then db.locked = false end
    -- v3's quest-area opacity defaults drew solid bright blue; move anyone still on them.
    if (tonumber(db.version) or 0) < 4 then
        if db.questAreaFill == 0.5 then db.questAreaFill = nil end
        if db.questAreaBorder == 0.75 then db.questAreaBorder = nil end
    end
    for k, v in pairs(Settings.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    for k in pairs(Settings.RANGES) do db[k] = Settings.Clamp(k, db[k]) end
    -- Per-category icon preferences (IconPrefs). Not in DEFAULTS: a table default would be shared.
    if type(db.icons) ~= "table" then db.icons = {} end
    -- LibDBIcon's saved state for the minimap button ({ hide, minimapPos }); same reason.
    if type(db.minimapButton) ~= "table" then db.minimapButton = {} end
    -- Names of the game's tracking entries NativeIcons switched off, to switch back on; same reason.
    if type(db.nativeOff) ~= "table" then db.nativeOff = {} end
    -- Other addons' settings the bars switched off, to switch back on (Overrides); same reason.
    if type(db.overridden) ~= "table" then db.overridden = {} end
    if type(db.x) ~= "number" or type(db.y) ~= "number" then
        db.x, db.y = nil, nil
    end
    db.version = Settings.VERSION
    return db
end
