-- TwizAH: Smelt - is it worth more to smelt your ore into bars, or sell the ore?
-- Uses the same take-home math as everything else: lowest AH price minus 1c,
-- the AH cut, the deposits you'd expect to lose for how fast each item sells,
-- and the vendor price as a floor.
local ADDON, ns = ...

local MINING = 186

-- ore = { bar, ore per smelt, bars per smelt, mining skill, English names (sanity check) }
-- If you open your Mining window once, the recipes you actually know replace these.
local BUILTIN = {
    [2770]  = { 2840,  1, 1, 1,   "Copper Ore",     "Copper Bar" },
    [2771]  = { 3576,  1, 1, 65,  "Tin Ore",        "Tin Bar" },
    [2775]  = { 2842,  1, 1, 75,  "Silver Ore",     "Silver Bar" },
    [2772]  = { 3575,  1, 1, 125, "Iron Ore",       "Iron Bar" },
    [2776]  = { 3577,  1, 1, 155, "Gold Ore",       "Gold Bar" },
    [3858]  = { 3860,  1, 1, 175, "Mithril Ore",    "Mithril Bar" },
    [7911]  = { 6037,  1, 1, 230, "Truesilver Ore", "Truesilver Bar" },
    [10620] = { 12359, 1, 1, 250, "Thorium Ore",    "Thorium Bar" },
    [23424] = { 23445, 2, 1, 300, "Fel Iron Ore",   "Fel Iron Bar" },
    [23425] = { 23446, 2, 1, 325, "Adamantite Ore", "Adamantite Bar" },
    [23427] = { 23447, 2, 1, 350, "Eternium Ore",   "Eternium Bar" },
    [23426] = { 23449, 2, 1, 375, "Khorium Ore",    "Khorium Bar" },
    [36909] = { 36916, 1, 1, 350, "Cobalt Ore",     "Cobalt Bar" },
    [36912] = { 36913, 2, 1, 400, "Saronite Ore",   "Saronite Bar" },
    [36910] = { 41163, 2, 1, 450, "Titanium Ore",   "Titanium Bar" },
}

local function SV() -- saved smelting data
    ns.db.smelt = ns.db.smelt or { known = {}, learnedAt = nil, skill = nil }
    return ns.db.smelt
end

------------------------------------------------------------------------
-- Your Mining skill and known smelting recipes
------------------------------------------------------------------------
function ns.MiningSkill()
    if not GetProfessions then return nil end
    local p1, p2 = GetProfessions()
    for _, idx in ipairs({ p1, p2 }) do
        if idx then
            local name, _, rank, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine == MINING or name == (PROFESSIONS_MINING or "Mining") then return rank or 0 end
        end
    end
    return nil
end

-- Called while the Mining window is open: remember the smelting recipes you know.
local function LearnFromWindow()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if not ok or type(info) ~= "table" then return end
    local id, parent = info.professionID, info.parentProfessionID
    local name = info.professionName or info.parentProfessionName
    if not (id == MINING or parent == MINING or name == (PROFESSIONS_MINING or "Mining")) then return end
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end

    local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" then return end
    local known = {}
    local n = 0
    for _, rid in ipairs(ids) do
        local okR, ri = pcall(C_TradeSkillUI.GetRecipeInfo, rid)
        if okR and ri and ri.learned then
            local okS, sc = pcall(C_TradeSkillUI.GetRecipeSchematic, rid, false)
            if okS and sc and sc.outputItemID then
                local slots = {}
                for _, slot in ipairs(sc.reagentSlotSchematics or {}) do
                    if slot.required ~= false and slot.reagents and slot.reagents[1] then slots[#slots + 1] = slot end
                end
                -- plain smelts only: one kind of ore in, bars out
                if #slots == 1 then
                    local ore = slots[1].reagents[1].itemID
                    local qtyIn = slots[1].quantityRequired or 1
                    local qtyOut = sc.quantityMin or 1
                    if ore and BUILTIN[ore] or (ore and C_Item.GetItemInfo(ore) and (C_Item.GetItemInfo(ore)):find("Ore")) then
                        known[ore] = { sc.outputItemID, qtyIn, qtyOut, 0 }
                        n = n + 1
                    end
                end
            end
        end
    end
    if n > 0 then
        local s = SV()
        local first = not s.learnedAt
        s.known, s.learnedAt, s.skill = known, time(), info.skillLevel
        if first then ns.Print(("learned your %d smelting recipes - the Smelt tab now uses them."):format(n)) end
    end
end

local learnFrame = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
    pcall(learnFrame.RegisterEvent, learnFrame, e)
end
local learnQueued
learnFrame:SetScript("OnEvent", function()
    if not ns.db or learnQueued then return end
    learnQueued = true
    C_Timer.After(0.5, function() learnQueued = false; pcall(LearnFromWindow) end)
end)

-- Recipe for an ore: { bar, oreIn, barsOut, skillReq, canSmelt, why }
function ns.SmeltRecipe(oreID)
    local s = SV()
    local k = s.known[oreID]
    if k then return { bar = k[1], ratio = k[2], out = k[3], can = true, source = "your recipes" } end
    local b = BUILTIN[oreID]
    if not b then return nil end
    -- skip a built-in entry if the game's name doesn't match (wrong ID on this server)
    if GetLocale() == "enUS" then
        local on = C_Item.GetItemInfo(oreID)
        if on and on ~= b[5] then return nil end
    end
    local r = { bar = b[1], ratio = b[2], out = b[3], req = b[4], source = "standard recipe" }
    if s.learnedAt then
        r.can, r.why = false, "you don't know this smelt"
    else
        local skill = ns.MiningSkill()
        if not skill then r.can, r.why = false, "needs Mining"
        elseif skill < b[4] then r.can, r.why = false, ("needs Mining %d (you have %d)"):format(b[4], skill)
        else r.can = true end
    end
    return r
end

function ns.IsOre(itemID)
    return SV().known[itemID] ~= nil or BUILTIN[itemID] ~= nil
end

-- Bars to look up on the AH for the ores in a list of bag items
function ns.SmeltPriceTargets(items)
    local have, need = {}, {}
    for _, it in ipairs(items) do have[it.itemID] = true end
    for _, it in ipairs(items) do
        local r = ns.SmeltRecipe(it.itemID)
        if r and not have[r.bar] and not need[r.bar] then need[r.bar] = true end
    end
    local out = {}
    for id in pairs(need) do out[#out + 1] = id end
    return out
end

------------------------------------------------------------------------
-- The comparison
------------------------------------------------------------------------
-- What qty of an item is worth to you: best of AH take-home or vendor.
local function Value(itemID, qty)
    if qty <= 0 then return 0, "-" end
    local vendorUnit = select(11, C_Item.GetItemInfo(itemID)) or 0
    local vend = vendorUnit * qty
    local price, t = ns.KnownPrice(itemID)
    if not price then
        if vend > 0 then return vend, "vendor", nil end
        return nil
    end
    local post = math.max(1, price - 1)
    local ok, best = pcall(ns.BestListing, itemID, qty, post)
    local ev = (ok and best and best.ev) or math.floor(post * qty * (1 - ns.S.ahCut))
    if vend >= ev then return vend, "vendor", price, t end
    return ev, "AH", price, t, best
end

ns.TakeHome = Value  -- shared with the Craft tab

function ns.SmeltCompare(oreID, qty, perStack)
    local r = ns.SmeltRecipe(oreID)
    if not r then return nil end
    local c = { ore = oreID, bar = r.bar, qty = qty, ratio = r.ratio, out = r.out, recipe = r, perStack = perStack }
    local smelts = math.floor(qty / r.ratio)
    c.bars = smelts * r.out
    c.left = qty - smelts * r.ratio
    c.oreUnit = ns.KnownPrice(oreID)
    c.barUnit = ns.KnownPrice(r.bar)

    local sellV, sellVia = Value(oreID, qty)
    local barV, barVia = Value(r.bar, c.bars)
    local leftV = Value(oreID, c.left)
    c.sellVia, c.barVia = sellVia, barVia

    if c.bars == 0 then
        c.verdict = "FEW"
    elseif not sellV or not barV then
        c.verdict = "PRICE"
        c.missing = (not barV and not sellV) and "ore and bar" or (not barV and "bar" or "ore")
    else
        c.sellValue = sellV
        c.smeltValue = barV + (leftV or 0)
        c.diff = c.smeltValue - c.sellValue
        local min = ns.S.minGain or 500
        if c.diff >= min then c.verdict = "SMELT"
        elseif c.diff <= -min then c.verdict = "ORE"
        else c.verdict = "EVEN" end
        if c.verdict == "SMELT" and not r.can then c.verdict = "SKILL" end
    end
    return c
end

-- Ores in your bags; if none, every ore we have prices for, compared per 20.
function ns.SmeltList()
    local list, inBags = {}, {}
    for oreID in pairs(BUILTIN) do inBags[oreID] = true end
    for oreID in pairs(SV().known) do inBags[oreID] = true end
    for oreID in pairs(inBags) do
        local n = C_Item.GetItemCount(oreID) or 0
        if n > 0 then
            local c = ns.SmeltCompare(oreID, n)
            if c then list[#list + 1] = c end
        end
    end
    ns.smeltFromBags = #list > 0
    if #list == 0 then
        for oreID in pairs(inBags) do
            if ns.KnownPrice(oreID) then
                local c = ns.SmeltCompare(oreID, 20, true)
                if c then list[#list + 1] = c end
            end
        end
    end
    table.sort(list, function(a, b)
        return math.abs(a.diff or 0) > math.abs(b.diff or 0)
    end)
    return list
end

ns.SMELT_TEXT = {
    SMELT = "|cff40ff40Smelt|r",
    ORE   = "|cffffd100Sell ore|r",
    EVEN  = "|cffc0c0c0Either|r",
    SKILL = "|cffff8040Smelt*|r",
    PRICE = "|cff808080Need price|r",
    FEW   = "|cff808080Too few|r",
}

function ns.SmeltAdvice(c)
    if c.verdict == "SMELT" then
        return ("Smelt into %d bars: %s more than selling the ore."):format(c.bars, ns.Money(c.diff))
    elseif c.verdict == "ORE" then
        return ("Sell the ore: %s more than smelting."):format(ns.Money(-c.diff))
    elseif c.verdict == "EVEN" then
        return ("About the same either way (%s difference) - sell the ore and save the time."):format(ns.Money(math.abs(c.diff)))
    elseif c.verdict == "SKILL" then
        return ("Bars would pay %s more, but %s."):format(ns.Money(c.diff), c.recipe.why or "you can't smelt it")
    elseif c.verdict == "PRICE" then
        return ("No AH price for the %s yet - open the AH (bars are looked up with your bags) or run a full scan."):format(c.missing)
    elseif c.verdict == "FEW" then
        return ("Need %d ore for one smelt."):format(c.ratio)
    end
    return ""
end
