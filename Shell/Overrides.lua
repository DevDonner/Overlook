-- Turning off what our bars replace. While our bottom bar shows a clock or coordinates, or the top
-- bar shows the zone, the same thing from the game or another minimap addon is switched off, so
-- nothing shows twice. What we switched off is remembered (ns.db.overridden) and switched back on
-- when our bar stops covering it, or when "replaceOthers" is unticked.
--
-- Covered:
--  * EllesmereUIMinimap: its clock, coordinates and location text, through its own settings
--    (clockMode / coordsMode / locationMode) and its own re-apply function.
--  * The game's clock button (TimeManagerClockButton). The game's zone header is the bars' own
--    hideZoneHeader setting.
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

-- EllesmereUI's setting for each, and the value that turns it off.
Overrides.EUI = {
    clock = { "clockMode", "none" },
    coords = { "coordsMode", "never" },
    location = { "locationMode", "none" },
}

local NONE = "<unset>" -- remembered stand-in for a setting that was nil (EllesmereUI's legacy fallback)

-- Brings a settings table in line with what's covered. Returns true if anything changed.
-- saved: where the previous values are remembered, keyed by prefix .. key.
function Overrides.Sync(settings, covered, saved, map, prefix)
    local changed = false
    for what, spec in pairs(map) do
        local key, off = spec[1], spec[2]
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

    local p = EllesmereProfile()
    if p and Overrides.Sync(p, covered, ns.db.overridden, Overrides.EUI, "EllesmereUIMinimap.") then
        local apply = _G._EMM_ApplyMinimap
        if type(apply) == "function" then pcall(apply) end
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
    ns.Printf("%d setting(s) switched off; EllesmereUI minimap %s; game clock %s", n,
        EllesmereProfile() and "found" or "not found", gameClockHidden and "hidden" or "shown")
end)
