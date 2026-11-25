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
--
-- Hosted (Core/Host.lua): another addon owns the Minimap (EllesmereUI, or one that takes it back
-- whenever we parent it). Then the Minimap is left exactly as that addon keeps it (parent, size,
-- place, mask, rotation, its buttons) and our root follows it instead: the far view, bars and the
-- rest lie over the host's map. Moving and resizing are the host's then, so the grip and Alt+drag
-- are off.
local _, ns = ...

local Shell = {}
ns.Shell = Shell

local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Fixed frame levels. Questie pins its minimap icons at level 2016 and up (fixed), so the far view
-- must sit above them to take the mouse; the border and Alt+drag catcher go above that.
local LEVEL_VIEW, LEVEL_BORDER, LEVEL_CATCHER = 3000, 3010, 3020

local root, catcher, border, ring
local nativeSize
local applyQueued = false
local hostFought = false -- an unknown addon took the Minimap back after we parented it
local foreignShape       -- the last GetMinimapShape another addon set, to give back

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

-- Who hosts the map now (Host.Decide); says so in chat when that changes.
local function RefreshHost()
    local owner = ns.Host.Decide(ns.db.hostOthers, ns.Host.Known(), hostFought)
    if owner == ns.Host.owner then return end
    ns.Host.owner = owner
    if owner then
        ns.Printf("%s has the minimap: Overlook's far zoom now works inside its map. /overlook > Other addons to change this.", owner)
    end
end

-- The host's shape, from the GetMinimapShape it answers.
local function HostShape()
    local fn = _G.GetMinimapShape
    if type(fn) ~= "function" or fn == Shell.MinimapShape then fn = foreignShape end
    if type(fn) ~= "function" then return "SQUARE" end
    local ok, shape = pcall(fn)
    return ok and shape or "SQUARE"
end

-- Whether we answer GetMinimapShape (see Build). Pure.
function Shell.WantShape(claimShape, hosted)
    return claimShape ~= false and not hosted
end

local function SyncShapeAnswer()
    local cur = _G.GetMinimapShape
    if cur ~= Shell.MinimapShape and cur ~= nil then foreignShape = cur end
    if Shell.WantShape(ns.db.claimShape, ns.Host.owner ~= nil) then
        if cur ~= Shell.MinimapShape then _G.GetMinimapShape = Shell.MinimapShape end
    elseif cur == Shell.MinimapShape then
        _G.GetMinimapShape = foreignShape -- theirs again (nil if there never was one)
    end
end

-- Hosted: our root lies over the host's map. A host that crops the map to a rectangle (EllesmereUI)
-- marks the cropped part with the Minimap's hit-rect insets; the root leaves that part out.
local function FollowHost()
    local ms, rs = Minimap:GetEffectiveScale(), root:GetEffectiveScale()
    local k = (ms and rs and rs > 0) and ms / rs or 1
    local _, _, cropTop, cropBottom = Minimap:GetHitRectInsets()
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, -(cropTop or 0) * k)
    root:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, (cropBottom or 0) * k)
    root:SetFrameStrata(Minimap:GetFrameStrata() or "LOW")
    ns.Host.size = Minimap:GetWidth() * k
    ns.Host.round = HostShape() == "ROUND"
    border:SetBackdropBorderColor(0, 0, 0, 0) -- the host draws its own edge
    ring:Hide()
end

local ApplyNow

local function ApplyHosted()
    FollowHost()
    border:SetFrameLevel(LEVEL_BORDER)
    catcher:SetFrameLevel(LEVEL_CATCHER)
    catcher:EnableMouse(false)
    catcher:EnableMouseWheel(false)
    if ns.Far then ns.Far.OnShellApplied() end
    if ns.Bars then ns.Bars.Apply() end
end

ApplyNow = function()
    applyQueued = false
    RefreshHost()
    SyncShapeAnswer()
    if ns.Host.owner then
        ApplyHosted()
        return
    end
    root:SetFrameStrata("LOW")
    PlaceRoot()

    if Minimap:GetParent() ~= root then
        Minimap:SetParent(root)
        -- Another addon's hook put it straight back: that addon owns the frame, so we move in.
        if Minimap:GetParent() ~= root and not hostFought then
            hostFought = true
            RefreshHost()
            if ns.Host.owner then
                SyncShapeAnswer()
                ApplyHosted()
                return
            end
        end
    end
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", root, "CENTER")
    Minimap:SetScale(ns.db.size / nativeSize)
    local round = ns.db.round == true
    Minimap:SetMaskTexture(round and ROUND_MASK or SQUARE_MASK)

    -- The quest/archaeology blob rings are drawn for a round map; hidden on the square.
    for _, fn in ipairs({ "SetArchBlobRingScalar", "SetQuestBlobRingScalar", "SetTaskBlobRingScalar" }) do
        if Minimap[fn] then pcall(Minimap[fn], Minimap, round and 1 or 0) end
    end

    -- The edge: a 1 px square outline, or a ring (a black disc 2 px wider, behind the round map).
    border:SetBackdropBorderColor(0, 0, 0, round and 0 or 1)
    ring:SetSize(ns.db.size + 2, ns.db.size + 2)
    ring:SetShown(round)
    Shell.SyncRotation()

    HideArt(_G.MinimapCompassTexture)
    HideArt(_G.MinimapCompassTextureUnderlay)
    HideArt(Minimap.ZoomIn)
    HideArt(Minimap.ZoomOut)
    HideArt(Minimap.ZoomHitArea)

    border:SetFrameLevel(LEVEL_BORDER)
    catcher:SetFrameLevel(LEVEL_CATCHER)

    if ns.Far then ns.Far.OnShellApplied() end
    if ns.Bars then ns.Bars.Apply() end
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
    -- While Alt is held the catcher is over the map; the wheel goes on to the map (Alt+wheel
    -- changes cave level or floor there).
    catcher:EnableMouseWheel(false)
    catcher:SetScript("OnMouseWheel", function(_, delta)
        if ns.Far and ns.Far.Wheel then ns.Far.Wheel(delta) end
    end)
    catcher:RegisterForDrag("LeftButton")
    catcher:SetScript("OnDragStart", function()
        -- The catcher can be left mouse-enabled if Alt was released while the game didn't have
        -- focus (Alt+Tab). Never move without Alt actually held.
        if not IsAltKeyDown() then
            catcher:EnableMouse(false)
            catcher:EnableMouseWheel(false)
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
        ApplyNow() -- (not only the root: the Recenter button picks its side from the position)
        catcher:EnableMouse(IsAltKeyDown())
        catcher:EnableMouseWheel(IsAltKeyDown())
    end
    catcher:SetScript("OnDragStop", Stop)
    catcher:SetScript("OnMouseUp", Stop)
end

local function BuildRoot()
    root = CreateFrame("Frame", "OverlookFrame", UIParent)
    root:SetFrameStrata("LOW")
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    root:SetDontSavePosition(true)

    border = CreateFrame("Frame", nil, root, "BackdropTemplate")
    border:SetAllPoints(root)
    border:EnableMouse(false)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(0, 0, 0, 1)

    ring = root:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("CENTER")
    ring:SetColorTexture(0, 0, 0, 1)
    local ringMask = root:CreateMaskTexture()
    ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetAllPoints(ring)
    ring:AddMaskTexture(ringMask)
    ring:Hide()

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

-- The Alt+drag catcher takes the mouse only while Alt is really held. Events can be missed (a key
-- released while the game is unfocused), so the grip's driver also calls this every frame. Off
-- while hosted: the host moves its map.
function Shell.SyncCatcher()
    if not catcher or root.moving then return end
    local want = IsAltKeyDown() and ns.Host.owner == nil
    if catcher:IsMouseEnabled() ~= want then
        catcher:EnableMouse(want)
        catcher:EnableMouseWheel(want)
    end
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
    if ns.Bars then ns.Bars.Build(root, LEVEL_BORDER + 1) end -- below the catcher: Alt+drag works on them
    HookBlizzardLayout()

    -- The cluster's now-empty area would otherwise still swallow clicks meant for the world.
    if MinimapCluster then MinimapCluster:EnableMouse(false) end

    -- LibDBIcon, HereBeDragons (Questie's pins) and similar libraries ask GetMinimapShape where the
    -- map's edge is. The map is ours, so the answer is too: other minimap addons (EnhanceQoL's and
    -- Leatrix Plus's square minimap) set it to SQUARE, which put Questie's icons in the round map's
    -- empty corners. Taken back if one of them sets it again later. Not while hosted (the host's
    -- answer is right for its map), nor with claimShape off; theirs is given back then.
    foreignShape = _G.GetMinimapShape
    C_Timer.NewTicker(2, Shell.Watch)
    if Minimap.HookScript then
        Minimap:HookScript("OnSizeChanged", function() if ns.Host.owner then Shell.Apply() end end)
    end

    ApplyNow()
end

-- Every 2 s: the shape answer, and whether the map's host changed (an addon loaded late, took the
-- Minimap back, or resized its map).
function Shell.Watch()
    if not root then return end
    SyncShapeAnswer()
    local parent = Minimap:GetParent()
    if not ns.Host.owner and parent ~= root and parent ~= MinimapCluster and not hostFought
        and ns.db.hostOthers ~= false then
        hostFought = true
    end
    local was, wasSize = ns.Host.owner, ns.Host.size
    RefreshHost()
    if ns.Host.owner ~= was then
        Shell.Apply()
    elseif ns.Host.owner then
        local ms, rs = Minimap:GetEffectiveScale(), root:GetEffectiveScale()
        local size = Minimap:GetWidth() * ((ms and rs and rs > 0) and ms / rs or 1)
        if math.abs(size - (wasSize or 0)) > 0.5 then Shell.Apply() end
    end
end

-- Hosting switched on or off in the settings.
function Shell.SetHostOthers(on)
    ns.db.hostOthers = on and true or false
    if not on then hostFought = false end
    Shell.Apply()
end

-- What GetMinimapShape answers while Overlook has the minimap.
function Shell.MinimapShape()
    return ns.db and ns.db.round and "ROUND" or "SQUARE"
end

-- Rotation is the game's own rotating minimap (the rotateMinimap setting), at normal zoom only:
-- the far map stays north-up. Only on the round map: a turning square looks wrong, so on the
-- square the game's setting is kept off. ns.db.rotate is the player's choice (a profile carries
-- it); on the round map it follows the game's setting both ways.
local function RotationNow()
    local ok, v = pcall(GetCVar, "rotateMinimap")
    return ok and v == "1"
end

-- Whether the game's setting should be on: the player's choice, on the round map only. Pure.
function Shell.WantRotation(rotate, round)
    return rotate == true and round == true
end

function Shell.SyncRotation()
    if ns.Host.owner then return end -- the host's setting
    local want = Shell.WantRotation(ns.db.rotate, ns.db.round)
    if RotationNow() ~= want then pcall(SetCVar, "rotateMinimap", want and "1" or "0") end
end

function Shell.SetRotate(on)
    ns.db.rotate = on and true or false
    Shell.SyncRotation()
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
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ns.name then
            ns.db = ns.Settings.Load(OverlookDB)
            if ns.Profiles then ns.Profiles.Init(ns.db) end
            OverlookDB = ns.db
            events:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if ns.db.round then ns.db.rotate = RotationNow() end
        Shell.Build()
    elseif event == "PLAYER_LOGOUT" then
        if ns.Profiles and ns.db then ns.Profiles.Save(ns.db) end
    elseif not root then
        return
    elseif event == "MODIFIER_STATE_CHANGED" then
        Shell.SyncCatcher()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if applyQueued then ApplyNow() end
    else -- CVAR_UPDATE (rotateMinimap resets the mask), EDIT_MODE_LAYOUTS_UPDATED
        -- On the round map the game's setting is the choice; on the square it's put back off.
        if event == "CVAR_UPDATE" and ns.db.round and not ns.Host.owner then ns.db.rotate = RotationNow() end
        Shell.Apply()
    end
end)

----------------------------------------------------------------------------------------------------
-- Commands

ns.RegisterCommand("reset", "move the minimap back to a visible spot at the default size", function()
    Shell.ResetPosition()
    ns.Print("minimap reset")
end)

ns.RegisterCommand("size", "set the minimap size in px (120-800), e.g. /overlook size 250", function(arg)
    if not tonumber(arg) then
        ns.Printf("size is %d px; usage: /overlook size 250", ns.db.size)
        return
    end
    ns.db.size = ns.Settings.ClampSize(arg)
    Shell.Apply()
    ns.Printf("size %d px", ns.db.size)
end)
