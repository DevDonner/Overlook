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
    size = 300,           -- px, square
    locked = false,       -- hides the resize grip; Alt+drag still moves it
    maxFarZoom = 3000,    -- yd radius; setting goes up to 6,400
    worldZoom = false,    -- no limit: zoom out until the whole world shows (every tile loaded)
    rotate = false,       -- the game's rotating minimap, at normal zoom (Shell.SetRotate)
    clustering = false,
    smoothZoom = true,    -- tween far-zoom steps
    routes = true,        -- Questie's NPC routes on the far map
    routeWidth = 1.5,     -- px, far-map route lines
    routeAlpha = 1,       -- opacity of the far-map route lines (times Questie's own)
    partyDots = true,     -- party and raid members on the far map
    dungeonEntrances = true, -- dungeon and raid entrances, on both maps, with name and levels
    entranceScale = 1,    -- their icon size (1 = 20 px)
    nativeIcons = false,  -- the game's own quest and town icons (Questie draws them instead)
    arrowScale = 1,       -- player arrow size on the far map (1 = the native arrow's size)
    questAreas = true,    -- the game's blue quest areas on the far map
    questAreaFill = 0.15, -- their fill opacity (several quests' areas merge into one shape)
    questAreaBorder = 0.2, -- their border opacity
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
    round = false,        -- round map instead of square
    barButtons = true,    -- our calendar and addon buttons
    collectButtons = true, -- other addons' minimap buttons gathered into a panel (Shell/Buttons.lua)
    buttonsPerRow = 6,
    -- Where our buttons (calendar, addons, the minimap-button panel's arrow) go: "bars" (on the
    -- top and bottom bars; a bar that's off puts its buttons in the side column), "side" (a slim
    -- column inside the map's left or right edge, so the bars can go), or "none".
    buttonSpot = "bars",
    buttonSide = "left",
    buttonColumn = "inside", -- the side column over the map's edge, or "outside" against it (square map)
    -- Living with other addons (Core/Host.lua, Pins/Others.lua).
    hostOthers = true,     -- another addon owns the minimap frame (EllesmereUI): fit inside its map
    claimShape = true,     -- answer GetMinimapShape for the map, so pins sit right on the square
    keepOthersVisible = true, -- other addons' buttons, text and borders on the map stay over the far map
    captureOthers = true,  -- other addons' drawings on the minimap copied onto the far map
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
    entranceScale = { 0.4, 2.5 },
    questAreaFill = { 0, 1 },
    questAreaBorder = { 0, 1 },
    coordDecimals = { 0, 2, true },
    barFont = { 8, 18, true },
    barAlpha = { 0, 1 },
    mountRadius = { 300, Settings.FAR_MAX, true },
    buttonsPerRow = { 2, 12, true },
}

-- Settings that take one of a few words. Load puts anything else back to the default.
Settings.CHOICES = {
    buttonSpot = { bars = true, side = true, none = true },
    buttonSide = { left = true, right = true },
    buttonColumn = { inside = true, outside = true },
}

-- The settings window's pick-one rows for the bars, over the two settings each bar has:
-- "outside" (above / below the map), "inside" (over its edge) or "off". Pure.
local BAR_KEYS = { top = { "topBar", "topBarInside" }, bottom = { "bottomBar", "bottomBarInside" } }

function Settings.BarPlace(db, which)
    local k = BAR_KEYS[which]
    if not db[k[1]] then return "off" end
    return db[k[2]] and "inside" or "outside"
end

function Settings.SetBarPlace(db, which, place)
    local k = BAR_KEYS[which]
    db[k[1]] = place ~= "off"
    if place ~= "off" then db[k[2]] = place == "inside" end
end

-- Layouts the settings window offers as one click. Each sets only the keys it lists.
--  full:    the bars above and below the map, the buttons on them (the defaults).
--  compact: the zone name over the map's top edge, no bottom bar, the buttons in a column
--           inside the map's edge: the map fills all the height it's given.
--  maponly: nothing but the map: no bars, no buttons (other addons' buttons are left alone).
Settings.PRESETS = {
    full = { topBar = true, topBarInside = false, bottomBar = true, bottomBarInside = false, buttonSpot = "bars" },
    compact = { topBar = true, topBarInside = true, bottomBar = false, buttonSpot = "side" },
    maponly = { topBar = false, bottomBar = false, buttonSpot = "none" },
}

-- Applies a preset to the settings. Returns false for an unknown name.
function Settings.ApplyPreset(db, name)
    local preset = Settings.PRESETS[name]
    if not preset then return false end
    for k, v in pairs(preset) do db[k] = v end
    return true
end

-- Which preset the settings match now, or nil.
function Settings.CurrentPreset(db)
    for _, name in ipairs({ "full", "compact", "maponly" }) do
        local match = true
        for k, v in pairs(Settings.PRESETS[name]) do
            if db[k] ~= v then match = false end
        end
        if match then return name end
    end
end

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
    for k, allowed in pairs(Settings.CHOICES) do
        if not allowed[db[k]] then db[k] = Settings.DEFAULTS[k] end
    end
    -- Per-category icon preferences (IconPrefs). Not in DEFAULTS: a table default would be shared.
    if type(db.icons) ~= "table" then db.icons = {} end
    -- welcomeSeen (UI/Welcome.lua) is kept as it is: account-wide, not in DEFAULTS, so profiles
    -- don't copy or reset it.
    if db.welcomeSeen ~= nil and type(db.welcomeSeen) ~= "boolean" then db.welcomeSeen = nil end
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
