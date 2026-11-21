-- Phase 1a: the square shell. Our root frame holds the native Minimap, masked square, with
-- Blizzard's round artwork hidden. Alt+drag moves it; the position is saved.
--
-- Client facts this relies on (Forever 1.60.1):
--  * Resize the native Minimap with SetScale, never SetSize: its renderer and PingLocation share
--    a fixed local coordinate system.
--  * Blizzard resets the round mask when the rotateMinimap CVar changes, so we re-apply on
--    CVAR_UPDATE.
--  * Don't hooksecurefunc Blizzard methods that take secret arguments (e.g. SetMaskTexture): it
--    makes Blizzard's own calls to them fail.
--  * A plain click on the Minimap pings (MinimapMixin:OnClick, on every mouse-up). Alt+drag uses
--    our own catcher frame, which takes the mouse only while Alt is held, so moving never pings.
local _, ns = ...

local Shell = {}
ns.Shell = Shell

local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"

-- Fixed frame levels. Questie pins its minimap icons at level 2016 and up (fixed), so the far view
-- must sit above them to take the mouse; the border and Alt+drag catcher go above that.
local LEVEL_VIEW, LEVEL_BORDER, LEVEL_CATCHER = 3000, 3010, 3020

local root, catcher, border
local nativeSize
local applyQueued = false

local function UIScaleRatio(frame)
    return frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Centre offset from the screen centre, in UIParent units.
local function SavePosition()
    local cx, cy = root:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s = UIScaleRatio(root)
    ns.db.x, ns.db.y = cx * s - ux, cy * s - uy
end

local function PlaceRoot()
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", ns.db.x or 0, ns.db.y or 0)
    root:SetSize(ns.db.size, ns.db.size)
end

local function HideArt(region)
    if not region then return end
    region:SetAlpha(0)
    if region.EnableMouse then region:EnableMouse(false) end
end

local function ApplyNow()
    applyQueued = false
    PlaceRoot()

    if Minimap:GetParent() ~= root then Minimap:SetParent(root) end
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", root, "CENTER")
    Minimap:SetScale(ns.db.size / nativeSize)
    Minimap:SetMaskTexture(SQUARE_MASK)

    -- The quest/archaeology blob rings are drawn for a round map; hide them on the square.
    for _, fn in ipairs({ "SetArchBlobRingScalar", "SetQuestBlobRingScalar", "SetTaskBlobRingScalar" }) do
        if Minimap[fn] then pcall(Minimap[fn], Minimap, 0) end
    end

    HideArt(_G.MinimapCompassTexture)
    HideArt(_G.MinimapCompassTextureUnderlay)
    HideArt(Minimap.ZoomIn)
    HideArt(Minimap.ZoomOut)
    HideArt(Minimap.ZoomHitArea)

    border:SetFrameLevel(LEVEL_BORDER)
    catcher:SetFrameLevel(LEVEL_CATCHER)

    if ns.Far then ns.Far.OnShellApplied() end
end

-- Re-applies the layout, waiting for combat to end if needed (safety default until we know
-- the Minimap is never protected).
function Shell.Apply()
    if not root then return end
    if InCombatLockdown() then
        applyQueued = true
        return
    end
    ApplyNow()
end

local function BuildCatcher()
    catcher = CreateFrame("Frame", nil, root)
    catcher:SetAllPoints(root)
    catcher:EnableMouse(false)
    catcher:RegisterForDrag("LeftButton")
    catcher:SetScript("OnDragStart", function()
        -- The catcher can be left mouse-enabled if Alt was released while the game didn't have
        -- focus (Alt+Tab). Never move without Alt actually held.
        if not IsAltKeyDown() then
            catcher:EnableMouse(false)
            return
        end
        if InCombatLockdown() then
            ns.Print("can't move the minimap in combat")
            return
        end
        root.moving = true
        root:StartMoving()
    end)
    local function Stop()
        if not root.moving then return end
        root.moving = false
        root:StopMovingOrSizing()
        SavePosition()
        PlaceRoot()
        catcher:EnableMouse(IsAltKeyDown())
    end
    catcher:SetScript("OnDragStop", Stop)
    catcher:SetScript("OnMouseUp", Stop)
end

local function BuildRoot()
    root = CreateFrame("Frame", "FarZoomMinimapFrame", UIParent)
    root:SetFrameStrata("LOW")
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    root:SetDontSavePosition(true)

    border = CreateFrame("Frame", nil, root, "BackdropTemplate")
    border:SetAllPoints(root)
    border:EnableMouse(false)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)

    BuildCatcher()
end

-- First login: start where the native minimap is now.
local function SeedPosition()
    if ns.db.x then return end
    local mx, my = Minimap:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if mx then
        local s = UIScaleRatio(Minimap)
        ns.db.x, ns.db.y = mx * s - ux, my * s - uy
    else
        ns.db.x, ns.db.y = 0, 0
    end
end

local function HookBlizzardLayout()
    -- Edit Mode and the cluster's own layout re-anchor the Minimap; put it back afterwards.
    -- These take plain numbers/booleans, not secret values.
    for _, name in ipairs({ "SetScale", "SetEditModeScale", "SetHeaderUnderneath", "SetIconScale" }) do
        if MinimapCluster and type(MinimapCluster[name]) == "function" then
            hooksecurefunc(MinimapCluster, name, Shell.Apply)
        end
    end
end

-- LibDBIcon parents addon buttons to the Minimap, which goes to alpha 0 in far mode. Move any
-- still sitting there into our root (their anchors to the Minimap still hold). Buttons another
-- addon has already collected (e.g. MinimapButtonButton) aren't on the Minimap, so they're left alone.
local function AdoptButtons()
    local ok, lib = pcall(LibStub, "LibDBIcon-1.0", true)
    if not (ok and lib and type(lib.objects) == "table") then return end
    for _, button in pairs(lib.objects) do
        if button.GetParent and button:GetParent() == Minimap then
            local strata = button:GetFrameStrata()
            button:SetParent(root)
            button:SetFrameStrata(strata)
        end
    end
end

-- The Alt+drag catcher takes the mouse only while Alt is really held. Events can be missed (a key
-- released while the game is unfocused), so the grip's driver also calls this every frame.
function Shell.SyncCatcher()
    if not catcher or root.moving then return end
    local want = IsAltKeyDown()
    if catcher:IsMouseEnabled() ~= want then catcher:EnableMouse(want) end
end

function Shell.Build()
    if root then return end
    nativeSize = math.max(Minimap:GetWidth(), 1)
    Shell.nativeSize = nativeSize
    SeedPosition()
    BuildRoot()
    Shell.root = root
    if ns.Far then ns.Far.Build(root, LEVEL_VIEW) end
    if ns.Grip then ns.Grip.Build(root, LEVEL_CATCHER + 10) end
    HookBlizzardLayout()
    AdoptButtons()
    C_Timer.NewTicker(2, AdoptButtons) -- addons can create buttons after login

    -- The cluster's now-empty area would otherwise still swallow clicks meant for the world.
    if MinimapCluster then MinimapCluster:EnableMouse(false) end

    -- LibDBIcon and similar libraries ask this global where the map's edge is.
    if _G.GetMinimapShape == nil then
        _G.GetMinimapShape = function() return "SQUARE" end
    end

    ApplyNow()
end

function Shell.ResetPosition()
    ns.db.size = ns.Settings.DEFAULTS.size
    -- Back to the middle-right of the screen, a known-visible spot.
    ns.db.x, ns.db.y = UIParent:GetWidth() / 2 - 150, UIParent:GetHeight() / 2 - 150
    Shell.Apply()
end

----------------------------------------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ns.name then
            ns.db = ns.Settings.Load(FarZoomMinimapDB)
            FarZoomMinimapDB = ns.db
            events:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        Shell.Build()
    elseif not root then
        return
    elseif event == "MODIFIER_STATE_CHANGED" then
        Shell.SyncCatcher()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if applyQueued then ApplyNow() end
    else -- CVAR_UPDATE (rotateMinimap resets the mask), EDIT_MODE_LAYOUTS_UPDATED
        Shell.Apply()
    end
end)

----------------------------------------------------------------------------------------------------
-- Commands

ns.RegisterCommand("reset", "move the minimap back to a visible spot at the default size", function()
    Shell.ResetPosition()
    ns.Print("minimap reset")
end)

ns.RegisterCommand("size", "set the minimap size in px (120-600), e.g. /fzm size 250", function(arg)
    if not tonumber(arg) then
        ns.Printf("size is %d px; usage: /fzm size 250", ns.db.size)
        return
    end
    ns.db.size = ns.Settings.ClampSize(arg)
    Shell.Apply()
    ns.Printf("size %d px", ns.db.size)
end)
