std = "lua51"
max_line_length = false

exclude_files = {
    "Data/MinimapTiles.lua", -- vendored, generated
    "Data/Caves.lua",        -- generated (tools/map-data/caves.py)
    ".lua/**",               -- CI's Lua install
    ".luarocks/**",
}

globals = {
    "SLASH_FARZOOMMINIMAP1",
    "SlashCmdList",
    "FarZoomMinimapDB",
    "GetMinimapShape",
    "FarZoomMinimap_OnAddonCompartmentClick",
}

read_globals = {
    -- WoW API
    "C_AddOns", "C_Map", "C_Minimap", "C_Timer",
    "CreateFrame", "GameTooltip", "GetNumGroupMembers", "GetPlayerFacing", "GetTime", "GetCursorPosition", "debugstack",
    "InCombatLockdown", "IsInRaid", "Minimap", "UIParent",
    "UnitName", "UnitPosition", "issecretvalue", "UnitClass", "UnitIsUnit", "UnitIsConnected",
    "hooksecurefunc", "IsAltKeyDown", "IsMouseButtonDown", "IsControlKeyDown", "MinimapCluster",
    "UISpecialFrames", "HideUIPanel", "IsIndoors", "IsShiftKeyDown", "CreateVector2D", "UnitExists",
    "GetCVar", "SetCVar", "GetNumTrackingTypes", "GetTrackingInfo", "SetTracking",
    -- Other addons
    "LibStub", "QuestieLoader",
}

files["tests/"] = {
    globals = { "LibStub", "QuestieLoader", "CreateFrame", "C_Timer", "hooksecurefunc", "GameTooltip", "GetCursorPosition", "Questie" },
}
