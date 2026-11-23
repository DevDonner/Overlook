-- Questie's icon switches driven from our panel (Core/QuestieToggles.lua), against a fake Questie
-- that records the redraw calls its own options panel makes.
local H = ...

local calls, profile, townsfolk
local saved = { Questie = _G.Questie, QuestieLoader = _G.QuestieLoader }

local MODULES = {
    QuestieQuest = {
        ToggleNotes = function(_, v) calls[#calls + 1] = "ToggleNotes " .. tostring(v) end,
        ToggleAvailableQuests = function(v) calls[#calls + 1] = "ToggleAvailable " .. tostring(v) end,
    },
    QuestiePartyObjectives = { ScheduleUpdate = function() calls[#calls + 1] = "Party" end },
    QuestieOptionsUtils = { DetermineTheme = function() calls[#calls + 1] = "Theme" end },
    QuestieMenu = { buildTownsfolkMenu = function() return townsfolk end },
}

local ns, Q
local function Fresh()
    calls = {}
    profile = { enabled = true, enableAvailable = true, enableTurnins = false, enableObjectives = true }
    townsfolk = {}
    _G.Questie = { db = { profile = profile } }
    _G.QuestieLoader = { ImportModule = function(_, name) return MODULES[name] end }
    ns = H.loadAddonFile("Core/QuestieToggles.lua", {})
    Q = ns.QuestieToggles
end
H.beforeEach(Fresh)

local function Has(name)
    for _, c in ipairs(calls) do if c == name then return true end end
    return false
end

H.test("reads Questie's own settings", function()
    H.truthy(Q.Available())
    H.eq(Q.Get("enableAvailable"), true)
    H.eq(Q.Get("enableTurnins"), false)
end)

H.test("turn-ins: sets Questie's setting and redraws the way its panel does", function()
    H.truthy(Q.Set("enableTurnins", true))
    H.eq(profile.enableTurnins, true)
    H.truthy(Has("ToggleAvailable true"))
end)

H.test("objectives: also refreshes party objectives and the icon theme", function()
    Q.Set("enableObjectives", false)
    H.eq(profile.enableObjectives, false)
    H.truthy(Has("ToggleNotes false")); H.truthy(Has("Party")); H.truthy(Has("Theme"))
end)

H.test("all icons: Questie's master switch", function()
    Q.Set("enabled", false)
    H.eq(profile.enabled, false)
    H.truthy(Has("ToggleNotes false"))
end)

H.test("unknown keys are refused and nothing changes", function()
    H.eq(Q.Set("somethingElse", true), false)
    H.eq(profile.somethingElse, nil)
end)

H.test("without Questie the switches are inert, not errors", function()
    _G.Questie, _G.QuestieLoader = nil, nil
    H.eq(Q.Available(), false)
    H.eq(Q.Get("enabled"), false)
    H.eq(Q.Set("enabled", true), false)
    H.eq(#Q.Townsfolk(), 0)
end)

H.test("a Questie redraw that errors doesn't break the panel", function()
    MODULES.QuestieQuest.ToggleAvailableQuests = function() error("renamed") end
    H.eq(Q.Set("enableAvailable", false), false, "reported as not taken")
    H.eq(profile.enableAvailable, false, "the setting itself is still written")
    MODULES.QuestieQuest.ToggleAvailableQuests = function(v) calls[#calls + 1] = "ToggleAvailable " .. tostring(v) end
end)

H.test("town icons: Questie's menu entries, toggled through Questie", function()
    local on = false
    townsfolk = {
        { text = "Flight Master", icon = 1, checked = function() return on end, func = function() on = not on end },
        { isDivider = true },
        { text = "Broken", checked = function() error("x") end, func = function() end },
    }
    local list = Q.Townsfolk()
    H.eq(#list, 2, "dividers skipped")
    H.eq(list[1].label, "Flight Master")
    H.eq(list[1].checked(), false)
    list[1].toggle()
    H.eq(list[1].checked(), true)
    H.eq(list[2].checked(), false, "an entry that errors reads as off")
end)

_G.Questie, _G.QuestieLoader = saved.Questie, saved.QuestieLoader
