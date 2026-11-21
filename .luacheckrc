std = "lua51"
max_line_length = false

exclude_files = {
    "Data/MinimapTiles.lua", -- vendored, generated
    ".lua/**",               -- CI's Lua install
    ".luarocks/**",
}

globals = {
    "SLASH_FARZOOMMINIMAP1",
    "SlashCmdList",
    "FarZoomMinimapDB",
    "GetMinimapShape",
}

read_globals = {
    -- WoW API
    "C_AddOns", "C_Map", "C_Minimap", "C_Timer",
    "CreateFrame", "GameTooltip", "GetNumGroupMembers", "GetPlayerFacing", "GetTime", "GetCursorPosition", "debugstack",
    "InCombatLockdown", "IsInRaid", "Minimap", "UIParent",
    "UnitName", "UnitPosition", "issecretvalue",
    "hooksecurefunc", "IsAltKeyDown", "IsControlKeyDown", "MinimapCluster",
    -- Other addons
    "LibStub", "QuestieLoader",
}

files["tests/"] = {
    globals = { "LibStub", "QuestieLoader", "CreateFrame", "C_Timer", "hooksecurefunc", "GameTooltip", "GetCursorPosition" },
}
