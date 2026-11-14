-- TwizAH: My Auctions - your listings, which ones have been undercut, and
-- whether cancelling and reposting is worth it.
--
-- On WoW: Forever cancelling loses that auction's deposit and the item comes back
-- by mail; reposting costs a new deposit. Deposits are tiny next to most prices,
-- so the rule is: cancel when you've been undercut, enough time is left that
-- waiting is pointless, and the repost at the new price still clears its deposit
-- with room to spare.
local ADDON, ns = ...

ns.owned = {}        -- rows for the tab
local checking = 0   -- lookups still running
local lastQuery = 0

local STATUS_TEXT = {
    SOLD     = "|cff40ff40Sold|r",
    LOWEST   = "|cff40ff40Cheapest|r",
    UNDERCUT = "|cffff6060Undercut|r",
    BIDS     = "|cff40c0ffHas bids|r",
    CHECK    = "|cff808080Checking...|r",
    UNKNOWN  = "|cff808080?|r",
}

local function IsCommodityKey(key)
    local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(key)
    if info and info.isCommodity ~= nil then return info.isCommodity end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(key.itemID)
    return not (classID == 2 or classID == 4) -- weapons/armor are single items
end

local function TimeText(sec)
    if not sec then return "?" end
    if sec < 3600 then return ("%dm"):format(sec / 60) end
    return ("%dh %02dm"):format(sec / 3600, (sec % 3600) / 60)
end

-- Is cancelling + reposting worth it for this auction?
local function Advise(a)
    a.cancel = false
    if a.status ~= "UNDERCUT" or not a.otherLow then return end
    local newUnit = a.otherLow - 1
    if newUnit < 1 then return end
    local okDep, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, a.itemID, 2, a.qty)
    dep = (okDep and dep) or ns.S.fallbackDeposit
    a.repostDeposit = dep
    a.newUnit = newUnit
    local net = newUnit * a.qty * (1 - ns.S.ahCut)
    -- worth it if: the auction isn't about to end anyway, and the repost clears its deposit 5x over
    if (a.timeLeftSec or 0) >= 30 * 60 and net >= dep * 5 then
        a.cancel = true
        a.reason = ("Cancel and repost at %s: you're behind %d cheaper unit%s. New deposit %s."):format(
            ns.Money(newUnit), a.ahead, a.ahead == 1 and "" or "s", ns.Money(dep))
    elseif (a.timeLeftSec or 0) < 30 * 60 then
        a.reason = "Undercut, but it ends in under 30 minutes - let it expire and repost from your mail."
    else
        a.reason = "Undercut, but the price is too low for a repost to be worth a new deposit."
    end
end

local function CheckUndercuts()
    if not ns.ahOpen then return end
    local byKey = {}
    for _, a in ipairs(ns.owned) do
        if a.status == "CHECK" then
            local k = a.itemID .. ":" .. (a.itemKey.itemLevel or 0) .. ":" .. (a.itemKey.itemSuffix or 0)
            byKey[k] = byKey[k] or { key = a.itemKey, list = {} }
            table.insert(byKey[k].list, a)
        end
    end
    for _, g in pairs(byKey) do
        checking = checking + 1
        local commodity = IsCommodityKey(g.key)
        ns.QueueLookup(g.key.itemID, g.key, commodity, function(rows)
            checking = math.max(0, checking - 1)
            for _, a in ipairs(g.list) do
                if not rows then
                    a.status = "UNKNOWN"
                else
                    -- units from other sellers listed cheaper than you
                    local ahead, otherLow = 0, nil
                    for _, r in ipairs(rows) do
                        if not r.own then
                            otherLow = otherLow or r.unit
                            if r.unit < a.unit then ahead = ahead + (r.qty or 1) end
                        end
                    end
                    a.ahead, a.otherLow = ahead, otherLow
                    a.status = ahead > 0 and "UNDERCUT" or "LOWEST"
                    Advise(a)
                end
            end
            if ns.UI then ns.UI.Refresh() end
        end)
    end
end

local function ReadOwned()
    local list = {}
    local n = C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetNumOwnedAuctions() or 0
    for i = 1, n do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if info and info.itemKey then
            local id = info.itemKey.itemID
            local a = {
                auctionID = info.auctionID, itemKey = info.itemKey, itemID = id, link = info.itemLink,
                qty = info.quantity or 1, unit = info.buyoutAmount or info.bidAmount or 0,
                timeLeftSec = info.timeLeftSeconds, bidder = info.bidder,
            }
            if info.status == 1 then
                a.status = "SOLD"
                -- count the sale now (the mail comes later and is then skipped)
                ns.db.ownedSold = ns.db.ownedSold or {}
                if a.auctionID and not ns.db.ownedSold[a.auctionID] then
                    ns.db.ownedSold[a.auctionID] = time()
                    local name = C_Item.GetItemInfo(id)
                    if name and ns.MarkChatOutcome then ns.MarkChatOutcome(name, "sold") end
                end
            elseif info.bidder or not info.buyoutAmount then
                a.status = "BIDS" -- can't cancel an auction with bids
            else
                a.status = "CHECK"
            end
            list[#list + 1] = a
        end
    end
    -- forget sold-auction ids after a week
    for id, t in pairs(ns.db.ownedSold or {}) do if time() - t > 7 * 86400 then ns.db.ownedSold[id] = nil end end
    local ORDER = { UNDERCUT = 1, CHECK = 2, LOWEST = 3, BIDS = 4, UNKNOWN = 5, SOLD = 6 }
    table.sort(list, function(x, y)
        if x.status ~= y.status then return (ORDER[x.status] or 9) < (ORDER[y.status] or 9) end
        return (x.unit * x.qty) > (y.unit * y.qty)
    end)
    ns.owned = list
end

function ns.OwnedSummary()
    local active, under, worth = 0, 0, 0
    for _, a in ipairs(ns.owned) do
        if a.status ~= "SOLD" then active = active + 1 end
        if a.status == "UNDERCUT" then under = under + 1 end
        if a.cancel and not a.cancelled then worth = worth + 1 end
    end
    return active, under, worth
end

function ns.QueryOwned()
    if not ns.ahOpen then ns.Print("Open the Auction House first."); return end
    lastQuery = time()
    ns.ownedQueried = true
    C_AuctionHouse.QueryOwnedAuctions({ { sortOrder = Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } })
end

local function NextToCancel()
    for _, a in ipairs(ns.owned) do
        if a.cancel and not a.cancelled then return a end
    end
end

function ns.CancelNextUndercut()
    if not ns.ahOpen then ns.Print("Open the Auction House first."); return end
    local a = NextToCancel()
    if not a then ns.Print("Nothing worth cancelling right now."); return end
    a.cancelled = true
    C_AuctionHouse.CancelAuction(a.auctionID)
    ns.Print(("Cancelling %s x%d (was %s, cheapest other seller %s). It comes back by mail - repost it from My Bags."):format(
        a.link or "auction", a.qty, ns.Money(a.unit), ns.Money(a.otherLow)))
    -- a cancelled auction is resolved: don't count it as sold or expired later
    local name = C_Item.GetItemInfo(a.itemID)
    if name and ns.RecordOutcome then ns.RecordOutcome(name, "cancelled") end
end

------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------
local function Summary()
    local active, under, worth, value, sold = 0, 0, 0, 0, 0
    for _, a in ipairs(ns.owned) do
        if a.status == "SOLD" then sold = sold + 1
        else
            active = active + 1
            value = value + a.unit * a.qty
            if a.status == "UNDERCUT" then under = under + 1 end
            if a.cancel and not a.cancelled then worth = worth + 1 end
        end
    end
    return active, under, worth, value, sold
end

ns.UI_RegisterLater = ns.UI_RegisterLater or {}
table.insert(ns.UI_RegisterLater, function(UI)
    UI.RegisterTab("AUCTIONS", {
        cols = {
            { title = "Item",        w = 190, j = "LEFT" },
            { title = "Qty",         w = 40,  j = "RIGHT" },
            { title = "Your price",  w = 85,  j = "RIGHT" },
            { title = "Cheapest other", w = 95, j = "RIGHT" },
            { title = "Ahead of you", w = 70, j = "RIGHT" },
            { title = "Time left",   w = 65,  j = "RIGHT" },
            { title = "Status",      w = 75,  j = "CENTER" },
            { title = "Do this",     w = 70,  j = "CENTER" },
        },
        list = function() return ns.owned end,
        fill = function(row, a, c, ItemLabel)
            c[1]:SetText(ItemLabel(a.link, nil, a.itemID))
            c[2]:SetText(a.qty)
            c[3]:SetText(ns.Money(a.unit))
            c[4]:SetText(a.otherLow and ns.Money(a.otherLow) or "")
            c[5]:SetText(a.ahead and a.ahead > 0 and a.ahead or "")
            c[6]:SetText(a.status == "SOLD" and "" or TimeText(a.timeLeftSec))
            c[7]:SetText(STATUS_TEXT[a.status] or "")
            c[8]:SetText(a.cancelled and "|cff808080Cancelled|r" or (a.cancel and "|cffffd100Cancel|r") or "")
        end,
        tooltip = function(a)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Your price (each)", ns.Money(a.unit), 1, 1, 1)
            if a.otherLow then GameTooltip:AddDoubleLine("Cheapest other seller", ns.Money(a.otherLow), 1, 1, 1) end
            if a.ahead and a.ahead > 0 then GameTooltip:AddDoubleLine("Cheaper units ahead of yours", tostring(a.ahead), 1, 1, 1, 1, 1, 1) end
            if a.reason then GameTooltip:AddLine(a.reason, 1, 0.82, 0, true) end
            if a.status == "BIDS" then GameTooltip:AddLine("Someone has bid on this - it can't be cancelled.", 0.6, 0.8, 1, true) end
        end,
        onClick = function(a) end,
        summary = function()
            local active, under, worth, value, sold = Summary()
            local text
            if not ns.ownedQueried then
                text = "Open the AH and click |cffffd100Check Auctions|r to see your listings."
            else
                text = ("%d active (%s listed), |cffff6060%d undercut|r, %d worth cancelling%s."):format(
                    active, ns.Money(value), under, worth, sold > 0 and (", |cff40ff40%d sold|r"):format(sold) or "")
            end
            local status = checking > 0 and ("Checking prices... %d left"):format(checking)
                or "Cancelled auctions come back by mail. Deposits on Forever are small, so cancel-and-repost is usually worth it."
            return text, status
        end,
        onShow = function()
            if ns.ahOpen and time() - lastQuery > 30 then ns.QueryOwned() end
        end,
        buttons = {
            { text = "Check Auctions", width = 120, onClick = function() ns.QueryOwned() end,
              tooltip = function()
                  GameTooltip:SetText("Check Auctions")
                  GameTooltip:AddLine("Loads your auctions and checks each one against the cheapest other seller.", 1, 1, 1, true)
              end },
            { text = "Cancel Undercut", width = 170, onClick = function() ns.CancelNextUndercut() end,
              label = function()
                  local _, _, worth = Summary()
                  return ("Cancel Undercut (%d)"):format(worth)
              end,
              enabled = function() return NextToCancel() ~= nil end,
              tooltip = function()
                  GameTooltip:SetText("Cancel Undercut")
                  GameTooltip:AddLine("Cancels the next undercut auction that's worth reposting (one per click - the game requires it). The item comes back by mail; repost it from My Bags.", 1, 1, 1, true)
                  GameTooltip:AddLine("Auctions with bids can't be cancelled. Auctions ending within 30 minutes are left to expire.", 0.7, 0.7, 0.7, true)
              end },
        },
    })
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "OWNED_AUCTIONS_UPDATED", "AUCTION_CANCELED", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_SHOW" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "OWNED_AUCTIONS_UPDATED" then
        ReadOwned()
        CheckUndercuts()
        if ns.UI then ns.UI.Refresh() end
    elseif event == "AUCTION_CANCELED" then
        for _, a in ipairs(ns.owned) do if a.auctionID == a1 then a.cancelled = true end end
        if ns.UI then ns.UI.Refresh() end
    elseif event == "AUCTION_HOUSE_SHOW" then
        -- after the bag research has had a head start
        C_Timer.After(4, function() if ns.ahOpen then ns.QueryOwned() end end)
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        -- refresh the list a moment after posting (one query for a burst of posts)
        if not ns.ownedRequery then
            ns.ownedRequery = true
            C_Timer.After(3, function() ns.ownedRequery = false; if ns.ahOpen then ns.QueryOwned() end end)
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        checking = 0
        lastQuery = 0
    end
end)
