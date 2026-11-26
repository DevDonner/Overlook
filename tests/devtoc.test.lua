-- The dev build's TOC (OverlookDev.toc) loads exactly the files the release TOC does, plus the
-- dev-only tools below, which the CurseForge zip leaves out (.pkgmeta).
local H = ...

local DEV_ONLY = { ["Far\\SelfTest.lua"] = true }

local function Files(path, skip)
    local list = {}
    for line in io.lines(path) do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:find("^#") and not (skip and skip[line]) then list[#list + 1] = line end
    end
    return table.concat(list, "\n")
end

H.test("OverlookDev.toc lists the same files as Overlook.toc, plus the dev-only tools", function()
    H.eq(Files("OverlookDev.toc", DEV_ONLY), Files("Overlook.toc"))
    local dev = "\n" .. Files("OverlookDev.toc") .. "\n"
    for f in pairs(DEV_ONLY) do
        H.truthy(dev:find("\n" .. f:gsub("%p", "%%%0") .. "\n"), f .. " in OverlookDev.toc")
    end
end)

H.test("the dev-only tools are left out of the CurseForge zip", function()
    local ignored = {}
    for line in io.lines(".pkgmeta") do
        local f = line:gsub("\r$", ""):match("^%s+%-%s+(%S+)%s*$") -- the whole line: the packager takes a trailing comment as part of the name
        if f then ignored[f] = true end
    end
    for f in pairs(DEV_ONLY) do
        H.truthy(ignored[(f:gsub("\\", "/"))], f .. " in .pkgmeta's ignore list")
    end
end)
