-- DepositWise: item tooltips show what you'd actually net on the AH
local ADDON, ns = ...

local function AgeText(t)
    local s = time() - t
    if s < 3600 then return ("%dm ago"):format(s / 60) end
    if s < 86400 then return ("%dh ago"):format(s / 3600) end
    return ("%dd ago"):format(s / 86400)
end

local function OnItemTooltip(tooltip, data)
    if not ns.S or not ns.S.tooltip then return end
    if InCombatLockdown() then return end
    local itemID = data and data.id
    if type(itemID) ~= "number" then return end
    if ns.IsOre and ns.IsOre(itemID) then
        local n = math.max(C_Item.GetItemCount(itemID) or 0, 0)
        local ok, c = pcall(ns.SmeltCompare, itemID, n > 0 and n or 20, n == 0)
        if ok and c and c.verdict ~= "PRICE" and c.verdict ~= "FEW" then
            local who = n > 0 and ("your " .. n) or "20"
            if c.diff >= 0 then
                tooltip:AddDoubleLine("|cff33ff99DW|r Smelt " .. who .. " into bars",
                    "|cff40ff40+" .. ns.Money(c.diff) .. "|r", 1, 1, 1)
            else
                tooltip:AddDoubleLine("|cff33ff99DW|r Sell " .. who .. " as ore",
                    "|cffffd100+" .. ns.Money(-c.diff) .. "|r", 1, 1, 1)
            end
        end
    end
    local price, t = ns.KnownPrice(itemID)
    if not price then return end
    local net = math.floor(price * (1 - ns.S.ahCut))
    local vendor = select(11, C_Item.GetItemInfo(itemID)) or 0
    tooltip:AddDoubleLine("|cff33ff99DW|r AH low (" .. AgeText(t) .. ")", ns.Money(price), 1, 1, 1)
    local label = net > vendor and "Net after cut |cff40ff40(beats vendor)|r" or "Net after cut |cffff8040(vendor pays more)|r"
    tooltip:AddDoubleLine("|cff33ff99DW|r " .. label, ns.Money(net), 1, 1, 1)
    local m = ns.db.market[itemID]
    if m and m.med then
        tooltip:AddDoubleLine("|cff33ff99DW|r Market median", ns.Money(m.med) .. ("  (%d listed)"):format(m.q or 0), 1, 1, 1)
    end
    -- how fast it moves, and the listing length worth using
    local demand = ns.MarketStats and ns.MarketStats(itemID)
    if demand then
        local rates = ns.SellRates(itemID, 1)
        tooltip:AddDoubleLine("|cff33ff99DW|r Sells about", ("%.1f a day  |cff808080(%s %d%%, %s %d%%, %s %d%%)|r"):format(demand * 24,
            ns.DURATION_LABEL[1], rates[1] * 100, ns.DURATION_LABEL[2], rates[2] * 100, ns.DURATION_LABEL[3], rates[3] * 100), 1, 1, 1, 1, 1, 1)
    end
    local o = ns.db.outcomes and ns.db.outcomes[itemID]
    if o and (o.s + o.e) > 0 then
        tooltip:AddDoubleLine("|cff33ff99DW|r Your auctions", ("%d of %d sold"):format(o.s, o.s + o.e), 1, 1, 1, 1, 1, 1)
    end
end

function ns.Tooltip_OnLoad()
    if TooltipDataProcessor and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            pcall(OnItemTooltip, tooltip, data)
        end)
    end
end
