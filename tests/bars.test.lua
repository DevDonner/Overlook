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
    return setmetatable(o, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })
end

local saved = {}
local GLOBALS = {
    CreateFrame = function() return Obj() end,
    GetMinimapZoneText = function() return "The Crossroads" end,
    GetZoneText = function() return "The Barrens" end,
    GetZonePVPInfo = function() return "contested" end,
    date = function(f) return f == "%H" and "13" or "07" end,
    MinimapCluster = { ZoneTextButton = Obj(), BorderTop = Obj() },
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

for k in pairs(GLOBALS) do _G[k] = saved[k] end
