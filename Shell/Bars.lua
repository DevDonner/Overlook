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
    local want = ns.db.hideGameButtons == true
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
    if ns.Overrides then ns.Overrides.Apply() end
    if ns.Far and ns.Far.PlaceRecenter then ns.Far.PlaceRecenter() end
    UpdateZone()
    UpdateBottom()
end

function Bars.Build(rootFrame, level)
    root = rootFrame
    top = Strip(level)
    zoneText = Text(top, "CENTER")
    zoneText:SetPoint("LEFT", top, "LEFT", PAD, 0)
    zoneText:SetPoint("RIGHT", top, "RIGHT", -PAD, 0)
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
    events:SetScript("OnEvent", UpdateZone)

    Bars.Apply()
end
