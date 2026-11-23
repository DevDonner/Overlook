-- Caves on the far view. Indoors in a cave (or mine, or building), the far view draws one level
-- of the cave's own minimap images and hides the terrain, which only shows the surface there,
-- like the native minimap indoors. It sits on the far canvas like the tiles, so panning and
-- zooming work the same. The view starts at the top level; Alt+wheel moves through the levels
-- (Far/Far.lua).
-- The maths is in Core/CaveMath.lua and the data in Data/Caves.lua (tools/map-data/caves.py).
local _, ns = ...

local C, G = ns.CaveMath, ns.Geometry

local Caves = {}
ns.Caves = Caves

local CHECK_EVERY = 0.25 -- seconds between looks at which cave the player is in

local canvas, view, cover, label
local textures, shown = {}, 0
local placement          -- the placed cave the player is in, or nil
local quads = {}         -- CaveMath.Quads for it
local count = 1          -- its number of levels
local at = 1             -- the level looked at (1 = top)
local layout             -- { inst, n, w, ppy } while far mode is drawing
local caveInst           -- the instance the placement is on
local nextCheck = 0

local function Data(inst)
    local d = ns.CaveData
    return d and d[inst], d and d.wmo
end

local function Hide()
    for i = 1, shown do textures[i]:Hide() end
    shown = 0
    if cover then cover:Hide() end
    if label then label:Hide() end
end

local function Draw()
    Hide()
    if not (layout and placement and caveInst == layout.inst) then return end
    cover:Show()
    local n = 0
    for _, q in ipairs(quads) do
        if q.level == at then
            n = n + 1
            local tex = textures[n]
            if not tex then
                tex = canvas:CreateTexture(nil, "ARTWORK", nil, 2) -- above the cover
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                textures[n] = tex
            end
            tex:SetTexture(q.file)
            local x, y = G.WorldToPixel(q.north, q.west, layout.n, layout.w, layout.ppy)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", canvas, "CENTER", x, y)
            tex:SetSize(q.width * layout.ppy, q.height * layout.ppy)
            tex:SetRotation(q.rotation)
            tex:Show()
        end
    end
    shown = n
    if count > 1 then
        label:SetText(string.format("Level %d of %d  (Alt+wheel)", at, count))
        label:Show()
    end
end

local function SetPlacement(p, inst)
    if p == placement then return end
    placement, caveInst, at = p, inst, 1
    if p then
        local _, wmo = Data(inst)
        local groups = wmo[p[1]]
        quads, count = C.Quads(p, groups), C.LevelCount(groups)
    else
        quads, count = {}, 1
    end
    Draw()
end

-- Far mode calls this every frame with the player's position; it looks for the cave the player
-- is in every CHECK_EVERY seconds. Indoors only: outdoors the terrain is the right picture.
function Caves.Update(now, inst, north, west)
    if now < nextCheck then return end
    nextCheck = now + CHECK_EVERY
    local p
    if IsIndoors and IsIndoors() then
        local list, wmo = Data(inst)
        p = C.Pick(list, north, west, wmo)
    end
    SetPlacement(p, inst)
end

-- True while a cave is drawn (other underground maps then stand aside).
function Caves.IsDrawing()
    return layout ~= nil and placement ~= nil
end

-- True when Alt+wheel has levels to move through here.
function Caves.HasLevels()
    return Caves.IsDrawing() and count > 1
end

-- Alt+wheel: down (delta < 0) a level, wrapping past the bottom to the top. True when handled.
function Caves.StepLevel(delta)
    if not Caves.HasLevels() then return false end
    at = C.Step(at, count, delta)
    Draw()
    return true
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Caves.SetLayout(inst, n, w, ppy)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
        Draw()
    else
        layout, nextCheck = nil, 0
        SetPlacement(nil)
        Hide()
    end
end

function Caves.Level() return at, count end
function Caves.ShownTiles() return shown end

function Caves.Build(canvasFrame, viewFrame, level)
    canvas, view = canvasFrame, viewFrame
    -- Hides the terrain while a cave is drawn (above the tiles, below the cave images), in the
    -- far view's own background colour.
    cover = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    cover:SetAllPoints(view)
    cover:SetColorTexture(0.06, 0.07, 0.09, 1)
    cover:Hide()
    local top = CreateFrame("Frame", nil, view)
    top:SetAllPoints(view)
    top:SetFrameLevel(level)
    label = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", view, "TOP", 0, -4)
    label:Hide()
end

-- /fzm caves: what the far view knows about the cave here, for checking in game.
if ns.RegisterCommand then
    ns.RegisterCommand("caves", "show the cave the far view would draw here", function()
        local north, west, _, inst = UnitPosition("player")
        local list, wmo = Data(inst)
        local p = north and C.Pick(list, north, west, wmo)
        ns.Printf("indoors %s  caves on this continent %d  cave here %s",
            tostring(IsIndoors and IsIndoors()), list and #list or 0, p and ns.Show(p[1]) or "none")
        if p then
            ns.Printf("images %d  levels %d  looking at %d  drawn %d", #C.Quads(p, wmo[p[1]]),
                C.LevelCount(wmo[p[1]]), at, shown)
        end
    end)
end
