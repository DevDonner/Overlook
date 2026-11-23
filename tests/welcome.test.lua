-- The welcome window: shown once after the first login, again on demand; its text covers the
-- controls the README lists.
local H = ...

local function noop() end
local function Obj()
    local o = { shown = false }
    setmetatable(o, { __index = function() return noop end })
    o.Show = function(self) self.shown = true end
    o.Hide = function(self) self.shown = false end
    o.GetStringHeight = function() return 12 end
    o.CreateTexture = function() return Obj() end
    o.CreateFontString = function() return Obj() end
    return o
end

local made, timers = {}, {}
local env = {
    CreateFrame = function() local f = Obj(); made[#made + 1] = f; return f end,
    UIParent = Obj(), UISpecialFrames = {},
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end },
}
local kept = {}
for k, v in pairs(env) do kept[k] = _G[k]; _G[k] = v end

local commands = {}
local ns = { RegisterCommand = function(name, _, fn) commands[name] = fn end, LOGO = "logo" }
H.loadAddonFile("UI/Welcome.lua", ns)
local W = ns.Welcome

H.test("welcome: shown once after the first login, never again by itself", function()
    ns.db = {}
    W.MaybeShow()
    H.eq(#timers, 1, "waits for the UI to settle")
    timers[1]()
    H.eq(ns.db.welcomeSeen, true)
    local window = made[2] -- made[1]: the login event frame
    H.truthy(window and window.shown, "the window is up")
    window:Hide()
    W.MaybeShow()
    H.eq(#timers, 1, "not again")
end)

H.test("welcome: the Instructions button and /overlook instructions open it again", function()
    local window = made[2]
    W.Show()
    H.truthy(window.shown)
    window:Hide()
    commands.instructions()
    H.truthy(window.shown)
end)

H.test("welcome: the text covers every control", function()
    local all = W.INTRO
    for _, s in ipairs(W.SECTIONS) do
        all = all .. " " .. s[1]
        for _, line in ipairs(s[2]) do all = all .. " " .. line[1] .. " " .. line[2] end
    end
    for _, want in ipairs({ "Mouse wheel", "Ctrl", "Drag the map", "Middle-click", "double-click", "Recenter",
        "Alt + drag", "grip", "reset", "Right-click", "ping", "Alt + wheel", "cave", "dungeon",
        "/overlook", "/ol", "minimap button", "Instructions", "Mount" }) do
        H.truthy(all:find(want, 1, true), want)
    end
end)

H.test("welcome: a profile switch or reset doesn't bring it back", function()
    local S = H.loadAddonFile("Core/Settings.lua", {})
    local db = S.Settings.Load({ welcomeSeen = true })
    H.eq(db.welcomeSeen, true)
    H.eq(S.Settings.DEFAULTS.welcomeSeen, nil, "not a profile setting")
    H.eq(S.Settings.Load({ welcomeSeen = "yes" }).welcomeSeen, nil, "junk dropped")
end)

for k in pairs(env) do _G[k] = kept[k] end
