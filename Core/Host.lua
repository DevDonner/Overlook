-- Hosting: when another addon owns the minimap frame (EllesmereUI's minimap, or anything that
-- keeps pulling the Minimap back to its own frame), Overlook stops fighting it for the frame and
-- moves in instead. The other addon keeps the map's size, place, shape, border, buttons and
-- zone text; Overlook lays its far view over that map and leaves the frame alone.
--
-- While hosted, the map's size and shape are the host's, not ours: every module asks
-- Host.Size() and Host.IsRound() instead of reading ns.db.size and ns.db.round.
--
-- Setting: hostOthers (on by default). Off: Overlook takes the map as before.
local _, ns = ...

local Host = {}
ns.Host = Host

Host.owner = nil -- the host's name while hosted, else nil
Host.size = nil  -- the host map's width in UIParent units, while hosted
Host.round = false

-- Minimap addons known to own the frame: { addon folder, name shown, active() }.
Host.KNOWN = {
    {
        addon = "EllesmereUIMinimap", label = "EllesmereUI",
        active = function()
            local eui = _G.EllesmereUI
            local lite = type(eui) == "table" and eui.Lite
            if not (lite and lite.GetAddon) then return true end -- loaded: assume its map is on
            local ok, addon = pcall(lite.GetAddon, "EllesmereUIMinimap", true)
            local p = ok and type(addon) == "table" and addon.db and addon.db.profile
            local m = type(p) == "table" and p.minimap
            return not (type(m) == "table" and m.enabled == false)
        end,
    },
}

local function Loaded(name)
    local api = _G.C_AddOns
    local fn = api and api.IsAddOnLoaded or _G.IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded and true or false
end

-- The known minimap addon that's loaded and has its map on, or nil.
function Host.Known()
    for _, k in ipairs(Host.KNOWN) do
        if Loaded(k.addon) then
            local ok, on = pcall(k.active)
            if not ok or on then return k.label end
        end
    end
end

-- Who hosts the map. Pure: want = the hostOthers setting; known = Host.Known(); fought = whether
-- an unknown addon took the Minimap back after we parented it.
function Host.Decide(want, known, fought)
    if want == false then return nil end
    if known then return known end
    if fought then return "another addon" end
    return nil
end

-- The map's size and shape now: the host's while hosted, else our own settings.
function Host.Size()
    if Host.owner and Host.size and Host.size > 0 then return Host.size end
    return ns.db and ns.db.size or 200
end

function Host.IsRound()
    if Host.owner then return Host.round == true end
    return ns.db ~= nil and ns.db.round == true
end
