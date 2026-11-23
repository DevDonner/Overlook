-- Cave maths (Core/CaveMath.lua): picking the cave the player is in, placing its images on the
-- world, levels and the Alt+wheel wrap. Wailing Caverns numbers are from the generated data and
-- were checked in game (the player's room lined up with the native minimap, north up).
local H = ...

local ns = H.loadAddonFile("Core/CaveMath.lua", {})
local C = ns.CaveMath

-- Wailing Caverns' outer cave as placed on Kalimdor, and two of its groups.
local WAILING = { 109550, -928.7, -2095.2, 0.1047, -874.0, -513.7, -2423.8, -1955.7 }
local GROUPS = {
    { 3, 122.5, -64.6, 213137, 0, 0, 256, 256 },
    { 5, 162.1, -337.3, 213150, 0, 0, 256, 256, 213151, 0, 1, 256, 256 },
}

H.test("pick: the cave whose bounds hold the player", function()
    H.eq(C.Pick({ WAILING }, -806.8, -2026.2), WAILING, "the spot checked in game")
    H.eq(C.Pick({ WAILING }, -400, -2026.2), nil, "north of it")
    H.eq(C.Pick(nil, 0, 0), nil, "no caves on this continent")
end)

H.test("pick: the smaller of two nested placements wins (a building inside a cave's bounds)", function()
    local inner = { 2, -800, -2000, 0, -810, -800, -2030, -2020 }
    H.eq(C.Pick({ WAILING, inner }, -806.8, -2026.2), inner)
    H.eq(C.Pick({ inner, WAILING }, -806.8, -2026.2), inner, "order doesn't matter")
end)

H.test("pick: placements of a model with no images are skipped", function()
    H.eq(C.Pick({ WAILING }, -806.8, -2026.2, {}), nil)
    H.eq(C.Pick({ WAILING }, -806.8, -2026.2, { [109550] = GROUPS }), WAILING)
end)

H.test("quads: one per image, centred where the image's middle lands on the world", function()
    local q = C.Quads(WAILING, GROUPS)
    H.eq(#q, 3)
    H.eq(q[1].file, 213137)
    H.eq(q[1].level, 3); H.eq(q[3].level, 5, "every image carries its group's level")
    -- Local centre (186.5, -0.6), turned by 6 degrees about the placement.
    H.near(q[1].north, -928.7 + 186.5 * math.cos(0.1047) + 0.6 * math.sin(0.1047), 0.01)
    H.near(q[1].west, -2095.2 + 186.5 * math.sin(0.1047) - 0.6 * math.cos(0.1047), 0.01)
    H.near(q[1].width, 128, 1e-9); H.near(q[1].height, 128, 1e-9)
    H.near(q[1].rotation, 0.1047 + math.pi / 2, 1e-9, "columns run along local X, which points north")
end)

H.test("quads: a second block sits 128 yards further along local Y", function()
    local q = C.Quads({ 1, 0, 0, 0, 0, 0, 0, 0 }, { { 1, 0, 0, 7, 0, 0, 256, 256, 8, 0, 1, 256, 256 } })
    H.near(q[1].north, 64, 1e-9); H.near(q[1].west, 64, 1e-9)
    H.near(q[2].north, 64, 1e-9); H.near(q[2].west, 192, 1e-9, "local +Y is west at no turn")
end)

H.test("quads: non-square images and scaled placements", function()
    local q = C.Quads({ 1, 0, 0, 0, 0, 0, 0, 0, 2 }, { { 1, 10, 20, 7, 0, 0, 128, 64 } })
    H.near(q[1].width, 128, 1e-9, "64 yd wide, doubled")
    H.near(q[1].height, 64, 1e-9)
    H.near(q[1].north, (10 + 32) * 2, 1e-9); H.near(q[1].west, (20 + 16) * 2, 1e-9)
end)

H.test("levels: the count is the deepest level", function()
    H.eq(C.LevelCount(GROUPS), 5)
    H.eq(C.LevelCount({ { 1 }, { 3 }, { 2 } }), 3)
    H.eq(C.LevelCount({}), 1)
end)

H.test("wheel: down peels the top level off the stack, past the bottom the whole stack is back", function()
    H.eq(C.Step(1, 3, -1), 2, "whole stack: level 1 peeled off")
    H.eq(C.Step(2, 3, -1), 3, "only the bottom level left")
    H.eq(C.Step(3, 3, -1), 1, "past the bottom: the whole stack again")
    H.eq(C.Step(1, 3, 1), 3, "up from the whole stack: round to the bottom level")
    H.eq(C.Step(3, 3, 1), 2, "up puts the last peeled level back")
    H.eq(C.Step(1, 1, -1), 1, "one level: nothing to step")
end)

H.test("stack: the top level drawn highest, every level at the same brightness", function()
    local s1, l1 = C.StackLook(1)
    local s2, l2 = C.StackLook(2)
    H.truthy(s1 > s2); H.eq(l1, 1); H.eq(l2, 1)
    local s9, l9 = C.StackLook(9)
    H.eq(s9, 2, "never under the terrain cover"); H.eq(l9, 1)
end)

H.test("generated data: the spot checked in game is in Wailing Caverns, with its images", function()
    local data = H.loadAddonFile("Data/Caves.lua", {}).CaveData
    local p = C.Pick(data[1], -806.8, -2026.2, data.wmo)
    H.truthy(p, "a cave there")
    H.eq(p[1], 109550, "wailingcaverns.wmo")
    H.eq(#C.Quads(p, data.wmo[p[1]]), 19)
    H.eq(C.LevelCount(data.wmo[p[1]]), 5, "by floor height: the eye ledge alone on top")
    H.eq(C.Pick(data[1], -806.8, -2026.2 + 2000, data.wmo), nil, "open Barrens")
end)
