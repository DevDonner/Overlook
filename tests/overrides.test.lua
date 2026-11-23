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
