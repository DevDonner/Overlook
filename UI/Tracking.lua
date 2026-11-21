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
        local ok, err = pcall(C_Minimap.SetTracking, e.index, on)
        if not ok then ns.Printf("the game refused %s: %s", e.name, tostring(err)) end
        -- The game may switch others off (one finder at a time), or keep this one as it was:
        -- read it all back and say so if it didn't change.
        local name, index = e.name, e.index
        C_Timer.After(0.3, function()
            for _, now in ipairs(TrackingList.Read(C_Minimap)) do
                if now.index == index and now.active ~= on then
                    ns.Printf("the game kept %s %s (it didn't take the change)", name, now.active and "on" or "off")
                end
            end
            Tracking.Refresh()
        end)
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

-- Every tracking entry as the game reports it, for finding out why one won't change.
local function Dump()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
        ns.Print("this client has no C_Minimap tracking list")
        return
    end
    local n = C_Minimap.GetNumTrackingTypes()
    ns.Printf("tracking entries: %s", ns.Show(n))
    if ns.IsSecret(n) then return end
    for i = 1, n do
        local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
        local parts = {}
        if ok and type(info) == "table" then
            for k, v in pairs(info) do parts[#parts + 1] = k .. "=" .. ns.Show(v) end
            table.sort(parts)
        else
            parts[1] = ok and ns.Show(info) or ("error " .. tostring(info))
        end
        if C_Minimap.GetTrackingFilter then
            local okF, f = pcall(C_Minimap.GetTrackingFilter, i)
            if okF and type(f) == "table" then
                for k, v in pairs(f) do parts[#parts + 1] = "filter." .. k .. "=" .. ns.Show(v) end
            end
        end
        ns.Printf("%d: %s", i, table.concat(parts, " "))
    end
end

ns.RegisterCommand("tracking", "open the minimap icons menu (/fzm tracking dump: list the raw entries)", function(arg)
    if arg == "dump" then
        Dump()
        return
    end
    if menu then
        if not button:IsShown() then ns.db.trackingButton = true; Tracking.Place() end
        Tracking.Toggle()
    end
end)
