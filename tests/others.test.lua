-- Other addons' things on the minimap in far mode (Pins/Others.lua): what's furniture (kept over
-- the far map), what's a drawing (copied to its place on the far map), what's left alone.
local H = ...

local function noop() end

local saved = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = noop, SetScript = noop } end
local base = { RegisterCommand = noop }
H.loadAddonFile("Core/IconPrefs.lua", base)
local O = H.loadAddonFile("Pins/Others.lua", base).Others
_G.CreateFrame = saved

----------------------------------------------------------------------------------------------------
-- Pure parts

local function Kind(over)
    local f = { shown = true, alpha = 1, map = 200, w = 10, h = 10, inside = true }
    for k, v in pairs(over or {}) do f[k] = v end
    return O.Kind(f)
end

H.test("kind: small pictures on the map are drawings", function()
    H.eq(Kind(), "drawing")
    H.eq(Kind({ mouse = true }), "drawing", "a pin with a tooltip is still a drawing")
end)

H.test("kind: buttons and text are furniture, wherever they are", function()
    H.eq(Kind({ button = true }), "furniture")
    H.eq(Kind({ text = true }), "furniture")
    H.eq(Kind({ inside = false }), "furniture", "a small thing off the map: part of its frame")
    H.eq(Kind({ w = 120, h = 20 }), "furniture", "a strip")
end)

H.test("kind: a frame over the whole map is looked into, unless it takes the mouse", function()
    H.eq(Kind({ w = 200, h = 200 }), "container")
    H.eq(Kind({ w = 200, h = 200, mouse = true }), "skip", "a click blocker would swallow the far map's clicks")
end)

H.test("kind: ours, pins, hidden or see-through things are left alone", function()
    H.eq(Kind({ skip = true }), "skip")
    H.eq(Kind({ shown = false }), "skip")
    H.eq(Kind({ alpha = 0 }), "skip")
end)

H.test("names: the game's hybrid minimap is the game's", function()
    H.eq(O.SkipName("HybridMinimap"), true)
end)

H.test("names: the game's, Questie's and ours are skipped, other addons' aren't", function()
    H.eq(O.SkipName("MinimapZoomIn"), true)
    H.eq(O.SkipName("QuestieFrameGroup"), true)
    H.eq(O.SkipName("OverlookFrame"), true)
    H.eq(O.SkipName("OverlookNativeEntrances"), true, "our own entrance layer on the native map")
    H.eq(O.SkipName("FactoruideMinimapWalk"), false)
    H.eq(O.SkipName(nil), false)
end)

H.test("small inside: border strips and off-map pictures aren't drawings", function()
    H.eq(O.SmallInside(5, 5, true, 200), true)
    H.eq(O.SmallInside(200, 1, true, 200), false, "a border strip")
    H.eq(O.SmallInside(5, 5, false, 200), false)
    H.eq(O.SmallInside(0, 0, true, 200), false)
end)

H.test("world offset: right is east, up is north, by the native pixels per yard", function()
    local dn, dw = O.WorldOffset(10, 5, 0.5, nil)
    H.near(dn, 10, 1e-9, "north"); H.near(dw, -20, 1e-9, "east is minus west")
end)

H.test("world offset: undoes a rotating minimap (Factoruide's own forward maths)", function()
    -- Factoruide's PathLines.OnMinimap: a point dn north, dw west, turned by the facing.
    local function Forward(dn, dw, ppy, facing)
        local x, y = -dw, dn
        local c, s = math.cos(facing), math.sin(facing)
        x, y = x * c + y * s, -x * s + y * c
        return x * ppy, y * ppy
    end
    for _, facing in ipairs({ 0, 0.7, math.pi / 2, 3, 5.5 }) do
        local px, py = Forward(37, -12, 0.8, facing)
        local dn, dw = O.WorldOffset(px, py, 0.8, facing)
        H.near(dn, 37, 1e-9, "north at " .. facing); H.near(dw, -12, 1e-9, "west at " .. facing)
    end
end)

H.test("copyable: real pictures only; never lines, masks or plain fills", function()
    H.eq(O.Copyable("Texture", "Interface\\COMMON\\Indicator-Gray"), true)
    H.eq(O.Copyable("Texture", 136235), true, "a file id")
    H.eq(O.Copyable("Texture", nil), true, "(CopyLook still needs a picture)")
    H.eq(O.Copyable("Line", "Interface\\COMMON\\Indicator-Gray"), false, "a route line")
    H.eq(O.Copyable("MaskTexture", nil), false)
    H.eq(O.Copyable("Texture", "Interface\\Buttons\\WHITE8X8"), false, "RareScanner's route texture")
    H.eq(O.Copyable("Texture", "Interface\\BUTTONS\\white8x8"), false)
    H.eq(O.Copyable("Texture", "Interface\\ChatFrame\\ChatFrameBackground"), false)
    H.eq(O.Copyable("Texture", "Interface\\Tooltips\\UI-Tooltip-Background"), false)
end)

H.test("owner: from a texture's addon folder, the frame's name, or 'Other addons'", function()
    local addons = { "Factoruide_Guide", "RareScanner", "TomTom" }
    H.eq(O.Owner(nil, "Interface\\AddOns\\ForeverFinds\\Media\\pin.blp", addons), "ForeverFinds")
    H.eq(O.Owner(nil, "interface/addons/TomTom/Images/x", addons), "TomTom")
    H.eq(O.Owner("FactoruideMinimapWalk", nil, addons), "Factoruide_Guide", "the folder's first word")
    H.eq(O.Owner("RareScannerMinimapPin", nil, addons), "RareScanner")
    H.eq(O.Owner("SomethingElse", nil, addons), "Other addons")
    H.eq(O.Owner(nil, "Interface\\COMMON\\Indicator-Gray", addons), "Other addons")
end)

----------------------------------------------------------------------------------------------------
-- A stub minimap with one of everything

local function Region(kind, x, y, w, h, extra)
    local r = { kind = kind, x = x, y = y, w = w, h = h, shown = true, alpha = 1 }
    r.GetCenter = function(self) return self.x, self.y end
    r.GetSize = function(self) return self.w, self.h end
    r.GetEffectiveScale = function() return 1 end
    r.IsShown = function(self) return self.shown end
    r.GetAlpha = function(self) return self.alpha end
    r.IsObjectType = function(self, t) return self.kind == t or (t == "Frame" and self.kind == "Button") end
    r.GetObjectType = function(self) return self.kind end
    r.GetText = function(self) return self.text end
    r.GetTexture = function(self) return self.file end
    r.GetTextureFilePath = function(self) return self.file end
    r.GetTexCoord = function() return 0, 1, 0, 1 end
    r.GetVertexColor = function() return 1, 1, 1, 1 end
    r.GetBlendMode = function() return "BLEND" end
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function Frame(kind, name, x, y, w, h, extra)
    local f = Region(kind, x, y, w, h, extra)
    f.name, f.regions, f.children = name, f.regions or {}, f.children or {}
    f.level, f.strata, f.ignore = f.level or 5, f.strata or "LOW", false
    f.GetName = function(self) return self.name end
    f.IsMouseEnabled = function(self) return self.mouse == true end
    f.GetRegions = function(self) return unpack(self.regions) end
    f.GetChildren = function(self) return unpack(self.children) end
    f.GetFrameLevel = function(self) return self.level end
    f.SetFrameLevel = function(self, v) self.level = v end
    f.GetFrameStrata = function(self) return self.strata end
    f.SetIgnoreParentAlpha = function(self, v) self.ignore = v end
    f.SetFixedFrameLevel = noop
    return f
end

local function Tex()
    local t = { shown = false }
    t.SetPoint = function(self, _, _, _, x, y) self.px, self.py = x, y end
    t.SetSize = function(self, w, h) self.sw, self.sh = w, h end
    t.Show = function(self) self.shown = true end
    t.Hide = function(self) self.shown = false end
    t.SetTexture = function(self, f) self.file = f end
    return setmetatable(t, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })
end

local W -- the world: frames by role
local GLOBALS = { "CreateFrame", "Minimap", "C_Minimap", "GetCVar", "GetPlayerFacing", "C_AddOns" }

local function World(dbOver)
    W = {}
    -- Factoruide: a frame over the whole map with small dots (one hidden).
    W.dot1 = Region("Texture", 510, 405, 5, 5, { file = "Interface\\COMMON\\Indicator-Gray" })
    W.dot2 = Region("Texture", 480, 400, 5, 5, { file = "Interface\\COMMON\\Indicator-Gray" })
    W.dot3 = Region("Texture", 470, 400, 5, 5, { file = "Interface\\COMMON\\Indicator-Gray", shown = false })
    W.walk = Frame("Frame", "FactoruideMinimapWalk", 500, 400, 200, 200, { regions = { W.dot1, W.dot2, W.dot3 } })
    -- A minimap addon's border: strips over the edges.
    W.border = Frame("Frame", nil, 500, 400, 200, 200, { regions = {
        Region("Texture", 500, 499.5, 200, 1), Region("Texture", 400.5, 400, 1, 200) } })
    -- A LibDBIcon button, the zone name in a box, a HereBeDragons pin, Questie's group, a click
    -- blocker, and a hand-placed rare pin.
    W.button = Frame("Button", "LibDBIcon10_Foo", 590, 490, 31, 31)
    W.zone = Frame("Frame", nil, 500, 310, 80, 14, { regions = { Region("FontString", 500, 310, 70, 12, { text = "The Crossroads" }) } })
    W.pin = Frame("Frame", nil, 520, 420, 16, 16, { regions = { Region("Texture", 520, 420, 16, 16, { file = 1 }) } })
    W.questie = Frame("Frame", "QuestieFrameGroup", 500, 400, 200, 200)
    W.blocker = Frame("Frame", nil, 500, 400, 200, 200, { mouse = true })
    W.rare = Frame("Frame", "ZzzPin", 460, 380, 16, 16, { regions = {
        Region("Texture", 460, 380, 16, 16, { file = "Interface\\AddOns\\RareThing\\icon.blp" }) } })
    -- RareScanner's route: an unnamed frame over the map holding short white lines from the player,
    -- and a hand-made white box (a plain fill) near the player.
    W.line = Region("Line", 505, 402, 10, 4, { file = "Interface\\Buttons\\WHITE8X8" })
    W.route = Frame("Frame", nil, 500, 400, 200, 200, { regions = { W.line } })
    W.fill = Region("Texture", 500, 400, 12, 12, { file = "Interface\\Buttons\\WHITE8X8" })
    W.box = Frame("Frame", nil, 500, 400, 12, 12, { regions = { W.fill } })
    -- The game's hybrid minimap (cities with floors): its canvas of map pieces, and the mask
    -- Leatrix Plus turns into a white square.
    W.tile = Region("Texture", 500, 400, 40, 40, { file = 5012345 })
    W.mask = Region("Texture", 500, 400, 45, 45, { file = 130871 })
    W.canvas = Frame("Frame", nil, 500, 400, 200, 200, { regions = { W.tile, W.mask } })
    W.hybrid = Frame("Frame", "HybridMinimap", 500, 400, 200, 200, { children = { W.canvas } })

    local kept = {}
    for _, k in ipairs(GLOBALS) do kept[k] = _G[k] end
    local minimap = Frame("Frame", "Minimap", 500, 400, 200, 200, { children = {
        W.walk, W.border, W.button, W.zone, W.pin, W.questie, W.blocker, W.rare, W.route, W.box, W.hybrid } })
    minimap.GetWidth = function() return 200 end
    _G.Minimap = minimap
    _G.CreateFrame = function()
        local f = Frame("Frame", nil, 0, 0, 1, 1)
        f.scripts = {}
        f.SetScript = function(self, k, fn) self.scripts[k] = fn end
        f.CreateTexture = function() return Tex() end
        return setmetatable(f, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })
    end
    _G.C_Minimap = { GetViewRadius = function() return 200 end } -- 100 px / 200 yd: 0.5 px per yard
    _G.GetCVar = function() return "0" end
    _G.GetPlayerFacing = function() return 0 end
    _G.C_AddOns = {
        GetNumAddOns = function() return 2 end,
        GetAddOnInfo = function(i) return ({ "Factoruide_Guide", "RareThing" })[i] end,
        IsAddOnLoaded = function() return true end,
    }

    local ns = { RegisterCommand = noop, Print = noop, IsSecret = function() return false end }
    H.loadAddonFile("Core/Geometry.lua", ns)
    H.loadAddonFile("Core/IconPrefs.lua", ns)
    H.loadAddonFile("Core/Settings.lua", ns)
    ns.db = ns.Settings.Load(nil)
    for k, v in pairs(dbOver or {}) do ns.db[k] = v end
    ns.Far = { PlayerWorld = function() return 1000, 2000, 0 end, Shape = noop }
    ns.Mirror = { IsPin = function(f) return f == W.pin end, AddCategory = noop }
    H.loadAddonFile("Pins/Others.lua", ns)
    local view = Frame("Frame", nil, 500, 400, 200, 200, { level = 3000 })
    ns.Others.Build(Frame("Frame", nil, 0, 0, 1, 1), view, 3002)
    local function Restore() for _, k in ipairs(GLOBALS) do _G[k] = kept[k] end end
    return ns, ns.Others, Restore
end

local function Far(Others)
    Others.SetFar(true)
    Others.SetLayout(0, 1000, 2000, 1, 1) -- the far map's origin at the player, 1 px per yard
end

local function CopyOf(Others, src)
    return Others._copies[src]
end

H.test("far map: drawings are copied, furniture kept, the rest left alone", function()
    local _, Others, Restore = World()
    Far(Others)
    local counts = Others.Counts()
    H.eq(counts["drawn:factoruide_guide"], 2, "the two shown dots")
    H.eq(counts["drawn:rarething"], 1, "the rare pin, named by its texture's folder")
    H.eq(CopyOf(Others, W.dot3), nil, "a hidden dot isn't copied")
    H.truthy(Others._lifted[W.border], "the border")
    H.truthy(Others._lifted[W.button], "the minimap button")
    H.truthy(Others._lifted[W.zone], "the zone text")
    for _, k in ipairs({ "walk", "pin", "questie", "blocker", "rare" }) do
        H.eq(Others._lifted[W[k]], nil, k .. " isn't furniture")
    end
    H.eq(W.button.ignore, true, "shows despite the Minimap's alpha 0")
    H.eq(W.button.level, 3025, "above the far view")
    Restore()
end)

H.test("far map: no white squares: route lines and plain fills aren't copied, nor shown at native scale", function()
    local _, Others, Restore = World()
    Far(Others)
    H.eq(CopyOf(Others, W.line), nil, "a route line")
    H.eq(CopyOf(Others, W.fill), nil, "a white box")
    H.eq(Others._lifted[W.route], nil, "the route's frame stays under the far view")
    local n = 0
    for _ in pairs(Others._copies) do n = n + 1 end
    H.eq(n, 3, "only the two dots and the rare pin")
    Restore()
end)

H.test("far map: no white box around the player from the game's hybrid minimap (Leatrix Plus)", function()
    local _, Others, Restore = World()
    Far(Others)
    H.eq(CopyOf(Others, W.tile), nil, "a map piece")
    H.eq(CopyOf(Others, W.mask), nil, "the mask")
    H.eq(Others._lifted[W.hybrid], nil, "not kept showing either")
    H.eq(Others._lifted[W.canvas], nil)
    Restore()
end)

H.test("far map: a drawing stands where the native map put it, in yards from the player", function()
    local _, Others, Restore = World()
    Far(Others)
    local c = CopyOf(Others, W.dot1)
    -- 10 px right and 5 px up at 0.5 px per yard: 20 yd east, 10 yd north of the player.
    H.near(c.n, 1010, 1e-9); H.near(c.w, 1980, 1e-9)
    H.eq(c.tex.shown, true)
    H.near(c.tex.px, 20, 1e-9, "1 px per yard east"); H.near(c.tex.py, 10, 1e-9)
    H.near(c.tex.sw, 5, 1e-9, "its own size")
    Restore()
end)

H.test("far map: a drawing that moves or hides is followed", function()
    local _, Others, Restore = World()
    Far(Others)
    W.dot1.x = 520
    Others.PlaceAll()
    H.near(CopyOf(Others, W.dot1).tex.px, 40, 1e-9)
    W.dot1.shown = false
    Others.PlaceAll()
    H.eq(CopyOf(Others, W.dot1).tex.shown, false)
    Others.Scan()
    H.eq(CopyOf(Others, W.dot1), nil, "gone on the next look")
    Restore()
end)

H.test("far map: each addon's drawings follow its icon group's show and size", function()
    local ns, Others, Restore = World()
    Far(Others)
    ns.IconPrefs.Apply(ns.db, "drawn:factoruide_guide", { ["drawn:factoruide_guide"] = true }, "size", "2")
    Others.RefreshPrefs()
    H.near(CopyOf(Others, W.dot1).tex.sw, 10, 1e-9, "twice the size")
    ns.IconPrefs.Apply(ns.db, "drawn:factoruide_guide", { ["drawn:factoruide_guide"] = true }, "hide")
    Others.RefreshPrefs()
    H.eq(CopyOf(Others, W.dot1).tex.shown, false)
    H.eq(CopyOf(Others, W.rare.regions[1]).tex.shown, true, "another addon's group is untouched")
    Restore()
end)

H.test("back to the native map: furniture as it was, copies gone", function()
    local _, Others, Restore = World()
    Far(Others)
    Others.SetLayout(nil)
    Others.SetFar(false)
    H.eq(W.button.ignore, false)
    H.eq(W.button.level, 5, "its own level back")
    H.eq(next(Others._lifted), nil)
    H.eq(next(Others._copies), nil)
    Restore()
end)

H.test("settings: keeping furniture off leaves it to vanish with the map", function()
    local _, Others, Restore = World({ keepOthersVisible = false })
    Far(Others)
    H.eq(next(Others._lifted), nil)
    H.eq(Others.Counts()["drawn:factoruide_guide"], 2, "drawings still copied")
    Restore()
end)

H.test("settings: copying off copies nothing, and a frame of drawings isn't shown as furniture", function()
    local _, Others, Restore = World({ captureOthers = false })
    Far(Others)
    H.eq(next(Others._copies), nil)
    H.eq(Others._lifted[W.walk], nil, "its dots would stand at the wrong places")
    H.truthy(Others._lifted[W.border], "the border is still kept")
    Restore()
end)

H.test("settings: switching a setting while zoomed out applies straight away", function()
    local ns, Others, Restore = World()
    Far(Others)
    ns.db.keepOthersVisible = false
    Others.Refresh()
    H.eq(next(Others._lifted), nil)
    H.eq(W.button.ignore, false)
    ns.db.keepOthersVisible = true
    Others.Refresh()
    H.truthy(Others._lifted[W.button])
    Restore()
end)
