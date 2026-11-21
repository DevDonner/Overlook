-- Phase 2: the pin mirror. Draws a lightweight copy (a "proxy") of every HereBeDragons minimap pin
-- on the far view: Questie's private registry and the shared LibStub one (TomTom, RareScanner...).
-- Questie's own frames are never moved.
--
-- Keeping in step (design: Pin mirroring and Questie gotchas):
--  * Hooks on AddMinimapIconWorld / RemoveMinimapIcon / RemoveAllMinimapIcons mark icons dirty;
--    a 0.1 s ticker drains the dirty set, reading the registry then. AddMinimapIconMap goes
--    through AddMinimapIconWorld, so one hook covers both.
--  * Questie recycles frames (#21), so the look is re-copied every time an icon is drained.
--  * Questie hides icons with FakeHide/FakeShow (#22), which never touch HBD: each frame's own
--    FakeHide/FakeShow is hooked once.
--  * Every 2 s a reconcile pass compares the registries with our proxies, so a missed hook or an
--    HBD upgrade that replaced the hooked functions costs at most 2 s of staleness.
--  * Visibility comes from icon.hidden, never from alpha: Questie's distance fade starts minimap
--    icons at alpha 0, and showing those far-away icons is the whole point.
local _, ns = ...

local G = ns.Geometry

local Mirror = {}
ns.Mirror = Mirror

local DRAIN_EVERY, RECONCILE_EVERY = 0.1, 2

local sources = {}        -- from PinSources.List(): { name, lib, minor }
local hookedLibs = {}     -- lib table -> minor version we hooked
local proxies = {}        -- icon frame -> proxy
local dirty = {}          -- icon frame -> source
local hookedFrames = {}   -- icon frame -> true once FakeHide/FakeShow are hooked
local layers = {}         -- [1] normal pins, [2] pins drawn on top (Questie turn-ins, other addons)
local owner               -- the far view: tooltip owner and hit-test frame
local layout              -- { inst, n, w, ppy } while far mode is drawing; nil otherwise
local hovered
local reconcileNow = false
local reportedErrors = {}

Mirror._proxies = proxies -- read by the offline tests

local function Report(err)
    err = tostring(err)
    if reportedErrors[err] then return end
    reportedErrors[err] = true
    ns.Print("pin mirror error (reported once): " .. err)
end

----------------------------------------------------------------------------------------------------
-- Proxy textures

local function Acquire(layer)
    local t = table.remove(layer.pool)
    if not t then
        t = layer.frame:CreateTexture(nil, "ARTWORK")
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
    end
    return t
end

local function ReleaseTextures(p)
    for i = p.nTex, 1, -1 do
        local t = p.tex[i]
        t:Hide()
        t:ClearAllPoints()
        t:SetTexture(nil)
        local pool = p.layer.pool
        pool[#pool + 1] = t
        p.tex[i] = nil
    end
    p.nTex = 0
end

-- Questie draws turn-ins above everything else; mirror that with a second layer.
-- Other addons' pins (TomTom waypoints) are few and wanted on top too.
local function LayerFor(icon)
    if icon.data and icon.data.Type ~= "complete" then return layers[1] end
    return layers[2]
end

-- Copies one texture region of the source frame onto a proxy texture.
local function CopyRegion(dst, src, frameW, frameH, ratio)
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        -- GetTexture returns negative ids for files that aren't in the client's listfile (Questie's
        -- own icons); the path works for both.
        local path = src.GetTextureFilePath and src:GetTextureFilePath()
        dst:SetTexture(path or src:GetTexture())
        dst:SetTexCoord(src:GetTexCoord())
    end
    local r, g, b = src:GetVertexColor()
    dst:SetVertexColor(r or 1, g or 1, b or 1, 1) -- alpha is Questie's distance fade: ignored
    dst:SetBlendMode(src:GetBlendMode())
    if src.IsDesaturated then dst:SetDesaturated(src:IsDesaturated()) end
    dst:SetDrawLayer(src:GetDrawLayer())

    local w, h, ox, oy = frameW, frameH, 0, 0
    if src:GetNumPoints() < 2 then -- not SetAllPoints: keep its own size and centre offset
        local sw, sh = src:GetSize()
        if sw and sw > 0 and sh and sh > 0 then w, h = sw, sh end
        local point, _, relPoint, x, y = src:GetPoint(1)
        if point == "CENTER" and relPoint == "CENTER" then ox, oy = x or 0, y or 0 end
    end
    dst:SetSize(w * ratio, h * ratio)
    dst.ox, dst.oy = ox * ratio, oy * ratio
end

local regionList = {}
local function CopyLook(p)
    local icon = p.icon
    local layer = LayerFor(icon)
    ReleaseTextures(p)
    p.layer = layer

    local ratio = icon:GetEffectiveScale() / layer.frame:GetEffectiveScale()
    local fw, fh = icon:GetSize()
    fw, fh = fw or 16, fh or 16

    for i = #regionList, 1, -1 do regionList[i] = nil end
    for _, region in ipairs({ icon:GetRegions() }) do
        if region:IsObjectType("Texture") and region:IsShown() then
            regionList[#regionList + 1] = region
        end
    end

    local alpha = icon:GetAlpha() or 1 -- Questie dims party members' objectives with frame alpha
    for i = 1, #regionList do
        local t = Acquire(layer)
        CopyRegion(t, regionList[i], fw, fh, ratio)
        t:SetAlpha(alpha)
        p.nTex = p.nTex + 1
        p.tex[p.nTex] = t
    end
    p.hw, p.hh = fw * ratio / 2, fh * ratio / 2
end

----------------------------------------------------------------------------------------------------
-- Placement

local function Hide(p)
    for i = 1, p.nTex do p.tex[i]:Hide() end
    p.drawn = false
end

local function Place(p)
    if not layout or p.hidden or p.inst ~= layout.inst or p.nTex == 0 then
        Hide(p)
        return
    end
    local x, y = G.WorldToPixel(p.n, p.w, layout.n, layout.w, layout.ppy)
    p.x, p.y = x, y
    local frame = p.layer.frame
    for i = 1, p.nTex do
        local t = p.tex[i]
        t:SetPoint("CENTER", frame, "CENTER", x + t.ox, y + t.oy)
        t:Show()
    end
    p.drawn = true
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Mirror.SetLayout(inst, n, w, ppy)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
    else
        layout = nil
        Mirror.ClearHover()
    end
    for _, p in pairs(proxies) do Place(p) end
end

----------------------------------------------------------------------------------------------------
-- Registry tracking

local function MarkDirtyFrame(icon)
    local p = proxies[icon]
    if p then dirty[icon] = p.source end
end

local function HookFrame(icon)
    if hookedFrames[icon] then return end
    hookedFrames[icon] = true
    if type(icon.FakeHide) == "function" then hooksecurefunc(icon, "FakeHide", MarkDirtyFrame) end
    if type(icon.FakeShow) == "function" then hooksecurefunc(icon, "FakeShow", MarkDirtyFrame) end
end

local function Remove(icon)
    local p = proxies[icon]
    if not p then return end
    if hovered == p then Mirror.ClearHover() end
    ReleaseTextures(p)
    proxies[icon] = nil
end

local function Update(icon, src)
    local data = src.lib.minimapPins and src.lib.minimapPins[icon]
    if not data then
        Remove(icon)
        return
    end
    local p = proxies[icon]
    if not p then
        p = { icon = icon, tex = {}, nTex = 0 }
        proxies[icon] = p
    end
    HookFrame(icon)
    p.source = src
    -- HBD world coordinates: x is UnitPosition's second value (west), y its first (north).
    p.n, p.w, p.inst = data.y, data.x, data.instanceID
    p.hidden = icon.hidden == true
    CopyLook(p)
    Place(p)
end

local function Drain()
    if reconcileNow then Mirror.Reconcile() end
    for icon, src in pairs(dirty) do
        dirty[icon] = nil
        local ok, err = pcall(Update, icon, src)
        if not ok then Report(err) end
    end
end

-- Marks anything that differs between the registries and our proxies.
function Mirror.Reconcile()
    reconcileNow = false
    for _, src in ipairs(sources) do
        local reg = src.lib.minimapPins
        if type(reg) == "table" then
            for icon, data in pairs(reg) do
                local p = proxies[icon]
                if not p or p.source ~= src or p.n ~= data.y or p.w ~= data.x
                    or p.inst ~= data.instanceID or p.hidden ~= (icon.hidden == true) then
                    dirty[icon] = src
                end
            end
        end
    end
    for icon, p in pairs(proxies) do
        local reg = p.source.lib.minimapPins
        if not (reg and reg[icon]) then dirty[icon] = p.source end
    end
end

function Mirror.MarkAllDirty()
    for icon, p in pairs(proxies) do dirty[icon] = p.source end
end

local function HookSource(src)
    local lib = src.lib
    if hookedLibs[lib] == (src.minor or true) then return end
    hookedLibs[lib] = src.minor or true
    -- Hooks may end up doubled after an HBD upgrade; marking dirty twice is harmless.
    local function OnIcon(_, _, icon)
        if icon then dirty[icon] = src end
    end
    for _, name in ipairs({ "AddMinimapIconWorld", "RemoveMinimapIcon" }) do
        if type(lib[name]) == "function" then hooksecurefunc(lib, name, OnIcon) end
    end
    if type(lib.RemoveAllMinimapIcons) == "function" then
        hooksecurefunc(lib, "RemoveAllMinimapIcons", function() reconcileNow = true end)
    end
end

-- Picks up the registries (again after an addon loads: a newer shared HBD may have replaced
-- the hooked functions) and hooks any that are new or upgraded.
function Mirror.RefreshSources()
    local list = ns.PinSources.List()
    for _, src in ipairs(list) do
        local known
        for _, old in ipairs(sources) do
            if old.lib == src.lib then known = old end
        end
        if known then
            known.minor = src.minor
            HookSource(known)
        else
            sources[#sources + 1] = src
            HookSource(src)
        end
    end
    reconcileNow = true
end

----------------------------------------------------------------------------------------------------
-- Hover and click: one hit test over the proxies, only while the mouse is over the far view.

local tooltipModule
local function QuestieTooltip()
    if tooltipModule == nil then
        tooltipModule = false
        if QuestieLoader then
            local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "MapIconTooltip")
            if ok and type(mod) == "table" and type(mod.ShowOnTooltip) == "function" then
                tooltipModule = mod
            end
        end
    end
    return tooltipModule
end

local function Enter(p)
    local icon = p.icon
    local mod = QuestieTooltip()
    local ok, err = true, nil
    if mod and icon.data and icon.texture then
        -- Passing an owner makes Questie skip its "faded to alpha 0, show nothing" check and
        -- anchor the tooltip to the cursor over our view. The tooltip is Questie's own.
        ok, err = pcall(mod.ShowOnTooltip, icon, GameTooltip, owner)
    else
        local f = icon:GetScript("OnEnter")
        if f then ok, err = pcall(f, icon) end
    end
    if not ok then Report(err) end
end

local function Leave(p)
    local f = p.icon:GetScript("OnLeave")
    if f then
        local ok, err = pcall(f, p.icon)
        if not ok then Report(err) end
    end
end

function Mirror.ClearHover()
    if hovered then
        local p = hovered
        hovered = nil
        Leave(p)
    end
end

local function HitTest()
    local s = layers[1].frame:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local lx, ly = layers[1].frame:GetCenter()
    if not lx then return nil end
    cx, cy = cx / s - lx, cy / s - ly
    local best, bestLayer, bestDist
    for _, p in pairs(proxies) do
        if p.drawn then
            local dx, dy = cx - p.x, cy - p.y
            if dx <= p.hw and dx >= -p.hw and dy <= p.hh and dy >= -p.hh then
                local li = p.layer == layers[2] and 2 or 1
                local d = dx * dx + dy * dy
                if not best or li > bestLayer or (li == bestLayer and d < bestDist) then
                    best, bestLayer, bestDist = p, li, d
                end
            end
        end
    end
    return best
end

-- Far mode calls this every frame while the mouse is over the view.
function Mirror.UpdateHover()
    local p = HitTest()
    if p == hovered then return end
    Mirror.ClearHover()
    hovered = p
    if p then Enter(p) end
end

function Mirror.Click(button)
    if not hovered then return end
    local icon = hovered.icon
    local f = icon:GetScript("OnClick")
    if f then
        local ok, err = pcall(f, icon, button)
        if not ok then Report(err) end
    end
end

----------------------------------------------------------------------------------------------------
-- Setup

function Mirror.Build(canvas, view, level)
    owner = view
    for i = 1, 2 do
        local f = CreateFrame("Frame", nil, canvas)
        f:SetSize(1, 1)
        f:SetPoint("CENTER", canvas, "CENTER")
        f:SetFrameLevel(level + i - 1)
        layers[i] = { frame = f, pool = {} }
    end
    Mirror.RefreshSources()
    C_Timer.NewTicker(DRAIN_EVERY, Drain)
    C_Timer.NewTicker(RECONCILE_EVERY, function() reconcileNow = true end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if layers[1] then Mirror.RefreshSources() end
end)

ns.RegisterCommand("pins", "show pin mirror counts", function()
    local total, drawn, hidden, other = 0, 0, 0, 0
    for _, p in pairs(proxies) do
        total = total + 1
        if p.drawn then drawn = drawn + 1 end
        if p.hidden then hidden = hidden + 1 end
        if layout and p.inst ~= layout.inst then other = other + 1 end
    end
    ns.Printf("proxies %d  drawn %d  hidden by Questie %d  other continent %d  sources %d",
        total, drawn, hidden, other, #sources)
    for _, src in ipairs(sources) do
        local n = 0
        for _ in pairs(src.lib.minimapPins or {}) do n = n + 1 end
        ns.Printf("  %s: %d pins (minor %s)", src.name, n, ns.Show(src.minor))
    end
end)
