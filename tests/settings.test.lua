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
