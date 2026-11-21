-- Offline test entry point. Run from the repo root: lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local H = require("harness")

local FILES = {
    "tests/geometry.test.lua",
    "tests/tiles.test.lua",
    "tests/pinsources.test.lua",
    "tests/settings.test.lua",
    "tests/view.test.lua",
}

for _, file in ipairs(FILES) do
    H.setFile(file)
    local chunk = assert(loadfile(file))
    chunk(H)
end

for _, f in ipairs(H.failures) do
    print("FAIL " .. f)
end
print(string.format("%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
