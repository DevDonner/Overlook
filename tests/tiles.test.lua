-- The vendored tile table loads and agrees with the geometry.
local H = ...
local ns = H.loadAddonFile("Data/MinimapTiles.lua", {})
local G = H.loadAddonFile("Core/Geometry.lua", ns).Geometry

H.test("tile table has both continents", function()
    H.truthy(type(ns.MapMinimap) == "table", "MapMinimap missing")
    H.truthy(type(ns.MapMinimap[0]) == "table", "Eastern Kingdoms missing")
    H.truthy(type(ns.MapMinimap[1]) == "table", "Kalimdor missing")
end)

H.test("every entry is a valid key with a positive integer file ID", function()
    for cont, tiles in pairs(ns.MapMinimap) do
        for key, fid in pairs(tiles) do
            if type(key) ~= "number" or key < 0 or key > 4095 or key % 1 ~= 0 then
                error(string.format("continent %s: bad key %s", tostring(cont), tostring(key)))
            end
            if type(fid) ~= "number" or fid <= 0 or fid % 1 ~= 0 then
                error(string.format("continent %s key %d: bad file ID %s", cont, key, tostring(fid)))
            end
        end
    end
end)

H.test("Northshire's tile is in the Eastern Kingdoms table", function()
    local col, row = G.WorldToTile(-8949, -132)
    -- 204493 also appears for this tile in a second, independently generated table.
    H.eq(ns.MapMinimap[0][G.TileKey(col, row)], 204493)
end)
