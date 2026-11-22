-- Party dots on the far map: hovering one shows the game's own unit tooltip for that member.
local H = ...

local function noop() end

local function NewTexture()
    return setmetatable({}, { __index = function() return noop end })
end

local frames = {}
local function NewFrame()
    local f = setmetatable({}, { __index = function() return noop end })
    f.CreateTexture = function() return NewTexture() end
    f.GetEffectiveScale = function() return 1 end
    f.GetCenter = function() return 0, 0 end
    frames[#frames + 1] = f
    return f
end

-- Group: party1 on this continent, party2 on another.
local positions = {
    party1 = { 10, -20, 0, 0 }, -- north, west, z, instance
    party2 = { 10, -20, 0, 1 },
}

local cursorX, cursorY = 0, 0
local tooltip = { calls = {}, owner = nil }
function tooltip:SetOwner(owner, anchor) self.owner = owner; self.calls[#self.calls + 1] = { "SetOwner", anchor } end
function tooltip:SetUnit(unit) self.calls[#self.calls + 1] = { "SetUnit", unit } end
function tooltip:Hide() self.owner = nil; self.calls[#self.calls + 1] = { "Hide" } end
function tooltip:IsOwned(f) return self.owner == f end
function tooltip:Last() return self.calls[#self.calls] end

local GLOBALS = {
    CreateFrame = function() return NewFrame() end,
    GetNumGroupMembers = function() return 3 end,
    IsInRaid = function() return false end,
    UnitIsUnit = function(a, b) return a == b end,
    UnitClass = function() return "Hunter", "HUNTER" end,
    UnitIsConnected = function() return true end,
    UnitPosition = function(unit) return unpack(positions[unit] or {}) end,
    GameTooltip = tooltip,
    GetCursorPosition = function() return cursorX, cursorY end,
}
local saved = {}
for k, v in pairs(GLOBALS) do saved[k] = _G[k]; _G[k] = v end

local ns = { db = {}, IsSecret = function() return false end }
H.loadAddonFile("Core/Geometry.lua", ns)
H.loadAddonFile("Pins/Party.lua", ns)
local Party = ns.Party

local view = NewFrame()
Party.Build(NewFrame(), view, 1)
Party.SetLayout(0, 0, 0, 1) -- origin at 0,0, one pixel per yard

H.test("the cursor on a party dot finds that member", function()
    cursorX, cursorY = 20, 10 -- party1: 20 yd west of the origin is +20 px, 10 yd north is +10 px
    H.eq(Party.UnitUnderCursor(), "party1")
    cursorX, cursorY = 23, 7 -- still on the 9 px dot
    H.eq(Party.UnitUnderCursor(), "party1")
end)

H.test("the cursor off every dot finds nobody", function()
    cursorX, cursorY = 60, 60
    H.eq(Party.UnitUnderCursor(), nil)
end)

H.test("a member on another continent has no dot to hover", function()
    positions.party1 = { 10, -20, 0, 5 }
    Party.Refresh()
    cursorX, cursorY = 20, 10
    H.eq(Party.UnitUnderCursor(), nil)
    positions.party1 = { 10, -20, 0, 0 }
    Party.Refresh()
end)

H.test("hovering shows the game's own unit tooltip, owned by the far view", function()
    Party.SetHover("party1")
    H.eq(tooltip.owner, view)
    H.eq(tooltip:Last()[1], "SetUnit")
    H.eq(tooltip:Last()[2], "party1")
    local n = #tooltip.calls
    Party.SetHover("party1") -- same member next frame: no flicker
    H.eq(#tooltip.calls, n)
end)

H.test("leaving the dot hides only a tooltip we showed", function()
    Party.SetHover(nil)
    H.eq(tooltip:Last()[1], "Hide")
    local n = #tooltip.calls
    Party.SetHover("party1")
    tooltip.owner = "someone else" -- another frame took the tooltip
    Party.SetHover(nil)
    H.eq(#tooltip.calls, n + 2, "no Hide for someone else's tooltip")
end)

for k in pairs(GLOBALS) do _G[k] = saved[k] end
