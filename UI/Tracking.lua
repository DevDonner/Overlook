-- The tracking button: a square button under the map's bottom-left corner (the Recenter button's
-- opposite side) that opens a checklist of the game's own minimap icons (town services, herbs,
-- minerals, quest areas...). Ticking one is the same as the game's tracking menu, so the choice
-- is the game's and is remembered by it.
local _, ns = ...

local W, TrackingList = ns.Widgets, ns.TrackingList

local Tracking = {}
ns.Tracking = Tracking

local BUTTON_SIZE = 22
local ROW_HEIGHT = 22
local MENU_WIDTH = 210
local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local root, button, menu
local rows = {}

local function Above()
    return (ns.db.y or 0) < 0 -- map in the lower half of the screen: controls go above it
end

function Tracking.Place()
    if not button then return end
    button:ClearAllPoints()
    if Above() then
        button:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 4)
    else
        button:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, -4)
    end
    button:SetShown(ns.db.trackingButton ~= false)
    if menu and menu:IsShown() then Tracking.PlaceMenu() end
end

function Tracking.PlaceMenu()
    menu:ClearAllPoints()
    if Above() then
        menu:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    end
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = W.Check(menu, "", function() return row.entry and row.entry.active end, function(on)
        local e = row.entry
        if not e or not C_Minimap.SetTracking then return end
        local ok = pcall(C_Minimap.SetTracking, e.index, on)
        if not ok then ns.Print("the game didn't allow that change") end
        -- The game may switch others off (one finder at a time): read it all back.
        C_Timer.After(0, Tracking.Refresh)
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "RIGHT", 2, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.label:SetWidth(MENU_WIDTH - 60)
    row.label:SetJustifyH("LEFT")
    rows[i] = row
    return row
end

function Tracking.Refresh()
    if not (menu and menu:IsShown()) then return end
    local list = TrackingList.Read(C_Minimap)
    local y = -8
    for i, e in ipairs(list) do
        local row = Row(i)
        row.entry = e
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, y)
        if e.texture then row.icon:SetTexture(e.texture) else row.icon:SetTexture(nil) end
        row.label:SetText(e.name)
        row.Refresh()
        row:Show()
        y = y - ROW_HEIGHT
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    menu.empty:SetShown(#list == 0)
    if #list == 0 then y = y - ROW_HEIGHT end
    menu:SetHeight(-y + 8)
end

function Tracking.Toggle()
    if menu:IsShown() then
        menu:Hide()
    else
        Tracking.PlaceMenu()
        menu:Show()
        Tracking.Refresh()
    end
end

local function BuildMenu()
    menu = CreateFrame("Frame", "FarZoomMinimapTrackingMenu", UIParent, "BackdropTemplate")
    menu:SetWidth(MENU_WIDTH)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu.empty = W.Note(menu, "The game lists nothing to track here.")
    menu.empty:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -12)
    menu:Hide()
    table.insert(UISpecialFrames, "FarZoomMinimapTrackingMenu") -- Escape closes it

    -- Closes on a click anywhere else.
    menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if self:IsShown() and not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
        else
            Tracking.Refresh()
        end
    end)
    menu:RegisterEvent("MINIMAP_UPDATE_TRACKING")
end

function Tracking.Build(parent, level)
    root = parent
    button = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameLevel(level)
    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.icon:SetTexture(ICON)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetScript("OnClick", function() Tracking.Toggle() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimap icons")
        GameTooltip:AddLine("Choose which of the game's own icons the minimap shows.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    BuildMenu()
    Tracking.Place()
end

ns.RegisterCommand("tracking", "open the minimap icons menu", function()
    if menu then
        if not button:IsShown() then ns.db.trackingButton = true; Tracking.Place() end
        Tracking.Toggle()
    end
end)
