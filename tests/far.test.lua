-- Far view state contract tests with stub frames and a fake clock: handing back to the native
-- minimap (cover and fade), backing out during the fade, loading screens and continent changes.
local H = ...

local function noop() end

-- A stub frame or texture: unknown methods are no-ops; the state these tests read is real.
local function NewObj()
    local o = { shown = true, alpha = 1, mouse = true, scripts = {} }
    o.Show = function(self) self.shown = true end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown end
    o.SetShown = function(self, v) self.shown = v and true or false end
    o.SetAlpha = function(self, a) self.alpha = a end
    o.GetAlpha = function(self) return self.alpha end
    o.EnableMouse = function(self, v) self.mouse = v end
    o.IsMouseEnabled = function(self) return self.mouse end
    o.SetScript = function(self, k, f) self.scripts[k] = f end
    o.GetScript = function(self, k) return self.scripts[k] end
    o.HookScript = noop
    o.CreateTexture = function() return NewObj() end
    o.CreateFontString = function() return NewObj() end
    o.SetTexture = function(self, f) self.file = f end
    o.GetEffectiveScale = function() return 1 end
    o.GetCenter = function() return 0, 0 end
    o.IsMouseOver = function() return false end
    o.GetParent = function() return NewObj() end
    return setmetatable(o, {
        __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then return noop end
        end,
    })
end

local clock, pos, zoom, indoors, alt, best

local function V(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

-- A fake C_Map. 100 and 101: two floors of a dungeon on instance 33 (no terrain), 1,000 yd square.
-- 1458: Undercity on instance 0, under the terrain.
local MAPS = {
    [100] = { inst = 33, top = 500, left = 300, mapType = 4, name = "Upper", group = 7, h = 1 },
    [101] = { inst = 33, top = 500, left = 300, mapType = 4, name = "Lower", group = 7, h = 2 },
    [1458] = { inst = 0, top = -8000, left = 200, mapType = 3, name = "Undercity" },
}
local CMap = {
    GetBestMapForUnit = function() return best end,
    GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, mapType = m.mapType } end,
    GetMapArtLayers = function(id)
        if MAPS[id] then return { { layerWidth = 400, layerHeight = 400, tileWidth = 256, tileHeight = 256 } } end
    end,
    GetMapArtLayerTextures = function(id) if MAPS[id] then return { id * 10 + 1, id * 10 + 2, id * 10 + 3, id * 10 + 4 } end end,
    GetWorldPosFromMapPos = function(id, p)
        local m = MAPS[id]
        if m then return m.inst, V(m.top - p.y * 1000, m.left - p.x * 1000) end
    end,
    GetPlayerMapPosition = function(id) if MAPS[id] then return V(0.5, 0.5) end end,
    GetMapGroupID = function(id) return MAPS[id] and MAPS[id].group end,
    GetMapGroupMembersInfo = function()
        return { { mapID = 101, name = "Lower", relativeHeightIndex = 2 }, { mapID = 100, name = "Upper", relativeHeightIndex = 1 } }
    end,
}

local GLOBALS = {
    C_Map = CMap,
    CreateVector2D = V,
    IsIndoors = function() return indoors end,
    IsAltKeyDown = function() return alt end,
    GetTime = function() return clock end,
    UnitPosition = function() if pos then return pos[1], pos[2], 0, pos[3] end end,
    GetCursorPosition = function() return 0, 0 end,
    IsMouseButtonDown = function() return false end,
    IsControlKeyDown = function() return false end,
    GetPlayerFacing = function() return 0 end,
}
local saved = {}
for k in pairs(GLOBALS) do saved[k] = _G[k] end
saved.Minimap, saved.CreateFrame = _G.Minimap, _G.CreateFrame

local ns, Far, view, OnUpdate

local function Fresh()
    clock, pos, zoom, indoors, alt, best = 100, { -8949, -132, 0 }, 0, false, false, nil
    for k, v in pairs(GLOBALS) do _G[k] = v end
    local minimap = NewObj()
    minimap.GetZoom = function() return zoom end
    minimap.GetZoomLevels = function() return 5 end
    minimap.SetZoom = function(_, z) zoom = z end
    _G.Minimap = minimap

    ns = {
        RegisterCommand = noop, Print = noop, Printf = noop, Show = tostring,
        IsSecret = function() return false end,
        db = { size = 200, maxFarZoom = 2000, smoothZoom = false },
        MapMinimap = { [0] = {}, [1] = {} }, -- continents 0 and 1 have tiles (no art needed here)
    }
    local made = {}
    _G.CreateFrame = function() local f = NewObj(); made[#made + 1] = f; return f end
    H.loadAddonFile("Core/Geometry.lua", ns)
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/Zoom.lua", ns)
    H.loadAddonFile("Core/MapArt.lua", ns)
    H.loadAddonFile("Core/CaveMath.lua", ns)
    H.loadAddonFile("Far/Far.lua", ns)
    H.loadAddonFile("Far/Art.lua", ns)
    H.loadAddonFile("Far/Caves.lua", ns)
    Far = ns.Far
    Far.Build(NewObj(), 10)
    view = nil -- the far view: the frame with both OnUpdate and OnMouseWheel
    for _, f in ipairs(made) do
        if f.scripts.OnUpdate and f.scripts.OnMouseWheel then view = f end
    end
    OnUpdate = view.scripts.OnUpdate
end
H.beforeEach(Fresh)

local function Frame(dt)
    clock = clock + (dt or 0.016)
    OnUpdate(view, dt or 0.016)
end

-- Enters far mode one step out and lets the zoom settle.
local function GoFar()
    H.truthy(Far.Enter(), "entered far mode")
    Frame()
    H.truthy(Far.IsActive())
end

-- Zooms back in until far mode hands back to the native minimap.
local function HandBack()
    Far.Step(1)
    Frame()
    H.eq(Far.IsActive(), false, "handed back")
end

H.test("far mode hides the native minimap and shows the far view", function()
    GoFar()
    H.eq(Minimap.alpha, 0)
    H.eq(view.shown, true)
end)

H.test("zooming back in hands back: native map shown, far view stays on top as a cover", function()
    GoFar()
    HandBack()
    H.eq(Minimap.alpha, 1, "native map visible again")
    H.eq(view.shown, true, "far view still covering")
    H.eq(view.alpha, 1, "opaque during the hold")
    H.eq(view.mouse, false, "the cover never takes the mouse")
end)

H.test("the cover holds 0.15 s, fades over 0.25 s, then hides and takes the mouse again", function()
    GoFar()
    HandBack()
    Frame(0.1)
    H.eq(view.alpha, 1, "still holding")
    Frame(0.05 + 0.125) -- 0.15 s hold + half the fade
    H.near(view.alpha, 0.5, 0.1, "half faded")
    Frame(0.2)
    H.eq(view.shown, false, "hidden after the fade")
    H.eq(view.alpha, 1, "alpha reset for next time")
    H.eq(view.mouse, true, "mouse back for next time")
end)

H.test("wheeling out during the fade resumes far mode at once", function()
    GoFar()
    HandBack()
    Frame(0.2) -- mid-fade
    H.truthy(Far.Enter(), "entered again")
    H.truthy(Far.IsActive())
    H.eq(view.shown, true)
    H.eq(view.alpha, 1, "no half-faded far view")
    H.eq(view.mouse, true, "takes the mouse again")
    Frame()
    H.truthy(Far.IsActive(), "the old fade doesn't end far mode")
end)

H.test("a loading screen (no position) leaves at once, with no cover", function()
    GoFar()
    pos = nil
    Frame()
    H.eq(Far.IsActive(), false)
    H.eq(view.shown, false, "no cover over a loading screen")
    H.eq(Minimap.alpha, 1)
end)

H.test("moving to a continent without tiles leaves at once", function()
    GoFar()
    pos = { 100, 100, 9 }
    Frame()
    H.eq(Far.IsActive(), false)
    H.eq(view.shown, false)
end)

H.test("moving to another continent with tiles stays in far mode", function()
    GoFar()
    pos = { 100, 100, 1 }
    Frame()
    H.truthy(Far.IsActive())
    H.eq(view.shown, true)
end)

H.test("no tiles for this continent: far mode never starts", function()
    pos = { 100, 100, 9 }
    H.eq(Far.Enter(), false)
    H.eq(Far.IsActive(), false)
    H.eq(Minimap.alpha, 1)
end)

H.test("in a dungeon, with no UnitPosition, far mode starts from the map and draws the dungeon", function()
    pos, best = nil, 100
    H.truthy(Far.Enter(), "entered without UnitPosition")
    Frame()
    H.truthy(Far.IsActive(), "stays in far mode with no terrain tiles")
    H.eq(ns.FarArt.DrawnMap(), 100)
    H.eq(ns.FarArt.ShownTiles(), 4)
end)

H.test("indoors in Undercity the city's map is drawn; outdoors only the terrain", function()
    best, indoors = 1458, true
    GoFar()
    Frame(0.6)
    H.eq(ns.FarArt.DrawnMap(), 1458)
    H.eq(ns.FarArt.ShownTiles(), 4)
    indoors = false
    Frame(0.6)
    H.eq(ns.FarArt.DrawnMap(), nil)
    H.eq(ns.FarArt.ShownTiles(), 0)
end)

local function Wheel(delta, dt)
    if dt then clock = clock + dt end
    view.scripts.OnMouseWheel(view, delta)
end

H.test("Alt+wheel changes floor in a multi-level dungeon, wrapping past the bottom", function()
    pos, best = nil, 100
    GoFar()
    alt = true
    Wheel(-1) -- down a level
    H.eq(ns.FarArt.DrawnMap(), 101)
    H.eq(ns.FarArt.ShownTiles(), 4)
    Wheel(-1, 0.1) -- past the bottom
    H.eq(ns.FarArt.DrawnMap(), 100, "back to the top")
    Wheel(1, 0.1) -- up from the top
    H.eq(ns.FarArt.DrawnMap(), 101, "round to the bottom")
    H.truthy(Far.IsActive(), "a floor change never zooms back in")
end)

H.test("Alt+wheel with no levels here zooms as usual", function()
    GoFar()
    alt = true
    Wheel(1) -- one step in from the first far step: back to the native minimap
    Frame()
    H.eq(Far.IsActive(), false)
end)

-- A three-level cave around the default player spot: two images on the top level, one on each
-- level below.
local function OneCave()
    ns.CaveData = {
        wmo = { [5] = {
            { 1, -64, -64, 501, 0, 0, 256, 256 },
            { 1, -64, 64, 504, 0, 0, 256, 256 },
            { 2, -64, -64, 502, 0, 0, 256, 256 },
            { 3, -64, -64, 503, 0, 0, 256, 256 },
        } },
        [0] = { { 5, -8949, -132, 0, -9013, -8885, -196, -68 } },
    }
end

H.test("indoors in a cave, the far view draws its top level only", function()
    OneCave()
    indoors = true
    GoFar()
    H.truthy(ns.Caves.IsDrawing())
    H.eq(ns.Caves.ShownTiles(), 2, "the top level's two images, not the levels below")
    H.eq(ns.Caves.Level(), 1)
end)

H.test("outdoors over a cave, only the terrain", function()
    OneCave()
    GoFar()
    H.eq(ns.Caves.IsDrawing(), false)
    H.eq(ns.Caves.ShownTiles(), 0)
end)

H.test("going outside stops drawing the cave", function()
    OneCave()
    indoors = true
    GoFar()
    indoors = false
    Frame(0.3)
    H.eq(ns.Caves.ShownTiles(), 0)
end)

H.test("Alt+wheel down goes a level deeper and wraps back to the top on the last step", function()
    OneCave()
    indoors = true
    GoFar()
    alt = true
    Wheel(-1)
    H.eq(ns.Caves.Level(), 2); H.eq(ns.Caves.ShownTiles(), 1, "only level 2")
    Wheel(-1, 0.1)
    H.eq(ns.Caves.Level(), 3); H.eq(ns.Caves.ShownTiles(), 1)
    Wheel(-1, 0.1)
    H.eq(ns.Caves.Level(), 1, "past the bottom: the top again"); H.eq(ns.Caves.ShownTiles(), 2)
    Wheel(1, 0.1)
    H.eq(ns.Caves.Level(), 3, "up from the top: round to the bottom")
    H.truthy(Far.IsActive(), "level changes never zoom")
end)

H.test("level changes wait 0.1 s between steps; steps inside it are swallowed, not zoomed", function()
    OneCave()
    indoors = true
    GoFar()
    alt = true
    Wheel(-1)
    Wheel(-1, 0.05)
    H.eq(ns.Caves.Level(), 2, "too soon: no second step")
    H.truthy(Far.IsActive(), "and no zoom either")
    Wheel(-1, 0.05)
    H.eq(ns.Caves.Level(), 3, "0.1 s after the first step")
end)

H.test("a new cave, or leaving far mode, starts back at the top level", function()
    OneCave()
    indoors = true
    GoFar()
    alt = true
    Wheel(-1)
    H.eq(ns.Caves.Level(), 2)
    Far.Leave(true)
    H.eq(ns.Caves.ShownTiles(), 0)
    alt = false
    GoFar()
    H.eq(ns.Caves.Level(), 1)
end)

H.test("in a cave the cave's own images win over an underground city map", function()
    OneCave()
    indoors, best = true, 1458
    GoFar()
    Frame(0.6)
    H.eq(ns.FarArt.DrawnMap(), nil)
    H.eq(ns.Caves.ShownTiles(), 2)
end)

H.test("leaving far mode hides the map art", function()
    pos, best = nil, 100
    GoFar()
    Far.Leave(true)
    H.eq(ns.FarArt.ShownTiles(), 0)
end)

-- Stub icon and party layers that record what far mode asks of them.
local function StubLayers(unitUnderCursor)
    local log = {}
    local function rec(name) return function(...) log[#log + 1] = { name, ... } end end
    ns.Mirror = { SetView = rec("SetView"), SetLayout = noop, ClearHover = rec("Mirror.Clear"),
        UpdateHover = rec("Mirror.Hover"), MarkAllDirty = noop }
    ns.Party = { SetLayout = noop, UnitUnderCursor = function() return unitUnderCursor end,
        SetHover = rec("Party.Hover") }
    return log
end

local function Has(log, name, arg)
    for _, e in ipairs(log) do
        if e[1] == name and (arg == nil or e[2] == arg) then return true end
    end
    return false
end

H.test("a party dot under the cursor wins over the icons under it", function()
    local log = StubLayers("party1")
    view.IsMouseOver = function() return true end
    GoFar()
    H.truthy(Has(log, "Party.Hover", "party1"), "party tooltip shown")
    H.truthy(Has(log, "Mirror.Clear"), "icon hover cleared")
    H.truthy(not Has(log, "Mirror.Hover"), "icons never hovered under a dot")
end)

H.test("with no dot under the cursor, icons get the hover and the party tooltip is cleared", function()
    local log = StubLayers(nil)
    view.IsMouseOver = function() return true end
    GoFar()
    H.truthy(Has(log, "Mirror.Hover"))
    H.truthy(Has(log, "Party.Hover"), "SetHover(nil) clears any party tooltip")
end)

H.test("far mode tells the icon layer where the view is every frame", function()
    local log = StubLayers(nil)
    GoFar()
    local n = 0
    for _, e in ipairs(log) do
        if e[1] == "SetView" then
            n = n + 1
            H.eq(e[2], -8949); H.eq(e[3], -132); H.eq(e[4], 100, "half the 200 px map")
        end
    end
    H.truthy(n >= 1)
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
_G.Minimap, _G.CreateFrame = saved.Minimap, saved.CreateFrame
