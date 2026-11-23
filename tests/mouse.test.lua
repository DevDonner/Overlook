-- Ping offsets and double clicks (Core/Zoom.lua), and when mounting zooms (Far/Mount.lua).
local H = ...

local ns = H.loadAddonFile("Core/Zoom.lua", {})
local Z = ns.Zoom

-- Native minimap: 140 units across 233.3 yd each way (the widest step outdoors).
local SIZE, MAX = 140, 700 / 3

H.test("ping: the cursor over the player pings the centre", function()
    local x, y = Z.PingOffset(0, 0, 0.1, 100, 200, 100, 200, SIZE, MAX)
    H.near(x, 0, 1e-9); H.near(y, 0, 1e-9)
end)

H.test("ping: north is up and east is right, in native units", function()
    -- 10 px right and 5 px up at 0.1 px/yd: 100 yd east, 50 yd north.
    local x, y = Z.PingOffset(10, 5, 0.1, 0, 0, 0, 0, SIZE, MAX)
    local k = SIZE / 2 / MAX
    H.near(x, 100 * k, 1e-9); H.near(y, 50 * k, 1e-9)
end)

H.test("ping: relative to the player, not the panned view centre", function()
    -- View centred 100 yd north of the player; cursor on the view centre.
    local x, y = Z.PingOffset(0, 0, 0.1, 100, 0, 0, 0, SIZE, MAX)
    H.near(x, 0, 1e-9); H.near(y, 100 * SIZE / 2 / MAX, 1e-9)
end)

H.test("ping: nothing past the native minimap's edge", function()
    H.eq(Z.PingOffset(30, 0, 0.1, 0, 0, 0, 0, SIZE, MAX), nil, "300 yd east")
    H.eq(Z.PingOffset(0, 0, 0, 0, 0, 0, 0, SIZE, MAX), nil, "no zoom yet")
    H.eq(Z.PingOffset(0, 0, 0.1, 0, 0, nil, nil, SIZE, MAX), nil, "no player position")
end)

H.test("double click: within 0.3 s", function()
    H.eq(Z.IsDoubleClick(nil, 5), false)
    H.eq(Z.IsDoubleClick(5, 5.25), true)
    H.eq(Z.IsDoubleClick(5, 5.4), false)
end)

local saved = _G.CreateFrame
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end }
end
local M = H.loadAddonFile("Far/Mount.lua", {}).Mount
_G.CreateFrame = saved

H.test("mount: zooms out from the native map or a closer far view", function()
    H.eq(M.Decide(true, false, true, nil, 800, false), "out")
    H.eq(M.Decide(true, false, true, 400, 800, false), "out")
end)

H.test("mount: already further out, or switched off: leaves the view alone", function()
    H.eq(M.Decide(true, false, true, 1200, 800, false), nil)
    H.eq(M.Decide(true, false, false, nil, 800, false), nil)
end)

H.test("dismount: back only if the zoom-out was ours", function()
    H.eq(M.Decide(false, true, true, 800, 800, true), "back")
    H.eq(M.Decide(false, true, true, 800, 800, false), nil)
    H.eq(M.Decide(true, true, true, nil, 800, false), nil, "no change, nothing to do")
end)
