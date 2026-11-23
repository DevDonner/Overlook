-- Other addons' minimap buttons, gathered into a panel. A small button on the bottom bar opens it
-- (on click, not hover); the buttons sit in a grid inside, in the bars' style, and can't be dragged
-- around the map any more. Buttons made later are picked up as they appear.
--
-- Which buttons: every LibDBIcon button (most addons), plus buttons parented to the minimap
-- whose names say they're minimap buttons. While MinimapButtonButton is loaded it owns them and
-- this stays out of the way. Turning collecting off puts them back after a /reload (LibDBIcon
-- places its buttons when it loads).
--
-- Settings: collectButtons (on/off), buttonsPerRow.
local _, ns = ...

local Buttons = {}
ns.Buttons = Buttons

local SIZE, GAP, PAD = 26, 4, 6 -- px: slot, between slots, panel edge
local SCAN_EVERY = 2            -- seconds, for buttons made after login

local panel, trigger
local collected = {}            -- button -> { setPoint, clearAllPoints, setParent } (originals)
local order = {}                -- buttons in the order shown

-- Slot positions for count buttons, perRow to a row: { x, y } offsets from the panel's top-left,
-- and the panel's width and height. Pure.
function Buttons.Grid(count, perRow, size, gap, pad)
    perRow = math.max(1, math.min(perRow, math.max(count, 1)))
    local out = {}
    for i = 1, count do
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        out[i] = { pad + col * (size + gap), -(pad + row * (size + gap)) }
    end
    local rows = math.max(1, math.ceil(count / perRow))
    return out, 2 * pad + perRow * size + (perRow - 1) * gap, 2 * pad + rows * size + (rows - 1) * gap
end

-- Whether a frame's name marks it as some addon's minimap button. Pure.
local BLIZZARD = { "^MiniMap", "^Minimap", "^GameTime", "^QueueStatus", "^ExpansionLanding",
    "^AddonCompartment", "^TimeManager", "^FarZoomMinimap" }
function Buttons.LooksLikeButton(name)
    if type(name) ~= "string" then return false end
    if name:find("^LibDBIcon10_") then return true end
    for _, p in ipairs(BLIZZARD) do
        if name:find(p) then return false end
    end
    local l = name:lower()
    return l:find("minimapbutton", 1, true) ~= nil or l:find("minimap_button", 1, true) ~= nil
end

local function Active()
    if ns.db.collectButtons == false or not ns.db.bottomBar then return false end
    local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
    if loaded and loaded("MinimapButtonButton") then return false end
    return true
end
Buttons.Active = Active

local function DBIcon()
    local ok, lib = pcall(LibStub, "LibDBIcon-1.0", true)
    return ok and lib or nil
end

-- Shown by its addon, and not hidden through LibDBIcon (its "hide" setting). Showing and hiding
-- stay with the addons; the panel only lays out what's shown.
local function Wanted(button)
    if button.db and button.db.hide then return false end
    return button:IsShown() == true
end

local function Noop() end

-- Takes a button into the panel. Its own SetPoint / ClearAllPoints / SetParent are swapped for
-- no-ops (originals kept), so LibDBIcon and the addon can't pull it back onto the map edge; its
-- strata and level are locked too, or an addon resetting them drops it under the panel's
-- background (the dark, greyed-out buttons).
local function Collect(button)
    if collected[button] or not button.SetParent then return end
    collected[button] = {
        setPoint = button.SetPoint, clearAllPoints = button.ClearAllPoints, setParent = button.SetParent,
    }
    order[#order + 1] = button
    local o = collected[button]
    o.setParent(button, panel)
    button.SetPoint, button.ClearAllPoints, button.SetParent = Noop, Noop, Noop
    if button.RegisterForDrag then pcall(button.RegisterForDrag, button) end -- no drag buttons
    if button.SetFrameStrata then button:SetFrameStrata(panel:GetFrameStrata()) end
    if button.SetFrameLevel then button:SetFrameLevel(panel:GetFrameLevel() + 2) end
    if button.SetFixedFrameStrata then pcall(button.SetFixedFrameStrata, button, true) end
    if button.SetFixedFrameLevel then pcall(button.SetFixedFrameLevel, button, true) end
    button.SetFrameStrata, button.SetFrameLevel = Noop, Noop
end

local function Layout()
    local shown = {}
    for _, b in ipairs(order) do
        if Wanted(b) then shown[#shown + 1] = b end
    end
    table.sort(shown, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    local slots, w, h = Buttons.Grid(#shown, ns.db.buttonsPerRow or 6, SIZE, GAP, PAD)
    for i, b in ipairs(shown) do
        local o = collected[b]
        o.clearAllPoints(b)
        o.setPoint(b, "CENTER", panel, "TOPLEFT", slots[i][1] + SIZE / 2, slots[i][2] - SIZE / 2)
    end
    panel:SetSize(w, h)
    if trigger then trigger:SetShown(#shown > 0) end
    panel.empty = #shown == 0
end

-- Looks for buttons to collect.
local function Scan()
    if not panel or not Active() then return end
    local before = #order
    local lib = DBIcon()
    if lib and lib.GetButtonList and lib.GetMinimapButton then
        local ok, names = pcall(lib.GetButtonList, lib)
        for _, name in ipairs(ok and names or {}) do
            local b = lib:GetMinimapButton(name)
            if b then Collect(b) end
        end
    end
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop, ns.Shell.root }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                local okN, name = pcall(child.GetName, child)
                if okN and Buttons.LooksLikeButton(name) and child.IsObjectType and child:IsObjectType("Button") then
                    Collect(child)
                end
            end
        end
    end
    if #order ~= before or panel:IsShown() then Layout() end
end
Buttons.Scan = Scan

-- Just above the bottom bar, from its left end (over the map, next to the button that opened it).
local function PlacePanel()
    local bar = trigger:GetParent()
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
end

function Buttons.Toggle()
    if not panel then return end
    if panel:IsShown() then
        panel:Hide()
    else
        Scan()
        Layout()
        if panel.empty then return end
        PlacePanel()
        panel:Show()
    end
end

-- The top bar calls this with its trigger button.
function Buttons.Build(triggerButton)
    trigger = triggerButton
    panel = CreateFrame("Frame", "FarZoomMinimapButtonPanel", UIParent, "BackdropTemplate")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.05, 0.06, 0.08, 0.92)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    table.insert(UISpecialFrames, "FarZoomMinimapButtonPanel") -- Escape closes it

    local lib = DBIcon()
    if lib and lib.RegisterCallback then
        pcall(lib.RegisterCallback, Buttons, "LibDBIcon_IconCreated", function() Scan() end)
    end
    C_Timer.NewTicker(SCAN_EVERY, Scan)
    Scan()
    Buttons.Apply()
end

-- Re-applies the settings (from the bars).
function Buttons.Apply()
    if not trigger then return end
    if not Active() then
        trigger:Hide()
        if panel then panel:Hide() end
        return
    end
    Scan()
    Layout()
    if panel:IsShown() then PlacePanel() end
end

function Buttons.Count()
    local n = 0
    for _, b in ipairs(order) do if Wanted(b) then n = n + 1 end end
    return n
end

ns.RegisterCommand("buttons", "list the minimap buttons in the button panel", function()
    if not Active() then
        local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
        ns.Printf("collecting is off%s", loaded and loaded("MinimapButtonButton")
            and " (MinimapButtonButton is loaded and handles them)" or "")
        return
    end
    for _, b in ipairs(order) do
        ns.Printf("  %s%s  %s %d  alpha %.2f", b:GetName() or "?", Wanted(b) and "" or " (hidden)",
            b:GetFrameStrata(), b:GetFrameLevel(), b:GetAlpha())
    end
    ns.Printf("%d button(s)", #order)
end)
