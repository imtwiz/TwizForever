-- TwizAH: Scanner - bag research (targeted searches) and full AH scan (deals)
local ADDON, ns = ...

local PRICE_SORT = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
-- gear and other non-stacking items sort by buyout (price sorting there can be by bid)
local BUYOUT_SORT = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout or 4, reverseSort = false } }
local FULL_SCAN_COOLDOWN = 15 * 60

ns.items = {}         -- bag items being evaluated (array)
ns.deals = {}         -- results of the last full scan
ns.bidDeals = {}      -- extremely low bids
ns.dealView = "BUYOUT"
local queue = {}
local current, currentTimer
ns.ahOpen = false

------------------------------------------------------------------------
-- Bags
------------------------------------------------------------------------
local function LastBagIndex()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function CollectBags()
    local groups, list = {}, {}
    for bag = 0, LastBagIndex() do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound and not ns.IsExcluded(info.itemID)
                and not ns.QuestNeeds(info.itemID) then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if loc and loc:IsValid() and SafeCall(C_AuctionHouse.IsSellItemValid, loc, false) then
                    local status = SafeCall(C_AuctionHouse.GetItemCommodityStatus, loc)
                    local isCommodity = status == Enum.ItemCommodityStatus.Commodity
                    -- Commodities stack across bags into one post; gear is posted one piece at a time
                    local key = isCommodity and ("c" .. info.itemID) or ("i" .. bag .. ":" .. slot)
                    local g = groups[key]
                    if g then
                        g.qty = g.qty + (info.stackCount or 1)
                        table.insert(g.locs, loc)
                    else
                        local vendor = select(11, C_Item.GetItemInfo(info.itemID))
                        g = {
                            key = key,
                            itemID = info.itemID,
                            link = info.hyperlink,
                            icon = info.iconFileID,
                            quality = info.quality,
                            qty = info.stackCount or 1,
                            locs = { loc },
                            isCommodity = isCommodity,
                            vendor = vendor or 0,
                        }
                        g.itemKey = isCommodity and C_AuctionHouse.MakeItemKey(info.itemID)
                            or SafeCall(C_AuctionHouse.GetItemKeyFromItem, loc)
                            or C_AuctionHouse.MakeItemKey(info.itemID)
                        groups[key] = g
                        table.insert(list, g)
                    end
                end
            end
        end
    end
    return list
end

local function FirstValidLoc(it)
    for _, loc in ipairs(it.locs) do
        if loc:IsValid() and C_Item.GetItemID(loc) == it.itemID then return loc end
    end
end

local function ComputeDeposits(it)
    it.rates, it.rateInfo = ns.SellRates(it.itemID, it.qty)
    it.deposit = {}
    local loc = FirstValidLoc(it)
    for d = 1, 3 do
        local dep
        if it.isCommodity then
            dep = SafeCall(C_AuctionHouse.CalculateCommodityDeposit, it.itemID, d, it.qty)
        elseif loc then
            dep = SafeCall(C_AuctionHouse.CalculateItemDeposit, loc, d, it.qty)
        end
        it.deposit[d] = dep
    end
end

function ns.ReEvaluateAll()
    for _, it in ipairs(ns.items) do
        if not it.posted then
            it.rates, it.rateInfo = ns.SellRates(it.itemID, it.qty)
            it.result = ns.Evaluate(it)
        end
    end
    table.sort(ns.items, function(a, b)
        local va = a.posted and "POSTED" or (a.result and a.result.verdict) or "NOPRICE"
        local vb = b.posted and "POSTED" or (b.result and b.result.verdict) or "NOPRICE"
        if va ~= vb then return ns.VERDICT_RANK[va] < ns.VERDICT_RANK[vb] end
        local ga = (a.result and a.result.gain) or (a.result and a.result.vendorTotal) or 0
        local gb = (b.result and b.result.gain) or (b.result and b.result.vendorTotal) or 0
        return ga > gb
    end)
end

------------------------------------------------------------------------
-- Search queue (one throttled query at a time)
------------------------------------------------------------------------
local function FinishCurrent()
    if currentTimer then currentTimer:Cancel(); currentTimer = nil end
    current = nil
end

local Pump

local function Done()
    ns.scanning = false
    ns.lastBagResearch = time()
    ns.ReEvaluateAll()
    ns.UI.Refresh()
    local post, ev, vend = 0, 0, 0
    for _, it in ipairs(ns.items) do
        local r = it.result
        if r and r.verdict == "POST" then post = post + 1; ev = ev + r.bestEV; vend = vend + r.vendorTotal end
    end
    ns.Print(("Researched %d items. %d worth posting: expected %s vs %s from a vendor."):format(
        #ns.items, post, ns.Money(ev), ns.Money(vend)))
end

Pump = function()
    if not ns.ahOpen then return end
    if current then return end
    if #queue == 0 then
        if ns.scanning then Done() end
        return
    end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY will call us again
    end
    local it = table.remove(queue, 1)
    current = it
    C_AuctionHouse.SendSearchQuery(it.itemKey, it.isCommodity and PRICE_SORT or BUYOUT_SORT, true)
    currentTimer = C_Timer.NewTimer(4, function()
        if current == it and it.priceOnly then
            FinishCurrent()
            if it.lookup then pcall(it.lookup, nil) end
            Pump()
        elseif current == it then
            -- no answer: fall back to whatever we know
            it.market = ns.KnownPrice(it.itemID)
            ComputeDeposits(it)
            it.result = ns.Evaluate(it)
            FinishCurrent()
            ns.scanProgress = (ns.scanProgress or 0) + 1
            ns.UI.Refresh()
            Pump()
        end
    end)
end

local function Resolve(it, unit, ownLowest, listed)
    if it.priceOnly then
        if unit then ns.RecordPrice(it.itemID, unit) end
        FinishCurrent()
        ns.UI.Refresh()
        Pump()
        return
    end
    if unit then
        it.market = unit
        it.ownLowest = ownLowest
        it.noListings = false
        ns.RecordPrice(it.itemID, unit)
    else
        it.market = nil
        it.noListings = true
    end
    it.listedQty = listed
    ComputeDeposits(it)
    it.result = ns.Evaluate(it)
    FinishCurrent()
    ns.scanProgress = (ns.scanProgress or 0) + 1
    ns.UI.Refresh()
    Pump()
end

local function IsOwnRow(r)
    if r.owners and r.owners[1] == "player" then return true end
    return r.containsOwnerItem and (r.numOwnerItems or r.quantity or 0) >= (r.quantity or 0)
end

-- Generic lookup: hand the first rows of a search to a callback
local function FinishLookup(rows)
    local cb = current.lookup
    local id = current.itemID
    if rows and rows[1] then
        for _, r in ipairs(rows) do if not r.own then ns.RecordPrice(id, r.unit); break end end
    end
    FinishCurrent()
    pcall(cb, rows)
    Pump()
end

local function OnCommodityResults(itemID)
    if not (current and current.isCommodity and current.itemID == itemID) then return end
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
    if current.lookup then
        local rows = {}
        for i = 1, math.min(n, 25) do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
            if r then rows[#rows + 1] = { unit = r.unitPrice, qty = r.quantity, own = IsOwnRow(r), auctionID = r.auctionID } end
        end
        return FinishLookup(rows)
    end
    if n == 0 then return Resolve(current, nil) end
    local first = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    local listed = SafeCall(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
    if first then
        -- If the cheapest listing is already yours, match it rather than undercutting yourself
        local own = first.containsOwnerItem and (first.numOwnerItems or first.quantity) >= first.quantity
        Resolve(current, first.unitPrice, own, listed)
    end
end

local function OnItemResults(itemKey)
    if not (current and not current.isCommodity and itemKey and itemKey.itemID == current.itemID) then return end
    local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
    if current.lookup then
        local rows = {}
        for i = 1, math.min(n, 25) do
            local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            if r and r.buyoutAmount and r.buyoutAmount > 0 then
                rows[#rows + 1] = { unit = math.floor(r.buyoutAmount / math.max(1, r.quantity or 1)), qty = r.quantity or 1,
                    own = IsOwnRow(r), auctionID = r.auctionID }
            end
        end
        return FinishLookup(rows)
    end
    for i = 1, n do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and r.buyoutAmount and r.buyoutAmount > 0 then
            local unit = math.floor(r.buyoutAmount / math.max(1, r.quantity or 1))
            return Resolve(current, unit, r.containsOwnerItem, n)
        end
    end
    Resolve(current, nil, nil, 0)
end

-- Ask the AH about one item; cb(rows) gets { {unit, qty, own, auctionID}, ... } cheapest first, or nil
function ns.QueueLookup(itemID, itemKey, isCommodity, cb)
    table.insert(queue, { itemID = itemID, itemKey = itemKey or C_AuctionHouse.MakeItemKey(itemID),
        isCommodity = isCommodity, priceOnly = true, lookup = cb, qty = 0, locs = {} })
    Pump()
end

function ns.StartBagScan()
    if not ns.ahOpen then ns.Print("Open the Auction House first."); return end
    -- keep pending lookups (e.g. the undercut check); drop the old bag research
    for i = #queue, 1, -1 do if not queue[i].lookup then table.remove(queue, i) end end
    if current and not current.lookup then FinishCurrent() end
    pcall(ns.RefreshQuestItems)
    ns.items = CollectBags()
    ns.scanProgress = 0
    ns.scanning = #ns.items > 0
    for _, it in ipairs(ns.items) do
        it.market = ns.KnownPrice(it.itemID) -- show last known price while we research
        table.insert(queue, it)
    end
    -- price-only lookups: the bars your ore would smelt into (for the Smelt tab)
    local okT, bars = pcall(ns.SmeltPriceTargets, ns.items)
    bars = okT and bars or {}
    local okC, products = pcall(ns.CraftPriceTargets, ns.items)
    local dup = {}
    for _, id in ipairs(bars) do dup[id] = true end
    for _, id in ipairs(okC and products or {}) do
        if not dup[id] then bars[#bars + 1] = id; dup[id] = true end
    end
    for _, barID in ipairs(bars) do
        table.insert(queue, { itemID = barID, itemKey = C_AuctionHouse.MakeItemKey(barID),
            isCommodity = true, priceOnly = true, qty = 0, locs = {} })
    end
    ns.UI.Refresh()
    if #ns.items == 0 then ns.Print("Nothing in your bags can be auctioned.") end
    Pump()
end

------------------------------------------------------------------------
-- Posting (must be called from a click - the game requires a hardware event)
------------------------------------------------------------------------
local pendingConfirm

StaticPopupDialogs["DEPOSITWISE_CONFIRM_POST"] = {
    text = "The game flagged this price as unusual:\n%s\nPost anyway?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local p = pendingConfirm; pendingConfirm = nil
        if not p then return end
        if p.isCommodity and C_AuctionHouse.ConfirmPostCommodity then
            C_AuctionHouse.ConfirmPostCommodity(p.loc, p.duration, p.qty, p.unit)
        elseif C_AuctionHouse.ConfirmPostItem then
            C_AuctionHouse.ConfirmPostItem(p.loc, p.duration, p.qty, nil, p.unit)
        end
        p.it.posted = true
        ns.RecordPost(p.it, p.it.result)
        ns.UI.Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.Post(it)
    if not ns.ahOpen then ns.Print("Open the Auction House first."); return end
    local r = it and it.result
    if not (r and r.postUnit and r.duration) then ns.Print("No price yet for that item."); return end
    local loc = FirstValidLoc(it)
    if not loc then ns.Print("That item moved - rescan your bags."); return end
    local needsConfirm
    if it.isCommodity then
        needsConfirm = C_AuctionHouse.PostCommodity(loc, r.duration, it.qty, r.postUnit)
    else
        needsConfirm = C_AuctionHouse.PostItem(loc, r.duration, 1, nil, r.postUnit)
    end
    if needsConfirm then
        pendingConfirm = { it = it, loc = loc, duration = r.duration, qty = it.isCommodity and it.qty or 1,
            unit = r.postUnit, isCommodity = it.isCommodity }
        StaticPopup_Show("DEPOSITWISE_CONFIRM_POST", (it.link or "") .. " at " .. ns.Money(r.postUnit))
        return
    end
    it.posted = true
    ns.RecordPost(it, r)
    ns.Print(("Posted %s x%d at %s each for %s (deposit %s)."):format(
        it.link or "item", it.isCommodity and it.qty or 1, ns.Money(r.postUnit),
        ns.DURATION_LABEL[r.duration], ns.Money(r.deposit)))
    ns.UI.Refresh()
end

-- Marginal = beats the vendor, but by less than your minimum gain. Post it anyway as long as it's a profit.
function ns.MarginalQueue()
    local q = {}
    for _, it in ipairs(ns.items) do
        local r = it.result
        if not it.posted and r and r.verdict == "MARGINAL" and (r.gain or 0) > 0 and (r.bestEV or 0) > 0 then
            q[#q + 1] = it
        end
    end
    return q
end

local lastPost = 0
local function Debounced()
    local now = GetTime()
    if now - lastPost < 0.5 then return true end -- give the AH a moment between posts
    lastPost = now
    return false
end

function ns.PostNextMarginal()
    if Debounced() then return end
    local it = ns.MarginalQueue()[1]
    if not it then ns.Print("No profitable marginal items left."); return end
    ns.Post(it)
    local left = #ns.MarginalQueue()
    if left > 0 then ns.Print(("%d marginal item%s left - click again or press your hotkey."):format(left, left == 1 and "" or "s")) end
end

function ns.PostNextBest()
    if Debounced() then return end
    for _, it in ipairs(ns.items) do
        if not it.posted and it.result and it.result.verdict == "POST" then
            return ns.Post(it)
        end
    end
    ns.Print("Nothing left that beats vendoring. Rescan if prices changed.")
end

------------------------------------------------------------------------
-- Full scan: builds a market picture of the whole AH and finds deals
------------------------------------------------------------------------
local fullScanPending = false

function ns.FullScanCooldownLeft()
    return math.max(0, FULL_SCAN_COOLDOWN - (time() - (ns.db.lastFullScan or 0)))
end

function ns.StartFullScan()
    if not ns.ahOpen then ns.Print("Open the Auction House first."); return end
    local left = ns.FullScanCooldownLeft()
    if left > 0 then
        ns.Print(("Full scan is on cooldown for %d:%02d (the game allows one every 15 minutes)."):format(left / 60, left % 60))
        return
    end
    fullScanPending = true
    local previous = ns.db.lastFullScan
    ns.db.lastFullScan = time()
    ns.fullScanStatus = "Requesting full scan..."
    ns.fullScanFailed = nil
    ns.UI.Refresh()
    C_AuctionHouse.ReplicateItems()
    -- if the AH never answers, say so and let you try again instead of waiting out a cooldown
    local token = {}
    ns.fullScanToken = token
    C_Timer.After(60, function()
        if fullScanPending and ns.fullScanToken == token then
            fullScanPending = false
            ns.db.lastFullScan = previous
            ns.fullScanFailed = true
            ns.fullScanStatus = "The AH didn't send the full scan. Try again."
            ns.Print("The Auction House didn't send the full scan (it can be busy right after a reload). You can try again now.")
            ns.UI.Refresh()
        end
    end)
    ns.fullScanPrevious = previous
end

-- AH closed mid-scan: the data is gone, so throw the partial scan away
function ns.AbortFullScan(reason)
    if fullScanPending then
        fullScanPending = false
        ns.db.lastFullScan = ns.fullScanPrevious or ns.db.lastFullScan
        ns.fullScanFailed = true
        ns.fullScanStatus = "Full scan cancelled: " .. reason
        ns.Print("Full scan cancelled: " .. reason .. " You can start another one right away.")
    end
    if ns.processingTicker then
        ns.processingTicker:Cancel()
        ns.processingTicker = nil
        ns.fullScanFailed = true
        ns.fullScanStatus = "Full scan cancelled: " .. reason
        ns.Print("Full scan cancelled: " .. reason .. " Nothing was saved from it.")
    end
end

local function Median(sorted, totalCount)
    -- sorted = array of {unit, count} ascending; weighted median by count
    local half, run = totalCount / 2, 0
    for _, e in ipairs(sorted) do
        run = run + e[2]
        if run >= half then return e[1] end
    end
    return sorted[#sorted] and sorted[#sorted][1]
end

local function IsMe(owner)
    if not owner then return false end
    local me = UnitName("player")
    return owner == me or owner:sub(1, #me + 1) == me .. "-"
end

local function ItemBasics(itemID)
    local name, link, _, _, _, _, _, _, _, icon, vendor = C_Item.GetItemInfo(itemID)
    if not name then C_Item.RequestLoadItemDataByID(itemID) end
    return name, link, icon, vendor or 0
end

-- Fill a buy plan: take the cheapest listings under `limit`, up to `cap` units, skipping your own
local function BuyBand(entries, limit, cap)
    local qty, cost, top = 0, 0, 0
    for _, e in ipairs(entries) do
        if e[1] >= limit or (cap and qty >= cap) then break end
        if not IsMe(e[3]) then
            local take = e[2]
            if cap then take = math.min(take, cap - qty) end
            qty = qty + take; cost = cost + e[1] * take; top = e[1]
        end
    end
    return qty, cost, top
end

local function SpeedCap(itemID)
    local sellable = ns.SellableUnits(itemID, 48)
    if sellable then return math.max(1, math.floor(sellable)), true end
    return 20, false -- unknown speed: stay small until rates are learned
end

local function AddDeal(deals, d)
    local S = ns.S
    d.cat = ns.ItemCategory(d.itemID)
    if d.qty <= 0 or d.profit < S.dealMinProfit then return end
    d.roi = d.cost > 0 and d.profit / d.cost or 0
    if d.roi < S.dealMinROI then return end
    table.insert(deals, d)
end

function ns.BuildDeals(fromScan)
    local S = ns.S
    local deals = {}
    local raw = ns.rawScan
    local now = time()
    local today = tonumber(date("%Y%m%d"))

    if raw then
        for itemID, entries in pairs(raw) do
            -- entries were sorted cheapest-first when the scan was processed
            local count = 0
            for _, e in ipairs(entries) do count = count + e[2] end
            local med = Median(entries, count)
            ns.db.market[itemID] = { min = entries[1][1], med = med, n = #entries, q = count, t = now }
          if not ns.IsExcluded(itemID) then
            local name, link, icon, vendor = ItemBasics(itemID)
            local base = { itemID = itemID, name = name, link = link, icon = icon,
                speed = ns.MarketStats(itemID) }

            -- 1) AH -> vendor: listed below what a vendor pays. Guaranteed, no deposit, no waiting.
            if vendor > 0 and entries[1][1] < vendor then
                local qty, cost = BuyBand(entries, vendor, nil)
                local d = CopyTable(base)
                d.kind, d.qty, d.cost, d.buyBelow, d.target = "VENDOR", qty, cost, vendor - 1, vendor
                d.profit = vendor * qty - cost
                d.plan = "Buy every unit under " .. ns.Money(vendor) .. " and sell it to any vendor. No risk."
                AddDeal(deals, d)
            end

            -- 2) Snipe & relist: a gap between cheap listings and the next real price
            if #entries >= S.dealMinListings and med and med > 0 and entries[1][1] < med * S.dealThreshold then
                local limit = med * S.dealThreshold
                local cap, known = SpeedCap(itemID)
                local qty, cost = BuyBand(entries, limit, cap)
                -- resell 1c under the first listing at or above the gap, never above the median
                local wall = med
                for _, e in ipairs(entries) do
                    if e[1] >= limit and not IsMe(e[3]) then wall = e[1]; break end
                end
                local resale = math.max(1, math.min(wall, med) - 1)
                if qty > 0 and resale * (1 - S.ahCut) > cost / qty then
                    local L = ns.BestListing(itemID, qty, resale)
                    local d = CopyTable(base)
                    d.kind, d.qty, d.cost, d.buyBelow, d.target = "FLIP", qty, cost, math.floor(limit), resale
                    d.profit = L.ev - cost
                    d.duration, d.deposit, d.p, d.known = L.d, L.dep, L.p, known
                    d.plan = ("Buy %d under %s, relist at %s for %s (%.0f%% sell chance). The next seller up is at %s."):format(
                        qty, ns.Money(limit), ns.Money(resale), ns.DURATION_LABEL[L.d], L.p * 100, ns.Money(wall))
                    AddDeal(deals, d)
                end
            end

            -- 3) Dip: well below its usual price over recent days - buy and relist when it recovers
            local h = ns.db.history[itemID]
            if h then
                local sum, n = 0, 0
                for day, v in pairs(h) do
                    if day < today and v.med then sum = sum + v.med; n = n + 1 end
                end
                if n >= 3 then
                    local norm = sum / n
                    if entries[1][1] < norm * 0.75 then
                        local cap, known = SpeedCap(itemID)
                        local qty, cost = BuyBand(entries, norm * 0.85, cap)
                        local resale = math.floor(norm * 0.95)
                        if qty > 0 then
                            local L = ns.BestListing(itemID, qty, resale)
                            local d = CopyTable(base)
                            d.kind, d.qty, d.cost, d.buyBelow, d.target = "DIP", qty, cost, math.floor(norm * 0.85), resale
                            d.profit = L.ev - cost
                            d.duration, d.deposit, d.p, d.known = L.d, L.dep, L.p, known
                            d.plan = ("Usually about %s (%d-day average), now %s. Buy %d and relist near %s once it recovers. Speculative: prices can keep falling."):format(
                                ns.Money(norm), n, ns.Money(entries[1][1]), qty, ns.Money(resale))
                            AddDeal(deals, d)
                        end
                    end
                end
            end
          end -- not excluded
        end
    end

    -- 4) Vendor -> AH: things a merchant sells for less than the AH pays (learned when you visit merchants)
    for itemID, m in pairs(ns.db.merchant or {}) do
        local ahLow = ns.KnownPrice(itemID)
        if ahLow and m.cost and m.cost > 0 and not ns.IsExcluded(itemID) then
            local resale = ahLow - 1
            if resale * (1 - S.ahCut) > m.cost then
                local cap, known = SpeedCap(itemID)
                local qty = cap
                if m.avail and m.avail > 0 then qty = math.min(qty, m.avail) end
                local L = ns.BestListing(itemID, qty, resale)
                local name, link, icon = ItemBasics(itemID)
                AddDeal(deals, { kind = "MERCHANT", itemID = itemID, name = name, link = link, icon = icon,
                    speed = ns.MarketStats(itemID), qty = qty, cost = m.cost * qty, buyBelow = m.cost, target = resale,
                    profit = L.ev - m.cost * qty, duration = L.d, deposit = L.dep, p = L.p, known = known,
                    plan = ("Buy %d from %s%s for %s each, list at %s."):format(qty, m.npc or "a vendor",
                        m.zone and (" (" .. m.zone .. ")") or "", ns.Money(m.cost), ns.Money(resale))
                        .. ((m.avail and m.avail > 0) and " Limited stock." or "") })
            end
        end
    end

    table.sort(deals, function(a, b) return a.profit > b.profit end)
    while #deals > 200 do table.remove(deals) end
    ns.deals = deals
    if raw and fromScan then
        ns.RecordHistory()
        ns.BuildMovers()
    end
    ns.BuildBidDeals()
end

-- Extremely low bids with a high chance of paying off if you win
function ns.BuildBidDeals()
    local S = ns.S
    local out = {}
    for _, c in ipairs(ns.bidRaw or {}) do
        if not IsMe(c.owner) and not ns.IsExcluded(c.itemID) then
            local m = ns.db.market[c.itemID]
            local name, link, icon, vendor = ItemBasics(c.itemID)
            local floorValue = vendor * c.count                     -- a vendor always pays this
            local relist
            if m and m.min then
                local unit = math.min(m.min, m.med or m.min) - 1    -- conservative: the lower of cheapest and median
                if unit > 0 then relist = ns.BestListing(c.itemID, c.count, unit); relist.unit = unit end
            end
            local ahValue = relist and relist.ev or 0
            local worth = math.max(floorValue, ahValue)
            local profit = worth - c.bid
            if worth > 0 and profit >= S.dealMinProfit and c.bid <= worth * S.bidMaxPct then
                local conf
                if floorValue >= c.bid * 1.1 then
                    conf = "SAFE"        -- even vendoring it beats the bid
                elseif relist and relist.info.demand and relist.p >= 0.6 then
                    conf = "HIGH"        -- learned: it sells, and fast enough
                elseif relist and S.bidIncludeUnknown then
                    conf = "UNKNOWN"
                end
                if conf then
                    out[#out + 1] = { kind = "BID", conf = conf, itemID = c.itemID, name = name, link = link, icon = icon,
                        qty = c.count, cost = c.bid, bid = c.bid, hasBids = c.hasBids, buyout = c.buyout,
                        worth = worth, vendorValue = floorValue, relist = relist, profit = profit,
                        roi = profit / c.bid, speed = ns.MarketStats(c.itemID),
                        sellVia = (floorValue >= ahValue) and "vendor" or "AH", cat = ns.ItemCategory(c.itemID),
                        timeLeft = c.timeLeft }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.conf ~= b.conf then return a.conf == "SAFE" or (a.conf == "HIGH" and b.conf == "UNKNOWN") end
        -- ending soonest first: less time for anyone to outbid you
        local ta, tb = a.timeLeft or 9, b.timeLeft or 9
        if ta ~= tb then return ta < tb end
        return a.roi > b.roi
    end)
    while #out > 200 do table.remove(out) end
    ns.bidDeals = out
end

------------------------------------------------------------------------
-- Auto-vendor: sell what a vendor pays more for - only with fresh AH data
------------------------------------------------------------------------
local BUYBACK_LIMIT = 12 -- the merchant's buyback tab holds 12 items, so never sell more per visit

local function FreshResult(itemID, fresh)
    if not (ns.lastBagResearch and ns.lastBagResearch >= fresh) then return nil end
    for _, it in ipairs(ns.items) do
        if it.itemID == itemID and it.result and not it.posted then return it.result end
    end
end

function ns.AutoVendor()
    local S = ns.S
    if not S.autoVendor or IsShiftKeyDown() then return end
    local now = time()
    local fresh = now - S.freshMinutes * 60
    local toSell, stale, staleValue = {}, 0, 0
    local kept, keptSeen = {}, {}
    pcall(ns.RefreshQuestItems)
    local okP, protected = pcall(ns.ProtectedSet)
    protected = okP and protected or {}
    for bag = 0, LastBagIndex() do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- bound items can't go on the AH, so there is nothing to compare: leave them alone
            if info and info.itemID and not info.isBound and not info.isLocked and not info.hasNoValue
                and not ns.IsExcluded(info.itemID) then
                local qty = info.stackCount or 1
                local vendor = (select(11, C_Item.GetItemInfo(info.itemID)) or 0) * qty
                if vendor > 0 then
                    local sell, ahValue = false, nil
                    local r = FreshResult(info.itemID, fresh)
                    if r and r.verdict == "VENDOR" then
                        -- full model: AH price, cut and deposit risk all lose to the vendor
                        sell = true; ahValue = r.bestEV and (r.bestEV / math.max(1, r.vendorTotal / vendor)) or 0
                    elseif not r then
                        local price, t = ns.KnownPrice(info.itemID)
                        if price and t >= fresh then
                            -- AH net after the cut (deposit ignored, which favors the AH: errs toward keeping)
                            ahValue = math.floor(price * qty * (1 - S.ahCut))
                            sell = vendor > ahValue
                        elseif price then
                            if vendor > math.floor(price * qty * (1 - S.ahCut)) then
                                stale = stale + 1; staleValue = staleValue + vendor
                            end
                        end
                    end
                    if sell then
                        -- would sell it - unless something you're doing needs it
                        local why = ns.QuestNeeds(info.itemID) or protected[info.itemID]
                        if why then
                            if not keptSeen[info.itemID] then
                                keptSeen[info.itemID] = true
                                kept[#kept + 1] = (info.hyperlink or "item") .. " (" .. why .. ")"
                            end
                        else
                            table.insert(toSell, { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                                qty = qty, vendor = vendor, ah = ahValue })
                        end
                    end
                end
            end
        end
    end

    table.sort(toSell, function(a, b) return (a.vendor - (a.ah or 0)) > (b.vendor - (b.ah or 0)) end)
    local count = math.min(#toSell, BUYBACK_LIMIT)
    if count > 0 then
        local total, ahTotal = 0, 0
        for i = 1, count do
            local s = toSell[i]
            total = total + s.vendor; ahTotal = ahTotal + (s.ah or 0)
            C_Timer.After(0.25 * i, function()
                if not (MerchantFrame and MerchantFrame:IsShown()) then return end
                -- make sure the slot still holds the same item before selling
                local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
                if info and info.itemID == s.itemID and not info.isLocked then
                    C_Container.UseContainerItem(s.bag, s.slot)
                    ns.Print(("Sold %s x%d for %s (AH would net %s)."):format(s.link or "item", s.qty,
                        ns.Money(s.vendor), ns.Money(s.ah)))
                end
            end)
        end
        ns.session.vendored = ns.session.vendored + count
        ns.session.vendoredGold = ns.session.vendoredGold + total
        ns.Print(("Auto-vendoring %d item%s for %s, %s more than the AH would net. Changed your mind? They're in the merchant's Buyback tab."):format(
            count, count == 1 and "" or "s", ns.Money(total), ns.Money(total - ahTotal)))
        if #toSell > count then
            ns.Print(("%d more to sell - reopen the merchant to sell the rest (buyback only holds 12)."):format(#toSell - count))
        end
    end
    if #kept > 0 then
        ns.Print("Not vendored, you need them: " .. table.concat(kept, ", "))
    end
    if stale > 0 then
        ns.Print(("Skipped %d item%s that look worth vendoring (%s): AH prices are older than %d minutes. Scan the AH, then come back."):format(
            stale, stale == 1 and "" or "s", ns.Money(staleValue), S.freshMinutes))
    end
end

------------------------------------------------------------------------
-- Merchant prices (for vendor -> AH opportunities)
------------------------------------------------------------------------
local function ScanMerchant()
    ns.db.merchant = ns.db.merchant or {}
    local npc, zone = UnitName("npc"), GetZoneText()
    for i = 1, (GetMerchantNumItems() or 0) do
        local itemID = GetMerchantItemID(i)
        local price, stack, avail, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then price, stack, avail, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
        else
            local _, _, p, q, n, _, _, ext = GetMerchantItemInfo(i)
            price, stack, avail, extended = p, q, n, ext
        end
        if itemID and price and price > 0 and not extended then
            ns.db.merchant[itemID] = { cost = price / math.max(1, stack or 1), avail = avail, npc = npc, zone = zone, t = time() }
        end
    end
end

------------------------------------------------------------------------
-- Daily price history -> market movers
------------------------------------------------------------------------
local function DayKey(t) return tonumber(date("%Y%m%d", t or time())) end

function ns.RecordHistory()
    local today = DayKey()
    local hist = ns.db.history
    for itemID, m in pairs(ns.db.market) do
        if m.t and DayKey(m.t) == today and m.med then
            local h = hist[itemID]
            if not h then h = {}; hist[itemID] = h end
            h[today] = { med = m.med, q = m.q }
        end
    end
    -- keep 14 days
    local cutoff = DayKey(time() - 14 * 86400)
    for _, h in pairs(hist) do
        for day in pairs(h) do if day < cutoff then h[day] = nil end end
    end
end

function ns.BuildMovers()
    local today = DayKey()
    local movers = {}
    ns.hasTrendData = false
    for itemID, h in pairs(ns.db.history) do
        local now = h[today]
        if now then
            local prevDay
            for day in pairs(h) do
                if day < today and (not prevDay or day > prevDay) then prevDay = day end
            end
            if prevDay then
                ns.hasTrendData = true
                local before = h[prevDay]
                local m = ns.db.market[itemID]
                if before.med > 0 and m and (m.n or 0) >= ns.S.dealMinListings then
                    local change = (now.med - before.med) / before.med
                    if math.abs(change) >= 0.10 then
                        local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
                        table.insert(movers, { itemID = itemID, name = name, link = link, icon = icon,
                            before = before.med, now = now.med, change = change, q = now.q })
                    end
                end
            end
        end
    end
    table.sort(movers, function(a, b) return math.abs(a.change) > math.abs(b.change) end)
    while #movers > 200 do table.remove(movers) end
    ns.movers = movers
end

local function ProcessReplicate()
    local total = C_AuctionHouse.GetNumReplicateItems() or 0
    local raw = {}
    local bids = {}
    local i = 0
    local ticker
    ns.fullScanStatus = ("Processing 0 / %d auctions..."):format(total)
    ns.UI.Refresh()
    ns.processingTicker = nil
    local ticks = 0
    local hasExist = C_Item.DoesItemExistByID ~= nil
    local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft
    ticker = C_Timer.NewTicker(0.01, function()
        if not ns.ahOpen then return ns.AbortFullScan("the Auction House was closed.") end
        ticks = ticks + 1
        local stop = math.min(total, i + 2000)
        while i < stop do
            -- returns: name, texture, count, quality, usable, level, levelType, minBid, minIncrement,
            --          buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName,
            --          saleStatus, itemID, hasAllInfo
            local _, _, count, _, _, _, _, minBid, minInc, buyout, bidAmount, highBidder, _, owner, ownerFull, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
            -- the game sometimes returns entries for items that don't exist; skip those
            if itemID and (not hasExist or C_Item.DoesItemExistByID(itemID)) then
                local band = timeLeft and timeLeft(i) -- 0 <30m, 1 30m-2h, 2 2h-12h, 3 >12h
                if minBid and minBid > 0 and not highBidder then
                    local nextBid = (bidAmount and bidAmount > 0) and (bidAmount + (minInc or 0)) or minBid
                    bids[#bids + 1] = { itemID = itemID, count = math.max(1, count or 1), bid = nextBid,
                        hasBids = (bidAmount or 0) > 0, buyout = buyout, owner = ownerFull or owner, timeLeft = band }
                end
                if buyout and buyout > 0 then
                    count = math.max(1, count or 1)
                    local list = raw[itemID]
                    if not list then list = {}; raw[itemID] = list end
                    list[#list + 1] = { math.floor(buyout / count), count, ownerFull or owner, band }
                end
            end
            i = i + 1
        end
        ns.fullScanStatus = ("Processing %d / %d auctions..."):format(i, total)
        if ticks % 10 == 0 then ns.UI.Refresh() end
        if i >= total then
            ticker:Cancel()
            ns.processingTicker = nil
            ns.fullScanFailed = nil
            if total == 0 then
                ns.fullScanStatus = "The AH sent an empty full scan - try again in 15 minutes."
                ns.Print(ns.fullScanStatus)
                return
            end
            for _, entries in pairs(raw) do table.sort(entries, function(a, b) return a[1] < b[1] end) end
            ns.rawScan = raw
            ns.bidRaw = bids
            pcall(ns.Rates_OnFullScan, raw)
            ns.BuildDeals(true)
            ns.fullScanStatus = ("Scanned %d auctions. %d deals found."):format(total, #ns.deals)
            -- item names/vendor prices load async; rebuild once they arrive
            C_Timer.After(3, function() ns.BuildDeals(); ns.UI.Refresh() end)
            ns.ReEvaluateAll()
            ns.UI.Refresh()
            ns.lastFullScanDone = time()
            ns.Print(ns.fullScanStatus)
            if ns.lastRateNote then ns.Print(ns.lastRateNote) end
        end
    end)
    ns.processingTicker = ticker
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
function ns.Scanner_OnLoad()
    ev:RegisterEvent("AUCTION_HOUSE_SHOW")
    ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
    ev:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
    ev:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
    ev:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    ev:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    ev:RegisterEvent("MERCHANT_SHOW")
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "AUCTION_HOUSE_SHOW" then
        ns.ahOpen = true
        ns.UI.Show()
        if ns.S.autoScanBags then C_Timer.After(0.5, ns.StartBagScan) end
        -- keep market data and sell rates learning without having to remember to scan
        if ns.autoScanTicker then ns.autoScanTicker:Cancel() end
        ns.autoScanTicker = C_Timer.NewTicker(15, function()
            if not ns.ahOpen or not ns.S.autoFullScan then return end
            if ns.scanning or ns.processingTicker or fullScanPending then return end
            if ns.FullScanCooldownLeft() == 0 then
                ns.Print("Starting an automatic full scan (/dw autofull off to stop).")
                ns.StartFullScan()
            end
        end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.ahOpen = false
        ns.AbortFullScan("the Auction House was closed.")
        if ns.autoScanTicker then ns.autoScanTicker:Cancel(); ns.autoScanTicker = nil end
        wipe(queue); FinishCurrent(); ns.scanning = false
        ns.UI.Hide()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        OnCommodityResults(arg1)
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        OnItemResults(arg1)
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        Pump()
    elseif event == "MERCHANT_SHOW" then
        pcall(ScanMerchant)
        ns.BuildDeals()
        C_Timer.After(0.3, function()
            local ok, err = pcall(ns.AutoVendor)
            if not ok then ns.Print("auto-vendor error: " .. tostring(err)) end
        end)
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if fullScanPending then
            fullScanPending = false
            ProcessReplicate()
        end
    end
end)
