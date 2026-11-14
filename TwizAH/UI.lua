-- TwizAH: UI - panel docked beside the Auction House
local ADDON, ns = ...
local UI = {}
ns.UI = UI

local ROWS, ROW_H = 40, 22   -- rows built; how many show depends on the window height
local visible = 16
local WIDTH, HEIGHT = 720, 520
local frame, rows, offset, tab, selected = nil, {}, 0, "BAGS", nil

local BAG_COLS = {
    { key = "item",    title = "Item",       w = 165, j = "LEFT" },
    { key = "qty",     title = "Qty",        w = 40,  j = "RIGHT" },
    { key = "post",    title = "Post at (ea)", w = 90, j = "RIGHT" },
    { key = "speed",   title = "Sells/day",  w = 50,  j = "RIGHT" },
    { key = "dur",     title = "Time",       w = 40,  j = "CENTER" },
    { key = "deposit", title = "Deposit",    w = 70,  j = "RIGHT" },
    { key = "ev",      title = "Expected",   w = 90,  j = "RIGHT" },
    { key = "vendor",  title = "Vendor",     w = 75,  j = "RIGHT" },
    { key = "verdict", title = "Verdict",    w = 65,  j = "CENTER" },
}
local DEAL_COLS = {
    { key = "item",    title = "Item",       w = 175, j = "LEFT" },
    { key = "kind",    title = "Type",       w = 65,  j = "CENTER" },
    { key = "qty",     title = "Buy",        w = 40,  j = "RIGHT" },
    { key = "below",   title = "Pay up to",  w = 80,  j = "RIGHT" },
    { key = "cost",    title = "Cost",       w = 80,  j = "RIGHT" },
    { key = "target",  title = "Sell at",    w = 80,  j = "RIGHT" },
    { key = "speed",   title = "Sells/day",  w = 55,  j = "RIGHT" },
    { key = "profit",  title = "Profit",     w = 80,  j = "RIGHT" },
    { key = "roi",     title = "ROI",        w = 45,  j = "RIGHT" },
}

local BID_COLS = {
    { key = "item",    title = "Item",       w = 175, j = "LEFT" },
    { key = "conf",    title = "Chance",     w = 70,  j = "CENTER" },
    { key = "qty",     title = "Qty",        w = 35,  j = "RIGHT" },
    { key = "bid",     title = "Bid now",    w = 80,  j = "RIGHT" },
    { key = "worth",   title = "Worth",      w = 80,  j = "RIGHT" },
    { key = "ends",    title = "Ends",       w = 55,  j = "CENTER" },
    { key = "speed",   title = "Sells/day",  w = 55,  j = "RIGHT" },
    { key = "profit",  title = "Profit",     w = 80,  j = "RIGHT" },
    { key = "roi",     title = "ROI",        w = 55,  j = "RIGHT" },
}
local CONF_TEXT = { SAFE = "|cff40ff40Safe|r", HIGH = "|cff80ff80High|r", UNKNOWN = "|cffffd100Unknown|r" }

local MOVER_COLS = {
    { key = "item",    title = "Item",       w = 240, j = "LEFT" },
    { key = "before",  title = "Before",     w = 100, j = "RIGHT" },
    { key = "now",     title = "Today",      w = 100, j = "RIGHT" },
    { key = "change",  title = "Change",     w = 80,  j = "RIGHT" },
    { key = "q",       title = "Listed",     w = 70,  j = "RIGHT" },
    { key = "speed",   title = "Sells/day",  w = 80,  j = "RIGHT" },
}

local SMELT_COLS = {
    { key = "item",    title = "Ore",        w = 150, j = "LEFT" },
    { key = "qty",     title = "Have",       w = 40,  j = "RIGHT" },
    { key = "bars",    title = "Bars",       w = 40,  j = "RIGHT" },
    { key = "orep",    title = "Ore (ea)",   w = 70,  j = "RIGHT" },
    { key = "barp",    title = "Bar (ea)",   w = 70,  j = "RIGHT" },
    { key = "sell",    title = "Sell ore",   w = 85,  j = "RIGHT" },
    { key = "smelt",   title = "Smelt+sell", w = 85,  j = "RIGHT" },
    { key = "diff",    title = "Difference", w = 85,  j = "RIGHT" },
    { key = "verdict", title = "Do this",    w = 70,  j = "CENTER" },
}

local CRAFT_COLS = {
    { key = "item",    title = "Make",         w = 160, j = "LEFT" },
    { key = "prof",    title = "Profession",   w = 80,  j = "LEFT" },
    { key = "n",       title = "How many",     w = 60,  j = "RIGHT" },
    { key = "mats",    title = "Mats if sold", w = 80,  j = "RIGHT" },
    { key = "supply",  title = "Buy",          w = 70,  j = "RIGHT" },
    { key = "product", title = "Crafted sells", w = 85, j = "RIGHT" },
    { key = "diff",    title = "Gain",         w = 75,  j = "RIGHT" },
    { key = "verdict", title = "Do this",      w = 75,  j = "CENTER" },
}

local TABS = {
    { key = "BRIEF",   label = "Briefing" },
    { key = "BAGS",    label = "My Bags" },
    { key = "DEALS",   label = "Deals" },
    { key = "MOVERS",  label = "Movers" },
    { key = "SMELT",   label = "Smelt" },
    { key = "CRAFT",   label = "Craft" },
    { key = "AUCTIONS", label = "Auctions" },
    { key = "SESSION", label = "Session" },
}

-- Tabs that live in their own files register here:
-- { cols, list(), fill(row, data, cells, ItemLabel), tooltip(data), summary() -> text, status,
--   onClick(data), buttons = { { text, width, onClick, tooltip } } }
ns.extraTabs = ns.extraTabs or {}
function UI.RegisterTab(key, def) ns.extraTabs[key] = def end
local TEXT_TABS = { BRIEF = true, SESSION = true }

local function ColsFor(t)
    if t == "BAGS" then return BAG_COLS
    elseif t == "DEALS" then return ns.dealView == "BIDS" and BID_COLS or DEAL_COLS
    elseif t == "MOVERS" then return MOVER_COLS
    elseif t == "SMELT" then return SMELT_COLS
    elseif t == "CRAFT" then return CRAFT_COLS
    elseif ns.extraTabs[t] then return ns.extraTabs[t].cols end
    return {}
end

local filteredCache = {}
local function FilteredDeals()
    local src = ns.dealView == "BIDS" and ns.bidDeals or ns.deals
    local f, quick = ns.S.dealFilter or "ALL", ns.S.quickOnly
    if f == "ALL" and not quick then return src end
    wipe(filteredCache)
    for _, d in ipairs(src) do
        d.cat = (d.cat == "OTHER" or not d.cat) and ns.ItemCategory(d.itemID) or d.cat -- late-loaded items
        if ns.MatchesCategory(d.cat, f) and (not quick or ns.IsQuickFlip(d)) then
            filteredCache[#filteredCache + 1] = d
        end
    end
    return filteredCache
end

local function ListFor(t)
    if t == "BAGS" then return ns.items
    elseif t == "DEALS" then return FilteredDeals()
    elseif t == "MOVERS" then return ns.movers or {}
    elseif t == "SMELT" then
        local ok, list = pcall(ns.SmeltList)
        return ok and list or {}
    elseif t == "CRAFT" then
        local ok, list = pcall(ns.CraftList)
        return ok and list or {}
    elseif ns.extraTabs[t] then
        local ok, list = pcall(ns.extraTabs[t].list)
        return ok and list or {}
    end
    return {}
end

local KIND_TEXT = {
    VENDOR   = "|cff40ff40To vendor|r",
    FLIP     = "|cffffd100Flip|r",
    DIP      = "|cff40c0ffDip|r",
    MERCHANT = "|cffff80ffFrom vendor|r",
}
local KIND_HELP = {
    VENDOR   = "AH to vendor: listed below what a vendor pays.",
    FLIP     = "Flip: cheap listings well under the next seller's price.",
    DIP      = "Dip: well below its usual price over recent days.",
    MERCHANT = "Vendor to AH: a merchant sells it for less than the AH pays.",
}

-- Items the client hasn't cached yet have no name at first. Look them up live every
-- time we draw, ask the game to load them, and refresh when the data arrives.
local requested = {}
local function LookUp(itemID)
    if not itemID then return end
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if name then
        ns.db.names = ns.db.names or {}
        ns.db.names[itemID] = name
        return name, link, icon
    end
    if not requested[itemID] then
        requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    -- Fallback 1: the auction house's own item info (what the Buy tab uses)
    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, C_AuctionHouse.MakeItemKey(itemID))
        if ok and info and info.itemName then
            ns.db.names = ns.db.names or {}
            ns.db.names[itemID] = info.itemName
            local color = info.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality]
            local label = color and (color.hex .. info.itemName .. "|r") or info.itemName
            return label, nil, info.iconFileID
        end
    end
    -- Fallback 2: a name we saw before
    local saved = ns.db.names and ns.db.names[itemID]
    if saved then return saved, nil, nil end
end

local function ItemLabel(link, name, itemID)
    if link then return link end
    local n, l = LookUp(itemID)
    if l then return l end
    if n or name then return n or name end
    return "|cff808080Loading item...|r"
end

-- Patches a deal / mover / bag record in place once its data has loaded
local function Resolve(d)
    if not d or (d.link and d.icon) then return d end
    local n, l, icon = LookUp(d.itemID)
    d.name = d.name or n
    d.link = d.link or l
    d.icon = d.icon or icon or (d.itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(d.itemID))
    return d
end

local function ShowItemTooltip(d)
    if d.link then GameTooltip:SetHyperlink(d.link)
    elseif d.itemID then GameTooltip:SetItemByID(d.itemID)
    else GameTooltip:SetText(ItemLabel(nil, d.name, d.itemID)) end
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------
local function MakeButton(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildHeader()
    local cols = ColsFor(tab)
    local sum = 0
    for _, c in ipairs(cols) do sum = sum + c.w end
    local k = (sum > 0) and math.max(0.5, (frame:GetWidth() - 36) / sum) or 1
    local x = 0
    for i = 1, 9 do
        local h = frame.headers[i]
        local c = cols[i]
        if c then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", x + 4, 0)
            h:SetWidth(c.w * k - 6)
            h:SetJustifyH(c.j)
            h:SetText(c.title)
            h:Show()
            x = x + c.w * k
        else
            h:Hide()
        end
    end
    for _, row in ipairs(rows) do
        x = 0
        for i = 1, 9 do
            local fs, c = row.cells[i], cols[i]
            if c then
                fs:ClearAllPoints()
                local pad = (i == 1) and 24 or 4
                fs:SetPoint("LEFT", row, "LEFT", x + pad, 0)
                fs:SetWidth(c.w * k - pad - 2)
                fs:SetJustifyH(c.j)
                fs:Show()
                x = x + c.w * k
            else
                fs:Hide()
            end
        end
    end
end

local function RowTooltip(row)
    local d = row.data
    if not d then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if ns.extraTabs[tab] then
        Resolve(d); ShowItemTooltip(d)
        if ns.extraTabs[tab].tooltip then ns.extraTabs[tab].tooltip(d) end
        GameTooltip:Show()
        return
    end
    if tab == "CRAFT" then
        local c = d
        local name = C_Item.GetItemInfo(c.r.out) or c.r.name
        GameTooltip:AddLine(("%s  |cff999999(%s)|r"):format(name, c.r.prof or ""), 1, 0.82, 0)
        GameTooltip:AddLine(ns.CraftAdvice(c), 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(c.kind == "FLIP" and ("Buying materials for %d craft%s:"):format(c.n, c.n == 1 and "" or "s")
            or ("Your materials for %d craft%s:"):format(c.n, c.n == 1 and "" or "s"), 1, 0.82, 0)
        for _, p in ipairs(c.parts or {}) do
            local how = ({ AH = "AH", vendor = "vendor", buy = "buy from vendor", have = "have" })[p.how] or p.how or ""
            GameTooltip:AddDoubleLine(("  %d x %s"):format(p.n, C_Item.GetItemInfo(p.id) or ("item " .. p.id)),
                ("%s  %s"):format(how, ns.Money(p.value or 0)), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        if c.product then
            GameTooltip:AddDoubleLine(("Crafted %d sell for (%s)"):format(c.n * c.r.made, c.productVia or "AH"), ns.Money(c.product), 1, 1, 1)
        end
        if c.kind == "FLIP" then
            local demand = ns.MarketStats(c.r.out)
            GameTooltip:AddLine(demand and ("Sized to what sells in about 2 days (%.1f a day)."):format(demand * 24)
                or "Sell speed not learned yet - start with one. Full scans 15+ min apart teach it.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine(("Values are what you'd keep: lowest AH price minus 1c, the %.0f%% cut and likely lost deposits - or the vendor price if higher."):format(ns.S.ahCut * 100), 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Click to search the AH for it.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
        return
    end
    if tab == "SMELT" then
        local c = d
        local oreName = C_Item.GetItemInfo(c.ore) or "Ore"
        local barName = C_Item.GetItemInfo(c.bar) or "Bar"
        GameTooltip:AddLine(oreName .. " -> " .. barName, 1, 0.82, 0)
        GameTooltip:AddLine(ns.SmeltAdvice(c), 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Recipe", ("%d ore -> %d bar (%s)"):format(c.ratio, c.out, c.recipe.source), 1, 1, 1, 0.8, 0.8, 0.8)
        if c.sellValue then
            GameTooltip:AddDoubleLine(("Sell %d ore (%s)"):format(c.qty, c.sellVia or "AH"), ns.Money(c.sellValue), 1, 1, 1)
            GameTooltip:AddDoubleLine(("Smelt to %d bars (%s)%s"):format(c.bars, c.barVia or "AH",
                c.left > 0 and (", sell " .. c.left .. " leftover ore") or ""), ns.Money(c.smeltValue), 1, 1, 1)
        end
        GameTooltip:AddLine(("Values are what you'd keep: lowest AH price minus 1c, the %.0f%% cut, and deposits you'd likely lose for how fast it sells - or the vendor price if that's higher."):format(ns.S.ahCut * 100), 0.6, 0.6, 0.6, true)
        if c.perStack then GameTooltip:AddLine("You have none of this ore - compared per 20.", 0.6, 0.6, 0.6, true) end
        GameTooltip:AddLine("Click to search the AH for the bar.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
        return
    end
    if tab == "BAGS" then
        Resolve(d); ShowItemTooltip(d)
        local r = d.result
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("TwizAH breakdown", 0.2, 1, 0.6)
        if r and r.postUnit then
            GameTooltip:AddDoubleLine("Lowest on AH" .. (d.ownLowest and " (yours)" or ""), ns.Money(d.market), 1, 1, 1)
            if d.listedQty then GameTooltip:AddDoubleLine("Listed on AH", tostring(d.listedQty), 1, 1, 1, 1, 1, 1) end
            GameTooltip:AddDoubleLine("Your price x" .. d.qty, ns.Money(r.gross), 1, 1, 1)
            GameTooltip:AddDoubleLine(("AH cut (%.0f%%)"):format(ns.S.ahCut * 100), ns.Money(-r.cut), 1, 1, 1)
            GameTooltip:AddDoubleLine("Take-home if it sells", ns.Money(r.netIfSold), 1, 1, 1)
            GameTooltip:AddLine(" ")
            for dd = 1, 3 do
                local dep = d.deposit and d.deposit[dd]
                local mark = (dd == r.duration) and "|cff40ff40> |r" or "   "
                local pr = (d.rates and d.rates[dd]) or ns.S.sellRate[dd]
                GameTooltip:AddDoubleLine(("%s%s  deposit %s, %d%% sell"):format(mark, ns.DURATION_LABEL[dd],
                    dep and ns.Money(dep) or "?", pr * 100), ns.Money(r.ev[dd]), 1, 1, 1)
            end
            GameTooltip:AddLine("Expected = take-home minus deposits you'd likely lose to expirations.", 0.6, 0.6, 0.6, true)
            local ri = d.rateInfo
            if ri then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Sell chance from", ri.source, 1, 1, 1, 0.2, 1, 0.6)
                if ri.demand then
                    GameTooltip:AddDoubleLine("Bought per day (cheap listings)", ("%.1f"):format(ri.demand * 24), 1, 1, 1, 1, 1, 1)
                    GameTooltip:AddDoubleLine("Undercut about every",
                        ri.under > 0 and ("%.1f h"):format(1 / ri.under) or "rarely", 1, 1, 1, 1, 1, 1)
                    GameTooltip:AddDoubleLine("Based on", ("%d scan pairs, %.1f h watched"):format(ri.pairs or 0, ri.hours or 0), 1, 1, 1, 0.7, 0.7, 0.7)
                end
                if ri.ownTotal > 0 then
                    GameTooltip:AddDoubleLine("Your past posts", ("%d of %d sold"):format(ri.ownSold, ri.ownTotal), 1, 1, 1, 1, 1, 1)
                end
                if ri.source == "default" then
                    GameTooltip:AddLine("No sales data yet: using starting guesses. Full scans 15+ min apart teach it.", 1, 0.5, 0.25, true)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Vendor instead", ns.Money(r.vendorTotal), 1, 1, 1)
            GameTooltip:AddDoubleLine("AH advantage", ns.Money(r.gain), 1, 1, 1)
            if r.depositEstimated then
                GameTooltip:AddLine("Deposit not reported by the game - using fallback.", 1, 0.5, 0.25, true)
            end
        elseif d.noListings then
            GameTooltip:AddLine("No one else is selling this. Price it yourself in the Sell tab -", 0.6, 0.8, 1, true)
            GameTooltip:AddLine("you set the market.", 0.6, 0.8, 1, true)
            if r then GameTooltip:AddDoubleLine("Vendor value", ns.Money(r.vendorTotal), 1, 1, 1) end
        else
            GameTooltip:AddLine("Waiting for AH data...", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to select, double-click to post.", 0.5, 0.5, 0.5)
    elseif tab == "MOVERS" then
        Resolve(d); ShowItemTooltip(d)
        GameTooltip:AddLine(" ")
        if d.change > 0 then
            GameTooltip:AddLine("Rising: if you hold some, now is a good time to list.", 0.2, 1, 0.6, true)
        else
            GameTooltip:AddLine("Falling: hold off selling, or buy if you think it rebounds.", 1, 0.5, 0.25, true)
        end
        GameTooltip:AddLine("Click to search the AH for it.", 0.5, 0.5, 0.5)
    else
        Resolve(d); ShowItemTooltip(d)
        GameTooltip:AddLine(" ")
        if d.kind == "BID" then
            GameTooltip:AddLine("Extremely low bid", 0.2, 1, 0.6)
            GameTooltip:AddDoubleLine("Bid to place now", ns.Money(d.bid), 1, 1, 1)
            if d.buyout and d.buyout > 0 then GameTooltip:AddDoubleLine("Its buyout", ns.Money(d.buyout), 1, 1, 1) end
            GameTooltip:AddDoubleLine("Vendor pays", ns.Money(d.vendorValue), 1, 1, 1)
            if d.relist then
                GameTooltip:AddDoubleLine(("Relist at %s (%s, %.0f%% sell)"):format(ns.Money(d.relist.unit),
                    ns.DURATION_LABEL[d.relist.d], d.relist.p * 100), ns.Money(d.relist.ev), 1, 1, 1)
            end
            GameTooltip:AddDoubleLine("Profit if you win", ns.Money(d.profit), 1, 1, 1)
            GameTooltip:AddDoubleLine("Then sell it to", d.sellVia == "vendor" and "a vendor" or "the AH", 1, 1, 1, 1, 1, 1)
            local ENDS = { [0] = "in under 30 minutes - best snipe", [1] = "within 2 hours", [2] = "within 12 hours", [3] = "in more than 12 hours" }
            if ENDS[d.timeLeft] then GameTooltip:AddDoubleLine("Ends", ENDS[d.timeLeft], 1, 1, 1, 1, 1, 1) end
            GameTooltip:AddLine(" ")
            if d.conf == "SAFE" then
                GameTooltip:AddLine("Safe: even selling to a vendor beats the bid.", 0.25, 1, 0.25, true)
            elseif d.conf == "HIGH" then
                GameTooltip:AddLine("High: sell speed is learned and it moves; relisting should pay.", 0.5, 1, 0.5, true)
            else
                GameTooltip:AddLine("Unknown: sell speed not learned yet. Riskier.", 1, 0.8, 0.2, true)
            end
            GameTooltip:AddLine((d.hasBids and "Someone has already bid - expect competition. " or "No bids yet. ")
                .. "You only win if you're the top bidder when it ends; bids with little time left are the best snipes. Your gold comes back if you're outbid.", 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("Click to find it in the Buy tab, then bid there.", 0.5, 0.5, 0.5)
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine(KIND_HELP[d.kind] or "", 0.2, 1, 0.6, true)
        if d.plan then GameTooltip:AddLine(d.plan, 1, 1, 1, true) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Cost", ns.Money(d.cost), 1, 1, 1)
        GameTooltip:AddDoubleLine("Expected profit", ns.Money(d.profit), 1, 1, 1)
        if d.deposit then
            GameTooltip:AddDoubleLine("Relist deposit (" .. ns.DURATION_LABEL[d.duration] .. ")", ns.Money(d.deposit), 1, 1, 1)
            GameTooltip:AddLine(("Profit is after the %.0f%% cut and the deposits you'd expect to lose to expirations."):format(ns.S.ahCut * 100), 0.6, 0.6, 0.6, true)
        end
        local ch = ns.ClearHours(d)
        if ch and ch > 0 then
            GameTooltip:AddDoubleLine("Expected to sell out in", ch < 1 and "under an hour" or ("about %d h"):format(ch + 0.5), 1, 1, 1, 1, 1, 1)
        end
        if d.kind ~= "VENDOR" and not d.known then
            GameTooltip:AddLine("Sell speed not learned yet: buy amount capped at 20. Do two full scans 15+ min apart.", 1, 0.5, 0.25, true)
        elseif d.speed and d.kind ~= "VENDOR" then
            GameTooltip:AddLine(("Buy amount sized to what sells in about 48h (%.1f a day)."):format(d.speed * 24), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:AddLine("Click to search the AH for it.", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function SearchAHFor(d)
    local name = d.name or (d.itemID and C_Item.GetItemInfo(d.itemID))
    if not name then ns.Print("Item data still loading - try again in a second."); return end
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if bar and bar.SearchBox then
        if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
            pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
        end
        bar.SearchBox:SetText(name)
        if bar.StartSearch then pcall(bar.StartSearch, bar) end
    end
end

local function CreateRows()
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", 0, -16 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
        row:RegisterForClicks("LeftButtonUp")
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints(); row.sel:SetColorTexture(0.2, 0.6, 1, 0.18); row.sel:Hide()
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
            bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03)
        end
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18); row.icon:SetPoint("LEFT", 2, 0)
        row.cells = {}
        for c = 1, 9 do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            if tab == "BAGS" then
                selected = self.data
                UI.Refresh()
            elseif ns.extraTabs[tab] and ns.extraTabs[tab].onClick then
                ns.extraTabs[tab].onClick(self.data)
            elseif ns.ahOpen then
                if tab == "SMELT" then SearchAHFor({ itemID = self.data.bar })
                elseif tab == "CRAFT" then SearchAHFor({ itemID = self.data.r.out })
                else SearchAHFor(self.data) end
            end
        end)
        row:SetScript("OnDoubleClick", function(self)
            if tab == "BAGS" and self.data and not self.data.posted then ns.Post(self.data) end
        end)
        rows[i] = row
    end
end

-- size-dependent bits: how many rows fit, widths of the text and filter bar
local function Layout()
    if not frame then return end
    local top = (tab == "DEALS") and 92 or 64
    visible = math.max(3, math.min(ROWS, math.floor((frame:GetHeight() - top - 16 - 60) / ROW_H)))
    frame.filterBar:SetWidth(frame:GetWidth() - 24)
    local tw = math.max(56, math.min(84, math.floor((frame:GetWidth() - 130 - 36) / #TABS) - 4))
    for _, b in pairs(frame.tabs) do b:SetWidth(tw) end
    frame.text:SetWidth(frame:GetWidth() - 36)
    BuildHeader()
end

local function SetTab(t)
    tab = t; offset = 0
    frame.listTop:ClearAllPoints()
    frame.listTop:SetPoint("TOPLEFT", 12, t == "DEALS" and -92 or -64)
    frame.filterBar:SetShown(t == "DEALS")
    for key, b in pairs(frame.tabs) do b:SetEnabled(key ~= t) end
    frame.text:SetShown(TEXT_TABS[t] or false)
    frame.postBest:SetShown(t == "BAGS")
    frame.postSel:SetShown(t == "BAGS")
    frame.postMarg:SetShown(t == "BAGS")
    frame.postAll:SetShown(t == "BAGS")
    frame.scanBags:SetShown(t == "BAGS")
    frame.fullScan:SetShown(t == "DEALS" or t == "MOVERS" or t == "BRIEF" or t == "SMELT" or t == "CRAFT")
    frame.lowBids:SetShown(t == "DEALS")
    frame.buyAll:SetShown(t == "CRAFT")
    for key, def in pairs(ns.extraTabs) do
        for _, b in ipairs(def.__buttons or {}) do b:SetShown(key == t) end
        if key == t and def.onShow then pcall(def.onShow) end
    end
    frame.cancelBuy:SetShown(t == "CRAFT")
    Layout()
    UI.Refresh()
end

local function Create()
    frame = CreateFrame("Frame", "TwizAHFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    frame:SetMovable(true); frame:EnableMouse(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -12)
    frame.title:SetText("TwizAH")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    frame.tabs = {}
    local prev
    for _, t in ipairs(TABS) do
        local b = MakeButton(frame, t.label, 72, function() SetTab(t.key) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 130, -10) end
        frame.tabs[t.key] = b
        prev = b
    end

    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.summary:SetPoint("TOPLEFT", 14, -40)
    frame.summary:SetPoint("RIGHT", -14, 0)
    frame.summary:SetJustifyH("LEFT")

    frame.listTop = CreateFrame("Frame", nil, frame)
    frame.listTop:SetPoint("TOPLEFT", 12, -64)
    frame.listTop:SetSize(1, 1)

    -- category filter bar (Deals tab)
    frame.filterBar = CreateFrame("Frame", nil, frame)
    frame.filterBar:SetPoint("TOPLEFT", 12, -60)
    frame.filterBar:SetSize(WIDTH - 24, 24)
    frame.filterButtons = {}
    local prevF
    for _, c in ipairs(ns.CATEGORIES) do
        local b = CreateFrame("Button", nil, frame.filterBar, "UIPanelButtonTemplate")
        b:SetHeight(20)
        b:SetText(c.short or c.label)
        b:SetNormalFontObject("GameFontNormalSmall"); b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontHighlightSmall")
        b:SetWidth(math.max(34, b:GetFontString():GetStringWidth() + 14))
        if prevF then b:SetPoint("LEFT", prevF, "RIGHT", 2, 0) else b:SetPoint("LEFT", 0, 0) end
        b:SetScript("OnClick", function() ns.S.dealFilter = c.key; offset = 0; UI.Refresh() end)
        frame.filterButtons[c.key] = b
        prevF = b
    end
    frame.quick = CreateFrame("CheckButton", nil, frame.filterBar, "UICheckButtonTemplate")
    frame.quick:SetSize(22, 22)
    frame.quick:SetPoint("LEFT", prevF, "RIGHT", 6, 0)
    frame.quick.label = frame.quick:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.quick.label:SetPoint("LEFT", frame.quick, "RIGHT", 0, 1)
    frame.quick.label:SetText("Quick flips")
    frame.quick:SetScript("OnClick", function(self) ns.S.quickOnly = self:GetChecked() and true or false; offset = 0; UI.Refresh() end)
    frame.quick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Quick flips")
        GameTooltip:AddLine("Only deals that turn around fast: vendor flips (instant), or relists the learned sell rate says will clear within about 24 hours.", 1, 1, 1, true)
        GameTooltip:AddLine("Items with no learned sell rate are hidden while this is on.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    frame.quick:SetScript("OnLeave", GameTooltip_Hide)

    frame.headers = {}
    for i = 1, 9 do
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.headers[i] = h
    end
    CreateRows()

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("TOPLEFT", frame.listTop, "TOPLEFT", 4, 0)
    frame.text:SetWidth(WIDTH - 36)
    frame.text:SetJustifyH("LEFT"); frame.text:SetJustifyV("TOP")
    frame.text:SetSpacing(6)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local n = #ListFor(tab)
        offset = math.max(0, math.min(math.max(0, n - visible), offset - delta * 3))
        UI.Refresh()
    end)

    -- Page buttons: shown whenever a list has more items than fit in the window
    local function PageInfo()
        local n = #ListFor(tab)
        local pages = math.max(1, math.ceil(n / math.max(1, visible)))
        return n, pages
    end
    frame.pager = CreateFrame("Frame", nil, frame)
    frame.pager:SetSize(150, 22)
    frame.pager:SetPoint("BOTTOMRIGHT", -12, 36)
    frame.pagePrev = MakeButton(frame.pager, "< Prev", 56, function()
        offset = math.max(0, offset - visible); UI.Refresh()
    end)
    frame.pagePrev:SetPoint("LEFT", 0, 0)
    frame.pageNext = MakeButton(frame.pager, "Next >", 56, function()
        local _, pages = PageInfo()
        offset = math.min(offset + visible, (pages - 1) * visible); UI.Refresh()
    end)
    frame.pageNext:SetPoint("RIGHT", 0, 0)
    frame.pageText = frame.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pageText:SetPoint("CENTER", 0, 0)
    frame.PageInfo = PageInfo

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("BOTTOMLEFT", 14, 40)
    frame.status:SetPoint("RIGHT", frame.pager, "LEFT", -8, 0)
    frame.status:SetJustifyH("LEFT")

    frame.scanBags = MakeButton(frame, "Rescan Bags", 100, function() ns.StartBagScan() end)
    frame.scanBags:SetPoint("BOTTOMLEFT", 12, 12)
    frame.postBest = MakeButton(frame, "Post Next Best", 120, function() ns.PostNextBest() end)
    frame.postBest:SetPoint("LEFT", frame.scanBags, "RIGHT", 6, 0)
    frame.postSel = MakeButton(frame, "Post Selected", 110, function()
        if selected and not selected.posted then ns.Post(selected) else ns.Print("Select an item first.") end
    end)
    frame.postSel:SetPoint("LEFT", frame.postBest, "RIGHT", 6, 0)
    frame.postMarg = MakeButton(frame, "Post Marginal", 140, function() ns.PostNextMarginal() end)
    frame.postMarg:SetPoint("LEFT", frame.postSel, "RIGHT", 6, 0)
    frame.postMarg:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Post Marginal")
        GameTooltip:AddLine("Posts the next item that beats the vendor but by less than your minimum gain. Only items that still turn a profit.", 1, 1, 1, true)
        GameTooltip:AddLine("The game allows one post per click - keep clicking, or bind a key in Options > Keybindings > AddOns > TwizAH.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    frame.postMarg:SetScript("OnLeave", GameTooltip_Hide)
    frame.postAll = MakeButton(frame, "Post All", 110, function() ns.PostAll() end)
    frame.postAll:SetPoint("LEFT", frame.postMarg, "RIGHT", 6, 0)
    frame.postAll:EnableMouseWheel(true)
    frame.postAll:SetScript("OnMouseWheel", function() ns.PostAll() end)
    frame.postAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Post All")
        GameTooltip:AddLine("Works down everything in your bags worth posting: the best items first, then the marginal ones that still turn a profit. Skips items that are worth more at a vendor, quest items and tools.", 1, 1, 1, true)
        GameTooltip:AddLine("Fastest: spin your mouse wheel - each notch posts the next item. The game needs a real click, key or wheel notch for every post, so fully automatic posting isn't possible.", 0.4, 1, 0.4, true)
        GameTooltip:Show()
    end)
    frame.postAll:SetScript("OnLeave", GameTooltip_Hide)
    frame.fullScan = MakeButton(frame, "Full AH Scan", 120, function() ns.StartFullScan() end)
    frame.fullScan:SetPoint("BOTTOMLEFT", 12, 12)
    frame.lowBids = MakeButton(frame, "Low Bids", 130, function()
        ns.dealView = (ns.dealView == "BIDS") and "BUYOUT" or "BIDS"
        offset = 0; BuildHeader(); UI.Refresh()
    end)
    frame.lowBids:SetPoint("LEFT", frame.fullScan, "RIGHT", 6, 0)
    frame.lowBids:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Low Bids")
        GameTooltip:AddLine(("Auctions whose next bid is at most %d%% of what the item is worth - vendor value or what you'd net relisting it - and that are safe or likely to pay off."):format(ns.S.bidMaxPct * 100), 1, 1, 1, true)
        GameTooltip:AddLine("Click again to go back to buyout deals.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame.lowBids:SetScript("OnLeave", GameTooltip_Hide)

    frame.buyAll = MakeButton(frame, "Buy All Supplies", 260, function() ns.BuyAllSupplies() end)
    frame.buyAll:SetPoint("LEFT", frame.fullScan, "RIGHT", 6, 0)
    frame.buyAll:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Buy All Supplies")
        GameTooltip:AddLine("Buys what every profitable craft on this tab is missing (Craft from bags + Buy & craft), minus what's already in your bags and bank.", 1, 1, 1, true)
        GameTooltip:AddLine("The game needs two clicks per reagent: one gets the price, one confirms. A red price means over 1.5x its usual market price.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Reagents that are cheaper from a vendor get a 'Buy Craft Supplies' button on the merchant window instead.", 0.7, 0.7, 0.7, true)
        local ah, ahCost, vend, vendCost = ns.SupplySummary()
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(("From the AH (%d)"):format(ah), ns.Money(ahCost), 1, 1, 1)
        GameTooltip:AddDoubleLine(("From vendors (%d)"):format(vend), ns.Money(vendCost), 1, 1, 1)
        GameTooltip:Show()
    end)
    frame.buyAll:SetScript("OnLeave", GameTooltip_Hide)
    frame.cancelBuy = MakeButton(frame, "Cancel", 70, function() ns.CancelSupplyPurchase() end)
    frame.cancelBuy:SetPoint("LEFT", frame.buyAll, "RIGHT", 6, 0)

    for _, def in pairs(ns.extraTabs) do
        def.__buttons = {}
        local prevB
        for _, bd in ipairs(def.buttons or {}) do
            local b = MakeButton(frame, bd.text, bd.width or 120, function() bd.onClick(); UI.Refresh() end)
            if prevB then b:SetPoint("LEFT", prevB, "RIGHT", 6, 0) else b:SetPoint("BOTTOMLEFT", 12, 12) end
            if bd.tooltip then
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    bd.tooltip()
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", GameTooltip_Hide)
            end
            b.def = bd
            b:Hide()
            def.__buttons[#def.__buttons + 1] = b
            prevB = b
        end
    end

    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("BOTTOMRIGHT", -14, 18)
    help:SetText("/dw help for settings")

    local resizing
    ns.resetSize = ns.MakeResizable(frame, ns.S, {
        minW = 560, minH = 300, maxW = 1600, maxH = 1100, defaultW = WIDTH, defaultH = HEIGHT,
        onResize = function()
            if resizing then return end
            resizing = true; Layout(); UI.Refresh(); resizing = false
        end })
    SetTab("BRIEF")
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function FillBagRow(row, it)
    Resolve(it)
    local r = it.result or {}
    local verdict = it.posted and "POSTED" or r.verdict or "NOPRICE"
    row.icon:SetTexture(it.icon)
    local c = row.cells
    c[1]:SetText(ItemLabel(it.link, nil, it.itemID))
    c[2]:SetText(it.qty)
    c[3]:SetText(r.postUnit and ns.Money(r.postUnit) or (it.noListings and "|cff40c0ffnone|r" or "..."))
    local demand = ns.MarketStats(it.itemID)
    c[4]:SetText(demand and ("%.1f"):format(demand * 24) or "|cff808080?|r")
    c[5]:SetText(r.duration and ns.DURATION_LABEL[r.duration] or "")
    c[6]:SetText(r.deposit and ns.Money(r.deposit) or "")
    c[7]:SetText(r.bestEV and ns.Money(r.bestEV) or "")
    c[8]:SetText(ns.Money(r.vendorTotal or (it.vendor or 0) * it.qty))
    c[9]:SetText(ns.VERDICT_TEXT[verdict])
    row.sel:SetShown(selected == it)
end

local function FillBidRow(row, d)
    Resolve(d)
    row.icon:SetTexture(d.icon or 134400)
    local c = row.cells
    c[1]:SetText(ItemLabel(d.link, d.name, d.itemID))
    c[2]:SetText(CONF_TEXT[d.conf])
    c[3]:SetText(d.qty)
    c[4]:SetText(ns.Money(d.bid))
    c[5]:SetText(ns.Money(d.worth))
    local BAND = { [0] = "|cff40ff40<30m|r", [1] = "|cffffd100<2h|r", [2] = "<12h", [3] = "|cff808080>12h|r" }
    c[6]:SetText(BAND[d.timeLeft] or "?")
    c[7]:SetText(d.speed and ("%.1f"):format(d.speed * 24) or "|cff808080?|r")
    c[8]:SetText(ns.Money(d.profit))
    c[9]:SetText(("%.0f%%"):format(d.roi * 100))
    row.sel:Hide()
end

local function FillDealRow(row, d)
    if d.kind == "BID" then return FillBidRow(row, d) end
    Resolve(d)
    row.icon:SetTexture(d.icon or 134400)
    local c = row.cells
    c[1]:SetText(ItemLabel(d.link, d.name, d.itemID))
    c[2]:SetText(KIND_TEXT[d.kind] or d.kind)
    c[3]:SetText(d.qty)
    c[4]:SetText(ns.Money(d.buyBelow))
    c[5]:SetText(ns.Money(d.cost))
    c[6]:SetText(ns.Money(d.target))
    c[7]:SetText(d.kind == "VENDOR" and "|cff808080n/a|r" or (d.speed and ("%.1f"):format(d.speed * 24) or "|cff808080?|r"))
    c[8]:SetText(ns.Money(d.profit))
    c[9]:SetText(("%.0f%%"):format((d.roi or 0) * 100))
    row.sel:Hide()
end

local function FillSmeltRow(row, c)
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(c.ore)
    if not name and C_Item.RequestLoadItemDataByID then
        requested[c.ore] = true; C_Item.RequestLoadItemDataByID(c.ore)
    end
    if not C_Item.GetItemInfo(c.bar) and C_Item.RequestLoadItemDataByID then
        requested[c.bar] = true; C_Item.RequestLoadItemDataByID(c.bar)
    end
    row.icon:SetTexture(icon or 134400)
    local x = row.cells
    x[1]:SetText(ItemLabel(link, name, c.ore))
    x[2]:SetText(c.perStack and "|cff808080(20)|r" or c.qty)
    x[3]:SetText(c.bars)
    x[4]:SetText(c.oreUnit and ns.Money(c.oreUnit) or "|cff808080?|r")
    x[5]:SetText(c.barUnit and ns.Money(c.barUnit) or "|cff808080?|r")
    x[6]:SetText(c.sellValue and ns.Money(c.sellValue) or "")
    x[7]:SetText(c.smeltValue and ns.Money(c.smeltValue) or "")
    if c.diff then
        x[8]:SetText((c.diff >= 0 and "|cff40ff40+" or "|cffffd100-") .. ns.Money(math.abs(c.diff)) .. "|r")
    else
        x[8]:SetText("")
    end
    x[9]:SetText(ns.SMELT_TEXT[c.verdict] or "")
    row.sel:Hide()
end

local function FillCraftRow(row, c)
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(c.r.out)
    if not name and C_Item.RequestLoadItemDataByID then
        requested[c.r.out] = true; C_Item.RequestLoadItemDataByID(c.r.out)
    end
    row.icon:SetTexture(icon or 134400)
    local x = row.cells
    x[1]:SetText(ItemLabel(link, name or c.r.name, c.r.out))
    x[2]:SetText("|cffaaaaaa" .. (c.r.prof or "") .. "|r")
    x[3]:SetText(c.kind == "FLIP" and ("|cff40c0ff%d|r"):format(c.n * c.r.made) or tostring(c.n * c.r.made))
    x[4]:SetText(c.kind == "FLIP" and "|cff808080-|r" or ns.Money(c.matsValue or 0))
    x[5]:SetText((c.supplies or 0) > 0 and ns.Money(c.supplies) or "")
    x[6]:SetText(c.product and ns.Money(c.product) or "")
    if c.diff then
        x[7]:SetText((c.diff >= 0 and "|cff40ff40+" or "|cffffd100-") .. ns.Money(math.abs(c.diff)) .. "|r")
    else
        x[7]:SetText("")
    end
    x[8]:SetText(ns.CRAFT_TEXT[c.verdict] or "")
    row.sel:Hide()
end

local function FillMoverRow(row, m)
    Resolve(m)
    row.icon:SetTexture(m.icon or 134400)
    local c = row.cells
    c[1]:SetText(ItemLabel(m.link, m.name, m.itemID))
    c[2]:SetText(ns.Money(m.before))
    c[3]:SetText(ns.Money(m.now))
    c[4]:SetText(("%s%+.0f%%|r"):format(m.change > 0 and "|cff40ff40" or "|cffff4040", m.change * 100))
    c[5]:SetText(m.q or "")
    local demand = ns.MarketStats(m.itemID)
    c[6]:SetText(demand and ("%.1f"):format(demand * 24) or "|cff808080?|r")
    row.sel:Hide()
end

local function Ago(t)
    if not t or t == 0 then return "never" end
    local s = time() - t
    if s < 3600 then return ("%dm ago"):format(s / 60) end
    if s < 86400 then return ("%dh ago"):format(s / 3600) end
    return ("%dd ago"):format(s / 86400)
end

-- Values your bags even when the AH is closed, from remembered prices
local function BagSnapshot()
    if #ns.items > 0 then
        local ah, vend, vendorBetter, toPost, ev, evVendor, risk = 0, 0, 0, 0, 0, 0, 0
        for _, it in ipairs(ns.items) do
            local r = it.result
            if r and not it.posted then
                vend = vend + (r.vendorTotal or 0)
                if r.netIfSold then ah = ah + r.netIfSold end
                if r.verdict == "VENDOR" then vendorBetter = vendorBetter + 1 end
                if r.verdict == "POST" then
                    toPost = toPost + 1; ev = ev + r.bestEV; evVendor = evVendor + r.vendorTotal
                    risk = risk + (r.deposit or 0)
                end
            end
        end
        return ah, vend, vendorBetter, toPost, ev, evVendor, risk, true
    end
    local ah, vend, vendorBetter = 0, 0, 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                local qty = info.stackCount or 1
                local v = (select(11, C_Item.GetItemInfo(info.itemID)) or 0) * qty
                local p = ns.KnownPrice(info.itemID)
                vend = vend + v
                if p then
                    local net = math.floor(p * qty * (1 - ns.S.ahCut))
                    ah = ah + net
                    if v > net then vendorBetter = vendorBetter + 1 end
                end
            end
        end
    end
    return ah, vend, vendorBetter
end

local function BriefingText()
    local L = {}
    local now, fresh, tracked = time(), 0, 0
    local seen = {}
    for id, m in pairs(ns.db.market) do
        seen[id] = true; tracked = tracked + 1
        if now - (m.t or 0) < 86400 then fresh = fresh + 1 end
    end
    for id, p in pairs(ns.db.prices) do
        if not seen[id] then
            tracked = tracked + 1
            if now - (p.t or 0) < 86400 then fresh = fresh + 1 end
        end
    end
    L[#L + 1] = ("Tracking %d items, %d with a price from the last 24 hours. Last full scan %s."):format(
        tracked, fresh, Ago(ns.db.lastFullScan))
    if ns.fullScanFailed then
        L[#L] = L[#L] .. " |cffff6060" .. (ns.fullScanStatus or "The last full scan didn't finish.") .. "|r"
    end

    if ns.OwnedSummary and ns.ownedQueried then
        local active, under, worth = ns.OwnedSummary()
        if under > 0 then
            L[#L + 1] = ("|cffff6060%d of your %d auctions are undercut|r%s (Auctions tab)."):format(under, active,
                worth > 0 and (" - %d worth cancelling and reposting"):format(worth) or "")
        elseif active > 0 then
            L[#L + 1] = ("All %d of your auctions are the cheapest of their kind."):format(active)
        end
    end

    -- how your own auctions have actually done
    local mr, s, e = ns.db.myRates or {}, 0, 0
    local parts = {}
    for d = 1, 3 do
        local m = mr[d]
        if m and (m.s + m.e) > 0 then
            s, e = s + m.s, e + m.e
            parts[#parts + 1] = ("%s %d/%d"):format(ns.DURATION_LABEL[d], m.s, m.s + m.e)
        end
    end
    local pending = 0
    for _, list in pairs(ns.db.pendingPosts or {}) do pending = pending + #list end
    if s + e > 0 then
        L[#L + 1] = ("Your auctions: |cff40ff40%d sold|r, %d expired (%.0f%% sell-through; by length %s)%s."):format(
            s, e, 100 * s / (s + e), table.concat(parts, ", "),
            pending > 0 and (", %d still listed or waiting in the mail"):format(pending) or "")
    elseif pending > 0 then
        L[#L + 1] = ("%d of your auctions are still listed or waiting in the mail. Results are learned from AH mail - open your mailbox now and then."):format(pending)
    end

    if not ns.hasTrendData then
        L[#L + 1] = "No market trend yet: it needs full scans from two different days."
    elseif #(ns.movers or {}) == 0 then
        L[#L + 1] = "The market is steady: nothing moved 10% or more since the last day scanned."
    else
        local up, down
        for _, m in ipairs(ns.movers) do
            if m.change > 0 and not up then up = m end
            if m.change < 0 and not down then down = m end
        end
        local parts = { ("%d items moved 10%%+."):format(#ns.movers) }
        if up then parts[#parts + 1] = ("Biggest riser: %s %+.0f%%."):format(ItemLabel(up.link, up.name, up.itemID), up.change * 100) end
        if down then parts[#parts + 1] = ("Biggest drop: %s %+.0f%%."):format(ItemLabel(down.link, down.name, down.itemID), down.change * 100) end
        L[#L + 1] = table.concat(parts, " ")
    end

    local okS, slist = pcall(ns.SmeltList)
    if okS and ns.smeltFromBags then
        local sm, g, so = 0, 0, 0
        for _, c in ipairs(slist) do
            if c.verdict == "SMELT" then sm = sm + 1; g = g + c.diff elseif c.verdict == "ORE" then so = so + 1 end
        end
        if sm > 0 then
            L[#L + 1] = ("Ore: smelting %d type%s into bars is worth |cff40ff40+%s|r over selling the ore (Smelt tab)."):format(sm, sm == 1 and "" or "s", ns.Money(g))
        elseif so > 0 then
            L[#L + 1] = "Ore: selling it as ore pays more than smelting right now (Smelt tab)."
        end
    end

    local okC, clist = pcall(ns.CraftList)
    if okC then
        local cn, cg, fn, fg = 0, 0, 0, 0
        for _, c in ipairs(clist) do
            if c.verdict == "CRAFT" then cn = cn + 1; cg = cg + c.diff
            elseif c.verdict == "FLIP" then fn = fn + 1; fg = fg + c.diff end
        end
        if cn > 0 or fn > 0 then
            L[#L + 1] = ("Crafting: %d recipe%s worth |cff40ff40+%s|r over selling your materials; %d buy-and-craft flip%s worth about |cff40c0ff+%s|r (Craft tab)."):format(
                cn, cn == 1 and "" or "s", ns.Money(cg), fn, fn == 1 and "" or "s", ns.Money(fg))
        end
    end

    local learned, sold, expired = ns.RatesSummary()
    if learned == 0 then
        L[#L + 1] = "Sell rates: still on starting guesses. Run full scans 15+ minutes apart (within 6 hours) and they'll be learned from what actually sells."
    else
        local own = (sold + expired) > 0 and ("; your auctions sold %d of %d (%.0f%%)"):format(sold, sold + expired, 100 * sold / (sold + expired)) or ""
        L[#L + 1] = ("Sell rates learned for %d items from the market%s."):format(learned, own)
    end

    local ah, vend, vendorBetter, toPost, ev, evVendor, risk, researched = BagSnapshot()
    L[#L + 1] = ("Your bags: %s on the auction house (after the cut), %s at a vendor. %d item%s worth more at a vendor."):format(
        ns.Money(ah), ns.Money(vend), vendorBetter, vendorBetter == 1 and " is" or "s are")
    if vendorBetter > 0 then
        local fresh = ns.lastBagResearch and (time() - ns.lastBagResearch) < ns.S.freshMinutes * 60
        if not ns.S.autoVendor then
            L[#L] = L[#L] .. " Auto-vendor is off (/dw autovendor on)."
        elseif fresh then
            L[#L] = L[#L] .. " Open any merchant and they'll be sold for you."
        else
            L[#L] = L[#L] .. (" Auto-vendor needs AH prices from the last %d minutes: open the AH first."):format(ns.S.freshMinutes)
        end
    end
    if researched then
        if toPost > 0 then
            L[#L + 1] = ("Post the %d recommended item%s: expect %s, |cff40ff40%s|r more than vendoring. Deposits up front: %s (you get them back when they sell)."):format(
                toPost, toPost == 1 and "" or "s", ns.Money(ev), ns.Money(ev - evVendor), ns.Money(risk))
        else
            L[#L + 1] = "Nothing in your bags beats the vendor after the cut and deposit risk right now."
        end
    else
        L[#L + 1] = "Open the Auction House to research your bags with live prices and real deposits."
    end

    if #ns.deals > 0 then
        local total, counts = 0, {}
        for _, d in ipairs(ns.deals) do total = total + d.profit; counts[d.kind] = (counts[d.kind] or 0) + 1 end
        L[#L + 1] = ("%d ways to profit right now, about %s in total: %d to vendor, %d flips, %d dips, %d from vendors. Best:"):format(
            #ns.deals, ns.Money(total), counts.VENDOR or 0, counts.FLIP or 0, counts.DIP or 0, counts.MERCHANT or 0)
        for i = 1, math.min(3, #ns.deals) do
            local d = ns.deals[i]
            L[#L] = L[#L] .. ("\n   %d. %s %s: spend %s, make %s"):format(i, KIND_TEXT[d.kind], ItemLabel(d.link, d.name, d.itemID),
                ns.Money(d.cost), ns.Money(d.profit))
        end
    end
    if #ns.bidDeals > 0 then
        local b = ns.bidDeals[1]
        L[#L + 1] = ("%d extremely low bids. Best: %s - bid %s, worth %s (%s)."):format(#ns.bidDeals,
            ItemLabel(b.link, b.name, b.itemID), ns.Money(b.bid), ns.Money(b.worth), CONF_TEXT[b.conf])
    end
    if #ns.deals > 0 then
    elseif ns.db.lastFullScan > 0 then
        L[#L + 1] = "No profitable buys in the last scan above your minimums (/dw minprofit, /dw minroi)."
    else
        L[#L + 1] = "Run a full AH scan to find profitable buys."
    end

    local s = ns.session
    if s.startMoney then
        L[#L + 1] = ("This session: %s gold change, %d posted."):format(ns.Money(GetMoney() - s.startMoney), s.posts)
    end
    return table.concat(L, "\n\n")
end

local function SessionText()
    local s = ns.session
    if not s.startMoney then return "Session starts at login." end
    local mins = math.max(1, (time() - s.start) / 60)
    local delta = GetMoney() - s.startMoney
    local L = {
        ("Playing for %dh %02dm."):format(mins / 60, mins % 60),
        ("Gold change: %s  (%s per hour)."):format(ns.Money(delta), ns.Money(delta / mins * 60)),
        ("Auctions posted: %d, worth %s after the cut if they all sell."):format(s.posts, ns.Money(s.postedValue)),
        ("Vendor value of those items: %s, so posting instead could add |cff40ff40%s|r."):format(
            ns.Money(s.vendorAvoided), ns.Money(s.postedValue - s.vendorAvoided)),
        ("Deposits paid this session: %s. You get these back on each sale; expired listings keep them."):format(ns.Money(s.deposits)),
        ("Auto-vendored: %d items for %s."):format(s.vendored, ns.Money(s.vendoredGold)),
    }
    return table.concat(L, "\n\n")
end

-- Many events ask for a redraw; draw at most ~10 times a second and only while visible.
local refreshQueued, lastRefresh = false, -1
local RefreshNow
function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    if refreshQueued then return end
    refreshQueued = true
    local wait = math.max(0, 0.1 - (GetTime() - lastRefresh))
    C_Timer.After(wait, function()
        refreshQueued = false
        lastRefresh = GetTime()
        RefreshNow()
    end)
end

RefreshNow = function()
    if not frame or not frame:IsShown() then return end
    local list = ListFor(tab)
    -- keep the page in range when the list shrinks (posting, vendoring) or the window resizes
    local pages = math.max(1, math.ceil(#list / math.max(1, visible)))
    offset = math.max(0, math.min(offset, (pages - 1) * visible))
    if frame.pager then
        local show = pages > 1 and not TEXT_TABS[tab]
        frame.pager:SetShown(show)
        if show then
            local page = (offset + visible >= #list) and pages or (math.floor(offset / visible) + 1)
            frame.pageText:SetText(("Page %d/%d"):format(page, pages))
            frame.pagePrev:SetEnabled(offset > 0)
            frame.pageNext:SetEnabled(page < pages)
        end
    end
    for i, row in ipairs(rows) do
        local data = (i <= visible) and list[i + offset] or nil
        row.data = data
        if data then
            if tab == "BAGS" then FillBagRow(row, data)
            elseif tab == "DEALS" then FillDealRow(row, data)
            elseif tab == "SMELT" then FillSmeltRow(row, data)
            elseif tab == "CRAFT" then FillCraftRow(row, data)
            elseif ns.extraTabs[tab] then
                Resolve(data)
                row.icon:SetTexture(data.icon or 134400)
                row.sel:Hide()
                ns.extraTabs[tab].fill(row, data, row.cells, ItemLabel)
            else FillMoverRow(row, data) end
            row:Show()
        else
            row:Hide()
        end
    end

    if frame.filterButtons then
        for key, b in pairs(frame.filterButtons) do b:SetEnabled(key ~= (ns.S.dealFilter or "ALL")) end
        frame.quick:SetChecked(ns.S.quickOnly)
    end
    if frame.lowBids then
        frame.lowBids:SetText(ns.dealView == "BIDS" and "Buyout Deals" or ("Low Bids (%d)"):format(#ns.bidDeals))
    end
    if frame.postMarg then
        local mq = ns.MarginalQueue()
        local mev = 0
        for _, it in ipairs(mq) do mev = mev + it.result.gain end
        frame.postMarg:SetText(("Post Marginal (%d)"):format(#mq))
        frame.postMarg:SetEnabled(#mq > 0)
        local all = #ns.PostAllQueue()
        frame.postAll:SetText(("Post All (%d)"):format(all))
        frame.postAll:SetEnabled(all > 0)
        if ns.UpdateWheelPost then ns.UpdateWheelPost() end
    end
    if tab == "BAGS" then
        local n, ev, vend, all = 0, 0, 0, 0
        for _, it in ipairs(ns.items) do
            local r = it.result
            if r then all = all + (r.vendorTotal or 0) end
            if r and not it.posted and r.verdict == "POST" then
                n = n + 1; ev = ev + r.bestEV; vend = vend + r.vendorTotal
            end
        end
        frame.summary:SetText(("Post |cff40ff40%d|r items for an expected %s  (vendor would pay %s, you gain |cff40ff40%s|r)"):format(
            n, ns.Money(ev), ns.Money(vend), ns.Money(ev - vend)))
        if ns.scanning then
            frame.status:SetText(("Researching the AH... %d / %d"):format(ns.scanProgress or 0, #ns.items))
        else
            local learnedHere = 0
            for _, it in ipairs(ns.items) do
                if it.rateInfo and it.rateInfo.source ~= "default" then learnedHere = learnedHere + 1 end
            end
            frame.status:SetText(("Undercut 1c to be first in Buyout  |  cut %.0f%%  |  learned sell rates for %d of %d items"):format(
                ns.S.ahCut * 100, learnedHere, #ns.items))
        end
    elseif tab == "BRIEF" then
        frame.summary:SetText("|cffffd100Briefing|r - what's worth doing right now")
        frame.text:SetText(BriefingText())
        local left = ns.FullScanCooldownLeft()
        frame.status:SetText(left > 0 and ("Next full scan in %d:%02d"):format(left / 60, left % 60) or "Full scan ready (AH must be open)")
    elseif tab == "SESSION" then
        frame.summary:SetText("|cffffd100Session|r")
        frame.text:SetText(SessionText())
        frame.status:SetText("Resets each time you log in.")
    elseif tab == "CRAFT" then
        local craft, gain, flips, fgain = 0, 0, 0, 0
        for _, c in ipairs(list) do
            if c.verdict == "CRAFT" then craft = craft + 1; gain = gain + c.diff
            elseif c.verdict == "FLIP" then flips = flips + 1; fgain = fgain + c.diff end
        end
        if #ns.KnownRecipes() == 0 then
            frame.summary:SetText("No recipes yet - open your profession windows once (TwizCraft and TwizChef record them).")
        else
            frame.summary:SetText(("From your bags: craft |cff40ff40%d|r recipe%s for |cff40ff40+%s|r.  Buy & craft: |cff40c0ff%d|r for about |cff40c0ff+%s|r."):format(
                craft, craft == 1 and "" or "s", ns.Money(gain), flips, ns.Money(fgain)))
        end
        frame.buyAll:SetText(ns.BuyButtonText())
        frame.cancelBuy:SetEnabled(ns.buy ~= nil)
        local ah, ahCost, vend, vendCost = ns.SupplySummary()
        if ah + vend > 0 then
            frame.status:SetText(("Supplies to buy: %d from the AH (%s), %d from vendors (%s)."):format(ah, ns.Money(ahCost), vend, ns.Money(vendCost)))
        else
            frame.status:SetText("Product prices are looked up with your bag scan; a full scan prices everything.")
        end
    elseif tab == "SMELT" then
        local smelt, gain, sell, total = 0, 0, 0, 0
        for _, c in ipairs(list) do
            total = total + 1
            if c.verdict == "SMELT" then smelt = smelt + 1; gain = gain + c.diff
            elseif c.verdict == "ORE" then sell = sell + 1 end
        end
        if total == 0 then
            frame.summary:SetText("No ore in your bags, and no ore prices known yet.")
        elseif ns.smeltFromBags then
            frame.summary:SetText(("Smelt |cff40ff40%d|r ore type%s for |cff40ff40+%s|r; sell %d as ore."):format(
                smelt, smelt == 1 and "" or "s", ns.Money(gain), sell))
        else
            frame.summary:SetText("No ore in your bags - showing what 20 of each ore is worth smelted vs sold.")
        end
        frame.status:SetText("Bar prices are looked up with your bag scan. Open your Mining window once so it knows your exact recipes.")
    elseif ns.extraTabs[tab] then
        local def = ns.extraTabs[tab]
        local okS, summary, status = pcall(def.summary)
        frame.summary:SetText(okS and summary or "")
        frame.status:SetText(okS and status or "")
        for _, b in ipairs(def.__buttons or {}) do
            if b.def.label then b:SetText(b.def.label()) end
            if b.def.enabled then b:SetEnabled(b.def.enabled()) end
        end
    elseif tab == "MOVERS" then
        frame.summary:SetText(("%d items moved 10%% or more since the previous day scanned"):format(#(ns.movers or {})))
        frame.status:SetText(ns.hasTrendData and "Medians from full scans. Run one each day to keep trends fresh."
            or "Needs full scans on two different days.")
    else
        local total = 0
        for _, d in ipairs(ns.deals) do total = total + d.profit end
        local shown = FilteredDeals()
        local st = 0
        for _, d in ipairs(shown) do st = st + d.profit end
        local filterNote = ""
        if (ns.S.dealFilter or "ALL") ~= "ALL" or ns.S.quickOnly then
            local label = "All"
            for _, c in ipairs(ns.CATEGORIES) do if c.key == ns.S.dealFilter then label = c.label end end
            filterNote = ("  |cff808080[%s%s]|r"):format(label, ns.S.quickOnly and ", quick flips" or "")
        end
        if ns.dealView == "BIDS" then
            local safe = 0
            for _, d in ipairs(shown) do if d.conf == "SAFE" then safe = safe + 1 end end
            frame.summary:SetText(("%d extremely low bids (%d safe), about %s profit if you win them all.%s"):format(#shown, safe, ns.Money(st), filterNote))
        else
            if #shown == 0 and #ns.deals > 0 and filterNote ~= "" then
                frame.summary:SetText(("Nothing matches your filter%s, but there are |cff40ff40%d deals|r (%s) in total - click |cffffd100All|r%s."):format(
                    filterNote, #ns.deals, ns.Money(total), ns.S.quickOnly and " or untick Quick flips" or ""))
            else
                frame.summary:SetText(("%d profitable buys, about %s expected profit.%s"):format(#shown, ns.Money(st), filterNote))
            end
        end
        local left = ns.FullScanCooldownLeft()
        local cd = left > 0 and ("  |  next full scan in %d:%02d"):format(left / 60, left % 60) or "  |  full scan ready"
        frame.status:SetText((ns.fullScanStatus or "Run a full scan to find deals.") .. cd)
    end
end

local itemEvents = CreateFrame("Frame")
itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemEvents:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
local refreshPending, rebuildTimer
itemEvents:SetScript("OnEvent", function(_, event, itemID)
    if event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        if not refreshPending then
            refreshPending = true
            C_Timer.After(0.2, function() refreshPending = false; UI.Refresh() end)
        end
        return
    end
    if not requested[itemID] then return end
    requested[itemID] = nil
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0.2, function() refreshPending = false; UI.Refresh() end)
    end
    if ns.rawScan or ns.db and ns.db.merchant then
        if rebuildTimer then rebuildTimer:Cancel() end
        rebuildTimer = C_Timer.NewTimer(2, function()
            rebuildTimer = nil
            ns.BuildDeals()
            UI.Refresh()
        end)
    end
end)

function UI.SetTab(t)
    if not frame then Create() end
    SetTab(t)
end

function UI.Show()
    if not frame then Create() end
    frame:ClearAllPoints()
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    UI.Refresh()
end

function UI.Hide()
    if frame then frame:Hide() end
end

function UI.Toggle()
    if frame and frame:IsShown() then UI.Hide() else UI.Show() end
end

UI.RefreshNow = function() if RefreshNow then RefreshNow() end end
function UI._rows() return rows end
function UI._frame() return frame end

-- tabs defined in other files (they load before this one)
for _, register in ipairs(ns.UI_RegisterLater or {}) do register(UI) end
