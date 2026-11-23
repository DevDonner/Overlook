-- The top and bottom bars: their text (Core/BarText.lua), and a smoke test of Shell/Bars.lua on
-- stub frames (placement inside / outside, the clamp rect, the game's header).
local H = ...

local ns = H.loadAddonFile("Core/BarText.lua", {})
local T = ns.BarText

H.test("zone: the subzone, or the zone when there's none; the zone after it on request", function()
    H.eq(T.Zone("The Crossroads", "The Barrens", false), "The Crossroads")
    H.eq(T.Zone("", "The Barrens", true), "The Barrens")
    H.eq(T.Zone("The Barrens", "The Barrens", true), "The Barrens", "not twice")
    H.eq(T.Zone("The Crossroads", "The Barrens", true), "The Crossroads  |cff8a8f99The Barrens|r")
    H.eq(T.Zone("", "", true), "")
end)

H.test("zone colour: by PvP status only when asked", function()
    H.eq(T.ZoneColor("hostile", true), T.PVP.hostile)
    H.eq(T.ZoneColor("hostile", false), T.NEUTRAL)
    H.eq(T.ZoneColor(nil, true), T.NEUTRAL)
end)

H.test("coordinates: percent with 0-2 decimals, dashes where there are none", function()
    H.eq(T.Coords(0.5123, 0.25, 1), "51.2, 25.0")
    H.eq(T.Coords(0.5123, 0.25, 0), "51, 25")
    H.eq(T.Coords(0.5123, 0.25, 2), "51.23, 25.00")
    H.eq(T.Coords(nil, nil, 1), "--")
    H.eq(T.Coords(0, 0, 1), "--", "the game's answer inside instances")
end)

H.test("clock: 24-hour and 12-hour", function()
    H.eq(T.Clock(7, 5, true), "07:05")
    H.eq(T.Clock(0, 30, false), "12:30 AM")
    H.eq(T.Clock(12, 0, false), "12:00 PM")
    H.eq(T.Clock(23, 59, false), "11:59 PM")
end)

H.test("yards: with thousands separators, empty in near mode", function()
    H.eq(T.Yards(1249.6), "1,250 yd")
    H.eq(T.Yards(640), "640 yd")
    H.eq(T.Yards(6400), "6,400 yd")
    H.eq(T.Yards(nil), "")
end)

----------------------------------------------------------------------------------------------------
-- Shell/Bars.lua on stub frames

local function noop() end
local function Obj()
    local o = { shown = true, points = {}, alpha = 1 }
    o.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    o.ClearAllPoints = function(self) self.points = {} end
    o.SetShown = function(self, v) self.shown = v end
    o.IsShown = function(self) return self.shown end
    o.SetAlpha = function(self, a) self.alpha = a end
    o.SetClampRectInsets = function(self, ...) self.clamp = { ... } end
    o.SetHeight = function(self, h) self.height = h end
    o.SetText = function(self, t) self.text = t end
    o.CreateFontString = function() return Obj() end
    o.CreateTexture = function() return Obj() end
    return setmetatable(o, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })
end

local saved = {}
local GLOBALS = {
    CreateFrame = function() return Obj() end,
    GetMinimapZoneText = function() return "The Crossroads" end,
    GetZoneText = function() return "The Barrens" end,
    GetZonePVPInfo = function() return "contested" end,
    date = function(f) return f == "%H" and "13" or "07" end,
    MinimapCluster = { ZoneTextButton = Obj(), BorderTop = Obj(), Tracking = Obj() },
    GameTimeFrame = Obj(),
    AddonCompartmentFrame = Obj(),
}
for k in pairs(GLOBALS) do saved[k] = _G[k] end

local B, root
local function Fresh()
    for k, v in pairs(GLOBALS) do _G[k] = v end
    GLOBALS.MinimapCluster.ZoneTextButton.alpha = 1
    ns = { IsSecret = function() return false end }
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/BarText.lua", ns)
    ns.db = ns.Settings.Load(nil)
    ns.Far = { Radius = function() return 1500 end }
    H.loadAddonFile("Shell/Bars.lua", ns)
    B = ns.Bars
    root = Obj()
    B.Build(root, 3011)
end

H.test("bars: outside by default, the clamp rect grows to keep them on screen", function()
    Fresh()
    local h = ns.db.barFont + 10
    H.eq(root.clamp[3], h - 1); H.eq(root.clamp[4], -(h - 1))
    H.eq(GLOBALS.MinimapCluster.ZoneTextButton.alpha, 0, "the game's header is hidden")
end)

H.test("bars: inside, or switched off, the clamp rect is the map's own", function()
    Fresh()
    ns.db.topBarInside, ns.db.bottomBar = true, false
    B.Apply()
    H.eq(root.clamp[3], 0); H.eq(root.clamp[4], 0)
    ns.db.topBar = false
    B.Apply()
    H.eq(GLOBALS.MinimapCluster.ZoneTextButton.alpha, 1, "the game's header comes back")
end)

H.test("bars: the game's calendar, tracking and addon buttons hide, and come back", function()
    Fresh()
    H.eq(GLOBALS.GameTimeFrame.alpha, 0)
    H.eq(GLOBALS.AddonCompartmentFrame.alpha, 0)
    H.eq(GLOBALS.MinimapCluster.Tracking.alpha, 0)
    ns.db.hideGameButtons = false
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 1)
    H.eq(GLOBALS.MinimapCluster.Tracking.alpha, 1)
end)

H.test("bars: with the top bar off, the game's buttons are back (ours are on that bar)", function()
    Fresh()
    H.eq(GLOBALS.GameTimeFrame.alpha, 0)
    ns.db.topBar = false
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 1)
    H.eq(GLOBALS.AddonCompartmentFrame.alpha, 1)
end)

-- Round map: the strips go, four boxes under the circle (frames made in Build's order: top,
-- bottom, then the name, buttons, coordinates and clock boxes).
local function FreshRound()
    local made = {}
    GLOBALS.CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end
    Fresh()
    GLOBALS.CreateFrame = function() return Obj() end
    ns.db.round = true
    B.Apply()
    return { top = made[1], bottom = made[2], name = made[3], buttons = made[4], coords = made[5], clock = made[6],
        zoom = made[7] }
end

H.test("round bars: no strips; name, buttons, coordinates and clock in boxes under the circle", function()
    local f = FreshRound()
    H.eq(f.top.shown, false); H.eq(f.bottom.shown, false)
    H.eq(f.name.shown, true); H.eq(f.coords.shown, true); H.eq(f.clock.shown, true)
    H.eq(f.name.points[1][1], "TOPLEFT"); H.eq(f.name.points[1][3], "BOTTOMLEFT")
    H.eq(f.buttons.points[1][1], "TOPRIGHT"); H.eq(f.buttons.points[1][3], "BOTTOMRIGHT")
    local h = ns.db.barFont + 10
    H.eq(f.coords.points[1][5], -(3 + h + 3), "the second row under the first")
    H.eq(root.clamp[3], 0, "nothing above the circle")
    H.eq(root.clamp[4], -(3 + h + 3 + h), "both rows kept on screen")
end)

H.test("round bars: the bar settings still choose what shows", function()
    local f = FreshRound()
    ns.db.topBar = false
    B.Apply()
    H.eq(f.name.shown, false)
    H.eq(f.buttons.shown, true, "the minimap-buttons button keeps the first row")
    ns.db.barClock = false
    B.Apply()
    H.eq(f.clock.shown, false); H.eq(f.coords.shown, true)
    ns.db.bottomBar = false
    B.Apply()
    H.eq(f.coords.shown, false)
end)

H.test("round bars: the zoom distance in the middle of the second row, while zoomed out", function()
    local f = FreshRound()
    H.eq(f.zoom.points[1][1], "TOP"); H.eq(f.zoom.points[1][3], "BOTTOM")
    H.eq(f.zoom.shown, true, "1,500 yd out")
    ns.Far.Radius = function() return nil end -- back at normal zoom
    B.Apply()
    H.eq(f.zoom.shown, false)
    ns.Far.Radius = function() return 1500 end
    ns.db.barZoom = false
    B.Apply()
    H.eq(f.zoom.shown, false, "its setting off")
end)

H.test("round bars: back to the strips on the square map", function()
    local f = FreshRound()
    ns.db.round = false
    B.Apply()
    H.eq(f.top.shown, true); H.eq(f.bottom.shown, true)
    H.eq(f.name.shown, false); H.eq(f.clock.shown, false)
    H.eq(B.InsideBottomHeight(), 0)
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
