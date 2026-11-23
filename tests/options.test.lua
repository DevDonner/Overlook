-- Smoke test for the settings window: builds it from stub frames, opens every tab and moves every
-- control, so a typo in a builder fails here instead of in game.
local H = ...

local function noop() end

local function NewObj()
    local o = { scripts = {}, shown = true, Text = false } -- (Text: a field on real checkboxes)
    o.SetScript = function(self, k, f) self.scripts[k] = f end
    o.GetScript = function(self, k) return self.scripts[k] end
    o.Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    o.Hide = function(self) self.shown = false end
    o.IsShown = function(self) return self.shown end
    o.SetShown = function(self, v) self.shown = v and true or false end
    o.CreateFontString = function() return NewObj() end
    o.CreateTexture = function() return NewObj() end
    o.GetChecked = function(self) return self.checked end
    o.SetChecked = function(self, v) self.checked = v end
    return setmetatable(o, {
        __index = function(_, k)
            if type(k) == "string" and k:match("^%u") then return noop end
        end,
    })
end

local made
local GLOBALS = {
    CreateFrame = function() local f = NewObj(); made[#made + 1] = f; return f end,
    UIParent = NewObj(),
    UISpecialFrames = {},
    GameTooltip = NewObj(),
    LibStub = function() return nil end,
    HideUIPanel = noop,
}
local saved = {}
for k in pairs(GLOBALS) do saved[k] = _G[k] end

local ns

local function Fresh()
    made = {}
    for k, v in pairs(GLOBALS) do _G[k] = v end
    ns = { RegisterCommand = noop, name = "FarZoomMinimap" }
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/IconPrefs.lua", ns)
    H.loadAddonFile("Core/QuestieToggles.lua", ns)
    ns.db = ns.Settings.Load(nil)
    ns.Shell = { Apply = noop, ResetPosition = noop, nativeSize = 140 }
    ns.Far = { SetMaxZoom = noop, ApplyArrowSize = noop, Recenter = noop }
    ns.Routes = { Refresh = noop }
    ns.Party = { Refresh = noop }
    ns.NativeIcons = { SetShown = noop }
    ns.Mirror = { Groups = function() return { { key = "questie:available", count = 3 }, { key = "tomtom", label = "TomTom", count = 1 } } end,
        RefreshPrefs = noop }
    H.loadAddonFile("UI/Widgets.lua", ns)
    H.loadAddonFile("UI/Options.lua", ns)
end
H.beforeEach(Fresh)

-- Every frame with an OnClick or OnValueChanged script: buttons, checkboxes, sliders.
local function Each(script)
    local out = {}
    for _, f in ipairs(made) do
        if f.scripts[script] then out[#out + 1] = f end
    end
    return out
end

H.test("the window builds and every tab opens", function()
    ns.Options.Show()
    local tabs = 0
    for _, f in ipairs(made) do
        if f.scripts.OnClick and not f.checked and f.SetText then tabs = tabs + 1 end
    end
    H.truthy(tabs >= 2)
    for _, b in ipairs(Each("OnClick")) do pcall(b.scripts.OnClick, b, "LeftButton") end
    ns.Options.Refresh()
end)

H.test("every checkbox and slider writes a setting without errors", function()
    ns.Options.Show()
    for _, c in ipairs(Each("OnClick")) do
        c.checked = true
        c.scripts.OnClick(c, "LeftButton")
        c.checked = false
        c.scripts.OnClick(c, "LeftButton")
    end
    for _, s in ipairs(Each("OnValueChanged")) do
        s.scripts.OnValueChanged(s, 1, true)
    end
    H.eq(ns.Settings.Load(ns.db), ns.db, "settings still load")
end)

H.test("the slider for arrow size stays inside its range", function()
    ns.Options.Show()
    for _, s in ipairs(Each("OnValueChanged")) do s.scripts.OnValueChanged(s, 999, true) end
    H.eq(ns.db.arrowScale, 2)
    H.eq(ns.db.routeWidth, 6)
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
