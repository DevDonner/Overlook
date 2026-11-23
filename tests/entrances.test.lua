-- Dungeon and raid entrances: places from the vendored table, the normal minimap's offsets
-- (north up and rotating, square and round), and the tooltip's level ranges.
local H = ...
local ns = H.loadAddonFile("Core/EntranceMath.lua", {})
H.loadAddonFile("Data/Entrances.lua", ns)
local EM = ns.EntranceMath

local function vec(x, y) return { x = x, y = y } end
local api = {
    GetWorldPosFromMapPos = function(mapID, pos)
        if mapID == 1455 then
            return 0, { GetXY = function() return -1000 + pos.x, 2000 + pos.y end }
        end
        return nil
    end,
}

H.test("places: world-yard entries as given, zone-map spots placed, shared entrances grouped", function()
    local list = EM.Resolve(ns.MapEntrances, api, vec)
    local byName = {}
    for _, p in ipairs(list) do
        for _, d in ipairs(p.list) do byName[d.name] = p end
    end
    local sfk = byName["Shadowfang Keep"]
    H.eq(sfk.inst, 0); H.eq(sfk.n, -231.0); H.eq(sfk.w, 1571.6)
    H.eq(sfk.list[1].min, 20); H.eq(sfk.list[1].max, 30); H.eq(sfk.raid, false)
    local thanes = byName["The Hall of Thanes"]
    H.eq(thanes.inst, 0); H.near(thanes.n, -1000 + 0.277, 1e-9)
    H.eq(byName["Alcaz Prison"], nil, "a spot the client can't place is left out")
    local brm = byName["Molten Core"]
    H.eq(brm, byName["Lower Blackrock Spire"], "one entrance for Blackrock Mountain")
    H.eq(brm.raid, false, "dungeons and raids together: a dungeon icon")
    H.eq(byName["Onyxia's Lair"].raid, true)
end)

H.test("places: nothing to place without data or a client", function()
    H.eq(#EM.Resolve(nil), 0)
    H.eq(#EM.Resolve({ instances = { { nil, 0.5, 0.5, { { 1, "X", false, 1, 2 } }, map = 9 } } }), 0)
end)

H.test("normal minimap: north up, east is right; outside the edge is hidden", function()
    -- player at 0,0; 100 px half width over 200 yd
    local x, y = EM.NativeOffset(100, -50, 0, 0, 100, 200)
    H.near(x, 25, 1e-9, "50 yd east"); H.near(y, 50, 1e-9, "100 yd north")
    H.eq(EM.NativeOffset(0, -300, 0, 0, 100, 200), nil, "past the edge")
    H.eq(EM.NativeOffset(0, -190, 0, 0, 100, 200, nil, false, 10), nil, "inside the margin")
end)

H.test("normal minimap: square corners show, round ones don't", function()
    H.truthy(EM.NativeOffset(180, -180, 0, 0, 100, 200, nil, false))
    H.eq(EM.NativeOffset(180, -180, 0, 0, 100, 200, nil, true), nil)
end)

H.test("normal minimap: rotating, what you face is up", function()
    -- facing west (pi/2): an entrance due west is straight up
    local x, y = EM.NativeOffset(0, 100, 0, 0, 100, 200, math.pi / 2)
    H.near(x, 0, 1e-9); H.near(y, 50, 1e-9)
    -- facing east: one due north is on the left
    x, y = EM.NativeOffset(100, 0, 0, 0, 100, 200, -math.pi / 2)
    H.near(x, -50, 1e-9); H.near(y, 0, 1e-9)
end)

H.test("levels: range text and which level colours it", function()
    H.eq(EM.Range(15, 24), "15-24"); H.eq(EM.Range(60, 60), "60"); H.eq(EM.Range(nil), "")
    H.eq(EM.ColorLevel(15, 24, 10), 15, "above you: its low end")
    H.eq(EM.ColorLevel(15, 24, 20), nil, "yours: the difficult colour")
    H.eq(EM.ColorLevel(15, 24, 40), 22, "below you: green or grey")
end)

H.test("drawing: both maps place pins, hover shows the levels, off hides them", function()
    local function noop() end
    local frames = {}
    local function Obj()
        local o = { shown = false, points = {} }
        setmetatable(o, { __index = function() return noop end })
        o.Show = function(self) self.shown = true end
        o.Hide = function(self) self.shown = false end
        o.IsShown = function(self) return self.shown end
        o.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
        return o
    end
    local function Frame()
        local f = Obj()
        f.CreateTexture = function() return Obj() end
        f.SetScript = function(self, k, fn) self[k] = fn end
        f.GetCenter = function() return 0, 0 end
        f.GetEffectiveScale = function() return 1 end
        f.GetFrameLevel = function() return 1 end
        frames[#frames + 1] = f
        return f
    end
    local tip = { lines = {} }
    setmetatable(tip, { __index = function() return noop end })
    tip.AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = a .. " " .. b end
    tip.IsOwned = function() return true end
    local kept = {}
    local env = {
        CreateFrame = function() return Frame() end, GameTooltip = tip,
        Minimap = Frame(), C_Minimap = { GetViewRadius = function() return 200 end },
        UnitPosition = function() return -231, 1571.6 + 50, 0, 0 end,
        UnitLevel = function() return 25 end, GetPlayerFacing = function() return 0 end,
        GetCVar = function() return "0" end, GetCursorPosition = function() return 0, 0 end,
        GetQuestDifficultyColor = function() return { r = 0, g = 1, b = 0 } end,
        C_Map = api, CreateVector2D = vec,
    }
    env.Minimap.GetWidth = function() return 200 end
    env.Minimap.GetScale = function() return 1 end
    env.Minimap.IsVisible = function() return true end
    for k, v in pairs(env) do kept[k] = _G[k]; _G[k] = v end
    ns.Geometry = H.loadAddonFile("Core/Geometry.lua", {}).Geometry
    ns.IsSecret = function() return false end
    ns.db = { dungeonEntrances = true }
    H.loadAddonFile("Pins/Entrances.lua", ns)
    local E = ns.Entrances
    E.BuildNative()
    local nativeLayer = frames[#frames]
    nativeLayer.OnUpdate(nativeLayer, 1)
    local shown = 0
    for _, f in ipairs(frames) do if f.shown and rawget(f, "place") then shown = shown + 1 end end
    H.eq(shown, 1, "Shadowfang Keep, 50 yd away, on the normal minimap")

    local canvas = Frame()
    E.Build(canvas, Frame(), 5)
    E.SetLayout(0, -231, 1571.6, 1)
    local place = E.UnderCursor()
    H.truthy(place, "the far map's pin is under the cursor")
    E.SetHover(place)
    H.eq(tip.lines[1], "Shadowfang Keep 20-30")

    ns.db.entranceScale = 2
    E.Refresh()
    local sized
    for _, f in ipairs(frames) do
        if rawget(f, "place") then
            f.SetSize = function(_, w) sized = w end
        end
    end
    nativeLayer.OnUpdate(nativeLayer, 1)
    H.eq(sized, 40, "entrance size 2: 40 px")

    ns.db.dungeonEntrances = false
    E.Refresh()
    H.eq(E.UnderCursor(), nil, "off: nothing on the far map")
    shown = 0
    for _, f in ipairs(frames) do if f.shown and rawget(f, "place") then shown = shown + 1 end end
    H.eq(shown, 0, "off: nothing on the normal minimap")
    for k in pairs(env) do _G[k] = kept[k] end
end)
