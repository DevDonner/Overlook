-- Phase 0 spike: in-game go/no-go checks. Throwaway code; nothing here ships in the real addon.
--
--   /fzm pos       player position, facing and map position, plus the tile under you
--   /fzm combat    toggle: report position automatically each time you enter combat
--   /fzm dump      pin registries: counts by continent, texture, Questie type, hidden flag
--   /fzm party     party/raid member positions
--   /fzm tooltip   does a tooltip stay up when its owner frame is off-screen?
--   /fzm tiles     draw the 5 x 5 minimap tiles around you from the tile table ("swap" flips axes)
--   /fzm selftest  run the automatic checks and print pass/fail
local _, ns = ...

local G = ns.Geometry

local Spike = {}
ns.Spike = Spike

local function Usable(v)
    return type(v) == "number" and not ns.IsSecret(v)
end

local function TileTable(instanceID)
    return ns.MapMinimap and Usable(instanceID) and ns.MapMinimap[instanceID]
end

local function ShortTexture(tex)
    if tex == nil then return "nil" end
    if type(tex) == "string" then return tex:match("([^\\/]+)$") or tex end
    return tostring(tex)
end

----------------------------------------------------------------------------------------------------
-- Position

local function ReadPosition()
    local north, west, _, instanceID = UnitPosition("player")
    local facing = GetPlayerFacing and GetPlayerFacing()
    local mapID = C_Map.GetBestMapForUnit("player")
    local mx, my
    if Usable(mapID) then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok and pos and not ns.IsSecret(pos) then
            mx, my = pos:GetXY()
        end
    end
    return { north = north, west = west, instanceID = instanceID, facing = facing,
             mapID = mapID, mx = mx, my = my }
end

local function ReportPosition(tag)
    local p = ReadPosition()
    ns.Printf("[%s] in combat: %s", tag, tostring(InCombatLockdown()))
    ns.Printf("  world (north, west) = (%s, %s)  instance %s  facing %s",
        ns.Show(p.north), ns.Show(p.west), ns.Show(p.instanceID), ns.Show(p.facing))
    ns.Printf("  map %s at (%s, %s)", ns.Show(p.mapID), ns.Show(p.mx), ns.Show(p.my))
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    ns.Printf("  minimap zoom %s, view radius %s yd", ns.Show(Minimap:GetZoom()), ns.Show(radius))

    local posOK = Usable(p.north) and Usable(p.west)
    local facingOK = Usable(p.facing)
    if posOK then
        local col, row = G.WorldToTile(p.north, p.west)
        local tiles = TileTable(p.instanceID)
        local fid = tiles and tiles[G.TileKey(col, row)]
        ns.Printf("  tile col %d row %d -> file %s", col, row, tostring(fid))
    end
    ns.Printf("  position %s, facing %s",
        posOK and "|cff55ff55usable|r" or "|cffff5555NOT usable|r",
        facingOK and "|cff55ff55usable|r" or "|cffff5555NOT usable|r")
    return posOK, facingOK
end

ns.RegisterCommand("pos", "player position, facing and the tile under you", function()
    ReportPosition("now")
end)

local combatFrame = CreateFrame("Frame")
combatFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, function() ReportPosition("entered combat") end)
end)

ns.RegisterCommand("combat", "toggle a position report each time you enter combat", function()
    Spike.combatWatch = not Spike.combatWatch
    if Spike.combatWatch then
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        ns.Print("combat watch ON: pull a mob and the report prints automatically")
    else
        combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ns.Print("combat watch OFF")
    end
end)

----------------------------------------------------------------------------------------------------
-- Pin registries

local function IconTexture(icon)
    local ok, tex = pcall(function()
        local t = icon.texture
        if not (t and t.GetTexture) then
            for _, r in ipairs({ icon:GetRegions() }) do
                if r:GetObjectType() == "Texture" then t = r break end
            end
        end
        return t and t:GetTexture()
    end)
    return ok and tex or nil
end

local function SortedCounts(counts, limit)
    local list = {}
    for k, n in pairs(counts) do list[#list + 1] = { k = k, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    local parts = {}
    for i = 1, math.min(limit, #list) do
        parts[#parts + 1] = string.format("%s=%d", tostring(list[i].k), list[i].n)
    end
    return table.concat(parts, "  "), #list
end

-- Collects the numbers both /fzm dump and /fzm selftest need.
local function SurveySource(src)
    local s = { total = 0, byInstance = {}, byTexture = {}, byType = {}, hidden = 0,
                faded = 0, hasFakeHide = 0, hasData = 0, refs = 0, world = 0 }
    for icon, data in pairs(src.lib.minimapPins) do
        s.total = s.total + 1
        local inst = type(data) == "table" and data.instanceID or "?"
        s.byInstance[inst] = (s.byInstance[inst] or 0) + 1
        local tex = ShortTexture(IconTexture(icon))
        s.byTexture[tex] = (s.byTexture[tex] or 0) + 1
        if type(icon) == "table" then
            if icon.hidden == true then s.hidden = s.hidden + 1 end
            if type(icon.FakeHide) == "function" then s.hasFakeHide = s.hasFakeHide + 1 end
            if type(icon.data) == "table" then
                s.hasData = s.hasData + 1
                local t = icon.data.Type or "?"
                s.byType[t] = (s.byType[t] or 0) + 1
            end
            local ok, a = pcall(icon.GetAlpha, icon)
            if ok and type(a) == "number" and a < 0.05 then s.faded = s.faded + 1 end
        end
    end
    for _ in pairs(src.lib.minimapPinRegistry or {}) do s.refs = s.refs + 1 end
    for _ in pairs(src.lib.worldmapPins or {}) do s.world = s.world + 1 end
    return s
end

ns.RegisterCommand("dump", "pin registries: counts by continent, texture, type, hidden flag", function()
    local sources = ns.PinSources.List()
    if #sources == 0 then
        ns.Print("|cffff5555no HereBeDragons-Pins registry found|r (is Questie or TomTom loaded?)")
        return
    end
    for _, src in ipairs(sources) do
        local s = SurveySource(src)
        ns.Printf("|cffffd200%s|r%s", src.name, src.minor and (" minor " .. src.minor) or "")
        ns.Printf("  minimap pins %d (refs %d), world map pins %d", s.total, s.refs, s.world)
        ns.Printf("  by continent: %s", (SortedCounts(s.byInstance, 8)))
        ns.Printf("  hidden flag %d, frame alpha < 0.05: %d, has FakeHide %d, has data %d",
            s.hidden, s.faded, s.hasFakeHide, s.hasData)
        if s.hasData > 0 then ns.Printf("  by Questie type: %s", (SortedCounts(s.byType, 10))) end
        local tex, distinct = SortedCounts(s.byTexture, 12)
        ns.Printf("  by texture (%d distinct): %s", distinct, tex)
    end
end)

----------------------------------------------------------------------------------------------------
-- Party

ns.RegisterCommand("party", "party/raid member positions", function()
    local n = GetNumGroupMembers()
    if n == 0 then
        ns.Print("not in a group: join a party, then run this again")
        return
    end
    local raid = IsInRaid()
    local count = raid and n or (n - 1)
    local usable = 0
    for i = 1, count do
        local unit = (raid and "raid" or "party") .. i
        local north, west = UnitPosition(unit)
        local ok = Usable(north) and Usable(west)
        if ok then usable = usable + 1 end
        ns.Printf("  %s %s: (%s, %s)", unit, ns.Show(UnitName(unit)), ns.Show(north), ns.Show(west))
    end
    ns.Printf("party positions usable for %d of %d members", usable, count)
end)

----------------------------------------------------------------------------------------------------
-- Tooltip with an off-screen owner

-- Records what hides GameTooltip while a test case is running.
local tip = { active = false }

local function FrameLabel(f)
    if f == nil then return "nil" end
    local ok, name = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
    return ok and tostring(name) or "?"
end

local function EnsureTooltipHook()
    if tip.hooked then return end
    tip.hooked = true
    GameTooltip:HookScript("OnHide", function()
        if tip.active and not tip.hideStack then
            tip.hideAt = GetTime() - tip.start
            tip.hideStack = debugstack(2, 10, 0)
        end
    end)
end

-- Shows a test tooltip owned by `owner`, checks it at 1 and 3 s, then calls done(passed).
local function RunTooltipCase(label, owner, done)
    tip.active, tip.hideStack, tip.hideAt, tip.start = true, nil, nil, GetTime()

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    GameTooltip:AddLine("FarZoomMinimap tooltip test: " .. label)
    GameTooltip:AddLine("Keep the mouse still over an empty part of the screen.", 1, 1, 1, true)
    GameTooltip:Show()
    ns.Printf("|cffffd200%s|r: shown right away %s", label, tostring(GameTooltip:IsShown()))

    local survived = true
    for _, t in ipairs({ 1, 3 }) do
        C_Timer.After(t, function()
            local shown = GameTooltip:IsShown()
            local current = GameTooltip:GetOwner()
            local up = shown and current == owner
            survived = survived and up
            ns.Printf("  after %d s: %s", t, up and "still up"
                or string.format("|cffff5555gone|r (shown %s, owner %s)", tostring(shown), FrameLabel(current)))
            if t == 3 then
                tip.active = false
                if tip.hideStack then
                    ns.Printf("  hidden after %.2f s by:", tip.hideAt)
                    for line in tip.hideStack:gmatch("[^\n]+") do
                        ns.Print("    " .. line:gsub("Interface/AddOns/", ""):sub(1, 160))
                    end
                end
                if up then GameTooltip:Hide() end
                ns.Printf("  %s: %s", label, survived and "|cff55ff55PASS|r" or "|cffff5555FAIL|r")
                done(survived)
            end
        end)
    end
end

ns.RegisterCommand("tooltip", "tooltip with an on-screen owner, then an off-screen one (keep the mouse still)", function()
    EnsureTooltipHook()
    local owner = Spike.tooltipOwner
    if not owner then
        owner = CreateFrame("Frame", nil, UIParent)
        owner:SetSize(10, 10)
        Spike.tooltipOwner = owner
    end
    owner:Show()

    -- Control: the owner is on-screen, so this should always pass. If it fails, something
    -- else (mouseover, another addon) is hiding the tooltip and the real case means nothing.
    owner:ClearAllPoints()
    owner:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    RunTooltipCase("control (owner on-screen)", owner, function(control)
        owner:ClearAllPoints()
        owner:SetPoint("BOTTOMRIGHT", UIParent, "TOPLEFT", -200, 200) -- well off-screen
        RunTooltipCase("owner off-screen", owner, function(offscreen)
            local verdict
            if not control then
                verdict = "|cffffaa00INCONCLUSIVE|r: the control failed too, so something else hides the tooltip"
            elseif offscreen then
                verdict = "|cff55ff55PASS|r: an off-screen owner is fine"
            else
                verdict = "|cffff5555FAIL|r: the off-screen owner itself kills the tooltip"
            end
            ns.Print("tooltip test: " .. verdict)
        end)
    end)
end)

----------------------------------------------------------------------------------------------------
-- Tile spike: draw the tiles around the player from the vendored tile table

local N, SIZE = 5, 64 -- 5 x 5 tiles, 64 px each
local MID = (N - 1) / 2

local function BuildTileFrame()
    local f = CreateFrame("Frame", "FarZoomMinimapSpikeTiles", UIParent)
    f:SetSize(N * SIZE, N * SIZE + 18)
    f:SetPoint("CENTER", UIParent, "CENTER", -350, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOPLEFT", 4, -3)

    f.map = CreateFrame("Frame", nil, f)
    f.map:SetPoint("BOTTOMLEFT")
    f.map:SetSize(N * SIZE, N * SIZE)
    f.map:SetClipsChildren(true)

    f.tiles = {}
    for i = 0, N - 1 do
        for j = 0, N - 1 do
            local t = f.map:CreateTexture(nil, "ARTWORK")
            t:SetSize(SIZE, SIZE)
            t:SetPoint("TOPLEFT", f.map, "TOPLEFT", i * SIZE, -j * SIZE)
            f.tiles[i * N + j] = t
        end
    end

    f.dot = f.map:CreateTexture(nil, "OVERLAY")
    f.dot:SetSize(6, 6)
    f.dot:SetColorTexture(1, 0.2, 0.2, 1)
    return f
end

-- Fills the grid around (col, row). Returns loaded, failed, missing counts.
local function LoadTiles(f, instanceID, col, row)
    local tiles = TileTable(instanceID)
    local loaded, failed, missing = 0, 0, 0
    for i = 0, N - 1 do
        for j = 0, N - 1 do
            local t = f.tiles[i * N + j]
            local c, r = col - MID + i, row - MID + j
            local fid = tiles and G.IsValidTile(c, r) and tiles[G.TileKey(c, r)]
            if fid then
                if t:SetTexture(fid) == false then
                    t:SetColorTexture(0.6, 0, 0.6, 1) -- magenta: in the table but didn't load
                    failed = failed + 1
                else
                    loaded = loaded + 1
                end
            else
                t:SetColorTexture(0.12, 0.12, 0.2, 1) -- dark blue: no tile in the table (sea, edge)
                missing = missing + 1
            end
        end
    end
    return loaded, failed, missing
end

local function UpdateTiles(f)
    local p = ReadPosition()
    local a, b = p.north, p.west
    if Spike.swapAxes then a, b = b, a end
    if not (Usable(a) and Usable(b) and Usable(p.instanceID)) then
        f.label:SetText("no usable position here")
        f.dot:Hide()
        return
    end
    local col, row, fx, fy = G.WorldToTile(a, b)
    if col ~= f.col or row ~= f.row or p.instanceID ~= f.instanceID then
        f.col, f.row, f.instanceID = col, row, p.instanceID
        f.loaded, f.failed, f.missing = LoadTiles(f, p.instanceID, col, row)
        Spike.lastTileStats = { loaded = f.loaded, failed = f.failed, missing = f.missing }
    end
    f.dot:Show()
    f.dot:ClearAllPoints()
    f.dot:SetPoint("CENTER", f.map, "TOPLEFT", (MID + fx) * SIZE, -(MID + fy) * SIZE)
    f.label:SetFormattedText("tile %d,%d  cont %s  loaded %d  failed %d  none %d%s",
        col, row, ns.Show(p.instanceID), f.loaded, f.failed, f.missing,
        Spike.swapAxes and "  |cffff8800SWAPPED|r" or "")
end

ns.RegisterCommand("tiles", "toggle a 5x5 tile view around you from the tile table ('/fzm tiles swap' flips axes)", function(arg)
    local f = Spike.tileFrame or BuildTileFrame()
    Spike.tileFrame = f
    if arg == "swap" then
        Spike.swapAxes = not Spike.swapAxes
        f.col = nil -- force a reload
        ns.Printf("axes %s", Spike.swapAxes and "SWAPPED (first value read as west)" or "normal")
        if not f:IsShown() then return end
    elseif f:IsShown() and f.ticker then
        f.ticker:Cancel()
        f.ticker = nil
        f:Hide()
        return
    end
    f:Show()
    f.col = nil
    if not f.ticker then
        f.ticker = C_Timer.NewTicker(0.1, function() UpdateTiles(f) end)
    end
    UpdateTiles(f)
    ns.Print("compare with your minimap: the red dot is you, the terrain should match. Drag to move.")
end)

----------------------------------------------------------------------------------------------------
-- Self-test

ns.RegisterCommand("selftest", "run the automatic Phase 0 checks", function()
    local pass, fail, skip = 0, 0, 0
    local function Result(state, name, detail)
        if state == "pass" then pass = pass + 1 elseif state == "fail" then fail = fail + 1 else skip = skip + 1 end
        local color = state == "pass" and "55ff55" or state == "fail" and "ff5555" or "aaaaaa"
        ns.Printf("  |cff%s%s|r %s%s", color, state:upper(), name, detail and (": " .. detail) or "")
    end

    ns.Print("selftest:")
    Result((UnitPosition and GetPlayerFacing and C_Map and C_Map.GetBestMapForUnit
        and C_Minimap and C_Minimap.GetViewRadius) and "pass" or "fail", "APIs present")

    local p = ReadPosition()
    local inWorld = Usable(p.instanceID) and (p.instanceID == 0 or p.instanceID == 1)
    if inWorld then
        Result((Usable(p.north) and Usable(p.west)) and "pass" or "fail", "I1 position usable",
            ns.Show(p.north) .. ", " .. ns.Show(p.west))
        Result(Usable(p.facing) and "pass" or "fail", "I1 facing usable", ns.Show(p.facing))
    else
        Result("skip", "I1 position/facing", "stand outdoors in Eastern Kingdoms or Kalimdor")
    end

    local radius = C_Minimap.GetViewRadius()
    Result(Usable(radius) and "pass" or "fail", "minimap view radius", ns.Show(radius) .. " yd")

    local sources = ns.PinSources.List()
    Result(#sources > 0 and "pass" or "fail", "pin registries found", tostring(#sources))
    local questieLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")
    local questieSrc
    for _, src in ipairs(sources) do
        if src.name:find("Questie") then questieSrc = src end
    end
    if questieLoaded then
        Result(questieSrc and "pass" or "fail", "Questie's private HBD copy found")
    else
        Result("skip", "Questie's private HBD copy", "Questie not loaded")
    end
    if questieSrc then
        local s = SurveySource(questieSrc)
        if s.total == 0 then
            Result("skip", "Questie pins", "none registered (accept a quest with objectives nearby)")
        else
            Result("pass", "Questie pins registered", tostring(s.total))
            Result(s.hasFakeHide > 0 and "pass" or "fail", "icons carry FakeHide (hidden flag model)",
                string.format("%d of %d, hidden now %d", s.hasFakeHide, s.total, s.hidden))
            Result(s.hasData > 0 and "pass" or "fail", "icons carry data.Type",
                string.format("%d of %d", s.hasData, s.total))
        end
    end

    if inWorld and Usable(p.north) and Usable(p.west) then
        local col, row = G.WorldToTile(p.north, p.west)
        local tiles = TileTable(p.instanceID)
        local fid = tiles and tiles[G.TileKey(col, row)]
        if fid then
            Spike.probe = Spike.probe or UIParent:CreateTexture(nil, "BACKGROUND")
            Spike.probe:Hide()
            local ok = Spike.probe:SetTexture(fid)
            Result(ok ~= false and "pass" or "fail", "I14 tile for your position loads",
                string.format("col %d row %d file %s", col, row, tostring(fid)))
        else
            Result("fail", "I14 tile for your position in the table", string.format("col %d row %d", col, row))
        end
    else
        Result("skip", "I14 tile load", "needs an outdoor position")
    end

    ns.Printf("selftest: %d pass, %d fail, %d skip", pass, fail, skip)
    ns.Print("manual checks: /fzm tiles (terrain matches?), /fzm tooltip, /fzm party, /fzm combat then pull a mob")
end)
