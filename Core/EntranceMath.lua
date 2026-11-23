-- Dungeon and raid entrances: where they are, where they go on the normal minimap, and what their
-- tooltip says. Pure Lua, so the offline tests cover it. The places come from Data/Entrances.lua.
local _, ns = ...

local EntranceMath = {}
ns.EntranceMath = EntranceMath

-- The entrances in world yards: { inst, n, w, raid (all of them raids), list = { { name, raid,
-- min, max }, ... } }. Entries given as a spot on a zone map are placed with api (C_Map) and vec
-- (CreateVector2D); those it can't place are left out.
function EntranceMath.Resolve(data, api, vec)
    local out = {}
    for _, e in ipairs(data and data.instances or {}) do
        local inst, n, w = e[1], e[2], e[3]
        if inst == nil and e.map and api and api.GetWorldPosFromMapPos and vec then
            local ok, i, pos = pcall(api.GetWorldPosFromMapPos, e.map, vec(e[2], e[3]))
            if ok and i and pos then
                inst = i
                n, w = pos:GetXY()
            else
                inst = nil
            end
        end
        if inst ~= nil and type(n) == "number" and type(w) == "number" then
            local list, raid = {}, true
            for _, d in ipairs(e[4] or {}) do
                list[#list + 1] = { name = d[2], raid = d[3] == true, min = d[4], max = d[5] }
                raid = raid and d[3] == true
            end
            if #list > 0 then
                out[#out + 1] = { inst = inst, n = n, w = w, raid = raid, list = list }
            end
        end
    end
    return out
end

-- Where an entrance goes on the normal minimap: x, y in px from its centre (east, north), or nil
-- outside it. pN, pW: the player; half: half the minimap's width in px; radius: the yards from its
-- centre to its edge; facing: the player's facing when the minimap rotates (nil: north up);
-- round: a round minimap; margin: px kept clear of the edge.
function EntranceMath.NativeOffset(n, w, pN, pW, half, radius, facing, round, margin)
    if not (half and radius and radius > 0) then return nil end
    local k = half / radius
    local x, y = (pW - w) * k, (n - pN) * k
    if facing then
        -- The rotating minimap turns the world so the player faces up: turn by -facing.
        local c, s = math.cos(-facing), math.sin(-facing)
        x, y = x * c - y * s, x * s + y * c
    end
    local r = half - (margin or 0)
    if round then
        if x * x + y * y > r * r then return nil end
    elseif math.abs(x) > r or math.abs(y) > r then
        return nil
    end
    return x, y
end

-- A level range as text: "15-24", or "60" when it's one level.
function EntranceMath.Range(lo, hi)
    if not lo then return "" end
    hi = hi or lo
    return lo == hi and tostring(hi) or (lo .. "-" .. hi)
end

-- Which level picks the range's colour for a player at `level`: its low end while that's above
-- you, its high end (less two, so a range wholly below you goes green or grey, not yellow) once
-- you're past it, nil inside it (the "difficult" orange).
function EntranceMath.ColorLevel(lo, hi, level)
    hi = hi or lo
    if not (lo and level) then return nil end
    if level < lo then return lo end
    if level > hi then return hi - 2 end
    return nil
end
