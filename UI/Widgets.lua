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

-- A pick-one row: the label, then a radio button per choice, side by side. choices: a list of
-- { value, text }, or a function returning one (the row can change with other settings).
-- get() -> the chosen value (none ticked when it matches no choice); set(value).
local LABEL_W, GAP = 110, 14

local function Radio(parent)
    local ok, r = pcall(CreateFrame, "CheckButton", nil, parent, "UIRadioButtonTemplate")
    if not ok or not r then
        r = CreateFrame("CheckButton", nil, parent)
        r:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
        r:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
        local n, c = r:GetNormalTexture(), r:GetCheckedTexture()
        if n then n:SetTexCoord(0, 0.25, 0, 1) end
        if c then c:SetTexCoord(0.25, 0.5, 0, 1) end
    end
    r:SetSize(16, 16)
    if r.text then r.text:SetText("") end
    if r.Text then r.Text:SetText("") end
    r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    r.label:SetPoint("LEFT", r, "RIGHT", 3, 0)
    return r
end

function W.Choice(parent, label, choices, get, set, tip)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(420, 22)
    holder.labelText = label
    holder.label = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    holder.label:SetPoint("LEFT", holder, "LEFT", 4, 0)
    holder.label:SetText(label)
    holder.radios = {}
    Tooltip(holder, tip)
    holder:EnableMouse(tip ~= nil)

    function holder.Refresh()
        local list = type(choices) == "function" and choices() or choices
        local now = get()
        local x = LABEL_W
        for i, c in ipairs(list) do
            local r = holder.radios[i]
            if not r then
                r = Radio(holder)
                r:SetScript("OnClick", function(self)
                    self:SetChecked(true)
                    set(self.value)
                end)
                holder.radios[i] = r
            end
            r.value = c[1]
            r.label:SetText(c[2])
            r:ClearAllPoints()
            r:SetPoint("LEFT", holder, "LEFT", x, 0)
            r:SetChecked(now == c[1])
            r:Show()
            local w = r.label:GetStringWidth()
            x = x + 16 + 3 + (type(w) == "number" and w or 70) + GAP
        end
        for i = #list + 1, #holder.radios do holder.radios[i]:Hide() end
    end
    return holder
end

-- A fold: a clickable "+ text" / "- text" line that shows or hides the settings under it.
-- onToggle(open) is called after a click.
function W.Fold(parent, text, onToggle)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(200, 20)
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.label:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.open = false
    local function Paint() b.label:SetText((b.open and "- " or "+ ") .. text) end
    b:SetScript("OnClick", function()
        b.open = not b.open
        Paint()
        onToggle(b.open)
    end)
    b:SetScript("OnEnter", function() b.label:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function() b.label:SetTextColor(1, 0.82, 0) end)
    Paint()
    function b.Refresh() Paint() end
    return b
end

function W.Button(parent, text, width, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    Tooltip(b, tip)
    return b
end

-- A one-line text box. Enter calls onEnter(text) if given; Escape clears the focus.
function W.Input(parent, width, onEnter, tip)
    local ok, e = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok then e = CreateFrame("EditBox", nil, parent) end
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetMaxLetters(0)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then onEnter(self:GetText()) end
    end)
    Tooltip(e, tip)
    e.Refresh = function() end
    return e
end
