-- Dungeon and raid entrances, on the normal minimap and on the far map, with a tooltip of what's
-- there and its levels (coloured for you, like quest levels). Places: Data/Entrances.lua.
--
-- Normal minimap: one small frame per entrance on the game's Minimap, placed from the player's
-- position and the minimap's view radius (turned when the minimap rotates); shown only inside the
-- map's shape. They take the mouse for their tooltip but not clicks, so right-click pings still work.
-- Far map: a layer on the far canvas, like the party dots; Far.lua asks UnderCursor while hovering.
local _, ns = ...

local G = ns.Geometry
local EM = ns.EntranceMath

local Entrances = {}
ns.Entrances = Entrances

local UPDATE_EVERY = 0.05
local SIZE = 20          -- px on screen, times the entranceScale setting
local MARGIN = 4         -- px kept clear of the normal minimap's edge
local LOOK = {
    dungeon = { atlas = "Dungeon", texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
    raid = { atlas = "Raid", texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
}

local places         -- EM.Resolve's list, made on first use
local nativeLayer, nativePins = nil, {}
local farLayer, farPins, farOwner = nil, {}, nil
local layout         -- { inst, n, w, ppy } while the far map draws
local hovered        -- the entrance whose tooltip the far map shows
local elapsed = 0

local function On() return ns.db and ns.db.dungeonEntrances ~= false end
local function Size() return SIZE * (tonumber(ns.db and ns.db.entranceScale) or 1) end

local function Places()
    if not places then
        local api = _G.C_Map
        places = EM.Resolve(ns.MapEntrances, api, _G.CreateVector2D)
    end
    return places
end

local function SetLook(tex, raid)
    local look = raid and LOOK.raid or LOOK.dungeon
    local atlas = look.atlas
    local has = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(atlas)
    if has and tex.SetAtlas then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture(look.texture)
    end
end

-- The tooltip: each dungeon or raid at the entrance, its level range in the game's quest colours.
function Entrances.ShowTooltip(owner, place, anchor)
    if not (place and GameTooltip) then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_CURSOR")
    local level = UnitLevel and UnitLevel("player")
    if ns.IsSecret(level) then level = nil end
    for _, d in ipairs(place.list) do
        local r, g, b = 1, 0.5, 0.25
        local at = EM.ColorLevel(d.min, d.max, level)
        local c = at and _G.GetQuestDifficultyColor and _G.GetQuestDifficultyColor(at)
        if c then r, g, b = c.r, c.g, c.b end
        local name = d.name .. (d.raid and " (raid)" or "")
        GameTooltip:AddDoubleLine(name, EM.Range(d.min, d.max), 1, 1, 1, r, g, b)
    end
    GameTooltip:Show()
end

----------------------------------------------------------------------------------------------------
-- Normal minimap

local function NativePin(i, place)
    local p = nativePins[i]
    if not p then
        p = CreateFrame("Frame", nil, nativeLayer)
        p.tex = p:CreateTexture(nil, "OVERLAY")
        p.tex:SetAllPoints(p)
        p:EnableMouse(true)
        if p.SetMouseClickEnabled then pcall(p.SetMouseClickEnabled, p, false) end
        p:SetScript("OnEnter", function(self) Entrances.ShowTooltip(self, self.place, "ANCHOR_LEFT") end)
        p:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        nativePins[i] = p
    end
    if p.place ~= place then
        p.place = place
        SetLook(p.tex, place.raid)
    end
    return p
end

local function Rotating()
    local ok, v = pcall(GetCVar, "rotateMinimap")
    return ok and v == "1"
end

local function DrawNative()
    local n = 0
    local far = ns.Far and ns.Far.IsActive and ns.Far.IsActive()
    if On() and not far and Minimap:IsVisible() then
        local pN, pW, _, inst = UnitPosition("player")
        local r = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
        if pN and r and not (ns.IsSecret(pN) or ns.IsSecret(pW) or ns.IsSecret(inst) or ns.IsSecret(r)) then
            local half = Minimap:GetWidth() / 2
            local facing = Rotating() and GetPlayerFacing() or nil
            if ns.IsSecret(facing) then facing = nil end
            local size = Size() / math.max(Minimap:GetScale(), 0.01)
            local round = ns.Host.IsRound()
            for _, place in ipairs(Places()) do
                if place.inst == inst then
                    local x, y = EM.NativeOffset(place.n, place.w, pN, pW, half, r, facing, round,
                        MARGIN + size / 2)
                    if x then
                        n = n + 1
                        local p = NativePin(n, place)
                        p:SetSize(size, size)
                        p:ClearAllPoints()
                        p:SetPoint("CENTER", Minimap, "CENTER", x, y)
                        p:Show()
                    end
                end
            end
        end
    end
    for i = n + 1, #nativePins do
        local p = nativePins[i]
        if p:IsShown() then
            if GameTooltip:IsOwned(p) then GameTooltip:Hide() end
            p:Hide()
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Far map

local farUsed = 0

local function DrawFar()
    local n = 0
    local size = Size()
    if layout and On() then
        for _, place in ipairs(Places()) do
            local dn, dw = 0, 0
            if place.inst ~= layout.inst then
                dn, dw = nil, nil
                if ns.World then dn, dw = ns.World.Shift(layout.inst, place.inst) end
            end
            if dn then
                local x, y = G.WorldToPixel(place.n + dn, place.w + dw, layout.n, layout.w, layout.ppy)
                n = n + 1
                local p = farPins[n]
                if not p then
                    p = { tex = farLayer:CreateTexture(nil, "ARTWORK") }
                    if ns.Far and ns.Far.Shape then ns.Far.Shape(p.tex) end
                    farPins[n] = p
                end
                if p.place ~= place then
                    p.place = place
                    SetLook(p.tex, place.raid)
                end
                p.x, p.y = x, y
                p.tex:SetSize(size, size)
                p.tex:SetPoint("CENTER", farLayer, "CENTER", x, y)
                p.tex:Show()
            end
        end
    end
    for i = n + 1, farUsed do
        farPins[i].place = nil
        farPins[i].tex:Hide()
    end
    farUsed = n
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Entrances.SetLayout(inst, n, w, ppy)
    if not farLayer then return end
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
        farLayer:Show()
    else
        layout = nil
        Entrances.SetHover(nil)
        farLayer:Hide()
    end
    DrawFar()
end

-- The entrance under the cursor on the far map (nearest if several), or nil.
function Entrances.UnderCursor()
    if not farLayer or not layout or farUsed == 0 then return nil end
    local HIT = Size() / 2
    local lx, ly = farLayer:GetCenter()
    if not lx then return nil end
    local s = farLayer:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s - lx, cy / s - ly
    local best, bestD
    for i = 1, farUsed do
        local p = farPins[i]
        local dx, dy = cx - p.x, cy - p.y
        if dx <= HIT and dx >= -HIT and dy <= HIT and dy >= -HIT then
            local d = dx * dx + dy * dy
            if not best or d < bestD then best, bestD = p.place, d end
        end
    end
    return best
end

-- Shows the tooltip for an entrance on the far map (nil hides ours). Far mode calls it every frame.
function Entrances.SetHover(place)
    if place == hovered then return end
    if hovered and GameTooltip:IsOwned(farOwner) then GameTooltip:Hide() end
    hovered = place
    if place then Entrances.ShowTooltip(farOwner, place) end
end

function Entrances.Refresh()
    if farLayer then DrawFar() end
    if nativeLayer then DrawNative() end
end

function Entrances.Build(canvas, view, level)
    farOwner = view
    farLayer = CreateFrame("Frame", nil, canvas)
    farLayer:SetSize(1, 1)
    farLayer:SetPoint("CENTER", canvas, "CENTER")
    farLayer:SetFrameLevel(level)
    farLayer:Hide()
end

-- The normal minimap's pins: a layer on the game's Minimap, redrawn a few times a second.
function Entrances.BuildNative()
    if nativeLayer then return end
    -- Named Overlook...: Pins/Others.lua leaves our own frames on the Minimap alone.
    nativeLayer = CreateFrame("Frame", "OverlookNativeEntrances", Minimap)
    nativeLayer:SetAllPoints(Minimap)
    nativeLayer:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    nativeLayer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < UPDATE_EVERY then return end
        elapsed = 0
        DrawNative()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() Entrances.BuildNative() end)
