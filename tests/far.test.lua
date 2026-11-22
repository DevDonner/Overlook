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

local clock, pos, zoom
local GLOBALS = {
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
    clock, pos, zoom = 100, { -8949, -132, 0 }, 0
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
    H.loadAddonFile("Far/Far.lua", ns)
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

for k in pairs(GLOBALS) do _G[k] = saved[k] end
_G.Minimap, _G.CreateFrame = saved.Minimap, saved.CreateFrame
