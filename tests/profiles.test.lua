-- Settings profiles and export strings (Core/Profiles.lua).
local H = ...

local ns, P, db
local function Fresh()
    ns = {}
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/IconPrefs.lua", ns)
    H.loadAddonFile("Core/Profiles.lua", ns)
    P = ns.Profiles
    db = P.Init(ns.Settings.Load({ size = 300, x = 10, y = 20, icons = { ["questie:monster"] = { hide = true } } }))
end
H.beforeEach(Fresh)

H.test("init: the settings from before profiles become the Default profile", function()
    H.eq(db.profile, "Default")
    H.eq(db.profiles.Default.size, 300)
    H.eq(db.profiles.Default.icons["questie:monster"].hide, true)
    H.eq(db.profiles.Default.x, nil, "the position isn't part of a profile")
end)

H.test("init: a damaged profile table is repaired", function()
    local d = P.Init(ns.Settings.Load({ profiles = { Default = 5, Raid = {} }, profile = "Gone" }))
    H.eq(d.profiles.Default, nil)
    H.eq(d.profile, "Raid")
end)

H.test("new, switch and back: each profile keeps its own settings, edited in place", function()
    local live = db
    H.truthy(P.New(db, "  Raid  "))
    H.eq(db.profile, "Raid", "trimmed, and switched to")
    db.size = 500
    db.icons["questie:monster"].hide = false
    H.truthy(P.Switch(db, "Default"))
    H.eq(db, live, "the same table")
    H.eq(db.size, 300)
    H.eq(db.icons["questie:monster"].hide, true)
    H.eq(db.x, 10, "the position stays")
    P.Switch(db, "Raid")
    H.eq(db.size, 500)
    H.eq(db.icons["questie:monster"].hide, false)
end)

H.test("names: empty, duplicate and odd characters", function()
    H.eq(P.New(db, "   "), nil)
    H.eq(P.New(db, "Default"), nil)
    H.truthy(P.New(db, "a|cffff0000b"))
    H.eq(db.profile, "acffff0000b", "no escape codes in names")
    H.truthy(#P.CleanName(string.rep("x", 100)) == P.MAX_NAME)
end)

H.test("delete: not the one in use", function()
    P.New(db, "Raid")
    H.eq(P.Delete(db, "Raid"), nil)
    P.Switch(db, "Default")
    H.truthy(P.Delete(db, "Raid"))
    H.eq(#P.List(db), 1)
end)

H.test("reset: the current profile back to the defaults, icon groups too", function()
    P.Reset(db)
    H.eq(db.size, ns.Settings.DEFAULTS.size)
    H.eq(next(db.icons), nil)
    H.eq(db.profiles.Default.size, ns.Settings.DEFAULTS.size)
end)

H.test("base64 round trip, all padding lengths", function()
    for _, s in ipairs({ "", "a", "ab", "abc", "abcd", "{\"x\"=T;}", string.char(0, 255, 128) }) do
        H.eq(P.FromBase64(P.ToBase64(s)), s)
    end
    H.eq(P.ToBase64("Man"), "TWFu")
    H.eq(P.ToBase64("Ma"), "TWE=")
    H.eq(P.FromBase64("not base64!"), nil)
end)

H.test("serialize round trip", function()
    local t = { a = true, b = false, n = -1.25, s = 'q"uo\te', t = { x = { y = 3 } } }
    local back = P.Deserialize(P.Serialize(t))
    H.eq(back.a, true); H.eq(back.b, false); H.eq(back.n, -1.25)
    H.eq(back.s, 'q"uo\te'); H.eq(back.t.x.y, 3)
end)

H.test("deserialize refuses anything malformed or too deep", function()
    for _, s in ipairs({ "", "{", "{\"a\"=T}", "{a=T;}", "{\"a\"=os.exit();}", "T extra", "{\"a\"={\"b\"={\"c\"={\"d\"={\"e\"=T;};};};};}" }) do
        H.eq(P.Deserialize(s), nil, s)
    end
end)

H.test("export and import: the same settings come back as a new profile", function()
    db.arrowScale = 1.5
    local text = P.Export(db)
    H.truthy(text:sub(1, 5) == "FZM1:")
    db.arrowScale = 1
    local ok, name = P.Import(db, "  " .. text .. "\n", "")
    H.truthy(ok)
    H.eq(name, "Imported")
    H.eq(db.profile, "Imported")
    H.eq(db.arrowScale, 1.5)
    H.eq(db.size, 300)
    H.eq(db.icons["questie:monster"].hide, true)
    local _, again = P.Import(db, text, "Imported")
    H.eq(again, "Imported 2", "never overwrites")
end)

H.test("import: values are checked and clamped, unknown keys dropped", function()
    local evil = { size = 99999, arrowScale = "big", locked = 1, x = 5, nativeOff = { "x" }, unknown = true,
        icons = { tomtom = { scale = 50, hide = "yes" }, [1] = { hide = true } } }
    local snap = P.Decode("FZM1:" .. P.ToBase64(P.Serialize(evil)))
    H.eq(snap.size, ns.Settings.SIZE_MAX)
    H.eq(snap.arrowScale, 1, "wrong type: default")
    H.eq(snap.locked, false)
    H.eq(snap.x, nil); H.eq(snap.nativeOff, nil); H.eq(snap.unknown, nil)
    H.eq(snap.icons.tomtom.scale, ns.IconPrefs.SCALE_MAX)
    H.eq(snap.icons.tomtom.hide, nil)
end)

H.test("import: friendly errors", function()
    H.eq(select(2, P.Import(db, "hello", "x")), "that isn't a FarZoomMinimap profile string")
    H.eq(select(2, P.Import(db, "FZM1:abc", "x")), "that profile string is damaged (copied in full?)")
    H.eq(#P.List(db), 1, "nothing added")
end)
