-- Cave maths: which cave the player is in, where each of its minimap images goes on the far
-- canvas, and which levels show. Pure functions over Data/Caves.lua's tables, so they run in the
-- offline tests. Far/Caves.lua draws the result.
--
-- A cave (any WMO with indoor minimap images: caves, mines, building interiors) is split into
-- levels by floor height, 1 at the top, and one level is drawn at a time, like the native
-- minimap indoors. The game doesn't give addons the player's height, so the level shown is
-- picked by hand (Alt+wheel) and starts at the top.
local _, ns = ...

local cos, sin = math.cos, math.sin

local CaveMath = {}
ns.CaveMath = CaveMath

-- Placement fields (Data/Caves.lua): { wmo, north, west, yaw, nMin, nMax, wMin, wMax [, scale] }.
local WMO, NORTH, WEST, YAW, NMIN, NMAX, WMIN, WMAX, SCALE = 1, 2, 3, 4, 5, 6, 7, 8, 9
-- Group fields: { level, minX, minY, then per image: file, bx, by, w, h }.
local LEVEL, MINX, MINY, FIRST = 1, 2, 3, 4

CaveMath.BLOCK_YARDS = 128 -- one 256 px image block at 2 px per yard

-- The placement around (north, west) with the smallest footprint, or nil. Footprints are the
-- placed WMO's world bounds, so a building inside a cave's bounds wins over the cave.
function CaveMath.Pick(list, north, west, data)
    if not list then return nil end
    local best, bestArea
    for _, p in ipairs(list) do
        if north >= p[NMIN] and north <= p[NMAX] and west >= p[WMIN] and west <= p[WMAX]
            and (not data or data[p[WMO]]) then
            local area = (p[NMAX] - p[NMIN]) * (p[WMAX] - p[WMIN])
            if not best or area < bestArea then best, bestArea = p, area end
        end
    end
    return best
end

-- How many levels a cave has.
function CaveMath.LevelCount(groups)
    local n = 1
    for _, g in ipairs(groups) do
        if g[LEVEL] > n then n = g[LEVEL] end
    end
    return n
end


-- The next level for a wheel step: down (delta < 0) goes one level deeper and past the bottom
-- back to the top; up goes the other way round.
-- Alt+wheel through a cave's levels. `at` is the top level of the stack shown (it and every level
-- below): 1 is the whole stack (the start). Down (delta < 0) peels off the top level, and past the
-- bottom level the whole stack comes back. Up puts the last peeled level back.
function CaveMath.Step(at, count, delta)
    if count <= 1 then return 1 end
    if delta < 0 then return at % count + 1 end
    return (at - 2) % count + 1
end

-- How a level is drawn in the stack: its draw sublevel (top level highest, so it covers the
-- ones below) and brightness (each level under the stack's top a little darker, so the depth
-- reads). depth: 1 for the stack's top level, 2 for the one under it, ... Pure.
function CaveMath.StackLook(depth)
    return math.max(2, 8 - depth), math.max(0.45, 1 - 0.15 * (depth - 1))
end

-- Every image of a placed cave as a quad on the world: { file, level, north, west (the image's
-- centre), width, height (yards), rotation (radians, counter-clockwise on screen) }.
function CaveMath.Quads(p, groups)
    local out = {}
    local a, s = p[YAW], p[SCALE] or 1
    local ca, sa = cos(a), sin(a)
    for _, g in ipairs(groups) do
        for i = FIRST, #g, 5 do
            local file, bx, by, w, h = g[i], g[i + 1], g[i + 2], g[i + 3], g[i + 4]
            -- Image centre in local yards: columns run along +X, rows down along -Y.
            local x = (g[MINX] + (bx * 256 + w / 2) / 2) * s
            local y = (g[MINY] + (by * 256 + h / 2) / 2) * s
            out[#out + 1] = {
                file = file, level = g[LEVEL],
                north = p[NORTH] + x * ca - y * sa,
                west = p[WEST] + x * sa + y * ca,
                width = w / 2 * s, height = h / 2 * s,
                rotation = a + math.pi / 2,
            }
        end
    end
    return out
end
