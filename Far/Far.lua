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
-- Tiles added per frame: at least NEW_TILES_PER_FRAME, more when many are missing (a big zoom
-- out at 6,400 yd needs ~600), so a full view fills in within about LOAD_FRAMES frames.
local NEW_TILES_PER_FRAME, MAX_TILES_PER_FRAME, LOAD_FRAMES = 16, 64, 12
local ARROW_SIZE = 32            -- px at native minimap scale
local ARROW_TEXTURE = "Interface\\Minimap\\MinimapArrow"

local view, canvas, arrowFrame, arrow
local mode = "near"
local radius, target, tweenFrom, tweenStart, leaving
local nativeMax = FALLBACK_RADIUS
local instance, tileSet, originN, originW
local active, pool = {}, {}      -- active[key] = texture, or false when the tile has no art
local loadStart, loadCount       -- GetTime() and tiles added since the current fill began
local lastLoad                   -- { seconds, tiles, radius } of the last fill, for /fzm far
local c0, c1, r0, r1             -- the tile range on screen
local layoutDirty, tilesPending = false, false
local lastFacing
local anchorN, anchorW           -- world point the view is pinned to after a pan; nil = follows the player
local playerN, playerW           -- last known player position
local drag                       -- { x, y, n, w, moved } while the left button is down
local nearDrag                   -- cursor at mouse-down on the native minimap, until it moves
local suppressPing = false       -- the native mouse-up after a drag must not ping
local recenter                   -- the Recenter button
local DRAG_START_PX = 4
-- Handing back to the native minimap: it has been at alpha 0 and can take a moment to draw again
-- (longest in cities and caves), which showed as a black map. The far view stays over it as a
-- cover, opaque for COVER_HOLD, then fades out over COVER_FADE.
local COVER_HOLD, COVER_FADE = 0.15, 0.25
local coverStart                 -- GetTime() when the cover began; nil when there's none

local function Cursor()
    local x, y = GetCursorPosition()
    local s = view:GetEffectiveScale()
    return x / s, y / s
end

-- Panned = the view is pinned to a world point visibly off the player (more than 2 px at the
-- current zoom). A pinned view stays put while the player moves; a centred one follows the
-- player and hands back to the native minimap when zoomed to its scale.
local ALIGNED_PX = 2
local function IsPanned()
    if not anchorN or not playerN then return false end
    local ppy = ns.db.size / 2 / (radius or nativeMax)
    local dN, dW = anchorN - playerN, anchorW - playerW
    return (dN * dN + dW * dW) * ppy * ppy > ALIGNED_PX * ALIGNED_PX
end

local function ClearAnchor()
    anchorN, anchorW, drag = nil, nil, nil
end

-- A drag released back on the player un-pins the view, so it follows the player again.
local function FinishDrag()
    drag = nil
    if anchorN and not IsPanned() then anchorN, anchorW = nil, nil end
end

local function Usable(v)
    return v ~= nil and not ns.IsSecret(v)
end

local function PlayerPosition()
    local n, w, _, inst = UnitPosition("player")
    if Usable(n) and Usable(w) and Usable(inst) then return n, w, inst end
    -- Instances hide UnitPosition; the player's spot on the dungeon's map still says where they are.
    if ns.FarArt then return ns.FarArt.PlayerFromMap() end
end

local NO_TERRAIN = {} -- an instance with no terrain tiles but a map of its own (a dungeon)

local function TilesFor(inst)
    local set = ns.MapMinimap and ns.MapMinimap[inst]
    if set then return set end
    if ns.FarArt and ns.FarArt.HasMapFor(inst) then return NO_TERRAIN end
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
        Far.Shape(t)
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

-- Drops tiles that left the range and adds missing ones, nearest first, a budget per frame so a
-- big zoom-out never stalls a frame (#28).
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
    local budget = math.min(MAX_TILES_PER_FRAME, max(NEW_TILES_PER_FRAME, math.ceil(#missing / LOAD_FRAMES)))
    if #missing > budget then table.sort(missing, ByDistance) end
    if #missing > 0 and not loadStart then loadStart, loadCount = GetTime(), 0 end

    local added = 0
    for i = 1, #missing do
        local key = missing[i]
        local fid = tileSet[key]
        if fid then
            if added >= budget then
                tilesPending = true
                loadCount = loadCount + added
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
    if loadStart then
        lastLoad = { GetTime() - loadStart, loadCount + added, radius }
        loadStart = nil
    end
end

----------------------------------------------------------------------------------------------------
-- Frame loop (runs only while the view is shown, i.e. in far mode)

local EndCover -- (below)
local CursorInside -- (below, with the shape)

local function OnUpdate()
    if coverStart then
        local t = GetTime() - coverStart - COVER_HOLD
        if t >= COVER_FADE then
            EndCover()
        elseif t > 0 then
            view:SetAlpha(1 - t / COVER_FADE)
        end
        return
    end
    local n, w, inst = PlayerPosition()
    if not n then
        Far.Leave(true) -- loading screen, or an instance without a usable position
        return
    end
    if inst ~= instance then
        local set = TilesFor(inst)
        if not set then
            Far.Leave(true)
            return
        end
        ReleaseAll()
        instance, tileSet, originN, originW = inst, set, n, w
        ClearAnchor()
        layoutDirty = true
    end

    if ns.Caves then ns.Caves.Update(GetTime(), instance, n, w) end
    if ns.FarArt then
        ns.FarArt.Update(GetTime(), tileSet ~= NO_TERRAIN, ns.Caves and ns.Caves.IsDrawing())
    end

    local zoomed = layoutDirty
    if radius ~= target then
        radius = Zoom.Tween(tweenFrom, target, GetTime() - tweenStart, ns.db.smoothZoom and Zoom.TWEEN or 0)
        zoomed = true
    end
    if leaving and IsPanned() then
        leaving = false -- panned during a zoom that was handing back: stay on the far view
    end
    if leaving and radius == target then
        Far.Leave()
        return
    end

    local ppy = ns.db.size / 2 / radius

    if drag then
        if not IsMouseButtonDown("LeftButton") then
            FinishDrag()
        else
            local cx, cy = Cursor()
            local dx, dy = cx - drag.x, cy - drag.y
            if not drag.moved and dx * dx + dy * dy >= DRAG_START_PX * DRAG_START_PX then
                drag.moved = true
                if ns.Mirror then ns.Mirror.ClearHover() end
            end
            if drag.moved then
                -- Dragging right shows more of the west: the centre moves west (west grows).
                -- Pinned to a world point, kept within reach of the player.
                local limit = 2 * ns.db.maxFarZoom
                anchorW = w + math.max(-limit, math.min(limit, drag.w + dx / ppy - w))
                anchorN = n + math.max(-limit, math.min(limit, drag.n - dy / ppy - n))
            end
        end
    end
    -- Recenter shows all through far mode (one click back to the native minimap), except while
    -- already zooming back to it.
    if recenter:IsShown() == leaving then recenter:SetShown(not leaving) end

    -- The view centre: the pinned point after a pan, else the player.
    playerN, playerW = n, w
    local cN, cW = anchorN or n, anchorW or w
    canvas:SetPoint("CENTER", view, "CENTER", (cW - originW) * ppy, (originN - cN) * ppy)
    arrow:SetPoint("CENTER", view, "CENTER", (cW - w) * ppy, (n - cN) * ppy)

    if ns.Areas then ns.Areas.Update(GetTime(), cN, cW, radius) end
    if ns.Pings then ns.Pings.Update(GetTime()) end
    -- Before SetLayout, so a zoom (or the first frame in far mode) places icons for this view.
    if ns.Mirror then ns.Mirror.SetView(cN, cW, ns.db.size / 2, zoomed) end
    if zoomed then
        layoutDirty = false
        RelayoutTiles(ppy)
        if ns.Mirror then ns.Mirror.SetLayout(instance, originN, originW, ppy, Zoom.Shrink(radius, nativeMax)) end
        if ns.Routes then ns.Routes.SetLayout(instance, originN, originW, ppy) end
        if ns.Party then ns.Party.SetLayout(instance, originN, originW, ppy) end
        if ns.FarArt then ns.FarArt.SetLayout(instance, originN, originW, ppy) end
        if ns.Caves then ns.Caves.SetLayout(instance, originN, originW, ppy) end
        if ns.Areas then ns.Areas.SetLayout(instance, originN, originW, ppy) end
        if ns.Pings then ns.Pings.SetLayout(instance, originN, originW, ppy) end
    end
    local a0, a1, b0, b1 = G.VisibleTiles(cN, cW, radius)
    if zoomed or tilesPending or a0 ~= c0 or a1 ~= c1 or b0 ~= r0 or b1 ~= r1 then
        UpdateTiles(a0, a1, b0, b1, cN, cW, ppy)
    end

    -- Hover: party dots sit above the icons, so a dot under the cursor wins.
    if view:IsMouseOver() and CursorInside() and not (drag and drag.moved) then
        local unit = ns.Party and ns.Party.UnitUnderCursor()
        if unit then
            if ns.Mirror then ns.Mirror.ClearHover() end
            ns.Party.SetHover(unit)
        else
            if ns.Party then ns.Party.SetHover(nil) end
            if ns.Mirror then ns.Mirror.UpdateHover() end
        end
    else
        if ns.Party then ns.Party.SetHover(nil) end
        if ns.Mirror then ns.Mirror.ClearHover() end
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

-- The player's last known world position, continent and the native minimap's radius (for pings).
function Far.PlayerWorld()
    return playerN, playerW, instance, nativeMax
end

-- Whether the view is pinned away from the player by a pan.
function Far.IsPanned()
    return mode == "far" and IsPanned()
end

-- The far view's radius in yards (centre to edge), or nil in near mode.
function Far.Radius()
    return mode == "far" and radius or nil
end

-- Starts a new zoom step from wherever the view is now. delta follows the wheel: > 0 is in.
function Far.Step(delta, fine)
    local r, leave = Zoom.FarStep(target, delta, fine, nativeMax, ns.db.maxFarZoom, IsPanned())
    tweenFrom, target, tweenStart, leaving = radius, r, GetTime(), leave
end

-- Hands over from the native minimap at its widest step. Returns false where there's no far
-- map (no usable position, or no tiles for this continent).
-- zoomOut false: enter at the native radius without a zoom step (a drag on the native map).
function Far.Enter(fine, zoomOut)
    if mode == "far" then return true end
    if not view then return false end
    local n, w, inst = PlayerPosition()
    local set = n and TilesFor(inst)
    if not set then return false end

    if coverStart then
        -- Back out during the hand-back fade: keep the tiles if still on the same continent.
        local same = inst == instance
        EndCover(same)
    end
    nativeMax = NativeRadius()
    mode = "far"
    instance, tileSet, originN, originW = inst, set, n, w
    radius, target, leaving = nativeMax, nativeMax, false
    layoutDirty, lastFacing = true, nil
    Minimap:SetAlpha(0)
    view:Show()
    if zoomOut ~= false then Far.Step(-1, fine) end
    return true
end

-- Makes the native minimap draw now: a zoom step there and back.
local function RefreshNative()
    local ok, z = pcall(Minimap.GetZoom, Minimap)
    local okL, levels = pcall(Minimap.GetZoomLevels, Minimap)
    if not (ok and okL and type(z) == "number" and type(levels) == "number") or levels < 2 then return end
    Minimap:SetZoom(z < levels - 1 and z + 1 or z - 1)
    Minimap:SetZoom(z)
end

-- Removes the cover. keepTiles: far mode is starting again on the same continent.
EndCover = function(keepTiles)
    coverStart = nil
    view:SetAlpha(1)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    if mode ~= "far" then view:Hide() end
    if not keepTiles then
        ReleaseAll()
        instance, tileSet = nil, nil
    end
end

-- Back to the native minimap. immediate: no cover (nothing usable to show, e.g. a loading screen).
function Far.Leave(immediate)
    if mode ~= "far" then return end
    mode = "near"
    ClearAnchor()
    recenter:Hide()
    if ns.Mirror then
        ns.Mirror.ClearHover()
        ns.Mirror.SetLayout(nil)
    end
    if ns.Routes then ns.Routes.SetLayout(nil) end
    if ns.Party then ns.Party.SetLayout(nil) end
    if ns.FarArt then ns.FarArt.SetLayout(nil) end
    if ns.Caves then ns.Caves.SetLayout(nil) end
    if ns.Areas then ns.Areas.SetLayout(nil) end
    if ns.Pings then ns.Pings.SetLayout(nil) end
    Minimap:SetAlpha(1)
    RefreshNative()
    if immediate then
        EndCover()
    else
        -- The far view stays on top as a cover, not taking the mouse, while the native map draws.
        coverStart = GetTime()
        view:EnableMouse(false)
        view:EnableMouseWheel(false)
    end
end

-- Sets the far-zoom limit, pulling the view in if it's further out.
function Far.SetMaxZoom(yards)
    ns.db.maxFarZoom = ns.Settings.ClampMaxFar(yards)
    if mode == "far" and target > ns.db.maxFarZoom then
        tweenFrom, target, tweenStart = radius, ns.db.maxFarZoom, GetTime()
    end
end

-- Back to the player and back to the native minimap at its widest step: the default view. In far
-- mode the view jumps back over the player and zooms in to the native scale, then hands back.
-- (Also from the minimap button, where the native map may be zoomed in.)
function Far.Recenter()
    if mode ~= "far" then
        if Minimap:GetZoom() ~= 0 then Minimap:SetZoom(0) end
        return
    end
    ClearAnchor()
    tweenFrom, target, tweenStart, leaving = radius, nativeMax, GetTime(), true
end

-- Zooms the far view to `yards` (capped at the furthest zoom), entering far mode if needed.
-- Returns false where there's no far map, or the radius is inside the native minimap's.
function Far.ZoomTo(yards)
    yards = math.min(yards, ns.db.maxFarZoom)
    if mode ~= "far" then
        if yards <= NativeRadius() * 1.0001 then return false end
        if not Far.Enter(false, false) then return false end
    end
    tweenFrom, target, tweenStart, leaving = radius, yards, GetTime(), false
    return true
end

-- Right-click: a ping where the cursor is, seen by the party, if the native minimap reaches it.
local function Ping()
    local cN, cW = anchorN or playerN, anchorW or playerW
    if not (cN and radius) then return end
    local cx, cy = Cursor()
    local vx, vy = view:GetCenter()
    local x, y = Zoom.PingOffset(cx - vx, cy - vy, ns.db.size / 2 / radius, cN, cW, playerN, playerW,
        ns.Shell.nativeSize or Minimap:GetWidth(), nativeMax)
    if x then
        pcall(Minimap.PingLocation, Minimap, x, y)
        local n, w = Zoom.PingToWorld(x, y, playerN, playerW, ns.Shell.nativeSize or Minimap:GetWidth(), nativeMax)
        if n and ns.Pings then ns.Pings.Local(n, w) end
    elseif _G.UIErrorsFrame then
        _G.UIErrorsFrame:AddMessage("Too far away to ping: the game only pings within the normal minimap's range.", 1, 0.1, 0.1)
    end
end

-- A click on the far view that wasn't a drag or on an icon.
local lastLeftClick
local function OnViewClick(button)
    if button == "MiddleButton" then
        if ns.db.recenterMiddle then Far.Recenter() end
    elseif button == "RightButton" then
        if ns.db.rightClickPing then Ping() end
    elseif button == "LeftButton" and ns.db.recenterDouble then
        local now = GetTime()
        if Zoom.IsDoubleClick(lastLeftClick, now) then
            lastLeftClick = nil
            Far.Recenter()
        else
            lastLeftClick = now
        end
    end
end

-- Inside the map's bottom-right corner, above the bottom bar when that bar sits over the map.
local RECENTER_INSET = 6
local function PlaceRecenter()
    if not recenter then return end
    local root = recenter:GetParent()
    local up = ns.Bars and ns.Bars.InsideBottomHeight() or 0
    recenter:ClearAllPoints()
    recenter:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -RECENTER_INSET, RECENTER_INSET + up)
    local font = math.max(9, (ns.db.barFont or 11) - 1)
    recenter.label:SetFont("Fonts\\FRIZQT__.TTF", font, "")
    recenter:SetSize(recenter.label:GetStringWidth() + 16, font + 10)
end
Far.PlaceRecenter = PlaceRecenter

----------------------------------------------------------------------------------------------------
-- Dragging. In far mode the view takes the mouse. On the native minimap a drag that moves more
-- than a few px switches to far mode at the same scale (the native map can't pan) and keeps
-- going; the native mouse-up after it is swallowed so it doesn't ping.

-- Remembers where the drag started: the cursor and the view centre in world yards.
local function BeginDrag(x, y, moved)
    local n, w = anchorN or playerN, anchorW or playerW
    if not n then n, w = PlayerPosition() end
    if not n then return end
    drag = { x = x, y = y, n = n, w = w, moved = moved }
end

local nearWatcher = CreateFrame("Frame")
nearWatcher:Hide()
nearWatcher:SetScript("OnUpdate", function(self)
    if not nearDrag or not IsMouseButtonDown("LeftButton") or mode == "far" then
        nearDrag = nil
        self:Hide()
        return
    end
    local cx, cy = Cursor()
    local dx, dy = cx - nearDrag.x, cy - nearDrag.y
    if dx * dx + dy * dy >= DRAG_START_PX * DRAG_START_PX then
        local x, y = nearDrag.x, nearDrag.y
        nearDrag = nil
        self:Hide()
        suppressPing = true
        if Far.Enter(false, false) then BeginDrag(x, y, true) end
    end
end)

local function HookNativeMouse()
    Minimap:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and mode == "near" and view then
            local x, y = Cursor()
            nearDrag = { x = x, y = y }
            suppressPing = false
            nearWatcher:Show()
        end
    end)
    -- MinimapMixin pings on every mouse-up. Wrap it so the mouse-up that ends a drag doesn't.
    local original = Minimap:GetScript("OnMouseUp")
    Minimap:SetScript("OnMouseUp", function(self, button, ...)
        nearDrag = nil
        if suppressPing then
            suppressPing = false
            return
        end
        if button == "MiddleButton" and ns.db.recenterMiddle then
            Far.Recenter()
            return
        end
        if original then return original(self, button, ...) end
    end)
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

-- Alt+wheel in far mode moves through the levels of a cave, or the floors of a city or dungeon
-- map: down goes deeper and wraps back to the top past the bottom. At most one step per
-- LEVEL_COOLDOWN, so a fast wheel can't skip levels; steps inside it are swallowed, not zoomed.
local LEVEL_COOLDOWN = 0.1
local lastLevelStep = -math.huge

local function HasLevels()
    return (ns.Caves and ns.Caves.HasLevels()) or (ns.FarArt and ns.FarArt.HasFloors()) or false
end

local function StepLevel(delta)
    local now = GetTime()
    if now - lastLevelStep < LEVEL_COOLDOWN - 0.001 then return end -- (1 ms: float rounding)
    lastLevelStep = now
    if not (ns.Caves and ns.Caves.StepLevel(delta)) and ns.FarArt then ns.FarArt.StepFloor(delta) end
end

local function OnWheel(_, delta)
    local fine = IsControlKeyDown()
    if mode == "far" and IsAltKeyDown() and HasLevels() then
        StepLevel(delta)
        return
    end
    if mode == "far" then
        Far.Step(delta, fine)
    elseif delta < 0 and Minimap:GetZoom() == 0 then
        Far.Enter(fine)
    else
        NativeZoom(delta)
    end
end

-- For the shell's Alt+drag catcher, which sits over the map while Alt is held.
function Far.Wheel(delta)
    OnWheel(nil, delta)
end

----------------------------------------------------------------------------------------------------
-- Shape: on a round map (ns.db.round) every texture on the far view takes a round mask the size of
-- the view; the view itself is still a square frame, so the corners are empty. Masks belong to a
-- frame, so each frame holding textures gets its own, anchored to the view. Textures register as
-- they're made (Far.Shape) and follow the setting from then on.

local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local masks = {}                                       -- [frame] = mask texture
local registered = setmetatable({}, { __mode = "k" })  -- [texture] = its frame
local masked = setmetatable({}, { __mode = "k" })      -- [texture] = true while masked

local function IsRound() return ns.db.round == true end

local function MaskFor(frame)
    local m = masks[frame]
    if not m then
        m = frame:CreateMaskTexture()
        if not m then return nil end
        m:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(view)
        masks[frame] = m
    end
    return m
end

local function ShapeOne(t)
    local want = IsRound()
    if (masked[t] == true) == want then return end
    local frame = registered[t]
    if not (frame and frame.CreateMaskTexture) then return end
    local m = MaskFor(frame)
    if not m then return end
    if want then pcall(t.AddMaskTexture, t, m) else pcall(t.RemoveMaskTexture, t, m) end
    masked[t] = want or nil
end

-- Every module making textures on the far view passes them here once.
function Far.Shape(t)
    if not t or registered[t] or not view then return end
    registered[t] = t:GetParent()
    ShapeOne(t)
end

function Far.ApplyShape()
    for t in pairs(registered) do ShapeOne(t) end
end

-- Whether the cursor is on the map (always, on a square one): the empty corners of a round map
-- take no hovers or clicks.
function CursorInside()
    if not IsRound() then return true end
    local vx, vy = view:GetCenter()
    if not vx then return true end
    local s = view:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    return G.InCircle(cx / s - vx, cy / s - vy, view:GetWidth() / 2)
end

----------------------------------------------------------------------------------------------------
-- Setup

-- The player arrow: the native arrow's size at this map size, times the arrow size setting.
function Far.ApplyArrowSize()
    if not arrow then return end
    local s = ARROW_SIZE * ns.db.size / max(ns.Shell.nativeSize or 1, 1) * (ns.db.arrowScale or 1)
    arrow:SetSize(s, s)
end

-- Called by the shell after every layout pass (size change, Edit Mode, CVar).
function Far.OnShellApplied()
    if not view then return end
    Far.ApplyArrowSize()
    layoutDirty = true
    Far.ApplyShape()
    -- Proxy sizes follow the native icons, which scale with the Minimap.
    if ns.Mirror then ns.Mirror.MarkAllDirty() end
    PlaceRecenter() -- the map may have moved
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
    Far.Shape(bg)

    canvas = CreateFrame("Frame", nil, view)
    canvas:SetSize(1, 1)
    canvas:SetPoint("CENTER", view, "CENTER")
    canvas:SetFrameLevel(level + 1)

    -- Pins (Phase 2) sit between the terrain and the arrow: two layers at level + 2 and + 3.
    if ns.Mirror then ns.Mirror.Build(canvas, view, level + 2) end
    -- Quest areas: one frame per zone in view, above the terrain, below the icons.
    if ns.Areas then ns.Areas.Build(canvas, level + 1) end
    -- Pings: on top of everything on the canvas.
    if ns.Pings then ns.Pings.Build(canvas, level + 7) end
    -- NPC routes: lines on the canvas itself, above its terrain, below the icon layers.
    if ns.Routes then ns.Routes.Build(canvas) end
    -- Party and raid dots: above the icons, below the player arrow (level + 5).
    if ns.Party then ns.Party.Build(canvas, view, level + 4) end
    if ns.FarArt then ns.FarArt.Build(canvas, view, level + 6) end
    if ns.Caves then ns.Caves.Build(canvas, view, level + 6) end
    view:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and CursorInside() then
            local x, y = Cursor()
            BeginDrag(x, y, false)
        end
    end)
    view:SetScript("OnMouseUp", function(_, button)
        local wasDrag = drag and drag.moved
        if button == "LeftButton" and drag then FinishDrag() end
        if wasDrag or not CursorInside() then return end
        if ns.Mirror and ns.Mirror.Click(button) then return end
        OnViewClick(button)
    end)
    view:SetScript("OnLeave", function()
        if ns.Mirror then ns.Mirror.ClearHover() end
        if ns.Party then ns.Party.SetHover(nil) end
    end)

    arrowFrame = CreateFrame("Frame", nil, view)
    arrowFrame:SetAllPoints(view)
    arrowFrame:SetFrameLevel(level + 5)
    arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("CENTER", view, "CENTER")
    if arrow:SetTexture(ARROW_TEXTURE) == false then
        arrow:SetColorTexture(1, 0.82, 0, 1) -- fallback so the player is still marked
    end
    Far.Shape(arrow)

    -- Shown while panned.
    -- Shown while panned: a flat chip in the bars' style.
    recenter = CreateFrame("Button", nil, root, "BackdropTemplate")
    recenter:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    recenter:SetBackdropColor(0.05, 0.06, 0.08, 0.85)
    recenter:SetBackdropBorderColor(0, 0, 0, 1)
    recenter.label = recenter:CreateFontString(nil, "OVERLAY")
    recenter.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    recenter.label:SetShadowOffset(1, -1)
    recenter.label:SetShadowColor(0, 0, 0, 0.9)
    recenter.label:SetPoint("CENTER")
    recenter.label:SetText("Recenter")
    recenter.label:SetTextColor(0.92, 0.92, 0.92)
    recenter:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)
        self.label:SetTextColor(1, 0.82, 0)
    end)
    recenter:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        self.label:SetTextColor(0.92, 0.92, 0.92)
    end)
    recenter:SetFrameLevel(level + 30)
    recenter:SetScript("OnClick", Far.Recenter)
    recenter:SetScript("OnShow", PlaceRecenter)
    recenter:Hide()

    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", OnWheel)
    HookNativeMouse()
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
    if lastLoad then
        ns.Printf("last fill: %d tiles in %.2f s (at %.0f yd)", lastLoad[2], lastLoad[1], lastLoad[3] or 0)
    end
end)

ns.RegisterCommand("maxzoom", "set the far-zoom limit in yards (500-6400), e.g. /fzm maxzoom 6400", function(arg)
    if not tonumber(arg) then
        ns.Printf("max far zoom is %d yd; usage: /fzm maxzoom 6400", ns.db.maxFarZoom)
        return
    end
    Far.SetMaxZoom(arg)
    ns.Printf("max far zoom %d yd", ns.db.maxFarZoom)
end)

ns.RegisterCommand("smooth", "toggle smooth zooming", function()
    ns.db.smoothZoom = not ns.db.smoothZoom
    ns.Printf("smooth zoom %s", ns.db.smoothZoom and "on" or "off")
end)
