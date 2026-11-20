-- Finds every HereBeDragons-Pins registry we can read.
--
-- Questie 12.x does NOT use the shared LibStub copy of HereBeDragons-Pins: it ships a private,
-- modified copy as a Questie module ("HBDPins"). Its tables have the same layout (minimapPins,
-- minimapPinRegistry, worldmapPins). TomTom, RareScanner and others use the shared LibStub copy.
-- So there are (up to) two registries, and the mirror has to read both.
local _, ns = ...

local PinSources = {}
ns.PinSources = PinSources

local function IsPinsTable(lib)
    return type(lib) == "table" and type(lib.minimapPins) == "table"
end

-- Returns a list of { name = string, lib = table, minor = number|nil }.
function PinSources.List()
    local list = {}

    -- Questie's private copy. QuestieLoader only exists once Questie has loaded. ImportModule
    -- creates an empty module when the name is unknown, so check the fields, not the return.
    local loader = _G.QuestieLoader
    if type(loader) == "table" and type(loader.ImportModule) == "function" then
        local ok, mod = pcall(loader.ImportModule, loader, "HBDPins")
        if ok and IsPinsTable(mod) then
            list[#list + 1] = { name = "Questie (private HBD copy)", lib = mod }
        end
    end

    -- The shared copy (TomTom, RareScanner, ...).
    local libStub = _G.LibStub
    if type(libStub) == "table" or type(libStub) == "function" then
        local ok, lib, minor = pcall(libStub, "HereBeDragons-Pins-2.0", true)
        if ok and IsPinsTable(lib) then
            list[#list + 1] = { name = "HereBeDragons-Pins-2.0 (shared)", lib = lib, minor = minor }
        end
    end

    return list
end
