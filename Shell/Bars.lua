-- The top bar (zone name) and bottom bar (coordinates, far radius, clock): thin dark strips with
-- the same 1 px black edge as the map, either outside the map (sharing its edge) or over it.
-- Clicking the top bar opens the world map.
--
-- On the round map there are no long strips: the same text and buttons sit in small separate boxes
-- in a grid under the circle, two rows of three:
--     zone name    |  (empty)        |  calendar, addons, minimap buttons
--     coordinates  |  zoom distance  |  clock
-- (the zoom distance only while zoomed out, and with its setting on).
--
-- Our buttons (calendar, addons, the minimap-button panel's arrow) can instead go in a slim column
-- inside the map's left or right edge (outside the circle on the round map), so the bars can be
-- turned off and the map keeps all the height it's given. Bars.ButtonSpots says where each goes.
local _, ns = ...

local T = ns.BarText

local Bars = {}
ns.Bars = Bars

local FONT = "Fonts\\FRIZQT__.TTF"
local BG = { 0.05, 0.06, 0.08 }
local PAD = 6
local TICK = 0.2 -- seconds between coordinate / clock updates

local GAP = 3 -- px between the circle and the grid, and between the grid's rows

local root, top, bottom, side
local namePill, buttonPill, coordPill, clockPill, zoomPill -- the round map's boxes
local zoneText, coordText, zoomText, clockText
local calendarButton, addonsButton, minimapButtons
local ICON = 12        -- px, the top bar's buttons
local GREY, GOLD, INVITE = { 0.75, 0.77, 0.8 }, { 1, 0.82, 0 }, { 1, 0.5, 0.15 }
local SIDE_W, SIDE_STEP = ICON + 8, ICON + 6 -- px: the side column's width, one button's room in it
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

local function Round() return ns.Host.IsRound() end

-- Where each of our buttons goes: { calendar = spot, addons = spot, collect = spot }, a spot being
-- "top" / "bottom" (a bar), "pill" (the round map's button box), "side" (the column) or nil (not
-- shown). A bar that's off hands its buttons to the column, so turning bars off never loses them.
-- Pure.
function Bars.ButtonSpots(db, round)
    local out = {}
    if db.buttonSpot == "none" then return out end
    local mine = db.barButtons ~= false
    local collect = db.collectButtons ~= false
    if db.buttonSpot == "side" then
        if mine then out.calendar, out.addons = "side", "side" end
        if collect then out.collect = "side" end
    elseif round then
        if mine then
            local s = db.topBar and "pill" or "side"
            out.calendar, out.addons = s, s
        end
        if collect then out.collect = (db.topBar or db.bottomBar) and "pill" or "side" end
    else
        if mine then
            local s = db.topBar and "top" or "side"
            out.calendar, out.addons = s, s
        end
        if collect then out.collect = db.bottomBar and "bottom" or "side" end
    end
    return out
end

local function TextWidth(t)
    local w = t.GetStringWidth and t:GetStringWidth()
    return type(w) == "number" and w or 0
end

-- A box just wide enough for its text (in steps of 4 px, so it doesn't twitch as digits change).
local function Fit(pill, t, minW)
    local w = math.ceil((TextWidth(t) + 2 * PAD) / 4) * 4
    pill:SetWidth(math.max(minW or 0, w))
end

----------------------------------------------------------------------------------------------------
-- Content

local FitName

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
    if Round() and FitName then FitName() end
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
    if not bottom or not ns.db.bottomBar then return end
    if ns.db.barCoords then
        local x, y = PlayerCoords()
        coordText:SetText(T.Coords(x, y, ns.db.coordDecimals))
    else
        coordText:SetText("")
    end
    local yards = ns.db.barZoom and ns.Far and T.Yards(ns.Far.Radius()) or ""
    zoomText:SetText(yards)
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
    if Round() then
        Fit(coordPill, coordText)
        Fit(clockPill, clockText)
        Fit(zoomPill, zoomText)
        zoomPill:SetShown(yards ~= "")
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

-- Whether the game's calendar / tracking / compartment buttons are hidden: only while ours stand
-- in for them somewhere (on a bar or in the side column). Pure.
function Bars.HideGameButtons(db, spots)
    return db.hideGameButtons == true and (spots.calendar ~= nil or spots.addons ~= nil)
end

local function SyncButtons()
    local want = Bars.HideGameButtons(ns.db, Bars.ButtonSpots(ns.db, Round()))
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
    for i = -1, 1 do Part(calendarButton, 2, 2, "CENTER", i * 3, -1) end
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

    -- Other addons' minimap buttons (Shell/Buttons.lua): a chevron, like a taskbar's hidden-icons
    -- arrow, at the left end of the bottom bar before the coordinates. Up while the panel is shut,
    -- down while it's open.
    minimapButtons = SmallButton(bottom, function()
        local n = ns.Buttons and ns.Buttons.Count() or 0
        return string.format("Minimap buttons (%d)", n)
    end, function() if ns.Buttons then ns.Buttons.Toggle() end end)
    minimapButtons:SetPoint("LEFT", bottom, "LEFT", PAD - 3, 0)
    local left = Part(minimapButtons, 7, 2, "CENTER", -2, 0)
    local right = Part(minimapButtons, 7, 2, "CENTER", 2, 0)
    function minimapButtons.SetOpen(open)
        local tilt = open and -1 or 1
        left:SetRotation(tilt * math.pi / 4)
        right:SetRotation(-tilt * math.pi / 4)
    end
    minimapButtons.SetOpen(false)
    Paint(minimapButtons, GREY)
    minimapButtons:Hide()
    if ns.Buttons then ns.Buttons.Build(minimapButtons) end
end

-- The side column: a slim strip inside the map's left or right edge (below the top bar when that
-- sits over the map), or just outside the circle on the round map. The buttons stack down it.
local function PlaceSide(n)
    side:ClearAllPoints()
    side:SetSize(SIDE_W, 4 + n * SIDE_STEP)
    local left = ns.db.buttonSide ~= "right"
    if Round() then
        if left then
            side:SetPoint("TOPRIGHT", root, "TOPLEFT", -GAP, 0)
        else
            side:SetPoint("TOPLEFT", root, "TOPRIGHT", GAP, 0)
        end
        return
    end
    local down = 0
    if ns.db.topBar and ns.db.topBarInside then down = ns.db.barFont + 2 * PAD - 2 - 1 end
    local edge = left and "LEFT" or "RIGHT"
    side:SetPoint("TOP" .. edge, root, "TOP" .. edge, 0, -down)
end

-- Every button to its spot (Bars.ButtonSpots); a button with no spot, or that can't work here
-- (no calendar in this client), is hidden. Returns how many sit in the side column and in the
-- round map's box.
local function ArrangeButtons(spots)
    local hosts = { top = top, bottom = bottom, side = side, pill = buttonPill }
    calendarButton:SetShown(spots.calendar ~= nil and (_G.GameTimeFrame ~= nil or _G.ToggleCalendar ~= nil))
    addonsButton:SetShown(spots.addons ~= nil and _G.AddonCompartmentFrame ~= nil)
    minimapButtons.spot = spots.collect
    -- The panel's arrow shows only while it has buttons to show (Buttons.Layout decides).
    if ns.Buttons then ns.Buttons.Apply() end
    if not spots.collect then minimapButtons:Hide() end

    local nSide, xPill = 0, 3
    for _, e in ipairs({ { calendarButton, spots.calendar }, { addonsButton, spots.addons },
        { minimapButtons, spots.collect } }) do
        local b, spot = e[1], e[2]
        if spot then b:SetParent(hosts[spot]) end
        b:ClearAllPoints()
        if b:IsShown() and spot == "side" then
            b:SetPoint("TOP", side, "TOP", 0, -(4 + nSide * SIDE_STEP) + 1)
            nSide = nSide + 1
        elseif b:IsShown() and spot == "pill" then
            b:SetPoint("LEFT", buttonPill, "LEFT", xPill, 0)
            xPill = xPill + ICON + 5
        end
    end
    if spots.calendar == "top" then calendarButton:SetPoint("LEFT", top, "LEFT", PAD - 2, 0) end
    if spots.addons == "top" then addonsButton:SetPoint("RIGHT", top, "RIGHT", -(PAD - 2), 0) end
    if spots.collect == "bottom" then minimapButtons:SetPoint("LEFT", bottom, "LEFT", PAD - 3, 0) end
    buttonPill:SetWidth(xPill + 2)
    return nSide, (xPill - 3) / (ICON + 5)
end

-- Square map: the text in the strips, clear of the buttons on them.
local function ArrangeSquareText(spots)
    zoneText:SetParent(top)
    coordText:SetParent(bottom)
    clockText:SetParent(bottom)
    zoomText:SetParent(bottom)
    zoomText:ClearAllPoints()
    zoomText:SetPoint("CENTER", bottom, "CENTER", 0, 0)
    clockText:ClearAllPoints()
    clockText:SetPoint("RIGHT", bottom, "RIGHT", -PAD, 0)
    coordText:ClearAllPoints()
    if spots.collect == "bottom" and minimapButtons:IsShown() then
        coordText:SetPoint("LEFT", minimapButtons, "RIGHT", 3, 0)
    else
        coordText:SetPoint("LEFT", bottom, "LEFT", PAD, 0)
    end
    -- The zone name stays centred: the same room on both sides, for the widest side; and clear of
    -- the side column when the bar sits over the map's top edge above it.
    local inset = (spots.calendar == "top" or spots.addons == "top") and (ICON + 8) or 0
    zoneText:ClearAllPoints()
    zoneText:SetPoint("LEFT", top, "LEFT", PAD + inset, 0)
    zoneText:SetPoint("RIGHT", top, "RIGHT", -(PAD + inset), 0)
end

-- Round map: the text in its own boxes.
local function ArrangeRoundText()
    zoneText:SetParent(namePill)
    zoneText:ClearAllPoints()
    zoneText:SetPoint("LEFT", namePill, "LEFT", PAD, 0)
    zoneText:SetPoint("RIGHT", namePill, "RIGHT", -PAD, 0)
    coordText:SetParent(coordPill)
    coordText:ClearAllPoints()
    coordText:SetPoint("CENTER", coordPill, "CENTER", 0, 0)
    clockText:SetParent(clockPill)
    clockText:ClearAllPoints()
    clockText:SetPoint("CENTER", clockPill, "CENTER", 0, 0)
    zoomText:SetParent(zoomPill)
    zoomText:ClearAllPoints()
    zoomText:SetPoint("CENTER", zoomPill, "CENTER", 0, 0)
end

local function SyncBarButtons()
    local spots = Bars.ButtonSpots(ns.db, Round())
    local nSide, nPill = ArrangeButtons(spots)
    side:SetShown(nSide > 0)
    if nSide > 0 then PlaceSide(nSide) end
    if Round() then
        buttonPill:SetShown(nPill > 0)
        ArrangeRoundText()
    else
        buttonPill:SetShown(false)
        ArrangeSquareText(spots)
    end
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

-- The round map's grid under the circle (see the top of the file). Returns its height.
local function PlaceRound(height)
    local size = ns.Host.Size()
    local row1 = ns.db.topBar or buttonPill:IsShown()
    namePill:SetShown(ns.db.topBar == true)
    coordPill:SetShown(ns.db.bottomBar and ns.db.barCoords and true or false)
    clockPill:SetShown(ns.db.bottomBar and ns.db.barClock and true or false)
    if not ns.db.bottomBar then zoomPill:SetShown(false) end
    -- The zoom box comes and goes as you zoom: the grid keeps its second row while it can show.
    local row2 = coordPill:IsShown() or clockPill:IsShown() or (ns.db.bottomBar and ns.db.barZoom and true or false)
    for _, pill in ipairs({ namePill, buttonPill, coordPill, clockPill, zoomPill }) do pill:SetHeight(height) end

    local y1 = -GAP
    local y2 = row1 and -(GAP + height + GAP) or -GAP
    namePill:ClearAllPoints()
    namePill:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, y1)
    buttonPill:ClearAllPoints()
    buttonPill:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, y1)
    coordPill:ClearAllPoints()
    coordPill:SetPoint("TOPLEFT", root, "BOTTOMLEFT", 0, y2)
    clockPill:ClearAllPoints()
    clockPill:SetPoint("TOPRIGHT", root, "BOTTOMRIGHT", 0, y2)
    zoomPill:ClearAllPoints()
    zoomPill:SetPoint("TOP", root, "BOTTOM", 0, y2)

    -- The name gets the row less the buttons' box and a gap; longer names are cut short.
    local room = size - (buttonPill:IsShown() and ((buttonPill.GetWidth and buttonPill:GetWidth() or 0) + GAP * 2) or 0)
    FitName = function()
        local w = math.ceil((TextWidth(zoneText) + 2 * PAD) / 4) * 4
        namePill:SetWidth(math.max(40, math.min(w, room)))
    end
    FitName()

    if row2 then return -y2 + height end
    if row1 then return GAP + height end
    return 0
end

-- How much of the map's bottom edge the bottom bar covers (0 when it sits outside or is off).
function Bars.InsideBottomHeight()
    if Round() then return 0 end
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
    for _, bar in ipairs({ top, bottom, side, namePill, buttonPill, coordPill, clockPill, zoomPill }) do
        bar:SetBackdropColor(BG[1], BG[2], BG[3], ns.db.barAlpha)
        bar:SetBackdropBorderColor(0, 0, 0, math.max(ns.db.barAlpha, 0.5))
    end
    SyncHeader()
    SyncButtons()

    if Round() then
        top:SetShown(false)
        bottom:SetShown(false)
        SyncBarButtons()
        local down = PlaceRound(height)
        -- The side column sits outside the circle: kept on screen too.
        local out = side:IsShown() and -(SIDE_W + GAP) or 0
        local left = ns.db.buttonSide ~= "right"
        root:SetClampRectInsets(left and out or 0, left and 0 or -out, 0, -down)
    else
        for _, pill in ipairs({ namePill, buttonPill, coordPill, clockPill, zoomPill }) do pill:SetShown(false) end
        Place(top, "TOP", ns.db.topBarInside, height)
        Place(bottom, "BOTTOM", ns.db.bottomBarInside, height)
        top:SetShown(ns.db.topBar)
        bottom:SetShown(ns.db.bottomBar)
        -- Keep outside bars on screen too.
        local up = (ns.db.topBar and not ns.db.topBarInside) and height - 1 or 0
        local down = (ns.db.bottomBar and not ns.db.bottomBarInside) and height - 1 or 0
        root:SetClampRectInsets(0, 0, up, -down)
        SyncBarButtons()
    end
    if ns.Overrides then ns.Overrides.Apply() end
    if ns.Far and ns.Far.PlaceRecenter then ns.Far.PlaceRecenter() end
    UpdateZone()
    UpdateBottom()
end

function Bars.Build(rootFrame, level)
    root = rootFrame
    top = Strip(level)
    zoneText = Text(top, "CENTER")
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

    namePill = Strip(level)
    namePill:EnableMouse(true)
    namePill:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and ToggleWorldMap then ToggleWorldMap() end
    end)
    buttonPill = Strip(level)
    coordPill = Strip(level)
    coordPill:EnableMouse(false)
    clockPill = Strip(level)
    clockPill:EnableMouse(false)
    zoomPill = Strip(level)
    zoomPill:EnableMouse(false)
    for _, pill in ipairs({ namePill, buttonPill, coordPill, clockPill, zoomPill }) do pill:Hide() end
    side = Strip(level)
    side:EnableMouse(false) -- only its buttons take clicks; the map shows through around them
    side:Hide()
    BuildButtons()

    local elapsed = 0
    local ticker = CreateFrame("Frame", nil, root) -- runs for the strips and the round boxes alike
    ticker:SetScript("OnUpdate", function(_, dt)
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
