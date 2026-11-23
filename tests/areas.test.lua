-- Quest areas on the far view (Far/Areas.lua): which zones get a QuestPOIFrame, where it sits on
-- the canvas, and what it draws. The game's widget is a stub that records its calls.
local H = ...

local function noop() end

local made, calls
local function Widget(kind, _, parent)
    local f = { kind = kind, shown = true, points = {}, scripts = {} }
    f.Show = function(self) self.shown = true end
    f.Hide = function(self) self.shown = false end
    f.IsShown = function(self) return self.shown end
    f.SetFrameLevel, f.EnableMouse, f.ClearAllPoints = noop, noop, function(self) self.points = {} end
    f.SetPoint = function(self, ...) self.points = { ... } end
    f.SetSize = function(self, w, h) self.w, self.h = w, h end
    f.RegisterEvent = noop
    f.GetParent = function(self) return self.parent end
    f.SetParent = function(self, p) self.parent = p end
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    for _, m in ipairs({ "SetMapID", "SetFillTexture", "SetBorderTexture", "SetBorderScalar", "DrawNone",
        "DrawAll", "DrawBlob", "SetFillAlpha", "SetBorderAlpha", "EnableMerging", "EnableSmoothing" }) do
        f[m] = function(_, ...) calls[#calls + 1] = { m, ... } end
    end
    if kind ~= "QuestPOIFrame" then f.SetMapID = nil end
    f.parent = parent
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
    C_QuestLog = _G.C_QuestLog, QuestieLoader = _G.QuestieLoader }
local ns, Areas

local function Fresh()
    made, calls = {}, {}
    _G.CreateFrame = Widget
    _G.C_Map = MAP
    _G.CreateVector2D = Vec
    _G.C_QuestLog = { GetNumQuestWatches = function() return 2 end,
        GetQuestIDForQuestWatchIndex = function(i) return 100 + i end,
        GetNumQuestLogEntries = function() return 4 end,
        GetInfo = function(i) return i == 1 and { isHeader = true } or { questID = 200 + i } end }
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
    local ids = {}
    for _, c in ipairs(calls) do if c[1] == "DrawBlob" then ids[#ids + 1] = c[2] end end
    H.eq(#ids, 5, "the log's quests (headers skipped) and the tracked ones (DrawAll draws nothing on Forever)")
    H.eq(ids[1], 101)
    H.truthy(Called("EnableMerging"), "overlapping areas merge")
end)

H.test("all quests: Questie's list too (it has quests under collapsed headers), each once", function()
    _G.QuestieLoader = { ImportModule = function(_, name)
        if name == "QuestLogCache" then return { questLog_DO_NOT_MODIFY = { [500] = {}, [101] = {} } } end
    end }
    local ids = Areas.AllQuests({ 101, 102 })
    _G.QuestieLoader = nil
    H.eq(#ids, 6, "500 and 101 from Questie, 202-204 from the log, 102 tracked; 101 once")
    H.eq(ids[6], 500)
end)

H.test("assign: a quest on two overlapping zone maps is drawn by one zone only", function()
    local owner = Areas.Assign({
        [1413] = { { questID = 7, mapID = 1413, x = 0.95, y = 0.5 }, { questID = 8, mapID = 1440, x = 0.1, y = 0.5 } },
        [1411] = { { questID = 7, mapID = 1413, x = 0.02, y = 0.5 }, { questID = 8, mapID = 1440, x = 0.45, y = 0.5 } },
    })
    H.eq(owner[7], 1413, "its own zone wins even near the edge")
    H.eq(owner[8], 1411, "otherwise the zone where it's nearest the middle")
end)

H.test("each frame draws only the quests it owns", function()
    _G.C_QuestLog.GetQuestsOnMap = function(map)
        if map == 1413 then return { { questID = 202, mapID = 1413, x = 0.5, y = 0.5 }, { questID = 203, mapID = 1411, x = 0.9, y = 0.5 } } end
        return { { questID = 202, mapID = 1413, x = 0.05, y = 0.5 }, { questID = 203, mapID = 1411, x = 0.5, y = 0.5 } }
    end
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, 0, -1900, 300) -- both zones in view
    local per = {}
    for _, c in ipairs(calls) do
        if c[1] == "DrawBlob" then per[c[2]] = (per[c[2]] or 0) + 1 end
    end
    H.eq(per[202], 1, "drawn once, not by both zones")
    H.eq(per[203], 1)
    _G.C_QuestLog.GetQuestsOnMap = nil
end)

H.test("a zoom redraws the areas on the next frame", function()
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300)
    calls = {}
    Areas.SetLayout(1, 0, -1000, 0.2)
    Areas.Update(1.01, -1000, -1000, 150)
    H.truthy(Called("DrawBlob"), "redrawn at the new size")
    H.near(POIs()[1].w, 400, 1e-9)
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

H.test("round map strips: fill the circle top to bottom, none past its edge", function()
    local r = 100
    local rows = Areas.Strips(r, 6)
    H.eq(#rows, 9)
    for _, row in ipairs(rows) do
        H.truthy(row.top > row.bottom)
        local far = math.max(math.abs(row.top), math.abs(row.bottom))
        H.truthy(row.half * row.half + far * far <= r * r + 1e-9, "a corner is inside the circle")
    end
    table.sort(rows, function(a, b) return a.top > b.top end)
    for i = 2, #rows do H.near(rows[i].top, rows[i - 1].bottom, 1e-9, "no gaps between rows") end
    H.truthy(rows[1].top > 0.95 * r, "reaches near the top")
end)

H.test("round map: each zone drawn once per strip, hidden while a zoom moves", function()
    ns.db.round = true
    local canvas = Widget("Frame")
    local viewFrame = Widget("Frame")
    canvas.GetParent = function() return viewFrame end
    Areas.Build(canvas, 5)
    Areas.SetLayout(1, 0, -1000, 0.1)
    Areas.Update(1, -1000, -1000, 300, false)
    H.eq(Areas.ShownFrames(), 9, "one zone in view, nine strips")
    Areas.Update(1.01, -1000, -1000, 300, true)
    H.eq(Areas.ShownFrames(), 0, "zooming: hidden")
    Areas.Update(1.02, -1000, -1000, 300, false)
    H.eq(Areas.ShownFrames(), 0, "settled: drawn on the next frame, once sizes apply")
    local before = #calls
    Areas.Update(1.03, -1000, -1000, 300, false)
    H.eq(Areas.ShownFrames(), 9, "back")
    local drew = 0
    for i = before + 1, #calls do if calls[i][1] == "DrawBlob" then drew = drew + 1 end end
    H.truthy(drew > 0, "and painted afresh")
    ns.db.round = false
    Areas.Refresh()
    H.eq(Areas.ShownFrames(), 1, "square again: one frame")
end)

for k, v in pairs(saved) do _G[k] = v end
