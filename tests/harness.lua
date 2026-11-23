-- Minimal test runner for plain Lua 5.1. No dependencies, so CI only needs Lua itself.
local H = { passed = 0, failed = 0, failures = {} }

local currentFile = "?"

local beforeEach

function H.setFile(name)
    currentFile = name
    beforeEach = nil
end

-- Runs fn before every following test in the current file, so no test sees another's state.
function H.beforeEach(fn)
    beforeEach = fn
end

function H.test(name, fn)
    local ok, err = pcall(function()
        if beforeEach then beforeEach() end
        fn()
    end)
    if ok then
        H.passed = H.passed + 1
    else
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = string.format("%s: %s\n    %s", currentFile, name, tostring(err))
    end
end

function H.eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "",
            tostring(expected), tostring(actual)), 2)
    end
end

function H.near(actual, expected, eps, msg)
    if type(actual) ~= "number" or math.abs(actual - expected) > eps then
        error(string.format("%sexpected %s +/- %s, got %s", msg and (msg .. ": ") or "",
            tostring(expected), tostring(eps), tostring(actual)), 2)
    end
end

function H.truthy(v, msg)
    if not v then error(msg or "expected a truthy value", 2) end
end

-- Runs an addon file the way the game does: with (addonName, namespace) as its varargs.
function H.loadAddonFile(path, ns)
    local chunk = assert(loadfile(path))
    chunk("Overlook", ns)
    return ns
end

return H
