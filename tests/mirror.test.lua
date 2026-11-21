-- Pin mirror contract tests with stub frames: registry -> proxy, FakeHide, removal, placement.
local H = ...

local function noop() end

-- A stub object: every unknown method is a no-op; calls to tracked methods are recorded.
local function Stub(fields)
    local o = fields or {}
    o.calls = o.calls or {}
    return setmetatable(o, {
        __index = function(t, k)
            local f = function(self, ...)
                self.calls[k] = { ... }
            end
            rawset(t, k, f)
            return f
        end,
    })
end

local function NewTexture()
    local t = Stub()
    t.shown = false
    t.Show = function(self) self.shown = true end
    t.Hide = function(self) self.shown = false end
    return t
end

local function NewFrame()
    local f = Stub()
    f.CreateTexture = function() return NewTexture() end
    f.GetEffectiveScale = function() return 1 end
    f.GetCenter = function() return 0, 0 end
    return f
end

-- A Questie-like icon: one texture filling the frame.
local function NewIcon(type_)
    local region = Stub({
        IsObjectType = function(_, kind) return kind == "Texture" end,
        IsShown = function() return true end,
        GetAtlas = function() return nil end,
        GetTextureFilePath = function() return "Interface/AddOns/Questie/Icons/available.png" end,
        GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end,
        GetVertexColor = function() return 1, 1, 1, 0 end,
        GetBlendMode = function() return "BLEND" end,
        IsDesaturated = function() return false end,
        GetDrawLayer = function() return "OVERLAY", 0 end,
        GetNumPoints = function() return 2 end,
    })
    local icon = Stub({
        data = { Type = type_ },
        GetRegions = function() return region end,
        GetEffectiveScale = function() return 1.5 end, -- Minimap scaled up 1.5x
        GetSize = function() return 16, 16 end,
        GetAlpha = function() return 1 end,
        GetScript = function() return nil end,
    })
    icon.FakeHide = function(self) self.hidden = true end
    icon.FakeShow = function(self) self.hidden = false end
    return icon
end

-- Globals the mirror touches, with a real hooksecurefunc and captured tickers.
local tickers = {}
local saved = {}
for _, k in ipairs({ "CreateFrame", "C_Timer", "hooksecurefunc", "QuestieLoader", "GameTooltip", "GetCursorPosition" }) do
    saved[k] = _G[k]
end
_G.CreateFrame = function() return NewFrame() end
_G.C_Timer = { NewTicker = function(_, fn) tickers[#tickers + 1] = fn end }
_G.hooksecurefunc = function(t, name, post)
    local orig = t[name]
    t[name] = function(...)
        local r = { orig(...) }
        post(...)
        return unpack(r)
    end
end
_G.QuestieLoader = nil

local minimapPins = {}
local lib = { minimapPins = minimapPins }
function lib:AddMinimapIconWorld(_, icon, instanceID, x, y)
    self.minimapPins[icon] = { instanceID = instanceID, x = x, y = y }
end
function lib:RemoveMinimapIcon(_, icon)
    self.minimapPins[icon] = nil
end
function lib:RemoveAllMinimapIcons()
    for k in pairs(self.minimapPins) do self.minimapPins[k] = nil end
end

local ns = {
    Print = noop,
    Printf = noop,
    Show = tostring,
    RegisterCommand = noop,
    PinSources = { List = function() return { { name = "test", lib = lib } } end },
}
H.loadAddonFile("Core/Geometry.lua", ns)
H.loadAddonFile("Pins/Mirror.lua", ns)
local Mirror = ns.Mirror

Mirror.Build(NewFrame(), NewFrame(), 10)
local function Drain() tickers[1]() end

local function Proxy(icon) return Mirror._proxies[icon] end

H.test("a pin added before or after the hooks gets a proxy with the icon's look", function()
    local early = NewIcon("available")
    minimapPins[early] = { instanceID = 0, x = -132, y = -8949 } -- added before Build: found by reconcile
    local late = NewIcon("monster")
    lib:AddMinimapIconWorld("Questie", late, 0, -100, -8900)
    Drain()
    H.truthy(Proxy(early), "early pin mirrored")
    H.truthy(Proxy(late), "hooked pin mirrored")
    local t = Proxy(late).tex[1]
    H.eq(t.calls.SetTexture[1], "Interface/AddOns/Questie/Icons/available.png", "texture by path")
    H.eq(t.calls.SetVertexColor[4], 1, "Questie's fade alpha is ignored")
    H.eq(t.calls.SetSize[1], 24, "size follows the icon's effective scale")
end)

H.test("placement: the pin at the origin sits at 0,0; 100 yd north at ppy 0.5 is 50 px up", function()
    local a, b = NewIcon("available"), NewIcon("available")
    lib:AddMinimapIconWorld("Questie", a, 0, -132, -8949)
    lib:AddMinimapIconWorld("Questie", b, 0, -132, -8849)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    local pa, pb = Proxy(a), Proxy(b)
    H.truthy(pa.drawn and pb.drawn, "both drawn")
    H.near(pa.x, 0, 1e-9); H.near(pa.y, 0, 1e-9)
    H.near(pb.x, 0, 1e-9); H.near(pb.y, 50, 1e-9)
    H.eq(pb.tex[1].shown, true)
end)

H.test("pins on another continent are not drawn", function()
    local icon = NewIcon("available")
    lib:AddMinimapIconWorld("Questie", icon, 1, 0, 0)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    H.eq(Proxy(icon).drawn, false)
end)

H.test("FakeHide hides the proxy and FakeShow brings it back (#22)", function()
    local icon = NewIcon("available")
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    icon:FakeHide()
    Drain()
    H.eq(Proxy(icon).drawn, false, "hidden")
    icon:FakeShow()
    Drain()
    H.eq(Proxy(icon).drawn, true, "shown again")
end)

H.test("RemoveMinimapIcon and RemoveAllMinimapIcons drop proxies", function()
    local a, b = NewIcon("available"), NewIcon("complete")
    lib:AddMinimapIconWorld("Questie", a, 0, 1, 1)
    lib:AddMinimapIconWorld("Questie", b, 0, 2, 2)
    Drain()
    lib:RemoveMinimapIcon("Questie", a)
    Drain()
    H.eq(Proxy(a), nil, "single remove")
    lib:RemoveAllMinimapIcons("Questie")
    Drain()
    H.eq(Proxy(b), nil, "remove all")
end)

H.test("leaving far mode hides everything", function()
    local icon = NewIcon("available")
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    Mirror.SetLayout(nil)
    H.eq(Proxy(icon).drawn, false)
end)

for k, v in pairs(saved) do _G[k] = v end
