-- TwizQuest window: the ordered steps, XP/hour, and click-to-waypoint.
local ADDON, NS = ...

local ROWS = 40
local PAD = 12                 -- space between the window edge and its contents
local DEFAULT_W = 520
local plan
local frame, rows = nil, {}
local wayUID

------------------------------------------------------------------------
-- The window (clean skin): header, the "Next" card, the "Up next" list,
-- and a footer with party XP bars, Solo/Group, Share and a "more" menu.
------------------------------------------------------------------------
local S = NS.Skin
local CARD_H, LINE_H, BAR_H, FOOT_H, HEAD_H = 74, 26, 16, 38, 40

local function Short(n)
    n = n or 0
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return NS.FormatNum(n)
end

-- what a step looks like: glyph, glyph color, title, subtitle, right-hand note
local function StepParts(s)
    local q = s.q
    local dist = s.dist and (s.dist > 0 and ("%d yd"):format(s.dist) or (s.mobNames and s.role == 2 and "here")) or nil
    local function join(...)
        local t = {}
        for i = 1, select("#", ...) do local v = select(i, ...) if v and v ~= "" then t[#t + 1] = v end end
        return table.concat(t, " · ")
    end
    if s.kind == "service" then
        return "$", "orange", (s.repair and "Sell & repair" or "Sell junk"), join(s.who, s.why, dist), s.why or ""
    elseif s.kind == "bank" then
        return "B", "blue", ("Bank: %d %s"):format(s.need or 0, s.name or "items"), join(q.name, dist), ""
    elseif s.kind == "useitem" or s.kind == "bankstart" then
        return "!", "gold", "Start " .. q.name, join("use " .. (s.name or "item"), dist), ""
    end
    if s.role == 1 then
        return "!", "gold", "Pick up " .. q.name, join(s.who, dist), s.who or ""
    elseif s.role == 3 then
        return "?", "green", "Turn in " .. q.name, join(s.who, dist), "+" .. NS.FormatNum(q.xp or 0) .. " XP"
    end
    local what
    if s.kind == "monster" or s.kind == "killcredit" then
        what = ("Kill %d %s"):format(s.need or 0, s.name or s.text or "targets")
    elseif s.kind == "item" then
        what = ("Get %d %s"):format(s.need or 0, s.name or s.text or "items")
    elseif s.kind == "loot" or s.kind == "object" then
        what = ("Collect %d %s"):format(s.need or 0, s.name or s.text or "objects")
    elseif s.kind == "buy" then
        what = ("Buy %s"):format(s.name or "item")
    else
        what = s.text or "Objective"
    end
    if s.elite then what = what .. " " .. S.Color("red", "(elite)") end
    local sub = join(q.name, dist, s.dropper and ("~" .. (s.kills or s.need) .. " " .. s.dropper) or nil,
        s.help and S.Color("blue", "helping " .. s.help) or nil)
    return (s.kind == "item" or s.kind == "loot" or s.kind == "object") and "o" or "x", "text", what, sub, dist or ""
end

-- the old one-line text (tooltips and chat still use it)
local function StepText(s)
    local _, _, title, sub = StepParts(s)
    return title .. (sub ~= "" and (" |cff999999- " .. sub .. "|r") or "")
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

local function StepTooltip(owner, s)
    if not s then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(s.q.name, S.C.gold[1], S.C.gold[2], S.C.gold[3])
    local plain = StepText(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    GameTooltip:AddLine(plain, 1, 1, 1, true)
    GameTooltip:AddDoubleLine("Travel", ("%d yd, %s"):format(s.dist or 0, NS.FormatTime(s.travel or 0)), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Work", NS.FormatTime(s.work or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    if (s.kxp or 0) > 0 then GameTooltip:AddDoubleLine("Kill XP", NS.FormatNum(s.kxp), 0.7, 0.7, 0.7, 1, 1, 1) end
    if s.role == 3 then GameTooltip:AddDoubleLine("Quest XP", NS.FormatNum(s.q.xp), 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:AddLine(s.kind == "service" and "Click: do this next.  Right-click: skip selling for 20 minutes."
        or "Click: do this next.  Right-click: skip this quest.", 0.5, 0.8, 1)
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Party: status text, tooltip, XP bars
------------------------------------------------------------------------
local partyOffset = 0
local function QName(id)
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return t or NS.Q(id, "name") or ("quest " .. id)
end

local function PartyText(st)
    if #st.members == 0 then
        if #st.noAddon > 0 then return S.Color("muted", ("synced 0/%d"):format(#st.noAddon)) end
        return nil
    end
    local bits = { S.Color("text", table.concat(st.members, ", ")) }
    bits[#bits + 1] = S.Color("green", #st.same .. " same")
    if #st.behind > 0 then bits[#bits + 1] = S.Color("orange", #st.behind .. " behind") end
    if #st.ready > 0 then bits[#bits + 1] = S.Color("green", #st.ready .. " ready") end
    if #st.theyHave > 0 then bits[#bits + 1] = S.Color("muted", #st.theyHave .. " theirs") end
    if #st.noAddon > 0 then
        bits[#bits + 1] = S.Color("muted", ("synced %d/%d"):format(#st.members, #st.members + #st.noAddon))
    end
    return table.concat(bits, S.Color("faint", " · "))
end

local function PartyTooltip(self)
    local st = NS.PartyStatus()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Party sync", S.C.blue[1], S.C.blue[2], S.C.blue[3])
    for _, m in ipairs(st.members) do
        local p = NS.party[m]
        GameTooltip:AddDoubleLine(m .. (p.level and (" (" .. p.level .. ")") or ""),
            p.step and ("Next: " .. p.step.text) or "", 1, 1, 1, 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Same quests: %d everyone has%s"):format(#st.same,
        st.sameSome > #st.same and (", " .. st.sameSome .. " with someone") or ""), S.C.green[1], S.C.green[2], S.C.green[3])
    for _, id in ipairs(st.same) do GameTooltip:AddLine("  " .. QName(id), 1, 1, 1) end
    if #st.missing > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Missing (Share):", S.C.gold[1], S.C.gold[2], S.C.gold[3])
        for _, m in ipairs(st.missing) do GameTooltip:AddDoubleLine(QName(m.id), m.who, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.behind > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Behind:", S.C.orange[1], S.C.orange[2], S.C.orange[3])
        for _, b in ipairs(st.behind) do GameTooltip:AddDoubleLine(QName(b.id), b.who .. " " .. b.left, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.ready > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ready to turn in:", S.C.green[1], S.C.green[2], S.C.green[3])
        for _, id in ipairs(st.ready) do GameTooltip:AddLine(QName(id), 1, 1, 1) end
    end
    if #st.theyHave > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Theirs only:", 0.7, 0.7, 0.7)
        for _, m in ipairs(st.theyHave) do GameTooltip:AddDoubleLine(QName(m.id), m.who, 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    if #st.noAddon > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Not synced: " .. table.concat(st.noAddon, ", "), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function XPRow(row, name, xp, classFile, isMe, note)
    row.name:SetText(isMe and S.Color("green", "You") or name)
    if not xp or not xp.max or xp.max <= 0 then
        row.bar:SetValue(0); row.bar.behind:SetValue(0)
        row.text:SetText("")
        row.right:SetText(S.Color("faint", note or "no data"))
        return
    end
    row.bar:SetMinMaxValues(0, xp.max); row.bar:SetValue(xp.cur)
    row.bar.behind:SetMinMaxValues(0, xp.max); row.bar.behind:SetValue(math.min(xp.max, xp.cur + (xp.rest or 0)))
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then row.bar:SetStatusBarColor(color.r, color.g, color.b) else row.bar:SetStatusBarColor(0.69, 0.49, 0.94) end
    local left = xp.max - xp.cur
    row.text:SetText(("%d%%"):format(math.floor(xp.cur / xp.max * 100)))
    row.right:SetText(S.Color("muted", ("L%d · %s to go"):format(xp.level or 0, Short(left))))
end

local function MyXP()
    local p = NS._plan and NS._plan()
    return { level = UnitLevel("player"), cur = UnitXP("player") or 0, max = UnitXPMax("player") or 0,
             rest = (GetXPExhaustion and GetXPExhaustion()) or 0, rate = p and p.rate or 0 }
end

local function UnitClassFile(name)
    local unit = NS.PartyUnit and NS.PartyUnit(name)
    if unit then return select(2, UnitClass(unit)) end
end

------------------------------------------------------------------------
-- Layout and refresh
------------------------------------------------------------------------
local function FooterHeight(nbars) return FOOT_H + nbars * BAR_H + (nbars > 0 and 8 or 0) end
local function FixedHeight(nbars, flags)
    return HEAD_H + (flags and 14 or 0) + 10 + CARD_H + 12 + 18 + 18 + FooterHeight(nbars) + 6
end

local function RowsFit(nbars, flags)
    if NS.db.sized then
        return math.max(0, math.min(ROWS, math.floor((frame:GetHeight() - FixedHeight(nbars, flags)) / LINE_H)))
    end
    return 5
end

local function Layout()
    if not frame then return end
    local w = frame:GetWidth()
    for _, row in ipairs(rows) do row:SetWidth(w - 2 * PAD) end
end

local function Refresh()
    if not frame then return end
    -- footer: party status, XP bars, Solo/Group, Share
    local synced = NS.KeepAllQuests and NS.KeepAllQuests()
    local st = NS.db.party and NS.PartyStatus and NS.PartyStatus() or nil
    local ptext = st and PartyText(st) or nil
    frame.dropAll:SetShown(not synced)
    local canGroup = NS.groupMode or (IsInGroup() and NS.SyncedCount and NS.SyncedCount() > 0)
    frame.groupBtn:SetText(NS.groupMode and "Solo" or "Group")
    frame.groupToggle:SetShown(canGroup and true or false)
    frame.groupToggle:Select(NS.groupMode and "group" or "solo")
    frame.partyLine.text:SetText(ptext or S.Color("faint", IsInGroup() and "party not synced" or "solo"))
    frame.partyLine:ClearAllPoints()
    if canGroup then frame.partyLine:SetPoint("LEFT", frame.groupToggle, "RIGHT", 10, 0)
    else frame.partyLine:SetPoint("LEFT", frame.controls, "LEFT", PAD, 0) end -- the bottom row, never over the XP bars
    frame.partyLine:SetPoint("RIGHT", frame.share, "LEFT", -8, 0)
    local missing = st and #st.missing or 0
    frame.share:SetText("Share " .. missing)
    frame.share:SetShown(missing > 0)
    local nbars = 0
    local everyone = NS.PartyXPList and NS.PartyXPList() or {}
    if st and NS.db.partyXP and #everyone > 0 then
        nbars = 1
        XPRow(frame.xpRows[1], UnitName("player"), MyXP(), select(2, UnitClass("player")), true)
        for _, m in ipairs(everyone) do
            if nbars < #frame.xpRows then
                nbars = nbars + 1
                XPRow(frame.xpRows[nbars], m.name, m.xp, m.unit and select(2, UnitClass(m.unit)), false,
                    not m.xp and (m.addon and "waiting for XP..." or ("L%s · no TwizQuest"):format(m.level or "?")))
            end
        end
    end
    for i, r in ipairs(frame.xpRows) do r:SetShown(i <= nbars) end
    frame.foot:SetHeight(FooterHeight(nbars))
    partyOffset = nbars

    -- flags under the header, only when there is something to flag
    local flags = {}
    if plan then
        if (plan.skipped or 0) > 0 then flags[#flags + 1] = S.Color("orange", plan.skipped .. " skipped") end
        if (plan.rested or 0) > 0 then flags[#flags + 1] = S.Color("blue", Short(plan.rested) .. " rested") end
        if #(plan.drop or {}) > 0 then flags[#flags + 1] = S.Color("gold", #plan.drop .. " worth dropping (/tq cleanup)") end
    end
    frame.flags:SetText(table.concat(flags, S.Color("faint", " · ")))
    frame.flags:SetShown(#flags > 0)
    frame.card:ClearAllPoints()
    frame.card:SetPoint("TOPLEFT", PAD, -(HEAD_H + 10 + (#flags > 0 and 14 or 0)))
    frame.card:SetPoint("RIGHT", -PAD, 0)

    -- header: the number that matters
    if not plan then
        frame.summary:SetText(S.Color("muted", NS.IsPlanning() and "Planning..." or (frame.status or "No plan yet")))
        frame.card:Hide(); frame.upLabel:Hide(); frame.more:Hide()
        for i = 1, ROWS do rows[i]:Hide() end
        if not NS.db.sized then frame:SetHeight(HEAD_H + 20 + FooterHeight(nbars)) end
        return
    end
    local need = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    local toLevel = (plan.rate > 0) and (need / plan.rate * 3600) or nil
    local head
    if plan.group then
        head = S.Color("green", Short(plan.group.rate) .. " XP/hr group")
            .. S.Color("muted", ("   %s you%s"):format(Short(plan.rate), plan.group.from and (" · " .. plan.group.from .. "'s plan") or ""))
    else
        head = S.Color("green", Short(plan.rate) .. " XP/hr")
            .. S.Color("muted", "   " .. NS.FormatNum(plan.xp) .. " XP in " .. NS.FormatTime(plan.time))
    end
    if toLevel then head = head .. S.Color("muted", " · level in " .. NS.FormatTime(toLevel)) end
    if NS.IsPlanning() then head = head .. S.Color("gold", " · updating") end
    frame.summary:SetText(head)

    -- the next step
    local first = plan.route[1]
    if not first then
        frame.summary:SetText(S.Color("muted", "No quests in range"))
        frame.card:Hide(); frame.upLabel:Hide(); frame.more:Hide()
        for i = 1, ROWS do rows[i]:Hide() end
        if not NS.db.sized then frame:SetHeight(HEAD_H + 20 + FooterHeight(nbars)) end
        return
    end
    local glyph, gc, title, sub = StepParts(first)
    frame.card.step = first
    frame.card.glyph:SetText(S.Color(gc, glyph))
    frame.card.title:SetText(title)
    frame.card.sub:SetText(S.Color("muted", sub))
    local have, total = first.have, first.total
    if total and total > 0 then
        frame.card.bar:SetMinMaxValues(0, total); frame.card.bar:SetValue(have or 0); frame.card.bar:Show()
    else
        frame.card.bar:Hide()
    end
    frame.card:Show()

    -- up next: the top 3 quests (the card's counts as the first) stay bright, the rest fade until you hover the list
    local fit = RowsFit(nbars, #flags > 0)
    local shown = 0
    local top, nTop, cut = {}, 0, false
    local function qid(st) return st and st.q and (st.q.id or st.q.name) end
    if qid(first) then top[qid(first)] = true; nTop = 1 end
    for i = 1, ROWS do
        local s = (i <= fit) and plan.route[i + 1] or nil
        local row = rows[i]
        if s then
            local g, c, t, sb, note = StepParts(s)
            row.step = s
            row.glyph:SetText(S.Color(c, g))
            local quest = (s.role ~= 1 and s.role ~= 3 and s.kind ~= "service") and S.Color("muted", " · " .. s.q.name) or ""
            row.text:SetText(t .. quest)
            row.right:SetText(S.Color("muted", note ~= "" and note or NS.FormatTime(s.eta or 0)))
            local id = qid(s)
            if id and not top[id] then
                if nTop < 3 and not cut then top[id] = true; nTop = nTop + 1 else cut = true end
            end
            row.faded = cut or (id ~= nil and not top[id])
            row:SetAlpha((row.faded and not frame.listHover) and 0.3 or 1)
            row:Show(); shown = i
        else
            row:Hide()
        end
    end
    local rest = math.max(0, #plan.route - 1 - shown)
    frame.upLabel:SetText("UP NEXT · " .. NS.FormatTime(plan.time))
    frame.upLabel:SetShown(#plan.route > 1)
    frame.more:SetText(rest > 0 and ("+%d more step%s"):format(rest, rest == 1 and "" or "s") or "")
    frame.more:ClearAllPoints()
    frame.more:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", 4, -(shown * LINE_H) - 4)
    frame.more:SetShown(rest > 0)
    if not NS.db.sized then
        frame:SetHeight(FixedHeight(nbars, #flags > 0) + shown * LINE_H - (#plan.route > 1 and 0 or 18) - (rest > 0 and 0 or 18))
    end
end

local function Build()
    frame = CreateFrame("Frame", "TwizQuestFrame", UIParent, "BackdropTemplate")
    frame:SetSize(DEFAULT_W, 300)
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        NS.db.pos = { p, rp, x, y }
    end)
    S.Panel(frame)
    if NS.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(NS.db.pos[1], UIParent, NS.db.pos[2], NS.db.pos[3], NS.db.pos[4])
    end

    -- header
    local head = CreateFrame("Frame", nil, frame)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(HEAD_H)
    S.Divider(frame, head)
    local title = S.Text(head, "title")
    title:SetPoint("LEFT", PAD, 0); title:SetText("TwizQuest")
    local close = S.IconButton(head, "x", "Close (/tq to reopen)", function() frame:Hide(); NS.db.shown = false end)
    close:SetPoint("RIGHT", -8, 0)
    local planBtn = S.Button(head, "Plan", "ghost", 44, 24, function() NS.Replan() end)
    planBtn:SetPoint("RIGHT", close, "LEFT", -2, 0)
    S.Tip(planBtn, "Plan", "Plan your route again now")
    frame.summary = S.Text(head, "small")
    frame.summary:SetPoint("LEFT", title, "RIGHT", 12, 0)
    frame.summary:SetPoint("RIGHT", planBtn, "LEFT", -8, 0)
    frame.flags = S.Text(frame, "small")
    frame.flags:SetPoint("TOPLEFT", PAD, -(HEAD_H + 4)); frame.flags:SetPoint("RIGHT", -PAD, 0)
    frame.flags:Hide()

    -- the "Next" card
    local card = CreateFrame("Button", nil, frame, "BackdropTemplate")
    card:SetHeight(CARD_H)
    S.Card(card)
    card:RegisterForClicks("AnyUp")
    card:SetScript("OnClick", function(self, button)
        -- right-click the sell/repair stop to skip it
        if button == "RightButton" and self.step and self.step.kind == "service" then NS.DismissService(); return end
        SetWaypoint(self.step)
    end)
    card:SetScript("OnEnter", function(self) StepTooltip(self, self.step) end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local icon = CreateFrame("Frame", nil, card, "BackdropTemplate")
    icon:SetSize(36, 36); icon:SetPoint("LEFT", 12, 0)
    if icon.SetBackdrop then
        icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        icon:SetBackdropColor(0.17, 0.13, 0.09, 1)
    end
    card.glyph = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.glyph:SetPoint("CENTER")
    local lbl = S.Label(card); lbl:SetPoint("TOPLEFT", 60, -10); lbl:SetLabel("Next")
    card.title = S.Text(card, "body"); card.title:SetPoint("TOPLEFT", 60, -24); card.title:SetPoint("RIGHT", -96, 0)
    card.sub = S.Text(card, "small"); card.sub:SetPoint("TOPLEFT", 60, -42); card.sub:SetPoint("RIGHT", -96, 0)
    card.bar = S.Bar(card, 4); card.bar:SetPoint("BOTTOMLEFT", 60, 10); card.bar:SetPoint("RIGHT", -96, 0); card.bar:Hide()
    frame.card = card

    -- up next
    frame.upLabel = S.Label(frame)
    frame.upLabel:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -12)
    frame.listTop = CreateFrame("Frame", nil, frame)
    frame.listTop:SetSize(1, 1)
    frame.listTop:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -28)
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(DEFAULT_W - 2 * PAD, LINE_H)
        row:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", 0, -(i - 1) * LINE_H)
        row:RegisterForClicks("AnyUp")
        row.glyph = S.Text(row, "body"); row.glyph:SetPoint("LEFT", 4, 0); row.glyph:SetWidth(16); row.glyph:SetJustifyH("CENTER")
        row.right = S.Text(row, "small"); row.right:SetPoint("RIGHT", -4, 0); row.right:SetJustifyH("RIGHT")
        row.text = S.Text(row, "body"); row.text:SetPoint("LEFT", 28, 0); row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
        local line = row:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(unpack(S.C.line)); line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT")
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
        row:SetScript("OnClick", function(self, button)
            -- right-click: skip that quest (e.g. the game won't give it to you), or the sell/repair stop
            if button == "RightButton" and self.step and self.step.kind == "service" then NS.DismissService(); return end
            if button == "RightButton" and self.step and self.step.q and self.step.q.id and self.step.kind ~= "service" then
                NS.Print(("skipping %s - /tq unskip brings it back."):format(self.step.q.name or "that quest"))
                NS.SkipQuest(self.step.q.id, "manual")
                return
            end
            -- left-click: do this one next
            NS.Promote(self.step)
        end)
        row:SetScript("OnEnter", function(self)
            StepTooltip(self, self.step)
            frame.listHover = true
            for _, r in ipairs(rows) do r:SetAlpha(1) end -- hovering the list shows every step
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
            frame.listHover = false
            C_Timer.After(0.15, function()
                if frame.listHover then return end
                for _, r in ipairs(rows) do r:SetAlpha(r.faded and 0.3 or 1) end
            end)
        end)
        row:Hide()
        rows[i] = row
    end
    NS._upNextRows = rows
    frame.more = S.Text(frame, "faint"); frame.more:Hide()

    -- footer: XP bars, then Solo/Group, party status, Share, more
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT"); foot:SetHeight(FOOT_H)
    S.Divider(frame, foot, "top")
    frame.foot = foot
    frame.xpRows = {}
    for i = 1, 5 do
        local r = CreateFrame("Frame", nil, foot)
        r:SetHeight(BAR_H - 2)
        r:SetPoint("TOPLEFT", PAD, -8 - (i - 1) * BAR_H); r:SetPoint("RIGHT", -PAD, 0)
        r.name = S.Text(r, "small"); r.name:SetPoint("LEFT"); r.name:SetWidth(64)
        r.right = S.Text(r, "small"); r.right:SetPoint("RIGHT"); r.right:SetWidth(120); r.right:SetJustifyH("RIGHT")
        r.bar = S.Bar(r, 6); r.bar:SetPoint("LEFT", 70, 0); r.bar:SetPoint("RIGHT", r.right, "LEFT", -10, 0)
        r.rest = r.bar.behind
        r.text = S.Text(r, "faint"); r.text:Hide()
        r:Hide()
        frame.xpRows[i] = r
    end
    local controls = CreateFrame("Frame", nil, foot)
    controls:SetPoint("BOTTOMLEFT"); controls:SetPoint("BOTTOMRIGHT"); controls:SetHeight(FOOT_H)
    frame.controls = controls

    -- Solo / Group (frame.groupBtn toggles; the segmented control shows the state)
    frame.groupBtn = CreateFrame("Button", nil, controls)
    frame.groupBtn:Hide()
    frame.groupBtn:SetScript("OnClick", function()
        if NS.groupMode then NS.EndGroupPlan() else NS.StartGroupPlan() end
    end)
    frame.groupToggle = S.Segmented(controls, { { "solo", "Solo", w = 44 }, { "group", "Group", w = 52 } }, function(key)
        if (key == "group") ~= (NS.groupMode and true or false) then frame.groupBtn:Click() end
    end, 26)
    frame.groupToggle:SetPoint("LEFT", PAD, 0)
    S.Tip(frame.groupToggle, "Group plan", "Group: the fastest XP for the whole party, sent to everyone running TwizQuest\nSolo: just your own route")
    frame.groupToggle:Hide()

    local more = S.MoreButton(controls, function()
        local synced = NS.KeepAllQuests and NS.KeepAllQuests()
        return {
            { "Plan again", function() NS.Replan() end },
            { "Share All", function() frame.shareAll:Click() end, nil, not IsInGroup() },
            { synced and "Drop All (off while synced)" or "Drop All", function() frame.dropAll:Click() end, nil, synced },
            { "Drop All incl. dungeon/class", function() NS.DropAllCmd(true) end, nil, synced },
            { "Party: " .. (NS.db.party and "sync on" or "sync off"), function() SlashCmdList.QUESTROUTE(NS.db.party and "party off" or "party on") end },
            { "Auto-accept: " .. (NS.db.autoAccept and "on" or "off"), function() SlashCmdList.QUESTROUTE("accept") end },
            { "Help (/tq help)", function() SlashCmdList.QUESTROUTE("help") end },
        }
    end, 30)
    more:SetPoint("RIGHT", -PAD, 0)
    frame.share = S.Button(controls, "Share 0", "secondary", 70, 26, function()
        local n = NS.ShareMissing()
        NS.Print(n > 0 and ("sharing %d quest%s with your party."):format(n, n == 1 and "" or "s") or "nothing to share.")
    end)
    frame.share:SetPoint("RIGHT", more, "LEFT", -6, 0)
    S.Tip(frame.share, "Share", "Offer your quests that party members are missing")
    frame.partyLine = CreateFrame("Button", nil, controls)
    frame.partyLine:SetHeight(20)
    frame.partyLine.text = S.Text(frame.partyLine, "small")
    frame.partyLine.text:SetPoint("LEFT"); frame.partyLine.text:SetPoint("RIGHT")
    frame.partyLine:SetScript("OnEnter", PartyTooltip)
    frame.partyLine:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Share All / Drop All live in the "more" menu (kept as buttons for key bindings and tests)
    frame.shareAll = CreateFrame("Button", nil, controls); frame.shareAll:Hide()
    frame.shareAll:SetScript("OnClick", function() NS.ShareAllCmd() end)
    frame.dropAll = CreateFrame("Button", nil, controls); frame.dropAll:Hide()
    frame.dropAll:SetScript("OnClick", function() NS.DropAllCmd(IsShiftKeyDown()) end)

    local resizing
    NS.resetSize = NS.MakeResizable(frame, NS.db, {
        minW = 400, minH = 180, maxW = 1400, maxH = 1000, defaultW = DEFAULT_W, defaultH = 300, savePos = true,
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
    if targetButton.label then targetButton:SetAlpha(name and 1 or 0.4) end
end

-- the gold "Target" button on the Next card is the secure button itself, so it
-- works from the key binding and in combat too
local function MakeTargetButton()
    local parent = frame and frame.card or UIParent
    targetButton = CreateFrame("Button", "TwizQuestTargetButton", parent, "SecureActionButtonTemplate,BackdropTemplate")
    targetButton:RegisterForClicks("AnyUp", "AnyDown")
    targetButton:SetAttribute("type", "macro")
    targetButton:SetAttribute("macrotext", "")
    if frame and frame.card then
        targetButton:SetSize(72, 30)
        targetButton:SetPoint("RIGHT", frame.card, "RIGHT", -12, 0)
        if targetButton.SetBackdrop then
            targetButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            targetButton:SetBackdropColor(NS.Skin.C.gold[1], NS.Skin.C.gold[2], NS.Skin.C.gold[3], 1)
        end
        targetButton.label = targetButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        targetButton.label:SetPoint("CENTER")
        targetButton.label:SetTextColor(unpack(NS.Skin.C.ink))
        targetButton.label:SetText("Target")
        targetButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.name and ("Target " .. self.name) or "Nothing to target for this step", 1, 1, 1)
            GameTooltip:AddLine("Bind a key: Options > Keybindings > AddOns > TwizQuest", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        targetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        targetButton:SetSize(1, 1); targetButton:SetAlpha(0)
        targetButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
    end
end

-- steps finished since a plan started: a plan that was already running when you accepted /
-- turned in a quest mustn't bring the finished step back
local recentDone = {}
local function StaleStep(st)
    local id = st.q and st.q.id
    if not id then return false end
    local t = recentDone[id .. ":" .. tostring(st.role)]
    if t and GetTime() - t < 30 then return true end
    -- objective steps of a quest that's now complete, pickups of a quest now in the log
    if st.role == 2 and C_QuestLog.IsComplete and NS.safe(C_QuestLog.IsComplete(id)) then return true end
    if st.role == 1 and C_QuestLog.IsOnQuest and NS.safe(C_QuestLog.IsOnQuest(id)) then return true end
    return false
end
-- a step you clicked stays "Next" until it's done, even when the plan is rebuilt
local pinned
local function SameStep(a, p)
    return a.q and a.q.id == p.id and a.role == p.role and a.kind == p.kind and a.key == p.key
end
local function ApplyPin(route)
    if not pinned or not route then return end
    for i, st in ipairs(route) do
        if SameStep(st, pinned) then
            if i > 1 then table.remove(route, i); table.insert(route, 1, st) end
            return
        end
    end
    pinned = nil -- done or gone
end
function NS.Promote(step)
    if not plan or not step then return end
    for i, st in ipairs(plan.route) do
        if st == step then
            table.remove(plan.route, i); table.insert(plan.route, 1, st)
            break
        end
    end
    pinned = step.q and { id = step.q.id, role = step.role, kind = step.kind, key = step.key } or nil
    SetWaypoint(step, true)
    NS.UpdateTargetButton()
    Refresh()
end
function NS.OnPlan(result, why)
    if result then
        for i = #result.route, 1, -1 do
            if StaleStep(result.route[i]) then table.remove(result.route, i) end
        end
        ApplyPin(result.route)
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
    if (dirty and t - lastFull >= 3) or t - lastFull >= 120 or Moved(400) then
        dirty, lastFull = false, t
        NS.Plan(true)
    elseif not dirty and Moved(60) then
        NS.Plan(false)
    end
    Refresh()
end

-- plan again on the next tick (even mid-fight: planning is spread over frames)
function NS.RequestPlan() wantFull = true end

-- Kept for the Plan button and slash commands: re-plan as soon as possible.
function NS.Replan()
    wantFull = true
    Tick()
end

-- Drop a finished step right away, before the next plan comes in.
local function Done(questID, role)
    if not questID then return end
    recentDone[questID .. ":" .. role] = GetTime()
    -- new quests may open up (follow-ups at the same NPC): plan again right away
    wantFull = true
    if not plan then return end
    for i = #plan.route, 1, -1 do
        local s = plan.route[i]
        if s.q.id == questID and s.role == role then table.remove(plan.route, i) end
    end
    if NS.db.autoWay and plan.route[1] then SetWaypoint(plan.route[1], true) end
    NS.UpdateTargetButton()
    Refresh()
end

-- dismiss the sell/repair stop: gone now, and not suggested again for 20 minutes
function NS.DismissService()
    NS.SnoozeService(20)
    if plan and plan.route then
        for i = #plan.route, 1, -1 do if plan.route[i].kind == "service" then table.remove(plan.route, i) end end
        plan.service = nil
        if NS.db.autoWay and plan.route[1] and not InCombatLockdown() then SetWaypoint(plan.route[1], true) end
        NS.UpdateTargetButton()
    end
    NS.Print("sell & repair skipped for 20 minutes.")
    Refresh()
end

------------------------------------------------------------------------
-- Live progress: counts on the card follow the quest log right away (even mid-fight), without
-- waiting for the next full plan; finished objectives drop off.
------------------------------------------------------------------------
local function ObjNeed(lo)
    if NS.safe(lo.finished) then return 0 end
    return (tonumber(NS.safe(lo.numRequired)) or 1) - (tonumber(NS.safe(lo.numFulfilled)) or 0)
end
function NS.LiveProgress()
    if not plan or not plan.route or not NS.LogKeys then return end
    local changed, logs = false, {}
    for i = #plan.route, 1, -1 do
        local s = plan.route[i]
        local id = s.q and s.q.id
        if s.role == 2 and id and (s.key or s.kind == "todo") and not s.help then
            logs[id] = logs[id] or { NS.LogKeys(id) }
            local keyed, list = logs[id][1], logs[id][2]
            local complete = C_QuestLog.IsComplete and NS.safe(C_QuestLog.IsComplete(id))
            local drop = false
            if complete then
                drop = true
            elseif s.kind == "todo" and list and s.todoBases then
                local left = {}
                for _, lo in ipairs(list) do
                    local txt = NS.safe(lo.text)
                    if txt and ObjNeed(lo) > 0 then
                        local base = NS.ObjBase(txt)
                        for _, b in ipairs(s.todoBases) do if b == base then left[#left + 1] = txt; break end end
                    end
                end
                if #left == 0 then drop = true else
                    local t = "Finish: " .. table.concat(left, ", ")
                    if t ~= s.text then s.text, changed = t, true end
                end
            elseif s.key and keyed and keyed[s.key] then
                local need = ObjNeed(keyed[s.key])
                if need <= 0 then drop = true
                elseif need ~= s.need then s.need, changed = need, true end
            end
            if drop then table.remove(plan.route, i); changed = true; if complete then NS.RequestPlan() end end
        end
    end
    if changed then
        if not InCombatLockdown() then
            if NS.db.autoWay and plan.route[1] then SetWaypoint(plan.route[1], true) end
            NS.UpdateTargetButton()
        end
        Refresh()
    end
end

------------------------------------------------------------------------
-- Live distance: the next step's yards update every time you move 1 yard
------------------------------------------------------------------------
-- yards to the step: 0 when one of its mobs is right there (your target or a nameplate),
-- else the nearest place they spawn - not the middle of the area the plan picked
local function MobHere(names)
    if not names then return false end
    local function hit(u)
        if not UnitExists(u) or UnitIsDead(u) then return false end
        local n = NS.safe(UnitName(u))
        return n ~= nil and names[n] == true
    end
    if hit("target") or hit("mouseover") then return true end
    for i = 1, 40 do
        local u = "nameplate" .. i
        if UnitExists(u) and hit(u) then return true end
    end
    return false
end
local nearestAt = setmetatable({}, { __mode = "k" })
function NS.LiveDistance(s, px, py)
    if MobHere(s.mobNames) then return 0 end
    local best = NS.Dist(px, py, s.x, s.y)
    local pts = s.points
    if pts and #pts > 0 then
        -- the full scan is cheap but there's no need to do it 20 times a second
        local now = GetTime()
        local c = nearestAt[s]
        if not c or now - c.t > 0.25 or NS.Dist(px, py, c.px, c.py) > 10 then
            local step = math.max(1, math.floor(#pts / 600))
            local d = math.huge
            for i = 1, #pts, step do
                local p = pts[i]
                local dd = NS.Dist(px, py, p.x, p.y)
                if dd < d then d = dd end
            end
            c = { t = now, px = px, py = py, d = d }
            nearestAt[s] = c
        end
        best = math.min(best, c.d)
    end
    return best
end

local live = CreateFrame("Frame")
local liveAcc, lastYd = 0, nil
live:SetScript("OnUpdate", function(_, e)
    liveAcc = liveAcc + e
    if liveAcc < 0.05 then return end
    liveAcc = 0
    if not (frame and frame:IsShown() and plan and NS.Bridge and NS.Bridge()) then return end
    local first = plan.route and plan.route[1]
    if not first or not first.x or first.kind == "todo" then return end
    local ok, px, py, inst = pcall(NS.PlayerPos)
    if not ok or not px then return end
    if plan.inst and inst and plan.inst ~= inst then return end
    local yd = math.floor(NS.LiveDistance(first, px, py) + 0.5)
    if yd == lastYd and first.dist == yd then return end
    lastYd = yd
    first.dist = yd
    if frame.card.step == first then
        local _, _, _, sub = StepParts(first)
        frame.card.sub:SetText(S.Color("muted", sub))
    end
end)

local liveQueued
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "MERCHANT_CLOSED", "GROUP_ROSTER_UPDATE",
    "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING", "BAG_UPDATE_DELAYED", "QUEST_WATCH_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        Build()
        MakeTargetButton()
        C_Timer.NewTicker(1, Tick)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if targetDirty then NS.UpdateTargetButton() end
        return
    end
    if event == "MERCHANT_CLOSED" then
        -- you've been to a vendor: if your bags are still full it's not junk, so stop asking
        NS.SnoozeService(20)
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
    if event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_WATCH_UPDATE" then
        -- the log can lag the event a moment: look now and again shortly after
        pcall(NS.LiveProgress)
        if not liveQueued then
            liveQueued = true
            C_Timer.After(0.5, function() liveQueued = nil; pcall(NS.LiveProgress) end)
        end
    end
    if event == "QUEST_ACCEPTED" then
        Done(a2 or a1, 1)          -- older clients pass (logIndex, questID)
    elseif event == "QUEST_TURNED_IN" then
        Done(a1, 3)
    elseif event == "QUEST_REMOVED" then
        wantFull = true
    end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
function NS.ShareAllCmd()
    local n, why, skipped = NS.ShareAll()
    skipped = skipped or 0
    local note = skipped > 0 and (" - skipped %d the whole group already has"):format(skipped) or ""
    if why then NS.Print(why .. ".")
    elseif n == 0 then NS.Print((skipped > 0 and "everyone already has your shareable quests" or "none of your quests can be shared") .. ".")
    else NS.Print(("sharing %d quest%s with your party (one every 0.5s)%s."):format(n, n == 1 and "" or "s", note)) end
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

-- class quests (Questie's requiredClasses, or the game's class tag)
local function IsClassQuest(id)
    local rc = NS.Q and NS.Q(id, "requiredClasses")
    if type(rc) == "number" and rc > 0 then return true end
    if C_QuestLog.GetQuestTagInfo then
        local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, id)
        local t = ok and type(tag) == "table" and NS.safe(tag.tagID)
        if t == 21 then return true end   -- class quest tag
    end
    return false
end
NS.IsClassQuest = IsClassQuest

-- quests Drop All keeps unless you shift-click: dungeon, raid and class quests
local function IsKeptQuest(id) return IsDungeonQuest(id) or IsClassQuest(id) end

-- the quests Drop All would remove: everything, or everything but dungeon/raid/class quests
local function DropList(withDungeons)
    local ids, kept, done = {}, 0, 0
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        local id = info and NS.safe(info.questID)
        if id and id > 0 and not NS.safe(info.isHeader) then
            if not withDungeons and IsKeptQuest(id) then
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
            kept > 0 and (", kept %d dungeon/class quest%s (shift-click Drop All to drop those too)"):format(kept, kept == 1 and "" or "s") or ""))
        NS.cache = nil
        NS.Replan()
    end,
}

-- Drop All keeps dungeon, raid and class quests; shift-click drops those too
function NS.DropAllCmd(withDungeons)
    if NS.KeepAllQuests and NS.KeepAllQuests() then
        NS.Print("you're synced with your party - TwizQuest never removes quests while synced. Leave the group or /tq party off first.")
        return
    end
    if withDungeons == nil then withDungeons = IsShiftKeyDown() end
    local ids, kept, done = DropList(withDungeons)
    if #ids == 0 then
        NS.Print(kept > 0 and ("only dungeon/class quests left (%d) - shift-click Drop All to drop them."):format(kept)
            or "your quest log is already empty.")
        return
    end
    local notes = ""
    if withDungeons then notes = notes .. "\n|cffff9933Including dungeon and class quests.|r"
    elseif kept > 0 then notes = notes .. ("\nKeeping %d dungeon/class quest%s."):format(kept, kept == 1 and "" or "s") end
    if done > 0 then notes = notes .. ("\n|cffff5555%d of them are complete and ready to turn in!|r"):format(done) end
    local dialog = StaticPopup_Show("TWIZQUEST_ABANDON_ALL", #ids, notes)
    if dialog then dialog.data = withDungeons end
end

local function Help()
    NS.Print("commands:")
    print("  /tq              - show or hide the route window")
    print("  /tq plan         - re-plan now (it also updates by itself)")
    print("  /tq unskip       - bring back quests skipped (right-click a step, or ones a giver didn't offer)")
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
    print("  /tq dropall      - abandon every quest except dungeon and class quests, asks first (Drop All button)")
    print("  /tq dropall dungeons - same, including dungeon and class quests (shift-click Drop All)")
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
                local xp = p.xp and ("L%d %d/%d XP"):format(p.xp.level or 0, p.xp.cur or 0, p.xp.max or 0) or "no XP received yet"
                print(("  %s: %d quests, %s%s"):format(m, NS.Count(p.quests), xp, p.step and (", heading to " .. p.step.text) or ""))
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
    elseif cmd == "unskip" then NS.UnskipAll(); NS.Print("skipped quests are back in the plan.")
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
