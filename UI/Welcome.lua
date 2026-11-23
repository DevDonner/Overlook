-- The welcome window: what Overlook does and every control, shown once after the first login
-- (ns.db.welcomeSeen, account-wide, kept out of profiles) and again from the Instructions button
-- (Map tab, the game's AddOns page) or /overlook instructions.
local _, ns = ...

local Welcome = {}
ns.Welcome = Welcome

local NAME = "OverlookWelcome"
local WIDTH = 460
local PAD = 18
local KEY = "|cffffd100"   -- the game's gold, for keys and commands
local END = "|r"

-- The text: an intro, then sections of { key, what it does }. Plain data, so the tests check it.
Welcome.INTRO = "Your minimap now zooms out past its old limit, with every Questie icon still on it. "
    .. "Scroll out to find your next objectives, plan your route, then zoom back in or leave it out "
    .. "while you travel."

Welcome.SECTIONS = {
    { "Zoom and look around", {
        { "Mouse wheel", "zoom in and out (Ctrl + wheel: half steps)" },
        { "Drag the map", "look anywhere; the map stays put while you move" },
        { "Middle-click, double-click or Recenter", "back to you" },
        { "Mount up", "zooms out for the ride; dismounting zooms back in" },
    } },
    { "Move and resize", {
        { "Alt + drag", "move the map" },
        { "Corner grip", "drag to resize (lock it in Settings, Map tab)" },
        { "/overlook reset", "brings a lost map back on screen" },
    } },
    { "On the map", {
        { "Hover an icon", "Questie's tooltip; click it like on the world map" },
        { "Hover a dungeon icon", "its name and level range" },
        { "Right-click", "ping" },
        { "Alt + wheel in a cave", "peel off levels one at a time" },
        { "Chevron, bottom left", "other addons' minimap buttons" },
    } },
    { "Settings", {
        { "/overlook or /ol", "open the settings (also the minimap button or the addon compartment)" },
        { "Instructions", "this window again, on the settings' Map tab" },
    } },
}

local frame

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", NAME, UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 } })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end
    frame = f
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    table.insert(UISpecialFrames, NAME) -- Escape closes it

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -6)
    title:SetText("Overlook")

    local inner = WIDTH - PAD * 2
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -36)
    logo:SetTexture(ns.LOGO)

    local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -4)
    head:SetText("Welcome to Overlook")

    local intro = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    intro:SetWidth(inner - 68)
    intro:SetJustifyH("LEFT")
    intro:SetText(Welcome.INTRO)

    local y = -36 - math.max(56, 10 + head:GetStringHeight() + intro:GetStringHeight()) - 14
    for _, section in ipairs(Welcome.SECTIONS) do
        local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        h:SetText(section[1])
        y = y - h:GetStringHeight() - 4
        for _, line in ipairs(section[2]) do
            local t = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            t:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 8, y)
            t:SetWidth(inner - 8)
            t:SetJustifyH("LEFT")
            t:SetText(KEY .. line[1] .. END .. "  " .. line[2])
            y = y - t:GetStringHeight() - 3
        end
        y = y - 8
    end

    local ok2, button = pcall(CreateFrame, "Button", nil, f, "UIPanelButtonTemplate")
    if ok2 and button then
        button:SetSize(120, 24)
        button:SetPoint("TOP", f, "TOP", 0, y - 4)
        button:SetText("Got it")
        button:SetScript("OnClick", function() f:Hide() end)
        y = y - 32
    end
    f:SetSize(WIDTH, -y + PAD)
end

function Welcome.Show()
    if not frame then Build() end
    frame:Show()
    frame:Raise()
    if ns.db then ns.db.welcomeSeen = true end
end

-- Once per account: after the first login with Overlook, a moment after the UI has settled.
function Welcome.MaybeShow()
    if not ns.db or ns.db.welcomeSeen then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
            if not ns.db.welcomeSeen then Welcome.Show() end
        end)
    else
        Welcome.Show()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function() Welcome.MaybeShow() end)

ns.RegisterCommand("instructions", "show the welcome window with every control again", function() Welcome.Show() end)
