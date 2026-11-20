-- U1: world -> tile index, edges and negative coordinates.
local H = ...
local G = H.loadAddonFile("Core/Geometry.lua", {}).Geometry

local TILE = 1600 / 3
local HALF = 32 * TILE

H.test("world origin is the corner of tile 32,32", function()
    local col, row, fx, fy = G.WorldToTile(0, 0)
    H.eq(col, 32, "col")
    H.eq(row, 32, "row")
    H.near(fx, 0, 1e-9, "fx")
    H.near(fy, 0, 1e-9, "fy")
end)

H.test("Northshire Abbey is tile column 32, row 48", function()
    local col, row = G.WorldToTile(-8949, -132)
    H.eq(col, 32, "col")
    H.eq(row, 48, "row")
end)

H.test("north edge of the grid is row 0, south edge row 63", function()
    local _, row = G.WorldToTile(HALF - 1, 0)
    H.eq(row, 0, "north edge")
    _, row = G.WorldToTile(-HALF + 1, 0)
    H.eq(row, 63, "south edge")
end)

H.test("west edge of the grid is column 0, east edge column 63", function()
    local col = G.WorldToTile(0, HALF - 1)
    H.eq(col, 0, "west edge")
    col = G.WorldToTile(0, -HALF + 1)
    H.eq(col, 63, "east edge")
end)

H.test("going east raises the column, going south raises the row", function()
    local c1, r1 = G.WorldToTile(1000, 1000)
    local c2 = G.WorldToTile(1000, 1000 - TILE)    -- one tile east (west decreases)
    local _, r2 = G.WorldToTile(1000 - TILE, 1000) -- one tile south (north decreases)
    H.eq(c2, c1 + 1, "east")
    H.eq(r2, r1 + 1, "south")
end)

H.test("fractions measure from the tile's north-west corner", function()
    local north, west = G.TileToWorld(10, 20)
    local col, row, fx, fy = G.WorldToTile(north - TILE * 0.25, west - TILE * 0.75)
    H.eq(col, 10, "col")
    H.eq(row, 20, "row")
    H.near(fx, 0.75, 1e-9, "fx")
    H.near(fy, 0.25, 1e-9, "fy")
end)

H.test("TileToWorld round-trips for every tile", function()
    for col = 0, 63 do
        for row = 0, 63 do
            local north, west = G.TileToWorld(col, row)
            local c, r = G.WorldToTile(north - TILE / 2, west - TILE / 2)
            if c ~= col or r ~= row then
                error(string.format("tile %d,%d came back as %d,%d", col, row, c, r))
            end
        end
    end
end)

H.test("tile key is column * 64 + row", function()
    H.eq(G.TileKey(32, 48), 2096)
    H.eq(G.TileKey(0, 0), 0)
    H.eq(G.TileKey(63, 63), 4095)
end)

H.test("IsValidTile bounds", function()
    H.truthy(G.IsValidTile(0, 0))
    H.truthy(G.IsValidTile(63, 63))
    H.truthy(not G.IsValidTile(-1, 0))
    H.truthy(not G.IsValidTile(0, 64))
end)
