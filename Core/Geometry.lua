-- Pure world <-> tile math. No game calls, so it runs in the offline tests.
--
-- World coordinates are in yards as UnitPosition returns them: the first value runs north, the
-- second runs west. Each continent is a 64 x 64 grid of 533.33-yard tiles centred on (0, 0);
-- tile columns run east and rows run south, matching the minimap tile table (Data/MinimapTiles.lua).
local _, ns = ...

local floor = math.floor

local Geometry = {}
ns.Geometry = Geometry

Geometry.TILE_YARDS = 1600 / 3
Geometry.GRID = 64

local TILE = Geometry.TILE_YARDS
local HALF = (Geometry.GRID / 2) * TILE

-- Returns column, row, and the position inside that tile as fractions (0 = west/north edge).
function Geometry.WorldToTile(north, west)
    local colF = (HALF - west) / TILE
    local rowF = (HALF - north) / TILE
    local col, row = floor(colF), floor(rowF)
    return col, row, colF - col, rowF - row
end

-- The world position of a tile's north-west corner.
function Geometry.TileToWorld(col, row)
    return HALF - row * TILE, HALF - col * TILE
end

function Geometry.IsValidTile(col, row)
    return col >= 0 and col < Geometry.GRID and row >= 0 and row < Geometry.GRID
end

-- Key used by the tile table: column * 64 + row.
function Geometry.TileKey(col, row)
    return col * Geometry.GRID + row
end

function Geometry.KeyToTile(key)
    return floor(key / Geometry.GRID), key % Geometry.GRID
end

-- Screen offset in px of a world point from the origin: x runs east, y runs north.
-- Tiles and pins both go through this, so they always agree (U2).
function Geometry.WorldToPixel(north, west, originNorth, originWest, ppy)
    return (originWest - west) * ppy, (north - originNorth) * ppy
end

local function Clamp(v)
    if v < 0 then return 0 end
    if v > Geometry.GRID - 1 then return Geometry.GRID - 1 end
    return v
end

-- Column and row range of the tiles a square view of half-width `radius` yards around
-- (north, west) touches, clamped to the grid: colMin, colMax, rowMin, rowMax.
function Geometry.VisibleTiles(north, west, radius)
    return Clamp(floor((HALF - (west + radius)) / TILE)),
        Clamp(floor((HALF - (west - radius)) / TILE)),
        Clamp(floor((HALF - (north + radius)) / TILE)),
        Clamp(floor((HALF - (north - radius)) / TILE))
end

-- Whether an offset (dx, dy) from a round map's centre is on the map (radius r). Pure.
function Geometry.InCircle(dx, dy, r)
    return dx * dx + dy * dy <= r * r
end
