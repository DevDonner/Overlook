-- Map art: the game's own world-map drawing of a city or dungeon, laid out in world yards so the
-- far view can draw it where the terrain tiles don't show the place (underground cities, dungeon
-- instances). Pure functions over a C_Map-like table, so they can be tested offline.
local _, ns = ...

local MapArt = {}
ns.MapArt = MapArt

-- Enum.UIMapType values used here.
MapArt.ZONE, MapArt.DUNGEON, MapArt.MICRO = 3, 4, 5

-- Maps that lie under the terrain at their own place on the continent. The terrain there shows
-- the surface, so indoors there the map art replaces it. 1458: Undercity.
MapArt.UNDERGROUND = { [1458] = true }

-- The map's world rectangle: instance, then north and west of its top-left corner and of its
-- bottom-right corner. vec makes a map position (CreateVector2D in game).
function MapArt.WorldRect(api, mapID, vec)
    local inst, tl = api.GetWorldPosFromMapPos(mapID, vec(0, 0))
    local _, br = api.GetWorldPosFromMapPos(mapID, vec(1, 1))
    if not (inst and tl and br) then return nil end
    local top, left = tl:GetXY()
    local bottom, right = br:GetXY()
    return inst, top, left, bottom, right
end

-- The art's tiles in world yards: { file, n0, w0 (top-left), n1, w1 (bottom-right), u1, v1 }.
-- Tiles on the right and bottom edges run past the layer; u1, v1 crop them to it.
function MapArt.Tiles(api, mapID, vec)
    local out = {}
    local layers = api.GetMapArtLayers(mapID)
    local L = layers and layers[1]
    local files = L and api.GetMapArtLayerTextures(mapID, 1)
    if not files then return out end
    local inst, top, left, bottom, right = MapArt.WorldRect(api, mapID, vec)
    if not inst then return out end
    local cols = math.ceil(L.layerWidth / L.tileWidth)
    local nPerPx = (bottom - top) / L.layerHeight
    local wPerPx = (right - left) / L.layerWidth
    for i, file in ipairs(files) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local x0, y0 = col * L.tileWidth, row * L.tileHeight
        local x1 = math.min(x0 + L.tileWidth, L.layerWidth)
        local y1 = math.min(y0 + L.tileHeight, L.layerHeight)
        if x1 > x0 and y1 > y0 then
            out[#out + 1] = {
                file = file,
                n0 = top + y0 * nPerPx, w0 = left + x0 * wPerPx,
                n1 = top + y1 * nPerPx, w1 = left + x1 * wPerPx,
                u1 = (x1 - x0) / L.tileWidth, v1 = (y1 - y0) / L.tileHeight,
            }
        end
    end
    return out
end

-- Which map's art to draw, or nil for the terrain alone.
-- s: { best (the player's map), mapType, hasArt, terrain (the instance has terrain tiles), indoors }
function MapArt.Choose(s)
    if not s.best or not s.hasArt then return nil end
    if not s.terrain then return s.best end -- a dungeon: its map is all there is
    if s.indoors and (MapArt.UNDERGROUND[s.best] or s.mapType == MapArt.DUNGEON or s.mapType == MapArt.MICRO) then
        return s.best
    end
    return nil
end

-- The player's world position (north, west, instance) from their map position, for instances
-- where UnitPosition gives nothing.
function MapArt.PlayerFromMap(api, mapID)
    local pos = api.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local inst, world = api.GetWorldPosFromMapPos(mapID, pos)
    if not (inst and world) then return nil end
    local n, w = world:GetXY()
    return n, w, inst
end

-- The floors of a multi-level map, top first ({ mapID, name }), or nil for a single level.
function MapArt.Floors(api, mapID)
    local group = api.GetMapGroupID and api.GetMapGroupID(mapID)
    local members = group and api.GetMapGroupMembersInfo(group)
    if not members or #members < 2 then return nil end
    local floors = {}
    for i, m in ipairs(members) do floors[i] = m end
    table.sort(floors, function(a, b) return (a.relativeHeightIndex or 0) < (b.relativeHeightIndex or 0) end)
    return floors
end

-- The floor delta steps away from current (+1 down a level), clamped to the ends.
function MapArt.StepFloor(floors, current, delta)
    local at
    for i, f in ipairs(floors) do
        if f.mapID == current then at = i end
    end
    if not at then return floors[1].mapID end
    return floors[math.max(1, math.min(#floors, at + delta))].mapID
end
