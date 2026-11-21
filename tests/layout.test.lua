-- Resize grip math.
local H = ...
local ns = H.loadAddonFile("Core/Layout.lua", {})
H.loadAddonFile("Core/Settings.lua", ns)
local L, Settings = ns.Layout, ns.Settings

H.test("grip faces the screen centre", function()
    local sx, sy = L.GripCorner(500, 300) -- top right map: bottom-left grip
    H.eq(sx, -1); H.eq(sy, -1)
    sx, sy = L.GripCorner(-500, -300) -- bottom left map: top-right grip
    H.eq(sx, 1); H.eq(sy, 1)
end)

H.test("dragging the bottom-left grip keeps the top-right corner fixed", function()
    -- map 200 px centred at (1000, 600): top-right corner at (1100, 700)
    local fx, fy = L.FixedCorner(1000, 600, 200, -1, -1)
    H.eq(fx, 1100); H.eq(fy, 700)
    -- drag the grip to (850, 520): 250 wide, 180 tall -> square 250
    local size, cx, cy = L.ResizeFrom(fx, fy, -1, -1, 850, 520, Settings.ClampSize)
    H.eq(size, 250)
    H.eq(cx, 975); H.eq(cy, 575)
    -- top-right corner unchanged
    H.eq(cx + size / 2, 1100); H.eq(cy + size / 2, 700)
end)

H.test("size is clamped, even when the cursor crosses the fixed corner", function()
    local size = L.ResizeFrom(1100, 700, -1, -1, 1200, 800, Settings.ClampSize)
    H.eq(size, Settings.SIZE_MIN)
    size = L.ResizeFrom(1100, 700, -1, -1, -2000, -2000, Settings.ClampSize)
    H.eq(size, Settings.SIZE_MAX)
end)

H.test("settings v1 -> v2 unlocks the map once", function()
    local db = Settings.Load({ version = 1, locked = true })
    H.eq(db.locked, false)
    db.locked = true
    H.eq(Settings.Load(db).locked, true, "a lock set after the migration stays")
end)
