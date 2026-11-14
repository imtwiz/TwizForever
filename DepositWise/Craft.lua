-- DepositWise: Craft - for every recipe you know (all professions), is it
-- worth more to craft and sell the result, or sell the materials as they are?
-- And which recipes make a profit even if you buy every material.
--
-- Recipes come from CraftRoute (any profession window you've opened) and
-- AutoChef (cooking). Values use the same take-home math as everything else.
local ADDON, ns = ...

local MINING = 186
local SUGGEST_MAX = 20 -- never suggest more flips than this per recipe

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- All learned recipes you've shown us: { name, prof, out, made, reagents = { {id, qty} } }
function ns.KnownRecipes()
    local list, seen = {}, {}
    local cr = CraftRouteDB and CraftRouteDB.chars and CraftRouteDB.chars[CharKey()]
    for line, p in pairs(cr and cr.profs or {}) do
        if line ~= MINING then -- smelting has its own tab
            for id, r in pairs(p.recipes or {}) do
                if r.learned and r.out and r.reagents and #r.reagents > 0 then
                    list[#list + 1] = { id = id, name = r.name, prof = p.name, out = r.out,
                                        made = r.made or 1, reagents = r.reagents }
                    seen[r.out] = true
                end
            end
        end
    end
    local ac = AutoChefDB and AutoChefDB.chars and AutoChefDB.chars[CharKey()]
    for id, r in pairs(ac and ac.recipes or {}) do
        if r.out and not seen[r.out] then
            local reagents = {}
            for _, slot in ipairs(r.reagents or {}) do
                if slot.ids and slot.ids[1] then reagents[#reagents + 1] = { id = slot.ids[1], qty = slot.qty } end
            end
            if #reagents > 0 then
                list[#list + 1] = { id = id, name = r.name, prof = "Cooking", out = r.out, made = 1, reagents = reagents }
            end
        end
    end
    return list
end

local function VendorCost(id)
    local m = ns.db.merchant and ns.db.merchant[id]
    return m and m.cost
end

-- Cheapest way to buy one unit: vendor or AH
local function BuyPrice(id)
    local v = VendorCost(id)
    local a = ns.KnownPrice(id)
    if v and a then return math.min(v, a), (v <= a) and "vendor" or "AH" end
    if v then return v, "vendor" end
    if a then return a, "AH" end
end

------------------------------------------------------------------------
-- One recipe
------------------------------------------------------------------------
-- Returns a row: { r, kind = "BAGS" | "FLIP", n, matsValue, product, supplies, diff, verdict, parts }
local function FromBags(r)
    -- materials a vendor sells are "supplies" (you'd just buy them); the rest come from your bags
    local n = math.huge
    local hasOwnMats = false
    for _, g in ipairs(r.reagents) do
        if not VendorCost(g.id) then
            hasOwnMats = true
            n = math.min(n, math.floor((C_Item.GetItemCount(g.id) or 0) / g.qty))
        end
    end
    if not hasOwnMats or n == math.huge or n <= 0 then return nil end

    local row = { r = r, kind = "BAGS", n = n, matsValue = 0, supplies = 0, parts = {} }
    for _, g in ipairs(r.reagents) do
        local need = g.qty * n
        local vc = VendorCost(g.id)
        if vc then
            local buy = math.max(0, need - (C_Item.GetItemCount(g.id) or 0))
            row.supplies = row.supplies + buy * vc
            row.parts[#row.parts + 1] = { id = g.id, n = need, value = buy * vc, how = buy > 0 and "buy" or "have" }
        else
            local v, via = ns.TakeHome(g.id, need)
            if not v then row.verdict, row.missing = "PRICE", g.id; return row end
            row.matsValue = row.matsValue + v
            row.parts[#row.parts + 1] = { id = g.id, n = need, value = v, how = via }
        end
    end
    local pv, pvia = ns.TakeHome(r.out, r.made * n)
    if not pv then row.verdict, row.missing = "PRICE", r.out; return row end
    row.product, row.productVia = pv, pvia
    row.diff = pv - row.supplies - row.matsValue
    local min = ns.S.minGain or 500
    if row.diff >= min then row.verdict = "CRAFT"
    elseif row.diff <= -min then row.verdict = "SELLMATS"
    else row.verdict = "EVEN" end
    return row
end

-- Buy every material, craft, sell: profit per craft and how many are worth making
local function Flip(r)
    local cost, parts = 0, {}
    for _, g in ipairs(r.reagents) do
        local p, src = BuyPrice(g.id)
        if not p then return nil end
        cost = cost + p * g.qty
        parts[#parts + 1] = { id = g.id, n = g.qty, value = p * g.qty, how = src }
    end
    -- how many will sell in about 2 days at the lowest price
    local sellable = ns.SellableUnits and ns.SellableUnits(r.out, 48)
    local n = 1
    if sellable then n = math.max(1, math.min(SUGGEST_MAX, math.floor(sellable / math.max(1, r.made)))) end
    local pv, pvia = ns.TakeHome(r.out, r.made * n)
    if not pv then return nil end
    local profit = pv - cost * n
    if profit < (ns.S.minGain or 500) then return nil end
    return { r = r, kind = "FLIP", n = n, supplies = cost * n, matsValue = 0, product = pv, productVia = pvia,
             diff = profit, verdict = "FLIP", parts = parts, known = sellable ~= nil }
end

function ns.CraftList()
    local rows = {}
    for _, r in ipairs(ns.KnownRecipes()) do
        local ok, b = pcall(FromBags, r)
        if ok and b then rows[#rows + 1] = b end
        if not (ok and b and b.verdict == "CRAFT") then
            local okF, f = pcall(Flip, r)
            if okF and f then rows[#rows + 1] = f end
        end
    end
    table.sort(rows, function(a, b)
        if (a.kind == "BAGS") ~= (b.kind == "BAGS") then return a.kind == "BAGS" end
        return (a.diff or -1e12) > (b.diff or -1e12)
    end)
    return rows
end

-- Products to price on the AH during the bag scan: things your bag
-- materials can make (capped so the scan stays quick)
function ns.CraftPriceTargets(items)
    local inBags, out, seen = {}, {}, {}
    for _, it in ipairs(items) do inBags[it.itemID] = true end
    for _, r in ipairs(ns.KnownRecipes()) do
        if not inBags[r.out] and not seen[r.out] then
            for _, g in ipairs(r.reagents) do
                if inBags[g.id] then
                    seen[r.out] = true
                    out[#out + 1] = r.out
                    break
                end
            end
        end
        if #out >= 30 then break end
    end
    return out
end

ns.CRAFT_TEXT = {
    CRAFT    = "|cff40ff40Craft|r",
    SELLMATS = "|cffffd100Sell mats|r",
    EVEN     = "|cffc0c0c0Either|r",
    FLIP     = "|cff40c0ffBuy & craft|r",
    PRICE    = "|cff808080Need price|r",
}

function ns.CraftAdvice(c)
    local name = C_Item.GetItemInfo(c.r.out) or c.r.name
    if c.verdict == "CRAFT" then
        return ("Craft %d %s: %s more than selling the materials."):format(c.n * c.r.made, name, ns.Money(c.diff))
    elseif c.verdict == "SELLMATS" then
        return ("Sell the materials: %s more than crafting %s."):format(ns.Money(-c.diff), name)
    elseif c.verdict == "EVEN" then
        return ("About the same either way (%s) - selling the materials is less work."):format(ns.Money(math.abs(c.diff)))
    elseif c.verdict == "FLIP" then
        return ("Buy the materials and craft %d: about %s profit%s."):format(c.n * c.r.made, ns.Money(c.diff),
            c.known and "" or " (sell speed not learned yet - start with 1)")
    elseif c.verdict == "PRICE" then
        return ("No price yet for %s - open the AH or run a full scan."):format(C_Item.GetItemInfo(c.missing) or "an item")
    end
    return ""
end

------------------------------------------------------------------------
-- Cache: the Craft tab, Briefing, supply list and auto-vendor all ask for
-- this list; work it out at most every 2 seconds, or when bags/prices change.
------------------------------------------------------------------------
do
    local compute = ns.CraftList
    local cache, cachedAt = nil, -100
    function ns.CraftList()
        if cache and GetTime() - cachedAt < 2 then return cache end
        cache = compute()
        cachedAt = GetTime()
        return cache
    end
    function ns.InvalidateCraft() cache = nil end
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:SetScript("OnEvent", function() cache = nil end)
end
