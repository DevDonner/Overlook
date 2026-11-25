-- Hosting (Core/Host.lua and the hosted path in Shell/Shell.lua): when another addon owns the
-- minimap frame, Overlook fits inside its map instead of taking the frame.
local H = ...

local function noop() end

----------------------------------------------------------------------------------------------------
-- Core/Host.lua

local function LoadHost(db, loaded, eui)
    local kept = { C_AddOns = _G.C_AddOns, EllesmereUI = _G.EllesmereUI }
    _G.C_AddOns = { IsAddOnLoaded = function(n) return loaded and loaded[n] or false end }
    _G.EllesmereUI = eui
    local ns = H.loadAddonFile("Core/Host.lua", { db = db or { size = 300, round = false } })
    return ns.Host, function() for k, v in pairs(kept) do _G[k] = v end end
end

H.test("decide: hosting off, a known minimap addon, one that fought for the frame, or nobody", function()
    local Host, Restore = LoadHost()
    H.eq(Host.Decide(false, "EllesmereUI", true), nil, "switched off: never")
    H.eq(Host.Decide(true, "EllesmereUI", false), "EllesmereUI")
    H.eq(Host.Decide(nil, nil, true), "another addon")
    H.eq(Host.Decide(true, nil, false), nil)
    Restore()
end)

H.test("known: EllesmereUI's minimap while it's loaded and switched on", function()
    local Host, Restore = LoadHost(nil, {})
    H.eq(Host.Known(), nil, "not loaded")
    Restore()
    local profile = { minimap = { enabled = true } }
    local eui = { Lite = { GetAddon = function() return { db = { profile = profile } } end } }
    Host, Restore = LoadHost(nil, { EllesmereUIMinimap = true }, eui)
    H.eq(Host.Known(), "EllesmereUI")
    profile.minimap.enabled = false
    H.eq(Host.Known(), nil, "its minimap module switched off")
    Restore()
end)

H.test("size and shape: ours, or the host's while hosted", function()
    local db = { size = 300, round = false }
    local Host, Restore = LoadHost(db)
    H.eq(Host.Size(), 300); H.eq(Host.IsRound(), false)
    Host.owner, Host.size, Host.round = "EllesmereUI", 180, true
    H.eq(Host.Size(), 180); H.eq(Host.IsRound(), true)
    Host.owner = nil
    db.round = true
    H.eq(Host.Size(), 300); H.eq(Host.IsRound(), true)
    Restore()
end)

----------------------------------------------------------------------------------------------------
-- Shell/Shell.lua on stub frames

local function Obj()
    local o = { points = {}, shown = true, alpha = 1 }
    o.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    o.ClearAllPoints = function(self) self.points = {} end
    o.GetEffectiveScale = function() return 1 end
    o.GetCenter = function() return 500, 400 end
    o.CreateTexture = function() return Obj() end
    o.CreateMaskTexture = function() return Obj() end
    o.SetShown = function(self, v) self.shown = v end
    o.Hide = function(self) self.shown = false end
    o.Show = function(self) self.shown = true end
    o.IsMouseEnabled = function() return false end
    o.SetFrameStrata = function(self, s) self.strata = s end
    o.GetFrameStrata = function(self) return self.strata or "LOW" end
    o.SetBackdropBorderColor = function(self, _, _, _, a) self.edgeAlpha = a end
    return setmetatable(o, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return noop end end })
end

local GLOBALS = { "CreateFrame", "Minimap", "UIParent", "MinimapCluster", "C_Timer", "hooksecurefunc", "GetCVar",
    "SetCVar", "InCombatLockdown", "IsAltKeyDown", "GetMinimapShape", "C_AddOns", "EllesmereUI" }

-- The shell with a stub Minimap. fight: an addon that takes the Minimap back whenever it's
-- parented elsewhere. euiLoaded: EllesmereUI's minimap is loaded. Returns the pieces to check.
local function Shell(opts)
    opts = opts or {}
    local kept = {}
    for _, k in ipairs(GLOBALS) do kept[k] = _G[k] end
    local theirParent = Obj()
    local minimap = Obj()
    minimap.parent, minimap.width, minimap.scale, minimap.setParents = theirParent, 140, 1, 0
    minimap.GetParent = function(self) return self.parent end
    minimap.SetParent = function(self, p)
        self.setParents = self.setParents + 1
        self.parent = opts.fight and theirParent or p
    end
    minimap.GetWidth = function(self) return self.width end
    minimap.SetScale = function(self, s) self.scale = s end
    minimap.GetHitRectInsets = function() return 0, 0, opts.crop or 0, opts.crop or 0 end
    minimap.HookScript = function(self, _, f) self.onSize = f end
    minimap.ZoomIn, minimap.ZoomOut, minimap.ZoomHitArea = false, false, false
    local made = {}
    local theirShape = function() return opts.theirShape or "SQUARE" end
    local tickers = {}
    local G = {
        CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end,
        Minimap = minimap, UIParent = Obj(), MinimapCluster = Obj(),
        C_Timer = { NewTicker = function(_, f) tickers[#tickers + 1] = f end, After = noop },
        hooksecurefunc = noop, GetCVar = function() return "0" end, SetCVar = noop,
        InCombatLockdown = function() return false end, IsAltKeyDown = function() return false end,
        GetMinimapShape = theirShape,
        C_AddOns = { IsAddOnLoaded = function(n) return opts.euiLoaded and n == "EllesmereUIMinimap" end },
        EllesmereUI = false,
    }
    for k, v in pairs(G) do _G[k] = v end
    local ns = { RegisterCommand = noop, Print = noop, Printf = noop, name = "Overlook" }
    H.loadAddonFile("Core/Settings.lua", ns)
    H.loadAddonFile("Core/Host.lua", ns)
    ns.db = ns.Settings.Load(opts.saved)
    H.loadAddonFile("Shell/Shell.lua", ns)
    ns.Shell.Build()
    local function Restore() for _, k in ipairs(GLOBALS) do _G[k] = kept[k] end end
    return { ns = ns, minimap = minimap, root = ns.Shell.root, theirShape = theirShape,
        theirParent = theirParent, tickers = tickers, Restore = Restore }
end

local function Anchored(frame, to)
    for _, p in ipairs(frame.points) do
        if p[2] == to then return true end
    end
    return false
end

H.test("shell: alone, Overlook takes the map and answers its shape", function()
    local s = Shell()
    H.eq(s.ns.Host.owner, nil)
    H.eq(s.minimap.parent, s.root, "the Minimap is in our frame")
    H.eq(_G.GetMinimapShape, s.ns.Shell.MinimapShape)
    H.eq(s.minimap.scale, 300 / 140, "scaled to our size")
    s.Restore()
end)

H.test("shell: with claimShape off, another addon's shape answer stands", function()
    local s = Shell({ saved = { claimShape = false } })
    H.eq(_G.GetMinimapShape, s.theirShape)
    s.ns.db.claimShape = true
    s.ns.Shell.Apply()
    H.eq(_G.GetMinimapShape, s.ns.Shell.MinimapShape)
    s.ns.db.claimShape = false
    s.ns.Shell.Apply()
    H.eq(_G.GetMinimapShape, s.theirShape, "given back")
    s.Restore()
end)

H.test("shell: an addon that takes the Minimap back is left to host it", function()
    local s = Shell({ fight = true })
    H.eq(s.ns.Host.owner, "another addon")
    H.eq(s.minimap.parent, s.theirParent)
    H.truthy(Anchored(s.root, s.minimap), "our frame lies over their map")
    H.eq(s.ns.Host.Size(), 140, "the far map is their map's size")
    H.eq(_G.GetMinimapShape, s.theirShape, "their shape answer, not ours")
    local before = s.minimap.setParents
    s.ns.Shell.Apply()
    H.eq(s.minimap.setParents, before, "no more tug of war")
    s.Restore()
end)

H.test("shell: EllesmereUI's minimap hosts from the start; the frame is never touched", function()
    local s = Shell({ euiLoaded = true, theirShape = "ROUND" })
    H.eq(s.ns.Host.owner, "EllesmereUI")
    H.eq(s.minimap.setParents, 0, "never parented")
    H.eq(s.minimap.scale, 1, "never scaled")
    H.eq(s.ns.Host.IsRound(), true, "their round map")
    H.truthy(Anchored(s.root, s.minimap))
    s.Restore()
end)

H.test("shell: a host that crops its map to a rectangle: our frame leaves the cropped part out", function()
    local s = Shell({ euiLoaded = true, crop = 20 })
    local top, bottom
    for _, p in ipairs(s.root.points) do
        if p[1] == "TOPLEFT" then top = p[5] end
        if p[1] == "BOTTOMRIGHT" then bottom = p[5] end
    end
    H.eq(top, -20); H.eq(bottom, 20)
    s.Restore()
end)

H.test("shell: hosting switched off takes the map back from EllesmereUI", function()
    local s = Shell({ euiLoaded = true })
    s.ns.Shell.SetHostOthers(false)
    H.eq(s.ns.Host.owner, nil)
    H.eq(s.minimap.parent, s.root)
    s.ns.Shell.SetHostOthers(true)
    H.eq(s.ns.Host.owner, "EllesmereUI")
    s.Restore()
end)

H.test("shell: the host resizing its map is followed", function()
    local s = Shell({ euiLoaded = true })
    s.minimap.width = 200
    s.ns.Shell.Watch()
    H.eq(s.ns.Host.Size(), 200)
    s.Restore()
end)

H.test("shell: an addon that takes the Minimap later is noticed by the watch", function()
    local s = Shell()
    H.eq(s.ns.Host.owner, nil)
    s.minimap.parent = s.theirParent -- e.g. a deferred reparent after login
    s.ns.Shell.Watch()
    H.eq(s.ns.Host.owner, "another addon")
    s.Restore()
end)

H.test("shell: the shape is answered only for our own map, and only when allowed", function()
    local s = Shell({ euiLoaded = true })
    local W = s.ns.Shell.WantShape
    H.eq(W(true, false), true); H.eq(W(false, false), false); H.eq(W(true, true), false)
    s.Restore()
end)
