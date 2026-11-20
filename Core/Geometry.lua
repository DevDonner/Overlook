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
