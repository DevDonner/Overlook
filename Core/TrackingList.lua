-- Reads the game's minimap tracking list (C_Minimap) into plain entries for the tracking menu.
-- Pure apart from the api table passed in, so it can be tested offline.
local _, ns = ...

local TrackingList = {}
ns.TrackingList = TrackingList

local function Secret(v)
    return ns.IsSecret and ns.IsSecret(v) or false
end

-- api: { GetNumTrackingTypes = fn() -> n, GetTrackingInfo = fn(i) -> table or name, texture, active, ... }
-- Returns { { index, name, texture, active, spell }, ... } in the game's order; entries the
-- game keeps secret or nameless are left out.
function TrackingList.Read(api)
    local out = {}
    if not (api and api.GetNumTrackingTypes and api.GetTrackingInfo) then return out end
    local okN, n = pcall(api.GetNumTrackingTypes)
    if not okN or Secret(n) or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, a, b, c, d = pcall(api.GetTrackingInfo, i)
        if ok and a ~= nil and not Secret(a) then
            local name, texture, active, kind
            if type(a) == "table" then
                name, texture, active, kind = a.name, a.texture, a.active, a.type
            else
                -- Older signature: name, texture, active, type
                name, texture, active, kind = a, b, c, d
            end
            if type(name) == "string" and name ~= "" and not Secret(name) and not Secret(active) then
                out[#out + 1] = {
                    index = i,
                    name = name,
                    texture = (not Secret(texture)) and texture or nil,
                    active = active and true or false,
                    spell = kind == "spell",
                }
            end
        end
    end
    return out
end
