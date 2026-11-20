-- PinSources finds Questie's private HBD copy and the shared LibStub copy.
local H = ...
local PinSources = H.loadAddonFile("Core/PinSources.lua", {}).PinSources

local function WithGlobals(questieModule, sharedLib, fn)
    local oldLoader, oldStub = _G.QuestieLoader, _G.LibStub
    if questieModule ~= nil then
        _G.QuestieLoader = {
            ImportModule = function(_, name)
                if name == "HBDPins" then return questieModule end
                return { private = {} }
            end,
        }
    else
        _G.QuestieLoader = nil
    end
    if sharedLib ~= nil then
        _G.LibStub = setmetatable({}, {
            __call = function(_, major, silent)
                if major == "HereBeDragons-Pins-2.0" then return sharedLib, 17 end
                if not silent then error("no library " .. major) end
            end,
        })
    else
        _G.LibStub = nil
    end
    local ok, err = pcall(fn)
    _G.QuestieLoader, _G.LibStub = oldLoader, oldStub
    if not ok then error(err, 0) end
end

H.test("no Questie and no LibStub: no sources", function()
    WithGlobals(nil, nil, function()
        H.eq(#PinSources.List(), 0)
    end)
end)

H.test("finds Questie's private copy and the shared copy", function()
    WithGlobals({ minimapPins = {} }, { minimapPins = {} }, function()
        local list = PinSources.List()
        H.eq(#list, 2)
        H.truthy(list[1].name:find("Questie"), "first source should be Questie")
        H.eq(list[2].minor, 17, "shared minor")
    end)
end)

H.test("an empty Questie module (HBDPins not loaded) is ignored", function()
    WithGlobals({ private = {} }, nil, function()
        H.eq(#PinSources.List(), 0)
    end)
end)

H.test("LibStub without HereBeDragons-Pins is ignored", function()
    WithGlobals(nil, nil, function()
        _G.LibStub = setmetatable({}, { __call = function() return nil end })
        H.eq(#PinSources.List(), 0)
    end)
end)
