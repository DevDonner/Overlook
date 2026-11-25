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
    IsShiftKeyDown = function() return false end,
}
local saved = {}
for k in pairs(GLOBALS) do saved[k] = _G[k] end

local ns

local function Fresh()
    made = {}
    for k, v in pairs(GLOBALS) do _G[k] = v end
    ns = { RegisterCommand = noop, name = "Overlook" }
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/IconPrefs.lua", ns)
    H.loadAddonFile("Core/QuestieToggles.lua", ns)
    H.loadAddonFile("Core/Profiles.lua", ns)
    ns.db = ns.Profiles.Init(ns.Settings.Load(nil))
    ns.Shell = { Apply = noop, ResetPosition = noop, SetRotate = noop, SetHostOthers = noop, nativeSize = 140 }
    H.loadAddonFile("Core/Host.lua", ns)
    ns.Others = { Refresh = noop }
    ns.Bars = { Apply = noop }
    ns.Far = { SetMaxZoom = noop, ApplyArrowSize = noop, Recenter = noop }
    ns.Routes = { Refresh = noop }
    ns.Party = { Refresh = noop }
    ns.NativeIcons = { SetShown = noop }
    ns.Mirror = { Groups = function() return { { key = "questie:available", count = 3 }, { key = "tomtom", label = "TomTom", count = 1 } } end,
        RefreshPrefs = noop }
    H.loadAddonFile("Shell/Bars.lua", ns) -- (its pure ButtonSpots; nothing built)
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

----------------------------------------------------------------------------------------------------
-- The Layout and Addons tabs: pick-one rows, rows that come and go, the Advanced fold

local LAYOUT, ADDONS = 4, 5

local function Page(i)
    ns.Options.Show()
    ns.Options._showPage(i)
    return ns.Options._pages[i]
end

local function Row(p, label)
    for _, it in ipairs(p.items) do
        if it.widget.labelText == label then return it.widget end
    end
    error("no row " .. label)
end

local function Pick(p, label, value)
    for _, r in ipairs(Row(p, label).radios) do
        if r.value == value and r.shown then
            r.scripts.OnClick(r)
            return
        end
    end
    error("no choice " .. tostring(value) .. " in " .. label)
end

local function Values(p, label)
    local out = {}
    for _, r in ipairs(Row(p, label).radios) do
        if r.shown then out[#out + 1] = r.value end
    end
    return table.concat(out, ",")
end

local function ShownCount(p)
    local n = 0
    for _, it in ipairs(p.items) do if it.widget.shown then n = n + 1 end end
    return n
end

local function Fold(p)
    for _, it in ipairs(p.items) do
        if it.widget.open ~= nil then return it.widget end
    end
end

H.test("layout: the layout row picks a preset, and shows which one is in use", function()
    local p = Page(LAYOUT)
    Pick(p, "Layout", "compact")
    H.eq(ns.Settings.CurrentPreset(ns.db), "compact")
    H.eq(ns.db.bottomBar, false)
    local ticked
    for _, r in ipairs(Row(p, "Layout").radios) do if r.checked then ticked = r.value end end
    H.eq(ticked, "compact")
end)

H.test("layout: the zone name and info bar each have one place: above/below, on the map, or off", function()
    local p = Page(LAYOUT)
    H.eq(Values(p, "Zone name"), "outside,inside,off")
    Pick(p, "Zone name", "inside")
    H.eq(ns.db.topBar, true); H.eq(ns.db.topBarInside, true)
    Pick(p, "Info bar", "off")
    H.eq(ns.db.bottomBar, false)
    Pick(p, "Info bar", "outside")
    H.eq(ns.db.bottomBar, true); H.eq(ns.db.bottomBarInside, false)
end)

H.test("layout: the round map offers only under the map or off", function()
    ns.db.round = true
    local p = Page(LAYOUT)
    H.eq(Values(p, "Zone name"), "outside,off")
end)

H.test("layout: the column rows show only while the column is used", function()
    local p = Page(LAYOUT)
    H.eq(Row(p, "Column side").shown, false, "everything on the bars")
    H.eq(Row(p, "Column").shown, false)
    Pick(p, "Buttons", "side")
    H.eq(Row(p, "Column side").shown, true)
    H.eq(Row(p, "Column").shown, true)
    Pick(p, "Column", "outside")
    H.eq(ns.db.buttonColumn, "outside")
    Pick(p, "Column side", "right")
    H.eq(ns.db.buttonSide, "right")
    Pick(p, "Buttons", "none")
    H.eq(Row(p, "Column side").shown, false)
end)

H.test("layout: a bar turned off puts its buttons in the column, so the column rows appear", function()
    local p = Page(LAYOUT)
    Pick(p, "Info bar", "off")
    H.eq(Row(p, "Column side").shown, true)
end)

H.test("layout: inside or outside isn't asked on the round map (always outside)", function()
    ns.db.round = true
    ns.db.buttonSpot = "side"
    local p = Page(LAYOUT)
    H.eq(Row(p, "Column side").shown, true)
    H.eq(Row(p, "Column").shown, false)
end)

H.test("layout: the advanced settings are folded away until asked for", function()
    local p = Page(LAYOUT)
    local closed = ShownCount(p)
    local fold = Fold(p)
    H.truthy(fold, "a fold")
    fold.scripts.OnClick(fold)
    local open = ShownCount(p)
    H.truthy(open > closed + 5, "text size, clock, coordinates... appear")
    Pick(p, "Info bar", "off")
    H.truthy(ShownCount(p) < open, "the info bar's own settings go with it")
    fold.scripts.OnClick(fold)
    H.eq(ShownCount(p) < open, true)
end)

H.test("addons: the work-inside switch shows only with another minimap addon", function()
    local p = Page(ADDONS)
    local hostRow
    for _, it in ipairs(p.items) do
        if it.when and it.widget.scripts.OnClick and not it.fold then hostRow = it.widget; break end
    end
    H.truthy(hostRow, "the host switch")
    H.eq(hostRow.shown, false, "nothing to work inside")
    ns.Host.owner = "EllesmereUI"
    p:Refresh()
    H.eq(hostRow.shown, true)
    ns.Host.owner = nil
end)

H.test("addons: two switches up front, the rest folded", function()
    local p = Page(ADDONS)
    local fold = Fold(p)
    local closed = ShownCount(p)
    fold.scripts.OnClick(fold)
    H.eq(ShownCount(p), closed + 5, "four takeover switches and the shape answer")
    ns.Host.owner = "EllesmereUI"
    p:Refresh()
    H.eq(ShownCount(p), closed + 5, "hosted: the shape answer goes, the host switch comes")
    ns.Host.owner = nil
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
