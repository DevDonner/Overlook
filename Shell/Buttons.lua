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
-- Stays out of the way (and gives back anything it took) while MinimapButtonButton is loaded,
-- while another addon hosts the map (Core/Host.lua: EllesmereUI has its own button row), while
-- our buttons are set to "none", or with collecting switched off. Giving back is immediate: the
-- originals are shown again where their addons put them, no /reload needed.
--
-- Settings: collectButtons (on/off), buttonsPerRow, buttonSpot.
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
    "^AddonCompartment", "^TimeManager", "^Overlook" }
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

-- Why collecting is off, or nil when it's on. Pure.
function Buttons.Blocked(db, hosted, mbbLoaded)
    if db.collectButtons == false then return "off" end
    if db.buttonSpot == "none" then return "no buttons" end
    if hosted then return "hosted" end
    if mbbLoaded then return "MinimapButtonButton" end
    return nil
end

local function MBBLoaded()
    local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
    return loaded and loaded("MinimapButtonButton") and true or false
end

local function Hosted() return ns.Host ~= nil and ns.Host.owner ~= nil end

local function Active()
    return Buttons.Blocked(ns.db, Hosted(), MBBLoaded()) == nil
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
    b.entry = { frame = b, name = name, orig = orig, obj = obj,
        kept = { show = rawget(orig, "Show"), setShown = rawget(orig, "SetShown") } }
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
        -- Where it was, to put it back.
        parent = button:GetParent(), strata = button:GetFrameStrata(), level = button:GetFrameLevel(),
        points = {},
        -- Our no-op setters are fields on the button; what was there before (usually nothing: the
        -- methods come from the frame type) goes back.
        fields = {},
    }
    for _, k in ipairs({ "SetPoint", "ClearAllPoints", "SetParent", "SetFrameStrata", "SetFrameLevel" }) do
        o.fields[k] = { rawget(button, k) }
    end
    for i = 1, (button.GetNumPoints and button:GetNumPoints() or 0) do
        o.points[i] = { button:GetPoint(i) }
    end
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

-- Gives one button back: the original shows again where its addon had it; ours goes.
local function Release(e)
    if e.obj then
        local orig = e.orig
        rawset(orig, "Show", e.kept.show)
        rawset(orig, "SetShown", e.kept.setShown)
        if not (orig.db and orig.db.hide) then orig:Show() end
        e.frame:Hide()
    elseif e.moved then
        local b, o = e.frame, e.moved
        for k, v in pairs(o.fields) do rawset(b, k, v[1]) end
        if b.SetFixedFrameStrata then pcall(b.SetFixedFrameStrata, b, false) end
        if b.SetFixedFrameLevel then pcall(b.SetFixedFrameLevel, b, false) end
        b:SetParent(o.parent)
        b:SetFrameStrata(o.strata)
        b:SetFrameLevel(o.level)
        b:ClearAllPoints()
        for _, pt in ipairs(o.points) do b:SetPoint(unpack(pt)) end
    end
end

-- Gives every button back and forgets them, so collecting can start over later.
function Buttons.ReleaseAll()
    for i = #entries, 1, -1 do
        local ok, err = pcall(Release, entries[i])
        if not ok and ns.Print then ns.Print("couldn't give a minimap button back: " .. tostring(err)) end
        entries[i] = nil
    end
    for k in pairs(byKey) do byKey[k] = nil end
    if panel then panel:Hide() end
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

-- Where the panel opens, next to the button that opened it. Pure: spot is where that button sits
-- (Bars.ButtonSpots), side the column's side. Returns point, relativePoint, x, y.
function Buttons.PanelAnchor(spot, side)
    if spot == "side" then
        if side == "right" then return "TOPRIGHT", "TOPLEFT", -2, 0 end
        return "TOPLEFT", "TOPRIGHT", 2, 0
    elseif spot == "pill" then
        return "BOTTOMRIGHT", "TOPRIGHT", 0, 2
    end
    return "BOTTOMLEFT", "TOPLEFT", 0, 2 -- the bottom bar: just above it, from its left end
end

local function PlacePanel()
    local host = trigger:GetParent()
    local point, rel, x, y = Buttons.PanelAnchor(trigger.spot, ns.db and ns.db.buttonSide)
    panel:ClearAllPoints()
    panel:SetPoint(point, host, rel, x, y)
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
    panel = CreateFrame("Frame", "OverlookButtonPanel", UIParent, "BackdropTemplate")
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
    table.insert(UISpecialFrames, "OverlookButtonPanel") -- Escape closes it

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
        if #entries > 0 then Buttons.ReleaseAll() end
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

local WHY = {
    off = "switched off in the settings",
    ["no buttons"] = "our buttons are set to none",
    hosted = "another addon hosts the map and keeps its own buttons",
    MinimapButtonButton = "MinimapButtonButton is loaded and handles them",
}

ns.RegisterCommand("buttons", "list the minimap buttons in the button panel", function()
    local why = Buttons.Blocked(ns.db, Hosted(), MBBLoaded())
    if why then
        ns.Printf("collecting is off: %s", WHY[why] or why)
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
