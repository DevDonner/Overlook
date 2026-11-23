-- Questie compatibility check. The far map reads parts of Questie that aren't a public API (its
-- private pin registry, tooltip builder, route data and icon table). A Questie update can rename
-- them, and the pcalls elsewhere then just leave things blank. This names what may not work, in
-- one chat line after login, so a blank map isn't a mystery. /fzm questie runs it again.
local _, ns = ...

local QuestieCheck = {}
ns.QuestieCheck = QuestieCheck

local function Import(loader, name)
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then return nil end
    local ok, mod = pcall(loader.ImportModule, loader, name)
    if ok and type(mod) == "table" then return mod end
end

local function Has(mod, fields)
    if not mod then return false end
    for k, kind in pairs(fields) do
        if type(mod[k]) ~= kind then return false end
    end
    return true
end

-- In report order: what stops working, and what it needs from Questie.
local CHECKS = {
    { "Questie icons on the far map", "HBDPins",
        { minimapPins = "table", AddMinimapIconWorld = "function", RemoveMinimapIcon = "function" } },
    { "tooltips on far icons", "MapIconTooltip", { ShowOnTooltip = "function" } },
    { "NPC routes", "QuestieWaypoints", { paths = "table", MinimapAlpha = "function", Color = "function" } },
}

-- What may not work with this Questie, as plain names; empty when everything is found.
function QuestieCheck.Missing(loader, questie)
    local missing = {}
    if type(loader) ~= "table" then
        missing[1] = "Questie"
        return missing
    end
    for _, c in ipairs(CHECKS) do
        if not Has(Import(loader, c[2]), c[3]) then missing[#missing + 1] = c[1] end
    end
    if not (type(questie) == "table" and type(questie.usedIcons) == "table") then
        missing[#missing + 1] = "some icon pictures"
    end
    return missing
end

-- One chat line for Missing's result, or nil when there's nothing to say.
function QuestieCheck.Message(missing)
    if #missing == 0 then return nil end
    if missing[1] == "Questie" then return "Questie isn't loaded, so the far map has no Questie icons." end
    local list = missing[1]
    if #missing > 1 then
        list = table.concat(missing, ", ", 1, #missing - 1) .. " and " .. missing[#missing]
    end
    return "Questie has changed in a way this version doesn't know: " .. list .. " may not work."
end

local function Run(quietWhenFine)
    local msg = QuestieCheck.Message(QuestieCheck.Missing(_G.QuestieLoader, _G.Questie))
    if msg then
        ns.Print(msg)
    elseif not quietWhenFine then
        ns.Print("Questie: every part the far map uses was found.")
    end
end

if not (CreateFrame and C_Timer and ns.RegisterCommand) then return end -- offline tests

ns.RegisterCommand("questie", "check the Questie parts the far map uses", function() Run(false) end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    -- Questie builds some of its tables during its own start-up, after login.
    C_Timer.After(10, function() Run(true) end)
end)
