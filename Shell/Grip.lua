-- Resize grip: a window-style size grabber on the corner of the map that faces the screen centre.
-- It fades in while the mouse is over the map; dragging it keeps the opposite corner fixed and
-- the map square. Hidden while the map is locked; refused in combat (like moving).
local _, ns = ...

local Layout, Settings = ns.Layout, ns.Settings

local Grip = {}
ns.Grip = Grip

local GRIP_SIZE = 16
local TEXTURE = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

local root, grip, readout
local sx, sy = -1, -1          -- grip corner: -1 left/bottom, 1 right/top
local fixedX, fixedY           -- the corner that stays put while resizing (UIParent units)
local resizing = false

local function CursorInUIParent()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function MapCentre()
    local ux, uy = UIParent:GetCenter()
    return ux + (ns.db.x or 0), uy + (ns.db.y or 0)
end

-- Puts the grip on the corner facing the screen centre and turns its art to point that way
-- (the art points bottom-right).
local function PlaceGrip()
    sx, sy = Layout.GripCorner(ns.db.x, ns.db.y)
    local point = (sy < 0 and "BOTTOM" or "TOP") .. (sx < 0 and "LEFT" or "RIGHT")
    grip:ClearAllPoints()
    grip:SetPoint(point, root, point, 0, 0)
    local l, r = 0, 1
    if sx < 0 then l, r = 1, 0 end
    local t, b = 0, 1
    if sy > 0 then t, b = 1, 0 end
    for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetPushedTexture(), grip:GetHighlightTexture() }) do
        if tex then tex:SetTexCoord(l, r, t, b) end
    end
end

local function Stop()
    if not resizing then return end
    resizing = false
    readout:Hide()
    ns.Shell.Apply()
    PlaceGrip()
end

local function Start()
    if InCombatLockdown() then
        ns.Print("can't resize the minimap in combat")
        return
    end
    local cx, cy = MapCentre()
    fixedX, fixedY = Layout.FixedCorner(cx, cy, ns.db.size, sx, sy)
    resizing = true
    readout.text:SetText(ns.db.size .. " px")
    readout:Show()
end

local function OnUpdate()
    if resizing then
        -- Mouse-up normally ends it; this also catches a release the grip never saw.
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
            Stop()
            return
        end
        local cx, cy = CursorInUIParent()
        local size, mx, my = Layout.ResizeFrom(fixedX, fixedY, sx, sy, cx, cy, Settings.ClampSize)
        if size ~= ns.db.size then
            local ux, uy = UIParent:GetCenter()
            ns.db.size, ns.db.x, ns.db.y = size, mx - ux, my - uy
            ns.Shell.Apply()
            readout.text:SetText(size .. " px")
        end
        return
    end

    local want = not ns.db.locked and root:IsMouseOver() and not InCombatLockdown()
    if want and not grip:IsShown() then
        PlaceGrip() -- the map may have moved since last time
        grip:Show()
    elseif not want and grip:IsShown() then
        grip:Hide()
    end
end

function Grip.Build(parent, level)
    if grip then return end
    root = parent

    grip = CreateFrame("Button", nil, root)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetFrameLevel(level)
    grip:SetNormalTexture(TEXTURE .. "Up")
    grip:SetPushedTexture(TEXTURE .. "Down")
    grip:SetHighlightTexture(TEXTURE .. "Highlight")
    grip:RegisterForClicks("LeftButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Start() end
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnHide", Stop)
    grip:Hide()

    readout = CreateFrame("Frame", nil, root)
    readout:SetAllPoints(root)
    readout:SetFrameLevel(level)
    readout.text = readout:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    readout.text:SetPoint("CENTER")
    readout.text:SetShadowOffset(1, -1)
    readout:Hide()

    -- Runs every frame, but only an IsMouseOver check unless a resize is in progress.
    local driver = CreateFrame("Frame", nil, root)
    driver:SetScript("OnUpdate", OnUpdate)
end

ns.RegisterCommand("lock", "lock or unlock the map (locked hides the resize grip; Alt+drag still moves it)", function()
    ns.db.locked = not ns.db.locked
    ns.Printf("map %s", ns.db.locked and "locked" or "unlocked")
end)
