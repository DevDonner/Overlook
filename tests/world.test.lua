-- The world out of the continents (Core/World.lua): where Kalimdor sits beside the Eastern
-- Kingdoms, checked against the real tile data, and the zoom that shows it all.
local H = ...

local ns = {}
H.loadAddonFile("Core/Geometry.lua", ns)
H.loadAddonFile("Data/MinimapTiles.lua", ns)
H.loadAddonFile("Core/World.lua", ns)
local W, G, TILES = ns.World, ns.Geometry, ns.MapMinimap
local TILE = G.TILE_YARDS

-- A block of land: every tile from col c0..c1, row r0..r1.
local function Block(c0, c1, r0, r1)
    local set = {}
    for c = c0, c1 do
        for r = r0, r1 do set[G.TileKey(c, r)] = c * 100 + r end
    end
    return set
end

H.test("extents: a continent's main land, without outlying islets", function()
    local set = Block(10, 20, 5, 30)
    set[G.TileKey(0, 0)] = 1 -- a lone islet far off
    local c0, c1, r0, r1 = W.Extents(set)
    H.eq(c0, 10); H.eq(c1, 20); H.eq(r0, 5); H.eq(r1, 30)
    H.eq(W.Extents({}), nil, "no land")
end)

H.test("extents: Kalimdor's islet in the far north-west isn't its coast (real tiles)", function()
    local c0 = W.Extents(TILES[1])
    H.truthy(c0 > 10, "west coast at column " .. tostring(c0))
end)

H.test("places: the second continent sits SEA tiles east of the first, middles level", function()
    local sets = { [1] = Block(10, 20, 10, 30), [0] = Block(30, 40, 20, 30) }
    local p = W.Places(sets)
    H.eq(p[1].cols, 0); H.eq(p[1].rows, 0)
    H.eq((30 + p[0].cols) - 20 - 1, W.SEA, "open water between the coasts")
    H.eq((20 + 30) / 2 + p[0].rows, (10 + 30) / 2, "middles level")
end)

H.test("shift: yards from one continent's coordinates into the other's, and back", function()
    local sets = { [1] = Block(10, 20, 10, 30), [0] = Block(30, 40, 20, 30) }
    local dn, dw = W.Shift(0, 1, sets)
    local bn, bw = W.Shift(1, 0, sets)
    H.eq(dn, -bn); H.eq(dw, -bw)
    -- Kalimdor's east coast, shifted into the Eastern Kingdoms' coordinates, is SEA tiles west
    -- of the Eastern Kingdoms' west coast (west grows westward).
    local _, kEast = G.TileToWorld(21, 0)   -- the east edge of column 20
    local _, eWest = G.TileToWorld(30, 0)   -- the west edge of column 30
    H.near(kEast + dw - eWest, W.SEA * TILE, 1e-6)
    H.eq(W.Shift(0, 0, sets), 0, "same continent")
    H.eq(W.Shift(0, 530, sets), nil, "a continent outside the world")
end)

H.test("real tiles: Kalimdor west of the Eastern Kingdoms, with sea between, not overlapping", function()
    local k0, k1 = W.Extents(TILES[1])
    local e0, e1 = W.Extents(TILES[0])
    local _, dw = W.Shift(0, 1)
    local _, kEast = G.TileToWorld(k1 + 1, 0)
    local _, eWest = G.TileToWorld(e0, 0)
    H.truthy(kEast + dw > eWest, "Kalimdor's east coast is west of the Eastern Kingdoms' west coast")
    H.near(kEast + dw - eWest, W.SEA * TILE, 1e-6)
    H.truthy(e1 > k0) -- (both real)
end)

H.test("neighbours: each continent has the other; a dungeon has none", function()
    local n = W.Neighbours(0)
    H.eq(#n, 1); H.eq(n[1].inst, 1)
    local dn, dw = W.Shift(0, 1)
    H.eq(n[1].dn, dn); H.eq(n[1].dw, dw)
    H.eq(#W.Neighbours(1), 1)
    H.eq(#W.Neighbours(33), 0)
end)

H.test("bounds and reach: the whole world, from either continent", function()
    local nMin, nMax, wMin, wMax = W.Bounds(0)
    -- Both coasts inside: the Eastern Kingdoms' own and Kalimdor's shifted west coast.
    local e0 = W.Extents(TILES[0])
    local k0 = W.Extents(TILES[1])
    local _, dw = W.Shift(0, 1)
    local _, kWest = G.TileToWorld(k0, 0)
    local _, eWest = G.TileToWorld(e0, 0)
    H.near(wMax, kWest + dw, 1e-6, "Kalimdor's west coast is the world's")
    H.truthy(eWest < wMax and eWest > wMin)
    H.truthy(nMax > nMin)
    H.eq(W.Bounds(33), nil)
    local reach = W.Reach()
    H.truthy(reach >= wMax - wMin, "the whole width fits, seen from either coast")
    H.truthy(reach >= nMax - nMin, "and the whole height")
    H.truthy(reach > 6400, "further than the normal limit")
end)
