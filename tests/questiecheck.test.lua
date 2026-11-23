-- The Questie check: names what may stop working when Questie's internals change.
local H = ...
local ns = H.loadAddonFile("Core/QuestieCheck.lua", {})
local QC = ns.QuestieCheck

local function fn() end

-- A Questie with every part the addon uses. ImportModule hands back an empty table for a module
-- it doesn't know, as Questie's loader does.
local function FullQuestie()
    local modules = {
        HBDPins = { minimapPins = {}, AddMinimapIconWorld = fn, RemoveMinimapIcon = fn },
        MapIconTooltip = { ShowOnTooltip = fn },
        QuestieWaypoints = { paths = {}, MinimapAlpha = fn, Color = fn },
    }
    local loader = { ImportModule = function(_, name) return modules[name] or {} end }
    return loader, { usedIcons = {} }, modules
end

H.test("everything found: nothing to report", function()
    local loader, questie = FullQuestie()
    H.eq(#QC.Missing(loader, questie), 0)
    H.eq(QC.Message(QC.Missing(loader, questie)), nil)
end)

H.test("a renamed tooltip function is reported as far icon tooltips", function()
    local loader, questie, modules = FullQuestie()
    modules.MapIconTooltip = { ShowTooltip = fn }
    local missing = QC.Missing(loader, questie)
    H.eq(#missing, 1)
    H.eq(missing[1], "tooltips on far icons")
end)

H.test("a changed pin registry is reported as Questie icons on the far map", function()
    local loader, questie, modules = FullQuestie()
    modules.HBDPins = nil -- the loader now hands back an empty table
    H.eq(QC.Missing(loader, questie)[1], "Questie icons on the far map")
end)

H.test("routes and icon pictures are reported too, in a fixed order", function()
    local loader, _, modules = FullQuestie()
    modules.QuestieWaypoints.paths = nil
    local missing = QC.Missing(loader, {})
    H.eq(#missing, 2)
    H.eq(missing[1], "NPC routes")
    H.eq(missing[2], "some icon pictures")
end)

H.test("a loader that errors counts as missing, never raises", function()
    local loader = { ImportModule = function() error("boom") end }
    H.eq(#QC.Missing(loader, { usedIcons = {} }), 3)
end)

H.test("no Questie at all is one line, not a list", function()
    local missing = QC.Missing(nil, nil)
    H.eq(#missing, 1)
    H.eq(missing[1], "Questie")
end)

H.test("the message names what may not work, in one line", function()
    H.eq(QC.Message({ "NPC routes", "some icon pictures" }),
        "Questie has changed in a way this version doesn't know: NPC routes and some icon pictures may not work.")
    H.eq(QC.Message({ "Questie" }), "Questie isn't loaded, so the far map has no Questie icons.")
    H.eq(QC.Message({ "a", "b", "c" }),
        "Questie has changed in a way this version doesn't know: a, b and c may not work.")
end)
