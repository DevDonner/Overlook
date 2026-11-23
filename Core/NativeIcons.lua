-- The game's own minimap icons, off by default: Questie (a required dependency) already draws the
-- same quest turn-ins, objectives and town services, so leaving the game's on stacks two icons on
-- one spot. The game's are also only drawn at native zoom.
--
-- Two switches:
--  * the questPOI CVar: the game's quest icons (turn-ins, objectives). Questie's own "Questie"
--    icon theme sets it to 0 for the same reason.
--  * C_Minimap tracking entries for town services (mailbox, trainers, flight masters...), which
--    Questie's Townsfolk icons cover. On 1.60.1 those are the entries with subType 2, plus
--    Flight Master (subType -1, told apart by its icon). Everything else is left alone: spells
--    (Find Minerals), Target, Focus Target, Low-Level Quests, Points of Interest, digsites...
--    Questie has no replacement for those.
--
-- Applied once per login while the setting is off, so a change made in the game's own tracking
-- menu lasts the session. Entries we switch off are remembered by name and switched back on if
-- the setting is turned on.
local _, ns = ...

local NativeIcons = {}
ns.NativeIcons = NativeIcons

local function Secret(v)
    return ns.IsSecret and ns.IsSecret(v) or false
end

-- api: { GetNumTrackingTypes = fn() -> n, GetTrackingInfo = fn(i) -> table or name, texture, active, type }
-- Returns { { index, name, active, spell, subType, texture }, ... } in the game's order; secret or nameless entries
-- are left out.
function NativeIcons.ReadTracking(api)
    local out = {}
    if not (api and api.GetNumTrackingTypes and api.GetTrackingInfo) then return out end
    local okN, n = pcall(api.GetNumTrackingTypes)
    if not okN or Secret(n) or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, a, b, c, d, e = pcall(api.GetTrackingInfo, i)
        if ok and a ~= nil and not Secret(a) then
            local name, texture, active, kind, subType
            if type(a) == "table" then
                name, texture, active, kind, subType = a.name, a.texture, a.active, a.type, a.subType
            else
                name, texture, active, kind, subType = a, b, c, d, e -- older: name, texture, active, type, subType
            end
            if type(name) == "string" and name ~= "" and not Secret(name) and not Secret(active) then
                out[#out + 1] = {
                    index = i, name = name, active = active and true or false, spell = kind == "spell",
                    subType = (not Secret(subType)) and subType or nil,
                    texture = (not Secret(texture)) and texture or nil,
                }
            end
        end
    end
    return out
end

local FLIGHT_MASTER_TEXTURE = 136456

-- A town service Questie's Townsfolk icons cover.
function NativeIcons.IsTownService(e)
    if e.spell then return false end
    return e.subType == 2 or e.texture == FLIGHT_MASTER_TEXTURE
end

-- Entries to switch off: active town services.
function NativeIcons.ToSwitchOff(entries)
    local out = {}
    for _, e in ipairs(entries) do
        if e.active and NativeIcons.IsTownService(e) then out[#out + 1] = e end
    end
    return out
end

-- Names in `remembered` that aren't town services: switched off by an earlier version that took
-- every non-spell entry (Target, Track Quest POIs...). Those get switched back on once.
function NativeIcons.Overreach(entries, remembered)
    local want, out = {}, {}
    for _, name in ipairs(remembered or {}) do want[name] = true end
    for _, e in ipairs(entries) do
        if want[e.name] and not NativeIcons.IsTownService(e) then out[#out + 1] = e end
    end
    return out
end

-- Entries to switch back on: ones we switched off (names in `remembered`) that are off now.
function NativeIcons.ToRestore(entries, remembered)
    local want, out = {}, {}
    for _, name in ipairs(remembered or {}) do want[name] = true end
    for _, e in ipairs(entries) do
        if want[e.name] and not e.active then out[#out + 1] = e end
    end
    return out
end

----------------------------------------------------------------------------------------------------
-- In game

local function TrackingApi()
    if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.SetTracking then return C_Minimap end
    if GetNumTrackingTypes and SetTracking then
        return { GetNumTrackingTypes = GetNumTrackingTypes, GetTrackingInfo = GetTrackingInfo, SetTracking = SetTracking }
    end
end

local function SetQuestPOI(on)
    local want = on and "1" or "0"
    if GetCVar and SetCVar and GetCVar("questPOI") ~= nil and GetCVar("questPOI") ~= want then
        pcall(SetCVar, "questPOI", want)
    end
end

-- Switches the game's icons off (setting off) and remembers which tracking entries it changed.
function NativeIcons.Apply()
    if ns.db.nativeIcons then return end
    SetQuestPOI(false)
    local api = TrackingApi()
    if not api then return end
    local entries = NativeIcons.ReadTracking(api)
    -- Give back what an earlier version wrongly switched off, and forget it.
    local overreach = NativeIcons.Overreach(entries, ns.db.nativeOff)
    if #overreach > 0 then
        local drop = {}
        for _, e in ipairs(overreach) do
            drop[e.name] = true
            if not e.active then pcall(api.SetTracking, e.index, true) end
        end
        local kept = {}
        for _, name in ipairs(ns.db.nativeOff) do
            if not drop[name] then kept[#kept + 1] = name end
        end
        ns.db.nativeOff = kept
    end
    local remembered, seen = ns.db.nativeOff, {}
    for _, name in ipairs(remembered) do seen[name] = true end
    for _, e in ipairs(NativeIcons.ToSwitchOff(entries)) do
        if pcall(api.SetTracking, e.index, false) and not seen[e.name] then
            seen[e.name] = true
            remembered[#remembered + 1] = e.name
        end
    end
end

-- The settings checkbox: on gives the game its icons back, off takes them away again.
function NativeIcons.SetShown(on)
    ns.db.nativeIcons = on and true or false
    if not on then
        NativeIcons.Apply()
        return
    end
    SetQuestPOI(true)
    local api = TrackingApi()
    if api then
        for _, e in ipairs(NativeIcons.ToRestore(NativeIcons.ReadTracking(api), ns.db.nativeOff)) do
            pcall(api.SetTracking, e.index, true)
        end
    end
    ns.db.nativeOff = {}
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- A moment later, so Questie and the game have finished their own login setup.
    C_Timer.After(2, function()
        if ns.db then NativeIcons.Apply() end
    end)
end)

-- Every tracking entry's raw fields, to see what tells town services from the rest.
local function Dump()
    local api = TrackingApi()
    if not api then
        ns.Print("this client has no tracking list")
        return
    end
    local n = api.GetNumTrackingTypes()
    for i = 1, n do
        local ok, a, b, c, d, e = pcall(api.GetTrackingInfo, i)
        local parts = {}
        if ok and type(a) == "table" then
            local keys = {}
            for k in pairs(a) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. ns.Show(a[k]) end
        else
            parts[1] = table.concat({ ns.Show(a), ns.Show(b), ns.Show(c), ns.Show(d), ns.Show(e) }, ", ")
        end
        ns.Printf("  %d: %s", i, table.concat(parts, "  "))
    end
end

-- What is under the mouse right now, and who owns the tooltip. Type it in chat while hovering.
ns.RegisterCommand("hover", "name what is under the mouse and who owns the tooltip", function()
    local foci = {}
    if _G.GetMouseFoci then
        foci = _G.GetMouseFoci() or {}
    elseif _G.GetMouseFocus then
        foci = { _G.GetMouseFocus() }
    end
    local function Describe(f)
        if not f then return "nil" end
        local name = (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or tostring(f)
        local p = f.GetParent and f:GetParent()
        local pname = p and ((p.GetDebugName and p:GetDebugName()) or (p.GetName and p:GetName())) or "-"
        return string.format("%s  (parent %s)", tostring(name), tostring(pname))
    end
    ns.Printf("under mouse: %d frame(s)", #foci)
    for i, f in ipairs(foci) do ns.Printf("  %d: %s", i, Describe(f)) end
    local tip = GameTooltip
    if tip and tip:IsShown() then
        ns.Printf("tooltip owner: %s", Describe(tip:GetOwner()))
        -- Text may be a secret value on this client: ns.Show never errors on one.
        local n = (tip.NumLines and tip:NumLines()) or 1
        if ns.IsSecret(n) or type(n) ~= "number" then n = 1 end
        for i = 1, math.min(n, 8) do
            local left = _G["GameTooltipTextLeft" .. i]
            local ok, text = pcall(function() return left and left:GetText() end)
            ns.Printf("  tooltip line %d: %s", i, ok and ns.Show(text) or ("error: " .. ns.Show(text)))
        end
    else
        ns.Print("no tooltip shown")
    end
end)

ns.RegisterCommand("native", "the game's own quest and town icons: state (/fzm native on | off | dump)", function(arg)
    arg = (arg or ""):lower()
    if arg == "dump" then
        Dump()
        return
    end
    if arg == "on" or arg == "off" then
        NativeIcons.SetShown(arg == "on")
        if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
    end
    ns.Printf("game's own icons: %s (questPOI %s)", ns.db.nativeIcons and "shown" or "off",
        ns.Show(GetCVar and GetCVar("questPOI")))
    local api = TrackingApi()
    for _, e in ipairs(api and NativeIcons.ReadTracking(api) or {}) do
        if e.active then ns.Printf("  tracking on: %s%s", e.name, e.spell and " (spell, left alone)" or "") end
    end
end)
