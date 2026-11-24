-- TwizForever: one menu for every Twiz addon. /twiz or the minimap button.
local ADDON, NS = ...
local db
local frame, list, pane
local selected

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8fe08fTwizForever|r: " .. tostring(msg)) end

------------------------------------------------------------------------
-- addon state (works with both the C_AddOns and the old global API)
------------------------------------------------------------------------
local A = C_AddOns or {}
local function Call(f, ...) if f then local ok, a, b, c = pcall(f, ...); if ok then return a, b, c end end end
local function Exists(name)
    local n = Call(A.GetNumAddOns or GetNumAddOns) or 0
    for i = 1, n do
        local an = Call(A.GetAddOnInfo or GetAddOnInfo, i)
        if an == name then return true end
    end
    return false
end
local function Loaded(name) return Call(A.IsAddOnLoaded or IsAddOnLoaded, name) and true or false end
local function Meta(name, key) return Call(A.GetAddOnMetadata or GetAddOnMetadata, name, key) end
local function Me() return UnitName("player") end
local function Enabled(name)
    local f = A.GetAddOnEnableState or GetAddOnEnableState
    if not f then return Loaded(name) end
    local st = Call(f, name, Me())                       -- newer: (addon, character)
    if type(st) ~= "number" then st = Call(f, Me(), name) end -- older: (character, addon)
    return (tonumber(st) or 0) > 0
end
local function SetEnabled(name, on)
    if on then Call(A.EnableAddOn or EnableAddOn, name, Me()) else Call(A.DisableAddOn or DisableAddOn, name, Me()) end
    db.pending = db.pending or {}
    db.pending[name] = (on ~= Loaded(name)) or nil
end
local function PendingReload()
    for _, v in pairs(db.pending or {}) do if v then return true end end
    return false
end

-- run one of an addon's own slash commands
local function Run(info, arg)
    local f = SlashCmdList and SlashCmdList[info.slash]
    if not f then Print(info.name .. " isn't loaded."); return end
    local ok, err = pcall(f, arg or "")
    if not ok then Print(info.cmd .. " " .. (arg or "") .. ": " .. tostring(err)) end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, function() if NS.Refresh then NS.Refresh() end end) end
end
NS.Run = Run

------------------------------------------------------------------------
-- small widgets
------------------------------------------------------------------------
local function Backdrop(f, r, g, b, a, br, bgc, bb, ba)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(r, g, b, a); f:SetBackdropBorderColor(br or 0.25, bgc or 0.27, bb or 0.32, ba or 1)
end
local function Text(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if fs.SetFont then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "") end
    fs:SetTextColor(r or 0.92, g or 0.92, b or 0.92)
    fs:SetJustifyH("LEFT")
    return fs
end
local function Button(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 110, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end
local function Check(parent, label, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    c.label = Text(c, 12)
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(label)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------
local W, H, LISTW = 600, 440, 170
local rows = {}
local settingChecks, actionButtons = {}, {}

local function Select(i)
    selected = i
    db.selected = i
    NS.Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "TwizForeverFrame", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton"); frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(); db.pos = { p, rp, x, y }
    end)
    if db.pos then frame:ClearAllPoints(); frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4]) end
    Backdrop(frame, 0.07, 0.08, 0.10, 0.96)
    frame:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "TwizForeverFrame") end -- Esc closes it

    local title = Text(frame, 15, 0.56, 0.88, 0.56)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("TwizForever")
    local sub = Text(frame, 11, 0.6, 0.62, 0.66)
    sub:SetPoint("LEFT", title, "RIGHT", 8, -1)
    sub:SetText("all your Twiz addons in one place")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- left: the addon list
    list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 10, -36); list:SetPoint("BOTTOMLEFT", 10, 40); list:SetWidth(LISTW)
    Backdrop(list, 0.10, 0.11, 0.14, 1)
    for i, info in ipairs(NS.ADDONS) do
        local r = CreateFrame("Button", nil, list, "BackdropTemplate")
        r:SetSize(LISTW - 8, 38)
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 40)
        Backdrop(r, 0.13, 0.14, 0.18, 1, 0.13, 0.14, 0.18, 1)
        r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(28, 28); r.icon:SetPoint("LEFT", 5, 0)
        r.icon:SetTexture(info.icon)
        r.name = Text(r, 12); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1); r.name:SetText(info.name)
        r.state = Text(r, 10, 0.6, 0.62, 0.66); r.state:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 1)
        r:SetScript("OnClick", function() Select(i) end)
        rows[i] = r
    end

    -- right: details for the selected addon
    pane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0); pane:SetPoint("BOTTOMRIGHT", -10, 40)
    Backdrop(pane, 0.10, 0.11, 0.14, 1)
    pane.icon = pane:CreateTexture(nil, "ARTWORK"); pane.icon:SetSize(36, 36); pane.icon:SetPoint("TOPLEFT", 10, -10)
    pane.name = Text(pane, 16); pane.name:SetPoint("TOPLEFT", pane.icon, "TOPRIGHT", 8, -2)
    pane.state = Text(pane, 11, 0.6, 0.62, 0.66); pane.state:SetPoint("BOTTOMLEFT", pane.icon, "BOTTOMRIGHT", 8, 2)
    pane.blurb = Text(pane, 11, 0.8, 0.8, 0.8)
    pane.blurb:SetPoint("TOPLEFT", pane.icon, "BOTTOMLEFT", 0, -8); pane.blurb:SetPoint("RIGHT", -10, 0)
    if pane.blurb.SetWordWrap then pane.blurb:SetWordWrap(true) end
    pane.enable = Check(pane, "Addon on (this character)", function(on)
        local info = NS.ADDONS[selected]; if not info then return end
        SetEnabled(info.name, on)
        NS.Refresh()
    end)
    pane.enable:SetPoint("TOPLEFT", pane.blurb, "BOTTOMLEFT", -4, -8)
    pane.settingsHead = Text(pane, 12, 0.56, 0.88, 0.56); pane.settingsHead:SetText("Settings")
    pane.actionsHead = Text(pane, 12, 0.56, 0.88, 0.56); pane.actionsHead:SetText("Actions")
    pane.note = Text(pane, 11, 1, 0.82, 0.3)

    -- bottom bar
    frame.reload = Button(frame, "Reload UI", 100, function() if ReloadUI then ReloadUI() end end)
    frame.reload:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.foot = Text(frame, 11, 1, 0.82, 0.3)
    frame.foot:SetPoint("BOTTOMLEFT", 12, 15); frame.foot:SetPoint("RIGHT", frame.reload, "LEFT", -8, 0)
end

local function StateText(info)
    if not Exists(info.name) then return "|cff808080not installed|r", "missing" end
    local on, loaded = Enabled(info.name), Loaded(info.name)
    local v = Meta(info.name, "Version")
    if loaded and on then return "|cff8fe08fon|r" .. (v and ("  v" .. v) or ""), "on" end
    if loaded and not on then return "|cffffd050off after reload|r", "pending" end
    if on and not loaded then return "|cffffd050on after reload|r", "pending" end
    return "|cffff6060off|r", "off"
end

function NS.Refresh()
    if not frame or not frame:IsShown() then return end
    for i, info in ipairs(NS.ADDONS) do
        local r = rows[i]
        local st = StateText(info)
        -- errors caught this session (TwizErrors)
        local nb = TwizErrors and TwizErrors.BugCount and TwizErrors.BugCount(info.name) or 0
        if nb > 0 then st = st .. ("  |cffff6060%d error%s|r"):format(nb, nb == 1 and "" or "s") end
        r.state:SetText(st)
        local sel = i == selected
        if r.SetBackdropColor then r:SetBackdropColor(sel and 0.20 or 0.13, sel and 0.26 or 0.14, sel and 0.20 or 0.18, 1) end
        if r.icon.SetDesaturated then r.icon:SetDesaturated(not Loaded(info.name)) end
    end
    local info = NS.ADDONS[selected]
    if not info then return end
    local stateText, state = StateText(info)
    pane.icon:SetTexture(info.icon)
    pane.name:SetText(info.name)
    pane.state:SetText(stateText .. "   |cff9aa0a6" .. info.cmd .. "|r")
    pane.blurb:SetText(info.blurb)
    pane.enable:SetShown(state ~= "missing")
    pane.enable:SetChecked(Enabled(info.name))

    for _, c in ipairs(settingChecks) do c:Hide() end
    for _, b in ipairs(actionButtons) do b:Hide() end
    local loaded = Loaded(info.name)
    local d = loaded and info.db and info.db()
    local anchor = state == "missing" and pane.blurb or pane.enable
    pane.settingsHead:ClearAllPoints(); pane.settingsHead:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", state == "missing" and 0 or 4, -12)
    pane.settingsHead:SetShown(#(info.settings or {}) > 0)
    local colW = 190
    for k, s in ipairs(info.settings or {}) do
        local c = settingChecks[k]
        if not c then
            c = Check(pane, "", function(on)
                local cur = NS.ADDONS[selected]; local def = cur and cur.settings[k]
                if not def then return end
                Run(cur, def[3](on))
            end)
            settingChecks[k] = c
        end
        c.label:SetText(s[1])
        c:ClearAllPoints()
        local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
        c:SetPoint("TOPLEFT", pane.settingsHead, "BOTTOMLEFT", -4 + col * colW, -4 - row * 24)
        local ok, v = false, nil
        if d then ok, v = pcall(s[2], d) end
        c:SetChecked(ok and v and true or false)
        if c.SetEnabled then c:SetEnabled(d ~= nil) end
        c.label:SetTextColor(d and 0.92 or 0.5, d and 0.92 or 0.5, d and 0.92 or 0.5)
        c:Show()
    end
    local nRows = math.ceil(#(info.settings or {}) / 2)
    pane.actionsHead:ClearAllPoints()
    pane.actionsHead:SetPoint("TOPLEFT", pane.settingsHead, "BOTTOMLEFT", 0, -10 - nRows * 24)
    pane.actionsHead:SetShown(loaded and #(info.actions or {}) > 0)
    for k, a in ipairs(info.actions or {}) do
        local b = actionButtons[k]
        if not b then
            b = Button(pane, "", 124, function()
                local cur = NS.ADDONS[selected]; local act = cur and cur.actions[k]
                if act then Run(cur, act[2]) end
            end)
            actionButtons[k] = b
        end
        b:SetText(a[1])
        b:ClearAllPoints()
        local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
        b:SetPoint("TOPLEFT", pane.actionsHead, "BOTTOMLEFT", col * 128, -6 - row * 26)
        b:SetShown(loaded)
    end
    pane.note:ClearAllPoints()
    pane.note:SetPoint("BOTTOMLEFT", 10, 10); pane.note:SetPoint("RIGHT", -10, 0)
    if state == "missing" then
        pane.note:SetText("Not in your AddOns folder.")
    elseif not loaded then
        pane.note:SetText("Not running right now - turn it on and Reload UI to use its settings.")
    else
        pane.note:SetText("Settings change through " .. info.cmd .. ", so the addon reacts right away. Type " .. info.cmd .. " help for everything else.")
    end
    if PendingReload() then
        frame.foot:SetText("Addons turned on or off take effect after Reload UI.")
        frame.reload:Show()
    else
        frame.foot:SetText("Click an addon on the left. /twiz opens this menu.")
        frame.reload:Show()
    end
end

function NS.Toggle()
    if not frame then Build() end
    if frame:IsShown() then frame:Hide() else frame:Show(); NS.Refresh() end
end
TwizForever_Toggle = NS.Toggle

------------------------------------------------------------------------
-- minimap button
------------------------------------------------------------------------
local mini
local function PlaceMini()
    if not mini then return end
    local a = math.rad(db.miniAngle or 225)
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end
local function BuildMini()
    if mini or not Minimap then return end
    mini = CreateFrame("Button", "TwizForeverMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM"); mini:SetFrameLevel(8)
    local icon = mini:CreateTexture(nil, "BACKGROUND"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    local ring = mini:CreateTexture(nil, "OVERLAY"); ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mini:RegisterForClicks("AnyUp")
    mini:RegisterForDrag("LeftButton")
    mini:SetScript("OnClick", function() NS.Toggle() end)
    mini:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.miniAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceMini()
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mini:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TwizForever")
        GameTooltip:AddLine("Click: all your Twiz addons. Drag to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    PlaceMini()
end
local function UpdateMini()
    if db.minimap == false then if mini then mini:Hide() end
    else BuildMini(); if mini then mini:Show() end end
end

------------------------------------------------------------------------
SLASH_TWIZFOREVER1 = "/twiz"
SLASH_TWIZFOREVER2 = "/twizforever"
SlashCmdList["TWIZFOREVER"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "minimap" then
        db.minimap = db.minimap == false
        UpdateMini()
        Print("minimap button " .. (db.minimap and "shown" or "hidden (/twiz minimap brings it back)"))
    elseif cmd == "help" then
        Print("/twiz - open the menu   /twiz minimap - show/hide the minimap button")
    else
        NS.Toggle()
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        TwizForeverDB = TwizForeverDB or {}
        db = TwizForeverDB
        if db.minimap == nil then db.minimap = true end
        db.pending = {} -- a reload has happened
        selected = db.selected or 1
    elseif event == "PLAYER_LOGIN" then
        UpdateMini()
    end
end)
NS.Exists, NS.Loaded, NS.Enabled, NS.Select = Exists, Loaded, Enabled, Select
TwizForever = NS
