-- Quest areas on the far view: the blue shading the game draws for quest objectives on the world
-- map and the normal minimap. The game's QuestPOIFrame widget draws them for one map at a time,
-- sized to that map, so each zone in view gets one, stretched over the zone's world rectangle on
-- the far canvas. Panning and zooming then move it like the tiles.
--
-- On a round map the widget can't be masked (it has no mask setting; only a frame's rectangle can
-- clip it), so each zone frame is drawn once per row of a stack of clipping strips that fill the
-- circle. Each strip is as wide as the circle at its outer edge: areas can stop a little short of
-- the rim, never past it. That's several draws per zone, so while a zoom is moving on the round
-- map the areas hide and redraw once it settles.
--
-- Settings: questAreas (on/off), questAreaFill / questAreaBorder (opacity), questAreaTracked
-- (only quests on the objective tracker).
local _, ns = ...

local A, G = ns.MapArt, ns.Geometry

local Areas = {}
ns.Areas = Areas

local CHECK_EVERY = 0.5   -- seconds between looks at which zones are in view
local CONTINENT = 2       -- Enum.UIMapType
local ZONE = 3
-- The fill: the game's own blue by default. The widget takes a texture, not a colour, so a colour
-- picked in the settings (questAreaColor, "rrggbb") is drawn with the nearest of 216 flat textures
-- (Media/AreaColors/cRGB, six shades per channel). Without the extension written out, or as TGA, the
-- widget drew them as the game's green missing-texture fill; they ship as BLP and TGA, and
-- /fzm areas tex blp|tga|plain switches between them for checking in game.
local FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local PALETTE = "Interface\\AddOns\\FarZoomMinimap\\Media\\AreaColors\\c%d%d%d"

-- "rrggbb" from 0-1 channels. Pure.
function Areas.Hex(r, g, b)
    local function C(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
    return string.format("%02x%02x%02x", C(r), C(g), C(b))
end

-- 0-1 channels from "rrggbb", or nil. Pure.
function Areas.Channels(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- The fill texture for a picked colour (nil or "" is the game's blue). Pure.
local paletteKind = ".blp" -- ".blp", ".tga" or "" (no extension)
function Areas.FillTexture(hex)
    local r, g, b = Areas.Channels(hex)
    if not r then return FILL end
    local function L(v) return math.floor(v * 5 + 0.5) end
    return string.format(PALETTE, L(r), L(g), L(b)) .. paletteKind
end
local BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"


local canvas, view, level
-- Sets of zone frames: [0] for the square map (on the canvas, clipped by the view), [1..] the round
-- map's strips. { clip = clipping frame or nil, frames = { [mapID] = QuestPOIFrame } }
local sets = {}
local zooming = false     -- a zoom is moving (the round map's strips wait for it to settle)
-- Found in game: the widget is clipped fine by the view, but shows nothing inside a clipping frame
-- that is itself inside the clipping view. So the round map's strips hang off the map's root
-- frame, outside the view, and are the only clipping around their widgets. (/fzm areas test
-- <mode> for checking: "nested" strips inside the view as before, "noclip" strips that don't clip.)
local experiment
local root -- the map's root frame (the view's parent): the round map's strips hang off it
local zones = {}          -- [instance] = { { mapID, top, left, bottom, right }, ... }
local layout              -- { inst, n, w, ppy } while far mode is drawing
local visible = {}        -- [mapID] = true for zones in view
local generation = 1      -- bumped when the quest log or a setting changes; frames repaint
local painted = setmetatable({}, { __mode = "k" }) -- [frame] = the generation it was last painted at
local nextCheck = 0
local supported           -- nil: not tried yet; false: this client has no QuestPOIFrame

local function Vec(x, y) return CreateVector2D(x, y) end

local function Api()
    local api = _G.C_Map
    if api and api.GetMapChildrenInfo and api.GetWorldPosFromMapPos and api.GetMapInfo then return api end
end

-- The zones of the continent the player is on, with their world rectangles, once per instance.
local function ZonesOf(inst)
    if zones[inst] then return zones[inst] end
    local api = Api()
    local list = {}
    if not api then return list end
    local map = api.GetBestMapForUnit and api.GetBestMapForUnit("player")
    local info = map and not ns.IsSecret(map) and api.GetMapInfo(map)
    while info and info.mapType and info.mapType > CONTINENT and info.parentMapID and info.parentMapID > 0 do
        info = api.GetMapInfo(info.parentMapID)
    end
    if not (info and info.mapType == CONTINENT) then return list end
    local ok, children = pcall(api.GetMapChildrenInfo, info.mapID, ZONE, true)
    if not ok or type(children) ~= "table" then return list end
    for _, child in ipairs(children) do
        local cInst, top, left, bottom, right = A.WorldRect(api, child.mapID, Vec)
        if cInst == inst then
            list[#list + 1] = { mapID = child.mapID, top = top, left = left, bottom = bottom, right = right }
        end
    end
    if #list > 0 then zones[inst] = list end -- (not cached empty: the map may not be known yet)
    return list
end

-- The round map's strips: rectangles { left, right, top, bottom } in px from the centre (y up)
-- that together fill a circle of radius r, none reaching past it, and none falling more than e px
-- short of it. Rows across the middle band (where the edge is steep), columns across the top and
-- bottom caps (where it's flat): one direction alone steps badly where the edge runs along it.
-- Each step is sized so the edge moves by e across it. Pure.
function Areas.Strips(r, e)
    local out = {}
    local inner = r / math.sqrt(2) -- the bands meet here, where the edge runs at 45 degrees
    -- Along one axis from 0 to inner: the step ends where the edge has moved in by e.
    local function Steps()
        local cuts, a = { 0 }, 0
        while a < inner do
            local edge = math.sqrt(r * r - a * a) - e
            local nextA = edge > inner and math.sqrt(r * r - edge * edge) or inner
            if nextA <= a + 0.5 then nextA = math.min(inner, a + 0.5) end
            a = math.min(nextA, inner)
            cuts[#cuts + 1] = a
        end
        return cuts
    end
    local cuts = Steps()
    local function Reach(a) return math.sqrt(math.max(0, r * r - a * a)) end
    -- Middle band: rows, mirrored above and below; the first row spans the centre.
    for i = 2, #cuts do
        local y0, y1 = cuts[i - 1], cuts[i]
        local half = Reach(y1)
        if i == 2 then
            out[#out + 1] = { left = -half, right = half, top = y1, bottom = -y1 }
        else
            out[#out + 1] = { left = -half, right = half, top = y1, bottom = y0 }
            out[#out + 1] = { left = -half, right = half, top = -y0, bottom = -y1 }
        end
    end
    -- Caps: columns, mirrored left and right; the first column spans the centre.
    for i = 2, #cuts do
        local x0, x1 = cuts[i - 1], cuts[i]
        local height = Reach(x1)
        if height > inner then
            if i == 2 then
                out[#out + 1] = { left = -x1, right = x1, top = height, bottom = inner }
                out[#out + 1] = { left = -x1, right = x1, top = -inner, bottom = -height }
            else
                for _, side in ipairs({ 1, -1 }) do
                    local l, rr = side > 0 and x0 or -x1, side > 0 and x1 or -x0
                    out[#out + 1] = { left = l, right = rr, top = height, bottom = inner }
                    out[#out + 1] = { left = l, right = rr, top = -inner, bottom = -height }
                end
            end
        end
    end
    return out
end

-- How far short of the rim the round map's areas may stop: finer on a bigger map.
local function RimError() return math.max(4, ns.db.size / 2 / 24) end

local function IsRound() return ns.db.round == true end

-- The sets in use: the square map's one, or the round map's strips (placed for the map's size).
local function ActiveSets()
    if not (IsRound() and view) then
        sets[0] = sets[0] or { frames = {} }
        return { sets[0] }
    end
    local out = {}
    for i, row in ipairs(Areas.Strips(ns.db.size / 2, RimError())) do
        local set = sets[i]
        if not set then
            local clip = CreateFrame("Frame", nil, root)
            -- The widgets' parent: a plain frame in the strip, like the canvas in the view.
            local holder = CreateFrame("Frame", nil, clip)
            holder:SetSize(1, 1)
            holder:SetPoint("CENTER", canvas, "CENTER")
            set = { clip = clip, holder = holder, frames = {} }
            sets[i] = set
        end
        local parent = experiment == "nested" and canvas or root
        if set.clip:GetParent() ~= parent then set.clip:SetParent(parent) end
        -- Above the terrain tiles (the canvas's level), which these no longer sit inside.
        set.clip:SetFrameLevel(level + 1)
        set.holder:SetFrameLevel(level + 1)
        if set.clip.SetClipsChildren then set.clip:SetClipsChildren(experiment ~= "noclip") end
        set.clip:ClearAllPoints()
        set.clip:SetPoint("TOPLEFT", view, "CENTER", row.left, row.top)
        set.clip:SetSize(row.right - row.left, row.top - row.bottom)
        set.clip:Show()
        out[#out + 1] = set
    end
    return out
end

local function Frame(set, mapID)
    local f = set.frames[mapID]
    if f or supported == false then return f end
    local ok, made = pcall(CreateFrame, "QuestPOIFrame", nil, set.holder or canvas)
    if not ok or not made or not made.SetMapID then
        supported = false
        return nil
    end
    supported = true
    f = made
    f:SetFrameLevel(set.holder and level + 1 or level)
    if f.EnableMouse then f:EnableMouse(false) end
    pcall(f.SetBorderTexture, f, BORDER)
    pcall(f.SetBorderScalar, f, 1)
    -- Overlapping areas merge into one shape instead of stacking into solid blue.
    pcall(f.EnableMerging, f, true)
    pcall(f.EnableSmoothing, f, true)
    f:SetMapID(mapID)
    set.frames[mapID] = f
    return f
end

local function TrackedQuests()
    local out = {}
    local log = _G.C_QuestLog
    if not (log and log.GetNumQuestWatches and log.GetQuestIDForQuestWatchIndex) then return out end
    for i = 1, log.GetNumQuestWatches() or 0 do
        local id = log.GetQuestIDForQuestWatchIndex(i)
        if id then out[#out + 1] = id end
    end
    return out
end

-- Questie's cache of every quest the player has, keyed by quest ID (read, never written).
local function QuestieQuests()
    local loader = _G.QuestieLoader
    if not (loader and loader.ImportModule) then return nil end
    local ok, cache = pcall(loader.ImportModule, loader, "QuestLogCache")
    local t = ok and type(cache) == "table" and cache.questLog_DO_NOT_MODIFY
    return type(t) == "table" and t or nil
end

-- Every quest the player has. The widget's DrawAll draws nothing on this client, so each quest is
-- drawn on its own. The game's log only lists quests under expanded headers, so Questie's cache
-- comes first; the tracked quests are always added, so this never draws less than tracked-only.
local function AllQuests(tracked)
    local out, seen = {}, {}
    local function Add(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    local cache = QuestieQuests()
    if cache then
        for id in pairs(cache) do Add(id) end
    end
    local log = _G.C_QuestLog
    local ok, n = false, nil
    if log and log.GetNumQuestLogEntries then ok, n = pcall(log.GetNumQuestLogEntries) end
    if not ok or type(n) ~= "number" then n = 0 end
    for i = 1, n do
        local id
        if log.GetInfo then
            local okI, info = pcall(log.GetInfo, i)
            if okI and type(info) == "table" and not info.isHeader then id = info.questID end
        end
        if not id and log.GetQuestIDForLogIndex then
            local okQ, q = pcall(log.GetQuestIDForLogIndex, i)
            if okQ then id = q end
        end
        Add(id)
    end
    for _, id in ipairs(tracked) do Add(id) end
    table.sort(out)
    return out
end
Areas.AllQuests = AllQuests

-- Each quest drawn by one zone only. Zone maps overlap at their edges, and a quest near a border
-- is on both maps: drawn by both frames, the overlap came out twice as dark.
-- onMaps: { [zone mapID] = { { questID, mapID, x, y }, ... } } (C_QuestLog.GetQuestsOnMap for
-- each zone in view). A quest goes to the zone its marker belongs to, else to the zone where its
-- marker is nearest the middle. Returns { [questID] = zone mapID }. Pure.
function Areas.Assign(onMaps)
    local owner, best = {}, {}
    for zone, quests in pairs(onMaps) do
        for _, q in ipairs(quests) do
            local id = q.questID
            if type(id) == "number" then
                local score
                if q.mapID == zone then
                    score = -1 -- its own zone always wins
                else
                    local dx, dy = (tonumber(q.x) or 0.5) - 0.5, (tonumber(q.y) or 0.5) - 0.5
                    score = dx * dx + dy * dy
                end
                if best[id] == nil or score < best[id] or (score == best[id] and zone < owner[id]) then
                    best[id], owner[id] = score, zone
                end
            end
        end
    end
    return owner
end

local owners = {} -- [questID] = the zone in view that draws it

local function UpdateOwners()
    local log = _G.C_QuestLog
    local onMaps = {}
    if log and log.GetQuestsOnMap then
        for id in pairs(visible) do
            local ok, list = pcall(log.GetQuestsOnMap, id)
            if ok and type(list) == "table" then onMaps[id] = list end
        end
    end
    owners = Areas.Assign(onMaps)
end

-- The quests to draw, worked out once per redraw (not once per zone).
local function QuestsToDraw()
    local tracked = TrackedQuests()
    return ns.db.questAreaTracked and tracked or AllQuests(tracked)
end

local function Paint(f, mapID, ids)
    pcall(f.DrawNone, f)
    pcall(f.SetFillTexture, f, Areas.FillTexture(ns.db.questAreaColor))
    pcall(f.SetFillAlpha, f, math.floor((ns.db.questAreaFill or 0.25) * 255 + 0.5))
    pcall(f.SetBorderAlpha, f, math.floor((ns.db.questAreaBorder or 0.5) * 255 + 0.5))
    for _, id in ipairs(ids) do
        -- A quest no zone in view lists has no marker: left to every frame, as before.
        local owner = owners[id]
        if owner == nil or owner == mapID then pcall(f.DrawBlob, f, id, true) end
    end
end

local function Place(f, z)
    local x, y = G.WorldToPixel(z.top, z.left, layout.n, layout.w, layout.ppy)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", canvas, "CENTER", x, y)
    f:SetSize((z.left - z.right) * layout.ppy, (z.top - z.bottom) * layout.ppy)
end

local function Showing()
    return layout ~= nil and ns.db.questAreas ~= false and not (ns.Caves and ns.Caves.IsDrawing())
        and not (zooming and IsRound())
end
local wasShowing = false

-- Shows the frames of the zones in view (placed, and painted if anything changed since), hides
-- every other frame.
local function Draw()
    local list = layout and ZonesOf(layout.inst) or {}
    local show, keep = Showing(), {}
    wasShowing = show
    local ids -- worked out the first time a frame needs painting
    local usedSets = {}
    if show then
        for _, set in ipairs(ActiveSets()) do
            usedSets[set] = true
            for _, z in ipairs(list) do
                if visible[z.mapID] then
                    local f = set.frames[z.mapID] or Frame(set, z.mapID)
                    if f then
                        Place(f, z)
                        f:Show() -- before painting: a hidden widget may not take the drawing
                        if painted[f] ~= generation then
                            if not ids then
                                UpdateOwners()
                                ids = QuestsToDraw()
                            end
                            Paint(f, z.mapID, ids)
                            painted[f] = generation
                        end
                        keep[f] = true
                    end
                end
            end
        end
    end
    for _, set in pairs(sets) do
        for _, f in pairs(set.frames) do
            if not keep[f] then f:Hide() end
        end
        if set.clip and not usedSets[set] then set.clip:Hide() end
    end
end

local resized = false
local settled = false -- a round-map zoom just ended: redraw next frame -- the frames changed size: redraw them next frame, once the size has applied

-- Far mode calls this every frame with the view's centre and radius (yards), and whether a zoom
-- is moving.
function Areas.Update(now, north, west, radius, isZooming)
    isZooming = isZooming == true
    if isZooming ~= zooming then
        zooming = isZooming
        if IsRound() then
            -- Hidden while the zoom moves. Once it settles they're drawn fresh, a frame later, when
            -- the last zoom step's sizes have applied (as after any resize).
            if zooming then
                Draw()
            else
                settled = true
            end
            return
        end
    end
    if settled then
        settled = false
        resized = true
    end
    if resized and layout and Showing() then
        -- Like the world map's quest areas: drawn for the frame's size, so redrawn after a zoom.
        resized = false
        generation = generation + 1
        Draw()
    end
    if now < nextCheck or not layout then return end
    nextCheck = now + CHECK_EVERY
    local changed = false
    for _, z in ipairs(ZonesOf(layout.inst)) do
        local v = A.Overlaps(z.top, z.left, z.bottom, z.right, north, west, radius) or nil
        if visible[z.mapID] ~= v then
            visible[z.mapID] = v
            changed = true
        end
    end
    -- Which zone draws a quest depends on which zones are in view: repaint them all.
    if changed then generation = generation + 1 end
    if Showing() ~= wasShowing then changed = true end -- a cave started or ended
    if Showing() then
        for _, set in ipairs(ActiveSets()) do
            for id in pairs(visible) do
                local f = set.frames[id]
                if not f or painted[f] ~= generation then changed = true end
            end
        end
    end
    if changed then Draw() end
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Areas.SetLayout(inst, n, w, ppy)
    if inst then
        layout = layout or {}
        if layout.ppy ~= ppy or layout.inst ~= inst then resized = true end
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
    else
        layout, nextCheck = nil, 0
        for k in pairs(visible) do visible[k] = nil end
    end
    Draw()
end

-- Redraws after a settings change.
function Areas.Refresh()
    generation = generation + 1
    Draw()
end

function Areas.ShownFrames()
    local n = 0
    for _, set in pairs(sets) do
        for _, f in pairs(set.frames) do if f:IsShown() then n = n + 1 end end
    end
    return n
end

function Areas.Build(canvasFrame, frameLevel)
    canvas, level = canvasFrame, frameLevel
    view = canvas.GetParent and canvas:GetParent() or nil
    root = view and view.GetParent and view:GetParent() or view
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function()
        generation = generation + 1
        nextCheck = 0
    end)
end

ns.RegisterCommand("areas", "show the quest areas the far view draws", function(arg)
    local kind = type(arg) == "string" and arg:match("^tex%s*(%a*)")
    if kind then
        paletteKind = ({ blp = ".blp", tga = ".tga", plain = "" })[kind] or ".blp"
        Areas.Refresh()
        ns.Printf("quest area colours from %s files", paletteKind == "" and "files without an extension" or paletteKind)
        return
    end
    local mode = type(arg) == "string" and arg:match("^test%s*(%a*)")
    if mode then
        experiment = (mode == "noclip" or mode == "nested") and mode or nil
        for _, set in pairs(sets) do
            if set.clip then set.clip:Hide() end
        end
        Areas.Refresh()
        ns.Printf("quest areas experiment: %s", experiment or "off (normal)")
        return
    end
    local tracked = TrackedQuests()
    ns.Printf("quest areas %s  widget %s  zones on this continent %d  shown %d",
        ns.db.questAreas ~= false and "on" or "off",
        supported == nil and "not tried" or (supported and "yes" or "missing"),
        layout and #ZonesOf(layout.inst) or 0, Areas.ShownFrames())
    ns.Printf("quests: %d in all (Questie's list %s), %d tracked; drawing %s", #AllQuests(tracked),
        QuestieQuests() and "found" or "missing", #tracked, ns.db.questAreaTracked and "tracked only" or "all")
    local strips, painted0 = 0, 0
    for i, set in pairs(sets) do
        if i > 0 and set.clip and set.clip:IsShown() then strips = strips + 1 end
        for _, f in pairs(set.frames) do
            if painted[f] == generation then painted0 = painted0 + 1 end
        end
    end
    ns.Printf("map %s  strips shown %d  frames painted this round %d  zooming %s  showing %s",
        IsRound() and "round" or "square", strips, painted0, tostring(zooming), tostring(Showing()))
end)
