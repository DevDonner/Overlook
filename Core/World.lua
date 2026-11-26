-- One world out of the continents: where each continent sits next to the others, so the far map
-- can pan across the sea from one to the next and show both at once.
--
-- Each continent has its own world coordinates (its own 64 x 64 tile grid, centred on 0). To draw
-- another continent beside the player's, its coordinates are shifted: Shift(home, other) gives
-- the yards to add to a point on `other` to place it in `home`'s coordinates. The continents sit
-- side by side, west to east in ORDER (as on the game's world map), with SEA tiles of open water
-- between their coasts and their middles level. The layout comes from the tile data, so it's
-- worked out once per set of tiles, not per frame.
--
-- Pure: the offline tests pass their own tile tables; the game passes ns.MapMinimap.
local _, ns = ...

local G = ns.Geometry

local World = {}
ns.World = World

local TILE = G.TILE_YARDS
World.ORDER = { 1, 0 } -- west to east: Kalimdor, then the Eastern Kingdoms
World.SEA = 6          -- tiles of open water between two continents' coasts (3,200 yd)
World.MIN_TILES = 4    -- a column or row with fewer tiles is an outlying islet, not the coast

-- A continent's main land: the first and last column and row with at least MIN_TILES tiles.
-- set: [col * 64 + row] = file id. Returns colMin, colMax, rowMin, rowMax, or nil for no land.
function World.Extents(set)
    local cols, rows = {}, {}
    for key in pairs(set) do
        local col, row = G.KeyToTile(key)
        cols[col] = (cols[col] or 0) + 1
        rows[row] = (rows[row] or 0) + 1
    end
    local function Range(counts)
        local lo, hi
        for i, n in pairs(counts) do
            if n >= World.MIN_TILES then
                if not lo or i < lo then lo = i end
                if not hi or i > hi then hi = i end
            end
        end
        return lo, hi
    end
    local c0, c1 = Range(cols)
    local r0, r1 = Range(rows)
    if not (c0 and r0) then return nil end
    return c0, c1, r0, r1
end

-- Each continent's place: [inst] = { cols, rows } it moves by (east, south), the first in ORDER
-- staying where it is. sets: [inst] = tile set.
function World.Places(sets)
    local places, prev = {}, nil
    for _, inst in ipairs(World.ORDER) do
        local set = sets and sets[inst]
        local c0, c1, r0, r1
        if set then c0, c1, r0, r1 = World.Extents(set) end
        if c0 then
            local place = { cols = 0, rows = 0, c0 = c0, c1 = c1, r0 = r0, r1 = r1 }
            if prev then
                -- West coast SEA tiles east of the previous one's east coast; middles level.
                place.cols = (prev.c1 + prev.cols) + World.SEA + 1 - c0
                local mid, prevMid = (r0 + r1) / 2, (prev.r0 + prev.r1) / 2 + prev.rows
                place.rows = math.floor(prevMid - mid + 0.5)
            end
            places[inst] = place
            prev = place
        end
    end
    return places
end

local cache, cachedFor
local function PlacesNow(sets)
    sets = sets or ns.MapMinimap
    if cachedFor ~= sets then cache, cachedFor = World.Places(sets), sets end
    return cache
end

-- Yards to add to a point on continent `other` to place it in continent `home`'s coordinates:
-- dn (north), dw (west). 0, 0 for the same continent; nil when either isn't in the world.
function World.Shift(home, other, sets)
    if home == other then return 0, 0 end
    local places = PlacesNow(sets)
    local a, b = places[home], places[other]
    if not (a and b) then return nil end
    -- Moving east (more columns) is less west; moving south (more rows) is less north.
    return -(b.rows - a.rows) * TILE, -(b.cols - a.cols) * TILE
end

-- The other continents beside `home`, as a list of { inst, dn, dw }; empty when home isn't one.
function World.Neighbours(home, sets)
    local out = {}
    local places = PlacesNow(sets)
    if not places[home] then return out end
    for _, inst in ipairs(World.ORDER) do
        if inst ~= home and places[inst] then
            local dn, dw = World.Shift(home, inst, sets)
            out[#out + 1] = { inst = inst, dn = dn, dw = dw }
        end
    end
    return out
end

-- The world's land in `home`'s coordinates: nMin, nMax, wMin, wMax (yards), or nil.
function World.Bounds(home, sets)
    local places = PlacesNow(sets)
    if not places[home] then return nil end
    local nMin, nMax, wMin, wMax
    for inst, p in pairs(places) do
        local dn, dw = World.Shift(home, inst, sets)
        -- A tile's north-west corner is TileToWorld; its land runs one tile south and east.
        local n0, w0 = G.TileToWorld(p.c0, p.r0)
        local n1, w1 = G.TileToWorld(p.c1 + 1, p.r1 + 1)
        n0, n1, w0, w1 = n0 + dn, n1 + dn, w0 + dw, w1 + dw
        nMin, nMax = math.min(nMin or n1, n1), math.max(nMax or n0, n0)
        wMin, wMax = math.min(wMin or w1, w1), math.max(wMax or w0, w0)
    end
    return nMin, nMax, wMin, wMax
end

-- The zoom (yards from the centre to the edge) that shows the whole world from anywhere on it:
-- the world's width or height, whichever is more, so the far coast shows from either one.
function World.Reach(sets)
    local places = PlacesNow(sets)
    local home = next(places)
    if home == nil then return nil end
    local nMin, nMax, wMin, wMax = World.Bounds(home, sets)
    return math.ceil(math.max(nMax - nMin, wMax - wMin) * 1.02)
end
