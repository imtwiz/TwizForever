-- DepositWise: Supplies - "Buy All Supplies" for the Craft tab.
-- Totals what every profitable craft needs (Craft from bags + Buy & craft),
-- subtracts what you already have (bags + bank), and buys the rest:
--   AH-cheapest reagents: from the Craft tab button (price quote, then confirm)
--   vendor-cheapest reagents: from a button on the merchant window
local ADDON, ns = ...

local PRICE_GUARD = 1.5 -- flag prices over 1.5x the usual market

local function Have(id)
    return C_Item.GetItemCount(id, true, false, true) or 0 -- bags + bank + reagent bank
end

-- Which source is cheapest for one unit
local function Source(id)
    local m = ns.db.merchant and ns.db.merchant[id]
    local ah = ns.KnownPrice(id)
    if m and m.cost and (not ah or m.cost <= ah) then return "VENDOR", m.cost, m end
    return "AH", ah
end

-- { { itemID, need, have, toBuy, unit, total, source, vendor, for = { "3x Bolt of Linen", ... } } }
function ns.SupplyNeeds()
    local need, uses = {}, {}
    local ok, rows = pcall(ns.CraftList)
    for _, c in ipairs(ok and rows or {}) do
        if c.verdict == "CRAFT" or c.verdict == "FLIP" then
            for _, g in ipairs(c.r.reagents) do
                local n = g.qty * c.n
                need[g.id] = (need[g.id] or 0) + n
                uses[g.id] = uses[g.id] or {}
                table.insert(uses[g.id], ("%dx %s"):format(c.n, C_Item.GetItemInfo(c.r.out) or c.r.name or "recipe"))
            end
        end
    end
    local list = {}
    for id, n in pairs(need) do
        local have = Have(id)
        local src, unit, vendor = Source(id)
        local toBuy = math.max(0, n - have)
        list[#list + 1] = { itemID = id, need = n, have = have, toBuy = toBuy, unit = unit,
            total = unit and unit * toBuy, source = src, vendor = vendor, uses = uses[id] }
    end
    table.sort(list, function(a, b) return (a.total or 0) > (b.total or 0) end)
    return list
end

function ns.SupplySummary()
    local ah, ahCost, vend, vendCost = 0, 0, 0, 0
    for _, e in ipairs(ns.SupplyNeeds()) do
        if e.toBuy > 0 then
            if e.source == "AH" then ah = ah + 1; ahCost = ahCost + (e.total or 0)
            else vend = vend + 1; vendCost = vendCost + (e.total or 0) end
        end
    end
    return ah, ahCost, vend, vendCost
end

------------------------------------------------------------------------
-- AH buying: click = price quote, click again = confirm (the game needs both)
------------------------------------------------------------------------
ns.buy = nil -- { itemID, qty, stage = "quote" | "ready" | "buying", unit, total, expensive }
local skipped = {}

local function NextToBuy()
    for _, e in ipairs(ns.SupplyNeeds()) do
        if e.toBuy > 0 and e.source == "AH" and not skipped[e.itemID] then return e end
    end
end

function ns.BuyButtonText()
    local b = ns.buy
    if b and (b.stage == "quote" or b.stage == "buying") then return "Working..." end
    if b and b.stage == "ready" then
        return ("%sConfirm %dx %s: %s|r"):format(b.expensive and "|cffff6060" or "",
            b.qty, C_Item.GetItemInfo(b.itemID) or "item", ns.Money(b.total))
    end
    local n = 0
    for _, e in ipairs(ns.SupplyNeeds()) do
        if e.toBuy > 0 and e.source == "AH" and not skipped[e.itemID] then n = n + 1 end
    end
    return ("Buy All Supplies (%d)"):format(n)
end

function ns.BuyAllSupplies()
    if not ns.ahOpen then ns.Print("Open the Auction House first. Vendor-sold supplies get a button on the merchant window."); return end
    local b = ns.buy
    if b and (b.stage == "quote" or b.stage == "buying") then return end
    if b and b.stage == "ready" then
        if b.total > GetMoney() then
            ns.Print("Not enough gold for that."); pcall(C_AuctionHouse.CancelCommoditiesPurchase); ns.buy = nil
        else
            b.stage = "buying"
            C_AuctionHouse.ConfirmCommoditiesPurchase(b.itemID, b.qty)
        end
        ns.UI.Refresh(); return
    end
    local e = NextToBuy()
    if not e then
        local _, _, vend = ns.SupplySummary()
        ns.Print("All AH supplies bought." .. (vend > 0 and (" %d more are cheaper from a vendor - open a merchant."):format(vend) or ""))
        ns.UI.Refresh(); return
    end
    ns.buy = { itemID = e.itemID, qty = e.toBuy, stage = "quote" }
    C_AuctionHouse.StartCommoditiesPurchase(e.itemID, e.toBuy)
    C_Timer.After(5, function()
        local cur = ns.buy
        if cur and cur.itemID == e.itemID and cur.stage == "quote" then
            ns.Print("No price came back for " .. (C_Item.GetItemInfo(e.itemID) or "that item") .. " - skipping it.")
            skipped[e.itemID] = true; ns.buy = nil; ns.UI.Refresh()
        end
    end)
    ns.UI.Refresh()
end

function ns.CancelSupplyPurchase()
    if ns.buy then pcall(C_AuctionHouse.CancelCommoditiesPurchase); ns.buy = nil; ns.UI.Refresh() end
end

------------------------------------------------------------------------
-- Vendor buying (thread, vials, flux, spices...)
------------------------------------------------------------------------
local function MerchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost end
    else
        local _, _, p, q, n, _, _, ext = GetMerchantItemInfo(i)
        return p, q, n, ext
    end
end

local function VendorWanted()
    local wanted = {}
    for _, e in ipairs(ns.SupplyNeeds()) do
        if e.toBuy > 0 then wanted[e.itemID] = e.toBuy end -- buy here whenever this merchant has it
    end
    return wanted
end

function ns.BuyVendorSupplies()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local wanted, bought = VendorWanted(), 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID(i)
        local qty = id and wanted[id]
        if qty then
            local price, stack, avail, extended = MerchantInfo(i)
            if price and price > 0 and not extended then
                stack = math.max(1, stack or 1)
                local units = math.ceil(qty / stack) * stack
                if avail and avail > 0 then units = math.min(units, avail * stack) end
                local cost = price / stack * units
                if cost <= GetMoney() then
                    local per = GetMerchantItemMaxStack(i) or units
                    local left = units
                    while left > 0 do
                        local n = math.min(left, per)
                        BuyMerchantItem(i, n)
                        left = left - n
                    end
                    bought = bought + 1
                    ns.Print(("Bought %dx %s for %s."):format(units, GetMerchantItemLink(i) or "item", ns.Money(cost)))
                else
                    ns.Print("Not enough gold for " .. (GetMerchantItemLink(i) or "an item") .. ".")
                end
            end
        end
    end
    if bought == 0 then ns.Print("This merchant doesn't sell anything your crafts need.") end
end

local merchantButton
local function UpdateMerchantButton()
    if not MerchantFrame then return end
    local wanted, n = VendorWanted(), 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID(i)
        if id and wanted[id] then n = n + 1 end
    end
    if not merchantButton then
        merchantButton = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
        merchantButton:SetSize(180, 22)
        merchantButton:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", 0, -2)
        merchantButton:SetScript("OnClick", function() ns.BuyVendorSupplies(); C_Timer.After(0.6, UpdateMerchantButton) end)
        merchantButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("DepositWise: Buy Craft Supplies")
            GameTooltip:AddLine("Buys what your profitable crafts (Craft tab) are missing that this merchant sells.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        merchantButton:SetScript("OnLeave", GameTooltip_Hide)
    end
    merchantButton:SetText(("Buy Craft Supplies (%d)"):format(n))
    merchantButton:SetShown(n > 0)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "BAG_UPDATE_DELAYED" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    local b = ns.buy
    if event == "COMMODITY_PRICE_UPDATED" then
        if b and b.stage == "quote" then
            b.unit, b.total, b.stage = a1, a2, "ready"
            local m = ns.db.market[b.itemID]
            local ref = (m and m.med) or ns.KnownPrice(b.itemID)
            b.expensive = ref and a1 > ref * PRICE_GUARD
            if b.expensive then
                ns.Print(("Careful: %s is %s each right now, over 1.5x its usual %s. Click again to buy anyway, or Cancel."):format(
                    C_Item.GetItemInfo(b.itemID) or "item", ns.Money(a1), ns.Money(ref)))
            end
            ns.UI.Refresh()
        end
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
        if b then
            ns.Print("Not enough " .. (C_Item.GetItemInfo(b.itemID) or "of that item") .. " on the AH - skipping it.")
            skipped[b.itemID] = true; ns.buy = nil; ns.UI.Refresh()
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        if b then
            ns.Print(("Bought %dx %s for %s."):format(b.qty, C_Item.GetItemInfo(b.itemID) or "item", ns.Money(b.total)))
            ns.buy = nil
        end
        C_Timer.After(0.5, ns.UI.Refresh)
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        if b then ns.Print("Purchase failed (prices moved?) - click again for a new quote.") end
        ns.buy = nil; ns.UI.Refresh()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ns.buy = nil; wipe(skipped)
    elseif event == "MERCHANT_SHOW" then
        C_Timer.After(0.8, function() pcall(UpdateMerchantButton) end) -- after auto-vendor
    elseif event == "BAG_UPDATE_DELAYED" then
        if merchantButton and MerchantFrame and MerchantFrame:IsShown() then pcall(UpdateMerchantButton) end
    end
end)
