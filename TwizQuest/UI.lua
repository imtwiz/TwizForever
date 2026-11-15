-- TwizQuest window: the ordered steps, XP/hour, and click-to-waypoint.
local ADDON, NS = ...

local ROWS, DEFAULT_ROWS, ROW_H = 40, 16, 20
local PAD = 12                 -- space between the window edge and its contents
local LIST_Y = 58              -- where the step list starts with nothing above it
local DEFAULT_W = 520
local plan
local frame, rows = nil, {}
local wayUID

local KIND_TEXT = {
    pickup = "|cffffd100Pick up|r",
    turnin = "|cff00ff66Turn in|r",
}

local function StepText(s)
    local q = s.q
    if s.kind == "service" then
        return ("|cffff9933%s|r %s |cff999999- %s|r"):format(s.repair and "Sell & repair:" or "Sell:",
            s.who or "vendor", s.why or "")
    end
    if s.kind == "bank" then
        return ("  |cff40c0ffBank:|r %d %s |cff999999- %s|r"):format(s.need or 0, s.name or "items", q.name)
    elseif s.kind == "useitem" then
        return ("%s %s |cff999999- use %s|r"):format(KIND_TEXT.pickup, q.name, s.name or "item")
    elseif s.kind == "bankstart" then
        return ("%s %s |cff999999- bank, use %s|r"):format(KIND_TEXT.pickup, q.name, s.name or "item")
    end
    if s.role == 1 then
        return ("%s %s%s"):format(KIND_TEXT.pickup, q.name, s.who and (" |cff999999- " .. s.who .. "|r") or "")
    elseif s.role == 3 then
        return ("%s %s%s"):format(KIND_TEXT.turnin, q.name, s.who and (" |cff999999- " .. s.who .. "|r") or "")
    end
    local what
    if s.kind == "monster" or s.kind == "killcredit" then
        what = ("Kill %d %s"):format(s.need or 0, s.name or s.text or "targets")
    elseif s.kind == "item" then
        what = ("Get %d %s%s"):format(s.need or 0, s.name or s.text or "items",
            s.dropper and (" (~" .. (s.kills or s.need) .. " " .. s.dropper .. ")") or "")
    elseif s.kind == "loot" or s.kind == "object" then
        what = ("Collect %d %s"):format(s.need or 0, s.name or s.text or "objects")
    elseif s.kind == "buy" then
        what = ("Buy %s from %s"):format(s.name or "item", s.vendor or "vendor")
    else
        what = s.text or "Objective"
    end
    if s.elite then what = what .. " |cffff5555(elite)|r" end
    if s.help then what = what .. (" |cff66ccff(for %s)|r"):format(s.help) end
    return ("  %s |cff999999- %s|r"):format(what, q.name)
end

local function SetWaypoint(s, silent)
    if not s or not s.map then return end
    local title = (s.role == 1 and "Pick up: " or s.role == 3 and "Turn in: " or "") .. s.q.name
    if TomTom and TomTom.AddWaypoint then
        if wayUID and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, wayUID) end
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, s.map, s.mx / 100, s.my / 100,
            { title = title, from = "TwizQuest", persistent = false, crazy = true })
        if ok then wayUID = uid end
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(s.map, s.mx / 100, s.my / 100))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end
    if not silent then NS.Print("waypoint set: " .. title) end
end

-- rows that fit: your chosen height, or the default when you haven't resized
------------------------------------------------------------------------
-- Party line: who's synced, quests to share, who's behind, ready together
------------------------------------------------------------------------
local partyOffset = 0
local function QName(id)
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return t or NS.Q(id, "name") or ("quest " .. id)
end

local function PartyText(st)
    if #st.members == 0 then
        if #st.noAddon > 0 then return ("|cff999999Party: synced 0/%d|r"):format(#st.noAddon) end
        return nil
    end
    local bits = { ("|cff66ccffParty:|r %s"):format(table.concat(st.members, ", ")) }
    if #st.noAddon > 0 then
        bits[#bits + 1] = ("|cff999999Synced: %d/%d|r"):format(#st.members, #st.members + #st.noAddon)
    end
    if #st.missing > 0 then bits[#bits + 1] = ("|cffffd100Share: %d|r"):format(#st.missing) end
    if #st.behind > 0 then bits[#bits + 1] = ("|cffff9933Behind: %d|r"):format(#st.behind) end
    if #st.ready > 0 then bits[#bits + 1] = ("|cff66ff66Ready: %d|r"):format(#st.ready) end
    if #st.theyHave > 0 then bits[#bits + 1] = ("|cff999999Theirs: %d|r"):format(#st.theyHave) end
    if #st.missing + #st.behind + #st.ready + #st.theyHave == 0 then bits[#bits + 1] = "|cff66ff66In sync|r" end
    return table.concat(bits, "   ")
end

local function PartyTooltip(self)
    local st = NS.PartyStatus()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Party sync", 0.4, 0.8, 1)
    for _, m in ipairs(st.members) do
        local p = NS.party[m]
        GameTooltip:AddDoubleLine(m .. (p.level and (" (" .. p.level .. ")") or ""),
            p.step and ("Next: " .. p.step.text) or "", 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if #st.missing > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Share: they lack", 1, 0.82, 0)
        for _, m in ipairs(st.missing) do GameTooltip:AddDoubleLine(QName(m.id), m.who, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.behind > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Behind: they still need", 1, 0.6, 0.2)
        for _, b in ipairs(st.behind) do GameTooltip:AddDoubleLine(QName(b.id), b.who .. " " .. b.left, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.ready > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ready: turn in together", 0.4, 1, 0.4)
        for _, id in ipairs(st.ready) do GameTooltip:AddLine(QName(id), 1, 1, 1) end
    end
    if #st.theyHave > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Theirs: you lack", 0.7, 0.7, 0.7)
        for _, m in ipairs(st.theyHave) do GameTooltip:AddDoubleLine(QName(m.id), m.who, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.noAddon > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Not synced: " .. table.concat(st.noAddon, ", "), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local BAR_H = 17
local function XPRow(row, name, xp, classFile, isMe)
    row.name:SetText((isMe and "|cff66ff66" or "") .. name .. (isMe and "|r" or ""))
    if not xp or not xp.max or xp.max <= 0 then
        row.bar:SetValue(0); row.rest:SetValue(0)
        row.text:SetText("")
        row.right:SetText("|cff999999No data|r")
        return
    end
    row.bar:SetMinMaxValues(0, xp.max); row.bar:SetValue(xp.cur)
    row.rest:SetMinMaxValues(0, xp.max); row.rest:SetValue(math.min(xp.max, xp.cur + (xp.rest or 0)))
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then row.bar:SetStatusBarColor(color.r, color.g, color.b) else row.bar:SetStatusBarColor(0.58, 0.0, 0.55) end
    local left = xp.max - xp.cur
    local eta = (xp.rate or 0) > 0 and ("   " .. NS.FormatTime(left / xp.rate * 3600)) or ""
    row.text:SetText(("%d%%"):format(math.floor(xp.cur / xp.max * 100)))
    row.right:SetText(("L%d   %s left%s%s"):format(xp.level or 0, NS.FormatNum(left),
        (xp.rest or 0) > 0 and ("   |cff6699ff+" .. NS.FormatNum(xp.rest) .. " rested|r") or "", "|cff999999" .. eta .. "|r"))
end

local function MyXP()
    local plan = NS._plan and NS._plan()
    return { level = UnitLevel("player"), cur = UnitXP("player") or 0, max = UnitXPMax("player") or 0,
             rest = (GetXPExhaustion and GetXPExhaustion()) or 0, rate = plan and plan.rate or 0 }
end

local function UnitClassFile(name)
    local unit = NS.PartyUnit and NS.PartyUnit(name)
    if unit then return select(2, UnitClass(unit)) end
end

local function RowsFit()
    if NS.db.sized then return math.max(1, math.min(ROWS, math.floor((frame:GetHeight() - LIST_Y - PAD - partyOffset) / ROW_H))) end
    return DEFAULT_ROWS
end

-- widths follow the window
local function Layout()
    if not frame then return end
    local w = frame:GetWidth()
    for _, row in ipairs(rows) do
        row:SetWidth(w - 2 * PAD)
        row.text:SetWidth(math.max(80, w - 2 * PAD - 28 - 110))
    end
end

local function Refresh()
    if not frame then return end
    if frame.dropAll then frame.dropAll:SetShown(not (NS.KeepAllQuests and NS.KeepAllQuests())) end
    if frame.groupBtn then
        local can = NS.groupMode or (IsInGroup() and NS.SyncedCount and NS.SyncedCount() > 0)
        frame.groupBtn:SetShown(can and true or false)
        frame.groupBtn:SetText(NS.groupMode and "Solo" or "Group")
    end
    local ptext = NS.db.party and NS.PartyStatus and PartyText(NS.PartyStatus()) or nil
    local nbars = 0
    -- flags: a second summary line, only when there is something to flag
    local flags = {}
    if plan then
        if (plan.skipped or 0) > 0 then flags[#flags + 1] = ("|cffff8040Skipped: %d|r"):format(plan.skipped) end
        if (plan.rested or 0) > 0 then flags[#flags + 1] = ("|cff6699ffRested: %s|r"):format(NS.FormatNum(plan.rested)) end
        if #(plan.drop or {}) > 0 then flags[#flags + 1] = ("|cffffd100Drop: %d|r"):format(#plan.drop) end
    end
    local flagsOffset = #flags > 0 and 16 or 0
    frame.flags:SetText(table.concat(flags, "   "))
    frame.flags:SetShown(#flags > 0)
    frame.partyLine:ClearAllPoints()
    frame.partyLine:SetPoint("TOPLEFT", PAD, -(LIST_Y - 2 + flagsOffset))
    frame.partyLine:SetPoint("RIGHT", -PAD, 0)
    if ptext then
        frame.partyLine.text:SetText(ptext); frame.partyLine:Show()
        local st = NS.PartyStatus()
        frame.share:SetText(("Share (%d)"):format(#st.missing))
        frame.share:SetShown(#st.missing > 0)
        partyOffset = 22
        if NS.db.partyXP and #st.members > 0 then
            nbars = 1
            XPRow(frame.xpRows[1], UnitName("player"), MyXP(), select(2, UnitClass("player")), true)
            for _, m in ipairs(st.members) do
                if nbars < #frame.xpRows then
                    nbars = nbars + 1
                    XPRow(frame.xpRows[nbars], m, NS.party[m].xp, UnitClassFile(m))
                end
            end
        end
        partyOffset = partyOffset + nbars * BAR_H + (nbars > 0 and 6 or 0)
    else
        frame.partyLine:Hide(); partyOffset = 0
    end
    partyOffset = partyOffset + flagsOffset
    for i, r in ipairs(frame.xpRows) do r:SetShown(i <= nbars) end
    frame.listTop:SetPoint("TOPLEFT", PAD, -LIST_Y - partyOffset)
    if not plan then
        frame.summary:SetText(NS.IsPlanning() and "Planning..." or (frame.status or "No plan"))
        for i = 1, ROWS do rows[i]:Hide() end
        if not NS.db.sized then frame:SetHeight(LIST_Y + PAD + partyOffset) end
        return
    end
    local need = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local toLevel = (plan.rate > 0) and (need / plan.rate * 3600) or nil
    local age = GetTime() - (plan.at or GetTime())
    local groupTag = ""
    if plan.group then
        groupTag = ("|cff66ccffGroup%s: %s XP/hr x%d|r   "):format(
            plan.group.from and (" (" .. plan.group.from .. ")") or "",
            NS.FormatNum(plan.group.rate), plan.group.members)
    end
    frame.summary:SetText(("%s|cff66ff66%s XP/hr|r   %s XP / %s%s   %s"):format(groupTag,
        NS.FormatNum(plan.rate), NS.FormatNum(plan.xp), NS.FormatTime(plan.time),
        toLevel and ("   Level: " .. NS.FormatTime(toLevel)) or "",
        NS.IsPlanning() and "|cffffff00Updating|r" or
            ("|cff777777Updated: " .. (age < 5 and "now" or NS.FormatTime(age)) .. "|r")))
    local shown, fit = 0, RowsFit()
    for i = 1, ROWS do
        local s = (i <= fit) and plan.route[i] or nil
        local row = rows[i]
        if s then
            row.step = s
            row.num:SetText(i .. ".")
            row.text:SetText(StepText(s))
            local gain = (s.kxp or 0) + ((s.role == 3) and s.q.xp or 0)
            row.right:SetText(("%s%s"):format(
                gain > 0 and ("+" .. NS.FormatNum(gain) .. " ") or "",
                "|cff999999" .. NS.FormatTime(s.eta) .. "|r"))
            row:Show(); shown = i
        else
            row:Hide()
        end
    end
    if #plan.route == 0 then
        frame.summary:SetText("No quests in range")
    end
    if not NS.db.sized then frame:SetHeight(LIST_Y + PAD + partyOffset + shown * ROW_H) end
end

local function Build()
    frame = CreateFrame("Frame", "TwizQuestFrame", UIParent, "BackdropTemplate")
    frame:SetSize(DEFAULT_W, LIST_Y + PAD)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        NS.db.pos = { p, rp, x, y }
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        frame:SetBackdropColor(0, 0, 0, 0.8)
    end
    if NS.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(NS.db.pos[1], UIParent, NS.db.pos[2], NS.db.pos[3], NS.db.pos[4])
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -12)
    title:SetText("TwizQuest")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() frame:Hide(); NS.db.shown = false end)

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(64, 22); btn:SetPoint("TOPRIGHT", -30, -7)
    btn:SetText("Plan")
    btn:SetScript("OnClick", function() NS.Replan() end)

    local function Tip(b, title, text)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(title, 1, 0.82, 0)
            GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    frame.shareAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.shareAll:SetSize(84, 22); frame.shareAll:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    frame.shareAll:SetText("Share All")
    frame.shareAll:SetScript("OnClick", function() NS.ShareAllCmd() end)
    Tip(frame.shareAll, "Share All", function()
        return IsInGroup() and "Every shareable quest in your log" or "Needs a party"
    end)
    frame.dropAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.dropAll:SetSize(80, 22); frame.dropAll:SetPoint("RIGHT", frame.shareAll, "LEFT", -6, 0)
    frame.dropAll:SetText("Drop All")
    frame.dropAll:SetScript("OnClick", function() NS.DropAllCmd(IsShiftKeyDown()) end)
    Tip(frame.dropAll, "Drop All", "Abandons every quest except dungeon quests (asks first)\nShift-click: dungeon quests too\nLow-value quests only: /tq cleanup")
    frame.groupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.groupBtn:SetSize(84, 22); frame.groupBtn:SetPoint("RIGHT", frame.dropAll, "LEFT", -6, 0)
    frame.groupBtn:SetText("Group")
    frame.groupBtn:SetScript("OnClick", function()
        if NS.groupMode then NS.EndGroupPlan() else NS.StartGroupPlan() end
    end)
    Tip(frame.groupBtn, "Group plan", function()
        if NS.groupMode then
            return (NS.groupPlan and ("Following " .. NS.groupPlan.from .. "'s group plan") or "Your group plan is on")
                .. "\nClick: back to your own route"
        end
        return "Plans the fastest XP for the whole group: quests count the XP of everyone who has them, can be shared them, or can pick them up\nSends the route to your party (click Share to offer quests they're missing)\nEveryone needs TwizQuest"
    end)
    frame.groupBtn:Hide()

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", PAD, -38)
    frame.summary:SetPoint("RIGHT", -PAD, 0)
    frame.summary:SetJustifyH("LEFT"); frame.summary:SetWordWrap(false)
    frame.flags = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.flags:SetPoint("TOPLEFT", PAD, -54)
    frame.flags:SetPoint("RIGHT", -PAD, 0)
    frame.flags:SetJustifyH("LEFT"); frame.flags:SetWordWrap(false)
    frame.flags:Hide()

    frame.partyLine = CreateFrame("Button", nil, frame)
    frame.partyLine:SetHeight(18)
    frame.partyLine:SetPoint("TOPLEFT", PAD, -(LIST_Y - 2))
    frame.partyLine:SetPoint("RIGHT", -PAD, 0)
    frame.partyLine.text = frame.partyLine:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.partyLine.text:SetPoint("LEFT"); frame.partyLine.text:SetPoint("RIGHT", -86, 0)
    frame.partyLine.text:SetJustifyH("LEFT"); frame.partyLine.text:SetWordWrap(false)
    frame.partyLine:SetScript("OnEnter", PartyTooltip)
    frame.partyLine:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.share = CreateFrame("Button", nil, frame.partyLine, "UIPanelButtonTemplate")
    frame.share:SetSize(80, 18); frame.share:SetPoint("RIGHT")
    frame.share:SetScript("OnClick", function()
        local n = NS.ShareMissing()
        NS.Print(n > 0 and ("sharing %d quest%s with your party."):format(n, n == 1 and "" or "s") or "nothing to share.")
    end)
    frame.partyLine:Hide()
    -- party XP bars (you + up to 4 friends)
    frame.xpRows = {}
    for i = 1, 5 do
        local r = CreateFrame("Frame", nil, frame)
        r:SetHeight(BAR_H - 3)
        r:SetPoint("TOPLEFT", frame.partyLine, "BOTTOMLEFT", 0, -4 - (i - 1) * BAR_H)
        r:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT"); r.name:SetWidth(96); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.rest = CreateFrame("StatusBar", nil, r)
        r.rest:SetPoint("LEFT", 102, 0); r.rest:SetSize(140, BAR_H - 4)
        r.rest:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.rest:SetStatusBarColor(0.25, 0.4, 0.9, 0.45)
        r.bar = CreateFrame("StatusBar", nil, r)
        r.bar:SetAllPoints(r.rest)
        r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.bar:SetFrameLevel(r.rest:GetFrameLevel() + 1)
        local bg = r.rest:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)
        r.text = r.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("CENTER")
        r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.right:SetPoint("LEFT", r.rest, "RIGHT", 10, 0); r.right:SetPoint("RIGHT")
        r.right:SetJustifyH("LEFT"); r.right:SetWordWrap(false)
        r:Hide()
        frame.xpRows[i] = r
    end
    frame.listTop = CreateFrame("Frame", nil, frame)
    frame.listTop:SetSize(1, 1)
    frame.listTop:SetPoint("TOPLEFT", PAD, -LIST_Y)

    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(DEFAULT_W - 2 * PAD, ROW_H)
        row:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:RegisterForClicks("AnyUp")
        row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.num:SetPoint("LEFT"); row.num:SetWidth(22); row.num:SetJustifyH("RIGHT")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 28, 0); row.text:SetWidth(DEFAULT_W - 2 * PAD - 28 - 110); row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT"); row.right:SetJustifyH("RIGHT")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        row:SetScript("OnClick", function(self) SetWaypoint(self.step) end)
        row:SetScript("OnEnter", function(self)
            local s = self.step
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(s.q.name, 1, 0.82, 0)
            local plain = StepText(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            GameTooltip:AddLine(plain, 1, 1, 1, true)
            GameTooltip:AddDoubleLine("Travel", ("%d yd, %s"):format(s.dist or 0, NS.FormatTime(s.travel or 0)), 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine("Work", NS.FormatTime(s.work or 0), 0.7, 0.7, 0.7, 1, 1, 1)
            if (s.kxp or 0) > 0 then GameTooltip:AddDoubleLine("Kill XP", NS.FormatNum(s.kxp), 0.7, 0.7, 0.7, 1, 1, 1) end
            if s.role == 3 then GameTooltip:AddDoubleLine("Quest XP", NS.FormatNum(s.q.xp), 0.7, 0.7, 0.7, 1, 1, 1) end
            GameTooltip:AddLine("Click: waypoint", 0.5, 0.8, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        rows[i] = row
    end
    local resizing
    NS.resetSize = NS.MakeResizable(frame, NS.db, {
        minW = 400, minH = 100, maxW = 1400, maxH = 1000, defaultW = DEFAULT_W, defaultH = LIST_Y + PAD, savePos = true,
        onResize = function()
            if resizing then return end
            resizing = true; Layout(); Refresh(); resizing = false
        end })
    Layout()
    if not NS.db.shown then frame:Hide() end
end

------------------------------------------------------------------------
-- Target key: targets the mob or NPC for step 1 (a secure button, so it
-- works from a key binding; updated out of combat whenever the plan changes)
------------------------------------------------------------------------
local targetButton, targetDirty
local function StepTargetName(s)
    if not s then return nil end
    if s.kind == "monster" or s.kind == "killcredit" then return s.name end
    if s.kind == "item" then return s.dropper end
    if s.role == 1 or s.role == 3 or s.kind == "service" then return s.who end
end

function NS.UpdateTargetButton()
    if not targetButton then return end
    if InCombatLockdown() then targetDirty = true; return end
    targetDirty = false
    local name = plan and plan.route[1] and StepTargetName(plan.route[1])
    targetButton:SetAttribute("macrotext", name and ("/targetexact " .. name) or "")
    targetButton.name = name
end

local function MakeTargetButton()
    targetButton = CreateFrame("Button", "TwizQuestTargetButton", UIParent, "SecureActionButtonTemplate")
    targetButton:SetSize(1, 1); targetButton:SetAlpha(0)
    targetButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    targetButton:RegisterForClicks("AnyUp", "AnyDown")
    targetButton:SetAttribute("type", "macro")
    targetButton:SetAttribute("macrotext", "")
end

function NS.OnPlan(result, why)
    if result then
        plan = result
        NS.UpdateTargetButton()
        if NS.db.autoWay and result.route[1] then SetWaypoint(result.route[1], true) end
    elseif frame then
        frame.status = "No plan: " .. tostring(why or "unknown")
    end
    Refresh()
end

------------------------------------------------------------------------
-- Keeping the plan up to date by itself
------------------------------------------------------------------------
local dirty = true          -- something changed: search all quests again
function NS.MarkDirty() dirty = true end
local partyPending
function NS.RefreshParty()
    if partyPending then return end
    partyPending = true
    C_Timer.After(0.5, function() partyPending = nil; Refresh() end)
end
function NS._plan() return plan end
local lastFull = -999
local wantFull = false      -- a manual "Plan" asked while busy

local function Moved(dist)
    if not plan then return true end
    local x, y, inst = NS.PlayerPos()
    return x and (inst ~= plan.inst or NS.Dist(x, y, plan.x, plan.y) > dist)
end

local function Tick()
    if not NS.db or not NS.Bridge() or NS.IsPlanning() then return end
    if wantFull then
        wantFull, dirty, lastFull = false, false, GetTime()
        NS.Plan(true); Refresh(); return
    end
    if not NS.db.auto then Refresh(); return end
    if InCombatLockdown() then return end            -- catch up right after the fight
    local t = GetTime()
    if (dirty and t - lastFull >= 6) or t - lastFull >= 120 or Moved(400) then
        dirty, lastFull = false, t
        NS.Plan(true)
    elseif not dirty and Moved(60) then
        NS.Plan(false)
    end
    Refresh()
end

-- Kept for the Plan button and slash commands: re-plan as soon as possible.
function NS.Replan()
    wantFull = true
    Tick()
end

-- Drop a finished step right away, before the next plan comes in.
local function Done(questID, role)
    if not plan or not questID then return end
    for i = #plan.route, 1, -1 do
        local s = plan.route[i]
        if s.q.id == questID and s.role == role then table.remove(plan.route, i) end
    end
    if NS.db.autoWay and plan.route[1] then SetWaypoint(plan.route[1], true) end
    NS.UpdateTargetButton()
    Refresh()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "MERCHANT_CLOSED", "GROUP_ROSTER_UPDATE",
    "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING", "BAG_UPDATE_DELAYED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        Build()
        MakeTargetButton()
        C_Timer.NewTicker(3, Tick)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if targetDirty then NS.UpdateTargetButton() end
        return
    end
    if event == "MERCHANT_CLOSED" and plan then
        -- sold and repaired: the service stop is done
        for i = #plan.route, 1, -1 do if plan.route[i].kind == "service" then table.remove(plan.route, i) end end
        Refresh()
    end
    if event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_UPDATE_RESTING" or event == "BAG_UPDATE_DELAYED" then
        -- only matters if it changes whether a service stop is needed / rested XP
        local need = NS.ServiceNeed and select(2, NS.ServiceNeed()) or nil
        if (need ~= nil) == (plan and plan.service ~= nil) and event ~= "PLAYER_UPDATE_RESTING" then return end
    end
    dirty = true
    if event == "QUEST_ACCEPTED" then
        Done(a2 or a1, 1)          -- older clients pass (logIndex, questID)
    elseif event == "QUEST_TURNED_IN" then
        Done(a1, 3)
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
function NS.ShareAllCmd()
    local n, why = NS.ShareAll()
    if why then NS.Print(why .. ".")
    elseif n == 0 then NS.Print("none of your quests can be shared.")
    else NS.Print(("sharing %d quest%s with your party (one every 0.5s)."):format(n, n == 1 and "" or "s")) end
end

-- dungeon and raid quests: Questie's database first, then the game's quest tag
local function IsDungeonQuest(id)
    local B = NS.Bridge and NS.Bridge()
    local DB = B and B.DB
    if DB then
        for _, fn in ipairs({ "IsDungeonQuest", "IsRaidQuest" }) do
            if DB[fn] then
                local ok, v = pcall(DB[fn], id)
                if ok and v then return true end
            end
        end
    end
    if C_QuestLog.GetQuestTagInfo then
        local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, id)
        local t = ok and type(tag) == "table" and NS.safe(tag.tagID)
        if t == 81 or t == 62 or t == 88 or t == 89 then return true end   -- dungeon, raid, raid (10/25)
    end
    return false
end
NS.IsDungeonQuest = IsDungeonQuest

-- the quests Drop All would remove: everything, or everything but dungeon/raid quests
local function DropList(withDungeons)
    local ids, kept, done = {}, 0, 0
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        local id = info and NS.safe(info.questID)
        if id and id > 0 and not NS.safe(info.isHeader) then
            if not withDungeons and IsDungeonQuest(id) then
                kept = kept + 1
            else
                ids[#ids + 1] = id
                if C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then done = done + 1 end
            end
        end
    end
    return ids, kept, done
end

StaticPopupDialogs.TWIZQUEST_ABANDON_ALL = {
    text = "Abandon %d quests?%s\n\nThis can't be undone.",
    button1 = YES or "Yes", button2 = NO or "No", timeout = 0, hideOnEscape = true, preferredIndex = 3,
    showAlert = true,
    OnAccept = function(_, withDungeons)
        if NS.KeepAllQuests and NS.KeepAllQuests() then
            NS.Print("you're synced with your party - TwizQuest never removes quests while synced.")
            return
        end
        local ids, kept = DropList(withDungeons)
        for _, id in ipairs(ids) do
            pcall(C_QuestLog.SetSelectedQuest, id)
            pcall(C_QuestLog.SetAbandonQuest)
            pcall(C_QuestLog.AbandonQuest)
        end
        NS.Print(("abandoned %d quest(s)%s."):format(#ids,
            kept > 0 and (", kept %d dungeon quest%s (shift-click Drop All to drop those too)"):format(kept, kept == 1 and "" or "s") or ""))
        NS.cache = nil
        NS.Replan()
    end,
}

-- Drop All keeps dungeon and raid quests; shift-click drops those too
function NS.DropAllCmd(withDungeons)
    if NS.KeepAllQuests and NS.KeepAllQuests() then
        NS.Print("you're synced with your party - TwizQuest never removes quests while synced. Leave the group or /tq party off first.")
        return
    end
    if withDungeons == nil then withDungeons = IsShiftKeyDown() end
    local ids, kept, done = DropList(withDungeons)
    if #ids == 0 then
        NS.Print(kept > 0 and ("only dungeon quests left (%d) - shift-click Drop All to drop them."):format(kept)
            or "your quest log is already empty.")
        return
    end
    local notes = ""
    if withDungeons then notes = notes .. "\n|cffff9933Including dungeon quests.|r"
    elseif kept > 0 then notes = notes .. ("\nKeeping %d dungeon quest%s."):format(kept, kept == 1 and "" or "s") end
    if done > 0 then notes = notes .. ("\n|cffff5555%d of them are complete and ready to turn in!|r"):format(done) end
    local dialog = StaticPopup_Show("TWIZQUEST_ABANDON_ALL", #ids, notes)
    if dialog then dialog.data = withDungeons end
end

local function Help()
    NS.Print("commands:")
    print("  /tq              - show or hide the route window")
    print("  /tq plan         - re-plan now (it also updates by itself)")
    print("  /tq auto         - automatic updates (now " .. (NS.db.auto and "on" or "off") .. ")")
    print("  /tq next         - waypoint to the first step")
    print("  /tq time 60      - minutes of play to plan (now " .. NS.db.horizon .. ")")
    print("  /tq above 3      - max levels above you a quest can be (now " .. NS.db.maxAbove .. ")")
    print("  /tq range 3000   - max yards to a quest giver (now " .. NS.db.maxDist .. ")")
    print("  /tq elites       - include quests with elite kills (now " .. (NS.db.elites and "on" or "off") .. ")")
    print("  /tq way          - auto-waypoint step 1 (now " .. (NS.db.autoWay and "on" or "off") .. ")")
    print("  /tq learned      - what it has learned about how you play")
    print("  /tq size         - reset the window size (drag the bottom-right corner to resize)")
    print("  /tq relearn      - forget learned speeds and rates")
    print("  /tq cleanup      - quests in your log that aren't worth their slot; /tq abandon drops them")
    print("  /tq party        - party sync status; /tq party on|off, /tq party sync (resend), /tq party xp (XP bars), /tq party auto (group plan on sync, on), /tq party pickup (share quests you pick up, on), /tq party share (share your log on join, off), /tq party help (stay to help)")
    print("  /tq share        - share your quests that party members don't have")
    print("  /tq accept       - auto-accept every quest offered, on/off (hold Shift to skip one NPC)")
    print("  /tq minimap      - show/hide the minimap button")
    print("  /tq group        - plan the fastest XP for the whole group and send it to your party (Group button)")
    print("  /tq solo         - back to your own route")
    print("  /tq shareall     - offer every shareable quest to your party (Share All button)")
    print("  /tq dropall      - abandon every quest except dungeon quests, asks first (Drop All button)")
    print("  /tq dropall dungeons - same, including dungeon quests (shift-click Drop All)")
    print("  /tq service      - sell & repair stop when bags are nearly full / gear is breaking (now " .. (NS.db.service and "on" or "off") .. ")")
    print("  Key bindings (Options > Keybindings > AddOns > TwizQuest): target step 1's mob/NPC, waypoint to step 1")
end

SLASH_QUESTROUTE1 = "/tq"
SLASH_QUESTROUTE2 = "/twizquest"
SLASH_QUESTROUTE3 = "/qr"          -- old shortcut still works
SLASH_QUESTROUTE4 = "/questroute"
SlashCmdList.QUESTROUTE = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if (cmd == "cleanup" or cmd == "abandon") and NS.KeepAllQuests and NS.KeepAllQuests() then
        NS.Print("you're synced with your party, so no quests are dropped - your route orders them by group XP instead.")
        return
    end
    if cmd == "cleanup" or cmd == "abandon" then
        local drop = plan and plan.drop or {}
        if #drop == 0 then NS.Print("every quest in your log is worth keeping right now."); return end
        if cmd == "cleanup" then
            NS.Print(("%d quest(s) aren't worth their log slot:"):format(#drop))
            for _, d in ipairs(drop) do print(("  %s - %s"):format(d.name, d.why)) end
            print("  /tq abandon drops them all (asks first).")
        else
            StaticPopupDialogs.TWIZQUEST_ABANDON = StaticPopupDialogs.TWIZQUEST_ABANDON or {
                text = "Abandon %d quest(s) that aren't worth it?\n(See chat for the list.)",
                button1 = YES or "Yes", button2 = NO or "No", timeout = 0, hideOnEscape = true, preferredIndex = 3,
                OnAccept = function(_, list)
                    if NS.KeepAllQuests and NS.KeepAllQuests() then
                        NS.Print("you're synced with your party - TwizQuest never removes quests while synced.")
                        return
                    end
                    for _, d in ipairs(list) do
                        pcall(C_QuestLog.SetSelectedQuest, d.id)
                        pcall(C_QuestLog.SetAbandonQuest)
                        pcall(C_QuestLog.AbandonQuest)
                    end
                    NS.Print(("abandoned %d quest(s)."):format(#list))
                    NS.Replan()
                end,
            }
            for _, d in ipairs(drop) do print(("  %s - %s"):format(d.name, d.why)) end
            StaticPopup_Show("TWIZQUEST_ABANDON", #drop, nil, drop)
        end
        return
    elseif cmd == "accept" then
        NS.db.autoAccept = not NS.db.autoAccept
        NS.Print("auto-accept quests " .. (NS.db.autoAccept and "on (hold Shift when talking to an NPC to skip)" or "off"))
        return
    elseif cmd == "minimap" then
        NS.db.minimap = NS.db.minimap == false
        NS.UpdateMinimap()
        NS.Print("minimap button " .. (NS.db.minimap and "shown" or "hidden (/tq minimap to bring it back)"))
        return
    elseif cmd == "group" then
        NS.StartGroupPlan(); return
    elseif cmd == "solo" then
        NS.EndGroupPlan(); return
    elseif cmd == "shareall" then
        NS.ShareAllCmd(); return
    elseif cmd == "dropall" then
        NS.DropAllCmd((rest or ""):lower() == "dungeons" or nil); return
    elseif cmd == "party" then
        local arg = (rest or ""):lower()
        if arg == "off" or arg == "on" then
            NS.db.party = arg == "on"
            NS.Print("party sync " .. (NS.db.party and "on" or "off"))
            Refresh()
        elseif arg == "xp" then
            NS.db.partyXP = not NS.db.partyXP
            NS.Print("party XP bars " .. (NS.db.partyXP and "on" or "off"))
            Refresh()
        elseif arg == "auto" then
            NS.db.autoGroup = NS.db.autoGroup == false
            NS.Print("plan for the group automatically when someone syncs: " .. (NS.db.autoGroup and "on" or "off"))
        elseif arg == "pickup" then
            NS.db.shareOnAccept = NS.db.shareOnAccept == false
            NS.Print("share new quests with the group when you pick them up: " .. (NS.db.shareOnAccept and "on" or "off"))
        elseif arg == "share" then
            NS.db.autoShare = not NS.db.autoShare
            NS.Print("share quests automatically when someone joins: " .. (NS.db.autoShare and "on" or "off (use the Share button)"))
        elseif arg == "sync" then
            if NS.PartyResync() then NS.Print("asked your party to resync quests.") else NS.Print("you're not in a party.") end
        elseif arg == "help" then
            NS.db.partyHelp = not NS.db.partyHelp
            NS.Print("stay to help party members finish kills " .. (NS.db.partyHelp and "on" or "off"))
            NS.cache = nil; NS.Replan()
        else
            local st = NS.PartyStatus()
            NS.Print(("party: %d syncing, %d to share, %d behind, %d ready to turn in."):format(
                #st.members, #st.missing, #st.behind, #st.ready))
            for _, m in ipairs(st.members) do
                local p = NS.party[m]
                print(("  %s: %d quests%s"):format(m, NS.Count(p.quests), p.step and (", heading to " .. p.step.text) or ""))
            end
            if #st.noAddon > 0 then
                print("  not syncing: " .. table.concat(st.noAddon, ", ")
                    .. " - they need TwizQuest 1.5+ enabled (it also needs Questie and TomTom installed, or it won't load)")
            end
            local ps = NS.partyStats or {}
            print(("  messages sent %d, received %d%s"):format(ps.sent or 0, ps.recv or 0,
                ps.last and (" - last from " .. ps.last) or ""))
            if not NS.db.party then print("  party sync is OFF - /tq party on") end
            print("  /tq party sync - ask everyone to resend")
        end
        return
    elseif cmd == "share" then
        local n = NS.ShareMissing()
        NS.Print(n > 0 and ("sharing %d quest%s with your party."):format(n, n == 1 and "" or "s") or "nothing to share.")
        return
    elseif cmd == "service" then
        NS.db.service = not NS.db.service
        NS.Print("sell & repair stops " .. (NS.db.service and "on" or "off"))
        NS.Replan()
        return
    end
    cmd = (cmd or ""):lower()
    local n = tonumber(rest)
    if cmd == "" then
        if frame:IsShown() then frame:Hide(); NS.db.shown = false
        else frame:Show(); NS.db.shown = true; Refresh() end
    elseif cmd == "plan" then NS.Replan()
    elseif cmd == "size" or cmd == "scale" then NS.resetSize(); NS.Print("window size reset")
    elseif cmd == "next" then
        if plan and plan.route[1] then SetWaypoint(plan.route[1]) else NS.Print("no plan yet.") end
    elseif cmd == "time" and n then NS.db.horizon = math.max(10, math.min(n, 240)); NS.Replan()
    elseif cmd == "above" and n then NS.db.maxAbove = math.max(0, math.min(n, 10)); NS.Replan()
    elseif cmd == "range" and n then NS.db.maxDist = math.max(300, n); NS.Replan()
    elseif cmd == "elites" then
        NS.db.elites = not NS.db.elites
        NS.Print("elite quests " .. (NS.db.elites and "included" or "skipped")); NS.Replan()
    elseif cmd == "auto" then
        NS.db.auto = not NS.db.auto
        NS.Print("automatic updates " .. (NS.db.auto and "on" or "off"))
    elseif cmd == "way" then
        NS.db.autoWay = not NS.db.autoWay
        NS.Print("auto-waypoint " .. (NS.db.autoWay and "on" or "off"))
    elseif cmd == "learned" then
        local L = NS.db.learn
        NS.Print("learned so far:")
        print(("  on foot %.1f yd/s, mounted %s"):format(L.runSpeed,
            L.mountSeen >= 10 and ("%.1f yd/s"):format(L.mountSpeed) or "not seen yet"))
        print(("  %.0fs fighting + %.0fs resting per kill (%d kills watched)"):format(L.secPerKill, L.restPerKill, L.kills))
        print(("  kill XP x%.2f of formula, quest XP x%.2f of database (%d turn-ins)"):format(
            L.killXPRatio, L.questXPRatio, L.quests))
        local at = NS.BankKnown()
        print(at and ("  bank contents remembered " .. NS.FormatTime(time() - at) .. " ago")
            or "  bank not seen yet - open your bank once so quest items there are counted")
    elseif cmd == "error" then
        local e = NS.db.lastError
        if not e then NS.Print("no errors recorded."); return end
        NS.Print("last problem: " .. e.msg)
        for line in (e.stack or ""):gmatch("[^\n]+") do print("  " .. line) end
    elseif cmd == "relearn" then
        NS.db.learn = {}
        for k, v in pairs(NS.DEFAULTS.learn) do NS.db.learn[k] = v end
        NS.Print("forgot everything learned; back to defaults.")
    else
        Help()
    end
end
