-- The dev build's TOC (OverlookDev.toc) loads exactly the files the release TOC does.
local H = ...

local function Files(path)
    local list = {}
    for line in io.lines(path) do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:find("^#") then list[#list + 1] = line end
    end
    return table.concat(list, "\n")
end

H.test("OverlookDev.toc lists the same files as Overlook.toc", function()
    H.eq(Files("OverlookDev.toc"), Files("Overlook.toc"))
end)
