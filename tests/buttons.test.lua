-- The minimap button panel (Shell/Buttons.lua): grid maths and which frames count as buttons.
local H = ...

local saved = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local B = H.loadAddonFile("Shell/Buttons.lua", { RegisterCommand = function() end }).Buttons
_G.CreateFrame = saved

H.test("grid: rows fill left to right, the panel fits them", function()
    local slots, w, h = B.Grid(7, 3, 20, 4, 6)
    H.eq(#slots, 7)
    H.eq(slots[1][1], 6); H.eq(slots[1][2], -6)
    H.eq(slots[3][1], 6 + 2 * 24)
    H.eq(slots[4][1], 6); H.eq(slots[4][2], -30, "second row")
    H.eq(w, 12 + 3 * 20 + 2 * 4)
    H.eq(h, 12 + 3 * 20 + 2 * 4, "three rows")
end)

H.test("grid: fewer buttons than a row makes a narrower panel", function()
    local _, w, h = B.Grid(2, 6, 20, 4, 6)
    H.eq(w, 12 + 2 * 20 + 4)
    H.eq(h, 12 + 20)
end)

H.test("grid: no buttons, still a sane size", function()
    local slots, w = B.Grid(0, 6, 20, 4, 6)
    H.eq(#slots, 0)
    H.truthy(w > 0)
end)

H.test("buttons: LibDBIcon and minimap-button names, not the game's own", function()
    H.eq(B.LooksLikeButton("LibDBIcon10_Questie"), true)
    H.eq(B.LooksLikeButton("AtlasLootMinimapButton"), true)
    H.eq(B.LooksLikeButton("Foo_MiniMapButton"), true)
    H.eq(B.LooksLikeButton("MiniMapTrackingButton"), false)
    H.eq(B.LooksLikeButton("MinimapZoomIn"), false)
    H.eq(B.LooksLikeButton("GameTimeFrame"), false)
    H.eq(B.LooksLikeButton("FarZoomMinimapFrame"), false)
    H.eq(B.LooksLikeButton(nil), false)
end)
