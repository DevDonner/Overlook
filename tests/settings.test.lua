-- U9 (defaults) and U12 (loading saved settings).
local H = ...
local Settings = H.loadAddonFile("Core/Settings.lua", {}).Settings

H.test("U9 defaults: clustering off, rotation off, max far zoom 3,000 yd, size 300", function()
    local db = Settings.Load(nil)
    H.eq(db.clustering, false, "clustering")
    H.eq(db.rotate, false, "rotate")
    H.eq(db.maxFarZoom, 3000, "maxFarZoom")
    H.eq(db.locked, false, "locked")
    H.eq(db.size, 300, "size")
    H.eq(db.x, nil, "x unset until first login")
end)

H.test("saved values are kept and the same table is returned", function()
    local saved = { size = 300, rotate = true, x = 10, y = -20 }
    local db = Settings.Load(saved)
    H.truthy(db == saved, "should reuse the saved table")
    H.eq(db.size, 300)
    H.eq(db.rotate, true)
    H.eq(db.x, 10)
    H.eq(db.clustering, false, "missing keys get defaults")
    H.eq(db.version, Settings.VERSION)
end)

H.test("size is clamped and rounded", function()
    H.eq(Settings.Load({ size = 50 }).size, 120)
    H.eq(Settings.Load({ size = 9999 }).size, 800)
    H.eq(Settings.Load({ size = 250.6 }).size, 251)
    H.eq(Settings.Load({ size = "junk" }).size, 300)
end)

H.test("a half-saved position is dropped", function()
    local db = Settings.Load({ x = 5 })
    H.eq(db.x, nil)
    H.eq(db.y, nil)
end)

H.test("garbage saved data falls back to defaults", function()
    H.eq(Settings.Load("nonsense").size, 300)
end)

H.test("max far zoom is clamped to 500-6,400 yd; smooth zoom on by default", function()
    H.eq(Settings.Load({ maxFarZoom = 100 }).maxFarZoom, 500)
    H.eq(Settings.Load({ maxFarZoom = 5000 }).maxFarZoom, 5000)
    H.eq(Settings.Load({ maxFarZoom = 9000 }).maxFarZoom, 6400)
    H.eq(Settings.Load({ maxFarZoom = "x" }).maxFarZoom, 3000)
    H.eq(Settings.Load(nil).smoothZoom, true)
    H.eq(Settings.Load(nil).routes, true)
    H.eq(Settings.Load(nil).partyDots, true)
    H.eq(Settings.Load(nil).nativeIcons, false)
    H.eq(type(Settings.Load(nil).nativeOff), "table")
    H.eq(type(Settings.Load(nil).minimapButton), "table")
    H.truthy(Settings.Load(nil).minimapButton ~= Settings.Load(nil).minimapButton, "not a shared table")
end)

H.test("arrow size, route width and route opacity: defaults and clamping", function()
    local db = Settings.Load(nil)
    H.eq(db.arrowScale, 1); H.eq(db.routeWidth, 1.5); H.eq(db.routeAlpha, 1)
    H.eq(Settings.Load({ arrowScale = 9 }).arrowScale, 2)
    H.eq(Settings.Load({ arrowScale = 0 }).arrowScale, 0.4)
    H.eq(Settings.Load({ routeWidth = 0.1 }).routeWidth, 0.5)
    H.eq(Settings.Load({ routeWidth = "x" }).routeWidth, 1.5)
    H.eq(Settings.Load({ routeAlpha = 2 }).routeAlpha, 1)
end)

H.test("every numeric setting has a default inside its range", function()
    for k, r in pairs(Settings.RANGES) do
        local d = Settings.DEFAULTS[k]
        H.truthy(type(d) == "number" and d >= r[1] and d <= r[2], k)
    end
end)

H.test("v3's bright quest-area defaults move to the new ones; a chosen value stays", function()
    local db = Settings.Load({ version = 3, questAreaFill = 0.5, questAreaBorder = 0.75 })
    H.eq(db.questAreaFill, 0.15); H.eq(db.questAreaBorder, 0.2)
    db = Settings.Load({ version = 3, questAreaFill = 0.4 })
    H.eq(db.questAreaFill, 0.4)
end)

----------------------------------------------------------------------------------------------------
-- Layout and living with other addons

H.test("defaults: buttons on the bars, every takeover can be switched off but starts on", function()
    local db = Settings.Load(nil)
    H.eq(db.buttonSpot, "bars"); H.eq(db.buttonSide, "left")
    H.eq(db.hostOthers, true); H.eq(db.claimShape, true)
    H.eq(db.keepOthersVisible, true); H.eq(db.captureOthers, true)
    H.eq(db.replaceOthers, true); H.eq(db.collectButtons, true)
end)

H.test("choices: a word that isn't one of the choices goes back to the default", function()
    local db = Settings.Load({ buttonSpot = "floating", buttonSide = 3 })
    H.eq(db.buttonSpot, "bars"); H.eq(db.buttonSide, "left")
    db = Settings.Load({ buttonSpot = "none", buttonSide = "right" })
    H.eq(db.buttonSpot, "none"); H.eq(db.buttonSide, "right")
end)

H.test("switched-off takeovers stay off after a reload", function()
    local db = Settings.Load({ hostOthers = false, claimShape = false, keepOthersVisible = false,
        captureOthers = false, collectButtons = false, replaceOthers = false })
    H.eq(db.hostOthers, false); H.eq(db.claimShape, false); H.eq(db.keepOthersVisible, false)
    H.eq(db.captureOthers, false); H.eq(db.collectButtons, false); H.eq(db.replaceOthers, false)
end)

H.test("presets: compact puts the name over the map and the buttons at its side", function()
    local db = Settings.Load(nil)
    H.eq(Settings.CurrentPreset(db), "full", "the defaults are the full layout")
    H.eq(Settings.ApplyPreset(db, "compact"), true)
    H.eq(db.topBar, true); H.eq(db.topBarInside, true); H.eq(db.bottomBar, false); H.eq(db.buttonSpot, "side")
    H.eq(Settings.CurrentPreset(db), "compact")
    H.eq(db.size, 300, "the size is the player's own")
end)

H.test("presets: map only turns off every bar and button", function()
    local db = Settings.Load(nil)
    Settings.ApplyPreset(db, "maponly")
    H.eq(db.topBar, false); H.eq(db.bottomBar, false); H.eq(db.buttonSpot, "none")
    H.eq(Settings.CurrentPreset(db), "maponly")
    Settings.ApplyPreset(db, "full")
    H.eq(db.topBar, true); H.eq(db.bottomBar, true); H.eq(db.buttonSpot, "bars")
end)

H.test("presets: an unknown name changes nothing; a mix is no preset", function()
    local db = Settings.Load(nil)
    H.eq(Settings.ApplyPreset(db, "tiny"), false)
    H.eq(Settings.CurrentPreset(db), "full")
    db.bottomBar = false
    H.eq(Settings.CurrentPreset(db), nil)
end)

H.test("bar places: above or below, on the map, or off, over each bar's two settings", function()
    local db = Settings.Load(nil)
    H.eq(Settings.BarPlace(db, "top"), "outside")
    Settings.SetBarPlace(db, "top", "inside")
    H.eq(db.topBar, true); H.eq(db.topBarInside, true)
    H.eq(Settings.BarPlace(db, "top"), "inside")
    Settings.SetBarPlace(db, "bottom", "off")
    H.eq(db.bottomBar, false); H.eq(Settings.BarPlace(db, "bottom"), "off")
    Settings.SetBarPlace(db, "bottom", "outside")
    H.eq(db.bottomBar, true); H.eq(db.bottomBarInside, false)
end)

H.test("button column: on the map by default; only inside or outside", function()
    H.eq(Settings.Load(nil).buttonColumn, "inside")
    H.eq(Settings.Load({ buttonColumn = "outside" }).buttonColumn, "outside")
    H.eq(Settings.Load({ buttonColumn = "floating" }).buttonColumn, "inside")
end)
