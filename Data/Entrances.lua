-- Vendored verbatim from OpenMap v0.8.13 (Data/Forever/Places.lua, its instances table), MIT licence:
-- see LICENSES/OpenMap-LICENSE.txt. Sets ns.MapEntrances. Replace with a newer OpenMap copy rather
-- than editing. Generated there by tools/map-data/build.py from the game's tables (build 1.60.1.70245).
--   instances[i] = { continent, north, west (world yards), { { mapID, name, raid, minLevel, maxLevel }, ... } }
--   or { nil, x, y, { ... }, map = uiMapID }: a spot on that zone's map (0..1)

local _, ns = ...

ns.MapEntrances = {
    instances = {
        { 0, -231.0, 1571.6, { { 33, "Shadowfang Keep", false, 20, 30 } } },
        { 0, -8762.4, 848.0, { { 34, "Stormwind Stockade", false, 24, 32 } } },
        { 0, -11207.8, 1681.2, { { 36, "Deadmines", false, 17, 26 } } },
        { 1, -751.1, -2209.2, { { 43, "Wailing Caverns", false, 15, 24 } } },
        { 1, -4459.4, -1660.2, { { 47, "Razorfen Kraul", false, 29, 38 } } },
        { 1, 4249.1, 748.4, { { 48, "Blackfathom Deeps", false, 24, 32 } } },
        { 0, -6060.2, -2955.0, { { 70, "Uldaman", false, 41, 51 } } },
        { 0, -5162.7, 931.6, { { 90, "Gnomeregan", false, 29, 38 } } },
        { 0, -10170.1, -3996.0, { { 109, "Sunken Temple", false, 50, 60 } } },
        { 1, -4662.9, -2535.9, { { 129, "Razorfen Downs", false, 37, 46 } } },
        { 0, 2892.2, -811.3, { { 189, "Scarlet Monastery - Graveyard", false, 30, 38 }, { 189, "Scarlet Monastery - Library", false, 33, 41 }, { 189, "Scarlet Monastery - Armory", false, 36, 44 }, { 189, "Scarlet Monastery - Cathedral", false, 38, 46 } } },
        { 1, -6790.6, -2891.3, { { 209, "Zul'Farrak", false, 44, 54 } } },
        { 0, -7522.5, -1233.0, { { 229, "Lower Blackrock Spire", false, 55, 60 }, { 229, "Upper Blackrock Spire", false, 59, 60 }, { 409, "Molten Core", true, 60, 60 }, { 469, "Blackwing Lair", true, 60, 60 } } },
        { 0, -7178.1, -928.6, { { 230, "Blackrock Depths", false, 52, 60 } } },
        { 1, -4753.3, -3752.4, { { 249, "Onyxia's Lair", true, 60, 60 } } },
        { 0, 1274.8, -2552.6, { { 289, "Scholomance", false, 58, 60 } } },
        { 0, -11916.1, -1224.6, { { 309, "Zul'Gurub", true, 60, 60 } } },
        { 0, 3392.3, -3378.5, { { 329, "Stratholme", false, 58, 60 } } },
        { 1, -1432.7, 2925.0, { { 349, "Maraudon", false, 46, 55 } } },
        { 1, 1816.8, -4423.4, { { 389, "Ragefire Chasm", false, 13, 18 } } },
        { 1, -3908.0, 1130.0, { { 429, "Dire Maul - East", false, 54, 60 }, { 429, "Dire Maul - West", false, 56, 60 }, { 429, "Dire Maul - North", false, 56, 60 } } },
        { 1, -8114.5, 1526.4, { { 509, "Ruins of Ahn'Qiraj", true, 60, 60 }, { 531, "Ahn'Qiraj Temple", true, 60, 60 } } },
        { nil, 0.085, 0.593, { { 2959, "City of Dalaran", false, 28, 35 } }, map = 1416 },
        { nil, 0.213, 0.278, { { 2970, "The Drowned City", false, 35, 42 } }, map = 1434 },
        { nil, 0.386, 0.332, { { 2974, "Blackmaw Hold", false, 55, 60 } }, map = 1447 },
        { nil, 0.753, 0.141, { { 2994, "Alcaz Prison", false, 48, 55 } }, map = 1445 },
        { nil, 0.478, 0.562, { { 2998, "Excavation Site: Wetlands", false, 26, 33 } }, map = 1437 },
        { nil, 0.725, 0.114, { { 2999, "Ruins of Lordaeron", false, 15, 22 } }, map = 1458 },
        { nil, 0.481, 0.061, { { 3001, "Shaper's Terrace", false, 58, 60 } }, map = 1449 },
        { nil, 0.375, 0.373, { { 3039, "Krol'dok Stronghold", false, 40, 47 } }, map = 2548 },
        { nil, 0.277, 0.479, { { 3065, "The Hall of Thanes", false, 13, 20 } }, map = 1455 },
    },
}
