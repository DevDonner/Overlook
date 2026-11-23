-- The settings window (/fzm, the minimap button, the addon compartment, or Options > AddOns),
-- and the minimap button itself. Settings sit on tabs; each tab is a scrolling page built with
-- the small Page helper below, so a new setting is one line in its tab's builder.
local _, ns = ...

local W, IconPrefs = ns.Widgets, ns.IconPrefs

local Options = {}
ns.Options = Options

local NAME = "FarZoomMinimapOptions"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local WIDTH, HEIGHT = 460, 580
local CONTENT_WIDTH = WIDTH - 50

local QUESTIE_LABELS = {
    available = "Available quests",
    complete = "Quest turn-ins",
    monster = "Kill objectives",
    object = "Object objectives",
    item = "Loot objectives",
    event = "Event objectives",
    manual = "Townsfolk and manual",
    other = "Other Questie icons",
}

local frame
local pages, tabs = {}, {}
local current

----------------------------------------------------------------------------------------------------
-- Page: a scrolling column of controls. Each add returns the control; Refresh re-reads them all.

local Page = {}
Page.__index = Page

local function NewPage(parent, title)
    local p = setmetatable({ title = title, controls = {}, y = -4, onRefresh = {} }, Page)
    p.scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    p.scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -58)
    p.scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -32, 10)
    p.content = CreateFrame("Frame", nil, p.scroll)
    p.content:SetSize(CONTENT_WIDTH, 400)
    p.scroll:SetScrollChild(p.content)
    p.scroll:Hide()
    return p
end

function Page:Place(widget, x, height)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, self.y)
    self.y = self.y - height
    self.content:SetHeight(-self.y + 20)
    return widget
end

function Page:Header(text)
    if self.y < -10 then self.y = self.y - 8 end
    return self:Place(W.Header(self.content, text), 0, 26)
end

function Page:Note(text)
    local n = W.Note(self.content, text)
    n:SetWidth(CONTENT_WIDTH - 10)
    return self:Place(n, 4, 18)
end

function Page:Add(control, x, height)
    self.controls[#self.controls + 1] = control
    return self:Place(control, x or 0, height)
end

-- A checkbox bound to ns.db[key] (or get/set when key is a table { get, set }).
function Page:Check(label, key, tip, after)
    local get, set
    if type(key) == "table" then
        get, set = key[1], key[2]
    else
        get = function() return ns.db[key] == true end
        set = function(on)
            ns.db[key] = on
            if after then after(on) end
        end
    end
    return self:Add(W.Check(self.content, label, get, set, tip), 0, 26)
end

-- A slider bound to ns.db[key], range from Settings.RANGES.
function Page:Slider(label, key, step, fmt, tip, after)
    local r = ns.Settings.RANGES[key]
    return self:Add(W.Slider(self.content, label, r[1], r[2], step, 200, fmt,
        function() return ns.db[key] end,
        function(v)
            ns.db[key] = ns.Settings.Clamp(key, v)
            if after then after(ns.db[key]) end
        end, tip), 4, 44)
end

function Page:Button(text, width, onClick, tip)
    return self:Place(W.Button(self.content, text, width, onClick, tip), 4, 32)
end

function Page:Refresh()
    for _, c in ipairs(self.controls) do c.Refresh() end
    for _, fn in ipairs(self.onRefresh) do fn() end
end

local function Percent(v) return string.format("%d%%", v * 100 + 0.5) end

-- A list of checkboxes rebuilt on every refresh from entries() -> { { label, icon, checked(),
-- toggle() } }, starting at the page's current position. Rows are pooled.
function Page:DynamicList(entries, empty)
    local top, pool = self.y, {}
    local note = W.Note(self.content, empty or "")
    local function Layout()
        local list = entries()
        local y = top
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", self.content, "TOPLEFT", 4, y)
        note:SetShown(#list == 0)
        if #list == 0 then y = y - 18 end
        for i, e in ipairs(list) do
            local row = pool[i]
            if not row then
                row = W.Check(self.content, "", function() return row.entry.checked() end,
                    function() row.entry.toggle(); row.Refresh() end)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", row, "RIGHT", 2, 0)
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                pool[i] = row
            end
            row.entry = e
            row.label:SetText(e.label)
            row.icon:SetTexture(e.icon)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, y)
            row.Refresh()
            row:Show()
            y = y - 26
        end
        for i = #list + 1, #pool do pool[i]:Hide() end
        self.content:SetHeight(-y + 20)
    end
    self.onRefresh[#self.onRefresh + 1] = Layout
end

----------------------------------------------------------------------------------------------------
-- Icons tab: far-map icon groups (show, size, shrink with zoom), one row per group seen

local rows = {}
local rowsPage, rowsTop

local function GroupLabel(group)
    if IconPrefs.IsQuestie(group.key) then
        local t = group.key:sub(9)
        return "Questie: " .. (QUESTIE_LABELS[t] or t)
    end
    return group.label or group.key
end

local function SetPref(key, action, value)
    IconPrefs.Apply(ns.db, key, { [key] = true }, action, value)
    if ns.Mirror then ns.Mirror.RefreshPrefs() end
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    local content = rowsPage.content
    row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_WIDTH, 26)
    row.show = W.Check(row, "", function() return not IconPrefs.Get(ns.db, row.key) end,
        function(on) SetPref(row.key, on and "show" or "hide") end, "Show this group on the far map")
    row.show:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.show, "RIGHT", 2, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.size = W.Slider(row, nil, IconPrefs.SCALE_MIN, IconPrefs.SCALE_MAX, 0.05, 90,
        function(v) return string.format("x%.2f", v) end,
        function() return select(2, IconPrefs.Get(ns.db, row.key)) end,
        function(v) SetPref(row.key, "size", v) end, "Icon size")
    row.size:SetPoint("LEFT", row, "LEFT", 182, 0)
    row.shrink = W.Check(row, "", function() return select(3, IconPrefs.Get(ns.db, row.key)) end,
        function(on) SetPref(row.key, "shrink", on and "on" or "off") end,
        "Shrink with zoom: icons get smaller as you zoom out")
    row.shrink:SetPoint("LEFT", row, "LEFT", 336, 0)
    rows[i] = row
    return row
end

local function LayoutRows()
    local groups = ns.Mirror and ns.Mirror.Groups() or {}
    local y = rowsTop
    for i, g in ipairs(groups) do
        local row = Row(i)
        row.key = g.key
        row.name:SetText(string.format("%s |cff888888(%d)|r", GroupLabel(g), g.count))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rowsPage.content, "TOPLEFT", 0, y)
        row.show.Refresh()
        row.size.Refresh()
        row.shrink.Refresh()
        row:Show()
        y = y - 28
    end
    for i = #groups + 1, #rows do rows[i]:Hide() end
    rowsPage.content:SetHeight(-y + 20)
end

----------------------------------------------------------------------------------------------------
-- Tabs

local BUILDERS = {}

BUILDERS[1] = { "Map", function(p)
    p:Header("Map")
    p:Slider("Size", "size", 5, function(v) return v .. " px" end,
        "The map's width and height. You can also drag the corner grip.",
        function() ns.Shell.Apply() end)
    p:Add(W.Slider(p.content, "Furthest zoom", ns.Settings.FAR_MIN, ns.Settings.FAR_MAX, 100, 200,
        function(v) return v .. " yd" end,
        function() return ns.db.maxFarZoom end,
        function(v) ns.Far.SetMaxZoom(v) end,
        "How far out the mouse wheel can zoom, in yards from the centre to the edge. "
            .. "/fzm far shows how long the last zoom took to fill in."), 4, 46)
    p:Check("Lock size (hide the resize grip)", "locked", "Alt+drag still moves the map when it's locked.")
    p:Check("Smooth zooming", "smoothZoom")
    p:Check("Minimap button", { function() return not ns.db.minimapButton.hide end,
        function(on) Options.SetButtonShown(on) end })
    p.y = p.y - 6
    p:Button("Reset position", 130, function()
        ns.Shell.ResetPosition()
        Options.Refresh()
    end, "Moves the map back to a visible spot at the default size.")
end }

BUILDERS[2] = { "Icons", function(p)
    p:Header("Player arrow")
    p:Slider("Arrow size", "arrowScale", 0.05, Percent, "The player arrow on the far map.",
        function() if ns.Far then ns.Far.ApplyArrowSize() end end)

    p:Header("Quest areas")
    local function Areas() if ns.Areas then ns.Areas.Refresh() end end
    p:Check("Show quest areas", { function() return ns.db.questAreas ~= false end,
        function(on) ns.db.questAreas = on; Areas() end },
        "The game's blue shading where quest objectives are, on the far map.")
    p:Check("Only tracked quests", "questAreaTracked", "Only quests on your objective tracker.", Areas)
    p:Slider("Area fill", "questAreaFill", 0.05, Percent, nil, Areas)
    p:Slider("Area border", "questAreaBorder", 0.05, Percent, nil, Areas)

    p:Header("Routes and groups")
    p:Check("Questie's NPC routes", "routes", "Follows Questie's own route settings too.",
        function() if ns.Routes then ns.Routes.Refresh() end end)
    p:Slider("Route line width", "routeWidth", 0.5, function(v) return string.format("%.1f px", v) end,
        "Far map only; Questie's own setting sets the normal minimap's.",
        function() if ns.Routes then ns.Routes.Refresh() end end)
    p:Slider("Route opacity", "routeAlpha", 0.05, Percent, nil,
        function() if ns.Routes then ns.Routes.Refresh() end end)
    p:Check("Party and raid members", { function() return ns.db.partyDots ~= false end,
        function(on)
            ns.db.partyDots = on
            if ns.Party then ns.Party.Refresh() end
        end }, "Class-coloured dots; faded when someone is offline.")
    p:Check("Game's own quest and town icons", { function() return ns.db.nativeIcons == true end,
        function(on) ns.NativeIcons.SetShown(on) end },
        "Off: only Questie's icons, so turn-ins and town services aren't drawn twice. The game's own icons only show at native zoom. Find Herbs and other tracking spells are left alone.")

    p:Header("Icon groups on the far map")
    p:Note("Groups appear here once their icons have been seen.")
    for _, col in ipairs({ { "Show", 0 }, { "Group", 28 }, { "Size", 182 }, { "Shrink", 330 } }) do
        local n = W.Note(p.content, col[1])
        n:SetPoint("TOPLEFT", p.content, "TOPLEFT", col[2], p.y)
    end
    p.y = p.y - 16
    rowsPage, rowsTop = p, p.y
    p.onRefresh[#p.onRefresh + 1] = LayoutRows
end }

BUILDERS[3] = { "Questie", function(p)
    local Q = ns.QuestieToggles
    p:Header("Questie icons")
    p:Note("These are Questie's own settings: they apply on the normal minimap and the world map too.")
    for _, t in ipairs(Q.QUEST) do
        local key = t[1]
        p:Check(t[2], { function() return Q.Get(key) end, function(on) Q.Set(key, on) end })
        if key == "enabled" then p.y = p.y - 4 end
    end
    p:Header("Town icons")
    p:Note("Questie's town services for this character, as in its tracking menu.")
    p:DynamicList(Q.Townsfolk, "Questie's town list isn't available (is Questie loaded?).")
end }

BUILDERS[4] = { "Bars", function(p)
    local function Apply() if ns.Bars then ns.Bars.Apply() end end
    p:Header("Top bar")
    p:Check("Show the zone name above the map", "topBar", "Click it to open the world map.", Apply)
    p:Check("Over the map instead of above it", "topBarInside", nil, Apply)
    p:Check("Add the zone after the subzone", "topBarZone", nil, Apply)
    p:Check("Colour by PvP status", "topBarPvP", "Green friendly, red hostile, orange contested, blue sanctuary.", Apply)
    p:Check("Hide the game's own zone header", "hideZoneHeader",
        "The zone name the game shows above the minimap, while the top bar is on.", Apply)

    p:Header("Bottom bar")
    p:Check("Show the bottom bar", "bottomBar", nil, Apply)
    p:Check("Over the map instead of below it", "bottomBarInside", nil, Apply)
    p:Check("Coordinates", "barCoords", nil, Apply)
    p:Slider("Coordinate decimals", "coordDecimals", 1, function(v) return tostring(v) end, nil, Apply)
    p:Check("Far zoom distance", "barZoom", "How far the view reaches from the centre, while zoomed out.", Apply)
    p:Check("Clock", "barClock", "Your computer's time.", Apply)
    p:Check("24-hour clock", "clock24", nil, Apply)

    p:Header("Style")
    p:Slider("Text size", "barFont", 1, function(v) return v .. " px" end, nil, Apply)
    p:Slider("Background opacity", "barAlpha", 0.05, Percent, nil, Apply)
end }

local function ShowPage(i)
    current = i
    for j, p in ipairs(pages) do
        p.scroll:SetShown(j == i)
        if j == i then tabs[j]:LockHighlight() else tabs[j]:UnlockHighlight() end
        tabs[j]:SetEnabled(j ~= i)
    end
    pages[i]:Refresh()
end

-- Other files add tabs: Options.AddTab(title, builder(page)). Call before the window is built.
function Options.AddTab(title, builder)
    BUILDERS[#BUILDERS + 1] = { title, builder }
end

----------------------------------------------------------------------------------------------------
-- Window

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", NAME, UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    table.insert(UISpecialFrames, NAME) -- Escape closes it

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -6)
    title:SetText("FarZoomMinimap")

    local x, gap = 12, 3
    local tabWidth = math.floor((WIDTH - 24 - gap * (#BUILDERS - 1)) / #BUILDERS)
    for i, b in ipairs(BUILDERS) do
        local page = NewPage(f, b[1])
        b[2](page)
        pages[i] = page
        local tab = W.Button(f, b[1], tabWidth, function() ShowPage(i) end)
        tab:SetPoint("TOPLEFT", f, "TOPLEFT", x, -28)
        tabs[i] = tab
        x = x + tabWidth + gap
    end

    f:SetScript("OnShow", function() ShowPage(current or 1) end)
end

function Options.Refresh()
    if frame and current then pages[current]:Refresh() end
end

function Options.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function Options.Show()
    if not frame then Build() end
    frame:Show()
end

----------------------------------------------------------------------------------------------------
-- Minimap button (LibDBIcon, like other addons), addon compartment, Options > AddOns

local dbIcon

function Options.SetButtonShown(on)
    ns.db.minimapButton.hide = not on
    if dbIcon then
        if on then dbIcon:Show(ns.name) else dbIcon:Hide(ns.name) end
    end
end

local function OnClick(_, button)
    if button == "RightButton" then
        if ns.Far then ns.Far.Recenter() end
    else
        Options.Toggle()
    end
end

local function RegisterButton()
    local okL, ldb = pcall(LibStub, "LibDataBroker-1.1", true)
    local okI, icon = pcall(LibStub, "LibDBIcon-1.0", true)
    if not (okL and ldb and okI and icon) then return end
    local obj = ldb:NewDataObject(ns.name, {
        type = "launcher",
        text = "FarZoomMinimap",
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = function(tt)
            tt:AddLine("FarZoomMinimap")
            tt:AddLine("|cffffffffClick|r  settings", 0.8, 0.8, 0.8)
            tt:AddLine("|cffffffffRight-click|r  recenter", 0.8, 0.8, 0.8)
        end,
    })
    if obj then
        icon:Register(ns.name, obj, ns.db.minimapButton)
        dbIcon = icon
    end
end

-- Named in the TOC (## AddonCompartmentFunc).
function FarZoomMinimap_OnAddonCompartmentClick(_, button)
    OnClick(nil, button)
end

local function RegisterBlizzardCategory()
    local S = _G.Settings
    if not (S and S.RegisterCanvasLayoutCategory and S.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FarZoomMinimap")
    local open = W.Button(panel, "Open settings", 140, function()
        if _G.SettingsPanel and _G.SettingsPanel:IsShown() then HideUIPanel(_G.SettingsPanel) end
        Options.Show()
    end)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    local hint = W.Note(panel, "Also: /fzm, or the minimap button.")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -8)
    pcall(function()
        local category = S.RegisterCanvasLayoutCategory(panel, "FarZoomMinimap")
        S.RegisterAddOnCategory(category)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    RegisterButton()
    RegisterBlizzardCategory()
end)

ns.RegisterCommand("options", "open the settings", Options.Show)
