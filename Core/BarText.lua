-- Text for the top and bottom bars. Pure Lua, so the offline tests cover it.
local _, ns = ...

local BarText = {}
ns.BarText = BarText

-- Zone colours by PvP status, as the game's own minimap header colours them.
BarText.PVP = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena = { 1, 0.1, 0.1 },
    combat = { 1, 0.1, 0.1 },
    hostile = { 1, 0.1, 0.1 },
    friendly = { 0.1, 1, 0.1 },
    contested = { 1, 0.7, 0 },
}
BarText.NEUTRAL = { 0.92, 0.92, 0.92 }

function BarText.ZoneColor(pvpType, usePvP)
    return (usePvP and BarText.PVP[pvpType]) or BarText.NEUTRAL
end

-- The top bar's text: the subzone (or the zone when there's none), and the zone after it, dimmed,
-- when withZone is set and it says something new.
function BarText.Zone(subzone, zone, withZone)
    subzone = subzone ~= "" and subzone or nil
    zone = zone ~= "" and zone or nil
    local main = subzone or zone or ""
    if withZone and zone and subzone and zone ~= subzone then
        return main .. "  |cff8a8f99" .. zone .. "|r"
    end
    return main
end

-- Map coordinates (0-1) as percentages with 0-2 decimals; "--" where the map has none.
function BarText.Coords(x, y, decimals)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return "--" end
    local fmt = "%." .. (decimals or 1) .. "f, %." .. (decimals or 1) .. "f"
    return string.format(fmt, x * 100, y * 100)
end

function BarText.Clock(hour, minute, use24)
    if use24 then return string.format("%02d:%02d", hour, minute) end
    local suffix = hour < 12 and "AM" or "PM"
    local h = hour % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d %s", h, minute, suffix)
end

-- The far view's radius, e.g. "1,250 yd".
function BarText.Yards(radius)
    if not radius then return "" end
    local n = tostring(math.floor(radius + 0.5))
    n = n:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return n .. " yd"
end
