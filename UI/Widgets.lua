-- Small self-made controls for the settings window. Built from plain frames and long-standing
-- textures rather than Blizzard's newer settings templates, whose names and signatures have moved
-- between client versions. Each control has :Refresh() to re-read its value.
local _, ns = ...

local W = {}
ns.Widgets = W

function W.Header(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

function W.Note(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Tooltip(frame, text)
    if not text then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A checkbox with a label to its right. get() -> boolean; set(boolean).
function W.Check(parent, label, get, set, tip)
    local ok, c = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
    if not ok then
        c = CreateFrame("CheckButton", nil, parent)
        c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    end
    c:SetSize(24, 24)
    if c.Text then c.Text:SetText("") end
    c.label = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(label or "")
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    Tooltip(c, tip)
    function c.Refresh() c:SetChecked(get() and true or false) end
    return c
end

-- A horizontal slider with its label above and its value to the right.
-- fmt(value) -> text. get() -> number; set(number), called while dragging.
function W.Slider(parent, label, minV, maxV, step, width, fmt, get, set, tip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width + 60, label and 34 or 18)

    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 1)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:EnableMouseWheel(false)

    if label then
        holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        holder.label:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.label:SetText(label)
    end
    holder.value = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    holder.value:SetPoint("LEFT", s, "RIGHT", 8, 0)

    local function Snap(v)
        return math.floor((v - minV) / step + 0.5) * step + minV
    end
    s:SetScript("OnValueChanged", function(_, v, userInput)
        v = Snap(v)
        holder.value:SetText(fmt(v))
        if userInput then set(v) end
    end)
    Tooltip(s, tip)
    function holder.Refresh()
        local v = get()
        s:SetValue(v)
        holder.value:SetText(fmt(v))
    end
    holder.slider = s
    return holder
end

function W.Button(parent, text, width, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    Tooltip(b, tip)
    return b
end
