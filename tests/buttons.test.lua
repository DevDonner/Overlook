-- The minimap button panel (Shell/Buttons.lua): grid maths and which frames count as buttons.
local H = ...

local saved = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local B = H.loadAddonFile("Shell/Buttons.lua", { RegisterCommand = function() end }).Buttons
_G.CreateFrame = saved

H.test("grid: rows fill left to right, the panel fits them", function()
    local slots, w, h = B.Grid(7, 3, 20, 4, 6)
    H.eq(#slots, 7)
    H.eq(slots[1][1], 6); H.eq(slots[1][2], -6)
    H.eq(slots[3][1], 6 + 2 * 24)
    H.eq(slots[4][1], 6); H.eq(slots[4][2], -30, "second row")
    H.eq(w, 12 + 3 * 20 + 2 * 4)
    H.eq(h, 12 + 3 * 20 + 2 * 4, "three rows")
end)

H.test("grid: fewer buttons than a row makes a narrower panel", function()
    local _, w, h = B.Grid(2, 6, 20, 4, 6)
    H.eq(w, 12 + 2 * 20 + 4)
    H.eq(h, 12 + 20)
end)

H.test("grid: no buttons, still a sane size", function()
    local slots, w = B.Grid(0, 6, 20, 4, 6)
    H.eq(#slots, 0)
    H.truthy(w > 0)
end)

H.test("buttons: LibDBIcon and minimap-button names, not the game's own", function()
    H.eq(B.LooksLikeButton("LibDBIcon10_Questie"), true)
    H.eq(B.LooksLikeButton("AtlasLootMinimapButton"), true)
    H.eq(B.LooksLikeButton("Foo_MiniMapButton"), true)
    H.eq(B.LooksLikeButton("MiniMapTrackingButton"), false)
    H.eq(B.LooksLikeButton("MinimapZoomIn"), false)
    H.eq(B.LooksLikeButton("GameTimeFrame"), false)
    H.eq(B.LooksLikeButton("OverlookFrame"), false)
    H.eq(B.LooksLikeButton(nil), false)
end)

H.test("icon: the data object's texture, coordinates and colour, with defaults", function()
    local tex, c, r, g, b = B.IconOf({ icon = "x" })
    H.eq(tex, "x"); H.eq(#c, 4); H.eq(r + g + b, 3)
    local _, c2, r2 = B.IconOf({ icon = 1, iconCoords = { 0, 1, 0, 1 }, iconR = 0.5 })
    H.eq(c2[2], 1); H.eq(r2, 0.5)
end)

-- A small world: frames that remember scripts and shown state, and LibDBIcon with two buttons.
local function Obj()
    local o = { shown = true, scripts = {}, points = 0 }
    o.Show = function(self) self.shown = true end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown end
    o.SetShown = function(self, v) self.shown = v and true or false end
    o.SetScript = function(self, k, f) self.scripts[k] = f end
    o.GetFrameLevel = function() return 5 end
    o.GetFrameStrata = function() return "DIALOG" end
    o.CreateTexture = function() return Obj() end
    return setmetatable(o, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
    end })
end

H.test("panel: our own button per LibDBIcon addon; clicks reach the addon, originals stay hidden", function()
    local clicked
    local origA = Obj(); origA.dataObject = { icon = "a", label = "Alpha", OnClick = function(_, b) clicked = b end }
    local origB = Obj(); origB.dataObject = { icon = "b", label = "Beta" }; origB.db = { hide = true }
    local lib = {
        GetButtonList = function() return { "A", "B" } end,
        GetMinimapButton = function(_, n) return n == "A" and origA or origB end,
    }
    local kept, made = {}, {}
    local G = {
        CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end,
        OverlookPanelShown = function() return made[1].shown end,
        LibStub = function() return lib end,
        C_Timer = { NewTicker = function() end }, UISpecialFrames = {}, UIParent = Obj(),
        Minimap = Obj(), GameTooltip = Obj(),
    }
    for k, v in pairs(G) do kept[k], _G[k] = _G[k], v end
    local ns = { RegisterCommand = function() end, db = { bottomBar = true, buttonsPerRow = 6 },
        Shell = {} }
    local M = H.loadAddonFile("Shell/Buttons.lua", ns).Buttons
    local trigger = Obj()
    M.Build(trigger)
    H.eq(M.Count(), 1, "the button hidden through LibDBIcon's setting isn't counted")
    H.eq(origA.shown, false, "the original is hidden")
    origA:Show()
    H.eq(origA.shown, false, "and stays hidden when its addon shows it")
    H.eq(trigger.shown, true)
    local ours
    for _, f in ipairs(made) do
        if f.entry and f.entry.name == "A" then ours = f end
    end
    H.truthy(ours, "our button for A")
    ours.scripts.OnClick(ours, "RightButton")
    H.eq(clicked, "RightButton", "the click went to the addon")
    M.Toggle()
    H.eq(_G.OverlookPanelShown(), true, "open")
    ours.scripts.OnClick(ours, "LeftButton")
    H.eq(_G.OverlookPanelShown(), false, "a click closes the panel")
    M.Toggle()
    for k in pairs(G) do _G[k] = kept[k] end
end)

H.test("panel: a hand-made button with a locked layer is still raised over the panel", function()
    local kept = {}
    local function Locked(name)
        local f = Obj()
        f.strata, f.level, f.fixed = "MEDIUM", 8, true
        f.GetName = function() return name end
        f.IsObjectType = function() return true end
        f.SetFixedFrameStrata = function(self, v) self.fixed = v end
        f.SetFixedFrameLevel = function() end
        f.SetFrameStrata = function(self, v) if not self.fixed then self.strata = v end end
        f.SetFrameLevel = function(self, v) if not self.fixed then self.level = v end end
        f.GetFrameStrata = function(self) return self.strata end
        f.GetFrameLevel = function(self) return self.level end
        return f
    end
    local lfg = Locked("LFGForeverMinimapButton")
    local minimap = Obj()
    minimap.GetChildren = function() return lfg end
    local G = {
        CreateFrame = function() return Obj() end, LibStub = function() return nil end,
        C_Timer = { NewTicker = function() end }, UISpecialFrames = {}, UIParent = Obj(),
        Minimap = minimap, GameTooltip = Obj(),
    }
    for k, v in pairs(G) do kept[k], _G[k] = _G[k], v end
    local ns = { RegisterCommand = function() end, db = { bottomBar = true, buttonsPerRow = 6 }, Shell = {} }
    local M = H.loadAddonFile("Shell/Buttons.lua", ns).Buttons
    M.Build(Obj())
    H.eq(M.Count(), 1)
    H.eq(lfg.strata, "DIALOG", "in the panel's strata")
    H.eq(lfg.level, 7, "above the panel")
    H.eq(lfg.fixed, true, "and locked again")
    for k in pairs(G) do _G[k] = kept[k] end
end)
