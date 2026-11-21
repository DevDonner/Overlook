-- Phase 1b: far zoom. Past the native minimap's widest step, our own view takes over: minimap
-- terrain tiles around the player plus our own player arrow. The native Minimap stays shown at
-- alpha 0 underneath so HereBeDragons keeps updating its pins (Phase 2 mirrors them).
--
-- Layout (design: Performance plan):
--  * view   - clipped square over the shell, mouse-enabled only in far mode, so invisible native
--             pins can't take hover and a plain click can't ping.
--  * canvas - unscaled layer; its CENTER is the fixed origin (where far mode started on this
--             continent). Each frame one SetPoint moves it under the player.
--  * tiles  - pooled textures placed relative to the canvas; re-placed only when the zoom changes.
local _, ns = ...

local G, Zoom = ns.Geometry, ns.Zoom
local abs, max = math.abs, math.max

local Far = {}
ns.Far = Far

local TILE = G.TILE_YARDS
local FALLBACK_RADIUS = 700 / 3  -- the widest native step outdoors on 1.60.1
local NEW_TILES_PER_FRAME = 16
local ARROW_SIZE = 32            -- px at native minimap scale
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow"

local view, canvas, arrowFrame, arrow
local mode = "near"
local radius, target, tweenFrom, tweenStart, leaving
local nativeMax = FALLBACK_RADIUS
local instance, tileSet, originN, originW
local active, pool = {}, {}      -- active[key] = texture, or false when the tile has no art
local c0, c1, r0, r1             -- the tile range on screen
local layoutDirty, tilesPending = false, false
local lastFacing

local function Usable(v)
    return v ~= nil and not ns.IsSecret(v)
end

local function PlayerPosition()
    local n, w, _, inst = UnitPosition("player")
    if Usable(n) and Usable(w) and Usable(inst) then return n, w, inst end
end

local function TilesFor(inst)
    return ns.MapMinimap and ns.MapMinimap[inst]
end

local function NativeRadius()
    local r = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if Usable(r) and type(r) == "number" and r > 0 then return r end
    return FALLBACK_RADIUS
end

----------------------------------------------------------------------------------------------------
-- Tiles

local function AcquireTexture()
    local t = table.remove(pool)
    if not t then
        t = canvas:CreateTexture(nil, "ARTWORK")
        -- Fractional tile sizes: don't let pixel snapping open hairline gaps between tiles (#17).
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
    end
    t:Show()
    return t
end

local function ReleaseTile(key)
    local t = active[key]
    if t then
        t:Hide()
        t:ClearAllPoints()
        pool[#pool + 1] = t
    end
    active[key] = nil
end

local function ReleaseAll()
    for key in pairs(active) do ReleaseTile(key) end
    c0, c1, r0, r1 = nil, nil, nil, nil
    tilesPending = false
end

local function PlaceTile(t, key, ppy)
    local n, w = G.TileToWorld(G.KeyToTile(key))
    local x, y = G.WorldToPixel(n, w, originN, originW, ppy)
    local s = TILE * ppy
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", canvas, "CENTER", x, y)
    t:SetSize(s, s)
end

local function RelayoutTiles(ppy)
    for key, t in pairs(active) do
        if t then PlaceTile(t, key, ppy) end
    end
end

local missing, distance = {}, {}
local function ByDistance(a, b) return distance[a] < distance[b] end

-- Drops tiles that left the range and adds missing ones, nearest first, at most
-- NEW_TILES_PER_FRAME per frame so a big zoom-out never stalls a frame (#28).
local function UpdateTiles(a0, a1, b0, b1, n, w, ppy)
    for key in pairs(active) do
        local col, row = G.KeyToTile(key)
        if col < a0 or col > a1 or row < b0 or row > b1 then ReleaseTile(key) end
    end
    c0, c1, r0, r1 = a0, a1, b0, b1

    local pc, pr = G.WorldToTile(n, w)
    for i = #missing, 1, -1 do missing[i] = nil end
    for col = a0, a1 do
        for row = b0, b1 do
            local key = G.TileKey(col, row)
            if active[key] == nil then
                missing[#missing + 1] = key
                distance[key] = max(abs(col - pc), abs(row - pr))
            end
        end
    end
    if #missing > NEW_TILES_PER_FRAME then table.sort(missing, ByDistance) end

    local added = 0
    for i = 1, #missing do
        local key = missing[i]
        local fid = tileSet[key]
        if fid then
            if added >= NEW_TILES_PER_FRAME then
                tilesPending = true
                return
            end
            local t = AcquireTexture()
            t:SetTexture(fid)
            PlaceTile(t, key, ppy)
            active[key] = t
            added = added + 1
        else
            active[key] = false -- open sea or off the map: the view's background shows
        end
    end
    tilesPending = false
end

----------------------------------------------------------------------------------------------------
-- Frame loop (runs only while the view is shown, i.e. in far mode)

local function OnUpdate()
    local n, w, inst = PlayerPosition()
    if not n then
        Far.Leave() -- loading screen, or an instance without a usable position
        return
    end
    if inst ~= instance then
        local set = TilesFor(inst)
        if not set then
            Far.Leave()
            return
        end
        ReleaseAll()
        instance, tileSet, originN, originW = inst, set, n, w
        layoutDirty = true
    end

    local zoomed = layoutDirty
    if radius ~= target then
        radius = Zoom.Tween(tweenFrom, target, GetTime() - tweenStart, ns.db.smoothZoom and Zoom.TWEEN or 0)
        zoomed = true
    end
    if leaving and radius == target then
        Far.Leave()
        return
    end

    local ppy = ns.db.size / 2 / radius
    canvas:SetPoint("CENTER", view, "CENTER", (w - originW) * ppy, (originN - n) * ppy)

    if zoomed then
        layoutDirty = false
        RelayoutTiles(ppy)
    end
    local a0, a1, b0, b1 = G.VisibleTiles(n, w, radius)
    if zoomed or tilesPending or a0 ~= c0 or a1 ~= c1 or b0 ~= r0 or b1 ~= r1 then
        UpdateTiles(a0, a1, b0, b1, n, w, ppy)
    end

    local facing = GetPlayerFacing()
    if Usable(facing) and facing ~= lastFacing then
        lastFacing = facing
        arrow:SetRotation(facing)
    end
end

----------------------------------------------------------------------------------------------------
-- Modes

function Far.IsActive()
    return mode == "far"
end

-- Starts a new zoom step from wherever the view is now. delta follows the wheel: > 0 is in.
function Far.Step(delta, fine)
    local r, leave = Zoom.FarStep(target, delta, fine, nativeMax, ns.db.maxFarZoom)
    tweenFrom, target, tweenStart, leaving = radius, r, GetTime(), leave
end

-- Hands over from the native minimap at its widest step. Returns false where there's no far
-- map (no usable position, or no tiles for this continent).
function Far.Enter(fine)
    if mode == "far" then return true end
    if not view then return false end
    local n, w, inst = PlayerPosition()
    local set = n and TilesFor(inst)
    if not set then return false end

    nativeMax = NativeRadius()
    mode = "far"
    instance, tileSet, originN, originW = inst, set, n, w
    radius, target, leaving = nativeMax, nativeMax, false
    layoutDirty, lastFacing = true, nil
    Minimap:SetAlpha(0)
    view:Show()
    Far.Step(-1, fine)
    return true
end

function Far.Leave()
    if mode ~= "far" then return end
    mode = "near"
    view:Hide()
    ReleaseAll()
    instance, tileSet = nil, nil
    Minimap:SetAlpha(1)
end

----------------------------------------------------------------------------------------------------
-- Mouse wheel: native steps first, then far zoom.

local function NativeZoom(delta)
    if delta > 0 then
        if _G.Minimap_ZoomIn then
            _G.Minimap_ZoomIn()
        else
            Minimap:SetZoom(math.min(Minimap:GetZoom() + 1, Minimap:GetZoomLevels() - 1))
        end
    elseif _G.Minimap_ZoomOut then
        _G.Minimap_ZoomOut()
    else
        Minimap:SetZoom(max(Minimap:GetZoom() - 1, 0))
    end
end

local function OnWheel(_, delta)
    local fine = IsControlKeyDown()
    if mode == "far" then
        Far.Step(delta, fine)
    elseif delta < 0 and Minimap:GetZoom() == 0 then
        Far.Enter(fine)
    else
        NativeZoom(delta)
    end
end

----------------------------------------------------------------------------------------------------
-- Setup

-- Called by the shell after every layout pass (size change, Edit Mode, CVar).
function Far.OnShellApplied()
    if not view then return end
    local s = ARROW_SIZE * ns.db.size / max(ns.Shell.nativeSize or 1, 1)
    arrow:SetSize(s, s)
    layoutDirty = true
end

function Far.Build(root, level)
    if view then return end
    view = CreateFrame("Frame", nil, root)
    view:SetAllPoints(root)
    view:SetFrameLevel(level)
    view:SetClipsChildren(true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", OnWheel)
    view:SetScript("OnUpdate", OnUpdate)
    view:Hide()

    local bg = view:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(view)
    bg:SetColorTexture(0.06, 0.07, 0.09, 1)

    canvas = CreateFrame("Frame", nil, view)
    canvas:SetSize(1, 1)
    canvas:SetPoint("CENTER", view, "CENTER")
    canvas:SetFrameLevel(level + 1)

    arrowFrame = CreateFrame("Frame", nil, view)
    arrowFrame:SetAllPoints(view)
    arrowFrame:SetFrameLevel(level + 3)
    arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("CENTER", view, "CENTER")
    if arrow:SetTexture(ARROW_TEXTURE) == false then
        arrow:SetColorTexture(1, 0.82, 0, 1) -- fallback so the player is still marked
    end

    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", OnWheel)
end

local events = CreateFrame("Frame")
events:RegisterEvent("MINIMAP_UPDATE_ZOOM")
events:SetScript("OnEvent", function()
    -- Keep the native map at its widest step under far mode, so handing back is seamless.
    if mode == "far" and Minimap:GetZoom() ~= 0 then Minimap:SetZoom(0) end
end)

----------------------------------------------------------------------------------------------------
-- Commands

ns.RegisterCommand("far", "show far-zoom state", function()
    local n = 0
    for _, t in pairs(active) do if t then n = n + 1 end end
    ns.Printf("mode %s  radius %s yd (target %s)  native max %.1f yd  max %d yd",
        mode, radius and string.format("%.0f", radius) or "-", target and string.format("%.0f", target) or "-",
        nativeMax, ns.db.maxFarZoom)
    ns.Printf("tiles shown %d  pooled %d  instance %s  pending %s", n, #pool, ns.Show(instance), tostring(tilesPending))
end)

ns.RegisterCommand("maxzoom", "set the far-zoom limit in yards (500-3200), e.g. /fzm maxzoom 3200", function(arg)
    if not tonumber(arg) then
        ns.Printf("max far zoom is %d yd; usage: /fzm maxzoom 3200", ns.db.maxFarZoom)
        return
    end
    ns.db.maxFarZoom = ns.Settings.ClampMaxFar(arg)
    if mode == "far" and target > ns.db.maxFarZoom then
        tweenFrom, target, tweenStart = radius, ns.db.maxFarZoom, GetTime()
    end
    ns.Printf("max far zoom %d yd", ns.db.maxFarZoom)
end)

ns.RegisterCommand("smooth", "toggle smooth zooming", function()
    ns.db.smoothZoom = not ns.db.smoothZoom
    ns.Printf("smooth zoom %s", ns.db.smoothZoom and "on" or "off")
end)
