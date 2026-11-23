-- The top bar (zone name) and bottom bar (coordinates, far radius, clock): thin dark strips with
-- the same 1 px black edge as the map, either outside the map (sharing its edge) or over it.
-- Clicking the top bar opens the world map.
local _, ns = ...

local T = ns.BarText

local Bars = {}
ns.Bars = Bars

local FONT = "Fonts\\FRIZQT__.TTF"
local BG = { 0.05, 0.06, 0.08 }
local PAD = 6
local TICK = 0.2 -- seconds between coordinate / clock updates

local root, top, bottom
local zoneText, coordText, zoomText, clockText
local calendarButton, addonsButton, minimapButtons
local ICON = 12        -- px, the top bar's buttons
local GREY, GOLD, INVITE = { 0.75, 0.77, 0.8 }, { 1, 0.82, 0 }, { 1, 0.5, 0.15 }
local headerHidden = false

local function Strip(level)
    local f = CreateFrame("Frame", nil, root, "BackdropTemplate")
    f:SetFrameLevel(level)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropBorderColor(0, 0, 0, 1)
    return f
end

local function Text(parent, justify)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, ns.db.barFont, "")
    t:SetShadowOffset(1, -1)
    t:SetShadowColor(0, 0, 0, 0.9)
    t:SetJustifyH(justify)
    t:SetWordWrap(false)
    return t
end

----------------------------------------------------------------------------------------------------
-- Content

local function UpdateZone()
    if not zoneText then return end
    local sub = GetMinimapZoneText and GetMinimapZoneText() or ""
    local zone = GetZoneText and GetZoneText() or ""
    if ns.IsSecret(sub) or ns.IsSecret(zone) then return end
    zoneText:SetText(T.Zone(sub, zone, ns.db.topBarZone))
    local pvp = GetZonePVPInfo and GetZonePVPInfo()
    if ns.IsSecret(pvp) then pvp = nil end
    local c = T.ZoneColor(pvp, ns.db.topBarPvP)
    zoneText:SetTextColor(c[1], c[2], c[3])
end

local function PlayerCoords()
    local api = _G.C_Map
    if not (api and api.GetBestMapForUnit and api.GetPlayerMapPosition) then return nil end
    local ok, map = pcall(api.GetBestMapForUnit, "player")
    if not ok or not map or ns.IsSecret(map) then return nil end
    local okP, pos = pcall(api.GetPlayerMapPosition, map, "player")
    if not okP or not pos then return nil end
    local x, y = pos:GetXY()
    if ns.IsSecret(x) or ns.IsSecret(y) then return nil end
    return x, y
end

local function UpdateBottom()
    if not bottom or not bottom:IsShown() then return end
    if ns.db.barCoords then
        local x, y = PlayerCoords()
        coordText:SetText(T.Coords(x, y, ns.db.coordDecimals))
    else
        coordText:SetText("")
    end
    zoomText:SetText(ns.db.barZoom and ns.Far and T.Yards(ns.Far.Radius()) or "")
    if ns.db.barClock then
        local h, m
        if ns.db.clockServer and GetGameTime then
            h, m = GetGameTime()
        else
            h, m = tonumber(date("%H")), tonumber(date("%M"))
        end
        clockText:SetText(T.Clock(h, m, ns.db.clock24))
    else
        clockText:SetText("")
    end
end

----------------------------------------------------------------------------------------------------
-- The game's own zone header above the minimap

local function Header()
    local c = _G.MinimapCluster
    return c and (c.ZoneTextButton or _G.MinimapZoneTextButton), c and c.BorderTop
end

-- The game's buttons above the minimap: calendar, tracking (the magnifier) and the addon
-- compartment (the number). Hidden with alpha and no mouse rather than Hide(), which the game's
-- own layout code would undo.
local function GameButtons()
    local c = _G.MinimapCluster or {}
    local out = {}
    for _, f in ipairs({ _G.GameTimeFrame, _G.AddonCompartmentFrame, c.Tracking, c.TrackingFrame,
        _G.MiniMapTracking, _G.MiniMapTrackingButton }) do
        if type(f) == "table" and f.SetAlpha then out[#out + 1] = f end
    end
    return out
end

local buttonsHidden = false
local function SyncButtons()
    -- Only while our top bar is there to replace them (with its own calendar and addon buttons).
    local want = ns.db.hideGameButtons == true and ns.db.topBar == true
    if want == buttonsHidden then return end
    buttonsHidden = want
    for _, f in ipairs(GameButtons()) do
        f:SetAlpha(want and 0 or 1)
        for _, part in ipairs({ f, f.Button }) do
            if type(part) == "table" and part.EnableMouse then part:EnableMouse(not want) end
        end
    end
end

local function SyncHeader()
    local want = ns.db.topBar and ns.db.hideZoneHeader
    if want == headerHidden then return end
    headerHidden = want
    local button, border = Header()
    for _, region in ipairs({ button, border }) do
        if region then
            region:SetAlpha(want and 0 or 1)
            if region.EnableMouse and region == button then region:EnableMouse(not want) end
        end
    end
end

----------------------------------------------------------------------------------------------------
-- The top bar's calendar and addon buttons, standing in for the game's hidden ones. Drawn from
-- flat squares in the bars' style; clicking goes through the game's own buttons.

local function Paint(button, c)
    for _, t in ipairs(button.parts) do t:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function Part(button, w, h, point, x, y)
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetSize(w, h)
    t:SetPoint(point, button, point, x, y)
    button.parts[#button.parts + 1] = t
    return t
end

local function SmallButton(parent, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON + 4, ICON + 4)
    b.parts = {}
    b.color = GREY
    b:SetScript("OnEnter", function(self)
        Paint(self, GOLD)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(type(tip) == "function" and tip() or tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        Paint(self, self.color)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

local function PendingInvites()
    local cal = _G.C_Calendar
    if not (cal and cal.GetNumPendingInvites) then return 0 end
    local ok, n = pcall(cal.GetNumPendingInvites)
    return ok and type(n) == "number" and not ns.IsSecret(n) and n or 0
end

local function OpenCalendar()
    local game = _G.GameTimeFrame
    if game and game.Click then
        game:Click()
    elseif _G.ToggleCalendar then
        _G.ToggleCalendar()
    end
end

local function AddonCount()
    local f = _G.AddonCompartmentFrame
    local text = f and f.Text and f.Text.GetText and f.Text:GetText()
    return tonumber(text)
end

-- Opens the game's addon compartment menu at our button: its (hidden) button is moved there
-- first, so the menu opens next to ours.
local function OpenAddons(button)
    local f = _G.AddonCompartmentFrame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
    if f.OpenMenu and pcall(f.OpenMenu, f) then return end
    local down = f:GetScript("OnMouseDown")
    if down then pcall(down, f, "LeftButton") end
end

local function BuildButtons()
    calendarButton = SmallButton(top, function()
        local n = PendingInvites()
        return n > 0 and string.format("Calendar (%d invite%s)", n, n == 1 and "" or "s") or "Calendar"
    end, OpenCalendar)
    calendarButton:SetPoint("LEFT", top, "LEFT", PAD - 2, 0)
    -- A page: outline, with a filled band across the top.
    local s = ICON
    Part(calendarButton, s, 3, "TOP", 0, -2)
    Part(calendarButton, s, 1, "BOTTOM", 0, 2)
    Part(calendarButton, 1, s, "LEFT", 2, 0)
    Part(calendarButton, 1, s, "RIGHT", -2, 0)
    Part(calendarButton, 2, 2, "CENTER", -2, -1)
    Part(calendarButton, 2, 2, "CENTER", 2, -1)
    Paint(calendarButton, GREY)

    addonsButton = SmallButton(top, function()
        local n = AddonCount()
        return n and string.format("Addons (%d)", n) or "Addons"
    end, function(self) OpenAddons(self) end)
    addonsButton:SetPoint("RIGHT", top, "RIGHT", -(PAD - 2), 0)
    -- Four small squares.
    local q = (ICON - 2) / 2
    Part(addonsButton, q, q, "TOPLEFT", 2, -2)
    Part(addonsButton, q, q, "TOPRIGHT", -2, -2)
    Part(addonsButton, q, q, "BOTTOMLEFT", 2, 2)
    Part(addonsButton, q, q, "BOTTOMRIGHT", -2, 2)
    Paint(addonsButton, GREY)

    -- Other addons' minimap buttons (Shell/Buttons.lua): three dots.
    minimapButtons = SmallButton(top, function()
        local n = ns.Buttons and ns.Buttons.Count() or 0
        return string.format("Minimap buttons (%d)", n)
    end, function() if ns.Buttons then ns.Buttons.Toggle() end end)
    minimapButtons:SetPoint("RIGHT", addonsButton, "LEFT", -2, 0)
    for i = -1, 1 do Part(minimapButtons, 2, 2, "CENTER", i * 4, 0) end
    Paint(minimapButtons, GREY)
    minimapButtons:Hide()
    if ns.Buttons then ns.Buttons.Build(minimapButtons) end
end

local function SyncBarButtons()
    local show = ns.db.barButtons ~= false
    calendarButton:SetShown(show and (_G.GameTimeFrame ~= nil or _G.ToggleCalendar ~= nil))
    addonsButton:SetShown(show and _G.AddonCompartmentFrame ~= nil)
    if ns.Buttons then ns.Buttons.Apply() end
    -- The zone name stays centred: the same room on both sides, for the widest side.
    local inset = show and (ICON + 8) or 0
    if minimapButtons:IsShown() then inset = inset + ICON + 6 end
    zoneText:ClearAllPoints()
    zoneText:SetPoint("LEFT", top, "LEFT", PAD + inset, 0)
    zoneText:SetPoint("RIGHT", top, "RIGHT", -(PAD + inset), 0)
    calendarButton.color = PendingInvites() > 0 and INVITE or GREY
    if not calendarButton:IsMouseOver() then Paint(calendarButton, calendarButton.color) end
end

----------------------------------------------------------------------------------------------------
-- Layout

local function Place(bar, edge, inside, height)
    bar:ClearAllPoints()
    bar:SetHeight(height)
    local opposite = edge == "TOP" and "BOTTOM" or "TOP"
    local y = edge == "TOP" and -1 or 1 -- outside: overlap the map's edge so the two lines merge
    if inside then
        bar:SetPoint(edge .. "LEFT", root, edge .. "LEFT", 0, 0)
        bar:SetPoint(edge .. "RIGHT", root, edge .. "RIGHT", 0, 0)
    else
        bar:SetPoint(opposite .. "LEFT", root, edge .. "LEFT", 0, y)
        bar:SetPoint(opposite .. "RIGHT", root, edge .. "RIGHT", 0, y)
    end
end

-- How much of the map's bottom edge the bottom bar covers (0 when it sits outside or is off).
function Bars.InsideBottomHeight()
    if not (ns.db.bottomBar and ns.db.bottomBarInside) then return 0 end
    return ns.db.barFont + 2 * PAD - 2
end

-- Re-applies every bar setting. The shell calls it after each layout pass.
function Bars.Apply()
    if not root then return end
    local height = ns.db.barFont + 2 * PAD - 2
    for _, t in ipairs({ zoneText, coordText, zoomText, clockText }) do
        t:SetFont(FONT, ns.db.barFont, "")
    end
    for _, bar in ipairs({ top, bottom }) do
        bar:SetBackdropColor(BG[1], BG[2], BG[3], ns.db.barAlpha)
        bar:SetBackdropBorderColor(0, 0, 0, math.max(ns.db.barAlpha, 0.5))
    end
    Place(top, "TOP", ns.db.topBarInside, height)
    Place(bottom, "BOTTOM", ns.db.bottomBarInside, height)
    top:SetShown(ns.db.topBar)
    bottom:SetShown(ns.db.bottomBar)

    -- Keep outside bars on screen too.
    local up = (ns.db.topBar and not ns.db.topBarInside) and height - 1 or 0
    local down = (ns.db.bottomBar and not ns.db.bottomBarInside) and height - 1 or 0
    root:SetClampRectInsets(0, 0, up, -down)

    SyncHeader()
    SyncButtons()
    SyncBarButtons()
    if ns.Overrides then ns.Overrides.Apply() end
    if ns.Far and ns.Far.PlaceRecenter then ns.Far.PlaceRecenter() end
    UpdateZone()
    UpdateBottom()
end

function Bars.Build(rootFrame, level)
    root = rootFrame
    top = Strip(level)
    zoneText = Text(top, "CENTER")
    BuildButtons()
    top:EnableMouse(true)
    top:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and ToggleWorldMap then ToggleWorldMap() end
    end)

    bottom = Strip(level)
    bottom:EnableMouse(false)
    coordText = Text(bottom, "LEFT")
    coordText:SetPoint("LEFT", bottom, "LEFT", PAD, 0)
    clockText = Text(bottom, "RIGHT")
    clockText:SetPoint("RIGHT", bottom, "RIGHT", -PAD, 0)
    zoomText = Text(bottom, "CENTER")
    zoomText:SetPoint("CENTER", bottom, "CENTER", 0, 0)
    zoomText:SetTextColor(0.7, 0.74, 0.8)

    local elapsed = 0
    bottom:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < TICK then return end
        elapsed = 0
        UpdateBottom()
    end)

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        events:RegisterEvent(e)
    end
    pcall(events.RegisterEvent, events, "CALENDAR_UPDATE_PENDING_INVITES")
    events:SetScript("OnEvent", function(_, event)
        if event == "CALENDAR_UPDATE_PENDING_INVITES" then
            SyncBarButtons()
        else
            UpdateZone()
        end
    end)

    Bars.Apply()
end
