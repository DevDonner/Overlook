-- Quest areas on the far view: the blue shading the game draws for quest objectives on the world
-- map and the normal minimap. The game's QuestPOIFrame widget draws them for one map at a time,
-- sized to that map, so each zone in view gets one, stretched over the zone's world rectangle on
-- the far canvas. Panning and zooming then move it like the tiles.
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
local FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local BORDER = "Interface\\WorldMap\\UI-QuestBlob-Outside"

local canvas, level
local frames = {}         -- [mapID] = QuestPOIFrame
local zones = {}          -- [instance] = { { mapID, top, left, bottom, right }, ... }
local layout              -- { inst, n, w, ppy } while far mode is drawing
local visible = {}        -- [mapID] = true for zones in view
local generation = 1      -- bumped when the quest log or a setting changes; frames repaint
local painted = {}        -- [mapID] = the generation that frame was last painted at
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

local function Frame(mapID)
    local f = frames[mapID]
    if f or supported == false then return f end
    local ok, made = pcall(CreateFrame, "QuestPOIFrame", nil, canvas)
    if not ok or not made or not made.SetMapID then
        supported = false
        return nil
    end
    supported = true
    f = made
    f:SetFrameLevel(level)
    if f.EnableMouse then f:EnableMouse(false) end
    pcall(f.SetFillTexture, f, FILL)
    pcall(f.SetBorderTexture, f, BORDER)
    pcall(f.SetBorderScalar, f, 1)
    -- Overlapping areas merge into one shape instead of stacking into solid blue.
    pcall(f.EnableMerging, f, true)
    pcall(f.EnableSmoothing, f, true)
    f:SetMapID(mapID)
    frames[mapID] = f
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
end
local wasShowing = false

-- Shows the frames of the zones in view (placed, and painted if anything changed since), hides
-- every other frame.
local function Draw()
    local list = layout and ZonesOf(layout.inst) or {}
    local show, keep = Showing(), {}
    wasShowing = show
    local ids -- worked out the first time a frame needs painting
    if show then
        for _, z in ipairs(list) do
            if visible[z.mapID] then
                local f = frames[z.mapID] or Frame(z.mapID)
                if f then
                    Place(f, z)
                    if painted[z.mapID] ~= generation then
                        if not ids then
                            UpdateOwners()
                            ids = QuestsToDraw()
                        end
                        Paint(f, z.mapID, ids)
                        painted[z.mapID] = generation
                    end
                    f:Show()
                    keep[z.mapID] = true
                end
            end
        end
    end
    for id, f in pairs(frames) do
        if not keep[id] then f:Hide() end
    end
end

local resized = false -- the frames changed size: redraw them next frame, once the size has applied

-- Far mode calls this every frame with the view's centre and radius (yards).
function Areas.Update(now, north, west, radius)
    if resized and layout then
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
    for id in pairs(visible) do
        if painted[id] ~= generation then changed = true end
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
    for _, f in pairs(frames) do if f:IsShown() then n = n + 1 end end
    return n
end

function Areas.Build(canvasFrame, frameLevel)
    canvas, level = canvasFrame, frameLevel
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function()
        generation = generation + 1
        nextCheck = 0
    end)
end

ns.RegisterCommand("areas", "show the quest areas the far view draws", function()
    local tracked = TrackedQuests()
    ns.Printf("quest areas %s  widget %s  zones on this continent %d  shown %d",
        ns.db.questAreas ~= false and "on" or "off",
        supported == nil and "not tried" or (supported and "yes" or "missing"),
        layout and #ZonesOf(layout.inst) or 0, Areas.ShownFrames())
    ns.Printf("quests: %d in all (Questie's list %s), %d tracked; drawing %s", #AllQuests(tracked),
        QuestieQuests() and "found" or "missing", #tracked, ns.db.questAreaTracked and "tracked only" or "all")
end)
