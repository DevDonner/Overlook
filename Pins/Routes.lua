-- Questie's NPC patrol routes on the far view. Questie draws them on its own layer over the native
-- minimap, culled to about two view radii around the player, so the far view draws its own copy:
-- every route Questie would show on the minimap (QuestieWaypoints.MinimapAlpha, so its settings
-- and hidden icons apply), in Questie's colours, once per route even when several quests share it.
--
-- Lines sit on the canvas above the terrain and below the icon layers, placed at the same fixed
-- origin as tiles and icons; they're re-placed only when the zoom or the routes change. Points
-- closer together than MIN_SEGMENT_PX at the current zoom are merged, so far zoom stays cheap.
local _, ns = ...

local G = ns.Geometry

local Routes = {}
ns.Routes = Routes

local MIN_SEGMENT_PX = 3
local REFRESH_EVERY = 2 -- seconds; backup for a missed change signal

local canvas
local lines, used = {}, 0       -- pooled Line regions; the first `used` are on screen
local routes = {}               -- built from Questie: { world = points, instanceId, r, g, b, a }
local dirty = true
local layout                    -- { inst, n, w, ppy } while far mode is drawing

local waypoints                 -- Questie's QuestieWaypoints module, once found
local function Waypoints()
    if waypoints == nil and QuestieLoader then
        local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieWaypoints")
        if ok and type(mod) == "table" and type(mod.paths) == "table"
            and type(mod.MinimapAlpha) == "function" and type(mod.Color) == "function" then
            waypoints = mod
            local okMini, mini = pcall(QuestieLoader.ImportModule, QuestieLoader, "WaypointMinimap")
            if okMini and type(mini) == "table" and type(mini.Invalidate) == "function" then
                hooksecurefunc(mini, "Invalidate", function() dirty = true end)
            end
        end
    end
    return waypoints or nil
end

-- Reads the routes Questie shows on the minimap: one copy per route, the highlighted one if any.
local function Build()
    dirty = false
    for i = #routes, 1, -1 do routes[i] = nil end
    local mod = Waypoints()
    if not mod then return end
    local chosen = {}
    for path in pairs(mod.paths) do
        local ok, alpha = pcall(mod.MinimapAlpha, path)
        if ok and alpha and type(path.world) == "table" and #path.world >= 2 then
            local key = path.route or path
            local prev = chosen[key]
            if not prev or (path.highlighted and not prev.path.highlighted) then
                chosen[key] = { path = path, alpha = alpha }
            end
        end
    end
    for _, c in pairs(chosen) do
        local okColor, color = pcall(mod.Color, c.path)
        if not okColor or type(color) ~= "table" then color = { 1, 0.8, 0, 0.8 } end
        routes[#routes + 1] = {
            world = c.path.world,
            instanceId = c.path.instanceId,
            r = color[1] or 1, g = color[2] or 1, b = color[3] or 1,
            a = (color[4] or 1) * c.alpha,
        }
    end
end

-- Our own width (px) and opacity: Questie's minimap width, scaled up with the map, was too thick.
local function Thickness()
    return ns.db.routeWidth or 1.5
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = canvas:CreateLine(nil, "OVERLAY")
        if ns.Far and ns.Far.Shape then ns.Far.Shape(line) end
        line:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        lines[i] = line
    end
    return line
end

local function Draw()
    local n = 0
    if layout and ns.db.routes ~= false then
        local thick = Thickness()
        local minSq = MIN_SEGMENT_PX * MIN_SEGMENT_PX
        for _, route in ipairs(routes) do
            local dn, dw = 0, 0
            if route.instanceId ~= nil and route.instanceId ~= layout.inst then
                dn, dw = nil, nil
                if ns.World then dn, dw = ns.World.Shift(layout.inst, route.instanceId) end
            end
            if dn then
                local world = route.world
                local lastX, lastY
                for i = 1, #world do
                    local pt = world[i]
                    -- HBD world yards: x runs west, y runs north.
                    local x, y = G.WorldToPixel(pt.y + dn, pt.x + dw, layout.n, layout.w, layout.ppy)
                    if not lastX then
                        lastX, lastY = x, y
                    else
                        local dx, dy = x - lastX, y - lastY
                        if dx * dx + dy * dy >= minSq or i == #world then
                            n = n + 1
                            local line = Line(n)
                            line:SetStartPoint("CENTER", canvas, lastX, lastY)
                            line:SetEndPoint("CENTER", canvas, x, y)
                            line:SetThickness(thick)
                            line:SetVertexColor(route.r, route.g, route.b, route.a * (ns.db.routeAlpha or 1))
                            line:Show()
                            lastX, lastY = x, y
                        end
                    end
                end
            end
        end
    end
    for i = n + 1, used do lines[i]:Hide() end
    used = n
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Routes.SetLayout(inst, n, w, ppy)
    if not canvas then return end
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
        if dirty then Build() end
    else
        layout = nil
    end
    Draw()
end

-- Redraws now (after the routes setting changes).
function Routes.Refresh()
    if canvas then Draw() end
end

function Routes.Build(parent)
    canvas = parent
    C_Timer.NewTicker(0.2, function()
        if layout and dirty then
            Build()
            Draw()
        end
    end)
    C_Timer.NewTicker(REFRESH_EVERY, function() dirty = true end)
end

ns.RegisterCommand("routes", "show NPC route counts", function()
    if dirty then Build() end
    ns.Printf("routes %d  lines on screen %d  Questie waypoints %s", #routes, used, Waypoints() and "found" or "not found")
end)
