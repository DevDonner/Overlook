-- Mounted zoom: mounting zooms the map out to the mounted radius (unless it's already further out
-- or panned); dismounting recenters, back to the native minimap, if the zoom-out was ours.
-- Settings: mountZoom (on/off), mountRadius (yd).
local _, ns = ...

local Mount = {}
ns.Mount = Mount

local mounted = false
local zoomedByUs = false

local function IsMountedNow()
    local ok, v = pcall(IsMounted)
    return ok and v == true
end

-- What to do when the mounted state changes: "out", "back" or nil. Pure, for the tests.
-- radius: the far view's radius now, nil in near mode.
function Mount.Decide(nowMounted, wasMounted, enabled, radius, mountRadius, ours)
    if nowMounted == wasMounted then return nil end
    if nowMounted then
        if enabled and (not radius or radius < mountRadius) then return "out" end
        return nil
    end
    if ours then return "back" end
    return nil
end

local function Check()
    local now = IsMountedNow()
    if now == mounted then return end
    local far = ns.Far
    local action = Mount.Decide(now, mounted, ns.db.mountZoom, far and far.Radius(), ns.db.mountRadius, zoomedByUs)
    mounted = now
    if action == "out" then
        zoomedByUs = far ~= nil and not far.IsPanned() and far.ZoomTo(ns.db.mountRadius) or false
    elseif action == "back" then
        zoomedByUs = false
        if far and not far.IsPanned() then far.Recenter() end
    else
        zoomedByUs = false
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
pcall(events.RegisterEvent, events, "PLAYER_MOUNT_DISPLAY_CHANGED")
events:RegisterEvent("UNIT_AURA") -- some clients don't send the event above for every mount
events:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "PLAYER_LOGIN" then
        mounted = IsMountedNow() -- logging in mounted isn't "just mounted"
        return
    end
    Check()
end)
