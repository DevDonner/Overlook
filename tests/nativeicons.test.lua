-- The game's own minimap icons: reading the tracking list and choosing what to switch.
local H = ...

-- The module registers an event frame and a command when loaded; stub just enough.
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local ns = { RegisterCommand = function() end }
H.loadAddonFile("Core/NativeIcons.lua", ns)
local N = ns.NativeIcons

local function api(list)
    return {
        GetNumTrackingTypes = function() return #list end,
        GetTrackingInfo = function(i) return list[i] end,
    }
end

H.test("reads the table signature", function()
    local e = N.ReadTracking(api({
        { name = "Mailbox", active = true, type = "other" },
        { name = "Find Herbs", active = false, type = "spell" },
        { name = "", active = true },
    }))
    H.eq(#e, 2)
    H.eq(e[1].name, "Mailbox"); H.eq(e[1].active, true); H.eq(e[1].spell, false)
    H.eq(e[2].spell, true); H.eq(e[2].index, 2)
end)

H.test("reads the older multi-value signature", function()
    local a = {
        GetNumTrackingTypes = function() return 1 end,
        GetTrackingInfo = function() return "Flight Master", 123, true, "other" end,
    }
    local e = N.ReadTracking(a)
    H.eq(e[1].name, "Flight Master"); H.eq(e[1].active, true)
end)

H.test("no api, or a failing one, gives an empty list", function()
    H.eq(#N.ReadTracking(nil), 0)
    H.eq(#N.ReadTracking({ GetNumTrackingTypes = function() error("x") end, GetTrackingInfo = print }), 0)
end)

H.test("reads subType and texture", function()
    local e = N.ReadTracking(api({ { name = "Mailbox", active = true, type = "other", subType = 2, texture = 136459 } }))
    H.eq(e[1].subType, 2); H.eq(e[1].texture, 136459)
end)

-- As 1.60.1 reports them (/overlook native dump).
local LIST = {
    { name = "Find Minerals", active = true, spell = true, subType = -1, texture = 136025 },
    { name = "Mailbox", active = true, spell = false, subType = 2, texture = 136459 },
    { name = "Class Trainer", active = false, spell = false, subType = 2, texture = 136455 },
    { name = "Flight Master", active = true, spell = false, subType = -1, texture = 136456 },
    { name = "Target", active = true, spell = false, subType = -1, texture = 524052 },
    { name = "Track Quest POIs", active = true, spell = false, subType = -1, texture = 535616 },
}

H.test("switches off active town services only: not spells, Target or quest POIs", function()
    local off = N.ToSwitchOff(LIST)
    H.eq(#off, 2)
    H.eq(off[1].name, "Mailbox")
    H.eq(off[2].name, "Flight Master")
end)

H.test("finds entries an earlier version switched off that aren't town services", function()
    local back = N.Overreach(LIST, { "Mailbox", "Target", "Track Quest POIs", "Gone" })
    H.eq(#back, 2)
    H.eq(back[1].name, "Target")
    H.eq(back[2].name, "Track Quest POIs")
end)

H.test("restores only what was switched off and is still off", function()
    local back = N.ToRestore({
        { name = "Mailbox", active = false },
        { name = "Trainer", active = false },
        { name = "Banker", active = true },
    }, { "Mailbox", "Banker" })
    H.eq(#back, 1)
    H.eq(back[1].name, "Mailbox")
    H.eq(#N.ToRestore({ { name = "Mailbox", active = false } }, nil), 0)
end)
