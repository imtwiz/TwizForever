-- TwizCraft window: steps to level the selected profession and a shopping list.
local ADDON, NS = ...

local STEP_ROWS, SHOP_ROWS, ROW_H = 30, 30, 17
local frame, stepRows, shopRows, tabs = nil, {}, {}, {}
local routeRows, ROUTE_ROWS = {}, 10
local nowRows, NOW_ROWS = {}, 12
local plan, why

local COLOR = { orange = "ff8040", yellow = "ffff00", green = "40bf40", gray = "808080" }
local SRC_TEXT = {
    vendor = "|cff40c0ffvendor|r", AH = "|cffffd100AH|r", craft = "|cff40ff40craft|r", farm = "|cffff8040gather|r",
}

local function Colored(s, r)
    return ("|cff%s%d|r"):format(COLOR[NS.Color(r, s)], s)
end

local function Selected()
    local c = NS.Char()
    if NS.current and c.profs[NS.current] then return NS.current end
    if NS.current then
        for _, p in ipairs(NS.Professions()) do
            if p.line == NS.current then
                local k = NS.ResolveLine(p.line, p.name)
                if c.profs[k] then return k end
            end
        end
    end
    for _, p in ipairs(NS.Professions()) do
        local k = NS.ResolveLine(p.line, p.name)
        if k and c.profs[k] then return k end
    end
    for line in pairs(c.profs) do return line end
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local function Refresh()
    if not frame or not frame:IsShown() then return end
    -- profession tabs
    local profs, i = NS.Professions(), 0
    local c = NS.Char()
    for _, p in ipairs(profs) do
        i = i + 1
        local b = tabs[i]
        if not b then
            b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            b:SetSize(100, 20)
            b:SetPoint("TOPLEFT", 10 + (i - 1) * 104, -28)
            tabs[i] = b
        end
        local line = p.line
        b:SetText(("%s %d"):format(p.name, p.skill))
        b:SetEnabled(line ~= NS.current)
        local resolved = NS.ResolveLine(line, p.name)
        b:SetEnabled(resolved ~= NS.current)
        b:SetScript("OnClick", function() NS.current = resolved; NS.Replan(true) end)
        b:SetAlpha(c.profs[resolved] and 1 or 0.6)
        b:Show()
    end
    for j = i + 1, #tabs do tabs[j]:Hide() end

    for _, r in ipairs(stepRows) do r:Hide() end
    for _, r in ipairs(shopRows) do r:Hide() end
    for _, r in ipairs(routeRows) do r:Hide() end
    for _, r in ipairs(nowRows) do r:Hide() end
    if frame.nowTitle then frame.nowTitle:Hide() end
    frame.shopTitle:Hide()
    frame.routeTitle:Hide()
    frame.buyBtn:Hide()

    if not plan then
        frame.summary:SetText(why or "Open a profession window once so I can read your recipes.")
        if not NS.db.sized then frame:SetHeight(90) end
        return
    end
    if plan.done then
        frame.summary:SetText(("%s %d/%d - at your cap. Train the next rank to keep going (/cr target to set a goal)."):format(
            plan.name, plan.skill, plan.max))
        if not NS.db.sized then frame:SetHeight(90) end
        return
    end

    frame.summary:SetText(("|cffffd100%s|r %d -> %d:  ~%d crafts, ~%s net, ~%s crafting%s"):format(
        plan.name, plan.skill, plan.target, plan.crafts, NS.Money(plan.cost), NS.FormatTime(plan.time),
        plan.stuck and ("  |cffff4040(no recipe past " .. plan.stuck .. " - learn new ones)|r") or ""))

    -- how many rows fit: your chosen height split between steps and shopping,
    -- or the defaults (12 steps, 10 items) when you haven't resized
    local okR, route = pcall(NS.ShoppingRoute, plan)
    route = okR and route or {}
    local makeNow = plan.makeNow or {}
    local stepCap, shopCap, routeCap, nowCap = NS.db.steps or 12, 10, 6, 10
    if NS.db.sized then
        local total = math.max(6, math.floor((frame:GetHeight() - 76 - 22 - 22 - 22 - 20 - 30) / ROW_H))
        nowCap = math.min(#makeNow, math.max(1, math.floor(total * 0.15)))
        total = total - nowCap
        routeCap = math.min(#route, math.max(2, math.floor(total * 0.25)))
        local shopWant = math.min(#plan.shop, math.max(3, math.floor(total * 0.35)))
        stepCap = math.min(#plan.steps, math.max(1, total - shopWant - routeCap))
        shopCap = math.max(0, total - stepCap - routeCap)
    end
    stepCap, shopCap = math.min(stepCap, STEP_ROWS), math.min(shopCap, SHOP_ROWS)
    routeCap = math.min(routeCap, ROUTE_ROWS)
    nowCap = math.min(nowCap, NOW_ROWS)

    local y = -76
    for k = 1, math.min(#plan.steps, stepCap) do
        local st = plan.steps[k]
        local row = stepRows[k]
        row.data = st
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, y)
        row.left:SetText(("%s-%s"):format(Colored(st.from, st.r), Colored(st.to, st.r)))
        row.mid:SetText(("%s%s x%d"):format(st.learn and "|cff40c0ff[learn]|r " or "", st.r.name, st.n))
        row.right:SetText(NS.Money(st.cost))
        row:Show()
        y = y - ROW_H
    end

    -- what you can make right now from your bags
    if #makeNow > 0 and nowCap > 0 then
        y = y - 6
        frame.nowTitle:ClearAllPoints(); frame.nowTitle:SetPoint("TOPLEFT", 12, y)
        frame.nowTitle:SetText("Make now from your bags  |cff999999(click to craft)|r")
        frame.nowTitle:Show()
        y = y - 16
        for k = 1, math.min(#makeNow, nowCap) do
            local m = makeNow[k]
            local row = nowRows[k]
            row.data = m
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, y)
            row.left:SetText(("x%d"):format(m.n))
            row.mid:SetText(("|cff%s%s|r  |cff999999%s|r"):format(COLOR[m.color], m.r.name, m.why))
            row.right:SetText(("|cff%s%s|r"):format(COLOR[m.color], m.color))
            row:Show()
            y = y - ROW_H
        end
    end

    y = y - 6
    frame.shopTitle:ClearAllPoints(); frame.shopTitle:SetPoint("TOPLEFT", 12, y)
    local subNote = ""
    if plan.subcrafts and #plan.subcrafts > 0 then
        local parts = {}
        for _, sc in ipairs(plan.subcrafts) do parts[#parts + 1] = ("%s%d %s"):format(sc.learn and "[learn] " or "", sc.n, sc.name) end
        subNote = "  |cff40ff40make first: " .. table.concat(parts, ", ") .. "|r"
    end
    frame.shopTitle:SetText(("Shopping list  (buy ~%s)%s"):format(NS.Money(plan.buyCost), subNote))
    frame.shopTitle:Show()
    y = y - 16
    for k = 1, math.min(#plan.shop, shopCap) do
        local e = plan.shop[k]
        local row = shopRows[k]
        row.data = e
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, y)
        local have = e.bags + e.bank + (e.mail or 0)
        row.left:SetText(e.buy > 0 and ("|cffffffff%d|r"):format(e.buy) or "|cff40ff40ok|r")
        local where = {}
        if e.bank > 0 then where[#where + 1] = e.bank .. " in bank" end
        if (e.mail or 0) > 0 then where[#where + 1] = "|cffffd100" .. e.mail .. " in mailbox|r" end
        row.mid:SetText(("%s  |cff999999need %d, have %d%s|r"):format(NS.ItemLink(e.id), e.need, have,
            #where > 0 and (" (" .. table.concat(where, ", ") .. "|cff999999)") or ""))
        row.right:SetText(e.buy > 0 and (SRC_TEXT[e.src] .. " " .. NS.Money(e.cost)) or "")
        row:Show()
        y = y - ROW_H
    end

    -- the cheapest shopping route
    if #route > 0 and routeCap > 0 then
        y = y - 6
        frame.routeTitle:ClearAllPoints(); frame.routeTitle:SetPoint("TOPLEFT", 12, y)
        frame.routeTitle:SetText("Cheapest route  |cff999999(click a stop for a waypoint)|r")
        frame.routeTitle:Show()
        y = y - 16
        for k = 1, math.min(#route, routeCap) do
            local s = route[k]
            local row = routeRows[k]
            row.data = s
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, y)
            row.left:SetText(k .. ".")
            local names = {}
            for i, it in ipairs(s.items) do
                if i > 3 then names[#names + 1] = "..."; break end
                names[#names + 1] = ("%d %s"):format(it.n, NS.ItemName(it.id))
            end
            row.mid:SetText(("|cffffd100%s|r%s"):format(s.label, #names > 0 and ("  |cff999999" .. table.concat(names, ", ") .. "|r") or ""))
            row.right:SetText((s.dist and ("%d yd  "):format(s.dist) or "") .. ((s.cost or 0) > 0 and NS.Money(s.cost) or ""))
            row:Show()
            y = y - ROW_H
        end
    end

    -- buy button: at a vendor or the AH
    local text
    if NS.merchantOpen and NS.VendorBusy and NS.VendorBusy() then
        text = "Buying..."
    elseif NS.merchantOpen then
        local cart, total = NS.VendorCart(plan)
        if #cart > 0 then text = ("Buy %d item%s here for %s"):format(#cart, #cart == 1 and "" or "s", NS.Money(total)) end
    elseif NS.ahOpen then
        text = NS.AHButtonText(plan)
    end
    if text then
        y = y - 6
        frame.buyBtn:ClearAllPoints(); frame.buyBtn:SetPoint("BOTTOMLEFT", 10, 8)
        frame.buyBtn:SetWidth(math.min(frame:GetWidth() - 40, 420))
        frame.buyBtn:SetText(text)
        frame.buyBtn:Show()
        y = y - 26
    end
    if not NS.db.sized then frame:SetHeight(-y + 16) end
end
NS.RefreshUI = function() Refresh() end

-- widths follow the window
local function Layout()
    if not frame then return end
    local w = frame:GetWidth()
    for _, list in ipairs({ stepRows, shopRows, routeRows, nowRows }) do
        for _, row in ipairs(list) do
            row:SetWidth(w - 20)
            row.mid:SetWidth(math.max(100, w - 20 - 64 - 115))
        end
    end
end

local function StepTooltip(row)
    local st = row.data
    if not st then return end
    local r = st.r
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if r.out then GameTooltip:SetItemByID(r.out) else GameTooltip:AddLine(r.name) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Skill colors: |cff%s%d|r |cff%s%d|r |cff%s%d|r |cff%s%d|r%s"):format(
        COLOR.orange, r.orange, COLOR.yellow, r.yellow, COLOR.green, r.green, COLOR.gray, r.gray,
        r.guess and "  (estimated)" or ""), 1, 1, 1)
    GameTooltip:AddDoubleLine("Skill-up chance", ("%d%% at %d -> %d%% at %d"):format(
        NS.Chance(r, st.from) * 100, st.from, NS.Chance(r, st.to - 1) * 100, st.to - 1), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Crafts (expected)", ("%d  (~%s)"):format(st.n, NS.FormatTime(st.time)), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Each craft uses:", 1, 0.82, 0)
    for _, g in ipairs(r.reagents) do
        local unit, src = NS.UnitCost(g.id)
        GameTooltip:AddDoubleLine(("  %d x %s"):format(g.qty, NS.ItemName(g.id)),
            ("%s  %s"):format(SRC_TEXT[src] or src, NS.Money(unit * g.qty)), 1, 1, 1, 1, 1, 1)
    end
    local cost, mats, resale = NS.CraftCost(r)
    GameTooltip:AddDoubleLine("Materials", NS.Money(mats), 1, 1, 1, 1, 1, 1)
    if resale > 0 then GameTooltip:AddDoubleLine("Sell the result back", "-" .. NS.Money(resale), 1, 1, 1, 0.4, 1, 0.4) end
    GameTooltip:AddDoubleLine("Net per craft", NS.Money(cost), 1, 1, 1, 1, 1, 1)
    if st.learn then GameTooltip:AddLine("Learn this recipe from your trainer first.", 0.4, 0.8, 1, true) end
    GameTooltip:AddLine("Click: craft as many as your materials allow (up to " .. st.n .. ").", 0.5, 0.8, 1, true)
    GameTooltip:AddLine("Shift-click: craft one.  Right-click: stop.", 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function ShopTooltip(row)
    local e = row.data
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(e.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Needed", e.need, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("In bags / bank", ("%d / %d"):format(e.bags, e.bank), 1, 1, 1, 1, 1, 1)
    if e.buy > 0 then
        local where = ({ vendor = "Vendor", AH = "Auction House", craft = "Craft it", farm = "Gather or farm it" })[e.src]
        if e.src == "vendor" and e.extra and e.extra.est then
            GameTooltip:AddLine("Vendor price estimated - it'll be exact once you visit the vendor.", 0.7, 0.7, 0.7, true)
        end
        if e.src == "vendor" and e.extra and e.extra.npc then
            where = ("Vendor: %s (%s)"):format(e.extra.npc, e.extra.zone or "?")
        end
        GameTooltip:AddDoubleLine("Get", ("%d from %s"):format(e.buy, where), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Cost", ("%s (%s each)"):format(NS.Money(e.cost), NS.Money(e.unit)), 1, 1, 1, 1, 1, 1)
        if e.src == "farm" then
            GameTooltip:AddLine("No vendor or AH price known - the cost is a rough guess. A TwizAH AH scan will price it.", 1, 0.5, 0.25, true)
        end
    end
    if e.via then GameTooltip:AddLine("For crafting: " .. e.via, 0.4, 1, 0.4) end
    if e.buy > 0 and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        GameTooltip:AddLine("Click to search the AH for it.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function MakeRow(onEnter, onClick)
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(500, ROW_H)
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT"); row.left:SetWidth(62); row.left:SetJustifyH("LEFT")
    row.mid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mid:SetPoint("LEFT", 64, 0); row.mid:SetWidth(330); row.mid:SetJustifyH("LEFT"); row.mid:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT"); row.right:SetJustifyH("RIGHT")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", onClick)
    row:Hide()
    return row
end

local function Build()
    frame = CreateFrame("Frame", "TwizCraftFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 90)
    frame:SetPoint("LEFT", UIParent, "LEFT", 40, 60)
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
        frame:SetBackdropColor(0, 0, 0, 0.85)
    end
    if NS.db.pos then
        frame:ClearAllPoints()
        frame:SetPoint(NS.db.pos[1], UIParent, NS.db.pos[2], NS.db.pos[3], NS.db.pos[4])
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8); title:SetText("TwizCraft")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() frame:Hide(); NS.db.shown = false end)
    local nextBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextBtn:SetSize(80, 18); nextBtn:SetPoint("TOPRIGHT", -28, -6)
    nextBtn:SetText("Craft next")
    nextBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nextBtn:SetScript("OnClick", function(_, button) NS.CraftNext(button) end)
    nextBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Craft next")
        GameTooltip:AddLine("Makes the next thing on the plan: anything you need to make first, then step 1.", 1, 1, 1, true)
        GameTooltip:AddLine("Bind a key: Options > Keybindings > AddOns > TwizCraft.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    nextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local allBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allBtn:SetSize(64, 18); allBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    allBtn:SetText("Craft All")
    allBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    allBtn:SetScript("OnClick", function(_, button) NS.CraftAll(button) end)
    allBtn:EnableMouseWheel(true)
    allBtn:SetScript("OnMouseWheel", function() NS.CraftAll() end)
    allBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Craft All")
        local q, grays = NS.CraftAllQueue(IsShiftKeyDown())
        if #q == 0 then
            GameTooltip:AddLine(#grays > 0 and ("Only gray recipes (no skill-ups): " .. table.concat(grays, ", ") .. ". Shift-click to make them anyway.")
                or "Nothing you can craft with what's in your bags right now.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Crafts everything you can make now in the open profession - plan first, then anything else that still gives skill-ups:", 1, 1, 1, true)
            for _, e in ipairs(q) do
                local can = math.huge
                for _, g in ipairs(e.r.reagents) do can = math.min(can, math.floor(NS.SlotBags(g) / math.max(1, g.qty))) end
                GameTooltip:AddDoubleLine(e.r.name, ("x%d"):format(math.min(can, e.want or can)), 1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("Each press crafts a whole batch of one recipe. The game needs a new click to start the next one - press again, or spin your mouse wheel while the profession window is open.", 0.4, 1, 0.4, true)
        GameTooltip:AddLine("Shift-click: include gray recipes too. Right-click: stop. Bind a key in Options > Keybindings > AddOns.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    allBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(64, 18); refresh:SetPoint("RIGHT", allBtn, "LEFT", -4, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() NS.RefreshAll() end)
    refresh:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Refresh")
        GameTooltip:AddLine("Re-reads your recipes (if a profession window is open), your bags and prices, then re-plans.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refresh:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", 12, -56); frame.summary:SetPoint("RIGHT", -10, 0)
    frame.summary:SetJustifyH("LEFT")
    frame.shopTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.routeTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.nowTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.buyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.buyBtn:SetSize(300, 22)
    frame.buyBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.buyBtn:SetScript("OnClick", function(_, button)
        if NS.merchantOpen then NS.BuyFromVendor(plan)
        elseif NS.ahOpen then NS.AHClick(plan, button) end
        Refresh()
    end)
    frame.buyBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if NS.ahOpen then
            GameTooltip:AddLine("Buy on the Auction House")
            GameTooltip:AddLine("Click once to get the live price, click again to confirm. The game needs a click for each purchase.", 1, 1, 1, true)
            GameTooltip:AddLine("Red means the price is over 50% above what TwizAH last saw.", 1, 0.4, 0.4, true)
            GameTooltip:AddLine("Right-click to skip this item.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Buy everything this vendor sells from your list, one purchase at a time.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame.buyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.buyBtn:Hide()

    for k = 1, STEP_ROWS do
        stepRows[k] = MakeRow(StepTooltip, function(self, button)
            NS.CraftStep(self.data, plan, button)
        end)
    end
    for k = 1, NOW_ROWS do
        nowRows[k] = MakeRow(function(self)
            local m = self.data
            if not m then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if m.r.out then GameTooltip:SetItemByID(m.r.out) else GameTooltip:AddLine(m.r.name) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("You can make %d now. %s"):format(m.n, m.why:gsub("^%l", string.upper)), 1, 1, 1, true)
            GameTooltip:AddLine(("Skill colors: |cff%s%d|r |cff%s%d|r |cff%s%d|r |cff%s%d|r%s"):format(
                COLOR.orange, m.r.orange, COLOR.yellow, m.r.yellow, COLOR.green, m.r.green, COLOR.gray, m.r.gray,
                m.r.guess and "  (estimated)" or ""), 1, 1, 1)
            GameTooltip:AddLine("Click: craft them all.  Shift-click: one.  Right-click: stop.", 0.5, 0.8, 1, true)
            GameTooltip:Show()
        end, function(self, button)
            local m = self.data
            if m and plan then NS.CraftRecipeNow(plan.line, m.id, m.r, m.n, plan.name, button) end
        end)
    end
    for k = 1, ROUTE_ROWS do
        routeRows[k] = MakeRow(function(self)
            local s = self.data
            if not s then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(s.label, 1, 0.82, 0)
            for _, it in ipairs(s.items) do
                GameTooltip:AddLine(("  %d x %s"):format(it.n, NS.ItemName(it.id)), 1, 1, 1)
            end
            if (s.cost or 0) > 0 then GameTooltip:AddDoubleLine("Cost", NS.Money(s.cost), 1, 1, 1, 1, 1, 1) end
            if s.dist then GameTooltip:AddDoubleLine("Distance", ("%d yd"):format(s.dist), 1, 1, 1, 1, 1, 1) end
            if s.map then GameTooltip:AddLine("Click for a waypoint", 0.5, 0.8, 1) end
            if s.kind == "make" then
                GameTooltip:AddLine("Click to craft as many as you can, shift-click for one, right-click to stop.", 0.5, 0.8, 1, true)
            end
            GameTooltip:Show()
        end, function(self, button)
            local s = self.data
            if s and s.kind == "make" then NS.CraftSub(s.sub, button) else NS.Waypoint(s) end
        end)
    end
    for k = 1, SHOP_ROWS do
        shopRows[k] = MakeRow(ShopTooltip, function(self)
            local e = self.data
            local bar = AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar
            if e and bar and bar.SearchBox then
                bar.SearchBox:SetText(NS.ItemName(e.id))
                if bar.StartSearch then pcall(bar.StartSearch, bar) end
            end
        end)
    end
    local resizing
    NS.resetSize = NS.MakeResizable(frame, NS.db, {
        minW = 440, minH = 120, maxW = 1400, maxH = 1100, defaultW = 520, defaultH = 90, savePos = true,
        onResize = function()
            if resizing then return end
            resizing = true; Layout(); Refresh(); resizing = false
        end })
    Layout()
    if not NS.db.shown then frame:Hide() end
end

------------------------------------------------------------------------
-- Re-planning (cheap: runs in a few milliseconds)
------------------------------------------------------------------------
function NS.RefreshAll()
    local n = NS.Capture and NS.Capture()
    if n then
        NS.Print(("re-read %d recipes and re-planned."):format(n))
    else
        NS.Print("re-planned. (Open the profession window and click Refresh to re-read its recipes too.)")
    end
    NS.Replan(true)
end

local queued
-- plan right now (Craft All uses this so its batches match your current bags)
function NS.PlanNow()
    local line = NS.current or Selected()
    if not line then return end
    local ok, p, w = pcall(NS.PlanFor, line)
    if ok and p then plan, why = p, w; NS.currentPlan = plan end
end

function NS.Replan(now)
    if not NS.db or not frame then return end
    if queued and not now then return end
    queued = true
    C_Timer.After(now and 0 or 1, function()
        queued = false
        local line = Selected()
        NS.current = line
        if line then
            local ok, p, w = pcall(NS.PlanFor, line)
            if ok then plan, why = p, w else plan, why = nil, "Error: " .. tostring(p) end
            NS.currentPlan = plan
        else
            plan, why = nil, "Open any profession window once so I can read your recipes."
        end
        Refresh()
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    Build()
    C_Timer.After(2, function() NS.Replan(true) end)
end)

SLASH_CRAFTROUTE1 = "/cr"
SLASH_CRAFTROUTE2 = "/twizcraft"
SLASH_CRAFTROUTE3 = "/craftroute"
SlashCmdList.CRAFTROUTE = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local n = tonumber(rest)
    if cmd == "" then
        if frame:IsShown() then frame:Hide(); NS.db.shown = false
        else frame:Show(); NS.db.shown = true; NS.Replan(true) end
    elseif cmd == "craftall" or cmd == "all" then
        NS.CraftAll()
    elseif cmd == "wheel" then
        NS.db.wheelCraft = NS.db.wheelCraft == false
        NS.Print("mouse wheel = Craft All while a profession window is open: " .. (NS.db.wheelCraft and "on" or "off"))
        NS.UpdateCraftWheel()
    elseif cmd == "refresh" then
        NS.RefreshAll()
    elseif cmd == "find" then
        NS.Find(rest)
    elseif cmd == "buy" then
        if NS.merchantOpen then NS.BuyFromVendor(plan) else NS.Print("open a vendor first (AH purchases need the button: one click per purchase).") end
    elseif cmd == "size" or cmd == "scale" then
        NS.resetSize(); NS.Print("window size reset")
    elseif cmd == "target" then
        NS.db.target = NS.db.target or {}
        if NS.current then NS.db.target[NS.current] = n end
        NS.Print(n and ("target for this profession: " .. n) or "target cleared (plans to your cap)")
        NS.Replan(true)
    elseif cmd == "resell" then
        NS.db.resellAH = not NS.db.resellAH
        NS.Print("count AH resale of crafted items: " .. (NS.db.resellAH and "on" or "off (vendor value only)"))
        NS.Replan(true)
    elseif cmd == "odds" then
        local o = NS.db.odds
        NS.Print(("skill-ups seen: yellow %d of %.0f expected, green %d of %.0f expected"):format(
            o.yellow.a, o.yellow.p, o.green.a, o.green.p))
    else
        NS.Print("commands:")
        print("  /cr            show or hide the window")
        print("  /cr craftall   craft the next batch of everything you can make (Craft All button)")
        print("  /cr wheel      mouse wheel presses Craft All while a profession window is open (on)")
        print("  /cr target 225 plan up to this skill instead of your cap (/cr target to clear)")
        print("  /cr resell     count AH resale of what you craft (default: vendor value)")
        print("  /cr odds       skill-up odds learned from your crafting")
        print("  /cr buy        at a vendor: buy everything on your list it sells")
        print("  /cr refresh    re-read recipes (profession window open) and re-plan")
        print("  /cr find fish  everything TwizCraft knows about matching recipes/ingredients")
        print("  /cr size       reset the window size (drag the bottom-right corner to resize)")
    end
end

------------------------------------------------------------------------
-- /cr find <text>: what TwizCraft knows about matching recipes, and why
-- each one is or isn't showing
------------------------------------------------------------------------
function NS.Find(text)
    text = (text or ""):lower()
    local c = NS.Char()
    if not next(c.profs) then
        NS.Print("no recipes recorded yet - open a profession window, then click Refresh.")
        return
    end
    if text == "" then
        NS.Print("recorded professions:")
        for line, p in pairs(c.profs) do print(("  %s (id %s): %d recipes"):format(p.name, tostring(line), p.count or 0)) end
        for _, p in ipairs(NS.Professions()) do print(("  you have %s %d/%d (id %s)"):format(p.name, p.skill, p.max, tostring(p.line))) end
        return
    end
    local found = 0
    for line, p in pairs(c.profs) do
        local skill = NS.SkillFor(line, p.name) or 0
        for id, r in pairs(p.recipes) do
            local hit = r.name:lower():find(text, 1, true)
            for _, g in ipairs(r.reagents) do
                for _, aid in ipairs(g.alts or { g.id }) do
                    if NS.ItemName(aid):lower():find(text, 1, true) then hit = true end
                end
            end
            if hit then
                found = found + 1
                local color = NS.Color(r, skill)
                print(("|cffffd100%s|r (%s, recipe %d): %s, colors %d/%d/%d/%d%s, you're at %d -> %s"):format(
                    r.name, p.name, id, r.learned and "learned" or "|cffff4040not learned|r",
                    r.orange, r.yellow, r.green, r.gray, r.guess and " (estimated)" or "", skill, color))
                local can = math.huge
                for _, g in ipairs(r.reagents) do
                    local have = NS.SlotBags(g)
                    can = math.min(can, math.floor(have / math.max(1, g.qty)))
                    local names = {}
                    for _, aid in ipairs(g.alts or { g.id }) do names[#names + 1] = NS.ItemName(aid) end
                    print(("   needs %d %s - you have %d in bags"):format(g.qty, table.concat(names, " or "), have))
                end
                print(("   you can make %d now"):format(can == math.huge and 0 or can))
            end
        end
    end
    if found == 0 then
        NS.Print(("no recorded recipe or ingredient matches '%s'. Open that profession's window and click Refresh."):format(text))
    end
end
