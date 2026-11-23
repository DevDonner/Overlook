-- Turning off what our bars replace. While our bottom bar shows a clock or coordinates, or the top
-- bar shows the zone, the same thing from the game or another minimap addon is switched off, so
-- nothing shows twice. What we switched off is remembered (ns.db.overridden) and switched back on
-- when our bar stops covering it, or when "replaceOthers" is unticked.
--
-- Covered (each through its own settings and its own refresh, as if switched off by hand):
--  * EllesmereUIMinimap: clock, coordinates and location text (clockMode / coordsMode /
--    locationMode).
--  * EnhanceQoL's square minimap stats: time, coordinates, zone and subzone.
--  * The game's clock button (TimeManagerClockButton). The game's zone header is the bars' own
--    hideZoneHeader setting.
-- To cover another addon, add an entry to Overrides.PROVIDERS.
local _, ns = ...

local Overrides = {}
ns.Overrides = Overrides

-- What our bars cover now: { clock = bool, coords = bool, location = bool }. Pure, for the tests.
function Overrides.Covered(db)
    local on = db.replaceOthers ~= false
    return {
        clock = on and db.bottomBar and db.barClock or false,
        coords = on and db.bottomBar and db.barCoords or false,
        location = on and db.topBar or false,
    }
end

-- Per addon: { what our bars cover, their setting, the value that turns it off }.
Overrides.EUI = {
    { "clock", "clockMode", "none" },
    { "coords", "coordsMode", "never" },
    { "location", "locationMode", "none" },
}
Overrides.ENHANCE_QOL = {
    { "clock", "squareMinimapStatsTime", false },
    { "coords", "squareMinimapStatsCoordinates", false },
    { "location", "squareMinimapStatsLocation", false },
    { "location", "squareMinimapStatsSubzone", false },
}

local NONE = "<unset>" -- remembered stand-in for a setting that was nil (EllesmereUI's legacy fallback)

-- Brings a settings table in line with what's covered. Returns true if anything changed.
-- saved: where the previous values are remembered, keyed by prefix .. key.
function Overrides.Sync(settings, covered, saved, map, prefix)
    local changed = false
    for _, spec in ipairs(map) do
        local what, key, off = spec[1], spec[2], spec[3]
        local mark = prefix .. key
        if covered[what] then
            if settings[key] ~= off then
                if saved[mark] == nil then
                    local v = settings[key]
                    if v == nil then v = NONE end
                    saved[mark] = v
                end
                settings[key] = off
                changed = true
            end
        elseif saved[mark] ~= nil then
            if settings[key] == off then
                local v = saved[mark]
                if v == NONE then v = nil end
                settings[key] = v
                changed = true
            end
            saved[mark] = nil -- (changed by hand meanwhile: theirs stands)
        end
    end
    return changed
end

----------------------------------------------------------------------------------------------------
-- In game

local function EllesmereProfile()
    local eui = _G.EllesmereUI
    local lite = type(eui) == "table" and eui.Lite
    if not (lite and lite.GetAddon) then return nil end
    local ok, addon = pcall(lite.GetAddon, "EllesmereUIMinimap", true)
    local p = ok and type(addon) == "table" and addon.db and addon.db.profile
    return type(p) == "table" and type(p.minimap) == "table" and p.minimap or nil
end

local function EnhanceQoL()
    local addon = _G.EnhanceQoL
    return type(addon) == "table" and type(addon.db) == "table" and addon.db or nil
end

-- name: the addon's folder (also the prefix of what we remember); settings() -> its settings
-- table or nil; active(settings): whether its feature is on at all; refresh() redraws it.
Overrides.PROVIDERS = {
    {
        name = "EllesmereUIMinimap", map = Overrides.EUI, settings = EllesmereProfile,
        refresh = function() if type(_G._EMM_ApplyMinimap) == "function" then _G._EMM_ApplyMinimap() end end,
    },
    {
        name = "EnhanceQoL", map = Overrides.ENHANCE_QOL, settings = EnhanceQoL,
        active = function(s) return s.enableSquareMinimapStats == true end,
        refresh = function()
            local f = _G.EnhanceQoL.functions
            if f and f.applySquareMinimapStats then f.applySquareMinimapStats(true) end
        end,
    },
}

local NOTHING = {}

local function GameClock(hide)
    local clock = _G.TimeManagerClockButton
    if not clock then return end
    clock:SetAlpha(hide and 0 or 1)
    if clock.EnableMouse then clock:EnableMouse(not hide) end
end

local pending, gameClockHidden = false, false

function Overrides.Apply()
    if InCombatLockdown() then
        pending = true -- other addons' layout code may touch protected frames
        return
    end
    pending = false
    local covered = Overrides.Covered(ns.db)

    if covered.clock ~= gameClockHidden then
        gameClockHidden = covered.clock
        GameClock(covered.clock)
    end

    for _, prov in ipairs(Overrides.PROVIDERS) do
        local s = prov.settings()
        if s then
            -- Feature off in that addon: nothing of it shows, so only give back what we took.
            local want = (not prov.active or prov.active(s)) and covered or NOTHING
            if Overrides.Sync(s, want, ns.db.overridden, prov.map, prov.name .. ".") then
                pcall(prov.refresh)
            end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Other addons finish their own setup around now; once more a moment later to be sure.
        Overrides.Apply()
        C_Timer.After(2, Overrides.Apply)
    elseif pending then
        Overrides.Apply()
    end
end)

ns.RegisterCommand("overrides", "show what the bars switched off in other addons and the game", function()
    local n = 0
    for k, v in pairs(ns.db.overridden) do
        ns.Printf("  %s was %s", k, tostring(v))
        n = n + 1
    end
    local found = {}
    for _, prov in ipairs(Overrides.PROVIDERS) do
        found[#found + 1] = prov.name .. (prov.settings() and " found" or " not loaded")
    end
    ns.Printf("%d setting(s) switched off; %s; game clock %s", n, table.concat(found, ", "),
        gameClockHidden and "hidden" or "shown")
end)
