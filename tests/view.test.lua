-- U2 (world -> pixel, tiles and pins agree) and U3 (zoom ladder).
local H = ...
local ns = H.loadAddonFile("Core/Geometry.lua", {})
H.loadAddonFile("Core/Zoom.lua", ns)
local G, Zoom = ns.Geometry, ns.Zoom

local TILE = 1600 / 3

H.test("U2 origin maps to 0,0; east is +x, north is +y", function()
    local x, y = G.WorldToPixel(100, 200, 100, 200, 0.5)
    H.near(x, 0, 1e-9); H.near(y, 0, 1e-9)
    x, y = G.WorldToPixel(110, 180, 100, 200, 0.5) -- 10 yd north, 20 yd east
    H.near(x, 10, 1e-9, "x"); H.near(y, 5, 1e-9, "y")
end)

H.test("U2 a pin at a tile's corner lands on the tile's corner at every zoom", function()
    local oN, oW = -8949, -132
    for _, ppy in ipairs({ 0.05, 0.1, 0.43, 1 }) do
        local n, w = G.TileToWorld(31, 47)
        local tx, ty = G.WorldToPixel(n, w, oN, oW, ppy)
        local px, py = G.WorldToPixel(n, w, oN, oW, ppy)
        H.near(tx, px, 1e-9); H.near(ty, py, 1e-9)
        -- the next tile east starts exactly one tile-width to the right
        local n2, w2 = G.TileToWorld(32, 47)
        local tx2 = G.WorldToPixel(n2, w2, oN, oW, ppy)
        H.near(tx2 - tx, TILE * ppy, 1e-6, "tile width at ppy " .. ppy)
    end
end)

H.test("U2 large offsets stay exact (I12 offline)", function()
    local x = G.WorldToPixel(0, -15000, 0, 15000, 0.5)
    H.near(x, 15000, 1e-6)
end)

H.test("visible tile range covers the view and contains the player tile", function()
    local n, w = -8949, -132
    local c0, c1, r0, r1 = G.VisibleTiles(n, w, 2000)
    local pc, pr = G.WorldToTile(n, w)
    H.truthy(c0 <= pc and pc <= c1 and r0 <= pr and pr <= r1, "player tile inside")
    H.truthy(c1 - c0 + 1 >= 8 and c1 - c0 + 1 <= 9, "about 8-9 columns at 2,000 yd, got " .. (c1 - c0 + 1))
    -- the west edge of the view lies inside column c0
    local cw = G.WorldToTile(n, w + 2000)
    H.eq(cw, c0)
end)

H.test("visible tile range is clamped to the grid", function()
    local c0, c1, r0, r1 = G.VisibleTiles(17000, 17000, 3200)
    H.eq(c0, 0); H.eq(r0, 0)
    H.truthy(c1 >= 0 and r1 >= 0)
end)

H.test("tile key round trip", function()
    local col, row = G.KeyToTile(G.TileKey(32, 48))
    H.eq(col, 32); H.eq(row, 48)
end)

local NATIVE = 700 / 3

H.test("U3 zooming out past native goes up by STEP and clamps at the max", function()
    local r, leave = Zoom.FarStep(NATIVE, -1, false, NATIVE, 2000)
    H.near(r, NATIVE * 1.25, 1e-9); H.eq(leave, false)
    r = Zoom.FarStep(1900, -1, false, NATIVE, 2000)
    H.eq(r, 2000)
end)

H.test("U3 Ctrl is a half step", function()
    local r = Zoom.FarStep(1000, -1, true, NATIVE, 2000)
    local full = Zoom.FarStep(1000, -1, false, NATIVE, 2000)
    H.near(r * r / 1000, full, 1e-6)
end)

H.test("U3 zooming back in lands exactly on the native radius and leaves far mode", function()
    local r, leave = Zoom.FarStep(NATIVE * 1.25, 1, false, NATIVE, 2000)
    H.eq(r, NATIVE); H.eq(leave, true)
    r, leave = Zoom.FarStep(NATIVE * 1.2, 1, false, NATIVE, 2000)
    H.eq(r, NATIVE); H.eq(leave, true)
    r, leave = Zoom.FarStep(1000, 1, false, NATIVE, 2000)
    H.near(r, 800, 1e-9); H.eq(leave, false)
end)

H.test("U3 ten notches reach 2,000 yd from the native 233 yd", function()
    local r = NATIVE
    for _ = 1, 10 do r = Zoom.FarStep(r, -1, false, NATIVE, 2000) end
    H.eq(r, 2000)
end)

H.test("tween runs from start to end evenly in log space", function()
    H.eq(Zoom.Tween(100, 400, 0, 0.15), 100)
    H.eq(Zoom.Tween(100, 400, 0.15, 0.15), 400)
    H.near(Zoom.Tween(100, 400, 0.075, 0.15), 200, 1e-9)
    H.eq(Zoom.Tween(100, 400, 0.01, 0), 400, "no smoothing jumps")
end)
