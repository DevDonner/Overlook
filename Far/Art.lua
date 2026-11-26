-- Map art on the far view: the game's own map of an underground city or a dungeon, drawn over
-- the terrain where the terrain only shows the surface (or nothing). It sits on the far canvas
-- like the tiles, so panning and zooming work the same over it. Multi-level maps change floor
-- with Alt+wheel (Far/Far.lua). The choice of map is in Core/MapArt.lua.
local _, ns = ...

local A, G = ns.MapArt, ns.Geometry

local FarArt = {}
ns.FarArt = FarArt

local CHECK_EVERY = 0.5 -- seconds between looks at which map the player is on

local canvas, label
local textures, shown = {}, 0
local tiles = {}  -- MapArt.Tiles for the drawn map
local artInst     -- the drawn map's instance
local chosen      -- the map MapArt.Choose picked for the player
local floorMap    -- a floor picked with Shift+wheel, or nil for the player's own
local drawn       -- the map whose art is drawn (chosen, or the picked floor)
local layout      -- { inst, n, w, ppy } while far mode is drawing
local nextCheck = 0

local function Vec(x, y) return CreateVector2D(x, y) end

local function Api()
    local api = _G.C_Map
    if api and api.GetBestMapForUnit and api.GetWorldPosFromMapPos then return api end
end

local function BestMap()
    local api = Api()
    local best = api and api.GetBestMapForUnit("player")
    if best and not ns.IsSecret(best) then return best end
end

-- The map to draw now, given whether the player's instance has terrain tiles and whether a
-- cave's own images are drawn.
local function ChooseNow(terrain, cave)
    local api, best = Api(), BestMap()
    if not best then return nil end
    local info = api.GetMapInfo(best)
    local layers = api.GetMapArtLayers(best)
    return A.Choose({
        best = best,
        mapType = info and info.mapType,
        hasArt = layers ~= nil and #layers > 0,
        terrain = terrain,
        indoors = IsIndoors and IsIndoors() and true or false,
        cave = cave or false,
    })
end

local function Hide()
    for i = 1, shown do textures[i]:Hide() end
    shown = 0
    if label then label:Hide() end
end

local function Draw()
    Hide()
    if not (layout and drawn and artInst == layout.inst) then return end
    for i, t in ipairs(tiles) do
        local tex = textures[i]
        if not tex then
            tex = canvas:CreateTexture(nil, "ARTWORK", nil, 1) -- above the terrain tiles
            tex.overlookPart = "map art"
            if ns.Far and ns.Far.Shape then ns.Far.Shape(tex) end
            textures[i] = tex
        end
        tex:SetTexture(t.file)
        tex:SetTexCoord(0, t.u1, 0, t.v1)
        local x, y = G.WorldToPixel(t.n0, t.w0, layout.n, layout.w, layout.ppy)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", canvas, "CENTER", x, y)
        tex:SetSize((t.w0 - t.w1) * layout.ppy, (t.n0 - t.n1) * layout.ppy)
        tex:Show()
        shown = i
    end
    local floors = chosen and A.Floors(Api(), chosen)
    if label and floors then
        local info = Api().GetMapInfo(drawn)
        label:SetText((info and info.name or "?") .. "  (Alt+wheel: floor)")
        label:Show()
    end
end

-- Loads the art of the map to draw (the picked floor, else the chosen map) and draws it.
local function Rebuild()
    local map = floorMap or chosen
    if map ~= drawn then
        drawn = map
        tiles = map and A.Tiles(Api(), map, Vec) or {}
        artInst = map and A.WorldRect(Api(), map, Vec) or nil
    end
    Draw()
end

-- True when there's a map to draw for an instance with no terrain tiles (a dungeon), so far
-- mode can start there.
function FarArt.HasMapFor(inst)
    if not Api() then return false end
    local map = ChooseNow(false)
    return map ~= nil and A.WorldRect(Api(), map, Vec) == inst
end

-- The player's world position from their map, where UnitPosition gives none (instances).
function FarArt.PlayerFromMap()
    return FarArt.UnitFromMap("player")
end

-- The same for a group member, on the player's map (nil when they're on another floor or map).
function FarArt.UnitFromMap(unit)
    local best = BestMap()
    if best then return A.PlayerFromMap(Api(), best, unit) end
end

-- Far mode calls this every frame; it looks at the player's map every CHECK_EVERY seconds.
-- cave: a cave is drawn here (Far/Caves.lua), so underground maps stand aside.
function FarArt.Update(now, terrain, cave)
    if now < nextCheck or not Api() then return end
    nextCheck = now + CHECK_EVERY
    local map = ChooseNow(terrain, cave)
    if map ~= chosen then
        chosen, floorMap = map, nil
        Rebuild()
    end
end

-- True when the drawn map has floors for Alt+wheel.
function FarArt.HasFloors()
    return layout ~= nil and chosen ~= nil and A.Floors(Api(), chosen) ~= nil
end

-- Alt+wheel: up (delta > 0) or down a floor, wrapping past either end. Returns true when there
-- were floors to change.
function FarArt.StepFloor(delta)
    local floors = chosen and A.Floors(Api(), chosen)
    if not floors then return false end
    local map = A.StepFloor(floors, floorMap or chosen, -delta)
    floorMap = map ~= chosen and map or nil
    Rebuild()
    return true
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function FarArt.SetLayout(inst, n, w, ppy)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
        Draw()
    else
        layout, chosen, floorMap, drawn, artInst, nextCheck = nil, nil, nil, nil, nil, 0
        tiles = {}
        Hide()
    end
end

function FarArt.DrawnMap() return layout and drawn or nil end
function FarArt.ShownTiles() return shown end

function FarArt.Build(canvasFrame, view, level)
    canvas = canvasFrame
    local top = CreateFrame("Frame", nil, view)
    top:SetAllPoints(view)
    top:SetFrameLevel(level)
    label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", view, "TOP", 0, -4)
    label:Hide()
end

-- /overlook underground: what the game says here, to check the far map can show this place.
if ns.RegisterCommand then
    ns.RegisterCommand("underground", "show the map the far view would draw here", function()
        local api = Api()
        if not api then
            ns.Print("This client has no C_Map, so no map art.")
            return
        end
        local best = BestMap()
        local info = best and api.GetMapInfo(best)
        local n, _, _, inst = UnitPosition("player")
        ns.Printf("indoors %s  map %s (%s, type %s)  UnitPosition %s",
            tostring(IsIndoors and IsIndoors()), ns.Show(best), info and info.name or "-",
            ns.Show(info and info.mapType), n and "yes" or "no (instance)")
        local layers = best and api.GetMapArtLayers(best)
        local terrain = inst and ns.MapMinimap and ns.MapMinimap[inst] ~= nil
        ns.Printf("map art %s  terrain tiles here %s  would draw %s  floors %d",
            layers and #layers > 0 and "yes" or "no", tostring(terrain), ns.Show(ChooseNow(terrain and true or false)),
            best and #(A.Floors(api, best) or {}) or 0)
        local units, onMap = 0, 0
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists and UnitExists(u) then
                units = units + 1
                if UnitPosition(u) or FarArt.UnitFromMap(u) then onMap = onMap + 1 end
            end
        end
        if units > 0 then ns.Printf("party members placed on the far map: %d of %d", onMap, units) end
    end)
end
