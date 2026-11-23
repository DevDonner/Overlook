-- Questie's icon switches, driven from our settings window. They change Questie's own settings,
-- the same values and refresh calls as Questie's options panel and tracking menu, so the choice
-- applies on the normal minimap, the far map and the world map alike, and Questie's own panel
-- shows the same state.
--
-- Questie's modules are reached through QuestieLoader; every call is guarded, so a Questie update
-- that renames something leaves a switch inert (and /overlook questie names it) instead of erroring.
local _, ns = ...

local QuestieToggles = {}
ns.QuestieToggles = QuestieToggles

local function Import(name)
    local loader = _G.QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, mod = pcall(loader.ImportModule, loader, name)
    if ok and type(mod) == "table" then return mod end
end

local function Profile()
    local q = _G.Questie
    return type(q) == "table" and type(q.db) == "table" and type(q.db.profile) == "table" and q.db.profile or nil
end

-- How Questie redraws after each kind of switch (from its NativeOptionsIcons.lua).
local APPLY = {
    notes = function(value)
        local quest = Import("QuestieQuest")
        if quest and quest.ToggleNotes then quest:ToggleNotes(value) end
    end,
    available = function(value)
        local quest = Import("QuestieQuest")
        if quest and quest.ToggleAvailableQuests then quest.ToggleAvailableQuests(value) end
    end,
    objectives = function(value)
        local quest = Import("QuestieQuest")
        if quest and quest.ToggleNotes then quest:ToggleNotes(value) end
        local party = Import("QuestiePartyObjectives")
        if party and party.ScheduleUpdate then party:ScheduleUpdate() end
        local utils = Import("QuestieOptionsUtils")
        if utils and utils.DetermineTheme then utils.DetermineTheme() end
    end,
}

-- The quest-icon switches, in panel order: { Questie profile key, label, how to apply }.
QuestieToggles.QUEST = {
    { "enabled", "All Questie icons", "notes" },
    { "enableAvailable", "Available quests", "available" },
    { "enableAvailableItems", "Quests started by items", "available" },
    { "showRepeatableQuests", "Repeatable quests", "available" },
    { "showEventQuests", "Event quests", "available" },
    { "showDungeonQuests", "Dungeon quests", "available" },
    { "showRaidQuests", "Raid quests", "available" },
    { "showPvPQuests", "PvP quests", "available" },
    { "enableTurnins", "Quest turn-ins", "available" },
    { "enableObjectives", "Quest objectives", "objectives" },
}

function QuestieToggles.Available()
    return Profile() ~= nil
end

function QuestieToggles.Get(key)
    local p = Profile()
    return p ~= nil and p[key] == true
end

-- Sets a quest-icon switch and has Questie redraw. Returns true when Questie took it.
function QuestieToggles.Set(key, value)
    local p = Profile()
    if not p then return false end
    local kind
    for _, t in ipairs(QuestieToggles.QUEST) do
        if t[1] == key then kind = t[3] end
    end
    if not kind then return false end
    p[key] = value and true or false
    local ok = pcall(APPLY[kind], p[key])
    if ns.Mirror and ns.Mirror.MarkAllDirty then ns.Mirror.MarkAllDirty() end
    return ok
end

-- Questie's town services (Flight Master, Mailbox, Innkeeper, ...) as its tracking menu lists
-- them for this character: { label, icon, checked(), toggle() }. Empty if Questie's menu changed.
function QuestieToggles.Townsfolk()
    local menu = Import("QuestieMenu")
    if not (menu and type(menu.buildTownsfolkMenu) == "function") then return {} end
    local ok, entries = pcall(menu.buildTownsfolkMenu)
    if not ok or type(entries) ~= "table" then return {} end
    local out = {}
    for _, e in ipairs(entries) do
        if type(e) == "table" and type(e.func) == "function" and type(e.checked) == "function" then
            out[#out + 1] = {
                label = tostring(e.text or "?"),
                icon = e.icon,
                checked = function()
                    local okC, v = pcall(e.checked)
                    return okC and v and true or false
                end,
                toggle = function()
                    pcall(e.func)
                    if ns.Mirror and ns.Mirror.MarkAllDirty then ns.Mirror.MarkAllDirty() end
                end,
            }
        end
    end
    return out
end
