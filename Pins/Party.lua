-- Party and raid members on the far map, as dots in their class colours. The game draws its own
-- dots only on the normal minimap; UnitPosition gives group members' positions, so the far map
-- draws its own. Dots sit above the icons and below the player arrow, on the canvas at the same
-- fixed origin as everything else, and move a few times a second.
local _, ns = ...

local G = ns.Geometry

local Party = {}
ns.Party = Party

local UPDATE_EVERY = 0.05
local DOT_SIZE = 9
local DOT_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local layer
local owner -- the far view: tooltip owner
local dots, used = {}, 0
local hovered -- the unit whose tooltip we show
local layout -- { inst, n, w, ppy } while far mode is drawing
local elapsed = 0

local function Secret(v)
    return ns.IsSecret(v)
end

local function Dot(i)
    local d = dots[i]
    if not d then
        d = {}
        d.border = layer:CreateTexture(nil, "ARTWORK", nil, 0)
        d.border:SetSize(DOT_SIZE + 2, DOT_SIZE + 2)
        d.border:SetTexture(DOT_TEXTURE)
        d.border:SetVertexColor(0, 0, 0, 0.9)
        d.fill = layer:CreateTexture(nil, "ARTWORK", nil, 1)
        d.fill:SetSize(DOT_SIZE, DOT_SIZE)
        d.fill:SetTexture(DOT_TEXTURE)
        dots[i] = d
    end
    return d
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    if Secret(class) or not class then return 0.7, 0.7, 0.7 end
    local c = (_G.C_ClassColor and _G.C_ClassColor.GetClassColor and _G.C_ClassColor.GetClassColor(class))
        or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

-- Group members other than the player: raid1..N in a raid, party1..4 in a party.
local function Units(out)
    for i = #out, 1, -1 do out[i] = nil end
    local n = GetNumGroupMembers() or 0
    if Secret(n) or n == 0 then return out end
    if IsInRaid() then
        for i = 1, n do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") then out[#out + 1] = u end
        end
    else
        for i = 1, math.min(n - 1, 4) do out[#out + 1] = "party" .. i end
    end
    return out
end

local units = {}

local function Draw()
    local n = 0
    if layout and ns.db.partyDots ~= false then
        for _, unit in ipairs(Units(units)) do
            local north, west, _, inst = UnitPosition(unit)
            if north and not (Secret(north) or Secret(west) or Secret(inst)) and inst == layout.inst then
                local x, y = G.WorldToPixel(north, west, layout.n, layout.w, layout.ppy)
                n = n + 1
                local d = Dot(n)
                local r, g, b = ClassColor(unit)
                local alpha = UnitIsConnected(unit) and 1 or 0.4
                d.unit, d.x, d.y = unit, x, y
                d.fill:SetVertexColor(r, g, b, alpha)
                d.border:SetAlpha(alpha)
                d.fill:SetPoint("CENTER", layer, "CENTER", x, y)
                d.border:SetPoint("CENTER", layer, "CENTER", x, y)
                d.fill:Show()
                d.border:Show()
            end
        end
    end
    for i = n + 1, used do
        dots[i].unit = nil
        dots[i].fill:Hide()
        dots[i].border:Hide()
    end
    used = n
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Party.SetLayout(inst, n, w, ppy)
    if not layer then return end
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
        layer:Show()
    else
        layout = nil
        Party.SetHover(nil)
        layer:Hide()
    end
    Draw()
end

-- The group member whose dot is under the cursor (nearest if several), or nil. The game shows
-- names for its own dots only on the normal minimap, so the far map finds the unit itself.
local HIT = DOT_SIZE / 2 + 1
function Party.UnitUnderCursor()
    if not layer or not layout or used == 0 then return nil end
    local lx, ly = layer:GetCenter()
    if not lx then return nil end
    local s = layer:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s - lx, cy / s - ly
    local best, bestD
    for i = 1, used do
        local d = dots[i]
        local dx, dy = cx - d.x, cy - d.y
        if dx <= HIT and dx >= -HIT and dy <= HIT and dy >= -HIT then
            local dist = dx * dx + dy * dy
            if not best or dist < bestD then best, bestD = d.unit, dist end
        end
    end
    return best
end

-- Shows the game's own unit tooltip for unit (nil hides ours). Far mode calls it every frame.
function Party.SetHover(unit)
    if unit == hovered then return end
    if hovered and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    hovered = unit
    if unit then
        GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        GameTooltip:SetUnit(unit)
    end
end

function Party.Refresh()
    if layer then Draw() end
end

function Party.Build(canvas, view, level)
    owner = view
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetSize(1, 1)
    layer:SetPoint("CENTER", canvas, "CENTER")
    layer:SetFrameLevel(level)
    layer:Hide()
    layer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_EVERY then return end
        elapsed = 0
        Draw()
    end)
end
