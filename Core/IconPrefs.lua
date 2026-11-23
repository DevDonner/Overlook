-- Per-category icon preferences for the far map: show/hide, size, shrink-with-zoom.
-- Pure Lua, so the offline tests cover it.
--
-- Categories ("keys") are lower-case: "questie:<type>" for each Questie icon type, and the owning
-- addon's folder name for everything else ("rarescanner", "tomtom", "other").
local _, ns = ...

local IconPrefs = {}
ns.IconPrefs = IconPrefs

IconPrefs.QUESTIE_TYPES = { "available", "complete", "monster", "object", "item", "event", "manual" }
IconPrefs.SCALE_MIN, IconPrefs.SCALE_MAX = 0.25, 3

function IconPrefs.QuestieKey(iconType)
    return "questie:" .. string.lower(tostring(iconType or "other"))
end

function IconPrefs.AddonKey(label)
    return string.lower(tostring(label or "other"))
end

function IconPrefs.IsQuestie(key)
    return key:sub(1, 8) == "questie:"
end

-- Defaults: Questie's icons don't shrink as you zoom out, other addons' icons (RareScanner's are
-- large) do. Sizes per group, where they differ from 1 (scale, shrink).
IconPrefs.DEFAULTS = {
    ["questie:monster"] = { 1.15 },
    ["questie:object"] = { 1.15 },
    ["questie:event"] = { 1.15 },
    ["questie:item"] = { 2, true },
}

function IconPrefs.Defaults(key)
    local d = IconPrefs.DEFAULTS[key]
    local shrink = not IconPrefs.IsQuestie(key)
    if d and d[2] ~= nil then shrink = d[2] end
    return false, d and d[1] or 1, shrink
end

-- Returns hide, scale, shrink for a category.
function IconPrefs.Get(db, key)
    local hide, scale, shrink = IconPrefs.Defaults(key)
    local e = db and db.icons and db.icons[key]
    if type(e) == "table" then
        if e.hide ~= nil then hide = e.hide end
        if type(e.scale) == "number" then scale = e.scale end
        if e.shrink ~= nil then shrink = e.shrink end
    end
    return hide, scale, shrink
end

-- Which keys a name the user typed means: "all", "questie" (every Questie type), a Questie type
-- on its own ("monster"), or a key as listed. `known` is a set of keys seen so far.
function IconPrefs.Match(name, known)
    name = string.lower(name or "")
    local out = {}
    local function add(k) out[#out + 1] = k end
    local all = {}
    for k in pairs(known or {}) do all[k] = true end
    for _, t in ipairs(IconPrefs.QUESTIE_TYPES) do all[IconPrefs.QuestieKey(t)] = true end

    if name == "all" then
        for k in pairs(all) do add(k) end
    elseif name == "questie" then
        for k in pairs(all) do if IconPrefs.IsQuestie(k) then add(k) end end
    elseif all[name] then
        add(name)
    elseif all["questie:" .. name] then
        add("questie:" .. name)
    end
    table.sort(out)
    return out
end

local function Entry(db, key)
    db.icons = type(db.icons) == "table" and db.icons or {}
    local e = db.icons[key]
    if type(e) ~= "table" then
        e = {}
        db.icons[key] = e
    end
    return e
end

-- Applies a command to the matched keys. Returns the keys changed, or nil and an error message.
-- action: "hide", "show", "size" (value: number), "shrink" (value: "on"/"off"), "reset".
function IconPrefs.Apply(db, name, known, action, value)
    local keys = IconPrefs.Match(name, known)
    if #keys == 0 then return nil, "no icon group called '" .. tostring(name) .. "'" end
    action = string.lower(action or "")
    local scale
    if action == "size" then
        scale = tonumber(value)
        if not scale then return nil, "size needs a number, e.g. 0.6" end
        scale = math.max(IconPrefs.SCALE_MIN, math.min(IconPrefs.SCALE_MAX, scale))
    elseif action == "shrink" then
        value = string.lower(value or "")
        if value ~= "on" and value ~= "off" then return nil, "shrink needs on or off" end
    elseif action ~= "hide" and action ~= "show" and action ~= "reset" then
        return nil, "unknown action '" .. action .. "'"
    end
    for _, key in ipairs(keys) do
        if action == "reset" then
            if type(db.icons) == "table" then db.icons[key] = nil end
        else
            local e = Entry(db, key)
            if action == "hide" then e.hide = true
            elseif action == "show" then e.hide = false
            elseif action == "size" then e.scale = scale
            else e.shrink = (value == "on") end
        end
    end
    return keys
end
