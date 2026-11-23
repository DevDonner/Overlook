-- Settings profiles, and export / import strings for sharing them. Pure Lua, so the offline tests
-- cover it; UI/Options.lua has the buttons and Profiles.Reapply puts a switched profile to work.
--
-- The live settings stay in ns.db (the saved table) as before. A profile is a copy of the
-- shareable settings: every key in Settings.DEFAULTS plus the icon-group preferences. Switching
-- saves the live settings into the current profile and copies the new one in, in place, so
-- nothing that holds ns.db goes stale. The map's position and the minimap button stay as they
-- are: they belong to this screen, not to a look.
--
-- An export string is "FZM1:" and base64 of a small table syntax of our own. Imports are parsed,
-- never run, and only known keys with the right types survive (then Settings.Load clamps them).
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

Profiles.DEFAULT = "Default"
Profiles.PREFIX = "FZM1:"
Profiles.MAX_NAME = 32

----------------------------------------------------------------------------------------------------
-- Snapshots

local function CopyIcons(icons)
    local out = {}
    if type(icons) ~= "table" then return out end
    local IP = ns.IconPrefs
    for key, e in pairs(icons) do
        if type(key) == "string" and type(e) == "table" then
            local c = {}
            if type(e.hide) == "boolean" then c.hide = e.hide end
            if type(e.shrink) == "boolean" then c.shrink = e.shrink end
            if type(e.scale) == "number" then
                c.scale = IP and math.max(IP.SCALE_MIN, math.min(IP.SCALE_MAX, e.scale)) or e.scale
            end
            if next(c) then out[key] = c end
        end
    end
    return out
end

-- The shareable settings of a table, with types checked against the defaults.
function Profiles.Snapshot(src)
    local out = {}
    for k, d in pairs(ns.Settings.DEFAULTS) do
        local v = src[k]
        if type(v) == type(d) then out[k] = v end
    end
    out.icons = CopyIcons(src.icons)
    return out
end

-- Copies a snapshot into the live table (in place); missing keys go back to their defaults.
local function LoadInto(db, snap)
    for k in pairs(ns.Settings.DEFAULTS) do db[k] = nil end
    for k, v in pairs(Profiles.Snapshot(snap)) do db[k] = v end
    ns.Settings.Load(db)
end

-- Sets up the profile table: a first run (or a saved table from before profiles) turns the
-- current settings into the Default profile.
function Profiles.Init(db)
    if type(db.profiles) ~= "table" then db.profiles = {} end
    for name, p in pairs(db.profiles) do
        if type(name) ~= "string" or type(p) ~= "table" then db.profiles[name] = nil end
    end
    if type(db.profile) ~= "string" or not db.profiles[db.profile] then
        db.profile = next(db.profiles) or Profiles.DEFAULT
    end
    if not db.profiles[db.profile] then db.profiles[db.profile] = Profiles.Snapshot(db) end
    return db
end

-- Saves the live settings into the current profile (on switching and on logout).
function Profiles.Save(db)
    db.profiles[db.profile] = Profiles.Snapshot(db)
end

function Profiles.List(db)
    local out = {}
    for name in pairs(db.profiles) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local function CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%c|]", "")
    if name == "" then return nil end
    return name:sub(1, Profiles.MAX_NAME)
end
Profiles.CleanName = CleanName

-- Each of these returns true, or nil and a message for the user.
function Profiles.Switch(db, name)
    if not db.profiles[name] then return nil, "no profile called " .. tostring(name) end
    if name == db.profile then return true end
    Profiles.Save(db)
    db.profile = name
    LoadInto(db, db.profiles[name])
    return true
end

-- A new profile, copied from the current settings, and switched to.
function Profiles.New(db, name)
    name = CleanName(name)
    if not name then return nil, "type a name first" end
    if db.profiles[name] then return nil, "there's already a profile called " .. name end
    Profiles.Save(db)
    db.profiles[name] = Profiles.Snapshot(db)
    db.profile = name
    return true
end

function Profiles.Delete(db, name)
    if not db.profiles[name] then return nil, "no profile called " .. tostring(name) end
    if name == db.profile then return nil, "switch to another profile before deleting this one" end
    db.profiles[name] = nil
    return true
end

-- The current profile back to the defaults (icon groups too).
function Profiles.Reset(db)
    LoadInto(db, {})
    Profiles.Save(db)
    return true
end

----------------------------------------------------------------------------------------------------
-- Serializing: { key = value; ... } with sorted keys; values are booleans, numbers, strings
-- ("..." with \ escapes) or nested tables.

local function Encode(v, out)
    local t = type(v)
    if t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "number" then
        out[#out + 1] = string.format("%.6g", v)
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[\\"]', "\\%0") .. '"'
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            Encode(k, out)
            out[#out + 1] = "="
            Encode(v[k], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    end
end

function Profiles.Serialize(v)
    local out = {}
    Encode(v, out)
    return table.concat(out)
end

-- Parses Serialize's output. Returns the value, or nil on anything malformed.
function Profiles.Deserialize(s)
    if type(s) ~= "string" then return nil end
    local pos, depth = 1, 0
    local value

    local function String()
        local buf = {}
        pos = pos + 1
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == "\\" then
                buf[#buf + 1] = s:sub(pos + 1, pos + 1)
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(buf)
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return nil
    end

    function value()
        local c = s:sub(pos, pos)
        if c == "T" or c == "F" then
            pos = pos + 1
            return c == "T"
        elseif c == '"' then
            return String()
        elseif c == "{" then
            depth = depth + 1
            if depth > 4 then return nil end
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                if s:sub(pos, pos) ~= '"' then return nil end
                local k = String()
                if not k or s:sub(pos, pos) ~= "=" then return nil end
                pos = pos + 1
                local v = value()
                if v == nil or s:sub(pos, pos) ~= ";" then return nil end
                pos = pos + 1
                t[k] = v
            end
            pos = pos + 1
            depth = depth - 1
            return t
        end
        local num = s:match("^-?[%d.]+e?[-+]?%d*", pos)
        local n = num and tonumber(num)
        if not n then return nil end
        pos = pos + #num
        return n
    end

    local ok, v = pcall(value)
    if not ok or v == nil or pos ~= #s + 1 then return nil end
    return v
end

----------------------------------------------------------------------------------------------------
-- Base64

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Profiles.ToBase64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = 2 + (b and 1 or 0) + (c and 1 or 0)
        for j = 1, 4 do
            if j <= chars then
                local idx = math.floor(n / 64 ^ (4 - j)) % 64
                out[#out + 1] = B64:sub(idx + 1, idx + 1)
            else
                out[#out + 1] = "="
            end
        end
    end
    return table.concat(out)
end

function Profiles.FromBase64(s)
    s = s:gsub("%s", "")
    if #s % 4 ~= 0 or s:find("[^%w+/=]") then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local n, pad = 0, 0
        for j = 0, 3 do
            local ch = s:sub(i + j, i + j)
            local idx
            if ch == "=" then
                idx, pad = 0, pad + 1
            else
                idx = B64:find(ch, 1, true) - 1
            end
            n = n * 64 + idx
        end
        local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end

----------------------------------------------------------------------------------------------------
-- Export / import

function Profiles.Export(db)
    return Profiles.PREFIX .. Profiles.ToBase64(Profiles.Serialize(Profiles.Snapshot(db)))
end

-- Reads an export string into a snapshot (checked and clamped). nil and a message if it isn't one.
function Profiles.Decode(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #Profiles.PREFIX) ~= Profiles.PREFIX then
        return nil, "that isn't a FarZoomMinimap profile string"
    end
    local raw = Profiles.FromBase64(text:sub(#Profiles.PREFIX + 1))
    local t = raw and Profiles.Deserialize(raw)
    if type(t) ~= "table" then return nil, "that profile string is damaged (copied in full?)" end
    local snap = ns.Settings.Load(Profiles.Snapshot(t))
    return Profiles.Snapshot(snap)
end

-- Imports an export string as a new profile and switches to it.
function Profiles.Import(db, text, name)
    local snap, err = Profiles.Decode(text)
    if not snap then return nil, err end
    name = CleanName(name) or "Imported"
    local base, i = name, 2
    while db.profiles[name] do
        name = (base:sub(1, Profiles.MAX_NAME - 4) .. " " .. i)
        i = i + 1
    end
    Profiles.Save(db)
    db.profiles[name] = snap
    db.profile = name
    LoadInto(db, snap)
    return true, name
end

----------------------------------------------------------------------------------------------------
-- In game: putting a switched profile to work

-- Re-applies every setting after the live table changed wholesale (switch, import, reset).
function Profiles.Reapply(nativeWas)
    local function try(fn, ...) if fn then pcall(fn, ...) end end
    try(ns.Shell and ns.Shell.SetRotate, ns.db.rotate)
    try(ns.Shell and ns.Shell.Apply)
    try(ns.Far and ns.Far.SetMaxZoom, ns.db.maxFarZoom)
    try(ns.Routes and ns.Routes.Refresh)
    try(ns.Party and ns.Party.Refresh)
    try(ns.Mirror and ns.Mirror.RefreshPrefs)
    try(ns.Areas and ns.Areas.Refresh)
    if ns.NativeIcons and nativeWas ~= nil and nativeWas ~= ns.db.nativeIcons then
        try(ns.NativeIcons.SetShown, ns.db.nativeIcons)
    end
    try(ns.Options and ns.Options.Refresh)
end
