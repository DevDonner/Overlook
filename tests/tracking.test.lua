-- Reading the game's tracking list for the minimap icons menu.
local H = ...
local ns = H.loadAddonFile("Core/TrackingList.lua", {})
local T = ns.TrackingList

local function Api(entries)
    return {
        GetNumTrackingTypes = function() return #entries end,
        GetTrackingInfo = function(i) return entries[i] end,
    }
end

H.test("tracking: table signature, game order, active flags", function()
    local list = T.Read(Api({
        { name = "Find Herbs", texture = 133939, active = true, type = "spell" },
        { name = "Repair", texture = "Interface\Minimap\Tracking\Repair", active = false, type = "other" },
    }))
    H.eq(#list, 2)
    H.eq(list[1].name, "Find Herbs"); H.eq(list[1].active, true); H.eq(list[1].spell, true)
    H.eq(list[2].index, 2); H.eq(list[2].active, false); H.eq(list[2].spell, false)
end)

H.test("tracking: older multi-value signature", function()
    local api = {
        GetNumTrackingTypes = function() return 1 end,
        GetTrackingInfo = function() return "Mailbox", "tex", 1, "other" end,
    }
    local list = T.Read(api)
    H.eq(#list, 1); H.eq(list[1].name, "Mailbox"); H.eq(list[1].active, true)
end)

H.test("tracking: missing api, nameless, secret and erroring entries are skipped", function()
    H.eq(#T.Read(nil), 0)
    H.eq(#T.Read({}), 0)
    local secret = {}
    ns.IsSecret = function(v) return v == secret end
    local api = {
        GetNumTrackingTypes = function() return 4 end,
        GetTrackingInfo = function(i)
            if i == 1 then return { name = "", active = true } end
            if i == 2 then return { name = secret, active = true } end
            if i == 3 then error("boom") end
            return { name = "Banker", active = false }
        end,
    }
    local list = T.Read(api)
    ns.IsSecret = nil
    H.eq(#list, 1); H.eq(list[1].name, "Banker"); H.eq(list[1].index, 4)
end)
