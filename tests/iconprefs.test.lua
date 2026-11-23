-- Per-category icon preferences and the zoom shrink curve.
local H = ...
local ns = H.loadAddonFile("Core/IconPrefs.lua", {})
H.loadAddonFile("Core/Zoom.lua", ns)
local P, Zoom = ns.IconPrefs, ns.Zoom

H.test("defaults: Questie icons fixed size, other addons shrink with zoom", function()
    local hide, scale, shrink = P.Get({}, "questie:available")
    H.eq(hide, false); H.eq(scale, 1); H.eq(shrink, false)
    hide, scale, shrink = P.Get({}, "questie:monster")
    H.eq(hide, false); H.eq(scale, 1.15); H.eq(shrink, false)
    hide, scale, shrink = P.Get({}, "questie:item")
    H.eq(hide, false); H.eq(scale, 2); H.eq(shrink, true)
    hide, scale, shrink = P.Get({}, "rarescanner")
    H.eq(hide, false); H.eq(scale, 1); H.eq(shrink, true)
end)

H.test("names: all, questie, a Questie type, an addon", function()
    local known = { rarescanner = true, tomtom = true }
    H.eq(#P.Match("questie", known), #P.QUESTIE_TYPES)
    H.eq(#P.Match("all", known), #P.QUESTIE_TYPES + 2)
    H.eq(P.Match("monster", known)[1], "questie:monster")
    H.eq(P.Match("RareScanner", known)[1], "rarescanner")
    H.eq(#P.Match("nothing", known), 0)
end)

H.test("apply: hide, size (clamped), shrink, reset", function()
    local db = {}
    local known = { rarescanner = true }
    H.truthy(P.Apply(db, "rarescanner", known, "size", "0.5"))
    H.truthy(P.Apply(db, "rarescanner", known, "shrink", "off"))
    H.truthy(P.Apply(db, "rarescanner", known, "hide"))
    local hide, scale, shrink = P.Get(db, "rarescanner")
    H.eq(hide, true); H.eq(scale, 0.5); H.eq(shrink, false)
    P.Apply(db, "rarescanner", known, "size", "99")
    H.eq(select(2, P.Get(db, "rarescanner")), 3, "clamped")
    P.Apply(db, "rarescanner", known, "reset")
    hide, scale, shrink = P.Get(db, "rarescanner")
    H.eq(hide, false); H.eq(scale, 1); H.eq(shrink, true)
end)

H.test("apply: bad input is refused with a message", function()
    local keys, err = P.Apply({}, "nothing", {}, "hide")
    H.eq(keys, nil); H.truthy(err)
    keys, err = P.Apply({}, "monster", {}, "size", "big")
    H.eq(keys, nil); H.truthy(err)
    keys, err = P.Apply({}, "monster", {}, "explode")
    H.eq(keys, nil); H.truthy(err)
end)

H.test("zoom shrink: 1 at native, square-root falloff, floored", function()
    local native = 700 / 3
    H.eq(Zoom.Shrink(native, native), 1)
    H.near(Zoom.Shrink(native * 4, native), 0.5, 1e-9)
    H.eq(Zoom.Shrink(native * 100, native), Zoom.SHRINK_MIN)
end)
