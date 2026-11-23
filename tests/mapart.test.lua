-- Map art maths: which map to draw, where its art tiles go in the world, floors, and the
-- player's position from the map when UnitPosition gives none (inside instances).
local H = ...
local ns = H.loadAddonFile("Core/MapArt.lua", {})
local A = ns.MapArt

local function V(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

-- A fake C_Map: map 100 spans north 500 -> -500 and west 300 -> -700 (1,000 yd square) on
-- instance 33, with a 2x2 layer of 256 px tiles cropped to 400 x 400 px.
local function Api(over)
    local api = {
        GetWorldPosFromMapPos = function(map, pos)
            if map ~= 100 then return nil end
            return 33, V(500 - pos.y * 1000, 300 - pos.x * 1000)
        end,
        GetMapArtLayers = function(map)
            if map ~= 100 then return nil end
            return { { layerWidth = 400, layerHeight = 400, tileWidth = 256, tileHeight = 256 } }
        end,
        GetMapArtLayerTextures = function(map, layer)
            if map == 100 and layer == 1 then return { 11, 12, 21, 22 } end
        end,
        GetPlayerMapPosition = function(map, unit)
            if map == 100 and unit == "player" then return V(0.25, 0.5) end
        end,
        GetMapGroupID = function() return nil end,
    }
    for k, v in pairs(over or {}) do api[k] = v end
    return api
end

H.test("a map's world rectangle comes from its corners", function()
    local inst, top, left, bottom, right = A.WorldRect(Api(), 100, V)
    H.eq(inst, 33)
    H.eq(top, 500); H.eq(left, 300); H.eq(bottom, -500); H.eq(right, -700)
    H.eq(A.WorldRect(Api(), 999, V), nil)
end)

H.test("art tiles cover the map; edge tiles are cropped to the layer", function()
    local tiles = A.Tiles(Api(), 100, V)
    H.eq(#tiles, 4)
    local t = tiles[1] -- top-left: 256 of 400 px each way
    H.eq(t.file, 11)
    H.near(t.n0, 500, 1e-9); H.near(t.w0, 300, 1e-9)
    H.near(t.n1, 500 - 640, 1e-9); H.near(t.w1, 300 - 640, 1e-9)
    H.eq(t.u1, 1); H.eq(t.v1, 1)
    local br = tiles[4] -- bottom-right: the remaining 144 px of a 256 px tile
    H.eq(br.file, 22)
    H.near(br.n0, -140, 1e-9); H.near(br.w0, -340, 1e-9)
    H.near(br.n1, -500, 1e-9); H.near(br.w1, -700, 1e-9)
    H.near(br.u1, 144 / 256, 1e-9); H.near(br.v1, 144 / 256, 1e-9)
    H.eq(tiles[2].file, 12, "row-major: second texture is the top row's second tile")
end)

H.test("a map without art has no tiles", function()
    H.eq(#A.Tiles(Api(), 999, V), 0)
end)

H.test("which map: dungeons with no terrain draw their own map", function()
    H.eq(A.Choose({ best = 100, hasArt = true, terrain = false }), 100)
    H.eq(A.Choose({ best = 100, hasArt = false, terrain = false }), nil, "nothing to draw")
end)

H.test("which map: outdoors on a continent with terrain, the terrain is enough", function()
    H.eq(A.Choose({ best = 100, hasArt = true, terrain = true, indoors = false, mapType = A.DUNGEON }), nil)
end)

H.test("which map: indoors, only underground maps and dungeon-like maps replace the terrain", function()
    H.eq(A.Choose({ best = 1458, hasArt = true, terrain = true, indoors = true, mapType = A.ZONE }), 1458,
        "Undercity")
    H.eq(A.Choose({ best = 77, hasArt = true, terrain = true, indoors = true, mapType = A.MICRO }), 77)
    H.eq(A.Choose({ best = 1429, hasArt = true, terrain = true, indoors = true, mapType = A.ZONE }), nil,
        "an inn in Elwynn keeps the terrain")
end)

H.test("which map: where a cave's own images are drawn, underground maps stand aside", function()
    H.eq(A.Choose({ best = 1458, hasArt = true, terrain = true, indoors = true, mapType = A.ZONE, cave = true }), nil)
    H.eq(A.Choose({ best = 100, hasArt = true, terrain = false, cave = true }), 100, "a dungeon still draws its map")
end)

H.test("the player's world position from the map when UnitPosition gives none", function()
    local n, w, inst = A.PlayerFromMap(Api(), 100)
    H.eq(inst, 33)
    H.near(n, 0, 1e-9)    -- halfway down
    H.near(w, 50, 1e-9)   -- a quarter across: 300 - 250
    H.eq(A.PlayerFromMap(Api({ GetPlayerMapPosition = function() return nil end }), 100), nil)
end)

H.test("a party member's world position from the map, by unit", function()
    local asked
    local api = Api({ GetPlayerMapPosition = function(_, unit) asked = unit; return V(0.5, 0.5) end })
    local n, w, inst = A.PlayerFromMap(api, 100, "party2")
    H.eq(asked, "party2")
    H.near(n, 0, 1e-9); H.near(w, -200, 1e-9); H.eq(inst, 33)
end)

H.test("floors: a map group's members in height order, else none", function()
    H.eq(A.Floors(Api(), 100), nil)
    local api = Api({
        GetMapGroupID = function() return 7 end,
        GetMapGroupMembersInfo = function()
            return { { mapID = 102, name = "Lower", relativeHeightIndex = 2 },
                { mapID = 101, name = "Upper", relativeHeightIndex = 1 } }
        end,
    })
    local floors = A.Floors(api, 100)
    H.eq(#floors, 2)
    H.eq(floors[1].mapID, 101); H.eq(floors[2].name, "Lower")
end)

H.test("floors: stepping wraps past either end and finds the current floor", function()
    local floors = { { mapID = 101 }, { mapID = 102 }, { mapID = 103 } }
    H.eq(A.StepFloor(floors, 102, 1), 103)
    H.eq(A.StepFloor(floors, 103, 1), 101, "past the bottom: back to the top")
    H.eq(A.StepFloor(floors, 101, -1), 103, "past the top: round to the bottom")
    H.eq(A.StepFloor(floors, 999, 1), 101, "unknown current: start at the first floor")
end)
