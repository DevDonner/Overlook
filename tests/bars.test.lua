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
    H.loadAddonFile("Core/Host.lua", ns)
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

H.test("bars: with the top bar off ours move to the side column, so the game's stay hidden", function()
    Fresh()
    H.eq(GLOBALS.GameTimeFrame.alpha, 0)
    ns.db.topBar = false
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 0, "ours still stand in for them")
end)

H.test("bars: with no buttons of ours, the game's are back", function()
    Fresh()
    ns.db.buttonSpot = "none"
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 1)
    H.eq(GLOBALS.AddonCompartmentFrame.alpha, 1)
    ns.db.buttonSpot = "side"
    ns.db.barButtons = false
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 1, "ours switched off: theirs back")
end)

H.test("bars: hiding the game's buttons can be switched off on its own", function()
    Fresh()
    ns.db.hideGameButtons = false
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 1)
    ns.db.hideGameButtons = true
    B.Apply()
    H.eq(GLOBALS.GameTimeFrame.alpha, 0)
end)

H.test("bars: hiding the game's zone header can be switched off on its own", function()
    Fresh()
    H.eq(GLOBALS.MinimapCluster.ZoneTextButton.alpha, 0)
    ns.db.hideZoneHeader = false
    B.Apply()
    H.eq(GLOBALS.MinimapCluster.ZoneTextButton.alpha, 1)
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

----------------------------------------------------------------------------------------------------
-- Where our buttons go (Bars.ButtonSpots), and the side column

local function Spots(over, round)
    local db = { buttonSpot = "bars", barButtons = true, collectButtons = true, topBar = true, bottomBar = true }
    for k, v in pairs(over or {}) do db[k] = v end
    return ns.Bars.ButtonSpots(db, round)
end

H.test("button spots: on the bars by default", function()
    Fresh()
    local s = Spots()
    H.eq(s.calendar, "top"); H.eq(s.addons, "top"); H.eq(s.collect, "bottom")
end)

H.test("button spots: a bar that's off hands its buttons to the side column", function()
    Fresh()
    local s = Spots({ topBar = false })
    H.eq(s.calendar, "side"); H.eq(s.addons, "side"); H.eq(s.collect, "bottom")
    s = Spots({ bottomBar = false })
    H.eq(s.calendar, "top"); H.eq(s.collect, "side")
    s = Spots({ topBar = false, bottomBar = false })
    H.eq(s.calendar, "side"); H.eq(s.collect, "side")
end)

H.test("button spots: all in the column, or none at all", function()
    Fresh()
    local s = Spots({ buttonSpot = "side" })
    H.eq(s.calendar, "side"); H.eq(s.addons, "side"); H.eq(s.collect, "side")
    s = Spots({ buttonSpot = "none" })
    H.eq(next(s), nil, "nothing")
end)

H.test("button spots: each kind can be switched off", function()
    Fresh()
    local s = Spots({ barButtons = false })
    H.eq(s.calendar, nil); H.eq(s.addons, nil); H.eq(s.collect, "bottom")
    s = Spots({ collectButtons = false })
    H.eq(s.calendar, "top"); H.eq(s.collect, nil)
end)

H.test("button spots: the round map's box, or the column when its rows are off", function()
    Fresh()
    local s = Spots(nil, true)
    H.eq(s.calendar, "pill"); H.eq(s.collect, "pill")
    s = Spots({ topBar = false }, true)
    H.eq(s.calendar, "side"); H.eq(s.collect, "pill", "the bottom row keeps the grid")
    s = Spots({ topBar = false, bottomBar = false }, true)
    H.eq(s.collect, "side")
    s = Spots({ buttonSpot = "side" }, true)
    H.eq(s.calendar, "side")
end)

H.test("game buttons: hidden only while ours stand in for them", function()
    Fresh()
    local HG = ns.Bars.HideGameButtons
    H.eq(HG({ hideGameButtons = true }, { calendar = "side" }), true)
    H.eq(HG({ hideGameButtons = true }, { collect = "bottom" }), false, "the panel arrow isn't a calendar")
    H.eq(HG({ hideGameButtons = false }, { calendar = "top" }), false)
end)

-- The side column is the eighth frame Build makes (after the strips and the round boxes).
local function FreshSide(over)
    local made = {}
    GLOBALS.CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end
    Fresh()
    GLOBALS.CreateFrame = function() return Obj() end
    for _, f in ipairs(made) do
        f.SetSize = function(self, w, h) self.w, self.h = w, h end
    end
    for k, v in pairs(over or {}) do ns.db[k] = v end
    B.Apply()
    return made[8], made
end

H.test("side column: hidden while every button sits on a bar", function()
    local side = FreshSide()
    H.eq(side.shown, false)
end)

H.test("side column: inside the map's top-left edge, a slot per button", function()
    local side = FreshSide({ buttonSpot = "side" })
    H.eq(side.shown, true)
    H.eq(side.points[1][1], "TOPLEFT"); H.eq(side.points[1][3], "TOPLEFT")
    H.eq(side.points[1][5], 0, "at the very top with no bar over the map")
    H.truthy(side.h >= 2 * 12, "room for the calendar and addons buttons")
end)

H.test("side column: on the right when asked, and below a top bar that sits over the map", function()
    local side = FreshSide({ buttonSpot = "side", buttonSide = "right", topBar = true, topBarInside = true })
    H.eq(side.points[1][1], "TOPRIGHT"); H.eq(side.points[1][3], "TOPRIGHT")
    H.truthy(side.points[1][5] < 0, "moved down under the top bar")
end)

H.test("side column: outside the circle on the round map, and kept on screen", function()
    local side = FreshSide({ buttonSpot = "side", round = true })
    H.eq(side.points[1][1], "TOPRIGHT"); H.eq(side.points[1][3], "TOPLEFT", "left of the circle")
    H.truthy(root.clamp[1] < 0, "the clamp rect grows left for it")
end)

H.test("compact preset: nothing above or below the map, the buttons at its side", function()
    local side = FreshSide()
    ns.Settings.ApplyPreset(ns.db, "compact")
    B.Apply()
    H.eq(root.clamp[3], 0, "the zone bar sits over the map")
    H.eq(root.clamp[4], 0, "no bottom bar")
    H.eq(side.shown, true)
end)

H.test("map only preset: no bars, no buttons, nothing of ours around the map", function()
    local side = FreshSide()
    ns.Settings.ApplyPreset(ns.db, "maponly")
    B.Apply()
    H.eq(root.clamp[3], 0); H.eq(root.clamp[4], 0)
    H.eq(side.shown, false)
    H.eq(GLOBALS.GameTimeFrame.alpha, 1, "the game's buttons aren't hidden for nothing")
end)

H.test("hosted: the round grid follows the host's shape and size, not our settings", function()
    local made = {}
    GLOBALS.CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end
    Fresh()
    GLOBALS.CreateFrame = function() return Obj() end
    ns.Host.owner, ns.Host.round, ns.Host.size = "EllesmereUI", true, 140
    B.Apply()
    H.eq(made[1].shown, false, "no strips: the host's map is round")
    H.eq(made[3].shown, true, "the name box")
    ns.Host.owner = nil
    B.Apply()
    H.eq(made[1].shown, true, "our own square again")
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
