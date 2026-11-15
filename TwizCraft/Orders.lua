-- TwizCraft craft orders: ask a friend in your group to craft something.
--
-- You (the asker): click a friend's recipe in the Friends' crafting window,
-- pick how many, stand near them and click "Trade mats". TwizCraft tells their
-- TwizCraft what you want, opens a trade and puts the materials in it - you
-- click Trade. If the trade doesn't go through, click the button again.
--
-- Your friend (the crafter): gets a TwizCraft popup with the order. Once the
-- materials arrive it shows "Craft", then "Trade to <you>", which opens a trade
-- with the crafted items already in it.
--
-- The game needs a click to start a trade, accept it and craft, so each of
-- those is a button press. Recipes that make bind-on-pickup items can't be
-- asked for: the result couldn't be traded back.
--
-- Messages (party channel, addressed by name):
--   Q|crafter|id|line|recipe|count   ask for a craft
--   S|crafter|id                     materials traded
--   X|other|id                       cancelled / declined / trade failed
--   D|asker|id                       crafted items traded back
local ADDON, NS = ...

local TRADE_SLOTS = 6
local req   -- asking side: { id, crafter, line, recipe, out, made, n, need = { {id, qty} }, name, stage }
local order -- crafting side: { id, from, line, recipe, n, name, out, made, stage, before }

-- automatic: trades accepted, items crafted and sent back by themselves (/tc orders manual to turn off)
local function Auto() return not NS.db or NS.db.ordersAuto ~= false end
local function Me() return NS.safe and NS.safe(UnitName("player")) or UnitName("player") end
local function IsMe(name) return name and NS._nameFits(name, Me()) or false end
local function ItemName(id) return (NS.ItemName and NS.ItemName(id)) or C_Item.GetItemInfo(id) or ("item " .. id) end

local function UnitFor(name)
    for _, m in ipairs(NS._partyRoster()) do
        if m.name == name or NS._nameFits(name, m.name) then return m.unit end
    end
end
local function InRange(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if CheckInteractDistance then
        local ok, near = pcall(CheckInteractDistance, unit, 2) -- 2 = trade distance
        return ok and near and true or false
    end
    return true
end
local function TradePartner()
    local n = UnitName("NPC")
    if n then return n end
    return TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
end
local function BagCount(id) return C_Item.GetItemCount(id, false) or 0 end

-- bind-on-pickup results can't be traded back, so they can't be ordered.
-- Returns true (BoP), false (tradeable) or nil (item not loaded yet).
local function IsBoP(itemID)
    if not itemID or itemID == 0 then return nil end
    local info = { C_Item.GetItemInfo(itemID) }
    if not info[1] then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    local bind = info[14]
    local BOP = (Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire) or 1
    return bind == BOP or bind == 1
end
NS.IsBoP = IsBoP

------------------------------------------------------------------------
-- Putting items into the trade window, one stack per slot
------------------------------------------------------------------------
local placing
local function PlaceItems(list, done)
    local steps, slot = {}, 0
    for _, want in ipairs(list) do
        local left = want.qty
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for s = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                if left <= 0 then break end
                local info = C_Container.GetContainerItemInfo(bag, s)
                if info and info.itemID == want.id and not info.isLocked then
                    local take = math.min(left, info.stackCount or 1)
                    slot = slot + 1
                    steps[#steps + 1] = { bag = bag, slot = s, take = take, whole = take >= (info.stackCount or 1), trade = slot }
                    left = left - take
                end
            end
        end
        if left > 0 then return false, ("you're missing %d %s"):format(left, ItemName(want.id)) end
    end
    if slot > TRADE_SLOTS then return false, ("that needs %d trade slots - a trade holds %d. Ask for fewer."):format(slot, TRADE_SLOTS) end
    placing = steps
    local function Step(i)
        if placing ~= steps then return end
        local st = steps[i]
        if not st then placing = nil; if done then done() end return end
        if ClearCursor then ClearCursor() end
        if st.whole then C_Container.PickupContainerItem(st.bag, st.slot)
        else C_Container.SplitContainerItem(st.bag, st.slot, st.take) end
        ClickTradeButton(st.trade)
        C_Timer.After(0.25, function() Step(i + 1) end)
    end
    Step(1)
    return true
end

------------------------------------------------------------------------
-- Panel (both sides use the same small window)
------------------------------------------------------------------------
local panel
local function Panel()
    if panel then return panel end
    local Skin = NS.Skin
    panel = CreateFrame("Frame", "TwizCraftOrderFrame", UIParent, "BackdropTemplate")
    panel:SetSize(330, 170)
    panel:SetPoint("CENTER", 0, 120)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton"); panel:SetClampedToScreen(true)
    panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    Skin.Panel(panel)
    panel.title = Skin.Text(panel, "title"); panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.close = Skin.IconButton(panel, "x", "Close", function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -8, -8)
    panel.what = Skin.Text(panel, "body"); panel.what:SetPoint("TOPLEFT", 12, -36); panel.what:SetPoint("RIGHT", -12, 0)
    panel.what:SetWordWrap(true)
    panel.mats = Skin.Text(panel, "small"); panel.mats:SetPoint("TOPLEFT", 12, -78); panel.mats:SetPoint("RIGHT", -12, 0)
    panel.mats:SetWordWrap(true); panel.mats:SetJustifyV("TOP")
    panel.status = Skin.Text(panel, "muted"); panel.status:SetPoint("BOTTOMLEFT", 12, 44); panel.status:SetPoint("RIGHT", -12, 0)
    panel.status:SetWordWrap(true)
    panel.main = Skin.Button(panel, "", "primary", 170, 26); panel.main:SetPoint("BOTTOMLEFT", 10, 10)
    panel.second = Skin.Button(panel, "", "secondary", 90, 26); panel.second:SetPoint("LEFT", panel.main, "RIGHT", 6, 0)
    panel.minus = Skin.Button(panel, "-", "secondary", 24, 22); panel.minus:SetPoint("TOPRIGHT", -40, -34)
    panel.plus = Skin.Button(panel, "+", "secondary", 24, 22); panel.plus:SetPoint("LEFT", panel.minus, "RIGHT", 2, 0)
    panel:Hide()
    local acc = 0
    panel:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        if acc > 0.5 then acc = 0; if NS.RefreshOrderPanel then NS.RefreshOrderPanel() end end
    end)
    return panel
end

local function MaxFromBags(r)
    local n = math.huge
    for _, g in ipairs(r.need) do n = math.min(n, math.floor(BagCount(g.id) / math.max(1, g.qty))) end
    return n == math.huge and 0 or n
end

local function DrawAsker()
    local p = Panel()
    local r = req
    p.title:SetText("Ask " .. r.crafter .. " to craft")
    p.minus:Show(); p.plus:Show()
    local made = (r.made or 1) * r.n
    p.what:SetText(("%s  x%d%s"):format(r.name, r.n, made ~= r.n and (" (makes %d)"):format(made) or ""))
    local lines = {}
    for _, g in ipairs(r.need) do
        local need, have = g.qty * r.n, BagCount(g.id)
        lines[#lines + 1] = ("%s%d %s|r  (you have %d)"):format(have >= need and "|cff8fe08f" or "|cffff8060", need, ItemName(g.id), have)
    end
    p.mats:SetText("You give: " .. table.concat(lines, ", "))
    local unit = UnitFor(r.crafter)
    local near = InRange(unit)
    local enough = MaxFromBags(r) >= r.n
    p.main:SetText(r.stage == "trading" and "Trading..." or ("Trade mats to " .. r.crafter))
    p.main:SetEnabled(r.stage ~= "trading" and r.stage ~= "waiting" and near and enough)
    p.second:SetText("Cancel")
    if r.stage == "waiting" then
        p.status:SetText(r.crafter .. " has your materials and is crafting. " .. (Auto() and "It comes back to you by itself." or "Accept their trade when it comes."))
    elseif r.stage == "trading" then
        p.status:SetText(Auto() and "Sending the materials..." or "Click Trade in the trade window to send the materials.")
    elseif not unit then
        p.status:SetText(r.crafter .. " isn't in your group.")
    elseif not near then
        p.status:SetText("Stand next to " .. r.crafter .. " to trade.")
    elseif not enough then
        p.status:SetText("You don't have the materials for that many in your bags.")
    else
        p.status:SetText(Auto() and ("Trades the materials to %s; they craft it and it comes back to you by itself."):format(r.crafter)
            or "Opens a trade with the materials in it - you click Trade.")
    end
end

local function DrawCrafter()
    local p = Panel()
    local o = order
    p.title:SetText("Craft for " .. o.from)
    p.minus:Hide(); p.plus:Hide()
    p.what:SetText(("%s  x%d"):format(o.name, o.n))
    p.mats:SetText(o.stage == "trade" and ("%s will trade you the materials."):format(o.from) or "")
    local unit = UnitFor(o.from)
    if o.stage == "trade" then
        p.main:SetText("Waiting for materials..."); p.main:SetEnabled(false)
        p.status:SetText(Auto() and ("Waiting for %s's trade - it's accepted by itself."):format(o.from) or ("Accept " .. o.from .. "'s trade."))
    elseif o.stage == "craft" then
        local r = NS.Char().profs[o.line] and NS.Char().profs[o.line].recipes[o.recipe]
        local done = o.out and o.before and BagCount(o.out) >= o.before + (o.made or 1) * o.n
        if done then o.stage = "back"; o.autoTries = 0 end
        p.main:SetText("Craft " .. o.name); p.main:SetEnabled(r ~= nil)
        p.status:SetText(r and "Click to craft (the first click may open your profession window)." or "You don't know this recipe any more.")
    end
    if o.stage == "back" then
        p.main:SetText("Trade to " .. o.from)
        p.main:SetEnabled(InRange(unit))
        p.status:SetText(InRange(unit) and "Opens a trade with the crafted items in it - you click Trade."
            or ("Stand next to " .. o.from .. " to trade."))
    elseif o.stage == "giving" then
        p.main:SetText("Trading..."); p.main:SetEnabled(false)
        p.status:SetText("Click Trade in the trade window.")
    end
    p.second:SetText(o.stage == "trade" and "Decline" or "Hide")
end

-- Crafted: open the trade back to the asker by itself, as soon as they're in range.
-- If the game won't let an addon start the trade, the "Trade to" button does it.
local autoBlocked = false
local function AutoTradeBack()
    local o = order
    if not o or o.stage ~= "back" or autoBlocked then return end
    if (o.autoTries or 0) >= 3 or (o.nextAuto and GetTime() < o.nextAuto) then return end
    if TradeFrame and TradeFrame:IsShown() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local unit = UnitFor(o.from)
    if not InRange(unit) then return end
    o.autoTries = (o.autoTries or 0) + 1
    o.nextAuto = GetTime() + 10
    o.stage, o.auto = "giving", true
    NS.Print(("Crafted %s - opening a trade with %s."):format(o.name, o.from))
    InitiateTrade(unit)
    C_Timer.After(6, function()
        if order == o and o.stage == "giving" and not o.tradeOpen then
            o.stage = "back"
            if o.autoTries >= 3 then NS.Print("Couldn't open the trade - click \"Trade to " .. o.from .. "\".") end
            NS.RefreshOrderPanel()
        end
    end)
end

local ticker = CreateFrame("Frame")
local tick = 0
ticker:SetScript("OnUpdate", function(_, e)
    tick = tick + e
    if tick < 0.5 then return end
    tick = 0
    local o = order
    if o and o.stage == "craft" and o.out and o.before and BagCount(o.out) >= o.before + (o.made or 1) * o.n then
        o.stage, o.autoTries = "back", 0
        if panel and not panel:IsShown() then panel:Show() end
    end
    if o and o.stage == "back" then AutoTradeBack() end
end)

function NS.RefreshOrderPanel()
    if not panel or not panel:IsShown() then return end
    if order and panel.mode == "crafter" then DrawCrafter()
    elseif req and panel.mode == "asker" then DrawAsker() end
end

------------------------------------------------------------------------
-- Asking side
------------------------------------------------------------------------
local nextID = 0
local function NewID() nextID = nextID + 1; return ("%d%03d"):format(time() % 100000, nextID % 1000) end

function NS.OpenCraftRequest(d)
    if not d.online then NS.Print(d.crafter .. " is offline - group up with them to ask for a craft."); return end
    if not d.need or #d.need == 0 then NS.Print("I don't know the materials for that recipe yet - ask " .. d.crafter .. " to open that profession."); return end
    local bop = IsBoP(d.out)
    if bop == nil then NS.Print("Still loading that item - click again in a second."); return end
    if bop then NS.Print(("%s is bind on pickup - %s couldn't trade it back to you."):format(ItemName(d.out), d.crafter)); return end
    local need = {}
    for _, g in ipairs(d.need) do need[#need + 1] = { id = g[1], qty = g[2] } end
    req = { crafter = d.crafter, line = d.line, recipe = d.id, out = d.out, made = d.need.made or 1, name = d.recipeName or ItemName(d.out),
            need = need, n = 1, stage = "ready" }
    req.n = math.max(1, math.min(MaxFromBags(req), 1))
    local p = Panel()
    p.mode = "asker"
    p.minus:SetScript("OnClick", function() if req and req.stage == "ready" then req.n = math.max(1, req.n - 1); DrawAsker() end end)
    p.plus:SetScript("OnClick", function()
        if req and req.stage == "ready" then req.n = math.min(math.max(1, MaxFromBags(req)), req.n + 1); DrawAsker() end
    end)
    p.main:SetScript("OnClick", function() NS.StartCraftRequest() end)
    p.second:SetScript("OnClick", function() NS.CancelCraftRequest(); p:Hide() end)
    p:Show(); DrawAsker()
end

-- the button: tell the crafter, open the trade (the materials go in when it opens)
function NS.StartCraftRequest()
    local r = req
    if not r or r.stage == "trading" or r.stage == "waiting" then return end
    local unit = UnitFor(r.crafter)
    if not InRange(unit) then NS.Print("Stand next to " .. r.crafter .. " first."); return end
    if MaxFromBags(r) < r.n then NS.Print("You don't have the materials for that in your bags."); return end
    r.id = NewID()
    r.stage = "trading"
    NS._partySend(("Q|%s|%s|%d|%d|%d"):format(r.crafter, r.id, r.line, r.recipe, r.n))
    InitiateTrade(unit)
    -- no trade window within a few seconds: it didn't start
    local id = r.id
    C_Timer.After(6, function()
        if req and req.id == id and req.stage == "trading" and not req.tradeOpen then
            NS.FailCraftRequest("the trade didn't open")
        end
    end)
    DrawAsker()
end

function NS.FailCraftRequest(why)
    local r = req
    if not r then return end
    if r.id then NS._partySend(("X|%s|%s"):format(r.crafter, r.id)) end
    r.stage, r.tradeOpen = "ready", nil
    NS.Print(("Trade with %s didn't go through (%s) - click \"Trade mats to %s\" to try again."):format(r.crafter, why or "cancelled", r.crafter))
    NS.RefreshOrderPanel()
end

function NS.CancelCraftRequest()
    if req and req.id and req.stage ~= "ready" then NS._partySend(("X|%s|%s"):format(req.crafter, req.id)) end
    req = nil
end

------------------------------------------------------------------------
-- Crafting side
------------------------------------------------------------------------
local function ShowOrder()
    local p = Panel()
    p.mode = "crafter"
    p.main:SetScript("OnClick", function() NS.OrderMainClick() end)
    p.second:SetScript("OnClick", function()
        if order and order.stage == "trade" then
            NS._partySend(("X|%s|%s"):format(order.from, order.id)); order = nil
        end
        p:Hide() -- an order you have the materials for stays: it comes back when the items are crafted
    end)
    p:Show(); DrawCrafter()
end

function NS.OrderMainClick()
    local o = order
    if not o then return end
    if o.stage == "craft" then
        local prof = NS.Char().profs[o.line]
        local r = prof and prof.recipes[o.recipe]
        if not r then return end
        o.out, o.made = r.out, r.made or 1
        o.before = o.before or BagCount(r.out)
        NS.CraftRecipeNow(o.line, o.recipe, r, o.n, prof.name, "LeftButton", true)
    elseif o.stage == "back" then
        local unit = UnitFor(o.from)
        if not InRange(unit) then NS.Print("Stand next to " .. o.from .. " first."); return end
        o.stage = "giving"
        InitiateTrade(unit)
        C_Timer.After(6, function()
            if order == o and o.stage == "giving" and not o.tradeOpen then
                o.stage = "back"; NS.Print("The trade didn't open - click \"Trade to " .. o.from .. "\" again.")
            end
        end)
    end
    DrawCrafter()
end

function NS.OnOrderMessage(kind, rest, who)
    if kind == "Q" then
        local target, id, line, recipe, n = rest:match("^(.-)|(%d+)|(%d+)|(%d+)|(%d+)$")
        if not target or not IsMe(target) then return end
        line, recipe, n = tonumber(line), tonumber(recipe), tonumber(n)
        local prof = NS.Char().profs[line]
        local r = prof and prof.recipes[recipe]
        if not r then NS._partySend(("X|%s|%s"):format(who, id)); return end
        if IsBoP(r.out) then
            NS.Print(("%s asked for %s, but it's bind on pickup - declined."):format(who, r.name))
            NS._partySend(("X|%s|%s"):format(who, id)); return
        end
        order = { id = id, from = who, line = line, recipe = recipe, n = n, name = r.name, out = r.out, made = r.made or 1, stage = "trade" }
        NS.Print(("%s asks you to craft %d %s - %s"):format(who, n, r.name,
            Auto() and "TwizCraft takes their materials, crafts it and trades it back by itself." or "accept their trade to get the materials."))
        if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
        ShowOrder()
    elseif kind == "X" then
        local target, id = rest:match("^(.-)|(%d+)$")
        if not target or not IsMe(target) then return end
        if order and order.id == id and order.stage == "trade" then
            NS.Print(who .. "'s craft order was cancelled (the trade didn't go through) - they can send it again.")
            order = nil; if panel then panel:Hide() end
        elseif req and req.id == id then
            NS.Print(who .. " declined the craft order.")
            req.stage = "ready"; NS.RefreshOrderPanel()
        end
    elseif kind == "D" then
        local target, id = rest:match("^(.-)|(%d+)$")
        if target and IsMe(target) and req and req.id == id then
            NS.Print(("%s traded you your %s. Thanks, %s!"):format(who, req.name, who))
            req = nil; if panel and panel.mode == "asker" then panel:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- Trade events (both sides)
------------------------------------------------------------------------
local accepted = { player = false, target = false }


local function TradeSide(side)
    local t, any = {}, false
    for i = 1, TRADE_SLOTS do
        local link = (side == "player" and GetTradePlayerItemLink or GetTradeTargetItemLink)(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, q = (side == "player" and GetTradePlayerItemInfo or GetTradeTargetItemInfo)(i)
            t[id] = (t[id] or 0) + (q or 1); any = true
        end
    end
    return t, any
end
local function MoneyOut() return (GetPlayerTradeMoney and GetPlayerTradeMoney() or 0) end

-- Is this trade exactly the order step we expect? (never auto-accept anything else)
local function TradeMatchesOrder()
    if placing then return false end
    if MoneyOut() > 0 then return false end
    local mine, mineAny = TradeSide("player")
    local theirs = TradeSide("target")
    local function exactly(want)
        for id, n in pairs(want) do if (mine[id] or 0) ~= n then return false end end
        for id in pairs(mine) do if not want[id] then return false end end
        return true
    end
    if req and req.tradeOpen and req.stage == "trading" then
        local want = {}
        for _, g in ipairs(req.need) do want[g.id] = g.qty * req.n end
        return exactly(want)
    end
    if req and req.tradeOpen and req.stage == "waiting" then
        return not mineAny and (theirs[req.out] or 0) > 0
    end
    if order and order.tradeOpen and order.stage == "trade" then
        if mineAny then return false end
        local prof = NS.Char().profs[order.line]
        local r = prof and prof.recipes[order.recipe]
        if not r then return false end
        for _, g in ipairs(r.reagents or {}) do
            local have = 0
            for _, aid in ipairs(g.alts or { g.id }) do have = have + (theirs[aid] or 0) end
            if have < (g.qty or 1) * order.n then return false end
        end
        return true
    end
    if order and order.tradeOpen and order.stage == "giving" then
        return order.placed and exactly({ [order.out] = order.placed })
    end
    return false
end

local acceptBlocked, acceptPending = false, false
local function TryAccept()
    if acceptPending or acceptBlocked or not Auto() then return end
    acceptPending = true
    C_Timer.After(0.4, function()
        acceptPending = false
        if not (TradeFrame and TradeFrame:IsShown()) or accepted.player then return end
        if TradeMatchesOrder() then
            NS.acceptingTrade = true
            AcceptTrade()
            C_Timer.After(0.2, function() NS.acceptingTrade = nil end)
        end
    end)
end

-- ---- auto craft once the materials are in
local craftBlocked = false
local function AutoCraft()
    local o = order
    if not o or o.stage ~= "craft" or craftBlocked or not Auto() then return end
    local prof = NS.Char().profs[o.line]
    local r = prof and prof.recipes[o.recipe]
    if not r then return end
    if InCombatLockdown and InCombatLockdown() then C_Timer.After(3, AutoCraft); return end
    o.out, o.made = r.out, r.made or 1
    o.before = o.before or BagCount(r.out)
    o.crafting = true
    NS.craftingOrder = true
    NS.CraftRecipeNow(o.line, o.recipe, r, o.n, prof.name, "LeftButton", true) -- opens the profession if needed
    C_Timer.After(1.5, function()
        NS.craftingOrder = nil
        -- the first call only opened the window: craft now (unless it already started)
        if order ~= o or o.stage ~= "craft" then return end
        if UnitCastingInfo and UnitCastingInfo("player") then return end
        if BagCount(r.out) > o.before then return end
        NS.craftingOrder = true
        NS.CraftRecipeNow(o.line, o.recipe, r, o.n, prof.name, "LeftButton", true)
        C_Timer.After(0.3, function() NS.craftingOrder = nil end)
    end)
end

local function TradeDone()
    -- the materials reached the crafter
    if req and req.stage == "trading" and req.tradeOpen then
        req.stage, req.tradeOpen = "waiting", nil
        NS._partySend(("S|%s|%s"):format(req.crafter, req.id))
        NS.Print(("Sent the materials to %s - they'll craft it and trade it back."):format(req.crafter))
    elseif req and req.stage == "waiting" and req.tradeOpen then
        NS.Print(("Got your %s from %s."):format(req.name, req.crafter))
        req = nil; if panel and panel.mode == "asker" then panel:Hide() end
    end
    if order and order.stage == "trade" and order.tradeOpen then
        order.stage, order.tradeOpen = "craft", nil
        C_Timer.After(1, AutoCraft)
        NS.Print(("Got the materials from %s - %s"):format(order.from, Auto() and "crafting." or "click Craft."))
    elseif order and order.stage == "giving" and order.tradeOpen then
        NS._partySend(("D|%s|%s"):format(order.from, order.id))
        NS.Print(("Traded %s to %s - order done."):format(order.name, order.from))
        order = nil; if panel and panel.mode == "crafter" then panel:Hide() end
    end
    NS.RefreshOrderPanel()
end

local function TradeFailed(why)
    if req and req.stage == "trading" then NS.FailCraftRequest(why) end
    if req and req.stage == "waiting" then req.tradeOpen = nil end
    if order and order.stage == "giving" then
        order.stage, order.tradeOpen = "back", nil
        NS.Print("The trade didn't go through - click \"Trade to " .. order.from .. "\" again.")
    end
    if order and order.stage == "trade" then order.tradeOpen = nil end
    NS.RefreshOrderPanel()
end

local blockEv = CreateFrame("Frame")
pcall(blockEv.RegisterEvent, blockEv, "ADDON_ACTION_BLOCKED")
pcall(blockEv.RegisterEvent, blockEv, "ADDON_ACTION_FORBIDDEN")
blockEv:SetScript("OnEvent", function(_, _, addon, fn)
    if addon ~= ADDON then return end
    if NS.acceptingTrade and not acceptBlocked then
        acceptBlocked = true
        NS.Print("The game won't let addons accept trades by themselves - click Trade in the trade window (everything else stays automatic).")
        return
    end
    if NS.craftingOrder and not craftBlocked then
        craftBlocked = true
        NS.Print("The game won't let addons craft by themselves - click \"Craft\" on the order (one click).")
        if panel then panel:Show() end
        NS.RefreshOrderPanel()
        return
    end
    if order and order.auto and not autoBlocked then
        autoBlocked = true
        order.stage, order.auto = "back", nil
        NS.Print(("The game won't let addons start trades by themselves - click \"Trade to %s\" (or have them open the trade; the items go in either way)."):format(order.from))
        if panel then panel:Show() end
        NS.RefreshOrderPanel()
    end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "TRADE_ACCEPT_UPDATE",
    "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "BAG_UPDATE_DELAYED",
    "TRADE_TARGET_ITEM_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_MONEY_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local closeTimer
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "TRADE_SHOW" then
        accepted.player, accepted.target = false, false
        local partner = TradePartner()
        if req and (req.stage == "trading" or req.stage == "waiting") and NS._nameFits(partner or "", req.crafter) then
            req.tradeOpen = true
            if req.stage == "waiting" then TryAccept() end
            if req.stage == "trading" then
                local list = {}
                for _, g in ipairs(req.need) do list[#list + 1] = { id = g.id, qty = g.qty * req.n } end
                local ok, why = PlaceItems(list, function() TryAccept() end)
                if not ok then NS.Print("Can't put the materials in: " .. why); if CancelTrade then CancelTrade() end end
            end
        end
        if order and order.stage == "back" and NS._nameFits(partner or "", order.from) then order.stage = "giving" end
        if order and (order.stage == "trade" or order.stage == "giving") and NS._nameFits(partner or "", order.from) then
            order.tradeOpen = true
            if order.stage == "trade" then TryAccept() end
            if order.stage == "giving" then
                local qty = math.min(BagCount(order.out), (order.made or 1) * order.n)
                order.placed = qty
                local ok, why = PlaceItems({ { id = order.out, qty = qty } }, function() TryAccept() end)
                if not ok then NS.Print("Can't put the items in: " .. why) end
            end
        end
        NS.RefreshOrderPanel()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        accepted.player, accepted.target = a1 == 1, a2 == 1
        if not accepted.player then TryAccept() end
    elseif event == "TRADE_TARGET_ITEM_CHANGED" or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_MONEY_CHANGED" then
        accepted.player = false
        TryAccept()
    elseif event == "UI_INFO_MESSAGE" then
        if a2 == ERR_TRADE_COMPLETE or a1 == ERR_TRADE_COMPLETE then TradeDone() end
    elseif event == "UI_ERROR_MESSAGE" then
        local msg = a2 or a1
        if type(msg) == "string" and (msg == ERR_TRADE_TOO_FAR or msg == ERR_TRADE_BAG_FULL or msg == ERR_TRADE_TARGET_BAG_FULL
            or msg == ERR_TRADE_BLOCKED_S or msg == ERR_TRADE_REQUEST_CANCELLED or msg == ERR_TRADE_CANCELLED) then
            TradeFailed(msg)
        end
    elseif event == "TRADE_REQUEST_CANCEL" then
        TradeFailed("they didn't accept")
    elseif event == "TRADE_CLOSED" then
        placing = nil
        -- "Trade complete" arrives as its own message; if both had accepted, count it as done
        local both = accepted.player and accepted.target
        if closeTimer then closeTimer:Cancel() end
        closeTimer = C_Timer.NewTimer(0.6, function()
            closeTimer = nil
            if (req and req.tradeOpen) or (order and order.tradeOpen) then
                if both then TradeDone() else TradeFailed("the trade was cancelled") end
            end
        end)
    elseif event == "BAG_UPDATE_DELAYED" then
        NS.RefreshOrderPanel()
    end
end)
