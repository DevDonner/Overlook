-- Other addons' minimap buttons, gathered into a panel. A small chevron on the bottom bar opens it
-- (on click, not hover); the buttons sit in a grid inside, in the bars' style. Buttons made later
-- are picked up as they appear.
--
-- LibDBIcon buttons (most addons) are not moved: the panel makes its own button from the addon's
-- data object (its icon, click and tooltip) and hides the original. Moving the originals left
-- them greyed out and dead to clicks, as their addons keep restyling and re-placing them. Other
-- buttons on the minimap whose names say they're minimap buttons have no data object, so those
-- are moved into the panel themselves.
--
-- While MinimapButtonButton is loaded it owns the buttons and this stays out of the way. Turning
-- collecting off puts them back after a /reload.
--
-- Settings: collectButtons (on/off), buttonsPerRow.
local _, ns = ...

local Buttons = {}
ns.Buttons = Buttons

local SIZE, GAP, PAD = 26, 4, 6 -- px: slot, between slots, panel edge
local SCAN_EVERY = 2            -- seconds, for buttons made after login
local TRIM = { 0.08, 0.92, 0.08, 0.92 } -- icon edges cut off, like LibDBIcon's

local panel, trigger
local entries = {}              -- { frame, name, obj (data object) or moved (original setters) }
local byKey = {}                -- [name or frame] = entry

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

-- A data object's icon: texture, texture coordinates and colour. Pure.
function Buttons.IconOf(obj)
    local c = type(obj.iconCoords) == "table" and #obj.iconCoords >= 4 and obj.iconCoords or TRIM
    return obj.icon, c, obj.iconR or 1, obj.iconG or 1, obj.iconB or 1
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

local function Noop() end

-- A click on a button in the panel closes it, once the addon's own click has run.
local function CloseAfterClick()
    if not panel then return end
    if C_Timer.After then
        C_Timer.After(0, function() panel:Hide() end)
    else
        panel:Hide()
    end
end

-- Hidden through LibDBIcon's own setting, or (a moved button) by its addon.
local function Wanted(e)
    if e.orig then return not (e.orig.db and e.orig.db.hide) end
    return e.frame:IsShown() == true
end

----------------------------------------------------------------------------------------------------
-- Our button for a LibDBIcon data object

local function ShowTooltip(self)
    local e = self.entry
    local obj = e.obj
    if obj.OnTooltipShow then
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        pcall(obj.OnTooltipShow, GameTooltip)
        GameTooltip:Show()
    elseif obj.OnEnter then
        pcall(obj.OnEnter, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(obj.label or e.name, 1, 1, 1)
        GameTooltip:Show()
    end
end

local function Proxy(name, orig, obj)
    local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
    b:SetSize(SIZE, SIZE)
    b:SetFrameLevel(panel:GetFrameLevel() + 2)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropColor(0.1, 0.11, 0.14, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:RegisterForClicks("AnyUp")
    b:SetScript("OnClick", function(self, button)
        local o = self.entry.obj
        if o.OnClick then pcall(o.OnClick, self, button) end
        CloseAfterClick()
    end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        ShowTooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        local o = self.entry.obj
        if o.OnLeave then pcall(o.OnLeave, self) end
        GameTooltip:Hide()
    end)
    b.entry = { frame = b, name = name, orig = orig, obj = obj }
    -- The original stays hidden: LibDBIcon and its addon show it again from time to time.
    orig:Hide()
    orig.Show = Noop
    if orig.SetShown then orig.SetShown = Noop end
    return b.entry
end

local function PaintIcon(e)
    local tex, c, r, g, bl = Buttons.IconOf(e.obj)
    e.frame.icon:SetTexture(tex)
    e.frame.icon:SetTexCoord(c[1], c[2], c[3], c[4])
    e.frame.icon:SetVertexColor(r, g, bl)
end

----------------------------------------------------------------------------------------------------
-- A button with no data object, moved into the panel. Its SetPoint / ClearAllPoints / SetParent
-- and strata setters become no-ops (originals kept), so its addon can't pull it back out.

local function Move(button)
    local o = {
        setPoint = button.SetPoint, clearAllPoints = button.ClearAllPoints, setParent = button.SetParent,
    }
    o.setParent(button, panel)
    button.SetPoint, button.ClearAllPoints, button.SetParent = Noop, Noop, Noop
    if button.RegisterForDrag then pcall(button.RegisterForDrag, button) end
    -- Some lock their strata and level (as LibDBIcon does; LFGForever's hand-made button too): a
    -- locked button ignores the change and stays under the panel's background, which then takes
    -- its clicks. Unlocked, raised over the panel, then locked again.
    if button.SetFixedFrameStrata then pcall(button.SetFixedFrameStrata, button, false) end
    if button.SetFixedFrameLevel then pcall(button.SetFixedFrameLevel, button, false) end
    button:SetFrameStrata(panel:GetFrameStrata())
    button:SetFrameLevel(panel:GetFrameLevel() + 2)
    if button.SetFixedFrameStrata then pcall(button.SetFixedFrameStrata, button, true) end
    if button.SetFixedFrameLevel then pcall(button.SetFixedFrameLevel, button, true) end
    button.SetFrameStrata, button.SetFrameLevel = Noop, Noop
    if button.HookScript then button:HookScript("OnClick", CloseAfterClick) end
    return { frame = button, name = button:GetName(), moved = o }
end

local function Add(key, e)
    byKey[key] = e
    entries[#entries + 1] = e
end

local function Place(e, x, y)
    local cx, cy = x + SIZE / 2, y - SIZE / 2
    if e.moved then
        e.moved.clearAllPoints(e.frame)
        e.moved.setPoint(e.frame, "CENTER", panel, "TOPLEFT", cx, cy)
    else
        e.frame:ClearAllPoints()
        e.frame:SetPoint("CENTER", panel, "TOPLEFT", cx, cy)
    end
end

local function Label(e)
    return tostring(e.obj and e.obj.label or e.name or ""):lower()
end

local function Layout()
    local shown = {}
    for _, e in ipairs(entries) do
        if Wanted(e) then
            shown[#shown + 1] = e
        elseif e.obj then
            e.frame:Hide()
        end
    end
    table.sort(shown, function(a, b) return Label(a) < Label(b) end)
    local slots, w, h = Buttons.Grid(#shown, ns.db.buttonsPerRow or 6, SIZE, GAP, PAD)
    for i, e in ipairs(shown) do
        Place(e, slots[i][1], slots[i][2])
        if e.obj then
            PaintIcon(e) -- addons change their icons (state, notifications)
            e.frame:Show()
        end
    end
    panel:SetSize(w, h)
    if trigger then trigger:SetShown(#shown > 0) end
    panel.empty = #shown == 0
end

-- Looks for buttons to collect.
local function Scan()
    if not panel or not Active() then return end
    local before = #entries
    local lib = DBIcon()
    if lib and lib.GetButtonList and lib.GetMinimapButton then
        local ok, names = pcall(lib.GetButtonList, lib)
        for _, name in ipairs(ok and names or {}) do
            local orig = not byKey[name] and lib:GetMinimapButton(name)
            if orig and orig.dataObject then
                Add(name, Proxy(name, orig, orig.dataObject))
                byKey[orig] = byKey[name]
            end
        end
    end
    for _, parent in ipairs({ Minimap, _G.MinimapBackdrop, ns.Shell.root }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                local okN, name = pcall(child.GetName, child)
                if okN and not byKey[child] and Buttons.LooksLikeButton(name)
                    and child.IsObjectType and child:IsObjectType("Button") then
                    Add(child, Move(child))
                end
            end
        end
    end
    if #entries ~= before or panel:IsShown() then Layout() end
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

-- The bottom bar calls this with its trigger button.
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
    if trigger.SetOpen then
        panel:SetScript("OnShow", function() trigger.SetOpen(true) end)
        panel:SetScript("OnHide", function() trigger.SetOpen(false) end)
    end
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
    for _, e in ipairs(entries) do if Wanted(e) then n = n + 1 end end
    return n
end

ns.RegisterCommand("buttons", "list the minimap buttons in the button panel", function()
    if not Active() then
        local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
        ns.Printf("collecting is off%s", loaded and loaded("MinimapButtonButton")
            and " (MinimapButtonButton is loaded and handles them)" or "")
        return
    end
    for _, e in ipairs(entries) do
        local f = e.frame
        ns.Printf("  %s  %s%s%s  %s %d", e.name or "?", e.obj and "own button" or "moved",
            Wanted(e) and "" or " (hidden)", e.obj and not e.obj.OnClick and " (no click)" or "",
            f:GetFrameStrata(), f:GetFrameLevel())
    end
    ns.Printf("%d button(s)", #entries)
end)
