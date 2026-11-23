-- Minimap pings on the far view. The game draws a ping only on the native minimap, which is hidden
-- under the far view, so a ping (the party's or our own right-click) is redrawn here: a dot with
-- gold pulses and the name of who pinged, at the same world spot, for as long as the game shows it.
--
-- The position comes from Minimap:GetPingPosition() (native units, offsets from the player) when
-- MINIMAP_PING fires, and is fixed in world yards then, so it stays put as the player moves.
local _, ns = ...

local G, Zoom = ns.Geometry, ns.Zoom

local Pings = {}
ns.Pings = Pings

local LIFE = 5          -- seconds, like the game's ping
local PULSE = 1         -- seconds per pulse
local DOT, RING = 6, 26 -- px
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- round mask

local canvas, layer
local layout            -- { inst, n, w, ppy }
local ping              -- { n, w, inst, start, name, r, g, b } or nil
local marker
local last              -- for /fzm pings: { x, y, n, w }

local function Round(parent, size, r, g, b)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(r, g, b, 1)
    t:SetSize(size, size)
    if t.SetMask then pcall(t.SetMask, t, MASK) end
    return t
end

local function BuildMarker()
    marker = CreateFrame("Frame", nil, layer)
    marker:SetSize(RING, RING)
    marker.pulse = Round(marker, RING, 1, 0.82, 0)
    marker.pulse:SetPoint("CENTER")
    marker.dot = Round(marker, DOT, 1, 0.9, 0.3)
    marker.dot:SetPoint("CENTER")
    marker.label = marker:CreateFontString(nil, "OVERLAY")
    marker.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    marker.label:SetPoint("TOP", marker, "CENTER", 0, -DOT)
    marker:Hide()
end

local function Place()
    if not (ping and layout and ping.inst == layout.inst) then
        marker:Hide()
        return
    end
    local x, y = G.WorldToPixel(ping.n, ping.w, layout.n, layout.w, layout.ppy)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", canvas, "CENTER", x, y)
    marker:Show()
end

-- Far mode calls this every frame: animates the pulse and ends the ping.
function Pings.Update(now)
    if not ping then return end
    local age = now - ping.start
    if age >= LIFE then
        ping = nil
        marker:Hide()
        return
    end
    local t = (age % PULSE) / PULSE
    local size = DOT + (RING - DOT) * t
    marker.pulse:SetSize(size, size)
    marker.pulse:SetAlpha(0.7 * (1 - t))
    marker:SetAlpha(age > LIFE - 0.5 and (LIFE - age) / 0.5 or 1)
end

-- Far mode calls this when the zoom, origin or continent changes; nil when it leaves.
function Pings.SetLayout(inst, n, w, ppy)
    if inst then
        layout = layout or {}
        layout.inst, layout.n, layout.w, layout.ppy = inst, n, w, ppy
    else
        layout = nil
    end
    if marker then Place() end
end

local function OnPing(unit)
    if not (ns.Far and ns.Far.PlayerWorld) then return end
    local pN, pW, inst, nativeMax = ns.Far.PlayerWorld()
    local ok, x, y = pcall(Minimap.GetPingPosition, Minimap)
    if not ok or ns.IsSecret(x) or ns.IsSecret(y) or not pN then return end
    local n, w = Zoom.PingToWorld(x, y, pN, pW, ns.Shell.nativeSize or Minimap:GetWidth(), nativeMax)
    if not n then return end
    last = { x = x, y = y, n = n, w = w }
    local name, r, g, b
    if type(unit) == "string" and not ns.IsSecret(unit) then
        local okN, nm = pcall(UnitName, unit)
        if okN and type(nm) == "string" and not ns.IsSecret(nm) then name = nm end
        local okC, _, class = pcall(UnitClass, unit)
        local c = okC and class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
        if c then r, g, b = c.r, c.g, c.b end
    end
    ping = { n = n, w = w, inst = inst, start = GetTime() }
    marker.label:SetText(name or "")
    marker.label:SetTextColor(r or 1, g or 0.82, b or 0)
    Place()
end

function Pings.Build(canvasFrame, level)
    canvas = canvasFrame
    layer = CreateFrame("Frame", nil, canvas)
    layer:SetSize(1, 1)
    layer:SetPoint("CENTER", canvas, "CENTER")
    layer:SetFrameLevel(level)
    BuildMarker()
    local events = CreateFrame("Frame")
    pcall(events.RegisterEvent, events, "MINIMAP_PING")
    events:SetScript("OnEvent", function(_, _, unit)
        if ns.Far and ns.Far.IsActive() then OnPing(unit) end
    end)
end

ns.RegisterCommand("pings", "show the last ping the far view drew", function()
    if not last then
        ns.Print("no ping seen in far mode yet")
        return
    end
    ns.Printf("last ping: native %.1f, %.1f  world %.1f N, %.1f W  %s", last.x, last.y, last.n, last.w,
        ping and "showing" or "ended")
end)
