-- Pin mirror contract tests with stub frames: registry -> proxy, FakeHide, removal, placement.
local H = ...

local function noop() end

-- A stub object: every unknown method is a no-op; calls to tracked methods are recorded.
local function Stub(fields)
    local o = fields or {}
    o.calls = o.calls or {}
    return setmetatable(o, {
        __index = function(t, k)
            if not k:match("^%u") then return nil end -- only methods (Capitalised); fields stay nil
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
-- opts.negativeId: the client gives no path, only a negative file id (Questie's sword on 1.60.1).
local function NewIcon(type_, opts)
    opts = opts or {}
    local region = Stub({
        IsObjectType = function(_, kind) return kind == "Texture" end,
        IsShown = function() return not opts.neverShown end,
        GetAtlas = function() return nil end,
        GetTextureFilePath = function()
            if opts.negativeId then return nil end
            return "Interface/AddOns/Questie/Icons/available.png"
        end,
        GetTexture = function() return opts.negativeId or 123 end,
        GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end,
        GetVertexColor = function() return 1, 1, 1, 0 end,
        GetBlendMode = function() return "BLEND" end,
        IsDesaturated = function() return false end,
        GetDrawLayer = function() return "OVERLAY", 0 end,
        GetNumPoints = function() return 2 end,
    })
    local icon = Stub({
        data = { Type = type_, Icon = opts.questieIcon },
        GetRegions = function() return region end,
        GetEffectiveScale = function() return 1.5 end, -- Minimap scaled up 1.5x
        GetSize = function() return 16, 16 end,
        GetAlpha = function() return 1 end,
        GetScript = function() return nil end,
    })
    icon.texture = region
    icon.FakeHide = function(self) self.hidden = true end
    icon.FakeShow = function(self) self.hidden = false end
    return icon
end

-- Globals the mirror touches, with a real hooksecurefunc and captured tickers.
local tickers = {}
local saved = {}
for _, k in ipairs({ "CreateFrame", "C_Timer", "hooksecurefunc", "QuestieLoader", "GameTooltip", "GetCursorPosition", "Questie" }) do
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

-- Each test gets a fresh registry and a freshly loaded mirror: nothing it caches (learned
-- texture paths, proxies, hooks) carries over from the test before.
local minimapPins, lib, ns, Mirror

local function Fresh()
    for i = #tickers, 1, -1 do tickers[i] = nil end
    minimapPins = {}
    lib = { minimapPins = minimapPins }
    function lib:AddMinimapIconWorld(_, icon, instanceID, x, y)
        self.minimapPins[icon] = { instanceID = instanceID, x = x, y = y }
    end
    function lib:RemoveMinimapIcon(_, icon)
        self.minimapPins[icon] = nil
    end
    function lib:RemoveAllMinimapIcons()
        for k in pairs(self.minimapPins) do self.minimapPins[k] = nil end
    end
    local src = lib
    ns = {
        Print = noop,
        Printf = noop,
        Show = tostring,
        RegisterCommand = noop,
        PinSources = { List = function() return { { name = "Questie (test)", lib = src } } end },
    }
    ns.db = { icons = {} }
    H.loadAddonFile("Core/Geometry.lua", ns)
    H.loadAddonFile("Core/IconPrefs.lua", ns)
    H.loadAddonFile("Pins/Mirror.lua", ns)
    Mirror = ns.Mirror
    Mirror.Build(NewFrame(), NewFrame(), 10)
end
H.beforeEach(Fresh)

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
    Mirror.SetLayout(0, -8949, -132, 0.5)
    H.eq(t.calls.SetSize[1], 24, "size follows the icon's effective scale")
end)

H.test("icon groups: Questie types are categories; hide and size apply", function()
    local icon = NewIcon("monster")
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5, 0.5)
    local p = Proxy(icon)
    H.eq(p.key, "questie:monster")
    H.eq(p.tex[1].calls.SetSize[1], 24, "Questie icons don't shrink by default")

    ns.IconPrefs.Apply(ns.db, "monster", {}, "size", "0.5")
    Mirror.RefreshPrefs()
    H.eq(p.tex[1].calls.SetSize[1], 12, "size 0.5")
    H.near(p.hw, 6, 1e-9, "hit box follows size")

    ns.IconPrefs.Apply(ns.db, "monster", {}, "shrink", "on")
    Mirror.RefreshPrefs()
    H.eq(p.tex[1].calls.SetSize[1], 6, "size 0.5 x zoom shrink 0.5")

    ns.IconPrefs.Apply(ns.db, "questie", {}, "hide")
    Mirror.RefreshPrefs()
    H.eq(p.drawn, false, "hidden by the user")
    ns.IconPrefs.Apply(ns.db, "all", {}, "reset")
    Mirror.RefreshPrefs()
    H.eq(p.drawn, true, "reset shows it again")
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

H.test("zoom places only icons near the view; the rest come in as the view nears them", function()
    local near, far = NewIcon("available"), NewIcon("available")
    lib:AddMinimapIconWorld("Questie", near, 0, -132, -8949)
    lib:AddMinimapIconWorld("Questie", far, 0, -132, -3949) -- 5,000 yd north: 2,500 px at ppy 0.5
    Drain()
    Mirror.SetView(-8949, -132, 100) -- a 200 px view centred on the first icon
    Mirror.SetLayout(0, -8949, -132, 0.5)
    H.eq(Proxy(near).drawn, true, "icon in view drawn")
    H.truthy(not Proxy(far).drawn, "icon far outside the view not placed")
    H.eq(Proxy(far).tex[1].shown, false, "and not shown")
    Mirror.SetView(-3949, -132, 100) -- panned over to the far icon
    H.eq(Proxy(far).drawn, true, "drawn once the view is over it")
    H.near(Proxy(far).y, 2500, 1e-9)
    H.truthy(not Proxy(near).drawn, "the one left behind is hidden")
end)

H.test("small moves of the view don't re-place icons", function()
    local icon = NewIcon("available")
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    Mirror.SetView(-8949, -132, 100)
    Mirror.SetLayout(0, -8949, -132, 0.5)
    local t = Proxy(icon).tex[1]
    local placed = 0
    t.SetPoint = function() placed = placed + 1 end
    Mirror.SetView(-8949 + 40, -132 + 40, 100) -- 20 px each way at ppy 0.5
    H.eq(placed, 0)
end)

H.test("a hidden icon stays hidden when the view comes over it", function()
    local icon = NewIcon("available")
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -3949)
    Drain()
    Mirror.SetView(-8949, -132, 100)
    Mirror.SetLayout(0, -8949, -132, 0.5)
    icon:FakeHide()
    Drain()
    Mirror.SetView(-3949, -132, 100)
    H.truthy(not Proxy(icon).drawn)
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

H.test("a texture known only by a negative file id uses Questie's path for the icon type", function()
    _G.Questie = { usedIcons = { [7] = "Interface/AddOns/Questie/Icons/slay.png" } }
    local icon = NewIcon("monster", { negativeId = -12175, questieIcon = 7 })
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    local p = Proxy(icon)
    H.eq(p.nTex, 1)
    H.eq(p.tex[1].calls.SetTexture[1], "Interface/AddOns/Questie/Icons/slay.png")
end)

H.test("an unsigned negative id (4294954171) is never passed on; Questie's path is used", function()
    _G.Questie = { usedIcons = { [3] = "Interface/AddOns/Questie/Icons/available.png" } }
    local icon = NewIcon("available", { negativeId = 4294954171, questieIcon = 3 })
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    local p = Proxy(icon)
    H.eq(p.nTex, 1)
    H.eq(p.tex[1].calls.SetTexture[1], "Interface/AddOns/Questie/Icons/available.png")
end)

H.test("the texture Questie sets is recorded and wins over reading it back", function()
    _G.Questie = { usedIcons = {} }
    local icon = NewIcon("available", { negativeId = 4294954171 })
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain() -- first sight: hooks installed, nothing resolvable yet
    icon.texture:SetTexture("Interface/AddOns/Questie/Icons/complete.png") -- frame recycled
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    local p = Proxy(icon)
    H.eq(p.nTex, 1)
    H.eq(p.tex[1].calls.SetTexture[1], "Interface/AddOns/Questie/Icons/complete.png")
end)

H.test("an unresolvable texture is skipped, never passed to SetTexture", function()
    _G.Questie = { usedIcons = {} }
    local before = Mirror.unresolved
    local icon = NewIcon("monster", { negativeId = -13999, questieIcon = 99 })
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    local p = Proxy(icon)
    H.eq(p.nTex, 0)
    H.eq(p.drawn, false)
    H.eq(Mirror.unresolved, before + 1)
    H.eq(Mirror.lastUnresolved, -13999)
end)

H.test("RareScanner-style pin: path from POI.Texture, own size and scale kept", function()
    _G.Questie = nil
    local tex = Stub({
        IsObjectType = function(_, kind) return kind == "Texture" end,
        IsShown = function() return true end,
        GetTexture = function() return 4294950000 end, -- unsigned negative id, no path
        GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end,
        GetVertexColor = function() return 1, 1, 1, 1 end,
        GetBlendMode = function() return "BLEND" end,
        GetDrawLayer = function() return "ARTWORK", 0 end,
        GetNumPoints = function() return 1 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetSize = function() return 32, 32 end,
        GetScale = function() return 0.5 end,
    })
    local pin = Stub({
        GetRegions = function() return tex end,
        GetEffectiveScale = function() return 1.5 end,
        GetSize = function() return 18, 18 end,
        GetAlpha = function() return 1 end,
        GetScript = function() return nil end,
    })
    pin.Texture = tex
    pin.POI = { Texture = "Interface/AddOns/RareScanner/Media/Icons/RareRed.blp" }
    lib:AddMinimapIconWorld("RareScanner", pin, 0, -132, -8949)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    local p = Proxy(pin)
    H.eq(p.nTex, 1)
    H.eq(p.tex[1].calls.SetTexture[1], "Interface/AddOns/RareScanner/Media/Icons/RareRed.blp")
    H.near(p.tex[1].calls.SetSize[1], 32 * 0.5 * 1.5, 1e-9, "own size x own scale x minimap scale")
end)

H.test("an icon HBD has never shown (out of native range) is still copied", function()
    -- Its texture reports IsShown() false because the frame has never been shown.
    local icon = NewIcon("complete", { neverShown = true })
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8000)
    Drain()
    Mirror.SetLayout(0, -8949, -132, 0.5)
    local p = Proxy(icon)
    H.eq(p.nTex, 1)
    H.eq(p.drawn, true)
end)

H.test("a file id returned as text is not a path; Questie's data is used", function()
    _G.Questie = { usedIcons = { [8] = "Interface/AddOns/Questie/Icons/complete.blp" } }
    local icon = NewIcon("complete", { negativeId = 4294955030, questieIcon = 8 })
    icon.texture.GetTextureFilePath = function() return "4294955030" end
    lib:AddMinimapIconWorld("Questie", icon, 0, -132, -8949)
    Drain()
    local p = Proxy(icon)
    H.eq(p.nTex, 1)
    H.eq(p.tex[1].calls.SetTexture[1], "Interface/AddOns/Questie/Icons/complete.blp")
end)

for k, v in pairs(saved) do _G[k] = v end
