-- Quest areas on the far view (Far/Areas.lua): which zones get a QuestPOIFrame, where it sits on
-- the canvas, and what it draws. The game's widget is a stub that records its calls.
local H = ...

local function noop() end

local made, calls
local function Widget(kind)
    local f = { kind = kind, shown = true, points = {}, scripts = {} }
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetFrameLevel, f.EnableMouse, f.ClearAllPoints = noop, noop, function(self) self.points = {} end
    f.SetPoint = function(self, ...) self.points = { ... } end
    f.SetSize = function(self, w, h) self.w, self.h = w, h end
    f.RegisterEvent = noop
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    for _, m in ipairs({ "SetMapID", "SetFillTexture", "SetBorderTexture", "SetBorderScalar", "DrawNone",
        "DrawAll", "DrawBlob", "SetFillAlpha", "SetBorderAlpha" }) do
        f[m] = function(_, ...) calls[#calls + 1] = { m, ... } end
    end
    if kind ~= "QuestPOIFrame" then f.SetMapID = nil end
    made[#made + 1] = f
    return f
end

-- Kalimdor (1414) with two zones: Barrens (1413) and Durotar (1411), world rects in yards.
local RECTS = { [1413] = { 1, 1000, 0, -3000, -2000 }, [1411] = { 1, 1000, -2000, -500, -3500 } }
local function Vec(x, y) return { x = x, y = y } end
local MAP = {
    GetBestMapForUnit = function() return 1413 end,
    GetMapInfo = function(id)
        if id == 1414 then return { mapID = 1414, mapType = 2 } end
        return { mapID = id, mapType = 3, parentMapID = 1414 }
    end,
    GetMapChildrenInfo = function() return { { mapID = 1413 }, { mapID = 1411 } } end,
    GetWorldPosFromMapPos = function(id, v)
        local r = RECTS[id]
        local n = v.x == 0 and r[2] or r[4]
        local w = v.x == 0 and r[3] or r[5]
        return r[1], { GetXY = function() return n, w end }
    end,
}

local saved = { CreateFrame = _G.CreateFrame, C_Map = _G.C_Map, CreateVector2D = _G.CreateVector2D,
    C_QuestLog = _G.C_QuestLog }
local ns, Areas

local function Fresh()
    made, calls = {}, {}
    _G.CreateFrame = Widget
    _G.C_Map = MAP
    _G.CreateVector2D = Vec
    _G.C_QuestLog = { GetNumQuestWatches = function() return 2 end,
        GetQuestIDForQuestWatchIndex = function(i) return 100 + i end }
    ns = { RegisterCommand = noop, IsSecret = function() return false end }
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/Geometry.lua", ns)
    H.loadAddonFile("Core/MapArt.lua", ns)
    ns.db = ns.Settings.Load(nil)
    H.loadAddonFile("Far/Areas.lua", ns)
    Areas = ns.Areas
    Areas.Build(Widget("Frame"), 5)
end
H.beforeEach(Fresh)

local function POIs()
    local out = {}
    for _, f in ipairs(made) do if f.kind == "QuestPOIFrame" then out[#out + 1] = f end end
    return out
end

local function Called(name)
    for _, c in ipairs(calls) do if c[1] == name then return c end end
end

H.test("overlap: a zone overlaps a square view that reaches it", function()
    local O = ns.MapArt.Overlaps
    H.truthy(O(1000, 0, -3000, -2000, -1000, -1000, 100), "view inside")
    H.truthy(O(1000, 0, -3000, -2000, 1050, -1000, 100), "view across the top edge")
    H.eq(O(1000, 0, -3000, -2000, 1200, -1000, 100), false, "view north of it")
    H.eq(O(1000, 0, -3000, -2000, 0, 500, 100), false, "view east of it")
end)

H.test("only zones in view get a frame, stretched over the zone's world rectangle", function()
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300) -- inside the Barrens, far from Durotar
    local p = POIs()
    H.eq(#p, 1)
    H.truthy(Called("SetMapID"))
    H.eq(Called("SetMapID")[2], 1413)
    H.near(p[1].w, 200, 1e-9); H.near(p[1].h, 400, 1e-9)
    H.eq(p[1].points[1], "TOPLEFT")
    H.near(p[1].points[4], -100, 1e-9); H.near(p[1].points[5], 100, 1e-9)
    H.truthy(Called("DrawAll"))
end)

H.test("zooming out over a border shows the next zone too", function()
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, 0, -1900, 300)
    H.eq(#POIs(), 2)
end)

H.test("opacity settings reach the widget as 0-255", function()
    ns.db.questAreaFill, ns.db.questAreaBorder = 0.2, 1
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300)
    H.eq(Called("SetFillAlpha")[2], 51)
    H.eq(Called("SetBorderAlpha")[2], 255)
end)

H.test("only tracked quests: one blob per watched quest, not all", function()
    ns.db.questAreaTracked = true
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300)
    H.eq(Called("DrawAll"), nil)
    local ids = {}
    for _, c in ipairs(calls) do if c[1] == "DrawBlob" then ids[#ids + 1] = c[2] end end
    H.eq(#ids, 2); H.eq(ids[1], 101)
end)

H.test("switched off, or leaving far mode, hides the frames", function()
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300)
    ns.db.questAreas = false
    Areas.Refresh()
    H.eq(POIs()[1].shown, false)
    ns.db.questAreas = true
    Areas.Refresh()
    H.eq(POIs()[1].shown, true)
    Areas.SetLayout(nil)
    H.eq(Areas.ShownFrames(), 0)
end)

H.test("a client without the widget: no frames, no errors", function()
    _G.CreateFrame = function(kind) if kind == "QuestPOIFrame" then error("unknown type") end return Widget(kind) end
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300)
    H.eq(#POIs(), 0)
end)

for k, v in pairs(saved) do _G[k] = v end
