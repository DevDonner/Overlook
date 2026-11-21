-- The far-zoom ladder and tween. Pure Lua, so the offline tests cover it (U3).
--
-- Near mode uses the native minimap's own zoom steps. Zooming out from its widest step hands over
-- to far mode, where the view radius (yards from the centre to the edge of the square) grows by
-- STEP per wheel notch, or by the square root of STEP with Ctrl held, up to the max far zoom.
-- Zooming back in to the native radius hands back to near mode.
local _, ns = ...

local Zoom = {}
ns.Zoom = Zoom

Zoom.STEP = 1.25
Zoom.TWEEN = 0.15 -- seconds per smooth step

-- Closest far zoom, as a fraction of the native widest radius: the native closest step outdoors
-- (66.7 of 233.3 yd). Reached only while panned, or after recentring below the native radius.
Zoom.CLOSEST = 2 / 7

local EPS = 1.0001

-- delta > 0 zooms in, delta < 0 zooms out (the wheel's sign).
-- Returns the new target radius and whether that target hands back to the native minimap.
--
-- Handing back only happens while the view is centred on the player (not panned): a step that
-- crosses the native radius, from either side, lands exactly on it and hands back. While panned
-- the far view keeps zooming through the native radius, down to CLOSEST, and never hands back.
function Zoom.FarStep(radius, delta, fine, nativeMax, maxFar, panned)
    local f = fine and math.sqrt(Zoom.STEP) or Zoom.STEP
    if delta < 0 then
        local r = math.min(radius * f, math.max(maxFar, nativeMax))
        if not panned and radius < nativeMax / EPS and r >= nativeMax / EPS then
            return nativeMax, true
        end
        return r, false
    end
    local r = radius / f
    if not panned and radius >= nativeMax / EPS and r <= nativeMax * EPS then
        return nativeMax, true
    end
    return math.max(r, nativeMax * Zoom.CLOSEST), false
end

Zoom.SHRINK_MIN = 0.35

-- How much "shrink with zoom" icons are scaled at a far radius: 1 at the native radius, falling
-- with the square root of the zoom so icons shrink more gently than the terrain.
function Zoom.Shrink(radius, nativeMax)
    if not radius or radius <= nativeMax then return 1 end
    return math.max(Zoom.SHRINK_MIN, math.sqrt(nativeMax / radius))
end

-- Radius t seconds into a tween from `from` to `to`, even in log space so every step feels the same.
function Zoom.Tween(from, to, t, duration)
    if duration <= 0 or t >= duration or from == to then return to end
    if t <= 0 then return from end
    return from * (to / from) ^ (t / duration)
end
