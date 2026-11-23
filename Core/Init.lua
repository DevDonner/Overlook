-- Namespace, chat output and the /overlook command dispatcher.
local ADDON, ns = ...

ns.name = ADDON

local PREFIX = "|cff4fc3f7Overlook|r "

function ns.Print(msg)
    print(PREFIX .. tostring(msg))
end

function ns.Printf(fmt, ...)
    ns.Print(string.format(fmt, ...))
end

-- issecretvalue exists on Midnight-era clients; doing math on a secret value errors.
local issecret = issecretvalue or function() return false end

function ns.IsSecret(v)
    return v ~= nil and issecret(v) and true or false
end

-- Formats a value for chat without erroring on secrets.
function ns.Show(v)
    if v == nil then return "nil" end
    if ns.IsSecret(v) then return "|cffff5555<secret>|r" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return tostring(v)
end

local commands, order = {}, {}

function ns.RegisterCommand(name, help, fn)
    if not commands[name] then order[#order + 1] = name end
    commands[name] = { help = help, fn = fn }
end

local function ShowHelp()
    if ns.Options then ns.Print("/overlook on its own opens the settings") end
    ns.Print("commands:")
    for _, name in ipairs(order) do
        ns.Printf("  /overlook %s - %s", name, commands[name].help)
    end
end

SLASH_OVERLOOK1 = "/overlook"
SLASH_OVERLOOK2 = "/ol"
SLASH_OVERLOOK3 = "/fzm" -- the name before the rebrand
SlashCmdList.OVERLOOK = function(msg)
    local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    name = name:lower()
    if name == "" and ns.Options then
        ns.Options.Toggle()
        return
    end
    local cmd = commands[name]
    if not cmd then
        ShowHelp()
        return
    end
    cmd.fn(rest)
end
