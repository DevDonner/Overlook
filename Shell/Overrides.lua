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
--  * The game's own "Player Minimap Coordinates" option (Options > Interface). It lives in the
--    client, not in any UI file, and the client won't list its CVars, so it's found in the game's
--    settings window by its label and switched through the same setting object as its checkbox.
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

local NOTHING = {}

-- Whether a game option's label is the minimap-coordinates switch ("Player Minimap Coordinates"),
-- not the precision option next to it ("Coordinates in Tenths"). Pure.
function Overrides.IsMinimapCoordLabel(label)
    local l = type(label) == "string" and label:lower() or ""
    if l:find("tenth", 1, true) or l:find("precision", 1, true) or l:find("decimal", 1, true) then return false end
    return l:find("minimap", 1, true) ~= nil and l:find("coord", 1, true) ~= nil
end

-- Calls fn(label, setting) for every option in the game's settings window (Options > Game and
-- AddOns), through the same setting objects its checkboxes use. The client won't list its CVars,
-- so this is how its own options are found: by the label the player sees.
local function EachGameSetting(fn)
    local panel = _G.SettingsPanel
    if not (panel and panel.GetAllCategories and panel.GetLayout) then return end
    local seen = {}
    local function Walk(cat)
        if type(cat) ~= "table" or seen[cat] then return end
        seen[cat] = true
        local okL, layout = pcall(panel.GetLayout, panel, cat)
        local okI, inits = false, nil
        if okL and type(layout) == "table" and layout.GetInitializers then
            okI, inits = pcall(layout.GetInitializers, layout)
        end
        if okI and type(inits) == "table" then
            for _, init in ipairs(inits) do
                local okD, data = pcall(function() return init.GetData and init:GetData() or init.data end)
                local setting = okD and type(data) == "table" and data.setting
                if type(setting) == "table" and setting.GetValue and setting.SetValue then
                    local label = data.name
                    if type(label) ~= "string" and setting.GetName then
                        local okN, n = pcall(setting.GetName, setting)
                        label = okN and n or nil
                    end
                    if type(label) == "string" then fn(label, setting) end
                end
            end
        end
        local okS, subs = pcall(function() return cat:GetSubcategories() end)
        if okS and type(subs) == "table" then
            for _, sub in ipairs(subs) do Walk(sub) end
        end
    end
    local ok, cats = pcall(panel.GetAllCategories, panel)
    if ok and type(cats) == "table" then
        for _, cat in ipairs(cats) do Walk(cat) end
    end
end
Overrides.EachGameSetting = EachGameSetting

-- The game's minimap-coordinates option(s), found once (retried until the window has them).
local gameSettings -- [label] = setting
local nextSearch = 0 -- not found yet: look again at most every SEARCH_EVERY seconds
local SEARCH_EVERY = 10
local function GameCoordSettings()
    if gameSettings then return gameSettings end
    local found = {}
    local now = GetTime()
    if now < nextSearch then return found end
    nextSearch = now + SEARCH_EVERY
    EachGameSetting(function(label, setting)
        if Overrides.IsMinimapCoordLabel(label) then found[label] = setting end
    end)
    if next(found) then gameSettings = found end
    return found
end

-- The game's options as a provider: their current values (on/off ones only), written back
-- through the setting objects after Sync, exactly as clicking the checkbox would.
local gameValues = {}
local function GameOptions()
    for k in pairs(gameValues) do gameValues[k] = nil end
    for label, setting in pairs(GameCoordSettings()) do
        local ok, v = pcall(setting.GetValue, setting)
        if ok and type(v) == "boolean" then gameValues[label] = v end
    end
    return gameValues
end

local function GameMap()
    local map = {}
    for label in pairs(GameCoordSettings()) do map[#map + 1] = { "coords", label, false } end
    return map
end

-- name: the addon's folder (also the prefix of what we remember); settings() -> its settings
-- table or nil; active(settings): whether its feature is on at all; refresh() redraws it.
Overrides.PROVIDERS = {
    {
        name = "game", settings = GameOptions,
        refresh = function()
            for label, setting in pairs(GameCoordSettings()) do
                local v = gameValues[label]
                local ok, now = pcall(setting.GetValue, setting)
                if v ~= nil and ok and now ~= v then pcall(setting.SetValue, setting, v) end
            end
        end,
    },
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
            local map = prov.map or GameMap()
            if Overrides.Sync(s, want, ns.db.overridden, map, prov.name .. ".") then
                pcall(prov.refresh)
            end
        end
    end
end

-- At logout everything we switched off goes back, so the other addons' saved settings and the
-- game's option are always their own: if FarZoomMinimap is ever disabled, nothing stays off.
-- Next login takes them over again.
function Overrides.RestoreAll()
    for _, prov in ipairs(Overrides.PROVIDERS) do
        local s = prov.settings()
        if s and Overrides.Sync(s, NOTHING, ns.db.overridden, prov.map or GameMap(), prov.name .. ".") then
            -- The addons' tables are saved as they are now; the game's option needs its setter.
            if prov.name == "game" then pcall(prov.refresh) end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "PLAYER_LOGOUT" then
        Overrides.RestoreAll()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Other addons finish their own setup around now; once more a moment later to be sure.
        Overrides.Apply()
        C_Timer.After(2, Overrides.Apply)
    elseif pending then
        Overrides.Apply()
    end
end)

ns.RegisterCommand("options", "list the game's own options whose label has this text, e.g. /fzm options coord", function(arg)
    local text = (arg or ""):lower()
    if text == "" then
        ns.Print("usage: /fzm options coord")
        return
    end
    local n = 0
    EachGameSetting(function(label, setting)
        if label:lower():find(text, 1, true) then
            local okV, v = pcall(setting.GetValue, setting)
            local okN, var = pcall(function() return setting.GetVariable and setting:GetVariable() end)
            ns.Printf("  %s = %s  (%s)", label, okV and tostring(v) or "?", okN and tostring(var) or "?")
            n = n + 1
        end
    end)
    ns.Printf("%d option(s) with \"%s\"", n, text)
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
