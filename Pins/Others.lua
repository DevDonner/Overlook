-- Other addons' things on the minimap, while the far map shows.
--
-- In far mode the native Minimap sits at alpha 0 under our view (so HereBeDragons keeps updating
-- its pins), and everything other addons put on it went with it. Not every addon draws through
-- HereBeDragons (Pins/Mirror.lua): some parent their own frames and textures to the Minimap and
-- place them with their own maths (Factoruide's route dots, item and rare finders). And minimap
-- addons hang their furniture on it: EllesmereUI's border, zone text and button column, LibDBIcon
-- buttons. Each direct child of the Minimap is sorted (Others.Kind) into:
--  * furniture (buttons, text, borders): kept showing over the far map. It ignores the Minimap's
--    alpha and is raised above our view while far mode lasts; put back as it was afterwards.
--    Setting: keepOthersVisible.
--  * drawings (small pictures inside the map that stand for a place): copied onto the far map at
--    that place, grouped by the addon that drew them. Each group gets show / size / shrink in the
--    settings' Icons tab like any other ("drawn:<addon>" keys). Setting: captureOthers.
--  * left alone: HereBeDragons pins and Questie (the mirror has them), the game's own frames,
--    anything hidden, and big mouse-taking frames (they'd swallow the far map's clicks).
--
-- Where a drawing stands: the native map keeps its widest zoom under far mode, centred on the
-- player, so a picture's offset from the Minimap's centre divided by the native pixels per yard
-- is its offset from the player in yards (turned back by the facing when the map rotates).
local _, ns = ...

local G, IconPrefs = ns.Geometry, ns.IconPrefs

local Others = {}
ns.Others = Others

local SCAN_EVERY, PLACE_EVERY = 0.5, 0.1 -- seconds: looking for new things; moving the copies
local SMALL = 0.25                       -- a drawing is at most this part of the map's width
local RAISE = 25                         -- furniture's level above the view's

-- The game's own frames on the Minimap, by name; and Questie (mirrored, in its own group frame).
local SKIP_NAMES = { "^Minimap", "^MiniMap", "^GameTime", "^QueueStatus", "^ExpansionLanding",
    "^AddonCompartment", "^TimeManager", "^Overlook", "^Questie", "^HereBeDragons" }
local SKIP_KEYS = { "ZoomIn", "ZoomOut", "ZoomHitArea" } -- the Minimap's own parts, by key

----------------------------------------------------------------------------------------------------
-- Pure parts (the offline tests cover these)

-- Whether a frame name belongs to the game, Questie or us.
function Others.SkipName(name)
    if type(name) ~= "string" then return false end
    for _, p in ipairs(SKIP_NAMES) do
        if name:find(p) then return true end
    end
    return false
end

-- Sorts one child of the Minimap from what can be read off it:
--   skip (ours, a pin, the game's), shown, alpha, button (a Button), text (shows text),
--   mouse (takes the mouse), w, h, inside (its centre is on the map), map (the map's width).
-- Returns "skip", "furniture", "drawing" or "container" (covers the map: look inside it).
function Others.Kind(f)
    if f.skip or not f.shown or (f.alpha or 1) <= 0 then return "skip" end
    if f.button or f.text then return "furniture" end
    local map = f.map or 1
    local w, h = f.w or 0, f.h or 0
    if w >= 0.6 * map and h >= 0.6 * map then
        if f.mouse then return "skip" end -- a click blocker over the whole map
        return "container"
    end
    if w <= SMALL * map and h <= SMALL * map and f.inside then return "drawing" end
    return "furniture"
end

-- Whether a texture inside a container is a drawing: small and on the map (not a border strip).
function Others.SmallInside(w, h, inside, map)
    return inside and w > 0 and h > 0 and w <= SMALL * map and h <= SMALL * map
end

-- A point drawn dx, dy px (right, up) from the Minimap's centre at ppy px per yard: yards north and
-- west of the player. facing: the player's facing when the minimap rotates with it, else nil.
function Others.WorldOffset(dx, dy, ppy, facing)
    local x, y = dx / ppy, dy / ppy
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        x, y = x * c - y * s, x * s + y * c
    end
    return y, -x
end

-- The addon that drew something: a loaded addon whose folder name (or its first word) starts the
-- frame's name, or the folder in a texture's path; else "Other addons". addons: folder names.
function Others.Owner(name, path, addons)
    if type(path) == "string" then
        local folder = path:match("[Aa][Dd][Dd][Oo][Nn][Ss][/\\]([^/\\]+)[/\\]")
        if folder then return folder end
    end
    if type(name) == "string" and name ~= "" then
        local lower, best, bestLen = name:lower(), nil, 0
        for _, folder in ipairs(addons or {}) do
            for _, stem in ipairs({ folder, folder:match("^([^_%-]+)") }) do
                local l = stem and stem:lower()
                if l and #l >= 3 and #l > bestLen and lower:sub(1, #l) == l then
                    best, bestLen = folder, #l
                end
            end
        end
        if best then return best end
    end
    return "Other addons"
end

function Others.Key(owner)
    return IconPrefs.DrawnKey(owner)
end

----------------------------------------------------------------------------------------------------
-- In game

local view, layer, pool = nil, nil, {}
local far = false
local layout                -- { inst, n, w, ppy, shrink } while far mode draws; nil otherwise
local lifted = {}           -- [frame] = { level, ignore } as it was, while lifted
local copies = {}           -- [source texture] = copy { src, tex, key, n, w, inst }
local categories = {}       -- [key] = label
local addonNames            -- loaded addons' folder names, read once
local skipForever = setmetatable({}, { __mode = "k" }) -- frames known to be the game's or Questie's

Others._copies, Others._lifted = copies, lifted -- for the offline tests

local function AddonNames()
    if addonNames then return addonNames end
    addonNames = {}
    local api = _G.C_AddOns
    if api and api.GetNumAddOns and api.GetAddOnInfo then
        for i = 1, api.GetNumAddOns() do
            local okI, name = pcall(api.GetAddOnInfo, i)
            if okI and type(name) == "string" and (not api.IsAddOnLoaded or api.IsAddOnLoaded(name)) then
                addonNames[#addonNames + 1] = name
            end
        end
    end
    return addonNames
end

-- Size and centre of a region in the Minimap's units, or nil when it isn't laid out.
local function Rect(region, mScale)
    local x, y = region:GetCenter()
    local w, h = region:GetSize()
    if not (x and y and w and h) then return nil end
    local k = (region.GetEffectiveScale and region:GetEffectiveScale() or mScale) / mScale
    return x * k, y * k, w * k, h * k
end

local function HasText(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("FontString") and r:IsShown() then
            local t = r:GetText()
            if type(t) == "string" and t ~= "" then return true end
        end
    end
    return false
end

local function OwnKeys()
    local set = {}
    for _, k in ipairs(SKIP_KEYS) do
        local f = rawget(Minimap, k)
        if f then set[f] = true end
    end
    return set
end

-- What Others.Kind needs to know about a frame.
local function Describe(frame, mx, my, mw, mh, mScale, own)
    local d = { map = mw }
    if skipForever[frame] then d.skip = true return d end
    local okN, name = pcall(frame.GetName, frame)
    if own[frame] or Others.SkipName(okN and name or nil) then
        skipForever[frame] = true
        d.skip = true
        return d
    end
    if ns.Mirror and ns.Mirror.IsPin and ns.Mirror.IsPin(frame) then d.skip = true return d end
    d.shown = frame:IsShown() == true
    if not d.shown then return d end
    d.alpha = frame:GetAlpha()
    d.button = frame:IsObjectType("Button") or (ns.Buttons and ns.Buttons.LooksLikeButton(okN and name or nil))
    d.mouse = frame:IsMouseEnabled()
    d.text = HasText(frame)
    local x, y, w, h = Rect(frame, mScale)
    if not x then d.skip = true return d end
    d.w, d.h = w, h
    d.inside = math.abs(x - mx) < mw / 2 and math.abs(y - my) < mh / 2
    d.name = okN and name or nil
    return d
end

----------------------------------------------------------------------------------------------------
-- Furniture: kept over the far map

local function ViewTop()
    return (view and view:GetFrameLevel() or 0) + RAISE, view and view:GetFrameStrata()
end

local function Lift(frame)
    local top, strata = ViewTop()
    local was = lifted[frame]
    if not was then
        was = { level = frame:GetFrameLevel() }
        lifted[frame] = was
        if frame.SetIgnoreParentAlpha then pcall(frame.SetIgnoreParentAlpha, frame, true) end
    end
    -- Raised only within our own strata: a frame in a higher strata is above the view already.
    if frame:GetFrameStrata() == strata and frame:GetFrameLevel() < top then
        if frame.SetFixedFrameLevel then pcall(frame.SetFixedFrameLevel, frame, false) end
        frame:SetFrameLevel(top)
        was.raised = true
    end
end

local function Drop(frame, was)
    if frame.SetIgnoreParentAlpha then pcall(frame.SetIgnoreParentAlpha, frame, false) end
    if was.raised then frame:SetFrameLevel(was.level) end
end

local function DropAll()
    for frame, was in pairs(lifted) do
        pcall(Drop, frame, was)
        lifted[frame] = nil
    end
end
Others.DropAll = DropAll

----------------------------------------------------------------------------------------------------
-- Drawings: copied onto the far map

local function Acquire()
    local t = table.remove(pool)
    if not t then
        t = layer:CreateTexture(nil, "ARTWORK")
        if ns.Far and ns.Far.Shape then ns.Far.Shape(t) end
    end
    return t
end

local function Release(src)
    local c = copies[src]
    if not c then return end
    c.tex:Hide()
    c.tex:ClearAllPoints()
    pool[#pool + 1] = c.tex
    copies[src] = nil
end

local function ReleaseAll()
    for src in pairs(copies) do Release(src) end
end

-- Copies the picture (texture or atlas, colour, blend) of a source texture.
local function CopyLook(dst, src)
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        local tex = ns.Mirror and ns.Mirror.ResolveTexture and ns.Mirror.ResolveTexture(src, src) or src:GetTexture()
        if not tex or not pcall(dst.SetTexture, dst, tex) then return false end
        dst:SetTexCoord(src:GetTexCoord())
    end
    local r, g, b, a = src:GetVertexColor()
    dst:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    dst:SetBlendMode(src:GetBlendMode())
    return true
end

local function Place(c)
    local t = c.tex
    if not layout or c.inst ~= layout.inst or not c.n then
        t:Hide()
        return
    end
    local hide, scale, shrink = IconPrefs.Get(ns.db, c.key)
    if hide then
        t:Hide()
        return
    end
    local k = scale * (shrink and layout.shrink or 1)
    local x, y = G.WorldToPixel(c.n, c.w, layout.n, layout.w, layout.ppy)
    t:SetSize(c.bw * k, c.bh * k)
    t:ClearAllPoints()
    t:SetPoint("CENTER", layer, "CENTER", x, y)
    t:Show()
end

-- The native map's pixels per yard, in the Minimap's units.
local function NativePPY(mw)
    local r = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    if type(r) ~= "number" or r <= 0 or ns.IsSecret(r) then return nil end
    return mw / 2 / r
end

local function Facing()
    local ok, v = pcall(GetCVar, "rotateMinimap")
    if not (ok and v == "1") then return nil end
    local f = GetPlayerFacing()
    if type(f) ~= "number" or ns.IsSecret(f) then return nil end
    return f
end

-- Where a source texture stands in the world now: sets c.n, c.w, c.bw, c.bh.
local function Measure(c, mx, my, mScale, ppy, pn, pw, facing)
    local x, y, w, h = Rect(c.src, mScale)
    if not x then
        c.n = nil
        return
    end
    local dn, dw = Others.WorldOffset(x - mx, y - my, ppy, facing)
    c.n, c.w = pn + dn, pw + dw
    -- Its size on the far map: the same as on screen, in the layer's units.
    local ratio = mScale / layer:GetEffectiveScale()
    c.bw, c.bh = w * ratio, h * ratio
end

local function Shown(region)
    return region:IsShown() and (region:GetAlpha() or 1) > 0
end

-- Finds the drawings and furniture on the Minimap; copies new drawings, drops gone ones.
local seen = {}
local function Scan()
    if not (far and Minimap) then return end
    local mx, my = Minimap:GetCenter()
    local mw, mh = Minimap:GetSize()
    if not (mx and mw and mw > 0) then return end
    local mScale = Minimap:GetEffectiveScale()
    local own = OwnKeys()
    local keepFurniture = ns.db.keepOthersVisible ~= false
    local capture = ns.db.captureOthers ~= false
    for k in pairs(seen) do seen[k] = nil end

    local function Drawing(src, owner)
        seen[src] = true
        if copies[src] then return end
        local tex = Acquire()
        if not CopyLook(tex, src) then
            pool[#pool + 1] = tex
            return
        end
        local key = Others.Key(owner)
        if not categories[key] then
            categories[key] = owner .. " (drawn on the map)"
            if ns.Mirror and ns.Mirror.AddCategory then ns.Mirror.AddCategory(key, categories[key]) end
        end
        copies[src] = { src = src, tex = tex, key = key }
    end

    -- A frame's pictures that are drawings (all of them for a drawing frame; in a container, only
    -- the small ones on the map). Copied when capturing; returns how many there are either way.
    local function Textures(frame, owner, smallOnly)
        local n = 0
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("Texture") and Shown(r) then
                local x, y, w, h = Rect(r, mScale)
                if x then
                    local inside = math.abs(x - mx) < mw / 2 and math.abs(y - my) < mh / 2
                    if not smallOnly or Others.SmallInside(w, h, inside, mw) then
                        n = n + 1
                        if capture then
                            local path = r.GetTextureFilePath and r:GetTextureFilePath()
                            Drawing(r, owner or Others.Owner(nil, path, AddonNames()))
                        end
                    end
                end
            end
        end
        return n
    end

    -- The addon a frame's name says drew it; nil lets each picture's own file say.
    local function NamedOwner(name)
        local owner = name and Others.Owner(name, nil, AddonNames()) or nil
        if owner == "Other addons" then return nil end
        return owner
    end

    local function Sort(frame, depth)
        local d = Describe(frame, mx, my, mw, mh, mScale, own)
        local kind = Others.Kind(d)
        if kind == "furniture" then
            if keepFurniture then Lift(frame) end
            return 0
        elseif kind == "drawing" then
            return Textures(frame, NamedOwner(d.name), false)
        elseif kind == "container" then
            local owner = NamedOwner(d.name)
            local n = Textures(frame, owner, true)
            if depth < 1 then
                for _, child in ipairs({ frame:GetChildren() }) do n = n + Sort(child, depth + 1) end
            end
            -- Nothing drawn in it: a border or frame of the map's own, kept showing. (One with
            -- drawings stays under the view: its pictures stand where the native zoom puts them.)
            if n == 0 and keepFurniture then Lift(frame) end
            return n
        end
        return 0
    end

    for _, child in ipairs({ Minimap:GetChildren() }) do
        local ok, err = pcall(Sort, child, 0)
        if not ok and ns.Print and not Others.reported then
            Others.reported = true
            ns.Print("other addons' minimap things: " .. tostring(err) .. " (reported once)")
        end
    end
    for src in pairs(copies) do
        if not seen[src] then Release(src) end
    end
end
Others.Scan = Scan

-- Moves the copies to where their sources stand now.
local function PlaceAll()
    if not (far and Minimap and layout) then return end
    local mx, my = Minimap:GetCenter()
    local mw = Minimap:GetWidth()
    local ppy = mw and NativePPY(mw)
    local pn, pw
    if ns.Far then pn, pw = ns.Far.PlayerWorld() end -- (not `a and f()`: that keeps one value)
    if not (mx and ppy and pn and pw) then return end
    local facing = Facing()
    local mScale = Minimap:GetEffectiveScale()
    for src, c in pairs(copies) do
        if Shown(src) then
            c.inst = layout.inst
            Measure(c, mx, my, mScale, ppy, pn, pw, facing)
            Place(c)
        else
            c.tex:Hide()
        end
    end
end
Others.PlaceAll = PlaceAll

----------------------------------------------------------------------------------------------------
-- Far mode calls these

-- Far mode starts (true) or ends (false).
function Others.SetFar(on)
    far = on and true or false
    if not view then return end
    if far then
        Scan()
        PlaceAll()
    else
        DropAll()
        ReleaseAll()
    end
end

-- The far map's layout (as for the mirror); nil when it goes.
function Others.SetLayout(inst, n, w, ppy, shrink)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy, layout.shrink = inst, n, w, ppy, shrink or 1
        PlaceAll()
    else
        layout = nil
        for _, c in pairs(copies) do c.tex:Hide() end
    end
end

-- A setting changed: start over.
function Others.Refresh()
    DropAll()
    ReleaseAll()
    if far then
        Scan()
        PlaceAll()
    end
end

-- Icon-group sizes changed (Icons tab).
function Others.RefreshPrefs()
    for _, c in pairs(copies) do Place(c) end
end

-- [key] = how many copies each group has now.
function Others.Counts()
    local counts = {}
    for _, c in pairs(copies) do counts[c.key] = (counts[c.key] or 0) + 1 end
    return counts
end

function Others.Build(canvas, farView, level)
    if view then return end
    view = farView
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetSize(1, 1)
    layer:SetPoint("CENTER", canvas, "CENTER")
    layer:SetFrameLevel(level)
    local scanT, placeT = 0, 0
    local driver = CreateFrame("Frame", nil, farView) -- runs only while the far view shows
    driver:SetScript("OnUpdate", function(_, dt)
        if not far then return end
        scanT, placeT = scanT + dt, placeT + dt
        if scanT >= SCAN_EVERY then
            scanT = 0
            Scan()
        end
        if placeT >= PLACE_EVERY then
            placeT = 0
            PlaceAll()
        end
    end)
end

ns.RegisterCommand("others", "show what other addons have on the minimap and how the far map treats it", function()
    local n = 0
    for _ in pairs(lifted) do n = n + 1 end
    local counts, groups = Others.Counts(), {}
    for key, c in pairs(counts) do groups[#groups + 1] = string.format("%s %d", categories[key] or key, c) end
    table.sort(groups)
    ns.Printf("far map %s; kept showing: %d frame(s) (%s); drawings copied: %s",
        far and "on" or "off", n, ns.db.keepOthersVisible ~= false and "on" or "off",
        #groups > 0 and table.concat(groups, ", ") or "none")
    if not far then ns.Print("(zoom out past the normal minimap to see them sorted)") end
end)
