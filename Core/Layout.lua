-- Pure layout math for the shell: which corner the resize grip goes on, and the new size and
-- position while dragging it. All values are in UIParent units. Offline tests cover it.
local _, ns = ...

local Layout = {}
ns.Layout = Layout

-- The grip goes on the corner facing the screen centre, so the map grows into the screen.
-- x, y: the map's centre offset from the screen centre. Returns sx, sy: -1 left/bottom, 1 right/top.
function Layout.GripCorner(x, y)
    return (x or 0) > 0 and -1 or 1, (y or 0) > 0 and -1 or 1
end

-- The corner opposite the grip stays fixed. Given that fixed corner, the grip direction and the
-- cursor, returns the new (square, clamped) size and centre.
function Layout.ResizeFrom(fixedX, fixedY, sx, sy, cursorX, cursorY, clamp)
    local size = math.max((cursorX - fixedX) * sx, (cursorY - fixedY) * sy)
    size = clamp(size)
    return size, fixedX + sx * size / 2, fixedY + sy * size / 2
end

-- The fixed corner (opposite the grip) of a square at centre (cx, cy).
function Layout.FixedCorner(cx, cy, size, sx, sy)
    return cx - sx * size / 2, cy - sy * size / 2
end
