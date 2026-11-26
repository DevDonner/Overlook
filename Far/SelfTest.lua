-- /overlook selftest: checks the far map in the real game, with whatever addons are installed.
--
-- Offline tests only know the world they're told about; the white box from 1.1.0 came from an
-- addon they'd never heard of. This runs in the client instead: it zooms the far map out through
-- a few levels, lists everything actually drawn on it at each one (which part of Overlook drew it,
-- its file, size and place), checks rules that hold whatever addons are loaded, and saves a
-- report to the saved variables (OverlookDB.selftest; written to disk on /reload or logout).
--
-- The rules (SelfTest.Check, pure, covered offline):
--  * fill:   no plain colour box (WHITE8X8, a colour texture) from anything that should be a picture.
--  * player: nothing big sits on the player except the map itself.
--  * scale:  nothing big stays the same size while the zoom changes (the far map's things scale).
--  * tiles:  every terrain tile is the size the zoom says.
--  * world:  with "no limit" at its furthest, both continents' tiles are drawn.
-- And notes (not failures): things in the far view that aren't Overlook's, tiles still loading.
local _, ns = ...

local SelfTest = {}
ns.SelfTest = SelfTest

local BIG = 0.12        -- "big": wider and taller than this part of the view (a box, not a line)
local SETTLE_FRAMES, SETTLE_SECONDS, GIVE_UP = 10, 0.4, 8

local FILLS = { "white8x8", "chatframebackground", "ui%-tooltip%-background", "^solid" }
-- Parts that are plain colour on purpose, may cover the player, or keep their size.
local MAY_FILL = { background = true, ["cave cover"] = true, ping = true, route = true, ["quest area"] = true }
local MAY_COVER = { tile = true, ["map art"] = true, cave = true, ["cave cover"] = true, background = true,
    ["quest area"] = true, arrow = true }
local FIXED = { background = true, ["cave cover"] = true, arrow = true }

----------------------------------------------------------------------------------------------------
-- Pure parts

-- Whether a texture is a plain fill: no picture of its own (a colour texture), or a solid file.
function SelfTest.IsFill(item)
    if item.kind ~= "Texture" or item.atlas then return false end
    if item.file == nil or item.file == "nil" then return true end
    local l = tostring(item.file):lower()
    for _, p in ipairs(FILLS) do
        if l:find(p) then return true end
    end
    return false
end

local function Describe(it)
    return string.format("%s %s %.0fx%.0f px at %.0f,%.0f%s%s", it.part, tostring(it.atlas or it.file),
        it.w, it.h, it.x, it.y, it.from and (" from " .. it.from) or "", it.frame and (" in " .. it.frame) or "")
end
SelfTest.Describe = Describe

-- Checks snapshots of the far map. snaps: list of { radius, size (view px), ppy, loading,
-- items = { { id, part, kind, file, atlas, w, h, x, y, from, inst, frame } } }. opts: { tile
-- (yards), world (no limit on), reach (its zoom), continents (list of instances) }.
-- Returns problems, notes: lists of { rule, text }.
function SelfTest.Check(snaps, opts)
    opts = opts or {}
    local problems, notes, said = {}, {}, {}
    local function Add(list, rule, key, text)
        if said[rule .. key] then return end
        said[rule .. key] = true
        list[#list + 1] = { rule = rule, text = text }
    end
    local seen = {} -- [id] = { radius, w, h } at the first snapshot it was in

    for _, snap in ipairs(snaps) do
        local big = BIG * snap.size
        local ax, ay = 0, 0
        for _, it in ipairs(snap.items) do
            if it.part == "arrow" then ax, ay = it.x, it.y end
        end
        local badTiles, firstBad = 0, nil
        local insts = {}
        for _, it in ipairs(snap.items) do
            local key = tostring(it.id)
            if SelfTest.IsFill(it) and not MAY_FILL[it.part] and it.w > 6 and it.h > 6 then
                Add(problems, "fill", key, "a plain colour box: " .. Describe(it))
            end
            if not MAY_COVER[it.part] and math.abs(it.x - ax) <= 8 and math.abs(it.y - ay) <= 8
                and (it.w > big and it.h > big) then
                Add(problems, "player", key, "something big on the player: " .. Describe(it))
            end
            if it.part == "tile" then
                insts[it.inst or "?"] = true
                if opts.tile and snap.ppy then
                    local want = opts.tile * snap.ppy
                    if math.abs(it.w - want) > want * 0.03 + 0.5 then
                        badTiles = badTiles + 1
                        firstBad = firstBad or it
                    end
                end
            end
            if it.part == "unlabelled" then
                Add(notes, "foreign", key, "not Overlook's, drawn in the far view: " .. Describe(it))
            end
            local was = seen[it.id]
            if not was then
                seen[it.id] = { radius = snap.radius, w = it.w, h = it.h }
            elseif not FIXED[it.part] and snap.radius >= was.radius * 2 and (it.w > big and it.h > big)
                and math.abs(it.w - was.w) <= was.w * 0.05 and math.abs(it.h - was.h) <= was.h * 0.05 then
                Add(problems, "scale", key, string.format("stays %.0fx%.0f px from %.0f to %.0f yd: %s",
                    it.w, it.h, was.radius, snap.radius, Describe(it)))
            end
        end
        if badTiles > 0 then
            Add(problems, "tiles", tostring(snap.radius), string.format("%d tile(s) the wrong size at %.0f yd (want %.1f px): %s",
                badTiles, snap.radius, opts.tile * snap.ppy, Describe(firstBad)))
        end
        if snap.loading then
            Add(notes, "loading", tostring(snap.radius), string.format("tiles still loading after %.1f s at %.0f yd",
                snap.seconds or 0, snap.radius))
        end
        if opts.world and opts.reach and snap.radius >= opts.reach * 0.99 then
            for _, inst in ipairs(opts.continents or {}) do
                if not insts[inst] then
                    Add(problems, "world", tostring(inst), string.format("continent %s has no tiles at the furthest zoom", tostring(inst)))
                end
            end
        end
    end
    return problems, notes
end

-- A snapshot made small enough to save: per part, how many and how big; and in full only what's
-- worth reading (other addons' copies, things that aren't ours, big things that aren't map).
function SelfTest.Summarise(snap)
    local parts, notable = {}, {}
    local big = BIG * snap.size
    for _, it in ipairs(snap.items) do
        local p = parts[it.part]
        if not p then
            p = { count = 0, wMin = it.w, wMax = it.w, files = {} }
            parts[it.part] = p
        end
        p.count = p.count + 1
        p.wMin, p.wMax = math.min(p.wMin, it.w), math.max(p.wMax, it.w)
        if #p.files < 4 then
            local f = tostring(it.atlas or it.file)
            local dup = false
            for _, x in ipairs(p.files) do if x == f then dup = true end end
            if not dup then p.files[#p.files + 1] = f end
        end
        if #notable < 60 and (it.part == "copy" or it.part == "unlabelled"
            or ((it.w > big and it.h > big) and not MAY_COVER[it.part])) then
            notable[#notable + 1] = Describe(it)
        end
    end
    return { radius = snap.radius, ppy = snap.ppy, seconds = snap.seconds, loading = snap.loading,
        fps = snap.fps, parts = parts, notable = notable }
end

-- The zoom levels to check: a little past the native map, a zone, the setting, and with "no
-- limit" the whole world. Ascending, each at least 1.5 times the last.
function SelfTest.Steps(native, maxFar, maxZoom)
    local want = { native * 1.6, 1500, maxFar, maxZoom }
    table.sort(want)
    local out = {}
    for _, r in ipairs(want) do
        if r > native * 1.1 and r <= maxZoom and (#out == 0 or r >= out[#out] * 1.5) then out[#out + 1] = r end
    end
    if out[#out] ~= maxZoom and maxZoom > native * 1.1 then out[#out + 1] = maxZoom end
    return out
end

----------------------------------------------------------------------------------------------------
-- In game

-- Everything shown in the far view: textures and lines, with the part of Overlook that drew them.
local function Walk(view)
    local vx, vy = view:GetCenter()
    local vw, vh = view:GetSize()
    local vs = view:GetEffectiveScale()
    local items = {}
    local function Name(f)
        local ok, n = pcall(f.GetName, f)
        return ok and n or nil
    end
    local function Visit(frame, part, depth)
        if depth > 8 or not frame:IsVisible() then return end
        part = frame.overlookPart or part
        local frameName = Name(frame)
        for _, r in ipairs({ frame:GetRegions() }) do
            local okT, kind = pcall(r.GetObjectType, r)
            if okT and (kind == "Texture" or kind == "Line") and r:IsVisible() and (r:GetAlpha() or 1) > 0.01 then
                local okC, x, y = pcall(r.GetCenter, r)
                local okS, w, h = pcall(r.GetSize, r)
                if okC and x and okS and w then
                    local k = r:GetEffectiveScale() / vs
                    x, y, w, h = x * k - vx, y * k - vy, w * k, h * k
                    if math.abs(x) - w / 2 < vw / 2 and math.abs(y) - h / 2 < vh / 2 then
                        local file = r.GetTextureFilePath and r:GetTextureFilePath()
                        if file == nil and r.GetTexture then file = r:GetTexture() end
                        items[#items + 1] = {
                            id = r, part = r.overlookPart or part or "unlabelled", kind = kind,
                            file = file, atlas = r.GetAtlas and r:GetAtlas() or nil,
                            w = w, h = h, x = x, y = y, from = r.overlookFrom, inst = r.overlookInst,
                            frame = frameName,
                        }
                    end
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do Visit(child, part, depth + 1) end
    end
    Visit(view, nil, 0)
    return items, vw
end

local function LoadedAddons()
    local out, api = {}, _G.C_AddOns
    if not (api and api.GetNumAddOns) then return out end
    for i = 1, api.GetNumAddOns() do
        local ok, name = pcall(api.GetAddOnInfo, i)
        if ok and name and (not api.IsAddOnLoaded or api.IsAddOnLoaded(name)) then out[#out + 1] = name end
    end
    return out
end

local function Memory()
    local ok = pcall(UpdateAddOnMemoryUsage)
    if not ok then return nil end
    local okM, kb = pcall(GetAddOnMemoryUsage, ns.name)
    return okM and kb or nil
end

local running, driver

local function Finish(state, aborted)
    running = nil
    state.driver:SetScript("OnUpdate", nil)
    ns.db.smoothZoom = state.smooth
    if ns.Far.IsActive() then ns.Far.Recenter() end
    if aborted then
        ns.Print("self-test stopped: " .. aborted)
        return
    end

    local world = ns.db.worldZoom and ns.World ~= nil
    local continents = {}
    if world then
        continents[1] = state.instance
        for _, other in ipairs(ns.World.Neighbours(state.instance)) do continents[#continents + 1] = other.inst end
    end
    local problems, notes = SelfTest.Check(state.snaps, {
        tile = ns.Geometry.TILE_YARDS, world = world, reach = state.maxZoom, continents = continents,
    })
    local steps = {}
    for _, snap in ipairs(state.snaps) do steps[#steps + 1] = SelfTest.Summarise(snap) end
    local okB, build, buildNum = pcall(GetBuildInfo)
    local api = _G.C_AddOns
    local version = api and api.GetAddOnMetadata and api.GetAddOnMetadata(ns.name, "Version")
    ns.db.selftest = {
        when = date("%Y-%m-%d %H:%M:%S"),
        overlook = version or "?",
        client = okB and (tostring(build) .. " " .. tostring(buildNum)) or "?",
        where = { instance = state.instance, zone = GetRealZoneText(), subzone = GetSubZoneText(),
            indoors = IsIndoors() and true or false },
        map = { size = ns.Host.Size(), round = ns.Host.IsRound(), hosted = ns.Host.owner,
            maxFarZoom = ns.db.maxFarZoom, worldZoom = ns.db.worldZoom == true },
        memoryKB = { before = state.memory, after = Memory() },
        problems = problems, notes = notes, steps = steps,
        others = ns.Others and ns.Others.Report and ns.Others.Report() or nil,
        addons = LoadedAddons(),
    }

    local color = #problems == 0 and "|cff55ff55" or "|cffff5555"
    ns.Printf("self-test: %s%d problem(s)|r and %d note(s) over %d zoom levels.", color, #problems, #notes, #state.snaps)
    for i = 1, math.min(#problems, 6) do ns.Print("  |cffff5555" .. problems[i].rule .. "|r " .. problems[i].text) end
    for i = 1, math.min(#notes, 3) do ns.Print("  " .. notes[i].rule .. ": " .. notes[i].text) end
    ns.Print("The report is saved on /reload (or logout), in the saved variables (OverlookDB.selftest).")
end

local function Snapshot(state, seconds)
    local view = ns.Far.View()
    local items, size = Walk(view)
    local r = state.steps[state.i]
    state.snaps[#state.snaps + 1] = {
        radius = r, size = size, ppy = ns.Host.Size() / 2 / r, items = items,
        loading = ns.Far.Loading() and true or false, seconds = seconds, fps = GetFramerate(),
    }
end

function SelfTest.Run()
    if running then
        ns.Print("the self-test is already running.")
        return
    end
    local Far = ns.Far
    if not (Far and Far.View and Far.View()) then
        ns.Print("self-test: the far map isn't built yet.")
        return
    end
    local wasFar = Far.IsActive()
    if not wasFar and Far.ZoomTo(1000) == false then
        ns.Print("self-test: there's no far map here (no terrain tiles, or no position). Try outdoors on a continent.")
        return
    end
    local _, _, inst, native = Far.PlayerWorld()
    local state = {
        steps = SelfTest.Steps(native or 233, ns.db.maxFarZoom, Far.MaxZoom()),
        snaps = {}, i = 0, instance = inst, maxZoom = Far.MaxZoom(),
        smooth = ns.db.smoothZoom, memory = Memory(),
    }
    driver = driver or CreateFrame("Frame")
    state.driver = driver
    running = state
    ns.db.smoothZoom = false
    ns.Printf("self-test: zooming through %d levels; hands off the map for a few seconds.", #state.steps)
    local started, frames
    local function Next()
        state.i = state.i + 1
        if state.i > #state.steps then
            Finish(state)
            return
        end
        Far.ZoomTo(state.steps[state.i])
        started, frames = GetTime(), 0
    end
    Next()
    state.driver:SetScript("OnUpdate", function()
        if not Far.IsActive() then
            Finish(state, "the far map closed (a loading screen, or it was zoomed back in)")
            return
        end
        frames = frames + 1
        local t = GetTime() - started
        if (frames >= SETTLE_FRAMES and t >= SETTLE_SECONDS and not Far.Loading()) or t >= GIVE_UP then
            Snapshot(state, t)
            Next()
        end
    end)
end

ns.RegisterCommand("selftest", "zoom the far map through a few levels and check what's drawn (report saved on /reload)",
    function() SelfTest.Run() end)

-- Try the far map's background colour live, to match the tiles' sea: /overlook bg 3 3 3 (0-255).
ns.RegisterCommand("bg", "dev: set the far map's background colour, 0-255 (/overlook bg 3 3 3)", function(arg)
    local r, g, b = tostring(arg or ""):match("^%s*(%d+)%s+(%d+)%s+(%d+)")
    if not r then print("Overlook Dev: /overlook bg <r> <g> <b>, each 0-255"); return end
    if ns.Far and ns.Far.SetBackground then ns.Far.SetBackground(r / 255, g / 255, b / 255) end
    print(("Overlook Dev: far map background %d %d %d"):format(r, g, b))
end)
