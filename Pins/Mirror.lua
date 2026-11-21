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

local G, IconPrefs = ns.Geometry, ns.IconPrefs

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
local refLabels = {}      -- HBD ref -> owning addon's folder name
local categories = {}     -- category key -> display label
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

-- Something SetTexture accepts for a source texture region, or nil.
-- Files outside the client's listfile (addons' own icons) get negative file ids, and SetTexture
-- rejects those ("integer overflow attempting to store 4294954171"). GetTextureFilePath usually
-- gives the path instead, but not always (seen on 1.60.1 for Questie's sword icon). Then: a path
-- learned earlier for that id, or Questie's own path for the icon type.
local learnedPaths = {} -- negative file id -> path
Mirror.unresolved = 0

local function ResolveTexture(region, icon)
    local id = region:GetTexture()
    local path = region.GetTextureFilePath and region:GetTextureFilePath()
    if type(path) == "string" and path ~= "" then
        if type(id) == "number" and id < 0 then learnedPaths[id] = path end
        return path
    end
    if type(path) == "number" and path > 0 then return path end
    if type(id) == "string" and id ~= "" then return id end
    if type(id) == "number" then
        if id > 0 then return id end
        if learnedPaths[id] then return learnedPaths[id] end
    end
    local questie = _G.Questie
    if region == icon.texture and icon.data and type(questie) == "table" and type(questie.usedIcons) == "table" then
        local q = questie.usedIcons[icon.data.Icon]
        if type(q) == "string" or (type(q) == "number" and q > 0) then
            if type(id) == "number" then learnedPaths[id] = q end
            return q
        end
    end
    return nil, id
end

-- Copies one texture region of the source frame onto a proxy texture. False if it has no
-- texture we can draw.
local function CopyRegion(dst, src, icon, frameW, frameH, ratio)
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        local tex, badId = ResolveTexture(src, icon)
        if not tex then
            Mirror.unresolved = Mirror.unresolved + 1
            Mirror.lastUnresolved = badId
            return false
        end
        dst:SetTexture(tex)
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
    -- Base size and offset; Place scales them by the category's size and the zoom.
    dst.bw, dst.bh = w * ratio, h * ratio
    dst.ox, dst.oy = ox * ratio, oy * ratio
    return true
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
        if CopyRegion(t, regionList[i], icon, fw, fh, ratio) then
            t:SetAlpha(alpha)
            p.nTex = p.nTex + 1
            p.tex[p.nTex] = t
        else
            t:Hide()
            layer.pool[#layer.pool + 1] = t
        end
    end
    p.bhw, p.bhh = fw * ratio / 2, fh * ratio / 2
end

----------------------------------------------------------------------------------------------------
-- Placement

local function Hide(p)
    for i = 1, p.nTex do p.tex[i]:Hide() end
    p.drawn = false
end

local function Place(p)
    if not layout or p.hidden or p.userHidden or p.inst ~= layout.inst or p.nTex == 0 then
        Hide(p)
        return
    end
    local x, y = G.WorldToPixel(p.n, p.w, layout.n, layout.w, layout.ppy)
    local k = p.scale * (p.shrink and layout.shrink or 1)
    p.x, p.y, p.hw, p.hh = x, y, p.bhw * k, p.bhh * k
    local frame = p.layer.frame
    for i = 1, p.nTex do
        local t = p.tex[i]
        t:SetSize(t.bw * k, t.bh * k)
        t:SetPoint("CENTER", frame, "CENTER", x + t.ox * k, y + t.oy * k)
        t:Show()
    end
    p.drawn = true
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
-- shrink is the zoom's scale for "shrink with zoom" icons (Zoom.Shrink).
function Mirror.SetLayout(inst, n, w, ppy, shrink)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy, layout.shrink = inst, n, w, ppy, shrink or 1
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

-- The addon that owns a ref: the first AddOns folder on the call stack that isn't ours or an
-- HBD library. Runs once per ref, from the Add hook, so the stack walk is rare.
local function LabelFromStack()
    if not debugstack then return nil end
    local stack = debugstack(3, 15, 0) or ""
    for line in stack:gmatch("[^\n]+") do
        local folder = line:match("AddOns[/\\]([^/\\]+)[/\\]")
        if folder and folder ~= ns.name and not line:find("HereBeDragons", 1, true) then
            return folder
        end
    end
end

local function LabelForRef(ref)
    if type(ref) == "string" then return ref end
    for _, name in ipairs({ "TomTom", "RareScanner", "HandyNotes", "GatherMate2" }) do
        if _G[name] ~= nil and _G[name] == ref then return name end
    end
    return "Other"
end

local function RefOf(src, icon)
    local registry = src.lib.minimapPinRegistry
    if type(registry) ~= "table" then return nil end
    for ref, set in pairs(registry) do
        if type(set) == "table" and set[icon] then return ref end
    end
end

local function CategoryOf(p, src)
    if src.questie then return IconPrefs.QuestieKey(p.icon.data and p.icon.data.Type) end
    local ref = RefOf(src, p.icon)
    local label = ref ~= nil and (refLabels[ref] or LabelForRef(ref)) or "Other"
    local key = IconPrefs.AddonKey(label)
    categories[key] = categories[key] or label
    return key
end

local function ApplyPrefs(p)
    p.userHidden, p.scale, p.shrink = IconPrefs.Get(ns.db, p.key)
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
    p.key = CategoryOf(p, src)
    categories[p.key] = categories[p.key] or p.key
    ApplyPrefs(p)
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
    local function OnIcon(_, ref, icon)
        if icon then dirty[icon] = src end
        if ref ~= nil and refLabels[ref] == nil then
            refLabels[ref] = LabelFromStack() or LabelForRef(ref)
        end
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
            src.questie = src.name:find("Questie", 1, true) ~= nil
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

-- Re-reads preferences for every proxy and redraws (after /fzm icons changes them).
function Mirror.RefreshPrefs()
    for _, p in pairs(proxies) do
        if p.key then ApplyPrefs(p) end
        Place(p)
    end
    if hovered and not hovered.drawn then Mirror.ClearHover() end
end

local ICONS_HELP = {
    "/fzm icons <group> hide | show",
    "/fzm icons <group> size 0.6   (0.25 - 3)",
    "/fzm icons <group> shrink on | off   (smaller as you zoom out)",
    "/fzm icons <group> reset",
    "<group>: a name from the list, a Questie type (monster, item...), questie, or all",
}

local function ListIcons()
    local counts = {}
    for _, p in pairs(proxies) do
        if p.key then counts[p.key] = (counts[p.key] or 0) + 1 end
    end
    local keys = {}
    for k in pairs(counts) do keys[#keys + 1] = k end
    table.sort(keys)
    ns.Print("icon groups (count, size, shrink with zoom):")
    for _, k in ipairs(keys) do
        local hide, scale, shrink = IconPrefs.Get(ns.db, k)
        ns.Printf("  %s  %d  x%.2f  %s%s", k, counts[k], scale, shrink and "shrink" or "fixed",
            hide and "  HIDDEN" or "")
    end
    for _, line in ipairs(ICONS_HELP) do ns.Print(line) end
end

ns.RegisterCommand("icons", "show, hide or resize icon groups: /fzm icons", function(arg)
    local name, action, value = (arg or ""):match("^(%S+)%s+(%S+)%s*(%S*)")
    if not name then
        ListIcons()
        return
    end
    local keys, err = IconPrefs.Apply(ns.db, name, categories, action, value)
    if not keys then
        ns.Print(err)
        for _, line in ipairs(ICONS_HELP) do ns.Print(line) end
        return
    end
    Mirror.RefreshPrefs()
    ns.Printf("%s: %s %s", table.concat(keys, ", "), action, value or "")
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
    if Mirror.unresolved > 0 then
        ns.Printf("  textures that couldn't be copied: %d (last id %s)", Mirror.unresolved, ns.Show(Mirror.lastUnresolved))
    end
    for _, src in ipairs(sources) do
        local n = 0
        for _ in pairs(src.lib.minimapPins or {}) do n = n + 1 end
        ns.Printf("  %s: %d pins (minor %s)", src.name, n, ns.Show(src.minor))
    end
end)
