-- Switching off what our bars replace (Shell/Overrides.lua), and switching it back.
local H = ...

local saved = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local ns = H.loadAddonFile("Shell/Overrides.lua", { RegisterCommand = function() end })
_G.CreateFrame = saved
local O = ns.Overrides

local function DB(over)
    local db = { replaceOthers = true, topBar = true, bottomBar = true, barClock = true, barCoords = true }
    for k, v in pairs(over or {}) do db[k] = v end
    return db
end

H.test("covered: what our bars show, only while replacing is on", function()
    local c = O.Covered(DB())
    H.eq(c.clock, true); H.eq(c.coords, true); H.eq(c.location, true)
    c = O.Covered(DB({ barClock = false, topBar = false }))
    H.eq(c.clock, false); H.eq(c.coords, true); H.eq(c.location, false)
    c = O.Covered(DB({ bottomBar = false }))
    H.eq(c.clock, false); H.eq(c.coords, false)
    c = O.Covered(DB({ replaceOthers = false }))
    H.eq(c.clock, false); H.eq(c.coords, false); H.eq(c.location, false)
end)

H.test("sync: switches EllesmereUI's off and remembers what they were", function()
    local eui = { clockMode = "inside", coordsMode = "always" } -- locationMode unset (legacy)
    local remembered = {}
    H.eq(O.Sync(eui, O.Covered(DB()), remembered, O.EUI, "E."), true)
    H.eq(eui.clockMode, "none"); H.eq(eui.coordsMode, "never"); H.eq(eui.locationMode, "none")
    H.eq(remembered["E.clockMode"], "inside")
    H.eq(O.Sync(eui, O.Covered(DB()), remembered, O.EUI, "E."), false, "nothing more to do")
end)

H.test("sync: our bar off gives theirs back, unset ones unset again", function()
    local eui = { clockMode = "inside", coordsMode = "always" }
    local remembered = {}
    O.Sync(eui, O.Covered(DB()), remembered, O.EUI, "E.")
    O.Sync(eui, O.Covered(DB({ replaceOthers = false })), remembered, O.EUI, "E.")
    H.eq(eui.clockMode, "inside"); H.eq(eui.coordsMode, "always"); H.eq(eui.locationMode, nil)
    H.eq(next(remembered), nil)
end)

H.test("sync: a setting they changed by hand meanwhile is left as they set it", function()
    local eui = { clockMode = "inside" }
    local remembered = {}
    O.Sync(eui, O.Covered(DB()), remembered, O.EUI, "E.")
    eui.clockMode = "edge"
    O.Sync(eui, O.Covered(DB({ barClock = false })), remembered, O.EUI, "E.")
    H.eq(eui.clockMode, "edge")
    H.eq(remembered["E.clockMode"], nil)
end)

H.test("sync: already off isn't remembered as theirs", function()
    local eui = { clockMode = "none", coordsMode = "never", locationMode = "none" }
    local remembered = {}
    H.eq(O.Sync(eui, O.Covered(DB()), remembered, O.EUI, "E."), false)
    H.eq(next(remembered), nil)
    O.Sync(eui, O.Covered(DB({ replaceOthers = false })), remembered, O.EUI, "E.")
    H.eq(eui.clockMode, "none", "stays off: it was off before us")
end)

H.test("EnhanceQoL: time, coordinates, zone and subzone switched off and back", function()
    local eq = { squareMinimapStatsTime = true, squareMinimapStatsCoordinates = true,
        squareMinimapStatsLocation = true, squareMinimapStatsSubzone = true }
    local remembered = {}
    H.eq(O.Sync(eq, O.Covered(DB()), remembered, O.ENHANCE_QOL, "Q."), true)
    for k, v in pairs(eq) do H.eq(v, false, k) end
    O.Sync(eq, {}, remembered, O.ENHANCE_QOL, "Q.")
    for k, v in pairs(eq) do H.eq(v, true, k) end
end)

H.test("game option: found by name, switched to 0 and back", function()
    local names = O.MinimapCoordCVars({ "showMinimapCoordinates", "mapCoordinates", "rotateMinimap",
        "MINIMAPCOORDSTENTHS", "coordinatesInTenths", 7 })
    H.eq(#names, 1, "the tenths option isn't the display switch")
    H.eq(names[1], "showMinimapCoordinates")
    local values, remembered = { showMinimapCoordinates = "1" }, {}
    local map = { { "coords", "showMinimapCoordinates", "0" } }
    O.Sync(values, O.Covered(DB()), remembered, map, "game.")
    H.eq(values.showMinimapCoordinates, "0")
    O.Sync(values, {}, remembered, map, "game.")
    H.eq(values.showMinimapCoordinates, "1")
end)

H.test("every provider covers only what our bars can show", function()
    for _, prov in ipairs(O.PROVIDERS) do
        H.eq(type(prov.settings), "function", prov.name .. " settings")
        H.eq(type(prov.refresh), "function", prov.name .. " refresh")
        for _, spec in ipairs(prov.map or {}) do
            H.truthy(spec[1] == "clock" or spec[1] == "coords" or spec[1] == "location", prov.name)
        end
    end
end)
