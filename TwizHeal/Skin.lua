-- Twiz clean skin (same file in TwizQuest, TwizAH, TwizCraft): the shared look of TwizQuest, TwizAH and TwizCraft.
-- Flat dark panels, one gold primary button per window, dark secondary
-- buttons, quiet icon buttons, small caps section labels, slim bars and a
-- simple "more" menu. The same file ships in each addon (NS.Skin).
local ADDON, NS = ...

local Skin = {}
NS.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
local C = {
    bg       = { 0.082, 0.094, 0.114, 0.97 },
    border   = { 0.173, 0.192, 0.227, 1 },
    card     = { 0.110, 0.125, 0.153, 1 },
    cardLine = { 0.204, 0.227, 0.267, 1 },
    line     = { 0.137, 0.153, 0.180, 1 },
    hover    = { 0.180, 0.204, 0.251, 1 },
    text     = { 0.910, 0.894, 0.855 },
    muted    = { 0.604, 0.631, 0.671 },
    faint    = { 0.486, 0.514, 0.553 },
    gold     = { 0.941, 0.769, 0.361 },
    goldHi   = { 1.000, 0.835, 0.455 },
    ink      = { 0.102, 0.078, 0.031 },
    green    = { 0.561, 0.878, 0.561 },
    blue     = { 0.486, 0.769, 1.000 },
    orange   = { 1.000, 0.690, 0.400 },
    track    = { 0.165, 0.184, 0.220, 1 },
}
Skin.C = C
Skin.HEX = {
    text = "e8e4da", muted = "9aa1ab", faint = "7c838d", gold = "f0c45c",
    green = "8fe08f", blue = "7cc4ff", orange = "ffb066", red = "ff7070",
}
function Skin.Color(name, s) return ("|cff%s%s|r"):format(Skin.HEX[name] or "ffffff", tostring(s)) end

local function Backdrop(f, bg, edge)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(unpack(bg))
    if edge then f:SetBackdropBorderColor(unpack(edge)) else f:SetBackdropBorderColor(0, 0, 0, 0) end
end

-- the window itself (frame must be made with "BackdropTemplate")
function Skin.Panel(f) Backdrop(f, C.bg, C.border) end
-- a card inside a window
function Skin.Card(f) Backdrop(f, C.card, C.cardLine) end

-- a 1px divider line under (or over) a region
function Skin.Divider(parent, anchor, where)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(unpack(C.line))
    t:SetHeight(1)
    if where == "top" then
        t:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    else
        t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0); t:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    end
    return t
end

-- text helpers
function Skin.Text(parent, kind, layer)
    local font = (kind == "title" and "GameFontNormal") or (kind == "big" and "GameFontHighlightLarge")
        or (kind == "body" and "GameFontHighlight") or "GameFontHighlightSmall"
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", font)
    if kind == "title" then fs:SetTextColor(unpack(C.gold))
    elseif kind == "muted" then fs:SetTextColor(unpack(C.muted))
    elseif kind == "faint" then fs:SetTextColor(unpack(C.faint))
    else fs:SetTextColor(unpack(C.text)) end
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    return fs
end
-- small caps section label: "UP NEXT · 11 MIN"
function Skin.Label(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(unpack(C.muted))
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    fs.SetLabel = function(self, s) self:SetText(tostring(s):upper()) end
    return fs
end

------------------------------------------------------------------------
-- Buttons. kind: "primary" (gold), "secondary" (dark, default), "ghost"
-- (no box, for icon buttons), "seg" (one half of a segmented toggle).
------------------------------------------------------------------------
local function Paint(b)
    local k, on, hover = b.kind, b.selected, b.hovered
    local enabled = b:IsEnabled()
    if k == "primary" then
        Backdrop(b, (hover and enabled) and { C.goldHi[1], C.goldHi[2], C.goldHi[3], 1 } or { C.gold[1], C.gold[2], C.gold[3], 1 })
        b.label:SetTextColor(unpack(C.ink))
    elseif k == "ghost" then
        Backdrop(b, hover and { 1, 1, 1, 0.07 } or { 0, 0, 0, 0 })
        b.label:SetTextColor(unpack(hover and C.text or C.muted))
    elseif k == "seg" then
        Backdrop(b, on and C.hover or { 0, 0, 0, 0 })
        b.label:SetTextColor(unpack(on and C.text or C.muted))
    else
        Backdrop(b, hover and C.hover or C.card, C.cardLine)
        b.label:SetTextColor(unpack(C.text))
    end
    b:SetAlpha(enabled and 1 or 0.45)
end
Skin.Paint = Paint

function Skin.Button(parent, text, kind, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b.kind = kind or "secondary"
    b:SetSize(w or 80, h or 24)
    b.label = b:CreateFontString(nil, "OVERLAY", b.kind == "primary" and "GameFontNormal" or "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    if b.SetFontString then b:SetFontString(b.label) end
    b:SetText(text or "")
    b.label:SetText(text or "")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end
    b:HookScript("OnEnter", function(self) self.hovered = true; Paint(self) end)
    b:HookScript("OnLeave", function(self) self.hovered = false; Paint(self) end)
    local setEnabled = b.SetEnabled
    b.SetEnabled = function(self, v) setEnabled(self, v); Paint(self) end
    local setText = b.SetText
    b.SetText = function(self, t) setText(self, t); self.label:SetText(t or "") end
    Paint(b)
    return b
end

-- a tooltip on any frame: title, then a line (string or function)
function Skin.Tip(f, title, text)
    f:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, C.gold[1], C.gold[2], C.gold[3])
        local t = type(text) == "function" and text() or text
        if t and t ~= "" then GameTooltip:AddLine(t, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    f:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Segmented toggle: Skin.Segmented(parent, { {key, text}, ... }, onPick) -> frame with :Select(key)
function Skin.Segmented(parent, items, onPick, h)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Backdrop(box, C.card, C.cardLine)
    box.buttons = {}
    local x = 2
    for _, it in ipairs(items) do
        local b = Skin.Button(box, it[2], "seg", it.w or (14 + #it[2] * 6), (h or 26) - 4)
        b:SetPoint("LEFT", x, 0)
        b.key = it[1]
        b:SetScript("OnClick", function(self) if onPick then onPick(self.key) end end)
        box.buttons[#box.buttons + 1] = b
        x = x + b:GetWidth() + 2
    end
    box:SetSize(x, h or 26)
    function box:Select(key)
        for _, b in ipairs(self.buttons) do b.selected = (b.key == key); Paint(b) end
    end
    return box
end

------------------------------------------------------------------------
-- Slim progress bar with an optional second (behind) value, e.g. rested XP
------------------------------------------------------------------------
function Skin.Bar(parent, h, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(h or 6)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(r or C.gold[1], g or C.gold[2], b or C.gold[3])
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(unpack(C.track))
    bar.behind = CreateFrame("StatusBar", nil, bar)
    bar.behind:SetAllPoints()
    bar.behind:SetStatusBarTexture(WHITE)
    bar.behind:SetStatusBarColor(0.24, 0.36, 0.62, 0.9)
    bar.behind:SetMinMaxValues(0, 1); bar.behind:SetValue(0)
    bar.behind:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    return bar
end

------------------------------------------------------------------------
-- "More" menu: Skin.Menu(anchorButton, function() return { {text, onClick, tip, disabled}, ... } end)
-- Click the anchor to open it; picking an item (or clicking the anchor again) closes it.
------------------------------------------------------------------------
local openMenu
function Skin.Menu(anchor, itemsFn)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    Backdrop(menu, C.card, C.cardLine)
    menu.buttons = {}
    menu:Hide()
    local function Close() menu:Hide(); if openMenu == menu then openMenu = nil end end
    function menu:Open()
        if openMenu and openMenu ~= menu then openMenu:Hide() end
        local items = itemsFn() or {}
        local w = 160
        for i, it in ipairs(items) do
            local b = menu.buttons[i]
            if not b then
                b = Skin.Button(menu, "", "ghost", 150, 24)
                b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 10, 0)
                menu.buttons[i] = b
            end
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
            b:SetText(it[1])
            b:SetEnabled(not it.disabled)
            b:SetScript("OnClick", function() Close(); if it[2] then it[2]() end end)
            b.tip = it[3]
            b:Show()
            w = math.max(w, 30 + (#tostring(it[1]) * 7))
        end
        for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
        for i = 1, #items do menu.buttons[i]:SetWidth(w - 8) end
        menu:SetSize(w, 8 + #items * 24)
        menu:ClearAllPoints()
        if anchor.menuBelow then
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            menu:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
        end
        menu:Show()
        openMenu = menu
        menu.openedAt = GetTime()
    end
    -- close when the mouse wanders off for a moment
    menu:SetScript("OnUpdate", function(self)
        if MouseIsOver and not MouseIsOver(self) and not MouseIsOver(anchor) and GetTime() - (self.openedAt or 0) > 1.5 then
            Close()
        end
    end)
    anchor:SetScript("OnClick", function()
        if menu:IsShown() then Close() else menu:Open() end
    end)
    anchor.menu = menu
    return menu
end

-- the little "⋯" button that opens a menu
function Skin.MoreButton(parent, itemsFn, size)
    local b = Skin.Button(parent, "...", "secondary", size or 30, size or 26)
    Skin.Menu(b, itemsFn)
    return b
end

-- an icon-only header button (text glyph), e.g. close "x"
function Skin.IconButton(parent, glyph, tip, onClick)
    local b = Skin.Button(parent, glyph, "ghost", 24, 24, onClick)
    if tip then Skin.Tip(b, tip) end
    return b
end

-- a small colored tag ("Post", "Vendor", "learn at trainer")
function Skin.Tag(parent)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetHeight(16)
    t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t.text:SetPoint("CENTER")
    function t:Set(s, color)
        local c = C[color or "muted"] or C.muted
        Backdrop(self, { c[1], c[2], c[3], 0.10 }, { c[1], c[2], c[3], 0.55 })
        self.text:SetText(s)
        self.text:SetTextColor(c[1], c[2], c[3])
        self:SetWidth(math.max(40, (self.text:GetStringWidth() or 30) + 16))
    end
    return t
end
