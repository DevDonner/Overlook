-- The settings window (/fzm, the minimap button, the addon compartment, or Options > AddOns),
-- and the minimap button itself.
local _, ns = ...

local W, IconPrefs = ns.Widgets, ns.IconPrefs

local Options = {}
ns.Options = Options

local NAME = "FarZoomMinimapOptions"
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local WIDTH, HEIGHT = 440, 560
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

local frame, content
local controls = {}       -- map controls, refreshed on show
local rows = {}           -- icon group rows, pooled
local rowsTop             -- y offset where the icon rows start

local function GroupLabel(group)
    if IconPrefs.IsQuestie(group.key) then
        local t = group.key:sub(9)
        return "Questie: " .. (QUESTIE_LABELS[t] or t)
    end
    return group.label or group.key
end

----------------------------------------------------------------------------------------------------
-- Icon group rows: show, size, shrink with zoom

local function SetPref(key, action, value)
    IconPrefs.Apply(ns.db, key, { [key] = true }, action, value)
    if ns.Mirror then ns.Mirror.RefreshPrefs() end
end

local function Row(i)
    local row = rows[i]
    if row then return row end
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
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        row.show.Refresh()
        row.size.Refresh()
        row.shrink.Refresh()
        row:Show()
        y = y - 28
    end
    for i = #groups + 1, #rows do rows[i]:Hide() end
    content:SetHeight(-y + 20)
end

----------------------------------------------------------------------------------------------------
-- Window

local function Place(widget, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
    return widget
end

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

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 10)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_WIDTH, 800)
    scroll:SetScrollChild(content)

    local y = -4
    Place(W.Header(content, "Map"), 0, y)
    y = y - 28

    controls.size = Place(W.Slider(content, "Size", ns.Settings.SIZE_MIN, ns.Settings.SIZE_MAX, 5, 200,
        function(v) return v .. " px" end,
        function() return ns.db.size end,
        function(v)
            ns.db.size = ns.Settings.ClampSize(v)
            ns.Shell.Apply()
        end, "The map's width and height. You can also drag the corner grip."), 4, y)
    y = y - 42

    controls.maxZoom = Place(W.Slider(content, "Furthest zoom", ns.Settings.FAR_MIN, ns.Settings.FAR_MAX, 100, 200,
        function(v) return v .. " yd" end,
        function() return ns.db.maxFarZoom end,
        function(v) ns.Far.SetMaxZoom(v) end,
        "How far out the mouse wheel can zoom, in yards from the centre to the edge."), 4, y)
    y = y - 46

    controls.locked = Place(W.Check(content, "Lock size (hide the resize grip)",
        function() return ns.db.locked end,
        function(on) ns.db.locked = on end,
        "Alt+drag still moves the map when it's locked."), 0, y)
    y = y - 26
    controls.smooth = Place(W.Check(content, "Smooth zooming",
        function() return ns.db.smoothZoom end,
        function(on) ns.db.smoothZoom = on end), 0, y)
    y = y - 26
    controls.routes = Place(W.Check(content, "Show Questie's NPC routes on the far map",
        function() return ns.db.routes ~= false end,
        function(on)
            ns.db.routes = on
            if ns.Routes then ns.Routes.Refresh() end
        end, "Follows Questie's own route settings too."), 0, y)
    y = y - 26
    controls.party = Place(W.Check(content, "Show party and raid members on the far map",
        function() return ns.db.partyDots ~= false end,
        function(on)
            ns.db.partyDots = on
            if ns.Party then ns.Party.Refresh() end
        end, "Class-coloured dots; faded when someone is offline."), 0, y)
    y = y - 26
    controls.tracking = Place(W.Check(content, "Minimap icons button (bottom-left)",
        function() return ns.db.trackingButton ~= false end,
        function(on)
            ns.db.trackingButton = on
            if ns.Tracking then ns.Tracking.Place() end
        end, "Opens a checklist of the game's own minimap icons: town services, herbs, minerals..."), 0, y)
    y = y - 26
    controls.button = Place(W.Check(content, "Minimap button",
        function() return not ns.db.minimapButton.hide end,
        function(on) Options.SetButtonShown(on) end), 0, y)
    y = y - 32

    Place(W.Button(content, "Reset position", 130, function()
        ns.Shell.ResetPosition()
        Options.Refresh()
    end, "Moves the map back to a visible spot at the default size."), 4, y)
    y = y - 40

    Place(W.Header(content, "Icons on the far map"), 0, y)
    y = y - 22
    for _, col in ipairs({ { "Show", 0 }, { "Group", 28 }, { "Size", 182 }, { "Shrink", 330 } }) do
        Place(W.Note(content, col[1]), col[2], y)
    end
    y = y - 16
    rowsTop = y

    f:SetScript("OnShow", Options.Refresh)
end

function Options.Refresh()
    if not frame then return end
    for _, c in pairs(controls) do c.Refresh() end
    LayoutRows()
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
