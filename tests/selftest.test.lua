-- The self-test's rules (Far/SelfTest.lua), on snapshots like the ones it takes in game: a healthy
-- far map passes, and the two white boxes from 1.1.0 are caught.
local H = ...

local function noop() end
local ns = { RegisterCommand = noop }
H.loadAddonFile("Far/SelfTest.lua", ns)
local S = ns.SelfTest

local TILE = 1600 / 3
local SIZE = 448

-- A healthy far map at radius r: tiles the right size, the arrow, a few icons, the background.
local ids = {}
local function Id(name) ids[name] = ids[name] or { name = name }; return ids[name] end

local function Snap(r, extra)
    local ppy = SIZE / 2 / r
    local items = {
        { id = Id("bg"), part = "background", kind = "Texture", file = nil, w = SIZE, h = SIZE, x = 0, y = 0 },
        { id = Id("arrow"), part = "arrow", kind = "Texture", file = "Interface\\Minimap\\MinimapArrow", w = 32, h = 32, x = 0, y = 0 },
        { id = Id("icon1"), part = "icon", kind = "Texture", file = 136235, w = 16, h = 16, x = 40, y = -20 },
        { id = Id("route"), part = "route", kind = "Line", file = "Interface\\BUTTONS\\WHITE8X8", w = 60, h = 3, x = 10, y = 10 },
    }
    for i = 1, 4 do
        items[#items + 1] = { id = Id("tile" .. i), part = "tile", inst = 0, kind = "Texture", file = 5313057 + i,
            w = TILE * ppy, h = TILE * ppy, x = (i - 2.5) * TILE * ppy, y = 0 }
    end
    for _, it in ipairs(extra or {}) do items[#items + 1] = it end
    return { radius = r, size = SIZE, ppy = ppy, items = items }
end

local function Rules(problems)
    local out = {}
    for _, p in ipairs(problems) do out[#out + 1] = p.rule end
    table.sort(out)
    return table.concat(out, ",")
end

H.test("a healthy far map has no problems at any zoom", function()
    local problems, notes = S.Check({ Snap(400), Snap(1500), Snap(3000) }, { tile = TILE })
    H.eq(#problems, 0, problems[1] and problems[1].text)
    H.eq(#notes, 0)
end)

H.test("1.1.0's white box (Leatrix Plus, the game's city map) is caught by three rules", function()
    -- A copy of the hybrid minimap's white mask: 80 px, on the player, the same size at every zoom.
    local box = { id = Id("box"), part = "copy", kind = "Texture", file = "Interface\\BUTTONS\\WHITE8X8",
        w = 80, h = 80, x = 0, y = 0, from = "Other addons" }
    local problems = S.Check({ Snap(400, { box }), Snap(1500, { box }), Snap(3000, { box }) }, { tile = TILE })
    H.eq(Rules(problems), "fill,player,scale")
end)

H.test("even as a real picture (no fill), a box that sits on the player and won't scale is caught", function()
    local box = { id = Id("pic"), part = "copy", kind = "Texture", file = 5012345, w = 80, h = 80, x = 1, y = -2 }
    local problems = S.Check({ Snap(400, { box }), Snap(1500, { box }) }, { tile = TILE })
    H.eq(Rules(problems), "player,scale")
end)

H.test("1.1.0's other white squares (RareScanner's route lines copied as boxes) are plain fills", function()
    local sq = { id = Id("sq"), part = "copy", kind = "Texture", file = "Interface\\Buttons\\WHITE8X8",
        w = 12, h = 9, x = 30, y = 14, from = "RareScanner" }
    local problems = S.Check({ Snap(400, { sq }) }, { tile = TILE })
    H.eq(Rules(problems), "fill")
    H.truthy(problems[1].text:find("RareScanner"), "names whose it is")
end)

H.test("a colour texture (no file) counts as a fill; an atlas doesn't; our own route lines may be white", function()
    H.eq(S.IsFill({ kind = "Texture", file = nil }), true)
    H.eq(S.IsFill({ kind = "Texture", file = "nil" }), true)
    H.eq(S.IsFill({ kind = "Texture", file = nil, atlas = "Minimap-Arrow" }), false)
    H.eq(S.IsFill({ kind = "Texture", file = "Interface\\Tooltips\\UI-Tooltip-Background" }), true)
    H.eq(S.IsFill({ kind = "Line", file = "Interface\\BUTTONS\\WHITE8X8" }), false)
    H.eq(S.IsFill({ kind = "Texture", file = 136235 }), false)
end)

H.test("tiles the wrong size for the zoom are caught, once per zoom", function()
    local s = Snap(1500)
    for _, it in ipairs(s.items) do
        if it.part == "tile" then it.w, it.h = it.w * 2, it.h * 2 end
    end
    local problems = S.Check({ s }, { tile = TILE })
    H.eq(Rules(problems), "tiles")
    H.truthy(problems[1].text:find("4 tile"))
end)

H.test("no limit at its furthest: a continent without tiles is caught", function()
    local opts = { tile = TILE, world = true, reach = 32000, continents = { 0, 1 } }
    H.eq(Rules((S.Check({ Snap(32000) }, opts))), "world", "only continent 0's tiles")
    local both = Snap(32000, { { id = Id("k"), part = "tile", inst = 1, kind = "Texture", file = 1,
        w = TILE * SIZE / 2 / 32000, h = TILE * SIZE / 2 / 32000, x = -150, y = 0 } })
    H.eq(#S.Check({ both }, opts), 0)
    H.eq(#S.Check({ Snap(3000) }, opts), 0, "not checked short of the furthest zoom")
end)

H.test("things in the far view that aren't Overlook's, and slow tiles, are notes, not problems", function()
    local s = Snap(1500, { { id = Id("x"), part = "unlabelled", kind = "Texture", file = "Interface\\AddOns\\Foo\\x.blp",
        w = 20, h = 20, x = 50, y = 50, frame = "FooFrame" } })
    s.loading, s.seconds = true, 8
    local problems, notes = S.Check({ s }, { tile = TILE })
    H.eq(#problems, 0)
    H.eq(#notes, 2)
    H.truthy(notes[1].text:find("FooFrame") or notes[2].text:find("FooFrame"))
end)

H.test("the arrow, background and a cave's cover may stay the same size", function()
    local cover = { id = Id("cover"), part = "cave cover", kind = "Texture", file = nil, w = SIZE, h = SIZE, x = 0, y = 0 }
    H.eq(#S.Check({ Snap(400, { cover }), Snap(3000, { cover }) }, { tile = TILE }), 0)
end)

H.test("summary: per part counts and sizes, and only what's worth reading in full", function()
    local box = { id = Id("box2"), part = "copy", kind = "Texture", file = "x", w = 80, h = 80, x = 0, y = 0 }
    local sum = S.Summarise(Snap(1500, { box }))
    H.eq(sum.parts.tile.count, 4)
    H.eq(sum.parts.icon.count, 1)
    H.eq(#sum.notable, 1, "the copy")
    H.eq(sum.radius, 1500)
end)

H.test("zoom levels: past the native map up to the furthest, spread out, ending at the furthest", function()
    local steps = S.Steps(233, 3000, 3000)
    H.eq(steps[#steps], 3000)
    H.truthy(steps[1] > 233)
    for i = 2, #steps do H.truthy(steps[i] >= steps[i - 1] * 1.5) end
    local world = S.Steps(233, 3000, 32000)
    H.eq(world[#world], 32000, "no limit: the whole world last")
    H.truthy(#world >= 4)
end)
